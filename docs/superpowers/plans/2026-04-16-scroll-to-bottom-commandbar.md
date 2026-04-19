# Scroll To Bottom Command Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a first-class terminal “Scroll to Bottom” command with a real shortcut and command-bar entry, while preserving the existing command/shortcut exhaustiveness protections.

**Architecture:** This command is intentionally modeled as a pane-scoped app command that goes through the existing validated pane-command path: `AppCommand -> WorkspaceCommandResolver -> WorkspaceCommandValidator -> PaneActionCommand -> PaneCoordinator -> RuntimeCommand -> TerminalRuntime -> SurfaceManager`. Even though a lighter direct-runtime route exists, this plan keeps `scrollToBottom` in the validated command plane because the requirement is to “go through validator etc.” The command remains runtime-only in effect, but not ad hoc in routing.

**Tech Stack:** Swift 6 `Testing`, AppKit keyboard shortcuts, `CommandDispatcher`, `WorkspaceCommandResolver`, `WorkspaceCommandValidator`, `PaneCoordinator`, `RuntimeCommand`, Ghostty binding actions.

---

## Shortcut Choice

This plan uses `⌥K`.

Why:
- no existing conflict in [AppShortcut.swift](/Users/shravansunder/Documents/dev/project-dev/agent-studio.fix-scroll/Sources/AgentStudio/App/Commands/AppShortcut.swift)
- avoids the system-arrow-key issues that made `⌘↓` unattractive
- fits terminal-app-owned context
- keeps the shortcut catalog uniqueness checks meaningful

## Exhaustiveness / Conflict Safety

This repo already protects command/shortcut completeness in three layers:

1. `AppCommand` exhaustiveness via `CommandDispatcher`
2. `AppShortcut` exhaustiveness via `ShortcutCatalogTests`
3. bidirectional command/shortcut consistency via `ShortcutCatalogTests`

This plan keeps those protections intact and adds `scrollToBottom` in the same style:
- `AppCommand.allCases`
- `AppShortcut.allCases`
- `CommandSpec.shortcut`
- `shortcutTriggers_areUniqueWithinEachContext`

The implementation must not weaken this system:

```text
Do not add ad hoc conflict checks for scrollToBottom.
Use the existing ShortcutCatalogTests safety net and make the new command/shortcut
participate in it normally.
```

## File Map

| File | Responsibility |
|---|---|
| `Sources/AgentStudio/App/Commands/AppCommand.swift` | Add `scrollToBottom` command definition and command-bar metadata |
| `Sources/AgentStudio/App/Commands/AppShortcut.swift` | Add `scrollToBottom` shortcut mapping (`⌥K`) |
| `Sources/AgentStudio/Core/Actions/PaneActionCommand.swift` | Add validated pane action case |
| `Sources/AgentStudio/Core/Actions/ActionResolver.swift` | Resolve `AppCommand.scrollToBottom` from active tab/pane |
| `Sources/AgentStudio/Core/Actions/ActionValidator.swift` | Validate target tab contains target pane |
| `Sources/AgentStudio/App/Coordination/PaneCoordinator+ActionExecution.swift` | Dispatch runtime terminal command for the validated action |
| `Sources/AgentStudio/Core/RuntimeEventSystem/Contracts/RuntimeCommand.swift` | Add `TerminalCommand.scrollToBottom` |
| `Sources/AgentStudio/Features/Terminal/Runtime/TerminalRuntime.swift` | Dispatch `scrollToBottom` through `SurfaceManager` |
| `Sources/AgentStudio/Features/Terminal/Ghostty/SurfaceManager.swift` | Add `scrollToBottom(forPaneId:)` binding-action wrapper |
| `Sources/AgentStudio/Features/CommandBar/CommandBarDataSource.swift` | Surface the command in the Pane group |
| `Tests/AgentStudioTests/App/AppCommandTests.swift` | Command/dispatcher tests |
| `Tests/AgentStudioTests/App/ShortcutCatalogTests.swift` | Shortcut uniqueness and bidirectional consistency |
| `Tests/AgentStudioTests/Features/Terminal/Runtime/TerminalRuntimeTests.swift` | Runtime command dispatch tests |
| `Tests/AgentStudioTests/Features/Terminal/Hosting/TerminalSurfaceActionTests.swift` | Binding string stability test |
| `Tests/AgentStudioTests/Features/CommandBar/CommandBarDataSourceTests.swift` | Command-bar surfacing test |
| `Tests/AgentStudioTests/Features/CommandBar/CommandBarShortcutRouterTests.swift` | Shortcut resolution test in command bar |

