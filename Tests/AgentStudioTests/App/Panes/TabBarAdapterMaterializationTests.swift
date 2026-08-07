import Foundation
import Observation
import Synchronization
import Testing

@testable import AgentStudio
@testable import AgentStudioCore
@testable import AgentStudioInboxNotification
@testable import AgentStudioInfrastructure
@testable import AgentStudioTestSupport

@MainActor
@Suite(.serialized)
final class TabBarAdapterMaterializationTests {

    private var store: WorkspaceStore!
    private var repoCache: RepoCacheAtom!
    private var inboxAtom: InboxNotificationAtom!
    private var adapter: TabBarAdapter!

    init() {
        installTestCoreAtomsIfNeeded()
        store = WorkspaceStore()
        repoCache = RepoCacheAtom()
        inboxAtom = InboxNotificationAtom()
        adapter = TabBarAdapter(
            store: store,
            repoCache: repoCache,
            inboxAtom: inboxAtom
        )
    }

    deinit {
        adapter = nil
        inboxAtom = nil
        store = nil
        repoCache = nil
    }

    @Test("first materialization exposes no authoritative items or active selection")
    func firstMaterializationHasNoAuthoritativeOutput() async throws {
        let projectionGate = TabBarAdapterProjectionGate()
        defer { projectionGate.release() }
        let projectionController = TabBarAdapterProjectionController(
            gatesByGeneration: [1: projectionGate]
        )
        let pane = store.createPane(title: "Held")
        let tab = Tab(paneId: pane.id, name: "Held")
        store.appendTab(tab)
        adapter.stop()

        adapter = TabBarAdapter(
            store: store,
            repoCache: repoCache,
            inboxAtom: inboxAtom,
            project: projectionController.project
        )
        let didStart = await projectionGate.waitUntilStarted()

        #expect(didStart, "Initial projection did not start")
        #expect(adapter.tabs.isEmpty)
        #expect(adapter.activeTabId == nil)
    }

    @Test("one materialized projection publishes coherent items and active identity")
    func materializedProjectionPublishesItemsAndActiveIdentityCoherently() async throws {
        let projectionGate = TabBarAdapterProjectionGate()
        defer { projectionGate.release() }
        let projectionController = TabBarAdapterProjectionController(
            gatesByGeneration: [1: projectionGate]
        )
        let completionRecorder = TabBarAdapterProjectionCompletionRecorder()
        let pane = store.createPane(title: "Coherent")
        let tab = Tab(paneId: pane.id, name: "Coherent")
        store.appendTab(tab)
        adapter.stop()
        adapter = TabBarAdapter(
            store: store,
            repoCache: repoCache,
            inboxAtom: inboxAtom,
            project: projectionController.project,
            onProjectionCompletion: completionRecorder.record
        )
        let didStart = await projectionGate.waitUntilStarted()
        #expect(didStart, "Initial projection did not start")

        projectionGate.release()
        let didPublish = await completionRecorder.wait(for: .published(.init(value: 1)))

        #expect(didPublish, "Initial coherent projection did not publish")
        #expect(adapter.tabs.map(\.id) == [tab.id])
        #expect(adapter.activeTabId == tab.id)
    }

    @Test("equal and unrelated source changes do not republish tab output")
    func equalAndUnrelatedSourceChangesDoNotRepublishOutput() async {
        let projectionController = TabBarAdapterProjectionController()
        let completionRecorder = TabBarAdapterProjectionCompletionRecorder()
        let pane = store.createPane(title: "Stable")
        store.appendTab(Tab(paneId: pane.id, name: "Stable"))
        adapter.stop()
        adapter = TabBarAdapter(
            store: store,
            repoCache: repoCache,
            inboxAtom: inboxAtom,
            project: projectionController.project,
            onProjectionCompletion: completionRecorder.record
        )
        #expect(await completionRecorder.wait(for: .published(.init(value: 1))))
        let outputObservationCount = TabBarAdapterTestCounter()
        withObservationTracking {
            _ = adapter.materializedProjection.value
        } onChange: {
            outputObservationCount.increment()
        }

        inboxAtom.append(
            InboxNotification(
                id: UUIDv7.generate(),
                timestamp: Date(timeIntervalSince1970: 100),
                kind: .unseenActivity,
                title: "Activity does not contribute tab attention",
                body: nil,
                source: .pane(.init(paneId: pane.id)),
                claimKey: .init(
                    paneId: pane.id,
                    lane: .activity,
                    semantic: .unseenActivity,
                    sessionId: nil
                ),
                isRead: false,
                isDismissedFromPaneInbox: false
            )
        )
        #expect(await completionRecorder.wait(for: .equal(.init(value: 2))))

        let projectionCountAfterEqualOutput = projectionController.projectionCount
        let managementLayerChanged = TabBarAdapterTestSignal()
        withObservationTracking {
            _ = adapter.isManagementLayerActive
        } onChange: {
            managementLayerChanged.signal()
        }
        atom(\.managementLayer).activate()
        #expect(await managementLayerChanged.wait(), "Management-layer observation did not update")

        #expect(adapter.materializedProjection.revision == 0)
        #expect(!outputObservationCount.didIncrement)
        #expect(projectionController.projectionCount == projectionCountAfterEqualOutput)
    }

