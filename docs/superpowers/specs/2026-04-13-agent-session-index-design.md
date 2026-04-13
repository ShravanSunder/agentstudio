# Agent Session Index Design

## Status

Proposed design spec for review.

## Problem

AgentStudio embeds Ghostty terminals where users run AI coding agents (Claude Code, Codex CLI, and future providers). Today, AgentStudio has no awareness of what is happening inside those terminals at the agent session level. It cannot:

- Tell the user which pane is running an agent session, on which model, at what cost
- List recent agent sessions for a worktree or repo
- Let the user resume a previous session from within AgentStudio
- Show aggregate usage (tokens, cost, tool profile) across sessions
- Search session history by name or prompt content

Both Claude Code and Codex write structured session data to well-known locations on disk (`~/.claude/projects/`, `~/.codex/sessions/`). This data is the source of truth. AgentStudio needs to **index** it — not own it, not duplicate it, not modify it.

## Decision

Introduce a new `AgentSessionAtom` with SQLite-backed persistence (via GRDB) for session indexing. The index is a Tier B derived cache — rebuildable by scanning the agent data directories on disk. A dedicated `AgentSessionScanner` actor handles all I/O (directory scanning, JSONL parsing, file watching). Pure Swift, no Zig.

## Research Basis

### Data Sources

Both providers write JSONL session transcripts to predictable disk locations:

**Claude Code** (`~/.claude/`):
- Sessions: `~/.claude/projects/<encoded-cwd>/<uuid>.jsonl`
- Active session registry: `~/.claude/sessions/<pid>.json` (maps PID to sessionId + cwd)
- Path encoding: `/` replaced with `-` (e.g., `/home/user/myproject` becomes `-home-user-myproject`)
- Record types: `user`, `assistant`, `system`, `queue-operation`, `attachment`, `summary`
- Token data: `message.usage.{input_tokens, output_tokens, cache_creation_input_tokens, cache_read_input_tokens}`
- CWD tracking: `cwd` field on every record + `gitBranch` field
- Resume: `claude --resume <sessionId>` or `claude --continue <sessionId>`
- Real-time hooks: 28 lifecycle events, configurable in `settings.json`

**Codex CLI** (`~/.codex/`):
- Sessions: `~/.codex/sessions/YYYY/MM/DD/rollout-<id>.jsonl`
- Compressed archives: `.jsonl.zst` (ignored — only parse plain `.jsonl`)
- Record format: `RolloutLine` envelope with `type` + `payload` fields
- Record types: `SessionMeta`, `ResponseItem`, `EventMsg`
- Token data: delivered in `turn/completed` events (`input_tokens`, `cached_input_tokens`, `output_tokens`)
- CWD tracking: `cwd` in thread start, changes via command execution
- Resume: `codex resume <threadId>`
- Session model: Thread (container) → Turn (exchange) → Item (atomic unit)
- Metadata DB: SQLite at `~/.codex/` stores thread metadata

### Why SQLite (Not DuckDB)

| Criterion | SQLite | DuckDB |
|-----------|--------|--------|
| Binary size | 0 (system lib) | ~20 MB |
| Build time | Negligible (GRDB is Swift) | Compiles full C++ engine via SPM |
| Point lookups | Sub-ms B-tree | Slower, no efficient point index |
| Swift ecosystem | GRDB v7 (mature, async, reactive) | duckdb-swift (known perf issues at 10k-50k rows) |
| Startup | Sub-millisecond | ~100ms |
| FTS | FTS5 (battle-tested) | Young extension |
| Data volume | 10k-100k rows — well within SQLite's comfort zone | Overkill |

GRDB provides `ValueObservation` with `AsyncStream` — reactive DB observation that drives `@Observable` state without polling.

### Ecosystem Reference

Projects that do similar work, studied for patterns:

- **T3 Code** (pingdotgg/t3code): Wraps agent process directly via SDK, event-sourcing with SQLite projections. 45 canonical provider event types.
- **ccusage**: CLI that scans `~/.claude/projects/**/*.jsonl`, tracks by mtime for incremental re-index.
- **Mission Control**: Next.js + SQLite, auto-discovers `~/.claude/projects/`, 101 REST endpoints.
- **claude-devtools**: Per-turn token attribution, context window visualization.
- **Opcode**: Tauri 2 + Rust, full GUI wrapper with session time-travel.