---

### Task 1: Add App Command and Shortcut Surface

**Files:**
- Modify: `Sources/AgentStudio/App/Commands/AppCommand.swift`
- Modify: `Sources/AgentStudio/App/Commands/AppShortcut.swift`
- Test: `Tests/AgentStudioTests/App/AppCommandTests.swift`
- Test: `Tests/AgentStudioTests/App/ShortcutCatalogTests.swift`

- [ ] **Step 1: Write the failing command/shortcut tests**

```swift
@Test
func test_scrollToBottom_definition_usesPaneGroupAndShortcut() {
    let def = CommandDispatcher.shared.definition(for: .scrollToBottom)

    #expect(def.command == .scrollToBottom)
    #expect(def.shortcut == .scrollToBottom)
    #expect(def.label == "Scroll to Bottom")
    #expect(def.commandBarGroupName == "Pane")
    #expect(def.requiresManagementLayer == false)
    #expect(def.visibleWhen == [.hasActivePane])
}

@Test
func test_scrollToBottom_shortcut_isOptionKInTerminalContext() {
    let shortcut = AppShortcut.scrollToBottom

    #expect(shortcut.trigger == .init(key: .character(.k), modifiers: [.option]))
    #expect(shortcut.contexts == [.terminalAppOwned])
}
```

- [ ] **Step 2: Run the failing tests**

Run:

```bash
swift test --build-path .build-agent-scroll-bottom --filter 'AppCommandTests|ShortcutCatalogTests'
```

Expected: FAIL because `scrollToBottom` is not yet present in `AppCommand` / `AppShortcut`.

- [ ] **Step 3: Add the command and shortcut**

In `AppCommand.swift` add the case:

```swift
// Pane commands
case closePane
case extractPaneToTab
case movePaneToTab
case focusPane
case scrollToBottom
case splitRight, splitLeft
```

Add the definition near other pane commands:

```swift
case .scrollToBottom:
    return CommandSpec(
        command: self,
        shortcut: .scrollToBottom,
        label: "Scroll to Bottom",
        icon: "arrow.down.to.line",
        helpText: "Scroll the active terminal pane to the bottom of its scrollback",
        appliesTo: [.pane, .floatingTerminal],
        requiresManagementLayer: false,
        visibleWhen: [.hasActivePane],
        commandBarGroupName: "Pane",
        commandBarGroupPriority: CommandBarGroupPriority.pane
    )
```

In `AppShortcut.swift` add the case:

```swift
case scrollToBottom
```

Add the spec:

```swift
case .scrollToBottom:
    return .init(
        trigger: .init(key: .character(.k), modifiers: [.option]),
        contexts: [.terminalAppOwned]
    )
```

- [ ] **Step 4: Run command + shortcut catalog tests**

Run:

```bash
swift test --build-path .build-agent-scroll-bottom --filter 'AppCommandTests|ShortcutCatalogTests'
```

Expected: PASS, including shortcut uniqueness within `terminalAppOwned`.

- [ ] **Step 4.5: Add an explicit catalog assertion for the new shortcut**

In `ShortcutCatalogTests.swift`, add:

```swift
@Test
func shortcutDecoder_decodesScrollToBottomShortcut() {
    let shortcut = ShortcutDecoder.shortcut(
        for: .init(key: .character(.k), modifiers: [.option]),
        in: .terminalAppOwned
    )

    #expect(shortcut == .scrollToBottom)
}
```

Run again:

```bash
swift test --build-path .build-agent-scroll-bottom --filter 'ShortcutCatalogTests'
```

Expected: PASS, proving the new shortcut is registered and conflict-free within the same context.

- [ ] **Step 5: Commit**

```bash
git add \
  Sources/AgentStudio/App/Commands/AppCommand.swift \
  Sources/AgentStudio/App/Commands/AppShortcut.swift \
  Tests/AgentStudioTests/App/AppCommandTests.swift \
  Tests/AgentStudioTests/App/ShortcutCatalogTests.swift
git commit -m "feat: add scroll-to-bottom command surface

Co-authored-by: Codex <noreply@openai.com>"
```

### Task 2: Add Validated Pane Action and Runtime Command

