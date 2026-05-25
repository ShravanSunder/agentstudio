# Navigation Arrangement Scrollback Shortcuts Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rebind Agent Studio navigation, arrangement, and terminal scrollback shortcuts to the agreed semantic lanes while guaranteeing Ghostty never receives overridden host shortcuts such as `⌘K`.

**Architecture:** Keep command identity, shortcut binding, command-bar metadata, validation, and runtime execution in the existing command pipeline. Use `AppShortcut` only for actual shortcut bindings; keep command cases such as tab ordinal selection and drawer ordinal focus only as command identities when they no longer have shortcuts. Terminal shortcuts remain `.terminalAppOwned` and dispatch through `AppShortcut -> AppCommand -> PaneActionCommand -> RuntimeCommand -> TerminalRuntime -> SurfaceManager -> ghostty_surface_binding_action`.

**Tech Stack:** Swift 6.2, AppKit key equivalents, SwiftUI popovers, AtomRegistry, Swift Testing, GhosttyKit binding actions.

---

## Shortcut Contract

Implement this exact map:

| Area | Action | Shortcut | Notes |
| --- | --- | --- | --- |
| Tabs | Previous tab | `⌘J` | Replaces current `⌘⌥J`. |
| Tabs | Next tab | `⌘L` | Replaces current `⌘⌥L`. |
| Tabs | Direct tab select | none | Remove `⌘1..9` shortcut binding. Keep `AppCommand.selectTab1...9` only as command identities if existing command-target flows still need them. |
| Panes | Focus pane 1..9 | `⌘1..9` | Replaces current `⌘⇧1..9`. Applies in global and terminal-app-owned contexts. |
| Panes / drawers | Move spatial focus | `⌥I/J/K/L` | Existing scope-aware path remains: drawer movement uses the same keys when drawer owns focus. |
| Drawers | Direct drawer pane focus | none | Remove `⌘⇧⌥1..9` shortcut bindings. Keep `AppCommand.focusDrawerPane1...9` if command bar/controller code still references command identities. |
| Arrangements | Show arrangement surface | `⌘⌥I` | Replaces current cycle arrangement shortcut behavior. |
| Arrangements | Previous arrangement | `⌘⌥J` | New command, current active tab only. |
| Arrangements | Next arrangement | `⌘⌥L` | New command, current active tab only. |
| Terminal | Scroll to bottom | `⌘⇧K` | Replaces current `⌘⌥K`. |
| Terminal | Page up | `⌘⇧I` | Terminal-owned shortcut, Ghostty `scroll_page_up`. |
| Terminal | Previous prompt | `⌘⇧J` | New terminal-owned shortcut, Ghostty `jump_to_prompt:-1`. |
| Terminal | Next prompt | `⌘⇧L` | New terminal-owned shortcut, Ghostty `jump_to_prompt:1`. |
| Notifications | Inbox sidebar | `⌘U` | Shows inbox notifications. |
| Notifications | Pane inbox | `⌘⇧U` | Shows notifications scoped to the active pane/drawer family. |
| Terminal | Clear scrollback | none | No direct shortcut. |
| Terminal host override | `⌘K` | swallowed | Agent Studio must consume it so Ghostty clear scrollback never fires. |

Tradeoffs to keep visible during implementation:

- `⌘⌥I` intentionally changes from "cycle to next arrangement" to "show the arrangement surface". The direct next-arrangement action moves to `⌘⌥L`.
- `⌘1...9` intentionally changes from tab selection to pane focus in the normal workspace surface. While the arrangement panel is open, that transient surface remaps `⌘1...9` to `selectTab1...9` so tab ordinal selection remains available without closing the panel.
- `⌥I/J/K/L` are not global app shortcuts. They are pane/drawer surface-owned keys. When the active keyboard owner is the pane chain and no text/transient surface owns input, Agent Studio consumes all four keys. If there is no valid movement target, the command is a no-op but still returns handled so Ghostty does not receive Alt/Meta input.

## Copy Since Last Prompt Scope

`Copy Since Last Prompt` is useful, but it is not part of this shortcut implementation. Evidence:

- `vendor/ghostty/include/ghostty.h` exposes `ghostty_surface_read_text(surface, ghostty_selection_s, ghostty_text_s*)`, which reads caller-supplied coordinate ranges.
- Ghostty internals have prompt iterators and semantic prompt data in `vendor/ghostty/src/terminal/PageList.zig`, but no current public C API exposes "last prompt row to bottom" as a binding action or text range.
- The existing Agent Studio wrapper in `Sources/AgentStudio/Features/Terminal/Hosting/TerminalSurfaceActionPerforming.swift` only wraps binding actions such as `scroll_to_bottom`, `start_search`, and `navigate_search:*`.
- Prompt navigation and any later prompt-range copy depend on shell integration emitting OSC 133 semantic prompt markers. Without those markers, `jump_to_prompt:<delta>` has no prompt anchors to navigate.

Follow-up design should add a dedicated Ghostty embedder API or an Agent Studio prompt-range reader before exposing `Copy Since Last Prompt` in the command bar.

## File Structure

### Command and shortcut model

- Modify: `Sources/AgentStudio/App/Commands/AppCommand.swift`
  - Add `previousArrangement`, `nextArrangement`, `jumpToPreviousPrompt`, `jumpToNextPrompt`.
  - Keep `selectTab1...9` and `focusDrawerPane1...9` as command identities.
- Modify: `Sources/AgentStudio/App/Commands/AppShortcut.swift`
  - Add `previousArrangement`, `nextArrangement`, `jumpToPreviousPrompt`, `jumpToNextPrompt`.
  - Change `prevTab`, `nextTab`, `focusPane1...9`, and `scrollToBottom` specs.
  - Remove `selectTab1...9` and `focusDrawerPane1...9` from `AppShortcut`.
- Modify: `Sources/AgentStudio/App/Commands/AppCommand+Catalog.swift`
  - Add command metadata for new arrangement and prompt commands.
  - Move terminal scroll/prompt commands into a `Terminal` command-bar group.
- Modify: `Sources/AgentStudio/App/Commands/AppShortcutDispatchPolicy.swift`
  - Update exhaustive switches for removed shortcut cases and new shortcut cases.
  - Keep terminal scroll/prompt commands terminal-owned, not globally dispatched from the main window chain.

### Arrangement surface

- Create: `Sources/AgentStudio/Core/State/MainActor/Atoms/ArrangementPanelPresentationAtom.swift`
  - Own one-shot arrangement panel presentation requests by workspace window and tab.
- Modify: `Sources/AgentStudio/AtomRegistry.swift`
  - Register the new atom.
- Modify: `Sources/AgentStudio/App/Panes/PaneTabViewController.swift`
  - Handle `.switchArrangement` by requesting the arrangement panel.
  - Handle `.previousArrangement` and `.nextArrangement` by switching the active tab arrangement.
- Modify: `Sources/AgentStudio/App/Panes/TabBar/CustomTabBar.swift`
  - Observe the arrangement presentation atom and open the active tab arrangement popover.
- Modify: `Sources/AgentStudio/Core/Views/Panes/CollapsedPaneBar.swift`
  - Observe the same request for minimized-bar arrangement panels.

### Terminal runtime

- Modify: `Sources/AgentStudio/Core/Actions/PaneActionCommand.swift`
  - Add `jumpToPrompt(tabId:paneId:delta:)`.
- Modify: `Sources/AgentStudio/Core/Actions/ActionResolver.swift`
  - Resolve prompt commands against the active terminal pane.
- Modify: `Sources/AgentStudio/Core/Actions/ActionValidator.swift`
  - Validate prompt actions with the same tab/pane containment and terminal-kind check as `scrollToBottom`.
- Modify: `Sources/AgentStudio/Core/RuntimeEventSystem/Contracts/RuntimeCommand.swift`
  - Add `TerminalCommand.jumpToPrompt(delta:)`.
- Modify: `Sources/AgentStudio/App/Coordination/PaneCoordinator+ActionExecution.swift`
  - Dispatch prompt actions to `RuntimeCommand.terminal(.jumpToPrompt(delta:))`.
- Modify: `Sources/AgentStudio/Features/Terminal/Hosting/TerminalSurfaceActionPerforming.swift`
  - Add `TerminalSurfaceAction.jumpToPrompt(Int)`.
- Modify: `Sources/AgentStudio/Features/Terminal/Ghostty/SurfaceManager.swift`
  - Add `jumpToPrompt(delta:forPaneId:)`.
- Modify: `Sources/AgentStudio/Features/Terminal/Runtime/TerminalRuntime.swift`
  - Execute the runtime command through `SurfaceManager`.
