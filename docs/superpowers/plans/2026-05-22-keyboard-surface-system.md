# Keyboard Surface System Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a compile-time-safe keyboard surface system where command bar is a first-class privileged surface, repo and inbox sidebars remain separate stable surfaces, and pane-local transient surfaces suppress app shortcuts without hiding command bar activation.

**Architecture:** Use the current `KeyboardOwner` and `TransientKeyboardSurfaceAtom` model, but add `CommandBarSurfaceAtom` and a resolved `ActiveKeyboardSurface`. `KeyboardRoutingContext` becomes the single read model for policy: command bar wins first, transient surfaces win second, stable owners win third. Local responders still own local editing/navigation keys.

**Tech Stack:** Swift 6.2, SwiftUI, AppKit `NSPanel`/`NSPopover`, Swift Testing, AtomRegistry state.

---

## Source Spec

This plan implements `docs/superpowers/specs/2026-05-22-keyboard-surface-system.md`.

## Current System Validation

The plan keeps the existing command architecture intact:

- `AppCommand` remains the command identity layer.
- `AppShortcut` remains the keyboard binding and context layer.
- `AppCommand+Catalog` remains the command bar metadata layer.
- `CommandDispatcher` remains the execution path.
- `AppShortcutDispatchPolicy` remains the allow/block policy layer.

The plan changes only the missing surface read model and the call sites that currently bypass it:

- `KeyboardRoutingContext` learns the resolved active surface.
- `CommandBarPanelController` publishes active command bar scope.
- `PaneTabViewController`, `ManagementLayerMonitor`, and `Ghostty.SurfaceView` consult the same active-surface policy.
- `AppCommand+Catalog` stops hiding command-bar activation commands from command bar results.

These constraints keep the implementation aligned with `docs/architecture/commands_and_shortcuts.md`: command identity, keyboard binding, command bar metadata, and local UI presentation stay separate.

## File Structure

- Create: `Sources/AgentStudio/Core/Models/CommandBarScope.swift`
  - Move `CommandBarScope` out of the CommandBar feature file so Core routing types can reference it.
- Modify: `Sources/AgentStudio/Features/CommandBar/CommandBarItem.swift`
  - Remove the old `CommandBarScope` declaration.
- Create: `Sources/AgentStudio/Core/State/MainActor/Atoms/CommandBarSurfaceAtom.swift`
  - Track active command bar scope as surface state.
- Modify: `Sources/AgentStudio/AtomRegistry.swift`
  - Register `commandBarSurface`.
- Create: `Sources/AgentStudio/Core/Models/ActiveKeyboardSurface.swift`
  - Add `ActiveKeyboardSurface.commandBar`, `.transient`, and `.stable`.
- Modify: `Sources/AgentStudio/Core/Models/KeyboardRoutingContext.swift`
  - Resolve stable owner plus active surface in command bar > transient > stable order.
- Modify: `Sources/AgentStudio/Core/Models/TransientKeyboardSurface.swift`
  - Add arrangement, pane inbox, and editor chooser transient kinds.
- Modify: `Sources/AgentStudio/App/Commands/AppShortcut.swift`
  - Add `.terminalAppOwned` to `AppShortcut.newTab` so `⌘T` repo command-bar activation decodes inside focused terminal panes.
- Modify: `Sources/AgentStudio/App/Commands/AppShortcutDispatchPolicy.swift`
  - Make command-bar activation a reserved allow-through policy.
  - Block non-command-bar shortcuts while command bar or transient surfaces own keys.
  - Add terminal-app-owned policy.
- Modify: `Sources/AgentStudio/Features/CommandBar/CommandBarPanelController.swift`
  - Publish command-bar active scope to `CommandBarSurfaceAtom`.
- Modify: `Sources/AgentStudio/App/Boot/AppDelegate.swift`
  - Pass `atomStore.commandBarSurface` into the command bar controller.
- Modify: `Sources/AgentStudio/App/Panes/PaneTabViewController.swift`
  - Use the new routing context and dispatch command-bar activation before broad transient blocking.
- Modify: `Sources/AgentStudio/Features/Terminal/Ghostty/GhosttySurfaceView+Input.swift`
  - Route terminal-app-owned shortcuts through the new policy.
- Create: `Sources/AgentStudio/Core/Views/TransientKeyboardSurfaceRegistrationModifier.swift`
  - Register SwiftUI popover/editor surfaces with the transient atom.
- Modify: `Sources/AgentStudio/Core/Views/Panes/ArrangementPanel.swift`
  - Register arrangement panel and arrangement rename transient surfaces.
- Modify: `Sources/AgentStudio/Features/InboxNotification/Views/PaneInboxNotificationPopover.swift`
  - Register pane inbox transient surface.
- Modify: `Sources/AgentStudio/App/Panes/DrawerEditorChooser/DrawerEditorChooserFactory.swift`
  - Register editor chooser transient surface.
- Modify: `Sources/AgentStudio/App/Commands/AppCommand+Catalog.swift`
  - Make command-bar activation commands visible in the command bar.
- Modify: `Tests/AgentStudioTests/Core/State/MainActor/Atoms/TransientKeyboardSurfaceAtomTests.swift`
  - Cover mixed transient kinds.
- Create: `Tests/AgentStudioTests/Core/State/MainActor/Atoms/CommandBarSurfaceAtomTests.swift`
  - Cover command-bar surface atom lifecycle.
- Create: `Tests/AgentStudioTests/Core/Models/KeyboardRoutingContextSurfaceTests.swift`
  - Cover active-surface resolution order.
- Modify: `Tests/AgentStudioTests/App/PaneTabViewControllerGlobalShortcutRoutingTests.swift`
  - Cover command-bar activation allow-through and non-command-bar suppression.
- Modify: `Tests/AgentStudioTests/App/ManagementLayerTests.swift`
  - Cover management pass-through while transients are active.
- Create: `Tests/AgentStudioTests/App/TerminalAppOwnedShortcutPolicyTests.swift`
  - Cover terminal-app-owned policy.
- Modify: `Tests/AgentStudioTests/Features/CommandBar/CommandBarDataSourceTests.swift`
  - Cover command-bar activation commands visible in command-bar results.
- Modify: `docs/architecture/commands_and_shortcuts.md`
  - Document stable owners, command bar surface, transient surfaces, and policy precedence.

---

### Task 1: Move CommandBarScope To Core

**Files:**
- Create: `Sources/AgentStudio/Core/Models/CommandBarScope.swift`
- Modify: `Sources/AgentStudio/Features/CommandBar/CommandBarItem.swift`

- [ ] **Step 1: Create Core command bar scope type**

Create `Sources/AgentStudio/Core/Models/CommandBarScope.swift`:

```swift
import Foundation

/// Scope of the command bar, determined by prefix character or default owner.
enum CommandBarScope: Equatable, Sendable {
    case everything
    case commands
    case panes
    case repos
    case inbox
}
```

- [ ] **Step 2: Remove old declaration**

