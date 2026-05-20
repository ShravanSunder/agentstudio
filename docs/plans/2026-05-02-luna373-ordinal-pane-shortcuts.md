# Ordinal Pane Shortcuts And Keyboard Surface Refactor Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development`
> or `superpowers:executing-plans` to implement this plan task-by-task. Steps use
> checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add ordinal pane shortcuts and badges while tightening the keyboard
surface model so app-owned shortcuts, focus-scoped keys, sidebar surfaces, and
empty-drawer shortcuts all have explicit ownership. Also move tab and
arrangement keyboard navigation onto exact app-owned shortcuts:
`Cmd+Option+J`, `Cmd+Option+L`, and `Cmd+Option+I`.

**Architecture:** `AppCommand` remains the command vocabulary, `AppShortcut`
remains exact keyboard ingress, `KeyboardOwner.current(...)` names the current
keyboard owner, `WorkspacePaneFocus` remains command visibility state, and all
pane-affecting focus exits through `PaneFocusTrigger -> PaneFocusDecision ->
PaneFocusExecutor`. The plan fixes the dead global shortcut policy and routes
empty-drawer `P` through command dispatch before adding new ordinal commands.

**Tech Stack:** Swift 6.2, Swift Testing, SwiftUI/AppKit, existing atom system,
Peekaboo for visual validation.

---

## Current Branch State

This branch is no longer plan-only. As of 2026-05-20 it has been merged with
current `origin/main` at `c1490278` (`Fix tab rename popover presentation`) and
contains the shortcut, command-routing, focus-publication, ordinal-resolution,
and badge implementation described below.

Current intended branch diff:

- `docs/plans/2026-05-02-luna373-ordinal-pane-shortcuts.md`
- command vocabulary, shortcut catalog, dispatch policy, shell/workspace command
  boundary, and pane controller routing updates
- `PaneOrdinalMap` plus pane/drawer ordinal badge rendering
- focused tests for command boundaries, shortcut decoding, keyboard ownership,
  empty-drawer raw `P`, tab/arrangement cycling, pane ordinals, drawer ordinals,
  and sidebar focus publication

Post-merge verification status:

- Latest base sync: `origin/main` at `c1490278`.
- Code audit: `renameTab` remains pane-owned and routes through
  `PaneTabViewController`.
- Focused shortcut/command/surface packet:
  `swift test --build-path .build-agent-1 --skip-build --filter ...`, 266 tests
  in 24 suites passed.
- Lint: `mise run lint`, exit 0. SwiftLint reported 0 violations across 835
  files and the Core boundary import check passed.
- Full local test: `mise run test` reached the WebKit serialized lane and then
  failed because `WebKitSerializedTests/BridgeContentWorldIsolationTests`
  exits with signal 11 after Swift Testing reports the test passed. The same
  single filtered test also reproduced this signal-11-after-pass behavior in
  the clean local main worktree at `c1490278`, so this is tracked as local
  WebKit teardown instability rather than a shortcut-routing regression.
- Visual validation remains separate from unit/lint proof. Do not treat green
  tests as proof that badge placement is visually accepted.

## Source-Of-Truth Model

The prior interaction model has landed in code, but the names differ slightly
from older specs. Use the live names below.

### Keyboard And Command Vocabulary

- `AppCommand`
  - Location: `Sources/AgentStudio/App/Commands/AppCommand.swift`
  - Job: semantic command identity.
  - It answers: "what action can be dispatched?"
- `AppShortcut`
  - Location: `Sources/AgentStudio/App/Commands/AppShortcut.swift`
  - Job: exact key binding plus the contexts where that binding fires.
  - It answers: "which keystroke maps to which command in this routing context?"
- `CommandSpec`
  - Location: `Sources/AgentStudio/App/Commands/AppCommand.swift`
  - Job: command presentation, shortcut display, visibility requirements, and
    command-bar grouping.
  - It answers: "how does this command appear in menus and command bar?"
- `CommandDispatcher`
  - Location: `Sources/AgentStudio/App/Commands/AppCommand.swift`
  - Job: common execution point for menus, command bar, shortcuts, toolbar
    actions, and targeted command actions.
  - It answers: "which owner executes this command right now?"
- `KeyboardOwner.current(...)`
  - Location: `Sources/AgentStudio/Core/Models/KeyboardOwner.swift`
  - Job: derived value naming who owns keyboard interpretation now.
  - Live cases: `.otherWindow`, `.managementLayer`, `.sidebar(SidebarSurface)`,
    `.mainWindowChain`.
  - It is not persisted and not manually toggled.
- `WorkspacePaneFocus`
  - Location: `Sources/AgentStudio/Core/State/MainActor/Atoms/WorkspacePaneFocus.swift`
  - Job: command visibility snapshot.
  - It answers: "what workspace/pane state is active?"
  - It must not become keyboard ownership state.
- `WorkspaceFocusOwner`
  - Location: `Sources/AgentStudio/Core/State/MainActor/Atoms/WorkspaceFocusOwnerAtom.swift`
  - Job: pane-scope focus identity for the workspace surface.
  - Live cases: `.mainPane(UUID)`, `.emptyDrawer(parentPaneId: UUID)`,
    `.drawerPane(parentPaneId: UUID, drawerPaneId: UUID)`.
  - Drawer ordinal resolution must use the normalized workspace navigation scope,
    not a raw active-pane fallback.
- `PaneFocusTrigger`
  - Location: `Sources/AgentStudio/Infrastructure/PaneFocus/PaneFocusTrigger.swift`
  - Job: typed ingress for pane-affecting focus.
  - Command focus cases already support `.focusPane(tabId:paneId)` and
    `.selectTab(UUID)`.

### Shortcut Resolution Flow

```text
Key event
  |
  +-- CommandBar or other key window handles first
  |
  +-- ManagementLayerMonitor handles raw management keys
  |     - Command-modified shortcuts pass through by existing contract
  |
  +-- Focus-scoped surface keys handle locally
  |     - Sidebar inbox row/search keys
  |     - Repo sidebar filter focus
  |     - SwiftUI/AppKit responder chain
  |
  +-- App-owned shortcut ingress
        - ShortcutDecoder
        - AppShortcutDispatchPolicy
        - CommandDispatcher
        - PaneFocusTrigger when command affects pane focus
```

### Surface Model In Current Code

The surface concept is implemented as typed ownership axes rather than one
single global "surface enum":

- Sidebar composition is explicit: `SidebarSurface` has `.repos` and `.inbox`,
  `UIStateAtom.sidebarSurface` persists the active sidebar surface, and
  `SidebarSurfaceHost` renders the matching child.
- Sidebar keyboard ownership is runtime-only: `UIStateAtom.sidebarHasFocus` is
  published by the repo sidebar and inbox sidebar focus bridges, then read by
  `KeyboardOwner.current(...)`.
- App-owned shortcut dispatch is gated by `KeyboardOwner` through
  `AppShortcutDispatchPolicy`.
- Scope-aware pane navigation keys (`Option+I/J/K/L`) are local pane-surface
  keys, not `AppShortcut` cases. They run only when `KeyboardOwner` is
  `.mainWindowChain`, text input does not own the responder chain, and the
  resolved pane/drawer command is currently executable.
- Workspace pane/drawer focus is separate: `WorkspaceFocusOwner` and
  `WorkspacePaneFocus` describe active pane, drawer pane, and empty-drawer
  state for command visibility and pane focus routing.