**Files:**
- Modify: `Sources/AgentStudio/Core/Actions/PaneActionCommand.swift`
- Modify: `Sources/AgentStudio/Core/Actions/ActionResolver.swift`
- Modify: `Sources/AgentStudio/Core/Actions/ActionValidator.swift`
- Modify: `Sources/AgentStudio/Core/RuntimeEventSystem/Contracts/RuntimeCommand.swift`
- Modify: `Sources/AgentStudio/Features/Terminal/Runtime/TerminalRuntime.swift`
- Modify: `Sources/AgentStudio/Features/Terminal/Ghostty/SurfaceManager.swift`
- Test: `Tests/AgentStudioTests/Features/Terminal/Runtime/TerminalRuntimeTests.swift`
- Test: `Tests/AgentStudioTests/Features/Terminal/Hosting/TerminalSurfaceActionTests.swift`

- [ ] **Step 1: Write the failing action/runtime tests**

```swift
@Test
func resolve_scrollToBottom_activePane_resolvesToValidatedPaneAction() {
    let action = WorkspaceCommandResolver.resolve(
        command: .scrollToBottom,
        tabs: [tab],
        activeTabId: tab.id
    )

    #expect(action == .scrollToBottom(tabId: tab.id, paneId: paneId))
}

@Test
func scrollToBottom_bindingActionString_isStable() {
    #expect(TerminalSurfaceAction.scrollToBottom.bindingActionString == "scroll_to_bottom")
}

@Test
func terminalRuntime_scrollToBottom_dispatchesThroughSurfaceManager() async {
    let runtime = TerminalRuntime(
        paneId: PaneId(uuid: UUIDv7.generate()),
        metadata: PaneMetadata(source: .floating(launchDirectory: nil, title: "Terminal"), title: "Terminal")
    )
    #expect(runtime.transitionToReady())

    let commandId = UUID()
    let envelope = RuntimeCommandEnvelope(
        commandId: commandId,
        correlationId: nil,
        targetPaneId: runtime.paneId,
        command: .terminal(.scrollToBottom),
        timestamp: ContinuousClock().now
    )

    let result = await runtime.handleCommand(envelope)

    #expect(result == .success(commandId: commandId))
}
```

- [ ] **Step 2: Run the failing tests**

Run:

```bash
swift test --build-path .build-agent-scroll-bottom --filter 'ActionResolverTests|TerminalRuntimeTests|TerminalSurfaceActionTests'
```

Expected: FAIL because the new action/command cases do not exist.

- [ ] **Step 3: Add validated pane action**

In `PaneActionCommand.swift`:

```swift
case scrollToBottom(tabId: UUID, paneId: UUID)
```

In `ActionResolver.swift`:

```swift
case .scrollToBottom:
    guard let activeTabId = activeTabId,
          let tab = tabs.first(where: { $0.id == activeTabId }),
          let paneId = tab.activePaneId
    else { return nil }
    return .scrollToBottom(tabId: tab.id, paneId: paneId)
```

In `ActionValidator.swift` add it to the existing pane-presence validation group:

```swift
case .toggleSplitZoom(let tabId, let paneId),
    .resizePaneByDelta(let tabId, let paneId, _, _),
    .minimizePane(let tabId, let paneId),
    .expandPane(let tabId, let paneId),
    .scrollToBottom(let tabId, let paneId):
    if let error = validateTabContainsPane(tabId: tabId, paneId: paneId, state: state) {
        return .failure(error)
    }
    return .success(ValidatedAction(action))
```

- [ ] **Step 4: Add runtime command plumbing**

In `RuntimeCommand.swift`:

```swift
enum TerminalCommand: Sendable {
    case sendInput(String)
    case resize(cols: Int, rows: Int)
    case clearScrollback
    case scrollToBottom
}
```

In `TerminalRuntime.requiredCapability(for:)`:

```swift
case .sendInput, .clearScrollback:
    return .input
case .scrollToBottom:
    return nil
```

In `TerminalRuntime.dispatchTerminalCommand(_:,commandId:)`:

```swift
case .scrollToBottom:
    let dispatchResult = SurfaceManager.shared.scrollToBottom(forPaneId: paneId.uuid)
    return mapSurfaceDispatchResult(dispatchResult, commandId: commandId, command: command)
```

In `SurfaceManager.swift`:

```swift
func scrollToBottom(forPaneId paneId: UUID) -> Result<Void, SurfaceError> {
    guard let surfaceId = surfaceId(forPaneId: paneId) else {
        return .failure(.surfaceNotFound)
    }

    let action = TerminalSurfaceAction.scrollToBottom.bindingActionString
    let didPerform = withSurface(surfaceId) { surface in
        action.withCString { ptr in
            ghostty_surface_binding_action(surface, ptr, UInt(action.utf8.count))
        }
    }

    switch didPerform {
    case .success(true):
        return .success(())
    case .success(false):
        return .failure(.operationFailed("Ghostty rejected scroll_to_bottom binding action"))
    case .failure(let error):
        return .failure(error)
    }
}
```