In `Sources/AgentStudio/Features/CommandBar/CommandBarItem.swift`, delete lines 3-12:

```swift
// MARK: - CommandBarScope

/// Scope of the command bar, determined by prefix character in the search input.
enum CommandBarScope {
    case everything  // no prefix — shows recents, tabs, panes, commands, worktrees
    case commands  // ">" prefix — shows only commands grouped by category
    case panes  // "$" prefix — shows only panes grouped by tab
    case repos  // "#" prefix — shows repos and worktrees for opening
    case inbox
}
```

- [ ] **Step 3: Run command bar scope tests**

Run:

```bash
swift test --build-path ".build-agent-$PPID" --filter "CommandBarState|CommandBarGlobalKeyRouter|CommandBarShortcutRouter"
```

Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add Sources/AgentStudio/Core/Models/CommandBarScope.swift \
  Sources/AgentStudio/Features/CommandBar/CommandBarItem.swift
git commit -m "$(cat <<'MSG'
refactor: move command bar scope to core models

Co-authored-by: Codex <noreply@openai.com>
MSG
)"
```

---

### Task 2: Add Command Bar Surface State And Active Surface Resolution

**Files:**
- Create: `Sources/AgentStudio/Core/State/MainActor/Atoms/CommandBarSurfaceAtom.swift`
- Create: `Sources/AgentStudio/Core/Models/ActiveKeyboardSurface.swift`
- Modify: `Sources/AgentStudio/AtomRegistry.swift`
- Modify: `Sources/AgentStudio/Core/Models/KeyboardRoutingContext.swift`
- Test: `Tests/AgentStudioTests/Core/State/MainActor/Atoms/CommandBarSurfaceAtomTests.swift`
- Test: `Tests/AgentStudioTests/Core/Models/KeyboardRoutingContextSurfaceTests.swift`

- [ ] **Step 1: Write failing command bar surface atom tests**

Create `Tests/AgentStudioTests/Core/State/MainActor/Atoms/CommandBarSurfaceAtomTests.swift`:

```swift
import Testing

@testable import AgentStudio

@MainActor
@Suite("CommandBarSurfaceAtom")
struct CommandBarSurfaceAtomTests {
    @Test("surface starts inactive")
    func surfaceStartsInactive() {
        let atom = CommandBarSurfaceAtom()

        #expect(atom.activeScope == nil)
        #expect(!atom.isActive)
    }

    @Test("present updates active scope")
    func presentUpdatesActiveScope() {
        let atom = CommandBarSurfaceAtom()

        atom.present(scope: .commands)

        #expect(atom.activeScope == .commands)
        #expect(atom.isActive)
    }

    @Test("dismiss clears active scope")
    func dismissClearsActiveScope() {
        let atom = CommandBarSurfaceAtom()
        atom.present(scope: .panes)

        atom.dismiss()

        #expect(atom.activeScope == nil)
        #expect(!atom.isActive)
    }
}
```

- [ ] **Step 2: Write failing active-surface resolution tests**

Create `Tests/AgentStudioTests/Core/Models/KeyboardRoutingContextSurfaceTests.swift`:

```swift
import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite("KeyboardRoutingContext active surface")
struct KeyboardRoutingContextSurfaceTests {
    private func makeKeyWindow(_ windowLifecycle: WindowLifecycleAtom) -> UUID {
        let workspaceWindowId = UUID()
        windowLifecycle.recordWindowRegistered(workspaceWindowId)
        windowLifecycle.recordWindowBecameKey(workspaceWindowId)
        return workspaceWindowId
    }

    @Test("command bar takes precedence over transient and stable owner")
    func commandBarTakesPrecedenceOverTransientAndStableOwner() {
        let windowLifecycle = WindowLifecycleAtom()
        let managementLayer = ManagementLayerAtom()
        let uiState = UIStateAtom()
        let commandBarSurface = CommandBarSurfaceAtom()
        let transientSurface = TransientKeyboardSurfaceAtom()
        let workspaceWindowId = makeKeyWindow(windowLifecycle)

        managementLayer.activate()
        commandBarSurface.present(scope: .commands)
        _ = transientSurface.present(.tabRename(tabId: UUID()), workspaceWindowId: workspaceWindowId)

        let context = KeyboardRoutingContext.current(
            windowLifecycle: windowLifecycle,
            managementLayer: managementLayer,
            uiState: uiState,
            commandBarSurface: commandBarSurface,
            transientKeyboardSurface: transientSurface
        )

        #expect(context.stableOwner == .managementLayer)
        #expect(context.activeSurface == .commandBar(scope: .commands))
    }

    @Test("transient takes precedence over stable owner")
    func transientTakesPrecedenceOverStableOwner() {
        let windowLifecycle = WindowLifecycleAtom()
        let managementLayer = ManagementLayerAtom()
        let uiState = UIStateAtom()
        let commandBarSurface = CommandBarSurfaceAtom()
        let transientSurface = TransientKeyboardSurfaceAtom()
        let workspaceWindowId = makeKeyWindow(windowLifecycle)
        let tabId = UUID()

        _ = transientSurface.present(.arrangementPanel(tabId: tabId), workspaceWindowId: workspaceWindowId)

        let context = KeyboardRoutingContext.current(
            windowLifecycle: windowLifecycle,
            managementLayer: managementLayer,
            uiState: uiState,
            commandBarSurface: commandBarSurface,
            transientKeyboardSurface: transientSurface
        )

        #expect(context.stableOwner == .mainWindowChain)
        #expect(context.activeSurface == .transient(.arrangementPanel(tabId: tabId)))
    }

    @Test("stable owner is active when no overlay is active")
    func stableOwnerIsActiveWhenNoOverlayIsActive() {
        let windowLifecycle = WindowLifecycleAtom()
        let managementLayer = ManagementLayerAtom()
        let uiState = UIStateAtom()
        let commandBarSurface = CommandBarSurfaceAtom()
        let transientSurface = TransientKeyboardSurfaceAtom()
        makeKeyWindow(windowLifecycle)
        uiState.setSidebarCollapsed(false)
        uiState.setSidebarSurface(.inbox)
        uiState.setSidebarHasFocus(true)

        let context = KeyboardRoutingContext.current(
            windowLifecycle: windowLifecycle,
            managementLayer: managementLayer,
            uiState: uiState,
            commandBarSurface: commandBarSurface,
            transientKeyboardSurface: transientSurface
        )

        #expect(context.stableOwner == .sidebar(.inbox))
        #expect(context.activeSurface == .stable(.sidebar(.inbox)))
    }
}
```

- [ ] **Step 3: Run tests to verify they fail**

Run:

```bash
swift test --build-path ".build-agent-$PPID" --filter "CommandBarSurfaceAtomTests|KeyboardRoutingContextSurfaceTests"
```

Expected: FAIL with missing `CommandBarSurfaceAtom`, `ActiveKeyboardSurface`, and `commandBarSurface` argument.

- [ ] **Step 4: Add command bar surface atom**

Create `Sources/AgentStudio/Core/State/MainActor/Atoms/CommandBarSurfaceAtom.swift`:

```swift
import Foundation
import Observation

