# AppKit + SwiftUI Hybrid Architecture

## TL;DR

Agent Studio uses an **AppKit-main** architecture hosting SwiftUI views for declarative UI. AppKit controls the window lifecycle, responder chain, and terminal surface management. SwiftUI handles forms, lists, and animations. State is distributed across independent `@Observable` stores (Jotai-style) with `private(set)` for unidirectional flow (Valtio-style). A coordinator sequences cross-store operations. See [Component Architecture](component_architecture.md) for the full data model and service layer.

---

## Architectural Philosophy
Agent Studio follows an **AppKit-main** architecture. This decision was made to ensure direct control over the macOS system integration while leveraging SwiftUI's strengths for declarative UI components.

### Why AppKit-first?
- **Direct Lifecycle Control**: AppDelegate and main NSApplication provide a predictable, standard macOS lifecycle.
- **Better Key Handling**: Native AppKit responder chain management for complex terminal keyboard shortcuts and global key monitoring.
- **Less Glue Code**: Avoids the "wrapper struct → representable → coordinator" ceremony for core system features like menus, windows, and traffic lights.
- **Performance**: Direct access to NSWindow and NSView for performance-sensitive components like the terminal emulator shell.

## Decision Matrix: AppKit vs. SwiftUI

| Use Case | Recommended Framework | Why? |
| :--- | :--- | :--- |
| **Windows & Lifecycle** | AppKit | Direct control over titlebars, traffic lights, and resize constraints. |
| **Global Key Monitoring** | AppKit | More robust and standard implementation via the responder chain. |
| **Complex Menus** | AppKit / NSHostingMenu | Better integration with standard macOS menu behaviors. |
| **Forms & Settings** | SwiftUI | Declarative style saves significant time for standard layouts. |
| **Dynamic Lists** | SwiftUI | `List` and `ForEach` are much more efficient to implement than `NSTableView`. |
| **Animations** | SwiftUI | Modern animation APIs are far superior to AppKit's legacy systems. |

## Core Hosting Patterns

### NSHostingController
Use for full-screen components, sidebars, or major view controller containment.
```swift
let sidebar = NSHostingController(rootView: SidebarView())
// Add as child view controller
self.addChild(sidebar)
self.view.addSubview(sidebar.view)
```

### NSHostingView
Use for granular embedding within existing `NSView` hierarchies (e.g., custom cells, small UI widgets).
```swift
let host = NSHostingView(rootView: SmallWidget())
parentView.addSubview(host)
```

### NSHostingMenu (macOS 14.4+)
Use for modern, declarative menu construction.
```swift
let menu = NSHostingMenu(rootView: MenuView())
```

## Sizing & Layout
- **Intrinsic Size**: SwiftUI views automatically update Auto Layout constraints based on their content size.
- **Flexible Sizing**: Use `.frame(minWidth:idealWidth:maxWidth:)` in SwiftUI to inform AppKit's layout system.
- **Constraint Management**: For `NSHostingController`, set `sizingOptions` (e.g., `.intrinsicContentSize`) to control how the view interacts with its container.

## Data Flow & State

The full data model, service layer, and mutation pipeline are documented in [Component Architecture](component_architecture.md). Key patterns relevant to the AppKit+SwiftUI boundary:

- **Atomic stores**: `WorkspaceStore`, `SurfaceManager`, `SessionRuntime` — each `@Observable @MainActor`, each owns one domain. All state is `private(set)` for unidirectional flow. SwiftUI views observe store properties automatically via `@Observable` property tracking. No `@Published`, no `objectWillChange`, no Combine subscriptions.
- **Coordinator**: `PaneCoordinator` sequences cross-store operations (e.g., close tab touches `WorkspaceStore` + `SurfaceManager` + `SessionRuntime`). Owns no domain state.
- **AppKit observation**: Non-SwiftUI code (e.g., `TabBarAdapter`) bridges to `@Observable` using `withObservationTracking` with re-registration pattern.
- **Event transport**: New plumbing uses `AsyncStream` + `swift-async-algorithms`. Existing `NotificationCenter` for AppKit menu actions migrated incrementally.

### NSHostingView → SwiftUI Root Mapping

Each AppKit controller that hosts SwiftUI creates NSHostingView(s) **once** at setup time. @Observable drives all re-renders — no manual rootView replacement.

**TerminalTabViewController** hosting regions:
| NSHostingView | SwiftUI Root | Purpose |
|---|---|---|
| `tabBarHostingView` | `CustomTabBar` | Tab bar (top strip) |
| `splitHostingView` | `ActiveTabContent` → `TerminalSplitContainer` | Main content area — renders active tab's split tree |
| `arrangementButtonHostingView` | `ArrangementFloatingButton` | Floating arrangement button |
| _(pure AppKit)_ | `emptyStateView` | Empty state when no tabs exist |