- [ ] **Step 5: Run the focused tests again**

Run:

```bash
swift test --build-path .build-agent-scroll-bottom --filter 'ActionResolverTests|TerminalRuntimeTests|TerminalSurfaceActionTests'
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add \
  Sources/AgentStudio/Core/Actions/PaneActionCommand.swift \
  Sources/AgentStudio/Core/Actions/ActionResolver.swift \
  Sources/AgentStudio/Core/Actions/ActionValidator.swift \
  Sources/AgentStudio/Core/RuntimeEventSystem/Contracts/RuntimeCommand.swift \
  Sources/AgentStudio/Features/Terminal/Runtime/TerminalRuntime.swift \
  Sources/AgentStudio/Features/Terminal/Ghostty/SurfaceManager.swift \
  Tests/AgentStudioTests/Features/Terminal/Runtime/TerminalRuntimeTests.swift \
  Tests/AgentStudioTests/Features/Terminal/Hosting/TerminalSurfaceActionTests.swift
git commit -m "feat: add validated scroll-to-bottom runtime command

Co-authored-by: Codex <noreply@openai.com>"
```

### Task 3: Wire the Command Through the Existing Validated Execution Path

**Files:**
- Modify: `Sources/AgentStudio/App/Panes/PaneTabViewController.swift`
- Modify: `Sources/AgentStudio/App/Coordination/PaneCoordinator+ActionExecution.swift`
- Test: `Tests/AgentStudioTests/App/AppCommandTests.swift`

- [ ] **Step 1: Write the failing controller tests**

```swift
@Test
func test_scrollToBottom_definition_isRegistered() {
    let dispatcher = CommandDispatcher.shared
    let def = dispatcher.definition(for: .scrollToBottom)
    #expect(def.label == "Scroll to Bottom")
}

@Test
func test_scrollToBottom_canExecute_requiresActivePane() {
    let dispatcher = CommandDispatcher.shared
    let handler = MockCommandHandler()
    dispatcher.handler = handler

    handler.canExecuteResult = false
    #expect(dispatcher.canDispatch(.scrollToBottom) == false)
}
```

- [ ] **Step 2: Run the failing tests**

Run:

```bash
swift test --build-path .build-agent-scroll-bottom --filter 'AppCommandTests'
```

Expected: FAIL until the command is wired through the current controller/coordinator path.

- [ ] **Step 3: Add execution path**

In `PaneCoordinator+ActionExecution.swift`, inside the existing `execute(_ action: PaneActionCommand)` switch:

```swift
case .scrollToBottom(_, let paneId):
    Task { @MainActor [weak self] in
        guard let self else { return }
        _ = await self.dispatchRuntimeCommand(
            .terminal(.scrollToBottom),
            target: .pane(PaneId(uuid: paneId))
        )
    }
```

In `PaneTabViewController.handleDirectCommand`, do **not** add a direct terminal call. Let `execute(_ command:)` continue to resolve through `WorkspaceCommandResolver` and `dispatchAction(_:)`.

If an explicit `canExecute` branch is needed, keep it in the current style:

```swift
case .scrollToBottom:
    guard let activeTabId = store.tabLayoutAtom.activeTabId,
          let tab = store.tabLayoutAtom.tab(activeTabId),
          tab.activePaneId != nil
    else { return false }
    return true
```

- [ ] **Step 4: Run the controller tests**

Run:

```bash
swift test --build-path .build-agent-scroll-bottom --filter 'AppCommandTests'
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add \
  Sources/AgentStudio/App/Panes/PaneTabViewController.swift \
  Sources/AgentStudio/App/Coordination/PaneCoordinator+ActionExecution.swift \
  Tests/AgentStudioTests/App/AppCommandTests.swift
git commit -m "feat: route scroll-to-bottom through validated pane execution

Co-authored-by: Codex <noreply@openai.com>"
```

### Task 4: Expose Scroll To Bottom in Command Bar

**Files:**
- Modify: `Sources/AgentStudio/Features/CommandBar/CommandBarDataSource.swift`
- Test: `Tests/AgentStudioTests/Features/CommandBar/CommandBarDataSourceTests.swift`
- Test: `Tests/AgentStudioTests/Features/CommandBar/CommandBarShortcutRouterTests.swift`

- [ ] **Step 1: Write the failing command-bar tests**