- Modify: `Sources/AgentStudio/Features/Terminal/Ghostty/GhosttySurfaceView+Input.swift`
  - Swallow `⌘K`.
  - Swallow any decoded terminal-app-owned host shortcut even when policy or dispatch rejects it.

### Tests

- Modify: `Tests/AgentStudioTests/App/ShortcutCatalogTests.swift`
- Modify: `Tests/AgentStudioTests/App/AppCommandTests.swift`
- Modify: `Tests/AgentStudioTests/App/PaneTabViewControllerCommandTests.swift`
- Modify: `Tests/AgentStudioTests/App/PaneTabViewControllerGlobalShortcutRoutingTests.swift`
- Modify: `Tests/AgentStudioTests/App/TerminalAppOwnedShortcutPolicyTests.swift`
- Modify: `Tests/AgentStudioTests/App/PaneTabViewControllerGlobalShortcutRoutingTests.swift`
- Create: `Tests/AgentStudioTests/Core/State/ArrangementPanelPresentationAtomTests.swift`
- Modify: `Tests/AgentStudioTests/Features/Terminal/Ghostty/GhosttySurfaceShortcutTests.swift`
- Modify: `Tests/AgentStudioTests/Features/Terminal/Hosting/TerminalSurfaceActionTests.swift`
- Modify: `Tests/AgentStudioTests/Features/Terminal/Runtime/TerminalRuntimeTests.swift`
- Modify: `Tests/AgentStudioTests/Core/Actions/ActionResolverTests.swift`
- Modify: `Tests/AgentStudioTests/Features/CommandBar/CommandBarDataSourceTests.swift`

---

### Task 1: Rebind The Shortcut Catalog

**Files:**
- Modify: `Tests/AgentStudioTests/App/ShortcutCatalogTests.swift`
- Modify: `Sources/AgentStudio/App/Commands/AppShortcut.swift`
- Modify: `Sources/AgentStudio/App/Commands/AppShortcutDispatchPolicy.swift`

- [ ] **Step 1: Write failing shortcut decoder tests**

Replace `shortcutDecoder_decodesTabAndArrangementCyclingShortcuts`, `shortcutDecoder_decodesPaneOrdinalShortcuts`, and `shortcutDecoder_decodesScrollToBottomShortcut` in `Tests/AgentStudioTests/App/ShortcutCatalogTests.swift` with:

```swift
@Test
func shortcutDecoder_decodesTabAndArrangementShortcuts() {
    let previousTab = ShortcutDecoder.shortcut(
        for: .init(key: .character(.j), modifiers: [.command]),
        in: .global
    )
    let nextTab = ShortcutDecoder.shortcut(
        for: .init(key: .character(.l), modifiers: [.command]),
        in: .global
    )
    let showArrangements = ShortcutDecoder.shortcut(
        for: .init(key: .character(.i), modifiers: [.command, .option]),
        in: .global
    )
    let previousArrangement = ShortcutDecoder.shortcut(
        for: .init(key: .character(.j), modifiers: [.command, .option]),
        in: .global
    )
    let nextArrangement = ShortcutDecoder.shortcut(
        for: .init(key: .character(.l), modifiers: [.command, .option]),
        in: .global
    )

    #expect(previousTab == .prevTab)
    #expect(nextTab == .nextTab)
    #expect(showArrangements == .showArrangementPanel)
    #expect(previousArrangement == .previousArrangement)
    #expect(nextArrangement == .nextArrangement)
}

@Test
func shortcutDecoder_decodesPaneOrdinalShortcutsAndLeavesTabOrdinalsUnbound() {
    let firstMainPane = ShortcutDecoder.shortcut(
        for: .init(key: .character(.digit1), modifiers: [.command]),
        in: .global
    )
    let ninthMainPaneFromTerminal = ShortcutDecoder.shortcut(
        for: .init(key: .character(.digit9), modifiers: [.command]),
        in: .terminalAppOwned
    )
    let firstTabOrdinal = ShortcutDecoder.shortcut(
        for: .init(key: .character(.digit1), modifiers: [.command, .shift]),
        in: .global
    )
    let firstDrawerOrdinal = ShortcutDecoder.shortcut(
        for: .init(key: .character(.digit1), modifiers: [.command, .shift, .option]),
        in: .global
    )

    #expect(firstMainPane == .focusPane1)
    #expect(ninthMainPaneFromTerminal == .focusPane9)
    #expect(firstTabOrdinal == nil)
    #expect(firstDrawerOrdinal == nil)
}

@Test
func shortcutDecoder_decodesTerminalScrollAndPromptShortcuts() {
    let scrollToBottom = ShortcutDecoder.shortcut(
        for: .init(key: .character(.k), modifiers: [.command, .shift]),
        in: .terminalAppOwned
    )
    let previousPrompt = ShortcutDecoder.shortcut(
        for: .init(key: .character(.j), modifiers: [.command, .shift]),
        in: .terminalAppOwned
    )
    let nextPrompt = ShortcutDecoder.shortcut(
        for: .init(key: .character(.l), modifiers: [.command, .shift]),
        in: .terminalAppOwned
    )
    let ghosttyClearScrollback = ShortcutDecoder.shortcut(
        for: .init(key: .character(.k), modifiers: [.command]),
        in: .terminalAppOwned
    )

    #expect(scrollToBottom == .scrollToBottom)
    #expect(previousPrompt == .jumpToPreviousPrompt)
    #expect(nextPrompt == .jumpToNextPrompt)
    #expect(ghosttyClearScrollback == nil)
}
```

- [ ] **Step 2: Run the focused tests to verify they fail**

Run:

```bash
mise run test -- --filter "ShortcutCatalogTests/shortcutDecoder_decodesTabAndArrangementShortcuts|ShortcutCatalogTests/shortcutDecoder_decodesPaneOrdinalShortcutsAndLeavesTabOrdinalsUnbound|ShortcutCatalogTests/shortcutDecoder_decodesTerminalScrollAndPromptShortcuts"
```

Expected: FAIL because `AppShortcut.showArrangementPanel`, `previousArrangement`, `nextArrangement`, `jumpToPreviousPrompt`, and `jumpToNextPrompt` do not exist, and the old shortcut specs still decode.

- [ ] **Step 3: Change `AppShortcut` cases**

In `Sources/AgentStudio/App/Commands/AppShortcut.swift`, change the enum cases around the current tab/arrangement area to:

```swift
case closeTab
case newTab
case undoCloseTab
case nextTab
case prevTab
case showArrangementPanel
case previousArrangement
case nextArrangement
case addDrawerPane
case toggleDrawer
case scrollToBottom
case jumpToPreviousPrompt
case jumpToNextPrompt
```

Remove these cases from `AppShortcut`:

```swift
case focusDrawerPane1
case focusDrawerPane2
case focusDrawerPane3
case focusDrawerPane4
case focusDrawerPane5
case focusDrawerPane6
case focusDrawerPane7
case focusDrawerPane8
case focusDrawerPane9
case selectTab1
case selectTab2
case selectTab3
case selectTab4
case selectTab5
case selectTab6
case selectTab7
case selectTab8
case selectTab9
```

Keep `AppCommand.selectTab1...9` and `AppCommand.focusDrawerPane1...9`; only remove their shortcut bindings.

Also delete every matching switch arm for removed shortcut cases from `AppShortcut.spec` and `AppShortcut.command`:

- Remove the old `.cycleArrangement` spec arm and command mapping.
- Remove the old `.selectTab1...9` spec arms and command mappings.
- Remove the old `.focusDrawerPane1...9` spec arms and command mappings.

Leaving orphaned switch arms after deleting enum cases will make `AppShortcut.swift` fail to compile.

- [ ] **Step 4: Change shortcut specs**

In `AppShortcut.spec`, replace the affected cases with:

```swift
case .nextTab:
    return .init(
        trigger: .init(key: .character(.l), modifiers: [.command]),
        contexts: [.global, .terminalAppOwned]
    )
case .prevTab:
    return .init(
        trigger: .init(key: .character(.j), modifiers: [.command]),
        contexts: [.global, .terminalAppOwned]
    )
case .showArrangementPanel:
    return .init(
        trigger: .init(key: .character(.i), modifiers: [.command, .option]),
        contexts: [.global, .terminalAppOwned]
    )
case .previousArrangement:
    return .init(
        trigger: .init(key: .character(.j), modifiers: [.command, .option]),
        contexts: [.global, .terminalAppOwned]
    )
case .nextArrangement:
    return .init(
        trigger: .init(key: .character(.l), modifiers: [.command, .option]),
        contexts: [.global, .terminalAppOwned]
    )
```

Change `scrollToBottom` and add prompt specs:

```swift
case .scrollToBottom:
    return .init(
        trigger: .init(key: .character(.k), modifiers: [.command, .shift]),
        contexts: [.terminalAppOwned]
    )
case .jumpToPreviousPrompt:
    return .init(
        trigger: .init(key: .character(.j), modifiers: [.command, .shift]),
        contexts: [.terminalAppOwned]
    )
case .jumpToNextPrompt:
    return .init(
        trigger: .init(key: .character(.l), modifiers: [.command, .shift]),
        contexts: [.terminalAppOwned]
    )
```

Change `focusPaneSpec` by dropping only the `.shift` modifier. The contexts already include `.global` and `.terminalAppOwned` today; keep them unchanged:

```swift
fileprivate static func focusPaneSpec(key: ShortcutCharacterKey) -> AppShortcutSpec {
    .init(
        trigger: .init(key: .character(key), modifiers: [.command]),
        contexts: [.global, .terminalAppOwned]
    )
}
```

Delete `selectTabSpec` and `focusDrawerPaneSpec` if they are no longer referenced.

- [ ] **Step 5: Change shortcut-to-command mapping**

In `AppShortcut.command`, replace the arrangement and prompt mappings:

```swift
case .showArrangementPanel:
    return .switchArrangement
case .previousArrangement:
    return .previousArrangement
case .nextArrangement:
    return .nextArrangement
case .jumpToPreviousPrompt:
    return .jumpToPreviousPrompt
case .jumpToNextPrompt:
    return .jumpToNextPrompt
```

- [ ] **Step 6: Update dispatch policy exhaustive switches**

In `Sources/AgentStudio/App/Commands/AppShortcutDispatchPolicy.swift`:

1. Replace `.cycleArrangement` with `.showArrangementPanel, .previousArrangement, .nextArrangement`.
2. Add `.jumpToPreviousPrompt, .jumpToNextPrompt` anywhere `.scrollToBottom` is explicitly listed.
3. Remove `.selectTab1...9` and `.focusDrawerPane1...9` from every `AppShortcut` switch.

The main-window-chain block should include:

```swift
case .filterSidebar, .scrollToBottom, .jumpToPreviousPrompt, .jumpToNextPrompt:
    return false
```

The allowed main-window shortcut branch should include:

```swift
case .toggleSidebar, .closeTab, .newTab, .undoCloseTab, .nextTab, .prevTab,
    .showArrangementPanel, .previousArrangement, .nextArrangement,
    .addDrawerPane, .toggleDrawer, .openPaneLocationInBookmarkedEditor,
    .openPaneLocationInFinder, .openPaneLocationInEditorMenu, .toggleManagementLayer,
    .showInboxNotifications, .showPaneInboxNotifications, .showWorktreeSidebar,
    .newWindow, .closeWindow, .showCommandBarEverything, .showCommandBarCommands,
    .showCommandBarPanes, .focusPane1, .focusPane2, .focusPane3, .focusPane4,
    .focusPane5, .focusPane6, .focusPane7, .focusPane8, .focusPane9,
    .managementLayerFocusLeft, .managementLayerFocusRight, .managementLayerEnterDrawer,
    .managementLayerExitDrawer, .managementLayerOpenDrawer, .managementLayerCreateTerminal,
    .managementLayerCreateBrowser, .managementLayerExit:
    return true
```

- [ ] **Step 7: Run the focused tests to verify they pass**

Run:

```bash
mise run test -- --filter "ShortcutCatalogTests"
```

Expected: PASS for `ShortcutCatalogTests`.

- [ ] **Step 8: Commit**

```bash
git add Sources/AgentStudio/App/Commands/AppShortcut.swift \
  Sources/AgentStudio/App/Commands/AppShortcutDispatchPolicy.swift \
  Tests/AgentStudioTests/App/ShortcutCatalogTests.swift
git commit -m "feat: rebind navigation shortcut catalog"
```

---

### Task 1B: Consume Pane And Drawer Option Movement Keys

**Files:**
- Modify: `Sources/AgentStudio/App/Panes/PaneTabViewController.swift`
- Modify: `Tests/AgentStudioTests/App/PaneTabViewControllerGlobalShortcutRoutingTests.swift`

- [ ] **Step 1: Write failing no-op consumption test**

Add this test to `Tests/AgentStudioTests/App/PaneTabViewControllerGlobalShortcutRoutingTests.swift` near the existing scope-aware pane shortcut tests:

```swift
@Test("scope-aware pane shortcuts consume impossible pane movement")
func scopeAwarePaneShortcutsConsumeImpossiblePaneMovement() async throws {
    try await withAsyncTestAtomRegistry { atoms in
        let harness = makeHarness()
        defer { try? FileManager.default.removeItem(at: harness.tempDir) }
        configureMainWindowKeyboardOwner(atoms)

        let pane = harness.store.createPane(source: .floating(launchDirectory: nil, title: "Only"))
        let tab = Tab(paneId: pane.id)
        harness.store.appendTab(tab)
        harness.store.setActiveTab(tab.id)
        harness.store.setActivePane(pane.id, inTab: tab.id)
        atoms.workspaceFocusOwner.focusMainPane(pane.id)

        let impossibleMovements: [(String, ShortcutTrigger, UInt16)] = [
            ("i", .init(key: .character(.i), modifiers: [.option]), 34),
            ("j", .init(key: .character(.j), modifiers: [.option]), 38),
            ("k", .init(key: .character(.k), modifiers: [.option]), 40),
            ("l", .init(key: .character(.l), modifiers: [.option]), 37),
        ]

        for (character, _, keyCode) in impossibleMovements {
            let event = try #require(
                makeKeyEvent(
                    modifierFlags: [.option],
                    characters: character,
                    charactersIgnoringModifiers: character,
                    keyCode: keyCode
                )
            )

            #expect(harness.controller.handleAppOwnedKeyEvent(event))
            #expect(harness.store.tab(tab.id)?.activePaneId == pane.id)
        }
    }
}
```

This test encodes the base rule: when a pane owns keyboard interpretation, all `⌥I/J/K/L` triggers are host-owned. Missing neighbors are valid no-ops, not pass-through to Ghostty or text input.

- [ ] **Step 2: Run the failing test**

Run:

```bash
mise run test -- --filter "PaneTabViewControllerGlobalShortcutRoutingTests/scopeAwarePaneShortcutsConsumeImpossiblePaneMovement"
```

Expected: FAIL because the current controller returns `false` when `scopeAwarePaneCommand(for:)` returns `nil` or `canExecute(command)` is false.

- [ ] **Step 3: Add a trigger classifier**

In `Sources/AgentStudio/App/Panes/PaneTabViewController.swift`, add this helper next to `scopeAwarePaneCommand(for:)`:

```swift
private func isScopeAwarePaneTrigger(_ trigger: ShortcutTrigger) -> Bool {
    switch trigger {
    case .init(key: .character(.i), modifiers: [.option]),
        .init(key: .character(.j), modifiers: [.option]),
        .init(key: .character(.k), modifiers: [.option]),
        .init(key: .character(.l), modifiers: [.option]):
        return true
    default:
        return false
    }
}
```

- [ ] **Step 4: Consume no-op movement**

Replace the current scope-aware dispatch block in `handleAppOwnedKeyEvent(_:)`:

```swift
if shouldHandleScopeAwarePaneTrigger(event: event, keyboardOwner: keyboardOwner),
    let command = scopeAwarePaneCommand(for: trigger),
    canExecute(command)
{
    execute(command)
    return true
}
```

with:

```swift
if shouldHandleScopeAwarePaneTrigger(event: event, keyboardOwner: keyboardOwner),
    isScopeAwarePaneTrigger(trigger)
{
    if let command = scopeAwarePaneCommand(for: trigger),
        canExecute(command)
    {
        execute(command)
    }
    return true
}
```

Do not change `shouldHandleScopeAwarePaneTrigger(event:keyboardOwner:)`. Its current guards are important:

- sidebar focus still blocks these keys
- transient surfaces still block these keys through the earlier app-owned route gate
- text responders still receive text input

- [ ] **Step 5: Run scope-aware routing tests**

Run:

```bash
mise run test -- --filter "PaneTabViewControllerGlobalShortcutRoutingTests/scopeAwarePaneShortcuts"
```

Expected: PASS. The existing sidebar/text/transient tests should still return `false`; only pane/drawer-owned no-op movement should return `true`.

- [ ] **Step 6: Commit**

```bash
git add Sources/AgentStudio/App/Panes/PaneTabViewController.swift \
  Tests/AgentStudioTests/App/PaneTabViewControllerGlobalShortcutRoutingTests.swift
git commit -m "fix: consume pane movement option chords"
```

---

### Task 2: Add Command Metadata For Arrangements And Terminal Prompts

