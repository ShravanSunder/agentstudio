# Terminal Scrollback UX Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add Agent Studio host-side scrollback UX for embedded Ghostty terminals: always-visible scrollbar, search overlay, scroll-to-bottom indicator, and mouse cursor handling on top of the runtime event plumbing already merged on `main`.

**Architecture:** `origin/main` already contains the Ghostty/runtime event coverage we need: `scrollbar`, `startSearch`, `endSearch`, `searchTotal`, `searchSelected`, `mouseShape`, and `mouseVisibility` all reach `TerminalRuntime`, and the event channel already uses AsyncStream bus posting. This plan only adds the remaining host pieces: a config override for Ghostty core scroll behavior, AppKit wrapper views, `TerminalPaneMountView` composition, Find menu integration, and a small `TerminalRuntime` follow-up to expose mouse state as observable properties for the surface view.

**Smooth Scroll Requirement:** Fix the current mouse-wheel feel as part of this PR. Once the terminal is wrapped in the host scroll view, ordinary wheel/trackpad scrolling should go through `NSScrollView` first, matching Ghostty.app's host behavior, instead of relying on the current raw `ghostty_surface_mouse_scroll(...)` path in `Ghostty.SurfaceView.scrollWheel(with:)`.

**Tech Stack:** Swift 6.2, macOS 26, AppKit, GhosttyKit/libghostty, Swift Testing (`@Suite`, `@Test`, `#expect`), mise, swift-format, swiftlint

**Spec:** `docs/superpowers/specs/2026-04-06-terminal-scrollback-ux-design.md`

---

## Scope

This plan covers:

- Ghostty config override for `scroll-to-bottom = no-keystroke, no-output`
- Always-visible host-side `NSScrollView` wrapper for terminal panes
- Search overlay and Find menu integration
- Scroll-to-bottom floating indicator with unread-output state
- Runtime-owned mouse state plus surface-side cursor application

This plan does **not** cover:

- Reimplementing router/adapter/event-channel plumbing that is already on `main`
- Cross-pane search
- Find pasteboard integration
- Search bar dragging/repositioning
- Command-finished notification UI

## File Structure Map

**Create**

| File | Responsibility |
|------|---------------|
| `Sources/AgentStudio/Features/Terminal/Hosting/TerminalSurfaceActionPerforming.swift` | Small host protocol for sending Ghostty binding actions from AppKit views |
| `Sources/AgentStudio/Features/Terminal/Hosting/TerminalSurfaceScrollView.swift` | Always-visible host-side `NSScrollView` wrapper consuming `TerminalRuntime.scrollbarState` |
| `Sources/AgentStudio/Features/Terminal/Hosting/TerminalSearchOverlayView.swift` | Floating AppKit search bar for the focused pane |
| `Sources/AgentStudio/Features/Terminal/Hosting/ScrollToBottomIndicatorView.swift` | Floating jump-to-bottom affordance with unread-output indicator |
| `Tests/AgentStudioTests/Features/Terminal/Hosting/TerminalSurfaceScrollViewTests.swift` | Scroll math, follow-bottom, deduped drag behavior |
| `Tests/AgentStudioTests/Features/Terminal/Hosting/TerminalSearchOverlayViewTests.swift` | Overlay callback and label behavior |
| `Tests/AgentStudioTests/Features/Terminal/Hosting/ScrollToBottomIndicatorViewTests.swift` | Indicator visibility and unread-output behavior |
| `Tests/AgentStudioTests/Features/Terminal/Hosting/TerminalPaneMountViewSearchTests.swift` | Responder-chain search actions and runtime-driven overlay behavior |

**Modify**

