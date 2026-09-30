import Foundation
import Testing

@testable import AgentStudioCore
@testable import AgentStudioInfrastructure

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
    @Test("unexpectedProcessGroup re-observes at the real exec and discovers correctly")
    func pendingSetsidReobservesAtRealExecAndDiscovers() async throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appending(path: "cold-start-observer-pending-setsid-exec-test-\(UUIDv7.generate().uuidString)")
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        let socketPath = temporaryDirectory.appending(path: "session").path
        FileManager.default.createFile(atPath: socketPath, contents: nil)

        let controlledProcess = Process()
        controlledProcess.executableURL = URL(fileURLWithPath: "/bin/sh")
        controlledProcess.arguments = ["-c", "sleep 0.05; exec /bin/sleep 300"]
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
            // the real process's 50ms sleep hasn't elapsed yet.
            .pendingSetsid(terminalPID: terminalPID),
            // The check the real NOTE_EXEC event triggers.
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

        let outcome = await observer.observeColdStart(
            zmxDirectory: temporaryDirectory,
            socketPath: socketPath,
            bootID: "test-boot-id",
            attemptID: ColdRestoreAttemptID.generate()
        )

        #expect(outcome == .handedOff)
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
}
