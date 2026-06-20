# Thin Titlebar Two-Row Implementation Plan

Date: 2026-06-20
Goal id: 2026-06-20-thin-titlebar-two-row
Branch: remove-top-bar
Worktree: agent-studio.remove-top-bar

## Goal

Keep AgentStudio's two-row shell model while making row 1 feel Ghostty-thin:
the native titlebar area keeps traffic lights and the user's top action buttons,
row 2 remains the existing SwiftUI tab strip/content start, tabs are not moved
into the titlebar, the sidebar expanded/collapsed behavior is not redesigned,
and the native toolbar right-click "Icon and Text / Icon Only" display menu
does not appear.

The current goal scope prefers removing product actions from real `NSToolbar`
ownership and moving them into App-owned titlebar accessories. Plan review found
that macOS 15+ also has supported `NSToolbar.allowsDisplayModeCustomization`.
Implementation must verify that smaller supported-toolbar path before custom
chrome. If the supported-toolbar path satisfies thinness, row-2 movement, and
right-click-menu requirements, stop for user reconvergence before changing the
goal scope from custom titlebar accessories back to product `NSToolbar`.

Target shape:

```text
row 1  traffic lights + repo/inbox + compact icon actions
row 2  sidebar search/action row + existing CustomTabBar
body   sidebar + terminal panes
```

## Non-Goals

- Do not put tabs in the titlebar.
- Do not redesign expanded or collapsed sidebar behavior.
- Do not change command identities, shortcut routing, or Watch Folder behavior.
- Do not use unsupported AppKit/private API to suppress the native toolbar menu.
- Do not broaden into tab pill redesign.
- Do not change the current goal scope to a product `NSToolbar` implementation
  without proving the supported-toolbar path and getting explicit reconvergence.

## Source Coverage

- Chat decision: user clarified they want row 1 thin like Ghostty while keeping
  their buttons; row 2 should move up/take space; tabs should not move into the
  titlebar; the toolbar right-click Icon/Text menu should not be available.
- `tmp/research-workflows/2026-06-20-thin-titlebar-two-row/research-ledger.md`:
  119 lines read completely. It establishes the two-row target, the
  `NSToolbar` context-menu concern, and the titlebar-accessory direction.
- `docs/guides/style_guide.md`: 61 lines counted; relevant lines 5-14 and
  46-58 read for content-over-chrome, dense controls, tooltip ownership, and
  AppStyles/AppPolicies placement.
- `docs/architecture/appkit_swiftui_architecture.md`: 503 lines counted;
  relevant lines 1-31 and 73-120 read for AppKit-main ownership and the
  `MainWindowController -> MainSplitViewController -> PaneTabViewController`
  hierarchy.
- `docs/architecture/window_system_design.md`: 1055 lines counted; relevant
  lines 111-122, 569-575, 673-692, and 895-903 read for AppKit-vs-SwiftUI
  structure, edit-mode command ownership, tab bar layout, and command pipeline
  invariants.
- `Sources/AgentStudio/App/Windows/MainWindowController.swift`: inspected row 1
  setup: `setupTitlebarAccessory()`, `setupToolbar()`, `commandToolbarButtonItem`,
  and `NSToolbarDelegate`.
- `Sources/AgentStudio/App/Panes/PaneTabViewController.swift`: inspected row 2
  placement: `CustomTabBar` pinned to `safeAreaLayoutGuide.top` at 36pt.
- `Sources/AgentStudio/App/Panes/TabBar/CustomTabBar.swift`: inspected existing
  row 2 controls; no default row 2 rewrite is planned.
- `Tests/AgentStudioTests/App/Windows/MainWindowControllerInboxToolbarButtonTests.swift`:
  identified as the focused test home for titlebar accessory behavior.

## Current Evidence

- `MainWindowController` creates an `NSWindow` with `.titled` and
  `.fullSizeContentView`, hides the native title, makes the titlebar
  transparent, then calls both `setupTitlebarAccessory()` and `setupToolbar()`.
- The left titlebar accessory already owns repo/inbox buttons and unread badge.
- The right/top product actions currently use a real `NSToolbar`; Watch Folder
  is a text-bearing rounded `NSButton`, so row 1 is visually larger than a
  Ghostty-like native titlebar.
