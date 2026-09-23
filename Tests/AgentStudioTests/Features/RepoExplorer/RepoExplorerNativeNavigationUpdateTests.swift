import AgentStudioInfrastructure
import Foundation
import Testing

@testable import AgentStudioRepoExplorer

@Suite("RepoExplorerNativeNavigationUpdateTests")
struct RepoExplorerNativeNavigationUpdateTests {
    @Test("changed native plans carry semantic and removal selection reconciliation")
    func changedPlansCarryPreparedReconciliation() throws {
        let fixture = nativeNavigationTransitionFixture()
        let baseline = nativePlanBaseline(snapshot: fixture.source, revision: 4)
        let plan = try RepoExplorerNativeUpdatePlan.validating(
            baseline: baseline,
            candidate: nativePlanContent(fixture.target),
            requestGeneration: 11
        ).get()

        #expect(
            plan.reconciledSelectionRowID(for: fixture.sourceWorktreeRowID)
                == fixture.targetWorktreeRowID
        )
        #expect(
            plan.reconciledSelectionRowID(for: fixture.removedPaneRowID)
                == fixture.targetSuccessorPaneRowID
        )
    }

    @Test("equal and content-rowless plans preserve or initialize selection by transition")
    func equalAndRowlessTransitionsCarrySelectionPolicy() throws {
        let paneID = UUIDv7.generate()
        let tabID = UUIDv7.generate()
        let paneRowID = RepoExplorerRowID.unassociatedPane(paneID: paneID)
        let snapshot = navigationSnapshot([
            .group(id: "group:before-pane", expanded: false),
            .unassociatedPane(paneID: paneID, tabID: tabID),
        ])
        let content = nativePlanContent(snapshot)
        let equalPlan = try RepoExplorerNativeUpdatePlan.validating(
            baseline: nativePlanBaseline(snapshot: snapshot, revision: 8),
            candidate: content,
            requestGeneration: 11
        ).get()
        let rowlessToContent = try RepoExplorerNativeUpdatePlan.validating(
            baseline: nativePlanRowlessBaseline(.noPanes, revision: 2),
            candidate: content,
            requestGeneration: 1
        ).get()
        let contentToRowless = try RepoExplorerNativeUpdatePlan.validating(
            baseline: nativePlanBaseline(snapshot: snapshot, revision: 8),
            candidate: .rowless(.noPanes),
            requestGeneration: 11
        ).get()

        #expect(equalPlan.reconciledSelectionRowID(for: paneRowID) == paneRowID)
        #expect(rowlessToContent.reconciledSelectionRowID(for: nil) == paneRowID)
        #expect(contentToRowless.reconciledSelectionRowID(for: paneRowID) == nil)
    }

    @Test("forward and reverse templates preserve their sealed reconciliation")
    func templatesPreserveForwardAndReverseReconciliation() throws {
        let fixture = nativeNavigationTransitionFixture()
        let source = nativePlanContent(fixture.source)
        let target = nativePlanContent(fixture.target)
        let templates = try RepoExplorerProjectionWorker.sealNativeUpdatePlanTemplates(
            source: source,
            target: target
        ).get()
        let forwardCandidate = try templates.forward.instantiate(
            baseline: nativePlanBaseline(snapshot: fixture.source, revision: 10),
            candidateID: RepoExplorerMaterializationCandidateID(rawValue: 1),
            requestGeneration: 11,
            visibleGeneration: 11
        ).get()
        let reverseCandidate = try templates.reverse.instantiate(
            baseline: nativePlanBaseline(snapshot: fixture.target, revision: 11),
            candidateID: RepoExplorerMaterializationCandidateID(rawValue: 2),
            requestGeneration: 12,
            visibleGeneration: 12
        ).get()

        #expect(
            forwardCandidate.nativeUpdatePlan.reconciledSelectionRowID(
                for: fixture.sourceWorktreeRowID
            ) == fixture.targetWorktreeRowID
        )
        #expect(
            reverseCandidate.nativeUpdatePlan.reconciledSelectionRowID(
                for: fixture.targetWorktreeRowID
            ) == fixture.sourceWorktreeRowID
        )
        #expect(
            reverseCandidate.nativeUpdatePlan.reconciledSelectionRowID(
                for: fixture.targetSuccessorPaneRowID
            ) == fixture.sourceSuccessorPaneRowID
        )
    }

    @Test("same membership with different navigation metadata fails delivery and template preflight")
    func navigationFingerprintRejectsMetadataMismatch() throws {
        let repositoryID = UUIDv7.generate()
        let worktreeID = UUIDv7.generate()
        let rowID = RepoExplorerRowID.worktree(
            groupID: "group:resolved",
            repoID: repositoryID,
            worktreeID: worktreeID
        )
        let resolved = navigationSnapshot([
            .worktree(
                groupID: "group:resolved",
                repositoryID: repositoryID,
                worktreeID: worktreeID
            )
        ])
        let unresolved = navigationSnapshot([.unresolved(rowID: rowID)])
        #expect(
            RepoExplorerMaterializationFingerprint.make(snapshot: resolved)
                == RepoExplorerMaterializationFingerprint.make(snapshot: unresolved)
        )
        #expect(resolved.navigationIndex.fingerprint != unresolved.navigationIndex.fingerprint)

        let resolvedBaseline = nativePlanBaseline(snapshot: resolved, revision: 4)
        let contentToRowless = try RepoExplorerNativeUpdatePlan.validating(
            baseline: resolvedBaseline,
            candidate: .rowless(.noPanes),
            requestGeneration: 11
        ).get()
        let mismatchedBaseline = nativePlanBaseline(snapshot: unresolved, revision: 4)
        #expect(
            !contentToRowless.preflightMatches(
                baseline: mismatchedBaseline,
                requestGeneration: 11
            )
        )

        let source = navigationSnapshot([.group(id: "group:source", expanded: false)])
        let sourceBaseline = nativePlanBaseline(snapshot: source, revision: 9)
        let resolvedPlan = try RepoExplorerNativeUpdatePlan.validating(
            baseline: sourceBaseline,
            candidate: nativePlanContent(resolved),
            requestGeneration: 11
        ).get()
        #expect(
            !resolvedPlan.matchesDelivery(
                baseline: sourceBaseline,
                presentation: nativePlanContent(unresolved),
                requestGeneration: 11,
                visibleGeneration: 11,
                expectedRevision: 9,
                proposedRevision: 10
            )
        )

        let template = try RepoExplorerProjectionWorker.sealNativeUpdatePlanTemplates(
            source: nativePlanContent(resolved),
            target: .rowless(.noPanes)
        ).get().forward
        #expect(
            template.instantiate(
                baseline: mismatchedBaseline,
                candidateID: RepoExplorerMaterializationCandidateID(rawValue: 3),
                requestGeneration: 11,
                visibleGeneration: 11
            ) == .failure(.baselineNavigationFingerprintMismatch)
        )
    }

    @Test("title-only content updates preserve navigation metadata and remain deliverable")
    func titleOnlyUpdatesPreserveNavigationMetadata() throws {
        let oldSnapshot = nativePlanSnapshot(["A", "B"])
        let newSnapshot = nativePlanSnapshot(["A", "B"], changedTitles: ["B"])
        #expect(oldSnapshot.navigationIndex.fingerprint == newSnapshot.navigationIndex.fingerprint)

        let baseline = nativePlanBaseline(snapshot: oldSnapshot, revision: 4)
        let candidate = nativePlanContent(newSnapshot)
        let plan = try RepoExplorerNativeUpdatePlan.validating(
            baseline: baseline,
            candidate: candidate,
            requestGeneration: 11
        ).get()
        #expect(
            plan.matchesDelivery(
                baseline: baseline,
                presentation: candidate,
                requestGeneration: 11,
                visibleGeneration: 11,
                expectedRevision: 4,
                proposedRevision: 5
            )
        )
    }
}