- Empty drawer is therefore not a `SidebarSurface`; it is a workspace-focus
  surface plus `ShortcutContext.emptyDrawer`.
- Tab rename is also not a `SidebarSurface`. It is a pane-owned transient
  editor surface presented by `PaneTabViewController`. Its keyboard handling
  belongs inside the AppKit popover/editor, and its command entry points must
  still target the pane controller.

This is enough structure for the current refactor: sidebar surfaces decide
whether sidebar-owned keyboard focus can block app-owned shortcuts, workspace
focus decides which pane/drawer commands are visible and viable, and transient
editors consume their own local editing keys.

### Post-Review Command-Surface Invariants

The current branch includes the following post-review hardening:

- Scope-aware pane keys must not bypass `KeyboardOwner`. Sidebar-owned focus,
  management-layer ownership, other-window ownership, and active `NSText`
  responders all cause these local pane keys to fall through.
- Scope-aware pane keys must not be consumed unless they map to a concrete,
  executable pane/drawer command. Main-row `Option+I` and `Option+K` now fall
  through because they do not currently resolve to a real pane movement.
- Targeted pane-controller dispatch must reject unsupported
  `(AppCommand, SearchItemType)` pairs. It must not fall back to contextual
  `execute(command)` or `canExecute(command)`, because that can mutate the
  active tab/pane when the caller passed the wrong target type.
- The repo sidebar participates in keyboard ownership through an AppKit focus
  bridge, matching the inbox surface pattern. `focusSidebar()` targets the repo
  focus bridge instead of the hosting view so `.sidebar(.repos)` can be derived
  consistently.

### Post-`c1490278` Rename Invariants

Current `origin/main` moved tab rename presentation out of SwiftUI popover state
inside `CustomTabBar` and into `PaneTabViewController`. The shortcut refactor
must preserve these invariants:

- `ShellCommandHandling` must return false for `.renameTab` in contextual and
  targeted dispatch. `AppDelegate` does not own tab rename.
- Tab context menu rename must call into `PaneTabViewController`, select the
  target tab when needed, then defer popover presentation until default run-loop
  mode after the context menu unwinds.
- Command-bar targeted `.renameTab` must dispatch with the selected tab target
  and preserve targeted pane-controller handling.
- `WorkspaceCommandResolver` must keep `.renameTab` out of structural resolution.
  Presentation starts from `PaneTabViewController`; the actual mutation is
  `PaneActionCommand.renameTab(tabId:name:)` after the editor commits.
- `TabRenamePopover` owns its text editor keys. Return, Cmd-Return, keypad
  Enter, and Escape are consumed by the editor and must not propagate upward
  into `KeyboardOwner`, `AppShortcutDispatchPolicy`, or app command handling.
- `.renameTab` intentionally has no `AppShortcut` case. Keyboard policy should
  have no rename row until a real app-owned rename shortcut is designed.

### The Four Distinct Questions

Do not collapse these into one state object.

| Question | Owner | Current live code |
| --- | --- | --- |
| Which command exists? | `AppCommand` | `App/Commands/AppCommand.swift` |
| Which key fires it? | `AppShortcut` | `App/Commands/AppShortcut.swift` |
| Should it be visible? | `WorkspacePaneFocus` + `CommandSpec.visibleWhen` | `Core/State/MainActor/Atoms/WorkspacePaneFocus.swift` |
| Who owns keyboard interpretation? | `KeyboardOwner.current(...)` | `Core/Models/KeyboardOwner.swift` |

### Compile-Time Safety Rules

This refactor is only successful if adding a new command or shortcut forces an
explicit routing decision at compile time.

- `AppShortcutDispatchPolicy` must switch exhaustively over `AppShortcut` for
  sidebar-owned keyboard states. Do not use `default` or `@unknown default`.
- Each later task that adds `AppShortcut` cases must update
  `AppShortcutDispatchPolicy` in the same changeset.
- Every `AppCommand` must have a `CommandSpec` covered by command-spec contract
  tests.
- Every `AppShortcut` must map to an `AppCommand`, except the existing explicit
  `.newTab -> .showCommandBarRepos` alias.
- Focus-only commands must be explicitly excluded from
  `WorkspaceCommandResolver` so they cannot accidentally become structural pane
  mutations.
- Keyboard ingress should be visible in one of three places:
  `AppShortcut`, `scopeAwarePaneCommand(for:)`, or a local SwiftUI/AppKit
  control with documented local ownership. New view-local `.keyboardShortcut`
  usages are out of scope for this refactor unless the plan names why they are
  local and not app-owned.
- No key event path should call `dispatchAction(...)` directly when an
  `AppCommand` already exists. Use `CommandDispatcher` first, then resolve to
  `PaneActionCommand` or `PaneFocusTrigger` at the owning boundary.

## Findings This Plan Must Fix

### Finding 1: `shouldDispatchGlobalShortcut(...)` Is Not Production Wiring

Before this refactor, `PaneTabViewController.shouldDispatchGlobalShortcut(...)`
encoded policy, but `handleAppOwnedKeyEvent(...)` did not call it before
dispatching a global `AppShortcut`. The tests covered the helper, not the
production path.

The implementation deletes that stale helper, replaces it with explicit
`AppShortcutDispatchPolicy`, and calls the policy from
`handleAppOwnedKeyEvent(...)`.

### Finding 2: Empty-Drawer `P` Uses The Shortcut Catalog But Bypasses Command Dispatch

Raw `P` in `.emptyDrawer` is modeled as an alternate trigger for
`AppShortcut.addDrawerPane`, but the event path currently resolves the parent
pane and directly calls `dispatchAction(.addDrawerPane(parentPaneId: ...))`.

That shortcut needs a consistent command path:

```text
raw P in empty drawer
  -> ShortcutDecoder.shortcut(..., in: .emptyDrawer) == .addDrawerPane
  -> resolve parent pane
  -> CommandDispatcher.dispatch(.addDrawerPane, target: parentPaneId, targetType: .pane)
  -> PaneTabViewController.targetedAction(...)
  -> PaneActionCommand.addDrawerPane(parentPaneId:)
  -> validated action execution
```

### Finding 3: Ordinal Pane Shortcuts Are Exact Commands, Not Focus-Scoped Keys

`Cmd+Shift+1...9` and `Cmd+Shift+Option+1...9` each map to exactly one semantic
command in every listed context. They belong in `AppShortcut`.

They still must obey `KeyboardOwner` at dispatch time:

- When `KeyboardOwner` is `.mainWindowChain`, pane ordinal shortcuts are allowed.
- When `KeyboardOwner` is `.managementLayer`, command-modified shortcuts keep
  the existing management-layer pass-through behavior.
- When `KeyboardOwner` is `.sidebar(.repos)` or `.sidebar(.inbox)`, pane ordinal
  shortcuts must not steal focus from the sidebar surface.
- When `KeyboardOwner` is `.otherWindow`, app-owned pane shortcuts must not fire.

### Finding 4: Inbox Sidebar Focus Publication Is A Sharp Edge

The inbox has a focus bridge for first responder handoff, but its SwiftUI focus
container currently clears `sidebarHasFocus` on nil and does not publish true
when focus moves to real inbox controls. That can make
`KeyboardOwner.current(...)` fall back to `.mainWindowChain`.

This is not required to add ordinal pane shortcuts, but it is required to trust
`KeyboardOwner` for surface ownership. This plan includes a small focus
publication fix before relying on the owner for routing.

