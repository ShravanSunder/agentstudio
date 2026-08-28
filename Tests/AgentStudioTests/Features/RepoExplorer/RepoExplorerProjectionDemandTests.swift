import AgentStudioCore
import AgentStudioInfrastructure
import AgentStudioTestSupport
import AppKit
import Darwin
import Foundation
import Observation
import Testing

@testable import AgentStudioRepoExplorer

private final class RepoExplorerProjectionExecutionRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storedExecutionCount = 0
    private var storedFullExecutionCount = 0
    private var storedDeltaExecutionCount = 0

    var executionCount: Int {
        lock.withLock { storedExecutionCount }
    }

    var fullExecutionCount: Int {
        lock.withLock { storedFullExecutionCount }
    }

    var deltaExecutionCount: Int {
        lock.withLock { storedDeltaExecutionCount }
    }

    func recordExecution(_ work: RepoExplorerProjectionWork) {
        lock.withLock {
            storedExecutionCount += 1
            switch work {
            case .full:
                storedFullExecutionCount += 1
            case .delta:
                storedDeltaExecutionCount += 1
            }
        }
    }
}

private actor RepoExplorerRecencyDelayGate {
    private var waits: [(Duration, Bool, CheckedContinuation<Void, Never>)] = []

    var waitCount: Int { waits.count }

    func wait(duration: Duration, ranOnMainThread: Bool) async {
        await withCheckedContinuation { continuation in
            waits.append((duration, ranOnMainThread, continuation))
        }
    }

    func releaseNext() -> (Duration, Bool)? {
        guard !waits.isEmpty else { return nil }
        let (duration, ranOnMainThread, continuation) = waits.removeFirst()
        continuation.resume()
        return (duration, ranOnMainThread)
    }
}

@MainActor
private final class RepoExplorerRecencyDateBox {
    var value: Date

    init(_ value: Date) {
        self.value = value
    }
}

@MainActor
private final class RepoExplorerRealMaterializationHostFixture {
    private final class MaterializerBox {
        var value: RepoExplorerTableMaterializer?
    }

    let host: RepoExplorerMaterializationHost
    let window: NSWindow
    private let materializerBox: MaterializerBox

    var materializer: RepoExplorerTableMaterializer? { materializerBox.value }

    init(adapter: RepoExplorerProjectionAdapter) {
        let hostLifetimeID = RepoExplorerMaterializationHostLifetimeID(rawValue: UUIDv7.generate())
        let materializerBox = MaterializerBox()
        self.materializerBox = materializerBox
        host = RepoExplorerMaterializationHost(
            lifetimeID: hostLifetimeID,
            initialDemandEpoch: adapter.materializationDemandEpoch,
            initialPresentation: .noRepositories,
            makeContentChild: {
                let materializer = RepoExplorerTableMaterializer(
                    materializationHostLifetimeID: hostLifetimeID,
                    octiconLoader: makeRepoExplorerTestOcticonLoader(),
                    onVisibleWorktreeSnapshotChange: { _ in }
                )
                materializerBox.value = materializer
                return materializer
            },
            onFeedback: adapter.receiveMaterializationFeedback
        )
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 480),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.layoutIfNeeded()
    }

    func stop(adapter: RepoExplorerProjectionAdapter) {
        host.detach()
        adapter.stop()
        window.close()
    }
}

@MainActor
private func makeProjectionPreferences(atoms: CoreAtoms) -> RepoExplorerSidebarPrefsAtom {
    RepoExplorerSidebarPrefsAtom(sidebarState: atoms.workspaceSidebarState)
}

@MainActor
private func expectVisibleMaterialization(
    fixture: RepoExplorerRealMaterializationHostFixture,
    adapter: RepoExplorerProjectionAdapter
) throws {
    let materializer = try #require(fixture.materializer)
    #expect(materializer.numberOfRows == adapter.publishedResult?.rowIndex.entries.count)
    let scrollView = try #require(materializer.view as? NSScrollView)
    let tableView = try #require(scrollView.documentView as? NSTableView)
    #expect(tableView.view(atColumn: 0, row: 0, makeIfNecessary: true) != nil)
}