@MainActor
@Observable
final class CommandBarSurfaceAtom {
    private(set) var activeScope: CommandBarScope?

    var isActive: Bool {
        activeScope != nil
    }

    func present(scope: CommandBarScope) {
        activeScope = scope
    }

    func dismiss() {
        activeScope = nil
    }
}
```

- [ ] **Step 5: Add active keyboard surface type**

Create `Sources/AgentStudio/Core/Models/ActiveKeyboardSurface.swift`:

```swift
import Foundation

enum ActiveKeyboardSurface: Equatable, Sendable {
    case commandBar(scope: CommandBarScope)
    case transient(TransientKeyboardSurfaceKind)
    case stable(KeyboardOwner)
}
```

- [ ] **Step 6: Register atom**

In `Sources/AgentStudio/AtomRegistry.swift`, add a stored property after `managementLayer`:

```swift
    let commandBarSurface: CommandBarSurfaceAtom
```

Add an initializer parameter after `managementLayer`:

```swift
        commandBarSurface: CommandBarSurfaceAtom = .init(),
```

Assign it after `self.managementLayer = managementLayer`:

```swift
        self.commandBarSurface = commandBarSurface
```

- [ ] **Step 7: Update keyboard routing context**

Replace `Sources/AgentStudio/Core/Models/KeyboardRoutingContext.swift` with:

```swift
import Foundation

struct KeyboardRoutingContext: Equatable, Sendable {
    let stableOwner: KeyboardOwner
    let activeSurface: ActiveKeyboardSurface
    let workspaceWindowId: UUID?

    init(
        stableOwner: KeyboardOwner,
        activeSurface: ActiveKeyboardSurface,
        workspaceWindowId: UUID? = nil
    ) {
        self.stableOwner = stableOwner
        self.activeSurface = activeSurface
        self.workspaceWindowId = workspaceWindowId
    }
}

extension KeyboardRoutingContext {
    @MainActor
    static func current(
        windowLifecycle: WindowLifecycleAtom,
        managementLayer: ManagementLayerAtom,
        uiState: UIStateAtom,
        commandBarSurface: CommandBarSurfaceAtom,
        transientKeyboardSurface: TransientKeyboardSurfaceAtom,
        workspaceWindowId: UUID? = nil
    ) -> KeyboardRoutingContext {
        let stableOwner = KeyboardOwner.current(
            windowLifecycle: windowLifecycle,
            managementLayer: managementLayer,
            uiState: uiState
        )
        let resolvedWorkspaceWindowId =
            workspaceWindowId ?? windowLifecycle.focusedWindowId ?? windowLifecycle.keyWindowId

        let activeSurface: ActiveKeyboardSurface
        if let commandBarScope = commandBarSurface.activeScope {
            activeSurface = .commandBar(scope: commandBarScope)
        } else if let transientSurface = transientKeyboardSurface.topSurface(for: resolvedWorkspaceWindowId) {
            activeSurface = .transient(transientSurface.kind)
        } else {
            activeSurface = .stable(stableOwner)
        }

        return KeyboardRoutingContext(
            stableOwner: stableOwner,
            activeSurface: activeSurface,
            workspaceWindowId: resolvedWorkspaceWindowId
        )
    }
}
```

- [ ] **Step 8: Run tests**

Run:

```bash
swift test --build-path ".build-agent-$PPID" --filter "CommandBarSurfaceAtomTests|KeyboardRoutingContextSurfaceTests"
```

Expected: PASS.

- [ ] **Step 9: Commit**

```bash
git add Sources/AgentStudio/Core/Models/CommandBarScope.swift \
  Sources/AgentStudio/Features/CommandBar/CommandBarItem.swift \
  Sources/AgentStudio/Core/State/MainActor/Atoms/CommandBarSurfaceAtom.swift \
  Sources/AgentStudio/Core/Models/ActiveKeyboardSurface.swift \
  Sources/AgentStudio/AtomRegistry.swift \
  Sources/AgentStudio/Core/Models/KeyboardRoutingContext.swift \
  Tests/AgentStudioTests/Core/State/MainActor/Atoms/CommandBarSurfaceAtomTests.swift \
  Tests/AgentStudioTests/Core/Models/KeyboardRoutingContextSurfaceTests.swift
git commit -m "$(cat <<'MSG'
feat: model active keyboard surfaces

Co-authored-by: Codex <noreply@openai.com>
MSG
)"
```

---

### Task 3: Expand Transient Kinds And Shortcut Policy

**Files:**
- Modify: `Sources/AgentStudio/Core/Models/TransientKeyboardSurface.swift`
- Modify: `Sources/AgentStudio/App/Commands/AppShortcutDispatchPolicy.swift`
- Test: `Tests/AgentStudioTests/Core/State/MainActor/Atoms/TransientKeyboardSurfaceAtomTests.swift`
- Test: `Tests/AgentStudioTests/App/PaneTabViewControllerGlobalShortcutRoutingTests.swift`

- [ ] **Step 1: Write failing mixed transient-kind test**

Append this test to `Tests/AgentStudioTests/Core/State/MainActor/Atoms/TransientKeyboardSurfaceAtomTests.swift`:

```swift
    @Test("mixed transient kinds remain token scoped and window scoped")
    func mixedTransientKindsRemainTokenScopedAndWindowScoped() {
        let atom = TransientKeyboardSurfaceAtom()
        let firstWindowId = UUID()
        let secondWindowId = UUID()
        let tabId = UUID()
        let arrangementId = UUID()
        let parentPaneId = UUID()
        let editorPaneId = UUID()

        let arrangementToken = atom.present(.arrangementPanel(tabId: tabId), workspaceWindowId: firstWindowId)
        let renameToken = atom.present(
            .arrangementRename(tabId: tabId, arrangementId: arrangementId),
            workspaceWindowId: firstWindowId
        )
        let inboxToken = atom.present(.paneInbox(parentPaneId: parentPaneId), workspaceWindowId: secondWindowId)
        let editorToken = atom.present(.editorChooser(paneId: editorPaneId), workspaceWindowId: firstWindowId)

        #expect(atom.surfaces.map(\.token) == [arrangementToken, renameToken, inboxToken, editorToken])
        #expect(atom.topAnySurface?.kind == .editorChooser(paneId: editorPaneId))
        #expect(atom.topSurface(for: firstWindowId)?.kind == .editorChooser(paneId: editorPaneId))
        #expect(atom.topSurface(for: secondWindowId)?.kind == .paneInbox(parentPaneId: parentPaneId))

        atom.dismiss(editorToken)

        #expect(atom.topSurface(for: firstWindowId)?.kind == .arrangementRename(
            tabId: tabId,
            arrangementId: arrangementId
        ))
    }
