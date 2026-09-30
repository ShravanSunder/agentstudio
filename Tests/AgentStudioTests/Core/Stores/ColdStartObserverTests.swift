import Darwin
import Dispatch
import Foundation
import Testing

@testable import AgentStudioCore
@testable import AgentStudioInfrastructure
@testable import AgentStudioTestSupport

/// SR4, SR5; Program Design item 3: `ColdStartObserver`'s total outcome and
/// its two settlement paths that don't need a real process or a real zmx
/// daemon -- `reportAttachClientExited()` racing an in-progress discovery,
/// and the `.unobservable` cases the plan explicitly sanctions injecting "at
/// the Darwin call boundary with a test double of the syscall wrapper only."
/// The real discovery/handoff paths against a real socket and a real
/// process are proven separately, with real zmx, in the E2E lane.
@Suite("Cold start observer")
struct ColdStartObserverTests {
    private final class ScriptedSyscalls: ColdStartObserverSyscalls, @unchecked Sendable {
        var directoryOpenResult: Result<Int32, POSIXErrorNumber> = .failure(POSIXErrorNumber(EACCES))
        var processArgumentsResult: Result<[UInt8], POSIXErrorNumber> = .failure(POSIXErrorNumber(ESRCH))
        /// Consulted only when `processArgumentsResult` is `.failure` and no
        /// `NOTE_EXIT` fired on that same check. Defaults to the same
        /// outcome the pre-2026-09-30 code always assumed (still alive,
        /// unreadable for some other reason) so a test that never touches
        /// this keeps its prior behavior.
        var leaderStateResult: ColdStartLeaderState = .sameIncarnationAlive
        /// Consumed one per `observeSession` call, in order; once exhausted,
        /// every further call repeats `observeSessionFallback`.
        var observeSessionResults: [ZmxDiscoveryObservation] = []
        /// `beginDiscovery`'s directory watch can (harmlessly, by design)
        /// fire more than once for the same socket appearance, calling
        /// `observeSession` more times than a test scripts -- default
        /// `.failure(.unavailable)` matches every test that doesn't expect
        /// extra calls; a test built around a redundant watch firing (e.g.
        /// `.pendingSetsid` re-checks) sets this to something that stays
        /// consistent with its own scripted sequence instead.
        var observeSessionFallback: ZmxDiscoveryObservation = .failure(.unavailable)

        private let lock = NSLock()
        private var callCount = 0
        private var callCountWaiters: [(threshold: Int, continuation: CheckedContinuation<Int, Never>)] = []

        func openDirectoryForWatching(path: String) -> Result<Int32, POSIXErrorNumber> {
            directoryOpenResult
        }

        func readProcessArgumentsBuffer(pid: Int32) -> Result<[UInt8], POSIXErrorNumber> {
            processArgumentsResult
        }

        func leaderState(of incarnation: ZmxProcessIncarnation) -> ColdStartLeaderState {
            leaderStateResult
        }

        func observeSession(path: String, bootID: String) -> ZmxDiscoveryObservation {
            lock.lock()
            let result = observeSessionResults.isEmpty ? observeSessionFallback : observeSessionResults.removeFirst()
            callCount += 1
            let count = callCount
            let readyWaiters = callCountWaiters.filter { $0.threshold <= count }
            callCountWaiters.removeAll { $0.threshold <= count }
            lock.unlock()
            for waiter in readyWaiters { waiter.continuation.resume(returning: count) }
            return result
        }

        var observeSessionCallCount: Int {
            lock.lock()
            defer { lock.unlock() }
            return callCount
        }

        /// Event-driven wait for the Nth `observeSession` call to have
        /// happened -- no polling, no sleeping: a continuation registered
        /// under the same lock `observeSession` itself resumes under.
        /// Returns the call count observed at resumption, so a caller
        /// asserts on that value directly rather than re-reading
        /// `observeSessionCallCount` afterward.
        @discardableResult
        func waitUntilObserveSessionCalled(atLeast threshold: Int) async -> Int {
            await withCheckedContinuation { continuation in
                lock.lock()
                if callCount >= threshold {
                    let observedCount = callCount
                    lock.unlock()
                    continuation.resume(returning: observedCount)
                    return
                }
                callCountWaiters.append((threshold, continuation))
                lock.unlock()
            }
        }
    }

