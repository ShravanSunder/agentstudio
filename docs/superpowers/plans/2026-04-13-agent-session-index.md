# Agent Session Index Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a queryable index of AI coding agent sessions (Claude Code first, Codex follow-up) integrated with AgentStudio's workspace/worktree model. Full vertical slice: index + sidebar + live detection.

**Design Spec:** [2026-04-13-agent-session-index-design.md](../specs/2026-04-13-agent-session-index-design.md)

**Depends On:** `sqlite` branch merged (GRDB, WorkspaceCoreRepository, WorkspaceLocalRepository, migration system)

**Tech Stack:** Swift 6.2, macOS 26, GRDB v7, `@MainActor` atom, `actor` scanner, `@concurrent nonisolated` I/O, Swift Testing, mise

---

## Phase 1: Models and Schema

### Task 1.1: Session data models

Create in `Core/Models/`:

- [ ] `AgentProvider.swift` — `enum AgentProvider: String, Codable, Sendable { case claudeCode, codex }`
- [ ] `SessionKey.swift` — `struct SessionKey: Hashable, Codable, Sendable { provider, sessionId }`
- [ ] `SessionStatus.swift` — `enum SessionStatus: String, Codable, Sendable { case running, idle, completed, interrupted }`
- [ ] `SessionSummary.swift` — lightweight read model for UI (from index_session + optional pointer join)
- [ ] `ActiveSessionState.swift` — extends summary with live paneId, pid, context window
- [ ] `SessionWorktreeMatch.swift` — resolved worktree association
- [ ] `CWDObservation.swift` — raw CWD observation from transcript
- [ ] `ToolUsage.swift` — tool name + count
- [ ] `CostSummary.swift` — aggregate stats
- [ ] `TranscriptScanState.swift` — per-file scan state with byte offset

### Task 1.2: Index DB migrations

Create `AgentSessionIndexMigrations` in `Core/State/MainActor/Persistence/`:

- [ ] `AgentSessionIndexMigrations.swift` — static migrator following `WorkspaceCoreMigrations` pattern
- [ ] Migration 001: all `index_*` tables, indexes, standalone FTS5 table (see spec schema)
- [ ] Write unit tests: migration creates tables, verify table structure

### Task 1.3: Core DB migration for session_pointer

Extend existing `WorkspaceCoreMigrations`:

- [ ] Add migration for `session_pointer` table (see spec schema)
- [ ] Write unit test: migration adds table, basic CRUD

### Task 1.4: Test fixtures

- [ ] Create sample Claude Code JSONL files (small, representative, covering: user, assistant, summary, tool_use records)
- [ ] Create sample `~/.claude/sessions/<pid>.json` PID registry file
- [ ] All fixtures in test resources directory

---

## Phase 2: Repository Layer

### Task 2.1: AgentSessionIndexRepository (writes)

Create in `Core/State/MainActor/Persistence/`:

- [ ] `AgentSessionIndexRepository.swift` — `struct` with `any DatabaseWriter`
- [ ] `migrate()` — delegates to `AgentSessionIndexMigrations`
- [ ] `upsertSession()` — INSERT OR REPLACE with raw SQL
- [ ] `upsertBatch()` — wraps multiple upserts in one transaction
- [ ] `updateStatus()` — point update by (provider, session_id)
- [ ] `upsertCWDObservation()` — append CWD observation
- [ ] `upsertWorktreeMatch()` — resolved worktree association
- [ ] `upsertToolUsage()` — tool histogram upsert
- [ ] `upsertScanState()` — per-file scan state with byte offset
- [ ] `rebuildFTSRow()` — standalone FTS5 delete-then-insert in one transaction
- [ ] `pruneOrphanedWorktreeMatches()` — clean up invalid worktree references
- [ ] `attachSessionPointer()` / `detachSessionPointer()` — soft reference to core
- [ ] Write unit tests for each method

### Task 2.2: AgentSessionReadHandler (reads)

Create in `Core/State/MainActor/Persistence/`:

- [ ] `AgentSessionReadHandler.swift` — `struct` with `any DatabaseWriter`
- [ ] `sessions(forWorktree:limit:)` — JOIN index_session_worktree_match, ORDER BY last_active_at DESC
- [ ] `sessions(forRepo:limit:)` — same with repo_id
- [ ] `sessions(branch:repoId:limit:)` — filter by git_branch
- [ ] `activeSessions()` — WHERE status = 'running'
- [ ] `search(query:limit:)` — FTS5 MATCH on standalone table, ORDER BY rank
- [ ] `costSummary(since:)` — SUM aggregation
- [ ] `toolProfile(for:)` — fetch from index_session_tool_usage
- [ ] `scanState(forPath:)` — check index_transcript_scan_state
- [ ] `unresolvedCWDObservations()` — CWDs with no worktree_match yet
- [ ] `activeSessionsObservation()` — ValueObservation factory (approved use)
- [ ] Write unit tests for each query

### Task 2.3: Core repository extension for session_pointer

Extend `WorkspaceCoreRepository`:

