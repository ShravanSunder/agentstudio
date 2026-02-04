# AppKit + SwiftUI Hybrid Architecture

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
- **AppState**: Use a shared `ObservableObject` (or `@Observable` in Swift 5.9+) passed from AppKit to SwiftUI views.
- **Bindings**: Pass `Binding` objects from AppKit to SwiftUI for bidirectional data flow.
- **Notifications**: Use `NotificationCenter` for loose coupling between AppKit services and SwiftUI views.

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

## Surface Management Architecture

Agent Studio embeds Ghostty terminal surfaces via libghostty. The `SurfaceManager` provides a robust lifecycle management layer with crash isolation.

### Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│  App                                                            │
│  - Owns SurfaceManager (singleton)                              │
│  - Lifecycle: launch → run → quit                               │
├─────────────────────────────────────────────────────────────────┤
│  Window                                                         │
│  - Contains tabs                                                │
│  - Delegates surface display to tabs                            │
├─────────────────────────────────────────────────────────────────┤
│  Tab (Composition)                                              │
│  - Displays a surface (does NOT own it)                         │
│  - Requests surface from SurfaceManager                         │
│  - Returns surface on close                                     │
├─────────────────────────────────────────────────────────────────┤
│  SurfaceManager (Always Present)                                │
│  - OWNS all surfaces                                            │
│  - Lifecycle: create, attach, detach, hide, undo, destroy       │
│  - Checkpoints surface CONFIG on quit                           │
│  - Restores surfaces on launch                                  │
├─────────────────────────────────────────────────────────────────┤
│  Ghostty.SurfaceView                                            │
│  - Rendering + PTY                                              │
│  - Dies with app (unless zellij)                                │
├─────────────────────────────────────────────────────────────────┤
│  SessionService (Optional - if zellij exists)                   │
│  - Surface runs: zellij attach <session>                        │
│  - PTY ownership moves to zellij server                         │
│  - Survives app quit                                            │
└─────────────────────────────────────────────────────────────────┘
```

### Surface States

| State | Description | Rendering | PTY |
|-------|-------------|-----------|-----|
| **Active** | Attached to visible container | Enabled | Alive |
| **Hidden** | Detached, no container | Paused (occlusion) | Alive |
| **PendingUndo** | In undo stack with TTL | Paused | Alive |
| **Destroyed** | ARC released | N/A | Freed |

### Crash Isolation Design

**Goal:** One terminal crash must NEVER bring down the app.

```
╔══════════════════════════════════════════════════════════════════╗
║  CRASH ISOLATION STRATEGY                                        ║
╠══════════════════════════════════════════════════════════════════╣
║                                                                  ║
║  1. PREVENTION                                                   ║
║     - Defensive API wrappers (withSurface)                       ║
║     - Validate surface pointers before use                       ║
║     - Retry surface creation on failure                          ║
║                                                                  ║
║  2. DETECTION                                                    ║
║     - Subscribe to Ghostty health notifications                  ║
║     - Periodic health checks (timer-based)                       ║
║     - Check process exit status                                  ║
║                                                                  ║
║  3. RECOVERY                                                     ║
║     - Show error overlay in affected tab only                    ║
║     - Offer restart button                                       ║
║     - Other tabs continue working                                ║
║                                                                  ║
║  LIMITATION: Zig panics on main thread WILL crash the app.       ║
║  We minimize this risk but can't eliminate it without IPC.       ║
╚══════════════════════════════════════════════════════════════════╝
```

### Decision Matrix: Session Persistence

| Approach | Process Survives Quit | Complexity | When to Use |
|----------|----------------------|------------|-------------|
| **Pure Ghostty** | No | Low | Quick terminals, dev tools |
| **Zellij Integration** | Yes | Medium | Long-running tasks (Claude) |
| **Process Isolation (XPC)** | Yes | High | Future consideration |

### Key APIs

| API | Purpose |
|-----|---------|
| `SurfaceManager.createSurface()` | Create with retry and error handling |
| `SurfaceManager.attach(to:)` | Attach to container, resume rendering |
| `SurfaceManager.detach(reason:)` | Hide, close (undo-able), or move |
| `SurfaceManager.undoClose()` | Restore last closed surface |
| `SurfaceManager.withSurface()` | Safe operation wrapper |
| `ghostty_surface_set_occlusion()` | Pause/resume rendering |
| `ghostty_surface_process_exited()` | Check if shell has exited |
| `ghostty_surface_needs_confirm_quit()` | Check if process is running |

### Health Monitoring

Ghostty provides renderer health notifications. SurfaceManager subscribes to these and performs periodic health checks:

```swift
// Health states
enum SurfaceHealth {
    case healthy
    case unhealthy(reason: UnhealthyReason)
    case processExited(exitCode: Int32?)
    case dead  // Surface pointer is nil/invalid
}

// Detection
- Ghostty.Notification.didUpdateRendererHealth
- Periodic check: ghostty_surface_process_exited()
- Surface pointer validation
```

### Files

| File | Purpose |
|------|---------|
| `Ghostty/SurfaceManager.swift` | Lifecycle management, health monitoring |
| `Ghostty/SurfaceTypes.swift` | Types, protocols, checkpoints |
| `Ghostty/Ghostty.swift` | App wrapper, notifications |
| `Ghostty/GhosttySurfaceView.swift` | Surface view, input handling |
| `Views/SurfaceErrorOverlay.swift` | Error state UI |

---

## Key Resources
- **WWDC22**: [Use SwiftUI with AppKit](https://developer.apple.com/videos/play/wwdc2022/10075/) (Essential for layout/sizing patterns)
- **WWDC19**: [Integrating SwiftUI](https://developer.apple.com/videos/play/wwdc2019/231/) (Foundational hosting concepts)
- **SwiftUI Lab**: [The Power of the Hosting+Representable Combo](https://swiftui-lab.com/a-powerful-combo/)
- **Ghostty**: [ghostty-org/ghostty](https://github.com/ghostty-org/ghostty) (Terminal emulator source)
