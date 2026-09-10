enum WorkspaceCoreSidebarPinsMigration {
    static let statements = [
        """
        ALTER TABLE repo RENAME COLUMN is_favorite TO is_pinned
        """,
        """
        ALTER TABLE pane ADD COLUMN is_pinned INTEGER NOT NULL DEFAULT 0
        CHECK (is_pinned IN (0, 1))
        """,
    ]
}

extension WorkspaceCoreMigrations {
    static var addIndependentSidebarPinsStatements: [String] {
        WorkspaceCoreSidebarPinsMigration.statements
    }
}
