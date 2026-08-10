# Repo Sidebar Grouping and Context Menus — Program Design

Date: 2026-08-03

Governing specification:
[Repo Sidebar Grouping and Context Menus](2026-08-03-repo-sidebar-grouping-and-menus.md)

## Integrated design

The existing RepoExplorer projection remains the single feature boundary
between canonical workspace state and sidebar presentation. It gains one
feature-owned pane-destination value and one pane-leaf row variant.

```text
Core canonical state
  WorkspacePaneAtom + WorkspaceTabLayoutDerived
    └─ WorkspaceLookupDerived.paneLocationsByWorktreeId
         owns active pane membership and Tab/Pane ordinals

RepoExplorer snapshot boundary
  RepoExplorerSnapshot
    ├─ repos and worktrees
    └─ pane locations by worktree

RepoExplorer projection
  RepoExplorerProjection
    ├─ By Repo ──► Repo groups + Worktree leaves
    ├─ By Pane ──► Repo groups + Pane leaves
    ├─ By Tab  ──► Tab groups + Worktree occurrences
    └─ pane destinations by worktree for context menus

RepoExplorer render boundary
  RepoExplorerView
    ├─ SidebarCacheState.collapsedGroups
    │    └─ absent group key means expanded
    ├─ RepoExplorerWorktreeRow
    │    ├─ Create New
    │    └─ Go to Pane ──► all exact open pane destinations
    ├─ RepoExplorerPaneRow ──► exact pane focus
    └─ Repo header menu
         ├─ Go to Pane ──► all exact open child-worktree panes
         ├─ Reveal in Finder(repoPath)
         └─ Copy Path(repoPath)

Existing command effect owner
  AppCommand.focusPane(pane ID)
    └─ PaneTabViewController.focusTargetedPane
```

State authority, command execution, repo paths, and workspace ownership do not
move. The new pane values are immutable projection output, not synchronized
product state. Existing projection execution is unchanged; the existing local
sidebar cache changes vocabulary from expanded group IDs to collapsed group
IDs.

## Current system and constraint degree

The change is compatibility-bound by the existing Repo grouping enum, command
identities, projection ownership, targeted pane command, and local sidebar
cache owner. `LocalActionSpec` remains the typed presentation owner for UI-only
menu labels.

The prior cache stores only expanded IDs, so absence conflates explicit
collapse with an unseen group. The target invariant is the inverse:

```text
group key absent from collapsedGroups  -> expanded
group key present in collapsedGroups   -> collapsed
filter active                          -> rendered expanded, memory unchanged
```

`SidebarCollapsedGroupAtom` remains the one in-memory owner and
`SidebarCacheStore` keeps the existing restore, observation, debounce, and save
path. `RepoExplorerProjectionRequest` and `RepoExplorerRowIndex` consume the
collapsed-ID set directly. No initialization pass or second state set is added.

`WorkspaceLocalMigrations` performs a one-time hard cut from
`local_window_sidebar_expanded_group` to
`local_window_sidebar_collapsed_group`. Legacy rows are discarded because no
lossless complement exists without the historical universe of group keys. This
resets only local presentation memory; subsequent collapse and re-expansion
round-trip through the new table.

Observed current paths:

1. Grouping presentation

```text
RepoExplorerView.repoToolbarRow
  ──► SidebarGroupingPopover
       ──► presented AppCommand label: "Group Repos by X"
```

2. Current `By Pane`

```text
RepoExplorerView.makeSidebarSnapshot
  ──► WorkspaceLookupDerived.paneLocationsByWorktreeId
  ──► RepoExplorerProjection.placementGroups(mode: .pane)
       ──► Pane group header
            └─ Worktree occurrence
```

3. Current worktree navigation

```text
RepoExplorerWorktreeRow.Open Worktree
  ──► AppCommand.openWorktree(worktree ID)
  ──► WorkspaceSurfaceCoordinator.openTerminal
       └─ selects the first containing tab or creates a terminal tab
```

