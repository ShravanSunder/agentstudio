import CoreServices
import Foundation
import Testing

@testable import AgentStudioCore
@testable import AgentStudioInfrastructure

@Suite("DarwinSharedLocalFSEventObserverFailureTests")
struct DarwinSharedLocalFSEventObserverFailureTests {
    @Test("nine repositories on one volume do not exceed the native exclusion limit")
    func nineRepositoriesOnOneVolumeDoNotExceedNativeExclusionLimit() throws {
        // Arrange
        let fixtureRoot = FileManager.default.temporaryDirectory.appending(
            path: "darwin-fsevents-shared-exclusions-\(UUIDv7.generate().uuidString)",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: fixtureRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: fixtureRoot) }
        let registry = DarwinSharedLocalFSEventObserverRegistry(
            streamFactory: DarwinLocalFSEventNativeStream.start,
            recordPhysicalRawCallback: { _ in }
        )
        defer { registry.shutdown() }
        var registrationLeases: [any DarwinLocalFSEventStreamLifetime] = []

        // Act
        for index in 0..<9 {
            let repositoryRoot = fixtureRoot.appending(
                path: "repository-\(index)",
                directoryHint: .isDirectory
            )
            let privateStagingRoot = repositoryRoot.appending(
                path: ".git/refs/agentstudio/staged",
                directoryHint: .isDirectory
            )
            try FileManager.default.createDirectory(
                at: privateStagingRoot,
                withIntermediateDirectories: true
            )
            let registrationLease = registry.bind(
                request: DarwinLocalFSEventStreamRequest(
                    worktreeId: UUIDv7.generate(),
                    lifecycleGeneration: UInt64(index + 1),
                    watchedPaths: [repositoryRoot.path],
                    privateStagingExclusionPaths: [privateStagingRoot.path],
                    eventHandler: { _ in }
                )
            )
            registrationLeases.append(try #require(registrationLease))
        }

        // Assert
        #expect(registrationLeases.count == 9)
        #expect(registry.snapshot().logicalRegistrationCount == 9)
        #expect(registry.snapshot().physicalStreamCount == 1)
    }

    @Test("private staged refs are contracted before logical callback fan-out")
    func privateStagedRefsAreContractedBeforeLogicalCallbackFanOut() throws {
        // Arrange
        let fixtureRoot = FileManager.default.temporaryDirectory.appending(
            path: "darwin-fsevents-shared-staged-ref-\(UUIDv7.generate().uuidString)",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: fixtureRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: fixtureRoot) }
        let privateStagingRoot = fixtureRoot.appending(
            path: ".git/refs/agentstudio/staged",
            directoryHint: .isDirectory
        )
        let streamFactory = CountingLocalFSEventStreamFactory()
        let deliveryRecorder = LogicalFSEventDeliveryRecorder()
        let registry = DarwinSharedLocalFSEventObserverRegistry(
            streamFactory: streamFactory.makeStream,
            recordPhysicalRawCallback: { _ in }
        )
        defer { registry.shutdown() }
        let worktreeId = UUIDv7.generate()
        let registrationLease = registry.bind(
            request: DarwinLocalFSEventStreamRequest(
                worktreeId: worktreeId,
                lifecycleGeneration: 1,
                watchedPaths: [fixtureRoot.path],
                privateStagingExclusionPaths: [privateStagingRoot.path],
                eventHandler: { _ in deliveryRecorder.record(worktreeId) }
            )
        )
        _ = try #require(registrationLease)

