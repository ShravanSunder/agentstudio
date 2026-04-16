# Ghostty Native Scrollbar Parity Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Agent Studio terminal panes use Ghostty-style native scrollbar behavior: native visible scroller, native gutter hover reveal, startup state driven by host-cached surface scrollbar state, and no custom overlay scrollbar.

**Architecture:** Copy Ghostty’s macOS host behavior, not its exact symbol names. We will add a host-side scrollbar/config snapshot cache to `Ghostty.SurfaceView`, populate it directly from Ghostty action routing plus finalized Ghostty config, then make `TerminalSurfaceScrollView` behave like vendor `SurfaceScrollView`: `synchronizeAppearance()`, `synchronizeScrollView()`, and native `mouseMoved` gutter reveal over the real scroller frame. Runtime replay stays as a secondary consumer for UI like the scroll-to-bottom indicator, but the scroll host itself must stop depending on delayed `TerminalRuntime.scrollbarState` for first paint.

**Tech Stack:** Swift 6 `Testing`, AppKit `NSScrollView`, GhosttyKit C API (`ghostty_config_get`), Agent Studio Ghostty action router, native NotificationCenter.

---

## Behavior Matrix

| Concern | Ghostty vendor app | Agent Studio target |
|---|---|---|
| Visible scrollbar primitive | Native `NSScrollView` / `NSScroller` | Same |
| Startup scrollbar source | Host-cached surface scrollbar state | Same |
| Effective scrollbar policy | Derived config (`system`/`never`) | Local mirror of finalized Ghostty config |
| Hover reveal | `mouseMoved` on native scroller frame + `flashScrollers()` | Same |
| Scroll positioning | Host `synchronizeScrollView()` from cached scrollbar | Same |
| Scrollbar drag | Native live scroll -> `scroll_to_row` | Same |
| Custom overlay thumb | None | None |

## State Flow

```text
Ghostty core
  -> scrollbar action payload
  -> config values from finalized ghostty_config_t
        |
        v
Ghostty.SurfaceView host cache
  - hostScrollbarState
  - hostConfigSnapshot
        |
        v
TerminalSurfaceScrollView
  - synchronizeAppearance()
  - synchronizeScrollView()
  - native mouseMoved gutter reveal
        |
        v
AppKit native NSScroller
```

## File Map

| File | Responsibility |
|---|---|
| `Sources/AgentStudio/Features/Terminal/Ghostty/GhosttyHostConfigSnapshot.swift` | Local Ghostty host config mirror (`scrollbarPolicy`, `backgroundColor`) decoded from `ghostty_config_t` |
| `Sources/AgentStudio/Features/Terminal/Ghostty/GhosttyAppHandle.swift` | Expose finalized host config snapshot from the loaded Ghostty config |
| `Sources/AgentStudio/Features/Terminal/Ghostty/Ghostty.swift` | Expose app-level accessor for host config snapshot |
| `Sources/AgentStudio/Features/Terminal/Ghostty/GhosttySurfaceView.swift` | Cache host scrollbar state + host config snapshot on the mounted surface view |
| `Sources/AgentStudio/Features/Terminal/Ghostty/GhosttyActionRouter.swift` | Update `Ghostty.SurfaceView` host cache directly when surface-scoped actions arrive |
| `Sources/AgentStudio/Features/Terminal/Hosting/TerminalSurfaceScrollView.swift` | Port vendor `SurfaceScrollView` ideas: `synchronizeAppearance()`, host-cache-driven `synchronizeScrollView()`, native gutter hover |
| `Sources/AgentStudio/Features/Terminal/Hosting/TerminalPaneMountView+SearchAndOverlays.swift` | Stop treating runtime replay as the primary source for scroll host behavior |
| `Tests/AgentStudioTests/Features/Terminal/Ghostty/GhosttyHostConfigSnapshotTests.swift` | Verify config decoding for `scrollbar` + `background` |
| `Tests/AgentStudioTests/Features/Terminal/Ghostty/GhosttyAppHandleTests.swift` | Verify the override file still only disables follow-bottom |
| `Tests/AgentStudioTests/Features/Terminal/Hosting/TerminalSurfaceScrollViewTests.swift` | Verify native wrapper behavior (appearance sync, live scroll, hover path plumbing, startup state) |
| `Tests/AgentStudioTests/Features/Terminal/Hosting/TerminalPaneMountViewSearchTests.swift` | Verify mount view keeps search/scroll-to-bottom behavior while scroll host ownership stays native |

