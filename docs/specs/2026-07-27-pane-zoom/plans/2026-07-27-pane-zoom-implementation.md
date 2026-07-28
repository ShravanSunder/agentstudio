# Pane Zoom Implementation Plan

## Scope

Implement the adjacent Pane Zoom spec using the current command system. Preserve
unrelated dirty work and do not modify the separate CommandContext follow-up.

## Task 1 — Command and runtime contract

- Narrow `zoomPane` to durable terminal main panes across all invocation paths.
- Make `showViewer` active-Zoom-only and remove durable pane/worktree fallback.
- Add the narrow active-terminal-Zoom visibility fact required by the current
  command catalog.
- Retain source-owned companions across cancel, retarget, and tab switches.
- Remove arrangement-restoration state that is unnecessary when Zoom leaves the
  durable arrangement unchanged.

Proof:

- Red/green command capability and fallback tests.
- Lifecycle integration for enter, cancel, retarget, tab switch, same-worktree
  identity, and teardown.
- Persistence exclusion and unchanged Bridge activity tests.

Stop if implementation requires durable companion membership, a new Bridge
lifecycle, Bridge protocol changes, or a generalized command-surface refactor.

## Task 2 — Typed UI contract

- Render exactly the normal and Zoomed terminal toolbar sequences in the spec.
- Keep Viewer absent outside terminal Zoom.
- Keep Drawer Toggle and Add Drawer adjacent.
- Apply shared spacing, icon-frame, separator, and typed tooltip contracts.
- Hide source and Viewer child toolbars under one Zoom parent toolbar.
- Render the Pane Zoom arrangement section and source identity only while active.
- Keep arrangement creation visible-disabled, hide Pane Visibility, and preserve
  durable arrangement selection.
- Render the Zoom Management cluster and suppress only the controls named by the
  spec.

Proof:

- Red/green presentation and arrangement display tests.
- Source checks proving typed tooltip participation.
- Native debug screenshots for normal, Viewer hidden/visible, Arrangements, and
  Management.

## Task 3 — Integrated verification

- Run focused Zoom, toolbar, arrangement, lifecycle, SQLite, IPC, and Bridge
  regression suites.
- Run formatter/lint, full relevant tests, and build.
- Launch the debug app and inspect screenshots against every UI requirement.
- Review the scoped diff, then commit, push, and open the Pane Zoom PR.

Required completion evidence is command output with exit codes, test/failure
counts, screenshot paths and observations, and a requirement-by-requirement
diff audit.
