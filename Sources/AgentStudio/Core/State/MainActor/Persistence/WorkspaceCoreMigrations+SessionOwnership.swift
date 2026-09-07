extension WorkspaceCoreMigrations {
    static let createSessionOwnershipJournalStatements = [
        """
        CREATE TABLE workspace_terminal_session_ownership (
            session_id TEXT PRIMARY KEY NOT NULL CHECK (length(trim(session_id)) > 0),
            cleanup_state TEXT NOT NULL DEFAULT 'owned'
                CHECK (cleanup_state IN ('owned', 'pending', 'completed')),
            cleanup_requested_at REAL,
            cleanup_completed_at REAL,
            last_cleanup_error TEXT,
            process_identity BLOB,
            CHECK ((cleanup_state = 'owned' AND cleanup_requested_at IS NULL)
                OR (cleanup_state <> 'owned' AND cleanup_requested_at IS NOT NULL)),
            CHECK ((cleanup_state = 'completed' AND cleanup_completed_at IS NOT NULL)
                OR (cleanup_state <> 'completed' AND cleanup_completed_at IS NULL))
        )
        """,
        """
        INSERT INTO workspace_terminal_session_ownership(session_id)
        SELECT DISTINCT zmx_session_id FROM pane_content_terminal
        WHERE zmx_session_id IS NOT NULL AND length(trim(zmx_session_id)) > 0
        """,
        """
        CREATE TABLE pane_content_terminal_with_ownership (
            pane_id TEXT PRIMARY KEY REFERENCES pane(id) ON DELETE CASCADE,
            provider TEXT NOT NULL,
            lifetime TEXT NOT NULL,
            zmx_session_id TEXT REFERENCES workspace_terminal_session_ownership(session_id) ON DELETE RESTRICT
        )
        """,
        """
        INSERT INTO pane_content_terminal_with_ownership(pane_id, provider, lifetime, zmx_session_id)
        SELECT pane_id, provider, lifetime, zmx_session_id FROM pane_content_terminal
        """,
        "DROP TABLE pane_content_terminal",
        "ALTER TABLE pane_content_terminal_with_ownership RENAME TO pane_content_terminal",
        """
        CREATE INDEX workspace_terminal_session_live_owner ON pane_content_terminal(zmx_session_id)
        """,
        """
        CREATE TRIGGER pane_content_terminal_matches_pane_content_type
        BEFORE INSERT ON pane_content_terminal
        WHEN (SELECT content_type FROM pane WHERE id = NEW.pane_id) != '\(SQLitePaneContentTypeStorage.terminal)'
        BEGIN
            SELECT RAISE(ABORT, 'pane_content_terminal requires terminal pane');
        END
        """,
        """
        CREATE TRIGGER pane_content_terminal_update_matches_pane_content_type
        BEFORE UPDATE OF pane_id ON pane_content_terminal
        WHEN (SELECT content_type FROM pane WHERE id = NEW.pane_id) != '\(SQLitePaneContentTypeStorage.terminal)'
        BEGIN
            SELECT RAISE(ABORT, 'pane_content_terminal requires terminal pane');
        END
        """,
        """
        CREATE TRIGGER workspace_terminal_session_insert_ownership
        BEFORE INSERT ON pane_content_terminal WHEN NEW.zmx_session_id IS NOT NULL
        BEGIN
            INSERT INTO workspace_terminal_session_ownership(session_id) VALUES (NEW.zmx_session_id)
                ON CONFLICT(session_id) DO NOTHING;
            SELECT RAISE(ABORT, 'terminal session is retiring')
            WHERE NOT EXISTS (
                SELECT 1 FROM workspace_terminal_session_ownership
                WHERE session_id = NEW.zmx_session_id AND cleanup_state = 'owned'
            );
        END
        """,
        """
        CREATE TRIGGER workspace_terminal_session_update_ownership
        BEFORE UPDATE OF zmx_session_id ON pane_content_terminal
        WHEN NEW.zmx_session_id IS NOT NULL AND NOT EXISTS (
            SELECT 1 FROM workspace_terminal_session_ownership
            WHERE session_id = NEW.zmx_session_id AND cleanup_state = 'owned'
        )
        BEGIN
            SELECT RAISE(ABORT, 'terminal session requires registered ownership');
        END
        """,
        """
        CREATE INDEX workspace_session_cleanup_state
        ON workspace_terminal_session_ownership(cleanup_state)
        """,
        """
        CREATE TABLE workspace_undo_close (
            close_id TEXT PRIMARY KEY NOT NULL,
            workspace_id TEXT NOT NULL,
            close_sequence INTEGER NOT NULL CHECK (close_sequence > 0),
            close_kind TEXT NOT NULL CHECK (close_kind IN ('pane', 'tab')),
            closed_at REAL NOT NULL,
            expires_at REAL NOT NULL CHECK (expires_at >= closed_at),
            state TEXT NOT NULL CHECK (state IN ('available', 'restored', 'expired', 'evicted')),
            snapshot_version INTEGER NOT NULL CHECK (snapshot_version > 0),
            snapshot_payload BLOB,
            deadline_boot_id TEXT NOT NULL CHECK (length(deadline_boot_id) > 0),
            deadline_uptime_ns INTEGER NOT NULL CHECK (deadline_uptime_ns >= 0),
            CHECK (state <> 'available' OR snapshot_payload IS NOT NULL),
            UNIQUE(workspace_id, close_sequence)
        )
        """,
        """
        CREATE INDEX workspace_undo_close_deadline ON workspace_undo_close(state, expires_at)
        """,
        """
        CREATE INDEX workspace_undo_continuous_deadline
        ON workspace_undo_close(state, deadline_boot_id, deadline_uptime_ns)
        """,
        """
        CREATE TABLE workspace_undo_close_member (
            close_id TEXT NOT NULL REFERENCES workspace_undo_close(close_id) ON DELETE CASCADE,
            pane_id TEXT NOT NULL,
            session_id TEXT REFERENCES workspace_terminal_session_ownership(session_id) ON DELETE RESTRICT,
            PRIMARY KEY(close_id, pane_id)
        )
        """,
        """
        CREATE INDEX workspace_undo_member_session ON workspace_undo_close_member(session_id)
        """,
        """
        CREATE INDEX workspace_undo_member_pane ON workspace_undo_close_member(pane_id)
        """,
        """
        CREATE TRIGGER workspace_undo_member_insert_guard
        BEFORE INSERT ON workspace_undo_close_member
        WHEN NOT EXISTS (
            SELECT 1 FROM workspace_undo_close WHERE close_id = NEW.close_id AND state = 'available'
        ) OR (NEW.session_id IS NOT NULL AND NOT EXISTS (
            SELECT 1 FROM workspace_terminal_session_ownership
            WHERE session_id = NEW.session_id AND cleanup_state = 'owned'
        ))
        BEGIN
            SELECT RAISE(ABORT, 'undo member requires available ownership');
        END
        """,
        """
        CREATE TRIGGER workspace_undo_member_update_guard
        BEFORE UPDATE ON workspace_undo_close_member
        BEGIN
            SELECT RAISE(ABORT, 'undo membership is immutable');
        END
        """,
        """
        CREATE TRIGGER workspace_undo_member_delete_guard
        BEFORE DELETE ON workspace_undo_close_member
        WHEN EXISTS (
            SELECT 1 FROM workspace_undo_close WHERE close_id = OLD.close_id AND state = 'available'
        ) OR EXISTS (
            SELECT 1 FROM workspace_terminal_session_ownership
            WHERE session_id = OLD.session_id AND cleanup_state = 'pending'
        )
        BEGIN
            SELECT RAISE(ABORT, 'unfinished undo membership');
        END
        """,
        """
        CREATE TRIGGER workspace_undo_close_delete_guard
        BEFORE DELETE ON workspace_undo_close
        WHEN OLD.state = 'available' OR EXISTS (
            SELECT 1 FROM workspace_undo_close_member AS member
            JOIN workspace_terminal_session_ownership AS session USING(session_id)
            WHERE member.close_id = OLD.close_id AND session.cleanup_state = 'pending'
        )
        BEGIN
            SELECT RAISE(ABORT, 'unfinished undo operation');
        END
        """,
        """
        CREATE TRIGGER workspace_undo_close_update_guard
        BEFORE UPDATE ON workspace_undo_close
        WHEN NEW.close_id IS NOT OLD.close_id
            OR NEW.workspace_id IS NOT OLD.workspace_id
            OR NEW.close_sequence IS NOT OLD.close_sequence
            OR NEW.close_kind IS NOT OLD.close_kind
            OR NEW.closed_at IS NOT OLD.closed_at
            OR NEW.expires_at IS NOT OLD.expires_at
            OR (OLD.state <> 'available' AND NEW.state <> OLD.state)
            OR (NEW.deadline_boot_id IS OLD.deadline_boot_id
                AND NEW.deadline_uptime_ns IS NOT OLD.deadline_uptime_ns)
        BEGIN
            SELECT RAISE(ABORT, 'undo identity, deadline or finished state is immutable');
        END
        """,
        """
        CREATE TRIGGER workspace_session_update_guard
        BEFORE UPDATE ON workspace_terminal_session_ownership
        WHEN NEW.session_id IS NOT OLD.session_id
            OR (OLD.cleanup_state <> 'owned' AND NEW.cleanup_state = 'owned')
            OR (OLD.cleanup_state = 'completed' AND NEW.cleanup_state <> 'completed')
            OR (OLD.process_identity IS NOT NULL AND NEW.process_identity IS NOT OLD.process_identity)
        BEGIN
            SELECT RAISE(ABORT, 'session identity or retirement state is immutable');
        END
        """,
        """
        CREATE TRIGGER workspace_session_retirement_owner_guard
        BEFORE UPDATE OF cleanup_state ON workspace_terminal_session_ownership
        WHEN NEW.cleanup_state <> 'owned' AND (
            EXISTS (SELECT 1 FROM pane_content_terminal WHERE zmx_session_id = OLD.session_id)
            OR EXISTS (
                SELECT 1 FROM workspace_undo_close_member AS member
                JOIN workspace_undo_close AS operation ON operation.close_id = member.close_id
                WHERE member.session_id = OLD.session_id AND operation.state = 'available'
            )
        )
        BEGIN
            SELECT RAISE(ABORT, 'session still has an owner');
        END
        """,
        """
        CREATE TRIGGER workspace_session_delete_guard
        BEFORE DELETE ON workspace_terminal_session_ownership
        WHEN OLD.cleanup_state <> 'completed' OR EXISTS (
            SELECT 1 FROM pane_content_terminal WHERE zmx_session_id = OLD.session_id
        )
        BEGIN
            SELECT RAISE(ABORT, 'session still owned or cleanup unfinished');
        END
        """,
    ]
}