**Files:**
- Modify: `Sources/AgentStudio/App/Commands/AppCommand.swift`
- Modify: `Sources/AgentStudio/App/Commands/AppCommand+Catalog.swift`
- Test: `Tests/AgentStudioTests/App/AppCommandTests.swift`

- [ ] **Step 1: Write failing command metadata tests**

Add these tests near the existing `test_scrollToBottom_definition_usesPaneCommandGroupAndShortcut` test in `Tests/AgentStudioTests/App/AppCommandTests.swift`:

```swift
@MainActor
@Test
func test_arrangementShortcutDefinitions_useTabGroupAndShortcuts() {
    let show = CommandDispatcher.shared.definition(for: .switchArrangement)
    let previous = CommandDispatcher.shared.definition(for: .previousArrangement)
    let next = CommandDispatcher.shared.definition(for: .nextArrangement)

    #expect(show.command == .switchArrangement)
    #expect(show.shortcut == .showArrangementPanel)
    #expect(show.label == "Show Arrangements")
    #expect(show.commandBarGroupName == "Tab")

    #expect(previous.command == .previousArrangement)
    #expect(previous.shortcut == .previousArrangement)
    #expect(previous.label == "Previous Arrangement")
    #expect(previous.commandBarGroupName == "Tab")

    #expect(next.command == .nextArrangement)
    #expect(next.shortcut == .nextArrangement)
    #expect(next.label == "Next Arrangement")
    #expect(next.commandBarGroupName == "Tab")
}

@MainActor
@Test
func test_terminalScrollAndPromptDefinitions_useTerminalGroupAndShortcuts() {
    let scroll = CommandDispatcher.shared.definition(for: .scrollToBottom)
    let previousPrompt = CommandDispatcher.shared.definition(for: .jumpToPreviousPrompt)
    let nextPrompt = CommandDispatcher.shared.definition(for: .jumpToNextPrompt)

    #expect(scroll.command == .scrollToBottom)
    #expect(scroll.shortcut == .scrollToBottom)
    #expect(scroll.label == "Scroll to Bottom")
    #expect(scroll.commandBarGroupName == "Terminal")
    #expect(scroll.visibleWhen == [.hasActivePane, .paneIsTerminal])

    #expect(previousPrompt.command == .jumpToPreviousPrompt)
    #expect(previousPrompt.shortcut == .jumpToPreviousPrompt)
    #expect(previousPrompt.label == "Previous Prompt")
    #expect(previousPrompt.commandBarGroupName == "Terminal")
    #expect(previousPrompt.visibleWhen == [.hasActivePane, .paneIsTerminal])

    #expect(nextPrompt.command == .jumpToNextPrompt)
    #expect(nextPrompt.shortcut == .jumpToNextPrompt)
    #expect(nextPrompt.label == "Next Prompt")
    #expect(nextPrompt.commandBarGroupName == "Terminal")
    #expect(nextPrompt.visibleWhen == [.hasActivePane, .paneIsTerminal])
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run:

```bash
mise run test -- --filter "AppCommandTests/test_arrangementShortcutDefinitions_useTabGroupAndShortcuts|AppCommandTests/test_terminalScrollAndPromptDefinitions_useTerminalGroupAndShortcuts"
```

Expected: FAIL because the new `AppCommand` cases do not exist and `scrollToBottom` is still grouped under `Pane`.

- [ ] **Step 3: Add AppCommand cases**

In `Sources/AgentStudio/App/Commands/AppCommand.swift`, change the arrangement and pane command region to include:

```swift
case scrollToBottom
case jumpToPreviousPrompt
case jumpToNextPrompt
```

and:

```swift
case switchArrangement
case previousArrangement
case nextArrangement
case cycleArrangement
case saveArrangement
case deleteArrangement
case renameArrangement
```

Keep `cycleArrangement` for command identity compatibility until no callers remain. It should not have a direct shortcut after Task 1.

- [ ] **Step 4: Add Terminal command group priority**

In `Sources/AgentStudio/App/Commands/AppCommand+Catalog.swift`, change the private `CommandBarGroupPriority` to include terminal before pane:

```swift
private enum CommandBarGroupPriority {
    static let terminal = 0
    static let pane = 1
    static let focus = 2
    static let tab = 3
    static let repo = 4
    static let window = 5
    static let webview = 6
    static let auth = 7
    static let miscellaneous = 8
}
```

- [ ] **Step 5: Update arrangement definitions**

Replace the arrangement section in `AppCommand+Catalog.swift` with:

```swift
case .switchArrangement:
    return arrangementDefinition(
        shortcut: .showArrangementPanel,
        label: "Show Arrangements",
        icon: .system(.rectangle3Group),
        helpText: "Show arrangements for the active tab"
    )
case .previousArrangement:
    return CommandSpec(
        command: self,
        shortcut: .previousArrangement,
        label: "Previous Arrangement",
        icon: .system(.chevronLeft),
        helpText: "Switch the active tab to the previous arrangement",
        visibleWhen: [.hasActiveTab, .hasArrangements],
        commandBarGroupName: "Tab",
        commandBarGroupPriority: CommandBarGroupPriority.tab
    )
case .nextArrangement:
    return CommandSpec(
        command: self,
        shortcut: .nextArrangement,
        label: "Next Arrangement",
        icon: .system(.chevronRight),
        helpText: "Switch the active tab to the next arrangement",
        visibleWhen: [.hasActiveTab, .hasArrangements],
        commandBarGroupName: "Tab",
        commandBarGroupPriority: CommandBarGroupPriority.tab
    )
case .cycleArrangement:
    return CommandSpec(
        command: self,
        label: "Cycle Arrangement",
        icon: .system(.rectangle3Group),
        helpText: "Switch to the next arrangement in the active tab",
        visibleWhen: [.hasActiveTab, .hasArrangements],
        commandBarGroupName: "Tab",
        commandBarGroupPriority: CommandBarGroupPriority.tab,
        isHiddenInCommandBar: true
    )
```

`cycleArrangement` is intentionally retained as a hidden compatibility command only. It must not appear beside `Previous Arrangement` and `Next Arrangement` in the command bar because its behavior duplicates `nextArrangement`.

If `arrangementDefinition` does not currently accept a `shortcut:` parameter, update its helper signature in the same file to:

```swift
private func arrangementDefinition(
    shortcut: AppShortcut? = nil,
    label: String,
    icon: CommandIcon,
    helpText: String
) -> CommandSpec {
    CommandSpec(
        command: self,
        shortcut: shortcut,
        label: label,
        icon: icon,
        helpText: helpText,
        appliesTo: [.tab],
        visibleWhen: [.hasActiveTab, .hasArrangements],
        commandBarGroupName: "Tab",
        commandBarGroupPriority: CommandBarGroupPriority.tab
    )
}
```

- [ ] **Step 6: Update terminal definitions**

Replace the `scrollToBottom` definition with:

```swift
case .scrollToBottom:
    return CommandSpec(
        command: self,
        shortcut: .scrollToBottom,
        label: "Scroll to Bottom",
        icon: .system(.arrowDownToLine),
        helpText: "Scroll the active terminal pane to the bottom",
        appliesTo: [.pane],
        visibleWhen: [.hasActivePane, .paneIsTerminal],
        commandBarGroupName: "Terminal",
        commandBarGroupPriority: CommandBarGroupPriority.terminal
    )
case .jumpToPreviousPrompt:
    return CommandSpec(
        command: self,
        shortcut: .jumpToPreviousPrompt,
        label: "Previous Prompt",
        icon: .system(.chevronUp),
        helpText: "Jump to the previous shell prompt in terminal scrollback",
        appliesTo: [.pane],
        visibleWhen: [.hasActivePane, .paneIsTerminal],
        commandBarGroupName: "Terminal",
        commandBarGroupPriority: CommandBarGroupPriority.terminal
    )
case .jumpToNextPrompt:
    return CommandSpec(
        command: self,
        shortcut: .jumpToNextPrompt,
        label: "Next Prompt",
        icon: .system(.chevronDown),
        helpText: "Jump to the next shell prompt in terminal scrollback",
        appliesTo: [.pane],
        visibleWhen: [.hasActivePane, .paneIsTerminal],
        commandBarGroupName: "Terminal",
        commandBarGroupPriority: CommandBarGroupPriority.terminal
    )
```

- [ ] **Step 7: Run focused tests**

Run:

```bash
mise run test -- --filter "AppCommandTests/test_arrangementShortcutDefinitions_useTabGroupAndShortcuts|AppCommandTests/test_terminalScrollAndPromptDefinitions_useTerminalGroupAndShortcuts"
```

Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add Sources/AgentStudio/App/Commands/AppCommand.swift \
  Sources/AgentStudio/App/Commands/AppCommand+Catalog.swift \
  Tests/AgentStudioTests/App/AppCommandTests.swift
git commit -m "feat: add arrangement and terminal shortcut metadata"
```

