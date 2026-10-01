import AgentStudioTestHarness
import Darwin
import Dispatch
import Foundation
import Testing

@testable import AgentStudioCore
@testable import AgentStudioInfrastructure
@testable import AgentStudioTestSupport

/// A3 (advisor review 2026-10-01; test technique corrected by the Lead
/// 2026-10-01 — option (c)): `ColdStartObserver`'s process-watch source
/// ownership, proven as direct facts (who got cancelled, who got created,
/// in what order, who stayed inert) through an injected
/// `ColdStartProcessWatchSourceMaker`, never through kernel or queue
/// timing — the SDK (source.h) says nothing about an already-submitted
/// registration handler's fate after `cancel()`, so a test relying on that
/// would be unsound. Split out of `ColdStartObserverTests.swift` to keep
/// both files under the repo's line-length ceiling; shares that file's own
/// `ScriptedSyscalls` double (`internal`, not `private`, for exactly this
/// reason).
@Suite("Cold start observer process-watch source ownership")
struct ColdStartObserverProcessWatchOwnershipTests {
    /// A3 (test technique corrected by the Lead 2026-10-01): a fake
    /// `ColdStartProcessWatchSource` that records its own `resume()`/
    /// `cancel()`/handler installs, and lets a test fire a simulated
    /// exec/exit event directly -- ownership proven as a direct fact
    /// (who got cancelled, who stayed inert) with no kernel or queue
    /// timing involved. `cancel()` clears the event handler, matching the
    /// real guarantee the fix's `hasBegunHandoffWatch`/`isSettled` guards
    /// rely on: a superseded source cannot advance the stage again.
    private final class FakeProcessWatchSource: ColdStartProcessWatchSource, @unchecked Sendable {
        let identifier: Int32
        private let lock = NSLock()
        private var eventHandler: (@Sendable (Bool) -> Void)?
        private var cancelHandler: (@Sendable () -> Void)?
        private var registrationHandler: (@Sendable () -> Void)?
        private(set) var resumeCallCount = 0
        private(set) var cancelCallCount = 0

        init(identifier: Int32) {
            self.identifier = identifier
        }

        func setEventHandler(_ handler: @escaping @Sendable (Bool) -> Void) {
            lock.lock()
            eventHandler = handler
            lock.unlock()
        }

        func setCancelHandler(_ handler: @escaping @Sendable () -> Void) {
            lock.lock()
            cancelHandler = handler
            lock.unlock()
        }

        func setRegistrationHandler(_ handler: @escaping @Sendable () -> Void) {
            lock.lock()
            registrationHandler = handler
            lock.unlock()
        }

        func resume() {
            lock.lock()
            resumeCallCount += 1
            let handler = registrationHandler
            lock.unlock()
            // The fake's own registration completes immediately --
            // deterministic, no real kernel involved.
            handler?()
        }

        func cancel() {
            lock.lock()
            guard cancelCallCount == 0 else {
                lock.unlock()
                return
            }
            cancelCallCount += 1
            let handler = cancelHandler
            eventHandler = nil
            lock.unlock()
            handler?()
        }

        /// Test-controlled: simulate a real exec/exit event. A no-op once
        /// this source has been cancelled, since `cancel()` already
        /// cleared the event handler -- proving a superseded source stays
        /// inert without relying on any production guard to have run.
        func simulateEvent(exitFired: Bool) {
            lock.lock()
            let handler = eventHandler
            lock.unlock()
            handler?(exitFired)
        }
    }

    /// A3: records every process-watch source this maker creates, in
    /// creation order, so a test can inspect the exact ownership sequence.
    private final class RecordingProcessWatchSourceMaker: @unchecked Sendable {
        private let lock = NSLock()
        private var sources: [FakeProcessWatchSource] = []

        var createdSources: [FakeProcessWatchSource] {
            lock.lock()
            defer { lock.unlock() }
            return sources
        }

