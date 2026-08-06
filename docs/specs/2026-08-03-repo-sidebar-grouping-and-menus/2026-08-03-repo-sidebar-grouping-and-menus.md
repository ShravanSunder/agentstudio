# Repo Sidebar Grouping and Context Menus

Date: 2026-08-03

## Goal and boundary

The Repo sidebar must make its three perspectives and its repository,
worktree, and pane actions match the object the user is looking at.

This specification changes only:

- the visible labels in the Repo grouping popover;
- the Repo sidebar group-expansion default and local memory vocabulary;
- the Repo sidebar's `By Pane` hierarchy;
- the worktree-row context-menu hierarchy; and
- the repository-header context menu.

Inbox grouping and menus, Repo grouping-mode persistence and command identities,
worktree-row double-click behavior, and the existing creation actions are not
redesigned. The existing local sidebar-group cache is inverted from expanded
IDs to collapsed IDs; no second persistence surface, user-facing action,
command transport, service, or external dependency is introduced.

This specification supersedes only the Repo-specific assumptions in
[Sidebar List Architecture](../2026-07-16-sidebar-list-architecture/2026-07-16-sidebar-list-architecture.md)
that `By Pane` uses Pane headers containing worktree rows or an Inactive
worktree group. Its shared identity and interaction requirements otherwise
remain authoritative where they do not conflict with this specification.

## User needs

| ID | Authorized need | Priority |
| --- | --- | --- |
| U1 | The grouping chooser uses short labels that fit the compact sidebar control. | Must |
| U2 | `By Pane` shows the panes belonging to each repository instead of using each pane as a container for a worktree row. | Must |
| U3 | A worktree menu separates creation from navigation and lets the user choose an exact existing pane for that worktree. | Must |
| U4 | A repository-header menu navigates every open pane in its child worktrees and otherwise contains only its three required repository actions. | Must |
| U5 | Repository groups start open while explicit collapse and re-expansion remain remembered locally. | Must |

## Current observable problem

- The grouping popover displays command-style labels such as
  `Group Repos by Tab`, which repeat context already supplied by the control.
- `By Pane` currently creates Pane group headers and places worktree rows under
  them. A Repo sidebar user looking for a repository's panes must scan an
  inside-out hierarchy.
- `Open Worktree` currently chooses a containing tab when a worktree is
  already open. It does not let the user choose among multiple panes.
- The worktree menu mixes navigation with creation at its top level.
- The repository-header menu currently contains `Reveal in Finder` and
  `Refresh Worktrees`; it neither navigates the repository's open panes nor
  provides the required repository path actions.

## Required perspectives

### R1. Compact grouping labels

The Repo grouping popover MUST label its choices exactly:

- `By Repo`
- `By Pane`
- `By Tab`

This is a surface-specific presentation rule. Command-palette and headless
command labels MAY remain command-style labels.

### R2. Perspective hierarchies

The perspectives MUST render these semantic hierarchies:

```text
By Repo                     By Pane                    By Tab
Repo header                 Repo header               Tab header
  Worktree leaf               Exact pane leaf           Worktree occurrence
```

`By Repo` and `By Tab` preserve their current behavior. In `By Tab`, one
worktree occurrence remains visible for each exact active pane, including
duplicates for the same worktree within one tab.

`By Pane` MUST:

- group by repository;
- list every active-residency pane belonging to the repository's child
  worktrees in the current workspace;
- omit repositories with no pane leaves;
- omit the current Inactive worktree group; and
- make each pane leaf a navigation-only row whose primary activation focuses
  that exact pane.

`By Pane` MUST NOT inherit worktree-row creation, double-click, or context-menu
behavior.

## Required context menus

### R3. Worktree-row menu

The worktree-row context menu MUST begin with:

```text
Create New                 ›
  Open in Current Tab      ›  existing actions unchanged
  Open in New Tab          ›  existing actions unchanged
Go to Pane                 ›  all exact open panes for this worktree
```

`Create New` reorganizes the two existing creation submenus; it does not add,
remove, flatten, or rename their leaf actions.

`Go to Pane` MUST:

- appear immediately below `Create New`;
- be omitted when the clicked worktree has no active pane;
- list only exact active panes belonging to the clicked worktree; and
- focus the selected exact pane without creating content or falling back to a
  different pane.

The existing Favorite, Open in Editor, Reveal in Finder, and Copy Path sections
below these entries remain unchanged.

### R4. Repository-header menu

This menu MUST be attached only to a semantic repository header in `By Repo`
or `By Pane`. A `By Tab` header MUST NOT select an arbitrary repository or
expose repository path actions.

The repository-header context menu MUST contain only the following entries, in
this order when present:

```text
Go to Pane                 ›  all exact open panes across child worktrees
Reveal in Finder
Copy Path
```