### Finding 5: Existing Focus `PaneActionCommand` Cases Are Legacy Residue

`PaneActionCommand` still contains drawer focus cases, but the live controller
routes drawer focus through `PaneFocusTrigger.drawer(.selectPane(...))`.

Do not add new focus `PaneActionCommand` cases. New ordinal focus commands must
enter through `PaneTabViewController.handlePaneFocusCommand(_:)` and emit
`PaneFocusTrigger` values.

### Finding 6: Tab And Arrangement Cycling Need Exact Shortcut Ownership

`Option+I/J/K/L` is a scope-aware pane/drawer movement surface handled locally by
`PaneTabViewController.scopeAwarePaneCommand(for:)`. The new
`Cmd+Option+I/J/L` bindings are different: they are exact app-owned commands and
must live in `AppShortcut`.

Use the existing tab commands for horizontal tab switching:

- `Cmd+Option+J` -> `AppCommand.prevTab`
- `Cmd+Option+L` -> `AppCommand.nextTab`

Arrangement cycling needs one new semantic command because the existing
`AppCommand.switchArrangement` is targeted at a specific arrangement. Add
`AppCommand.cycleArrangement`, resolve it against the active tab's arrangement
order, then execute the existing `PaneActionCommand.switchArrangement`.

## Product Behavior

### Main Pane Ordinals

- `Cmd+Shift+1...9` targets main panes in active arrangement order.
- The order source is `Tab.activePaneIds`, which follows
  `activeArrangement.layout.paneIds`.
- Minimized panes keep their ordinal and remain addressable.
- If the target main pane is minimized, expand it before focusing it.
- If the tab is zoomed and the target is not the current zoomed pane, set zoom to
  the target pane and then focus it. This preserves zoom mode while making every
  ordinal meaningful.
- If the ordinal is out of range, the command is unavailable and dispatch no-ops.

### Tab And Arrangement Cycling

- `Cmd+Option+J` switches to the previous tab.
- `Cmd+Option+L` switches to the next tab.
- These are a hard cutover for `AppShortcut.nextTab` and
  `AppShortcut.prevTab`; do not keep bracket shortcuts as alternate triggers in
  this refactor.
- `Cmd+Option+I` cycles the active tab to the next arrangement in
  `tab.arrangements` order.
- Arrangement cycling wraps from the final arrangement back to the first.
- If there is no active tab or the active tab has fewer than two arrangements,
  `cycleArrangement` is unavailable and dispatch no-ops.
- `cycleArrangement` must execute through the existing
  `PaneActionCommand.switchArrangement(tabId:arrangementId:)`; do not create a
  new pane-action case.
- `Cmd+Option+I/J/L` are app-owned shortcuts and obey
  `AppShortcutDispatchPolicy`. They are allowed in `.mainWindowChain` and
  `.managementLayer`, and blocked while `.sidebar(.repos)`, `.sidebar(.inbox)`,
  or `.otherWindow` owns keyboard interpretation.

### Drawer Pane Ordinals

- `Cmd+Shift+Option+1...9` targets drawer panes by drawer-wide order.
- The order source is `DrawerGridLayout.paneIds`.
- Top and bottom drawer rows must not each restart at `1`.
- Minimized drawer panes keep their ordinal and remain addressable.
- If focus is already in a drawer, drawer ordinals target that drawer's parent.
- If focus is in an empty drawer, drawer ordinals target that drawer's parent
  but remain unavailable until the drawer has an addressable child pane.
- If focus is in a main pane, drawer ordinals target the active main pane's
  drawer.
- If the target drawer pane is minimized, expand it before focusing it.
- If the parent drawer is collapsed but populated, open it before selecting the
  target child pane.
- If no drawer, no parent, or out-of-range ordinal exists, the command is
  unavailable and dispatch no-ops.
- Do not use `visibleDrawerPaneIds(for:)` for ordinal resolution because it
  filters minimized panes.

### Focus Restoration Contract

- Pane focus restoration is `WorkspaceFocusOwner`-driven.
- In main-pane scope, the active main pane is the visible focus target.
- In drawer-pane scope, the visible focused drawer child is the focus identity,
  not the parent main pane.
- In empty-drawer scope, the parent pane owns the empty drawer surface and drawer
  ordinal commands do not synthesize a hidden child target.
- Command execution should use `normalizedWorkspaceNavigationScopeState()` and
  the pane-focus pipeline so `WorkspacePaneFocusDerived` stays consistent with
  the responder target.

### Badges

- Badges render for every currently rendered addressable pane.
- Badge numbers must match the shortcut target exactly.
- Main badges use `Tab.activePaneIds` ordinals.
- Drawer badges use `DrawerGridLayout.paneIds` ordinals.
- Minimized bars keep their badge.
- Zoomed content shows the zoomed pane's underlying ordinal.
- Badges are visible in management layer.
- Badges are non-interactive and accessibility-hidden.
- Badges must not cover terminal input, pane chrome controls, drawer controls,
  editor chooser controls, pane inbox controls, management controls, or split
  handles.

## Implementation Tasks

### Task 1: Global Shortcut Dispatch Policy

**Files:**

- Create: `Sources/AgentStudio/App/Commands/AppShortcutDispatchPolicy.swift`
- Modify: `Sources/AgentStudio/App/Panes/PaneTabViewController.swift`
- Modify: `Tests/AgentStudioTests/App/PaneTabViewControllerGlobalShortcutRoutingTests.swift`

- [ ] **Step 1: Write policy tests that fail against current production behavior**

Add tests that prove the policy allows and blocks by `KeyboardOwner`.

Required cases:

- `.mainWindowChain` allows pane-affecting exact shortcuts.
- `.sidebar(.repos)` blocks pane-affecting exact shortcuts.
- `.sidebar(.inbox)` blocks pane-affecting exact shortcuts.
- `.sidebar(.repos)` still allows sidebar surface commands such as
  `.showInboxNotifications`, `.showWorktreeSidebar`, `.toggleSidebar`, and
  command-bar launchers.
- `.sidebar(.inbox)` does not allow `.filterSidebar`.
- `.sidebar(.repos)` and `.sidebar(.inbox)` block `.prevTab`, `.nextTab`, and
  `.cycleArrangement` for the same reason they block pane ordinals: sidebar
  focus owns keyboard interpretation.
- The policy uses no `default` branch, so new `AppShortcut` cases fail to
  compile until they choose an explicit routing row.
- `.managementLayer` preserves existing command-modified pass-through behavior,
  so ordinal shortcuts remain active while management chrome is visible.
- The production `handleAppOwnedKeyEvent(...)` / `performKeyEquivalent(with:)`
  path calls the policy before dispatching `.global` shortcuts. Do not treat
  `shouldDispatchGlobalShortcut(...)` as proof unless it delegates to the new
  policy and is exercised by the production ingress tests.

- [ ] **Step 2: Add the policy type**

Suggested shape:

```swift
@MainActor
enum AppShortcutDispatchPolicy {
    static func shouldDispatchGlobalShortcut(
        _ shortcut: AppShortcut,
        keyboardOwner: KeyboardOwner
    ) -> Bool {
        switch keyboardOwner {
        case .otherWindow:
            return false
        case .managementLayer:
            return true
        case .mainWindowChain:
            return true
        case .sidebar(let surface):
            return sidebarOwnedPolicy(shortcut, surface: surface)
        }
    }

    private static func sidebarOwnedPolicy(
        _ shortcut: AppShortcut,
        surface: SidebarSurface
    ) -> Bool {
        switch shortcut {
        case .toggleSidebar,
            .showInboxNotifications,
            .showWorktreeSidebar,
            .showCommandBarEverything,
            .showCommandBarCommands,
            .showCommandBarPanes:
            return true
        case .filterSidebar:
            return surface == .repos
        case .closeTab,
            .newTab,
            .undoCloseTab,
            .nextTab,
            .prevTab,
            .addDrawerPane,
            .toggleDrawer,
            .scrollToBottom,
            .openPaneLocationInBookmarkedEditor,
            .openPaneLocationInFinder,
            .openPaneLocationInEditorMenu,
            .toggleManagementLayer,
            .showPaneInboxNotifications,
            .newWindow,
            .closeWindow,
            .selectTab1,
            .selectTab2,
            .selectTab3,
            .selectTab4,
            .selectTab5,
            .selectTab6,
            .selectTab7,
            .selectTab8,
            .selectTab9,
            .managementLayerFocusLeft,
            .managementLayerFocusRight,
            .managementLayerEnterDrawer,
            .managementLayerExitDrawer,
            .managementLayerOpenDrawer,
            .managementLayerCreateTerminal,
            .managementLayerCreateBrowser,
            .managementLayerExit:
            return false
        }
    }
}
```

The exact allow-list must be explicit. New shortcuts must choose a policy row.
This policy intentionally blocks pane ordinals, tab cycling, and arrangement
cycling while a sidebar surface owns focus.

- [ ] **Step 3: Wire production dispatch through the policy**

In `PaneTabViewController.handleAppOwnedKeyEvent(...)`, after resolving a
`.global` shortcut and before `CommandDispatcher.shared.canDispatch(...)`, compute:

```swift
let owner = KeyboardOwner.current(
    windowLifecycle: atom(\.windowLifecycle),
    managementLayer: atom(\.managementLayer),
    uiState: atom(\.uiState)
)
guard AppShortcutDispatchPolicy.shouldDispatchGlobalShortcut(
    shortcut,
    keyboardOwner: owner
) else {
    return false
}
```

- [ ] **Step 4: Remove or replace stale helper tests**

If `PaneTabViewController.shouldDispatchGlobalShortcut(...)` remains, it must
delegate to `AppShortcutDispatchPolicy`. Prefer deleting it if no call sites
remain after the policy lands.

- [ ] **Step 5: Verify**

Run:

```bash
mise run test -- --filter "PaneTabViewControllerGlobalShortcutRoutingTests|ShortcutCatalogTests"
```

Expected: pass.

### Task 2: Command Boundary Exhaustiveness

**Files:**

- Modify: `Sources/AgentStudio/App/Boot/AppDelegate+ShellCommandHandling.swift`
- Modify: `Sources/AgentStudio/App/Panes/PaneTabViewController.swift`
- Modify: `Sources/AgentStudio/Core/Actions/ActionResolver.swift`
- Test: `Tests/AgentStudioTests/App/AppDelegateInboxNotificationCommandsTests.swift`
- Test: `Tests/AgentStudioTests/App/AppCommandTests.swift`
- Test: `Tests/AgentStudioTests/Core/Actions/ActionResolverTests.swift`
- Test: `Tests/AgentStudioTests/Architecture/CoordinationPlaneArchitectureTests.swift`

- [ ] **Step 1: Write failing command-boundary tests**

Add coverage for commands that arrived from current `origin/main` and can be
missed by default branches:

- `toggleInboxNotificationSort` is shell-owned and never resolves through
  `WorkspaceCommandResolver`.
- `clearReadInboxNotifications` is shell-owned and never resolves through
  `WorkspaceCommandResolver`.
- `clearAllInboxNotifications` is shell-owned and never resolves through
  `WorkspaceCommandResolver`.
- `showPaneInboxNotifications` and `clearPaneInboxNotifications` remain
  workspace-owned pane-inbox commands, not shell commands.
- `AppDelegate+ShellCommandHandling` does not use `default` in its command
  routing switches.
- `WorkspaceCommandResolver.isNonPaneCommand(...)` does not use `default`.

- [ ] **Step 2: Make shell command ownership exhaustive**

In `AppDelegate+ShellCommandHandling.swift`, replace `default: false` and
`default: return false` with exhaustive false rows. This makes any future
`AppCommand` addition choose whether the shell owns it.

The true row must include:

```swift
.watchFolder,
.toggleSidebar,
.filterSidebar,
.showInboxNotifications,
.toggleInboxNotificationSort,
.clearReadInboxNotifications,
.clearAllInboxNotifications,
.showWorktreeSidebar,
.signInGitHub,
.signInGoogle,
.newWindow,
.closeWindow,
.showCommandBarEverything,
.showCommandBarCommands,
.showCommandBarPanes,
.showCommandBarRepos
```

- [ ] **Step 3: Make resolver ownership exhaustive**

In `WorkspaceCommandResolver.isNonPaneCommand(...)`, remove the `default` branch
and explicitly classify every `AppCommand`.

The non-pane row must include the current inbox commands:

```swift
.toggleInboxNotificationSort,
.clearReadInboxNotifications,
.clearAllInboxNotifications
```

Focus-only commands, including the new ordinal commands, must also be explicit
non-pane resolver commands so structural validation cannot accidentally claim
them.

- [ ] **Step 4: Keep pane controller fallbacks explicit**

Where `PaneTabViewController` intentionally ignores shell-owned commands in
`handleDirectCommand(_:)`, keep those commands in a named exhaustive row instead
of relying on accidental fallthrough. The post-merge inbox commands must remain
in that row:

```swift
.showInboxNotifications,
.toggleInboxNotificationSort,
.clearReadInboxNotifications,
.clearAllInboxNotifications
```

- [ ] **Step 5: Verify**

Run:

```bash
mise run test -- --filter "AppCommandTests|AppDelegateInboxNotificationCommandsTests|ActionResolverTests|CoordinationPlaneArchitectureTests"
```

Expected: pass.

### Task 3: Inbox Sidebar Focus Publication

**Files:**

- Modify: `Sources/AgentStudio/Features/InboxNotification/Views/InboxSidebarComponents.swift`
- Test: `Tests/AgentStudioTests/Features/InboxNotification/Views/InboxNotificationSidebarViewTests.swift`
- Test: `Tests/AgentStudioTests/Core/State/MainActor/Atoms/KeyboardOwnerDerivedTests.swift`

- [ ] **Step 1: Write failing focus publication tests**

Add coverage for:

- Focus entering inbox search publishes `uiState.sidebarHasFocus == true`.
- Focus entering an inbox row publishes `uiState.sidebarHasFocus == true`.
- Focus becoming nil publishes `uiState.sidebarHasFocus == false`.
- With `sidebarSurface == .inbox` and inbox focus true,
  `KeyboardOwner.current(...) == .sidebar(.inbox)`.

- [ ] **Step 2: Publish non-nil inbox focus**

Update `InboxSidebarRootContainer` so its `focusedField` change mirrors
`RepoExplorerFocusPublisher` behavior:

```swift
.onChange(of: focusedField.wrappedValue) { _, newValue in
    uiState.setSidebarHasFocus(newValue != nil)
}
```

Keep `InboxNotificationSidebarFocusBridge` as the initial AppKit focus target.

- [ ] **Step 3: Verify**

Run:

```bash
mise run test -- --filter "InboxNotificationSidebarViewTests|KeyboardOwnerDerivedTests|CommandBarInboxScopeDefaultingTests"
```

