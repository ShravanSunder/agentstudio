import AgentStudioCore
import AgentStudioInfrastructure
import AgentStudioTestSupport
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

@Suite("RepoExplorer projection demand")
struct RepoExplorerProjectionDemandTests {
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
            defer { adapter.stop() }

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
            #expect(capture.fullCaptureCount == 1)
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

            let fullCaptureCountBeforeTabRename = capture.fullCaptureCount
            let scopedCaptureCountBeforeTabRename = capture.scopedCaptureCount
            let publishedRevisionBeforeTabRename = adapter.publishedRevision
            store.tabLayoutAtom.renameTab(tab.id, name: "Renamed")
            for _ in 0..<300
            where adapter.publishedRevision == publishedRevisionBeforeTabRename
                || adapter.publishedResult?.tabGroupFactsByTabId[tab.id]?.displayTitle != "Renamed"
            {
                await Task.yield()
            }
            #expect(capture.fullCaptureCount == fullCaptureCountBeforeTabRename)
            #expect(capture.scopedCaptureCount == scopedCaptureCountBeforeTabRename + 1)
            #expect(adapter.publishedRevision == publishedRevisionBeforeTabRename + 1)
            #expect(adapter.publishedResult?.projectionDuration == .zero)

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

            adapter.updateDemand(isVisible: true, query: "")
            for _ in 0..<200 where adapter.publishedResult == nil { await Task.yield() }
            #expect(capture.fullCaptureCount == 1)

            _ = store.createPane(title: "new membership")
            for _ in 0..<300 where capture.fullCaptureCount < 2 { await Task.yield() }

            #expect(capture.fullCaptureCount == 2)
            #expect(capture.scopedCaptureCount == 0)
        }
    }

    @Test("same-baseline pending deltas union B and C scope")
    func sameBaselinePendingDeltasUnionScope() throws {
        let repositoryID = UUIDv7.generate()
        let worktreeID = UUIDv7.generate()
        let baseline = RepoExplorerProjectionResult.empty
        let pending = RepoExplorerProjectionWork.delta(
            RepoExplorerProjectionDelta(
                baselineRevision: 7,
                baselineResult: baseline,
                targetRequest: emptyRequest(generation: 2),
                changes: [.repo(repositoryID)]
            )
        )
        let latest = RepoExplorerProjectionWork.delta(
            RepoExplorerProjectionDelta(
                baselineRevision: 7,
                baselineResult: baseline,
                targetRequest: emptyRequest(generation: 3),
                changes: [.worktreeFact(worktreeID)]
            )
        )

        let combined = RepoExplorerProjectionWork.combinePending(pending, latest)
        guard case .delta(let delta) = combined else {
            Issue.record("Expected same-baseline deltas to remain delta work")
            return
        }
        #expect(delta.targetRequest.generation == 3)
        #expect(delta.changes == [.repo(repositoryID), .worktreeFact(worktreeID)])
    }

    @Test("different-baseline pending deltas promote latest intent to full")
    func differentBaselinePendingDeltasPromoteToFull() {
        let baseline = RepoExplorerProjectionResult.empty
        let pending = RepoExplorerProjectionWork.delta(
            RepoExplorerProjectionDelta(
                baselineRevision: 7,
                baselineResult: baseline,
                targetRequest: emptyRequest(generation: 2),
                changes: [.repo(UUIDv7.generate())]
            )
        )
        let latestRequest = emptyRequest(generation: 3)
        let latest = RepoExplorerProjectionWork.delta(
            RepoExplorerProjectionDelta(
                baselineRevision: 8,
                baselineResult: baseline,
                targetRequest: latestRequest,
                changes: [.worktreeFact(UUIDv7.generate())]
            )
        )

        #expect(RepoExplorerProjectionWork.combinePending(pending, latest) == .full(latestRequest))
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
}
