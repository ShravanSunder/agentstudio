# Phase 2a + 2b Design: Arrangement UI + Drawer UI

> Agent Studio — Window System Phase 2 Design
> Date: 2026-02-14

## Status

**Approved** — Ready for implementation planning.

## Context

Phase 1 (Foundation) is complete: Pane, PaneContent, PaneArrangement, Drawer, DrawerPane models and WorkspaceStore CRUD are all implemented and tested (863 tests passing on `window-system-3`). Phase 2a and 2b are purely UI work on top of the existing model/store layer.

## Core Architecture Principle

**One command system, multiple trigger surfaces.** Every operation dispatches `PaneAction` through `ActionExecutor`. Floating UI, command bar, keyboard shortcuts, and context menus are all entry points to the same pipeline.

**All floating UI is overlay-based** — no permanent chrome, no layout shifts, no terminal resizing. Appears on demand, dismisses easily.

### Trigger Surface Matrix

| Trigger | Surface | Pattern |
|---|---|---|
| Command bar (Cmd+P) | `CommandBarDataSource` -> `CommandDispatcher` | Existing |
| Keyboard shortcut | Menu item -> `PaneAction` | Existing |
| Right-click context menu | Tab context menu -> `PaneAction` | Existing |
| Floating arrangement bar | SwiftUI overlay -> `PaneAction` | **New** |
| Drawer icon bar | SwiftUI overlay -> `PaneAction` | **New** |

---

## Phase 2a: Arrangement UI

### Visual Indicator (permanent, minimal)

When a tab has more than one arrangement, show the arrangement name as a subtle badge/subtitle on the tab in `CustomTabBar`.

- Example: `my-project . coding` — the `. coding` part only appears when a custom arrangement is active
- Hidden when only the default arrangement exists
- Zero extra height in the tab bar

### Floating Arrangement Bar (on demand)

- **Trigger**: Cmd+Opt or mouse hover near tab bar area
- **Position**: Floats below the tab bar, overlays terminal content (does not push content down)
- **Content**: Arrangement chips/pills for the active tab — click to switch
- **Actions**:
  - Click chip to switch arrangement
  - [+] button for "save current as..." flow
  - Right-click chip for delete/rename
- **Dismiss**: Click-outside, Escape, or after switching

### Command Bar Commands

- `>Switch arrangement` — list arrangements for current tab, select to switch
- `>Save arrangement as...` — name input, creates custom from current visible panes + tiling
- `>Delete arrangement` — list custom arrangements, confirm deletion
- `>Rename arrangement` — list, then name input

### Right-Click Context Menu

Arrangement submenu on tab right-click with the same operations as command bar.

### Backgrounded Pane Lifecycle

When switching arrangements, panes not in the new arrangement:

- Ghostty surface detached for resource efficiency
- Terminal state preserved via zmx backend
- When pane becomes visible again: surface reattached seamlessly
- No content loss during background/foreground transitions

---

## Phase 2b: Drawer UI

### Trapezoid Connector (visual anchor)

Each pane has a small trapezoid shape at its bottom edge that visually connects the pane to its drawer controls.

```
+----------------------------------------+
|  Terminal content (parent pane)         |
|                                        |
+----------------------------------------+  <-- pane bottom edge (WIDE end)
 \                                      /
  \        TRAPEZOID BRIDGE            /    <-- small visual connector
   \      (not too large)             /
    +--------------------------------+      <-- NARROW end -> icon bar
     |   [dp1] [dp2] [dp3] [+]      |
     +-------------------------------+
```

- **Wide end**: starts at pane boundary (full pane width)
- **Narrow end**: tapers to the drawer icon bar (centered, smaller)
- **Purpose**: visually communicates "these drawer controls belong to this pane"
- **Size**: small — just a visual bridge, not a content area

### Drawer Icon Bar (on demand)

- **Trigger**: Hover near pane bottom edge or keyboard shortcut
- **Content**: Icons for each drawer pane + [+] button
- **[+] button**: Creates terminal drawer pane immediately, inheriting parent's CWD/worktree
- **Other content types**: Available via command bar or secondary mechanism
- **Dismiss**: Move mouse away, or after interaction

### Expanded Drawer Panel (floating overlay)

When a drawer pane icon is clicked, the drawer content panel appears:

- **Shape**: Rectangular content area with squared-off top, connected to icon bar via trapezoid bridge
- **Behavior**: Slides up from bottom, overlays terminal content (no terminal resize)
- **Height**: 75% of pane height by default. Draggable resize handle at top edge. Global memory (drag once, applies to all panes).
- **Width**:
  - Single pane tab: full pane width
  - Multi-pane tab: 90% of total tab width, floating over neighboring panes
  - Draggable with global memory
- **Icon bar**: Stays visible while drawer is expanded

### Drawer Interactions

| Action | Trigger |
|---|---|
| Switch drawer panes | Click different icon in icon bar |
| Collapse drawer | Click active icon again, Escape, or click-outside |
| Close drawer pane | Right-click icon -> close, or command bar |
| Toggle drawer | Keyboard shortcut |
| Cycle drawer panes | Keyboard shortcut |

### Command Bar Commands

- `>Add drawer pane` — creates terminal in focused pane's drawer
- `>Navigate to drawer pane` — list drawer panes for focused pane
- `>Toggle drawer` — expand/collapse for focused pane

---

## Implementation Order

1. **Phase 2a first** — lower risk, extends existing command bar patterns
2. **Phase 2b second** — changes pane rendering architecture (adds drawer overlay to TerminalPaneLeaf)

---

## Linear Ticket Cleanup

| Action | Ticket | Reason |
|---|---|---|
| Keep | LUNA-314 (Arrangement switching UI) | Consolidated Phase 2a ticket |
| Keep | LUNA-302 (Backgrounded pane lifecycle) | Distinct scope: surface detach/reattach |
| Keep | LUNA-315 (Drawer UI) | Consolidated Phase 2b ticket |
| Archive | LUNA-300 (Custom arrangement CRUD) | Superseded by LUNA-314 |
| Archive | LUNA-301 (Arrangement switching) | Superseded by LUNA-314 |
| Archive | LUNA-303 (Drawer+DrawerPane types) | Already done in Phase B |
| Archive | LUNA-304 (Drawer lifecycle) | Superseded by LUNA-316 (Phase 3b) |
| Archive | LUNA-305 (Drawer UI) | Superseded by LUNA-315 |
| Defer | LUNA-306 (Drawer in dynamic views) | Depends on Phase 2c/3a |

---

## Design References

- `docs/architecture/window_system_design.md` — Concept 2 (Arrangement), Concept 3 (Drawer)
- `docs/architecture/app_architecture.md` — AppKit+SwiftUI hybrid patterns
- `docs/guides/style_guide.md` — macOS design conventions
