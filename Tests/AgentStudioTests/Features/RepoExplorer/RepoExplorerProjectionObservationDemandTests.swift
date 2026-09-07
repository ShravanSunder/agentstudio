import AgentStudioCore
import AgentStudioInfrastructure
import AgentStudioTestSupport
import AppKit
import Darwin
import Foundation
import Observation
import Testing

@testable import AgentStudioRepoExplorer

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
final class RepoExplorerRecencyDateBox {
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
private func expectKeyedTabRenamePromotesToFullWorkerProjection(
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
    #expect(adapter.publishedResult?.projectionDuration != .zero)
}

extension RepoExplorerProjectionDemandTests {
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
            preferences.setGroupingMode(.repo, for: .repos)
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
            preferences.setSortDirection(.descending, for: .repos)
            for _ in 0..<200 where capture.presentationCaptureCount == presentationCountBeforeSort {
                await Task.yield()
            }
            #expect(capture.fullCaptureCount == 1)

            atoms.workspaceSidebarState.setSidebarSurface(.panes)
            preferences.setGroupingMode(.repo, for: .panes)
            for _ in 0..<300 where adapter.observationRegistration.paneIDs.isEmpty { await Task.yield() }
            #expect(adapter.observationRegistration.paneIDs == [pane.id])
            #expect(adapter.observationRegistration.tabIDs.isEmpty)
            let paneFactCaptureCountAfterGrouping = capture.paneFactCaptureCount

            let presentationCountBeforePaneSort = capture.presentationCaptureCount
            preferences.setSortDirection(.ascending, for: .panes)
            for _ in 0..<200 where capture.presentationCaptureCount == presentationCountBeforePaneSort {
                await Task.yield()
            }
            #expect(capture.paneFactCaptureCount == paneFactCaptureCountAfterGrouping)

            preferences.setGroupingMode(.tab, for: .panes)
            for _ in 0..<300
            where adapter.observationRegistration.tabIDs.isEmpty
                || adapter.publishedResult?.snapshot.groupingMode != .tab
            {
                await Task.yield()
            }
            // One initial Repos capture plus one structural capture for the Panes screen switch.
            #expect(capture.fullCaptureCount == 2)
            #expect(adapter.observationRegistration.paneIDs == [pane.id])
            #expect(adapter.observationRegistration.tabIDs == [tab.id])
            #expect(adapter.publishedResult?.snapshot.groupingMode == .tab)
            try expectVisibleMaterialization(fixture: hostFixture, adapter: adapter)

            await expectKeyedTabRenamePromotesToFullWorkerProjection(
                store: store,
                tab: tab,
                capture: capture,
                adapter: adapter
            )

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
            atoms.workspaceSidebarState.setSidebarSurface(.panes)
            let preferences = RepoExplorerSidebarPrefsAtom()
            preferences.setGroupingMode(.repo, for: .panes)
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
            let adapter = RepoExplorerProjectionAdapter(
                inputCapture: capture,
                recencyDelay: AsyncDelay { _ in throw CancellationError() }
            )
            defer { adapter.stop() }
            let host = registerProjectionTestMaterializationHost(adapter: adapter)
            defer { host.detach() }

            adapter.updateDemand(isVisible: true, query: "")
            for _ in 0..<400
            where adapter.publishedResult == nil
                || adapter.materializedProjection?.hasUnsettledProjectionTasks != false
                || adapter.invalidationTask != nil
                || !adapter.pendingInvalidation.isEmpty
            {
                await Task.yield()
            }
            #expect(capture.fullCaptureCount == 1)
            #expect(adapter.materializedProjection?.hasUnsettledProjectionTasks == false)
            #expect(adapter.invalidationTask == nil)
            #expect(adapter.pendingInvalidation.isEmpty)

            let fullCaptureCountBeforeMembershipChange = capture.fullCaptureCount
            let scopedCaptureCountBeforeMembershipChange = capture.scopedCaptureCount

