import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite("Repo Explorer duplicate topology containment")
struct RepoExplorerDuplicateTopologyContainmentTests {
    @Test("duplicate worktree identities do not produce duplicate sidebar row identities")
    func duplicateWorktreeIdentitiesDoNotProduceDuplicateSidebarRowIdentities() {
        let duplicatedWorktreeId = UUID()
        let repoId = UUID()
        let repo = RepoPresentationItem(
            id: repoId,
            name: "agent-studio",
            repoPath: URL(fileURLWithPath: "/tmp/agent-studio"),
            stableKey: "agent-studio",
            worktrees: [
                Worktree(
                    id: duplicatedWorktreeId,
                    repoId: repoId,
                    name: "main",
                    path: URL(fileURLWithPath: "/tmp/agent-studio")
                ),
                Worktree(
                    id: duplicatedWorktreeId,
                    repoId: repoId,
                    name: "renamed",
                    path: URL(fileURLWithPath: "/tmp/agent-studio-renamed")
                ),
            ]
        )
        let group = RepoPresentationGroup(
            id: "remote:askluna/agent-studio",
            repoTitle: "agent-studio",
            organizationName: "askluna",
            repos: [repo]
        )

        let projection = RepoExplorerProjection.project(
            RepoExplorerSnapshot(
                repos: [repo],
                repoEnrichmentByRepoId: [:],
                query: "no-matching-repository"
            )
        )
        let rowIndex = RepoExplorerRowIndex(
            projection: projection,
            expandedGroupIds: [group.id],
            isFiltering: true
        )

        guard case .degraded(.duplicateWorktreeIdentities(let duplicateIdentities)) = rowIndex.state else {
            Issue.record("Expected duplicate worktree identity fault")
            return
        }
        let duplicateIdentity = duplicateIdentities.first

        guard case .topologyFault(let entryFault) = rowIndex.entries.first else {
            Issue.record("Expected the degraded row index to expose a fault row")
            return
        }

        #expect(rowIndex.entries.count == 1)
        #expect(projection.showsNoResults == false)
        #expect(Set(rowIndex.entries.map(\.id)).count == rowIndex.entries.count)
        #expect(entryFault == .duplicateWorktreeIdentities(duplicateIdentities))
        #expect(rowIndex.worktreeIds.isEmpty)
        #expect(duplicateIdentity?.worktreeId == duplicatedWorktreeId)
        #expect(
            duplicateIdentity?.claims.map(\.path.path) == [
                "/tmp/agent-studio", "/tmp/agent-studio-renamed",
            ])
        #expect(
            rowIndex.resolve(
                groupId: group.id,
                repoId: repoId,
                worktreeId: duplicatedWorktreeId,
                rowId: "duplicate-topology-must-not-resolve"
            ) == nil
        )
    }

    @Test("duplicate identity remains degraded across resolved and loading repositories")
    func duplicateIdentityRemainsDegradedAcrossResolvedAndLoadingRepositories() {
        let duplicatedWorktreeId = UUID()
        let resolvedRepoId = UUID()
        let loadingRepoId = UUID()
        let resolvedRepo = RepoPresentationItem(
            id: resolvedRepoId,
            name: "visible-match",
            repoPath: URL(fileURLWithPath: "/tmp/visible-match"),
            stableKey: "visible-match",
            worktrees: [
                Worktree(
                    id: duplicatedWorktreeId,
                    repoId: resolvedRepoId,
                    name: "visible-match",
                    path: URL(fileURLWithPath: "/tmp/visible-match")
                )
            ]
        )
        let loadingRepo = RepoPresentationItem(
            id: loadingRepoId,
            name: "hidden-loading",
            repoPath: URL(fileURLWithPath: "/tmp/hidden-loading"),
            stableKey: "hidden-loading",
            worktrees: [
                Worktree(
                    id: duplicatedWorktreeId,
                    repoId: loadingRepoId,
                    name: "hidden-loading",
                    path: URL(fileURLWithPath: "/tmp/hidden-loading")
                )
            ]
        )
        let projection = RepoExplorerProjection.project(
            RepoExplorerSnapshot(
                repos: [resolvedRepo, loadingRepo],
                repoEnrichmentByRepoId: [
                    resolvedRepoId: .resolvedLocal(
                        repoId: resolvedRepoId,
                        identity: RepoIdentity(
                            groupKey: "path:\(resolvedRepo.repoPath.path)",
                            remoteSlug: nil,
                            organizationName: nil,
                            displayName: resolvedRepo.name
                        ),
                        updatedAt: Date()
                    )
                ],
                query: "visible"
            )
        )
        let rowIndex = RepoExplorerRowIndex(
            projection: projection,
            expandedGroupIds: [],
            isFiltering: true
        )

        guard case .degraded(.duplicateWorktreeIdentities(let duplicates)) = rowIndex.state else {
            Issue.record("Expected unfiltered topology preflight to detect both claims")
            return
        }

        #expect(duplicates.count == 1)
        #expect(duplicates[0].claims.map(\.repoId) == [resolvedRepoId, loadingRepoId].sorted(by: uuidPrecedes))
        #expect(rowIndex.entries.count == 1)
        #expect(rowIndex.worktreeIds.isEmpty)
        #expect(projection.showsNoResults == false)
    }

    private func uuidPrecedes(_ lhs: UUID, _ rhs: UUID) -> Bool {
        lhs.uuidString < rhs.uuidString
    }
}
