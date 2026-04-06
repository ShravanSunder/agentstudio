# Command Visibility & WorkspaceFocus Design

## Problem

The command bar shows all 61 commands regardless of workspace state. An empty workspace with no tabs or panes still shows "Add Drawer Pane", "Close Pane", "Equalize Panes", "Focus Pane Down", etc. The current `canDispatch` only checks management mode and a coarse handler chain — it conflates "is this safe to execute?" with "should this appear at all?"

The status strip shows "Terminal" even when no terminal exists because `WorkspaceFocus` (formerly `CommandBarAppContext`) maps `nil` to terminal.

## Root Cause

`PaneTabViewController.canExecute` (line 1149): when `ActionResolver.resolve` returns `nil` for non-pane commands (drawer, arrangement, worktree, etc.), the handler returns `true` unconditionally. These 20+ commands bypass all validation.

## Design

### Two separate questions per command

| Question | Determines | Check | Surface behavior |
|----------|-----------|-------|-----------------|
| **Is it visible?** | Should it appear at all? | `visibleWhen` tags on `CommandDefinition` | Command bar: hidden. Menus: hidden or static. |
| **Is it enabled?** | Can it execute right now? | Existing `canDispatch` chain | Command bar: dimmed. Menus: dimmed. |

A command can be visible but disabled (e.g., "Close Pane" shows when a pane exists but is dimmed because management mode is off). A command that isn't visible never shows.

### `FocusRequirement` — what workspace state a command needs

```swift
enum FocusRequirement: Hashable, CaseIterable, Sendable {
    /// At least one tab exists in the workspace.
    case hasActiveTab
    /// A pane is focused in the active tab.
    case hasActivePane
    /// The active tab has more than one pane in its layout.
    case hasMultiplePanes
    /// The active pane has a drawer (even if collapsed/empty).
    case hasDrawer
    /// The active pane's drawer has at least one child pane.
    case hasDrawerPanes
    /// The workspace has more than one tab.
    case hasMultipleTabs
    /// The active tab has saved arrangements beyond the default.
    case hasArrangements
    /// The active pane is a terminal.
    case paneIsTerminal
    /// The active pane is a webview.
    case paneIsWebview
    /// The active pane is a bridge panel.
    case paneIsBridge
}
```

### `visibleWhen` on `CommandDefinition`

```swift
struct CommandDefinition {
    let command: AppCommand
    var keyBinding: KeyBinding?
    let label: String
    let icon: String?
    let appliesTo: Set<SearchItemType>
    let requiresManagementMode: Bool
    let visibleWhen: Set<FocusRequirement>  // empty = always visible
}
```

### Computing current focus from workspace state

A single function computes the satisfied `FocusRequirement` set from live `WorkspaceStore` state:

```swift
@MainActor
func computeCurrentFocus(store: WorkspaceStore) -> Set<FocusRequirement> {
    var focus: Set<FocusRequirement> = []

    guard let activeTabId = store.activeTabId,
          let tab = store.tab(activeTabId)
    else { return focus }

    focus.insert(.hasActiveTab)

    if store.tabs.count > 1 {
        focus.insert(.hasMultipleTabs)
    }

    if tab.arrangements.count > 1 {
        focus.insert(.hasArrangements)
    }

    if tab.paneIds.count > 1 {
        focus.insert(.hasMultiplePanes)
    }

    guard let activePaneId = tab.activePaneId,
          let pane = store.pane(activePaneId)
    else { return focus }

    focus.insert(.hasActivePane)

    if let drawer = pane.drawer {
        focus.insert(.hasDrawer)
        if !drawer.paneIds.isEmpty {
            focus.insert(.hasDrawerPanes)
        }
    }

    switch pane.content {
    case .terminal: focus.insert(.paneIsTerminal)
    case .webview: focus.insert(.paneIsWebview)
    case .bridgePanel: focus.insert(.paneIsBridge)
    case .codeViewer, .unsupported: break
    }

    return focus
}
```

### Visibility check

```swift
func isCommandVisible(
    _ definition: CommandDefinition,
    currentFocus: Set<FocusRequirement>
) -> Bool {
    definition.visibleWhen.isSubset(of: currentFocus)
}
```

### `WorkspaceFocus` for the status strip

Rename `CommandBarAppContext` to `WorkspaceFocus`. Derive from the same `computeCurrentFocus` result:

