# Agent Session Index Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement an indexed, queryable catalog of AI coding agent sessions (Claude Code, Codex CLI) that integrates with AgentStudio's workspace/worktree model. Users can discover, search, and resume sessions from within AgentStudio.

**Design Spec:** [2026-04-13-agent-session-index-design.md](../specs/2026-04-13-agent-session-index-design.md)

**Tech Stack:** Swift 6.2, macOS 26, GRDB (SQLite), `@MainActor` atom, `actor` scanner, `@concurrent nonisolated` I/O, Swift Testing, mise

---

## Phase 1: Foundation — Models, Schema, GRDB Setup

### Task 1.1: Add GRDB dependency

- [ ] Add `groue/GRDB.swift` to `Package.swift` (latest v7.x, SPM)
- [ ] Verify it builds: `mise run build`
- [ ] Add to `.swift-format` and `.swiftlint.yml` excludes if needed for generated code

### Task 1.2: Session data models

Create the core value types in `Core/Models/`:

- [ ] `AgentProvider.swift` — `enum AgentProvider: String, Codable, Sendable { case claudeCode, codex }`
- [ ] `SessionKey.swift` — `struct SessionKey: Hashable, Codable, Sendable`
- [ ] `SessionStatus.swift` — `enum SessionStatus: String, Codable, Sendable { case running, idle, completed, interrupted }`
- [ ] `SessionSummary.swift` — lightweight index record (see spec for full field list)
- [ ] `ActiveSessionState.swift` — extends summary with live data (paneId, pid, context window)
- [ ] `SessionWorktreeAssociation.swift` — junction record
- [ ] `ToolUsage.swift` — tool name + count
- [ ] `CostSummary.swift` — aggregate stats

All types are `Sendable` value types. No `@Observable`, no actor isolation.

### Task 1.3: GRDB database setup and migrations

Create `AgentSessionStore` in `Core/State/MainActor/Persistence/`:

- [ ] `AgentSessionStore.swift` — owns `DatabasePool`, manages migrations
- [ ] Migration v1: `sessions` table with all columns and indexes (see spec schema)
- [ ] Migration v1: `session_worktrees` junction table with indexes
- [ ] Migration v1: `session_tools` histogram table
- [ ] Migration v1: `session_commits` table
- [ ] Migration v1: `sessions_fts` FTS5 virtual table
- [ ] GRDB `Record` types: `SessionRecord`, `SessionWorktreeRecord`, `SessionToolRecord`, `SessionCommitRecord`
- [ ] DB location: `~/.agentstudio/workspaces/<workspace-id>/agent-sessions.db`
- [ ] WAL mode enabled on pool creation
- [ ] Write unit tests: migration creates tables, basic CRUD operations

### Task 1.4: Store query methods

Add typed query methods to `AgentSessionStore`:

- [ ] `sessions(forWorktree:offset:limit:)` — JOIN on session_worktrees, ORDER BY last_active_at DESC
- [ ] `sessions(forRepo:offset:limit:)` — same pattern with repo_id
- [ ] `sessions(branch:repoId:limit:)` — filter by git_branch in junction table
- [ ] `activeSessions()` — WHERE status = 'running'
- [ ] `search(query:limit:)` — FTS5 MATCH on sessions_fts
- [ ] `costSummary(since:)` — SUM aggregation
- [ ] `toolProfile(for:)` — fetch from session_tools
- [ ] `worktreeAssociations(for:)` — fetch from session_worktrees
- [ ] `restoreCommand(for:)` — single column fetch
- [ ] `bulkUpsert(_:)` — INSERT OR REPLACE in a transaction
- [ ] `updateStatus(_:for:)` — point update
- [ ] Write unit tests: each query with test fixtures

---

## Phase 2: JSONL Parsing — Provider-Specific

### Task 2.1: Claude Code JSONL parser

Create `ClaudeSessionParser` in `Core/RuntimeEventSystem/Runtime/Parsers/`:

- [ ] `@concurrent nonisolated` free function: `parseClaudeJSONL(at: URL) async throws -> ParsedSession`
- [ ] Parse line-by-line using `FileHandle.bytes.lines`
- [ ] Lightweight `Decodable` structs — only decode fields we need (not full message content)
- [ ] Extract from first `user` record: `cwd`, `gitBranch`, `sessionId`, `version`, timestamp
- [ ] Extract from `assistant` records: accumulate `message.usage.*` tokens, `message.model`, count `tool_use` blocks by name
- [ ] Track all `cwd` changes across records → build `[CWDVisit]` list with timestamps
- [ ] Extract `summary` record → `displayName`
- [ ] Extract first user message content → `firstPrompt` (truncated to 200 chars)
- [ ] Build `restoreCommand`: `"claude --resume <sessionId>"`
- [ ] Return `ParsedSession` (provider-agnostic intermediate type)
- [ ] Write unit tests: parse sample Claude JSONL fixture, verify all extracted fields

