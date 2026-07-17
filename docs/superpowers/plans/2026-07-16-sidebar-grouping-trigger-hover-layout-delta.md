# Sidebar Grouping Trigger, Hover, and Inbox Layout Delta Plan

Status: accepted chat design; ready for implementation
Date: 2026-07-16
Base plan: `docs/superpowers/plans/2026-06-20-sidebar-grouping-icons-ipc-performance-delta.md`

## Outcome

- Repo and Inbox use the same stable `rectangle.grid.1x3` grouping trigger.
- The trigger renders the stable icon, current grouping label, and disclosure chevron.
- Grouping stays anchored at the far right in both sidebar toolbar rows, separated from preceding actions by a divider.
- Inbox notification-history deletion moves from the search row into the toolbar before sort; grouping remains last after its divider.
- Shared sidebar toolbar controls expose visible hover, pressed, active, and open feedback.
- Grouping popovers use the existing selectable-popover interaction semantics rather than custom borderless rows.

## Non-Goals

- Do not change grouping, sorting, filtering, deletion, command, or IPC semantics.
- Do not move the search field's contextual clear button or active-filter clear action.
- Do not add a second feature-owned toolbar style.
- Do not change repo, pane, tab, or notification group-header coloring.
- Keep repo grouping, sort, and visibility persistence in `WorkspaceSettingsStore.repoExplorer`.

## Requirements And Proof

| Requirement | Owning task | Proof | Layer | Red/green |
| --- | --- | --- | --- | --- |
| Shared stable grouping trigger with current-mode text | T1 | shared-component and source convergence tests | unit/architecture | required |
| Visible toolbar hover/open/active feedback | T1 | style-state unit coverage plus PID-targeted visual proof | unit/e2e visual | required |
| Full-width selectable grouping rows with keyboard behavior | T2 | selectable-popover tests and sidebar interaction tests | unit/integration | required |
| Grouping remains rightmost after a divider on both surfaces | T2 | accessibility hierarchy assertions plus PID-targeted visual proof | integration/e2e visual | required |
| Inbox delete menu moves before sort without semantic drift | T3 | existing delete-menu action tests plus hierarchy assertion | integration | required |

Freshness guard: all automated commands and visual captures run from the final working-tree contents after implementation. Visual proof must target the deterministic debug app PID for this worktree.

## Task Sequence

### T1. Shared Sidebar Toolbar Interaction Primitives

Write surfaces:

- `Sources/AgentStudio/Core/Actions/CommandIcon.swift`
- `Sources/AgentStudio/Infrastructure/AppStyles.swift`
- `Sources/AgentStudio/SharedComponents/SidebarSortButton.swift`
- focused shared-component tests

Add the typed symbol and a shared grouping trigger that accepts direct presentation values and callbacks. Centralize toolbar hover/pressed/active/open paint without adding atom or feature dependencies.

### T2. Shared Grouping Popover And Surface Wiring

Write surfaces:

- `Sources/AgentStudio/SharedComponents/SelectablePopover/`
- `Sources/AgentStudio/Features/RepoExplorer/RepoExplorerView.swift`
- `Sources/AgentStudio/Features/InboxNotification/Views/InboxSidebarComponents.swift`
- focused Repo and Inbox tests

Wire both surfaces to the same stable trigger and selectable-row behavior. Keep feature enums and mutations at the feature call sites. Place grouping last in each toolbar row with a divider immediately before it.

### T3. Inbox Delete Menu Relocation

Write surfaces:

- `Sources/AgentStudio/Features/InboxNotification/Views/InboxSidebarComponents.swift`
- `Tests/AgentStudioTests/Features/InboxNotification/Views/InboxNotificationSidebarViewTests.swift`

Move the existing menu intact from the search-row primary action into the toolbar before sort. Preserve action specs, destructive roles, accessibility identity, tooltip source, and callbacks.

### T4. Validation And Visual Proof

1. Run `SWIFT_TEST_TIMEOUT_SECONDS=180 mise run test -- --filter "SidebarToolbar|RepoExplorer|InboxNotificationSidebarView"`.
2. Run `mise run lint`.
3. Run `mise run test`; keep WebKit suites serialized through this repo task.
4. Launch with `mise run run-debug-observability -- --detach` without foreground activation.
5. Use PID-targeted Peekaboo to verify both surfaces, hover feedback, menu placement, grouping placement, and popup rows.
6. Run `mise run verify-debug-observability`.

## Execution DAG

```text
gate 0: validate clean worktree and live source
  -> T1 shared primitive and style states
  -> T2 both sidebar grouping surfaces
  -> T3 inbox delete-menu relocation
  -> focused automated validation
  -> lint and broad relevant tests
  -> background debug launch and PID-targeted visual proof
  -> implementation review
```

The work is intentionally serial: both feature edits consume the same shared trigger and interaction-state contract, and Inbox placement overlaps the Inbox grouping call site.

## Risks And Recovery

- Minimum sidebar width may become cramped. Keep stable control dimensions and prove the minimum-width layout visually; split or shorten labels only if evidence shows overflow.
- Custom popup conversion may regress keyboard focus. Preserve `SelectablePopoverKeyboardBridge` semantics and add focused coverage before wiring both surfaces.
- Relocating the native delete menu may affect tooltip suppression. Preserve the existing hover-suppression state and prove reopen/hover behavior.
- Recovery is a scoped revert of this delta's shared primitive and two call-site changes; no persistence or schema migration is involved.

Security context: not applicable. This changes presentation and existing callbacks only; command and IPC authorization are unchanged.