---

### Task 1: Add a Local Ghostty Host Config Snapshot

**Files:**
- Create: `Sources/AgentStudio/Features/Terminal/Ghostty/GhosttyHostConfigSnapshot.swift`
- Modify: `Sources/AgentStudio/Features/Terminal/Ghostty/GhosttyAppHandle.swift`
- Modify: `Sources/AgentStudio/Features/Terminal/Ghostty/Ghostty.swift`
- Test: `Tests/AgentStudioTests/Features/Terminal/Ghostty/GhosttyHostConfigSnapshotTests.swift`
- Test: `Tests/AgentStudioTests/Features/Terminal/Ghostty/GhosttyAppHandleTests.swift`

- [ ] **Step 1: Write the failing host-config tests**

```swift
import AppKit
import Testing

@testable import AgentStudio

@Suite("GhosttyHostConfigSnapshot")
@MainActor
struct GhosttyHostConfigSnapshotTests {
    @Test("ghostty app handle override keeps scrollbar actions enabled")
    func ghosttyAppHandleOverrideKeepsScrollbarActionsEnabled() {
        let overrideContents = Ghostty.AppHandle.scrollBehaviorOverrideContents

        #expect(overrideContents.contains("scroll-to-bottom = no-keystroke, no-output"))
        #expect(overrideContents.contains("scrollbar = never") == false)
    }

    @Test("decodes system scrollbar policy from ghostty config")
    func decodesSystemScrollbarPolicyFromGhosttyConfig() {
        let config = ghostty_config_new()!
        defer { ghostty_config_free(config) }

        let override = "scrollbar = system\nbackground = 12,34,56"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? override.write(to: url, atomically: true, encoding: .utf8)
        url.path.withCString { ghostty_config_load_file(config, $0) }
        ghostty_config_finalize(config)

        let snapshot = GhosttyHostConfigSnapshot(configHandle: config)

        #expect(snapshot.scrollbarPolicy == .system)
        #expect(snapshot.backgroundColor == NSColor(
            calibratedRed: 12.0 / 255.0,
            green: 34.0 / 255.0,
            blue: 56.0 / 255.0,
            alpha: 1
        ))
    }
}
```

- [ ] **Step 2: Run the host-config test to verify it fails**

Run: `swift test --build-path .build-agent-ghostty-native --filter 'GhosttyHostConfigSnapshotTests'`

Expected: FAIL with “no such file / symbol `GhosttyHostConfigSnapshot`”.

- [ ] **Step 3: Implement the local config snapshot**

```swift
import AppKit
import Foundation
import GhosttyKit

enum GhosttyScrollbarPolicy: Equatable {
    case system
    case never
}

struct GhosttyHostConfigSnapshot: Equatable {
    let scrollbarPolicy: GhosttyScrollbarPolicy
    let backgroundColor: NSColor

    init(configHandle: ghostty_config_t?) {
        guard let configHandle else {
            self.scrollbarPolicy = .system
            self.backgroundColor = .windowBackgroundColor
            return
        }

        var scrollbarPtr: UnsafePointer<Int8>?
        let scrollbarKey = "scrollbar"
        if ghostty_config_get(configHandle, &scrollbarPtr, scrollbarKey, UInt(scrollbarKey.count)),
           let scrollbarPtr
        {
            self.scrollbarPolicy = String(cString: scrollbarPtr) == "never" ? .never : .system
        } else {
            self.scrollbarPolicy = .system
        }

        var color = ghostty_config_color_s()
        let backgroundKey = "background"
        if ghostty_config_get(configHandle, &color, backgroundKey, UInt(backgroundKey.count)) {
            self.backgroundColor = NSColor(
                calibratedRed: CGFloat(color.r) / 255.0,
                green: CGFloat(color.g) / 255.0,
                blue: CGFloat(color.b) / 255.0,
                alpha: 1
            )
        } else {
            self.backgroundColor = .windowBackgroundColor
        }
    }
}
```

