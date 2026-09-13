import Foundation
import GRDB

/// Optional context is valid only while both topology records are available and still related.
func paneWithValidatedTopologyFacets(
    _ database: Database,
    pane: WorkspaceCoreRepository.PaneRecord
) throws -> WorkspaceCoreRepository.PaneRecord {
    let facets = pane.metadata.durableFacets
    guard facets.repoId != nil || facets.worktreeId != nil else { return pane }
    if let repositoryID = facets.repoId, let worktreeID = facets.worktreeId,
        try Bool.fetchOne(
            database,
            sql: """
                SELECT EXISTS (
                    SELECT 1 FROM worktree
                    WHERE id = ? AND repo_id = ?
                    AND NOT EXISTS (SELECT 1 FROM unavailable_worktree WHERE worktree_id = worktree.id)
                    AND NOT EXISTS (SELECT 1 FROM unavailable_repo WHERE repo_id = worktree.repo_id)
                )
                """,
            arguments: [worktreeID.uuidString, repositoryID.uuidString]
        ) == true
    {
        return pane
    }
    var sanitized = pane
    sanitized.metadata.durableFacets.repoId = nil
    sanitized.metadata.durableFacets.worktreeId = nil
    return sanitized
}

/// Runs in the topology transaction, covering inactive workspaces as well as the loaded one.
func clearInvalidPaneTopologyFacets(_ database: Database) throws {
    try database.execute(
        sql: """
            UPDATE pane SET facet_repo_id = NULL, facet_worktree_id = NULL
            WHERE (facet_repo_id IS NOT NULL OR facet_worktree_id IS NOT NULL)
            AND NOT EXISTS (
                SELECT 1 FROM worktree
                WHERE worktree.id = pane.facet_worktree_id
                AND worktree.repo_id = pane.facet_repo_id
                AND NOT EXISTS (SELECT 1 FROM unavailable_worktree WHERE worktree_id = worktree.id)
                AND NOT EXISTS (SELECT 1 FROM unavailable_repo WHERE repo_id = worktree.repo_id)
            )
            """)
}