- `NSToolbar.displayMode = .iconOnly` and `allowsUserCustomization = false` are
  already set. Plan review found that the local Xcode 26.3 SDK exposes
  `NSToolbar.allowsDisplayModeCustomization API_AVAILABLE(macos(15.0))`, and
  the package targets macOS v26. The supported-toolbar path must be verified or
  rejected before custom titlebar work proceeds.
- `PaneTabViewController` keeps `CustomTabBar` separate from the titlebar. It
  should move upward naturally if row 1's safe area shrinks, but this must be
  visually verified in the debug app.
- `WelcomeLauncherArchitectureTests` currently asserts the old
  `commandToolbarButtonItem(for: .watchFolder, ...)` path and must be updated
  to prove the new titlebar action contract instead of deleted.

## Requirements / Proof Matrix

| Requirement / claim | Owning task | Proof owner | Proof gate | Proof layer | Stale-proof guard | Red/green required | Sized to pass |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Supported-toolbar alternative is either proven viable and returned for user reconvergence, or rejected with evidence before custom titlebar work proceeds. | Task 1A | parent + executor | SDK/header evidence, unit assertion for `allowsDisplayModeCustomization`, native right-click and geometry probe if implemented | unit + native UI smoke | local Xcode SDK path and fresh debug PID from this branch | yes if implemented as code probe | yes |
| Row 1 keeps traffic lights and top buttons and the native toolbar display context menu is not present. Default accepted path has `window.toolbar == nil` and product actions in titlebar accessories. | Task 1, Task 2 | parent + executor | focused `MainWindowControllerInboxToolbarButtonTests` plus PID-targeted Peekaboo/manual right-click check | unit + native UI smoke | fresh debug PID from this branch; inspect `window.toolbar`/accessories in tests | yes | yes |
| Repo/inbox controls remain in row 1 with typed tooltips, active surface icon state, and unread badge behavior. | Task 1 | parent + executor | existing titlebar tests extended/kept green | unit | current `AppCommandDispatcher` definitions and `InboxNotificationAtom` state | yes | yes |
| Management/layout and Watch Folder actions remain directly visible in row 1 as compact icon-only buttons at default width and 720pt minimum width. | Task 2 | parent + executor | new/updated titlebar action strip test proves identifiers/tooltips/actions; harness click tests prove dispatch for both controls | unit + native UI smoke | current `AppCommand.watchFolder`, `.toggleManagementLayer`, and management atom definitions | yes | yes |
| Row 2 remains outside the titlebar; tabs are not moved into row 1. | Task 3 | parent + reviewer | code diff review plus existing `PaneTabViewController` constraints unchanged unless a tiny safe-area fix is justified | review + smoke | compare against current `PaneTabViewController` top constraint | no red required if preserved | yes |
| Sidebar expanded/collapsed behavior is unchanged. | Task 3 | parent + executor | `MainSplitViewControllerSidebarStateTests` plus visual smoke with expanded and collapsed sidebar | unit + native UI smoke | current `MainSplitViewController` behavior; no unrelated sidebar edits | no if no sidebar code touched | yes |
| The new row 1 is thinner and row 2 moves up/takes the recovered space. | Task 0, Task 5 | parent + user | baseline and post-change `contentLayoutRect`/safe-area/tab-bar top measurement plus PID-targeted Peekaboo screenshots | native UI smoke/manual | fresh app launch after build; do not reuse stale screenshots | no automated red unless frame helper exists | yes |
| Dense icon controls follow tooltip source contract, stable accessibility labels/identifiers, and AppStyles presentation ownership. | Task 2 | parent + reviewer | focused tests for tooltip text, empty visible titles, AX labels/identifiers, and code review of constants | unit + review | current `docs/guides/style_guide.md` dense-control guidance | yes | yes |
| Added titlebar accessory/hosted state does not outlive the window controller. | Task 2 | parent + executor | close harness window, mutate observed atoms, and assert no re-registration/crash or prove deallocation if practical | unit/reliability | current observation loops in `MainWindowController` | yes if new observation/hosting lifecycle is added | yes |

