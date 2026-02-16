# Phase 2a + 2b Design: Arrangement UI + Drawer UI + Pane Controls

> Agent Studio — Window System Phase 2 Design
> Date: 2026-02-14
> Updated: 2026-02-15 — revised after implementation feedback

## Status

**Revised** — Updated based on live testing and user feedback. Supersedes the original approved design.

## Context

Phase 1 (Foundation) is complete: Pane, PaneContent, PaneArrangement, Drawer, DrawerPane models and WorkspaceStore CRUD are all implemented and tested. Phase 2 adds the UI controls layer on top of the existing model/store layer.

Key revisions from original design:
- Edit mode toggle **stays** — gates pane overlay controls
- Arrangement bar is **always visible** (not hover-triggered)
- Drawer icon bar is **always visible** (not hover-triggered)
- Pane controls (minimize/close, split) are **edit-mode gated**
- Drag handle replaced with a **thick drag bar** across middle of pane

## Core Architecture Principles

**One command system, multiple trigger surfaces.** Every operation dispatches `PaneAction` through `ActionExecutor`. All UI surfaces are entry points to the same pipeline.

**AppKit for structure, SwiftUI for all UI and layouts.** AppKit owns window lifecycle, toolbar, responder chain, and `NSHostingView` bridges. SwiftUI renders everything visual: tab bar, arrangement bar, split layouts, pane controls, drawer.

| AppKit | SwiftUI |
|--------|---------|
| `NSWindow`, `NSToolbar`, `NSViewController` | Tab bar, arrangement bar |
| Responder chain, key handling | Split layout, pane rendering |
| `NSHostingView` / `NSHostingController` bridge | Pane overlay controls, drawer UI |
| Surface management (Ghostty `NSView`) | All visual content and animations |

### Trigger Surface Matrix

| Trigger | Surface | Pattern |
|---|---|---|
| Command bar (Cmd+P) | `CommandBarDataSource` -> `CommandDispatcher` | Existing |
| Keyboard shortcut | Menu item -> `PaneAction` | Existing |
| Right-click context menu | Tab context menu -> `PaneAction` | Existing |
| Arrangement bar | SwiftUI bar below tab bar -> `PaneAction` | **New** |
| Pane management panel | SwiftUI popover from arrangement bar -> `PaneAction` | **New** |
| Pane overlay controls | SwiftUI overlays on pane -> `PaneAction` | **New** |
| Drawer icon bar | SwiftUI bar at pane bottom -> `PaneAction` | **New** |

---

## Edit Mode

### Definition

A window-level toggle that enables pane manipulation controls. When off, panes show clean terminal content with no distractions. When on, hover reveals controls for rearranging, splitting, minimizing, and closing panes.

### State

- Stored in `ManagementModeMonitor.shared` — singleton `ObservableObject` with `@Published var isActive: Bool`
- Observed reactively by all `TerminalPaneLeaf` instances via `@ObservedObject`
- Toggled via toolbar button or keyboard shortcut

### Toolbar Button

- Positioned in `NSToolbar`, left of "Add Repo" as a separate button group
- Icon: `slider.horizontal.3`
- Visual state: highlighted/filled background when active
- Tooltip: "Toggle Edit Mode (⌥⌘A)"

### What Edit Mode Gates

| Control | Visible When | Position |
|---------|-------------|----------|
| Minimize button | editMode + hover + isSplit | Top-left of pane |
| Close button | editMode + hover + isSplit | Top-left of pane (next to minimize) |
| Quarter-moon split button | editMode + hover | Top-right of pane |
| Drag bar | editMode | Center of pane (thick, full-width) |
| Hover border | editMode + hover + isSplit | Pane outline |

### What Is NOT Edit-Mode Gated

| Control | Always Visible When |
|---------|-------------------|
| Collapsed pane bar | Pane is minimized |
| Arrangement bar | Always (below tab bar) |
| Drawer icon bar | Always (bottom of every pane) |
| Drawer panel | Drawer is expanded |

---

## Pane Overlay Controls (Edit Mode)

### Minimize + Close Buttons (Top-Left)

```
┌──[—][✕]────────────────────────────────┐
│                                         │
│            Terminal content              │
│                                         │
└─────────────────────────────────────────┘
```

- **Visibility**: `managementMode.isActive && isHovered && isSplit`
- **Icons**: `minus.circle.fill` (minimize), `xmark.circle.fill` (close)
- **Size**: 16pt, with dark circle background for contrast
- **Actions**: dispatch `.minimizePane` / `.closePane`

### Quarter-Moon Split Button (Top-Right)

```
┌────────────────────────────────────[+]──┐
│                                         │
│            Terminal content              │
│                                         │
└─────────────────────────────────────────┘
```

