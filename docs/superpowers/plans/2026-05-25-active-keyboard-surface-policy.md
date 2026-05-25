# Active Keyboard Surface Policy Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make shortcut dispatch compile-time-safe around active keyboard surfaces so transient surfaces block by default, command bar activation always has precedence, and arrangement panels explicitly behave as tab-local surfaces.

**Architecture:** `AppShortcutDispatchPolicy` remains the single policy owner. Call sites continue to ask `shouldDispatchGlobalShortcut(_:context:)` and `shouldDispatchTerminalAppOwnedShortcut(_:context:)`; the policy internally routes through a shortcut-aware `ActiveKeyboardSurface` decision. Transient surfaces get an explicit exhaustive sub-policy, with arrangement panel allowing only arrangement navigation and tab navigation while arrangement rename remains editor-like. Arrangement panel presentation is also made tab-local: tab switching through `Cmd+J/L` closes the currently presented arrangement panel instead of retargeting it to the newly active tab.

**Tech Stack:** Swift 6.2, Swift Testing (`@Suite`, `@Test`, `#expect`), existing `mise run test` / `mise run lint` workflow.

---

## Current State

`Sources/AgentStudio/App/Commands/AppShortcutDispatchPolicy.swift` currently has this blunt transient gate:

```swift
private static func shouldEvaluateStableOwnerPolicy(context: KeyboardRoutingContext) -> Bool {
    switch context.activeSurface {
    case .commandBar:
        return false
    case .transient(let surface):
        return shouldDispatchFromTransientSurface(surface: surface)
    case .stable:
        return true
    }
}

private static func shouldDispatchFromTransientSurface(surface: TransientKeyboardSurfaceKind) -> Bool {
    switch surface {
    case .tabRename, .arrangementPanel, .arrangementRename, .paneInbox, .editorChooser:
        return false
    }
}
```

That blocks every non-command-bar shortcut while `.arrangementPanel` owns keyboard input. The intended contract is narrower:

- Command bar activation shortcuts are reserved and evaluated before any surface policy.
- Command bar surface blocks app shortcuts while open.
- Transient surfaces block by default.
- A transient surface may explicitly allow a tiny set of app shortcuts it owns.
- `.arrangementPanel` is tab-local and owns `previousArrangement`, `nextArrangement`, `prevTab`, and `nextTab`.
- `.arrangementRename` is editor-like and owns no app shortcuts; Return/Escape/text editing stay local to the rename field.
- Arrangement panel presentation is tab-owned: the command request may be global, but the presented popover belongs to the tab that consumed the request. Switching tabs closes the current tab bar arrangement panel.
- Pane inbox popovers are already pane-local: `PaneLeafContainer` owns `paneInboxPopoverOpen`, resolves `PaneInboxScope(parentPaneId:paneIds:)`, and consumes only matching requests. Inbox sidebar remains a stable `.sidebar(.inbox)` surface, not a transient pane panel.

## File Map

- Modify: `Tests/AgentStudioTests/App/PaneTabViewControllerGlobalShortcutRoutingTests.swift`
  - Owns policy-level regression coverage for active surface routing.
- Modify: `Sources/AgentStudio/App/Commands/AppShortcutDispatchPolicy.swift`
  - Owns compile-time-safe shortcut dispatch policy.
- Create: `Sources/AgentStudio/App/Panes/TabBar/ArrangementPanelTabPresentationState.swift`
  - Owns tab-local arrangement popover presentation state transitions.
- Create: `Tests/AgentStudioTests/App/ArrangementPanelTabPresentationStateTests.swift`
  - Tests tab-local presentation state without needing SwiftUI popover automation.
- Modify: `Sources/AgentStudio/App/Panes/TabBar/CustomTabBar.swift`
  - Uses tab-local presentation state for the tab bar arrangement button.
- Modify: `docs/architecture/commands_and_shortcuts.md`
  - Documents the stable command/shortcut contract.
