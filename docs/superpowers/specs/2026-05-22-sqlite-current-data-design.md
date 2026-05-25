# SQLite Current Data Design

## Status

This is now the entrypoint for the SQLite persistence design. The detailed spec
has been split into checkpoint files under `docs/superpowers/specs/sqlite/`.

## Decision Summary

AgentStudio should move durable workspace structure into migrated SQLite rows
without turning SQLite into a giant snapshot store.

The target storage shape is:

```text
<AppDataPaths.rootDirectory()>/core.sqlite
<AppDataPaths.workspacesDirectory()>/<workspace-id>.settings.json
<AppDataPaths.workspacesDirectory()>/<workspace-id>.local.sqlite
```

There is no app-local SQLite database in Step 1.

The critical boundary:

```text
core.sqlite
  durable product truth
  includes app_workspace_selection.active_workspace_id

<workspace-id>.settings.json
  intentional user preferences

<workspace-id>.local.sqlite
  workspace cursor state, local UX memory, cache, and future index rows
```

`active_workspace_id` belongs in core because it chooses which workspace graph to
open. Active tab, active arrangement, active pane, drawer expanded state, and
active drawer child belong in local because they are workspace cursor/attention
state.

## Checkpoints

Read and review in this order:

```text
00-persistence-boundaries.md
  C1: core/settings/local mental model, current data mapping, active-state rule

01-core-workspace-schema.md
  C2: durable core schema for workspace graph and future pointers

02-local-ux-and-cache-schema.md
  C3: per-workspace local schema for cursor, UX memory, cache, future index

03-settings-json.md
  C3: editable workspace settings JSON

04-migration-and-recovery.md
  C5: atom boundary prep, boot, import, hard cutover, deletion, recovery,
      migration identifiers

05-write-paths-and-actors.md
  C4: DB-first core writes, atom-first local/settings writes, GRDB rules

06-test-checkpoints.md
  C6: migration, repository, recovery, capability, and integration tests

07-session-index-brainstorm.md
  C7: future Claude/Codex session index and durable session pointer ideas
```

## Implementation Order

```text
1. Freeze boundaries.
2. Split lifecycle-mixed atoms into write-owner atoms plus derived readers.
3. Implement core migrations and core repository tests.
4. Implement settings extraction.
5. Implement local UX/cache migrations and repository tests.
6. Replace observation-driven core snapshot saves with transaction-first writes.
7. Add recovery/quarantine paths.
8. Return to session indexing after the foundation is stable.
```

## Non-Goals

- Do not store the whole workspace as one SQLite blob.
- Do not keep JSON and SQLite as peer sources of truth.
- Do not introduce DuckDB in Step 1.
- Do not parse Claude Code or Codex transcripts in Step 1.