```

- [ ] **Step 2: Write failing policy tests**

Append these tests to `Tests/AgentStudioTests/App/PaneTabViewControllerGlobalShortcutRoutingTests.swift`:

```swift
    @Test("command bar activation shortcuts are allowed through transient surfaces")
    func commandBarActivationShortcutsAreAllowedThroughTransientSurfaces() {
        let context = KeyboardRoutingContext(
            stableOwner: .managementLayer,
            activeSurface: .transient(.arrangementPanel(tabId: UUID())),
            workspaceWindowId: UUID()
        )

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

    @Test("non command bar shortcuts are blocked while command bar owns keyboard")
    func nonCommandBarShortcutsAreBlockedWhileCommandBarOwnsKeyboard() {
        let context = KeyboardRoutingContext(
            stableOwner: .mainWindowChain,
            activeSurface: .commandBar(scope: .everything),
            workspaceWindowId: UUID()
        )

        for shortcut in AppShortcut.allCases where !AppShortcutDispatchPolicy.isCommandBarActivationShortcut(shortcut) {
            #expect(
                !AppShortcutDispatchPolicy.shouldDispatchGlobalShortcut(shortcut, context: context),
                "\(shortcut) should not dispatch while command bar owns keyboard input"
            )
        }
    }

    @Test("non command bar shortcuts are blocked while arrangement owns keyboard")
    func nonCommandBarShortcutsAreBlockedWhileArrangementOwnsKeyboard() {
        let context = KeyboardRoutingContext(
            stableOwner: .mainWindowChain,
            activeSurface: .transient(.arrangementPanel(tabId: UUID())),
            workspaceWindowId: UUID()
        )

        for shortcut in AppShortcut.allCases where !AppShortcutDispatchPolicy.isCommandBarActivationShortcut(shortcut) {
            #expect(
                !AppShortcutDispatchPolicy.shouldDispatchGlobalShortcut(shortcut, context: context),
                "\(shortcut) should not dispatch while arrangement owns keyboard input"
            )
        }
    }
```

- [ ] **Step 3: Run tests to verify they fail**

Run:

```bash
swift test --build-path ".build-agent-$PPID" --filter "TransientKeyboardSurfaceAtomTests|PaneTabViewControllerGlobalShortcutRoutingTests"
```

Expected: FAIL with missing transient cases and policy helpers.

- [ ] **Step 4: Add transient kinds**

Update `Sources/AgentStudio/Core/Models/TransientKeyboardSurface.swift`:

```swift
enum TransientKeyboardSurfaceKind: Equatable, Sendable {
    case tabRename(tabId: UUID)
    case arrangementPanel(tabId: UUID)
    case arrangementRename(tabId: UUID, arrangementId: UUID)
    case paneInbox(parentPaneId: UUID)
    case editorChooser(paneId: UUID)
}
```

- [ ] **Step 5: Update shortcut policy**

Replace the top of `Sources/AgentStudio/App/Commands/AppShortcutDispatchPolicy.swift` with:

```swift
@MainActor
enum AppShortcutDispatchPolicy {
    static func shouldRouteAppOwnedKeyEvent(context: KeyboardRoutingContext) -> Bool {
        switch context.activeSurface {
        case .commandBar:
            return false
        case .transient(let surface):
            return shouldDispatchFromTransientSurface(surface: surface)
        case .stable:
            return true
        }
    }

    static func shouldDispatchGlobalShortcut(
        _ shortcut: AppShortcut,
        context: KeyboardRoutingContext
    ) -> Bool {
        if isCommandBarActivationShortcut(shortcut) {
            return context.stableOwner != .otherWindow
        }

        switch context.activeSurface {
        case .commandBar:
            return false
        case .transient(let surface):
            guard shouldDispatchFromTransientSurface(surface: surface) else { return false }
            return shouldDispatchGlobalShortcut(shortcut, keyboardOwner: context.stableOwner)
        case .stable(let owner):
            return shouldDispatchGlobalShortcut(shortcut, keyboardOwner: owner)
        }
    }