**MainSplitViewController**:
| NSHostingController | SwiftUI Root | Purpose |
|---|---|---|
| Sidebar hosting controller | `SidebarViewWrapper` → `SidebarContentView` | Worktree/repo sidebar |

**CommandBarPanelController**:
| NSHostingView | SwiftUI Root | Purpose |
|---|---|---|
| Panel hosting view | `CommandBarView` | Command palette UI |

### Ownership Hierarchy

Services are created in `AppDelegate.applicationDidFinishLaunching()` in dependency order:

```
AppDelegate
├── WorkspaceStore      ← @Observable, restore from disk
├── SessionRuntime      ← runtime health tracking
├── ViewRegistry        ← paneId → NSView mapping (not @Observable)
├── TerminalViewCoordinator ← sole model↔view↔surface bridge
├── ActionExecutor      ← action dispatch hub
├── TabBarAdapter       ← bridges @Observable store via withObservationTracking
├── CommandBarPanelController ← command bar lifecycle (⌘P/⌘⇧P/⌘⌥P)
└── MainWindowController
    └── MainSplitViewController
        └── TerminalTabViewController
```

See [Component Architecture — Service Layer](component_architecture.md#3-service-layer) for detailed descriptions of each service.

## AppKit Event Handling in Hybrid Views

When adding drag-to-reorder to SwiftUI views hosted in AppKit, use gesture recognizers rather than overriding `hitTest`. This lets SwiftUI handle all normal interactions while AppKit intercepts only drag gestures.

### Recommended: NSPanGestureRecognizer

```swift
class DraggableHostingView: NSView, NSDraggingSource {
    private var panGesture: NSPanGestureRecognizer!
    private var panStartItemId: UUID?

    override init(frame: NSRect) {
        super.init(frame: frame)
        panGesture = NSPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        panGesture.delaysPrimaryMouseButtonEvents = false
        addGestureRecognizer(panGesture)
    }

    @objc private func handlePan(_ gesture: NSPanGestureRecognizer) {
        let location = gesture.location(in: self)
        switch gesture.state {
        case .began:
            panStartItemId = itemAtPoint(location)
        case .changed:
            if let itemId = panStartItemId, !isDragging {
                startDrag(itemId: itemId, event: NSApp.currentEvent!)
                panStartItemId = nil
            }
        case .ended, .cancelled:
            panStartItemId = nil
        default: break
        }
    }
}
```

**Why this works:**
- SwiftUI receives all clicks, hovers, right-clicks normally
- Pan gesture only fires after sufficient movement
- No event ownership conflicts

### Avoid: hitTest Override

Overriding `hitTest` to claim events creates problems:
- Breaks SwiftUI's event handling (close buttons, context menus)
- Risk of infinite loops if events are forwarded back to subviews
- Requires reimplementing click handling manually

### Reference Implementation

See `DraggableTabBarHostingView.swift` for the gesture recognizer pattern applied to tab bar drag-to-reorder.

---

## Command Bar (⌘P)

The command bar is a keyboard-driven search/command palette modeled after Linear's ⌘K. It provides unified access to tabs, panes, commands, and worktrees through a single interface with prefix-based scoping.

### Architecture: NSPanel as Child Window

The command bar uses an `NSPanel` (child window) rather than a SwiftUI overlay. This guarantees:

- **Z-ordering** above all AppKit terminal views (Ghostty surfaces are `NSView` subclasses)
- **Clean first-responder management** — the search field gets focus; the terminal releases it
- **Click-outside-to-dismiss** via backdrop `NSView` overlay on the parent window
- **Native backdrop blur** via `NSVisualEffectView` with `.sidebar` material

```
MainWindow
├── MainSplitViewController (all existing content)
│   ├── Sidebar
│   └── TerminalTabViewController
│
├── CommandBarBackdropView (NSView overlay, click to dismiss)
│
└── CommandBarPanel (NSPanel, child window)
    ├── NSVisualEffectView (.sidebar material)
    └── NSHostingView
        └── CommandBarView (SwiftUI)
            ├── CommandBarScopePill
            ├── CommandBarSearchField
            ├── CommandBarResultsList
            └── CommandBarFooter
```

### Keyboard Shortcuts

Three shortcuts open the same command bar with different prefix scoping:

| Shortcut | Prefix | Scope |
|----------|--------|-------|
| `⌘P` | _(none)_ | Everything — tabs, panes, commands, worktrees |
| `⌘⇧P` | `>` | Commands only, grouped by category |
| `⌘⌥P` | `@` | Panes and tabs, grouped by parent tab |

Shortcuts are registered as menu items in `AppDelegate` (responder chain routing). Pressing the same shortcut again while the bar is open toggles it closed. Pressing a different shortcut while open switches the prefix in-place.

### Keyboard Interception

`CommandBarTextField` is an `NSViewRepresentable` wrapping `NSTextField` to intercept keys that SwiftUI's `TextField` doesn't expose:

| Key | Selector | Action |
|-----|----------|--------|
| `↑` / `↓` | `moveUp:` / `moveDown:` | Move selection (wraps at boundaries) |
| `↩` | `insertNewline:` | Execute selected item or drill into children |
| `⎋` | `cancelOperation:` | Dismiss entirely (routed through panel's `onDismiss`) |
| `⌫` on empty | `deleteBackward:` | Pop nested level or clear prefix |

### Focus Management

1. **On show**: `CommandBarPanel.makeKeyAndOrderFront()` → search field becomes first responder
2. **During**: Terminal surface loses first responder (Ghostty handles this gracefully)
3. **On dismiss**: `parentWindow.makeKeyAndOrderFront()` → terminal regains focus

### Execution Flow

The command bar never mutates `WorkspaceStore` directly. All actions flow through the existing validation pipeline:

```
CommandBarView.executeItem()
  ├── .dispatch(command)         → CommandDispatcher.dispatch() → full pipeline
  ├── .dispatchTargeted(cmd,id)  → CommandDispatcher.dispatch(_:target:targetType:)
  ├── .navigate(level)           → state.pushLevel() (nested drill-in)
  └── .custom(closure)           → Direct execution (e.g., tab switching via Notification)
```

### Key Components

| Component | Role |
|-----------|------|
| `CommandBarPanelController` | Lifecycle: show/dismiss/toggle, backdrop, animation, state ownership |
| `CommandBarState` | Observable state: visibility, prefix parsing, navigation stack, selection, recents |
| `CommandBarDataSource` | Builds `CommandBarItem` arrays from `WorkspaceStore` + `CommandDispatcher` |
| `CommandBarSearch` | Custom fuzzy matching with score + character match ranges for highlighting |
| `CommandBarPanel` | `NSPanel` subclass with `NSVisualEffectView` and `NSHostingView` |
| `CommandBarView` | Root SwiftUI view composing search, results, scope pill, footer |

> **Files:** `CommandBar/CommandBarPanelController.swift`, `CommandBar/CommandBarState.swift`, `CommandBar/CommandBarPanel.swift`, `CommandBar/CommandBarDataSource.swift`, `CommandBar/CommandBarSearch.swift`, `CommandBar/CommandBarItem.swift`, `CommandBar/Views/*.swift`

---

## Ghostty Terminal Integration

For the Ghostty surface lifecycle, ownership model, state machine, and health monitoring, see:

**[Ghostty Surface Architecture](ghostty_surface_architecture.md)**

## Session Restore

Terminal session state is managed by `WorkspaceStore` (persistence) and `SessionRuntime` (health/lifecycle). `TerminalViewCoordinator` is the sole intermediary for surface and runtime lifecycle — views never call `SurfaceManager` or `SessionRuntime` directly. The zmx backend (`ZmxBackend`) provides session persistence across app restarts via raw byte passthrough daemons.

For the full session lifecycle, restore flow, and zmx configuration, see: **[Session Lifecycle](session_lifecycle.md)**

---

## Key Resources
- **WWDC22**: [Use SwiftUI with AppKit](https://developer.apple.com/videos/play/wwdc2022/10075/) (Essential for layout/sizing patterns)
- **WWDC19**: [Integrating SwiftUI](https://developer.apple.com/videos/play/wwdc2019/231/) (Foundational hosting concepts)
- **SwiftUI Lab**: [The Power of the Hosting+Representable Combo](https://swiftui-lab.com/a-powerful-combo/)
- **Ghostty**: [ghostty-org/ghostty](https://github.com/ghostty-org/ghostty) (Terminal emulator source)

---

## Related Documentation

- **[Architecture Overview](README.md)** — System overview and document index
- **[Component Architecture](component_architecture.md)** — Data model, service layer, data flow, persistence
- **[Session Lifecycle](session_lifecycle.md)** — Session creation, close, undo, restore, zmx backend
- **[Surface Architecture](ghostty_surface_architecture.md)** — Surface ownership, health monitoring, crash isolation
