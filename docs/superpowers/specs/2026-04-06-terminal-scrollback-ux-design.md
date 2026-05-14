# Terminal Scrollback UX Design Spec

## Problem

Agent Studio now has the deferred Ghostty/runtime event coverage on `main`, but it still does not expose a usable host-side scrollback UX for embedded terminals. We can receive terminal scrollbar and search facts from Ghostty core, yet the host app still mounts `Ghostty.SurfaceView` directly into a plain `NSView`, so there is no native scrollbar UI, no visible scrollback search UI, no scroll-to-bottom affordance, and no host-side cursor handling for the promoted mouse events.

The goal of this work is to add the macOS host-side UI that sits on top of the already-landed libghostty/runtime primitives.

## Current Foundation On Main

This is the key refresh after merging `origin/main`:

- `GhosttyActionRouter` and `GhosttyActionRouter+ObservedActions` already route scrollbar/search/mouse actions into `TerminalRuntime`.
- `GhosttyAdapter` already translates those actions into typed `GhosttyEvent` values.
- `TerminalRuntime` already owns `scrollbarState` and `searchState`.
- `PaneRuntimeEventChannel` already uses the AsyncStream outbound bus continuation.

This design does **not** re-implement that infrastructure. It consumes it.

## Scope

### In Scope

| Feature | Detail |
|---------|--------|
| Always-visible native scrollbar | Agent Studio host-side `NSScrollView` wrapper around embedded terminal surfaces. This is an Agent Studio product choice, not Ghostty parity. |
| Ghostty-owned scroll behavior | Ghostty core remains the ordinary scroll authority for wheel/trackpad scrolling and follow-bottom semantics. |
| No keystroke scroll-to-bottom | Disable Ghostty core auto-scroll on keypress and output using a host-owned config override. |
| Scroll-to-bottom button | Bottom-right floating affordance when scrolled up; icon/badge changes when unread output exists below viewport. |
| Scrollback search | `cmd+f`, `cmd+g`, `shift+cmd+g`, Escape, and host-side visible search overlay for the focused pane. |
| Find menu | Edit > Find menu entries routed through the responder chain. |
| Mouse cursor management | Consume promoted `mouseShape` and `mouseVisibility` events via runtime-owned observable state, then apply `NSCursor` behavior on the surface view. |

### Out of Scope

- Cross-pane search
- Find pasteboard integration
- Search bar dragging/repositioning
- Click-to-move-cursor implementation in core
- Command-finished notification UI
- Respecting Ghostty/macOS `scrollbar = system` behavior in Agent Studio

## libghostty vs Ghostty macOS App

This distinction is important:

- `libghostty` / embedded runtime owns terminal state, scrollback, search thread, binding actions, and runtime action callbacks.
- Ghostty's macOS app adds host-side AppKit/SwiftUI presentation such as `SurfaceScrollView`, search overlay UI, menu integration, and config-to-UI glue.

Agent Studio embeds libghostty directly. It does **not** instantiate Ghostty.app's `SurfaceScrollView` or its search overlay. That means:

1. Scrollbar and search events from Ghostty core are already useful inputs.
2. The visible scrollbar/search UI still has to be built in Agent Studio's host layer.
3. The host should reuse Ghostty's action semantics (`scroll_to_row`, `start_search`, `search:`, `navigate_search:*`, `end_search`) rather than inventing new ones.

## Product Direction

### Scrollbar Visibility

Agent Studio will use an **always-visible** scrollbar.

This is an intentional product divergence from Ghostty.app, which respects `scrollbar = system|never` in its macOS host code. Agent Studio is choosing a more explicit scrollback affordance for AI-heavy workflows.

### Scroll-to-Bottom Behavior

Agent Studio will override Ghostty's default scroll behavior by loading a host-owned config fragment before `ghostty_config_finalize`:

```text
scroll-to-bottom = no-keystroke, no-output
```