| File | Change |
|------|--------|
| `Sources/AgentStudio/Features/Terminal/Ghostty/GhosttyAppHandle.swift` | Inject Agent Studio Ghostty config override before finalize |
| `Sources/AgentStudio/Features/Terminal/Runtime/TerminalRuntime.swift` | Add observable mouse state on top of already-landed mouse events |
| `Sources/AgentStudio/Features/Terminal/Ghostty/GhosttySurfaceView.swift` | Add `TerminalSurfaceActionPerforming` conformance and consume runtime mouse state |
| `Sources/AgentStudio/Features/Terminal/Hosting/GhosttyMountView.swift` | Promote mount boundary from raw surface-only to generic hosted terminal container |
| `Sources/AgentStudio/Features/Terminal/Hosting/TerminalPaneMountView.swift` | Compose scroll wrapper, search overlay, indicator, and runtime binding |
| `Sources/AgentStudio/App/Coordination/PaneCoordinator+ViewLifecycle.swift` | Bind `TerminalRuntime` into `TerminalPaneMountView` once both exist |
| `Sources/AgentStudio/App/Boot/AppDelegate.swift` | Add Edit > Find entries |
| `Tests/AgentStudioTests/Features/Terminal/Runtime/TerminalRuntimeTests.swift` | Add mouse runtime-state tests |
| `Tests/AgentStudioTests/Features/Terminal/Hosting/GhosttyMountViewTests.swift` | Update mount-boundary expectations for generic hosted terminal views |
| `docs/architecture/ghostty_surface_architecture.md` | Document host-side terminal scrollback UX boundary |

---

### Task 1: Inject Ghostty Scroll Behavior Overrides

**Files:**
- Modify: `Sources/AgentStudio/Features/Terminal/Ghostty/GhosttyAppHandle.swift`

- [ ] **Step 1: Write the failing config override test scaffold or inspection test**

If there is no existing focused test file for `GhosttyAppHandle`, add a minimal assertion in an adjacent test file that verifies the override helper writes the expected config contents.

```swift
@Test("ghostty config override disables built-in scroll-to-bottom behavior")
@MainActor
func configOverrideContainsExpectedScrollBehavior() throws {
    let overrideContents = Ghostty.AppHandle.ghosttyOverrideContentsForTesting
    #expect(overrideContents.contains("scroll-to-bottom = no-keystroke, no-output"))
}
```

- [ ] **Step 2: Run the focused test and confirm it fails**

Run:

```bash
SWIFT_BUILD_DIR=".build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8)"
swift test --build-path "$SWIFT_BUILD_DIR" --filter "ghostty config override disables built-in scroll-to-bottom behavior"
```

Expected:

- FAIL because the override helper and exposed test contents do not exist yet.

- [ ] **Step 3: Implement the override helper in `GhosttyAppHandle.swift`**

Add a helper that writes a temporary override file between `ghostty_config_load_default_files(config)` and `ghostty_config_finalize(config)`.

```swift
extension Ghostty {
    final class AppHandle {
        static let ghosttyOverrideContentsForTesting = """
        scroll-to-bottom = no-keystroke, no-output
        """

        private static func writeGhosttyOverrideFile() throws -> URL {
            let overrideURL = FileManager.default.temporaryDirectory
                .appending(path: "agent-studio-ghostty-overrides.conf")
            try ghosttyOverrideContentsForTesting.write(to: overrideURL, atomically: true, encoding: .utf8)
            return overrideURL
        }

        init?(runtimeConfig: ghostty_runtime_config_s) {
            guard let config = ghostty_config_new() else {
                ghosttyLogger.error("Failed to create ghostty config")
                return nil
            }

            ghostty_config_load_default_files(config)
            if let overrideURL = try? Self.writeGhosttyOverrideFile() {
                overrideURL.path.withCString { path in
                    ghostty_config_load_file(config, path)
                }
            } else {
                ghosttyLogger.error("Failed to write Ghostty override file")
            }
            ghostty_config_finalize(config)

            var mutableRuntimeConfig = runtimeConfig
            guard let app = ghostty_app_new(&mutableRuntimeConfig, config) else {
                ghosttyLogger.error("Failed to create ghostty app")
                ghostty_config_free(config)
                return nil
            }

            self.appHandle = app
            self.configHandle = config
        }
    }
}
```

