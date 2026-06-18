# Inbox Toolbar Polish Implementation Plan

Date: 2026-06-18
Goal id: 2026-06-18-inbox-toolbar-polish
Branch: notification-toolbar-polish

## Goal

Polish the inbox sidebar header so it is readable at narrow sidebar widths, uses the command/presentation metadata correctly, and exposes the new attention filter as a simple Attention-only vs All toggle. Carry the branch to PR-ready status after implementation, review, debug launch, and manual-test handoff.

## Non-Goals

- Do not revisit agent-settled heuristics, row-dot colors, or notification promotion policy.
- Do not add new command shortcuts unless a command already exists and the tooltip must display it.
- Do not change pane inbox behavior except where shared presentation helpers are intentionally reused and tested.
- Do not merge the PR.

## Source Coverage

- Chat requirements from 2026-06-18: screenshot shows the inbox header crowded; search and the clear-notifications menu should share the first row with the clear menu right-aligned, while the remaining toolbar controls should move to a second line; controls need friendly tooltips; the attention/viewfinder button should show only attention/action-safety-settled rows when on and all rows when off; shortcuts must be included in tooltips where applicable; user wants to manually test the debug build before PR readiness.
- `docs/architecture/commands_and_shortcuts.md`: 362 lines read, including the command/local action split and UI hint rules.
- `Sources/AgentStudio/Features/InboxNotification/Views/InboxSidebarComponents.swift`: 409 lines read. Current header places search and six controls in one `HStack`; several tooltips are hardcoded; content mode is currently tri-state.
- `Sources/AgentStudio/Features/InboxNotification/Views/InboxNotificationSidebarView.swift`: 450 lines read. Current `cycleContentMode()` cycles `rollUpAlerts -> activity -> all -> rollUpAlerts`.
- `Sources/AgentStudio/Features/InboxNotification/Models/InboxNotificationDisplayFilters.swift`: 57 lines read. Current `InboxNotificationContentMode` has `rollUpAlerts`, `activity`, and `all`.
- `Sources/AgentStudio/App/Commands/AppCommand+Catalog.swift`: 995 lines read. Inbox command specs exist for sort, clear read/all, and inbox toggles; `toggleInboxNotificationSort` is command-backed but has no `AppShortcut`.
- `Sources/AgentStudio/Core/Actions/UIActionPresentation.swift`: 257 lines read. `CommandSpec.controlToolTip` is the shortcut-aware tooltip helper; `LocalActionSpec` is the correct home for UI-only labels/help/icons.
- `Sources/AgentStudio/Features/InboxNotification/Views/InboxSidebarKeyboard.swift`: 60 lines read. Inbox-sidebar local shortcuts such as `⌥F`, `⌥G`, and `⌥S` are feature-local `KeyPress` routing, not `AppShortcut` bindings.
- Nearby test evidence inspected: `InboxNotificationSidebarViewTests`, `InboxNotificationListModelTests`, `InboxRowTests`, and command-bar inbox tests.

## Current Evidence

- Current branch is clean but behind `origin/main` by 3 commits. The first execution checkpoint must refresh the branch before product edits. Because repo instructions gate merge/rebase operations, use a fast-forward-only update or recreate the branch from current `origin/main` before coding, then re-check status.
- The visible UI issue is caused by `InboxSidebarHeader.body` putting search and all toolbar buttons in one row.
- The functional issue is `cycleContentMode()` exposing Activity as a separate mode, while the requested global sidebar control is binary: attention-only when on, all rows when off.
- Tooltip issue is mixed ownership: sort uses `CommandSpec.controlToolTip`, but row-state, mark-read, content-mode, grouping, and delete menu use hardcoded text. The sort button also has a feature-local `⌥S` key route that is not represented by `CommandSpec.controlToolTip` because no `AppShortcut` exists for `.toggleInboxNotificationSort`.

## Requirements / Proof Matrix

