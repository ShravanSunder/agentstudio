# Ghostty Custom Overlay Scrollbar Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the visible native Ghostty terminal scrollbar with a host-owned thin overlay scrollbar that stays thin at startup, reveals on hover over the gutter, and remains independent of macOS `Show scroll bars = Always`.

**Architecture:** Keep Ghostty core authoritative for scroll position and scrollback state. Use the existing `TerminalRuntime.scrollbarState` as the source of truth and the existing `TerminalSurfaceActionPerforming` seam (`scroll_to_row`, `scroll_to_bottom`) as the output path. The native `NSScrollView` remains an internal scrolling mechanism only; the visible terminal scrollbar becomes a custom overlay view mounted by `TerminalPaneMountView`.

**Tech Stack:** Swift 6.2, AppKit, GhosttyKit, Swift Testing, Peekaboo

---

## Grounding

This plan is grounded in the following existing code and research:

- Ghostty macOS host keeps scrollbar ownership in `SurfaceScrollView`, not in terminal core:
  [vendor/ghostty/macos/Sources/Ghostty/Surface View/SurfaceScrollView.swift](/Users/shravansunder/Documents/dev/project-dev/agent-studio.fix-scroll/vendor/ghostty/macos/Sources/Ghostty/Surface%20View/SurfaceScrollView.swift)
- Ghostty surface state already publishes scrollbar information through `Ghostty.Action.Scrollbar`, which Agent Studio already routes into runtime state:
  [Sources/AgentStudio/Features/Terminal/Ghostty/GhosttyActionRouter+ObservedActions.swift](/Users/shravansunder/Documents/dev/project-dev/agent-studio.fix-scroll/Sources/AgentStudio/Features/Terminal/Ghostty/GhosttyActionRouter+ObservedActions.swift)
- Agent Studio already exposes the exact action seam needed to control Ghostty scrolling from the host:
  [Sources/AgentStudio/Features/Terminal/Hosting/TerminalSurfaceActionPerforming.swift](/Users/shravansunder/Documents/dev/project-dev/agent-studio.fix-scroll/Sources/AgentStudio/Features/Terminal/Hosting/TerminalSurfaceActionPerforming.swift)
- Terminal overlays already live in `TerminalPaneMountView` and are hit-tested there:
  [Sources/AgentStudio/Features/Terminal/Hosting/TerminalPaneMountView.swift](/Users/shravansunder/Documents/dev/project-dev/agent-studio.fix-scroll/Sources/AgentStudio/Features/Terminal/Hosting/TerminalPaneMountView.swift)
  [Sources/AgentStudio/Features/Terminal/Hosting/TerminalPaneMountView+SearchAndOverlays.swift](/Users/shravansunder/Documents/dev/project-dev/agent-studio.fix-scroll/Sources/AgentStudio/Features/Terminal/Hosting/TerminalPaneMountView+SearchAndOverlays.swift)
- Native AppKit scroller behavior is still influenced by `NSScroller.preferredScrollerStyle`, which is determined by the user’s Appearance setting:
  https://developer.apple.com/documentation/appkit/nsscroller/preferredscrollerstyle

## Scope Notes

- **In scope:** Ghostty terminal panes only
- **Out of scope:** sidebar, webview, bridge, code viewer, generic AppKit scrollbar behavior
- Hard requirements this plan must satisfy:
  - no fat startup terminal scrollbar
  - hover over the scrollbar gutter reveals a scrollbar
  - revealed scrollbar remains thin
  - macOS `Show scroll bars = Always` must not break terminal behavior

## File Structure

- Modify: `Sources/AgentStudio/Features/Terminal/Ghostty/GhosttyAppHandle.swift`
  - Keep embedded Ghostty from competing for visible scrollbar ownership (`scrollbar = never`).
- Create: `Sources/AgentStudio/Features/Terminal/Hosting/TerminalOverlayScrollbarModel.swift`
  - Own the pure geometry/visibility/drag math for the terminal overlay scrollbar so it can be tested without AppKit-only hooks.