- [ ] `upsertSessionPointer()` — pin, archive, alias, notes, preferred restore command
- [ ] `deleteSessionPointer()` — remove curation
- [ ] `fetchSessionPointers(forWorkspace:)` — list curated sessions
- [ ] Write unit tests

---

## Phase 3: JSONL Parsing

### Task 3.1: Parsed session intermediate type

- [ ] `ParsedSession.swift` in `Core/Models/` — provider-agnostic result of parsing a JSONL file
- [ ] Carries: all index_session fields + raw CWD observations + tool usage counts
- [ ] `toIndexSessionRecord()` conversion
- [ ] `toCWDObservations()` conversion
- [ ] `toToolUsageRecords()` conversion

### Task 3.2: Claude Code JSONL parser

Create `ClaudeSessionParser.swift` in `Core/RuntimeEventSystem/Runtime/Parsers/`:

- [ ] `@concurrent nonisolated func parseClaudeJSONL(at: URL, since offset: UInt64) async throws -> ParsedSession`
- [ ] Lightweight `Decodable` structs — only decode fields needed
- [ ] Seek to byte offset for incremental parsing
- [ ] Per-line try/catch — skip malformed lines, don't abort file
- [ ] Skip last line on JSON decode failure (partial write from active session)
- [ ] Extract: sessionId, cwd, gitBranch, model, token usage, tool_use counts, summary, first prompt
- [ ] Track CWD changes → build CWDObservation list
- [ ] Build restore command: `"claude --resume <sessionId>"`
- [ ] Return `(ParsedSession, newByteOffset: UInt64)`
- [ ] Write unit tests with fixture JSONL files

### Task 3.3: Codex JSONL parser

Create `CodexSessionParser.swift` in `Core/RuntimeEventSystem/Runtime/Parsers/`:

- [ ] `@concurrent nonisolated func parseCodexJSONL(at: URL, since offset: UInt64) async throws -> ParsedSession`
- [ ] Parse `RolloutLine` envelope format: `{"type": "...", "payload": {...}}`
- [ ] Extract from `SessionMeta`: conversation_id, model, timestamp
- [ ] Extract from `ResponseItem`: accumulate tokens, count tool items (command_execution, file_change, mcp_tool_call)
- [ ] Extract from `EventMsg`: track CWD changes, extract first user input
- [ ] Skip `.jsonl.zst` files (compressed archives)
- [ ] Build restore command: `"codex resume <threadId>"`
- [ ] Return `(ParsedSession, newByteOffset: UInt64)`
- [ ] Write unit tests with fixture Codex JSONL files

### Task 3.4: Codex test fixtures

- [ ] Create sample Codex JSONL files (SessionMeta + ResponseItem + EventMsg records)
- [ ] Cover: normal session, multi-turn, tool usage, CWD changes

---

## Phase 4: Scanner Actor

### Task 4.1: Directory discovery

Create `AgentSessionScanner.swift` in `Core/RuntimeEventSystem/Runtime/`:

- [ ] `actor AgentSessionScanner`
- [ ] Resolve Claude paths: `~/.claude/projects/` (also check `~/.config/claude/projects/`)
- [ ] Resolve Codex paths: `~/.codex/sessions/` (also check `$CODEX_HOME/sessions/`)
- [ ] `@concurrent nonisolated func discoverClaudeFiles() async throws -> [DiscoveredFile]` — glob `**/*.jsonl`
- [ ] `@concurrent nonisolated func discoverCodexFiles() async throws -> [DiscoveredFile]` — glob `**/*.jsonl`, skip `.zst`
- [ ] `DiscoveredFile` — path, mtime, size, provider
- [ ] Handle missing directories gracefully (skip, don't crash)

### Task 4.2: Full scan (startup)

- [ ] `func fullScan() async throws`
- [ ] Discover files from both Claude and Codex directories
- [ ] Check index_transcript_scan_state for existing mtime/offset per file
- [ ] Skip unchanged files (mtime matches)
- [ ] Route to correct parser by provider (`discoverClaudeFiles` → `parseClaudeJSONL`, `discoverCodexFiles` → `parseCodexJSONL`)
- [ ] Parse changed/new files (incremental from byte offset)
- [ ] Write to DB via AgentSessionIndexRepository
- [ ] Return scan summary (new, updated, unchanged counts)

### Task 4.3: Active session detection

- [ ] `func scanActiveSessions() async throws`
- [ ] Claude: read `~/.claude/sessions/*.json` — parse PID → sessionId + cwd, check `kill(pid, 0) == 0`
- [ ] Codex: no PID registry — detect running status from JSONL mtime within last 60s
- [ ] Update status in DB (.running for alive/recent, .idle for dead/stale)

### Task 4.4: File watching

- [ ] Use existing `DarwinFSEventStreamClient` pattern (NOT DispatchSource)
- [ ] Watch `~/.claude/projects/` for new/changed JSONL files
- [ ] Watch `~/.claude/sessions/` for PID registry changes
- [ ] Watch `~/.codex/sessions/` for new/changed JSONL files
- [ ] Debounce: 1s coalesce window before triggering scan
- [ ] If any directory doesn't exist: skip, re-check periodically (5m)
- [ ] Emit `RuntimeEnvelope.system(.agentSessionsIndexed(count:))` after scan

---

## Phase 5: Atom and Coordinator Wiring

### Task 5.1: AgentSessionAtom

Create in `Core/State/MainActor/Atoms/`:

- [ ] `@MainActor @Observable final class AgentSessionAtom`
- [ ] `private(set) var activeSessions: [SessionKey: ActiveSessionState]` — hot state
- [ ] `private(set) var recentByWorktree: [WorktreeId: [SessionSummary]]` — warm cache
- [ ] `prefetchRecent(for:)` — loads recent sessions for a worktree from DB
- [ ] `evictCache(for:)` — removes warm cache entry
- [ ] `refreshActiveSessions()` — re-queries active sessions from DB
- [ ] `refreshRecent(for:)` — re-queries recent for specific worktree

### Task 5.2: ValueObservation for active sessions

- [ ] Subscribe to `index_session WHERE status = 'running'` via `activeSessionsObservation()`
- [ ] Delivers on MainActor, updates `activeSessions` property
- [ ] Observation lifetime tied to atom

### Task 5.3: Coordinator integration

- [ ] Subscribe to `.agentSessionsIndexed` fact on event bus
- [ ] On receipt: tell atom to refresh active sessions + invalidate affected worktree caches
- [ ] On topology change (worktree added/removed): 
  - Read unresolved CWD observations from DB
  - Resolve via topology atom
  - Write worktree matches back to DB
  - Refresh atom

### Task 5.4: Register in AtomRegistry

- [ ] Add `agentSession: AgentSessionAtom` to `AtomRegistry`
- [ ] Wire index DB path from `AppDataPaths.workspacesDirectory()`
- [ ] Initialize index DB + run migrations during workspace boot
- [ ] Start scanner after DB is ready
- [ ] Integrate into boot sequence (after loadUIStore, before topology sync)

---

## Phase 6: Testing

### Task 6.1: Unit tests

- [ ] Index migration creates all tables and indexes
- [ ] Core migration adds session_pointer table
- [ ] All repository write methods (upsert, update status, FTS rebuild)
- [ ] All read handler query methods with fixtures
- [ ] Claude JSONL parser: normal file, truncated last line, malformed lines, empty file
- [ ] Codex JSONL parser: normal rollout, multi-turn, tool items, empty file
- [ ] Incremental parsing: parse from byte offset, verify only new content parsed
- [ ] FTS5 search: standalone upsert, delete-then-insert, search matches
- [ ] CWD → worktree resolution logic
- [ ] Session pointer reconciliation

### Task 6.2: Integration tests

- [ ] Full scan: temp JSONL files → scanner discovers → DB populated → atom queries correct
- [ ] Incremental scan: modify file → scanner detects → DB updated with new data only
- [ ] Active session detection: create PID file → running, remove → idle
- [ ] Concurrent read/write: scanner reads while file is being appended

---

## Phase 7: Future (Not in This Plan)

- [ ] Sidebar UI — session list per worktree
- [ ] Command bar — "Resume session" action, session search
- [ ] Pane ↔ session association — live status in tab bar
- [ ] Hooks / statusline / OTLP integration
- [ ] Cost estimation pricing tables
- [ ] Session diff viewer
- [ ] Compressed archives (.jsonl.zst)

---

## Dependency Graph

```
Phase 1 (Models + Schema) — no external deps beyond sqlite branch
  ├── 1.1 Models
  ├── 1.2 Index migrations (depends on GRDB from sqlite branch)
  ├── 1.3 Core migration extension
  └── 1.4 Test fixtures

Phase 2 (Repositories) — depends on Phase 1
  ├── 2.1 Index repository (depends on 1.2)
  ├── 2.2 Read handler (depends on 1.2)
  └── 2.3 Core pointer extension (depends on 1.3)

Phase 3 (Parsers) — parallel with Phase 2
  ├── 3.1 ParsedSession type (depends on 1.1)
  ├── 3.2 Claude parser (depends on 3.1, 1.4)
  ├── 3.3 Codex parser (depends on 3.1, 3.4)
  └── 3.4 Codex fixtures (no deps)

Phase 4 (Scanner) — depends on Phase 2 + 3
  ├── 4.1 Discovery (depends on 1.1)
  ├── 4.2 Full scan (depends on 2.1, 3.2)
  ├── 4.3 Active detection (depends on 2.1)
  └── 4.4 File watching (depends on 4.2)

Phase 5 (Atom + Wiring) — depends on Phase 2 + 4
  ├── 5.1 Atom (depends on 2.2)
  ├── 5.2 ValueObservation (depends on 5.1, 2.2)
  ├── 5.3 Coordinator (depends on 5.1, 4.4)
  └── 5.4 Registration (depends on 5.1)

Phase 6 (Tests) — parallel with each phase
```