@MainActor
private func expectScopedTabRename(
    store: WorkspaceStore,
    tab: Tab,
    capture: RepoExplorerProjectionInputCapture,
    adapter: RepoExplorerProjectionAdapter
) async {
    let fullCaptureCount = capture.fullCaptureCount
    let scopedCaptureCount = capture.scopedCaptureCount
    let publishedRevision = adapter.publishedRevision
    store.tabLayoutAtom.renameTab(tab.id, name: "Renamed")
    for _ in 0..<300
    where adapter.publishedRevision == publishedRevision
        || adapter.publishedResult?.tabGroupFactsByTabId[tab.id]?.displayTitle != "Renamed"
    {
        await Task.yield()
    }
    #expect(capture.fullCaptureCount == fullCaptureCount)
    #expect(capture.scopedCaptureCount == scopedCaptureCount + 1)
    #expect(adapter.publishedRevision == publishedRevision + 1)
    #expect(adapter.publishedResult?.projectionDuration == .zero)
}

@Suite("RepoExplorer projection demand")
struct RepoExplorerProjectionDemandTests {
    @MainActor
    @Test("demand waits for synchronous rowless R0 host registration before first admission")
    func demandWaitsForRowlessR0BeforeFirstAdmission() async {
        await withAsyncTestCoreAtoms { atoms in
            let store = WorkspaceStore(
                catalogAtom: atoms.workspaceRepositoryTopology,
                graphAtom: atoms.workspacePane,
                interactionAtom: atoms.workspaceTabLayout
            )
            let capture = RepoExplorerProjectionInputCapture(
                store: store,
                preferences: RepoExplorerSidebarPrefsAtom(),
                repoCache: atoms.repoCache,
                sidebarState: atoms.workspaceSidebarState,
                sidebarCache: atoms.sidebarCache,
                coreAtoms: atoms,
                bridgeAttendanceSnapshot: { _ in nil },
                latestPaneMessageSnapshot: { _ in nil }
            )
            let recorder = RepoExplorerProjectionExecutionRecorder()
            let adapter = RepoExplorerProjectionAdapter(
                inputCapture: capture,
                project: { work throws(CancellationError) in
                    recorder.recordExecution(work)
                    do {
                        return try RepoExplorerProjectionWorker.project(work)
                    } catch is CancellationError {
                        throw CancellationError()
                    } catch {
                        preconditionFailure("Unexpected projection failure: \(error)")
                    }
                }
            )
            defer { adapter.stop() }

            adapter.updateDemand(isVisible: true, query: "")
            for _ in 0..<20 { await Task.yield() }

            #expect(adapter.cachedProjectionRequest == nil)
            #expect(recorder.executionCount == 0)

            let host = registerProjectionTestMaterializationHost(adapter: adapter)
            defer { host.detach() }
            for _ in 0..<400 where adapter.publishedResult == nil {
                await Task.yield()
            }

            #expect(recorder.executionCount == 1)
            #expect(host.acceptedBaseline?.revision == 0)
            #expect(host.acceptedBaseline?.visibleGeneration == 0)
            #expect(adapter.acknowledgedMaterializationBaseline == host.acceptedBaseline)
        }
    }

