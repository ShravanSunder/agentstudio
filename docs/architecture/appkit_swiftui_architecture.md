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

Host surfaces such as pane toolbars, drawer chrome, window chrome, and tab shells remain App-owned assembly points. When those surfaces embed capability-specific UI, keep the shell and placement logic in `App/` while the reusable capability content lives in its owning `Features/<Capability>/` slice.

Example:
- `App/Panes/DrawerEditorChooser/` owns the drawer toolbar button, anchoring, divider, and pane wiring
- `SharedComponents/EditorChooser/` owns the numbered editor chooser menu rows and bookmark UI

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

## Native Titlebar And Tab Strip

The main window uses one native `NSToolbar` with `.unifiedCompact` styling. The
toolbar owns titlebar placement, traffic-light coexistence, item ordering, and
overflow. Agent Studio does not draw a second content-owned chrome row below
it.

```text
NSWindow (.fullSizeContentView, transparent titlebar)
└── NSToolbar (.unifiedCompact)
    ├── native and hosted toolbar controls
    └── workspaceTabs NSToolbarItem
        └── MainToolbarChromeView             40-point AppKit envelope
            └── DraggableTabBarHostingView    hit testing + drag ownership
                └── NSHostingView
                    └── CustomTabBar          SwiftUI tab pills and controls
```

### Ownership

- `MainWindowController` configures the `NSWindow` and `NSToolbar`, declares
  toolbar item order, and installs the workspace-tabs item.
- `MainSplitViewController` creates one `PaneTabViewController`, initializes
  its shared tab host, and hands that same host to the toolbar. It does not
  create a second tab surface.
- `MainToolbarChromeView` is the AppKit layout envelope for the flexible tab
  item. It owns no click or drag policy.
- `DraggableTabBarHostingView` bridges AppKit events to the SwiftUI tab surface.
  It owns pill-frame hit testing, management-mode tab dragging, and native
  window dragging from empty strip space.
- `CustomTabBar` renders the tab pills and toolbar-local controls. SwiftUI owns
  ordinary tab selection, hover, close buttons, and context menus.

### Geometry And Hit Testing

The visible and interactive geometry must be treated as one contract:

| Layer | Height | Purpose |
| --- | ---: | --- |
| `MainToolbarChromeView` | `AppStyles.Shell.TabBar.height` (40 points) | Full native toolbar hit-test envelope |
| `DraggableTabBarHostingView` | fills the 40-point chrome | AppKit event and drag owner |
| visible SwiftUI tab pill | `tabPillHeight` (32 points) | Product appearance |

The tab host uses `NSHostingView.sizingOptions = []` and is constrained through
the chrome instead of accepting an intrinsic 24-point toolbar-control height.
This distinction is load-bearing: a 32-point pill can still render outside a
24-point AppKit ancestor, but window-rooted hit testing clips at that ancestor.
The result looks correct while clicks near the visible pill edges fall through
to `NSToolbarItemViewer` or the window frame.

Keep the AppKit chrome and tab host at the full 40-point tab-bar height. Use
`stripCenterlineOffset` only to align the full-height host with native controls;
do not shrink the host to move the visible pill. Changes to the toolbar style,
tab height, pill height, or centerline offset must verify both visible
alignment and window-rooted hits at the top and bottom of a rendered pill.

### Tab Dragging Versus Window Dragging

The tab strip deliberately owns two different drag paths:

1. A mouse-down inside a reported tab-pill frame remains a tab interaction.
   In management mode, `NSPanGestureRecognizer` can promote it to a tab reorder.
2. A mouse-down outside every pill is empty titlebar chrome.
   `DraggableTabBarHostingView.mouseDown(with:)` calls
   `NSWindow.performDrag(with:)`; a double-click follows the user's macOS
   titlebar action preference.

`window.isMovable` remains enabled so explicit `performDrag` works, while
`window.isMovableByWindowBackground` remains disabled so terminal or content
clicks cannot move the window. Do not add a transparent drag overlay or a
`hitTest` override above the tab surface: either would compete with SwiftUI tab
clicks and controls.

### Content Below The Titlebar

Because the window uses `.fullSizeContentView`, `MainSplitViewController`
projects `window.contentLayoutRect` into `additionalSafeAreaInsets`. This keeps
sidebar and pane content below the native toolbar without recreating toolbar
height assumptions in the content hierarchy.

### Proof Obligations

- Use a real `NSWindow` and `NSToolbar` for hit-test regression coverage. Begin
  at the window root and require both visible pill edges to resolve to the tab
  host or one of its descendants.