    static func isCommandBarActivationShortcut(_ shortcut: AppShortcut) -> Bool {
        switch shortcut {
        case .newTab, .showCommandBarEverything, .showCommandBarCommands, .showCommandBarPanes:
            return true
        case .closeTab, .undoCloseTab, .nextTab, .prevTab, .cycleArrangement, .addDrawerPane,
            .toggleDrawer, .scrollToBottom, .openPaneLocationInBookmarkedEditor,
            .openPaneLocationInFinder, .openPaneLocationInEditorMenu, .toggleManagementLayer,
            .toggleSidebar, .filterSidebar, .showInboxNotifications, .showPaneInboxNotifications,
            .showWorktreeSidebar, .newWindow, .closeWindow, .selectTab1, .selectTab2, .selectTab3,
            .selectTab4, .selectTab5, .selectTab6, .selectTab7, .selectTab8, .selectTab9,
            .focusPane1, .focusPane2, .focusPane3, .focusPane4, .focusPane5, .focusPane6,
            .focusPane7, .focusPane8, .focusPane9, .focusDrawerPane1, .focusDrawerPane2,
            .focusDrawerPane3, .focusDrawerPane4, .focusDrawerPane5, .focusDrawerPane6,
            .focusDrawerPane7, .focusDrawerPane8, .focusDrawerPane9, .managementLayerFocusLeft,
            .managementLayerFocusRight, .managementLayerEnterDrawer, .managementLayerExitDrawer,
            .managementLayerOpenDrawer, .managementLayerCreateTerminal, .managementLayerCreateBrowser,
            .managementLayerExit:
            return false
        }
    }
```

Replace `shouldDispatchFromTransientSurface(surface:)` with:

```swift
    private static func shouldDispatchFromTransientSurface(surface: TransientKeyboardSurfaceKind) -> Bool {
        switch surface {
        case .tabRename, .arrangementPanel, .arrangementRename, .paneInbox, .editorChooser:
            return false
        }
    }
```

Keep `shouldDispatchGlobalShortcut(_:keyboardOwner:)`, `shouldDispatchFromMainWindowChain`, and `shouldDispatchFromSidebar`, updating any old `context.keyboardOwner` references to `context.stableOwner`.

- [ ] **Step 6: Run tests**

Run:

```bash
swift test --build-path ".build-agent-$PPID" --filter "TransientKeyboardSurfaceAtomTests|PaneTabViewControllerGlobalShortcutRoutingTests"
```

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add Sources/AgentStudio/Core/Models/TransientKeyboardSurface.swift \
  Sources/AgentStudio/App/Commands/AppShortcutDispatchPolicy.swift \
  Tests/AgentStudioTests/Core/State/MainActor/Atoms/TransientKeyboardSurfaceAtomTests.swift \
  Tests/AgentStudioTests/App/PaneTabViewControllerGlobalShortcutRoutingTests.swift
git commit -m "$(cat <<'MSG'
refactor: expand keyboard surface shortcut policy

Co-authored-by: Codex <noreply@openai.com>
MSG
)"
```

---

### Task 4: Publish Command Bar Surface Lifecycle

**Files:**
- Modify: `Sources/AgentStudio/Features/CommandBar/CommandBarPanelController.swift`
- Modify: `Sources/AgentStudio/App/Boot/AppDelegate.swift`
- Test: `Tests/AgentStudioTests/Features/CommandBar/CommandBarPanelControllerTests.swift`

- [ ] **Step 1: Write failing lifecycle tests**

Append these tests to `Tests/AgentStudioTests/Features/CommandBar/CommandBarPanelControllerTests.swift`:

```swift
    @Test
    func test_show_publishesCommandBarSurfaceScope() {
        let commandBarSurface = CommandBarSurfaceAtom()
        let controller = CommandBarPanelController(
            store: WorkspaceStore(),
            repoCache: RepoCacheAtom(),
            dispatcher: .shared,
            commandBarSurface: commandBarSurface
        )

        controller.show(prefix: ">", parentWindow: window)

        #expect(commandBarSurface.activeScope == .commands)
    }

    @Test
    func test_switchPrefix_updatesCommandBarSurfaceScope() {
        let commandBarSurface = CommandBarSurfaceAtom()
        let controller = CommandBarPanelController(
            store: WorkspaceStore(),
            repoCache: RepoCacheAtom(),
            dispatcher: .shared,
            commandBarSurface: commandBarSurface
        )

        controller.show(prefix: ">", parentWindow: window)
        controller.show(prefix: "$", parentWindow: window)

        #expect(commandBarSurface.activeScope == .panes)
    }

    @Test
    func test_dismiss_clearsCommandBarSurfaceScope() {
        let commandBarSurface = CommandBarSurfaceAtom()
        let controller = CommandBarPanelController(
            store: WorkspaceStore(),
            repoCache: RepoCacheAtom(),
            dispatcher: .shared,
            commandBarSurface: commandBarSurface
        )
        controller.show(parentWindow: window)

        controller.dismiss()

        #expect(commandBarSurface.activeScope == nil)
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run:

```bash
swift test --build-path ".build-agent-$PPID" --filter "CommandBarPanelControllerTests"
```

Expected: FAIL because `commandBarSurface` is not accepted by the controller.

- [ ] **Step 3: Add controller dependency**

In `Sources/AgentStudio/Features/CommandBar/CommandBarPanelController.swift`, add the property after `notificationInboxCommands`:

```swift
    private let commandBarSurface: CommandBarSurfaceAtom
```

Update the initializer:

```swift
    init(
        store: WorkspaceStore,
        repoCache: RepoCacheAtom,
        dispatcher: CommandDispatcher,
        notificationInboxCommands: InboxNotificationCommands? = nil,
        commandBarSurface: CommandBarSurfaceAtom = CommandBarSurfaceAtom()
    ) {
        self.store = store
        self.repoCache = repoCache
        self.dispatcher = dispatcher
        self.notificationInboxCommands = notificationInboxCommands
        self.commandBarSurface = commandBarSurface
        state.loadRecents()
    }
```

- [ ] **Step 4: Publish surface on show, prefix switch, and dismiss**

In `show(mode:parentWindow:)`, after every call that updates `state`, publish the current scope:

```swift
                    state.switchPrefix(prefix)
                    commandBarSurface.present(scope: state.currentScope)
```

```swift
                    state.show(defaultScope: defaultRootScope(for: mode))
                    commandBarSurface.present(scope: state.currentScope)
```

```swift
                state.show(prefix: prefix)
                commandBarSurface.present(scope: state.currentScope)
```

```swift
                state.show(defaultScope: defaultRootScope)
                commandBarSurface.present(scope: state.currentScope)
```

In `dismiss()`, after `state.dismiss()` add:

```swift
        commandBarSurface.dismiss()
```

- [ ] **Step 5: Pass app atom into controller**

In `Sources/AgentStudio/App/Boot/AppDelegate.swift`, update the command bar controller construction:

```swift
        commandBarController = CommandBarPanelController(
            store: store,
            repoCache: repoCache,
            dispatcher: .shared,
            notificationInboxCommands: makeInboxNotificationCommands(),
            commandBarSurface: atomStore.commandBarSurface
        )
```

- [ ] **Step 6: Run tests**

Run:

```bash
swift test --build-path ".build-agent-$PPID" --filter "CommandBarPanelControllerTests|CommandBarSurfaceAtomTests"
```

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add Sources/AgentStudio/Features/CommandBar/CommandBarPanelController.swift \
  Sources/AgentStudio/App/Boot/AppDelegate.swift \
  Tests/AgentStudioTests/Features/CommandBar/CommandBarPanelControllerTests.swift
git commit -m "$(cat <<'MSG'
feat: publish command bar as active keyboard surface

Co-authored-by: Codex <noreply@openai.com>
MSG
)"
```

---

### Task 5: Update App-Owned And Terminal Shortcut Ingress

**Files:**
- Modify: `Sources/AgentStudio/App/Panes/PaneTabViewController.swift`
- Modify: `Sources/AgentStudio/App/Lifecycle/ManagementLayerMonitor.swift`
- Modify: `Sources/AgentStudio/Features/Terminal/Ghostty/GhosttySurfaceView+Input.swift`
- Modify: `Sources/AgentStudio/App/Commands/AppShortcut.swift`
- Modify: `Sources/AgentStudio/App/Commands/AppShortcutDispatchPolicy.swift`
- Test: `Tests/AgentStudioTests/App/PaneTabViewControllerGlobalShortcutRoutingTests.swift`
- Test: `Tests/AgentStudioTests/App/ManagementLayerTests.swift`
- Test: `Tests/AgentStudioTests/App/TerminalAppOwnedShortcutPolicyTests.swift`

- [ ] **Step 1: Write failing terminal policy tests**

Create `Tests/AgentStudioTests/App/TerminalAppOwnedShortcutPolicyTests.swift`:

```swift
import Testing

@testable import AgentStudio

@MainActor
@Suite("Terminal app-owned shortcut policy")
struct TerminalAppOwnedShortcutPolicyTests {
    @Test("terminal app-owned shortcuts are blocked by transient surfaces")
    func terminalAppOwnedShortcutsAreBlockedByTransientSurfaces() {
        let context = KeyboardRoutingContext(
            stableOwner: .mainWindowChain,
            activeSurface: .transient(.paneInbox(parentPaneId: UUID())),
            workspaceWindowId: UUID()
        )

        #expect(!AppShortcutDispatchPolicy.shouldDispatchTerminalAppOwnedShortcut(.nextTab, context: context))
        #expect(!AppShortcutDispatchPolicy.shouldDispatchTerminalAppOwnedShortcut(.scrollToBottom, context: context))
    }

    @Test("command bar activation is allowed through terminal transient surfaces")
    func commandBarActivationIsAllowedThroughTerminalTransientSurfaces() {
        let context = KeyboardRoutingContext(
            stableOwner: .mainWindowChain,
            activeSurface: .transient(.editorChooser(paneId: UUID())),
            workspaceWindowId: UUID()
        )

        #expect(AppShortcut.newTab.spec.contexts.contains(.terminalAppOwned))
        #expect(AppShortcut.newTab.command == .showCommandBarRepos)
        #expect(AppShortcutDispatchPolicy.shouldDispatchTerminalAppOwnedShortcut(.showCommandBarEverything, context: context))
        #expect(AppShortcutDispatchPolicy.shouldDispatchTerminalAppOwnedShortcut(.newTab, context: context))
    }

    @Test("terminal app-owned shortcuts are blocked when command bar owns keyboard")
    func terminalAppOwnedShortcutsAreBlockedWhenCommandBarOwnsKeyboard() {
        let context = KeyboardRoutingContext(
            stableOwner: .mainWindowChain,
            activeSurface: .commandBar(scope: .everything),
            workspaceWindowId: UUID()
        )

        #expect(!AppShortcutDispatchPolicy.shouldDispatchTerminalAppOwnedShortcut(.nextTab, context: context))
        #expect(AppShortcutDispatchPolicy.shouldDispatchTerminalAppOwnedShortcut(.showCommandBarEverything, context: context))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run:

```bash
swift test --build-path ".build-agent-$PPID" --filter "TerminalAppOwnedShortcutPolicyTests"
```

Expected: FAIL because `shouldDispatchTerminalAppOwnedShortcut` does not exist and `.newTab` has not yet been added to `.terminalAppOwned`.

- [ ] **Step 3: Make `⌘T` repo command-bar activation terminal-owned**

In `Sources/AgentStudio/App/Commands/AppShortcut.swift`, update `.newTab`:

```swift
        case .newTab:
            return .init(
                trigger: .init(key: .character(.t), modifiers: [.command]),
                contexts: [.global, .terminalAppOwned]
            )
```

This is intentionally named `.newTab` at the shortcut layer because the existing command mapping routes it to `AppCommand.showCommandBarRepos`:

```swift
        case .newTab:
            return .showCommandBarRepos
```

- [ ] **Step 4: Add terminal app-owned policy**

Add this method to `Sources/AgentStudio/App/Commands/AppShortcutDispatchPolicy.swift`:

```swift
    static func shouldDispatchTerminalAppOwnedShortcut(
        _ shortcut: AppShortcut,
        context: KeyboardRoutingContext
    ) -> Bool {
        if isCommandBarActivationShortcut(shortcut) {
            return context.stableOwner != .otherWindow
        }

        switch context.activeSurface {
        case .commandBar:
            return false
        case .transient(let surface):
            guard shouldDispatchFromTransientSurface(surface: surface) else { return false }
            return shortcut.spec.contexts.contains(.terminalAppOwned)
        case .stable(let owner):
            switch owner {
            case .mainWindowChain, .managementLayer:
                return shortcut.spec.contexts.contains(.terminalAppOwned)
            case .sidebar, .otherWindow:
                return false
            }
        }
    }
```

- [ ] **Step 5: Update context call sites**

Update every `KeyboardRoutingContext.current(...)` call to pass `commandBarSurface: atom(\.commandBarSurface)`.

In `Sources/AgentStudio/App/Panes/PaneTabViewController.swift`:

```swift
        let keyboardContext = KeyboardRoutingContext.current(
            windowLifecycle: atom(\.windowLifecycle),
            managementLayer: atom(\.managementLayer),
            uiState: atom(\.uiState),
            commandBarSurface: atom(\.commandBarSurface),
            transientKeyboardSurface: atom(\.transientKeyboardSurface),
            workspaceWindowId: workspaceWindowId
        )
```

In `Sources/AgentStudio/App/Lifecycle/ManagementLayerMonitor.swift`:

```swift
        let keyboardContext = KeyboardRoutingContext.current(
            windowLifecycle: windowLifecycle,
            managementLayer: managementLayer,
            uiState: atom(\.uiState),
            commandBarSurface: atom(\.commandBarSurface),
            transientKeyboardSurface: transientKeyboardSurface
        )
```

- [ ] **Step 6: Reserve command-bar activation in pane key routing**

In `Sources/AgentStudio/App/Panes/PaneTabViewController.swift`, inside `handleAppOwnedKeyEvent`, resolve the global shortcut once immediately after `trigger` is decoded:

```swift
        let globalShortcut = ShortcutDecoder.shortcut(for: trigger, in: .global)
```

After `keyboardContext` is built and before `shouldRouteAppOwnedKeyEvent`, add:

```swift
        if let shortcut = globalShortcut,
            AppShortcutDispatchPolicy.isCommandBarActivationShortcut(shortcut)
        {
            guard
                AppShortcutDispatchPolicy.shouldDispatchGlobalShortcut(
                    shortcut,
                    context: keyboardContext
                ),
                CommandDispatcher.shared.canDispatch(shortcut.command)
            else {
                return false
            }
            CommandDispatcher.shared.dispatch(shortcut.command)
            return true
        }
```

Replace the later global shortcut branch to reuse the same decoded value:

```swift
        if let shortcut = globalShortcut {
            guard
                AppShortcutDispatchPolicy.shouldDispatchGlobalShortcut(
                    shortcut,
                    context: keyboardContext
                )
            else {
                return false
            }
            guard CommandDispatcher.shared.canDispatch(shortcut.command) else {
                return false
            }
            CommandDispatcher.shared.dispatch(shortcut.command)
            return true
        }
```

- [ ] **Step 7: Gate Ghostty terminal app-owned shortcuts**

In `Sources/AgentStudio/Features/Terminal/Ghostty/GhosttySurfaceView+Input.swift`, replace the dispatch branch at lines 69-78 with:

```swift
        if let trigger = ShortcutDecoder.decode(event: event),
            let shortcut = ShortcutDecoder.shortcut(for: trigger, in: .terminalAppOwned),
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
                return false
            }
            CommandDispatcher.shared.dispatch(shortcut.command)
            return true
        }
