import AgentStudioGit
import CoreServices
import Foundation
import Testing

@testable import AgentStudioCore
@testable import AgentStudioInfrastructure

@Suite("DarwinSharedExactItemObserver")
struct DarwinSharedExactItemObserverTests {
    @Test("shared exact observer routes hits selectively after unrelated misses")
    func sharedExactObserverRoutesOnlyExactSubscribers() throws {
        let parentKey = makeSharedParentKey()
        let configurationPath = "\(parentKey.parentPath)/configuration"
        let configurationWorktreeId = UUIDv7.generate()
        let ignoreWorktreeId = UUIDv7.generate()
        let fixture = makeSharedExactItemFixture()

        #expect(
            bind(
                fixture.registry,
                worktreeId: configurationWorktreeId,
                parentKey: parentKey,
                itemName: "configuration"
            )
        )
        #expect(
            bind(
                fixture.registry,
                worktreeId: ignoreWorktreeId,
                parentKey: parentKey,
                itemName: "ignore"
            )
        )
        let generation = try #require(fixture.registry.snapshot().generationByParent[parentKey])

        receive(
            fixture.registry,
            parentKey: parentKey,
            streamGeneration: generation,
            path: "\(parentKey.parentPath)/unrelated",
            eventId: 40
        )

        #expect(fixture.effectRecorder.actions.isEmpty)

        receive(
            fixture.registry,
            parentKey: parentKey,
            streamGeneration: generation,
            path: configurationPath,
            eventId: 41
        )

        #expect(
            fixture.effectRecorder.actions == [
                .mutation(worktreeId: configurationWorktreeId, eventIds: [41]),
                .fullGitRefresh(worktreeId: configurationWorktreeId),
            ]
        )
        fixture.registry.shutdown()
    }

    @Test("shared exact observer uncertainty reaches only the affected parent's dependents")
    func sharedExactObserverUncertaintyIsParentScoped() throws {
        let affectedParentKey = makeSharedParentKey("affected-parent")
        let isolatedParentKey = makeSharedParentKey("isolated-parent")
        let firstAffectedWorktreeId = UUIDv7.generate()
        let secondAffectedWorktreeId = UUIDv7.generate()
        let isolatedWorktreeId = UUIDv7.generate()
        let fixture = makeSharedExactItemFixture()

        #expect(
            bind(
                fixture.registry,
                worktreeId: firstAffectedWorktreeId,
                parentKey: affectedParentKey,
                itemName: "configuration"
            )
        )
        #expect(
            bind(
                fixture.registry,
                worktreeId: secondAffectedWorktreeId,
                parentKey: affectedParentKey,
                itemName: "ignore"
            )
        )
        #expect(
            bind(
                fixture.registry,
                worktreeId: isolatedWorktreeId,
                parentKey: isolatedParentKey,
                itemName: "configuration"
            )
        )
        let generation = try #require(
            fixture.registry.snapshot().generationByParent[affectedParentKey]
        )

        receive(
            fixture.registry,
            parentKey: affectedParentKey,
            streamGeneration: generation,
            path: "\(affectedParentKey.parentPath)/unrelated",
            eventId: 42,
            flags: FSEventStreamEventFlags(kFSEventStreamEventFlagRootChanged)
        )

        let affectedWorktreeIds = Set([firstAffectedWorktreeId, secondAffectedWorktreeId])
        #expect(Set(fixture.effectRecorder.uncertainWorktreeIds) == affectedWorktreeIds)
        #expect(Set(fixture.effectRecorder.fullGitRefreshWorktreeIds) == affectedWorktreeIds)
        #expect(!fixture.effectRecorder.uncertainWorktreeIds.contains(isolatedWorktreeId))
        #expect(!fixture.effectRecorder.fullGitRefreshWorktreeIds.contains(isolatedWorktreeId))
        #expect(fixture.registry.hasBinding(worktreeId: firstAffectedWorktreeId))
        #expect(fixture.registry.hasBinding(worktreeId: secondAffectedWorktreeId))
        #expect(fixture.registry.hasBinding(worktreeId: isolatedWorktreeId))
        #expect(fixture.registry.snapshot().generationByParent[affectedParentKey] == nil)
        #expect(fixture.registry.snapshot().generationByParent[isolatedParentKey] != nil)
        #expect(fixture.streamFactory.retirementCount == 1)
        let firstIngressIndex = try #require(
            fixture.effectRecorder.actions.firstIndex {
                if case .fullGitRefresh = $0 { return true }
                return false
            }
        )
        #expect(
            fixture.effectRecorder.actions[..<firstIngressIndex].allSatisfy {
                if case .uncertain = $0 { return true }
                return false
            }
        )
        fixture.registry.shutdown()
    }

    @Test("shared exact observer uses one parent stream for 148 dependent plans")
    func sharedExactObserverContractsSharedParentTopology() {
        let parentKey = makeSharedParentKey()
        let fixture = makeSharedExactItemFixture()

        for _ in 0..<148 {
            #expect(
                bind(
                    fixture.registry,
                    worktreeId: UUIDv7.generate(),
                    parentKey: parentKey,
                    itemName: "configuration"
                )
            )
        }

        let snapshot = fixture.registry.snapshot()
        #expect(snapshot.observerCount == 1)
        #expect(snapshot.bindingCount == 148)
        #expect(snapshot.referenceCountByParent[parentKey] == 148)
        #expect(fixture.streamFactory.startCount == 1)
        fixture.registry.shutdown()
        #expect(fixture.streamFactory.retirementCount == 1)
    }

    @Test("shared exact observer installs no subscriber when its parent stream cannot start")
    func sharedExactObserverFailsStreamStartClosed() {
        let parentKey = makeSharedParentKey()
        let effectRecorder = SharedExactItemEffectRecorder()
        let streamFactory = RecordingSharedExactItemStreamFactory(startsSuccessfully: false)
        let registry = makeSharedExactItemRegistry(
            effectRecorder: effectRecorder,
            streamFactory: streamFactory
        )

        #expect(
            !bind(
                registry,
                worktreeId: UUIDv7.generate(),
                parentKey: parentKey,
                itemName: "configuration"
            )
        )
        #expect(registry.snapshot().observerCount == 0)
        #expect(registry.snapshot().bindingCount == 0)
        #expect(effectRecorder.actions.isEmpty)
        registry.shutdown()
    }

    @Test("shared exact observer tears down only after its final subscriber retires")
    func sharedExactObserverReferenceCountsLifecycle() {
        let parentKey = makeSharedParentKey()
        let firstWorktreeId = UUIDv7.generate()
        let secondWorktreeId = UUIDv7.generate()
        let fixture = makeSharedExactItemFixture()

        #expect(
            bind(
                fixture.registry,
                worktreeId: firstWorktreeId,
                parentKey: parentKey,
                itemName: "configuration"
            )
        )
        #expect(
            bind(
                fixture.registry,
                worktreeId: secondWorktreeId,
                parentKey: parentKey,
                itemName: "configuration"
            )
        )

        fixture.registry.unbind(worktreeId: firstWorktreeId)
        #expect(fixture.registry.snapshot().observerCount == 1)
        #expect(fixture.streamFactory.retirementCount == 0)

        fixture.registry.unbind(worktreeId: secondWorktreeId)
        fixture.registry.unbind(worktreeId: secondWorktreeId)
        #expect(fixture.registry.snapshot().observerCount == 0)
        #expect(fixture.streamFactory.retirementCount == 1)
        fixture.registry.shutdown()
        #expect(fixture.streamFactory.retirementCount == 1)
    }

    @Test("shared exact observer rejects callbacks from a retired stream generation")
    func sharedExactObserverRejectsLateGeneration() throws {
        let parentKey = makeSharedParentKey()
        let configurationPath = "\(parentKey.parentPath)/configuration"
        let retiredWorktreeId = UUIDv7.generate()
        let currentWorktreeId = UUIDv7.generate()
        let fixture = makeSharedExactItemFixture()

        #expect(
            bind(
                fixture.registry,
                worktreeId: retiredWorktreeId,
                parentKey: parentKey,
                itemName: "configuration"
            )
        )
        let retiredGeneration = try #require(
            fixture.registry.snapshot().generationByParent[parentKey]
        )

        receive(
            fixture.registry,
            parentKey: parentKey,
            streamGeneration: retiredGeneration,
            path: "\(parentKey.parentPath)/unrelated",
            eventId: 50
        )
        #expect(fixture.effectRecorder.actions.isEmpty)
        receive(
            fixture.registry,
            parentKey: parentKey,
            streamGeneration: retiredGeneration,
            path: "\(parentKey.parentPath)/unrelated",
            eventId: 49
        )
        #expect(
            fixture.effectRecorder.actions == [
                .uncertain(worktreeId: retiredWorktreeId),
                .fullGitRefresh(worktreeId: retiredWorktreeId),
            ]
        )
        fixture.effectRecorder.reset()
        fixture.registry.unbind(worktreeId: retiredWorktreeId)
        #expect(
            bind(
                fixture.registry,
                worktreeId: currentWorktreeId,
                parentKey: parentKey,
                itemName: "configuration"
            )
        )
        let currentGeneration = try #require(
            fixture.registry.snapshot().generationByParent[parentKey]
        )
        #expect(currentGeneration != retiredGeneration)
        fixture.effectRecorder.reset()

        receive(
            fixture.registry,
            parentKey: parentKey,
            streamGeneration: retiredGeneration,
            path: configurationPath,
            eventId: 43
        )
        #expect(fixture.effectRecorder.actions.isEmpty)

        receive(
            fixture.registry,
            parentKey: parentKey,
            streamGeneration: currentGeneration,
            path: configurationPath,
            eventId: 44
        )
        #expect(
            fixture.effectRecorder.actions == [
                .mutation(worktreeId: currentWorktreeId, eventIds: [44]),
                .fullGitRefresh(worktreeId: currentWorktreeId),
            ]
        )
        fixture.registry.shutdown()
    }

    @Test("continuity hierarchy streams request watched-root replacement events")
    func continuityHierarchyStreamsUseWatchRoot() {
        #expect(
            DarwinFSEventStreamConfiguration.continuityFlags
                & FSEventStreamCreateFlags(kFSEventStreamCreateFlagWatchRoot) != 0
        )
    }

    @Test("shared-dependent preparation cannot mint local-only continuity authority")
    func sharedDependentPreparationFailsAuthorityClosed() async throws {
        let fixtureRoot = FileManager.default.temporaryDirectory.appending(
            path: "darwin-fsevent-shared-authority-\(UUIDv7.generate().uuidString)",
            directoryHint: .isDirectory
        )
        let worktreeRoot = fixtureRoot.appending(path: "worktree", directoryHint: .isDirectory)
        let externalParent = fixtureRoot.appending(path: "external", directoryHint: .isDirectory)
        let configurationPath = externalParent.appending(path: "configuration")
        try FileManager.default.createDirectory(at: worktreeRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: externalParent, withIntermediateDirectories: true)
        try Data().write(to: configurationPath)
        defer { try? FileManager.default.removeItem(at: fixtureRoot) }
        let streamFactory = RecordingSharedExactItemStreamFactory()
        let client = DarwinFSEventStreamClient(
            sharedExactItemStreamFactory: streamFactory.makeStream
        )
        defer { client.shutdown() }
        let worktreeId = UUIDv7.generate()
        client.register(worktreeId: worktreeId, repoId: UUIDv7.generate(), rootPath: worktreeRoot)
        let observationPlan = AgentStudioGit.GitStatusObservationPlan(
            identity: AgentStudioGit.GitStatusObservationIdentity(rawValue: "shared-dependent"),
            scopes: [
                AgentStudioGit.GitStatusObservationScope(kind: .subtree, path: worktreeRoot),
                AgentStudioGit.GitStatusObservationScope(kind: .item, path: configurationPath),
            ],
            support: .supported
        )

        let barrier = await client.prepare(
            worktreeId: worktreeId,
            rootPath: worktreeRoot,
            observationPlan: observationPlan
        )

        #expect(barrier == nil)
        #expect(streamFactory.startCount == 1)
        client.unregister(worktreeId: worktreeId)
        #expect(streamFactory.retirementCount == 1)
    }

    @Test("unregister during shared stream start cannot publish a stale binding")
    func unregisterDuringSharedStreamStartRejectsStaleBinding() async throws {
        let fixtureRoot = FileManager.default.temporaryDirectory.appending(
            path: "darwin-fsevent-shared-unregister-race-\(UUIDv7.generate().uuidString)",
            directoryHint: .isDirectory
        )
        let worktreeRoot = fixtureRoot.appending(path: "worktree", directoryHint: .isDirectory)
        let externalParent = fixtureRoot.appending(path: "external", directoryHint: .isDirectory)
        let configurationPath = externalParent.appending(path: "configuration")
        try FileManager.default.createDirectory(at: worktreeRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: externalParent, withIntermediateDirectories: true)
        try Data().write(to: configurationPath)
        defer { try? FileManager.default.removeItem(at: fixtureRoot) }
        let streamFactory = ControllableSharedExactItemStreamFactory()
        let client = DarwinFSEventStreamClient(
            sharedExactItemStreamFactory: streamFactory.makeStream
        )
        defer {
            streamFactory.allowStreamStartToComplete()
            client.shutdown()
        }
        let worktreeId = UUIDv7.generate()
        client.register(worktreeId: worktreeId, repoId: UUIDv7.generate(), rootPath: worktreeRoot)
        let observationPlan = AgentStudioGit.GitStatusObservationPlan(
            identity: AgentStudioGit.GitStatusObservationIdentity(rawValue: "shared-unregister-race"),
            scopes: [
                AgentStudioGit.GitStatusObservationScope(kind: .subtree, path: worktreeRoot),
                AgentStudioGit.GitStatusObservationScope(kind: .item, path: configurationPath),
            ],
            support: .supported
        )
        let prepareTask = Task {
            await client.prepare(
                worktreeId: worktreeId,
                rootPath: worktreeRoot,
                observationPlan: observationPlan
            )
        }

        await streamFactory.waitUntilStreamStartBegins()
        client.unregister(worktreeId: worktreeId)
        streamFactory.allowStreamStartToComplete()
        let barrier = await prepareTask.value

        #expect(barrier == nil)
        #expect(streamFactory.startCount == 1)
        #expect(streamFactory.retirementCount == 1)
    }

    private func makeSharedExactItemRegistry(
        effectRecorder: SharedExactItemEffectRecorder,
        streamFactory: RecordingSharedExactItemStreamFactory
    ) -> DarwinSharedExactItemObserverRegistry {
        DarwinSharedExactItemObserverRegistry(
            streamFactory: streamFactory.makeStream,
            recordRawEvents: effectRecorder.recordRawEvents,
            markUncertain: effectRecorder.markUncertain,
            yieldFullGitRefresh: effectRecorder.yieldFullGitRefresh
        )
    }

    private func makeSharedExactItemFixture() -> (
        registry: DarwinSharedExactItemObserverRegistry,
        effectRecorder: SharedExactItemEffectRecorder,
        streamFactory: RecordingSharedExactItemStreamFactory
    ) {
        let effectRecorder = SharedExactItemEffectRecorder()
        let streamFactory = RecordingSharedExactItemStreamFactory()
        return (
            registry: makeSharedExactItemRegistry(
                effectRecorder: effectRecorder,
                streamFactory: streamFactory
            ),
            effectRecorder: effectRecorder,
            streamFactory: streamFactory
        )
    }

    private func makeSharedParentKey(
        _ name: String = "shared-parent"
    ) -> DarwinSharedExactItemParentKey {
        DarwinSharedExactItemParentKey(
            parentPath: "/private/tmp/\(name)",
            volumeSystemNumber: 1
        )
    }

    private func bind(
        _ registry: DarwinSharedExactItemObserverRegistry,
        worktreeId: UUID,
        parentKey: DarwinSharedExactItemParentKey,
        itemName: String
    ) -> Bool {
        registry.bind(
            worktreeId: worktreeId,
            bindingGeneration: 1,
            exactItemsByParent: [parentKey: ["\(parentKey.parentPath)/\(itemName)"]],
            bindingIsCurrent: { true }
        )
    }

    private func receive(
        _ registry: DarwinSharedExactItemObserverRegistry,
        parentKey: DarwinSharedExactItemParentKey,
        streamGeneration: UInt64,
        path: String,
        eventId: FSEventStreamEventId,
        flags: FSEventStreamEventFlags = 0
    ) {
        registry.receive(
            parentKey: parentKey,
            streamGeneration: streamGeneration,
            rawEvents: [
                DarwinSharedExactItemRawEvent(
                    path: path,
                    eventId: eventId,
                    flags: flags
                )
            ]
        )
    }
}