## Task Sequence

### Task 0: Baseline And Branch Hygiene

1. Re-run `git status --short --branch`.
2. Confirm no unrelated product edits are present. Keep existing `tmp/` research
   artifacts out of the product diff unless intentionally committed later.
3. Inspect `MainWindowControllerInboxToolbarButtonTests` before editing to keep
   the new tests in the existing harness style.
4. Capture a baseline before product edits:
   - current `window.contentLayoutRect` or titlebar/safe-area top measurement
   - current row-2/tab-bar top edge measurement if available from the harness
   - current screenshot notes at default width and 720pt minimum width, or an
     explicit "baseline unavailable" note with the reason.
   Screenshots support the proof; geometry/frame measurements are the contract.

### Task 1A: Verify Or Reject Supported Native Toolbar Path

1. Verify the local SDK/compiler surface for
   `NSToolbar.allowsDisplayModeCustomization`; the observed source is the Xcode
   26.3 `NSToolbar.h` header and `Package.swift` macOS v26 target.
2. Before removing `NSToolbar`, test the smaller supported-toolbar path in the
   narrowest possible slice if it can be done without broad refactor:
   - `toolbar.displayMode = .iconOnly`
   - `toolbar.allowsUserCustomization = false`
   - `toolbar.allowsDisplayModeCustomization = false`
   - `window.toolbarStyle = .unifiedCompact` if it improves row height
   - Watch Folder rendered icon-only with no visible text.
3. Accept the supported-toolbar path only if all of these are true:
   - native right-click no longer shows "Icon and Text", "Icon Only", or
     "Customize Toolbar"
   - row 1 is materially thinner and row 2 starts higher than baseline
   - row-1 controls remain directly visible at default and 720pt widths
   - user agrees to change the current goal scope back to product
     `NSToolbar` ownership.
4. If the supported-toolbar path succeeds before user reconvergence, stop code
   edits and report the evidence. Do not silently switch the goal scope.
5. If the supported-toolbar path fails any required gate or is not sufficient,
   record the failure evidence and continue to the custom titlebar-accessory
   path below.

### Task 1: Convert Row 1 Ownership Away From Product `NSToolbar`

1. Stop installing the product `NSToolbar` for the main window. The default
   accepted end state is `window.toolbar == nil`.
2. Remove or retire `NSToolbarDelegate` conformance and
   `commandToolbarButtonItem` if no longer needed.
3. Preserve existing window shape: `.titled`, `.fullSizeContentView`,
   `titleVisibility = .hidden`, and `titlebarAppearsTransparent = true`.
4. Keep the existing left titlebar accessory semantics for repo/inbox. Do not
   combine all row-1 controls into one full-width overlay.
5. Use an empty/non-product `NSToolbar` only after documented AppKit layout
   evidence proves `window.toolbar == nil` cannot satisfy the row-2 placement
   contract. A fallback toolbar must have zero product items, no product
   `NSToolbarDelegate` path, and native right-click proof that the display menu
   is still absent. If the menu returns, stop and reconverge.

Likely write surfaces:
- `Sources/AgentStudio/App/Windows/MainWindowController.swift`
- `Sources/AgentStudio/Infrastructure/Extensions/AppKitExtensions.swift` if
  toolbar item identifiers become unused
- `Tests/AgentStudioTests/App/Windows/MainWindowControllerInboxToolbarButtonTests.swift`
- `Tests/AgentStudioTests/App/WelcomeLauncherArchitectureTests.swift`

### Task 2: Add Compact Titlebar Action Strip

1. Add App-owned titlebar controls for row 1:
   - keep repo/worktree sidebar and inbox bell with badge in the left accessory
   - add a separate right titlebar accessory for management/layout and Watch Folder
   - do not add overflow in this slice unless 720pt width proof fails; if
     overflow is required, stop for design reconvergence before hiding any of
     the four requested top actions.
2. Prefer a focused helper/view in `App/Windows/` rather than growing
   `MainWindowController` further. The view/helper only renders compact
   controls and forwards actions.
