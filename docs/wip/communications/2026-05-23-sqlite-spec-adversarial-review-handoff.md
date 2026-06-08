# SQLite Spec Adversarial Review Handoff

## Scope

Review these two files as the current SQLite persistence proposal:

- `docs/superpowers/specs/2026-05-22-sqlite-current-data-design.md`
- `docs/superpowers/specs/2026-05-22-sqlite-session-index-design.md`

The current-data spec is intended to become the actionable Step 1 plan. The
session/index spec is intentionally a future brainstorming companion and should
not pull session parsing into Step 1.

## Intended Design

The proposal uses one global SQLite database, one per-workspace settings file,
and one per-workspace local SQLite database through GRDB:

- `<AppDataPaths.rootDirectory()>/core.sqlite`
  - global durable product truth, rows keyed by `workspace_id`
  - owns workspaces, repos, worktrees, panes, tabs, workflows, workers, and
    durable session pointers
  - must not be discarded during local/cache rebuilds

- `<AppDataPaths.workspacesDirectory()>/<workspace-id>.settings.json`
  - user-editable workspace preferences
  - owns editor bookmark, checkout colors, and notification preferences

- `<AppDataPaths.workspacesDirectory()>/<workspace-id>.local.sqlite`
  - lower-criticality local UX memory plus rebuildable cache/index data
  - table prefixes divide responsibility: `local_*`, `cache_*`, `index_*`
  - `cache_*` / `index_*` may be reset without losing `local_*`
  - deleting the whole local DB loses relaunch memory and cache/index state, but
    must never lose core workspace truth or settings

DuckDB is deliberately out of scope for Step 1.

## Adversarial Questions

1. Are all current durable JSON-backed surfaces accounted for?
   - `*.workspace.state.json`
   - `*.workspace.cache.json`
   - `*.workspace.ui.json`
   - `*.workspace.sidebar-cache.json`
   - `*.notification-inbox.json`
   - `surface-checkpoint.json`
   - current UserDefaults keys

2. Are all current rebuildable cache fields accounted for?
   - repo enrichment
   - worktree enrichment
   - pull request counts
   - notification counts while they remain in `RepoCacheStore`
   - source revision
   - last rebuilt timestamp

3. Is `recentTargets` correctly classified as `local_*` user activity memory
   rather than rebuildable `cache_*` data or durable `core.sqlite` product truth?

4. Does the database/file path model match current `AppDataPaths` behavior,
   including debug build and `AGENTSTUDIO_DATA_DIR` override?

5. Does the spec accurately describe current atom boundaries?
   - `WorkspacePaneAtom`
   - `WorkspaceTabShellAtom`
   - `WorkspaceTabArrangementAtom`
   - composed `WorkspaceTabLayoutAtom`
   - runtime-only `CommandBarSurfaceAtom`
   - runtime-only `TransientKeyboardSurfaceAtom`
   - runtime-only `ManagementLayerAtom`

6. Is the persistence write boundary clear enough?
   - core mutations commit SQLite rows and then update atoms
   - local UX writes update atoms first and persist asynchronously
   - cache writes are rebuildable and should not block core UI interactions
   - atoms do not write SQLite directly

7. Is the SQLite corruption recovery rule operationally sufficient?
   - core DB corruption quarantines DB/WAL/SHM together
   - settings corruption never touches core/local
   - local DB corruption never touches core/settings
   - `cache_*` / `index_*` rebuilds preserve `local_*` where possible

8. Is the pane/tab JSON-column decision sufficiently explicit?
   - Step 1 rejects whole-workspace, whole-pane-list, and whole-tab-list blobs
   - tactical JSON is allowed only for unsupported or feature-specific pane
     content bodies

9. Does the future workflow/worker/session pointer language conflict with the
   existing management layer, command system, or current atom model?

10. What implementation blockers would appear if an agent tried to turn this
    spec directly into an implementation plan tomorrow?

## Review Output Requested

Please return findings first, ordered by severity:

- P0: data loss or impossible migration risk
- P1: architecture or ownership mismatch that would block implementation
- P2: ambiguous decision likely to become an implementation blocker
- P3: wording, naming, or future-proofing issue

Each finding should cite file paths and line numbers from the specs or current
code.