Update `Ghostty.AppHandle`:

```swift
final class AppHandle {
    // existing storage...

    func hostConfigSnapshot() -> GhosttyHostConfigSnapshot {
        GhosttyHostConfigSnapshot(configHandle: configHandle)
    }
}
```

Update the override contents explicitly:

```swift
static let scrollBehaviorOverrideContents = """
    scroll-to-bottom = no-keystroke, no-output
    """
```

Update `Ghostty.App`:

```swift
final class App: @unchecked Sendable {
    // existing code...

    func hostConfigSnapshot() -> GhosttyHostConfigSnapshot {
        appHandle?.hostConfigSnapshot() ?? GhosttyHostConfigSnapshot(configHandle: nil)
    }
}
```

- [ ] **Step 4: Run the focused config tests**

Run: `swift test --build-path .build-agent-ghostty-native --filter 'GhosttyHostConfigSnapshotTests|GhosttyAppHandleTests'`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add \
  Sources/AgentStudio/Features/Terminal/Ghostty/GhosttyHostConfigSnapshot.swift \
  Sources/AgentStudio/Features/Terminal/Ghostty/GhosttyAppHandle.swift \
  Sources/AgentStudio/Features/Terminal/Ghostty/Ghostty.swift \
  Tests/AgentStudioTests/Features/Terminal/Ghostty/GhosttyHostConfigSnapshotTests.swift \
  Tests/AgentStudioTests/Features/Terminal/Ghostty/GhosttyAppHandleTests.swift
git commit -m "feat: add ghostty host config snapshot

Co-authored-by: Codex <noreply@openai.com>"
```

### Task 2: Cache Host Scrollbar State on `Ghostty.SurfaceView`

**Files:**
- Modify: `Sources/AgentStudio/Features/Terminal/Ghostty/GhosttySurfaceView.swift`
- Modify: `Sources/AgentStudio/Features/Terminal/Ghostty/GhosttyActionRouter.swift`
- Test: `Tests/AgentStudioTests/Features/Terminal/Ghostty/GhosttyActionRouterTests.swift`

- [ ] **Step 1: Write the failing action-router test for host scrollbar caching**

```swift
@Test("scrollbar action updates surface host scrollbar cache before runtime replay")
@MainActor
func scrollbarActionUpdatesSurfaceHostScrollbarCache() {
    let app = Ghostty.shared
    let surface = Ghostty.SurfaceView(
        app: app,
        config: Ghostty.SurfaceConfiguration(
            startupStrategy: .surfaceCommand(nil),
            initialFrame: NSRect(x: 0, y: 0, width: 640, height: 480)
        )
    )

    surface.updateHostConfigSnapshot(app.hostConfigSnapshot())
    #expect(surface.hostScrollbarState == nil)

    surface.updateHostScrollbarState(
        ScrollbarState(top: 80, bottom: 120, total: 200)
    )

    #expect(surface.hostScrollbarState == ScrollbarState(top: 80, bottom: 120, total: 200))
}
```

- [ ] **Step 2: Run the action-router/surface test to verify it fails**

Run: `swift test --build-path .build-agent-ghostty-native --filter 'GhosttyActionRouterTests'`

Expected: FAIL because `hostScrollbarState` / `updateHostScrollbarState` do not exist.

- [ ] **Step 3: Add host cache to `Ghostty.SurfaceView`**

```swift
final class SurfaceView: NSView {
    private(set) var hostScrollbarState: ScrollbarState?
    private(set) var hostConfigSnapshot = GhosttyHostConfigSnapshot(configHandle: nil)
    var onHostScrollbarStateChanged: (@MainActor @Sendable (ScrollbarState) -> Void)?

