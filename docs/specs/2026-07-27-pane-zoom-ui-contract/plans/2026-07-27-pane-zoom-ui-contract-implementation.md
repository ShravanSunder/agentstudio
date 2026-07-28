# Pane Zoom UI Contract Implementation Plan

## Source coverage

- Accepted source:
  `docs/specs/2026-07-27-pane-zoom-ui-contract/2026-07-27-pane-zoom-ui-contract.md`
- Coverage: the complete accepted spec was re-read before this revision.
- Existing command owner: `AppCommand.zoomPane.definition`.
- Existing runtime owner: `WorkspacePanePresentationAtom`.
- Security context: no IPC exposure, privileges, token escrow, filesystem
  authority, or Bridge protocol changes. BridgeWeb receives one
  presentation-only change that stops rendering an existing transport ID.

## Goal

Make the current Pane Zoom implementation match the accepted UI contract
without changing Zoom ownership, durable pane membership, or companion
lifecycle.

## Non-goals

- CommandContext restoration.
- Bridge protocol or transport-identity changes.
- A new toolbar framework.
- New Zoom state or persistence.
- Active-Zoom pane retargeting from Arrangements.

## Requirements and proof matrix

| Requirements | Owning slice | RED proof | GREEN proof | Freshness guard |
| --- | --- | --- | --- | --- |
| R1-R4, R17 | Command and toolbar | Command name, canonical icon, icon-only bottom control, exact toolbar-order/geometry, and divider tests fail against the current presentation | Focused command and toolbar presentation/mount tests pass | Run after final toolbar diff |
| R5 | Location actions | Toolbar mount test fails because Copy Path is absent | Copy Path presence, order, enabled state, tooltip, and callback tests pass | Run after final trailing-action diff |
| R6-R9, R16 | Arrangements UI | Display/projection/presentation tests fail for the selected-row active state, missing explicit Cancel Zoom action, popover dismissal, and unstable rename | Arrangement model, popover state, rename, and mounted-view tests pass | Run after final panel/model diff |
| R10, R15, R20 | Zoom and Viewer chrome | Container/title/File Viewer tests fail for missing or misplaced management Cancel Zoom control, visible transport ID, Viewer ordinal, or missing live `· Zoom` title | Container, File Viewer, and management-title tests pass for Default and named arrangements | Run after final native/BridgeWeb diff |
| R11-R14 | Arrangement transitions | Existing lifecycle test is inverted to require preservation and fails while switch clears Zoom; creation test fails while disabled or persisted incorrectly | Switch, traversal, creation, persistence-exclusion, and real teardown tests pass | Run after final coordinator/store diff |
| R18 | Viewer split memory | Runtime-state test fails because Cancel Zoom deletes the only saved ratio | Per-source runtime memory restores the ratio across hide/show and Cancel/re-entry while SQLite exclusion remains green | Run after final presentation-atom diff |
| R19 | Spatial transitions | Transition-state/native proof shows instantaneous replacement and Viewer appearance | Zoom expands/contracts from the durable source frame and Viewer opens/closes from center with host continuity | Capture native recording after final container diff |
| All | Integrated UI | Existing debug app shows stale UI | Fresh PID-targeted screenshots cover all five named states | Capture from a newly built app at final HEAD |

Every behavior row requires observed red/green evidence. If a focused test
passes before its production change, strengthen it until it demonstrates the
missing contract rather than accepting a false RED.

## Execution DAG

```text
gate 0: accepted spec + dirty-worktree overlap audit
  |
  v
slice 1: command identity and pure presentation RED/GREEN
  |
  v
slice 2: toolbar composition and Copy Path RED/GREEN
  |
  v
slice 3: Arrangements model/view/popover/rename and transition RED/GREEN
  |
  v
slice 4: Zoom management chrome/title and Viewer projection RED/GREEN
  |
  v
targeted integration gate
  |
  v
format + lint + full relevant tests + build
  |
  v
fresh native screenshot gate
  |
  v
implementation-review-swarm
```

Execution is serial because `DrawerIconBar`, `ArrangementPanel`,
`ZoomPresentationContainer`, and the coordinator/test harnesses are already
overlapping uncommitted work. Parallel production edits would create ambiguous
ownership and conflict risk.

## Slice 1 — Typed command and presentation contract

Requirements: R1-R4 and R17.

Likely files:

- `Sources/AgentStudio/App/Commands/AppCommand+Catalog.swift`
- `Sources/AgentStudio/Core/Views/Panes/PaneSurfaceToolbarPresentation.swift`
- command and toolbar presentation tests

Work:

- Change the existing `zoomPane` command spec icon to
  `arrow.down.left.and.arrow.up.right.rectangle`.
- Rename the command to `Pane Zoom`; keep tooltip, visibility, capability, and
  IPC exposure command-owned.
- Keep the bottom toolbar control icon-only.
- Remove the separate cancel-Zoom action from the presentation model.
- Express Viewer as the first trailing Zoom context action, not a leading pane
  mode action.

Checkpoint: pure presentation tests prove the canonical command state and exact
normal/Zoom membership.