```swift
@Test
func commandBar_commandsScope_includesScrollToBottomInPaneGroup() {
    let items = CommandBarDataSource.items(
        scope: .commands,
        store: store,
        repoCache: repoCache,
        dispatcher: dispatcher,
        focus: focus
    )

    let item = items.first { $0.command == .scrollToBottom }
    #expect(item?.group == "Pane")
    #expect(item?.shortcutTrigger == AppShortcut.scrollToBottom.trigger)
}

@Test
func commandBar_shortcutRouter_matchesScrollToBottomShortcut() {
    let item = CommandBarItem(
        id: "cmd-scrollToBottom",
        title: "Scroll to Bottom",
        icon: "arrow.down.to.line",
        shortcutTrigger: AppShortcut.scrollToBottom.trigger,
        group: "Pane",
        groupPriority: 0,
        action: .dispatch(.scrollToBottom),
        command: .scrollToBottom
    )

    let selected = CommandBarRowShortcutResolver.selectedItem(
        for: AppShortcut.scrollToBottom.trigger,
        selectedItem: nil,
        displayedItems: [item]
    )

    #expect(selected?.id == item.id)
}
```

- [ ] **Step 2: Run the failing command-bar tests**

Run:

```bash
swift test --build-path .build-agent-scroll-bottom --filter 'CommandBarDataSourceTests|CommandBarShortcutRouterTests'
```

Expected: FAIL until the command is surfaced.

- [ ] **Step 3: Surface the command in command bar**

This should mostly fall out automatically from the new `CommandSpec`, because `CommandBarDataSource.commandItems(...)` uses `dispatcher.definitions.values`. Keep any grouping/visibility tweaks local to `AppCommand.definition`.

- [ ] **Step 4: Run the command-bar tests**

Run:

```bash
swift test --build-path .build-agent-scroll-bottom --filter 'CommandBarDataSourceTests|CommandBarShortcutRouterTests'
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add \
  Sources/AgentStudio/Features/CommandBar/CommandBarDataSource.swift \
  Tests/AgentStudioTests/Features/CommandBar/CommandBarDataSourceTests.swift \
  Tests/AgentStudioTests/Features/CommandBar/CommandBarShortcutRouterTests.swift
git commit -m "feat: expose scroll-to-bottom in command bar

Co-authored-by: Codex <noreply@openai.com>"
```

### Task 5: Full Verification

**Files:**
- Verify only

- [ ] **Step 1: Run focused suites**

Run:

```bash
swift test --build-path .build-agent-scroll-bottom --filter 'AppCommandTests|ShortcutCatalogTests|ActionResolverTests|TerminalRuntimeTests|TerminalSurfaceActionTests|CommandBarDataSourceTests|CommandBarShortcutRouterTests'
```

Expected: PASS.

- [ ] **Step 2: Run lint**

Run: `mise run lint`

Expected: exit code `0`.

- [ ] **Step 3: Run full suite**

Run: `mise run test`

Expected: full suite passes.

- [ ] **Step 4: Build debug and release**

Run:

```bash
mise run build
mise run build-release
```

Expected: both builds pass.

- [ ] **Step 5: Manual verification checklist**

```text
1. ⌥K scrolls the active terminal pane to bottom when terminal is focused
2. The command appears in Command Bar > Commands under Pane
3. Selecting the command from the command bar scrolls the active terminal pane to bottom
4. The command is unavailable when there is no active pane
5. Existing scroll-to-bottom indicator click still works
6. ⌥K is consumed as an app-owned terminal shortcut and does not double-fire with any Ghostty binding or Option-character input on the active keyboard layout
7. ShortcutCatalogTests still pass, proving no same-context shortcut conflict was introduced
```

- [ ] **Step 6: No extra commit for verification**

Verification only.

---

## Self-Review

### Spec coverage
- shortcut choice covered: `⌥K`
- command-bar entry covered
- validated pane-command path covered
- runtime dispatch covered
- compile/test shortcut conflict protection covered
- manual terminal behavior verification covered

### Placeholder scan
- no TBD/TODO placeholders
- all tasks include concrete files, commands, and code snippets

### Type consistency
- `AppCommand.scrollToBottom`
- `AppShortcut.scrollToBottom`
- `PaneActionCommand.scrollToBottom(tabId:paneId:)`
- `TerminalCommand.scrollToBottom`
- `SurfaceManager.scrollToBottom(forPaneId:)`

All names are consistent across tasks.

---

Plan complete and saved to `docs/superpowers/plans/2026-04-16-scroll-to-bottom-commandbar.md`. Two execution options:

**1. Subagent-Driven (recommended)** - I dispatch a fresh subagent per task, review between tasks, fast iteration

**2. Inline Execution** - Execute tasks in this session using executing-plans, batch execution with checkpoints

**Which approach?**
