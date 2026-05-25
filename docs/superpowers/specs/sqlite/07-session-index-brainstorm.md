# Session Index Brainstorm

## Status

Checkpoint C7 for future provider session and derived index data.

This is not the Step 1 implementation plan. Step 1 is the current persistence
cutover described in `00-persistence-boundaries.md` through
`06-test-checkpoints.md`.

## Working Direction

Session indexing should live in the per-workspace local database, not in a third
standalone index database.

```text
<AppDataPaths.rootDirectory()>/core.sqlite
  durable session pointers, workflows, workers, user aliases, user notes,
  pinned/archive state, and preferred restore command overrides

<AppDataPaths.workspacesDirectory()>/<workspace-id>.local.sqlite
  rebuildable provider/session facts, scan checkpoints, FTS rows,
  tool histograms, token summaries, cwd observations, and cache data
```

Use table prefixes inside `local.sqlite`:

```text
local_*   local UX memory
cache_*   current rebuildable cache
index_*   provider/session/search index
```

The first migration work should not parse Claude or Codex transcripts. Session
indexing comes after the current workspace data has a migrated foundation.

`local.sqlite` is still per-workspace in this future model. `workspace_id`
columns in `index_*` tables are guard rails and copied-query keys, not a
multi-tenant local database design.

## Why Session Pointers Split From Session Facts

Provider transcripts are external facts. User curation is product truth.

```text
core.sqlite
  "I care about this session."
  "This session belongs to this worker."
  "Pin it."
  "Archive it."
  "Call it Migration Spike."
  "Use this restore command."

local.sqlite index_* tables
  "Claude wrote this JSONL file."
  "Codex rollout had this model."
  "This cwd was observed."
  "These tools were used."
  "These tokens were counted."
  "This snippet matched search."
```

If `local.sqlite` is deleted, AgentStudio can re-scan provider-owned files and
rebuild index facts. If `core.sqlite` loses a session pointer, the user loses
curation that cannot be reconstructed.

No `index_*` table has a real foreign key into `core.sqlite`. SQLite cannot
enforce FKs across separate database files. `session_pointer_id`, `repo_id`,
`worktree_id`, `pane_id`, and `tab_id` values copied into `index_*` rows must be
treated as soft references and reconciled against current core rows during
rebuild or topology deletion.

## AgentStudio Mapping

Provider sessions fit under the existing workspace identity chain, but they do
not replace pane sessions.

```text
Workspace
  -> Repo
  -> Worktree
  -> Pane
  -> terminal process
  -> Claude Code / Codex provider session
```

Important mapping rules:

- `PaneId` is useful only when AgentStudio observes a live session in a pane.
- Disk-discovered sessions may have no pane id.
- A provider session can touch multiple cwd paths and therefore multiple
  worktrees.
- Primary association is the first/best resolvable cwd/worktree.
- Additional cwd/worktree matches are stored as observations.
- Durable worker/workflow membership is a core session pointer relationship,
  not an inferred index fact.

## Useful Research Ideas

The pasted research remains useful, but it is input for the later session model,
not a reason to pull session parsing into Step 1.

### T3 Code

T3 Code is most useful as a provider-normalization reference.

Ideas worth borrowing later:

- adapter boundary per provider
- canonical provider events over native provider events
- thread / turn / item vocabulary for agent work
- provider session runtime metadata
- resume cursors
- normalized token usage events
- command receipts for idempotency
- checkpoint/diff concepts around turns

Ideas not needed for Step 1:

- wrapping Claude/Codex processes directly
- hosting agent sessions through SDKs
- event-sourcing the entire AgentStudio app
- storing every provider-native event as durable product truth

### Claude Code

Useful local sources:

```text
~/.claude/projects/<encoded-cwd>/<session-id>.jsonl
~/.claude/sessions/<pid>.json
```

Useful fields and events:

- `sessionId`
- `cwd`
- `gitBranch`
- `timestamp`
- `uuid`
- `parentUuid`
- assistant `message.usage`
- summary records
- tool-use records
- active PID mapping from `~/.claude/sessions`
- hooks as a future live source
- statusline JSON as a future live source
- OTLP telemetry as a future observability source

Initial restore command:

```text
claude --resume <session-id>
```

Possible future command:

```text
claude --continue <session-id>
```

### Codex

Useful local sources:

```text
~/.codex/sessions/YYYY/MM/DD/rollout-<id>.jsonl
~/.codex/sessions/YYYY/MM/DD/rollout-<id>.jsonl.zst
~/.codex/state_*.sqlite
```

Useful concepts:

- thread as durable conversation container
- turn as one user request plus agent work
- item as an atomic unit such as command execution, file change, reasoning, or
  agent message
- thread resume
- thread fork
- ephemeral thread behavior
- `codex app-server` JSON-RPC stream as a future live integration

Initial restore command:

```text
codex resume <thread-id>
```

Possible future fork command:

```text
codex fork <thread-id>
```

