# Keyboard Surface System Spec

**Date:** 2026-05-22
**Scope:** `agent-studio.pane-shortcuts`
**Status:** Target design for the next implementation slice.

## Goal

Make keyboard ownership explicit across stable app surfaces, the command bar overlay, and pane-local transient surfaces.

## Grounding In The Current System

The current code already has the core pieces:

- `KeyboardOwner` names stable ownership for `.otherWindow`, `.managementLayer`, `.sidebar(.repos)`, `.sidebar(.inbox)`, and `.mainWindowChain`.
- `TransientKeyboardSurfaceAtom` is a window-scoped stack, currently only used for `.tabRename`.
- `AppShortcutDispatchPolicy` decides which app shortcuts survive the current owner.
- `CommandBarPanel` is already an `NSPanel` that owns `performKeyEquivalent` while active.
- `CommandBarState` already knows `isVisible` and `activeScope`.

The earlier interaction model also separates command bar from sidebars correctly: command bar is a key-window overlay, sidebars are focus-scoped stable surfaces, and management layer is the only true global layer.

The architecture doc keeps command identity, shortcut binding, catalog metadata, and presentation metadata as separate layers. This surface system does not replace those layers. It adds a typed policy read model that answers one question before dispatch: which surface owns keyboard interpretation right now?

## Current Policy Validation

The current policy shape is sound and should be kept:

- `AppCommand` remains the dispatch identity.
- `AppShortcut` remains the binding plus context declaration.
- `AppCommand+Catalog` remains the command bar metadata source.
- `CommandDispatcher` remains the execution path.
- `AppShortcutDispatchPolicy` remains the centralized allow/block decision for app-owned shortcut routing.

The gap is not the command model. The gap is surface resolution:

- command bar activity is currently known by `CommandBarPanelController` and `CommandBarState`, but not by `KeyboardRoutingContext`
- transient surface state blocks all app/global dispatch, including command bar activation
- terminal app-owned ingress dispatches shortcuts directly and must consult the same policy
- command bar activation commands are currently hidden in command bar results, but the target UX requires them to be visible

## Policy Rules

The implementation must preserve these rules:

- Command bar activation is reserved and workspace-wide. It can open from management layer, main window chain, repo sidebar, inbox sidebar, and pane-local transients.
- Command bar activation is still blocked for `otherWindow`; another app or unrelated window must not be stolen from.
- `AppShortcut.newTab` is the `⌘T` binding for `AppCommand.showCommandBarRepos`, not a tab-creation command. Its contexts must include `.terminalAppOwned` so terminal-host routing can decode it directly.
- When command bar is active, the command bar panel owns keyboard interpretation and non-command-bar workspace shortcuts do not dispatch through pane/global paths.
- Transient pane-local surfaces suppress app/global/management shortcuts, but local AppKit or SwiftUI responders still handle their local keys.
- Repo sidebar and inbox sidebar are stable focus owners. They do not become transient surfaces.
- Arrangement panel, arrangement rename, pane inbox popover, and editor chooser are transient because they are temporary keyboard islands attached to an existing stable owner.
- While a transient surface is active, global destructive workspace shortcuts such as `closeWindow` are intentionally blocked. The local responder may close or cancel the transient surface; the app-level shortcut must not close the workspace window from underneath it.

## Surface Taxonomy

### Stable Keyboard Owners

Stable owners are long-lived focus regions:

- `KeyboardOwner.mainWindowChain`
- `KeyboardOwner.managementLayer`
- `KeyboardOwner.sidebar(.repos)`
- `KeyboardOwner.sidebar(.inbox)`
- `KeyboardOwner.otherWindow`

Repo sidebar and inbox sidebar are separate surfaces. When either is visible and focused, that sidebar surface owns keyboard interpretation. They do not need a shortcut that creates the surface to be testable as surfaces; tests set sidebar visibility, selected sidebar surface, and sidebar focus state.

### Privileged Overlay Surface

Command bar is a first-class keyboard surface:

- active when its panel is visible and key
- owns typing, arrows, Return, Escape, row shortcuts, and modified Enter
- has top precedence while active
- can be activated from any workspace-owned surface, including while a transient pane surface is active
- is scoped to the workspace window that presented it; an active command bar in one workspace window must not suppress or reclassify shortcuts in another workspace window

Command bar activation commands must remain visible in the command bar command list:

- `showCommandBarEverything`
- `showCommandBarCommands`
- `showCommandBarPanes`
- `showCommandBarRepos`

The `⌘T` alias maps through `AppShortcut.newTab` to `AppCommand.showCommandBarRepos`; it is part of command-bar activation policy despite the legacy shortcut case name. It must be available in both `.global` and `.terminalAppOwned` contexts so a focused terminal pane does not depend on `NSApp.mainMenu` fallback to open the repo command bar.

### Transient Pane-Local Surfaces

Transient surfaces are temporary keyboard islands layered above the stable owner but below command bar:

- `.tabRename(tabId:)`
- `.arrangementPanel(tabId:)`
- `.arrangementRename(tabId:arrangementId:)`
- `.paneInbox(parentPaneId:)`
- `.editorChooser(paneId:)`

They suppress app/global/management shortcuts while their local responder handles local keys such as Return, Escape, arrows, and number selection.

Transient registration is workspace-window scoped. Views that know their owning workspace window must pass that `workspaceWindowId` explicitly; the key/focused-window fallback exists only as a last resort for callers that cannot be threaded yet. A registered transient must keep its original workspace owner across kind changes such as arrangement panel to arrangement rename.

## Precedence

Keyboard policy resolves in this order:

1. `commandBar(scope:)`
2. `transient(kind:)`
3. `stable(owner:)`

Command bar activation is special:

- allowed through transient surfaces
- allowed through management layer, repo sidebar, inbox sidebar, and main window chain
- blocked for `otherWindow`

Once command bar is active, it takes precedence. Non-command-bar shortcuts should not dispatch through workspace app-owned paths while command bar owns keyboard interpretation.

## Type Shape

`CommandBarScope` should move to Core so surface resolution can reference it without making Core depend on the CommandBar feature slice.

```swift
enum CommandBarScope: Equatable, Sendable {
    case everything
    case commands
    case panes
    case repos
    case inbox
}
```

`CommandBarSurfaceAtom` stores command bar visibility/scope for routing, scoped to the workspace window that owns the active panel:

```swift
struct CommandBarSurface: Equatable, Sendable {
    let workspaceWindowId: UUID
    let scope: CommandBarScope
}

@MainActor
@Observable
final class CommandBarSurfaceAtom {
    private(set) var activeSurface: CommandBarSurface?

    var activeScope: CommandBarScope? {
        activeSurface?.scope
    }

    var isActive: Bool {
        activeSurface != nil
    }

    func activeScope(for workspaceWindowId: UUID?) -> CommandBarScope? {
        guard let workspaceWindowId else { return nil }
        guard activeSurface?.workspaceWindowId == workspaceWindowId else { return nil }
        return activeSurface?.scope
    }

    func present(scope: CommandBarScope, workspaceWindowId: UUID) {
        activeSurface = CommandBarSurface(workspaceWindowId: workspaceWindowId, scope: scope)
    }

    func dismiss(workspaceWindowId: UUID? = nil) {
        guard let workspaceWindowId else {
            activeSurface = nil
            return
        }
        guard activeSurface?.workspaceWindowId == workspaceWindowId else { return }
        activeSurface = nil
    }
}
```

`ActiveKeyboardSurface` names the resolved top surface:

```swift
enum ActiveKeyboardSurface: Equatable, Sendable {
    case commandBar(scope: CommandBarScope)
    case transient(TransientKeyboardSurfaceKind)
    case stable(KeyboardOwner)
}
```

`KeyboardRoutingContext` should carry both stable owner and active surface:

```swift
struct KeyboardRoutingContext: Equatable, Sendable {
    let stableOwner: KeyboardOwner
    let activeSurface: ActiveKeyboardSurface
    let workspaceWindowId: UUID?
}
```

Resolution order:

```swift
if let commandBarScope = commandBarSurface.activeScope(for: resolvedWorkspaceWindowId) {
    activeSurface = .commandBar(scope: commandBarScope)
} else if let transient = transientKeyboardSurface.topSurface(for: resolvedWorkspaceWindowId) {
    activeSurface = .transient(transient.kind)
} else {
    activeSurface = .stable(stableOwner)
}
```

## Testing Strategy

Stable surface tests:

- set `WindowLifecycleAtom` to a key workspace window
- set `UIStateAtom.sidebarCollapsed = false`
- set `UIStateAtom.sidebarSurface`
- set `UIStateAtom.sidebarHasFocus = true`
- assert `KeyboardOwner.current(...)`
- assert `AppShortcutDispatchPolicy` allow/block behavior

Command bar surface tests:

- set `CommandBarSurfaceAtom.present(scope:workspaceWindowId:)`
- assert `KeyboardRoutingContext.current(...)` resolves `.commandBar(scope:)`
- assert a command bar in a different workspace window does not affect the current window
- assert command-bar activation shortcuts are allowed
- assert non-command-bar shortcuts are blocked while command bar is active
- assert command-bar activation commands are visible in `CommandBarDataSource`

Transient surface tests:

- register each transient kind in `TransientKeyboardSurfaceAtom`
- assert `KeyboardRoutingContext.current(...)` resolves `.transient(kind)`
- assert SwiftUI transient registration preserves the original workspace window across kind changes
- assert command-bar activation shortcuts are allowed
- assert non-command-bar app/global/management shortcuts are blocked

Terminal app-owned ingress tests:

- prove `Ghostty.SurfaceView` app-owned shortcuts use `AppShortcutDispatchPolicy`
- prove transient surfaces block terminal app-owned shortcuts
- prove command-bar activation shortcuts remain allowed