- **Visibility**: `managementMode.isActive && isHovered`
- **Shape**: Half-rounded pill (flat on right edge, rounded on left)
- **Icon**: `+` (10pt bold)
- **Action**: dispatch `.insertPane(source: .newTerminal, direction: .right)`

### Drag Bar (Center)

```
┌─────────────────────────────────────────┐
│                                         │
│          ═══════════════════            │  ← thick drag bar
│                                         │
└─────────────────────────────────────────┘
```

- **Visibility**: `managementMode.isActive` (always visible in edit mode, not just hover)
- **Shape**: Thick horizontal bar across the middle of the pane
- **Purpose**: Easy grab target for drag-to-rearrange between panes/tabs
- **Interaction**: `NSPanGestureRecognizer` initiates drag session via `Transferable`

---

## Collapsed Pane Bar

When a pane is minimized (via minimize button or arrangement panel), it collapses to a narrow vertical bar.

```
┌──────┐
│  ⊕   │  ← expand button (top)
│  ☰   │  ← hamburger menu (expand, close)
│      │
│  m   │
│  a   │  ← sideways text (bottom-to-top)
│  i   │     .rotationEffect(Angle(degrees: -90))
│  n   │     font: .system(size: 12, weight: .bold)
│      │
└──────┘
```

- **Width**: 30px (horizontal splits) / **Height**: 30px (vertical splits)
- **Always visible**: Not gated on edit mode — the minimized state persists
- **Click body**: Expands the pane (dispatches `.expandPane`)
- **Hamburger menu**: Expand, Close options
- **Styling**: Dark semi-transparent background, subtle border, hover highlight

### Minimize State

- Stored as `minimizedPaneIds: Set<UUID>` on `Tab` (transient, not persisted)
- Surface detached on minimize (`coordinator.detachForViewSwitch`), reattached on expand
- Cannot minimize the last non-minimized pane in a tab
- Focusing a minimized pane auto-expands it
- Closing a pane's sibling auto-expands remaining minimized panes if they'd be alone

---

## Arrangement Bar

### Definition

A persistent bar below the tab bar showing arrangement chips for the active tab. Provides quick switching between arrangements and access to pane management.

### Visual Structure

```
┌─────────────────────────────────────────────────────────────┐
│  [tab1]  [tab2 (active)]  [tab3]  [+]                      │  ← tab bar
├─────────────────────────────────────────────────────────────┤
│  [Default] [coding] [testing]  [+]  [≡]                    │  ← arrangement bar
├─────────────────────────────────────────────────────────────┤
│                                                             │
│                    Terminal content                          │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### Properties

- **Always visible** for ALL tabs (not gated on edit mode or tab type)
- **Position**: Below the tab bar, hosted in `NSHostingView` overlay within TTVC
- **Content**:
  - Arrangement chips — click to switch, right-click for rename/delete
  - [+] button — save current layout as new arrangement
  - [≡] pane management button — opens the pane management panel
- **Active chip**: Highlighted with subtle background
- **"Default"**: Always present, cannot be deleted

### Data Flow

- TTVC observes `WorkspaceStore` changes and refreshes arrangement bar data
- Each chip dispatches `.switchArrangement` via `ActionExecutor`
- [+] dispatches `.createArrangement` with auto-generated name

---

## Pane Management Panel

### Definition

A floating panel that drops down from the arrangement bar's [≡] button. Shows all panes in the active tab with visibility controls and saved arrangements.

### Visual Structure

```
  [≡] button → click → panel slides open
    ┌─────────────────────────┐
    │  Panes:                 │
    │  ● main          [—]   │  ← visible, [—] to minimize
    │  ○ tests         [+]   │  ← minimized, [+] to restore
    │  ● server        [—]   │
    │  ● logs          [—]   │
    │                         │
    │  Saved:                 │
    │  [default] [coding]    │  ← quick-recall chips
    │                         │
    │  [Save] [Save as...]   │
    └─────────────────────────┘