| Requirement / claim | Owning task | Proof owner: | Proof gate | Proof layer | Stale-proof guard: | Red/green required | Sized to pass |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Header search and clear-notifications menu are on the first row, while the remaining inbox controls are on a second row so the sidebar does not crowd at narrow widths. | Task 2 | parent + implementation phase | mounted SwiftUI/header test or stable accessibility identifiers plus debug visual/manual proof | unit + smoke/manual | current branch diff and launched `Agent Studio Debug akm3` marker | yes, add/adjust view test if feasible | yes |
| Toolbar tooltips come from command/local-action specs, and shortcut text appears from the correct source: `CommandSpec.controlToolTip` for `AppShortcut`-backed commands, and a tested inbox-sidebar keyboard hint helper for feature-local routes such as `⌥S`. | Task 1, Task 3 | parent | focused test for `CommandSpec.controlToolTip`/new toolbar tooltip helpers/local key hint strings; manual hover check in debug app | unit + manual | current `docs/architecture/commands_and_shortcuts.md`, `AppShortcut`, and `InboxSidebarKeyboardRouter` | yes | yes |
| Viewfinder/scope button is binary: on means attention-only (`actionNeeded`, `safety`, `settledAgent`), off means all notifications. | Task 1, Task 4 | parent | `InboxNotificationListModelTests` or view-model helper test proving activity rows are hidden in attention mode and visible in all mode | unit | current `InboxNotificationContentMode` definitions and row-state filter state | yes | yes |
| Activity remains a blue row dot/lane and is not lost from All mode. | Task 4 | parent | list-model test includes an activity row visible in `.all` and excluded from attention-only | unit | current claim lane model | yes | yes |
| Sort arrow animation still flips 180 degrees on click/order change. | Task 2 | parent | retain `.rotationEffect` and `.animation` coverage via header contract test or direct code review; manual debug check | unit/manual | current `InboxSidebarHeader` implementation | no new red state required if behavior is preserved | yes |
| Mark visible scope read still clears dots by marking visible rows read. | Task 4 | parent | existing/added `markVisibleScopeRead` behavior test where feasible; manual debug check | unit/manual | use current visible list model after filter changes | yes if existing coverage is insufficient | yes |
| Command spec rules are followed: command identities stay in `AppCommand+Catalog`; app-wide UI-only presentation moves to `LocalActionSpec`; feature-local keyboard hint text stays beside `InboxSidebarKeyboardRouter` so local sidebar keys do not masquerade as global `AppShortcut`s. | Task 1, Task 3 | parent + reviewer | code review plus focused tests for constants | review + unit | `docs/architecture/commands_and_shortcuts.md` current at execution time | no | yes |
| User can manually test the debug build after implementation. | Task 6 | parent + user | `mise run observability:up`; launch debug through `AGENTSTUDIO_IPC_UNSAFE_NO_AUTH=1 mise run run-debug-observability -- --detach`; report PID/marker/log | smoke/manual | fresh marker in `tmp/debug-observability/latest-observability.env`, not stale | no | yes |
| PR-ready state is proven but not merged. | Task 8 | parent | pushed branch, draft/ready PR link, fresh checks/review-thread/mergeability report | PR gate | current GitHub PR state after push | no | yes |

## Task Sequence

### Task 0: Refresh Branch Baseline

1. Re-check `git status --short --branch`.
2. Refresh `notification-toolbar-polish` onto current `origin/main` with the least invasive allowed operation. If an integration write needs explicit permission, pause and ask before running it.
3. Re-run `git status --short --branch` and record the baseline in workflow details.

### Task 1: Define Toolbar Presentation Contract

1. Add local action presentation for inbox-only toolbar controls that are not app commands: unread/all row filter, mark visible read, attention/all filter, grouping menu, delete menu if command specs alone are not sufficient.
2. Prefer `CommandSpec.controlToolTip` for command-backed controls and local action specs for UI-only controls.
3. Add a small `InboxSidebarKeyboardHint`/presentation helper beside `InboxSidebarKeyboardRouter` for feature-local shortcuts (`⌥F`, `⌥G`, `⌥S`, `⌥↑`, `⌥↓`, `⌘↑`, `⌘↓`, Return, Space) when those shortcuts appear in sidebar tooltips or accessibility help.
4. Add small helper methods/properties on `InboxSidebarHeader` only if they keep the view readable and testable.