## Architecture

### Component Placement

| Component | Location | Isolation |
|-----------|----------|-----------|
| `AgentSessionAtom` | `Core/State/MainActor/Atoms/` | `@MainActor @Observable` |
| `AgentSessionStore` | `Core/State/MainActor/Persistence/` | `@MainActor` (GRDB wrapper) |
| `AgentSessionScanner` | `Core/RuntimeEventSystem/Runtime/` | `actor` |
| `AgentSessionParser` | `Core/RuntimeEventSystem/Runtime/` | `nonisolated` (pure functions) |
| Session models | `Core/Models/` | `Sendable` value types |
| Provider-specific parsers | `Core/RuntimeEventSystem/Runtime/Parsers/` | `nonisolated` |

**Import rule compliance:** All components live in `Core/` or `Infrastructure/`. No `Features/` dependency. No `Core/ → Features/` import.

### Data Flow

```
~/.claude/projects/**/*.jsonl  ──┐
~/.codex/sessions/**/*.jsonl   ──┤
~/.claude/sessions/*.json      ──┘  (active session PID registry)
         │
         ▼
AgentSessionScanner (actor)
  ├── glob directories
  ├── compare mtime → indexed_at (skip unchanged)
  ├── parse JSONL headers + tails (provider-specific)
  ├── resolve worktreeId/repoId from CWD via topology atom
  ├── bulk INSERT/UPDATE into SQLite via AgentSessionStore
  └── emit RuntimeEnvelope.system(.agentSessionsIndexed(count))
         │
         ▼
PaneRuntimeEventBus
         │
         ▼
AgentSessionAtom (@MainActor @Observable)
  ├── activeSessions: [SessionKey: ActiveSessionState]      ← hot
  ├── recentByWorktree: [WorktreeId: [SessionSummary]]      ← warm cache
  └── query methods → GRDB DatabasePool                     ← on-demand
```

### Session Detection for Running Panes

A terminal pane can detect an agent session through multiple signals:

1. **Active session registry** — `~/.claude/sessions/<pid>.json` maps PID → sessionId + cwd. Poll periodically or watch with FSEvents.
2. **JSONL file watching** — new/growing `.jsonl` files in known directories indicate active sessions.
3. **CWD matching** — a pane's `worktreeId` → `worktree.path` → encoded path → `~/.claude/projects/<encoded>/`. If recent JSONL files exist there, sessions are associated.

Association is by CWD/worktree, not by process tree inspection — simpler, provider-agnostic, and works for sessions discovered after the fact.

### Multi-Worktree Association

A session can visit multiple worktrees over its lifetime (agent `cd`s to a different worktree). The `cwd` field changes in the JSONL records. The index tracks this:

- `session_worktrees` junction table: one row per (session, worktree) visited
- `is_primary` flag marks the starting worktree
- A session appears in queries for **every** worktree it touched
- `first_seen_at` / `last_seen_at` per association for ordering

CWD → worktree resolution uses `WorkspaceRepositoryTopologyAtom.repoAndWorktree(containing: cwd)`. CWDs that don't resolve to a known worktree are still tracked (the session happened, even if the folder isn't in the workspace).

## Data Model

### Core Types