    func updateHostConfigSnapshot(_ snapshot: GhosttyHostConfigSnapshot) {
        hostConfigSnapshot = snapshot
    }

    func updateHostScrollbarState(_ state: ScrollbarState) {
        hostScrollbarState = state
        onHostScrollbarStateChanged?(state)
    }
}
```

Seed the config snapshot in `init(app:config:)`:

```swift
init(app: App, config: SurfaceConfiguration? = nil) {
    // existing setup...
    self.ghosttyApp = app
    self.hostConfigSnapshot = app.hostConfigSnapshot()
    super.init(frame: config.initialFrame!)
    // continue existing init
}
```

- [ ] **Step 4: Update action routing to mutate the surface host cache**

Inside `Ghostty.ActionRouter`, extend the surface-scoped updates already used for title and pwd:

```swift
if target.tag == GHOSTTY_TARGET_SURFACE,
   let surface = target.target.surface,
   let resolvedSurfaceView = surfaceView(from: surface) {
    Task { @MainActor [weak resolvedSurfaceView] in
        resolvedSurfaceView?.updateHostScrollbarState(
            ScrollbarState(
                top: Int(action.action.scrollbar.offset),
                bottom: Int(action.action.scrollbar.offset + action.action.scrollbar.len),
                total: Int(action.action.scrollbar.total)
            )
        )
    }
}
```

For `.configChange` and `.reloadConfig`, refresh the host config snapshot:

```swift
Task { @MainActor [weak resolvedSurfaceView] in
    guard let resolvedSurfaceView else { return }
    resolvedSurfaceView.updateHostConfigSnapshot(Ghostty.shared.hostConfigSnapshot())
}
```

Ownership note:

```text
The action router already hops to MainActor once for surface-scoped updates.
Do not add a second async hop for scrollbar cache propagation.
The host cache update and wrapper invalidation must happen in the same main-actor turn.
```

- [ ] **Step 5: Run the focused Ghostty routing tests**

Run: `swift test --build-path .build-agent-ghostty-native --filter 'GhosttyActionRouterTests|GhosttySurfaceViewInitialFrameTests'`

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add \
  Sources/AgentStudio/Features/Terminal/Ghostty/GhosttySurfaceView.swift \
  Sources/AgentStudio/Features/Terminal/Ghostty/GhosttyActionRouter.swift \
  Tests/AgentStudioTests/Features/Terminal/Ghostty/GhosttyActionRouterTests.swift
git commit -m "feat: cache ghostty host scrollbar state on surface views

Co-authored-by: Codex <noreply@openai.com>"
```

### Task 3: Port `TerminalSurfaceScrollView` to Ghostty-Style Host Synchronization

**Files:**
- Modify: `Sources/AgentStudio/Features/Terminal/Hosting/TerminalSurfaceScrollView.swift`
- Test: `Tests/AgentStudioTests/Features/Terminal/Hosting/TerminalSurfaceScrollViewTests.swift`

- [ ] **Step 1: Write failing tests for appearance sync and host-cached startup state**