3. Route actions through `AppCommandDispatcher.shared.dispatch(...)`:
   - Watch Folder dispatches `.watchFolder`
   - management/layout dispatches `.toggleManagementLayer`
   Do not mutate `ManagementLayerAtom` directly from `MainWindowController`,
   `TitlebarActionStrip`, or a hosted titlebar SwiftUI view.
4. Render Watch Folder as icon-only using `AppCommand.watchFolder.definition`.
   Keep label in accessibility/tooltips, not visible text.
5. Prefer AppKit `NSButton`/`NSStackView` for row-1 titlebar controls unless a
   SwiftUI-hosted implementation is equally unit-testable in the harness.
6. Every row-1 control must have:
   - stable `identifier`
   - empty visible title for icon-only buttons
   - typed tooltip from `ControlTooltipRenderValue`
   - explicit accessibility label
   - inspectable image accessibility description or equivalent AX label.
7. Put any new spacing/icon constants in `AppStyles`; do not add behavior
   constants to presentation style.
8. If new observation loops, hosting controllers, or accessory controllers are
   added, define their teardown behavior and prove they do not re-register or
   retain the window controller after close.

Likely write surfaces:
- `Sources/AgentStudio/App/Windows/MainWindowController.swift`
- optional new `Sources/AgentStudio/App/Windows/TitlebarActionStrip.swift`
- `Sources/AgentStudio/App/Windows/ControlTooltipAppKitAdapters.swift`
- `Sources/AgentStudio/Infrastructure/AppStyles.swift`
- `Tests/AgentStudioTests/App/Windows/MainWindowControllerInboxToolbarButtonTests.swift`
- `Tests/AgentStudioTests/App/WelcomeLauncherArchitectureTests.swift`

### Task 3: Preserve Row 2 And Sidebar Contracts

1. Leave `CustomTabBar` outside the titlebar.
2. Leave `MainSplitViewController` sidebar collapse/expand/focus behavior
   untouched unless tests reveal accidental layout fallout.
3. Only adjust `PaneTabViewController` safe-area/top constraints if the debug
   app shows row 2 did not move up after row 1 changed and the baseline
   geometry proves the row-2 movement contract failed.
4. If a constraint adjustment is needed, keep it narrowly tied to content
   placement below the titlebar, not a tab redesign.

Likely write surfaces only if required:
- `Sources/AgentStudio/App/Panes/PaneTabViewController.swift`
- `Tests/AgentStudioTests/App/Windows/MainWindowControllerInboxToolbarButtonTests.swift`

### Task 4: Focused Verification

Run focused unit tests first:

```bash
mise run test -- --filter "MainWindowControllerInboxToolbarButtonTests|WelcomeLauncherArchitectureTests|MainSplitViewControllerSidebarStateTests|ManagementLayerTests|AppCommandTests|WorkspaceEmptyStateViewTests"
```

Then run quality gates:

```bash
mise run format
mise run lint
```

If the focused lane exposes unrelated failures outside titlebar/window chrome,
stop code edits, report scoped pass/fail, and ask before touching unrelated
runtime/tooling/infrastructure.

### Task 5: Native UI Proof With Dev Workflow Tools / Peekaboo

Use the `Dev Workflow Tools:peekaboo` capability after lower layers pass because
this is native macOS chrome.

Preferred debug path:

```bash
mise run observability:up
AGENTSTUDIO_IPC_UNSAFE_NO_AUTH=1 mise run run-debug-observability -- --detach
mise run verify-debug-observability
```

Then target the debug PID from the verifier handoff, not the app name:

```bash
STATE_FILE=tmp/debug-observability/latest-observability.env
PID="$(sed -n 's/^AGENTSTUDIO_OBSERVABILITY_PID=//p' "$STATE_FILE" | tail -1)"
STATUS="$(sed -n 's/^AGENTSTUDIO_OBSERVABILITY_STATUS=//p' "$STATE_FILE" | tail -1)"
test "$STATUS" = "running"
test -n "$PID"
kill -0 "$PID"
peekaboo see --app "PID:$PID" --json
```