### Task 2.2: Codex JSONL parser

Create `CodexSessionParser` in `Core/RuntimeEventSystem/Runtime/Parsers/`:

- [ ] `@concurrent nonisolated` free function: `parseCodexJSONL(at: URL) async throws -> ParsedSession`
- [ ] Parse `RolloutLine` envelope format: `{"type": "...", "payload": {...}}`
- [ ] Extract from `SessionMeta`: conversation_id, model, timestamp
- [ ] Extract from `ResponseItem`: accumulate tokens, count tool items
- [ ] Extract from `EventMsg`: track CWD changes, extract first user input
- [ ] Skip `.jsonl.zst` files entirely
- [ ] Build `restoreCommand`: `"codex resume <threadId>"`
- [ ] Return `ParsedSession`
- [ ] Write unit tests: parse sample Codex JSONL fixture

### Task 2.3: ParsedSession intermediate type

- [ ] `ParsedSession.swift` in `Core/Models/` — provider-agnostic, carries all extracted fields plus raw CWD visit list
- [ ] `CWDVisit` — `(cwd: URL, timestamp: Date)` for worktree resolution
- [ ] Conversion method: `ParsedSession.toSessionRecord()` → GRDB `SessionRecord`
- [ ] Conversion method: `ParsedSession.toWorktreeAssociations(resolving:)` → uses topology atom to resolve CWD → worktreeId

---

## Phase 3: Scanner Actor

### Task 3.1: Directory discovery

Create `AgentSessionScanner` in `Core/RuntimeEventSystem/Runtime/`:

- [ ] `actor AgentSessionScanner`
- [ ] `claudeProjectsPath` — resolve `~/.claude/projects/` (also check `~/.config/claude/projects/`)
- [ ] `codexSessionsPath` — resolve `~/.codex/sessions/` (also check `$CODEX_HOME`)
- [ ] `@concurrent nonisolated func discoverClaudeFiles() async throws -> [DiscoveredFile]` — glob `**/*.jsonl`
- [ ] `@concurrent nonisolated func discoverCodexFiles() async throws -> [DiscoveredFile]` — glob `**/*.jsonl` (skip `.zst`)
- [ ] `DiscoveredFile` — `(path: URL, mtime: Date, size: Int64, provider: AgentProvider)`

### Task 3.2: Full scan (startup)

- [ ] `func fullScan() async throws`
- [ ] Discover all files from both providers
- [ ] Fetch existing `(transcript_path, transcript_mtime)` from DB
- [ ] Skip files where `mtime == transcript_mtime` (unchanged)
- [ ] Parse changed/new files (sequential initially, parallel later if needed)
- [ ] Resolve CWD → worktreeId via `WorkspaceRepositoryTopologyAtom.repoAndWorktree(containing:)`
- [ ] Bulk upsert into DB
- [ ] Emit `RuntimeEnvelope.system(.agentSessionsIndexed(count:))` on bus
- [ ] Write integration test: create temp JSONL files, scan, verify DB contents

### Task 3.3: Incremental scan (file watcher)

- [ ] Set up `DispatchSource.makeFileSystemObjectSource` or `FSEvents` on both directories
- [ ] On change: discover new/modified files, parse only those, upsert
- [ ] Debounce: coalesce events within 1s window before scanning
- [ ] Handle file deletion: mark sessions as `completed` if transcript disappears (unlikely but possible)

### Task 3.4: Active session detection

- [ ] `func scanActiveSessions() async throws`
- [ ] Read `~/.claude/sessions/*.json` — parse `{pid, sessionId, cwd, startedAt, kind}`
- [ ] Check if PID is still alive: `kill(pid, 0) == 0`
- [ ] For alive PIDs: find matching session in DB by sessionId, mark status = `.running`
- [ ] For dead PIDs or missing files: mark status = `.idle` (if was `.running`)
- [ ] Schedule: every 30s while app is active, plus on FSEvents for `~/.claude/sessions/`
- [ ] Codex: no equivalent PID registry — detect running status from JSONL file being actively appended (mtime within last 60s)

---

## Phase 4: Atom and Reactive UI Binding

### Task 4.1: AgentSessionAtom

Create in `Core/State/MainActor/Atoms/`:

- [ ] `@MainActor @Observable final class AgentSessionAtom`
- [ ] `private(set) var activeSessions: [SessionKey: ActiveSessionState]` — hot, reactive
- [ ] `private(set) var recentByWorktree: [WorktreeId: [SessionSummary]]` — warm cache
- [ ] Async query methods delegating to `AgentSessionStore` (see spec interface)
- [ ] `prefetchRecent(for:)` — loads last 5 sessions for a worktree into warm cache
- [ ] `evictCache(for:)` — removes warm cache for a worktree
- [ ] `didUpdateIndex()` — called by scanner, triggers GRDB observation refresh

### Task 4.2: GRDB ValueObservation subscriptions

- [ ] Subscribe to `sessions WHERE status = 'running'` → drives `activeSessions`
- [ ] Use `DatabaseRegionObservation` for change notifications (lighter than full ValueObservation for warm cache invalidation)
- [ ] On change: invalidate affected worktree caches, re-fetch if visible
- [ ] Observation lifetime tied to atom lifecycle

### Task 4.3: Register in AtomStore

- [ ] Add `agentSession: AgentSessionAtom` to `AtomStore`
- [ ] Add `agentSessionStore: AgentSessionStore` to persistence layer
- [ ] Wire DB path from workspace metadata
- [ ] Initialize DB + run migrations on workspace load
- [ ] Start scanner after DB is ready

### Task 4.4: Event bus integration

- [ ] Define `SystemScopedEvent.agentSessionsIndexed(count: Int)` — emitted after scan completes
- [ ] `WorkspaceCacheCoordinator` or new coordinator subscribes — triggers atom refresh
- [ ] On topology change (worktree added/removed): notify scanner to re-resolve unresolved CWDs

---

## Phase 5: Testing

### Task 5.1: Unit tests

- [ ] GRDB schema migration test
- [ ] GRDB CRUD operations test
- [ ] All query methods with fixtures
- [ ] Claude JSONL parser with sample data
- [ ] Codex JSONL parser with sample data
- [ ] CWD → worktree resolution logic
- [ ] Multi-worktree association building
- [ ] FTS5 search test
- [ ] Cost aggregation test

### Task 5.2: Integration tests

- [ ] End-to-end: create temp JSONL files → scanner discovers → DB populated → atom queries return correct results
- [ ] Incremental scan: modify a file → scanner detects → DB updated
- [ ] Active session detection: create PID file → scanner marks running → remove PID file → scanner marks idle
- [ ] Worktree resolution: set up topology atom with known worktrees → scanner resolves CWDs correctly
- [ ] FTS search: index sessions → search by name/prompt → correct results

### Task 5.3: Test fixtures

- [ ] Create sample Claude Code JSONL files (small, representative)
- [ ] Create sample Codex JSONL files
- [ ] Create sample `~/.claude/sessions/<pid>.json` files
- [ ] All fixtures in test resources, not hardcoded strings

---

## Phase 6: Future (Not in This Plan)

These are explicitly deferred. They build on the index but are separate work:

- [ ] **Sidebar UI** — session list per worktree, session detail panel
- [ ] **Command bar integration** — search sessions, "Resume session" action
- [ ] **Pane↔session association** — detect which pane is running which session, show live status in tab bar
- [ ] **Hooks integration** — receive Claude Code PostToolUse/SessionStart hooks for richer live data
- [ ] **Statusline integration** — parse Claude Code statusline JSON for context window / rate limit data
- [ ] **Agent pane content type** — wire `PaneContentType.agent` to session index
- [ ] **Cost estimation** — per-model token pricing for `estimatedCostUSD`
- [ ] **Session diff viewer** — show git diff for commits created during a session

---

## Dependency Graph

```
Phase 1 (Foundation)
  ├── 1.1 GRDB dependency
  ├── 1.2 Models (no deps)
  ├── 1.3 DB setup (depends on 1.1, 1.2)
  └── 1.4 Store queries (depends on 1.3)

Phase 2 (Parsers) — parallel with Phase 1.3/1.4
  ├── 2.1 Claude parser (depends on 1.2)
  ├── 2.2 Codex parser (depends on 1.2)
  └── 2.3 ParsedSession (depends on 1.2)

Phase 3 (Scanner) — depends on Phase 1 + 2
  ├── 3.1 Directory discovery
  ├── 3.2 Full scan (depends on 3.1, 2.1, 2.2, 1.4)
  ├── 3.3 Incremental scan (depends on 3.2)
  └── 3.4 Active session detection (depends on 3.2)

Phase 4 (Atom) — depends on Phase 1.4 + 3
  ├── 4.1 Atom (depends on 1.4)
  ├── 4.2 GRDB observation (depends on 4.1, 1.3)
  ├── 4.3 AtomStore registration (depends on 4.1)
  └── 4.4 Event bus (depends on 4.1, 3.2)

Phase 5 (Tests) — parallel with each phase
```
