# AppKit + SwiftUI Hybrid Architecture

## TL;DR

Agent Studio uses an **AppKit-main** architecture hosting SwiftUI views for declarative UI. AppKit controls the window lifecycle, responder chain, and terminal surface management. SwiftUI handles forms, lists, and animations. Services are created in `AppDelegate` in dependency order, with `WorkspaceStore` as the single source of truth. See [Component Architecture](component_architecture.md) for the full data model and service layer.

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

- **WorkspaceStore**: `@MainActor ObservableObject` — the single source of truth. SwiftUI views observe `@Published` properties; AppKit controllers subscribe via Combine.
- **Bindings**: Pass `Binding` objects from AppKit to SwiftUI for bidirectional data flow.
- **Notifications**: `NotificationCenter` for loose coupling between AppKit menu actions and controllers (e.g., `.newTabRequested`, `.closeTabRequested`, `.undoCloseTabRequested`).
- **Combine**: `TerminalTabViewController` subscribes to `store.$activeViewId` and re-renders the terminal container on changes.

### Ownership Hierarchy

Services are created in `AppDelegate.applicationDidFinishLaunching()` in dependency order:

```
AppDelegate
├── WorkspaceStore      ← restore from disk
├── SessionRuntime      ← runtime health tracking
├── ViewRegistry        ← sessionId → NSView mapping
├── TerminalViewCoordinator ← sole model↔view↔surface bridge
├── ActionExecutor      ← action dispatch hub
├── TabBarAdapter       ← Combine-derived tab bar state
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

## Ghostty Terminal Integration

For the Ghostty surface lifecycle, ownership model, state machine, and health monitoring, see:

**[Ghostty Surface Architecture](ghostty_surface_architecture.md)**

## Session Restore

Terminal session state is managed by `WorkspaceStore` (persistence) and `SessionRuntime` (health/lifecycle). `TerminalViewCoordinator` is the sole intermediary for surface and runtime lifecycle — views never call `SurfaceManager` or `SessionRuntime` directly. The tmux backend (`TmuxBackend`) provides session persistence across app restarts.

For the full session lifecycle, restore flow, and tmux configuration, see: **[Session Lifecycle](session_lifecycle.md)**

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
- **[Session Lifecycle](session_lifecycle.md)** — Session creation, close, undo, restore, tmux backend
- **[Surface Architecture](ghostty_surface_architecture.md)** — Surface ownership, health monitoring, crash isolation