- Preserve the focused window-drag tests for pill exclusion, empty-strip drag,
  double-click behavior, and the window movement policy.
- For manual proof, launch the worktree-isolated debug app and verify clicks at
  the lowest visible row of inactive pills, management-mode tab reorder, empty
  strip window movement on a non-maximized window, and unchanged visual
  alignment.

### Gotchas

- **Rendering outside an ancestor does not expand its hit area.** AppKit may
  display a SwiftUI pill beyond a smaller hosting ancestor, but window-rooted
  hit testing still clips at the ancestor. Inspect every view from the rendered
  control back to the window root when only part of a visible control responds.
- **`NSToolbarItemViewer` geometry is not the custom view's geometry.** A
  40-point toolbar row does not guarantee that `MainToolbarChromeView` or
  `DraggableTabBarHostingView` also resolved to 40 points. Measure each layer
  independently before changing event routing.
- **Intrinsic hosting size can silently collapse the interactive envelope.** The
  tab host intentionally uses `NSHostingView.sizingOptions = []`. Restoring
  intrinsic sizing can make the AppKit host follow a compact control height
  even while SwiftUI continues drawing the larger pill.
- **Move the full-height host; do not resize it to align the pills.** The same
  `stripCenterlineOffset` is applied to the host's top and bottom constraints,
  translating the host without changing its height. Using asymmetric constants
  changes the hit envelope and can fix one edge while breaking the other.
- **AppKit and SwiftUI use opposite vertical coordinate conventions here.** Tab
  frames are reported in SwiftUI coordinates and converted by
  `DraggableTabBarGeometry` for the AppKit host. Do not compare or hit-test raw
  Y coordinates across the boundary without performing that conversion.
- **The toolbar can reframe custom views after their initial layout.** Do not
  rely on a one-time frame assignment. Toolbar control hosts perform
  backing-pixel alignment from `layout()` so later AppKit layout passes preserve
  crisp borders.
- **A drag overlay competes with the tab surface.** Transparent titlebar views,
  broad `hitTest` overrides, and `isMovableByWindowBackground = true` can steal
  clicks from SwiftUI buttons or make terminal content move the window. Keep
  pill-versus-empty-strip classification in `DraggableTabBarHostingView`.
- **The pan recognizer is management-mode-only.** Enabling it continuously can
  delay or consume SwiftUI tab clicks. `delaysPrimaryMouseButtonEvents = false`
  is necessary but does not replace the management-mode enablement boundary.
- **Do not hard-code content insets from the 40-point toolbar constant.** The
  effective non-obscured content rectangle belongs to AppKit and can change with
  window or toolbar configuration. Project `window.contentLayoutRect` instead.
- **A maximized window is not useful window-drag proof.** `performDrag(with:)`
  may receive the event correctly while the frame cannot visibly move. Exercise
  empty-strip dragging on a non-maximized window and report the limitation when
  that is not possible.

## Data Flow & State

The full data model, service layer, and mutation pipeline are documented in [Component Architecture](component_architecture.md). Key patterns relevant to the AppKit+SwiftUI boundary:

- **Atomic stores**: `WorkspaceStore`, `SurfaceManager`, `SessionRuntime` — each `@Observable @MainActor`, each owns one domain. All state is `private(set)` for unidirectional flow. SwiftUI views observe store properties automatically via `@Observable` property tracking. No `@Published`, no `objectWillChange`, no Combine subscriptions.
- **Coordinator**: `WorkspaceSurfaceCoordinator` sequences cross-store operations (e.g., close tab touches `WorkspaceStore` + `SurfaceManager` + `SessionRuntime`). Owns no domain state.
- **AppKit observation**: Non-SwiftUI code (e.g., `TabBarAdapter`) bridges to `@Observable` using `withObservationTracking` with re-registration pattern.
- **Event transport**: New plumbing uses `AsyncStream` + `swift-async-algorithms`. Existing `NotificationCenter` for AppKit menu actions migrated incrementally.

### NSHostingView → SwiftUI Root Mapping

Each AppKit controller that hosts SwiftUI creates NSHostingView(s) **once** at setup time. @Observable drives all re-renders — no manual rootView replacement.

