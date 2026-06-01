# Agent Session Index Design

## Status

Spec aligned with the `sqlite` branch architecture (`00-persistence-boundaries.md` through `07-session-index-brainstorm.md`). Adversarially reviewed.

## Problem

AgentStudio embeds Ghostty terminals where users run AI coding agents (Claude Code, Codex CLI). AgentStudio has no awareness of what happens at the agent session level. It cannot list sessions, show costs, search history, or help the user resume a session.

Both providers write structured JSONL transcripts to well-known disk locations. AgentStudio needs to **index** this data — not own it, not duplicate it.

## Decision

### Session Pointers → `core.sqlite`

User curation is durable product truth:

```sql
session_pointer (in core.sqlite)
  → "I care about this session"
  → pin, archive, alias, notes, preferred restore command
  → loss = user loses curation that cannot be reconstructed
```

This extends the existing `WorkspaceCoreRepository` with a new migration and new methods.

### Session Index → `<workspace-id>.local.sqlite` (`index_*` tables)

Provider-discovered facts are rebuildable from JSONL. They live in the
per-workspace local database using the `index_*` prefix convention established
in `02-local-ux-and-cache-schema.md`:

```
index_session                    → provider facts from scanning
index_session_cwd_observation    → every CWD change observed
index_session_worktree_match     → resolved worktree associations
index_session_tool_usage         → tool histograms
index_session_relationship_fact  → fork/parent relationships
index_transcript_scan_state      → byte offsets, mtimes, scan errors
index_session_search_fts         → standalone FTS5 search
```

**Why `local.sqlite`, not a separate DB:**

The sqlite branch decided this in `00-persistence-boundaries.md`, `02-local-ux-and-cache-schema.md`, and `07-session-index-brainstorm.md`. A separate `index.sqlite` was considered and rejected because:

- One fewer `DatabasePool` to manage per workspace lifecycle
- Cross-table queries with `cache_*` data are possible (e.g., enriched worktree names)
- Workspace delete/backup/export manages two files, not three
- The `index_*` prefix convention already provides logical separation
- Reset rule: `DELETE FROM index_*` rebuilds the index without touching `local_*` or `cache_*` rows
- Index migration failure is handled defensively (try/catch, degrade gracefully) rather than with file isolation

**Location:** `<AppDataPaths.workspacesDirectory()>/<workspace-id>.local.sqlite`

**Migrations:** Registered in `WorkspaceLocalMigrations` (e.g., `005_create_session_index`), not a separate migrator.

**Loss semantics:** `DELETE FROM index_*` triggers a full re-scan. `DELETE local.sqlite` loses cursor/cache AND index — cursor/cache loss is annoying but not destructive (per existing contract), index is rebuildable. Core session pointers survive independently in `core.sqlite`.

## Data Flow

### Write Path: Scanner → Index DB → Atom

```
AgentSessionScanner (actor)
  ├── discoverFiles()                    @concurrent nonisolated
  ├── parseClaudeJSONL(at:since:)        @concurrent nonisolated
  ├── parseCodexJSONL(at:since:)         @concurrent nonisolated (future)
  │
  ├── fullScan()                         actor-isolated
  │   └── discover → filter by mtime → parse → collect raw CWDs
  │       └── AgentSessionIndexRepository.upsertBatch() (off MainActor)
  │           └── returns committed results
  │
  └── emit RuntimeEnvelope.system(.agentSessionsIndexed(count:))
      └── PaneRuntimeEventBus
          └── coordinator subscribes
              └── coordinator tells atom to refresh from DB
```

This follows the sqlite branch's core pattern:
```
repository writes one SQLite transaction off MainActor
  → repository returns committed domain result
  → coordinator applies result to @MainActor atoms
```

The difference: for session index, the "mutation" originates from the scanner (external data discovery), not from a user action. But the flow is the same — DB-first, atom projects committed result.

### Write Path: User Curation → Core DB → Atom

```
User pins/archives/aliases a session
  → PaneActionCommand (validated)
  → WorkspaceMutationCoordinator
  → WorkspaceCoreRepository.upsertSessionPointer() (off MainActor)
  → coordinator applies committed result to atom
```

This is identical to any other core workspace mutation.

### Read Path: Atom → DB