```

- [ ] **Step 8: Run focused routing tests**

Run:

```bash
swift test --build-path ".build-agent-$PPID" --filter "PaneTabViewControllerGlobalShortcutRoutingTests|ManagementLayerTests|TerminalAppOwnedShortcutPolicyTests|ShortcutCatalogTests|GhosttySurfaceShortcutTests"
```

Expected: PASS.

- [ ] **Step 9: Commit**

```bash
git add Sources/AgentStudio/App/Panes/PaneTabViewController.swift \
  Sources/AgentStudio/App/Lifecycle/ManagementLayerMonitor.swift \
  Sources/AgentStudio/Features/Terminal/Ghostty/GhosttySurfaceView+Input.swift \
  Sources/AgentStudio/App/Commands/AppShortcut.swift \
  Sources/AgentStudio/App/Commands/AppShortcutDispatchPolicy.swift \
  Tests/AgentStudioTests/App/PaneTabViewControllerGlobalShortcutRoutingTests.swift \
  Tests/AgentStudioTests/App/ManagementLayerTests.swift \
  Tests/AgentStudioTests/App/TerminalAppOwnedShortcutPolicyTests.swift
git commit -m "$(cat <<'MSG'
fix: route app-owned shortcuts through active surface policy

Co-authored-by: Codex <noreply@openai.com>
MSG
)"
```

---

### Task 6: Register Pane-Local Transient Surfaces

**Files:**
- Create: `Sources/AgentStudio/Core/Views/TransientKeyboardSurfaceRegistrationModifier.swift`
- Modify: `Sources/AgentStudio/Core/Views/Panes/ArrangementPanel.swift`
- Modify: `Sources/AgentStudio/Features/InboxNotification/Views/PaneInboxNotificationPopover.swift`
- Modify: `Sources/AgentStudio/App/Panes/DrawerEditorChooser/DrawerEditorChooserFactory.swift`
- Test: `Tests/AgentStudioTests/App/ManagementLayerTests.swift`

- [ ] **Step 1: Write failing management pass-through tests**

Append this helper and tests to `Tests/AgentStudioTests/App/ManagementLayerTests.swift`:

```swift
    private func expectManagementPassThrough(
        for transientSurface: TransientKeyboardSurfaceKind,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        withTestAtomRegistry { atoms in
            let monitor = makeMonitor()
            let workspaceWindowId = UUID()
            atoms.windowLifecycle.recordWindowRegistered(workspaceWindowId)
            atoms.windowLifecycle.recordWindowBecameKey(workspaceWindowId)
            _ = atoms.transientKeyboardSurface.present(
                transientSurface,
                workspaceWindowId: workspaceWindowId
            )

            let decision = monitor.keyDownDecision(
                keyCode: 35,
                modifierFlags: [],
                charactersIgnoringModifiers: "p"
            )

            #expect(decision == .passThrough, sourceLocation: sourceLocation)
        }
    }

    @Test("management layer passes through while arrangement panel owns keyboard")
    func test_managementLayer_keyPolicy_arrangementPanelPassesThrough() async {
        expectManagementPassThrough(for: .arrangementPanel(tabId: UUID()))
    }

    @Test("management layer passes through while arrangement rename owns keyboard")
    func test_managementLayer_keyPolicy_arrangementRenamePassesThrough() async {
        expectManagementPassThrough(for: .arrangementRename(tabId: UUID(), arrangementId: UUID()))
    }

    @Test("management layer passes through while pane inbox owns keyboard")
    func test_managementLayer_keyPolicy_paneInboxPassesThrough() async {
        expectManagementPassThrough(for: .paneInbox(parentPaneId: UUID()))
    }

    @Test("management layer passes through while editor chooser owns keyboard")
    func test_managementLayer_keyPolicy_editorChooserPassesThrough() async {
        expectManagementPassThrough(for: .editorChooser(paneId: UUID()))
    }