```swift
struct WorkspaceFocus {
    enum ContentType {
        case terminal
        case webview
        case bridge
        case codeViewer
        case none       // no active pane — replaces the nil → terminal mapping
    }

    let paneContentType: ContentType

    var label: String {
        switch paneContentType {
        case .terminal: return "Terminal"
        case .webview: return "Webview"
        case .bridge: return "Bridge"
        case .codeViewer: return "Code Viewer"
        case .none: return ""  // empty = hide the context label
        }
    }

    var icon: String {
        switch paneContentType {
        case .terminal: return "terminal"
        case .webview: return "globe"
        case .bridge: return "rectangle.split.2x1"
        case .codeViewer: return "doc.text"
        case .none: return "rectangle.dashed"
        }
    }
}
```

When `paneContentType` is `.none`, the status strip hides the context section entirely (no icon, no label). This fixes the "Terminal when there's no terminal" bug.

---

## Command Requirement Mapping (all 61 commands)

### Always visible (no requirements)

These commands are valid regardless of workspace state:

| Command | Label | Rationale |
|---------|-------|-----------|
| `newTab` | New Tab | Always can create a tab |
| `newFloatingTerminal` | New Floating Terminal | Always can create |
| `openWebview` | Open New Webview Tab | Always can create |
| `addRepo` | Add Repo | Always can add |
| `addFolder` | Add Folder | Always can add |
| `toggleSidebar` | Toggle Sidebar | Always available |
| `filterSidebar` | Filter Sidebar | Always available |
| `toggleManagementMode` | Toggle Management Mode | Always available |
| `undoCloseTab` | Undo Close Tab | Shows always; `canDispatch` handles empty undo stack |

### Requires `[hasActiveTab]`

| Command | Label | Notes |
|---------|-------|-------|
| `closeTab` | Close Tab | Drill-in: pick tab |
| `nextTab` | Next Tab | |
| `prevTab` | Previous Tab | |
| `newTerminalInTab` | New Terminal in Tab | Needs a tab to add to |
| `saveArrangement` | Save Arrangement As... | Saves current tab's panes |
| `equalizePanes` | Equalize Panes | Operates on active tab |

### Requires `[hasActiveTab, hasMultiplePanes]`

| Command | Label | Notes |
|---------|-------|-------|
| `breakUpTab` | Split Tab Into Individuals | Rename from "Break Up Tab" |
| `focusPaneLeft` | Focus Pane Left | |
| `focusPaneRight` | Focus Pane Right | |
| `focusPaneUp` | Focus Pane Up | |
| `focusPaneDown` | Focus Pane Down | |
| `focusNextPane` | Focus Next Pane | |
| `focusPrevPane` | Focus Previous Pane | |

### Requires `[hasActiveTab, hasArrangements]`

| Command | Label | Notes |
|---------|-------|-------|
| `switchArrangement` | Switch Arrangement | Drill-in: pick arrangement |
| `deleteArrangement` | Delete Arrangement | Drill-in: pick arrangement |
| `renameArrangement` | Rename Arrangement | Drill-in: pick arrangement |

### Requires `[hasActivePane]`

| Command | Label | Notes |
|---------|-------|-------|
| `splitRight` | Split Right | |
| `splitLeft` | Split Left | |
| `closePane` | Close Pane | Also requires management mode (existing) |
| `extractPaneToTab` | Extract Pane to Tab | |
| `movePaneToTab` | Move Pane to Tab | Also requires management mode (existing) |
| `minimizePane` | Minimize Pane | |
| `expandPane` | Expand Pane | |
| `addDrawerPane` | Add Drawer Pane | |
| `toggleDrawer` | Toggle Drawer | |

### Requires `[hasActivePane, hasDrawerPanes]`

| Command | Label | Notes |
|---------|-------|-------|
| `navigateDrawerPane` | Navigate to Drawer Pane | Drill-in: pick drawer pane |
| `closeDrawerPane` | Close Drawer Pane | |

### Requires `[hasMultipleTabs]`

| Command | Label | Notes |
|---------|-------|-------|
| (none currently — but `nextTab`/`prevTab` could be here instead of `hasActiveTab` if we want to hide when only 1 tab) | | |

### Worktree commands (always visible in repos scope, context-gated in everything scope)

| Command | Label | Notes |
|---------|-------|-------|
| `openWorktree` | Open Worktree | Drill-in: pick worktree |
| `openWorktreeInPane` | Open Worktree in Pane | Drill-in: pick worktree |
| `openNewTerminalInTab` | Open New Terminal in Tab | Drill-in: pick worktree |
| `removeRepo` | Remove Repo | Drill-in: pick repo |