            _ = store.createPane(title: "new membership")
            for _ in 0..<300
            where capture.fullCaptureCount == fullCaptureCountBeforeMembershipChange {
                await Task.yield()
            }

            #expect(capture.fullCaptureCount == fullCaptureCountBeforeMembershipChange + 1)
            #expect(capture.scopedCaptureCount == scopedCaptureCountBeforeMembershipChange)
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
            surface: .panes,
            groupingMode: .repo,
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
            surface: .repos,
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

    @Test("Repos observes keyed pane activity only when activity organization demands it")
    func reposActivityOrganizationRegistersPaneActivityInputs() {
        let paneID = UUIDv7.generate()
        let registration = RepoExplorerObservationRegistration.make(
            isVisible: true,
            surface: .repos,
            groupingMode: .repo,
            subgroupMode: .activity,
            sortField: .name,
            repositoryIDs: [],
            worktreeIDs: [],
            paneIDs: [paneID],
            tabIDs: []
        )

        #expect(registration.paneIDs == [paneID])
        #expect(!registration.observesPanePresentation)
        #expect(!registration.observesAttention)
        #expect(!registration.observesTabPresentation)
    }

    @MainActor
    @Test("By Repository activity deadline waits off-main and rejects a stale observation generation")
    func repositoryActivityDeadlineUsesGenerationCheckedOffMainWait() async throws {
        let initialDate = Date(timeIntervalSince1970: 100_000)
        let transitionDate = initialDate.addingTimeInterval(60)
        let repositoryID = UUIDv7.generate()
        let dateBox = RepoExplorerRecencyDateBox(initialDate)
        let delayGate = RepoExplorerRecencyDelayGate()
        let adapter = RepoExplorerProjectionAdapter(
            recencyNow: { dateBox.value },
            deadlineNow: { initialDate },
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
            surface: .repos,
            groupingMode: .repo,
            repositoryIDs: [repositoryID],
            worktreeIDs: [],
            paneIDs: [],
            tabIDs: []
        )
        #expect(!adapter.observationRegistration.requiresRecencyDeadline)
        adapter.observationGeneration = 1

        adapter.scheduleRecencyDeadline(
            for: repositoryActivityDeadlineResult(
                repositoryID: repositoryID,
                transitionAt: transitionDate
            )
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
            for: repositoryActivityDeadlineResult(
                repositoryID: repositoryID,
                transitionAt: transitionDate
            )
        )
        for _ in 0..<300 where await delayGate.waitCount == 0 { await Task.yield() }
        dateBox.value = transitionDate
        let currentWait = try #require(await delayGate.releaseNext())
        for _ in 0..<300 where adapter.recencyReferenceDate != transitionDate { await Task.yield() }
        #expect(currentWait.0 == .seconds(60))
        #expect(!currentWait.1)
        #expect(adapter.recencyReferenceDate == transitionDate)
        #expect(adapter.pendingInvalidation.repositoryActivityIDs == [repositoryID])
    }

    @Test("Panes by Repository observes demanded panes but not tab display")
    func panesByRepositoryRegistersPaneInputs() {
        let paneID = UUIDv7.generate()
        let tabID = UUIDv7.generate()
        let registration = RepoExplorerObservationRegistration.make(
            isVisible: true,
            surface: .panes,
            groupingMode: .repo,
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
            surface: .panes,
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

    private func repositoryActivityDeadlineResult(
        repositoryID: UUID,
        transitionAt: Date
    ) -> RepoExplorerProjectionResult {
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
            repositoryActivityTransitionAtByRepoId: [repositoryID: transitionAt],
            sidebarPresentationTransitionAtByPaneId: [:],
            preparedPresentationDeadline: RepoExplorerPreparedPresentationDeadline(
                deadline: transitionAt,
                paneIDs: [],
                repositoryIDs: [repositoryID]
            ),
            semanticBaselineSequence: empty.semanticBaselineSequence
        )
    }
}