---

### Task 3: Add Arrangement Panel Presentation State

**Files:**
- Create: `Sources/AgentStudio/Core/State/MainActor/Atoms/ArrangementPanelPresentationAtom.swift`
- Modify: `Sources/AgentStudio/AtomRegistry.swift`
- Test: `Tests/AgentStudioTests/Core/State/ArrangementPanelPresentationAtomTests.swift`

- [ ] **Step 1: Write failing atom tests**

Create `Tests/AgentStudioTests/Core/State/ArrangementPanelPresentationAtomTests.swift`:

```swift
import Foundation
import Testing

@testable import AgentStudio

@Suite("ArrangementPanelPresentationAtom")
@MainActor
struct ArrangementPanelPresentationAtomTests {
    @Test("present creates one-shot request scoped to window and tab")
    func presentCreatesOneShotRequest() {
        let atom = ArrangementPanelPresentationAtom()
        let windowId = UUID()
        let tabId = UUID()

        let request = atom.present(tabId: tabId, workspaceWindowId: windowId)

        #expect(atom.pendingRequest?.id == request.id)
        #expect(atom.pendingRequest?.tabId == tabId)
        #expect(atom.pendingRequest?.workspaceWindowId == windowId)
    }

    @Test("consume only clears matching request")
    func consumeOnlyClearsMatchingRequest() {
        let atom = ArrangementPanelPresentationAtom()
        let request = atom.present(tabId: UUID(), workspaceWindowId: UUID())

        atom.consume(ArrangementPanelPresentationRequest(tabId: UUID(), workspaceWindowId: UUID()))
        #expect(atom.pendingRequest?.id == request.id)

        atom.consume(request)
        #expect(atom.pendingRequest == nil)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
mise run test -- --filter "ArrangementPanelPresentationAtomTests"
```

Expected: FAIL because the atom type does not exist.

- [ ] **Step 3: Create the atom**

Create `Sources/AgentStudio/Core/State/MainActor/Atoms/ArrangementPanelPresentationAtom.swift`:

```swift
import Foundation
import Observation

struct ArrangementPanelPresentationRequest: Equatable, Identifiable, Sendable {
    let id: UUID
    let tabId: UUID
    let workspaceWindowId: UUID?

    init(id: UUID = UUID(), tabId: UUID, workspaceWindowId: UUID?) {
        self.id = id
        self.tabId = tabId
        self.workspaceWindowId = workspaceWindowId
    }
}

@MainActor
@Observable
final class ArrangementPanelPresentationAtom {
    private(set) var pendingRequest: ArrangementPanelPresentationRequest?

    @discardableResult
    func present(tabId: UUID, workspaceWindowId: UUID?) -> ArrangementPanelPresentationRequest {
        let request = ArrangementPanelPresentationRequest(
            tabId: tabId,
            workspaceWindowId: workspaceWindowId
        )
        pendingRequest = request
        return request
    }

    func consume(_ request: ArrangementPanelPresentationRequest) {
        guard pendingRequest?.id == request.id else { return }
        pendingRequest = nil
    }
}
```

- [ ] **Step 4: Register atom**

In `Sources/AgentStudio/AtomRegistry.swift`, add a stored property:

```swift
let arrangementPanelPresentation: ArrangementPanelPresentationAtom
```

Add an initializer parameter after `paneInboxPresentationState`:

```swift
arrangementPanelPresentation: ArrangementPanelPresentationAtom = .init(),
```

Assign it in `init`:

```swift
self.arrangementPanelPresentation = arrangementPanelPresentation
```

- [ ] **Step 5: Run test to verify it passes**

Run:

```bash
mise run test -- --filter "ArrangementPanelPresentationAtomTests"
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources/AgentStudio/Core/State/MainActor/Atoms/ArrangementPanelPresentationAtom.swift \
  Sources/AgentStudio/AtomRegistry.swift \
  Tests/AgentStudioTests/Core/State/ArrangementPanelPresentationAtomTests.swift
git commit -m "feat: add arrangement panel presentation atom"
```

---

### Task 4: Wire Arrangement Commands Through PaneTabViewController And Tab Bars

**Files:**
- Modify: `Sources/AgentStudio/App/Panes/PaneTabViewController.swift`
- Modify: `Sources/AgentStudio/App/Panes/TabBar/CustomTabBar.swift`
- Modify: `Sources/AgentStudio/Core/Views/Panes/CollapsedPaneBar.swift`
- Modify: `Tests/AgentStudioTests/App/PaneTabViewControllerCommandTestSupport.swift`
- Test: `Tests/AgentStudioTests/App/PaneTabViewControllerCommandTests.swift`

- [ ] **Step 1: Write failing controller tests**

Add tests near the existing arrangement or focus tests in `Tests/AgentStudioTests/App/PaneTabViewControllerCommandTests.swift`:

```swift
@Test("switchArrangement requests arrangement panel for active tab")
func executeSwitchArrangement_requestsArrangementPanel() throws {
    let presentation = ArrangementPanelPresentationAtom()
    let harness = makeHarness(arrangementPanelPresentation: presentation)
    defer { try? FileManager.default.removeItem(at: harness.tempDir) }
    let (tab, _) = try makeOrdinalTab(in: harness, paneCount: 2)
    harness.store.setActiveTab(tab.id)

    harness.controller.execute(.switchArrangement)

    #expect(presentation.pendingRequest?.tabId == tab.id)
}

@Test("previous and next arrangement switch active tab arrangement")
func executePreviousAndNextArrangement_switchesCurrentTabArrangement() throws {
    let harness = makeHarness()
    defer { try? FileManager.default.removeItem(at: harness.tempDir) }
    let (tab, _) = try makeOrdinalTab(in: harness, paneCount: 2)
    let secondArrangementId = try #require(harness.store.tab(tab.id)?.arrangements.last?.id)
    harness.store.setActiveTab(tab.id)

    harness.controller.execute(.nextArrangement)
    #expect(harness.store.tab(tab.id)?.activeArrangementId == secondArrangementId)

    harness.controller.execute(.previousArrangement)
    #expect(harness.store.tab(tab.id)?.activeArrangementId == tab.defaultArrangement.id)
}
```

If `makeHarness` does not accept `arrangementPanelPresentation`, update the test harness initializer in that file to pass the atom into `PaneTabViewController`.

- [ ] **Step 2: Run tests to verify failure**

Run:

```bash
mise run test -- --filter "PaneTabViewControllerCommandTests/executeSwitchArrangement_requestsArrangementPanel|PaneTabViewControllerCommandTests/executePreviousAndNextArrangement_switchesCurrentTabArrangement"
```

Expected: FAIL because `PaneTabViewController` does not accept the presentation atom and does not handle the new commands.

- [ ] **Step 3: Thread presentation atom through command test support**

In `Tests/AgentStudioTests/App/PaneTabViewControllerCommandTestSupport.swift`, add the atom to `PaneTabViewControllerCommandHarness`:

```swift
let arrangementPanelPresentation: ArrangementPanelPresentationAtom
```

Add an optional parameter to both `makeHarness` and `makePaneTabViewControllerCommandHarness`:

```swift
arrangementPanelPresentation: ArrangementPanelPresentationAtom = ArrangementPanelPresentationAtom(),
```

Forward it from `makeHarness` into `makePaneTabViewControllerCommandHarness`.

Pass it into `PaneTabViewController(...)`:

```swift
arrangementPanelPresentation: arrangementPanelPresentation,
```

Include it in the returned harness value:

```swift
arrangementPanelPresentation: arrangementPanelPresentation,
```

- [ ] **Step 4: Inject presentation atom into `PaneTabViewController`**

In `Sources/AgentStudio/App/Panes/PaneTabViewController.swift`, add a property:

```swift
private let arrangementPanelPresentation: ArrangementPanelPresentationAtom
```

Add an initializer parameter:

```swift
arrangementPanelPresentation: ArrangementPanelPresentationAtom = atom(\.arrangementPanelPresentation),
```

Assign it:

```swift
self.arrangementPanelPresentation = arrangementPanelPresentation
```

- [ ] **Step 5: Handle arrangement commands**

Replace `handleArrangementCommand(_:)` with:

```swift
private func handleArrangementCommand(_ command: AppCommand) -> Bool {
    switch command {
    case .switchArrangement:
        requestArrangementPanel()
        return true
    case .previousArrangement:
        switchActiveArrangement(delta: -1)
        return true
    case .nextArrangement, .cycleArrangement:
        switchActiveArrangement(delta: 1)
        return true
    default:
        return false
    }
}
```

Replace `cycleActiveArrangement()` with:

```swift
private func requestArrangementPanel() {
    guard let activeTabId = store.tabLayoutAtom.activeTabId else { return }
    let workspaceWindowId = atom(\.windowLifecycle).focusedWindowId
        ?? atom(\.windowLifecycle).keyWindowId
    arrangementPanelPresentation.present(
        tabId: activeTabId,
        workspaceWindowId: workspaceWindowId
    )
}

private func switchActiveArrangement(delta: Int) {
    guard
        let activeTabId = store.tabLayoutAtom.activeTabId,
        let tab = store.tabLayoutAtom.tab(activeTabId),
        tab.arrangements.count > 1,
        let activeIndex = tab.arrangements.firstIndex(where: { $0.id == tab.activeArrangementId })
    else {
        return
    }

    let count = tab.arrangements.count
    let nextIndex = (activeIndex + delta + count) % count
    let arrangement = tab.arrangements[nextIndex]
    dispatchAction(.switchArrangement(tabId: tab.id, arrangementId: arrangement.id))
}
```

Update `canExecute(_:)` around the arrangement cases:

```swift
case .switchArrangement:
    return store.tabLayoutAtom.activeTabId != nil
case .previousArrangement, .nextArrangement, .cycleArrangement:
    guard
        let activeTabId = store.tabLayoutAtom.activeTabId,
        let tab = store.tabLayoutAtom.tab(activeTabId)
    else {
        return false
    }
    return tab.arrangements.count > 1
```

- [ ] **Step 6: Observe requests in `CustomTabBar`**

In `TabBarArrangementButton`, add:

```swift
private var presentationAtom: ArrangementPanelPresentationAtom {
    atom(\.arrangementPanelPresentation)
}
```

Add this modifier after the existing `.onChange(of: adapter.activeTabId)`:

```swift
.onChange(of: presentationAtom.pendingRequest?.id) { _, _ in
    openPopoverIfRequestedForActiveTab()
}
```

Add:

```swift
private func openPopoverIfRequestedForActiveTab() {
    guard let request = presentationAtom.pendingRequest else { return }
    guard request.tabId == activeTab?.id else { return }
    isPanelPresented = true
    presentationAtom.consume(request)
}
```

- [ ] **Step 7: Observe requests in `CollapsedPaneBar`**

In `CollapsedPaneBar`, add a computed atom accessor:

```swift
private var arrangementPanelPresentation: ArrangementPanelPresentationAtom {
    atom(\.arrangementPanelPresentation)
}
```

Add this modifier to the `arrangementButton` popover chain:

```swift
.onChange(of: arrangementPanelPresentation.pendingRequest?.id) { _, _ in
    openArrangementPanelIfRequested()
}
```

Add:

```swift
private func openArrangementPanelIfRequested() {
    guard let request = arrangementPanelPresentation.pendingRequest else { return }
    guard request.tabId == tabId else { return }
    isArrangementPanelPresented = true
    arrangementPanelPresentation.consume(request)
}
```

- [ ] **Step 8: Run focused tests**

Run:

```bash
mise run test -- --filter "PaneTabViewControllerCommandTests/executeSwitchArrangement_requestsArrangementPanel|PaneTabViewControllerCommandTests/executePreviousAndNextArrangement_switchesCurrentTabArrangement"
```

Expected: PASS.

- [ ] **Step 9: Commit**

```bash
git add Sources/AgentStudio/App/Panes/PaneTabViewController.swift \
  Sources/AgentStudio/App/Panes/TabBar/CustomTabBar.swift \
  Sources/AgentStudio/Core/Views/Panes/CollapsedPaneBar.swift \
  Tests/AgentStudioTests/App/PaneTabViewControllerCommandTestSupport.swift \
  Tests/AgentStudioTests/App/PaneTabViewControllerCommandTests.swift
git commit -m "feat: route arrangement shortcuts to panel and selection"
```

---

### Task 5: Add Terminal Prompt Runtime Commands

**Files:**
- Modify: `Sources/AgentStudio/Core/Actions/PaneActionCommand.swift`
- Modify: `Sources/AgentStudio/Core/Actions/ActionResolver.swift`
- Modify: `Sources/AgentStudio/Core/Actions/ActionValidator.swift`
- Modify: `Sources/AgentStudio/Core/RuntimeEventSystem/Contracts/RuntimeCommand.swift`
- Modify: `Sources/AgentStudio/App/Coordination/PaneCoordinator+ActionExecution.swift`
- Modify: `Sources/AgentStudio/Features/Terminal/Hosting/TerminalSurfaceActionPerforming.swift`
- Modify: `Sources/AgentStudio/Features/Terminal/Ghostty/SurfaceManager.swift`
- Modify: `Sources/AgentStudio/Features/Terminal/Runtime/TerminalRuntime.swift`
- Test: `Tests/AgentStudioTests/Features/Terminal/Hosting/TerminalSurfaceActionTests.swift`
- Test: `Tests/AgentStudioTests/Features/Terminal/Runtime/TerminalRuntimeTests.swift`
- Test: `Tests/AgentStudioTests/Core/Actions/ActionResolverTests.swift`

- [ ] **Step 1: Write failing terminal action serialization test**

Modify `TerminalSurfaceActionTests.bindingActionStringSerializationMatchesGhosttyBindings` to include:

```swift
(.jumpToPrompt(-1), "jump_to_prompt:-1"),
(.jumpToPrompt(1), "jump_to_prompt:1"),
```

- [ ] **Step 2: Write failing runtime missing-surface test**

Add to `Tests/AgentStudioTests/Features/Terminal/Runtime/TerminalRuntimeTests.swift`:

```swift
@Test("jumpToPrompt terminal command fails without surface")
func jumpToPromptTerminalCommandFailsWithoutSurface() async {
    let runtime = TerminalRuntime(
        paneId: PaneId(),
        metadata: PaneMetadata(source: .floating(launchDirectory: nil, title: "Runtime"), title: "Runtime")
    )
    runtime.transitionToReady()

    let commandEnvelope = makeEnvelope(command: .terminal(.jumpToPrompt(delta: -1)), paneId: runtime.paneId)
    let result = await runtime.handleCommand(commandEnvelope)

    #expect(result == .failure(.backendUnavailable(backend: "SurfaceManager")))
}
```

- [ ] **Step 3: Run tests to verify failure**

Run:

```bash
mise run test -- --filter "TerminalSurfaceActionTests|TerminalRuntimeTests/jumpToPromptTerminalCommandFailsWithoutSurface"
```

Expected: FAIL because `jumpToPrompt` cases do not exist.

- [ ] **Step 4: Add action and runtime command cases**

In `TerminalSurfaceActionPerforming.swift`:

```swift
case jumpToPrompt(Int)
```

and:

```swift
case .jumpToPrompt(let delta):
    return "jump_to_prompt:\(delta)"
```

In `RuntimeCommand.swift`:

```swift
case jumpToPrompt(delta: Int)
```

- [ ] **Step 5: Add SurfaceManager method**

In `SurfaceManager.swift` after `scrollToBottom(forPaneId:)`:

```swift
func jumpToPrompt(delta: Int, forPaneId paneId: UUID) -> Result<Void, SurfaceError> {
    guard let surfaceId = surfaceId(forPaneId: paneId) else {
        return .failure(.surfaceNotFound)
    }

    let action = TerminalSurfaceAction.jumpToPrompt(delta).bindingActionString
    let didPerform = withSurface(surfaceId) { surface in
        action.withCString { ptr in
            ghostty_surface_binding_action(surface, ptr, UInt(action.utf8.count))
        }
    }

    switch didPerform {
    case .success(true):
        return .success(())
    case .success(false):
        return .failure(.operationFailed("Ghostty rejected \(action) binding action"))
    case .failure(let error):
        return .failure(error)
    }
}
```

- [ ] **Step 6: Dispatch terminal runtime command**

In `TerminalRuntime.requiredCapability(for:)`, keep prompt jumps aligned with scroll-to-bottom:

```swift
case .scrollToBottom, .jumpToPrompt:
    return .terminalSurface
```

In `TerminalRuntime.dispatchTerminalCommand(_:commandId:)`:

```swift
case .jumpToPrompt(let delta):
    let dispatchResult = SurfaceManager.shared.jumpToPrompt(delta: delta, forPaneId: paneId.uuid)
    return terminalSurfaceActionResult(dispatchResult, command: command)
```

- [ ] **Step 7: Add pane action case and resolver**

In `PaneActionCommand.swift`:

```swift
case jumpToPrompt(tabId: UUID, paneId: UUID, delta: Int)
```

In `ActionResolver.resolve(command:tabs:activeTabId:)` near `.scrollToBottom`:

```swift
case .jumpToPreviousPrompt:
    guard let (tab, paneId) = activeTabAndPane(tabs: tabs, activeTabId: activeTabId)
    else { return nil }
    return .jumpToPrompt(tabId: tab.id, paneId: paneId, delta: -1)
case .jumpToNextPrompt:
    guard let (tab, paneId) = activeTabAndPane(tabs: tabs, activeTabId: activeTabId)
    else { return nil }
    return .jumpToPrompt(tabId: tab.id, paneId: paneId, delta: 1)
```

Add `.jumpToPreviousPrompt, .jumpToNextPrompt` to the command families that resolve through active pane actions.

Also update `ActionResolver.isNonPaneCommand(_:)`:

- Add `.previousArrangement, .nextArrangement` to the `return true` arm with `.switchArrangement, .cycleArrangement, .saveArrangement`.
- Add `.jumpToPreviousPrompt, .jumpToNextPrompt` to the `return false` arm with `.scrollToBottom`.

This switch enumerates every `AppCommand`; adding new command cases without updating it will break compilation.

- [ ] **Step 8: Validate and execute pane action**

In `ActionValidator.swift`, add `.jumpToPrompt` beside `.scrollToBottom`:

```swift
case .scrollToBottom(let tabId, let paneId),
    .jumpToPrompt(let tabId, let paneId, _):
    return validatePaneInTab(tabId: tabId, paneId: paneId, snapshot: snapshot)
```

If the existing validator checks terminal capability separately, mirror the exact `.scrollToBottom` branch and include `.jumpToPrompt`.

In `PaneCoordinator+ActionExecution.swift` near `.scrollToBottom`:

```swift
case .jumpToPrompt(_, let paneId, let delta):
    Task { @MainActor [weak self] in
        guard let self else { return }
        _ = await self.dispatchRuntimeCommand(
            .terminal(.jumpToPrompt(delta: delta)),
            target: .pane(PaneId(uuid: paneId))
        )
    }
```

- [ ] **Step 9: Run focused tests**

Run:

```bash
mise run test -- --filter "TerminalSurfaceActionTests|TerminalRuntimeTests/jumpToPromptTerminalCommandFailsWithoutSurface|ActionResolverTests"
```

Expected: PASS for the new prompt tests and no regression in resolver tests.

- [ ] **Step 10: Commit**

```bash
git add Sources/AgentStudio/Core/Actions/PaneActionCommand.swift \
  Sources/AgentStudio/Core/Actions/ActionResolver.swift \
  Sources/AgentStudio/Core/Actions/ActionValidator.swift \
  Sources/AgentStudio/Core/RuntimeEventSystem/Contracts/RuntimeCommand.swift \
  Sources/AgentStudio/App/Coordination/PaneCoordinator+ActionExecution.swift \
  Sources/AgentStudio/Features/Terminal/Hosting/TerminalSurfaceActionPerforming.swift \
  Sources/AgentStudio/Features/Terminal/Ghostty/SurfaceManager.swift \
  Sources/AgentStudio/Features/Terminal/Runtime/TerminalRuntime.swift \
  Tests/AgentStudioTests/Features/Terminal/Hosting/TerminalSurfaceActionTests.swift \
  Tests/AgentStudioTests/Features/Terminal/Runtime/TerminalRuntimeTests.swift \
  Tests/AgentStudioTests/Core/Actions/ActionResolverTests.swift
git commit -m "feat: add terminal prompt navigation commands"
```

---

### Task 6: Swallow Ghostty Host Overrides

**Files:**
- Modify: `Sources/AgentStudio/Features/Terminal/Ghostty/GhosttySurfaceView+Input.swift`
- Modify: `Tests/AgentStudioTests/Features/Terminal/Ghostty/GhosttySurfaceShortcutTests.swift`

- [ ] **Step 1: Write failing swallow policy tests**

Add to `GhosttySurfaceShortcutTests`:

```swift
@Test
func terminalHostSuppressedTriggers_swallowCmdKClearScrollback() {
    let trigger = ShortcutTrigger(key: .character(.k), modifiers: [.command])

    #expect(Ghostty.SurfaceView.shouldSuppressTerminalHostTrigger(trigger))
}

@Test
func appOwnedTerminalShortcuts_includeScrollAndPromptNavigation() {
    #expect(Ghostty.SurfaceView.appOwnedShortcuts.contains(.scrollToBottom))
    #expect(Ghostty.SurfaceView.appOwnedShortcuts.contains(.jumpToPreviousPrompt))
    #expect(Ghostty.SurfaceView.appOwnedShortcuts.contains(.jumpToNextPrompt))
}
```

- [ ] **Step 2: Run tests to verify failure**

Run:

```bash
mise run test -- --filter "GhosttySurfaceShortcutTests"
```

Expected: FAIL because `shouldSuppressTerminalHostTrigger(_:)` and prompt shortcut cases do not exist.

- [ ] **Step 3: Add suppression helper**

In `GhosttySurfaceView+Input.swift`, add inside `extension Ghostty.SurfaceView` near `appOwnedShortcuts`:

```swift
static let terminalHostSuppressedTriggers: Set<ShortcutTrigger> = [
    .init(key: .character(.k), modifiers: [.command])
]

static func shouldSuppressTerminalHostTrigger(_ trigger: ShortcutTrigger) -> Bool {
    terminalHostSuppressedTriggers.contains(trigger)
}
```

- [ ] **Step 4: Swallow `⌘K` and rejected host-owned shortcuts**

Replace the first decoded-shortcut block in `performKeyEquivalent(with:)` with:

```swift
if let trigger = ShortcutDecoder.decode(event: event) {
    if Self.shouldSuppressTerminalHostTrigger(trigger) {
        return true
    }

    if let shortcut = ShortcutDecoder.shortcut(for: trigger, in: .terminalAppOwned),
        Self.appOwnedShortcuts.contains(shortcut)
    {
        let keyboardContext = KeyboardRoutingContext.current(
            windowLifecycle: atom(\.windowLifecycle),
            managementLayer: atom(\.managementLayer),
            uiState: atom(\.uiState),
            commandBarSurface: atom(\.commandBarSurface),
            transientKeyboardSurface: atom(\.transientKeyboardSurface)
        )
        guard
            AppShortcutDispatchPolicy.shouldDispatchTerminalAppOwnedShortcut(
                shortcut,
                context: keyboardContext
            ),
            CommandDispatcher.shared.canDispatch(shortcut.command)
        else {
            return true
        }
        CommandDispatcher.shared.dispatch(shortcut.command)
        return true
    }
}
```

This is intentional: when Agent Studio declares a terminal host override, Ghostty should not receive it even when the current surface policy blocks dispatch.

- [ ] **Step 5: Run tests**

Run:

```bash
mise run test -- --filter "GhosttySurfaceShortcutTests|TerminalAppOwnedShortcutPolicyTests"
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources/AgentStudio/Features/Terminal/Ghostty/GhosttySurfaceView+Input.swift \
  Tests/AgentStudioTests/Features/Terminal/Ghostty/GhosttySurfaceShortcutTests.swift
git commit -m "fix: swallow ghostty host override shortcuts"
```

---

### Task 7: Update Command Bar Grouping And Routing Tests

**Files:**
- Modify: `Tests/AgentStudioTests/Features/CommandBar/CommandBarDataSourceTests.swift`
- Modify: `Tests/AgentStudioTests/App/PaneTabViewControllerGlobalShortcutRoutingTests.swift`
- Modify: `Tests/AgentStudioTests/App/TerminalAppOwnedShortcutPolicyTests.swift`

- [ ] **Step 1: Add command bar terminal grouping expectations**

In `CommandBarDataSourceTests`, add a test near the existing scroll-to-bottom item coverage:

```swift
@Test("terminal scroll and prompt commands appear in Terminal group")
func terminalScrollAndPromptCommandsAppearInTerminalGroup() async throws {
    let context = try makeFocusedTerminalCommandBarContext()
    let items = CommandBarDataSource.commandItems(context: context)

    let scroll = try #require(items.first { $0.command == .scrollToBottom })
    let previousPrompt = try #require(items.first { $0.command == .jumpToPreviousPrompt })
    let nextPrompt = try #require(items.first { $0.command == .jumpToNextPrompt })

    #expect(scroll.groupName == "Terminal")
    #expect(previousPrompt.groupName == "Terminal")
    #expect(nextPrompt.groupName == "Terminal")
    #expect(scroll.shortcutTrigger == AppShortcut.scrollToBottom.trigger)
    #expect(previousPrompt.shortcutTrigger == AppShortcut.jumpToPreviousPrompt.trigger)
    #expect(nextPrompt.shortcutTrigger == AppShortcut.jumpToNextPrompt.trigger)
}
```

If the helper in this file names the field `commandBarGroupName` instead of `groupName`, use the actual field already asserted in nearby tests.