- [ ] **Step 4: Run the focused test until it passes**

Run:

```bash
SWIFT_BUILD_DIR=".build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8)"
swift test --build-path "$SWIFT_BUILD_DIR" --filter "ghostty config override disables built-in scroll-to-bottom behavior"
```

Expected:

- PASS

- [ ] **Step 5: Commit the config override**

```bash
git add Sources/AgentStudio/Features/Terminal/Ghostty/GhosttyAppHandle.swift
git commit -F - <<'EOF'
feat: override ghostty scroll-to-bottom behavior for host scrollback UX

Co-authored-by: Codex <noreply@openai.com>
EOF
```

---

### Task 2: Add Runtime-Owned Mouse State

**Files:**
- Modify: `Sources/AgentStudio/Features/Terminal/Runtime/TerminalRuntime.swift`
- Modify: `Tests/AgentStudioTests/Features/Terminal/Runtime/TerminalRuntimeTests.swift`

- [ ] **Step 1: Write failing runtime tests for mouse state**

```swift
@Test("mouse events update observable runtime state")
@MainActor
func mouseEventsUpdateObservableRuntimeState() {
    let runtime = TerminalRuntime(
        paneId: PaneId(),
        metadata: PaneMetadata(
            source: .floating(launchDirectory: nil, title: "Runtime"),
            title: "Runtime"
        )
    )
    runtime.transitionToReady()

    runtime.handleGhosttyEvent(.mouseShapeChanged(shapeRawValue: 1))
    runtime.handleGhosttyEvent(.mouseVisibilityChanged(isVisible: false))

    #expect(runtime.mouseShapeRawValue == 1)
    #expect(runtime.isMouseVisible == false)
}
```

- [ ] **Step 2: Run the focused runtime tests and confirm failure**

Run:

```bash
SWIFT_BUILD_DIR=".build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8)"
swift test --build-path "$SWIFT_BUILD_DIR" --filter "mouseEventsUpdateObservableRuntimeState"
```

Expected:

- FAIL because `mouseShapeRawValue` and `isMouseVisible` do not exist yet.

- [ ] **Step 3: Add observable mouse state to `TerminalRuntime.swift`**

```swift
@Observable
final class TerminalRuntime: BusPostingPaneRuntime {
    private(set) var mouseShapeRawValue: UInt32?
    private(set) var isMouseVisible: Bool = true

    private func handleGhosttyConfigurationEvent(
        _ event: GhosttyEvent,
        commandId: UUID?,
        correlationId: UUID?
    ) -> Bool {
        switch event {
        case .mouseShapeChanged(let rawValue):
            mouseShapeRawValue = rawValue
            emit(event, commandId: commandId, correlationId: correlationId, persistForReplay: false)
            return true
        case .mouseVisibilityChanged(let isVisible):
            isMouseVisible = isVisible
            emit(event, commandId: commandId, correlationId: correlationId, persistForReplay: false)
            return true
        case .mouseLinkHovered, .keySequenceChanged, .keyTableChanged:
            emit(event, commandId: commandId, correlationId: correlationId, persistForReplay: false)
            return true
        case .colorChanged, .configChanged:
            emit(event, commandId: commandId, correlationId: correlationId, persistForReplay: true)
            return true
        case .configReloadRequested:
            emit(event, commandId: commandId, correlationId: correlationId, persistForReplay: false)
            return true
        default:
            return false
        }
    }
}
```

- [ ] **Step 4: Run the focused runtime tests until they pass**

Run:

```bash
SWIFT_BUILD_DIR=".build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8)"
swift test --build-path "$SWIFT_BUILD_DIR" --filter "mouseEventsUpdateObservableRuntimeState"
```

Expected:

- PASS

- [ ] **Step 5: Commit the runtime mouse follow-up**