    @Test("leading-edge invalidation revokes held work before successor admission")
    func leadingEdgeInvalidationRevokesHeldWorkBeforeSuccessorAdmission() async {
        let firstGate = TabBarAdapterProjectionGate()
        let successorGate = TabBarAdapterProjectionGate()
        defer {
            firstGate.release()
            successorGate.release()
        }
        let projectionController = TabBarAdapterProjectionController(
            gatesByGeneration: [1: firstGate, 2: successorGate]
        )
        let completionRecorder = TabBarAdapterProjectionCompletionRecorder()
        let pane = store.createPane(title: "Before")
        let tab = Tab(paneId: pane.id, name: "Before")
        store.appendTab(tab)
        adapter.stop()
        adapter = TabBarAdapter(
            store: store,
            repoCache: repoCache,
            inboxAtom: inboxAtom,
            project: projectionController.project,
            onProjectionCompletion: completionRecorder.record
        )
        #expect(await firstGate.waitUntilStarted(), "First projection did not start")

        store.renameTab(tab.id, name: "After")
        firstGate.release()
        #expect(await completionRecorder.wait(for: .superseded(.init(value: 1))))
        #expect(adapter.materializedProjection.value == nil)
        #expect(await successorGate.waitUntilStarted(), "Successor projection did not start")

        successorGate.release()
        #expect(await completionRecorder.wait(for: .published(.init(value: 2))))
        #expect(adapter.tabs.first?.displayTitle == "After")
    }

    @Test("overlapping projections publish only the latest admitted request")
    func overlappingProjectionsPublishOnlyLatestRequest() async {
        let secondGate = TabBarAdapterProjectionGate()
        let thirdGate = TabBarAdapterProjectionGate()
        defer {
            secondGate.release()
            thirdGate.release()
        }
        let projectionController = TabBarAdapterProjectionController(
            gatesByGeneration: [2: secondGate, 3: thirdGate]
        )
        let completionRecorder = TabBarAdapterProjectionCompletionRecorder()
        let pane = store.createPane(title: "Initial")
        let tab = Tab(paneId: pane.id, name: "Initial")
        store.appendTab(tab)
        adapter.stop()
        adapter = TabBarAdapter(
            store: store,
            repoCache: repoCache,
            inboxAtom: inboxAtom,
            project: projectionController.project,
            onProjectionCompletion: completionRecorder.record
        )
        #expect(await completionRecorder.wait(for: .published(.init(value: 1))))

        store.renameTab(tab.id, name: "Superseded")
        #expect(await secondGate.waitUntilStarted(), "Second projection did not start")
        store.renameTab(tab.id, name: "Latest")
        secondGate.release()
        #expect(await completionRecorder.wait(for: .superseded(.init(value: 2))))
        #expect(await thirdGate.waitUntilStarted(), "Third projection did not start")

        thirdGate.release()
        #expect(await completionRecorder.wait(for: .published(.init(value: 3))))
        #expect(adapter.tabs.first?.displayTitle == "Latest")
        #expect(projectionController.projectedGenerations == [1, 2, 3])
    }

    @Test("stop cancels held projection and permits adapter release")
    func stopBeforeProjectionReleaseSuppressesOutputAndReleasesAdapter() async {
        let projectionGate = TabBarAdapterProjectionGate()
        defer { projectionGate.release() }
        let projectionController = TabBarAdapterProjectionController(
            gatesByGeneration: [1: projectionGate]
        )
        let completionRecorder = TabBarAdapterProjectionCompletionRecorder()
        let pane = store.createPane(title: "Stopping")
        store.appendTab(Tab(paneId: pane.id, name: "Stopping"))
        adapter.stop()
        adapter = TabBarAdapter(
            store: store,
            repoCache: repoCache,
            inboxAtom: inboxAtom,
            project: projectionController.project,
            onProjectionCompletion: completionRecorder.record
        )
        #expect(await projectionGate.waitUntilStarted(), "Held projection did not start")
        let materializedProjection = adapter.materializedProjection
        weak let weakAdapter = adapter

        adapter.stop()
        adapter = nil
        projectionGate.release()
        #expect(await completionRecorder.wait(for: .cancelled(.init(value: 1))))

        #expect(weakAdapter == nil)
        #expect(materializedProjection.value == nil)
        #expect(materializedProjection.freshness == .stopped)
    }
}

