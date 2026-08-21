import AgentStudioCore
import AgentStudioInfrastructure
import Foundation
import Observation
import Testing

@testable import AgentStudioRepoExplorer

@Suite("RepoExplorer projection demand")
struct RepoExplorerProjectionDemandTests {
    @MainActor
    @Test("adapter owns observation generation and hidden suspension")
    func adapterOwnsObservationLifecycle() async {
        let source = RepoExplorerObservationSourceProbe()
        let adapter = RepoExplorerProjectionAdapter()
        defer { adapter.stop() }
        var invalidationCount = 0

        adapter.startObservation {
            _ = source.value
        } onInvalidated: { _ in
            invalidationCount += 1
        }
        #expect(invalidationCount == 1)

        source.value = 1
        for _ in 0..<100 where invalidationCount != 2 {
            await Task.yield()
        }
        #expect(invalidationCount == 2)

        adapter.suspendObservation()
        source.value = 2
        for _ in 0..<100 { await Task.yield() }
        #expect(invalidationCount == 2)
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

@MainActor
@Observable
private final class RepoExplorerObservationSourceProbe {
    var value = 0
}