## Session Characteristics

The index should store lightweight summaries and query keys, not full
transcripts.

```text
identity
  provider
  provider_session_id
  provider_thread_id when different
  transcript_path
  transcript_size
  transcript_mtime

display
  display_name
  provider_summary
  first_prompt_snippet
  model
  status
  restore_command

time
  created_at
  last_active_at
  ended_at
  indexed_at
  indexed_byte_offset

usage
  turn_count
  total_input_tokens
  total_output_tokens
  total_cache_read_tokens
  estimated_cost_usd
  tool usage histogram

association
  cwd observations
  repo/worktree matches
  git branch observations
  pane id when observed live
  session pointer id when curated
  parent/fork relationship when provider exposes it

search
  title/summary/prompt snippets
  cwd paths
  tool names
  small extracted message snippets
```

Do not store:

- full provider JSONL transcript bodies
- large command output bodies
- large tool results
- large diffs
- provider-owned raw event streams as product truth

## Loading Rule

Do not hold all sessions in memory.

Load into memory:

- active sessions
- recent sessions for visible worktrees
- selected session summary
- current search result page
- pinned/curated session pointers for visible workflows

Query on demand:

- full historical session list
- all cwd observations
- all tool histograms
- FTS rows
- transcript scan state
- cost aggregates

## Local Index Schema Sketch

This is design DDL, not final executable migration text.

```sql
CREATE TABLE index_session (
    workspace_id TEXT NOT NULL,
    provider TEXT NOT NULL,
    provider_session_id TEXT NOT NULL,
    provider_thread_id TEXT,
    session_pointer_id TEXT,
    display_name TEXT,
    provider_summary TEXT,
    first_prompt_snippet TEXT,
    status TEXT NOT NULL,
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
    transcript_size INTEGER NOT NULL DEFAULT 0,
    transcript_mtime REAL,
    indexed_byte_offset INTEGER NOT NULL DEFAULT 0,
    indexed_at REAL NOT NULL,
    PRIMARY KEY(provider, provider_session_id)
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

CREATE TABLE index_session_worktree_match (
    workspace_id TEXT NOT NULL,
    provider TEXT NOT NULL,
    provider_session_id TEXT NOT NULL,
    repo_id TEXT,
    worktree_id TEXT,
    cwd_path TEXT NOT NULL,
    is_primary INTEGER NOT NULL,
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
    use_count INTEGER NOT NULL,
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
        provider,
        provider_session_id,
        relationship_kind,
        related_provider,
        related_provider_session_id
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
```

FTS sync rule:

```text
index_session_search_fts
  -> rebuildable projection table
  -> no durable truth
  -> one row per provider/session id

session summary upsert
  -> DELETE FROM index_session_search_fts
       WHERE provider = ? AND provider_session_id = ?
  -> INSERT rebuilt search document

session deleted or transcript no longer visible
  -> DELETE matching FTS row

index reset
  -> delete/recreate FTS rows from index_session + child summary tables
```

The FTS table stores `provider` and `provider_session_id` as unindexed identity
columns so search results can join back to `index_session`. It does not enforce
uniqueness itself; the repository owns delete-then-insert upsert semantics in
one local transaction.

## Core Session Pointer Schema

Durable user curation belongs in `core.sqlite`.

```sql
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

`index_session.session_pointer_id` is copied into the local index when a pointer
exists. The core row remains authoritative.

Restore command precedence:

```text
effective restore command
  -> session_pointer.preferred_restore_command, when present
  -> otherwise index_session.restore_command
```

The UI should resolve this at read time by joining the durable pointer summary
with the local index result. Do not overwrite the provider-derived
`index_session.restore_command` just because a user override exists; the derived
command remains useful if the override is cleared.

Pointer attachment is a reconciliation step, not a FK:

```text
index session discovered
  -> match by workspace_id + provider + provider_session_id
  -> copy session_pointer.id into index_session.session_pointer_id

session pointer deleted from core
  -> clear matching index_session.session_pointer_id
  -> keep provider-discovered session facts

local index rebuilt
  -> reattach any existing core pointers by provider/session id
```

## Rebuild Rule

On missing or reset `cache_*`/`index_*` tables:

```text
1. run local.sqlite migrations
2. recreate cache summaries from runtime/git facts
3. scan provider transcript directories incrementally
4. match cwd paths to current core topology
5. rebuild FTS rows from extracted snippets
6. attach existing core session pointers by provider/session id
```

The local database never rebuilds core rows. It only references them by copied
ids.

## DuckDB Revisit Gate

Do not use DuckDB for Step 1 cache or session data.

Reconsider DuckDB only if the workload becomes analytical:

- hundreds of thousands of indexed sessions
- frequent large aggregate reports across all history
- Parquet export/import becomes a product feature
- transcript analytics need columnar scans
- SQLite FTS and indexed summary tables become measurably insufficient

Until then, one SQLite stack is simpler and fits the app's migration and UI
state needs better.