```

- [ ] **Step 2: Create registration modifier**

Create `Sources/AgentStudio/Core/Views/TransientKeyboardSurfaceRegistrationModifier.swift`:

```swift
import SwiftUI

struct TransientKeyboardSurfaceRegistrationModifier: ViewModifier {
    let kind: TransientKeyboardSurfaceKind
    let workspaceWindowId: UUID?

    @State private var token: TransientKeyboardSurfaceToken?

    func body(content: Content) -> some View {
        content
            .onAppear {
                register(kind)
            }
            .onDisappear {
                dismiss()
            }
            .onChange(of: kind) { _, newKind in
                // SwiftUI delivers this synchronously on the main actor. Keep the
                // old token alive until the new kind is known, then replace it
                // within the same UI update so no user keystroke can interleave.
                dismiss()
                register(newKind)
            }
    }

    private func register(_ kind: TransientKeyboardSurfaceKind) {
        guard token == nil else { return }
        let resolvedWindowId = workspaceWindowId
            ?? atom(\.windowLifecycle).focusedWindowId
            ?? atom(\.windowLifecycle).keyWindowId
        // A transient surface is workspace-window scoped. If no workspace
        // window has been registered yet, there is no safe owner to suppress.
        guard let resolvedWindowId else { return }
        token = atom(\.transientKeyboardSurface).present(kind, workspaceWindowId: resolvedWindowId)
    }

    private func dismiss() {
        guard let token else { return }
        atom(\.transientKeyboardSurface).dismiss(token)
        self.token = nil
    }
}

extension View {
    func transientKeyboardSurface(
        _ kind: TransientKeyboardSurfaceKind,
        workspaceWindowId: UUID? = nil
    ) -> some View {
        modifier(
            TransientKeyboardSurfaceRegistrationModifier(
                kind: kind,
                workspaceWindowId: workspaceWindowId
            )
        )
    }
}
```

- [ ] **Step 3: Register arrangement panel and rename**

In `Sources/AgentStudio/Core/Views/Panes/ArrangementPanel.swift`, add:

```swift
    private var transientSurfaceKind: TransientKeyboardSurfaceKind {
        if let editingArrangementId = inlineRenameState.editingArrangementId {
            return .arrangementRename(tabId: tabId, arrangementId: editingArrangementId)
        }
        return .arrangementPanel(tabId: tabId)
    }
```

Add this modifier to the root `VStack` chain after `.frame(...)`:

```swift
        .transientKeyboardSurface(transientSurfaceKind)
```

- [ ] **Step 4: Register pane inbox popover**

In `Sources/AgentStudio/Features/InboxNotification/Views/PaneInboxNotificationPopover.swift`, add this modifier to the root `VStack` chain after `.frame(...)`:

```swift
        .transientKeyboardSurface(.paneInbox(parentPaneId: parentPaneId))
```

- [ ] **Step 5: Register editor chooser popover**

In `Sources/AgentStudio/App/Panes/DrawerEditorChooser/DrawerEditorChooserFactory.swift`, add this modifier to the `EditorChooserPopover(...)` view:

```swift
                .transientKeyboardSurface(.editorChooser(paneId: paneId))
```

- [ ] **Step 6: Run tests**

Run:

```bash
swift test --build-path ".build-agent-$PPID" --filter "ManagementLayerTests|TransientKeyboardSurfaceAtomTests|KeyboardRoutingContextSurfaceTests"
```

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add Sources/AgentStudio/Core/Views/TransientKeyboardSurfaceRegistrationModifier.swift \
  Sources/AgentStudio/Core/Views/Panes/ArrangementPanel.swift \
  Sources/AgentStudio/Features/InboxNotification/Views/PaneInboxNotificationPopover.swift \
  Sources/AgentStudio/App/Panes/DrawerEditorChooser/DrawerEditorChooserFactory.swift \
  Tests/AgentStudioTests/App/ManagementLayerTests.swift
git commit -m "$(cat <<'MSG'
feat: register pane-local keyboard surfaces

Co-authored-by: Codex <noreply@openai.com>
MSG
)"
```

---

### Task 7: Make Command Bar Activation Commands Visible

**Files:**
- Modify: `Sources/AgentStudio/App/Commands/AppCommand+Catalog.swift`
- Modify: `Tests/AgentStudioTests/Features/CommandBar/CommandBarDataSourceTests.swift`

- [ ] **Step 1: Write failing visibility test**