4. Existing exact-pane precedent

```text
CommandBar worktree "Navigate to" row
  ──► AppCommand.focusPane(pane ID)
  ──► PaneTabViewController.focusTargetedPane
       └─ selects the containing tab and exact pane
```

5. Current group-header menu

```text
Any RepoExplorer group header, including Tab groups
  ──► primaryRepoForGroup
       ├─ Reveal in Finder(primary repoPath)
       └─ Refresh Worktrees
```

The target changes only the presentation and projection edges. Canonical state,
target validation, focus execution, and projection execution remain in their
current owners.

## Structural crux and selected direction

The crux is whether pane presentation becomes an explicit leaf type or remains
encoded as a duplicated worktree row with placement text.

### Selected: explicit pane destinations and pane leaves

Introduce immutable RepoExplorer-owned values:

```swift
struct RepoExplorerPaneDestination: Equatable, Sendable, Identifiable {
    let paneId: UUID
    let repoId: UUID
    let worktreeId: UUID
    let worktreeLabel: String
    let tabId: UUID
    let tabIndex: Int
    let paneIndexInTab: Int
    let isActiveInTab: Bool
}

struct RepoExplorerProjectedPaneRow: Equatable, Sendable {
    let groupId: String
    let repoId: UUID
    let destination: RepoExplorerPaneDestination
    let rowId: String
}
```

The exact declaration may follow existing package-visibility conventions, but
the behavioral interface is fixed:

- identity is the exact pane ID;
- repository and worktree IDs establish containment;
- the worktree label is an immutable projection fact, while the current pane
  display label is resolved by the RepoExplorer container for a visible row or
  menu item through the existing Core derived reader;
- location order is ascending tab index, ascending pane index, then pane ID;
- no value can create, retain, or mutate a Pane.

This makes pane navigation explicit and prevents a pane leaf from accidentally
inheriting worktree creation or context-menu behavior.

### Rejected: keep pane occurrences as worktree rows

Changing only group headers while retaining
`RepoExplorerProjectedWorktreeRow` would keep the wrong action identity:
the leaf would still expose worktree creation, favorite, editor, and path
behavior even though its primary identity is a pane. Conditional hiding would
spread mode checks through rendering and menus.

### Rejected: add a new pane-navigation store

Canonical pane membership, titles, and focus already have owners. A new store
would duplicate state and require synchronization without serving any
requirement.

The selected direction spends one immutable read-model variant and one pure
row view. It adds no durable state. Revisit only if another feature needs the
same destination model with identical product semantics; shared extraction
before then would be premature.

## Components, ownership, and interfaces

### Canonical state owners — unchanged

- `WorkspacePaneAtom` owns panes, content, worktree association, and
  residency.
- `WorkspaceTabLayoutDerived` exposes tab membership and active-pane
  placement.
- `WorkspaceLookupDerived` owns canonical worktree-to-pane location
  derivation.
- `PaneDisplayDerived` owns the current pane display label.
- `PaneTabViewController` owns validation and the focus side effect.

### RepoExplorer snapshot boundary — extended

`RepoExplorerView.makeSidebarSnapshot` continues to pass the existing repos,
worktrees, and `paneLocationsByWorktreeId` into the projection worker. It does
not add pane objects or a pane-label map.
Canonical atom reads and immutable request construction remain MainActor work;
they do not perform destination aggregation, grouping, or sorting.

### RepoExplorer projection — extended

`RepoExplorerProjection` derives one
`RepoExplorerPaneDestination` per canonical pane location and exposes:

- destinations keyed by worktree ID for worktree menus;
- repo aggregation by traversing that repo's child worktree IDs for repo
  menus; and
- projected pane rows grouped by repo for `By Pane`.

Destination maps and repository aggregates are derived from the snapshot's
complete repo/worktree topology and canonical pane locations before query
filtering narrows visible worktrees. Search therefore changes visible rows but
cannot remove valid pane destinations from a context-clicked repository's
menu.