```
AgentSessionAtom (@MainActor @Observable)
  ├── activeSessions     ← hot, refreshed on scanner notification
  ├── recentByWorktree   ← warm, lazy-loaded per visible worktree
  └── query methods delegate to AgentSessionReadHandler
       └── reads from local.sqlite (shared DatabasePool, concurrent reads)
```

### ValueObservation (Limited, Approved Use)

The sqlite branch spec 05 explicitly lists session index as an approved ValueObservation use:

> Good future ValueObservation uses:
> - visible session search results
> - active session summaries
> - recent sessions for a selected worktree
> - cost/token aggregates

ValueObservation drives **only** the hot `activeSessions` state (small result set, changes infrequently). All other reads go through the read handler on demand. ValueObservation is NOT used for core workspace UI — that follows the coordinator → atom projection pattern.

## Component Placement

| Component | Location | Isolation | Pattern |
|-----------|----------|-----------|---------|
| `AgentSessionIndexRepository` | `Core/State/MainActor/Persistence/` | `struct`, Sendable | Same as `WorkspaceCoreRepository` |
| `AgentSessionReadHandler` | `Core/State/MainActor/Persistence/` | `struct`, Sendable | Owns read queries + ValueObservation factories |
| `AgentSessionAtom` | `Core/State/MainActor/Atoms/` | `@MainActor @Observable` | Hot state only |
| `AgentSessionScanner` | `Core/RuntimeEventSystem/Runtime/` | `actor` | I/O + parsing |
| Session parsers | `Core/RuntimeEventSystem/Runtime/Parsers/` | `nonisolated` | Pure functions |
| Session models | `Core/Models/` | `Sendable` value types | — |
| Index migrations | extends `WorkspaceLocalMigrations` | — | Same migrator, new migration ID |
| `session_pointer` migration | extends `WorkspaceCoreMigrations` | — | Existing pattern |

**Import rule compliance:** Everything in `Core/` or `Infrastructure/`. No `Features/` dependency.

### Table-Level Write Ownership

Two components write to `index_*` tables. Explicit ownership prevents races:

| Table | Write Owner | Reason |
|-------|-------------|--------|
| `index_session` | Scanner | Provider facts from JSONL parsing |
| `index_session_cwd_observation` | Scanner | Raw CWD observations from transcripts |
| `index_session_tool_usage` | Scanner | Tool histograms from transcripts |
| `index_session_relationship_fact` | Scanner | Fork/parent from transcripts |
| `index_transcript_scan_state` | Scanner | Byte offsets, mtimes, errors |
| `index_session_search_fts` | Scanner | Rebuilt after each session upsert |
| `index_session_worktree_match` | Coordinator | CWD→worktree resolution requires topology atom |
| `index_session.session_pointer_id` | Coordinator | Reconciles with core session_pointer |

Scanner writes happen off MainActor inside the actor. Coordinator writes happen on MainActor after resolving CWDs against topology. These never race because they own different columns/tables.

## Repository Pattern (Following Existing Code)

The sqlite branch uses `struct` repositories with `any DatabaseWriter`, raw SQL, and manual `Row` decoding. No GRDB `Record` types. The session index follows this exactly:

```swift
struct AgentSessionIndexRepository {
    // Shares the same DatabaseWriter as WorkspaceLocalRepository
    // (both point to <workspace-id>.local.sqlite)
    let workspaceId: UUID
    let databaseWriter: any DatabaseWriter

    // ── Scanner writes (off MainActor) ──

    func upsertSession(_ record: IndexSessionRecord) throws { ... }
    func upsertBatch(_ records: [IndexSessionRecord]) throws { ... }
    func updateStatus(_ key: SessionKey, status: SessionStatus) throws { ... }
    func upsertCWDObservation(_ obs: CWDObservationRecord) throws { ... }
    func upsertToolUsage(_ usage: [ToolUsageRecord]) throws { ... }
    func upsertScanState(_ state: TranscriptScanStateRecord) throws { ... }
    func rebuildFTSRow(for key: SessionKey) throws { ... }

    // rebuildFTSRow must be called after upsertSession, upsertToolUsage,
    // and upsertCWDObservation for the same session key. The scanner
    // should call it once at the end of a session upsert batch.

    // ── Coordinator writes (on MainActor, via await) ──

    func upsertWorktreeMatch(_ match: WorktreeMatchRecord) throws { ... }
    func attachSessionPointer(_ pointerId: String, to key: SessionKey) throws { ... }
    func detachSessionPointer(from key: SessionKey) throws { ... }
    func pruneOrphanedWorktreeMatches(validIds: Set<UUID>) throws { ... }

    // ── Rebuild ──

    func deleteAllIndexRows() throws { ... }  // DELETE FROM index_* (preserves local_*/cache_*)
}
```

