# Ordinal Pane Shortcuts Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Linear:** LUNA-373 — Ordinal pane focus shortcuts and pane number badges

**Goal:** Add `Cmd+Shift+1...9` shortcuts for current-tab panes, `Cmd+Shift+Option+1...9` shortcuts for drawer panes, and matching pane ordinal badges.

**Architecture:** Keep ordinal focus in the existing command/shortcut and pane-focus systems. `AppShortcut` owns key bindings, `AppCommand+Catalog` owns command metadata, `PaneTabViewController` resolves the target pane/drawer pane, and existing focus triggers apply focus. Do not add a validator plane or new `PaneActionCommand` for focus-only behavior; use existing expand actions only when a minimized target must be expanded before focus.

**Tech Stack:** Swift 6.2, AppKit, SwiftUI, Observation, Swift Testing, `mise`.

---

## Prerequisites

- [ ] Rebase or merge the implementation branch onto current `origin/main` before editing.
- [ ] Confirm `docs/architecture/commands_and_shortcuts.md` exists locally after syncing main.
- [ ] Confirm the command catalog split is present:
  - `Sources/AgentStudio/App/Commands/AppCommand.swift`
  - `Sources/AgentStudio/App/Commands/AppShortcut.swift`
  - `Sources/AgentStudio/App/Commands/AppCommand+Catalog.swift`
- [ ] Confirm `DrawerGridLayout` is present and drawer rendering is split across:
  - `Sources/AgentStudio/Core/Models/DrawerGridLayout.swift`
  - `Sources/AgentStudio/Core/Views/Drawer/DrawerPanel.swift`
  - `Sources/AgentStudio/Core/Views/Drawer/DrawerPanelOverlay.swift`
  - `Sources/AgentStudio/Core/Views/Drawer/DrawerIconBar.swift`

This plan was written from `origin/main` at `d0d96511` on 2026-05-02. The local `pane-shortcuts` worktree was 155 commits behind at the time, so do not implement against the unsynced branch shape.

## Decisions

### Shortcut contracts

- Top-level current-tab panes: `Cmd+Shift+1` through `Cmd+Shift+9`.
- Drawer panes: `Cmd+Shift+Option+1` through `Cmd+Shift+Option+9`.
- Use `.global` and `.terminalAppOwned` contexts so shortcuts work while terminal content owns key focus.
- Add explicit allow-list handling in `PaneTabViewController.shouldDispatchGlobalShortcut(...)`.

### Ordinal ordering

- Main panes: active arrangement layout order, `tab.activeArrangement.layout.paneIds` / `tab.activePaneIds`.
- Drawer panes: `drawer.layout.paneIds`, not `drawer.paneIds`.
- `DrawerGridLayout.paneIds` is row-major visual order: top row left-to-right, then bottom row left-to-right.
- Do not use `PaneTabViewController.visibleDrawerPaneIds(for:)` for ordinal resolution because it filters minimized panes.

### Minimized and zoom behavior

- Minimized panes count in the ordinal model and keep their badge number.
- Activating a minimized main pane dispatches `expandPane(tabId:paneId:)`, then applies focus.
- Activating a minimized drawer pane dispatches `expandDrawerPane(parentPaneId:drawerPaneId:)`, then applies drawer focus.
- While zoomed, keep underlying active arrangement ordinals. The zoomed pane badge shows its underlying ordinal. Ordinal shortcuts targeting any non-zoomed pane no-op; do not implicitly unzoom in this ticket.

### Badge behavior

- Badges are always visible for addressable panes, including in management layer.
- Badges are non-interactive and must not cover terminal input, pane controls, drawer controls, editor chooser controls, or inbox controls.
- Main minimized/collapsed pane bars must show badges too.
- Drawer badges must use a drawer-wide ordinal map; do not reset numbering per row when `DrawerPanel` renders top and bottom rows separately.

## File Structure

Create:

- `Sources/AgentStudio/Core/Views/Panes/PaneOrdinalBadge.swift`

Modify:

- `Sources/AgentStudio/App/Commands/AppCommand.swift`
- `Sources/AgentStudio/App/Commands/AppCommand+Catalog.swift`
- `Sources/AgentStudio/App/Commands/AppShortcut.swift`
- `Sources/AgentStudio/App/Panes/PaneTabViewController.swift`
- `Sources/AgentStudio/Core/Actions/ActionResolver.swift`
- `Sources/AgentStudio/Core/Views/Panes/FlatPaneStripContent.swift`
- `Sources/AgentStudio/Core/Views/Panes/PaneLeafContainer.swift`
- `Sources/AgentStudio/Core/Views/Panes/CollapsedPaneBar.swift`
- `Sources/AgentStudio/Core/Views/Drawer/DrawerPanel.swift`

Tests:

- `Tests/AgentStudioTests/App/ShortcutCatalogTests.swift`
- `Tests/AgentStudioTests/App/CommandSpecContractTests.swift`
- `Tests/AgentStudioTests/App/PaneTabViewControllerGlobalShortcutRoutingTests.swift`
- `Tests/AgentStudioTests/App/PaneTabViewControllerCommandTests.swift`
- `Tests/AgentStudioTests/App/PaneTabViewControllerDrawerCommandTests.swift`
- Add a focused view-model/pure-helper test file if badge ordinal maps are extracted.

## Task 1: Command And Shortcut Catalog

**Files:**

- Modify: `Sources/AgentStudio/App/Commands/AppCommand.swift`
- Modify: `Sources/AgentStudio/App/Commands/AppCommand+Catalog.swift`
- Modify: `Sources/AgentStudio/App/Commands/AppShortcut.swift`
- Modify: `Tests/AgentStudioTests/App/ShortcutCatalogTests.swift`
- Modify: `Tests/AgentStudioTests/App/CommandSpecContractTests.swift`

- [ ] **Step 1: Add failing shortcut decode tests**

Add coverage that decodes every pane and drawer ordinal shortcut in both `.global` and `.terminalAppOwned` contexts.

Expected assertions:

```swift
#expect(
    ShortcutDecoder.shortcut(
        for: .init(key: .character(.digit1), modifiers: [.command, .shift]),
        in: .global
    ) == .focusPane1
)
#expect(
    ShortcutDecoder.shortcut(
        for: .init(key: .character(.digit1), modifiers: [.command, .shift, .option]),
        in: .terminalAppOwned
    ) == .focusDrawerPane1
)
```

Repeat or loop for digits 1 through 9.

- [ ] **Step 2: Run the catalog tests and confirm they fail**

Run:

```bash
swift test --build-path ".build-agent-$PPID" --filter "ShortcutCatalogTests|CommandSpecContractTests"
```

Expected: failure because `AppShortcut.focusPane1` and `AppShortcut.focusDrawerPane1` do not exist yet.

- [ ] **Step 3: Add command identities**

Add `AppCommand` cases:

```swift
case focusPane1, focusPane2, focusPane3, focusPane4, focusPane5
case focusPane6, focusPane7, focusPane8, focusPane9
case focusDrawerPane1, focusDrawerPane2, focusDrawerPane3, focusDrawerPane4, focusDrawerPane5
case focusDrawerPane6, focusDrawerPane7, focusDrawerPane8, focusDrawerPane9
```

Add ordered helpers near `selectTabCommands`:

```swift
static let focusPaneCommands: [AppCommand] = [
    .focusPane1, .focusPane2, .focusPane3, .focusPane4, .focusPane5,
    .focusPane6, .focusPane7, .focusPane8, .focusPane9,
]

static let focusDrawerPaneCommands: [AppCommand] = [
    .focusDrawerPane1, .focusDrawerPane2, .focusDrawerPane3, .focusDrawerPane4, .focusDrawerPane5,
    .focusDrawerPane6, .focusDrawerPane7, .focusDrawerPane8, .focusDrawerPane9,
]
```

- [ ] **Step 4: Add shortcut cases and specs**

Add matching `AppShortcut` cases. Use helper methods so digit-to-index mapping is not repeated by hand.

Shape:

```swift
case .focusPane1:
    return Self.focusPaneSpec(key: .digit1)
case .focusDrawerPane1:
    return Self.focusDrawerPaneSpec(key: .digit1)
```

Helper shape:

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

- [ ] **Step 5: Add command definitions**

Add hidden definitions in `AppCommand+Catalog.swift` unless product explicitly wants 18 visible command-bar rows.

Helper shape:

```swift
private func hiddenPaneOrdinalFocusDefinition(index: Int, shortcut: AppShortcut) -> CommandSpec {
    CommandSpec(
        command: self,
        shortcut: shortcut,
        label: "Focus Pane \(index)",
        icon: .system(.rectangleSplit2x1),
        helpText: "Focus pane \(index) in the current tab",
        appliesTo: [.pane],
        visibleWhen: [.hasActivePane],
        commandBarGroupName: "Pane",
        commandBarGroupPriority: CommandBarGroupPriority.pane,
        isHiddenInCommandBar: true
    )
}
```

Use a parallel helper for drawer ordinals with label `Focus Drawer Pane \(index)` and drawer-specific help text.

- [ ] **Step 6: Keep focus-only commands out of the action resolver**

Add the new commands to `ActionResolver.isNonPaneCommand(...)` or the equivalent nil-return path so `ActionResolver.resolve(command:...)` returns `nil`. These commands are handled by `PaneTabViewController`, not `PaneActionCommand`.

- [ ] **Step 7: Re-run catalog and contract tests**

Run:

```bash
swift test --build-path ".build-agent-$PPID" --filter "ShortcutCatalogTests|CommandSpecContractTests"
```

Expected: pass.

## Task 2: Main Pane Ordinal Focus

**Files:**

- Modify: `Sources/AgentStudio/App/Panes/PaneTabViewController.swift`
- Modify: `Tests/AgentStudioTests/App/PaneTabViewControllerGlobalShortcutRoutingTests.swift`
- Modify: `Tests/AgentStudioTests/App/PaneTabViewControllerCommandTests.swift`

- [ ] **Step 1: Add failing routing tests**

Add assertions that all `focusPaneN` and `focusDrawerPaneN` shortcuts are allowed by `PaneTabViewController.shouldDispatchGlobalShortcut(...)`.

Expected assertion shape:

```swift
#expect(
    PaneTabViewController.shouldDispatchGlobalShortcut(
        .focusPane1,
        uiState: uiState,
        managementLayer: managementLayer
    )
)
```

- [ ] **Step 2: Add failing command tests for main ordinals**

Cover:

- `focusPane1` focuses the first active arrangement pane.
- `focusPane3` focuses the third active arrangement pane.
- Out-of-range ordinal no-ops.
- Minimized target dispatches expand before focus.
- Zoomed state no-ops when the target is not the zoomed pane.

Use the existing `PaneTabViewControllerCommandTestSupport` helpers rather than creating new ad hoc fixtures.

- [ ] **Step 3: Allow global routing**

Update `PaneTabViewController.shouldDispatchGlobalShortcut(...)` to return `true` for all new ordinal shortcuts. Keep the existing special-case behavior for `filterSidebar`.

- [ ] **Step 4: Add ordinal index helpers**

Add helpers in `PaneTabViewController` that map command cases to zero-based ordinals:

```swift
private func paneOrdinalIndex(for command: AppCommand) -> Int? {
    AppCommand.focusPaneCommands.firstIndex(of: command)
}

private func drawerPaneOrdinalIndex(for command: AppCommand) -> Int? {
    AppCommand.focusDrawerPaneCommands.firstIndex(of: command)
}
```

- [ ] **Step 5: Implement main-pane resolution**

Resolution contract:

```text
active tab missing                  -> no-op
ordinal index out of range          -> no-op
tab.zoomedPaneId != nil and target
  is not zoomed pane                -> no-op
target minimized                    -> dispatch expandPane, then focus
target not minimized                -> focus
```

Use existing focus trigger:

```swift
handlePaneFocusTrigger(.command(.focusPane(tabId: tab.id, paneId: targetPaneId)))
```

