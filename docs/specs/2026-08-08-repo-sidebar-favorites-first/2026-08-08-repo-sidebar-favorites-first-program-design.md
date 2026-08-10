# Repository Sidebar Favorites-First Program Design

## Structure

```text
RepositoryTopologyAtom.isFavorite
             │
             ▼
RepoExplorerSnapshot (repos + grouping + sort + query)
             │
             ▼
RepoExplorerView projection request owner
  ├─ increments generation
  ├─ cancels the prior request task
  └─ submits the current request
             │
             ▼
RepoExplorerProjectionWorker
  ├─ forwards caller cancellation to detached computation
  ├─ RepoExplorerProjection + RepoExplorerRowIndex off-main
  └─ returns request generation with projected result
             │
             ▼
RepoExplorerView generation gate
  └─ rejects stale results before main-actor apply
             │
             ▼
RepoExplorerProjection
  ├─ By Repo ─────────────► optional Favorites + required Repositories
  ├─ By Pane ─────────────► optional Favorites + required Panes
  └─ By Tab ──────────────► optional Favorites + required Tabs, with tab
                             groups partitioned across the two sections
             │
             ▼
RepoExplorerRowIndex ──► section/header/group/leaf list entries
             │
             ▼
RepoExplorerView List
```

## Ownership

- `RepositoryTopologyAtom` remains the sole favorite-state owner.
- `RepoExplorerProjection` owns mode-specific ordering and section classification because it already owns search, sort, grouping, loading, and empty-state projection.
- `RepoExplorerRowIndex` owns flattening projected sections and groups into stable render entries and visible-row correspondence.
- `RepoExplorerView` renders section labels and existing semantic group/leaf rows; it does not derive favorite partitions in `body`.
- `SectionSubheadingLabel` owns the non-interactive Sidebar and Command Bar
  small-caps, accent-muted typography. Each host applies the same
  `AppStyles.Components.SectionSubheading` insets.

## Projection model

Add a small RepoExplorer-owned section descriptor with stable identity (`favorites`, `repositories`, `panes`, `tabs`), resolved groups, and loading repositories. Favorites exists only when its collection is non-empty. Every grouping mode always emits its normal descriptor so normal content retains an explicit heading even when that section is empty. The existing no-results and degraded states still replace the list before list entries render. Flattening order is section header, resolved group/expanded-leaf runs, then the existing `Scanning…` label and loading rows. Section identity is distinct from semantic group identity. Existing `repo:` and `pane-repo:` group IDs remain unchanged. Non-favorite tab groups retain `tab:` IDs; favorite tab groups use a `:favorites` suffix so the two top-level presentations cannot collide and row resolution remains fail-closed.

For By Repo and By Pane, classify a group by its single semantic repository's `isFavorite`. For By Tab, stable-partition each tab's projected rows by `row.repo.isFavorite`, create section-qualified favorite group and row identities, and place those group presentations in the top-level Favorites section. The remaining tab groups appear under Tabs. Every leaf destination occurs once. The section-qualified group identity is also the disclosure identity: a mixed tab's Favorites and Tabs presentations collapse independently, and collapse state does not transfer when a repository moves between sections.

## List-entry cutover

Extend the list-entry vocabulary with section-header, loading-label, and
loading-repository entries whose IDs cannot collide with group IDs. Flatten
every mode as optional Favorites header and groups, then the required normal
header and groups; each group expands directly to its leaves. Remove the
obsolete nested group-section-header entry and the view's separate global
loading `Section`. Visible-worktree reporting ignores section and loading
entries exactly as it ignores group headers.

## Removed path

The pre-cutover predecessor path was:

```text
toolbar / command / IPC request
  → AppCommand.setRepoSidebarVisibilityMode catalog + IPC projection
  → App command decoding and RepoExplorer command presentation
  → AppDelegate shell-command validation/execution
  → RepoExplorerSidebarPrefsAtom.repoVisibilityMode
  → WorkspaceSettingsStore hydration/write
  → RepoExplorerSnapshot.visibilityMode
  → RepoExplorerProjection favorite filter + favorite-only empty state
```

Current HEAD realizes removal of every active edge in that path:

- delete `RepoExplorerVisibilityMode` and `RepoExplorerVisibilityButton`;
- delete the callback/injection and presentation-batch edges from `SidebarSurfaceHost`, `RepoExplorerView`, and RepoExplorer command presentation;
- delete `setRepoSidebarVisibilityMode` from `AppCommand`, its catalog, resolver/shortcut policy, execution argument decoding, IPC exposure/argument contract, AppDelegate validation/execution, and programmatic-control contract;
- delete the preference atom field/mutator/hydration parameter and `WorkspaceSettingsStore` observation, decode, encode, and reset edges;
- delete the snapshot field, projection filter branch, favorites-only empty state, and the global UI empty-state branch;
- delete or replace performance/smoke script invocations and source-architecture assertions that use the command as an automation trigger.

The projection always consumes all repositories before query filtering. The current SQLite schema retains its non-null `visibility_mode` column and the repository DTO retains the corresponding storage field solely for row-shape compatibility. Application hydration ignores it, repository reads clamp it to `all`, and writes persist the fixed legacy-compatible `all` token. No application preference, command, projection, or observable behavior reads it. Tests distinguish inert schema compatibility from active runtime behavior.

## State and failure behavior

Favorite mutation continues through the existing command dispatcher to topology state. `RepoExplorerView` increments the existing projection request generation, cancels its prior request task, and sends the current snapshot through `RepoExplorerProjectionWorker`. The worker forwards caller cancellation to its detached computation. The main-actor apply gate independently rejects results whose generation or request facts no longer match. Only the newest matching result atomically replaces rendered ordering. No new state, lifecycle, cache, coordinator, or async lane is added. Projection failure retains the existing last-good/degraded disposition.

## Proof seams

- Pure projection tests inspect section identities, group membership, within-section sort, and By Tab stable partition.
- Row-index tests inspect flattened entry order, stable group/leaf resolution, and favorite-mutation transitions against distinct stored Favorites and normal-section collapse keys.
- Projection-worker tests observe cancellation forwarding. View-level projection tests exercise generation and request-fact rejection before main-actor apply without adding worker-owned task state.
- Existing command exhaustiveness, IPC, settings, script, and architecture tests are updated to prove the removed path has no active residue.
- Native UI proof uses the standard debug observability launcher and Peekaboo/Computer Use against the exact debug PID.

## Tradeoffs

- Non-collapsible section labels spend vertical space but avoid a third disclosure state and hidden favorite content.
- By Tab may present the same tab label once in Favorites and once in Tabs when
  that tab contains both kinds of leaf. Distinct group identities and unique
  leaves pay a small repeated-context cost to keep Favorites top-level and
  prevent duplicate destinations.
- Legacy SQLite column retention, if required, pays a small schema residue cost to avoid destructive migration. The value is never hydrated into application state or used for behavior; a fixed inert `all` token may be written only when the unchanged schema/upsert requires it. That compatibility I/O is not an active preference contract.
