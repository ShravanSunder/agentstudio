import Darwin
import Dispatch
import Foundation

/// Proves handoff or failure for one cold-restore attempt entirely from
/// OS-observable facts (SR4, SR5; Program Design item 3). Two register-then
/// -check stages, each registering its kqueue-backed watch before checking
/// so no event between registration and check is missed:
///
/// 1. **Discovery** — `EVFILT_VNODE` `NOTE_WRITE` on the zmx directory, then
///    checks whether the session's socket exists; on appearance, calls
///    `ZmxSessionControl.observe` for the new session's identity.
/// 2. **Handoff** — `EVFILT_PROC` `NOTE_EXEC | NOTE_EXIT` on the identity's
///    terminal-leader pid, then reads `KERN_PROCARGS2` for the
///    `AGENTSTUDIO_RESTORE_ATTEMPT` marker (see `ColdStartObserverSyscalls`
///    for this read's unverified production behavior).
///
/// `reportAttachClientExited()` is a third, independent settlement path:
/// Ghostty's `showChildExited` action is the one event-driven fact present
/// whether the attach client dies during discovery (never creates a
/// socket) or after (Program Design item 3: "that exit is the failure
/// fact. No timer is involved."). It can fire at any point and always wins
/// once it does — the App/Features bridge that calls it owns resolving
/// which pending observer a given pane's exit belongs to.
///
/// One observer per attempt: `observeColdStart` may be called exactly once.
package actor ColdStartObserver {
    private enum MarkerReadResult {
        case markerFound
        case markerAbsent
        case environmentOmitted
        case unreadable(errno: Int32)
    }

    private let syscalls: any ColdStartObserverSyscalls
    private var settlementContinuation: CheckedContinuation<ColdStartOutcome, Never>?
    /// Set when `settle()` runs before `observeColdStart` ever started —
    /// `reportAttachClientExited()` is registered (via
    /// `ColdStartAttachExitBinding`) before the surface that could exit is
    /// even created, so a `showChildExited` racing ahead of this actor's own
    /// `observeColdStart` call is a real, expected ordering, not a bug.
    /// `observeColdStart` returns this immediately instead of waiting.
    private var preSettledOutcome: ColdStartOutcome?
    private var isSettled = false
    private var hasStartedObserving = false
    private var directoryDescriptor: Int32?
    private var directoryWatchSource: (any DispatchSourceProtocol)?
    private var processWatchSource: (any DispatchSourceProtocol)?

    package init(syscalls: any ColdStartObserverSyscalls = DarwinColdStartObserverSyscalls()) {
        self.syscalls = syscalls
    }

    /// Runs the full two-stage watch for one cold-restore attempt, returning
    /// the total outcome. Never called twice on the same instance.
    package func observeColdStart(
        zmxDirectory: URL,
        socketPath: String,
        bootID: String,
        attemptID: ColdRestoreAttemptID
    ) async -> ColdStartOutcome {
        precondition(!hasStartedObserving, "observeColdStart called more than once")
        hasStartedObserving = true
        if let preSettledOutcome {
            return preSettledOutcome
        }
        return await withCheckedContinuation { continuation in
            settlementContinuation = continuation
            beginDiscovery(zmxDirectory: zmxDirectory, socketPath: socketPath, bootID: bootID, attemptID: attemptID)
        }
    }

    /// SR5; Program Design item 3, "the surface's command exits before
    /// handoff, including while discovering": the App/Features bridge for
    /// Ghostty's `showChildExited` fact. Never inspects an exit status —
    /// Ghostty's own comment on macOS exit-code detection being unreliable
    /// applies here too — so any attach-client exit before handoff settles
    /// this window as failed, full stop.
    package func reportAttachClientExited() {
        settle(.failed(.exitedBeforeHandoff(exitStatus: nil)))
    }

    /// Retirement or activation cancellation (Program Design item 4):
    /// "removes its kqueue registrations and settles the slot." The
    /// returned outcome carries no meaning worth acting on — the caller
    /// already knows this ended because it retired the pane, not because
    /// the observer learned anything.
    package func cancel() {
        settle(.unobservable(.identityUnverifiable))
    }

    private func settle(_ outcome: ColdStartOutcome) {
        guard !isSettled else { return }
        isSettled = true
        teardownWatches()
        if let settlementContinuation {
            settlementContinuation.resume(returning: outcome)
            self.settlementContinuation = nil
        } else {
            preSettledOutcome = outcome
        }
    }

    private func teardownWatches() {
        directoryWatchSource?.cancel()
        directoryWatchSource = nil
        if let directoryDescriptor {
            close(directoryDescriptor)
        }
        directoryDescriptor = nil
        processWatchSource?.cancel()
        processWatchSource = nil
    }

    // MARK: - Stage 1: discovery

    private func beginDiscovery(
        zmxDirectory: URL,
        socketPath: String,
        bootID: String,
        attemptID: ColdRestoreAttemptID
    ) {
        let descriptor: Int32
        switch syscalls.openDirectoryForWatching(path: zmxDirectory.path) {
        case .failure(let errorNumber):
            settle(.unobservable(.watchRegistrationFailed(errno: errorNumber.rawValue)))
            return
        case .success(let openedDescriptor):
            descriptor = openedDescriptor
        }
        directoryDescriptor = descriptor
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: .write,
            queue: DispatchQueue.global(qos: .userInitiated)
        )
        source.setEventHandler { [weak self] in
            self?.checkForSocketAndAdvance(socketPath: socketPath, bootID: bootID, attemptID: attemptID)
        }
        source.setCancelHandler {}
        directoryWatchSource = source
        source.resume()

        // Register first, then check: the socket may already exist by the
        // time this registers (or appear between registration and this
        // call — the event fires again and this re-checks harmlessly).
        checkForSocketAndAdvance(socketPath: socketPath, bootID: bootID, attemptID: attemptID)
    }

    /// Runs wherever it's called from — the DispatchSource's own GCD queue
    /// (its event handler) or synchronously right after registration —
    /// never on this actor's executor, so the blocking
    /// `ZmxSessionControl.observe` call below never blocks the actor's
    /// serial executor (SE-0461). Re-enters the actor only to record the
    /// result.
    nonisolated private func checkForSocketAndAdvance(
        socketPath: String,
        bootID: String,
        attemptID: ColdRestoreAttemptID
    ) {
        guard FileManager.default.fileExists(atPath: socketPath) else { return }
        let identity: ZmxSessionIdentity?
        do {
            identity = try ZmxSessionControl.observe(path: socketPath, bootID: bootID)
        } catch {
            identity = nil
        }
        Task { await self.discoverySettled(identity: identity, socketPath: socketPath, attemptID: attemptID) }
    }

    private func discoverySettled(
        identity: ZmxSessionIdentity?,
        socketPath: String,
        attemptID: ColdRestoreAttemptID
    ) {
        guard !isSettled else { return }
        directoryWatchSource?.cancel()
        directoryWatchSource = nil
        if let directoryDescriptor {
            close(directoryDescriptor)
        }
        directoryDescriptor = nil

        guard let identity else {
            // "once the session was discovered, observe finds its endpoint
            // gone or refused" is proof (SR2); anything else `observe`
            // threw is a genuine "couldn't verify," distinguished by
            // whether the endpoint itself is still there.
            let endpointGone = (try? ZmxSessionControl.endpointIsAbsent(path: socketPath)) ?? false
            if endpointGone {
                settle(.failed(.exitedBeforeHandoff(exitStatus: nil)))
            } else {
                settle(.unobservable(.identityUnverifiable))
            }
            return
        }
        beginHandoffWatch(terminalLeaderPid: identity.terminalLeader.pid, attemptID: attemptID)
    }

    // MARK: - Stage 2: handoff

    private func beginHandoffWatch(terminalLeaderPid: Int32, attemptID: ColdRestoreAttemptID) {
        let source = DispatchSource.makeProcessSource(
            identifier: terminalLeaderPid,
            eventMask: [.exit, .exec],
            queue: DispatchQueue.global(qos: .userInitiated)
        )
        source.setEventHandler { [weak self] in
            let exitFired = source.data.contains(.exit)
            self?.checkForMarkerAndAdvance(pid: terminalLeaderPid, attemptID: attemptID, exitFired: exitFired)
        }
        source.setCancelHandler {}
        processWatchSource = source
        source.resume()

        // Register first, then check: handoff may already have completed
        // between discovering the identity and registering this watch.
        checkForMarkerAndAdvance(pid: terminalLeaderPid, attemptID: attemptID, exitFired: false)
    }

    nonisolated private func checkForMarkerAndAdvance(
        pid: Int32,
        attemptID: ColdRestoreAttemptID,
        exitFired: Bool
    ) {
        let result = readMarker(pid: pid, attemptID: attemptID)
        Task { await self.handoffChecked(markerResult: result, exitFired: exitFired) }
    }

    nonisolated private func readMarker(pid: Int32, attemptID: ColdRestoreAttemptID) -> MarkerReadResult {
        switch syscalls.readProcessArgumentsBuffer(pid: pid) {
        case .failure(let errorNumber):
            return .unreadable(errno: errorNumber.rawValue)
        case .success(let buffer):
            guard ProcessArgumentsBufferParser.environmentSectionIsPresent(in: buffer) else {
                return .environmentOmitted
            }
            let value = ProcessArgumentsBufferParser.environmentValue(
                named: "AGENTSTUDIO_RESTORE_ATTEMPT",
                in: buffer
            )
            return value == attemptID.rawValue ? .markerFound : .markerAbsent
        }
    }

    private func handoffChecked(markerResult: MarkerReadResult, exitFired: Bool) {
        guard !isSettled else { return }
        switch markerResult {
        case .markerFound:
            settle(.handedOff)
        case .environmentOmitted:
            settle(.unobservable(.environmentOmitted))
        case .unreadable(let errorNumber):
            settle(.unobservable(.processArgsUnreadable(errno: errorNumber)))
        case .markerAbsent:
            // Still pending unless the leader has also exited: another
            // exec (or a stray wakeup) without the marker yet is normal —
            // "no time-only failure" — so this simply waits for the next
            // EVFILT_PROC event instead of settling here.
            if exitFired {
                settle(.failed(.exitedBeforeHandoff(exitStatus: nil)))
            }
        }
    }
}