- [ ] **Step 6: Wire execution and availability**

In `handlePaneFocusCommand(_:)`, handle `focusPane1...focusPane9` before returning false. In `canExecute(_:)`, return true only when resolution finds an executable target under the current zoom/minimized rules.

- [ ] **Step 7: Run pane command tests**

Run:

```bash
swift test --build-path ".build-agent-$PPID" --filter "PaneTabViewControllerCommandTests|PaneTabViewControllerGlobalShortcutRoutingTests"
```

Expected: pass.

## Task 3: Drawer Pane Ordinal Focus

**Files:**

- Modify: `Sources/AgentStudio/App/Panes/PaneTabViewController.swift`
- Modify: `Tests/AgentStudioTests/App/PaneTabViewControllerDrawerCommandTests.swift`

- [ ] **Step 1: Add failing drawer ordinal tests**

Cover:

- Drawer ordinal order uses `drawer.layout.paneIds`.
- Top row panes are numbered before bottom row panes.
- Minimized drawer panes count and expand before focus.
- Collapsed drawer expands before focus.
- Out-of-range ordinal no-ops.
- If focus is already in a drawer, ordinals target that drawer's parent.
- If focus is in a main pane, ordinals target that active main pane's drawer.

- [ ] **Step 2: Implement drawer parent resolution**

Resolution contract:

```text
workspace focus owner is drawerPane/emptyDrawer -> use that parentPaneId
otherwise active main pane exists               -> use active main pane id
otherwise                                       -> no-op
```

Use the current `workspaceFocusOwner` / normalized navigation scope helpers already in `PaneTabViewController`; do not introduce a second focus-owner model.

- [ ] **Step 3: Resolve drawer target from row-major layout order**

Use:

```swift
let orderedDrawerPaneIds = drawer.layout.paneIds
```

Do not use:

```swift
drawer.paneIds
visibleDrawerPaneIds(for:)
```

- [ ] **Step 4: Sequence expand and focus**

If the drawer is collapsed, dispatch:

```swift
dispatchAction(.toggleDrawer(paneId: parentPaneId))
```

If the target drawer pane is minimized, dispatch:

```swift
dispatchAction(.expandDrawerPane(parentPaneId: parentPaneId, drawerPaneId: targetDrawerPaneId))
```

Then focus with:

```swift
handlePaneFocusTrigger(
    .drawer(.selectPane(parentPaneId: parentPaneId, drawerPaneId: targetDrawerPaneId))
)
```

- [ ] **Step 5: Wire execution and availability**

Handle `focusDrawerPane1...focusDrawerPane9` in `handlePaneFocusCommand(_:)` or an adjacent drawer-command branch. `canExecute(_:)` should be true only when a parent drawer exists and the ordinal resolves in `drawer.layout.paneIds`.

- [ ] **Step 6: Run drawer command tests**

Run:

```bash
swift test --build-path ".build-agent-$PPID" --filter "PaneTabViewControllerDrawerCommandTests"
```

Expected: pass.

## Task 4: Badge Model And Shared View

**Files:**

- Create: `Sources/AgentStudio/Core/Views/Panes/PaneOrdinalBadge.swift`
- Modify: `Sources/AgentStudio/Core/Views/Panes/FlatPaneStripContent.swift`
- Modify: `Sources/AgentStudio/Core/Views/Panes/PaneLeafContainer.swift`
- Modify: `Sources/AgentStudio/Core/Views/Panes/CollapsedPaneBar.swift`
- Modify: `Sources/AgentStudio/Core/Views/Drawer/DrawerPanel.swift`
- Test: focused pure-helper tests if ordinal maps are extracted

- [ ] **Step 1: Extract ordinal maps before rendering**

Main pane badge map:

```swift
let paneOrdinalById = Dictionary(
    uniqueKeysWithValues: layout.paneIds.enumerated().map { index, paneId in
        (paneId, index + 1)
    }
)
```

Drawer badge map must be drawer-wide, not per-row:

```swift
let drawerOrdinalById = Dictionary(
    uniqueKeysWithValues: layout.paneIds.enumerated().map { index, paneId in
        (paneId, index + 1)
    }
)
```

