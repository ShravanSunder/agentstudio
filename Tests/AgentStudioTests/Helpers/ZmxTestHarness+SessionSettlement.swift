import AgentStudioTestHarness
import Darwin
import Foundation

@testable import AgentStudio

/// `ZmxTestHarness`'s session-settlement waits, split into their own file
/// (the repo's line-length ceiling, same precedent as
/// `ZmxE2ETests+RealEventWaits.swift`/`ZmxE2ETests+ForcedTiming.swift`):
/// `waitForSessionSocket`/`awaitSessionSocketEvent` (the socket-appearance
/// wait, now racing against the spawning launcher's own exit) and
/// `waitUntilSessionSettled`/`resolveSettledDiscovery`/`resolveViaSetsidWatch`
/// (the identity-discovery wait that follows it). Everything else --
/// construction, environment, spawning, cleanup -- stays in
/// `ZmxTestHarness.swift`.
extension ZmxTestHarness {
    /// F7 residual (advisor review round 2, Lead 2026-10-02): `open(2)`
    /// failing on `zmxDir` used to fall back to a deadline poll -- the
    /// owner's rule bans deadline polling in tests outright, and having no
    /// event source available is not an exemption. There is nothing to
    /// register a real watch against in that case, so the honest test
    /// behavior is to fail immediately with the real cause
    /// (`SessionSettlementError.sessionDirectoryUnwatchable`), not poll
    /// hoping the directory becomes openable. No deadline/timeout
    /// parameter remains on this function at all.
    ///
    /// R1 gate 3 (Lead 2026-10-02): `zmxLauncherProcessID`, when known, races
    /// the watch below against that launcher exiting -- see
    /// `awaitSessionSocketEvent`'s doc comment. `nil` (default) leaves every
    /// other caller, including this file's own `exists: false` checks,
    /// unchanged.
    func waitForSessionSocket(
        sessionId: String,
        exists expectedExists: Bool,
        racingAgainstExitOf zmxLauncherProcessID: Int32? = nil
    ) async throws -> Bool {
        let sessionSocketPath = sessionSocketPath(for: sessionId)
        if FileManager.default.fileExists(atPath: sessionSocketPath) == expectedExists {
            return true
        }

        let directoryFileDescriptor = open(zmxDir, O_EVTONLY)
        guard directoryFileDescriptor >= 0 else {
            throw SessionSettlementError.sessionDirectoryUnwatchable(path: zmxDir, errno: errno)
        }
        // R2-4 item 2 (review round 2, Lead 2026-10-01): ownership of this
        // descriptor passes to `awaitSessionSocketEvent`, which now closes
        // it from its own dispatch source's cancel handler -- the SDK's
        // documented safe boundary (source.h:449), matching A4's own
        // `closeWatchedDirectory`-from-cancel-handler shape in production.
        // A bare `defer` here would close it the instant that call
        // returns, which is not the same moment: `dispatch_source_cancel`
        // only requests cancellation (source.h:512), so this scope's own
        // close could race the source's still-in-flight teardown.
        return await awaitSessionSocketEvent(
            fileDescriptor: directoryFileDescriptor,
            sessionSocketPath: sessionSocketPath,
            exists: expectedExists,
            racingAgainstExitOf: zmxLauncherProcessID
        )
    }

    /// Blocks until a freshly spawned session's terminal leader has
    /// completed `setsid()`, using the exact production discovery mechanism
    /// (`ZmxSessionControl.observeForDiscovery`, backed off on a refused
    /// connect, and an `EVFILT_PROC NOTE_EXEC` watch when setsid hasn't
    /// landed yet) rather than a sleep or a retry-until poll loop --
    /// mirroring `ColdStartObserver.attemptDiscoveryConnect` and
    /// `beginSetsidWatch`. `spawnZmxSession` and `spawnColdRestoreSession`
    /// call this before returning, so every zmx-e2e test that spawns
    /// through them starts from a session whose leader is already past the
    /// setsid race window.
    ///
    /// R2-5 item 2 (Lead decision 2026-10-02, option c): widened from
    /// `private` so `ZmxE2ETests+RealEventWaits.swift`'s
    /// `awaitSessionIdentityOnRealEvent` can reuse this exact settle wait
    /// for its own transient-connect-failure case, instead of its own
    /// polling loop -- the one architecture-debt-ledger-tracked polling
    /// instance in this file stays the only one; no new retry site.
    ///
    /// R1 gate 3 (Lead 2026-10-02): `zmxLauncherProcessID`, when known, races
    /// the socket wait below against that launcher's exit; `nil` (default)
    /// leaves every other caller, `RealEventWaits`' retry-reuse included,
    /// unchanged.
    @discardableResult
    func waitUntilSessionSettled(
        sessionId: String,
        zmxLauncherProcessID: Int32? = nil
    ) async throws -> ZmxSessionIdentity {
        guard
            try await waitForSessionSocket(
                sessionId: sessionId, exists: true, racingAgainstExitOf: zmxLauncherProcessID
            )
        else {
            throw SessionSettlementError.socketNeverAppeared(sessionId: sessionId)
        }
        let socketPath = sessionSocketPath(for: sessionId)
        let bootID = try await WorkspaceUndoJournalClock.current().bootID
        return try await resolveSettledDiscovery(socketPath: socketPath, bootID: bootID, retryIndex: 0)
    }