```swift
struct AgentSessionReadHandler {
    // Same DatabaseWriter as the index repository
    let databaseWriter: any DatabaseWriter

    // ── Queries (called from atom or command bar) ──

    func sessions(forWorktree id: UUID, limit: Int) throws -> [SessionSummary] { ... }
    func sessions(forRepo id: UUID, limit: Int) throws -> [SessionSummary] { ... }
    func search(query: String, limit: Int) throws -> [SessionSummary] { ... }
    func costSummary(since: Date) throws -> CostSummary { ... }
    func scanState(forPath path: String) throws -> TranscriptScanStateRecord? { ... }
    func unresolvedCWDObservations() throws -> [CWDObservationRecord] { ... }

    // "Unresolved" = CWD observation where no matching row exists in
    // index_session_worktree_match for (provider, provider_session_id, cwd_path)

    // ── Observation factories (approved per spec 05) ──

    func activeSessionsObservation() -> ValueObservation<[IndexSessionRecord]> { ... }
}
```

## Schema

### `core.sqlite` Addition

```sql
-- New migration in WorkspaceCoreMigrations
CREATE TABLE session_pointer (
    id TEXT PRIMARY KEY,
    workspace_id TEXT NOT NULL REFERENCES workspace(id) ON DELETE CASCADE,
    provider TEXT NOT NULL,
    provider_session_id TEXT NOT NULL,
    display_alias TEXT,
    user_note TEXT,
    preferred_restore_command TEXT,
    pinned INTEGER NOT NULL DEFAULT 0,
    archived_at REAL,
    created_at REAL NOT NULL,
    updated_at REAL NOT NULL,
    UNIQUE(workspace_id, provider, provider_session_id)
);
```

### `<workspace-id>.local.sqlite` — Index Tables

