# Command-T Quick Open

Status: Draft for product approval
Date: 2026-07-27

## Decision Summary

`Command-T` opens a dedicated Quick Open root. It must not be represented as
the `#` repository prefix.

Quick Open is an action-first location launcher:

```text
Quick Open
  Current Location
  Recent Locations
  All Locations
```

Repository rows resolve to their stored main worktree, falling back to the
first live worktree only when no main worktree exists. Worktree rows target
their concrete filesystem location.

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

The selected location row exposes a visible trailing actions affordance so
mouse users can enter the same menu without discovering the Tab shortcut.

`#` remains the object-first repository navigator. Return on a repository or
worktree row in `#` enters its menu instead of performing Quick Open's immediate
terminal action.

## Product Intent

`Command-T` serves the shortest path from a known filesystem location to a
usable pane. It should let a user choose a current, recent, or searched
repository/worktree and open a terminal without traversing repository
management menus.

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
3. Empty Quick Open shows current, recent, and complete location sections
   without duplicating a location.
4. A meaningful query removes the current/recent projection and searches the
   complete live repository/worktree candidates.
5. Immediate actions re-resolve the selected repository/worktree from current
   topology before dispatch.
6. Tab enters actions only when the selected row has a child action menu.
7. Shift-Tab and empty Backspace pop one level; neither dismisses the panel.
8. Escape dismisses the complete Command Bar from every level.
9. Existing `#`, `$`, `>`, and Main activation semantics remain unchanged.

## Boundary

```text
AppShortcut.newTab / Command-T
  -> CommandBarScope.quickOpen
  -> Quick Open location projection
  -> existing targeted terminal commands

selected location --Tab--> existing repo/worktree action-menu builders

"#" prefix
  -> CommandBarScope.repos
  -> existing repository navigator projection
```

Quick Open owns entry identity, projection, and primary activation semantics.
Repository topology remains the source of truth for live repositories and
worktrees. Existing command handlers continue to own pane/tab creation.

## Non-Goals

- No new SQLite tables, recency entities, or persistence abstractions.
- No duplication of repo/worktree action-menu construction.
- No change to repository/worktree ownership or topology.
- No arbitrary Commands-root verbs in Quick Open.
- No new generic router, service locator, or command framework.

## Tradeoffs

The target-first design makes terminal creation one action and keeps Review,
Files, path, and navigation actions one level away. Projecting every pane kind
for every location would reduce some secondary interactions but multiply rows
and make location search noisy.

Tab is reserved for forward navigation while Quick Open owns the search field.
This departs from ordinary focus traversal, so the footer and trailing actions
affordance must teach it. Shift-Tab provides the matching one-level reverse
operation.

## Proof Expectations

- Shortcut routing proves `Command-T` opens Quick Open rather than `#`.
- Projection tests prove empty and searched section boundaries and
  deduplication.
- Activation tests prove Return, Command-Return, Option-Return, Tab, Shift-Tab,
  empty Backspace, and Escape.
- Existing `#` navigation tests prove its object-menu behavior does not change.
- Native UI proof verifies the visible actions affordance, footer hints, and
  keyboard navigation in the launched debug app.