    @MainActor
    @Test("By Repository pane activity performs zero capture execution and publication")
    func byRepositoryRejectsPaneActivityBeforeCapture() async throws {
        try await withAsyncTestCoreAtoms { atoms in
            let store = WorkspaceStore(
                catalogAtom: atoms.workspaceRepositoryTopology,
                graphAtom: atoms.workspacePane,
                interactionAtom: atoms.workspaceTabLayout
            )
            let repo = store.addRepo(at: URL(filePath: "/tmp/repo-explorer-adapter-admission"))
            let worktree = try #require(repo.worktrees.first)
            let pane = store.createPane(
                launchDirectory: worktree.path,
                title: "before",
                facets: PaneContextFacets(cwd: worktree.path)
            )
            store.appendTab(Tab(paneId: pane.id))
            atoms.repoCache.setRepoEnrichment(
                .resolvedLocal(
                    repoId: repo.id,
                    identity: RemoteIdentityNormalizer.localIdentity(repoName: repo.name),
                    updatedAt: Date()
                )
            )
            let preferences = makeProjectionPreferences(atoms: atoms)
            preferences.setGroupingMode(.repo)
            let capture = RepoExplorerProjectionInputCapture(
                store: store,
                preferences: preferences,
                repoCache: atoms.repoCache,
                sidebarState: atoms.workspaceSidebarState,
                sidebarCache: atoms.sidebarCache,
                coreAtoms: atoms,
                bridgeAttendanceSnapshot: { _ in nil },
                latestPaneMessageSnapshot: { paneID in
                    atoms.paneActivityStatus.status(for: paneID)?.lastOutputLine
                }
            )
            let recorder = RepoExplorerProjectionExecutionRecorder()
            let adapter = RepoExplorerProjectionAdapter(
                inputCapture: capture,
                project: { work throws(CancellationError) in
                    recorder.recordExecution(work)
                    do {
                        return try RepoExplorerProjectionWorker.project(work)
                    } catch is CancellationError {
                        throw CancellationError()
                    } catch {
                        preconditionFailure("Unexpected projection failure: \(error)")
                    }
                }
            )
            defer { adapter.stop() }
            let host = registerProjectionTestMaterializationHost(adapter: adapter)
            defer { host.detach() }

            adapter.updateDemand(isVisible: true, query: "")
            for _ in 0..<200 where adapter.publishedResult == nil {
                await Task.yield()
            }
            let baselineExecutionCount = recorder.executionCount
            let baselineRevision = adapter.publishedRevision
            #expect(baselineExecutionCount == 1)
            #expect(adapter.observationRegistration.paneIDs.isEmpty)

            store.paneAtom.updatePaneTitle(pane.id, title: "after")
            atoms.paneActivityStatus.recordSettledActivity(
                paneId: pane.id,
                lastOutputLine: "activity changed"
            )
            for _ in 0..<200 { await Task.yield() }

            #expect(recorder.executionCount == baselineExecutionCount)
            #expect(adapter.publishedRevision == baselineRevision)
        }
    }