- Modify: `docs/superpowers/specs/2026-05-22-keyboard-surface-system.md`
  - Documents the active-surface precedence model.

Do not add controller special cases in `PaneTabViewController`. The controller should remain a command executor, not the keyboard policy owner. Do not move inbox sidebar into tab-local presentation; only pane inbox popovers are pane-local.

---

### Task 1: Policy Red Tests

**Files:**
- Modify: `Tests/AgentStudioTests/App/PaneTabViewControllerGlobalShortcutRoutingTests.swift`

- [ ] **Step 1: Replace the arrangement transient policy tests**

Find the existing arrangement transient tests near the command-bar/transient block and replace them with this block:

```swift
    @Test("arrangement panel allows tab-local navigation shortcuts")
    func arrangementPanelAllowsTabLocalNavigationShortcuts() {
        let context = KeyboardRoutingContext(
            stableOwner: .mainWindowChain,
            activeSurface: .transient(.arrangementPanel(tabId: UUID())),
            workspaceWindowId: UUID()
        )

        #expect(AppShortcutDispatchPolicy.shouldDispatchGlobalShortcut(.previousArrangement, context: context))
        #expect(AppShortcutDispatchPolicy.shouldDispatchGlobalShortcut(.nextArrangement, context: context))
        #expect(AppShortcutDispatchPolicy.shouldDispatchGlobalShortcut(.prevTab, context: context))
        #expect(AppShortcutDispatchPolicy.shouldDispatchGlobalShortcut(.nextTab, context: context))
    }

    @Test("arrangement panel blocks non owned app shortcuts")
    func arrangementPanelBlocksNonOwnedAppShortcuts() {
        let context = KeyboardRoutingContext(
            stableOwner: .mainWindowChain,
            activeSurface: .transient(.arrangementPanel(tabId: UUID())),
            workspaceWindowId: UUID()
        )

        for shortcut in AppShortcut.allCases
        where !AppShortcutDispatchPolicy.isCommandBarActivationShortcut(shortcut)
            && shortcut != .previousArrangement
            && shortcut != .nextArrangement
            && shortcut != .prevTab
            && shortcut != .nextTab
        {
            #expect(
                !AppShortcutDispatchPolicy.shouldDispatchGlobalShortcut(shortcut, context: context),
                "\(shortcut) should not dispatch while arrangement panel owns keyboard input"
            )
        }
    }

    @Test("arrangement rename blocks tab local navigation shortcuts")
    func arrangementRenameBlocksTabLocalNavigationShortcuts() {
        let context = KeyboardRoutingContext(
            stableOwner: .mainWindowChain,
            activeSurface: .transient(.arrangementRename(tabId: UUID(), arrangementId: UUID())),
            workspaceWindowId: UUID()
        )

        for shortcut in [
            AppShortcut.previousArrangement,
            .nextArrangement,
            .prevTab,
            .nextTab,
        ] {
            #expect(
                !AppShortcutDispatchPolicy.shouldDispatchGlobalShortcut(shortcut, context: context),
                "\(shortcut) should not dispatch while arrangement rename owns keyboard input"
            )
        }
    }
```

- [ ] **Step 2: Expand the command-bar activation transient test**

Replace the body of `commandBarActivationShortcutsAreAllowedThroughTransientSurfaces` with this code so both arrangement panel and arrangement rename prove the higher-precedence reservation:

```swift
        let contexts = [
            KeyboardRoutingContext(
                stableOwner: .managementLayer,
                activeSurface: .transient(.arrangementPanel(tabId: UUID())),
                workspaceWindowId: UUID()
            ),
            KeyboardRoutingContext(
                stableOwner: .managementLayer,
                activeSurface: .transient(.arrangementRename(tabId: UUID(), arrangementId: UUID())),
                workspaceWindowId: UUID()
            ),
        ]

        for context in contexts {
            for shortcut in [
                AppShortcut.newTab,
                .showCommandBarEverything,
                .showCommandBarCommands,
                .showCommandBarPanes,
            ] {
                #expect(
                    AppShortcutDispatchPolicy.shouldDispatchGlobalShortcut(shortcut, context: context),
                    "\(shortcut) should remain reserved for command bar activation"
                )
            }
        }
```

