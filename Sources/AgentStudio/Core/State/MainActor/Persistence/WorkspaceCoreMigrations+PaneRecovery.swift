extension WorkspaceCoreMigrations {
    /// Preserves panes written by the historical close-tab path before strict
    /// save validation existed. These top-level panes retain their complete
    /// payload and facets in the recoverable pool; the migration neither
    /// deletes them nor invents tab ownership.
    static let backgroundActiveUnownedLayoutPanesStatements = [
        """
        UPDATE pane
        SET
            residency_kind = '\(SQLitePaneGraphStorage.residencyKindBackgrounded)',
            pending_undo_expires_at = NULL,
            orphan_reason_kind = NULL,
            orphan_worktree_path = NULL
        WHERE residency_kind = '\(SQLitePaneGraphStorage.residencyKindActive)'
          AND kind IN ('\(SQLitePaneGraphStorage.placementKindLayout)', 'leaf')
          AND parent_pane_id IS NULL
          AND NOT EXISTS (
              SELECT 1
              FROM tab_pane
              WHERE tab_pane.pane_id = pane.id
          )
          AND NOT EXISTS (
              SELECT 1
              FROM drawer_pane
              WHERE drawer_pane.pane_id = pane.id
          )
        """
    ]
}
