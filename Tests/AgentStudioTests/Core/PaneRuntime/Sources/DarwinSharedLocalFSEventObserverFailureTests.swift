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
                    flags: FSEventStreamEventFlags(
                        kFSEventStreamEventFlagMustScanSubDirs
                            | kFSEventStreamEventFlagUserDropped
                    )
                )
            ])
        )

        // Assert
        #expect(deliveryRecorder.worktreeIds == [firstWorktreeId, secondWorktreeId])
    }

    @Test("path-scoped control events reach only intersecting logical roots")
    func pathScopedControlEventsReachOnlyIntersectingLogicalRoots() throws {
        for flags in [
            FSEventStreamEventFlags(kFSEventStreamEventFlagMustScanSubDirs),
            FSEventStreamEventFlags(kFSEventStreamEventFlagMount),
            FSEventStreamEventFlags(kFSEventStreamEventFlagUnmount),
        ] {
            let fixture = try LogicalFSEventRoutingFixture()
            defer { fixture.removeTemporaryFiles() }

            #expect(
                fixture.streamFactory.sendToCurrentStream([
                    DarwinLocalFSEventRawEvent(
                        path: fixture.firstRoot.path,
                        eventId: FSEventStreamEventId(80 + flags),
                        flags: flags
                    )
                ])
            )

            #expect(fixture.deliveryRecorder.worktreeIds == [fixture.firstWorktreeId])
        }
    }

    @Test("successor stream request drops paths owned only by retired registrations")
    func successorStreamRequestDropsRetiredRegistrationPaths() throws {
        let fixtureRoot = FileManager.default.temporaryDirectory.appending(
            path: "darwin-fsevents-shared-live-paths-\(UUIDv7.generate().uuidString)",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: fixtureRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: fixtureRoot) }
        let firstRoot = fixtureRoot.appending(path: "first", directoryHint: .isDirectory)
        let secondRoot = fixtureRoot.appending(path: "second", directoryHint: .isDirectory)
        let thirdRoot = fixtureRoot.appending(path: "third", directoryHint: .isDirectory)
        let streamFactory = RecordingLocalFSEventStreamFactory()
        let registry = DarwinSharedLocalFSEventObserverRegistry(
            streamFactory: streamFactory.makeStream,
            recordPhysicalRawCallback: { _ in }
        )
        defer { registry.shutdown() }
        let firstLease = try #require(
            registry.bind(request: Self.request(root: firstRoot, generation: 1))
        )
        let secondLease = try #require(
            registry.bind(request: Self.request(root: secondRoot, generation: 2))
        )

        firstLease.retire()
        let thirdLease = try #require(
            registry.bind(request: Self.request(root: thirdRoot, generation: 3))
        )

        let finalRequest = try #require(streamFactory.watchedPathRequests.last)
        #expect(!finalRequest.contains(firstRoot.path))
        #expect(finalRequest.contains(secondRoot.path))
        #expect(finalRequest.contains(thirdRoot.path))
        _ = secondLease
        _ = thirdLease
    }

    @Test("new generation replaces the prior logical handler for one worktree")
    func newGenerationReplacesPriorLogicalHandlerForOneWorktree() throws {
        let fixtureRoot = FileManager.default.temporaryDirectory.appending(
            path: "darwin-fsevents-shared-logical-generation-\(UUIDv7.generate().uuidString)",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: fixtureRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: fixtureRoot) }
        let streamFactory = RecordingLocalFSEventStreamFactory()
        let deliveryRecorder = OrderedFSEventDeliveryRecorder()
        let registry = DarwinSharedLocalFSEventObserverRegistry(
            streamFactory: streamFactory.makeStream,
            recordPhysicalRawCallback: { _ in }
        )
        defer { registry.shutdown() }
        let worktreeId = UUIDv7.generate()
        let firstLease = try #require(
            registry.bind(
                request: Self.request(root: fixtureRoot, worktreeId: worktreeId, generation: 1) {
                    deliveryRecorder.record(generation: 1, events: $0)
                }
            )
        )
        let secondLease = try #require(
            registry.bind(
                request: Self.request(root: fixtureRoot, worktreeId: worktreeId, generation: 2) {
                    deliveryRecorder.record(generation: 2, events: $0)
                }
            )
        )

        #expect(
            streamFactory.sendToCurrentStream([
                DarwinLocalFSEventRawEvent(path: fixtureRoot.path, eventId: 90, flags: 0)
            ])
        )

        #expect(deliveryRecorder.generations == [2])
        #expect(registry.snapshot().logicalRegistrationCount == 1)
        _ = firstLease
        _ = secondLease
    }

    @Test("older generation cannot replace the current logical handler")
    func olderGenerationCannotReplaceCurrentLogicalHandler() throws {
        let fixtureRoot = FileManager.default.temporaryDirectory.appending(
            path: "darwin-fsevents-shared-stale-generation-\(UUIDv7.generate().uuidString)",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: fixtureRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: fixtureRoot) }
        let streamFactory = RecordingLocalFSEventStreamFactory()
        let deliveryRecorder = OrderedFSEventDeliveryRecorder()
        let registry = DarwinSharedLocalFSEventObserverRegistry(
            streamFactory: streamFactory.makeStream,
            recordPhysicalRawCallback: { _ in }
        )
        defer { registry.shutdown() }
        let worktreeId = UUIDv7.generate()
        let currentLease = try #require(
            registry.bind(
                request: Self.request(root: fixtureRoot, worktreeId: worktreeId, generation: 2) {
                    deliveryRecorder.record(generation: 2, events: $0)
                }
            )
        )

        let staleLease = registry.bind(
            request: Self.request(root: fixtureRoot, worktreeId: worktreeId, generation: 1) {
                deliveryRecorder.record(generation: 1, events: $0)
            }
        )
        #expect(
            streamFactory.sendToCurrentStream([
                DarwinLocalFSEventRawEvent(path: fixtureRoot.path, eventId: 91, flags: 0)
            ])
        )

        #expect(staleLease == nil)
        #expect(deliveryRecorder.generations == [2])
        #expect(registry.snapshot().logicalRegistrationCount == 1)
        _ = currentLease
    }

    @Test("replacement replay preserves callback order and records physical input once")
    func replacementReplayPreservesOrderAndPhysicalTelemetry() throws {
        let fixtureRoot = FileManager.default.temporaryDirectory.appending(
            path: "darwin-fsevents-shared-replay-order-\(UUIDv7.generate().uuidString)",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: fixtureRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: fixtureRoot) }
        let firstRoot = fixtureRoot.appending(path: "first", directoryHint: .isDirectory)
        let secondRoot = fixtureRoot.appending(path: "second", directoryHint: .isDirectory)
        let streamFactory = ReplayOrderingLocalFSEventStreamFactory(bufferedEventPath: firstRoot.path)
        let deliveryRecorder = OrderedFSEventDeliveryRecorder()
        let telemetryRecorder = PhysicalCallbackEventCountRecorder()
        let registry = DarwinSharedLocalFSEventObserverRegistry(
            streamFactory: streamFactory.makeStream,
            recordPhysicalRawCallback: telemetryRecorder.record
        )
        defer { registry.shutdown() }
        let firstLease = try #require(
            registry.bind(
                request: Self.request(root: firstRoot, generation: 1) { events in
                    if events.map(\.eventId) == [100] {
                        streamFactory.sendNewestEvent(
                            path: firstRoot.path,
                            eventId: 101
                        )
                    }
                    deliveryRecorder.record(generation: 1, events: events)
                }
            )
        )

        let secondLease = try #require(
            registry.bind(request: Self.request(root: secondRoot, generation: 2))
        )

        #expect(deliveryRecorder.eventIds == [100, 101])
        #expect(telemetryRecorder.eventCount == 2)
        _ = firstLease
        _ = secondLease
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

    private static func request(
        root: URL,
        worktreeId: UUID = UUIDv7.generate(),
        generation: UInt64,
        eventHandler: @escaping @Sendable ([DarwinLocalFSEventRawEvent]) -> Void = { _ in }
    ) -> DarwinLocalFSEventStreamRequest {
        DarwinLocalFSEventStreamRequest(
            worktreeId: worktreeId,
            lifecycleGeneration: generation,
            watchedPaths: [root.path],
            privateStagingExclusionPaths: [
                root.appending(path: ".git/refs/agentstudio/staged", directoryHint: .isDirectory).path
            ],
            eventHandler: eventHandler
        )
    }
}