```swift
enum AgentProvider: String, Codable, Sendable {
    case claudeCode
    case codex
}

struct SessionKey: Hashable, Codable, Sendable {
    let provider: AgentProvider
    let sessionId: String
}

enum SessionStatus: String, Codable, Sendable {
    case running        // process is alive, JSONL being appended
    case idle           // not running but resumable
    case completed      // agent finished normally
    case interrupted    // user stopped or process killed
}

struct SessionSummary: Sendable, Identifiable {
    let key: SessionKey
    let displayName: String?          // summary or thread name
    let firstPrompt: String?          // truncated, for search
    let status: SessionStatus
    let model: String?
    let createdAt: Date
    let lastActiveAt: Date
    let endedAt: Date?
    let turnCount: Int
    let totalInputTokens: Int64
    let totalOutputTokens: Int64
    let totalCacheReadTokens: Int64
    let estimatedCostUSD: Double?
    let filesModified: Int
    let linesAdded: Int
    let linesRemoved: Int
    let restoreCommand: String        // exact CLI to resume
    let transcriptPath: String        // absolute JSONL path on disk
    let transcriptSize: Int64

    var id: SessionKey { key }
}

struct ActiveSessionState: Sendable {
    let summary: SessionSummary
    let paneId: PaneId?               // which pane is running this (if known)
    let pid: Int?                     // OS process ID
    let contextWindowUsedPercent: Int?
    let currentModel: String?
    let lastToolUse: String?
    let updatedAt: Date
}

struct SessionWorktreeAssociation: Sendable {
    let worktreeId: WorktreeId
    let repoId: UUID
    let isPrimary: Bool
    let firstSeenAt: Date
    let lastSeenAt: Date
    let timeSpentMs: Int64
    let gitBranch: String?
    let cwdPaths: [String]            // distinct CWDs within this worktree
}

struct ToolUsage: Sendable {
    let toolName: String
    let useCount: Int
}

struct CostSummary: Sendable {
    let totalCostUSD: Double
    let totalInputTokens: Int64
    let totalOutputTokens: Int64
    let sessionCount: Int
    let topModels: [(model: String, cost: Double)]
}
```

### SQLite Schema

```sql
CREATE TABLE sessions (
    provider          TEXT NOT NULL,
    session_id        TEXT NOT NULL,
    display_name      TEXT,
    first_prompt      TEXT,
    status            TEXT NOT NULL DEFAULT 'idle',
    model             TEXT,
    created_at        REAL NOT NULL,
    last_active_at    REAL NOT NULL,
    ended_at          REAL,
    turn_count        INTEGER DEFAULT 0,
    total_input_tokens    INTEGER DEFAULT 0,
    total_output_tokens   INTEGER DEFAULT 0,
    total_cache_read_tokens INTEGER DEFAULT 0,
    estimated_cost_usd    REAL,
    files_modified    INTEGER DEFAULT 0,
    lines_added       INTEGER DEFAULT 0,
    lines_removed     INTEGER DEFAULT 0,
    restore_command   TEXT NOT NULL,
    transcript_path   TEXT NOT NULL,
    transcript_size   INTEGER DEFAULT 0,
    transcript_mtime  REAL,
    indexed_at        REAL NOT NULL,
    PRIMARY KEY (provider, session_id)
);

CREATE TABLE session_worktrees (
    provider        TEXT NOT NULL,
    session_id      TEXT NOT NULL,
    worktree_id     TEXT NOT NULL,
    repo_id         TEXT NOT NULL,
    is_primary      INTEGER NOT NULL DEFAULT 0,
    first_seen_at   REAL NOT NULL,
    last_seen_at    REAL NOT NULL,
    time_spent_ms   INTEGER DEFAULT 0,
    git_branch      TEXT,
    cwd_paths       TEXT,              -- JSON array
    PRIMARY KEY (provider, session_id, worktree_id),
    FOREIGN KEY (provider, session_id) REFERENCES sessions
);

CREATE TABLE session_tools (
    provider      TEXT NOT NULL,
    session_id    TEXT NOT NULL,
    tool_name     TEXT NOT NULL,
    use_count     INTEGER DEFAULT 0,
    PRIMARY KEY (provider, session_id, tool_name),
    FOREIGN KEY (provider, session_id) REFERENCES sessions
);

CREATE TABLE session_commits (
    provider      TEXT NOT NULL,
    session_id    TEXT NOT NULL,
    sha           TEXT NOT NULL,
    message       TEXT,
    created_at    REAL,
    PRIMARY KEY (provider, session_id, sha),
    FOREIGN KEY (provider, session_id) REFERENCES sessions
);

-- Query indexes
CREATE INDEX idx_sessions_last_active ON sessions(last_active_at DESC);
CREATE INDEX idx_sessions_status ON sessions(status);
CREATE INDEX idx_sw_worktree ON session_worktrees(worktree_id, last_seen_at DESC);
CREATE INDEX idx_sw_repo ON session_worktrees(repo_id, last_seen_at DESC);
CREATE INDEX idx_sw_branch ON session_worktrees(git_branch, repo_id);

-- FTS5 for command bar search
CREATE VIRTUAL TABLE sessions_fts USING fts5(
    display_name,
    first_prompt,
    content=sessions,
    content_rowid=rowid
);
```