- Create: `Sources/AgentStudio/Features/Terminal/Hosting/TerminalOverlayScrollbarView.swift`
  - Own the AppKit overlay view, hover tracking, drawing, and delegation to the model.
- Modify: `Sources/AgentStudio/Features/Terminal/Hosting/TerminalPaneMountView.swift`
  - Host the overlay scrollbar view alongside existing terminal overlays.
- Modify: `Sources/AgentStudio/Features/Terminal/Hosting/TerminalPaneMountView+SearchAndOverlays.swift`
  - Wire runtime scrollbar state into the overlay and define hit-test priority.
- Modify: `Sources/AgentStudio/Features/Terminal/Hosting/TerminalSurfaceScrollView.swift`
  - Keep native scroll mechanics, but ensure the native visible scroller stays hidden.
- Modify: `Sources/AgentStudio/Features/Terminal/Hosting/ScrollToBottomIndicatorView.swift`
  - Adjust bottom-right placement if needed so it doesn’t overlap the overlay scrollbar gutter.
- Test: `Tests/AgentStudioTests/Features/Terminal/Ghostty/GhosttyAppHandleTests.swift`
  - Assert embedded Ghostty override still disables visible scrollbar ownership.
- Create: `Tests/AgentStudioTests/Features/Terminal/Hosting/TerminalOverlayScrollbarModelTests.swift`
  - Cover thumb geometry, visibility state, and drag-to-row conversion.
- Create: `Tests/AgentStudioTests/Features/Terminal/Hosting/TerminalOverlayScrollbarViewTests.swift`
  - Cover hover behavior and handoff from the AppKit view to the model.
- Modify: `Tests/AgentStudioTests/Features/Terminal/Hosting/TerminalPaneMountViewSearchTests.swift`
  - Verify overlay installation, hit-testing priority, and overlay coexistence with other terminal overlays.
- Modify: `Tests/AgentStudioTests/Features/Terminal/Hosting/TerminalSurfaceScrollViewTests.swift`
  - Assert native visible scroller remains hidden while scroll mechanics still work.
- Modify: `Tests/AgentStudioTests/Features/Terminal/Hosting/ScrollToBottomIndicatorViewTests.swift`
  - Keep unread-output behavior correct after layout adjustments.
- Create: `Tests/AgentStudioTests/Features/Terminal/Hosting/TerminalSurfaceActionPerformerSpy.swift`
  - Shared spy used by overlay tests to avoid duplicating `FakeSurfaceActionPerformer`.

### Task 1: Keep Embedded Ghostty Out of Visible Scrollbar Ownership

**Files:**
- Modify: `Sources/AgentStudio/Features/Terminal/Ghostty/GhosttyAppHandle.swift`
- Test: `Tests/AgentStudioTests/Features/Terminal/Ghostty/GhosttyAppHandleTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
@Test("ghostty config override disables built-in scroll-to-bottom behavior and scrollbar ownership")
func configOverrideContainsExpectedScrollBehavior() {
    let overrideContents = Ghostty.AppHandle.scrollBehaviorOverrideContents

    #expect(overrideContents.contains("scroll-to-bottom = no-keystroke, no-output"))
    #expect(overrideContents.contains("scrollbar = never"))
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
SWIFT_BUILD_DIR=.build-agent-ghostty-overlay swift test \
  --build-path .build-agent-ghostty-overlay \
  --filter 'GhosttyAppHandleTests'
```

Expected:

```text
FAIL
Expected overrideContents to contain "scrollbar = never"
```

- [ ] **Step 3: Verify the core assumption before implementation**

Run:

```bash
rg -n "scrollbar: Scrollbar = \\.system|hasVerticalScroller = scrollbarConfig != \\.never" \
  vendor/ghostty/src/config/Config.zig \
  vendor/ghostty/macos/Sources/Ghostty/Surface\ View/SurfaceScrollView.swift
```