Expected: pass.

### Task 4: Empty-Drawer `P` Through Targeted Command Dispatch

**Files:**

- Modify: `Sources/AgentStudio/App/Panes/PaneTabViewController.swift`
- Modify: `Sources/AgentStudio/Core/Actions/ActionResolver.swift` if pure
  resolver support is useful for tests.
- Test: `Tests/AgentStudioTests/App/PaneTabViewControllerEmptyDrawerShortcutTests.swift`
- Test: `Tests/AgentStudioTests/App/PaneTabViewControllerDrawerCommandTests.swift`

- [ ] **Step 1: Write failing tests for the command path**

Add tests proving:

- Raw `P` in `.emptyDrawer` still adds a drawer pane.
- Raw `P` does not fire when a text responder owns focus.
- `Cmd+Shift+D` still adds a drawer pane.
- Empty-drawer raw `P` reaches `CommandDispatcher.dispatch(_:target:targetType:)`
  semantics by exercising targeted `.addDrawerPane` support.

- [ ] **Step 2: Add targeted `.addDrawerPane` support**

In `PaneTabViewController.targetedAction(command:target:targetType:)`, add:

```swift
case (.addDrawerPane, .pane), (.addDrawerPane, .floatingTerminal):
    return .addDrawerPane(parentPaneId: target)
```

Validation already knows how to validate `PaneActionCommand.addDrawerPane`.

- [ ] **Step 3: Route empty-drawer `P` through dispatcher**

Replace the direct action dispatch in `handleAppOwnedKeyEvent(...)`:

```swift
CommandDispatcher.shared.dispatch(
    .addDrawerPane,
    target: parentPaneId,
    targetType: .pane
)
```

Do not call `dispatchAction(.addDrawerPane(parentPaneId: ...))` directly from
the key event path.

- [ ] **Step 4: Verify**

Run:

```bash
mise run test -- --filter "PaneTabViewControllerEmptyDrawerShortcutTests|PaneTabViewControllerDrawerCommandTests|ActionValidatorTests"
```

Expected: pass.

### Task 5: Command Catalog For Ordinal Pane Shortcuts

**Files:**

- Modify: `Sources/AgentStudio/App/Commands/AppCommand.swift`
- Modify: `Sources/AgentStudio/App/Commands/AppCommand+Catalog.swift`
- Modify: `Sources/AgentStudio/App/Commands/AppShortcut.swift`
- Modify: `Sources/AgentStudio/App/Commands/AppShortcutDispatchPolicy.swift`
- Modify: `Sources/AgentStudio/Core/Actions/ActionResolver.swift`
- Test: `Tests/AgentStudioTests/App/ShortcutCatalogTests.swift`
- Test: `Tests/AgentStudioTests/App/CommandSpecContractTests.swift`
- Test: `Tests/AgentStudioTests/Core/Actions/ActionResolverTests.swift`
- Test: `Tests/AgentStudioTests/Features/Terminal/Ghostty/GhosttySurfaceShortcutTests.swift`
- Test: `Tests/AgentStudioTests/Features/CommandBar/CommandBarDataSourceTests.swift`

- [ ] **Step 1: Write failing catalog tests**

Add tests for:

- `focusPane1...focusPane9` commands exist.
- `focusDrawerPane1...focusDrawerPane9` commands exist.
- `Cmd+Shift+1...9` decode in `.global` and `.terminalAppOwned`.
- `Cmd+Shift+Option+1...9` decode in `.global` and `.terminalAppOwned`.
- `Ghostty.SurfaceView.appOwnedShortcuts` includes the new ordinal shortcuts so
  terminal focus uses the same app-owned shortcut path.
- Every new `AppShortcut` maps to the matching `AppCommand`.
- Every new command has a hidden `CommandSpec`.
- The command-bar data source does not surface any of the 18 hidden ordinal
  commands in `.commands` results.
- `WorkspaceCommandResolver.resolve(command:...)` returns nil for every new
  focus-only ordinal command.
- `AppShortcutDispatchPolicy` blocks the new pane ordinal shortcuts while
  `KeyboardOwner` is `.sidebar(.repos)` or `.sidebar(.inbox)`.
- `AppShortcutDispatchPolicy.sidebarOwnedPolicy(...)` remains exhaustive and
  contains no `default` branch after adding the new ordinal shortcut cases.

- [ ] **Step 2: Add command cases**

Add:

```swift
case focusPane1, focusPane2, focusPane3, focusPane4, focusPane5
case focusPane6, focusPane7, focusPane8, focusPane9
case focusDrawerPane1, focusDrawerPane2, focusDrawerPane3, focusDrawerPane4, focusDrawerPane5
case focusDrawerPane6, focusDrawerPane7, focusDrawerPane8, focusDrawerPane9
```

- [ ] **Step 3: Add ordered command helpers**

Add helpers near `selectTabCommands`:

```swift
static let focusPaneCommands: [AppCommand] = [
    .focusPane1, .focusPane2, .focusPane3, .focusPane4, .focusPane5,
    .focusPane6, .focusPane7, .focusPane8, .focusPane9,
]

static let focusDrawerPaneCommands: [AppCommand] = [
    .focusDrawerPane1, .focusDrawerPane2, .focusDrawerPane3,
    .focusDrawerPane4, .focusDrawerPane5, .focusDrawerPane6,
    .focusDrawerPane7, .focusDrawerPane8, .focusDrawerPane9,
]
```

- [ ] **Step 4: Add shortcut cases and digit helpers**

Add 18 `AppShortcut` cases and helper specs:

```swift
fileprivate static func focusPaneSpec(key: ShortcutCharacterKey) -> AppShortcutSpec {
    .init(
        trigger: .init(key: .character(key), modifiers: [.command, .shift]),
        contexts: [.global, .terminalAppOwned]
    )
}

fileprivate static func focusDrawerPaneSpec(key: ShortcutCharacterKey) -> AppShortcutSpec {
    .init(
        trigger: .init(key: .character(key), modifiers: [.command, .shift, .option]),
        contexts: [.global, .terminalAppOwned]
    )
}
```

- [ ] **Step 5: Add hidden command specs**

Use hidden command specs so the shortcuts exist in menus/metadata but do not add
18 noisy command-bar rows.

Requirements:

- Main labels: `Focus Pane 1` through `Focus Pane 9`.
- Drawer labels: `Focus Drawer Pane 1` through `Focus Drawer Pane 9`.
- Main visible requirements: `.hasActiveTab`.
- Drawer visible requirements: `.hasActivePane`.
- `isHiddenInCommandBar: true`.

- [ ] **Step 6: Keep structural resolver out of focus**

Update `WorkspaceCommandResolver.isNonPaneCommand(...)` or switch cases so all
new ordinal focus commands resolve to nil.

- [ ] **Step 7: Update the exhaustive shortcut policy**

Add every new ordinal `AppShortcut` case to the false/blocking row in
`AppShortcutDispatchPolicy.sidebarOwnedPolicy(...)`. This is intentionally
compile-time noisy: the app should not compile after adding the cases until the
policy chooses whether each new shortcut is sidebar-owned or app-owned.

- [ ] **Step 8: Verify**

Run:

```bash
mise run test -- --filter "ShortcutCatalogTests|CommandSpecContractTests|ActionResolverTests|PaneTabViewControllerGlobalShortcutRoutingTests|GhosttySurfaceShortcutTests|CommandBarDataSourceTests"
```