- [ ] **Step 3: Run the single red test**

Run:

```bash
source scripts/swift-build-slot.sh debug >/dev/null && swift test --build-path "$SWIFT_BUILD_DIR" --filter "arrangementPanelAllowsTabLocalNavigationShortcuts"
```

Expected: FAIL with expectations for `.previousArrangement`, `.nextArrangement`, `.prevTab`, and `.nextTab`, because current transient policy blocks `.arrangementPanel`.

---

### Task 2: Active Surface Policy Refactor

**Files:**
- Modify: `Sources/AgentStudio/App/Commands/AppShortcutDispatchPolicy.swift`

- [ ] **Step 1: Replace the context-based global policy path**

Replace:

```swift
        guard shouldEvaluateStableOwnerPolicy(context: context) else { return false }
        return shouldDispatchGlobalShortcut(shortcut, keyboardOwner: context.stableOwner)
```

with:

```swift
        return shouldDispatchFromActiveSurface(shortcut, context: context)
```

- [ ] **Step 2: Replace the terminal app-owned transient gate**

Replace:

```swift
        guard shouldEvaluateStableOwnerPolicy(context: context) else { return false }
```

with:

```swift
        guard shouldDispatchTerminalAppOwnedShortcutFromActiveSurface(shortcut, context: context) else {
            return false
        }
```

Keep the existing stable-owner switch immediately after it:

```swift
        switch context.stableOwner {
        case .mainWindowChain, .managementLayer:
            return shortcut.spec.contexts.contains(.terminalAppOwned)
        case .sidebar, .otherWindow:
            return false
        }
```

- [ ] **Step 3: Replace the old transient helper with active-surface helpers**

Delete:

```swift
    private static func shouldEvaluateStableOwnerPolicy(context: KeyboardRoutingContext) -> Bool {
        switch context.activeSurface {
        case .commandBar:
            return false
        case .transient(let surface):
            return shouldDispatchFromTransientSurface(surface: surface)
        case .stable:
            return true
        }
    }

    private static func shouldDispatchFromTransientSurface(surface: TransientKeyboardSurfaceKind) -> Bool {
        switch surface {
        case .tabRename, .arrangementPanel, .arrangementRename, .paneInbox, .editorChooser:
            return false
        }
    }
```

Insert:

```swift
    private static func shouldDispatchFromActiveSurface(
        _ shortcut: AppShortcut,
        context: KeyboardRoutingContext
    ) -> Bool {
        switch context.activeSurface {
        case .commandBar:
            return false
        case .transient(let surface):
            guard shouldDispatchFromTransientSurface(shortcut, surface: surface) else {
                return false
            }
            return shouldDispatchGlobalShortcut(shortcut, keyboardOwner: context.stableOwner)
        case .stable:
            return shouldDispatchGlobalShortcut(shortcut, keyboardOwner: context.stableOwner)
        }
    }

    private static func shouldDispatchTerminalAppOwnedShortcutFromActiveSurface(
        _ shortcut: AppShortcut,
        context: KeyboardRoutingContext
    ) -> Bool {
        switch context.activeSurface {
        case .commandBar:
            return false
        case .transient(let surface):
            return shouldDispatchFromTransientSurface(shortcut, surface: surface)
        case .stable:
            return true
        }
    }

    private static func shouldDispatchFromTransientSurface(
        _ shortcut: AppShortcut,
        surface: TransientKeyboardSurfaceKind
    ) -> Bool {
        switch surface {
        case .arrangementPanel:
            return shouldDispatchFromArrangementPanel(shortcut)
        case .tabRename, .arrangementRename, .paneInbox, .editorChooser:
            return false
        }
    }

    private static func shouldDispatchFromArrangementPanel(_ shortcut: AppShortcut) -> Bool {
        switch shortcut {
        case .previousArrangement, .nextArrangement, .prevTab, .nextTab:
            return true
        case .closeTab, .undoCloseTab, .newTab, .showArrangementPanel, .addDrawerPane,
            .toggleDrawer, .scrollToBottom, .jumpToPreviousPrompt, .jumpToNextPrompt,
            .openPaneLocationInBookmarkedEditor, .openPaneLocationInFinder,
            .openPaneLocationInEditorMenu, .toggleManagementLayer, .toggleSidebar,
            .filterSidebar, .showInboxNotifications, .showPaneInboxNotifications,
            .showWorktreeSidebar, .showCommandBarEverything, .showCommandBarCommands,
            .showCommandBarPanes, .newWindow, .closeWindow, .focusPane1, .focusPane2,
            .focusPane3, .focusPane4, .focusPane5, .focusPane6, .focusPane7, .focusPane8,
            .focusPane9, .managementLayerFocusLeft, .managementLayerFocusRight,
            .managementLayerEnterDrawer, .managementLayerExitDrawer,
            .managementLayerOpenDrawer, .managementLayerCreateTerminal,
            .managementLayerCreateBrowser, .managementLayerExit:
            return false
        }
    }
```