```sql
-- WorkspaceLocalMigrations: 005_create_session_index

CREATE TABLE index_session (
    workspace_id TEXT NOT NULL,
    provider TEXT NOT NULL,
    provider_session_id TEXT NOT NULL,
    provider_thread_id TEXT,
    session_pointer_id TEXT,
    display_name TEXT,
    provider_summary TEXT,
    first_prompt_snippet TEXT,
    status TEXT NOT NULL DEFAULT 'idle',
    model TEXT,
    created_at REAL,
    last_active_at REAL NOT NULL,
    ended_at REAL,
    turn_count INTEGER NOT NULL DEFAULT 0,
    total_input_tokens INTEGER NOT NULL DEFAULT 0,
    total_output_tokens INTEGER NOT NULL DEFAULT 0,
    total_cache_read_tokens INTEGER NOT NULL DEFAULT 0,
    estimated_cost_usd REAL,
    restore_command TEXT NOT NULL,
    transcript_path TEXT NOT NULL,
    indexed_at REAL NOT NULL,
    PRIMARY KEY(provider, provider_session_id),
    CHECK(status IN ('running', 'idle', 'completed', 'interrupted'))
);

CREATE TABLE index_session_cwd_observation (
    id TEXT PRIMARY KEY,
    workspace_id TEXT NOT NULL,
    provider TEXT NOT NULL,
    provider_session_id TEXT NOT NULL,
    cwd_path TEXT NOT NULL,
    observed_at REAL NOT NULL,
    source TEXT NOT NULL,
    FOREIGN KEY(provider, provider_session_id)
        REFERENCES index_session(provider, provider_session_id)
        ON DELETE CASCADE
);

CREATE INDEX idx_index_cwd_obs_session
    ON index_session_cwd_observation(provider, provider_session_id);

CREATE TABLE index_session_worktree_match (
    workspace_id TEXT NOT NULL,
    provider TEXT NOT NULL,
    provider_session_id TEXT NOT NULL,
    repo_id TEXT,
    worktree_id TEXT,
    cwd_path TEXT NOT NULL,
    is_primary INTEGER NOT NULL DEFAULT 0,
    first_seen_at REAL NOT NULL,
    last_seen_at REAL NOT NULL,
    git_branch TEXT,
    PRIMARY KEY(provider, provider_session_id, cwd_path),
    FOREIGN KEY(provider, provider_session_id)
        REFERENCES index_session(provider, provider_session_id)
        ON DELETE CASCADE
);

CREATE TABLE index_session_tool_usage (
    workspace_id TEXT NOT NULL,
    provider TEXT NOT NULL,
    provider_session_id TEXT NOT NULL,
    tool_name TEXT NOT NULL,
    use_count INTEGER NOT NULL DEFAULT 0,
    PRIMARY KEY(provider, provider_session_id, tool_name),
    FOREIGN KEY(provider, provider_session_id)
        REFERENCES index_session(provider, provider_session_id)
        ON DELETE CASCADE
);

CREATE TABLE index_session_relationship_fact (
    workspace_id TEXT NOT NULL,
    provider TEXT NOT NULL,
    provider_session_id TEXT NOT NULL,
    relationship_kind TEXT NOT NULL,
    related_provider TEXT NOT NULL,
    related_provider_session_id TEXT NOT NULL,
    source TEXT NOT NULL,
    observed_at REAL NOT NULL,
    PRIMARY KEY(
        provider, provider_session_id,
        relationship_kind,
        related_provider, related_provider_session_id
    ),
    FOREIGN KEY(provider, provider_session_id)
        REFERENCES index_session(provider, provider_session_id)
        ON DELETE CASCADE
);

CREATE TABLE index_transcript_scan_state (
    transcript_path TEXT PRIMARY KEY,
    workspace_id TEXT NOT NULL,
    provider TEXT NOT NULL,
    transcript_mtime REAL,
    transcript_size INTEGER NOT NULL DEFAULT 0,
    indexed_byte_offset INTEGER NOT NULL DEFAULT 0,
    last_scanned_at REAL NOT NULL,
    last_error TEXT
);

-- Standalone FTS5 (NOT content= external content)
-- Delete-then-insert upsert. Rebuildable projection.
CREATE VIRTUAL TABLE index_session_search_fts USING fts5(
    provider UNINDEXED,
    provider_session_id UNINDEXED,
    display_name,
    provider_summary,
    first_prompt_snippet,
    tool_names,
    cwd_paths,
    tokenize = 'unicode61'
);

-- Query indexes
CREATE INDEX idx_index_session_last_active
    ON index_session(last_active_at DESC);
CREATE INDEX idx_index_session_status
    ON index_session(status);
CREATE INDEX idx_index_session_pointer
    ON index_session(session_pointer_id)
    WHERE session_pointer_id IS NOT NULL;
CREATE INDEX idx_index_swm_worktree
    ON index_session_worktree_match(worktree_id, last_seen_at DESC);
CREATE INDEX idx_index_swm_repo
    ON index_session_worktree_match(repo_id, last_seen_at DESC);
CREATE INDEX idx_index_swm_branch
    ON index_session_worktree_match(git_branch, repo_id);
CREATE INDEX idx_index_scan_state_provider
    ON index_transcript_scan_state(provider, workspace_id);
```

### FTS5 Upsert Pattern (Standalone)

```swift
func rebuildFTSRow(for key: SessionKey) throws {
    try databaseWriter.write { db in
        // Delete old search document
        try db.execute(sql: """
            DELETE FROM index_session_search_fts
            WHERE provider = ? AND provider_session_id = ?
            """, arguments: [key.provider.rawValue, key.sessionId])

        // Build search document from index tables
        guard let session = try Row.fetchOne(db, sql: """
            SELECT display_name, provider_summary, first_prompt_snippet
            FROM index_session
            WHERE provider = ? AND provider_session_id = ?
            """, arguments: [key.provider.rawValue, key.sessionId])
        else { return }

        let toolNames = try String.fetchAll(db, sql: """
            SELECT tool_name FROM index_session_tool_usage
            WHERE provider = ? AND provider_session_id = ?
            """, arguments: [key.provider.rawValue, key.sessionId])
            .joined(separator: " ")

        let cwdPaths = try String.fetchAll(db, sql: """
            SELECT DISTINCT cwd_path FROM index_session_cwd_observation
            WHERE provider = ? AND provider_session_id = ?
            """, arguments: [key.provider.rawValue, key.sessionId])
            .joined(separator: " ")

        // Insert rebuilt search document
        try db.execute(sql: """
            INSERT INTO index_session_search_fts(
                provider, provider_session_id,
                display_name, provider_summary, first_prompt_snippet,
                tool_names, cwd_paths
            ) VALUES (?, ?, ?, ?, ?, ?, ?)
            """, arguments: [
                key.provider.rawValue, key.sessionId,
                session["display_name"], session["provider_summary"],
                session["first_prompt_snippet"], toolNames, cwdPaths,
            ])
    }
}
```

