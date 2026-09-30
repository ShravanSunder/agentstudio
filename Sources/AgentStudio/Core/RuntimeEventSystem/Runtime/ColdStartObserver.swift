import AgentStudioInfrastructure
import Darwin
import Dispatch
import Foundation

/// Proves handoff or failure for one cold-restore attempt entirely from
/// OS-observable facts (SR4, SR5; Program Design revision 11, item 3). Two
/// register-then-check stages, each registering its kqueue-backed watch
/// before checking so no event between registration and check is missed:
///
/// 1. **Discovery** — `EVFILT_VNODE` `NOTE_WRITE` on the zmx directory, then
///    checks whether the session's socket exists; on appearance, calls
///    `ZmxSessionControl.observe` for the new session's identity. A
///    `.connectionRefused` connect (zmx binds the socket's path before it
///    calls `listen`; amended 2026-09-30) retries on a short backoff rather
///    than settling — see `attemptDiscoveryConnect`. A `.pendingSetsid`
///    connect (the pty child hasn't called `setsid` yet; amended again
///    2026-09-30) registers `EVFILT_PROC` on the terminal pid and
///    re-observes at its next exec/exit — see `beginSetsidWatch`.
/// 2. **Handoff** — `EVFILT_PROC` `NOTE_EXEC | NOTE_EXIT` on the identity's
///    terminal-leader pid, then reads its argument vector via
///    `KERN_PROCARGS2` (never the environment: macOS returns none to a
///    third-party reader for any process) and looks for the startup token
///    (`ColdRestoreAttemptID.startupToken`) among its elements.
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
    /// One handoff check's result: read the leader's current argv, then
    /// decide what it means. `unreadable` means the read itself failed
    /// (`sysctl` error or no argument vector returned) — whether that
    /// becomes `.failed` or `.unobservable` still depends on whether
    /// `NOTE_EXIT` was also observed (a dead process explains an
    /// unreadable argv; an unreadable argv from a live process does not).
    private enum HandoffCheckResult {
        case tokenAbsent
        case tokenStillPresent
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
    /// (its event handler) or synchronously right after registration.
    /// Launches the connect attempt as its own task rather than blocking
    /// here, since a refused connect now retries with a real `Task.sleep`
    /// (see `attemptDiscoveryConnect`), which this `nonisolated` function
    /// itself cannot `await`.
    nonisolated private func checkForSocketAndAdvance(
        socketPath: String,
        bootID: String,
        attemptID: ColdRestoreAttemptID
    ) {
        guard FileManager.default.fileExists(atPath: socketPath) else { return }
        Task {
            await self.attemptDiscoveryConnect(
                socketPath: socketPath, bootID: bootID, attemptID: attemptID, retryIndex: 0)
        }
    }

    /// Program Design item 3, stage 1, amended 2026-09-30: zmx binds the
    /// session socket's filesystem path before it calls `listen`
    /// (socket.zig:113-114), so a connect landing in that gap is refused,
    /// not queued, and no further kqueue directory event follows `listen`
    /// to re-trigger discovery -- the next-`NOTE_WRITE` idea doesn't work
    /// here. `.connectionRefused` retries on `AppPolicies.Restore
    /// .discoveryConnectRetryDelays`'s backoff instead. Exhausting every
    /// attempt still refused does NOT settle: the window stays discovering,
    /// resolved only by a later real fact -- `reportAttachClientExited()`,
    /// or a subsequent `observeSession` failure that isn't `.connectionRefused`
    /// reaching `discoverySettled`'s existing endpoint check.
    ///
    /// `@concurrent nonisolated` (SE-0461): escapes to the global concurrent
    /// executor for its blocking `syscalls.observeSession` call and its
    /// `Task.sleep` backoff, neither of which may run on this actor's own
    /// serial executor. Re-enters the actor only through `discoverySettled`.
    @concurrent nonisolated private func attemptDiscoveryConnect(
        socketPath: String,
        bootID: String,
        attemptID: ColdRestoreAttemptID,
        retryIndex: Int
    ) async {
        switch syscalls.observeSession(path: socketPath, bootID: bootID) {
        case .identity(let identity):
            await discoverySettled(identity: identity, socketPath: socketPath, attemptID: attemptID)
        case .pendingSetsid(let terminalPID):
            // Program Design item 3, stage 1, amended again 2026-09-30:
            // forkpty's child hasn't called setsid yet. This is still
            // discovering, not unobservable -- watch its own exec/exit
            // rather than the zmx directory (listen leaves no further
            // directory event to catch).
            await beginSetsidWatch(
                terminalPID: terminalPID, socketPath: socketPath, bootID: bootID, attemptID: attemptID)
        case .failure(.connectionRefused):
            let delaysMilliseconds = AppPolicies.Restore.discoveryConnectRetryDelays
            guard retryIndex < delaysMilliseconds.count else { return }
            let delayNanoseconds = UInt64(delaysMilliseconds[retryIndex]) * 1_000_000
            try? await Task.sleep(nanoseconds: delayNanoseconds)
            await attemptDiscoveryConnect(
                socketPath: socketPath, bootID: bootID, attemptID: attemptID, retryIndex: retryIndex + 1)
        case .failure:
            await discoverySettled(identity: nil, socketPath: socketPath, attemptID: attemptID)
        }
    }

    /// Program Design item 3, stage 1, amended again 2026-09-30: forkpty's
    /// child always calls `setsid` before its first exec, so this registers
    /// `EVFILT_PROC` `NOTE_EXEC | NOTE_EXIT` on the terminal pid `observe`
    /// couldn't yet validate, then re-observes -- register-then-check,
    /// exactly like discovery's own socket watch and stage 2's handoff
    /// watch. `NOTE_EXIT` firing before any successful observe means the
    /// leader died before ever becoming a session/group leader: failed, not
    /// unobservable.
    private func beginSetsidWatch(
        terminalPID: Int32,
        socketPath: String,
        bootID: String,
        attemptID: ColdRestoreAttemptID
    ) {
        let source = DispatchSource.makeProcessSource(
            identifier: terminalPID,
            eventMask: [.exit, .exec],
            queue: DispatchQueue.global(qos: .userInitiated)
        )
        source.setEventHandler { [weak self] in
            let exitFired = source.data.contains(.exit)
            self?.checkForSetsidAndAdvance(
                terminalPID: terminalPID, socketPath: socketPath, bootID: bootID, attemptID: attemptID,
                exitFired: exitFired)
        }
        source.setCancelHandler {}
        processWatchSource = source
        source.resume()

        // Register first, then check: setsid (and the exec after it) may
        // already have completed by the time this registers.
        checkForSetsidAndAdvance(
            terminalPID: terminalPID, socketPath: socketPath, bootID: bootID, attemptID: attemptID, exitFired: false)
    }

    /// Runs wherever it's called from — the DispatchSource's own GCD queue
    /// or synchronously right after registration — never on this actor's
    /// executor, matching `checkForSocketAndAdvance`'s reasoning.
    nonisolated private func checkForSetsidAndAdvance(
        terminalPID: Int32,
        socketPath: String,
        bootID: String,
        attemptID: ColdRestoreAttemptID,
        exitFired: Bool
    ) {
        if exitFired {
            // Direct settle, not discoverySettled's endpoint-absence check:
            // the socket already exists (that's how this reached
            // .pendingSetsid at all) -- it's the leader itself that died,
            // the exact fact reportAttachClientExited() and stage 2's own
            // exitFired branch already settle unconditionally.
            Task { await self.settle(.failed(.exitedBeforeHandoff(exitStatus: nil))) }
            return
        }
        switch syscalls.observeSession(path: socketPath, bootID: bootID) {
        case .identity(let identity):
            Task { await self.discoverySettled(identity: identity, socketPath: socketPath, attemptID: attemptID) }
        case .pendingSetsid:
            // Not yet -- the watch stays armed and re-checks on the next
            // exec/exit event, exactly like discovery's socket watch and
            // stage 2's handoff watch.
            break
        case .failure:
            // A genuinely different failure than the one that started this
            // watch (e.g. the endpoint disappeared underneath it): resolve
            // through the existing settlement logic rather than looping.
            Task { await self.discoverySettled(identity: nil, socketPath: socketPath, attemptID: attemptID) }
        }
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
        beginHandoffWatch(identity: identity, attemptID: attemptID)
    }

    // MARK: - Stage 2: handoff

    private func beginHandoffWatch(identity: ZmxSessionIdentity, attemptID: ColdRestoreAttemptID) {
        let terminalLeaderPid = identity.terminalLeader.pid
        let source = DispatchSource.makeProcessSource(
            identifier: terminalLeaderPid,
            eventMask: [.exit, .exec],
            queue: DispatchQueue.global(qos: .userInitiated)
        )
        source.setEventHandler { [weak self] in
            let exitFired = source.data.contains(.exit)
            self?.checkForHandoffAndAdvance(identity: identity, attemptID: attemptID, exitFired: exitFired)
        }
        source.setCancelHandler {}
        processWatchSource = source
        source.resume()

        // Register first, then check: handoff may already have completed
        // between discovering the identity and registering this watch.
        checkForHandoffAndAdvance(identity: identity, attemptID: attemptID, exitFired: false)
    }

    /// Runs wherever it's called from — the DispatchSource's own GCD queue
    /// or synchronously right after registration — never on this actor's
    /// executor, matching `checkForSocketAndAdvance`'s reasoning.
    nonisolated private func checkForHandoffAndAdvance(
        identity: ZmxSessionIdentity,
        attemptID: ColdRestoreAttemptID,
        exitFired: Bool
    ) {
        let result = checkHandoff(pid: identity.terminalLeader.pid, attemptID: attemptID)
        Task {
            await self.handoffChecked(identity: identity, checkResult: result, exitFired: exitFired)
        }
    }

    nonisolated private func checkHandoff(pid: Int32, attemptID: ColdRestoreAttemptID) -> HandoffCheckResult {
        switch syscalls.readProcessArgumentsBuffer(pid: pid) {
        case .failure(let errorNumber):
            return .unreadable(errno: errorNumber.rawValue)
        case .success(let buffer):
            guard let arguments = ProcessArgumentsBufferParser.argumentVector(in: buffer) else {
                return .unreadable(errno: EINVAL)
            }
            return arguments.contains(attemptID.startupToken) ? .tokenStillPresent : .tokenAbsent
        }
    }

    private func handoffChecked(
        identity: ZmxSessionIdentity,
        checkResult: HandoffCheckResult,
        exitFired: Bool
    ) {
        guard !isSettled else { return }
        switch checkResult {
        case .tokenAbsent:
            // "the leader is alive, it is still the process from the
            // discovered session's identity (same pid and start time, so a
            // reused pid can't pass), and its arguments no longer carry
            // this attempt's token" — a successful, token-absent read wins
            // as handed off regardless of whether NOTE_EXIT also fired in
            // this same event: the token's absence already proves the exec
            // happened, even if the shell then exited immediately after.
            if ZmxSessionControl.currentIncarnation(forPID: identity.terminalLeader.pid) == identity.terminalLeader {
                settle(.handedOff)
            } else {
                settle(.unobservable(.identityUnverifiable))
            }
        case .tokenStillPresent:
            // Still pending unless the leader has also exited: another exec
            // (zmx's own forked child, /bin/sh's re-exec into bash) without
            // the token gone yet is normal — "no time-only failure" — so
            // this simply waits for the next EVFILT_PROC event.
            if exitFired {
                settle(.failed(.exitedBeforeHandoff(exitStatus: nil)))
            }
        case .unreadable(let errorNumber):
            // NOTE_EXIT explains an unreadable argv (the process is gone);
            // otherwise this is a genuine "couldn't establish the witness."
            if exitFired {
                settle(.failed(.exitedBeforeHandoff(exitStatus: nil)))
            } else {
                settle(.unobservable(.processArgsUnreadable(errno: errorNumber)))
            }
        }
    }
}