private enum SharedExactItemRecordedAction: Equatable {
    case mutation(worktreeId: UUID, eventIds: [FSEventStreamEventId])
    case uncertain(worktreeId: UUID)
    case fullGitRefresh(worktreeId: UUID)
}

private final class SharedExactItemEffectRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recordedActions: [SharedExactItemRecordedAction] = []

    var actions: [SharedExactItemRecordedAction] {
        lock.withLock { recordedActions }
    }

    var uncertainWorktreeIds: [UUID] {
        actions.compactMap { action in
            guard case .uncertain(let worktreeId) = action else { return nil }
            return worktreeId
        }
    }

    var fullGitRefreshWorktreeIds: [UUID] {
        actions.compactMap { action in
            guard case .fullGitRefresh(let worktreeId) = action else { return nil }
            return worktreeId
        }
    }

    func recordRawEvents(
        worktreeId: UUID,
        events: [DarwinFSEventClassifiedRawEvent]
    ) {
        let mutationEventIds = events.compactMap { event in
            event.hasRelevantMutation ? event.eventId : nil
        }
        guard !mutationEventIds.isEmpty else { return }
        lock.withLock {
            recordedActions.append(
                .mutation(worktreeId: worktreeId, eventIds: mutationEventIds)
            )
        }
    }

    func markUncertain(worktreeId: UUID) {
        lock.withLock {
            recordedActions.append(.uncertain(worktreeId: worktreeId))
        }
    }

    func yieldFullGitRefresh(worktreeId: UUID) {
        lock.withLock {
            recordedActions.append(.fullGitRefresh(worktreeId: worktreeId))
        }
    }

    func reset() {
        lock.withLock {
            recordedActions.removeAll(keepingCapacity: true)
        }
    }
}