```swift
@Test("scroll wrapper uses host config snapshot to decide scrollbar visibility")
func scrollWrapperUsesHostConfigSnapshotToDecideScrollbarVisibility() {
    let performer = FakeSurfaceActionPerformer()
    let scrollView = TerminalSurfaceScrollView(actionPerformer: performer)
    let surface = Ghostty.SurfaceView(app: Ghostty.shared, config: .init(
        startupStrategy: .surfaceCommand(nil),
        initialFrame: NSRect(x: 0, y: 0, width: 640, height: 480)
    ))

    surface.updateHostConfigSnapshot(.init(scrollbarPolicy: .never, backgroundColor: .black))
    scrollView.embedSurfaceView(surface)
    scrollView.layoutSubtreeIfNeeded()

    #expect(scrollView.hasVerticalScrollerForTesting == false)
}

@Test("scroll wrapper uses host scrollbar cache before runtime replay")
func scrollWrapperUsesHostScrollbarCacheBeforeRuntimeReplay() {
    let performer = FakeSurfaceActionPerformer()
    let scrollView = TerminalSurfaceScrollView(actionPerformer: performer)
    let surface = Ghostty.SurfaceView(app: Ghostty.shared, config: .init(
        startupStrategy: .surfaceCommand(nil),
        initialFrame: NSRect(x: 0, y: 0, width: 640, height: 480)
    ))

    surface.updateHostScrollbarState(.init(top: 80, bottom: 120, total: 200))
    surface.updateReportedCellSize(NSSize(width: 8, height: 20))
    scrollView.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
    scrollView.embedSurfaceView(surface)
    scrollView.layoutSubtreeIfNeeded()

    #expect(scrollView.documentOffsetYForTesting == 1600)
}
```

- [ ] **Step 2: Run the wrapper tests to verify they fail**

Run: `swift test --build-path .build-agent-ghostty-native --filter 'TerminalSurfaceScrollViewTests'`

Expected: FAIL because the wrapper still uses `previousScrollbarState` only and has no `synchronizeAppearance()`.

- [ ] **Step 3: Port the vendor host ideas into our wrapper**

Add host-driven sync methods:

```swift
private func synchronizeAppearance() {
    guard let surfaceView else { return }
    scrollView.hasVerticalScroller = surfaceView.hostConfigSnapshot.scrollbarPolicy != .never
    let hasLightBackground = surfaceView.hostConfigSnapshot.backgroundColor.isLightColor
    scrollView.appearance = NSAppearance(named: hasLightBackground ? .aqua : .darkAqua)
    updateTrackingAreas()
}

private func synchronizeScrollView() {
    documentView.frame.size.height = documentHeight()

    if !isLiveScrolling,
       let surfaceView,
       let scrollbar = surfaceView.hostScrollbarState,
       surfaceView.reportedCellSize?.height ?? 0 > 0 {
        let cellHeight = surfaceView.reportedCellSize!.height
        let offsetY = CGFloat(scrollbar.total - scrollbar.top - scrollbar.visibleRowCount) * cellHeight
        scrollView.contentView.scroll(to: CGPoint(x: 0, y: offsetY))
        lastSentRow = scrollbar.top
    }

    scrollView.reflectScrolledClipView(scrollView.contentView)
}
```

Refactor `ScrollbarState` helpers to avoid relying on runtime only:

```swift
private func currentScrollbarState() -> ScrollbarState? {
    surfaceView?.hostScrollbarState ?? previousScrollbarState
}

private func currentCellHeight() -> CGFloat {
    surfaceView?.reportedCellSize?.height ?? cellHeight
}
```

Update init/notifications to match vendor behavior more closely:

```swift
notificationObservers.append(
    NotificationCenter.default.addObserver(
        forName: NSScroller.preferredScrollerStyleDidChangeNotification,
        object: nil,
        queue: nil
    ) { [weak self] _ in
        self?.handleScrollerStyleChange()
    }
)
```

Wire the mounted surface directly into wrapper invalidation so host-cached scrollbar updates trigger immediately:

```swift
func embedSurfaceView(_ surfaceView: Ghostty.SurfaceView) {
    self.surfaceView?.onHostScrollbarStateChanged = nil
    self.surfaceView = surfaceView
    surfaceView.onHostScrollbarStateChanged = { [weak self] _ in
        guard let self else { return }
        self.synchronizeScrollView()
        self.synchronizeSurfaceFrame()
    }
    // existing mount code...
    synchronizeAppearance()
}
```