This is required because Ghostty core auto-scroll behavior is implemented below the host wrapper. Without this override, typing while reading scrollback would still yank the viewport to bottom even if the host-side scroll wrapper tried not to.

## Architecture

### View Hierarchy

```text
TerminalPaneMountView
├── TerminalSurfaceScrollView
│   └── documentView
│       └── GhosttyMountView
│           └── Ghostty.SurfaceView
├── TerminalSearchOverlayView
├── ScrollToBottomIndicatorView
├── SurfaceErrorOverlayView
└── SurfaceStartupOverlayView
```

### Responsibilities

#### `TerminalSurfaceScrollView`

Owns:
- visible AppKit scrollbar
- row/pixel coordinate conversion
- scrollbar drag / live-scroll -> `scroll_to_row:N`
- host-side synchronization that follows core scrollbar state

Consumes:
- `TerminalRuntime.scrollbarState`
- `TerminalRuntime.cellSize`

#### `TerminalSearchOverlayView`

Owns:
- visible search field
- match count label
- next/previous/close controls

Consumes:
- `TerminalRuntime.searchState`

Sends:
- `start_search`
- `search:<needle>`
- `navigate_search:next`
- `navigate_search:previous`
- `end_search`

#### `ScrollToBottomIndicatorView`

Owns:
- visible “jump to bottom” affordance
- unread-output state when scrolled up

Consumes:
- `TerminalRuntime.scrollbarState`

Sends:
- `scroll_to_bottom`

#### `Ghostty.SurfaceView`

Already owns:
- terminal rendering
- keyboard/mouse forwarding
- edit-menu binding actions like copy/paste/select all

Will additionally own:
- `TerminalSurfaceActionPerforming` conformance
- observation of runtime-owned mouse cursor state

### Runtime Injection

`TerminalPaneMountView` is still created separately from `TerminalRuntime`, so the coordinator remains the composition seam:

- `PaneCoordinator+ViewLifecycle` creates the mount view
- `registerTerminalRuntimeIfNeeded` creates/registers the runtime
- after both exist, the coordinator calls `terminalView.bind(runtime:)`

This preserves the current ownership model instead of pushing runtime construction into the view layer.

### Current Runtime Shapes To Consume

The design should match the code already on `main` unless we intentionally change it later:

```swift
struct ScrollbarState {
    let top: Int
    let bottom: Int
    let total: Int
}

struct TerminalSearchState {
    var query: String
    var totalMatches: Int?
    var selectedMatchIndex: Int?
}
```

The host layer may add computed helpers such as `visibleRowCount`, `firstVisibleRow`, or `isPinnedToBottom`, but it should not assume a shape change as part of this feature unless we explicitly decide to do that follow-up.

### Mouse State Gap

Current `main` promotes `mouseShapeChanged` and `mouseVisibilityChanged` events, but `TerminalRuntime` does not currently store them as observable properties. This feature should add:

```swift
private(set) var mouseShapeRawValue: UInt32?
private(set) var isMouseVisible: Bool = true
```

or an equivalent small runtime-owned representation that `Ghostty.SurfaceView` can observe directly.

### Observation Model

Host-side state consumption should use the existing `@Observable` + `withObservationTracking` style already used in the app. Scrollbar drag lifecycle may still use `NSScrollView`/`NSView` notifications where AppKit is the source of truth, matching Ghostty's macOS host implementation.

## Core Behaviors

### Follow-Bottom

- Ghostty core owns follow-bottom semantics.
- Agent Studio disables Ghostty's keypress/output auto-scroll through config so reading scrollback is stable.
- While the user is actively dragging the scrollbar, the host must not fight the drag with programmatic repositioning.

### Scrollbar Math

The host wrapper should use the existing scrollbar facts from core:

- `top`: first visible row
- `bottom`: last visible row
- `total`: total rows

Derived host helpers:

```swift
let visibleRowCount = max(0, bottom - top)
let isPinnedToBottom = bottom >= total
```

### Smooth Scrolling Requirement