    /// A minimal, valid `KERN_PROCARGS2`-shaped buffer with `argc = 0` --
    /// `ProcessArgumentsBufferParser.argumentVector` parses it to an empty
    /// array, which never contains a startup token, without needing any
    /// argv strings encoded.
    private func makeEmptyArgumentVectorBuffer(execPath: String = "/bin/example") -> [UInt8] {
        var buffer = withUnsafeBytes(of: Int32(0)) { Array($0) }
        buffer.append(contentsOf: Array(execPath.utf8))
        buffer.append(0)
        return buffer
    }

    /// Same `KERN_PROCARGS2` shape, carrying `argv` -- used where a test
    /// needs the token genuinely present (`tokenStillPresent`), not just an
    /// empty argv that can only ever read as absent.
    private func makeArgumentVectorBuffer(execPath: String = "/bin/example", argv: [String]) -> [UInt8] {
        var buffer = withUnsafeBytes(of: Int32(argv.count)) { Array($0) }
        buffer.append(contentsOf: Array(execPath.utf8))
        buffer.append(0)
        for argument in argv {
            buffer.append(contentsOf: Array(argument.utf8))
            buffer.append(0)
        }
        return buffer
    }

    private func makeFIFOPath() throws -> String {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("cold-start-observer-fifo-\(UUIDv7.generate().uuidString)").path
        guard mkfifo(path, 0o600) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        return path
    }

    /// Blocks until the matching read end (`cat <fifo>`) has genuinely
    /// opened -- real POSIX rendezvous, not a timing guess. Offloaded off
    /// the cooperative pool since it's a real blocking syscall.
    private func openFIFOForWriting(atPath path: String) async throws -> Int32 {
        try await withoutBlockingCooperativePool {
            let descriptor = open(path, O_WRONLY)
            guard descriptor >= 0 else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
            return descriptor
        }
    }

    private func closeFIFOWriteDescriptor(_ descriptor: Int32) async throws {
        try await withoutBlockingCooperativePool {
            guard close(descriptor) == 0 else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
        }
    }

    @Test("a directory-watch registration failure settles unobservable, carrying the injected errno")
    func registrationFailureSettlesUnobservable() async throws {
        let syscalls = ScriptedSyscalls()
        syscalls.directoryOpenResult = .failure(POSIXErrorNumber(EACCES))
        let observer = ColdStartObserver(syscalls: syscalls)

        let outcome = await observer.observeColdStart(
            zmxDirectory: URL(filePath: "/does/not/matter"),
            socketPath: "/does/not/matter/session",
            bootID: "test-boot-id",
            attemptID: ColdRestoreAttemptID.generate()
        )

        #expect(outcome == .unobservable(.watchRegistrationFailed(errno: EACCES)))
    }

    /// R1 Stage 1 fix (2026-09-30), bullet 2 of its own test list: a
    /// positively-confirmed-dead terminal leader (`ZmxSessionControl
    /// .observeForDiscovery`'s `.terminalLeaderGone`, now that
    /// `processSnapshot` tells it apart from a genuinely unverifiable
    /// daemon) settles discovery `.failed` directly -- proof of death
    /// (SR2), never `.unobservable`, matching an absent endpoint's own
    /// standing in `discoverySettled`.
    @Test("a terminal leader positively confirmed dead settles failed, not unobservable")
    func terminalLeaderGoneSettlesFailed() async throws {
        // Arrange
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appending(path: "cold-start-observer-terminal-leader-gone-test-\(UUIDv7.generate().uuidString)")
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        // Pre-created: "register first, then check" means discovery must
        // already find this socket path present the moment it starts.
        let socketPath = temporaryDirectory.appending(path: "session").path
        FileManager.default.createFile(atPath: socketPath, contents: nil)

        let syscalls = ScriptedSyscalls()
        syscalls.directoryOpenResult = .success(try openRealDirectoryDescriptor(at: temporaryDirectory.path))
        syscalls.observeSessionResults = [.terminalLeaderGone]
        let observer = ColdStartObserver(syscalls: syscalls)

        // Act
        let outcome = await observer.observeColdStart(
            zmxDirectory: temporaryDirectory,
            socketPath: socketPath,
            bootID: "test-boot-id",
            attemptID: ColdRestoreAttemptID.generate()
        )

        // Assert
        #expect(outcome == .failed(.exitedBeforeHandoff(exitStatus: nil)))
        #expect(syscalls.observeSessionCallCount == 1)
    }