Expected:

```text
vendor/ghostty/src/config/Config.zig:... scrollbar: Scrollbar = .system
vendor/ghostty/macos/Sources/Ghostty/Surface View/SurfaceScrollView.swift:... hasVerticalScroller = scrollbarConfig != .never
```

This confirms `scrollbar = never` only disables visible native scrollbar ownership in the Ghostty host path; it does not remove terminal scrolling actions from the core.

- [ ] **Step 4: Write minimal implementation**

```swift
static let scrollBehaviorOverrideContents = """
    scroll-to-bottom = no-keystroke, no-output
    scrollbar = never
    """
```

- [ ] **Step 5: Run test to verify it passes**

Run:

```bash
SWIFT_BUILD_DIR=.build-agent-ghostty-overlay swift test \
  --build-path .build-agent-ghostty-overlay \
  --filter 'GhosttyAppHandleTests'
```

Expected:

```text
PASS
```

- [ ] **Step 6: Commit**

```bash
git add \
  Sources/AgentStudio/Features/Terminal/Ghostty/GhosttyAppHandle.swift \
  Tests/AgentStudioTests/Features/Terminal/Ghostty/GhosttyAppHandleTests.swift
git commit -m "fix: remove native ghostty scrollbar ownership"
```

### Task 2: Build a Pure Overlay Scrollbar Model

**Files:**
- Create: `Sources/AgentStudio/Features/Terminal/Hosting/TerminalOverlayScrollbarModel.swift`
- Create: `Tests/AgentStudioTests/Features/Terminal/Hosting/TerminalOverlayScrollbarModelTests.swift`
- Create: `Tests/AgentStudioTests/Features/Terminal/Hosting/TerminalSurfaceActionPerformerSpy.swift`

- [ ] **Step 1: Write the failing tests**

```swift
import AppKit
import Testing

@testable import AgentStudio

@MainActor
@Suite("TerminalOverlayScrollbarModel")
struct TerminalOverlayScrollbarModelTests {
    @Test("model stays hidden without scrollbar state")
    func modelStaysHiddenWithoutScrollbarState() {
        var model = TerminalOverlayScrollbarModel()

        model.update(scrollbarState: nil, viewportHeight: 600)

        #expect(model.visibility == .hidden)
        #expect(model.thumbFrame == .zero)
    }

    @Test("model computes thumb geometry from scrollbar state")
    func modelComputesThumbGeometryFromScrollbarState() {
        var model = TerminalOverlayScrollbarModel()

        model.update(
            scrollbarState: ScrollbarState(top: 80, bottom: 120, total: 200),
            viewportHeight: 600
        )

        #expect(model.thumbFrame.height >= 36)
        #expect(model.thumbFrame.maxY <= 600)
    }

    @Test("hover reveals model when scrollback exists")
    func hoverRevealsModelWhenScrollbackExists() {
        var model = TerminalOverlayScrollbarModel()

        model.update(
            scrollbarState: ScrollbarState(top: 80, bottom: 120, total: 200),
            viewportHeight: 600
        )
        model.handleHoverChanged(true)

        #expect(model.visibility == .visible)
    }

    @Test("drag location maps to scrollToRow action")
    func dragLocationMapsToScrollToRowAction() {
        let spy = TerminalSurfaceActionPerformerSpy()
        var model = TerminalOverlayScrollbarModel()

        model.update(
            scrollbarState: ScrollbarState(top: 80, bottom: 120, total: 200),
            viewportHeight: 600
        )
        model.handleThumbDrag(relativeY: 0.5, actionPerformer: spy)

        guard case .scrollToRow(let row)? = spy.actions.last else {
            Issue.record("Expected scrollToRow action")
            return
        }
        #expect(row >= 0)
    }
}
```

Create the shared test spy:

```swift
import Testing

@testable import AgentStudio

@MainActor
final class TerminalSurfaceActionPerformerSpy: TerminalSurfaceActionPerforming {
    private(set) var actions: [TerminalSurfaceAction] = []

    @discardableResult
    func performBindingAction(_ action: TerminalSurfaceAction) -> Bool {
        actions.append(action)
        return true
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
SWIFT_BUILD_DIR=.build-agent-ghostty-overlay swift test \
  --build-path .build-agent-ghostty-overlay \
  --filter 'TerminalOverlayScrollbarModelTests'
```

Expected:

```text
FAIL
Cannot find 'TerminalOverlayScrollbarModel' in scope
```

- [ ] **Step 3: Write minimal implementation**

```swift
import AppKit

@MainActor
enum TerminalOverlayScrollbarVisibility: Equatable {
    case hidden
    case visible
}

@MainActor
struct TerminalOverlayScrollbarModel {
    private(set) var scrollbarState: ScrollbarState?
    private(set) var thumbFrame: NSRect = .zero
    private(set) var visibility: TerminalOverlayScrollbarVisibility = .hidden
    private var isHovering = false
    private var isDragging = false

    mutating func update(scrollbarState: ScrollbarState?, viewportHeight: CGFloat) {
        self.scrollbarState = scrollbarState

        guard let scrollbarState, scrollbarState.total > scrollbarState.visibleRowCount, viewportHeight > 0 else {
            thumbFrame = .zero
            visibility = .hidden
            return
        }

        let visibleFraction = CGFloat(scrollbarState.visibleRowCount) / CGFloat(scrollbarState.total)
        let thumbHeight = max(36, viewportHeight * visibleFraction)
        let maximumOffset = max(0, viewportHeight - thumbHeight)
        let topFraction = CGFloat(scrollbarState.top) / CGFloat(max(1, scrollbarState.total - scrollbarState.visibleRowCount))
        let thumbY = maximumOffset * (1 - topFraction)
        thumbFrame = NSRect(x: 0, y: thumbY, width: 12, height: thumbHeight)
        visibility = (isHovering || isDragging) ? .visible : .hidden
    }

    mutating func handleHoverChanged(_ isHovering: Bool) {
        self.isHovering = isHovering
        visibility = (isHovering || isDragging) ? .visible : .hidden
    }

    mutating func handleThumbDrag(relativeY: CGFloat, actionPerformer: any TerminalSurfaceActionPerforming) {
        guard let scrollbarState else { return }
        isDragging = true
        visibility = .visible
        let clamped = min(max(0, relativeY), 1)
        let row = Int(CGFloat(max(0, scrollbarState.total - scrollbarState.visibleRowCount)) * clamped)
        _ = actionPerformer.performBindingAction(.scrollToRow(row))
    }

    mutating func endThumbDrag() {
        isDragging = false
        visibility = isHovering ? .visible : .hidden
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run:

```bash
SWIFT_BUILD_DIR=.build-agent-ghostty-overlay swift test \
  --build-path .build-agent-ghostty-overlay \
  --filter 'TerminalOverlayScrollbarModelTests'
```

Expected:

```text
PASS
```

- [ ] **Step 5: Commit**

```bash
git add \
  Sources/AgentStudio/Features/Terminal/Hosting/TerminalOverlayScrollbarModel.swift \
  Tests/AgentStudioTests/Features/Terminal/Hosting/TerminalOverlayScrollbarModelTests.swift \
  Tests/AgentStudioTests/Features/Terminal/Hosting/TerminalSurfaceActionPerformerSpy.swift
git commit -m "feat: add terminal overlay scrollbar model"
```

### Task 3: Build the AppKit Overlay View

**Files:**
- Create: `Sources/AgentStudio/Features/Terminal/Hosting/TerminalOverlayScrollbarView.swift`
- Create: `Tests/AgentStudioTests/Features/Terminal/Hosting/TerminalOverlayScrollbarViewTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
import AppKit
import Testing

@testable import AgentStudio