private struct RepoExplorerNativeNavigationTransitionFixture {
    let source: RepoExplorerMaterializationSnapshot
    let target: RepoExplorerMaterializationSnapshot
    let sourceWorktreeRowID: RepoExplorerRowID
    let targetWorktreeRowID: RepoExplorerRowID
    let removedPaneRowID: RepoExplorerRowID
    let sourceSuccessorPaneRowID: RepoExplorerRowID
    let targetSuccessorPaneRowID: RepoExplorerRowID
}

private func nativeNavigationTransitionFixture() -> RepoExplorerNativeNavigationTransitionFixture {
    let repositoryID = UUIDv7.generate()
    let worktreeID = UUIDv7.generate()
    let removedPaneID = UUIDv7.generate()
    let successorPaneID = UUIDv7.generate()
    let tabID = UUIDv7.generate()
    let sourceWorktreeRowID = RepoExplorerRowID.worktree(
        groupID: "group:repository",
        repoID: repositoryID,
        worktreeID: worktreeID
    )
    let targetWorktreeRowID = RepoExplorerRowID.worktree(
        groupID: "group:pinned",
        repoID: repositoryID,
        worktreeID: worktreeID
    )
    let removedPaneRowID = RepoExplorerRowID.unassociatedPane(paneID: removedPaneID)
    let sourceSuccessorPaneRowID = RepoExplorerRowID.unassociatedPane(paneID: successorPaneID)
    let targetSuccessorPaneRowID = RepoExplorerRowID.tabPane(
        groupID: "group:tab",
        paneID: successorPaneID
    )
    return RepoExplorerNativeNavigationTransitionFixture(
        source: navigationSnapshot([
            .worktree(
                groupID: "group:repository",
                repositoryID: repositoryID,
                worktreeID: worktreeID
            ),
            .unassociatedPane(paneID: removedPaneID, tabID: tabID),
            .section(.panes),
            .unassociatedPane(paneID: successorPaneID, tabID: tabID),
        ]),
        target: navigationSnapshot([
            .worktree(
                groupID: "group:pinned",
                repositoryID: repositoryID,
                worktreeID: worktreeID
            ),
            .tabPane(groupID: "group:tab", paneID: successorPaneID, tabID: tabID),
        ]),
        sourceWorktreeRowID: sourceWorktreeRowID,
        targetWorktreeRowID: targetWorktreeRowID,
        removedPaneRowID: removedPaneRowID,
        sourceSuccessorPaneRowID: sourceSuccessorPaneRowID,
        targetSuccessorPaneRowID: targetSuccessorPaneRowID
    )
}