## Boot Sequence Integration

Session index initializes during workspace boot. Concrete ordering:

```
WorkspaceBootSequence:
  step 1: loadCanonicalStore (core.sqlite + local.sqlite opened)
  step 2: loadRepoCacheStore
  step 3: loadUIStore
  step 4: ← NEW: initSessionIndex
          - local.sqlite already open (shared DatabaseWriter)
          - run index_* migrations (005+) via WorkspaceLocalMigrations
          - create AgentSessionIndexRepository (shares local DatabaseWriter)
          - create AgentSessionReadHandler (shares local DatabaseWriter)
          - create AgentSessionAtom (with read handler)
          - start ValueObservation for active sessions
  step 5-8: (existing steps)
  step 9: triggerInitialTopologySync
  step 10: ← NEW: startSessionScanner
          - create AgentSessionScanner (with index repository)
          - trigger fullScan() (async, does not block boot)
          - start FSEvents watchers
          - scanner emits .agentSessionsIndexed when done
          - coordinator resolves CWDs against now-populated topology
```

If `index_*` migration fails: log error, proceed without session index. The
atom exposes empty state. The scanner does not start. Session features degrade
gracefully — no crash, no data loss.

## Scanner Lifecycle

One scanner per workspace. Created at boot step 10, shut down on workspace close.

The scanner watches global directories (`~/.claude/projects/`, `~/.codex/sessions/`)
but filters discovered sessions to those whose CWDs fall within this workspace's
known repos/worktrees. Sessions with CWDs outside the workspace are still indexed
(they may be resolved later when a new folder is added), but they are lower
priority.

On workspace close: cancel FSEvents watchers, cancel pending scans, let the actor
deinit. The shared `local.sqlite` DatabaseWriter remains open for other components.

## CWD → Worktree Resolution

Parsers return raw CWDs. Resolution happens **after** scan completes, on MainActor where topology is accessible:

```
Scanner (actor):
  parse JSONL → collect [(cwd: URL, timestamp: Date)] per session
  write index_session + index_session_cwd_observation to DB

Coordinator (MainActor):
  receives .agentSessionsIndexed fact from bus
  reads unresolved CWD observations from DB
  resolves each CWD via WorkspaceRepositoryTopologyAtom.repoAndWorktree(containing:)
  writes index_session_worktree_match rows back to DB
  projects committed results into atom
```

On topology change (worktree added/removed): coordinator re-resolves unmatched CWDs.

## Session Pointer ↔ Index Reconciliation

No cross-DB foreign keys. Soft references with concrete reconciliation triggers:

### Attachment triggers

| Event | Who | Action |
|-------|-----|--------|
| Scanner indexes a new session | Coordinator (after scan fact) | Query `core.sqlite` for `session_pointer` matching `(workspace_id, provider, provider_session_id)`. If found, write `session_pointer_id` into `index_session`. |
| User creates a session pointer (pin/alias) | Coordinator (after core mutation) | Write `session_pointer_id` into matching `index_session` row in `local.sqlite`. |
| User deletes a session pointer | Coordinator (after core mutation) | Clear `session_pointer_id` in matching `index_session` row. |
| Index rebuilt (`DELETE FROM index_*` + re-scan) | Coordinator (after scan fact) | Re-query all `session_pointer` rows from `core.sqlite`, attach matching `session_pointer_id` values. |

### Restore command precedence

```
session_pointer.preferred_restore_command (if set)
  → otherwise index_session.restore_command (provider-derived)
```

Resolved at read time by the read handler joining both sources. The provider-derived
command is never overwritten — it remains useful if the user clears their override.

## Stale Session Pruning