@MainActor
@Suite("TerminalOverlayScrollbarView")
struct TerminalOverlayScrollbarViewTests {
    @Test("view reflects model thumb geometry")
    func viewReflectsModelThumbGeometry() {
        let view = TerminalOverlayScrollbarView()
        var model = TerminalOverlayScrollbarModel()

        model.update(
            scrollbarState: ScrollbarState(top: 80, bottom: 120, total: 200),
            viewportHeight: 600
        )
        view.apply(model: model)

        #expect(view.thumbFrameForTesting.height > 0)
    }

    @Test("hover updates model visibility")
    func hoverUpdatesModelVisibility() {
        let view = TerminalOverlayScrollbarView()
        var model = TerminalOverlayScrollbarModel()

        model.update(
            scrollbarState: ScrollbarState(top: 80, bottom: 120, total: 200),
            viewportHeight: 600
        )
        view.apply(model: model)
        view.simulateHoverEnteredForTesting()

        #expect(view.isVisibleForTesting == true)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
SWIFT_BUILD_DIR=.build-agent-ghostty-overlay swift test \
  --build-path .build-agent-ghostty-overlay \
  --filter 'TerminalOverlayScrollbarViewTests'
```

Expected:

```text
FAIL
Cannot find 'TerminalOverlayScrollbarView' in scope
```

- [ ] **Step 3: Write minimal implementation**

```swift
import AppKit

@MainActor
final class TerminalOverlayScrollbarView: NSView {
    private(set) var model = TerminalOverlayScrollbarModel()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        isHidden = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not supported")
    }

    func apply(model: TerminalOverlayScrollbarModel) {
        self.model = model
        isHidden = model.visibility == .hidden
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard model.visibility == .visible else { return }
        NSColor.white.withAlphaComponent(0.10).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6).fill()
        NSColor.white.withAlphaComponent(0.45).setFill()
        NSBezierPath(roundedRect: model.thumbFrame.insetBy(dx: 2, dy: 2), xRadius: 4, yRadius: 4).fill()
    }

    override func updateTrackingAreas() {
        trackingAreas.forEach(removeTrackingArea)
        super.updateTrackingAreas()
        addTrackingArea(
            NSTrackingArea(
                rect: bounds,
                options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                owner: self,
                userInfo: nil
            ))
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        model.handleHoverChanged(true)
        apply(model: model)
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        model.handleHoverChanged(false)
        apply(model: model)
    }
}
```

Add test-only read-only helpers **without `#if DEBUG`**:

```swift
extension TerminalOverlayScrollbarView {
    var thumbFrameForTesting: NSRect { model.thumbFrame }
    var isVisibleForTesting: Bool { model.visibility == .visible }

    func simulateHoverEnteredForTesting() {
        model.handleHoverChanged(true)
        apply(model: model)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run:

```bash
SWIFT_BUILD_DIR=.build-agent-ghostty-overlay swift test \
  --build-path .build-agent-ghostty-overlay \
  --filter 'TerminalOverlayScrollbarViewTests'
```

Expected:

```text
PASS
```

- [ ] **Step 5: Commit**

```bash
git add \
  Sources/AgentStudio/Features/Terminal/Hosting/TerminalOverlayScrollbarView.swift \
  Tests/AgentStudioTests/Features/Terminal/Hosting/TerminalOverlayScrollbarViewTests.swift