private final class LogicalFSEventRoutingFixture: @unchecked Sendable {
    let fixtureRoot: URL
    let firstRoot: URL
    let secondRoot: URL
    let firstWorktreeId = UUIDv7.generate()
    let secondWorktreeId = UUIDv7.generate()
    let streamFactory = CountingLocalFSEventStreamFactory()
    let deliveryRecorder = LogicalFSEventDeliveryRecorder()
    private let registry: DarwinSharedLocalFSEventObserverRegistry
    private var leases: [any DarwinLocalFSEventStreamLifetime] = []

    init() throws {
        fixtureRoot = FileManager.default.temporaryDirectory.appending(
            path: "darwin-fsevents-shared-control-routing-\(UUIDv7.generate().uuidString)",
            directoryHint: .isDirectory
        )
        firstRoot = fixtureRoot.appending(path: "first", directoryHint: .isDirectory)
        secondRoot = fixtureRoot.appending(path: "second", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: firstRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: secondRoot, withIntermediateDirectories: true)
        registry = DarwinSharedLocalFSEventObserverRegistry(
            streamFactory: streamFactory.makeStream,
            recordPhysicalRawCallback: { _ in }
        )
        let firstWorktreeId = self.firstWorktreeId
        let secondWorktreeId = self.secondWorktreeId
        guard
            let firstLease = registry.bind(
                request: DarwinLocalFSEventStreamRequest(
                    worktreeId: firstWorktreeId,
                    lifecycleGeneration: 1,
                    watchedPaths: [firstRoot.path],
                    privateStagingExclusionPaths: [],
                    eventHandler: { [deliveryRecorder] _ in deliveryRecorder.record(firstWorktreeId) }
                )
            ),
            let secondLease = registry.bind(
                request: DarwinLocalFSEventStreamRequest(
                    worktreeId: secondWorktreeId,
                    lifecycleGeneration: 1,
                    watchedPaths: [secondRoot.path],
                    privateStagingExclusionPaths: [],
                    eventHandler: { [deliveryRecorder] _ in deliveryRecorder.record(secondWorktreeId) }
                )
            )
        else {
            throw LogicalFSEventRoutingFixtureError.bindingFailed
        }
        leases = [firstLease, secondLease]
    }

