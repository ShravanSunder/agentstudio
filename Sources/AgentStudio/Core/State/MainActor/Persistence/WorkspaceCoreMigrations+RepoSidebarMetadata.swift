enum WorkspaceCoreRepoSidebarMetadataMigration {
    static let statements = [
        """
        ALTER TABLE repo ADD COLUMN is_favorite INTEGER NOT NULL DEFAULT 0
        """,
        """
        ALTER TABLE repo ADD COLUMN note TEXT
        """,
        """
        ALTER TABLE worktree ADD COLUMN note TEXT
        """,
    ]
}

extension WorkspaceCoreMigrations {
    static var addRepoSidebarMetadataStatements: [String] {
        WorkspaceCoreRepoSidebarMetadataMigration.statements
    }
}