git commit -m "feat: add terminal overlay scrollbar view"
```

### Task 4: Mount the Overlay and Resolve Hit-Testing

**Files:**
- Modify: `Sources/AgentStudio/Features/Terminal/Hosting/TerminalPaneMountView.swift`
- Modify: `Sources/AgentStudio/Features/Terminal/Hosting/TerminalPaneMountView+SearchAndOverlays.swift`
- Modify: `Tests/AgentStudioTests/Features/Terminal/Hosting/TerminalPaneMountViewSearchTests.swift`
- Modify: `Sources/AgentStudio/Features/Terminal/Hosting/ScrollToBottomIndicatorView.swift`
- Modify: `Tests/AgentStudioTests/Features/Terminal/Hosting/ScrollToBottomIndicatorViewTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
@Test("hitTest prioritizes terminal overlay scrollbar over terminal content")
func hitTestPrioritizesTerminalOverlayScrollbarOverTerminalContent() {
    let mountView = makeMountView()
    mountView.ensureTerminalOverlayScrollbarForTesting()

    guard let overlayFrame = mountView.terminalOverlayScrollbarFrameForTesting else {
        Issue.record("Expected terminal overlay scrollbar frame")
        return
    }

    let point = NSPoint(x: overlayFrame.midX, y: overlayFrame.midY)
    let hitView = mountView.hitTest(point)

    #expect(hitView === mountView.terminalOverlayScrollbarViewForTesting)
}

@Test("runtime scrollbar snapshot updates terminal overlay scrollbar")
func runtimeScrollbarSnapshotUpdatesTerminalOverlayScrollbar() {
    let mountView = makeMountView()
    let runtime = TerminalRuntime(
        paneId: PaneId(uuid: UUIDv7.generate()),
        metadata: PaneMetadata(source: .floating(launchDirectory: nil, title: "Terminal"))
    )

    runtime.handleGhosttyEvent(.scrollbarChanged(ScrollbarState(top: 80, bottom: 120, total: 200)))
    mountView.bind(runtime: runtime)

    #expect(mountView.terminalOverlayScrollbarFrameForTesting != nil)
}
```

Add an indicator spacing test:

```swift
@Test("scroll-to-bottom indicator stays clear of terminal overlay gutter")
func scrollToBottomIndicatorStaysClearOfTerminalOverlayGutter() {
    let view = ScrollToBottomIndicatorView()
    view.translatesAutoresizingMaskIntoConstraints = false

    #expect(view.contentEdgeInsets.right >= 8)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
SWIFT_BUILD_DIR=.build-agent-ghostty-overlay swift test \
  --build-path .build-agent-ghostty-overlay \
  --filter 'TerminalPaneMountViewSearchTests|ScrollToBottomIndicatorViewTests'
```

Expected:

```text
FAIL
Cannot find terminal overlay scrollbar hooks
```

- [ ] **Step 3: Write minimal implementation**

In `TerminalPaneMountView`, add:

```swift
var terminalOverlayScrollbarView: TerminalOverlayScrollbarView?
```

Create/install it:

```swift
func ensureTerminalOverlayScrollbar() {
    guard terminalOverlayScrollbarView == nil else { return }
    let overlay = TerminalOverlayScrollbarView()
    overlay.translatesAutoresizingMaskIntoConstraints = false
    addSubview(overlay)
    NSLayoutConstraint.activate([
        overlay.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
        overlay.topAnchor.constraint(equalTo: topAnchor, constant: 8),
        overlay.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
        overlay.widthAnchor.constraint(equalToConstant: 12),
    ])
    terminalOverlayScrollbarView = overlay
}
```

Update it from runtime state:

```swift
if let scrollbarState = runtime.scrollbarState {
    ensureTerminalOverlayScrollbar()
    var model = terminalOverlayScrollbarView?.model ?? TerminalOverlayScrollbarModel()
    model.update(scrollbarState: scrollbarState, viewportHeight: bounds.height)
    terminalOverlayScrollbarView?.apply(model: model)
}
```

Hit-test priority:

```swift
if let overlay = terminalOverlayScrollbarView, !overlay.isHidden {
    let overlayPoint = convert(point, to: overlay)
    if overlay.bounds.contains(overlayPoint) {
        return overlay.hitTest(overlayPoint) ?? overlay
    }
}
```

Move the scroll-to-bottom indicator away from the gutter:

```swift
indicator.contentEdgeInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 12)
```

Add internal test accessors without `#if DEBUG`:

```swift
extension TerminalPaneMountView {
    func ensureTerminalOverlayScrollbarForTesting() {
        ensureTerminalOverlayScrollbar()
        layoutSubtreeIfNeeded()
    }

    var terminalOverlayScrollbarViewForTesting: TerminalOverlayScrollbarView? {
        terminalOverlayScrollbarView
    }

    var terminalOverlayScrollbarFrameForTesting: NSRect? {
        terminalOverlayScrollbarView?.frame
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run:

```bash
SWIFT_BUILD_DIR=.build-agent-ghostty-overlay swift test \
  --build-path .build-agent-ghostty-overlay \
  --filter 'TerminalPaneMountViewSearchTests|ScrollToBottomIndicatorViewTests'
```

Expected:

```text
PASS
```

- [ ] **Step 5: Commit**

```bash
git add \
  Sources/AgentStudio/Features/Terminal/Hosting/TerminalPaneMountView.swift \
  Sources/AgentStudio/Features/Terminal/Hosting/TerminalPaneMountView+SearchAndOverlays.swift \
  Sources/AgentStudio/Features/Terminal/Hosting/ScrollToBottomIndicatorView.swift \
  Tests/AgentStudioTests/Features/Terminal/Hosting/TerminalPaneMountViewSearchTests.swift \
  Tests/AgentStudioTests/Features/Terminal/Hosting/ScrollToBottomIndicatorViewTests.swift