- [ ] **Step 2: Update global routing tests**

In `PaneTabViewControllerGlobalShortcutRoutingTests`, update key events that currently use `⌘⌥L` for next tab to use:

```swift
makeKeyEvent(
    modifierFlags: [.command],
    characters: "l",
    charactersIgnoringModifiers: "l",
    keyCode: 37
)
```

Update expectations from:

```swift
#expect(ShortcutDecoder.shortcut(for: trigger, in: .global) == .nextTab)
```

to the same assertion, with the new trigger.

Add a terminal-owned prompt policy assertion:

```swift
@Test("prompt shortcuts are terminal owned only")
func promptShortcutsAreTerminalOwnedOnly() {
    let context = KeyboardRoutingContext(
        stableOwner: .mainWindowChain,
        activeSurface: .stable(.mainWindowChain),
        workspaceWindowId: UUID()
    )

    #expect(!AppShortcutDispatchPolicy.shouldDispatchGlobalShortcut(.jumpToPreviousPrompt, context: context))
    #expect(!AppShortcutDispatchPolicy.shouldDispatchGlobalShortcut(.jumpToNextPrompt, context: context))
    #expect(AppShortcutDispatchPolicy.shouldDispatchTerminalAppOwnedShortcut(.jumpToPreviousPrompt, context: context))
    #expect(AppShortcutDispatchPolicy.shouldDispatchTerminalAppOwnedShortcut(.jumpToNextPrompt, context: context))
}
```

- [ ] **Step 3: Run focused tests**

Run:

```bash
mise run test -- --filter "CommandBarDataSourceTests|PaneTabViewControllerGlobalShortcutRoutingTests|TerminalAppOwnedShortcutPolicyTests"
```

Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add Tests/AgentStudioTests/Features/CommandBar/CommandBarDataSourceTests.swift \
  Tests/AgentStudioTests/App/PaneTabViewControllerGlobalShortcutRoutingTests.swift \
  Tests/AgentStudioTests/App/TerminalAppOwnedShortcutPolicyTests.swift
git commit -m "test: update shortcut routing coverage"
```

---

### Task 8: Update Architecture Docs

**Files:**
- Modify: `docs/architecture/commands_and_shortcuts.md`
- Modify: `docs/superpowers/specs/2026-05-22-keyboard-surface-system.md`

- [ ] **Step 1: Update command shortcut docs**

In `docs/architecture/commands_and_shortcuts.md`, add or update the shortcut table to include:

```markdown
| Command | Shortcut | Owner | Notes |
| --- | --- | --- | --- |
| `prevTab` | `⌘J` | PaneTabViewController | Selects previous tab in the active workspace window. |
| `nextTab` | `⌘L` | PaneTabViewController | Selects next tab in the active workspace window. |
| `focusPane1...9` | `⌘1...9` | PaneTabViewController | Focuses visible pane ordinal in active arrangement. Arrangement panel overrides the same chord to `selectTab1...9`. |
| `switchArrangement` | `⌘⌥I` | PaneTabViewController + arrangement panel presentation atom | Shows the arrangement surface for the active tab. |
| `previousArrangement` | `⌘⌥J` | PaneTabViewController | Selects previous arrangement in current tab. |
| `nextArrangement` | `⌘⌥L` | PaneTabViewController | Selects next arrangement in current tab. |
| `scrollToBottom` | `⌘⇧K` | Terminal runtime | Terminal-owned; dispatches `scroll_to_bottom`. |
| `scrollPageUp` | `⌘⇧I` | Terminal runtime | Terminal-owned; dispatches `scroll_page_up`. |
| `jumpToPreviousPrompt` | `⌘⇧J` | Terminal runtime | Terminal-owned; dispatches `jump_to_prompt:-1`. |
| `jumpToNextPrompt` | `⌘⇧L` | Terminal runtime | Terminal-owned; dispatches `jump_to_prompt:1`. |
| `showInboxNotifications` | `⌘U` | AppDelegate shell | Shows inbox notifications. |
| `showPaneInboxNotifications` | `⌘⇧U` | PaneTabViewController | Shows notifications scoped to the active pane/drawer family. |
| Ghostty clear scrollback | none | GhosttySurfaceView host override | `⌘K` is swallowed and never forwarded to Ghostty. |
```

- [ ] **Step 2: Update keyboard surface spec**

In `docs/superpowers/specs/2026-05-22-keyboard-surface-system.md`, add this terminal host override rule:

```markdown
### Terminal Host Override Rule

When a focused Ghostty surface receives a key chord that Agent Studio owns in
`.terminalAppOwned`, the host consumes that key even if the active keyboard
surface policy blocks dispatch. This prevents blocked or transient surfaces
from accidentally forwarding host-reserved chords into Ghostty. `⌘K` is also
explicitly swallowed so Ghostty clear scrollback never fires from Agent Studio.
```

- [ ] **Step 3: Run docs lint through project lint**

Run:

```bash
mise run lint
```

Expected: PASS with zero lint errors.

- [ ] **Step 4: Commit**

```bash
git add docs/architecture/commands_and_shortcuts.md \
  docs/superpowers/specs/2026-05-22-keyboard-surface-system.md
git commit -m "docs: update keyboard shortcut architecture"
```

---

### Task 9: Final Verification

**Files:**
- No new edits expected.

- [ ] **Step 1: Run formatting**

Run:

```bash
mise run format
```

Expected: exit code 0.

- [ ] **Step 2: Run full tests**

Run:

```bash
mise run test
```

Expected: all Swift Testing suites pass. Record pass/fail counts from output.

- [ ] **Step 3: Run lint**

Run:

```bash
mise run lint
```

Expected: exit code 0, zero swift-format/swiftlint/boundary errors.

- [ ] **Step 4: Inspect final diff**

Run:

```bash
git status --short
git diff --stat
git diff -- Sources/AgentStudio/App/Commands/AppShortcut.swift \
  Sources/AgentStudio/Features/Terminal/Ghostty/GhosttySurfaceView+Input.swift
```

Expected:

- Dirty files are only from this plan.
- `AppShortcut` has no `selectTab1...9` or `focusDrawerPane1...9` shortcut cases.
- `scrollToBottom` is `⌘⇧K`.
- `scrollPageUp` is `⌘⇧I`.
- `jumpToPreviousPrompt` is `⌘⇧J`.
- `jumpToNextPrompt` is `⌘⇧L`.
- `showInboxNotifications` is `⌘U`.
- `showPaneInboxNotifications` is `⌘⇧U`.
- `GhosttySurfaceView` swallows `⌘K`.

- [ ] **Step 5: Commit verification fixes if format changed files**

If `mise run format` changed files:

```bash
git add .
git commit -m "style: format shortcut migration"
```

If no files changed, do not create an empty commit.

---

## Self-Review

### Spec coverage

- `⌘J / ⌘L` tab movement: Task 1 and Task 4.
- `⌘1..9` pane focus: Task 1.
- No drawer ordinal shortcuts: Task 1.
- Drawer movement uses pane movement keys when drawer is active: preserved by the existing scope-aware `⌥I/J/K/L` path; no new shortcut cases are added.
- `⌘⌥I` arrangement surface: Task 1, Task 3, Task 4.
- `⌘⌥J / ⌘⌥L` arrangement previous/next: Task 1, Task 2, Task 4.
- `⌘⇧K` scroll to bottom: Task 1, Task 2, Task 7.
- `⌘⇧J / ⌘⇧L` prompt navigation: Task 1, Task 2, Task 5, Task 7.
- `⌘K` swallowed and Ghostty clear scrollback removed from shortcut access: Task 6.
- Scrollback command-bar organization: Task 2, Task 7, Task 8.
- `Copy Since Last Prompt`: explicitly scoped out with code-grounded reason and follow-up seam.

### Placeholder scan

This plan contains no `TBD`, no `TODO`, no undefined code-only placeholders, and no "similar to Task N" instructions.

### Type consistency

- `AppShortcut.showArrangementPanel` maps to existing `AppCommand.switchArrangement`.
- `AppShortcut.previousArrangement` maps to new `AppCommand.previousArrangement`.
- `AppShortcut.nextArrangement` maps to new `AppCommand.nextArrangement`.
- `AppShortcut.jumpToPreviousPrompt` maps to new `AppCommand.jumpToPreviousPrompt`.
- `AppShortcut.jumpToNextPrompt` maps to new `AppCommand.jumpToNextPrompt`.
- `PaneActionCommand.jumpToPrompt(tabId:paneId:delta:)` maps to `TerminalCommand.jumpToPrompt(delta:)`.
- `TerminalSurfaceAction.jumpToPrompt(Int)` serializes to `jump_to_prompt:<delta>`.