        var maker: ColdStartProcessWatchSourceMaker {
            { [weak self] identifier, _, _ in
                let source = FakeProcessWatchSource(identifier: identifier)
                self?.lock.lock()
                self?.sources.append(source)
                self?.lock.unlock()
                return source
            }
        }
    }

    /// Opens `path` for `EVFILT_VNODE` watching itself, the same call
    /// `DarwinColdStartObserverSyscalls.openDirectoryForWatching` makes --
    /// a scripted `ScriptedSyscalls` still needs a real, valid descriptor
    /// for `ColdStartObserver`'s real `DispatchSource` registration to work
    /// against, even though the connect/observe step past it is faked.
    /// Duplicated from `ColdStartObserverTests`'s own private helper of the
    /// same name -- small and self-contained enough that sharing it isn't
    /// worth a cross-file seam.
    private func openRealDirectoryDescriptor(at path: String) throws -> Int32 {
        let descriptor = open(path, O_EVTONLY)
        try #require(descriptor >= 0, "expected to open a real directory for EVFILT_VNODE watching")
        return descriptor
    }

    /// A minimal, valid `KERN_PROCARGS2`-shaped buffer with `argc = 0` --
    /// `ProcessArgumentsBufferParser.argumentVector` parses it to an empty
    /// array, which never contains a startup token. Duplicated from
    /// `ColdStartObserverTests`'s own private helper of the same name.
    private func makeEmptyArgumentVectorBuffer(execPath: String = "/bin/example") -> [UInt8] {
        var buffer = withUnsafeBytes(of: Int32(0)) { Array($0) }
        buffer.append(contentsOf: Array(execPath.utf8))
        buffer.append(0)
        return buffer
    }

    /// A3 (important, advisor review 2026-10-01; test technique corrected
    /// by the Lead 2026-10-01 -- option (c), a direct ownership fact
    /// instead of a mechanism the SDK doesn't specify): proves a late
    /// `.pendingSetsid` discovery result reaching `beginSetsidWatch` after
    /// this attempt has already settled installs no new source.
    ///
    /// Settles the observer first, then delivers the late result directly
    /// through `beginSetsidWatch` itself (relaxed to `package` visibility
    /// for exactly this reason) -- no race against discovery's own timing,
    /// since the observer is unconditionally already settled before this
    /// call.
    @Test("beginSetsidWatch installs no source once the attempt has already settled")
    func beginSetsidWatchInstallsNoSourceAfterSettlement() async throws {
        let recordingMaker = RecordingProcessWatchSourceMaker()
        let syscalls = ColdStartObserverTests.ScriptedSyscalls()
        let observer = ColdStartObserver(syscalls: syscalls, processWatchSourceMaker: recordingMaker.maker)

        await observer.cancel()

        // Act: the late .pendingSetsid result, delivered directly.
        await observer.beginSetsidWatch(
            terminalPID: 4242,
            socketPath: "/tmp/cold-start-observer-a3-late-pending-setsid-does-not-exist",
            bootID: "test-boot-id",
            attemptID: ColdRestoreAttemptID.generate()
        )

        // Assert: the maker was never called.
        #expect(recordingMaker.createdSources.isEmpty)
    }

    /// A3: proves `beginHandoffWatch` cancels the setsid watch's own
    /// source before creating the handoff source, and that the cancelled
    /// source stays inert — a late event on it can never advance the
    /// stage again (no second `observeSession` call).
    @Test("the setsid watch's source is cancelled before the handoff source is created, and stays inert")
    func setsidSourceCancelledBeforeHandoffSourceCreatedAndStaysInert() async throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appending(path: "cold-start-observer-a3-superseded-watch-\(UUIDv7.generate().uuidString)")
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        let socketPath = temporaryDirectory.appending(path: "session").path
        FileManager.default.createFile(atPath: socketPath, contents: nil)

