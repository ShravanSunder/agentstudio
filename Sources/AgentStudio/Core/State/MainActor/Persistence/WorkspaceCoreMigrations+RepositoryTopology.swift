extension WorkspaceCoreMigrations {
    static let repositoryTopologyTagsAndTabColorStatements = [
        """
        DROP TABLE IF EXISTS pane_tag
        """,
        """
        CREATE UNIQUE INDEX idx_worktree_id_workspace_repo_id
        ON worktree(id, workspace_id, repo_id)
        """,
        """
        CREATE TABLE repo_tag (
            repo_id TEXT NOT NULL,
            workspace_id TEXT NOT NULL,
            tag TEXT NOT NULL CHECK (
                tag = trim(tag)
                AND length(tag) BETWEEN 1 AND 64
            ),
            PRIMARY KEY(workspace_id, repo_id, tag),
            FOREIGN KEY(repo_id, workspace_id)
                REFERENCES repo(id, workspace_id)
                ON DELETE CASCADE
        )
        """,
        """
        CREATE TABLE worktree_tag (
            worktree_id TEXT NOT NULL,
            workspace_id TEXT NOT NULL,
            repo_id TEXT NOT NULL,
            tag TEXT NOT NULL CHECK (
                tag = trim(tag)
                AND length(tag) BETWEEN 1 AND 64
            ),
            PRIMARY KEY(workspace_id, worktree_id, tag),
            FOREIGN KEY(worktree_id, workspace_id, repo_id)
                REFERENCES worktree(id, workspace_id, repo_id)
                ON DELETE CASCADE,
            FOREIGN KEY(repo_id, workspace_id)
                REFERENCES repo(id, workspace_id)
                ON DELETE CASCADE
        )
        """,
        """
        CREATE INDEX idx_repo_tag_workspace_tag
        ON repo_tag(workspace_id, tag)
        """,
        """
        CREATE INDEX idx_worktree_tag_workspace_tag
        ON worktree_tag(workspace_id, tag)
        """,
        """
        CREATE INDEX idx_worktree_tag_repo_id
        ON worktree_tag(repo_id)
        """,
        """
        ALTER TABLE tab_shell
        ADD COLUMN color_hex TEXT CHECK (
            color_hex IS NULL
            OR color_hex GLOB '#[0-9A-F][0-9A-F][0-9A-F][0-9A-F][0-9A-F][0-9A-F]'
        )
        """,
    ]
}