| Condition | Action |
|-----------|--------|
| Transcript file no longer exists on disk | Scanner marks `index_transcript_scan_state.last_error = 'file_not_found'`. Session status set to `completed`. Session kept in index (historical value). |
| `seek offset > file size` (file truncated/rewritten) | Scanner resets `indexed_byte_offset = 0` and does a full rescan of the file. |
| Workspace topology prune (worktree removed) | Coordinator calls `pruneOrphanedWorktreeMatches(validIds:)`. CWD observations and index_session rows are preserved (the session happened, even if the worktree is gone). |
| No growth limit in v1 | Acceptable for <100k sessions. If needed later: prune sessions older than N months where `session_pointer_id IS NULL` (no user curation). |

## JSONL Parsing

### Incremental Tail Parsing

`index_transcript_scan_state` tracks per-file byte offset:

1. Check `transcript_mtime` — skip unchanged files
2. Seek to `indexed_byte_offset` — read only new lines
3. If last line fails JSON decode → skip it (likely partial write from active session)
4. Update `indexed_byte_offset` and `last_scanned_at`
5. If parse error → store in `last_error`, don't abort

### Per-Line Error Handling

Each JSONL line is independently try/catch. A malformed line skips without aborting the file. `last_error` in scan state records the most recent per-line error for diagnostics.

### Concurrent Read/Write Safety

Agent writes JSONL while scanner reads. On APFS, reads see consistent file content but the scanner may read a partial last line. The parser skips the last line on JSON decode failure and re-reads it on the next scan (the byte offset excludes the partial line).

## Scan Scheduling

| Trigger | Action |
|---------|--------|
| App startup (after boot step 3, before topology sync) | Full scan (compare all mtimes) |
| FSEvents on `~/.claude/projects/` | Incremental scan (changed files only) |
| FSEvents on `~/.codex/sessions/` | Incremental scan (future, Codex parser) |
| FSEvents on `~/.claude/sessions/` | Active session detection (PID registry) |
| Every 30s while app is active | Active session detection |
| Topology change (worktree added/removed) | Re-resolve unmatched CWDs |

FSEvents uses the existing `DarwinFSEventStreamClient` pattern, not `DispatchSource`. Debounce: coalesce events within 1s window.

If `~/.claude/` doesn't exist: skip, don't create a watcher. Check periodically (every 5m) if the directory appears.

## What This Does Not Cover

- Codex parser (follow-up — schema supports it, parser deferred)
- Compressed archives (.jsonl.zst) — skip
- Hooks/statusline/OTLP live integration — additive later
- SDK wrapping / ACP — not using
- Sidebar UI, command bar integration, drawer panel — separate specs
- Cost estimation pricing tables — hardcode or skip for v1
- Multi-agent orchestration — future

## Resolved Questions

1. **Boot sequence ordering.** ← Resolved: step 4 (initSessionIndex) and step 10 (startSessionScanner). See Boot Sequence Integration section.
2. **Separate DB vs local.sqlite.** ← Resolved: `local.sqlite` with `index_*` prefix tables, as the sqlite branch decided.
3. **Unresolvable CWDs.** ← Resolved: store in `index_session_worktree_match` with `worktree_id = NULL` and `repo_id = NULL`. The row still tracks the `cwd_path` and `is_primary` flag. Re-resolved when topology changes.

## Open Questions

1. **Atom registration.** Does `AgentSessionAtom` go in `AtomRegistry`? It depends on the read handler which depends on the DB. May need lazy initialization or a two-phase setup (create atom with nil handler, inject handler at boot step 4).
2. **Cross-workspace session visibility.** A user may want "all my sessions globally." Per-workspace index can't answer this without scanning all workspace DBs. Acceptable for v1? (Yes — defer global view.)
3. **CWD observation `source` values.** What are the valid values? Proposal: `transcript_record_cwd` (from the cwd field on each JSONL record), `transcript_tool_cwd` (from tool-use blocks with explicit cwd). Needs a CHECK constraint or documented enum.
4. **Scanner filtering.** The scanner watches global `~/.claude/` but each workspace has its own index. Should all discovered sessions be indexed in every open workspace, or only sessions whose CWDs overlap with the workspace's known repos? The former is simpler but duplicates work. The latter requires filtering but gives cleaner per-workspace results.