```

### Properties

- **Trigger**: Click the [≡] button in the arrangement bar
- **Position**: Drops down from the arrangement bar (popover or floating panel)
- **Pane list**: Shows all panes with:
  - Visibility indicator: ● visible, ○ minimized
  - Title from `Pane.title`
  - Toggle button: [—] to minimize, [+] to restore
- **Arrangement chips**: Same as arrangement bar, for quick switching within the panel
- **"Default"**: Always present — clicking restores all panes visible
- **Save / Save as**: Create new arrangement from current visible panes + layout
- **Dismiss**: Click-outside or Escape

### Actions

| Action | PaneAction |
|--------|-----------|
| Minimize pane | `.minimizePane(tabId:paneId:)` |
| Expand pane | `.expandPane(tabId:paneId:)` |
| Switch arrangement | `.switchArrangement(tabId:arrangementId:)` |
| Save arrangement | `.createArrangement(tabId:name:paneIds:)` |
| Delete arrangement | `.removeArrangement(tabId:arrangementId:)` |
| Rename arrangement | `.renameArrangement(tabId:arrangementId:name:)` |

---

## Drawer

### Definition

A collapsible panel at the bottom of each pane that holds DrawerPanes. DrawerPanes inherit context from their parent pane and can hold any content type (terminal, webview, code viewer).

### Visual Structure

```
┌─────────────────────────────────┐
│  Pane content                   │
│  (terminal / webview / etc)     │
│                                 │
├─────────────────────────────────┤
│ [dp1] [dp2] [dp3] [+] [▾]     │  ← icon bar (ALWAYS VISIBLE)
│ ┌─────────────────────────────┐ │
│ │ Active drawer pane content  │ │  ← expanded panel (when toggled)
│ │ (terminal / webview / etc)  │ │
│ └─────────────────────────────┘ │
└─────────────────────────────────┘
```

### Icon Bar

- **Always visible** at the bottom of every pane (not hover-gated)
- Shows icons for each drawer pane + [+] to add + [▾] to expand/collapse
- Click icon to switch active drawer pane
- Right-click icon for close

### Expanded Panel

- Slides up from bottom, overlays terminal content (no terminal resize)
- Height: 75% of pane height by default, draggable resize handle, global memory
- Width: full pane width (single pane) or 90% of tab width (split layout)

### Interactions

| Action | Trigger |
|---|---|
| Switch drawer panes | Click different icon in icon bar |
| Collapse drawer | Click active icon again, Escape, or click-outside |
| Close drawer pane | Right-click icon → close, or command bar |
| Add drawer pane | [+] button in icon bar |
| Toggle drawer | Keyboard shortcut or [▾] button |

---

## Command Bar Commands

All arrangement and drawer operations are also available through the command bar:

| Command | Action |
|---------|--------|
| `>Switch arrangement` | List arrangements, select to switch |
| `>Save arrangement as...` | Name input, creates custom from current layout |
| `>Delete arrangement` | List custom arrangements, confirm deletion |
| `>Rename arrangement` | List, then name input |
| `>Add drawer pane` | Creates terminal in focused pane's drawer |
| `>Navigate to drawer pane` | List drawer panes for focused pane |
| `>Toggle drawer` | Expand/collapse for focused pane |
| `>Minimize pane` | Minimize focused pane |
| `>Expand pane` | Expand focused pane |

---

## Backgrounded Pane Lifecycle

When switching arrangements or minimizing panes:

- Ghostty surface detached for resource efficiency (`coordinator.detachForViewSwitch`)
- Terminal state preserved via zmx backend
- When pane becomes visible again: surface reattached seamlessly (`coordinator.reattachForViewSwitch`)
- No content loss during background/foreground transitions

---

## Implementation Status

| Component | Status | Notes |
|-----------|--------|-------|
| `minimizedPaneIds` on Tab | Done | Transient state, excluded from Codable |
| `minimizePane`/`expandPane` in WorkspaceStore | Done | With guards and cleanup |
| PaneAction cases for minimize/expand | Done | Through full pipeline |
| CollapsedPaneBar view | Done | 30px, bold sideways text |
| SplitSubtreeView minimized rendering | Done | HStack/VStack with fixed-width collapsed bars |
| Tab bar [+] always visible | Done | Moves to fixed controls zone when overflowing |
| ArrangementBar view | Done | Chips with switch/save/delete/rename |
| ArrangementPanel view | Done | Pane list with toggles, arrangement chips |
| DrawerOverlay / DrawerIconBar / DrawerPanel | Done | Full drawer UI |
| Quarter-moon split button | Done | Needs edit mode gate |
| **Edit mode toolbar button** | **Needs fix** | Was removed, needs restoration |
| **Pane controls edit mode gate** | **Needs fix** | Currently always-on-hover |
| **Drawer icon bar always visible** | **Needs fix** | Currently hover-gated |
| **Arrangement bar always visible** | **Needs fix** | Currently edit-mode-gated |
| **Drag bar (thick, center)** | **Not started** | Replaces small drag handle icon |
| **Pane control positioning** | **Needs fix** | Move minimize/close to top-left |

---

## Design References

- `docs/architecture/window_system_design.md` — Concept 2 (Arrangement), Concept 3 (Drawer)
- `docs/architecture/app_architecture.md` — AppKit+SwiftUI hybrid patterns
- `docs/guides/style_guide.md` — macOS design conventions