The `shouldDispatchFromArrangementPanel` switch intentionally has no `default`. Adding a new `AppShortcut` must force a compile-time classification.

- [ ] **Step 4: Run focused policy tests**

Run:

```bash
source scripts/swift-build-slot.sh debug >/dev/null && swift test --build-path "$SWIFT_BUILD_DIR" --filter "PaneTabViewController global shortcut routing"
```

Expected: PASS.

---

### Task 3: Controller Path Verification

**Files:**
- Test: `Tests/AgentStudioTests/App/PaneTabViewControllerGlobalShortcutRoutingTests.swift`
- Verify existing behavior in: `Sources/AgentStudio/App/Panes/PaneTabViewController.swift`

- [ ] **Step 1: Add production global key path coverage**

Add this test in the same suite:

```swift
    @Test("production global key path dispatches arrangement navigation through arrangement panel")
    func productionGlobalKeyPathDispatchesArrangementNavigationThroughArrangementPanel() async throws {
        try await withAsyncTestAtomRegistry { atoms in
            let harness = makeHarness()
            let handler = MockCommandHandler()
            configureMainWindowKeyboardOwner(atoms)
            let workspaceWindowId = try #require(atoms.windowLifecycle.focusedWindowId)
            _ = atoms.transientKeyboardSurface.present(
                .arrangementPanel(tabId: UUID()),
                windowId: workspaceWindowId
            )
            CommandDispatcher.shared.register(handler)
            defer { CommandDispatcher.shared.unregister(handler) }

            let event = NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: [.command, .option],
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                characters: "l",
                charactersIgnoringModifiers: "l",
                isARepeat: false,
                keyCode: 37
            )

            let handled = harness.controller.handleAppOwnedKeyEvent(try #require(event))

            #expect(handled)
            #expect(handler.executedCommands.map(\.0) == [.nextArrangement])
        }
    }
```

- [ ] **Step 2: Run the controller path test red or green**

Run:

```bash
source scripts/swift-build-slot.sh debug >/dev/null && swift test --build-path "$SWIFT_BUILD_DIR" --filter "production global key path dispatches arrangement navigation through arrangement panel"
```

Expected after Task 2: PASS.

---

### Task 4: Tab-Local Arrangement Panel Presentation

**Files:**
- Create: `Sources/AgentStudio/App/Panes/TabBar/ArrangementPanelTabPresentationState.swift`
- Create: `Tests/AgentStudioTests/App/ArrangementPanelTabPresentationStateTests.swift`
- Modify: `Sources/AgentStudio/App/Panes/TabBar/CustomTabBar.swift`

- [ ] **Step 1: Write the failing state tests**

Create `Tests/AgentStudioTests/App/ArrangementPanelTabPresentationStateTests.swift`:

```swift
import Foundation
import Testing

@testable import AgentStudio

@Suite("ArrangementPanelTabPresentationState")
struct ArrangementPanelTabPresentationStateTests {
    @Test("present records the owning tab")
    func presentRecordsOwningTab() {
        let tabId = UUID()
        var state = ArrangementPanelTabPresentationState()

        state.present(tabId: tabId)

        #expect(state.isPresented)
        #expect(state.presentedTabId == tabId)
    }

    @Test("active tab change closes panel owned by previous tab")
    func activeTabChangeClosesPanelOwnedByPreviousTab() {
        let firstTabId = UUID()
        let secondTabId = UUID()
        var state = ArrangementPanelTabPresentationState()
        state.present(tabId: firstTabId)

        state.activeTabDidChange(to: secondTabId)

        #expect(!state.isPresented)
        #expect(state.presentedTabId == nil)
    }

    @Test("active tab change keeps panel owned by same tab")
    func activeTabChangeKeepsPanelOwnedBySameTab() {
        let tabId = UUID()
        var state = ArrangementPanelTabPresentationState()
        state.present(tabId: tabId)

        state.activeTabDidChange(to: tabId)

        #expect(state.isPresented)
        #expect(state.presentedTabId == tabId)
    }

    @Test("toggle opens for active tab and closes when already open")
    func toggleOpensForActiveTabAndClosesWhenAlreadyOpen() {
        let tabId = UUID()
        var state = ArrangementPanelTabPresentationState()

        state.toggle(activeTabId: tabId)
        #expect(state.isPresented)
        #expect(state.presentedTabId == tabId)

        state.toggle(activeTabId: tabId)
        #expect(!state.isPresented)
        #expect(state.presentedTabId == nil)
    }

    @Test("set presented false clears owner")
    func setPresentedFalseClearsOwner() {
        let tabId = UUID()
        var state = ArrangementPanelTabPresentationState()
        state.present(tabId: tabId)

        state.setPresented(false, activeTabId: tabId)

        #expect(!state.isPresented)
        #expect(state.presentedTabId == nil)
    }
}
```

- [ ] **Step 2: Run the red state tests**

Run:

```bash
source scripts/swift-build-slot.sh debug >/dev/null && swift test --build-path "$SWIFT_BUILD_DIR" --filter "ArrangementPanelTabPresentationState"
```

Expected: FAIL because `ArrangementPanelTabPresentationState` does not exist.

- [ ] **Step 3: Add the tab-local presentation state**

Create `Sources/AgentStudio/App/Panes/TabBar/ArrangementPanelTabPresentationState.swift`:

```swift
import Foundation

struct ArrangementPanelTabPresentationState: Equatable {
    private(set) var presentedTabId: UUID?

    var isPresented: Bool {
        presentedTabId != nil
    }

    mutating func present(tabId: UUID) {
        presentedTabId = tabId
    }

    mutating func dismiss() {
        presentedTabId = nil
    }

    mutating func toggle(activeTabId: UUID?) {
        if isPresented {
            dismiss()
        } else if let activeTabId {
            present(tabId: activeTabId)
        }
    }

    mutating func setPresented(_ isPresented: Bool, activeTabId: UUID?) {
        if isPresented, let activeTabId {
            present(tabId: activeTabId)
        } else if !isPresented {
            dismiss()
        }
    }

    mutating func activeTabDidChange(to activeTabId: UUID?) {
        guard isPresented, presentedTabId != activeTabId else { return }
        dismiss()
    }
}
```

- [ ] **Step 4: Update the tab bar arrangement button**

In `Sources/AgentStudio/App/Panes/TabBar/CustomTabBar.swift`, replace:

```swift
    @State private var isPanelPresented = false
```

with:

```swift
    @State private var presentationState = ArrangementPanelTabPresentationState()
```

Replace the button action:

```swift
            popoverToggleGate.toggle(isPresented: &isPanelPresented)
```

with:

```swift
            var isPresented = presentationState.isPresented
            popoverToggleGate.toggle(isPresented: &isPresented)
            presentationState.setPresented(isPresented, activeTabId: adapter.activeTabId)
```

Replace every non-binding read of `isPanelPresented` in `TabBarArrangementButton` with `presentationState.isPresented`.

Replace the popover binding with:

```swift
            isPresented: Binding(
                get: { presentationState.isPresented },
                set: { newValue in
                    if !newValue && presentationState.isPresented {
                        presentationState.setPresented(false, activeTabId: adapter.activeTabId)
                        popoverToggleGate.recordSystemDismissal()
                    } else {
                        presentationState.setPresented(newValue, activeTabId: adapter.activeTabId)
                    }
                }
            ),
```

Replace `openPopoverIfRenameTargetsActiveTab()` with:

```swift
    private func openPopoverIfRenameTargetsActiveTab() {
        guard
            ArrangementPopoverAutoOpen.shouldOpen(
                editingArrangementId: arrangementInlineRenameState.editingArrangementId,
                activeTabArrangements: activeTab?.arrangements,
                isPresented: presentationState.isPresented
            ),
            let activeTabId = adapter.activeTabId
        else { return }
        presentationState.present(tabId: activeTabId)
    }
```

Replace `openPopoverIfRequested()` with:

```swift
    private func openPopoverIfRequested() {
        guard
            let request = presentationAtom.pendingRequest,
            request.tabId == adapter.activeTabId,
            request.workspaceWindowId == workspaceWindowId
        else { return }

        presentationState.present(tabId: request.tabId)
        presentationAtom.consume(request)
    }
```

In the `onChange(of: adapter.activeTabId)` handler, add `presentationState.activeTabDidChange(to: newTabId)` before trying to open pending requests:

```swift
        .onChange(of: adapter.activeTabId) { _, newTabId in
            presentationState.activeTabDidChange(to: newTabId)
            openPopoverIfRenameTargetsActiveTab()
            openPopoverIfRequested()
        }
```

Do not change `CollapsedPaneBar` for this task. It already has a fixed `tabId` and consumes only requests whose `request.tabId == tabId`.

- [ ] **Step 5: Run the state tests green**

Run:

```bash
source scripts/swift-build-slot.sh debug >/dev/null && swift test --build-path "$SWIFT_BUILD_DIR" --filter "ArrangementPanelTabPresentationState"
```

Expected: PASS.

- [ ] **Step 6: Run affected arrangement/tab bar tests**

Run:

```bash
source scripts/swift-build-slot.sh debug >/dev/null && swift test --build-path "$SWIFT_BUILD_DIR" --filter "TabBarArrangementChip|ArrangementPanelPresentationAtom|PaneTabViewControllerCommandTests"
```

Expected: PASS.

---

### Task 5: Documentation

**Files:**
- Modify: `docs/architecture/commands_and_shortcuts.md`
- Modify: `docs/superpowers/specs/2026-05-22-keyboard-surface-system.md`

- [ ] **Step 1: Update commands and shortcuts architecture doc**

In `docs/architecture/commands_and_shortcuts.md`, update the keyboard surface section so it contains this contract:

```markdown
### Active Keyboard Surface Precedence

Shortcut dispatch is resolved in this order:

1. Command-bar activation shortcuts are globally reserved for workspace windows. `⌘T`, `⌘P`, `⌘⇧P`, and `⌘⌥P` are checked before active surface policy and cannot be blocked by transient surfaces.
2. When the command bar is active, it owns keyboard input and blocks non-activation app shortcuts.
3. Transient surfaces block app shortcuts by default. A transient surface may explicitly allow a small set of app shortcuts it owns.
4. Stable keyboard owners (`mainWindowChain`, `managementLayer`, `sidebar`, `otherWindow`) use the stable owner dispatch policy.

Arrangement panel is a tab-local transient surface. It allows `previousArrangement`, `nextArrangement`, `prevTab`, and `nextTab` while open. Arrangement rename is editor-like and blocks app shortcuts except command-bar activation; Return, Escape, and text editing are local responder behavior.

Arrangement panel presentation is owned by the tab that opens or consumes the request. Switching tabs while the tab bar arrangement panel is open closes that panel instead of retargeting it to the new active tab. Pane inbox popovers are pane-local panels; inbox sidebar remains the stable `.sidebar(.inbox)` surface.
```