private final class RecordingSharedExactItemStreamFactory: @unchecked Sendable {
    private let lock = NSLock()
    private let startsSuccessfully: Bool
    private var startedStreamCount = 0
    private var retiredStreamCount = 0

    init(startsSuccessfully: Bool = true) {
        self.startsSuccessfully = startsSuccessfully
    }

    var startCount: Int {
        lock.withLock { startedStreamCount }
    }

    var retirementCount: Int {
        lock.withLock { retiredStreamCount }
    }

    func makeStream(
        parentKey _: DarwinSharedExactItemParentKey,
        streamGeneration _: UInt64,
        eventHandler _: @escaping @Sendable ([DarwinSharedExactItemRawEvent]) -> Void
    ) -> (any DarwinSharedExactItemStreamLifetime)? {
        lock.withLock {
            startedStreamCount += 1
        }
        guard startsSuccessfully else { return nil }
        return RecordingSharedExactItemStreamLifetime { [weak self] in
            self?.lock.withLock {
                self?.retiredStreamCount += 1
            }
        }
    }
}

private final class RecordingSharedExactItemStreamLifetime:
    DarwinSharedExactItemStreamLifetime, @unchecked Sendable
{
    private let lock = NSLock()
    private let onRetire: @Sendable () -> Void
    private var hasRetired = false

    init(onRetire: @escaping @Sendable () -> Void) {
        self.onRetire = onRetire
    }

    func retire() {
        let shouldRetire = lock.withLock { () -> Bool in
            guard !hasRetired else { return false }
            hasRetired = true
            return true
        }
        if shouldRetire {
            onRetire()
        }
    }
}