Update hover path:

```swift
override func mouseMoved(with event: NSEvent) {
    guard NSScroller.preferredScrollerStyle == .legacy else { return }
    scrollView.flashScrollers()
}

override func updateTrackingAreas() {
    trackingAreas.forEach(removeTrackingArea)
    super.updateTrackingAreas()
    guard let scroller = scrollView.verticalScroller else { return }
    addTrackingArea(NSTrackingArea(
        rect: convert(scroller.bounds, from: scroller),
        options: [.mouseMoved, .activeInKeyWindow],
        owner: self,
        userInfo: nil
    ))
}
```

- [ ] **Step 4: Run the terminal wrapper tests**

Run: `swift test --build-path .build-agent-ghostty-native --filter 'TerminalSurfaceScrollViewTests'`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add \
  Sources/AgentStudio/Features/Terminal/Hosting/TerminalSurfaceScrollView.swift \
  Tests/AgentStudioTests/Features/Terminal/Hosting/TerminalSurfaceScrollViewTests.swift
git commit -m "feat: align terminal scroll host with ghostty native behavior

Co-authored-by: Codex <noreply@openai.com>"
```

### Task 4: Keep Runtime Replay Secondary and Remove Startup Dependence on It

**Files:**
- Modify: `Sources/AgentStudio/Features/Terminal/Hosting/TerminalPaneMountView+SearchAndOverlays.swift`
- Test: `Tests/AgentStudioTests/Features/Terminal/Hosting/TerminalPaneMountViewSearchTests.swift`

- [ ] **Step 1: Write the failing mount-view test for “runtime is no longer primary for scroll host startup”**

```swift
@Test("bind still updates scroll-to-bottom indicator but scroll host startup does not require runtime scrollbar replay")
func bindStillUpdatesScrollToBottomIndicatorButScrollHostStartupDoesNotRequireRuntimeReplay() {
    let mountView = TerminalPaneMountView(paneId: UUID(), title: "Terminal")
    let scrollView = TerminalSurfaceScrollView(actionPerformer: PaneScrollActionPerformer())
    scrollView.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
    scrollView.layoutSubtreeIfNeeded()
    mountView.installSurfaceScrollViewForTesting(scrollView)

    let runtime = TerminalRuntime(
        paneId: PaneId(),
        metadata: PaneMetadata(source: .floating(launchDirectory: nil, title: "Terminal"), title: "Terminal")
    )
    #expect(runtime.transitionToReady())

    mountView.bind(runtime: runtime)

    #expect(mountView.scrollToBottomIndicatorFrameForTesting != nil)
}
```

- [ ] **Step 2: Run the mount-view tests to verify intent**

Run: `swift test --build-path .build-agent-ghostty-native --filter 'TerminalPaneMountViewSearchTests'`

Expected: FAIL or require implementation changes because `bind(runtime:)` still assumes runtime replay is the only scrollbar path.

- [ ] **Step 3: Simplify mount view responsibilities**

Keep runtime replay only for runtime-owned overlays:

```swift
func applyRuntimeStateSnapshot(_ runtime: TerminalRuntime) {
    if let scrollbarState = runtime.scrollbarState {
        scrollToBottomIndicatorView?.applyScrollbarState(scrollbarState)
    }

    if let searchState = runtime.searchState {
        ensureSearchOverlay()
        searchOverlayView?.update(
            query: searchState.query,
            totalMatches: searchState.totalMatches,
            selectedMatchIndex: searchState.selectedMatchIndex
        )
    } else {
        hideSearchOverlay()
    }
}
```

Do **not** let mount view own scrollbar UI or scrollbar startup state. That remains inside `TerminalSurfaceScrollView`.

Explicitly remove the old primary call:

```text
Delete any remaining call from applyRuntimeStateSnapshot(...) to
surfaceScrollView?.applyScrollbarState(...)
```

- [ ] **Step 4: Run the mount-view tests**

Run: `swift test --build-path .build-agent-ghostty-native --filter 'TerminalPaneMountViewSearchTests'`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add \
  Sources/AgentStudio/Features/Terminal/Hosting/TerminalPaneMountView+SearchAndOverlays.swift \
  Tests/AgentStudioTests/Features/Terminal/Hosting/TerminalPaneMountViewSearchTests.swift
git commit -m "refactor: keep terminal scroll host ownership inside native wrapper

Co-authored-by: Codex <noreply@openai.com>"
```