```bash
git add \
  Sources/AgentStudio/Features/Terminal/Runtime/TerminalRuntime.swift \
  Tests/AgentStudioTests/Features/Terminal/Runtime/TerminalRuntimeTests.swift
git commit -F - <<'EOF'
feat: expose mouse state on terminal runtime for host cursor handling

Co-authored-by: Codex <noreply@openai.com>
EOF
```

---

### Task 3: Add Host Scroll Wrapper, Search Overlay, And Scroll-To-Bottom Indicator

**Files:**
- Create: `Sources/AgentStudio/Features/Terminal/Hosting/TerminalSurfaceActionPerforming.swift`
- Create: `Sources/AgentStudio/Features/Terminal/Hosting/TerminalSurfaceScrollView.swift`
- Create: `Sources/AgentStudio/Features/Terminal/Hosting/TerminalSearchOverlayView.swift`
- Create: `Sources/AgentStudio/Features/Terminal/Hosting/ScrollToBottomIndicatorView.swift`
- Modify: `Sources/AgentStudio/Features/Terminal/Hosting/GhosttyMountView.swift`
- Modify: `Tests/AgentStudioTests/Features/Terminal/Hosting/GhosttyMountViewTests.swift`
- Test: `Tests/AgentStudioTests/Features/Terminal/Hosting/TerminalSurfaceScrollViewTests.swift`
- Test: `Tests/AgentStudioTests/Features/Terminal/Hosting/TerminalSearchOverlayViewTests.swift`
- Test: `Tests/AgentStudioTests/Features/Terminal/Hosting/ScrollToBottomIndicatorViewTests.swift`

- [ ] **Step 1: Add the host action protocol**

Create `Sources/AgentStudio/Features/Terminal/Hosting/TerminalSurfaceActionPerforming.swift`:

```swift
import AppKit
import GhosttyKit

@MainActor
protocol TerminalSurfaceActionPerforming: AnyObject {
    @discardableResult
    func performBindingAction(_ action: String) -> Bool
}

extension Ghostty.SurfaceView: TerminalSurfaceActionPerforming {
    @discardableResult
    func performBindingAction(_ action: String) -> Bool {
        guard let surface else { return false }
        return action.withCString { ptr in
            ghostty_surface_binding_action(surface, ptr, UInt(action.utf8.count))
        }
    }
}
```

- [ ] **Step 2: Write the failing host-view tests**

Add focused tests that exercise:

```swift
@Test("scroll wrapper converts live drag into scroll_to_row")
@MainActor
func scrollWrapperConvertsLiveDragIntoScrollToRow() {
    let performer = FakeSurfaceActionPerformer()
    let scrollView = TerminalSurfaceScrollView(actionPerformer: performer)

    scrollView.applyScrollbarState(
        ScrollbarState(top: 80, bottom: 120, total: 200),
        cellHeight: 20
    )
    scrollView.simulateLiveScrollForTesting(documentOffsetY: 1200)

    #expect(performer.actions.last?.starts(with: "scroll_to_row:") == true)
}

@Test("scroll wrapper is the primary scrollback host for wheel scrolling")
@MainActor
func scrollWrapperOwnsWheelScrolling() {
    let performer = FakeSurfaceActionPerformer()
    let scrollView = TerminalSurfaceScrollView(actionPerformer: performer)

    scrollView.applyScrollbarState(
        ScrollbarState(top: 80, bottom: 120, total: 200),
        cellHeight: 20
    )
    scrollView.simulateLiveScrollForTesting(documentOffsetY: 1180)

    #expect(performer.actions.last?.starts(with: "scroll_to_row:") == true)
}

@Test("search overlay emits expected callbacks")
@MainActor
func searchOverlayEmitsExpectedCallbacks() {
    let overlay = TerminalSearchOverlayView()
    var capturedQuery: String?
    var capturedDirections: [TerminalSearchOverlayView.NavigationDirection] = []
    var closeCount = 0

    overlay.onQueryChanged = { capturedQuery = $0 }
    overlay.onNavigate = { capturedDirections.append($0) }
    overlay.onClose = { closeCount += 1 }

    overlay.simulateQueryChangeForTesting("needle")
    overlay.simulateNavigateForTesting(.next)
    overlay.simulateNavigateForTesting(.previous)
    overlay.simulateCloseForTesting()

    #expect(capturedQuery == "needle")
    #expect(capturedDirections == [.next, .previous])
    #expect(closeCount == 1)
}

@Test("scroll-to-bottom indicator shows unread output while scrolled up")
@MainActor
func scrollToBottomIndicatorShowsUnreadOutputWhileScrolledUp() {
    let view = ScrollToBottomIndicatorView()

    view.applyScrollbarState(ScrollbarState(top: 80, bottom: 120, total: 200))
    #expect(view.isHidden == false)
    #expect(view.hasNewOutputForTesting == false)

    view.applyScrollbarState(ScrollbarState(top: 80, bottom: 120, total: 210))
    #expect(view.hasNewOutputForTesting == true)
}
```