Expected: pass.

### Task 6: Tab And Arrangement Cycling Shortcuts

**Files:**

- Modify: `Sources/AgentStudio/App/Commands/AppCommand.swift`
- Modify: `Sources/AgentStudio/App/Commands/AppCommand+Catalog.swift`
- Modify: `Sources/AgentStudio/App/Commands/AppShortcut.swift`
- Modify: `Sources/AgentStudio/App/Commands/AppShortcutDispatchPolicy.swift`
- Modify: `Sources/AgentStudio/App/Panes/PaneTabViewController.swift`
- Modify: `Sources/AgentStudio/Core/Actions/ActionResolver.swift`
- Test: `Tests/AgentStudioTests/App/ShortcutCatalogTests.swift`
- Test: `Tests/AgentStudioTests/App/CommandSpecContractTests.swift`
- Test: `Tests/AgentStudioTests/App/PaneTabViewControllerCommandTests.swift`
- Test: `Tests/AgentStudioTests/App/PaneTabViewControllerGlobalShortcutRoutingTests.swift`
- Test: `Tests/AgentStudioTests/Core/Actions/ActionResolverTests.swift`
- Test: `Tests/AgentStudioTests/Features/Terminal/Ghostty/GhosttySurfaceShortcutTests.swift`

- [ ] **Step 1: Write failing shortcut and command tests**

Add tests proving:

- `AppShortcut.prevTab` decodes `Cmd+Option+J` in `.global` and
  `.terminalAppOwned`.
- `AppShortcut.nextTab` decodes `Cmd+Option+L` in `.global` and
  `.terminalAppOwned`.
- `AppShortcut.cycleArrangement` decodes `Cmd+Option+I` in `.global` and
  `.terminalAppOwned`.
- `Cmd+Shift+[` and `Cmd+Shift+]` no longer decode as tab switching shortcuts.
- `Ghostty.SurfaceView.appOwnedShortcuts` includes the tab and arrangement
  cycling shortcuts.
- `AppShortcutDispatchPolicy` blocks `.prevTab`, `.nextTab`, and
  `.cycleArrangement` while `KeyboardOwner` is `.sidebar(.repos)` or
  `.sidebar(.inbox)`.
- `AppShortcutDispatchPolicy.sidebarOwnedPolicy(...)` remains exhaustive and
  contains no `default` branch after adding `.cycleArrangement`.

- [ ] **Step 2: Move tab shortcut bindings**

Update `AppShortcut.nextTab` and `AppShortcut.prevTab`:

```swift
case .nextTab:
    return .init(
        trigger: .init(key: .character(.l), modifiers: [.command, .option]),
        contexts: [.global, .terminalAppOwned]
    )
case .prevTab:
    return .init(
        trigger: .init(key: .character(.j), modifiers: [.command, .option]),
        contexts: [.global, .terminalAppOwned]
    )
```

Do not add the old bracket shortcuts as alternates.

- [ ] **Step 3: Add `cycleArrangement` to command and shortcut catalogs**

Add `case cycleArrangement` to `AppCommand` near the arrangement commands and
`case cycleArrangement` to `AppShortcut`.

Add the shortcut spec:

```swift
case .cycleArrangement:
    return .init(
        trigger: .init(key: .character(.i), modifiers: [.command, .option]),
        contexts: [.global, .terminalAppOwned]
    )
```

Add a visible command spec:

```swift
case .cycleArrangement:
    return CommandSpec(
        command: self,
        shortcut: .cycleArrangement,
        label: "Cycle Arrangement",
        icon: .system(.rectangle3Group),
        helpText: "Switch the active tab to the next saved arrangement",
        appliesTo: [.tab],
        visibleWhen: [.hasActiveTab],
        commandBarGroupName: "Tab",
        commandBarGroupPriority: CommandBarGroupPriority.tab
    )
```

- [ ] **Step 4: Keep resolver boundaries explicit**

Add `.cycleArrangement` to `WorkspaceCommandResolver.isNonPaneCommand(...)`.
The pure resolver should not guess which arrangement is next because that logic
depends on the live active tab.

- [ ] **Step 5: Update the exhaustive shortcut policy**

Add `.cycleArrangement` to the false/blocking row in
`AppShortcutDispatchPolicy.sidebarOwnedPolicy(...)`. Keep `.nextTab` and
`.prevTab` blocked while sidebar focus owns keyboard interpretation. Do not add
a `default` branch to quiet the compiler.

- [ ] **Step 6: Execute arrangement cycling from the pane controller**

Add a helper in `PaneTabViewController`:

```swift
private func resolveNextArrangementTarget() -> (tabId: UUID, arrangementId: UUID)? {
    guard
        let tabId = store.tabLayoutAtom.activeTabId,
        let tab = store.tabLayoutAtom.tab(tabId),
        tab.arrangements.count > 1,
        let currentIndex = tab.arrangements.firstIndex(where: { $0.id == tab.activeArrangementId })
    else { return nil }

    let nextIndex = (currentIndex + 1) % tab.arrangements.count
    return (tabId, tab.arrangements[nextIndex].id)
}
```

Handle the command in `execute(_:)`:

```swift
case .cycleArrangement:
    guard let target = resolveNextArrangementTarget() else { break }
    dispatchAction(.switchArrangement(tabId: target.tabId, arrangementId: target.arrangementId))
```

Handle availability in `canExecute(_:)`:

```swift
case .cycleArrangement:
    return resolveNextArrangementTarget() != nil
```

- [ ] **Step 7: Preserve tab switching through the existing focus path**

Keep `.nextTab` and `.prevTab` in `handlePaneFocusCommand(_:)` so tab switching
continues through `PaneFocusTrigger.command(.selectTab(...))` and restores the
visible responder correctly.

- [ ] **Step 8: Verify**

Run:

```bash
mise run test -- --filter "ShortcutCatalogTests|CommandSpecContractTests|PaneTabViewControllerCommandTests|PaneTabViewControllerGlobalShortcutRoutingTests|ActionResolverTests|GhosttySurfaceShortcutTests"
```

Expected: pass.

### Task 7: Shared Ordinal Model

**Files:**

- Create: `Sources/AgentStudio/Core/Models/PaneOrdinalMap.swift`
- Test: `Tests/AgentStudioTests/Core/Models/PaneOrdinalMapTests.swift`

- [ ] **Step 1: Write pure failing tests**

Add tests for:

- Main pane ordinal map preserves `Tab.activePaneIds` order.
- Main pane ordinal target returns nil for out-of-range ordinals.
- Drawer ordinal map preserves `DrawerGridLayout.paneIds`.
- Drawer top and bottom rows produce one continuous sequence.

- [ ] **Step 2: Add pure helper**

Suggested shape:

```swift
struct PaneOrdinalMap: Equatable, Sendable {
    let paneIdByOrdinal: [Int: UUID]
    let ordinalByPaneId: [UUID: Int]

    init(orderedPaneIds: [UUID]) {
        var paneIdByOrdinal: [Int: UUID] = [:]
        var ordinalByPaneId: [UUID: Int] = [:]
        for (index, paneId) in orderedPaneIds.prefix(9).enumerated() {
            let ordinal = index + 1
            paneIdByOrdinal[ordinal] = paneId
            ordinalByPaneId[paneId] = ordinal
        }
        self.paneIdByOrdinal = paneIdByOrdinal
        self.ordinalByPaneId = ordinalByPaneId
    }

    func paneId(forOrdinal ordinal: Int) -> UUID? {
        paneIdByOrdinal[ordinal]
    }

    func ordinal(forPaneId paneId: UUID) -> Int? {
        ordinalByPaneId[paneId]
    }
}
```

