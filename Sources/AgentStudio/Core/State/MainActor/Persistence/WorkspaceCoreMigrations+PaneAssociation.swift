extension WorkspaceCoreMigrations {
    static let addPaneAssociationFacetsStatements = [
        "ALTER TABLE pane ADD COLUMN facet_repo_id TEXT",
        """
        ALTER TABLE pane ADD COLUMN facet_worktree_id TEXT CHECK (
            (facet_repo_id IS NULL) = (facet_worktree_id IS NULL)
        )
        """,
    ]
}