    private func resolveSettledDiscovery(
        socketPath: String,
        bootID: String,
        retryIndex: Int
    ) async throws -> ZmxSessionIdentity {
        switch ZmxSessionControl.observeForDiscovery(path: socketPath, bootID: bootID) {
        case .identity(let identity):
            return identity
        case .pendingSetsid(let terminalPID):
            return try await resolveViaSetsidWatch(terminalPID: terminalPID, socketPath: socketPath, bootID: bootID)
        case .terminalLeaderGone:
            throw SessionSettlementError.terminalLeaderConfirmedGone
        case .failure(let failure) where Self.isTransientDuringSettlement(failure):
            // Amended 2026-09-30 against evidence, not guessed: a fresh
            // two-daemon spawn ("orphan discovery finds untracked session")
            // hit .timeout on its first full zmx-e2e run here. This wait
            // runs right after the socket first appears -- the same early,
            // racy window `waitForObservedSessionIdentity` below already
            // tolerates .unavailable/.connectionRefused/.processUnverifiable
            // /.timeout on for the identical reason ("a busy startup may not
            // answer within one bounded request"). ColdStartObserver's own
            // attemptDiscoveryConnect only retries .connectionRefused
            // because its directory-watch trigger already gives the daemon
            // more time before the first connect; this harness wait has no
            // such head start, so it matches the broader, already-proven
            // tolerance instead.
            //
            // F7 (review round 1): exhausting the backoff schedule must not
            // throw -- that would fail this wait on elapsed time alone,
            // which the production discoverer
            // (`ColdStartObserver.attemptDiscoveryConnect`) never does for
            // this same failure: exhausting its own identical schedule
            // just leaves the window "discovering," resolved only by a
            // later real fact. This harness has no later event source to
            // lean on for this specific transient case, so past the
            // schedule's own last entry it keeps retrying at that entry's
            // cadence -- bounded only by the suite's runner-owned hang
            // bound, never by a time budget of its own.
            //
            // R2-4 item 1 (review round 2, Lead 2026-10-01): `try?`
            // swallowed every throw from `clock.sleep`, cancellation
            // included -- the suite's own hang bound relies on task
            // cancellation to end an owned wait, and this loop kept
            // retrying through it regardless. `try await` instead: this
            // function is already `async throws`, so a thrown
            // `CancellationError` (or any other) now ends the retry here
            // and propagates to `waitUntilSessionSettled`'s own caller
            // exactly as every other failure case in this `switch` already
            // does, rather than retrying past it.
            let delaysMilliseconds = AppPolicies.Restore.discoveryConnectRetryDelays
            let delayIndex = min(retryIndex, delaysMilliseconds.count - 1)
            try await clock.sleep(for: .milliseconds(delaysMilliseconds[delayIndex]))
            return try await resolveSettledDiscovery(socketPath: socketPath, bootID: bootID, retryIndex: retryIndex + 1)
        case .failure(let failure):
            throw failure
        }
    }

    private static func isTransientDuringSettlement(_ failure: ZmxSessionControlFailure) -> Bool {
        switch failure {
        case .connectionRefused, .unavailable, .processUnverifiable, .timeout:
            return true
        case .invalidIdentity, .invalidSocketPath, .invalidResponse, .identityMismatch,
            .unexpectedProcessParent, .unexpectedProcessGroup, .nativeAttachmentPresent, .awaitingProcessExit:
            return false
        }
    }