        // Act / Assert
        #expect(
            streamFactory.sendToCurrentStream([
                DarwinLocalFSEventRawEvent(
                    path: privateStagingRoot.appending(path: "attempt/main").path,
                    eventId: 75,
                    flags: FSEventStreamEventFlags(kFSEventStreamEventFlagItemModified)
                )
            ])
        )
        #expect(deliveryRecorder.worktreeIds.isEmpty)

        #expect(
            streamFactory.sendToCurrentStream([
                DarwinLocalFSEventRawEvent(
                    path: fixtureRoot.appending(path: "Changed.swift").path,
                    eventId: 76,
                    flags: FSEventStreamEventFlags(kFSEventStreamEventFlagItemModified)
                )
            ])
        )
        #expect(deliveryRecorder.worktreeIds == [worktreeId])
    }

    @Test("coverage loss under a private staged-ref path still reaches every registration")
    func coverageLossUnderPrivateStagedRefPathReachesEveryRegistration() throws {
        // Arrange
        let fixtureRoot = FileManager.default.temporaryDirectory.appending(
            path: "darwin-fsevents-shared-staged-loss-\(UUIDv7.generate().uuidString)",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: fixtureRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: fixtureRoot) }
        let firstRoot = fixtureRoot.appending(path: "first", directoryHint: .isDirectory)
        let secondRoot = fixtureRoot.appending(path: "second", directoryHint: .isDirectory)
        let privateStagingRoot = firstRoot.appending(
            path: ".git/refs/agentstudio/staged",
            directoryHint: .isDirectory
        )
        let streamFactory = CountingLocalFSEventStreamFactory()
        let deliveryRecorder = LogicalFSEventDeliveryRecorder()
        let registry = DarwinSharedLocalFSEventObserverRegistry(
            streamFactory: streamFactory.makeStream,
            recordPhysicalRawCallback: { _ in }
        )
        defer { registry.shutdown() }
        let firstWorktreeId = UUIDv7.generate()
        let secondWorktreeId = UUIDv7.generate()
        let firstLease = registry.bind(
            request: DarwinLocalFSEventStreamRequest(
                worktreeId: firstWorktreeId,
                lifecycleGeneration: 1,
                watchedPaths: [firstRoot.path],
                privateStagingExclusionPaths: [privateStagingRoot.path],
                eventHandler: { _ in deliveryRecorder.record(firstWorktreeId) }
            )
        )
        let secondLease = registry.bind(
            request: DarwinLocalFSEventStreamRequest(
                worktreeId: secondWorktreeId,
                lifecycleGeneration: 1,
                watchedPaths: [secondRoot.path],
                privateStagingExclusionPaths: [],
                eventHandler: { _ in deliveryRecorder.record(secondWorktreeId) }
            )
        )
        _ = try #require(firstLease)
        _ = try #require(secondLease)

        // Act
        #expect(
            streamFactory.sendToCurrentStream([
                DarwinLocalFSEventRawEvent(
                    path: privateStagingRoot.appending(path: "attempt/main").path,
                    eventId: 78,
                    flags: FSEventStreamEventFlags(kFSEventStreamEventFlagMustScanSubDirs)
                )
            ])
        )

        // Assert
        #expect(deliveryRecorder.worktreeIds == [firstWorktreeId, secondWorktreeId])
    }

    @Test("root-change retirement completes during a synchronous predecessor flush")
    func rootChangeRetirementCompletesDuringSynchronousPredecessorFlush() throws {
        // Arrange
        let fixtureRoot = FileManager.default.temporaryDirectory.appending(
            path: "darwin-fsevents-shared-root-change-flush-\(UUIDv7.generate().uuidString)",
            directoryHint: .isDirectory
        )
        let firstRoot = fixtureRoot.appending(path: "first", directoryHint: .isDirectory)
        let secondRoot = fixtureRoot.appending(path: "second", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: firstRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: secondRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: fixtureRoot) }
        let streamFactory = RootChangeDuringFlushLocalFSEventStreamFactory(rootChangedPath: firstRoot.path)
        let client = DarwinFSEventStreamClient(localStreamFactory: streamFactory.makeStream)
        defer { client.shutdown() }
        let repositoryId = UUIDv7.generate()
        client.register(worktreeId: UUIDv7.generate(), repoId: repositoryId, rootPath: firstRoot)

        // Act
        client.register(worktreeId: UUIDv7.generate(), repoId: repositoryId, rootPath: secondRoot)

        // Assert
        #expect(streamFactory.rootChangedCallbackCompletedDuringFlush)
    }

    @Test("root change routes only to logical roots contained by the changed root")
    func rootChangeRoutesOnlyToLogicalRootsContainedByChangedRoot() throws {
        // Arrange
        let fixtureRoot = FileManager.default.temporaryDirectory.appending(
            path: "darwin-fsevents-shared-root-change-routing-\(UUIDv7.generate().uuidString)",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: fixtureRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: fixtureRoot) }
        let firstRoot = fixtureRoot.appending(path: "first", directoryHint: .isDirectory)
        let secondRoot = fixtureRoot.appending(path: "second", directoryHint: .isDirectory)
        let streamFactory = CountingLocalFSEventStreamFactory()
        let deliveryRecorder = LogicalFSEventDeliveryRecorder()
        let registry = DarwinSharedLocalFSEventObserverRegistry(
            streamFactory: streamFactory.makeStream,
            recordPhysicalRawCallback: { _ in }
        )
        defer { registry.shutdown() }
        let firstWorktreeId = UUIDv7.generate()
        let secondWorktreeId = UUIDv7.generate()
        let firstLease = registry.bind(
            request: DarwinLocalFSEventStreamRequest(
                worktreeId: firstWorktreeId,
                lifecycleGeneration: 1,
                watchedPaths: [firstRoot.path],
                privateStagingExclusionPaths: [],
                eventHandler: { _ in deliveryRecorder.record(firstWorktreeId) }
            )
        )
        let secondLease = registry.bind(
            request: DarwinLocalFSEventStreamRequest(
                worktreeId: secondWorktreeId,
                lifecycleGeneration: 1,
                watchedPaths: [secondRoot.path],
                privateStagingExclusionPaths: [],
                eventHandler: { _ in deliveryRecorder.record(secondWorktreeId) }
            )
        )
        _ = try #require(firstLease)
        _ = try #require(secondLease)

        // Act
        #expect(
            streamFactory.sendToCurrentStream([
                DarwinLocalFSEventRawEvent(
                    path: firstRoot.path,
                    eventId: 73,
                    flags: FSEventStreamEventFlags(kFSEventStreamEventFlagRootChanged)
                )
            ])
        )

        // Assert
        #expect(deliveryRecorder.worktreeIds == [firstWorktreeId])
    }

    @Test("compound coverage loss retires only the path-affected registration")
    func compoundCoverageLossRetiresOnlyPathAffectedRegistration() async throws {
        // Arrange
        let fixtureRoot = FileManager.default.temporaryDirectory.appending(
            path: "darwin-fsevents-shared-compound-root-change-\(UUIDv7.generate().uuidString)",
            directoryHint: .isDirectory
        )
        let firstRoot = fixtureRoot.appending(path: "first", directoryHint: .isDirectory)
        let secondRoot = fixtureRoot.appending(path: "second", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: firstRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: secondRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: fixtureRoot) }
        let streamFactory = CountingLocalFSEventStreamFactory()
        let client = DarwinFSEventStreamClient(localStreamFactory: streamFactory.makeStream)
        defer { client.shutdown() }
        let repositoryId = UUIDv7.generate()
        let firstWorktreeId = UUIDv7.generate()
        let secondWorktreeId = UUIDv7.generate()
        client.register(worktreeId: firstWorktreeId, repoId: repositoryId, rootPath: firstRoot)
        client.register(worktreeId: secondWorktreeId, repoId: repositoryId, rootPath: secondRoot)
        let fenceConsumer = Task {
            for await ingressItem in client.events() {
                guard case .activityProcessingFence(let fenceID) = ingressItem else { continue }
                client.acknowledgeActivityProcessingFence(fenceID)
                return
            }
        }

        // Act
        #expect(
            streamFactory.sendToCurrentStream([
                DarwinLocalFSEventRawEvent(
                    path: DarwinFSEventPathCanonicalizer.canonicalURL(firstRoot).path,
                    eventId: 77,
                    flags: FSEventStreamEventFlags(
                        kFSEventStreamEventFlagRootChanged
                            | kFSEventStreamEventFlagMustScanSubDirs
                    )
                )
            ])
        )
        let barrier = try #require(await client.captureActivityBarrier())
        await fenceConsumer.value

        // Assert
        #expect(barrier.bindings.map(\.worktreeId) == [secondWorktreeId])
    }
}