### Atom Interface

```swift
@MainActor @Observable
final class AgentSessionAtom {
    // ═══ Hot — always in memory, drives reactive UI ═══

    /// Running sessions. Small (typically 0-5).
    /// Driven by GRDB ValueObservation on status='running'.
    private(set) var activeSessions: [SessionKey: ActiveSessionState] = [:]

    /// Recent sessions per visible worktree. Lazy-loaded as sidebar expands.
    /// Evicted when worktree collapses or tab switches away.
    private(set) var recentByWorktree: [WorktreeId: [SessionSummary]] = [:]

    // ═══ Warm — async queries against GRDB DatabasePool ═══

    func sessions(for worktreeId: WorktreeId, offset: Int, limit: Int) async -> [SessionSummary]
    func sessions(for repoId: UUID, offset: Int, limit: Int) async -> [SessionSummary]
    func sessions(branch: String, repoId: UUID, limit: Int) async -> [SessionSummary]
    func search(query: String, limit: Int) async -> [SessionSummary]
    func costSummary(since: Date) async -> CostSummary
    func toolProfile(for key: SessionKey) async -> [ToolUsage]
    func worktreeAssociations(for key: SessionKey) async -> [SessionWorktreeAssociation]
    func restoreCommand(for key: SessionKey) async -> String?

    // ═══ Lifecycle ═══

    /// Called by scanner when index changes. Refreshes hot state.
    func didUpdateIndex()

    /// Called when a worktree becomes visible in sidebar.
    func prefetchRecent(for worktreeId: WorktreeId)

    /// Called when worktree collapses or tab switches.
    func evictCache(for worktreeId: WorktreeId)
}
```

### Scanner Actor

```swift
actor AgentSessionScanner {
    private let store: AgentSessionStore
    private let topology: @MainActor () -> WorkspaceRepositoryTopologyAtom

    // ── Full scan (startup) ──

    func fullScan() async throws {
        let claudeSessions = try await scanClaudeDirectory()
        let codexSessions = try await scanCodexDirectory()
        try await store.bulkUpsert(claudeSessions + codexSessions)
    }

    // ── Incremental scan (periodic + file watch) ──

    func incrementalScan() async throws {
        // Only re-parse files with mtime > indexed_at
    }

    // ── Active session detection ──

    func scanActiveSessions() async throws {
        // Read ~/.claude/sessions/*.json (PID → sessionId + cwd)
        // Mark matching sessions as .running, others as .idle
    }

    // ── Blocking I/O on concurrent executor ──

    @concurrent nonisolated
    private func scanClaudeDirectory() async throws -> [ParsedSession] { ... }

    @concurrent nonisolated
    private func scanCodexDirectory() async throws -> [ParsedSession] { ... }

    @concurrent nonisolated
    private func parseClaudeJSONL(at path: URL, since offset: UInt64) async throws -> ParsedSession { ... }

    @concurrent nonisolated
    private func parseCodexJSONL(at path: URL, since offset: UInt64) async throws -> ParsedSession { ... }
}
```

### JSONL Parsing Strategy

**Do not parse entire transcripts.** Extract only the fields needed for the index:

For Claude Code:
1. First `user` record: `cwd`, `gitBranch`, `version`, `sessionId`, timestamp → `createdAt`, `primaryWorktree`
2. All `assistant` records: accumulate `message.usage.*` tokens, extract `message.model`, count `tool_use` blocks
3. All records: track `cwd` changes → build worktree association list
4. Last record: timestamp → `lastActiveAt`
5. `summary` records: extract `summary` text → `displayName`