`Go to Pane` MUST:

- be omitted when none of the repository's child worktrees has an active pane;
- include every exact active pane belonging to every child worktree of the
  context-clicked repository; and
- focus the selected exact pane without creating content or falling back to a
  different pane.

`Reveal in Finder` and `Copy Path` MUST both use the `repoPath` of the
context-clicked repository. Context-clicking one repository MUST NOT act on a
previously selected repository.

`Refresh Worktrees` is removed from this menu. No Create, Favorite, Editor,
Remove Repo, or other unlisted action is added.

## Pane destination contract

### R5. Identity, labels, and order

Every pane destination in `By Pane` or a `Go to Pane` submenu MUST:

- carry the exact pane identity used for navigation;
- identify its child worktree, the current
  `PaneDisplayDerived.displayLabel(for:)` value, `Tab N`, and `Pane N`; the
  derived label's existing `Terminal` fallback remains authoritative;
- mark `Active` when it is the selected pane within its tab;
- remain distinguishable when panes or worktrees have similar titles; and
- sort by current workspace tab index, then pane index, using stable pane
  identity only as a non-visible tie-breaker.

Repository ordering in `By Pane` preserves the existing Repo ordering policy.

### R6. Stale destinations

If a pane closes after a menu or projection was produced but before activation,
the action MUST be rejected by the existing targeted-command validation. It
MUST NOT create a new pane, focus another pane, or mutate sidebar preferences.

### R7. Expanded-by-default group memory

Every Repo sidebar group without a collapsed-group record MUST render expanded.
Collapsing a group MUST add its stable group key to local memory; re-expanding
it MUST remove that key. Both states MUST survive relaunch through the existing
`local.sqlite` sidebar cache. Filtering MAY temporarily force a group open but
MUST NOT mutate its remembered state.

The prior expanded-ID cache cannot distinguish an explicitly collapsed group
from a group that has never been seen. Its rows are reset once during the hard
cut to collapsed-ID memory; after that cut, absence consistently means
expanded.

## Accessibility and quality constraints

- Every menu and pane leaf MUST expose the same visible action meaning to
  accessibility clients.
- Pane navigation MUST use the existing typed exact-pane command path.
- The UI MUST derive pane destinations from the current workspace's canonical
  pane and tab state; it MUST NOT introduce a synchronized product-state copy.
- This change introduces no new security, privacy, network, persistence, or
  observability surface.

## Requirement and proof coverage

| Need | Problem | Outcome | Requirement / contract | Proof obligation |
| --- | --- | --- | --- | --- |
| U1 | P1 long repeated labels | O1 compact chooser | R1 exact labels | V1 automated presentation plus native visual evidence |
| U2 | P2 inside-out Pane hierarchy | O2 Repo-to-pane navigation | R2, R5 | V2 projection behavior plus native activation evidence |
| U3 | P3 creation/navigation mixed and pane choice ambiguous | O3 worktree-scoped exact navigation | R3, R5, R6 | V3 menu structure, exact focus, empty and stale cases |
| U4 | P4 repo menu lacks child-pane navigation and the required path-action set | O4 repo-scoped exact navigation and path actions | R4-R6 | V4 menu structure, aggregate destinations, clicked-repo path evidence |
| U5 | P5 absent expansion rows currently mean collapsed | O5 groups open by default with durable collapse memory | R7 | V5 unseen, collapse/relaunch, re-expand/relaunch, and migration behavior |

Automated behavior evidence must distinguish exact-pane focus from containing-
tab selection. Manual native UI evidence must show the compact labels, all
three context-menu structures, pane destination disambiguation, and activation
of a non-current pane. State inspection must show that stale targets and path
actions cannot affect a different pane or repository. Persistence evidence must
show that unseen groups open, collapsed IDs round-trip, and re-expansion removes
the remembered collapsed ID.

## Source anchors

- Grouping popover presentation:
  `Sources/AgentStudio/Features/RepoExplorer/RepoExplorerView.swift`
- Current projection and Pane/Tab placement:
  `Sources/AgentStudio/Features/RepoExplorer/Models/RepoExplorerProjection.swift`
- Current row index:
  `Sources/AgentStudio/Features/RepoExplorer/Models/RepoExplorerRowIndex.swift`
- Current worktree menu:
  `Sources/AgentStudio/Features/RepoExplorer/RepoExplorerWorktreeRow.swift`
- Canonical workspace pane locations:
  `Sources/AgentStudio/Core/State/MainActor/Atoms/WorkspaceLookupDerived.swift`
- Exact pane focus:
  `Sources/AgentStudio/App/Panes/PaneTabViewController.swift`
- Existing command-bar pane navigation precedent:
  `Sources/AgentStudio/Features/CommandBar/CommandBarDataSource+WorktreeRows.swift`