    func removeTemporaryFiles() {
        registry.shutdown()
        leases.removeAll()
        try? FileManager.default.removeItem(at: fixtureRoot)
    }
}

private enum LogicalFSEventRoutingFixtureError: Error {
    case bindingFailed
}

private final class RootChangeDuringFlushLocalFSEventStreamFactory: @unchecked Sendable {
    private let lock = NSLock()
    private let callbackQueue = DispatchQueue(
        label: "com.agentstudio.tests.fsevents.root-change-during-flush"
    )
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
                self.callbackQueue.async {
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

private final class RecordingLocalFSEventStreamFactory: @unchecked Sendable {
    private let lock = NSLock()
    private var eventHandler: (@Sendable ([DarwinLocalFSEventRawEvent]) -> Void)?
    private var recordedWatchedPathRequests: [[String]] = []

    var watchedPathRequests: [[String]] {
        lock.withLock { recordedWatchedPathRequests }
    }

    func makeStream(
        request: DarwinLocalFSEventStreamRequest
    ) -> (any DarwinLocalFSEventStreamLifetime)? {
        lock.withLock {
            eventHandler = request.eventHandler
            recordedWatchedPathRequests.append(request.watchedPaths)
        }
        return RootChangeDuringFlushLocalFSEventStreamLifetime(flush: { true })
    }

    func sendToCurrentStream(_ events: [DarwinLocalFSEventRawEvent]) -> Bool {
        guard let eventHandler = lock.withLock({ eventHandler }) else { return false }
        eventHandler(events)
        return true
    }
}

private final class ReplayOrderingLocalFSEventStreamFactory: @unchecked Sendable {
    private let lock = NSLock()
    private let bufferedEventPath: String
    private var eventHandlers: [@Sendable ([DarwinLocalFSEventRawEvent]) -> Void] = []

    init(bufferedEventPath: String) {
        self.bufferedEventPath = bufferedEventPath
    }

    func makeStream(
        request: DarwinLocalFSEventStreamRequest
    ) -> (any DarwinLocalFSEventStreamLifetime)? {
        let streamIndex = lock.withLock { () -> Int in
            eventHandlers.append(request.eventHandler)
            return eventHandlers.count
        }
        return RootChangeDuringFlushLocalFSEventStreamLifetime(
            flush: { [weak self] in
                guard let self else { return false }
                if streamIndex == 1 {
                    sendNewestEvent(path: bufferedEventPath, eventId: 100)
                }
                return true
            }
        )
    }

    func sendNewestEvent(path: String, eventId: FSEventStreamEventId) {
        let eventHandler = lock.withLock { eventHandlers.last }
        eventHandler?([DarwinLocalFSEventRawEvent(path: path, eventId: eventId, flags: 0)])
    }
}

private final class OrderedFSEventDeliveryRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recordedGenerations: [UInt64] = []
    private var recordedEventIds: [FSEventStreamEventId] = []

    var generations: [UInt64] {
        lock.withLock { recordedGenerations }
    }

    var eventIds: [FSEventStreamEventId] {
        lock.withLock { recordedEventIds }
    }

    func record(generation: UInt64, events: [DarwinLocalFSEventRawEvent]) {
        lock.withLock {
            recordedGenerations.append(generation)
            recordedEventIds.append(contentsOf: events.map(\.eventId))
        }
    }
}

private final class PhysicalCallbackEventCountRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recordedEventCount = 0

    var eventCount: Int {
        lock.withLock { recordedEventCount }
    }

    func record(_ eventCount: Int) {
        lock.withLock {
            recordedEventCount += eventCount
        }
    }
}