    /// Register-then-check, exactly like `ColdStartObserver
    /// .beginSetsidWatch`/`checkForSetsidAndAdvance`: the leader can
    /// complete setsid and exec between the `.pendingSetsid` observation
    /// above and this registration, so the mandatory initial check must
    /// run only once kernel registration is confirmed complete, not
    /// synchronously after `resume()` returns on the caller's own Task.
    ///
    /// R2-4 item 2 (review round 2, Lead 2026-10-01): the prior shape ran
    /// that initial check synchronously right after `resume()`, which only
    /// requests registration -- the SDK's own contract (source.h:745) says
    /// the registration handler fires "once the corresponding kevent() has
    /// been registered with the system, following the initial
    /// dispatch_resume()". A transition landing in the gap between
    /// `resume()` returning and kernel registration actually completing
    /// could be missed by both: the kqueue wasn't registered yet to catch
    /// it as an edge, and the synchronous check had already read "still
    /// pending." Setting `setRegistrationHandler` before `resume()`, and
    /// running the same check from it, closes that gap -- the same one F1
    /// fixed in production. Both the event handler and the registration
    /// handler now run on this source's own GCD queue and may call
    /// `arriveBlocking` directly; there is no longer a separate
    /// caller's-Task code path.
    private func resolveViaSetsidWatch(
        terminalPID: Int32,
        socketPath: String,
        bootID: String
    ) async throws -> ZmxSessionIdentity {
        // `HeldStep` itself already guarantees only the first arrival is
        // returned by `firstArrival()` -- a later arrival is simply
        // recorded and ignored, so the former hand-kept `SettlementGate`
        // added nothing `HeldStep` doesn't already provide.
        let step = HeldStep<Result<ZmxSessionIdentity, any Error>>(
            "zmx setsid watch settlement")
        let source = DispatchSource.makeProcessSource(
            identifier: terminalPID,
            eventMask: [.exit, .exec],
            queue: DispatchQueue.global(qos: .userInitiated)
        )

        // Pure: nil means "not settled yet, stays armed." Shared by the
        // registration handler's mandatory initial check and the event
        // handler's later re-checks -- both now run on this source's own
        // GCD queue, never on the caller's Task.
        func outcome(exitFired: Bool) -> Result<ZmxSessionIdentity, any Error>? {
            if exitFired {
                return .failure(SessionSettlementError.terminalLeaderExitedBeforeSetsid(terminalPID: terminalPID))
            }
            switch ZmxSessionControl.observeForDiscovery(path: socketPath, bootID: bootID) {
            case .identity(let identity):
                return .success(identity)
            case .pendingSetsid:
                return nil  // not settled yet; the watch stays armed for the next event
            case .terminalLeaderGone:
                return .failure(SessionSettlementError.terminalLeaderConfirmedGone)
            case .failure(let failure):
                return .failure(failure)
            }
        }

        // One shared check, called from both the event handler and the
        // registration handler -- mirroring `ColdStartObserver
        // .beginSetsidWatch`'s own `checkForSetsidAndAdvance` shape.
        // Idempotent: a settled source is already cancelled, so a harmless
        // re-entry from the other callback finds nothing left to check
        // (`outcome` would be called again, but `step.arriveBlocking` after
        // the first `firstArrival()` only records and is ignored).
        func checkAndSettleIfReady(exitFired: Bool) {
            guard let result = outcome(exitFired: exitFired) else { return }
            source.cancel()
            // A raw GCD callback on .global(), not inside a Swift Task.
            try? step.arriveBlocking(result)
        }

        source.setEventHandler {
            checkAndSettleIfReady(exitFired: source.data.contains(.exit))
        }
        source.setCancelHandler {}
        // The mandatory initial check: `exitFired: false` mirrors the event
        // handler's own shape for this call -- this firing carries no real
        // `NOTE_EXIT`, so an already-dead leader is still caught by
        // `ZmxSessionControl.observeForDiscovery`'s own `.terminalLeaderGone`
        // case inside `outcome`, not assumed from this call alone.
        source.setRegistrationHandler {
            checkAndSettleIfReady(exitFired: false)
        }
        source.resume()

        let settled = try await step.firstArrival()
        step.release()
        return try settled.get()
    }