Keep this helper pure and UI-free. Command resolution and badge rendering must
share it.

- [ ] **Step 3: Verify**

Run:

```bash
mise run test -- --filter "PaneOrdinalMapTests"
```

Expected: pass.

### Task 8: Main Pane Ordinal Focus

**Files:**

- Modify: `Sources/AgentStudio/App/Panes/PaneTabViewController.swift`
- Test: `Tests/AgentStudioTests/App/PaneTabViewControllerCommandTests.swift`

- [ ] **Step 1: Write failing command tests**

Add tests proving:

- `focusPane1` focuses the first active-arrangement pane.
- `focusPane3` focuses the third active-arrangement pane.
- Out-of-range ordinal no-ops and `canExecute` is false.
- Minimized target expands before focus.
- If split zoom is active and target differs from current zoomed pane, zoom
  moves to the target and focus follows.
- The final focus action goes through the pane focus pipeline.

- [ ] **Step 2: Add main ordinal resolution**

Add helpers:

```swift
private func mainPaneOrdinal(for command: AppCommand) -> Int? {
    AppCommand.focusPaneCommands.firstIndex(of: command).map { $0 + 1 }
}

private func resolveMainPaneOrdinalTarget(for command: AppCommand) -> (tabId: UUID, paneId: UUID)? {
    guard
        let ordinal = mainPaneOrdinal(for: command),
        let tabId = store.tabLayoutAtom.activeTabId,
        let tab = store.tabLayoutAtom.tab(tabId)
    else { return nil }

    let ordinalMap = PaneOrdinalMap(orderedPaneIds: tab.activePaneIds)
    guard let paneId = ordinalMap.paneId(forOrdinal: ordinal) else { return nil }
    return (tabId, paneId)
}
```

- [ ] **Step 3: Execute via existing focus pipeline**

In `handlePaneFocusCommand(_:)`, handle main ordinal commands:

- Resolve target.
- If minimized, dispatch `.expandPane(tabId:paneId:)`.
- If zoomed to a different pane, dispatch `.toggleSplitZoom(tabId:paneId:)`
  for the target so zoom switches to the target.
- Call `handlePaneFocusTrigger(.command(.focusPane(tabId:paneId)))`.

- [ ] **Step 4: Add `canExecute` support**

`canExecute(_:)` returns true for main ordinal commands only when
`resolveMainPaneOrdinalTarget(for:)` returns a target.

- [ ] **Step 5: Verify**

Run:

```bash
mise run test -- --filter "PaneTabViewControllerCommandTests|PaneCommandFocusDeciderTests|PaneFocusExecutorTests"
```

Expected: pass.

### Task 9: Drawer Pane Ordinal Focus

**Files:**

- Modify: `Sources/AgentStudio/App/Panes/PaneTabViewController.swift`
- Test: `Tests/AgentStudioTests/App/PaneTabViewControllerDrawerCommandTests.swift`

- [ ] **Step 1: Write failing drawer ordinal tests**

Add tests proving:

- `focusDrawerPane1` targets first drawer pane by `DrawerGridLayout.paneIds`.
- `focusDrawerPane3` targets third drawer pane by `DrawerGridLayout.paneIds`.
- Top and bottom drawer rows share one ordinal sequence.
- Minimized drawer panes remain addressable.
- Minimized target expands before focus.
- Out-of-range ordinal no-ops and `canExecute` is false.
- Drawer ordinals use current drawer parent when focus owner is `.drawerPane`.
- Drawer ordinals use current drawer parent when focus owner is `.emptyDrawer`,
  but return unavailable/no-op when that drawer has no child pane for the
  requested ordinal.
- Drawer ordinals use active main pane when focus owner is `.mainPane`.
- No parent drawer means command unavailable/no-op.

- [ ] **Step 2: Add drawer ordinal helpers**

Add:

```swift
private func drawerPaneOrdinal(for command: AppCommand) -> Int? {
    AppCommand.focusDrawerPaneCommands.firstIndex(of: command).map { $0 + 1 }
}

private func drawerOrdinalParentPaneId() -> UUID? {
    switch normalizedWorkspaceNavigationScopeState() {
    case .drawerPane(let parentPaneId, _), .emptyDrawer(let parentPaneId):
        return parentPaneId
    case .mainPane:
        return activeMainPaneId()
    }
}

private func resolveDrawerPaneOrdinalTarget(
    for command: AppCommand
) -> (parentPaneId: UUID, drawerPaneId: UUID)? {
    guard
        let ordinal = drawerPaneOrdinal(for: command),
        let parentPaneId = drawerOrdinalParentPaneId(),
        let drawer = store.paneAtom.pane(parentPaneId)?.drawer
    else { return nil }

    let ordinalMap = PaneOrdinalMap(orderedPaneIds: drawer.layout.paneIds)
    guard let drawerPaneId = ordinalMap.paneId(forOrdinal: ordinal) else { return nil }
    return (parentPaneId, drawerPaneId)
}
```

- [ ] **Step 3: Execute via existing focus pipeline**

In `handlePaneFocusCommand(_:)`, handle drawer ordinal commands:

- Resolve target.
- If target is minimized, dispatch
  `.expandDrawerPane(parentPaneId:drawerPaneId:)`.
- If the parent drawer is collapsed, dispatch `.toggleDrawer(paneId:)` before
  selecting the drawer child.
- Focus parent first via `.command(.focusPane(tabId:paneId:))` when needed.
- Focus child via `.drawer(.selectPane(parentPaneId:drawerPaneId:))`.

Prefer reusing `focusTargetedDrawerPane(parentPaneId:drawerPaneId:)` if its
current behavior satisfies the tests after minimized expansion is added.

- [ ] **Step 4: Add `canExecute` support**

`canExecute(_:)` returns true for drawer ordinal commands only when
`resolveDrawerPaneOrdinalTarget(for:)` returns a target.

- [ ] **Step 5: Verify**

Run:

```bash
mise run test -- --filter "PaneTabViewControllerDrawerCommandTests|PaneDrawerFocusDeciderTests|PaneFocusExecutorTests"
```

Expected: pass.

### Task 10: Badge Rendering

**Files:**

- Create: `Sources/AgentStudio/SharedComponents/PaneOrdinalBadge.swift`
- Modify: `Sources/AgentStudio/Core/Views/Panes/FlatPaneStripContent.swift`
- Modify: `Sources/AgentStudio/Core/Views/Panes/FlatTabStripContainer.swift`
- Modify: `Sources/AgentStudio/Core/Views/Panes/PaneLeafContainer.swift`
- Modify: `Sources/AgentStudio/Core/Views/Panes/CollapsedPaneBar.swift`
- Modify: `Sources/AgentStudio/Core/Views/Drawer/DrawerPanel.swift`
- Test: `Tests/AgentStudioTests/Core/Models/PaneOrdinalMapTests.swift`
- Add view-level tests only where current test utilities can assert the ordinal
  propagation without brittle pixel checks.

- [ ] **Step 1: Add badge component**

Create a small shared visual component:

```swift
struct PaneOrdinalBadge: View {
    let ordinal: Int

    var body: some View {
        Text("\(ordinal)")
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .frame(minWidth: 18, minHeight: 18)
            .background(.thinMaterial, in: Circle())
            .overlay(Circle().stroke(.separator.opacity(0.55), lineWidth: 1))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
```