`By Repo` and `By Tab` continue to produce existing worktree rows.
`By Pane` produces pane rows only. The Inactive group is removed from that
branch. Its repository groups use the same resolved-metadata and configured
sort-order policy as `By Repo`, then omit groups with no pane rows; destination
children retain their independent tab-index and pane-index order.

Destination construction, full-topology repo aggregation, pane-row projection,
grouping, sorting, and row-index construction stay inside the existing
RepoExplorer projection boundary. No new product state or command path is
introduced.

### Row index — explicit variants

`RepoExplorerListEntry` gains an exact pane-row variant. The row index keeps
separate lookup maps for projected worktree rows and pane rows and resolves
each variant through its own typed context.

Forbidden edges:

- a pane row resolving through `RepoExplorerResolvedWorktreeContext`;
- a worktree callback receiving a pane ID as if it were a worktree ID;
- a projection value invoking the command dispatcher;
- a menu or row reading ambient atoms after receiving its immutable values.

The enum and typed resolver enforce the first two boundaries; existing target
type validation enforces the command boundary.

### Render and menu composition

`RepoExplorerView` resolves the current pane display label for each visible
destination through `PaneDisplayDerived`, then passes direct values into the
pure `RepoExplorerPaneRow`. The row renders the destination and invokes one
supplied focus callback.

Those visible-only label reads remain on MainActor because
`PaneDisplayDerived` reads canonical product state. MainActor also retains
SwiftUI menu/row composition, projection installation, and exact-focus
dispatch. None of those edges repeats full-workspace aggregation or sorting.

One feature-owned pane-destination menu-content view renders the same
destination grammar for:

- the clicked worktree's destination array; and
- the clicked repo's child-worktree aggregate.

It accepts immutable destinations, pane display labels resolved by its
RepoExplorer container, and a `paneId` callback. It does not read atoms or
decide scope.

`LocalActionSpec.createNew` owns the new wrapper submenu's label, help text,
and icon. This is typed presentation for reorganizing existing creation
commands, not a new command identity or action effect. The existing
`openInCurrentTabMenu` and `openInNewTabMenu` cases continue to own their
unchanged child submenu presentation.

The worktree and repo containers include `Go to Pane` only when their
scoped destination array is nonempty. A repo with no destinations therefore
renders only `Reveal in Finder` and `Copy Path`.

The group-header context menu is conditional on semantic grouping mode:

- `By Repo` and `By Pane`: the header is a repo and receives only the allowed
  repo actions in their specified order;
- `By Tab`: the header is a tab and receives no repo path menu.

## Current-to-target call-path deltas

### Grouping labels

```text
[changed]
Repo grouping popover
  current  ──► AppCommand.commandSpec.label
  target   ──► RepoExplorerGroupingMode popover label "By X"

[intentionally unchanged]
Command bar / IPC ──► AppCommand command-style label and identity
```

### `By Pane` projection and activation

```text
[intentionally unchanged]
Workspace canonical pane/tab state
  ──sync read──► WorkspaceLookupDerived locations

[changed]
locations + repo/worktree projection facts
  current  ──worker──► Pane groups + Worktree rows + Inactive group
  target   ──worker──► Repo groups + exact Pane rows; no Inactive group

[added]
RepoExplorerPaneRow activation
  ──sync──► AppCommand.focusPane(pane ID, target type .pane)
  ──sync──► PaneTabViewController.focusTargetedPane
  ──effect► exact tab and pane selection

[removed]
Pane-mode leaf ──► worktree creation/favorite/editor/path callbacks
```

### Worktree menu