Pass the already-computed ordinal into row rendering so top and bottom rows share one numbering sequence.

- [ ] **Step 2: Create the badge view**

Create a small reusable badge. Keep it non-interactive:

```swift
struct PaneOrdinalBadge: View {
    let ordinal: Int

    var body: some View {
        Text("\(ordinal)")
            .font(.system(size: AppStyles.General.Typography.textXs, weight: .semibold))
            .foregroundStyle(.primary)
            .frame(width: 16, height: 16)
            .background(
                RoundedRectangle(cornerRadius: AppStyles.General.CornerRadius.badge)
                    .fill(Color.primary.opacity(0.06))
            )
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
```

If `AppStyles.General.CornerRadius.badge` does not exist, use the closest existing compact badge token rather than adding a new style token for this ticket.

- [ ] **Step 3: Render main expanded pane badges**

Thread `ordinal: Int?` through `FlatPaneStripContent` into `PaneSegmentSlotView` and `PaneLeafContainer`. Overlay near the same top-left area shown in the annotated screenshot, but ensure it does not overlap management-layer minimize/close controls.

- [ ] **Step 4: Render minimized pane badges**

Add the badge to `CollapsedPaneBar`. The minimized/collapsed bar must still show the same ordinal as the expanded pane would.

- [ ] **Step 5: Render drawer pane badges**

In `DrawerPanel`, compute one drawer-wide ordinal map from `DrawerGridLayout.paneIds` and pass row-specific ordinals into each `FlatPaneStripContent` call. Do not let each row start at 1.

- [ ] **Step 6: Verify visual behavior manually before full app verification**

Run the narrowest view/unit tests available for the touched view helpers. If no suitable view tests exist, rely on the Peekaboo task below.

## Task 5: Full Verification

**Files:**

- No additional source files expected.

- [ ] **Step 1: Run focused tests**

Run:

```bash
swift test --build-path ".build-agent-$PPID" --filter "ShortcutCatalogTests|CommandSpecContractTests|PaneTabViewControllerGlobalShortcutRoutingTests|PaneTabViewControllerCommandTests|PaneTabViewControllerDrawerCommandTests"
```

Expected: pass.

- [ ] **Step 2: Run full test suite**

Run:

```bash
mise run test
```

Expected: pass with zero failures.

- [ ] **Step 3: Run lint**

Run:

```bash
mise run lint
```

Expected: pass with zero errors.

- [ ] **Step 4: Build and launch a debug app for visual verification**

Run:

```bash
BUILD_PATH=".build-agent-$PPID"
swift build --build-path "$BUILD_PATH"
"$BUILD_PATH/debug/AgentStudio" &
APP_PID=$!
peekaboo see --app "PID:$APP_PID" --json
```

Expected: app launches and Peekaboo returns a screenshot/state payload.

- [ ] **Step 5: Verify badge states with Peekaboo**

Capture at least these states:

- main split with two or more panes
- a minimized main pane
- an expanded drawer with a top row only
- an expanded drawer with top and bottom rows
- a minimized drawer pane
- a narrow pane where the badge could overlap controls

Expected: badges are visible, stable, non-overlapping, and match the shortcut ordinal model.

## Definition Of Done

- [ ] Linear ticket LUNA-373 points at this plan.
- [ ] All ordinal shortcuts decode in `.global` and `.terminalAppOwned`.
- [ ] `Cmd+Shift+1...9` focuses main panes by active arrangement layout order.
- [ ] `Cmd+Shift+Option+1...9` focuses drawer panes by `DrawerGridLayout.paneIds`.
- [ ] Minimized main and drawer panes expand before focus.
- [ ] Zoom behavior matches the no-implicit-unzoom contract.
- [ ] Badges render for expanded and minimized main panes.
- [ ] Badges render for drawer panes using drawer-wide row-major numbering.
- [ ] Focused tests pass.
- [ ] `mise run test` passes.
- [ ] `mise run lint` passes.
- [ ] Peekaboo verification captures the required UI states.
