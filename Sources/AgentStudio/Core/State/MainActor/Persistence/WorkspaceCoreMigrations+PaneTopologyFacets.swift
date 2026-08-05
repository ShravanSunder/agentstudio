extension WorkspaceCoreMigrations {
    static let dropPaneTopologyFacetsStatements = [
        "DROP TRIGGER IF EXISTS pane_facet_repo_matches_workspace",
        "DROP TRIGGER IF EXISTS pane_facet_repo_update_matches_workspace",
        "DROP TRIGGER IF EXISTS pane_facet_worktree_matches_workspace",
        "DROP TRIGGER IF EXISTS pane_facet_worktree_update_matches_workspace",
        "ALTER TABLE pane DROP COLUMN facet_repo_id",
        "ALTER TABLE pane DROP COLUMN facet_worktree_id",
    ]
}