Visual/manual checklist:
- Row 1 is thinner than baseline by geometry/frame measurement, with screenshot support.
- Repo/inbox icons remain in row 1; inbox badge still appears when unread.
- Watch Folder appears as an icon-only titlebar control with tooltip/accessibility label.
- Right-clicking row 1 and empty titlebar space no longer shows the native
  toolbar display menu.
- Row 2 remains the tab/sidebar content row and starts higher than baseline.
- Expanded sidebar still works.
- Collapsed sidebar still works.
- Traffic lights and window dragging remain usable at 720pt, 900pt, and 1200pt widths.
- Row-1 controls do not overlap traffic lights at 720pt minimum width.
- The implementation review packet reports PID, status, launch method, marker,
  and Peekaboo target.

### Task 6: Review Route

After implementation proof, use `shravan-dev-workflow:implementation-review-swarm`
with a packet containing:
- this plan
- current diff
- focused test output
- lint/format output
- debug PID/marker
- Peekaboo screenshot or exact visual-proof blocker
- explicit review question: "Does the chosen row-1 titlebar/top-row path
  preserve AppKit window behavior while eliminating the toolbar display menu?"

### Task 7: PR Readiness

After implementation review findings are addressed or explicitly rejected, use
`shravan-dev-workflow:implementation-pr-wrapup`.

Required output:
- PR created or updated for branch `remove-top-bar`
- fresh CI/check state
- unresolved review-thread state
- mergeability state
- explicit note that merge was not performed because the user asked for
  PR-ready-to-merge, not merge.

## Validation Gates

- Unit: focused Swift Testing filter for `MainWindowControllerInboxToolbarButtonTests`
  and related command/management coverage.
- Quality: `mise run format`; `mise run lint`.
- Native smoke: debug observability launch, `verify-debug-observability`, and
  PID-targeted Peekaboo/manual visual checks.
- Review: implementation review swarm before claiming ready.
- PR readiness: implementation PR wrapup with fresh PR checks, review threads,
  and mergeability before the goal is complete.

## Risks And Recovery

- The supported `NSToolbar.allowsDisplayModeCustomization` path may satisfy the
  no-menu requirement with less custom chrome. Recovery: prove it in Task 1A.
  If it passes, stop for user reconvergence because the current goal scope
  excludes product `NSToolbar` ownership.
- AppKit may rely on an installed toolbar for a particular safe-area/titlebar
  layout on macOS 26. Recovery: prefer `window.toolbar == nil`; try an
  empty/non-product compact toolbar only after documenting layout evidence, and
  fail the gate if any native display menu returns.
- Titlebar accessory placement can collide with traffic lights or narrow
  windows. Recovery: keep repo/inbox left, management/Watch Folder right,
  constrain widths, preserve drag space, and stop for design reconvergence
  before introducing overflow.
- SwiftUI-hosted titlebar controls may not expose AppKit identifiers the same
  way as `NSButton`s. Recovery: prefer AppKit `NSButton`/`NSStackView` for row 1
  if testability or accessibility is cleaner.
- Visual proof may be blocked by local Peekaboo/screen-capture state. Recovery:
  record the exact Peekaboo blocker, keep unit/lint/debug proof separate, and
  request manual screenshot verification from the user.
- Removing `NSToolbarItem.Identifier` values may break architecture/string tests
  that assert the old path. Recovery: update tests to assert the new titlebar
  accessory contract rather than deleting proof coverage.
- Existing row 2 already has a management control. Recovery: keep row 2
  unchanged for this slice, make row 1 dispatch through the same command path,
  and prove active-state sync rather than inventing a second management model.

## Open Questions

- If Task 1A proves the supported `NSToolbar` path fully satisfies no-menu,
  thinness, and row-2 movement requirements, should the goal scope change from
  custom titlebar accessories to compact native toolbar? This requires explicit
  reconvergence before implementation continues on that path.
- Should Watch Folder have a visible badge/count state in the future? Out of
  scope for this slice.

## Phase Footer

phase_result: complete
evidence: docs/plans/2026-06-20-thin-titlebar-two-row.md
recommended_next_workflow: shravan-dev-workflow:implementation-execute-plan
recommended_transition_reason: Accepted plan-review findings were folded into
the plan; the next lifecycle gate is implementation with Task 1A as the first
decision/proof slice.
