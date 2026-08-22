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

    var executionCount: Int {
        lock.withLock { storedExecutionCount }
    }

    func recordExecution() {
        lock.withLock { storedExecutionCount += 1 }
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
                    recorder.recordExecution()
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