- [ ] **Step 2: Update keyboard surface spec**

In `docs/superpowers/specs/2026-05-22-keyboard-surface-system.md`, add this rule near the transient surface section:

```markdown
### Transient Surface-Owned App Shortcuts

Transient surfaces block app shortcuts by default. Surface-owned app shortcuts are explicit and compile-time classified in `AppShortcutDispatchPolicy`.

Current owned shortcuts:

- `.arrangementPanel`: `.previousArrangement`, `.nextArrangement`, `.prevTab`, `.nextTab`
- `.tabRename`, `.arrangementRename`, `.paneInbox`, `.editorChooser`: none

Command-bar activation is not a transient-surface allowance. It is a higher-precedence reservation and is evaluated before transient surface policy.

Arrangement panel presentation is tab-local. Command dispatch may create a request in `ArrangementPanelPresentationAtom`, but the tab bar or collapsed bar consumes that request only when its tab matches. Tab switching closes an open tab bar arrangement panel. Pane inbox popovers follow the same locality principle at pane scope; the inbox sidebar remains a stable sidebar surface.
```

---

### Task 6: Verification

**Files:**
- Verify all modified source, tests, and docs.

- [ ] **Step 1: Format**

Run:

```bash
mise run format
```

Expected: exits `0`.

- [ ] **Step 2: Focused tests**

Run:

```bash
source scripts/swift-build-slot.sh debug >/dev/null && swift test --build-path "$SWIFT_BUILD_DIR" --filter "PaneTabViewController global shortcut routing"
```

Expected: exits `0`; the arrangement panel allow/block tests pass.

- [ ] **Step 3: Tab-local panel tests**

Run:

```bash
source scripts/swift-build-slot.sh debug >/dev/null && swift test --build-path "$SWIFT_BUILD_DIR" --filter "ArrangementPanelTabPresentationState|ArrangementPanelPresentationAtom|TabBarArrangementChip"
```

Expected: exits `0`; tab-local panel state and existing arrangement UI tests pass.

- [ ] **Step 4: Full tests**

Run:

```bash
mise run test
```

Expected: exits `0`. Project-default E2E/Zmx suites may be skipped when their env flags are unset.

- [ ] **Step 5: Lint**

Run:

```bash
mise run lint
```

Expected: exits `0`; swift-format lint OK, swiftlint 0 serious violations, architecture boundary checks pass.

- [ ] **Step 6: Worktree audit**

Run:

```bash
git status --short
git diff --stat
```

Expected: only the planned files are changed plus any existing untracked plan/review artifacts already present before execution. Do not commit unless the user explicitly asks for a git write.

---

## Self-Review

Spec coverage:

- Command bar precedence is covered in Task 1 and Task 4.
- General active-surface policy is covered in Task 2.
- Compile-time-safe shortcut classification is covered by exhaustive switches in Task 2.
- Arrangement panel tab-local behavior is covered in Task 1 and Task 3.
- Arrangement rename editor-like behavior is covered in Task 1.
- Tab-local presentation lifecycle is covered in Task 4.
- Pane inbox/sidebar locality is documented in Task 5.
- Full verification is covered in Task 6.

Placeholder scan:

- No `TBD`, `TODO`, or unspecified implementation steps remain.

Type consistency:

- Uses existing types: `AppShortcut`, `KeyboardRoutingContext`, `ActiveKeyboardSurface`, `TransientKeyboardSurfaceKind`, `AppShortcutDispatchPolicy`.
- Uses existing command names: `.previousArrangement`, `.nextArrangement`, `.prevTab`, `.nextTab`.