private final class RootChangeDuringFlushLocalFSEventStreamFactory: @unchecked Sendable {
    private let lock = NSLock()
    private let rootChangedPath: String
    private var streamCount = 0
    private var callbackCompletedDuringFlush = false

    init(rootChangedPath: String) {
        self.rootChangedPath = rootChangedPath
    }

    var rootChangedCallbackCompletedDuringFlush: Bool {
        lock.withLock { callbackCompletedDuringFlush }
    }

    func makeStream(
        request: DarwinLocalFSEventStreamRequest
    ) -> (any DarwinLocalFSEventStreamLifetime)? {
        let shouldEmitRootChangeDuringFlush = lock.withLock { () -> Bool in
            streamCount += 1
            return streamCount == 1
        }
        return RootChangeDuringFlushLocalFSEventStreamLifetime(
            flush: { [weak self] in
                guard let self, shouldEmitRootChangeDuringFlush else { return true }
                let callbackCompleted = DispatchSemaphore(value: 0)
                DispatchQueue.global(qos: .utility).async {
                    request.eventHandler([
                        DarwinLocalFSEventRawEvent(
                            path: self.rootChangedPath,
                            eventId: 74,
                            flags: FSEventStreamEventFlags(kFSEventStreamEventFlagRootChanged)
                        )
                    ])
                    callbackCompleted.signal()
                }
                let didComplete = callbackCompleted.wait(timeout: .now() + 1) == .success
                self.lock.withLock {
                    self.callbackCompletedDuringFlush = didComplete
                }
                return didComplete
            }
        )
    }
}

private final class RootChangeDuringFlushLocalFSEventStreamLifetime:
    DarwinLocalFSEventStreamLifetime, @unchecked Sendable
{
    private let flushCallback: @Sendable () -> Bool

    init(flush: @escaping @Sendable () -> Bool) {
        flushCallback = flush
    }

    func flush() -> Bool {
        flushCallback()
    }

    func retire() {}

    func scheduleRetirement() {}
}

private final class LogicalFSEventDeliveryRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recordedWorktreeIds: Set<UUID> = []

    var worktreeIds: Set<UUID> {
        lock.withLock { recordedWorktreeIds }
    }

    func record(_ worktreeId: UUID) {
        _ = lock.withLock {
            recordedWorktreeIds.insert(worktreeId)
        }
    }
}