Use existing style constants where there is already a local constant for badge
size, typography, or material. Do not create a separate visual language.

- [ ] **Step 2: Thread main ordinals from the active tab boundary**

Compute:

```swift
let mainOrdinalMap = PaneOrdinalMap(orderedPaneIds: tab.activePaneIds)
```

Pass `ordinal: Int?` through the pane rendering chain so the same map drives:

- normal split content,
- all-minimized content,
- collapsed/minimized bars,
- zoomed content.

- [ ] **Step 3: Thread drawer ordinals from `DrawerPanel`**

For each drawer:

```swift
let drawerOrdinalMap = PaneOrdinalMap(orderedPaneIds: drawer.layout.paneIds)
```

Pass each drawer pane's ordinal into row rendering. Do not compute row-local
ordinals inside the top or bottom row.

- [ ] **Step 4: Place badges safely with explicit surface ownership**

Badge placement requirements:

- Does not intercept clicks.
- Does not overlap pane close/minimize/management controls.
- Does not overlap pane inbox badges.
- Does not overlap drawer editor chooser affordances.
- Does not cover terminal input text in normal or zoomed states.
- Remains legible on active and inactive panes.

Use this ownership strategy unless implementation evidence proves a better one:

- Normal split panes:
  - Thread the ordinal through the nested `PaneSegmentSlotView` inside
    `FlatPaneStripContent.swift`.
  - Render the badge from the split-slot composition layer, not from terminal
    content, so the badge is tied to pane geometry and not runtime content.
  - Anchor away from split handles and reserve enough inset that terminal text
    remains readable.
- Zoomed panes:
  - Render the badge from `FlatTabStripContainer.swift` in the zoom shell.
  - Avoid the existing zoom ribbon at the top-right; choose a different corner
    or an inset that cannot collide with `ZoomedIndicator`.
- Management layer:
  - Do not place the badge in `PaneLeafContainer` top-left, top-center, or
    top-right chrome because those anchors are already owned by management
    controls, the drag handle, and edge actions.
  - Keep badges visible while management layer is active, but subordinate their
    placement to the management controls.
- Collapsed/minimized bars:
  - Render the badge in `CollapsedPaneBar.swift` as part of the bar chrome, not
    as an overlay on hidden content.
- Drawer children:
  - Compute ordinals in `DrawerPanel.swift` from `DrawerGridLayout.paneIds`.
  - Pass the child ordinal into row rendering and avoid the drawer editor chooser
    and drawer controls.

- [ ] **Step 5: Verify build**

Run:

```bash
mise run test -- --filter "PaneOrdinalMapTests|TabBar|Drawer|PaneInbox"
mise run build
```

Expected: tests and build pass.

### Task 11: Visual Frontend Validation Packet

**Files:**

- Create: `docs/wip/debugging/2026-05-15-pane-ordinal-shortcuts-visual-validation.md`

- [ ] **Step 1: Launch isolated debug app**

Run:

```bash
mise run build
```

Launch the debug app from the build slot reported by `mise run build`, then use
the repo's visual-verification guide to capture Peekaboo screenshots for that
debug instance. Keep process-launch mechanics in the validation note instead of
hard-coding them in this feature plan.

- [ ] **Step 2: Capture required screenshots**

Capture and document screenshots for:

- one tab with three visible main panes,
- a minimized middle pane with badge still visible,
- split zoom on pane 2 with badge `2`,
- split zoom switched to pane 3 by `Cmd+Shift+3`,
- drawer with at least four panes split across top/bottom rows,
- minimized drawer pane with badge still visible,
- management layer with badges visible and unobstructed,
- inbox/sidebar focused with pane ordinal shortcuts blocked.

- [ ] **Step 3: Record visual acceptance notes**

The validation doc must include:

- debug app identifier,
- build slot,
- commands run,
- screenshot paths,
- pass/fail notes for every scenario,
- any overlap or readability concerns.

Do not claim visual completion from unit tests alone.

### Task 12: Full Verification

- [ ] **Step 1: Focused test pass**

Run:

```bash
mise run test -- --filter "ShortcutCatalogTests|CommandSpecContractTests|PaneTabViewControllerGlobalShortcutRoutingTests|PaneTabViewControllerEmptyDrawerShortcutTests|PaneTabViewControllerCommandTests|PaneTabViewControllerDrawerCommandTests|PaneOrdinalMapTests|ActionResolverTests|KeyboardOwnerDerivedTests|CommandBarInboxScopeDefaultingTests|GhosttySurfaceShortcutTests|CommandBarDataSourceTests|AppDelegateInboxNotificationCommandsTests|CoordinationPlaneArchitectureTests"
```

Expected: pass.

- [ ] **Step 2: Full project pass**

Run:

```bash
mise run test
mise run lint
```

Expected: pass with zero lint errors.

- [ ] **Step 3: Final sanity grep**

Run:

```bash
rg -n "focusPane[1-9]|focusDrawerPane[1-9]|cycleArrangement|nextTab|prevTab|shouldDispatchGlobalShortcut|displayShortcutTrigger|keyboardShortcut" Sources/AgentStudio Tests/AgentStudioTests
```

Expected:

- New ordinal commands appear in command, shortcut, catalog, tests, and
  `PaneTabViewController` execution.
- Tab switching shortcuts are `Cmd+Option+J/L` and old bracket shortcuts are not
  retained as alternates.
- `cycleArrangement` appears in command, shortcut, catalog, policy, controller,
  and tests.
- No stale production dependency remains on the dead
  `shouldDispatchGlobalShortcut(...)` helper.
- Existing `displayShortcutTrigger` use for scope-aware `Option+I/J/K/L` is
  documented and unchanged.
- Existing view-local `.keyboardShortcut` usages are either unrelated local
  controls or documented out of scope.

## Definition Of Done

- `AppShortcutDispatchPolicy` exists and is used by production global shortcut
  dispatch.
- `AppShortcutDispatchPolicy.sidebarOwnedPolicy(...)` uses an exhaustive switch
  with no `default`.
- Shell command ownership and resolver non-pane ownership are exhaustive enough
  that new `AppCommand` cases must choose a boundary.
- Sidebar-owned keyboard states block pane ordinal shortcuts.
- Inbox focus publishes `sidebarHasFocus` correctly for real focused controls.
- Empty-drawer `P` routes through targeted command dispatch.
- `Cmd+Option+J` switches to the previous tab.
- `Cmd+Option+L` switches to the next tab.
- `Cmd+Option+I` cycles to the next arrangement through
  `PaneActionCommand.switchArrangement`.
- Old bracket tab-switching shortcuts are removed from `AppShortcut`.
- All 18 ordinal commands exist in `AppCommand`.
- All 18 ordinal shortcuts exist in `AppShortcut`.
- New commands are hidden from command bar but have catalog metadata.
- New focus-only ordinal commands do not create new `PaneActionCommand` focus
  cases.
- Main pane ordinals use active arrangement order.
- Drawer pane ordinals use `DrawerGridLayout.paneIds`.
- Minimized main and drawer panes remain addressable.
- Zoomed main pane ordinals switch zoom to the requested pane before focusing.
- Badges render in normal, minimized, zoomed, drawer, and management states.
- Peekaboo visual validation is captured for the debug app instance.
- Focused tests pass.
- `mise run test` passes.
- `mise run lint` passes.