    /// F7 (review round 1): no more a timed race. A real-time `clock.sleep`
    /// racing the real vnode event made this return `false` ("never
    /// appeared") whenever the daemon was merely slow, not actually broken
    /// -- "wrapping a timeout in HeldStep does not change what determines
    /// its verdict." Register-then-check against the real event alone now;
    /// a socket that genuinely never appears with no `zmxLauncherProcessID`
    /// given is caught only by the suite's own runner-owned hang bound,
    /// which names this step ("session socket event") as what was awaited.
    ///
    /// R2-4 item 2 (review round 2, Lead 2026-10-01): the prior shape ran
    /// its "register-then-check" synchronously on the caller's own Task
    /// right after `resume()`, which only requests kernel registration
    /// (source.h:745) -- a transition landing in the gap before that
    /// registration actually completes could be missed by both the
    /// not-yet-armed kqueue and the already-run synchronous check. Moving
    /// the mandatory initial check into `setRegistrationHandler` closes
    /// that gap, mirroring `resolveViaSetsidWatch`'s identical fix above.
    /// The cancel handler now also owns closing `fileDescriptor` -- the
    /// caller (`waitForSessionSocket`) no longer does, for the same A4
    /// reasoning: only the cancel handler is the SDK's documented
    /// safe-to-close point (source.h:449).
    ///
    /// R1 gate 3 (Lead 2026-10-02): `zmxLauncherProcessID`, when given, races
    /// this wait against that process exiting -- "the zmx process it
    /// expected to create the socket exiting," named above but not yet
    /// built. Confirmed against source: `zmx attach`'s
    /// `Daemon.ensureSession`/`run` (vendor/zmx/src/loop.zig:741,763-784)
    /// creates and binds the socket synchronously, before any fork, inside
    /// this exact launcher; any failure there exits the launcher with no
    /// socket ever created and nothing under `zmxDir` to watch for. The
    /// launcher does not exit quickly on success -- `run()`'s
    /// `error.IsClientProc` branch (loop.zig:769-777) keeps it alive as the
    /// attached client for the whole session -- so this cannot false-positive.
    private func awaitSessionSocketEvent(
        fileDescriptor: Int32,
        sessionSocketPath: String,
        exists expectedExists: Bool,
        racingAgainstExitOf zmxLauncherProcessID: Int32?
    ) async -> Bool {
        let step = HeldStep<Bool>("session socket event")
        let eventSource = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.write, .rename, .delete],
            queue: DispatchQueue.global(qos: .userInitiated)
        )

        // Shared by the registration handler's mandatory initial check and
        // the event handler's later re-checks -- both run on this source's
        // own GCD queue, never on the caller's Task, so both may call
        // `arriveBlocking` directly. Idempotent: a settled source is
        // already cancelled, so a harmless re-entry from the other
        // callback finds nothing new to do.
        func checkAndSettleIfSocketReady() {
            guard FileManager.default.fileExists(atPath: sessionSocketPath) == expectedExists else { return }
            eventSource.cancel()
            // A raw GCD callback on .global(), not inside a Swift Task.
            try? step.arriveBlocking(true)
        }

        eventSource.setEventHandler {
            checkAndSettleIfSocketReady()
        }
        // A4-shaped: closes the descriptor this source owns, exactly once,
        // only once cancellation has actually completed.
        eventSource.setCancelHandler {
            close(fileDescriptor)
        }
        // The mandatory initial check, run once kernel registration is
        // confirmed complete -- not synchronously after `resume()` returns.
        eventSource.setRegistrationHandler {
            checkAndSettleIfSocketReady()
        }
        eventSource.resume()

        // R1 gate 3: the other half of the race, armed only when named.
        // Mirrors `resolveViaSetsidWatch`'s own register-then-check process
        // watch, including its `exitFired` shape: a real `NOTE_EXIT` is the
        // fact once it fires -- not the launcher's reaped status, which
        // races Foundation's own `Process` reaping it on an unrelated
        // handler. `kill(pid, 0)` is only the mandatory initial check's own
        // fallback, for a launcher already gone (and possibly already
        // reaped) before this watch's kevent was registered to see a real
        // exit event for it. `HeldStep` guarantees only the first of the
        // two sources racing here wins.
        var processExitSource: DispatchSourceProcess?
        if let zmxLauncherProcessID {
            let exitSource = DispatchSource.makeProcessSource(
                identifier: zmxLauncherProcessID,
                eventMask: [.exit],
                queue: DispatchQueue.global(qos: .userInitiated)
            )
            // Pure: true only once the socket still never matched, and
            // either the real exit event fired or (registration-time only)
            // the launcher is independently confirmed gone.
            func launcherGone(exitFired: Bool) -> Bool {
                guard FileManager.default.fileExists(atPath: sessionSocketPath) != expectedExists else {
                    return false
                }
                if exitFired { return true }
                return kill(zmxLauncherProcessID, 0) != 0 && errno == ESRCH
            }
            func checkAndSettleIfLauncherGone(exitFired: Bool) {
                guard launcherGone(exitFired: exitFired) else { return }
                eventSource.cancel()
                exitSource.cancel()
                try? step.arriveBlocking(false)
            }
            exitSource.setEventHandler {
                checkAndSettleIfLauncherGone(exitFired: exitSource.data.contains(.exit))
            }
            exitSource.setCancelHandler {}
            exitSource.setRegistrationHandler {
                checkAndSettleIfLauncherGone(exitFired: false)
            }
            exitSource.resume()
            processExitSource = exitSource
        }

        let result = (try? await step.firstArrival()) ?? false
        step.release()
        processExitSource?.cancel()
        // Safety net, not the primary path: if `firstArrival()` returned
        // through external cancellation rather than a matched check above,
        // the source may still be live -- cancelling here is a no-op when
        // already cancelled, and still routes the descriptor's close
        // through the cancel handler either way.
        eventSource.cancel()
        return result
    }
}