**PaneTabViewController** hosting regions:
| NSHostingView | SwiftUI Root | Purpose |
|---|---|---|
| `tabBarHostingView` | `CustomTabBar` | Tab bar (top strip) |
| `PersistentTabHostView.hostingView` | `SingleTabContent` | Main content area — one persistent hosting view per tab, shown/hidden by AppKit while all tabs stay alive |
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
├── AtomRegistry                  ← internal App root: CoreAtoms + explicit Feature roots
│   └── CoreAtoms                 ← installed into the sole CoreAtomScope
├── WorkspaceStore             ← persistence wrapper, restore from disk
├── RepoCacheStore             ← persistence wrapper for RepoCacheAtom
├── UIStateStore               ← persistence wrapper for sidebar memory
├── AppLifecycleAtom          ← app active/terminating state (in-memory)
├── WindowLifecycleAtom       ← key/focused window identity (in-memory)
├── SessionRuntime             ← runtime health tracking
├── WorkspaceCacheCoordinator  ← event bus consumer, updates stores
├── ApplicationLifecycleMonitor ← AppKit lifecycle ingress → lifecycle stores
├── ManagementLayerMonitor      ← management layer state tracking
├── ViewRegistry               ← paneId → PaneViewSlot mapping (@Observable per-pane slots)
├── WorkspaceSurfaceCoordinator            ← action dispatch + model↔view↔surface orchestration
├── WorkspaceActionExecutor             ← validated action execution
├── TabBarAdapter              ← bridges @Observable store via withObservationTracking
├── CommandBarPanelController  ← command bar lifecycle (⌘P/⌘⇧P/⌘⌥P)
└── MainWindowController
    └── MainSplitViewController
        └── PaneTabViewController
```

### Embedded Ghostty Host Boundary

The embedded terminal host keeps one subsystem entry seam:

```text
callers
  │
  ▼
Ghostty.shared
  │
  ▼
thin Ghostty.App
  ├── Ghostty.AppHandle
  ├── Ghostty.CallbackRouter
  ├── Ghostty.ActionRouter
  └── Ghostty.AppFocusSynchronizer
