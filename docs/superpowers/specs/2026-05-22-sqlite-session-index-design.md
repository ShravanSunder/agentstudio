# SQLite Session And Future Index Brainstorming

## Status

This file is now a pointer to the split checkpoint spec:

```text
docs/superpowers/specs/sqlite/07-session-index-brainstorm.md
```

Session indexing remains future work. The current SQLite cutover should first
land the core/settings/local storage foundation described by:

```text
docs/superpowers/specs/sqlite/00-persistence-boundaries.md
docs/superpowers/specs/sqlite/01-core-workspace-schema.md
docs/superpowers/specs/sqlite/02-local-ux-and-cache-schema.md
docs/superpowers/specs/sqlite/03-settings-json.md
docs/superpowers/specs/sqlite/04-migration-and-recovery.md
docs/superpowers/specs/sqlite/05-write-paths-and-actors.md
docs/superpowers/specs/sqlite/06-test-checkpoints.md
```

The durable decision is:

```text
core.sqlite
  -> user-owned workflow / worker / session_pointer rows

<workspace-id>.local.sqlite
  -> rebuildable provider session facts, scan checkpoints, FTS rows,
     tool histograms, token summaries, cwd observations, and cache data
```