These are always visible — they create or modify workspace structure and don't depend on current focus. They appear in the worktrees group and repos scope.

### Hidden commands (never in command bar)

Unchanged from current `isHiddenCommand`:

| Command | Why hidden |
|---------|-----------|
| `selectTab` | Internal: used by targeted dispatch only |
| `focusPane` | Internal: used by targeted dispatch only |
| `selectTab1`-`selectTab9` | Keyboard-only (⌘1-⌘9) |
| `quickFind` | Not registered |
| `commandBar` | Not registered |
| `newWindow` | Menu/keyboard only (⌘N) |
| `closeWindow` | Menu/keyboard only (⌘⇧W) |
| `signInGitHub` | Pending OAuth setup |
| `signInGoogle` | Pending OAuth setup |

### Unregistered commands (no CommandDefinition)

| Command | Status |
|---------|--------|
| `toggleSplitZoom` | Not registered but ActionResolver handles it — should be registered |
| `quickFind` | Handled outside CommandDispatcher |
| `commandBar` | Handled outside CommandDispatcher |

**Action items:**
- Register `toggleSplitZoom` with label "Toggle Split Zoom", icon `"arrow.up.left.and.arrow.down.right.magnifyingglass"`, `visibleWhen: [.hasActivePane, .hasMultiplePanes]`.
- `quickFind` and `commandBar` are handled outside CommandDispatcher — no registration needed.

---

## Label Improvements

Some command labels are unclear. Proposed renames:

| Current | Proposed | Rationale |
|---------|----------|-----------|
| Break Up Tab | Split Tab Into Individuals | "Break up" is ambiguous |
| Extract Pane to Tab | Move Pane to New Tab | Clearer action |
| Move Pane to Tab | Move Pane to Existing Tab | Distinguish from "to new tab" |
| New Terminal in Tab | Add Terminal to Tab | Consistent "add" verb |
| Open New Terminal in Tab | Open Terminal in New Tab | "New" modifies tab, not terminal |
| Toggle Management Mode | Manage Workspace | Action-oriented, matches status strip |
| Navigate to Drawer Pane | Switch Drawer Pane | Simpler |

---

## Integration Points

### Command bar

- `CommandBarDataSource.items()` filters by `isCommandVisible` before building items
- `dimmedItemIds` continues using `canDispatch` for enablement
- Hidden commands (`isHiddenCommand`) remain filtered separately — they never show anywhere

### Menus

- `validateMenuItem` / `NSUserInterfaceValidations` can use the same `computeCurrentFocus` + `isCommandVisible` check
- Menus may choose to show-but-dim instead of hide, depending on macOS conventions

### Keyboard shortcuts

- Shortcuts always registered. `canDispatch` gates execution. Visibility doesn't apply to shortcuts — you press ⌘W and either it works or it doesn't.

---

## Files Changed

| File | Change |
|------|--------|
| `Core/Models/AppCommand.swift` → `CommandDefinition` | Add `visibleWhen: Set<FocusRequirement>` field |
| `Core/Models/FocusRequirement.swift` | Create: the enum |
| `Core/Models/WorkspaceFocus.swift` | Create: replaces `CommandBarAppContext`, adds `.none` case |
| `Core/Models/WorkspaceFocusComputer.swift` | Create: `computeCurrentFocus(store:)` function |
| `Features/CommandBar/CommandBarDataSource.swift` | Filter items by visibility |
| `Features/CommandBar/CommandBarItem.swift` | Remove `CommandBarAppContext`, import `WorkspaceFocus` |
| `Features/CommandBar/Views/CommandBarView.swift` | Use `WorkspaceFocus` for status strip |
| `Features/CommandBar/Views/CommandBarStatusStrip.swift` | Update to use `WorkspaceFocus` |
| `App/Commands/AppCommand.swift` → `registerDefaults()` | Add `visibleWhen` to all 55 registered definitions |

---

## Behavior Summary

```
User opens command bar
       │
       ▼
computeCurrentFocus(store:) → Set<FocusRequirement>
       │
       ▼
For each CommandDefinition:
  ├── isHidden? → skip entirely (internal/unregistered)
  ├── isVisible? (visibleWhen ⊆ currentFocus) → no → skip
  ├── isEnabled? (canDispatch) → no → show dimmed
  └── yes → show normal
       │
       ▼
Filter by scope prefix ($, >, #)
       │
       ▼
Filter by search query (fuzzy match)
       │
       ▼
Display grouped results
```