Split trigger: stop if the existing command spec cannot project every Zoom
surface without a new command or parallel descriptor.

## Slice 2 — Toolbar composition and location actions

Requirements: R3-R5 and R17.

Likely files:

- `Sources/AgentStudio/Core/Views/Drawer/DrawerOverlay.swift`
- `Sources/AgentStudio/Core/Views/Drawer/DrawerIconBar.swift`
- `Sources/AgentStudio/Core/Views/Panes/PaneSurfaceToolbarHost.swift`
- toolbar mounting/geometry tests

Work:

- Render exact normal and Zoom group order.
- Add Copy Path through the existing command/path action and actual source CWD.
- Share Finder and Copy Path availability; do not substitute a worktree root
  when live terminal CWD is unavailable.
- Replace two-point divider padding with
  `AppStyles.General.Spacing.standard`.
- Preserve square control geometry, typed tooltips, accessibility bridges, and
  Drawer Toggle/Add adjacency.

Checkpoint: mounted toolbar tests prove order, geometry, callbacks, availability,
and divider spacing.

Split trigger: stop if Copy Path requires a new global service or a second path
source.

## Slice 3 — Arrangements UI and durable transition behavior

Requirements: R6-R9, R11-R14, and R16.

Likely files:

- `Sources/AgentStudio/Core/Models/ArrangementPanelModels.swift`
- `Sources/AgentStudio/Core/State/MainActor/Atoms/ArrangementDerived.swift`
- `Sources/AgentStudio/Core/Views/Panes/ArrangementPanel.swift`
- arrangement action/coordinator files that currently clear Zoom
- arrangement display, projection, lifecycle, store, and persistence tests

Work:

- Add canonical Zoom affordances to Zoom-capable normal pane rows.
- Keep Pane Visibility hidden during active Zoom.
- Render one Pane Zoom status/details block using
  `repo | branch | worktree folder`, full actual CWD, and explicit
  icon-and-text `Cancel Zoom`; remove selected-list styling.
- Keep the Arrangements popover open for Zoom, arrangement
  selection/creation, and rename actions.
- Reproduce and repair the inline rename focus/flicker regression at its source.
- Keep arrangement creation enabled during Zoom.
- Route creation through the real validated command path.
- Preserve Zoom and retained companion across arrangement switch, traversal,
  and creation.
- Treat the active Zoom source as effectively visible when an underlying
  arrangement minimizes it; reconcile its surface after explicit Zoom exit.
- Do not silently cancel Zoom when reusing a durable Files/Review pane.
- Move the split ratio from one active presentation's disposable state to
  per-source retained runtime memory, restoring it across Viewer hide/show and
  Cancel/re-entry without persisting it.
- Add state-driven spatial transitions using existing pane geometry and
  standard animation timing; preserve the same terminal and Viewer hosts
  throughout every transition.
- Save only the underlying durable arrangement and reveal the latest selected
  arrangement when Zoom exits.
- Preserve existing teardown and invalid-resource cancellation.

Checkpoint: display/projection tests plus lifecycle and persistence integration
tests prove the complete arrangement contract.

Split trigger: stop if preserving Zoom would require durable companion
membership or persisting Zoom state.

## Slice 4 — Parent management chrome

Requirements: R10 and R15.

Likely files:

- `Sources/AgentStudio/Core/Views/Panes/ZoomPresentationContainer.swift`
- management presentation helpers and tests

Work:

- Render the canonical selected Zoom control before Arrangements in normal and
  active parent management chrome. Active Zoom presents it as Cancel Zoom and
  keeps it immediately left of Arrangements at the top-left.
- Remove the floating all-caps Zoom badge.
- Keep Viewer child chrome hidden and remove its pane ordinal/raw identity.
- Stop rendering the Bridge File Viewer transport `sourceId` in visible chrome;
  retain it for protocol state and diagnostic data attributes.
- Render `<pane ordinal> · <active arrangement name> · Zoom`, updating the
  arrangement segment live.

Checkpoint: mounted container tests prove child-chrome absence and exact source
management title for Default and named layouts.

Split trigger: stop if the title cannot derive from the existing active
arrangement read model.

## Validation gates

1. Focused RED/GREEN tests after every slice.
2. Focused Zoom, toolbar, Arrangements, lifecycle, persistence, IPC, and Bridge
   regression suites.
3. `mise run format`.
4. `mise run lint`.
5. `mise run test`.
6. `mise run build`.
7. Fresh debug launch and PID-targeted screenshots:
   normal toolbar, Zoom toolbar with Viewer hidden, Zoom toolbar with Viewer
   visible, active Arrangements details, and Zoom management chrome.
8. Requirements/diff audit followed by `implementation-review-swarm`.

## Recovery

All changes are source and test changes over existing uncommitted work. Preserve
the current worktree and do not use destructive Git operations. If a slice
breaks the accepted ownership model, stop at that slice with its passing lower
proof layers and return to the spec rather than adding a compatibility path.

## Open questions

None. The accepted spec resolves the product and interaction decisions required
for implementation.