For Codex:
1. First `SessionMeta` record: conversation ID, model, timestamp → `createdAt`
2. `ResponseItem` records: accumulate token counts, count tool items
3. `EventMsg` records: track CWD changes, user inputs
4. Last record: timestamp → `lastActiveAt`

**Incremental parsing:** Store the last-read byte offset per file. On re-scan, seek to offset and parse only new lines. This makes live session tracking efficient — only read the new tail.

### Persistence Tier

**Tier B** — derived cache, rebuildable from source JSONL files.

Location: `~/.agentstudio/workspaces/<workspace-id>/agent-sessions.db`

Per-workspace because `worktreeId` and `repoId` are workspace-scoped UUIDs. The session→worktree associations reference those UUIDs.

If the DB is deleted: `AgentSessionScanner.fullScan()` rebuilds everything from `~/.claude/` and `~/.codex/`.

### Reactive UI Binding (GRDB ValueObservation)

GRDB's `ValueObservation` drives `@Observable` state reactively. When the scanner inserts/updates rows, the atom's subscriptions fire automatically:

```swift
// Subscribe to active sessions — fires on any status change
let activeObservation = ValueObservation.tracking { db in
    try SessionRecord
        .filter(Column("status") == "running")
        .fetchAll(db)
}

// In atom setup
for try await records in activeObservation.values(in: dbPool) {
    self.activeSessions = records.toActiveSessionMap()
}
```

No polling. No manual event bus wiring for the DB→atom path. The scanner writes to SQLite, GRDB notifies the atom.

The `PaneRuntimeEventBus` is still used for **system-level facts** (e.g., "scan completed, N sessions indexed") that other coordinators may want to observe.

### Scan Scheduling

| Trigger | Action |
|---------|--------|
| App startup | Full scan (compare all mtimes) |
| FSEvents on `~/.claude/projects/` | Incremental scan (changed files only) |
| FSEvents on `~/.codex/sessions/` | Incremental scan (changed files only) |
| FSEvents on `~/.claude/sessions/` | Active session detection (PID registry) |
| Every 30s while app is active | Active session detection (PID registry) |
| Workspace topology change (repo/worktree added) | Re-resolve worktree associations for unresolved CWDs |

### Restore Commands

Stored as the exact CLI invocation string:

| Provider | Command Template |
|----------|-----------------|
| Claude Code | `claude --resume <sessionId>` |
| Claude Code (continue) | `claude --continue <sessionId>` |
| Codex | `codex resume <threadId>` |

The atom provides `restoreCommand(for:)`. The UI can offer "Resume in this pane" which feeds the command to the pane's terminal via the existing zmx/Ghostty input path.

## What This Does Not Cover

- **SDK wrapping** — this design reads JSONL files, it does not spawn or control agent processes. That is a separate, higher-complexity integration (T3 Code's approach).
- **Real-time hooks** — Claude Code's hooks system (28 events, HTTP POST) could provide richer live data. This is an additive enhancement on top of the file-based index, not a replacement. Can be added later.
- **OTLP telemetry** — Claude Code's built-in OpenTelemetry export is another live data source. Same story — additive, later.
- **Compressed archives** — Codex's `.jsonl.zst` files are ignored. Only plain `.jsonl` is parsed. This covers all active and recent sessions.
- **Agent as a pane content type** — `PaneContentType.agent` already exists as a reserved enum case. Wiring it to the session index is future work that depends on this index existing first.
- **Cost estimation pricing** — initial version can use hardcoded per-model rates (like ccusage does) or skip cost entirely and just show token counts.

## Open Questions

1. **Should the scanner run in a `TaskGroup` for parallel JSONL parsing?** At 100k files this helps. At 100 files it doesn't matter. Start sequential, measure, parallelize if slow.
2. **Should `AgentSessionAtom` live in `AtomStore`?** It has a different lifecycle (requires DB setup before atom creation). May need a separate initialization path.
3. **Per-workspace vs global DB?** Spec says per-workspace. But a user might want "show me all sessions across all workspaces." A global DB with workspace-id column is an alternative.
4. **How to handle CWDs that don't resolve to any known worktree?** Store with `worktree_id = NULL` in `session_worktrees`? Or a separate `session_unresolved_cwds` table?
