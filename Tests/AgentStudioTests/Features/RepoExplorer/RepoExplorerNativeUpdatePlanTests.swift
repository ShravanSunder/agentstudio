import AgentStudioInfrastructure
import Foundation
import Testing

@testable import AgentStudioRepoExplorer

@Suite("Repo Explorer native update plan")
struct RepoExplorerNativeUpdatePlanTests {
    @Test("equal presentation derives R to R with O(1) preflight")
    func equalPresentationKeepsRevision() throws {
        let snapshot = nativePlanSnapshot(["A", "B"])
        let baseline = nativePlanBaseline(snapshot: snapshot, revision: 3)
        let plan = try RepoExplorerNativeUpdatePlan.validating(
            baseline: baseline,
            candidate: nativePlanContent(snapshot),
            requestGeneration: 11
        ).get()

        guard case .equal(let equal) = plan.kind else {
            Issue.record("Expected equal native update plan")
            return
        }
        #expect(equal.preflight.oldRevision == 3)
        #expect(equal.newRevision == 3)
        #expect(equal.rowCount == 2)
        #expect(plan.preflightMatches(baseline: baseline, requestGeneration: 11))
        #expect(!plan.preflightMatches(baseline: baseline, requestGeneration: 12))
    }

    @Test(
        "rowless transitions cover every empty and content edge",
        arguments: RepoExplorerRowlessPresentation.allCases
    )
    func rowlessTransitionsAreTotal(empty: RepoExplorerRowlessPresentation) throws {
        let rowlessBaseline = nativePlanRowlessBaseline(.noRepositories, revision: 0)
        let changedEmpty = try RepoExplorerNativeUpdatePlan.validating(
            baseline: rowlessBaseline,
            candidate: .rowless(empty),
            requestGeneration: 1
        ).get()
        if empty == .noRepositories {
            guard case .equal = changedEmpty.kind else {
                Issue.record("Equal empty must derive R to R")
                return
            }
        } else {
            guard case .changed(let changed) = changedEmpty.kind,
                case .changedEmptyToEmpty(let target) = changed.presentation
            else {
                Issue.record("Expected changed empty-to-empty plan")
                return
            }
            #expect(target == empty)
            #expect(changed.proposedRevision == 1)
        }

        let content = nativePlanSnapshot(["A"])
        let emptyToContent = try RepoExplorerNativeUpdatePlan.validating(
            baseline: rowlessBaseline,
            candidate: nativePlanContent(content),
            requestGeneration: 1
        ).get()
        guard case .changed(let contentChange) = emptyToContent.kind,
            case .emptyToContent(let tablePlan) = contentChange.presentation,
            case .membership(let membership) = tablePlan
        else {
            Issue.record("Expected empty-to-content membership plan")
            return
        }
        #expect(membership.insertRowsInNewSpace == IndexSet(integer: 0))
        #expect(membership.removeRowsInOldSpace.isEmpty)

        let contentBaseline = nativePlanBaseline(snapshot: content, revision: 4)
        let contentToEmpty = try RepoExplorerNativeUpdatePlan.validating(
            baseline: contentBaseline,
            candidate: .rowless(empty),
            requestGeneration: 5
        ).get()
        guard case .changed(let emptyChange) = contentToEmpty.kind,
            case .contentToEmpty(let target) = emptyChange.presentation
        else {
            Issue.record("Expected content-to-empty plan")
            return
        }
        #expect(target == empty)
        #expect(emptyChange.proposedRevision == 5)
    }

    @Test("content-only change emits final-space reload and height indexes")
    func contentOnlyChangeUsesFinalSpaceIndexes() throws {
        let oldSnapshot = nativePlanSnapshot(["A", "B"])
        let newSnapshot = nativePlanSnapshot(["A", "B"], changedTitles: ["B"], changedLayouts: ["A"])
        let baseline = nativePlanBaseline(snapshot: oldSnapshot, revision: 2)
        #expect(
            RepoExplorerMaterializationFingerprint.make(snapshot: oldSnapshot)
                == RepoExplorerMaterializationFingerprint.make(snapshot: newSnapshot)
        )
        let plan = try RepoExplorerNativeUpdatePlan.validating(
            baseline: baseline,
            candidate: nativePlanContent(newSnapshot),
            requestGeneration: 9
        ).get()