In `Tests/AgentStudioTests/Features/CommandBar/CommandBarDataSourceTests.swift`, replace the current assertions that command-bar commands are absent with:

```swift
        #expect(ids.contains("cmd-showCommandBarEverything"))
        #expect(ids.contains("cmd-showCommandBarCommands"))
        #expect(ids.contains("cmd-showCommandBarPanes"))
        #expect(ids.contains("cmd-showCommandBarRepos"))
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
swift test --build-path ".build-agent-$PPID" --filter "CommandBarDataSourceTests"
```

Expected: FAIL because command-bar activation commands are hidden.

- [ ] **Step 3: Unhide command-bar activation commands**

In `Sources/AgentStudio/App/Commands/AppCommand+Catalog.swift`, remove `isHiddenInCommandBar: true` from the definitions for:

```swift
case .showCommandBarEverything
case .showCommandBarCommands
case .showCommandBarPanes
case .showCommandBarRepos
```

Keep labels, icons, shortcuts, and group names unchanged.

- [ ] **Step 4: Run command bar data source tests**

Run:

```bash
swift test --build-path ".build-agent-$PPID" --filter "CommandBarDataSourceTests|ShortcutCatalogTests|AppCommandTests"
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/AgentStudio/App/Commands/AppCommand+Catalog.swift \
  Tests/AgentStudioTests/Features/CommandBar/CommandBarDataSourceTests.swift
git commit -m "$(cat <<'MSG'
feat: show command bar activation commands in command bar

Co-authored-by: Codex <noreply@openai.com>
MSG
)"
```

---

### Task 8: Document Surface Contract

**Files:**
- Modify: `docs/architecture/commands_and_shortcuts.md`

- [ ] **Step 1: Add keyboard surface section**

Add this section to `docs/architecture/commands_and_shortcuts.md`:

```markdown
## Keyboard Surface Contract

Keyboard interpretation resolves in this precedence order:

1. `ActiveKeyboardSurface.commandBar(scope:)`
2. `ActiveKeyboardSurface.transient(kind:)`
3. `ActiveKeyboardSurface.stable(owner:)`

Stable owners are long-lived focus regions:

- `.mainWindowChain`
- `.managementLayer`
- `.sidebar(.repos)`
- `.sidebar(.inbox)`
- `.otherWindow`

Command bar is a privileged overlay surface. While active, it owns keyboard
interpretation through its AppKit panel and local command-bar router. Its
activation shortcuts remain available from workspace-owned surfaces even when a
pane-local transient surface is active.

The `⌘T` repo command-bar activation is named `AppShortcut.newTab` at the
shortcut layer but dispatches `AppCommand.showCommandBarRepos`. It belongs in
both `.global` and `.terminalAppOwned` contexts so a focused terminal pane can
decode it directly rather than relying on AppKit main-menu fallback.

Transient surfaces are temporary pane-local keyboard islands:

- `.tabRename(tabId:)`
- `.arrangementPanel(tabId:)`
- `.arrangementRename(tabId:arrangementId:)`
- `.paneInbox(parentPaneId:)`
- `.editorChooser(paneId:)`

Transient surfaces suppress app/global/management shortcuts while their local
responder handles local keys such as Return, Escape, arrows, and number
selection.

This suppression intentionally includes destructive global shortcuts such as
`closeWindow`. When a transient popover or editor is open, local cancellation
or close behavior belongs to that responder; the workspace window should not
close from an app-level shortcut underneath it.

Repo sidebar and inbox sidebar are separate stable keyboard surfaces. They are
tested by setting sidebar visibility, selected surface, and sidebar focus; they
do not require a shortcut that creates the surface.
```

- [ ] **Step 2: Run placeholder scan**

Run:

```bash
rg -n "T[B]D|T[O]DO|implement[ ]later|fill[ ]in[ ]details|Similar[ ]to[ ]Task" docs/architecture/commands_and_shortcuts.md docs/superpowers/specs/2026-05-22-keyboard-surface-system.md docs/superpowers/plans/2026-05-22-keyboard-surface-system.md
```

Expected: no output.

- [ ] **Step 3: Commit**

```bash
git add docs/architecture/commands_and_shortcuts.md \
  docs/superpowers/specs/2026-05-22-keyboard-surface-system.md \
  docs/superpowers/plans/2026-05-22-keyboard-surface-system.md
git commit -m "$(cat <<'MSG'
docs: define keyboard surface system

Co-authored-by: Codex <noreply@openai.com>
MSG
)"
```

---

### Task 9: Full Verification

**Files:**
- No source changes.

- [ ] **Step 1: Run focused surface and shortcut tests**

Run:

```bash
swift test --build-path ".build-agent-$PPID" --filter "CommandBarSurfaceAtomTests|KeyboardRoutingContextSurfaceTests|TransientKeyboardSurfaceAtomTests|PaneTabViewControllerGlobalShortcutRoutingTests|ManagementLayerTests|TerminalAppOwnedShortcutPolicyTests|CommandBarPanelControllerTests|CommandBarDataSourceTests|ShortcutCatalogTests|GhosttySurfaceShortcutTests|KeyboardOwner"
```

Expected: PASS.

- [ ] **Step 2: Run full test suite**

Run:

```bash
mise run test
```

Expected: PASS with all Swift Testing suites complete.

- [ ] **Step 3: Run lint**

Run:

```bash
mise run lint
```

Expected: PASS with zero SwiftLint violations and passing boundary checks.

- [ ] **Step 4: Inspect working tree**

Run:

```bash
git status --short --branch
```

Expected: clean branch ahead of `origin/pane-shortcuts` by the implementation commits, or clean after push.

- [ ] **Step 5: Push**

Run:

```bash
git push
```

Expected: branch updates successfully.

---

## Self-Review

- Spec coverage:
  - Repo sidebar and inbox sidebar remain separate stable surfaces.
  - Command bar is modeled as a first-class active surface with top precedence.
  - Command bar activation remains available through transient surfaces.
  - `AppShortcut.newTab` is explicitly documented as the `⌘T` binding for `AppCommand.showCommandBarRepos`.
  - `AppShortcut.newTab` gains `.terminalAppOwned` so terminal-host routing can decode repo command-bar activation directly.
  - Command bar activation commands become visible in command-bar results.
  - Arrangement panel is modeled as transient because it will own shortcuts.
  - Pane inbox and editor chooser selectable popovers are modeled as transient surfaces.
  - Terminal app-owned shortcut dispatch no longer bypasses surface policy.
- Placeholder scan:
  - This plan contains no banned placeholder phrases.
- Type consistency:
  - `CommandBarScope`, `CommandBarSurfaceAtom`, `ActiveKeyboardSurface`, and `KeyboardRoutingContext.current(...)` signatures are consistent across tasks.
  - `TransientKeyboardSurfaceKind` cases used in tests match the enum changes.
  - `AppShortcutDispatchPolicy.isCommandBarActivationShortcut` is used by policy, app-owned routing, terminal-app-owned routing, and tests.