Scrolling with a mouse wheel or trackpad must match Ghostty.app by keeping **Ghostty core** as the ordinary scroll authority, while the host wrapper provides native scrollbar UI and drag synchronization.

Current Agent Studio behavior:

- `Ghostty.SurfaceView.scrollWheel(with:)` forwards raw wheel deltas directly to `ghostty_surface_mouse_scroll(...)`.
- With a discrete physical mouse wheel, that path can feel like large jumps.

Target behavior for this feature:

- `Ghostty.SurfaceView.scrollWheel(with:)` remains the primary wheel/trackpad path while embedded.
- The host `NSScrollView` provides the native scrollbar and uses live-scroll notifications to translate thumb/track movement into `scroll_to_row:N`.
- The host follows core-emitted scrollbar state instead of owning a second scroll state machine.

This Ghostty-centered smooth-scroll fix is part of this PR, not a follow-up.

### Search UX

- `cmd+f` opens search for the focused terminal pane.
- `cmd+g` and `shift+cmd+g` navigate results.
- Escape closes the visible overlay and ends search.
- Search overlay visibility follows runtime state, not a second local boolean.

### Mouse UX

- Cursor shape updates should map into AppKit cursors where possible.
- Visibility transitions must keep `NSCursor.hide()` / `NSCursor.unhide()` balanced.

## Testing Strategy

### Unit Tests

- `TerminalSurfaceScrollViewTests`
  - row/pixel conversion
  - live-scroll dedup
  - follow-bottom behavior
- `TerminalSearchOverlayViewTests`
  - callback wiring
  - label formatting
- `ScrollToBottomIndicatorViewTests`
  - visibility
  - unread-output state
- `TerminalPaneMountViewSearchTests`
  - responder methods emit the correct binding actions
- `TerminalRuntimeTests`
  - mouse runtime state becomes observable

### Integration-Focused Checks

- `TerminalPaneMountView` reacts to `scrollbarState` and `searchState`
- Find menu items route to the focused terminal responder chain
- Surface view mouse cursor updates react to runtime state

### Non-Goals For Tests

- No end-to-end Ghostty app parity tests
- No wall-clock sleep tests

## Files

### Create

- `Sources/AgentStudio/Features/Terminal/Hosting/TerminalSurfaceActionPerforming.swift`
- `Sources/AgentStudio/Features/Terminal/Hosting/TerminalSurfaceScrollView.swift`
- `Sources/AgentStudio/Features/Terminal/Hosting/TerminalSearchOverlayView.swift`
- `Sources/AgentStudio/Features/Terminal/Hosting/ScrollToBottomIndicatorView.swift`
- `Tests/AgentStudioTests/Features/Terminal/Hosting/TerminalSurfaceScrollViewTests.swift`
- `Tests/AgentStudioTests/Features/Terminal/Hosting/TerminalSearchOverlayViewTests.swift`
- `Tests/AgentStudioTests/Features/Terminal/Hosting/ScrollToBottomIndicatorViewTests.swift`
- `Tests/AgentStudioTests/Features/Terminal/Hosting/TerminalPaneMountViewSearchTests.swift`

### Modify

- `Sources/AgentStudio/Features/Terminal/Ghostty/GhosttyAppHandle.swift`
- `Sources/AgentStudio/Features/Terminal/Hosting/GhosttyMountView.swift`
- `Sources/AgentStudio/Features/Terminal/Hosting/TerminalPaneMountView.swift`
- `Sources/AgentStudio/Features/Terminal/Ghostty/GhosttySurfaceView.swift`
- `Sources/AgentStudio/App/Coordination/PaneCoordinator+ViewLifecycle.swift`
- `Sources/AgentStudio/App/Boot/AppDelegate.swift`
- `Sources/AgentStudio/Features/Terminal/Runtime/TerminalRuntime.swift`
- `Tests/AgentStudioTests/Features/Terminal/Runtime/TerminalRuntimeTests.swift`