- [ ] **Step 3: Run the focused hosting tests and confirm failure**

Run:

```bash
SWIFT_BUILD_DIR=".build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8)"
swift test --build-path "$SWIFT_BUILD_DIR" --filter "TerminalSurfaceScrollViewTests|TerminalSearchOverlayViewTests|ScrollToBottomIndicatorViewTests|GhosttyMountViewTests"
```

Expected:

- FAIL because the new host views and generic mount behavior do not exist yet.

- [ ] **Step 4: Implement the generic mount boundary and host views**

Promote `GhosttyMountView` from raw-surface-only mounting to generic hosted terminal content:

```swift
@MainActor
final class GhosttyMountView: NSView {
    private(set) var mountedView: NSView?

    func mount(_ view: NSView) {
        unmountCurrentView()
        view.translatesAutoresizingMaskIntoConstraints = false
        addSubview(view)
        NSLayoutConstraint.activate([
            view.topAnchor.constraint(equalTo: topAnchor),
            view.leadingAnchor.constraint(equalTo: leadingAnchor),
            view.trailingAnchor.constraint(equalTo: trailingAnchor),
            view.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        mountedView = view
    }

    func unmountCurrentView() {
        mountedView?.removeFromSuperview()
        mountedView = nil
    }
}
```

Implement `TerminalSurfaceScrollView` as a three-layer wrapper:

```swift
@MainActor
final class TerminalSurfaceScrollView: NSView {
    private let scrollView = NSScrollView()
    private let documentView = NSView()
    private weak var actionPerformer: (any TerminalSurfaceActionPerforming)?
    private weak var surfaceView: Ghostty.SurfaceView?
    private var lastSentRow: Int?
    private var isLiveScrolling = false
    private var previousScrollbarState: ScrollbarState?

    init(actionPerformer: any TerminalSurfaceActionPerforming) {
        self.actionPerformer = actionPerformer
        super.init(frame: .zero)
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = false
        scrollView.documentView = documentView
        addSubview(scrollView)
    }

    func embedSurfaceView(_ surfaceView: Ghostty.SurfaceView) {
        self.surfaceView = surfaceView
        documentView.addSubview(surfaceView)
    }

    func applyScrollbarState(_ state: ScrollbarState, cellHeight: CGFloat) {
        guard cellHeight > 0 else { return }
        let wasPinnedToBottom = previousScrollbarState.map { $0.bottom >= $0.total } ?? true
        previousScrollbarState = state

        let visibleRowCount = max(0, state.bottom - state.top)
        let totalHeight = CGFloat(state.total) * cellHeight
        documentView.setFrameSize(CGSize(width: scrollView.contentSize.width, height: totalHeight))

        if !isLiveScrolling && wasPinnedToBottom {
            let offsetY = CGFloat(state.total - state.bottom) * cellHeight
            scrollView.contentView.scroll(to: CGPoint(x: 0, y: offsetY))
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }
    }
}
```