private final class ControllableSharedExactItemStreamFactory: @unchecked Sendable {
    private let condition = NSCondition()
    private let startEvents: AsyncStream<Void>
    private let startEventsContinuation: AsyncStream<Void>.Continuation
    private var canCompleteStreamStart = false
    private var startedStreamCount = 0
    private var retiredStreamCount = 0

    init() {
        (startEvents, startEventsContinuation) = AsyncStream.makeStream(
            of: Void.self,
            bufferingPolicy: .bufferingNewest(1)
        )
    }

    var startCount: Int {
        condition.withLock { startedStreamCount }
    }

    var retirementCount: Int {
        condition.withLock { retiredStreamCount }
    }

    func waitUntilStreamStartBegins() async {
        for await _ in startEvents {
            return
        }
    }

    func allowStreamStartToComplete() {
        condition.withLock {
            canCompleteStreamStart = true
            condition.broadcast()
        }
    }

    func makeStream(
        parentKey _: DarwinSharedExactItemParentKey,
        streamGeneration _: UInt64,
        eventHandler _: @escaping @Sendable ([DarwinSharedExactItemRawEvent]) -> Void
    ) -> (any DarwinSharedExactItemStreamLifetime)? {
        condition.lock()
        startedStreamCount += 1
        startEventsContinuation.yield(())
        while !canCompleteStreamStart {
            condition.wait()
        }
        condition.unlock()
        return RecordingSharedExactItemStreamLifetime { [weak self] in
            self?.condition.withLock {
                self?.retiredStreamCount += 1
            }
        }
    }
}
