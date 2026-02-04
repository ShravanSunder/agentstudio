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

When wrapping SwiftUI views in AppKit containers that need custom event handling (like drag-to-reorder), careful attention must be paid to event ownership.

### The Event Ownership Rule

**When you claim an event via `hitTest`, you must handle it completely yourself—no forwarding to subviews.**

This is critical when using composition patterns (wrapping `NSHostingView` instead of subclassing) to add AppKit event handling to SwiftUI views.

### The Problem: Infinite Event Loops

```swift
// ❌ WRONG - Causes infinite loop crash
override func hitTest(_ point: NSPoint) -> NSView? {
    if pointIsInMyCustomArea(point) {
        return self  // Claim the event
    }
    return super.hitTest(point)
}

override func mouseDown(with event: NSEvent) {
    // Process our logic...
    hostingView.mouseDown(with: event)  // Forward to subview
    // ❗ This re-triggers hitTest → mouseDown → hitTest → crash
}
```

When `hitTest` returns `self`, the event system sends `mouseDown` to us. If we then forward to a subview, that subview may call back through the event system, creating an infinite loop.

### The Solution: Complete Event Ownership

```swift
// ✅ CORRECT - Handle events completely ourselves
override func hitTest(_ point: NSPoint) -> NSView? {
    let localPoint = convert(point, from: superview)
    if pointIsInMyCustomArea(localPoint) {
        return self  // We claim this event and will handle it completely
    }
    return super.hitTest(point)  // Let subviews handle other areas
}

override func mouseDown(with event: NSEvent) {
    let point = convert(event.locationInWindow, from: nil)
    if let item = itemAtPoint(point) {
        // Track for potential drag
        mouseDownPoint = point
        mouseDownItem = item
        return  // DO NOT forward to subviews
    }
    // If we're here, hitTest should have returned the subview, not us
}

override func mouseDragged(with event: NSEvent) {
    // Start drag if moved enough distance
}

override func mouseUp(with event: NSEvent) {
    // If we tracked a click (not drag), perform the action
    // e.g., post a notification for the controller to handle
}
```

### Pattern: Click vs. Drag Disambiguation

For views that need both click-to-select and drag-to-reorder:

1. **mouseDown**: Capture the item and start point, do NOT forward
2. **mouseDragged**: If moved beyond threshold, initiate drag operation
3. **mouseUp**: If no drag occurred, treat as click (e.g., post notification)

### Communication Back to Controllers

Since we can't directly call SwiftUI callbacks from mouseUp (no gesture context), use `NotificationCenter`:

```swift
// In mouseUp, after determining it was a click:
NotificationCenter.default.post(
    name: .selectItemById,
    object: nil,
    userInfo: ["itemId": itemId]
)
```

### Reference Implementation

See `DraggableTabBarHostingView.swift` for a complete working example of this pattern applied to tab bar drag-to-reorder.

## Key Resources
- **WWDC22**: [Use SwiftUI with AppKit](https://developer.apple.com/videos/play/wwdc2022/10075/) (Essential for layout/sizing patterns)
- **WWDC19**: [Integrating SwiftUI](https://developer.apple.com/videos/play/wwdc2019/231/) (Foundational hosting concepts)
- **SwiftUI Lab**: [The Power of the Hosting+Representable Combo](https://swiftui-lab.com/a-powerful-combo/)