When implementing this wrapper, make it the primary scrollback host for ordinary wheel/trackpad scrolling, matching Ghostty.app's `SurfaceScrollView` behavior. The goal is to replace the current direct discrete-wheel path that can feel like a page jump.

Implementation constraints:

- `NSScrollView` owns the visible wheel/trackpad scrolling behavior.
- `didLiveScroll` / clip-view observation translates the visible position back into `scroll_to_row:N`.
- `scroll_to_row:N` remains the synchronization action between host UI and Ghostty core.
- The old direct `Ghostty.SurfaceView.scrollWheel(with:)` path should no longer be the primary scrollback UX path when the surface is embedded in the wrapper.

Implement `TerminalSearchOverlayView` and `ScrollToBottomIndicatorView` as pure AppKit views with callback closures and test helpers.

- [ ] **Step 5: Run the hosting tests until they pass**

Run:

```bash
SWIFT_BUILD_DIR=".build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8)"
swift test --build-path "$SWIFT_BUILD_DIR" --filter "TerminalSurfaceScrollViewTests|TerminalSearchOverlayViewTests|ScrollToBottomIndicatorViewTests|GhosttyMountViewTests"
```

Expected:

- PASS

- [ ] **Step 6: Commit the host view layer**

```bash
git add \
  Sources/AgentStudio/Features/Terminal/Hosting/TerminalSurfaceActionPerforming.swift \
  Sources/AgentStudio/Features/Terminal/Hosting/TerminalSurfaceScrollView.swift \
  Sources/AgentStudio/Features/Terminal/Hosting/TerminalSearchOverlayView.swift \
  Sources/AgentStudio/Features/Terminal/Hosting/ScrollToBottomIndicatorView.swift \
  Sources/AgentStudio/Features/Terminal/Hosting/GhosttyMountView.swift \
  Tests/AgentStudioTests/Features/Terminal/Hosting/TerminalSurfaceScrollViewTests.swift \
  Tests/AgentStudioTests/Features/Terminal/Hosting/TerminalSearchOverlayViewTests.swift \
  Tests/AgentStudioTests/Features/Terminal/Hosting/ScrollToBottomIndicatorViewTests.swift \
  Tests/AgentStudioTests/Features/Terminal/Hosting/GhosttyMountViewTests.swift
git commit -F - <<'EOF'
feat: add host-side terminal scrollback ui primitives

Co-authored-by: Codex <noreply@openai.com>
EOF
```

---

### Task 4: Compose The UX In `TerminalPaneMountView` And Add Find Menu Integration

**Files:**
- Modify: `Sources/AgentStudio/Features/Terminal/Hosting/TerminalPaneMountView.swift`
- Modify: `Sources/AgentStudio/App/Coordination/PaneCoordinator+ViewLifecycle.swift`
- Modify: `Sources/AgentStudio/Features/Terminal/Ghostty/GhosttySurfaceView.swift`
- Modify: `Sources/AgentStudio/App/Boot/AppDelegate.swift`
- Create: `Tests/AgentStudioTests/Features/Terminal/Hosting/TerminalPaneMountViewSearchTests.swift`

- [ ] **Step 1: Write the failing mount-view integration tests**

```swift
@Test("mount view search responders send exact ghostty binding actions")
@MainActor
func mountViewSearchRespondersSendExactGhosttyBindingActions() {
    let mountView = TerminalPaneMountView(paneId: UUID(), title: "Terminal")
    let performer = FakeSurfaceActionPerformer()
    mountView.installActionPerformerForTesting(performer)

    mountView.startSearch(nil)
    mountView.findNext(nil)
    mountView.findPrevious(nil)
    mountView.cancelOperation(nil)

    #expect(performer.actions == [
        "start_search",
        "navigate_search:next",
        "navigate_search:previous",
        "end_search",
    ])
}
```

- [ ] **Step 2: Run the focused mount-view tests and confirm failure**