        guard case .changed(let changed) = plan.kind,
            case .contentToContent(.content(let content)) = changed.presentation
        else {
            Issue.record("Expected content-only table plan")
            return
        }
        #expect(content.reloadRowsInNewSpace == IndexSet(integer: 1))
        #expect(content.heightReloadRowsInNewSpace == IndexSet(integer: 0))
        #expect(changed.proposedRevision == 3)
    }

    @Test("membership plan preserves old and final index spaces")
    func membershipPlanUsesDeclaredIndexSpaces() throws {
        let oldSnapshot = nativePlanSnapshot(["A", "B", "C", "D"])
        let newSnapshot = nativePlanSnapshot(["B", "E", "D", "A"], changedTitles: ["B"])
        let baseline = nativePlanBaseline(snapshot: oldSnapshot, revision: 7)
        let plan = try RepoExplorerNativeUpdatePlan.validating(
            baseline: baseline,
            candidate: nativePlanContent(newSnapshot),
            requestGeneration: 12
        ).get()

        guard case .changed(let changed) = plan.kind,
            case .contentToContent(.membership(let membership)) = changed.presentation
        else {
            Issue.record("Expected membership plan")
            return
        }
        #expect(membership.removeRowsInOldSpace == IndexSet([0, 2]))
        #expect(membership.insertRowsInNewSpace == IndexSet([1, 3]))
        #expect(membership.movesFromOldToNewSpace.isEmpty)
        #expect(membership.reloadRowsInNewSpace == IndexSet(integer: 0))
        #expect(membership.heightReloadRowsInNewSpace.isEmpty)
        #expect(membership.oldCount == 4)
        #expect(membership.newCount == 4)
        #expect(
            membership.anchorFallbacks.entries == [
                RepoExplorerNativeRemovedRowAnchorFallback(
                    removedRowID: .group(groupID: "C"),
                    targetRowID: .group(groupID: "D")
                )
            ]
        )
    }

    @Test("removed anchor fallback prefers successor then predecessor")
    func removedAnchorFallbackUsesOldOrdering() throws {
        let oldSnapshot = nativePlanSnapshot(["A", "B", "C", "D", "E"])
        let newSnapshot = nativePlanSnapshot(["E", "A"])
        let baseline = nativePlanBaseline(snapshot: oldSnapshot, revision: 2)
        let plan = try RepoExplorerNativeUpdatePlan.validating(
            baseline: baseline,
            candidate: nativePlanContent(newSnapshot),
            requestGeneration: 3
        ).get()

        guard case .changed(let changed) = plan.kind,
            case .contentToContent(.membership(let membership)) = changed.presentation
        else {
            Issue.record("Expected membership plan")
            return
        }

        #expect(
            membership.anchorFallbacks.entries == [
                RepoExplorerNativeRemovedRowAnchorFallback(
                    removedRowID: .group(groupID: "B"),
                    targetRowID: .group(groupID: "E")
                ),
                RepoExplorerNativeRemovedRowAnchorFallback(
                    removedRowID: .group(groupID: "C"),
                    targetRowID: .group(groupID: "E")
                ),
                RepoExplorerNativeRemovedRowAnchorFallback(
                    removedRowID: .group(groupID: "D"),
                    targetRowID: .group(groupID: "E")
                ),
            ]
        )
    }

    @Test("validation rejects stale baseline identity and malformed snapshots")
    func validationRejectsInvalidInputs() {
        let snapshot = nativePlanSnapshot(["A", "B"])
        let baseline = nativePlanBaseline(snapshot: snapshot, revision: 1)
        let wrongFingerprintBaseline = RepoExplorerMaterializationBaseline(
            lifetimeID: baseline.lifetimeID,
            demandEpoch: baseline.demandEpoch,
            revision: baseline.revision,
            visibleGeneration: baseline.visibleGeneration,
            presentation: .content(
                snapshot: snapshot,
                fingerprint: RepoExplorerMaterializationFingerprint(rawValue: 999)
            )
        )

        #expect(
            RepoExplorerNativeUpdatePlan.validating(
                baseline: wrongFingerprintBaseline,
                candidate: nativePlanContent(snapshot),
                requestGeneration: 2
            ) == .failure(.baselineFingerprintMismatch)
        )
    }
}