    @Test("reportAttachClientExited settles a still-pending discovery as failed, never touching exit status")
    func attachClientExitSettlesPendingDiscoveryAsFailed() async throws {
        // A real, harmless directory whose socket never appears: proves the
        // real kqueue registration path doesn't hang or crash, while the
        // race is decided deterministically because discovery genuinely
        // cannot complete on its own here.
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appending(path: "cold-start-observer-test-\(UUIDv7.generate().uuidString)")
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        let observer = ColdStartObserver()

        let observationTask = Task {
            await observer.observeColdStart(
                zmxDirectory: temporaryDirectory,
                socketPath: temporaryDirectory.appending(path: "never-appears").path,
                bootID: "test-boot-id",
                attemptID: ColdRestoreAttemptID.generate()
            )
        }
        await observer.reportAttachClientExited()

        let outcome = await observationTask.value

        #expect(outcome == .failed(.exitedBeforeHandoff(exitStatus: nil)))
    }

    @Test(
        "reportAttachClientExited racing ahead of observeColdStart itself is not a crash -- observeColdStart returns the pre-settled outcome"
    )
    func attachClientExitBeforeObserveColdStartIsNotACrash() async throws {
        let observer = ColdStartObserver()

        await observer.reportAttachClientExited()
        let outcome = await observer.observeColdStart(
            zmxDirectory: URL(filePath: "/does/not/matter"),
            socketPath: "/does/not/matter/session",
            bootID: "test-boot-id",
            attemptID: ColdRestoreAttemptID.generate()
        )

        #expect(outcome == .failed(.exitedBeforeHandoff(exitStatus: nil)))
    }

    @Test("a second reportAttachClientExited after settlement is a no-op, not a double-resume")
    func secondReportAfterSettlementIsANoOp() async throws {
        let observer = ColdStartObserver()

        await observer.reportAttachClientExited()
        let outcome = await observer.observeColdStart(
            zmxDirectory: URL(filePath: "/does/not/matter"),
            socketPath: "/does/not/matter/session",
            bootID: "test-boot-id",
            attemptID: ColdRestoreAttemptID.generate()
        )
        // Would trap (double resume of a CheckedContinuation) if settle()
        // weren't idempotent.
        await observer.reportAttachClientExited()

        #expect(outcome == .failed(.exitedBeforeHandoff(exitStatus: nil)))
    }

    @Test("cancel settles a still-pending discovery without hanging its awaiter")
    func cancelSettlesPendingDiscoveryWithoutHanging() async throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appending(path: "cold-start-observer-cancel-test-\(UUIDv7.generate().uuidString)")
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        let observer = ColdStartObserver()

        let observationTask = Task {
            await observer.observeColdStart(
                zmxDirectory: temporaryDirectory,
                socketPath: temporaryDirectory.appending(path: "never-appears").path,
                bootID: "test-boot-id",
                attemptID: ColdRestoreAttemptID.generate()
            )
        }
        await observer.cancel()

