enum WorkspaceCoreTabGraphLayoutRepairMigrations {
    static let statements = [
        """
        DELETE FROM drawer_view_layout_pane
        WHERE row_kind NOT IN ('\(SQLiteTabGraphStorage.topRow)', '\(SQLiteTabGraphStorage.bottomRow)')
        """,
        """
        DELETE FROM drawer_view_layout_divider
        WHERE row_kind NOT IN ('\(SQLiteTabGraphStorage.topRow)', '\(SQLiteTabGraphStorage.bottomRow)')
        """,
        """
        DELETE FROM arrangement_layout_divider
        WHERE NOT EXISTS (
            SELECT 1
            FROM arrangement_layout_pane AS left_pane
            WHERE left_pane.arrangement_id = arrangement_layout_divider.arrangement_id
            AND left_pane.sort_index = arrangement_layout_divider.sort_index
            AND EXISTS (
                SELECT 1
                FROM arrangement_layout_pane AS right_pane
                WHERE right_pane.arrangement_id = arrangement_layout_divider.arrangement_id
                AND right_pane.sort_index > left_pane.sort_index
            )
        )
        """,
        """
        DELETE FROM drawer_view_layout_divider
        WHERE NOT EXISTS (
            SELECT 1
            FROM drawer_view_layout_pane AS left_pane
            WHERE left_pane.arrangement_id = drawer_view_layout_divider.arrangement_id
            AND left_pane.drawer_id = drawer_view_layout_divider.drawer_id
            AND left_pane.row_kind = drawer_view_layout_divider.row_kind
            AND left_pane.sort_index = drawer_view_layout_divider.sort_index
            AND EXISTS (
                SELECT 1
                FROM drawer_view_layout_pane AS right_pane
                WHERE right_pane.arrangement_id = drawer_view_layout_divider.arrangement_id
                AND right_pane.drawer_id = drawer_view_layout_divider.drawer_id
                AND right_pane.row_kind = drawer_view_layout_divider.row_kind
                AND right_pane.sort_index > left_pane.sort_index
            )
        )
        """,
        """
        DROP TRIGGER IF EXISTS arrangement_layout_pane_prunes_adjacent_divider_after_delete
        """,
        """
        CREATE TRIGGER arrangement_layout_pane_prunes_adjacent_divider_after_delete
        AFTER DELETE ON arrangement_layout_pane
        BEGIN
            DELETE FROM arrangement_layout_divider
            WHERE arrangement_id = OLD.arrangement_id
            AND sort_index = (
                SELECT MAX(sort_index)
                FROM arrangement_layout_divider
                WHERE arrangement_id = OLD.arrangement_id
                AND sort_index <= OLD.sort_index
            );
        END
        """,
        """
        DROP TRIGGER IF EXISTS drawer_view_layout_pane_prunes_adjacent_divider_after_delete
        """,
        """
        CREATE TRIGGER drawer_view_layout_pane_prunes_adjacent_divider_after_delete
        AFTER DELETE ON drawer_view_layout_pane
        BEGIN
            DELETE FROM drawer_view_layout_divider
            WHERE arrangement_id = OLD.arrangement_id
            AND drawer_id = OLD.drawer_id
            AND row_kind = OLD.row_kind
            AND sort_index = (
                SELECT MAX(sort_index)
                FROM drawer_view_layout_divider
                WHERE arrangement_id = OLD.arrangement_id
                AND drawer_id = OLD.drawer_id
                AND row_kind = OLD.row_kind
                AND sort_index <= OLD.sort_index
            );
        END
        """,
        """
        DROP TRIGGER IF EXISTS drawer_view_layout_pane_row_kind_check_insert
        """,
        """
        CREATE TRIGGER drawer_view_layout_pane_row_kind_check_insert
        BEFORE INSERT ON drawer_view_layout_pane
        WHEN NEW.row_kind NOT IN ('\(SQLiteTabGraphStorage.topRow)', '\(SQLiteTabGraphStorage.bottomRow)')
        BEGIN
            SELECT RAISE(ABORT, 'drawer view layout row_kind must be top or bottom');
        END
        """,
        """
        DROP TRIGGER IF EXISTS drawer_view_layout_pane_row_kind_check_update
        """,
        """
        CREATE TRIGGER drawer_view_layout_pane_row_kind_check_update
        BEFORE UPDATE OF row_kind ON drawer_view_layout_pane
        WHEN NEW.row_kind NOT IN ('\(SQLiteTabGraphStorage.topRow)', '\(SQLiteTabGraphStorage.bottomRow)')
        BEGIN
            SELECT RAISE(ABORT, 'drawer view layout row_kind must be top or bottom');
        END
        """,
        """
        DROP TRIGGER IF EXISTS drawer_view_layout_divider_row_kind_check_insert
        """,
        """
        CREATE TRIGGER drawer_view_layout_divider_row_kind_check_insert
        BEFORE INSERT ON drawer_view_layout_divider
        WHEN NEW.row_kind NOT IN ('\(SQLiteTabGraphStorage.topRow)', '\(SQLiteTabGraphStorage.bottomRow)')
        BEGIN
            SELECT RAISE(ABORT, 'drawer view layout row_kind must be top or bottom');
        END
        """,
        """
        DROP TRIGGER IF EXISTS drawer_view_layout_divider_row_kind_check_update
        """,
        """
        CREATE TRIGGER drawer_view_layout_divider_row_kind_check_update
        BEFORE UPDATE OF row_kind ON drawer_view_layout_divider
        WHEN NEW.row_kind NOT IN ('\(SQLiteTabGraphStorage.topRow)', '\(SQLiteTabGraphStorage.bottomRow)')
        BEGIN
            SELECT RAISE(ABORT, 'drawer view layout row_kind must be top or bottom');
        END
        """,
    ]
}

extension WorkspaceCoreMigrations {
    static let repairTabGraphLayoutStorageStatements = WorkspaceCoreTabGraphLayoutRepairMigrations.statements
}