func nativePlanLifetime(_ value: UInt8 = 1) -> RepoExplorerMaterializationHostLifetimeID {
    RepoExplorerMaterializationHostLifetimeID(
        rawValue: UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, value))
    )
}

func nativePlanBaseline(
    snapshot: RepoExplorerMaterializationSnapshot,
    revision: UInt64,
    lifetime: RepoExplorerMaterializationHostLifetimeID = nativePlanLifetime(),
    demandEpoch: UInt64 = 7,
    visibleGeneration: UInt64 = 10
) -> RepoExplorerMaterializationBaseline {
    RepoExplorerMaterializationBaseline(
        lifetimeID: lifetime,
        demandEpoch: demandEpoch,
        revision: revision,
        visibleGeneration: visibleGeneration,
        presentation: nativePlanContent(snapshot)
    )
}

func nativePlanRowlessBaseline(
    _ rowless: RepoExplorerRowlessPresentation,
    revision: UInt64
) -> RepoExplorerMaterializationBaseline {
    RepoExplorerMaterializationBaseline(
        lifetimeID: nativePlanLifetime(),
        demandEpoch: 7,
        revision: revision,
        visibleGeneration: 0,
        presentation: .rowless(rowless)
    )
}

func nativePlanContent(
    _ snapshot: RepoExplorerMaterializationSnapshot
) -> RepoExplorerMaterializationPresentation {
    .content(snapshot: snapshot, fingerprint: .make(snapshot: snapshot))
}

func nativePlanSnapshot(
    _ identities: [String],
    changedTitles: Set<String> = [],
    changedLayouts: Set<String> = []
) -> RepoExplorerMaterializationSnapshot {
    RepoExplorerMaterializationSnapshot(
        rows: identities.map { identity in
            let rowID = RepoExplorerRowID.group(groupID: identity)
            let presentation = RepoExplorerMaterializedRowPresentation.groupHeader(
                RepoExplorerMaterializedGroupHeaderPresentation(
                    groupID: identity,
                    icon: .repo,
                    title: changedTitles.contains(identity) ? "\(identity)-changed" : identity,
                    organizationName: nil,
                    colorHex: nil,
                    isExpanded: true,
                    repoIDs: [],
                    semanticRepoPath: nil,
                    paneDestinations: []
                )
            )
            var layout = RepoExplorerRowLayout.make(for: presentation)
            if changedLayouts.contains(identity) {
                layout = RepoExplorerRowLayout(
                    rowClass: layout.rowClass,
                    metrics: RepoExplorerRowLayoutMetrics(
                        primaryLineHeight: layout.metrics.primaryLineHeight + 1,
                        metadataLineHeight: layout.metrics.metadataLineHeight,
                        chipLineHeight: layout.metrics.chipLineHeight,
                        contentSpacing: layout.metrics.contentSpacing,
                        verticalInset: layout.metrics.verticalInset,
                        leadingInset: layout.metrics.leadingInset,
                        trailingInset: layout.metrics.trailingInset,
                        minimumHeight: layout.metrics.minimumHeight + 1,
                        fallbackHeight: layout.metrics.fallbackHeight + 1
                    ),
                    requiresVisibleWidthMeasurement: layout.requiresVisibleWidthMeasurement
                )
            }
            return RepoExplorerMaterializedRow(
                id: rowID,
                contentRevision: RepoExplorerRowContentRevision(presentation: presentation),
                layout: layout,
                representedRepoID: nil,
                representedWorktreeID: nil
            )
        }
    )
}