        // The awaiter is unblocked; the specific outcome value carries no
        // meaning the caller of cancel() should act on (see cancel()'s doc).
        _ = await observationTask.value
    }

    /// Opens `path` for `EVFILT_VNODE` watching itself, the same call
    /// `DarwinColdStartObserverSyscalls.openDirectoryForWatching` makes --
    /// a scripted `ScriptedSyscalls` still needs a real, valid descriptor
    /// for `ColdStartObserver`'s real `DispatchSource` registration to work
    /// against, even though the connect/observe step past it is faked. The
    /// observer's own `teardownWatches()` closes it on settlement.
    private func openRealDirectoryDescriptor(at path: String) throws -> Int32 {
        let descriptor = open(path, O_EVTONLY)
        try #require(descriptor >= 0, "expected to open a real directory for EVFILT_VNODE watching")
        return descriptor
    }

    /// Program Design item 3, stage 1, amended 2026-09-30: zmx binds the
    /// session socket's filesystem path before it calls `listen`, so a
    /// connect landing in that gap is refused, not queued -- `discovery`
    /// retries rather than settling unobservable. `terminalLeader` is this
    /// test process's own real, live incarnation (queried the same way
    /// `ZmxSessionControl.currentIncarnation` does), so stage 2's handoff
    /// comparison is fully real, not scripted -- only the discovery-connect
    /// seam is a test double.
    @Test("a connect refused twice then succeeding retries discovery and reaches handoff")
    func connectRefusedTwiceThenSucceedingRetriesDiscoveryAndReachesHandoff() async throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appending(path: "cold-start-observer-discovery-retry-test-\(UUIDv7.generate().uuidString)")
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        // Pre-created: "register first, then check" means discovery must
        // already find this socket path present the moment it starts.
        let socketPath = temporaryDirectory.appending(path: "session").path
        FileManager.default.createFile(atPath: socketPath, contents: nil)

        let syscalls = ScriptedSyscalls()
        syscalls.directoryOpenResult = .success(try openRealDirectoryDescriptor(at: temporaryDirectory.path))
        let selfPID = ProcessInfo.processInfo.processIdentifier
        let selfIncarnation = try #require(ZmxSessionControl.currentIncarnation(forPID: selfPID))
        let identity = ZmxSessionIdentity(
            version: 1,
            bootID: "test-boot-id",
            daemon: selfIncarnation,
            terminalLeader: selfIncarnation,
            processGroupID: selfIncarnation.pid,
            sessionCreatedAt: 0
        )
        syscalls.observeSessionResults = [
            .failure(.connectionRefused),
            .failure(.connectionRefused),
            .identity(identity),
        ]
        syscalls.processArgumentsResult = .success(makeEmptyArgumentVectorBuffer())
        let observer = ColdStartObserver(syscalls: syscalls)

        let outcome = await observer.observeColdStart(
            zmxDirectory: temporaryDirectory,
            socketPath: socketPath,
            bootID: "test-boot-id",
            attemptID: ColdRestoreAttemptID.generate()
        )

        #expect(outcome == .handedOff)
        #expect(syscalls.observeSessionCallCount == 3)
    }

    /// The other half of the same amendment: exhausting every retry still
    /// refused must NOT settle on the timing alone -- the window stays
    /// discovering until a real fact resolves it. Driven entirely through
    /// the scripted call-count seam, never a sleep in this test.
    @Test("a connect refused on every retry stays discovering, and settles only on a later attach-client exit")
    func connectRefusedOnEveryRetryStaysDiscoveringAndSettlesOnAttachClientExit() async throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appending(path: "cold-start-observer-discovery-exhausted-test-\(UUIDv7.generate().uuidString)")
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        let socketPath = temporaryDirectory.appending(path: "session").path
        FileManager.default.createFile(atPath: socketPath, contents: nil)

        let syscalls = ScriptedSyscalls()
        syscalls.directoryOpenResult = .success(try openRealDirectoryDescriptor(at: temporaryDirectory.path))
        syscalls.observeSessionResults = Array(
            repeating: .failure(.connectionRefused), count: AppPolicies.Restore.discoveryConnectRetryDelays.count + 1)
        let observer = ColdStartObserver(syscalls: syscalls)

        let observationTask = Task {
            await observer.observeColdStart(
                zmxDirectory: temporaryDirectory,
                socketPath: socketPath,
                bootID: "test-boot-id",
                attemptID: ColdRestoreAttemptID.generate()
            )
        }

        // Every scripted attempt (the initial connect plus every retry) has
        // genuinely run before the exit fires -- proves the window was
        // still discovering through the whole retry budget, not settled
        // early by some other path.
        let expectedAttempts = AppPolicies.Restore.discoveryConnectRetryDelays.count + 1
        let observedCallCount = await syscalls.waitUntilObserveSessionCalled(atLeast: expectedAttempts)
        #expect(observedCallCount == expectedAttempts)
        await observer.reportAttachClientExited()

        let outcome = await observationTask.value

        #expect(outcome == .failed(.exitedBeforeHandoff(exitStatus: nil)))
    }

    /// Program Design item 3, stage 1, amended again 2026-09-30:
    /// `unexpectedProcessGroup`/`unexpectedProcessParent` means the pty
    /// child hasn't called `setsid` yet -- still discovering, not
    /// unobservable. Watches a real, short-lived process's own real exec
    /// (spawned here, not zmx) so the re-observe genuinely happens at a
    /// real `NOTE_EXEC`, not just the immediate post-registration check --
    /// the scripted sequence's middle entry proves that immediate check
    /// still sees `.pendingSetsid` (the real process hasn't exec'd yet).
    ///
    /// Amended a third time 2026-09-30, against real evidence, not a guess:
    /// a plain `sleep 0.05` before the real exec raced the test's own async
    /// setup under load -- the scripted immediate-post-registration check
    /// always answers `.pendingSetsid` regardless of what the real process
    /// has actually done, so if the real exec happened before
    /// `beginSetsidWatch`'s registration (possible under load, since
    /// nothing bounded that race), the watch registered too late to ever
    /// see its `NOTE_EXEC`, and the observer hung until the final `/bin/sleep
    /// 300` itself exited (`.failed`, not `.handedOff`, after minutes, not
    /// milliseconds). A deterministic FIFO hold point (the same pattern
    /// `43f02d4c8` uses against real zmx) removes the race instead of
    /// tolerating it: the real process cannot reach its own exec until this
    /// test releases it, and the release itself waits for `ScriptedSyscalls`'
    /// own call-count event -- proof the immediate post-registration check
    /// (call 2) has already happened, which only occurs after
    /// `beginSetsidWatch`'s `DispatchSource` has already registered.
    @Test("unexpectedProcessGroup re-observes at the real exec and discovers correctly")
    func pendingSetsidReobservesAtRealExecAndDiscovers() async throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appending(path: "cold-start-observer-pending-setsid-exec-test-\(UUIDv7.generate().uuidString)")
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        let socketPath = temporaryDirectory.appending(path: "session").path
        FileManager.default.createFile(atPath: socketPath, contents: nil)

        let holdFIFOPath = try makeFIFOPath()
        defer { try? FileManager.default.removeItem(atPath: holdFIFOPath) }

        let controlledProcess = Process()
        controlledProcess.executableURL = URL(fileURLWithPath: "/bin/sh")
        controlledProcess.arguments = ["-c", "read _ < '\(holdFIFOPath)'; exec /bin/sleep 300"]
        controlledProcess.standardOutput = FileHandle.nullDevice
        controlledProcess.standardError = FileHandle.nullDevice
        try controlledProcess.run()
        defer { controlledProcess.terminate() }
        let terminalPID = controlledProcess.processIdentifier

        let syscalls = ScriptedSyscalls()
        syscalls.directoryOpenResult = .success(try openRealDirectoryDescriptor(at: temporaryDirectory.path))
        let selfPID = ProcessInfo.processInfo.processIdentifier
        let selfIncarnation = try #require(ZmxSessionControl.currentIncarnation(forPID: selfPID))
        let identity = ZmxSessionIdentity(
            version: 1,
            bootID: "test-boot-id",
            daemon: selfIncarnation,
            terminalLeader: selfIncarnation,
            processGroupID: selfIncarnation.pid,
            sessionCreatedAt: 0
        )
        syscalls.observeSessionResults = [
            .pendingSetsid(terminalPID: terminalPID),
            // The immediate post-registration check (register-then-check):
            // the real process is still blocked at the FIFO hold, so it
            // genuinely hasn't exec'd yet -- deterministically, not by
            // timing luck.
            .pendingSetsid(terminalPID: terminalPID),
            // The check the real NOTE_EXEC event triggers, once this test
            // releases the hold below.
            .identity(identity),
        ]
        // beginDiscovery's directory watch can harmlessly re-fire beyond
        // what's scripted above (e.g. the temp directory's own creation
        // write); keep any such extra call consistent with "still
        // discovering" instead of falling to the default .unavailable,
        // which would spuriously settle unobservable.
        syscalls.observeSessionFallback = .pendingSetsid(terminalPID: terminalPID)
        syscalls.processArgumentsResult = .success(makeEmptyArgumentVectorBuffer())
        let observer = ColdStartObserver(syscalls: syscalls)

        async let outcome = observer.observeColdStart(
            zmxDirectory: temporaryDirectory,
            socketPath: socketPath,
            bootID: "test-boot-id",
            attemptID: ColdRestoreAttemptID.generate()
        )

        // Release only once the observer's own immediate post-registration
        // check has genuinely happened -- an event ScriptedSyscalls itself
        // reports, never a poll or a sleep.
        await syscalls.waitUntilObserveSessionCalled(atLeast: 2)
        let fifoWriteDescriptor = try await openFIFOForWriting(atPath: holdFIFOPath)
        try await closeFIFOWriteDescriptor(fifoWriteDescriptor)

        let settledOutcome = await outcome
        #expect(settledOutcome == .handedOff)
        #expect(syscalls.observeSessionCallCount == 3)
    }

    /// The other half: a leader that exits before ever calling `setsid`
    /// (or at least before `observe` ever succeeds) settles failed, never
    /// unobservable -- `NOTE_EXIT` fires with no intervening `NOTE_EXEC`.
    @Test("a leader that exits before setsid ever succeeds settles failed")
    func pendingSetsidExitBeforeAnySuccessSettlesFailed() async throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appending(path: "cold-start-observer-pending-setsid-exit-test-\(UUIDv7.generate().uuidString)")
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        let socketPath = temporaryDirectory.appending(path: "session").path
        FileManager.default.createFile(atPath: socketPath, contents: nil)

        let controlledProcess = Process()
        controlledProcess.executableURL = URL(fileURLWithPath: "/bin/sh")
        controlledProcess.arguments = ["-c", "sleep 0.05; exit 1"]
        controlledProcess.standardOutput = FileHandle.nullDevice
        controlledProcess.standardError = FileHandle.nullDevice
        try controlledProcess.run()
        let terminalPID = controlledProcess.processIdentifier

        let syscalls = ScriptedSyscalls()
        syscalls.directoryOpenResult = .success(try openRealDirectoryDescriptor(at: temporaryDirectory.path))
        syscalls.observeSessionResults = [
            .pendingSetsid(terminalPID: terminalPID),
            .pendingSetsid(terminalPID: terminalPID),
        ]
        // See the sibling test's comment: absorb any extra redundant
        // directory-watch-triggered call without spuriously settling.
        syscalls.observeSessionFallback = .pendingSetsid(terminalPID: terminalPID)
        let observer = ColdStartObserver(syscalls: syscalls)

        let outcome = await observer.observeColdStart(
            zmxDirectory: temporaryDirectory,
            socketPath: socketPath,
            bootID: "test-boot-id",
            attemptID: ColdRestoreAttemptID.generate()
        )

        #expect(outcome == .failed(.exitedBeforeHandoff(exitStatus: nil)))
    }

    /// Event-driven wait for a real process's own `NOTE_EXIT`, so a test can
    /// know for certain a leader has already exited before the observer
    /// ever looks at it -- never `Process.waitUntilExit()` (a blocking call
    /// off the cooperative pool) or a sleep. Returns the pid that exited,
    /// the observation that satisfied the wait.
    @discardableResult
    private func waitForRealProcessExit(pid: Int32) async -> Int32 {
        await withCheckedContinuation { (continuation: CheckedContinuation<Int32, Never>) in
            let source = DispatchSource.makeProcessSource(
                identifier: pid, eventMask: .exit, queue: .global(qos: .userInitiated))
            source.setEventHandler {
                source.cancel()
                continuation.resume(returning: pid)
            }
            source.setCancelHandler {}
            source.resume()
        }
    }

    /// 2026-09-30 finding: `beginHandoffWatch`'s register-then-check
    /// immediate call hardcodes `exitFired: false` --
    /// `checkForHandoffAndAdvance(identity: identity, attemptID: attemptID,
    /// exitFired: false)`, right after `source.resume()`. Its own comment
    /// only accounts for "handoff may have already completed" (the
    /// token-absent case); it doesn't account for the leader having already
    /// exited before this watch even registers. When that happens, the argv
    /// read genuinely fails (observed for real against a zmx cold-restore
    /// leader that already exited: `EINVAL`, not the `ESRCH` a dead-process
    /// read might suggest), and `handoffChecked`'s `.unreadable` branch sees
    /// the hardcoded `false` and settles `.unobservable` instead of
    /// `.failed` -- even though the leader is provably, already dead.
    /// Reproduced deterministically here: the real process is confirmed
    /// exited (via a real `NOTE_EXIT` wait) before `observeColdStart` is
    /// even called, so the scripted `.unreadable` result can only be seen
    /// through the immediate check's hardcoded `exitFired: false` -- no
    /// later real event is what settles this.
    @Test(
        "a leader already exited before Stage 2 registers still settles failed, not unobservable, on an unreadable argv"
    )
    func leaderAlreadyExitedBeforeHandoffRegistrationSettlesFailedNotUnobservable() async throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appending(path: "cold-start-observer-handoff-already-exited-test-\(UUIDv7.generate().uuidString)")
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        let socketPath = temporaryDirectory.appending(path: "session").path
        FileManager.default.createFile(atPath: socketPath, contents: nil)

        let controlledProcess = Process()
        controlledProcess.executableURL = URL(fileURLWithPath: "/bin/sh")
        controlledProcess.arguments = ["-c", "exit 0"]
        controlledProcess.standardOutput = FileHandle.nullDevice
        controlledProcess.standardError = FileHandle.nullDevice
        try controlledProcess.run()
        let terminalPID = controlledProcess.processIdentifier
        // Captured while the process is still resolvable -- observeColdStart
        // itself never queries process state for this identity; only
        // checkHandoff's scripted argv read does, below.
        let incarnation = try #require(ZmxSessionControl.currentIncarnation(forPID: terminalPID))
        await waitForRealProcessExit(pid: terminalPID)

        let syscalls = ScriptedSyscalls()
        syscalls.directoryOpenResult = .success(try openRealDirectoryDescriptor(at: temporaryDirectory.path))
        let identity = ZmxSessionIdentity(
            version: 1,
            bootID: "test-boot-id",
            daemon: incarnation,
            terminalLeader: incarnation,
            processGroupID: incarnation.pid,
            sessionCreatedAt: 0
        )
        syscalls.observeSessionResults = [.identity(identity)]
        syscalls.processArgumentsResult = .failure(POSIXErrorNumber(EINVAL))
        syscalls.leaderStateResult = .exited
        let observer = ColdStartObserver(syscalls: syscalls)

        let outcome = await observer.observeColdStart(
            zmxDirectory: temporaryDirectory,
            socketPath: socketPath,
            bootID: "test-boot-id",
            attemptID: ColdRestoreAttemptID.generate()
        )

        #expect(outcome == .failed(.exitedBeforeHandoff(exitStatus: nil)))
    }

    /// The other half of the same amendment: an unreadable argv from a
    /// leader that's still genuinely alive (the same incarnation) must stay
    /// `.unobservable`, not become `.failed` just because it couldn't be
    /// read -- `leaderState` is what tells these two apart now.
    @Test("an unreadable argv from a leader that's still the same, alive incarnation settles unobservable")
    func unreadableArgvFromAStillAliveLeaderSettlesUnobservable() async throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appending(path: "cold-start-observer-handoff-still-alive-test-\(UUIDv7.generate().uuidString)")
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        let socketPath = temporaryDirectory.appending(path: "session").path
        FileManager.default.createFile(atPath: socketPath, contents: nil)

        let syscalls = ScriptedSyscalls()
        syscalls.directoryOpenResult = .success(try openRealDirectoryDescriptor(at: temporaryDirectory.path))
        let selfPID = ProcessInfo.processInfo.processIdentifier
        let selfIncarnation = try #require(ZmxSessionControl.currentIncarnation(forPID: selfPID))
        let identity = ZmxSessionIdentity(
            version: 1,
            bootID: "test-boot-id",
            daemon: selfIncarnation,
            terminalLeader: selfIncarnation,
            processGroupID: selfIncarnation.pid,
            sessionCreatedAt: 0
        )
        syscalls.observeSessionResults = [.identity(identity)]
        syscalls.processArgumentsResult = .failure(POSIXErrorNumber(EACCES))
        syscalls.leaderStateResult = .sameIncarnationAlive
        let observer = ColdStartObserver(syscalls: syscalls)

        let outcome = await observer.observeColdStart(
            zmxDirectory: temporaryDirectory,
            socketPath: socketPath,
            bootID: "test-boot-id",
            attemptID: ColdRestoreAttemptID.generate()
        )

        #expect(outcome == .unobservable(.processArgsUnreadable(errno: EACCES)))
    }

    /// The same defect could hit the *event* path too, not just the
    /// immediate post-registration check: a `NOTE_EXEC` event whose own
    /// argv read races a later exit. Held at a real FIFO so the leader-state
    /// swap below happens-before the real leader's own exec, and that
    /// exec's real `NOTE_EXEC` happens-before the check that must see the
    /// swapped values -- not a timing guess.
    @Test("an exec event whose own argv read races a later exit also settles failed, not just the immediate check")
    func execEventArgvReadRacingALaterExitSettlesFailed() async throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appending(path: "cold-start-observer-handoff-event-race-test-\(UUIDv7.generate().uuidString)")
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        let socketPath = temporaryDirectory.appending(path: "session").path
        FileManager.default.createFile(atPath: socketPath, contents: nil)
        let holdFIFOPath = try makeFIFOPath()
        defer { try? FileManager.default.removeItem(atPath: holdFIFOPath) }

        let attemptID = ColdRestoreAttemptID.generate()
        let controlledProcess = Process()
        controlledProcess.executableURL = URL(fileURLWithPath: "/bin/sh")
        controlledProcess.arguments = ["-c", "cat \(holdFIFOPath); exec /bin/sleep 300"]
        controlledProcess.standardOutput = FileHandle.nullDevice
        controlledProcess.standardError = FileHandle.nullDevice
        try controlledProcess.run()
        defer { controlledProcess.terminate() }
        let terminalPID = controlledProcess.processIdentifier
        let terminalIncarnation = try #require(ZmxSessionControl.currentIncarnation(forPID: terminalPID))

        let syscalls = ScriptedSyscalls()
        syscalls.directoryOpenResult = .success(try openRealDirectoryDescriptor(at: temporaryDirectory.path))
        let identity = ZmxSessionIdentity(
            version: 1,
            bootID: "test-boot-id",
            daemon: terminalIncarnation,
            terminalLeader: terminalIncarnation,
            processGroupID: terminalIncarnation.pid,
            sessionCreatedAt: 0
        )
        syscalls.observeSessionResults = [.identity(identity)]
        // The immediate post-registration check: the real leader is
        // genuinely still blocked on the FIFO, token present -- Stage 2
        // must wait here, not settle.
        syscalls.processArgumentsResult = .success(
            makeArgumentVectorBuffer(execPath: "/bin/sh", argv: [attemptID.startupToken]))
        let observer = ColdStartObserver(syscalls: syscalls)

        async let outcome = observer.observeColdStart(
            zmxDirectory: temporaryDirectory,
            socketPath: socketPath,
            bootID: "test-boot-id",
            attemptID: attemptID
        )

        // Swap before releasing: happens-before the real leader's own exec,
        // which happens-before the real NOTE_EXEC event this swap must be
        // visible to.
        syscalls.processArgumentsResult = .failure(POSIXErrorNumber(EINVAL))
        syscalls.leaderStateResult = .exited
        let writeDescriptor = try await openFIFOForWriting(atPath: holdFIFOPath)
        try await closeFIFOWriteDescriptor(writeDescriptor)

        let settledOutcome = await outcome

        #expect(settledOutcome == .failed(.exitedBeforeHandoff(exitStatus: nil)))
    }
}