```

- `Ghostty.shared` is the only host entrypoint other app code should use.
- `Ghostty.App` is composition-only. It does not own callback logic, the action switch, or lifecycle observation directly.
- `Ghostty.CallbackRouter` stays at the C boundary and captures stable identity before any async hop.
- `Ghostty.ActionRouter` is the only place Ghostty action routing should expand in future terminal work.
- `Ghostty.AppFocusSynchronizer` keeps app-level focus separate from per-surface focus in `GhosttySurfaceView` / `GhosttyMountView`.

### Per-Tab Persistent Hosting

The main pane area keeps one persistent AppKit content host per tab.

- `PaneTabViewController` owns the tab-host lifecycle
- each tab host contains one `NSHostingView<SingleTabContent>`
- inactive tabs are hidden at the AppKit level, not removed from the SwiftUI tree
- pane actions and drop routing flow through stable dispatcher references instead of fresh closures in the visible tab subtree

This replaces the older single-host `ActiveTabContent` pattern, which rendered only the active tab and caused `NSViewRepresentable` teardown on tab switch.

### ViewRegistry Slot Model

`ViewRegistry` provides per-pane `@Observable PaneViewSlot` objects for scoped SwiftUI invalidation. Each slot holds an optional `host: PaneHostView?`. SwiftUI views read `slot(for: paneId).host` and get automatic, pane-scoped re-render when the host changes — no global invalidation.

**Slot lifecycle:**

| Method | When | Effect |
|--------|------|--------|
| `ensureSlot(for:)` | Pane enters workspace structure (create, restore) | Creates slot proactively. Idempotent. |
| `register(view, for:)` | Host view created | Sets `slot.host` — triggers SwiftUI observation |
| `unregister(paneId)` | Close/undo teardown | Clears `slot.host = nil` — slot object survives |
| `removeSlot(for:)` | Pane permanently removed | Deletes the slot entirely |

Slots have **pane-lifetime identity**, not host-lifetime identity. This ensures SwiftUI observers survive across unregister/re-register cycles (repair, undo). The old `viewRevision` global invalidation bridge has been removed.

**Slot seeding on restore:** `AppDelegate.seedSlotsForRestoredPanes()` calls `ensureSlot` for every restored pane *before* `PersistentTabHostView` creation. `WorkspaceSurfaceCoordinator.restoreAllViews()` also seeds slots for all layout and drawer panes before the first `createViewForContent` call, because SwiftUI body evaluation may run before restore completes.

### PaneHostView Identity

`PaneHostView.hostIdentity` returns `ObjectIdentifier(self)` — a stable identity for the specific host instance. `PaneLeafContainer` applies `.id(paneHost.hostIdentity)` on `PaneViewRepresentable`. When the host is replaced (repair, placeholder retry), the identity changes, forcing SwiftUI to dismantle the old representable and create a new one. Without this, `updateNSView` is a no-op and stale views stay mounted.

### PaneActionDispatching Protocol

`PaneActionDispatching` extracts the action dispatch and drop handling interface from scattered closure parameters. `PaneTabActionDispatcher` implements it with stable references (`dispatch`, `shouldAcceptDrop`, `handleDrop`) passed through the per-tab SwiftUI subtree. This replaced fresh closure captures that caused unnecessary re-renders.

### Terminal Exit Hardening

Terminal process termination routes through `PaneTabViewController.handleTerminalProcessTerminated`:
- **Drawer children**: dispatches `removeDrawerPane` to parent
- **Arrangement-visible panes**: normal validated `closePane`/`closeTab`
- **Arrangement-hidden panes**: uses `executor.executeTrusted()` to bypass arrangement validation, since the pane is hidden by the active arrangement but still exists in the tab's canonical model

### Close Transitions

`PaneCloseTransitionCoordinator` provides fast visual feedback on pane close. It marks a pane as "closing" (opacity 0.58, scale 0.985) then dispatches the actual close action after a short delay. `PaneLeafContainer` reads `closingPaneIds` and applies the transition. The pane is non-interactive during the transition.

See [Component Architecture — Service Layer](component_architecture.md#3-service-layer) for detailed descriptions of each service.

### Split Drag Interaction Path

Management-mode split insertion is coordinated at the tab container level:

- `PaneLeafContainer` renders pane content and controls uniformly for all pane kinds.
- `PaneFramePreferenceKey` reports pane frames in `tabContainer` coordinates.
- `SplitContainerDropCaptureOverlay` resolves drag location using `PaneDragCoordinator` and submits validated drop actions through existing `WorkspaceActionCommand` flow.
- `PaneDropTargetOverlay` renders the active destination marker from `PaneDropTarget` + `DropZoneSide`.

This keeps split targeting pane-type-agnostic (terminal/webview/bridge/future panes).

## Swift 6 Concurrency

Swift 6.2 toolchain, `.swiftLanguageMode(.v6)`, macOS 26. Data-race safety is enforced — Sendable violations are compilation errors. Research via DeepWiki (`swiftlang/swift-evolution`) before guessing at concurrency patterns.

### Rules

**Do:**

- **`Task { }` inherits actor isolation** (SE-0304, SE-0420, SE-0431). Inside a `@MainActor` method, the Task body runs on MainActor. Access stored properties directly — no `await` needed.
- **`isolated deinit` for `@MainActor` classes** (SE-0371, Swift 6.2). Access stored properties, cancel Tasks, finish continuations directly.
- **`AsyncStream.makeStream(of:)` for new code** (SE-0388, Swift 5.9+). Returns `(stream, continuation)` tuple.
- **`@preconcurrency import`** for frameworks that haven't fully adopted Sendable.
- **C callback routers capture stable identity before hopping**. Embedded Ghostty callback trampolines should convert raw pointers to stable IDs synchronously, then `Task { @MainActor ... }` before touching AppKit or stores.

**Don't:**

- **Prefer `@concurrent nonisolated` over `Task.detached { }`** (project policy) — `Task.detached` strips task priority and task-locals. `@concurrent nonisolated` helpers (Swift 6.2, SE-0461) preserve structured concurrency and priority inheritance. In `@MainActor` types, helpers must opt out of actor isolation (`nonisolated`) before using `@concurrent`; project convention is `static` helpers to avoid accidental `self` capture. Exception: `Task.detached` is still appropriate when you need to escape structured concurrency scope or intentionally strip task-locals.
- **No `MainActor.assumeIsolated { }` in deinit** — use `isolated deinit` instead (SE-0414 makes `assumeIsolated` problematic with non-Sendable types). Note: `assumeIsolated` is valid in synchronous C callback trampolines where you can prove you're on MainActor but the compiler can't see it — this restriction is specifically about deinit.
- **No plain `deinit` accessing non-Sendable `@MainActor` stored properties** — compilation error. Use `isolated deinit`.
- **Prefer `isolated deinit` over `@MainActor deinit`** — both are valid (SE-0371 allows global actor annotations on deinit), but `isolated deinit` is more generic and works for any actor type.
- **No `nonisolated(unsafe)`** without a comment explaining why it's necessary and safe.

### Correct Patterns

**Task isolation — safe, do not flag in reviews:**

```swift
@MainActor
final class Foo {
    private var buffer: [Int] = []