git commit -m "feat: mount terminal overlay scrollbar"
```

### Task 5: Hide Native Visible Terminal Scroller

**Files:**
- Modify: `Sources/AgentStudio/Features/Terminal/Hosting/TerminalSurfaceScrollView.swift`
- Modify: `Tests/AgentStudioTests/Features/Terminal/Hosting/TerminalSurfaceScrollViewTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
@Test("native terminal scroller stays hidden because overlay owns visible scrollbar UI")
func nativeTerminalScrollerStaysHiddenBecauseOverlayOwnsVisibleScrollbarUI() {
    let performer = TerminalSurfaceActionPerformerSpy()
    let scrollView = TerminalSurfaceScrollView(actionPerformer: performer)

    scrollView.applyScrollbarState(
        ScrollbarState(top: 80, bottom: 120, total: 200),
        cellHeight: 20
    )

    #expect(scrollView.hasVerticalScrollerForTesting == false)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
SWIFT_BUILD_DIR=.build-agent-ghostty-overlay swift test \
  --build-path .build-agent-ghostty-overlay \
  --filter 'TerminalSurfaceScrollViewTests'
```

Expected:

```text
FAIL
Expected native terminal scroller to stay hidden
```

- [ ] **Step 3: Write minimal implementation**

```swift
scrollView.hasVerticalScroller = false
scrollView.hasHorizontalScroller = false
scrollView.autohidesScrollers = true
scrollView.scrollerStyle = .overlay
```

Do **not** turn `hasVerticalScroller` back on in `applyScrollbarState`.

Keep native scrolling mechanics:

```swift
private func handleLiveScroll() {
    // existing row conversion path
}
```

and:

```swift
private func synchronizeScrollView() {
    documentView.frame.size.height = documentHeight()
    // existing document/surface sync
}
```

- [ ] **Step 4: Run test to verify it passes**

Run:

```bash
SWIFT_BUILD_DIR=.build-agent-ghostty-overlay swift test \
  --build-path .build-agent-ghostty-overlay \
  --filter 'TerminalSurfaceScrollViewTests'
```

Expected:

```text
PASS
```

- [ ] **Step 5: Commit**

```bash
git add \
  Sources/AgentStudio/Features/Terminal/Hosting/TerminalSurfaceScrollView.swift \
  Tests/AgentStudioTests/Features/Terminal/Hosting/TerminalSurfaceScrollViewTests.swift
git commit -m "fix: hide native terminal scroller UI"
```

### Task 6: Full Verification in Debug and Release Modes

**Files:**
- Modify: none

- [ ] **Step 1: Run focused terminal tests**

Run:

```bash
SWIFT_BUILD_DIR=.build-agent-ghostty-overlay swift test \
  --build-path .build-agent-ghostty-overlay \
  --filter 'GhosttyAppHandleTests|TerminalOverlayScrollbarModelTests|TerminalOverlayScrollbarViewTests|TerminalPaneMountViewSearchTests|TerminalSurfaceScrollViewTests|ScrollToBottomIndicatorViewTests'
```

Expected:

```text
PASS
```

- [ ] **Step 2: Run lint**

Run:

```bash
mise run lint
```

Expected:

```text
swift-format: OK
swiftlint: OK
Core boundary import check passed
```

- [ ] **Step 3: Run full tests**

Run:

```bash
mise run test
```

Expected:

```text
exit code 0
non-serialized suites PASS
WebKit serialized suites PASS
```

- [ ] **Step 4: Build local debug and release artifacts**

Run:

```bash
mise run build
mise run build-release
```

Expected:

```text
Build complete!
Build complete!
```

- [ ] **Step 5: Package local release app**

Run:

```bash
set -euo pipefail
APP_ROOT="$PWD/tmp/AgentStudioRelease.app/Contents"
rm -rf "$PWD/tmp/AgentStudioRelease.app"
mkdir -p "$APP_ROOT/MacOS" "$APP_ROOT/Resources"
cp .build-release-agent-ghostty-overlay-scrollbar/release/AgentStudio "$APP_ROOT/MacOS/"
[ -f "vendor/zmx/zig-out/bin/zmx" ] && cp vendor/zmx/zig-out/bin/zmx "$APP_ROOT/MacOS/"
cp Sources/AgentStudio/Resources/Info.plist "$APP_ROOT/"
cp Sources/AgentStudio/Resources/AppIcon.icns "$APP_ROOT/Resources/"
RESOURCE_BUNDLE=$(find .build-release-agent-ghostty-overlay-scrollbar -path '*/release/AgentStudio_AgentStudio.bundle' -type d | head -n 1)
cp -R "$RESOURCE_BUNDLE" "$APP_ROOT/Resources/"
[ -d "Sources/AgentStudio/Resources/terminfo" ] && cp -R Sources/AgentStudio/Resources/terminfo "$APP_ROOT/Resources/"
if [ -d "Sources/AgentStudio/Resources/ghostty" ]; then
  mkdir -p "$APP_ROOT/Resources/ghostty"
  cp -R Sources/AgentStudio/Resources/ghostty/. "$APP_ROOT/Resources/ghostty/"
fi
codesign --force --deep --sign - "$PWD/tmp/AgentStudioRelease.app" >/dev/null 2>&1 || true
```

Expected:

```text
tmp/AgentStudioRelease.app exists
```

- [ ] **Step 6: Visually verify debug build**

Run:

```bash
pkill -f "/.build-agent-ghostty-overlay-scrollbar/debug/AgentStudio" || true
./.build-agent-ghostty-overlay-scrollbar/debug/AgentStudio >/tmp/agentstudio-ghostty-overlay-debug.log 2>&1 &
DEBUG_PID=$!
sleep 5
peekaboo see --pid "$DEBUG_PID" --json
```

Expected:

```text
No fat startup scrollbar
Hover over gutter reveals thin overlay scrollbar
Dragging overlay thumb scrolls terminal
```

- [ ] **Step 7: Visually verify release app**

Run:

```bash
pkill -f "$PWD/tmp/AgentStudioRelease.app/Contents/MacOS/AgentStudio" || true
open -na "$PWD/tmp/AgentStudioRelease.app"
sleep 5
RELEASE_PID=$(pgrep -f "$PWD/tmp/AgentStudioRelease.app/Contents/MacOS/AgentStudio" | head -n 1)
peekaboo see --pid "$RELEASE_PID" --json
```

Expected:

```text
No fat startup scrollbar
Hover over gutter reveals thin overlay scrollbar
No dependence on macOS Show scroll bars = Always
```

No commit in this verification task. Prior tasks already committed the implementation.
