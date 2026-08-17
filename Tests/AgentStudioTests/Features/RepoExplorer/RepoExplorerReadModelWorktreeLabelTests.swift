import AgentStudioCore
import AgentStudioInfrastructure
import Foundation
import Testing

@testable import AgentStudioRepoExplorer

/// Split from `RepoExplorerReadModelTests` (SwiftLint `file_length`).
extension RepoExplorerReadModelTests {
    @Test("F6a: worktree label uses the worktree's display name, not a path-component derivation")
    func worktreeLabelUsesDisplayNameNotPathComponentDerivation() throws {
        // A worktree's on-disk directory name is not required to match its display name (worktree
        // checkout directories are often disambiguated with a suffix). Using
        // `worktree.path.lastPathComponent` as the label is a path-derivation substitute for the
        // real keyed fact `Worktree.name` already carries.
        let repoId = UUIDv7.generate()
        let mismatchedWorktree = Worktree(
            repoId: repoId,
            name: "feature-display-name",
            path: URL(fileURLWithPath: "/tmp/checkout-dir-does-not-match-a1b2c3"),
            isMainWorktree: false
        )
        let paneId = UUIDv7.generate()
        let tabId = UUIDv7.generate()
        let projection = RepoExplorerProjection.project(
            RepoExplorerSnapshot(
                repos: [repo(id: repoId, name: "agent-studio", worktrees: [mismatchedWorktree])],
                repoEnrichmentByRepoId: [repoId: resolvedRemote(repoId: repoId)],
                groupingMode: .pane,
                query: "",
                paneLocationsByWorktreeId: [
                    mismatchedWorktree.id: [
                        WorkspacePaneLocation(
                            paneId: paneId,
                            tabId: tabId,
                            tabIndex: 0,
                            paneIndexInTab: 0,
                            isActiveInTab: true
                        )
                    ]
                ]
            )
        )

        let expectedGroupId = "pane-repo:\(repoId.uuidString)"
        let paneRow = try #require(projection.paneRowsByGroupId[expectedGroupId]?.first)
        #expect(paneRow.destination.worktreeLabel == "feature-display-name")
    }
}
