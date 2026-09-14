import Foundation

extension WorkspaceCoreMigrations {
    static let repositoryLocationAbsenceStatements: [String] = [
        absenceTable(name: "unavailable_repo_retention", ownerColumn: "repo_id", ownerTable: "repo"),
        "INSERT INTO unavailable_repo_retention(repo_id) SELECT repo_id FROM unavailable_repo",
        """
        INSERT OR IGNORE INTO unavailable_repo_retention(repo_id)
        SELECT repo.id FROM repo WHERE NOT EXISTS (
            SELECT 1 FROM worktree WHERE worktree.repo_id = repo.id AND worktree.stable_key = repo.stable_key
        )
        """,
        "DROP TABLE unavailable_repo",
        "ALTER TABLE unavailable_repo_retention RENAME TO unavailable_repo",
        absenceTable(name: "unavailable_worktree", ownerColumn: "worktree_id", ownerTable: "worktree"),
    ]

    private static func absenceTable(name: String, ownerColumn: String, ownerTable: String) -> String {
        """
        CREATE TABLE \(name) (
            \(ownerColumn) TEXT PRIMARY KEY REFERENCES \(ownerTable)(id) ON DELETE CASCADE,
            first_absent_at_utc REAL,
            anchor_utc REAL,
            anchor_boot_id TEXT,
            anchor_uptime_ns INTEGER,
            elapsed_before_anchor REAL,
            CHECK (
                (first_absent_at_utc IS NULL AND anchor_utc IS NULL AND anchor_boot_id IS NULL
                    AND anchor_uptime_ns IS NULL AND elapsed_before_anchor IS NULL)
                OR
                (first_absent_at_utc IS NOT NULL AND anchor_utc IS NOT NULL
                    AND anchor_boot_id IS NOT NULL AND length(anchor_boot_id) > 0
                    AND anchor_uptime_ns IS NOT NULL AND anchor_uptime_ns >= 0
                    AND elapsed_before_anchor IS NOT NULL AND elapsed_before_anchor >= 0)
            )
        )
        """
    }
}