Run:

```bash
SWIFT_BUILD_DIR=".build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8)"
swift test --build-path "$SWIFT_BUILD_DIR" --filter "TerminalPaneMountViewSearchTests"
```

Expected:

- FAIL because runtime binding, responder methods, and test seams do not exist yet.

- [ ] **Step 3: Compose the scroll wrapper, overlay, and indicator in `TerminalPaneMountView`**

Key changes:

```swift
private var surfaceScrollView: TerminalSurfaceScrollView?
private var searchOverlayView: TerminalSearchOverlayView?
private var scrollToBottomIndicatorView: ScrollToBottomIndicatorView?
private weak var boundRuntime: TerminalRuntime?
private var actionPerformerOverrideForTesting: (any TerminalSurfaceActionPerforming)?

private var currentActionPerformer: (any TerminalSurfaceActionPerforming)? {
    actionPerformerOverrideForTesting ?? ghosttySurface
}

func displaySurface(_ surfaceView: Ghostty.SurfaceView) {
    ghosttySurface?.onCloseRequested = nil
    ghosttyMountView.unmountCurrentView()
    clearPlaceholder()

    let wrappedScrollView = TerminalSurfaceScrollView(actionPerformer: surfaceView)
    wrappedScrollView.embedSurfaceView(surfaceView)
    ghosttyMountView.mount(wrappedScrollView)
    surfaceScrollView = wrappedScrollView
    ghosttySurface = surfaceView
    lastReportedSurfaceSize = .zero

    beginRestorePresentationIfNeeded()
    surfaceView.onCloseRequested = { [weak self] processAlive in
        self?.handleSurfaceClose(processAlive: processAlive)
    }
}
```

Bind the runtime:

```swift
func bind(runtime: TerminalRuntime) {
    boundRuntime = runtime
    observeScrollbarAndSearchState()
}
```

Add responders:

```swift
@objc func startSearch(_ sender: Any?) {
    ensureSearchOverlay()
    _ = currentActionPerformer?.performBindingAction("start_search")
}

@objc func findNext(_ sender: Any?) {
    _ = currentActionPerformer?.performBindingAction("navigate_search:next")
}

@objc func findPrevious(_ sender: Any?) {
    _ = currentActionPerformer?.performBindingAction("navigate_search:previous")
}

@objc override func cancelOperation(_ sender: Any?) {
    guard searchOverlayView != nil else {
        super.cancelOperation(sender)
        return
    }

    _ = currentActionPerformer?.performBindingAction("end_search")
    hideSearchOverlay()
}
```

Expose a test seam:

```swift
func installActionPerformerForTesting(_ performer: any TerminalSurfaceActionPerforming) {
    actionPerformerOverrideForTesting = performer
}
```

- [ ] **Step 4: Bind runtime from `PaneCoordinator+ViewLifecycle.swift`**

After runtime registration, bind the terminal view if both exist:

```swift
private func registerTerminalRuntimeIfNeeded(for pane: Pane) {
    // existing runtime creation

    let terminalRuntime = TerminalRuntime(
        paneId: runtimePaneId,
        metadata: pane.metadata
    )
    guard terminalRuntime.transitionToReady() else { return }
    registerRuntime(terminalRuntime)

    if let terminalView = viewRegistry.terminalView(for: pane.id) {
        terminalView.bind(runtime: terminalRuntime)
    }
}
```

Also bind on reattach/recreate paths where the runtime already exists and a new mount view is attached.

- [ ] **Step 5: Consume runtime-owned mouse state in `GhosttySurfaceView.swift`**

Add a lightweight bind method and cursor application helpers:

```swift
private weak var terminalRuntime: TerminalRuntime?
private var lastAppliedMouseVisibility = true

func bindRuntime(_ runtime: TerminalRuntime) {
    terminalRuntime = runtime
    observeMouseState()
}

private func observeMouseState() {
    guard let runtime = terminalRuntime else { return }
    withObservationTracking {
        _ = runtime.mouseShapeRawValue
        _ = runtime.isMouseVisible
    } onChange: { [weak self] in
        Task { @MainActor [weak self] in
            guard let self, let runtime = self.terminalRuntime else { return }
            self.applyMouseShape(rawValue: runtime.mouseShapeRawValue)
            self.applyMouseVisibility(isVisible: runtime.isMouseVisible)
            self.observeMouseState()
        }
    }
}
```

- [ ] **Step 6: Add Find menu entries in `AppDelegate.swift`**

Insert a Find submenu under Edit:

```swift
let findMenu = NSMenu(title: "Find")
findMenu.addItem(NSMenuItem(title: "Find…", action: Selector(("startSearch:")), keyEquivalent: "f"))
findMenu.addItem(NSMenuItem(title: "Find Next", action: Selector(("findNext:")), keyEquivalent: "g"))
let findPreviousItem = NSMenuItem(title: "Find Previous", action: Selector(("findPrevious:")), keyEquivalent: "G")
findPreviousItem.keyEquivalentModifierMask = [.command, .shift]
findMenu.addItem(findPreviousItem)

let findMenuItem = NSMenuItem()
findMenuItem.submenu = findMenu
editMenu.addItem(NSMenuItem.separator())
editMenu.addItem(findMenuItem)
```

- [ ] **Step 7: Run the focused integration tests until they pass**

Run:

```bash
SWIFT_BUILD_DIR=".build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8)"
swift test --build-path "$SWIFT_BUILD_DIR" --filter "TerminalPaneMountViewSearchTests|TerminalRuntimeTests"
```

Expected:

- PASS

- [ ] **Step 8: Commit the composed host integration**

```bash
git add \
  Sources/AgentStudio/Features/Terminal/Hosting/TerminalPaneMountView.swift \
  Sources/AgentStudio/App/Coordination/PaneCoordinator+ViewLifecycle.swift \
  Sources/AgentStudio/Features/Terminal/Ghostty/GhosttySurfaceView.swift \
  Sources/AgentStudio/App/Boot/AppDelegate.swift \
  Tests/AgentStudioTests/Features/Terminal/Hosting/TerminalPaneMountViewSearchTests.swift
git commit -F - <<'EOF'
feat: compose terminal scrollback ux into pane mount view

Co-authored-by: Codex <noreply@openai.com>
EOF
```

---

### Task 5: Document The Boundary And Run Full Verification

**Files:**
- Modify: `docs/architecture/ghostty_surface_architecture.md`

- [ ] **Step 1: Update the architecture doc**

Add a short section documenting that:

- runtime event plumbing for scrollbar/search now lives on `main`
- Agent Studio supplies its own host-side scrollbar and search UI
- Ghostty core remains the source of scroll/search truth

```markdown
## Host Scrollback UX Boundary

Agent Studio consumes libghostty/runtime scrollback facts (`scrollbarState`, `searchState`) but renders its own macOS host UI for scrollbars, search, and jump-to-bottom affordances. This differs from Ghostty.app, which ships its own host-side `SurfaceScrollView` and search presentation on top of the same embedded runtime.
```

- [ ] **Step 2: Format**

Run:

```bash
mise run format
```

Expected:

- exit code `0`

- [ ] **Step 3: Lint**

Run:

```bash
mise run lint
```

Expected:

- `swift-format: OK`
- `swiftlint: OK`
- boundary checks pass
- exit code `0`

- [ ] **Step 4: Full tests**

Run:

```bash
AGENT_RUN_ID="$(uuidgen | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9' | head -c 12)" mise run test
```

Expected:

- full suite passes
- exit code `0`

- [ ] **Step 5: Commit the architecture doc update**

```bash
git add docs/architecture/ghostty_surface_architecture.md
git commit -F - <<'EOF'
docs: record terminal scrollback host boundary

Co-authored-by: Codex <noreply@openai.com>
EOF
```