```text
[changed presentation]
Worktree context menu
  ├─ LocalActionSpec.createNew ──► Create New
  │    ├─ Open in Current Tab ──► existing command leaves
  │    └─ Open in New Tab     ──► existing command leaves
  └─ Go to Pane
       └─ all exact open pane destinations for clicked worktree

[changed navigation effect]
Go to Pane destination
  current  ──► openWorktree(worktree ID) ──► first containing tab/create
  target   ──► focusPane(pane ID) ──► exact existing pane

[intentionally unchanged]
Double-click worktree row ──► openWorktree(worktree ID)
Existing creation leaves    ──► existing commands and effects
```

### Repo header menu

```text
[changed]
Context-click semantic repo header
  ├─ Go to Pane
  │    └─ all exact open destinations across child worktrees
  │         ──► focusPane(selected pane ID)
  ├─ Reveal in Finder(clicked repo.repoPath)
  └─ Copy Path(clicked repo.repoPath)

[removed]
Repo header ──► Refresh Worktrees
Tab header  ──► primaryRepoForGroup ──► repo path actions

[intentionally unchanged]
PathActions owns Finder and pasteboard effects.
```

## State, failure, and consistency

| Value | Owner | Lifetime | Consistency |
| --- | --- | --- | --- |
| pane/worktree/tab truth | existing Core atoms | workspace | canonical MainActor state |
| pane destinations | RepoExplorer projection result | one projection result | immutable snapshot |
| menu visibility/content | SwiftUI render | current menu presentation | derived from admitted result |
| focused pane | existing pane/tab owners | workspace | mutated only by targeted focus command |

If a destination becomes stale after rendering:

1. the menu or row sends the exact pane ID;
2. existing `canFocusTargetedPane` / targeted dispatch validation cannot
   resolve it;
3. no focus, creation, fallback, preference mutation, retry, or compensation
   occurs.

This is a contained no-op.

Pane identity, rather than visible index or label, resolves the action, so
reordered or duplicate labels cannot retarget it.

## Cross-cutting realization

- Accessibility: pane rows and menu items expose the same destination label
  and exact focus action; semantic repo menus attach only to repo headers.
- Reliability: existing projection validation rejects stale structural results;
  targeted command validation rejects stale activation.
- Privacy and security: no new data leaves the process, no path is added to
  telemetry, and authenticated IPC contracts do not change.
- Persistence and compatibility: the three grouping enum values and their
  stored preference remain unchanged. The sidebar group cache hard-cuts once
  from expanded IDs to collapsed IDs; no dual path exists.

## Requirement realization and proof seams

| Requirement | Realization owner | Observable seam | Enforcement |
| --- | --- | --- | --- |
| R1 | Repo grouping popover adapter | rendered three labels | presentation test plus native UI |
| R2 | RepoExplorerProjection + typed row index | projected group/leaf identities and exact activation | projection/row-index tests plus native UI |
| R3 | RepoExplorerWorktreeRow + destination menu content | menu hierarchy and targeted dispatch | menu-structure and dispatcher integration proof |
| R4 | Repo header menu composition | allowed ordered actions, conditional navigation, repo aggregate, clicked repoPath | projection/menu tests plus Finder/clipboard boundary proof |
| R5 | RepoExplorerPaneDestination + Repo group ordering | labels, leaf ordering, stable IDs, By Repo/By Pane header-order parity | pure model/projection tests plus native visual proof |
| R6 | existing targeted focus validation | no state change for stale pane ID | integration state inspection |
| R7 | SidebarCollapsedGroupAtom + SidebarCacheStore + WorkspaceLocalMigrations | unseen groups expand; collapse inserts and re-expansion removes one stable key | atom, row-index, repository, migration, and relaunch proof |

Production-real proof keeps canonical atoms, projection worker, command
dispatcher, and focus executor real. Pure projection fixtures may substitute
immutable repo/pane inputs. Native UI proof remains necessary for menu nesting,
label readability, semantic header attachment, and exact non-current pane
activation.

No new architecture lint rule is warranted: the existing target boundaries,
typed row variants, and targeted command validation provide the structural
enforcement.
