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
        """
        ALTER TABLE tab_shell ADD COLUMN color_hex TEXT
        """,
        """
        CREATE TABLE repo_tag (
            repo_id TEXT NOT NULL REFERENCES repo(id) ON DELETE CASCADE,
            tag TEXT NOT NULL,
            PRIMARY KEY(repo_id, tag)
        )
        """,
    ]
}

extension WorkspaceCoreMigrations {
    static var addRepoSidebarMetadataStatements: [String] {
        WorkspaceCoreRepoSidebarMetadataMigration.statements
    }
}