        let recordingMaker = RecordingProcessWatchSourceMaker()
        let syscalls = ColdStartObserverTests.ScriptedSyscalls()
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
            .pendingSetsid(terminalPID: 4242),
            .identity(identity),
        ]
        syscalls.processArgumentsResult = .success(makeEmptyArgumentVectorBuffer())
        let observer = ColdStartObserver(syscalls: syscalls, processWatchSourceMaker: recordingMaker.maker)

        let outcome = await observer.observeColdStart(
            zmxDirectory: temporaryDirectory,
            socketPath: socketPath,
            bootID: "test-boot-id",
            attemptID: ColdRestoreAttemptID.generate()
        )

        #expect(outcome == .handedOff)

        // Assert ownership: exactly two sources -- setsid, then handoff --
        // and the setsid source was cancelled (by beginHandoffWatch, before
        // the handoff source's own creation call in the same synchronous
        // body). Settlement (teardownWatches) then cancels the current
        // (handoff) source too -- every owned source cancelled exactly
        // once, the teardown half of ownership.
        let createdSources = recordingMaker.createdSources
        #expect(createdSources.count == 2)
        guard let setsidSource = createdSources.first, let handoffSource = createdSources.last else { return }
        #expect(setsidSource.cancelCallCount == 1)
        #expect(handoffSource.cancelCallCount == 1)

        // Assert inert: a late event on the superseded setsid source
        // cannot advance anything.
        let callCountBeforeSimulatedEvent = syscalls.observeSessionCallCount
        setsidSource.simulateEvent(exitFired: true)
        #expect(syscalls.observeSessionCallCount == callCountBeforeSimulatedEvent)
    }

    /// A3: proves settlement cancels an in-flight setsid watch's own
    /// source exactly once -- the teardown half of ownership, separate
    /// from the setsid-to-handoff transition the sibling test covers.
    @Test("external cancellation cancels the in-flight setsid watch's source exactly once")
    func externalCancellationCancelsInFlightSetsidSourceExactlyOnce() async throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appending(path: "cold-start-observer-a3-teardown-\(UUIDv7.generate().uuidString)")
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        let socketPath = temporaryDirectory.appending(path: "session").path
        FileManager.default.createFile(atPath: socketPath, contents: nil)

        let recordingMaker = RecordingProcessWatchSourceMaker()
        let syscalls = ColdStartObserverTests.ScriptedSyscalls()
        syscalls.directoryOpenResult = .success(try openRealDirectoryDescriptor(at: temporaryDirectory.path))
        syscalls.observeSessionResults = [.pendingSetsid(terminalPID: 4242)]
        syscalls.observeSessionFallback = .pendingSetsid(terminalPID: 4242)
        let observeSessionCallSource = LocalFactSource(
            vocabulary: ColdStartObserverTests.ScriptedSyscalls.observeSessionCallFactVocabulary())
        let observeSessionCallRecorder = try observeSessionCallSource.attach()
        syscalls.observeSessionCallFactSink = observeSessionCallSource.sink
        let observer = ColdStartObserver(syscalls: syscalls, processWatchSourceMaker: recordingMaker.maker)

        // Act
        async let outcome = observer.observeColdStart(
            zmxDirectory: temporaryDirectory,
            socketPath: socketPath,
            bootID: "test-boot-id",
            attemptID: ColdRestoreAttemptID.generate()
        )

        // Wait for the setsid watch's own source to exist: call 1 is
        // discovery's own mandatory check (-> .pendingSetsid), call 2 is
        // the setsid watch's own mandatory check -- an event, never a
        // poll.
        try await observeSessionCallRecorder.expectNext(
            in: ColdStartObserverTests.ScriptedSyscalls.observeSessionScope, 1)
        try await observeSessionCallRecorder.expectNext(
            in: ColdStartObserverTests.ScriptedSyscalls.observeSessionScope, 2)

        await observer.cancel()
        _ = await outcome

        // Assert: exactly one source, cancelled exactly once.
        let createdSources = recordingMaker.createdSources
        #expect(createdSources.count == 1)
        #expect(createdSources.first?.cancelCallCount == 1)
    }
}