    func start() {
        // Task inherits @MainActor from enclosing context (SE-0304).
        // buffer access is on MainActor — no await needed.
        Task { [weak self] in
            while let self, !self.buffer.isEmpty {
                try? await Task.sleep(for: .milliseconds(16))
                self.flush()
            }
        }
    }
}
```

**`isolated deinit` — required for `@MainActor` classes accessing non-Sendable stored properties:**

```swift
@MainActor
final class StreamOwner {
    private var timer: Task<Void, Never>?
    private let continuation: AsyncStream<Int>.Continuation

    // Runs on MainActor. Safe to access all stored properties.
    // Both `isolated deinit` and `@MainActor deinit` are valid (SE-0371),
    // but `isolated deinit` is preferred — it's more generic across actor types.
    isolated deinit {
        timer?.cancel()
        continuation.finish()
    }
}
```

**Note:** Nonisolated `deinit` can still access stored properties that have `Sendable` types (both `let` and `var`). The compilation error only occurs for non-Sendable stored properties. `Task<Void, Never>` and `AsyncStream.Continuation` are Sendable, but `isolated deinit` is still preferred for clarity and forward safety.

**AsyncStream creation — both patterns are safe:**

```swift
// Synchronous closure pattern (existing code, safe).
// The build closure executes synchronously — cont is always set before the unwrap.
var cont: AsyncStream<T>.Continuation?
let stream = AsyncStream<T> { cont = $0 }
let continuation = cont!

// makeStream factory (preferred for new code).
let (stream, continuation) = AsyncStream.makeStream(of: T.self)
```

`AsyncStream.Continuation` is `Sendable` — `yield()` and `finish()` are safe from any isolation context, including `isolated deinit`.

### Common False Positives

Agents reviewing Swift concurrency code must not flag these as bugs:

| Pattern | Why it's safe |
|---------|--------------|
| `Task { [weak self] in self?.prop }` in `@MainActor` method | Task inherits MainActor isolation (SE-0304) |
| `cont!` after `AsyncStream<T> { cont = $0 }` | Build closure is synchronous — cont is always set |
| `continuation.finish()` in `isolated deinit` | Continuation is Sendable, deinit runs on actor |
| Events emitted during `.draining` lifecycle | `.draining` is the lifecycle state where a runtime flushes remaining events before transitioning to `.terminated`. Events during draining are intentional — see [Contract 5](pane_runtime_architecture.md#contract-5-panelifecyclestatemachine). |
| `[weak self]` + `while let self` loop in Task | Strong ref held per iteration, released between iterations — no retain cycle |
| `DispatchQueue.main.async` in NSView subclasses | These classes are already `@MainActor`. The dispatch is redundant but compiles. Tracked as SwiftLint warnings for LUNA-325 migration — not a correctness bug. |

### SE Proposal Quick Reference

| Proposal | What it governs | Key rule |
|----------|----------------|----------|
| SE-0304 | Task isolation inheritance | `Task { }` inherits actor; `Task.detached { }` does not |
| SE-0371 | `isolated deinit` | Runs deinit on owning actor's executor (Swift 6.2) |
| SE-0388 | `AsyncStream.makeStream` | Factory returning `(stream, continuation)` tuple (Swift 5.9) |
| SE-0420 | Isolation inheritance refinement | Clarified `@_inheritActorContext` semantics for Task/TaskGroup |
| SE-0431 | `@isolated(any)` function types | Task.init uses `@isolated(any)` for correct executor enqueue |
| SE-0461 | `@concurrent` / `nonisolated(nonsending)` | `nonisolated async` inherits caller isolation by default (Swift 6.2); use `@concurrent` to explicitly run on cooperative pool |

---

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
│   └── PaneTabViewController
│
├── CommandBarBackdropView (NSView overlay, click to dismiss)
│
└── CommandBarPanel (NSPanel, child window)
    ├── NSVisualEffectView (.sidebar material)
    └── NSHostingView
        └── CommandBarView (SwiftUI)
            ├── CommandBarStatusStrip
            ├── CommandBarSearchField
            ├── CommandBarBreadcrumbRow (when nested)
            ├── CommandBarResultsList
            └── CommandBarFooter
```

### Keyboard Shortcuts

Four scopes open the same command bar with different prefix scoping:

| Shortcut | Prefix | Scope |
|----------|--------|-------|
| `⌘P` | _(none)_ | Everything — tabs, panes, commands, worktrees |
| `⌘⇧P` | `> ` | Commands only, grouped by category |
| `⌘⌥P` | `$ ` | Panes and tabs, grouped by parent tab |
| _(programmatic)_ | `# ` | Repos and worktrees for opening |

The first three shortcuts are registered as menu items in `AppDelegate` (responder chain routing). The repos scope (`# `) is triggered programmatically via `showCommandBarRepos()` (e.g., from the tab bar's "Open Repo/Worktree" button). Pressing the same shortcut again while the bar is open toggles it closed. Pressing a different shortcut while open switches the prefix in-place.

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
  ├── .dispatch(command)         → AppCommandDispatcher.dispatch() → full pipeline
  ├── .dispatchTargeted(cmd,id)  → AppCommandDispatcher.dispatch(_:target:targetType:)
  ├── .navigate(level)           → state.pushLevel() (nested drill-in)
  ├── .worktreeAction(presence)  → CommandBarWorktreeActionResolver → dispatch/navigate/choice
  └── .custom(closure)           → Direct execution (e.g., tab switching via Notification)
```

### Key Components

| Component | Role |
|-----------|------|
| `CommandBarPanelController` | Lifecycle: show/dismiss/toggle, backdrop, animation, state ownership. Depends on `WorkspaceStore` and `repoCache: RepoCacheAtom` |
| `CommandBarState` | Observable state: visibility, prefix parsing (`> `, `$ `, `# `), navigation stack, selection, recents |
| `CommandBarDataSource` | Builds `CommandBarItem` arrays from `WorkspaceStore`, `atom(\\.workspaceFocusContext).currentFocus`, and `AppCommandDispatcher` metadata |
| `CommandBarWorktreeActionResolver` | Resolves worktree selection into dispatch/navigate/choice based on presence state and modifier keys |
| `CommandBarSearch` | Custom fuzzy matching with score + character match ranges for highlighting |
| `CommandBarPanel` | `NSPanel` subclass with `NSVisualEffectView` and `NSHostingView` |
| `CommandBarView` | Root SwiftUI view composing search, results, shared focus context, and footer |

Notable views: `CommandBarBreadcrumbRow` (clickable nested navigation trail),
`CommandBarStatusStrip` (app mode display), `CommandBarSearchField` (search
input), and `CommandBarFooter` (contextual keyboard hints).

The command bar no longer owns its own hidden-command or grouping switches. `AppCommand` remains
the authoritative command ID, `AppCommandSpec` carries the authoritative metadata for dispatchable
commands, and `atom(\.workspaceFocus).currentFocus(...)` provides the shared app-wide focus context.
The command bar consumes those shared models; it does not define commands itself.

> **Files:** `CommandBar/CommandBarPanelController.swift`, `CommandBar/CommandBarState.swift`, `CommandBar/CommandBarPanel.swift`, `CommandBar/CommandBarDataSource.swift`, `CommandBar/CommandBarWorktreeActionResolver.swift`, `CommandBar/CommandBarSearch.swift`, `CommandBar/CommandBarItem.swift`, `CommandBar/Views/*.swift`

---

## Management Layer

Management layer enables split insertion and pane rearrangement. Three components coordinate the feature:

| Component | Location | Role |
|-----------|----------|------|
| `ManagementLayerAtom` | `Core/State/MainActor/Atoms/ManagementLayerAtom.swift` | Canonical active/inactive state |
| `ManagementLayerMonitor` | `App/Lifecycle/ManagementLayerMonitor.swift` | Observes atom state changes, drives side effects |
| `ManagementLayerToolbarButton` | `App/Lifecycle/ManagementLayerToolbarButton.swift` | Toolbar integration for toggling management layer |

Toggled via the command pipeline or the toolbar button. The command bar's `CommandBarStatusStrip` also reflects the current mode.

---

## Ghostty Terminal Integration

For the Ghostty surface lifecycle, ownership model, state machine, and health monitoring, see:

**[Ghostty Surface Architecture](ghostty_surface_architecture.md)**

## Session Restore

Terminal session state is managed by `WorkspaceStore` (persistence) and `SessionRuntime` (health/lifecycle). `WorkspaceSurfaceCoordinator` is the active intermediary for surface and runtime orchestration — views never call `SurfaceManager` or `SessionRuntime` directly. The zmx backend (`ZmxBackend`) provides session persistence across app restarts via raw byte passthrough daemons.

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