    @MainActor
    @Test("By Pane title change captures one pane delta without a full source rebuild")
    func byPaneTitleChangeUsesOneKeyedDelta() async throws {
        try await withAsyncTestCoreAtoms { atoms in
            let store = WorkspaceStore(
                catalogAtom: atoms.workspaceRepositoryTopology,
                graphAtom: atoms.workspacePane,
                interactionAtom: atoms.workspaceTabLayout
            )
            let repo = store.addRepo(at: URL(filePath: "/tmp/repo-explorer-pane-keyed-delta"))
            let worktree = try #require(repo.worktrees.first)
            let pane = store.createPane(
                launchDirectory: worktree.path,
                title: "before",
                facets: PaneContextFacets(cwd: worktree.path)
            )
            store.appendTab(Tab(paneId: pane.id))
            atoms.repoCache.setRepoEnrichment(
                .resolvedLocal(
                    repoId: repo.id,
                    identity: RemoteIdentityNormalizer.localIdentity(repoName: repo.name),
                    updatedAt: Date()
                )
            )
            let preferences = RepoExplorerSidebarPrefsAtom()
            preferences.setGroupingMode(.pane)
            let capture = RepoExplorerProjectionInputCapture(
                store: store,
                preferences: preferences,
                repoCache: atoms.repoCache,
                sidebarState: atoms.workspaceSidebarState,
                sidebarCache: atoms.sidebarCache,
                coreAtoms: atoms,
                bridgeAttendanceSnapshot: { _ in nil },
                latestPaneMessageSnapshot: { paneID in
                    atoms.paneActivityStatus.status(for: paneID)?.lastOutputLine
                }
            )
            let recorder = RepoExplorerProjectionExecutionRecorder()
            let adapter = RepoExplorerProjectionAdapter(
                inputCapture: capture,
                project: { work throws(CancellationError) in
                    recorder.recordExecution(work)
                    do {
                        return try RepoExplorerProjectionWorker.project(work)
                    } catch is CancellationError {
                        throw CancellationError()
                    } catch {
                        preconditionFailure("Unexpected projection failure: \(error)")
                    }
                }
            )
            defer { adapter.stop() }
            let host = registerProjectionTestMaterializationHost(adapter: adapter)
            defer { host.detach() }

            adapter.updateDemand(isVisible: true, query: "")
            for _ in 0..<200 where adapter.publishedRevision < 1 { await Task.yield() }
            #expect(capture.fullCaptureCount == 1)
            #expect(recorder.fullExecutionCount == 1)
            #expect(recorder.deltaExecutionCount == 0)
            store.paneAtom.updatePaneTitle(pane.id, title: "after")
            for _ in 0..<400
            where adapter.publishedResult?.paneRowFactsByPaneId[pane.id]?.terminalTitle != "after" {
                await Task.yield()
            }

            #expect(capture.fullCaptureCount == 1)
            #expect(capture.scopedCaptureCount == 1)
            #expect(recorder.fullExecutionCount == 1)
            #expect(recorder.deltaExecutionCount == 1)
            #expect(adapter.cachedProjectionRequest?.paneRowFactsByPaneId[pane.id]?.terminalTitle == "after")
            #expect(
                adapter.materializedProjection?.latestAcceptedValue?
                    .paneRowFactsByPaneId[pane.id]?.terminalTitle == "after"
            )
            #expect(adapter.publishedResult?.paneRowFactsByPaneId[pane.id]?.terminalTitle == "after")
            #expect(adapter.publishedResult?.projectionDuration == .zero)
        }
    }

    @MainActor
    @Test("sort and grouping changes reuse adapter topology and add only demanded registrations")
    func presentationChangesReuseTopologyCapture() async throws {
        try await withAsyncTestCoreAtoms { atoms in
            let store = WorkspaceStore(
                catalogAtom: atoms.workspaceRepositoryTopology,
                graphAtom: atoms.workspacePane,
                interactionAtom: atoms.workspaceTabLayout
            )
            let repo = store.addRepo(at: URL(filePath: "/tmp/repo-explorer-presentation-reuse"))
            let worktree = try #require(repo.worktrees.first)
            atoms.repoCache.setRepoEnrichment(
                .resolvedLocal(
                    repoId: repo.id,
                    identity: RemoteIdentityNormalizer.localIdentity(repoName: repo.name),
                    updatedAt: Date()
                )
            )
            let pane = store.createPane(
                launchDirectory: worktree.path,
                facets: PaneContextFacets(cwd: worktree.path)
            )
            let tab = Tab(paneId: pane.id)
            store.appendTab(tab)
            let preferences = RepoExplorerSidebarPrefsAtom()
            preferences.setGroupingMode(.repo)
            let capture = RepoExplorerProjectionInputCapture(
                store: store,
                preferences: preferences,
                repoCache: atoms.repoCache,
                sidebarState: atoms.workspaceSidebarState,
                sidebarCache: atoms.sidebarCache,
                coreAtoms: atoms,
                bridgeAttendanceSnapshot: { _ in nil },
                latestPaneMessageSnapshot: { _ in nil }
            )
            let adapter = RepoExplorerProjectionAdapter(inputCapture: capture)
            let hostFixture = RepoExplorerRealMaterializationHostFixture(adapter: adapter)
            #expect(adapter.registerMaterializationHost(hostFixture.host))
            defer { hostFixture.stop(adapter: adapter) }

            adapter.updateDemand(isVisible: true, query: "")
            for _ in 0..<200 where adapter.publishedRevision < 1 { await Task.yield() }
            #expect(capture.fullCaptureCount == 1)
            #expect(adapter.observationRegistration.paneIDs.isEmpty)
            #expect(adapter.observationRegistration.tabIDs.isEmpty)

            adapter.updateDemand(isVisible: true, query: "needle")
            for _ in 0..<200 where adapter.cachedProjectionRequest?.isFiltering != true { await Task.yield() }
            #expect(adapter.cachedProjectionRequest?.snapshot.query == "needle")
            #expect(adapter.cachedProjectionRequest?.isFiltering == true)
            adapter.updateDemand(isVisible: true, query: "")
            for _ in 0..<200 where adapter.cachedProjectionRequest?.isFiltering != false { await Task.yield() }
            #expect(adapter.cachedProjectionRequest?.snapshot.query.isEmpty == true)
            #expect(adapter.cachedProjectionRequest?.isFiltering == false)

            let presentationCountBeforeSort = capture.presentationCaptureCount
            preferences.setSortOrder(.descending)
            for _ in 0..<200 where capture.presentationCaptureCount == presentationCountBeforeSort {
                await Task.yield()
            }
            #expect(capture.fullCaptureCount == 1)

            preferences.setGroupingMode(.pane)
            for _ in 0..<300 where adapter.observationRegistration.paneIDs.isEmpty { await Task.yield() }
            #expect(adapter.observationRegistration.paneIDs == [pane.id])
            #expect(adapter.observationRegistration.tabIDs.isEmpty)
            let paneFactCaptureCountAfterGrouping = capture.paneFactCaptureCount

            let presentationCountBeforePaneSort = capture.presentationCaptureCount
            preferences.setSortOrder(.ascending)
            for _ in 0..<200 where capture.presentationCaptureCount == presentationCountBeforePaneSort {
                await Task.yield()
            }
            #expect(capture.paneFactCaptureCount == paneFactCaptureCountAfterGrouping)

            preferences.setGroupingMode(.tab)
            for _ in 0..<300
            where adapter.observationRegistration.tabIDs.isEmpty
                || adapter.publishedResult?.snapshot.groupingMode != .tab
            {
                await Task.yield()
            }
            #expect(capture.fullCaptureCount == 1)
            #expect(adapter.observationRegistration.paneIDs == [pane.id])
            #expect(adapter.observationRegistration.tabIDs == [tab.id])
            #expect(adapter.publishedResult?.snapshot.groupingMode == .tab)
            try expectVisibleMaterialization(fixture: hostFixture, adapter: adapter)

            await expectScopedTabRename(store: store, tab: tab, capture: capture, adapter: adapter)

            let captureCountBeforeHiding = capture.fullCaptureCount + capture.scopedCaptureCount
            adapter.updateDemand(isVisible: false, query: "")
            #expect(adapter.observationTokens.isEmpty)
            #expect(adapter.observationRegistration == .hidden)
            #expect(adapter.recencyDeadlineTask == nil)
            store.paneAtom.updatePaneTitle(pane.id, title: "hidden change")
            for _ in 0..<100 { await Task.yield() }
            #expect(capture.fullCaptureCount + capture.scopedCaptureCount == captureCountBeforeHiding)
        }
    }

    @MainActor
    @Test("pane membership change promotes to one full capture")
    func membershipChangePromotesToFullCapture() async {
        await withAsyncTestCoreAtoms { atoms in
            let store = WorkspaceStore(
                catalogAtom: atoms.workspaceRepositoryTopology,
                graphAtom: atoms.workspacePane,
                interactionAtom: atoms.workspaceTabLayout
            )
            let initialPane = store.createPane(title: "initial")
            store.appendTab(Tab(paneId: initialPane.id))
            let preferences = RepoExplorerSidebarPrefsAtom()
            preferences.setGroupingMode(.pane)
            let capture = RepoExplorerProjectionInputCapture(
                store: store,
                preferences: preferences,
                repoCache: atoms.repoCache,
                sidebarState: atoms.workspaceSidebarState,
                sidebarCache: atoms.sidebarCache,
                coreAtoms: atoms,
                bridgeAttendanceSnapshot: { _ in nil },
                latestPaneMessageSnapshot: { _ in nil }
            )
            let adapter = RepoExplorerProjectionAdapter(inputCapture: capture)
            defer { adapter.stop() }
            let host = registerProjectionTestMaterializationHost(adapter: adapter)
            defer { host.detach() }

            adapter.updateDemand(isVisible: true, query: "")
            for _ in 0..<200 where adapter.publishedResult == nil { await Task.yield() }
            #expect(capture.fullCaptureCount == 1)

            _ = store.createPane(title: "new membership")
            for _ in 0..<300 where capture.fullCaptureCount < 2 { await Task.yield() }

            #expect(capture.fullCaptureCount == 2)
            #expect(capture.scopedCaptureCount == 0)
        }
    }

    @Test("compatible pending delta intents union B and C scope")
    func compatiblePendingDeltaIntentsUnionScope() throws {
        let repositoryID = UUIDv7.generate()
        let worktreeID = UUIDv7.generate()
        let pendingRequest = emptyRequest(generation: 2)
        let latestRequest = emptyRequest(generation: 3)
        let target = RepoExplorerProjectionStructuralTarget(request: latestRequest)
        let pending = RepoExplorerProjectionIntent.delta(
            RepoExplorerProjectionDeltaIntent(
                targetRequest: pendingRequest,
                changes: [.repo(repositoryID)],
                structuralTarget: target
            )
        )
        let latest = RepoExplorerProjectionIntent.delta(
            RepoExplorerProjectionDeltaIntent(
                targetRequest: latestRequest,
                changes: [.worktreeFact(worktreeID)],
                structuralTarget: target
            )
        )

        let combined = RepoExplorerProjectionIntent.combinePending(pending, latest)
        guard case .delta(let delta) = combined else {
            Issue.record("Expected compatible deltas to remain pure delta intent")
            return
        }
        #expect(delta.targetRequest.generation == 3)
        #expect(delta.changes == [.repo(repositoryID), .worktreeFact(worktreeID)])
    }

    @Test("incompatible structural targets retain scope for off-main full promotion")
    func incompatibleStructuralTargetsRetainScopeForOffMainPromotion() {
        let pendingRepositoryID = UUIDv7.generate()
        let latestWorktreeID = UUIDv7.generate()
        let pendingRequest = emptyRequest(generation: 2)
        let pending = RepoExplorerProjectionIntent.delta(
            RepoExplorerProjectionDeltaIntent(
                targetRequest: pendingRequest,
                changes: [.repo(pendingRepositoryID)],
                structuralTarget: RepoExplorerProjectionStructuralTarget(request: pendingRequest)
            )
        )
        let latestRequest = emptyRequest(generation: 3).replacing(
            snapshot: RepoExplorerSnapshot(
                repos: [],
                repoEnrichmentByRepoId: [:],
                groupingMode: .repo,
                query: "changed"
            )
        )
        let latest = RepoExplorerProjectionIntent.delta(
            RepoExplorerProjectionDeltaIntent(
                targetRequest: latestRequest,
                changes: [.worktreeFact(latestWorktreeID)],
                structuralTarget: RepoExplorerProjectionStructuralTarget(request: latestRequest)
            )
        )

        guard case .delta(let combined) = RepoExplorerProjectionIntent.combinePending(pending, latest) else {
            Issue.record("Expected the off-main worker to own structural promotion")
            return
        }
        #expect(combined.targetRequest == latestRequest)
        #expect(combined.structuralTarget == RepoExplorerProjectionStructuralTarget(request: latestRequest))
        #expect(combined.changes == [.repo(pendingRepositoryID), .worktreeFact(latestWorktreeID)])
    }

    @Test("hidden demand registers no hot facts and keeps no recency deadline")
    func hiddenDemandRegistersNothing() {
        let registration = RepoExplorerObservationRegistration.make(
            isVisible: false,
            groupingMode: .pane,
            repositoryIDs: [UUIDv7.generate()],
            worktreeIDs: [UUIDv7.generate()],
            paneIDs: [UUIDv7.generate()],
            tabIDs: [UUIDv7.generate()]
        )

        #expect(registration == .hidden)
        #expect(!registration.requiresRecencyDeadline)
    }

    @Test("By Repository excludes pane presentation, focus, recency, and tab display")
    func byRepositoryRegistersOnlyRepositoryInputs() {
        let repositoryID = UUIDv7.generate()
        let worktreeID = UUIDv7.generate()
        let paneID = UUIDv7.generate()
        let tabID = UUIDv7.generate()
        let registration = RepoExplorerObservationRegistration.make(
            isVisible: true,
            groupingMode: .repo,
            repositoryIDs: [repositoryID],
            worktreeIDs: [worktreeID],
            paneIDs: [paneID],
            tabIDs: [tabID]
        )

        #expect(registration.repositoryIDs == [repositoryID])
        #expect(registration.worktreeIDs == [worktreeID])
        #expect(registration.paneIDs.isEmpty)
        #expect(registration.tabIDs.isEmpty)
        #expect(!registration.observesPanePresentation)
        #expect(!registration.observesAttention)
        #expect(!registration.observesTabPresentation)
        #expect(!registration.requiresRecencyDeadline)
    }

    @MainActor
    @Test("By Repository activity deadline waits off-main and rejects a stale observation generation")
    func repositoryActivityDeadlineUsesGenerationCheckedOffMainWait() async throws {
        let initialDate = Date(timeIntervalSince1970: 100_000)
        let transitionDate = initialDate.addingTimeInterval(60)
        let dateBox = RepoExplorerRecencyDateBox(initialDate)
        let delayGate = RepoExplorerRecencyDelayGate()
        let adapter = RepoExplorerProjectionAdapter(
            recencyNow: { dateBox.value },
            recencyDelay: AsyncDelay { duration in
                await delayGate.wait(
                    duration: duration,
                    ranOnMainThread: pthread_main_np() == 1
                )
            }
        )
        defer { adapter.stop() }
        adapter.isDemanded = true
        adapter.observationRegistration = RepoExplorerObservationRegistration.make(
            isVisible: true,
            groupingMode: .repo,
            repositoryIDs: [UUIDv7.generate()],
            worktreeIDs: [],
            paneIDs: [],
            tabIDs: []
        )
        #expect(!adapter.observationRegistration.requiresRecencyDeadline)
        adapter.observationGeneration = 1

        adapter.scheduleRecencyDeadline(
            for: repositoryActivityDeadlineResult(transitionAt: transitionDate)
        )
        for _ in 0..<300 where await delayGate.waitCount == 0 { await Task.yield() }
        adapter.observationGeneration = 2
        dateBox.value = transitionDate
        let staleWait = try #require(await delayGate.releaseNext())
        for _ in 0..<100 { await Task.yield() }
        #expect(staleWait.0 == .seconds(60))
        #expect(!staleWait.1)
        #expect(adapter.recencyReferenceDate != transitionDate)
        #expect(adapter.pendingInvalidation.isEmpty)

        dateBox.value = initialDate
        adapter.scheduleRecencyDeadline(
            for: repositoryActivityDeadlineResult(transitionAt: transitionDate)
        )
        for _ in 0..<300 where await delayGate.waitCount == 0 { await Task.yield() }
        dateBox.value = transitionDate
        let currentWait = try #require(await delayGate.releaseNext())
        for _ in 0..<300 where adapter.recencyReferenceDate != transitionDate { await Task.yield() }
        #expect(currentWait.0 == .seconds(60))
        #expect(!currentWait.1)
        #expect(adapter.recencyReferenceDate == transitionDate)
        #expect(adapter.pendingInvalidation.includesActivity)
    }

    @Test("By Pane observes demanded panes but not tab display")
    func byPaneRegistersPaneInputs() {
        let paneID = UUIDv7.generate()
        let tabID = UUIDv7.generate()
        let registration = RepoExplorerObservationRegistration.make(
            isVisible: true,
            groupingMode: .pane,
            repositoryIDs: [],
            worktreeIDs: [],
            paneIDs: [paneID],
            tabIDs: [tabID]
        )

        #expect(registration.paneIDs == [paneID])
        #expect(registration.tabIDs.isEmpty)
        #expect(registration.observesPanePresentation)
        #expect(registration.observesAttention)
        #expect(!registration.observesTabPresentation)
        #expect(registration.requiresRecencyDeadline)
    }

    @Test("By Tab observes demanded panes and tabs")
    func byTabRegistersPaneAndTabInputs() {
        let paneID = UUIDv7.generate()
        let tabID = UUIDv7.generate()
        let registration = RepoExplorerObservationRegistration.make(
            isVisible: true,
            groupingMode: .tab,
            repositoryIDs: [],
            worktreeIDs: [],
            paneIDs: [paneID],
            tabIDs: [tabID]
        )

        #expect(registration.paneIDs == [paneID])
        #expect(registration.tabIDs == [tabID])
        #expect(registration.observesPanePresentation)
        #expect(registration.observesAttention)
        #expect(registration.observesTabPresentation)
        #expect(registration.requiresRecencyDeadline)
    }

    @Test("recency deadline is the next visible text or tier transition")
    func recencyDeadlineUsesEarliestVisibleTransition() throws {
        let referenceDate = Date(timeIntervalSince1970: 100_000)

        #expect(
            RepoExplorerPaneRecencyText.nextPresentationChangeDate(
                referenceDate: referenceDate,
                now: referenceDate
            ) == referenceDate.addingTimeInterval(60)
        )
        #expect(
            RepoExplorerPaneRecencyText.nextPresentationChangeDate(
                referenceDate: referenceDate,
                now: referenceDate.addingTimeInterval(61)
            ) == referenceDate.addingTimeInterval(120)
        )
        #expect(
            RepoExplorerPaneRecencyText.nextPresentationChangeDate(
                referenceDate: referenceDate,
                now: referenceDate.addingTimeInterval((9 * 60) + 59)
            ) == referenceDate.addingTimeInterval(10 * 60)
        )
        #expect(
            RepoExplorerPaneRecencyText.nextPresentationChangeDate(
                referenceDate: referenceDate,
                now: referenceDate.addingTimeInterval((60 * 60) + 1)
            ) == referenceDate.addingTimeInterval(2 * 60 * 60)
        )
        #expect(
            RepoExplorerPaneRecencyText.nextPresentationChangeDate(
                referenceDate: referenceDate,
                now: referenceDate.addingTimeInterval((24 * 60 * 60) + 1)
            ) == referenceDate.addingTimeInterval(2 * 24 * 60 * 60)
        )
    }

    private func emptyRequest(generation: Int) -> RepoExplorerProjectionRequest {
        RepoExplorerProjectionRequest(
            generation: generation,
            snapshot: RepoExplorerSnapshot(
                repos: [],
                repoEnrichmentByRepoId: [:],
                query: ""
            ),
            collapsedGroupIds: [],
            isFiltering: false,
            trigger: .dataRefresh
        )
    }

    private func repositoryActivityDeadlineResult(transitionAt: Date) -> RepoExplorerProjectionResult {
        let empty = RepoExplorerProjectionResult.empty
        return RepoExplorerProjectionResult(
            generation: empty.generation,
            snapshot: empty.snapshot,
            collapsedGroupIds: empty.collapsedGroupIds,
            isFiltering: empty.isFiltering,
            trigger: empty.trigger,
            projection: empty.projection,
            rowIndex: empty.rowIndex,
            materializationSnapshot: empty.materializationSnapshot,
            workerDuration: empty.workerDuration,
            projectionDuration: empty.projectionDuration,
            rowIndexDuration: empty.rowIndexDuration,
            branchStatusByWorktreeId: empty.branchStatusByWorktreeId,
            branchNameByWorktreeId: empty.branchNameByWorktreeId,
            bridgeCommandResolutionByWorktreeId: empty.bridgeCommandResolutionByWorktreeId,
            paneRowFactsByPaneId: [:],
            tabGroupFactsByTabId: empty.tabGroupFactsByTabId,
            repositoryActivityDispositionByRepoId: empty.repositoryActivityDispositionByRepoId,
            nextRepositoryActivityTransitionAt: transitionAt,
            semanticBaselineSequence: empty.semanticBaselineSequence
        )
    }
}
