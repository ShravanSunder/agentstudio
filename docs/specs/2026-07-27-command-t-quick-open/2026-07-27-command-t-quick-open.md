# Command-T Quick Open

Status: Approved for implementation
Date: 2026-07-27

## Decision Summary

`Command-T` opens a dedicated Quick Open root. It must not be represented as
the `#` repository prefix.

Quick Open is an action-first terminal launcher:

```text
Quick Open
  Current
  Recent
  Repositories & Worktrees
```

Repository rows resolve to their stored main worktree, falling back to the
first live worktree only when no main worktree exists. Worktree rows target
their concrete filesystem location. Directory rows target their exact
filesystem path.

`Current` contains the useful starting points available now, deduplicated by
normalized path while preserving this order:

1. the focused worktree, or the focused pane's exact cwd when it has no
   worktree;
2. the first watched-folder root;
3. the user's home folder.

`Recent` contains up to five recently opened repository or worktree targets
that are not already present in `Current`.

Activation is immediate:

```text
Return          open a terminal pane in the current tab;
                when no current tab exists, open a terminal in a new tab

Command-Return  open a terminal in a new tab

Option-Return   open a terminal pane in the current tab;
                unavailable when no current tab exists

Tab             enter the selected location's existing action menu

Shift-Tab       return exactly one navigation level

empty Backspace return exactly one navigation level

Escape          dismiss the entire Command Bar
```

Selected repository and worktree rows expose a visible trailing actions
affordance so mouse users can enter the same menu without discovering the Tab
shortcut. Directory rows are immediate terminal actions and have no child
menu.

`#` remains the object-first repository navigator. Return on a repository or
worktree row in `#` enters its menu instead of performing Quick Open's immediate
terminal action.

## Product Intent

`Command-T` serves the shortest path from a useful filesystem starting point
to a usable pane. It should let a user choose a current directory or a recent
or searched repository/worktree and open a terminal without traversing
repository management menus.

Less-frequent actions remain one level away in the existing location menu:

- terminal pane in the current tab;
- terminal in a new tab;
- copy path and reveal in Finder;
- repository worktrees;
- Review and Files panes, including new-tab variants;
- navigation to panes already open at the location.

## Requirements

1. `Command-T` has a distinct Quick Open scope and breadcrumb identity.
2. Opening through `Command-T` never inserts or aliases the `#` prefix.
3. Empty Quick Open shows `Current`, `Recent`, and
   `Repositories & Worktrees` without duplicating a normalized path.
4. `Current` projects the focused worktree-or-cwd, first watched root, and home
   as separate rows in that order.
5. `Recent` shows at most five live repository or worktree launch targets that
   are not already in `Current`.
6. A meaningful query removes the current/recent projection and searches the
   complete live repository/worktree candidates.
7. Immediate repository/worktree actions re-resolve current topology before
   dispatch; directory actions reject paths that are no longer directories.
8. Tab enters actions only when the selected row has a child action menu.
9. Shift-Tab and empty Backspace pop one level; neither dismisses the panel.
10. Escape dismisses the complete Command Bar from every level.
11. Existing `#`, `$`, `>`, and Main activation semantics remain unchanged.

## Boundary

```text
AppShortcut.newTab / Command-T
  -> CommandBarScope.quickOpen
  -> Quick Open target projection
  -> existing workspace terminal owner

selected repo/worktree --Tab--> existing action-menu builders
selected directory ---------> immediate terminal action

"#" prefix
  -> CommandBarScope.repos
  -> existing repository navigator projection
```

Quick Open owns entry identity, projection, and primary activation semantics.
Repository topology remains the source of truth for live repositories,
worktrees, and watched roots. Focused pane state owns the current cwd.
`FileManager` supplies the home directory. Existing workspace action handlers
continue to own pane/tab creation.

## Non-Goals

- No new SQLite tables, migrations, or persistence abstractions.
- No duplication of repo/worktree action-menu construction.
- No change to repository/worktree ownership or topology.
- No arbitrary Commands-root verbs in Quick Open.
- No new generic router, service locator, or command framework.

## Tradeoffs

The target-first design makes terminal creation one action and keeps Review,
Files, path, and navigation actions one level away. Current directory choices
extend only the empty projection; Recent and meaningful search remain bounded
to discovered repositories and worktrees.

Tab is reserved for forward navigation while Quick Open owns the search field.
This departs from ordinary focus traversal, so the footer and trailing actions
affordance must teach it. Shift-Tab provides the matching one-level reverse
operation.

## Proof Expectations

- Shortcut routing proves `Command-T` opens Quick Open rather than `#`.
- Projection tests prove Current ordering, empty and searched section
  boundaries, and normalized-path deduplication.
- Activation tests prove Return, Command-Return, Option-Return, Tab, Shift-Tab,
  empty Backspace, and Escape.
- Existing `#` navigation tests prove its object-menu behavior does not change.
- Native UI proof verifies the visible actions affordance, footer hints, and
  keyboard navigation in the launched debug app.
