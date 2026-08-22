import AgentStudioCore
import AgentStudioInfrastructure
import Foundation
import Testing

@testable import AgentStudioRepoExplorer

@Suite("RepoExplorerMaterializationSnapshotTests")
struct RepoExplorerMaterializationSnapshotTests {
    @Test("worker stores ordered rows with O(1) identity and occurrence indexes")
    func workerStoresOrderedRowsAndOccurrenceIndexes() throws {
        let repoID = UUIDv7.generate()
        let worktreeID = UUIDv7.generate()
        let request = makeRepoRequest(repoID: repoID, worktreeID: worktreeID)

        let result = try RepoExplorerProjectionWorker.project(request)
        let materialization = result.materializationSnapshot
        let orderedIDs = materialization.rows.map(\.id)

        #expect(orderedIDs == result.rowIndex.entries.map(\.id))
        #expect(materialization.rowIndexByID.count == materialization.rows.count)
        for (expectedIndex, rowID) in orderedIDs.enumerated() {
            #expect(materialization.rowIndexByID[rowID] == expectedIndex)
            #expect(materialization.row(id: rowID)?.id == rowID)
        }
        #expect(materialization.rowIDsByRepoID[repoID]?.count == 2)
        #expect(materialization.rowIDsByWorktreeID[worktreeID]?.count == 1)
        #expect(
            materialization.rowIDsByWorktreeID[worktreeID]?.first
                == .worktree(
                    groupID: "remote:askluna/agent-studio",
                    repoID: repoID,
                    worktreeID: worktreeID
                )
        )
    }

    @Test("layout facts are stable and only declared wrapping rows request visible measurement")
    func layoutFactsAreStableAndWrappingIsExplicit() throws {
        let repoID = UUIDv7.generate()
        let worktreeID = UUIDv7.generate()
        let result = try RepoExplorerProjectionWorker.project(
            makeRepoRequest(repoID: repoID, worktreeID: worktreeID)
        )

        #expect(
            result.materializationSnapshot.rows.map(\.layout.rowClass) == [
                .sectionHeader,
                .groupHeader,
                .worktree,
            ])
        #expect(result.materializationSnapshot.rows.allSatisfy { !$0.layout.requiresVisibleWidthMeasurement })
        #expect(
            result.materializationSnapshot.rows.allSatisfy {
                $0.layout.metrics.primaryLineHeight == AppStyles.General.Typography.textBase
            }
        )

        let fault = RepoExplorerTopologyFault.duplicateWorktreeIdentities([
            RepoExplorerDuplicateWorktreeIdentity(
                worktreeId: worktreeID,
                claims: [
                    RepoExplorerWorktreeIdentityClaim(
                        repoId: repoID,
                        stableKey: "first",
                        path: URL(fileURLWithPath: "/tmp/first")
                    ),
                    RepoExplorerWorktreeIdentityClaim(
                        repoId: UUIDv7.generate(),
                        stableKey: "second",
                        path: URL(fileURLWithPath: "/tmp/second")
                    ),
                ]
            )
        ])
        let faultProjection = RepoExplorerSidebarProjection.degraded(fault)
        let faultIndex = RepoExplorerRowIndex(
            projection: faultProjection,
            collapsedGroupIds: [],
            isFiltering: false
        )
        let faultMaterialization = RepoExplorerMaterializationSnapshot.build(
            rowIndex: faultIndex,
            inputs: RepoExplorerMaterializationInputs(
                snapshot: .init(
                    repos: [], repoEnrichmentByRepoId: [:], groupingMode: .repo, query: ""),
                projection: faultProjection,
                branchStatusByWorktreeID: [:],
                branchNameByWorktreeID: [:],
                bridgeCommandResolutionByWorktreeID: [:],
                paneRowFactsByPaneID: [:]
            )
        )

        #expect(faultMaterialization.rows.map(\.layout.rowClass) == [.fault])
        #expect(faultMaterialization.rows.allSatisfy { $0.layout.requiresVisibleWidthMeasurement })
    }

    @Test("content revision changes for every associated-pane rendered field")
    func paneContentRevisionIncludesEveryRenderedField() {
        let repoID = UUIDv7.generate()
        let worktreeID = UUIDv7.generate()
        let paneID = UUIDv7.generate()
        let tabID = UUIDv7.generate()
        let destination = RepoExplorerPaneDestination(
            paneId: paneID,
            repoId: repoID,
            worktreeId: worktreeID,
            worktreeLabel: "main",
            tabId: tabID,
            tabIndex: 0,
            paneIndexInTab: 0,
            isActiveInTab: true
        )
        let baseline = RepoExplorerProjectedPaneRow(
            groupId: "pane-group",
            repoId: repoID,
            destination: destination,
            rowId: "legacy-worker-row-id",
            primaryText: "zsh",
            secondaryLine: .terminalOutput("building"),
            branchContextText: "main",
            branchStatus: .unknown,
            recencyText: "Now",
            recencyTier: .strongBlue,
            isActive: false,
            isDrawerPane: false
        )
        let changedRows = [
            replacing(baseline, primaryText: "tests"),
            replacing(baseline, secondaryLine: .note("review")),
            replacing(baseline, branchContextText: "feature"),
            replacing(
                baseline,
                branchStatus: GitBranchStatus(
                    isDirty: true,
                    syncState: .ahead(1),
                    prCount: 0,
                    pullRequestIsLoading: false,
                    pullRequestDataUnavailable: false,
                    linesAdded: 3,
                    linesDeleted: 1,
                    untrackedFileCount: 0
                )
            ),
            replacing(baseline, recencyText: "5m"),
            replacing(baseline, recencyTier: .grey),
            replacing(baseline, isActive: true),
            replacing(baseline, isDrawerPane: true),
        ]
        let baselineRevision = RepoExplorerRowContentRevision(
            presentation: .associatedPane(baseline)
        )

        for changedRow in changedRows {
            #expect(
                RepoExplorerRowContentRevision(presentation: .associatedPane(changedRow))
                    != baselineRevision
            )
        }
    }

    private func makeRepoRequest(
        repoID: UUID,
        worktreeID: UUID
    ) -> RepoExplorerProjectionRequest {
        let worktree = Worktree(
            id: worktreeID,
            repoId: repoID,
            name: "main",
            path: URL(fileURLWithPath: "/tmp/agent-studio"),
            isMainWorktree: true
        )
        let repo = RepoPresentationItem(
            id: repoID,
            name: "agent-studio",
            repoPath: worktree.path,
            stableKey: "agent-studio",
            worktrees: [worktree]
        )
        return RepoExplorerProjectionRequest(
            generation: 1,
            snapshot: RepoExplorerSnapshot(
                repos: [repo],
                repoEnrichmentByRepoId: [
                    repoID: .resolvedRemote(
                        repoId: repoID,
                        raw: RawRepoOrigin(
                            origin: "git@github.com:askluna/agent-studio.git",
                            upstream: nil
                        ),
                        identity: RepoIdentity(
                            groupKey: "remote:askluna/agent-studio",
                            remoteSlug: "askluna/agent-studio",
                            organizationName: "askluna",
                            displayName: "agent-studio"
                        ),
                        updatedAt: Date(timeIntervalSince1970: 0)
                    )
                ],
                groupingMode: .repo,
                query: ""
            ),
            collapsedGroupIds: [],
            isFiltering: false,
            trigger: .dataRefresh
        )
    }

    private func replacing(
        _ row: RepoExplorerProjectedPaneRow,
        primaryText: String? = nil,
        secondaryLine: RepoExplorerPaneSecondaryLine?? = nil,
        branchContextText: String?? = nil,
        branchStatus: GitBranchStatus?? = nil,
        recencyText: String? = nil,
        recencyTier: RepoExplorerPaneRecencyTier? = nil,
        isActive: Bool? = nil,
        isDrawerPane: Bool? = nil
    ) -> RepoExplorerProjectedPaneRow {
        RepoExplorerProjectedPaneRow(
            groupId: row.groupId,
            repoId: row.repoId,
            destination: row.destination,
            rowId: row.rowId,
            primaryText: primaryText ?? row.primaryText,
            secondaryLine: secondaryLine ?? row.secondaryLine,
            branchContextText: branchContextText ?? row.branchContextText,
            branchStatus: branchStatus ?? row.branchStatus,
            recencyText: recencyText ?? row.recencyText,
            recencyTier: recencyTier ?? row.recencyTier,
            isActive: isActive ?? row.isActive,
            isDrawerPane: isDrawerPane ?? row.isDrawerPane
        )
    }
}