final class TabBarAdapterTestSignal: Sendable {
    private struct State {
        var didSignal = false
        var waiters: [UUID: CheckedContinuation<Bool, Never>] = [:]
    }

    private let state = Mutex(State())

    func signal() {
        let waiters = state.withLock { state in
            guard !state.didSignal else { return [CheckedContinuation<Bool, Never>]() }
            state.didSignal = true
            let waiters = Array(state.waiters.values)
            state.waiters.removeAll()
            return waiters
        }
        for waiter in waiters {
            waiter.resume(returning: true)
        }
    }

    func wait() async -> Bool {
        let waiterID = UUID()
        return await withCheckedContinuation { continuation in
            let shouldResumeImmediately = state.withLock { state in
                guard !state.didSignal else { return true }
                state.waiters[waiterID] = continuation
                return false
            }
            if shouldResumeImmediately {
                continuation.resume(returning: true)
                return
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + .seconds(5)) { [weak self] in
                let timedOutContinuation = self?.state.withLock { state in
                    state.waiters.removeValue(forKey: waiterID)
                }
                timedOutContinuation?.resume(returning: false)
            }
        }
    }
}

private final class TabBarAdapterProjectionGate: Sendable {
    private let started = TabBarAdapterTestSignal()
    private let releaseSemaphore = DispatchSemaphore(value: 0)
    private let didRelease = Mutex(false)

    func hold() throws(CancellationError) {
        started.signal()
        guard releaseSemaphore.wait(timeout: .now() + .seconds(5)) == .success else {
            throw CancellationError()
        }
    }

    func waitUntilStarted() async -> Bool {
        await started.wait()
    }

    func release() {
        let shouldRelease = didRelease.withLock { didRelease in
            guard !didRelease else { return false }
            didRelease = true
            return true
        }
        if shouldRelease {
            releaseSemaphore.signal()
        }
    }
}

private final class TabBarAdapterProjectionController: Sendable {
    private struct State {
        var projectedGenerations: [UInt64] = []
    }

    private let gatesByGeneration: [UInt64: TabBarAdapterProjectionGate]
    private let state = Mutex(State())

    init(gatesByGeneration: [UInt64: TabBarAdapterProjectionGate] = [:]) {
        self.gatesByGeneration = gatesByGeneration
    }

    var projectionCount: Int {
        state.withLock { $0.projectedGenerations.count }
    }

    var projectedGenerations: [UInt64] {
        state.withLock { $0.projectedGenerations }
    }

    func project(
        _ request: TabBarProjectionRequest
    ) throws(CancellationError) -> TabBarProjection {
        let generation = request.generation.value
        state.withLock { $0.projectedGenerations.append(generation) }
        try gatesByGeneration[generation]?.hold()
        return try TabBarProjector.project(request)
    }
}

private final class TabBarAdapterTestCounter: Sendable {
    private let countState = Mutex(0)

    var didIncrement: Bool {
        countState.withLock { $0 > 0 }
    }

    func increment() {
        countState.withLock { $0 += 1 }
    }
}

@MainActor
private final class TabBarAdapterProjectionCompletionRecorder {
    private var completions: [TabBarMaterializedProjection.ProjectionCompletion] = []
    private var waiters:
        [(
            completion: TabBarMaterializedProjection.ProjectionCompletion,
            signal: TabBarAdapterTestSignal
        )] = []

    func record(_ completion: TabBarMaterializedProjection.ProjectionCompletion) {
        completions.append(completion)
        for waiter in waiters where waiter.completion == completion {
            waiter.signal.signal()
        }
    }

    func wait(
        for completion: TabBarMaterializedProjection.ProjectionCompletion
    ) async -> Bool {
        if completions.contains(completion) {
            return true
        }
        if let existingWaiter = waiters.first(where: { $0.completion == completion }) {
            return await existingWaiter.signal.wait()
        }
        let signal = TabBarAdapterTestSignal()
        waiters.append((completion: completion, signal: signal))
        return await signal.wait()
    }
}