Likely write surfaces:
- `Sources/AgentStudio/Core/Actions/UIActionPresentation.swift`
- `Sources/AgentStudio/Features/InboxNotification/Views/InboxSidebarKeyboard.swift`
- `Sources/AgentStudio/Features/InboxNotification/Views/InboxSidebarComponents.swift`
- `Tests/AgentStudioTests/Features/InboxNotification/Views/InboxNotificationSidebarViewTests.swift`

### Task 2: Split Header Layout Into Search Row + Control Row

1. Change `InboxSidebarHeader.body` from one `HStack` to a `VStack` with:
   - Row 1: `SidebarSearchField` plus the clear-notifications menu right-aligned. Do not otherwise redesign the search field.
   - Row 2: compact toolbar controls, excluding clear notifications, with stable icon-button sizing, predictable spacing, and no text labels.
2. Preserve the active filter chip below the toolbar rows.
3. Keep visual constants local only if existing app styles do not already define a sidebar toolbar control size; if a new visual constant is needed, put it under `AppStyles`, not behavior policy.

Likely write surfaces:
- `Sources/AgentStudio/Features/InboxNotification/Views/InboxSidebarComponents.swift`
- optional `Sources/AgentStudio/App/AppStyles.swift` or existing style file if a shared constant is warranted
- `Tests/AgentStudioTests/Features/InboxNotification/Views/InboxNotificationSidebarViewTests.swift`

### Task 3: Fix Tooltip / Accessibility Metadata

1. Ensure each toolbar button/menu has:
   - `accessibilityLabel`
   - `accessibilityIdentifier` where useful for tests/manual verification
   - `.help(...)` sourced from command/local-action presentation
2. Ensure `AppShortcut`-bearing command tooltips display shortcut text through `CommandSpec.controlToolTip`.
3. Ensure feature-local sidebar shortcut text, especially sort `⌥S`, is generated from the inbox keyboard presentation helper and covered by tests.
4. Keep button help friendly and state-aware:
   - Attention button on: "Showing attention notifications; click to show all notifications."
   - Attention button off: "Showing all notifications; click to show attention notifications."
   - Unread/all button similarly says what will happen next.

Likely write surfaces:
- `Sources/AgentStudio/Features/InboxNotification/Views/InboxSidebarComponents.swift`
- `Sources/AgentStudio/Features/InboxNotification/Views/InboxSidebarKeyboard.swift`
- `Sources/AgentStudio/Core/Actions/UIActionPresentation.swift`
- `Tests/AgentStudioTests/Features/InboxNotification/Views/InboxNotificationSidebarViewTests.swift`

### Task 4: Make Content Mode Binary For Sidebar Toolbar

1. Replace global sidebar content-mode cycling with a binary toggle: `.rollUpAlerts` <-> `.all`.
2. Do not remove `.activity` if pane inbox or existing model/tests still use it. The change is the sidebar toolbar behavior, not necessarily the enum itself.
3. Update tests so activity rows are excluded in attention mode and included in all mode.
4. Re-check pane inbox tests before touching shared enum behavior.

Likely write surfaces:
- `Sources/AgentStudio/Features/InboxNotification/Views/InboxNotificationSidebarView.swift`
- `Sources/AgentStudio/Features/InboxNotification/Views/InboxSidebarComponents.swift`
- `Tests/AgentStudioTests/Features/InboxNotification/Models/InboxNotificationListModelTests.swift`
- `Tests/AgentStudioTests/Features/InboxNotification/Views/InboxNotificationSidebarViewTests.swift`

### Task 5: Focused Verification

Run the smallest useful red/green and regression gates:

```bash
SWIFT_TEST_TIMEOUT_SECONDS=180 mise run test -- --filter "InboxNotificationSidebarView|InboxNotificationListModel|InboxRow|CommandBarInboxCommands"
```

Then run:

```bash
mise run lint
```

If focused tests expose unrelated failures outside this scope, stop code edits, record the scoped pass/fail, and ask before changing unrelated infrastructure.

### Task 6: Debug Launch For User Test

After focused tests and lint are clean enough for manual verification:

```bash
mise run observability:up
AGENTSTUDIO_IPC_UNSAFE_NO_AUTH=1 mise run run-debug-observability -- --detach
```

Report:
- debug app name/code
- PID
- marker
- log path
- state file

Ask the user to test the actual sidebar toolbar behavior before PR wrapup. Manual checklist:
- Search field and clear-notifications menu share the first row, with clear right-aligned.
- Toolbar controls other than clear notifications are on the second row and do not crowd the search field.
- Hover each toolbar control and confirm a friendly tooltip appears; shortcuts show for shortcut-backed controls.
- Viewfinder/scope button toggles Attention-only vs All, not Activity as a third mode.
- Blue activity rows remain available in All mode.
- Sort button still rotates/flips when order changes.
- Mark visible read clears unread dots.

### Task 7: Implementation Review

Use `shravan-dev-workflow:implementation-review-swarm` after implementation proof. Review packet should include:
- current diff
- plan path
- focused test/lint output
- manual debug marker or manual-test blocker
- explicit questions around command/local action tooltip ownership and binary content-mode semantics

Address accepted findings in scoped commits.

### Task 8: PR Wrapup

Use `shravan-dev-workflow:implementation-pr-wrapup`:
1. Commit scoped implementation and workflow artifacts.
2. Push `notification-toolbar-polish`.
3. Open/update a PR against `main`.
4. Report PR URL, checks, review-thread state, mergeability, and remaining manual-test status.
5. Do not merge.

## Validation Gates

- Unit/model/view: focused Swift Testing filter for inbox sidebar/list model/row/command-bar inbox coverage.
- Quality: `mise run lint`.
- Smoke/manual: debug observability launch with fresh marker and user manual check.
- Review: implementation review swarm accepted findings addressed or explicitly rejected.
- PR: branch pushed, PR created/updated, fresh CI/check/review-thread/mergeability state reported.

## Risks And Recovery

- `origin/main` drift: branch is already behind by 3 commits. Refresh before code or risk building a PR on stale base.
- SwiftUI tooltip inspection may not be fully automatable. Mitigation: pin tooltip strings/helpers in unit tests and use debug/manual hover as the higher proof layer.
- Removing `.activity` globally could break pane inbox expectations. Mitigation: keep enum case and change only global sidebar toolbar toggle unless tests prove a broader cutover is safe.
- Shortcut ownership drift: `⌥S` sort is a feature-local inbox key route, not an `AppShortcut`. Mitigation: do not fake an `AppShortcut`; expose/test a feature-local hint helper and reserve `CommandSpec.controlToolTip` for actual command bindings.
- Debug launch may fail on Ghostty/runtime startup independent of toolbar code. Mitigation: report app launch/marker separately from UI behavior proof; do not edit runtime infrastructure for toolbar work without permission.

## Open Questions

- Should the delete menu tooltip include both destructive actions or should each menu item carry its own tooltip only? Default plan: menu button tooltip summarizes the menu; menu items use command labels.
- Does the user want the PR as draft until manual testing is confirmed? Default plan: open draft PR if manual testing is still pending; mark ready only after manual signoff.

## Phase Footer

phase_result: complete
evidence: docs/superpowers/plans/2026-06-18-inbox-toolbar-polish.md
recommended_next_workflow: shravan-dev-workflow:plan-review-swarm
recommended_transition_reason: The plan defines write surfaces, proof matrix, risks, and PR-ready lifecycle gates; it should be reviewed before product code edits.
