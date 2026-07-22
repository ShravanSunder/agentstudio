extension WorkspaceCoreMigrations {
    static let globalizeRepositoryTopologyStatements = [
        "DROP TRIGGER IF EXISTS pane_facet_repo_matches_workspace",
        "DROP TRIGGER IF EXISTS pane_facet_repo_update_matches_workspace",
        "DROP TRIGGER IF EXISTS pane_facet_worktree_matches_workspace",
        "DROP TRIGGER IF EXISTS pane_facet_worktree_update_matches_workspace",
        """
        CREATE TABLE watched_path_global_new (
            id TEXT PRIMARY KEY,
            path TEXT NOT NULL,
            stable_key TEXT NOT NULL UNIQUE,
            added_at REAL NOT NULL
        )
        """,
        """
        CREATE TABLE repo_global_new (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            repo_path TEXT NOT NULL,
            stable_key TEXT NOT NULL UNIQUE,
            created_at REAL NOT NULL,
            is_favorite INTEGER NOT NULL DEFAULT 0
                        CHECK (is_favorite IN (0, 1)),
            note TEXT
        )
        """,
        """
        CREATE TABLE worktree_global_new (
            id TEXT PRIMARY KEY,
            repo_id TEXT NOT NULL
                    REFERENCES repo(id) ON DELETE CASCADE,
            name TEXT NOT NULL,
            path TEXT NOT NULL,
            stable_key TEXT NOT NULL UNIQUE,
            is_main_worktree INTEGER NOT NULL
                             CHECK (is_main_worktree IN (0, 1)),
            note TEXT
        )
        """,
        """
        CREATE TABLE repo_tag_global_new (
            repo_id TEXT NOT NULL
                    REFERENCES repo(id) ON DELETE CASCADE,
            tag TEXT NOT NULL CHECK (
                tag = trim(tag) AND length(tag) BETWEEN 1 AND 64
            ),
            PRIMARY KEY (repo_id, tag)
        )
        """,
        """
        CREATE TABLE unavailable_repo_global_new (
            repo_id TEXT PRIMARY KEY
                    REFERENCES repo(id) ON DELETE CASCADE
        )
        """,
        """
        INSERT INTO watched_path_global_new(id, path, stable_key, added_at)
        SELECT id, path, stable_key, added_at
        FROM watched_path
        """,
        """
        INSERT INTO repo_global_new(
            id, name, repo_path, stable_key, created_at, is_favorite, note
        )
        SELECT id, name, repo_path, stable_key, created_at, is_favorite, note
        FROM repo
        """,
        """
        INSERT INTO worktree_global_new(
            id, repo_id, name, path, stable_key, is_main_worktree, note
        )
        SELECT id, repo_id, name, path, stable_key, is_main_worktree, note
        FROM worktree
        """,
        """
        INSERT INTO repo_tag_global_new(repo_id, tag)
        SELECT repo_id, tag
        FROM repo_tag
        """,
        """
        INSERT INTO unavailable_repo_global_new(repo_id)
        SELECT repo_id
        FROM unavailable_repo
        """,
        "DROP TABLE repo_tag",
        "DROP TABLE unavailable_repo",
        "DROP TABLE worktree",
        "DROP TABLE watched_path",
        "DROP TABLE repo",
        "ALTER TABLE watched_path_global_new RENAME TO watched_path",
        "ALTER TABLE repo_global_new RENAME TO repo",
        "ALTER TABLE worktree_global_new RENAME TO worktree",
        "ALTER TABLE repo_tag_global_new RENAME TO repo_tag",
        "ALTER TABLE unavailable_repo_global_new RENAME TO unavailable_repo",
        "CREATE INDEX idx_worktree_repo_id ON worktree(repo_id)",
        "CREATE INDEX idx_repo_tag_tag ON repo_tag(tag)",
        "DROP TABLE workspace_sqlite_snapshot_status",
        "DROP TABLE legacy_workspace_import_status",
    ]
}