### Task 5: Full Verification in Debug and Release

**Files:**
- Modify: `Sources/AgentStudio/Features/Terminal/Hosting/TerminalSurfaceScrollView.swift` (only if fixing verification findings)
- Verify: `tmp/AgentStudioRelease.app`

- [ ] **Step 1: Run the focused terminal suites**

Run:

```bash
swift test --build-path .build-agent-ghostty-native --filter 'GhosttyAppHandleTests|TerminalPaneMountViewSearchTests|TerminalSurfaceScrollViewTests|GhosttyActionRouterTests|GhosttyHostConfigSnapshotTests'
```

Expected: PASS.

- [ ] **Step 2: Run lint**

Run: `mise run lint`

Expected: exit code `0`.

- [ ] **Step 3: Run the full test suite**

Run: `mise run test`

Expected: PASS, including printed pass/fail counts.

- [ ] **Step 4: Build debug app**

Run: `AGENT_RUN_ID=ghostty-native mise run build`

Expected: debug app builds successfully.

- [ ] **Step 5: Build release app**

Run: `AGENT_RUN_ID=ghostty-native mise run build-release`

Expected: release app builds successfully.

- [ ] **Step 6: Launch the release artifact**

Run:

```bash
pkill -9 -f 'AgentStudioRelease.app' || true
open -n /Users/shravansunder/Documents/dev/project-dev/agent-studio.fix-scroll/tmp/AgentStudioRelease.app
sleep 2
pgrep -f 'AgentStudioRelease.app' | tail -n 1
```

Expected: prints a live PID.

- [ ] **Step 7: Visual verification checklist**

Check in the running app:

```text
1. Terminal pane with existing scrollback does not paint a duplicate/custom scrollbar
2. Native scrollbar appears on gutter hover, like Ghostty
3. Hover path still works on second launch
4. Native scrollbar drag scrolls terminal history correctly
5. Startup on a pane with scrollback matches Ghostty behavior on the same machine
```

- [ ] **Step 8: If all checks pass, stop**

No new commit here. Verification does not create another commit.

---

## Self-Review

### Spec coverage
- Behavioral Ghostty parity: covered in Tasks 2-4
- Native visible scrollbar, not custom overlay: covered in Tasks 2-4
- Hover reveal like Ghostty: covered in Task 3
- Startup state driven by host-cached surface state: covered in Tasks 2-3
- Debug + release verification: covered in Task 5
- Scrollbar actions remain enabled by removing `scrollbar = never`: covered in Task 1

### Placeholder scan
- No `TODO`/`TBD`
- No “write tests” without actual test code
- No “similar to previous task” shortcuts

### Type consistency
- `GhosttyHostConfigSnapshot`
- `GhosttyScrollbarPolicy`
- `hostScrollbarState`
- `hostConfigSnapshot`
- `updateHostScrollbarState(_:)`
- `updateHostConfigSnapshot(_:)`

All names are consistent across tasks.

---

Plan complete and saved to `docs/superpowers/plans/2026-04-16-ghostty-native-scrollbar-parity.md`. Two execution options:

**1. Subagent-Driven (recommended)** - I dispatch a fresh subagent per task, review between tasks, fast iteration

**2. Inline Execution** - Execute tasks in this session using executing-plans, batch execution with checkpoints

**Which approach?**
