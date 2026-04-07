# Terminal Scrollback UX Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add native macOS scrollbars, scrollback search (cmd+f), scroll-to-bottom indicator, and mouse cursor management to Agent Studio's embedded Ghostty terminal panes.

**Architecture:** Ghostty core owns all scrollback/search/cursor state. The host-side composes three new pure-AppKit views inside `TerminalPaneMountView` — a scroll wrapper, search overlay, and scroll-to-bottom button — each observing `TerminalRuntime`'s `@Observable` properties via `withObservationTracking`. User interactions flow back to Ghostty core through a `TerminalSurfaceActionPerforming` protocol. Seven Ghostty action tags move from `deferredTags` to `explicitlyRoutedTags` with typed payloads.

**Tech Stack:** Swift 6.2, macOS 26, AppKit, GhosttyKit/libghostty, Swift Testing (`@Suite`, `@Test`, `#expect`), mise

**Spec:** `docs/superpowers/specs/2026-04-06-terminal-scrollback-ux-design.md`

**Coordination:** The `agent-studio.deffered-contracts` worktree promotes ALL remaining deferred tags (C15/C16). This branch merges first — the other branch skips the 7 tags we promote here and rebases after.

---

## Scope

This plan covers:

- Native macOS scrollbar wrapper for terminal panes (always visible, overlay style)
- Scrollbar and search event routing from Ghostty core into `TerminalRuntime`
- Scrollback search UI (`cmd+f`) and macOS Find menu integration
- Follow-bottom behavior (no keystroke scroll-to-bottom)
- Scroll-to-bottom floating button with new-output indicator
- Mouse cursor shape and visibility management

This plan does NOT cover: cross-pane search, Find pasteboard, click-to-move host-side code, command finished notification UI.

## File Structure Map

**Create**

| File | Responsibility |
|------|---------------|
| `Sources/AgentStudio/Features/Terminal/Hosting/TerminalSurfaceActionPerforming.swift` | Protocol for sending Ghostty binding actions from AppKit views |
| `Sources/AgentStudio/Features/Terminal/Hosting/TerminalSurfaceScrollView.swift` | NSScrollView wrapper with overlay scrollbar, follow-bottom, coordinate math |
| `Sources/AgentStudio/Features/Terminal/Hosting/TerminalSearchOverlayView.swift` | Floating search bar — NSSearchField, match counter, navigation buttons |
| `Sources/AgentStudio/Features/Terminal/Hosting/ScrollToBottomIndicatorView.swift` | Floating button — appears when scrolled up, new-output badge |
| `Tests/AgentStudioTests/Features/Terminal/Hosting/TerminalSurfaceScrollViewTests.swift` | Coordinate math, follow-bottom, live scroll dedup |
| `Tests/AgentStudioTests/Features/Terminal/Hosting/TerminalSearchOverlayViewTests.swift` | Callback wiring, result label formatting |
| `Tests/AgentStudioTests/Features/Terminal/Hosting/ScrollToBottomIndicatorViewTests.swift` | Visibility logic, new-output tracking |
| `Tests/AgentStudioTests/Features/Terminal/Hosting/TerminalPaneMountViewSearchTests.swift` | Responder chain actions produce correct binding actions |

**Modify**

| File | Change |
|------|--------|
| `Sources/AgentStudio/Core/RuntimeEventSystem/Contracts/PaneRuntimeEvent.swift` | Update `ScrollbarState` fields; add `TerminalSearchState`, `GhosttyMouseShape`; add 6 new `GhosttyEvent` cases; update `actionPolicy` and `eventName` |
| `Sources/AgentStudio/Core/RuntimeEventSystem/Contracts/PaneKindEvent.swift` | Add 6 `EventIdentifier` cases |
| `Sources/AgentStudio/Features/Terminal/Ghostty/GhosttyAdapter.swift` | Add 7 `ActionPayload` variants; add translation logic |
| `Sources/AgentStudio/Features/Terminal/Ghostty/GhosttyActionRouter.swift` | Move 7 tags from `deferredTags` to `explicitlyRoutedTags`; add routing cases |
| `Sources/AgentStudio/Features/Terminal/Runtime/TerminalRuntime.swift` | Add `scrollbarState`, `searchState`, `mouseShape`, `mouseVisible` properties; handle 6 new events |
| `Sources/AgentStudio/Features/Terminal/Hosting/TerminalPaneMountView.swift` | Compose scroll wrapper + search overlay + scroll-to-bottom button; add `bind(runtime:)`; add responder methods; update `hitTest` |
| `Sources/AgentStudio/Features/Terminal/Ghostty/GhosttySurfaceView.swift` | Conform to `TerminalSurfaceActionPerforming`; observe mouse shape/visibility |
| `Sources/AgentStudio/App/Boot/AppDelegate.swift` | Add Find menu entries |
| `Sources/AgentStudio/App/Coordination/PaneCoordinator+ViewLifecycle.swift` | Call `bind(runtime:)` after runtime registration |

**Modify Tests**

| File | Change |
|------|--------|
| `Tests/AgentStudioTests/Features/Terminal/Ghostty/GhosttyAdapterTests.swift` | Add translation tests for 7 new payloads |
| `Tests/AgentStudioTests/Features/Terminal/Ghostty/GhosttyActionRouterTests.swift` | Update deferred tag assertions |
| `Tests/AgentStudioTests/Features/Terminal/Runtime/TerminalRuntimeTests.swift` | Add search/mouse state machine tests |

---

### Task 0: Inject Ghostty Config Overrides

**Files:**
- Modify: `Sources/AgentStudio/Features/Terminal/Ghostty/GhosttyAppHandle.swift`

Without this task, Ghostty core auto-scrolls to bottom on every keystroke (`scroll-to-bottom = keystroke` in user config) and renders its own scrollbar (`scrollbar = system`). Both behaviors conflict with Agent Studio's host-side scroll wrapper.

- [ ] **Step 1: Write the override config file at startup**

In `Sources/AgentStudio/Features/Terminal/Ghostty/GhosttyAppHandle.swift`, update `init` to inject overrides between `ghostty_config_load_default_files` and `ghostty_config_finalize`:

```swift
init?(runtimeConfig: ghostty_runtime_config_s) {
    guard let config = ghostty_config_new() else {
        ghosttyLogger.error("Failed to create ghostty config")
        return nil
    }

    ghostty_config_load_default_files(config)

    // Agent Studio overrides — disable Ghostty's built-in scrollbar and
    // keystroke scroll-to-bottom. Agent Studio renders its own scrollbar
    // via TerminalSurfaceScrollView and manages follow-bottom behavior
    // through host-side state tracking.
    let overridePath = Self.writeConfigOverrideFile()
    if let overridePath {
        overridePath.withCString { path in
            ghostty_config_load_file(config, path)
        }
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

private static func writeConfigOverrideFile() -> String? {
    let tempDir = FileManager.default.temporaryDirectory
    let overrideURL = tempDir.appendingPathComponent("agent-studio-ghostty-overrides.conf")
    let contents = """
    scroll-to-bottom = no-keystroke, no-output
    scrollbar = never
    """
    do {
        try contents.write(to: overrideURL, atomically: true, encoding: .utf8)
        return overrideURL.path
    } catch {
        ghosttyLogger.error("Failed to write ghostty config override: \(error)")
        return nil
    }
}
```

- [ ] **Step 2: Build to verify no compilation errors**

Run:

```bash
SWIFT_BUILD_DIR=".build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8)" swift build --build-path "$SWIFT_BUILD_DIR" > /tmp/build-output.txt 2>&1 && echo "PASS" || echo "FAIL"
```

Expected: PASS

- [ ] **Step 3: Commit config overrides**

```bash
git add Sources/AgentStudio/Features/Terminal/Ghostty/GhosttyAppHandle.swift
git commit -m "$(cat <<'EOF'
feat: inject ghostty config overrides for scroll behavior

Disable Ghostty's built-in scrollbar and keystroke scroll-to-bottom.
Agent Studio renders its own scrollbar and manages follow-bottom
through host-side state tracking.
EOF
)"
```

---

### Task 1: Update Contracts — ScrollbarState, Search State, Mouse Types, New Events

**Files:**
- Modify: `Sources/AgentStudio/Core/RuntimeEventSystem/Contracts/PaneRuntimeEvent.swift`
- Modify: `Sources/AgentStudio/Core/RuntimeEventSystem/Contracts/PaneKindEvent.swift`
- Modify: `Sources/AgentStudio/Core/RuntimeEventSystem/Replay/EventReplayBuffer.swift`

- [ ] **Step 1: Update ScrollbarState to upstream-aligned fields**

In `Sources/AgentStudio/Core/RuntimeEventSystem/Contracts/PaneRuntimeEvent.swift`, replace the `ScrollbarState` struct (currently around line 357-361):

```swift
// BEFORE:
struct ScrollbarState: Sendable, Equatable {
    let top: Int
    let bottom: Int
    let total: Int
}

// AFTER:
struct ScrollbarState: Sendable, Equatable {
    let totalRows: Int
    let firstVisibleRow: Int
    let visibleRowCount: Int

    var lastVisibleRow: Int {
        min(totalRows, firstVisibleRow + visibleRowCount)
    }

    var isPinnedToBottom: Bool {
        firstVisibleRow + visibleRowCount >= totalRows
    }
}
```

- [ ] **Step 2: Add TerminalSearchState and GhosttyMouseShape**

In the same file, after `ScrollbarState`, add:

```swift
struct TerminalSearchState: Sendable, Equatable {
    let isPresented: Bool
    let query: String
    let totalMatches: Int?
    let selectedMatchIndex: Int?
}

enum GhosttyMouseShape: Sendable, Equatable {
    case defaultCursor
    case text
    case pointer
    case crosshair
    case resizeVertical
    case resizeHorizontal
    case resizeAll
    case notAllowed

    init(rawValue: UInt32) {
        switch rawValue {
        case 0: self = .defaultCursor
        case 1: self = .text
        case 2: self = .pointer
        case 3: self = .crosshair
        case 4: self = .resizeVertical
        case 5: self = .resizeHorizontal
        case 6: self = .resizeAll
        case 7: self = .notAllowed
        default: self = .defaultCursor
        }
    }

    var nsCursor: NSCursor {
        switch self {
        case .defaultCursor: return .arrow
        case .text: return .iBeam
        case .pointer: return .pointingHand
        case .crosshair: return .crosshair
        case .resizeVertical: return .resizeUpDown
        case .resizeHorizontal: return .resizeLeftRight
        case .resizeAll: return .openHand
        case .notAllowed: return .operationNotAllowed
        }
    }
}
```

- [ ] **Step 3: Add 6 new GhosttyEvent cases**

In the `GhosttyEvent` enum (around line 276), add these cases after `.scrollbarChanged`:

```swift
case searchStarted(query: String)
case searchEnded
case searchMatchesUpdated(totalMatches: Int)
case searchSelectionChanged(selectedMatchIndex: Int?)
case mouseShapeChanged(GhosttyMouseShape)
case mouseVisibilityChanged(Bool)
```

- [ ] **Step 4: Update GhosttyEvent.actionPolicy for new cases**

In the `actionPolicy` computed property, add to the lossy branch:

```swift
case .scrollbarChanged:
    return .lossy(consolidationKey: "scroll")
case .searchMatchesUpdated, .searchSelectionChanged:
    return .lossy(consolidationKey: "search")
case .mouseShapeChanged, .mouseVisibilityChanged:
    return .lossy(consolidationKey: "mouse")
```

Add the remaining new cases to the `.critical` fallthrough group:

```swift
case .newTab, .closeTab, .gotoTab, .moveTab, .newSplit, .gotoSplit, .resizeSplit, .equalizeSplits,
    .toggleSplitZoom, .titleChanged, .cwdChanged, .commandFinished, .progressReportUpdated,
    .readOnlyChanged, .secureInputRequested, .secureInputChanged, .rendererHealthChanged,
    .cellSizeChanged, .initialSizeChanged, .sizeLimitChanged, .promptTitleRequested,
    .desktopNotificationRequested, .openURLRequested, .undoRequested, .redoRequested,
    .copyTitleToClipboardRequested, .bellRang, .deferred, .unhandled,
    .searchStarted, .searchEnded:
    return .critical
```

- [ ] **Step 5: Update GhosttyEvent.eventName for new cases**

In the `eventName` computed property, add:

```swift
case .searchStarted: return .searchStarted
case .searchEnded: return .searchEnded
case .searchMatchesUpdated: return .searchMatchesUpdated
case .searchSelectionChanged: return .searchSelectionChanged
case .mouseShapeChanged: return .mouseShapeChanged
case .mouseVisibilityChanged: return .mouseVisibilityChanged
```

- [ ] **Step 6: Add EventIdentifier cases in PaneKindEvent.swift**

In `Sources/AgentStudio/Core/RuntimeEventSystem/Contracts/PaneKindEvent.swift`, add to the `EventIdentifier` enum:

```swift
case searchStarted
case searchEnded
case searchMatchesUpdated
case searchSelectionChanged
case mouseShapeChanged
case mouseVisibilityChanged
```

Add matching `rawValue` entries in the computed property:

```swift
case .searchStarted: return "searchStarted"
case .searchEnded: return "searchEnded"
case .searchMatchesUpdated: return "searchMatchesUpdated"
case .searchSelectionChanged: return "searchSelectionChanged"
case .mouseShapeChanged: return "mouseShapeChanged"
case .mouseVisibilityChanged: return "mouseVisibilityChanged"
```

- [ ] **Step 7: Fix any exhaustiveness errors in EventReplayBuffer**

Read `Sources/AgentStudio/Core/RuntimeEventSystem/Replay/EventReplayBuffer.swift` and add size estimates for new events if the compiler requires it.

- [ ] **Step 8: Build to verify no compilation errors**

Run:

```bash
SWIFT_BUILD_DIR=".build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8)" swift build --build-path "$SWIFT_BUILD_DIR" > /tmp/build-output.txt 2>&1 && echo "PASS" || echo "FAIL"
```

Expected: The build may fail due to exhaustiveness in `TerminalRuntime.handleGhosttyEvent` — that's expected and will be fixed in Task 2.

- [ ] **Step 9: Commit contracts**

```bash
git add \
  Sources/AgentStudio/Core/RuntimeEventSystem/Contracts/PaneRuntimeEvent.swift \
  Sources/AgentStudio/Core/RuntimeEventSystem/Contracts/PaneKindEvent.swift \
  Sources/AgentStudio/Core/RuntimeEventSystem/Replay/EventReplayBuffer.swift
git commit -m "$(cat <<'EOF'
feat: add scrollbar/search/mouse event contracts

Update ScrollbarState to upstream-aligned fields. Add TerminalSearchState,
GhosttyMouseShape, and 6 new GhosttyEvent cases for search and mouse.
EOF
)"
```

---

### Task 2: Route Scrollbar, Search, and Mouse Events Through Runtime

**Files:**
- Modify: `Sources/AgentStudio/Features/Terminal/Ghostty/GhosttyAdapter.swift`
- Modify: `Sources/AgentStudio/Features/Terminal/Ghostty/GhosttyActionRouter.swift`
- Modify: `Sources/AgentStudio/Features/Terminal/Runtime/TerminalRuntime.swift`
- Test: `Tests/AgentStudioTests/Features/Terminal/Ghostty/GhosttyAdapterTests.swift`
- Test: `Tests/AgentStudioTests/Features/Terminal/Ghostty/GhosttyActionRouterTests.swift`
- Test: `Tests/AgentStudioTests/Features/Terminal/Runtime/TerminalRuntimeTests.swift`

- [ ] **Step 1: Write failing adapter translation tests**

In `Tests/AgentStudioTests/Features/Terminal/Ghostty/GhosttyAdapterTests.swift`, add tests to the existing `assertObservedStateMappings` or as new test methods:

```swift
@Test("scrollbar payload maps to upstream-aligned state")
@MainActor
func scrollbarMapsToUpstreamAlignedState() {
    let adapter = GhosttyAdapter.shared
    let event = adapter.translate(
        actionTag: GhosttyActionTag.scrollbar,
        payload: .scrollbar(total: 200, offset: 150, len: 40)
    )
    #expect(
        event == .scrollbarChanged(
            ScrollbarState(totalRows: 200, firstVisibleRow: 150, visibleRowCount: 40)
        )
    )
}

@Test("startSearch payload maps to searchStarted")
@MainActor
func startSearchMapsToSearchStarted() {
    let adapter = GhosttyAdapter.shared
    let event = adapter.translate(
        actionTag: GhosttyActionTag.startSearch,
        payload: .startSearch(query: "needle")
    )
    #expect(event == .searchStarted(query: "needle"))
}

@Test("endSearch maps to searchEnded")
@MainActor
func endSearchMapsToSearchEnded() {
    let adapter = GhosttyAdapter.shared
    let event = adapter.translate(
        actionTag: GhosttyActionTag.endSearch,
        payload: .noPayload
    )
    #expect(event == .searchEnded)
}

@Test("searchTotal maps to searchMatchesUpdated")
@MainActor
func searchTotalMapsToSearchMatchesUpdated() {
    let adapter = GhosttyAdapter.shared
    let event = adapter.translate(
        actionTag: GhosttyActionTag.searchTotal,
        payload: .searchTotal(total: 12)
    )
    #expect(event == .searchMatchesUpdated(totalMatches: 12))
}

@Test("searchSelected maps to searchSelectionChanged")
@MainActor
func searchSelectedMapsToSearchSelectionChanged() {
    let adapter = GhosttyAdapter.shared
    let event = adapter.translate(
        actionTag: GhosttyActionTag.searchSelected,
        payload: .searchSelected(selected: 3)
    )
    #expect(event == .searchSelectionChanged(selectedMatchIndex: 3))
}

@Test("mouseShape maps to mouseShapeChanged")
@MainActor
func mouseShapeMapsToMouseShapeChanged() {
    let adapter = GhosttyAdapter.shared
    let event = adapter.translate(
        actionTag: GhosttyActionTag.mouseShape,
        payload: .mouseShape(shapeRawValue: 2)
    )
    #expect(event == .mouseShapeChanged(.pointer))
}

@Test("mouseVisibility maps to mouseVisibilityChanged")
@MainActor
func mouseVisibilityMapsToMouseVisibilityChanged() {
    let adapter = GhosttyAdapter.shared
    let event = adapter.translate(
        actionTag: GhosttyActionTag.mouseVisibility,
        payload: .mouseVisibility(visible: false)
    )
    #expect(event == .mouseVisibilityChanged(false))
}
```

- [ ] **Step 2: Run adapter tests to confirm they fail**

Run:

```bash
SWIFT_BUILD_DIR=".build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8)"
swift test --build-path "$SWIFT_BUILD_DIR" --filter "GhosttyAdapterTests" > /tmp/test-output.txt 2>&1 && echo "PASS" || echo "FAIL"
```

Expected: FAIL — new `ActionPayload` variants and translation logic don't exist yet.

- [ ] **Step 3: Add ActionPayload variants in GhosttyAdapter.swift**

In the `ActionPayload` enum (around line 57-78), add:

```swift
case scrollbar(total: UInt64, offset: UInt64, len: UInt64)
case startSearch(query: String)
case searchTotal(total: Int)
case searchSelected(selected: Int)
case mouseShape(shapeRawValue: UInt32)
case mouseVisibility(visible: Bool)
```

- [ ] **Step 4: Add translation logic in GhosttyAdapter.swift**

Add a new private translation method and wire it into the main `translate` method. Update the scrollbar translation to use the new `ScrollbarState` fields:

```swift
private func translateScrollbackAction(
    tag: GhosttyActionTag,
    payload: ActionPayload
) -> GhosttyEvent? {
    switch tag {
    case .scrollbar:
        guard case .scrollbar(let total, let offset, let len) = payload else {
            return .unhandled(tag: tag.rawValue)
        }
        return .scrollbarChanged(
            ScrollbarState(
                totalRows: Int(total),
                firstVisibleRow: Int(offset),
                visibleRowCount: Int(len)
            )
        )
    case .startSearch:
        guard case .startSearch(let query) = payload else {
            return .unhandled(tag: tag.rawValue)
        }
        return .searchStarted(query: query)
    case .endSearch:
        return .searchEnded
    case .searchTotal:
        guard case .searchTotal(let total) = payload else {
            return .unhandled(tag: tag.rawValue)
        }
        return .searchMatchesUpdated(totalMatches: total)
    case .searchSelected:
        guard case .searchSelected(let selected) = payload else {
            return .unhandled(tag: tag.rawValue)
        }
        return .searchSelectionChanged(selectedMatchIndex: selected >= 0 ? selected : nil)
    case .mouseShape:
        guard case .mouseShape(let shapeRawValue) = payload else {
            return .unhandled(tag: tag.rawValue)
        }
        return .mouseShapeChanged(GhosttyMouseShape(rawValue: shapeRawValue))
    case .mouseVisibility:
        guard case .mouseVisibility(let visible) = payload else {
            return .unhandled(tag: tag.rawValue)
        }
        return .mouseVisibilityChanged(visible)
    default:
        return nil
    }
}
```

Wire this into the main `translate` method — call `translateScrollbackAction` and return if non-nil.

Also remove `scrollbar`, `startSearch`, `endSearch`, `searchTotal`, `searchSelected`, `mouseShape`, `mouseVisibility` from the adapter's `deferredTags` set.

- [ ] **Step 5: Move tags in GhosttyActionRouter.swift**

In `Sources/AgentStudio/Features/Terminal/Ghostty/GhosttyActionRouter.swift`:

Remove from `deferredTags` (line 48-64):
- `.scrollbar`
- `.startSearch`
- `.endSearch`
- `.searchTotal`
- `.searchSelected`
- `.mouseShape`
- `.mouseVisibility`

Add to `explicitlyRoutedTags` (line 20-47):
- `.scrollbar`
- `.startSearch`
- `.endSearch`
- `.searchTotal`
- `.searchSelected`
- `.mouseShape`
- `.mouseVisibility`

Add routing cases in the action handler. Read the existing `handleObservedRequestAction` method to see the pattern, then add cases for each tag. Extract C payloads and call `routeActionToTerminalRuntime` with `handledResult: false`:

```swift
case .scrollbar:
    return routeActionToTerminalRuntime(
        actionTag: rawActionTag,
        payload: .scrollbar(
            total: action.action.scrollbar.total,
            offset: action.action.scrollbar.offset,
            len: action.action.scrollbar.len
        ),
        target: target,
        routingLookupProvider: routingLookupProvider,
        handledResult: false
    )
case .startSearch:
    let query = action.action.start_search.needle.map { String(cString: $0) } ?? ""
    return routeActionToTerminalRuntime(
        actionTag: rawActionTag,
        payload: .startSearch(query: query),
        target: target,
        routingLookupProvider: routingLookupProvider,
        handledResult: false
    )
case .endSearch:
    return routeActionToTerminalRuntime(
        actionTag: rawActionTag,
        payload: .noPayload,
        target: target,
        routingLookupProvider: routingLookupProvider,
        handledResult: false
    )
case .searchTotal:
    return routeActionToTerminalRuntime(
        actionTag: rawActionTag,
        payload: .searchTotal(total: Int(action.action.search_total.total)),
        target: target,
        routingLookupProvider: routingLookupProvider,
        handledResult: false
    )
case .searchSelected:
    return routeActionToTerminalRuntime(
        actionTag: rawActionTag,
        payload: .searchSelected(selected: Int(action.action.search_selected.selected)),
        target: target,
        routingLookupProvider: routingLookupProvider,
        handledResult: false
    )
case .mouseShape:
    return routeActionToTerminalRuntime(
        actionTag: rawActionTag,
        payload: .mouseShape(shapeRawValue: action.action.mouse_shape.rawValue),
        target: target,
        routingLookupProvider: routingLookupProvider,
        handledResult: false
    )
case .mouseVisibility:
    return routeActionToTerminalRuntime(
        actionTag: rawActionTag,
        payload: .mouseVisibility(visible: action.action.mouse_visibility),
        target: target,
        routingLookupProvider: routingLookupProvider,
        handledResult: false
    )
```

**Important:** Read the C header (`vendor/ghostty/include/ghostty.h`) to verify the exact C struct field names before coding. The field names above are best guesses — the implementer must confirm against the header.

- [ ] **Step 6: Handle new events in TerminalRuntime.handleGhosttyEvent**

In `Sources/AgentStudio/Features/Terminal/Runtime/TerminalRuntime.swift`, add `@Observable` properties:

```swift
private(set) var scrollbarState: ScrollbarState?
private(set) var searchState: TerminalSearchState?
private(set) var mouseShape: GhosttyMouseShape = .defaultCursor
private(set) var mouseVisible: Bool = true
```

Update `handleGhosttyEvent` — the existing `scrollbarChanged` case needs to update the new property. Add new cases:

```swift
case .scrollbarChanged(let state):
    scrollbarState = state
    emit(event, commandId: commandId, correlationId: correlationId, persistForReplay: true)
case .searchStarted(let query):
    searchState = TerminalSearchState(isPresented: true, query: query, totalMatches: nil, selectedMatchIndex: nil)
    emit(event, commandId: commandId, correlationId: correlationId, persistForReplay: true)
case .searchMatchesUpdated(let totalMatches):
    if let existing = searchState {
        searchState = TerminalSearchState(
            isPresented: existing.isPresented,
            query: existing.query,
            totalMatches: totalMatches,
            selectedMatchIndex: existing.selectedMatchIndex
        )
    }
    emit(event, commandId: commandId, correlationId: correlationId, persistForReplay: true)
case .searchSelectionChanged(let selectedMatchIndex):
    if let existing = searchState {
        searchState = TerminalSearchState(
            isPresented: existing.isPresented,
            query: existing.query,
            totalMatches: existing.totalMatches,
            selectedMatchIndex: selectedMatchIndex
        )
    }
    emit(event, commandId: commandId, correlationId: correlationId, persistForReplay: true)
case .searchEnded:
    searchState = nil
    emit(event, commandId: commandId, correlationId: correlationId, persistForReplay: true)
case .mouseShapeChanged(let shape):
    mouseShape = shape
case .mouseVisibilityChanged(let visible):
    mouseVisible = visible
```

Note: mouse events are `@Observable` only — no bus post, no replay. The surface view observes them directly.

- [ ] **Step 7: Write runtime search state machine test**

In `Tests/AgentStudioTests/Features/Terminal/Runtime/TerminalRuntimeTests.swift`:

```swift
@Test("search state machine: started → matches → selection → ended")
@MainActor
func searchStateMachine() {
    let runtime = TerminalRuntime(
        paneId: PaneId(),
        metadata: PaneMetadata(
            source: .floating(launchDirectory: nil, title: "Test"),
            title: "Test"
        )
    )
    runtime.transitionToReady()

    #expect(runtime.searchState == nil)

    runtime.handleGhosttyEvent(.searchStarted(query: "needle"))
    #expect(runtime.searchState?.isPresented == true)
    #expect(runtime.searchState?.query == "needle")
    #expect(runtime.searchState?.totalMatches == nil)

    runtime.handleGhosttyEvent(.searchMatchesUpdated(totalMatches: 12))
    #expect(runtime.searchState?.totalMatches == 12)

    runtime.handleGhosttyEvent(.searchSelectionChanged(selectedMatchIndex: 3))
    #expect(runtime.searchState?.selectedMatchIndex == 3)

    runtime.handleGhosttyEvent(.searchEnded)
    #expect(runtime.searchState == nil)
}

@Test("scrollbarState updates with upstream-aligned fields")
@MainActor
func scrollbarStateUpdates() {
    let runtime = TerminalRuntime(
        paneId: PaneId(),
        metadata: PaneMetadata(
            source: .floating(launchDirectory: nil, title: "Test"),
            title: "Test"
        )
    )
    runtime.transitionToReady()

    runtime.handleGhosttyEvent(.scrollbarChanged(
        ScrollbarState(totalRows: 200, firstVisibleRow: 160, visibleRowCount: 40)
    ))
    #expect(runtime.scrollbarState?.totalRows == 200)
    #expect(runtime.scrollbarState?.isPinnedToBottom == true)

    runtime.handleGhosttyEvent(.scrollbarChanged(
        ScrollbarState(totalRows: 200, firstVisibleRow: 80, visibleRowCount: 40)
    ))
    #expect(runtime.scrollbarState?.isPinnedToBottom == false)
}

@Test("mouseShape and mouseVisible are observable-only")
@MainActor
func mouseObservableOnly() {
    let runtime = TerminalRuntime(
        paneId: PaneId(),
        metadata: PaneMetadata(
            source: .floating(launchDirectory: nil, title: "Test"),
            title: "Test"
        )
    )
    runtime.transitionToReady()

    runtime.handleGhosttyEvent(.mouseShapeChanged(.pointer))
    #expect(runtime.mouseShape == .pointer)

    runtime.handleGhosttyEvent(.mouseVisibilityChanged(false))
    #expect(runtime.mouseVisible == false)
}
```

- [ ] **Step 8: Update action router test — deferred tags no longer include scrollbar/search/mouse**

In `Tests/AgentStudioTests/Features/Terminal/Ghostty/GhosttyActionRouterTests.swift`, find the test that checks `Ghostty.ActionRouter.deferredTags` contains `.startSearch`, `.mouseShape`, etc. Update it to verify these are NOT in `deferredTags`:

```swift
@Test("scrollbar, search, and mouse tags are not deferred")
@MainActor
func scrollbarSearchMouseNotDeferred() {
    let deferred = Ghostty.ActionRouter.deferredTags
    #expect(!deferred.contains(.scrollbar))
    #expect(!deferred.contains(.startSearch))
    #expect(!deferred.contains(.endSearch))
    #expect(!deferred.contains(.searchTotal))
    #expect(!deferred.contains(.searchSelected))
    #expect(!deferred.contains(.mouseShape))
    #expect(!deferred.contains(.mouseVisibility))
}
```

- [ ] **Step 9: Run all tests**

Run:

```bash
SWIFT_BUILD_DIR=".build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8)"
swift test --build-path "$SWIFT_BUILD_DIR" --filter "GhosttyAdapterTests|GhosttyActionRouterTests|TerminalRuntimeTests" > /tmp/test-output.txt 2>&1 && echo "PASS" || echo "FAIL"
```

Expected: PASS

- [ ] **Step 10: Commit event routing**

```bash
git add \
  Sources/AgentStudio/Features/Terminal/Ghostty/GhosttyAdapter.swift \
  Sources/AgentStudio/Features/Terminal/Ghostty/GhosttyActionRouter.swift \
  Sources/AgentStudio/Features/Terminal/Runtime/TerminalRuntime.swift \
  Tests/AgentStudioTests/Features/Terminal/Ghostty/GhosttyAdapterTests.swift \
  Tests/AgentStudioTests/Features/Terminal/Ghostty/GhosttyActionRouterTests.swift \
  Tests/AgentStudioTests/Features/Terminal/Runtime/TerminalRuntimeTests.swift
git commit -m "$(cat <<'EOF'
feat: route scrollbar, search, and mouse events through terminal runtime

Move 7 tags from deferredTags to explicitlyRoutedTags with typed payloads.
Add search state machine and mouse shape/visibility on TerminalRuntime.
EOF
)"
```

---

### Task 3: Action Performing Protocol and Scroll Wrapper

**Files:**
- Create: `Sources/AgentStudio/Features/Terminal/Hosting/TerminalSurfaceActionPerforming.swift`
- Create: `Sources/AgentStudio/Features/Terminal/Hosting/TerminalSurfaceScrollView.swift`
- Modify: `Sources/AgentStudio/Features/Terminal/Ghostty/GhosttySurfaceView.swift`
- Test: `Tests/AgentStudioTests/Features/Terminal/Hosting/TerminalSurfaceScrollViewTests.swift`

- [ ] **Step 1: Create TerminalSurfaceActionPerforming protocol**

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

- [ ] **Step 2: Write failing scroll view tests**

Create `Tests/AgentStudioTests/Features/Terminal/Hosting/TerminalSurfaceScrollViewTests.swift`:

```swift
import AppKit
import Testing

@testable import AgentStudio

@MainActor
private final class FakeSurfaceActionPerformer: TerminalSurfaceActionPerforming {
    private(set) var actions: [String] = []

    @discardableResult
    func performBindingAction(_ action: String) -> Bool {
        actions.append(action)
        return true
    }
}

@Suite("TerminalSurfaceScrollView")
@MainActor
struct TerminalSurfaceScrollViewTests {
    @Test("live scroll sends scroll_to_row with dedup")
    func liveScrollSendsScrollToRow() {
        let performer = FakeSurfaceActionPerformer()
        let scrollView = TerminalSurfaceScrollView(actionPerformer: performer)
        scrollView.frame = NSRect(x: 0, y: 0, width: 800, height: 600)

        scrollView.applyScrollbarState(
            ScrollbarState(totalRows: 200, firstVisibleRow: 100, visibleRowCount: 40),
            cellHeight: 20
        )
        scrollView.simulateLiveScrollForTesting(documentOffsetY: 1200)

        #expect(performer.actions.last?.starts(with: "scroll_to_row:") == true)

        // Same position again — should NOT send duplicate
        let countBefore = performer.actions.count
        scrollView.simulateLiveScrollForTesting(documentOffsetY: 1200)
        #expect(performer.actions.count == countBefore)
    }

    @Test("follow-bottom: pinned viewport follows new output")
    func pinnedViewportFollowsOutput() {
        let performer = FakeSurfaceActionPerformer()
        let scrollView = TerminalSurfaceScrollView(actionPerformer: performer)
        scrollView.frame = NSRect(x: 0, y: 0, width: 800, height: 600)

        // Start pinned to bottom
        scrollView.applyScrollbarState(
            ScrollbarState(totalRows: 200, firstVisibleRow: 160, visibleRowCount: 40),
            cellHeight: 20
        )
        let pinnedOffset = scrollView.documentOffsetYForTesting

        // New output arrives, still pinned
        scrollView.applyScrollbarState(
            ScrollbarState(totalRows: 210, firstVisibleRow: 170, visibleRowCount: 40),
            cellHeight: 20
        )
        #expect(scrollView.documentOffsetYForTesting != pinnedOffset)
    }

    @Test("follow-bottom: scrolled-up viewport holds position")
    func scrolledUpViewportHoldsPosition() {
        let performer = FakeSurfaceActionPerformer()
        let scrollView = TerminalSurfaceScrollView(actionPerformer: performer)
        scrollView.frame = NSRect(x: 0, y: 0, width: 800, height: 600)

        // User scrolled up (not pinned)
        scrollView.applyScrollbarState(
            ScrollbarState(totalRows: 200, firstVisibleRow: 80, visibleRowCount: 40),
            cellHeight: 20
        )
        let historyOffset = scrollView.documentOffsetYForTesting

        // New output arrives — should NOT move
        scrollView.applyScrollbarState(
            ScrollbarState(totalRows: 210, firstVisibleRow: 80, visibleRowCount: 40),
            cellHeight: 20
        )
        #expect(scrollView.documentOffsetYForTesting == historyOffset)
    }

    @Test("isPinnedToBottom computed property")
    func isPinnedToBottom() {
        let pinned = ScrollbarState(totalRows: 200, firstVisibleRow: 160, visibleRowCount: 40)
        #expect(pinned.isPinnedToBottom == true)

        let notPinned = ScrollbarState(totalRows: 200, firstVisibleRow: 80, visibleRowCount: 40)
        #expect(notPinned.isPinnedToBottom == false)
    }
}
```

- [ ] **Step 3: Run tests to confirm they fail**

Run:

```bash
SWIFT_BUILD_DIR=".build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8)"
swift test --build-path "$SWIFT_BUILD_DIR" --filter "TerminalSurfaceScrollViewTests" > /tmp/test-output.txt 2>&1 && echo "PASS" || echo "FAIL"
```

Expected: FAIL — `TerminalSurfaceScrollView` doesn't exist yet.

- [ ] **Step 4: Implement TerminalSurfaceScrollView**

Create `Sources/AgentStudio/Features/Terminal/Hosting/TerminalSurfaceScrollView.swift`. Follow Ghostty's `SurfaceScrollView` three-layer architecture. Read `vendor/ghostty/macos/Sources/Ghostty/Surface View/SurfaceScrollView.swift` lines 15-396 for the reference implementation. Key adaptations:

- Always-visible scrollbar (not config-dependent)
- Observe `TerminalRuntime.scrollbarState` via `withObservationTracking` instead of `NotificationCenter`
- Send `scroll_to_row:N` via `TerminalSurfaceActionPerforming` instead of `surfaceModel.perform()`
- Track `wasPinnedToBottom` for follow-bottom behavior
- Coordinate math: same formulas as upstream (lines 220-242, 354-366)

The implementation must include:
- `applyScrollbarState(_:cellHeight:)` — public method for testing and runtime observation
- `simulateLiveScrollForTesting(documentOffsetY:)` — test helper
- `documentOffsetYForTesting` — test helper
- `embedSurfaceView(_:)` — adds the Ghostty surface as a subview of documentView

- [ ] **Step 5: Run tests until they pass**

Run:

```bash
SWIFT_BUILD_DIR=".build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8)"
swift test --build-path "$SWIFT_BUILD_DIR" --filter "TerminalSurfaceScrollViewTests" > /tmp/test-output.txt 2>&1 && echo "PASS" || echo "FAIL"
```

Expected: PASS

- [ ] **Step 6: Commit scroll wrapper**

```bash
git add \
  Sources/AgentStudio/Features/Terminal/Hosting/TerminalSurfaceActionPerforming.swift \
  Sources/AgentStudio/Features/Terminal/Hosting/TerminalSurfaceScrollView.swift \
  Tests/AgentStudioTests/Features/Terminal/Hosting/TerminalSurfaceScrollViewTests.swift
git commit -m "$(cat <<'EOF'
feat: add terminal scroll wrapper with follow-bottom behavior

NSScrollView overlay wrapper around Ghostty surface. Follows
Ghostty's SurfaceScrollView coordinate math. Only auto-scrolls
when pinned to bottom.
EOF
)"
```

---

### Task 4: Search Overlay and Find Menu

**Files:**
- Create: `Sources/AgentStudio/Features/Terminal/Hosting/TerminalSearchOverlayView.swift`
- Modify: `Sources/AgentStudio/Features/Terminal/Hosting/TerminalPaneMountView.swift`
- Modify: `Sources/AgentStudio/App/Boot/AppDelegate.swift`
- Test: `Tests/AgentStudioTests/Features/Terminal/Hosting/TerminalSearchOverlayViewTests.swift`
- Test: `Tests/AgentStudioTests/Features/Terminal/Hosting/TerminalPaneMountViewSearchTests.swift`

- [ ] **Step 1: Write failing search overlay tests**

Create `Tests/AgentStudioTests/Features/Terminal/Hosting/TerminalSearchOverlayViewTests.swift`:

```swift
import AppKit
import Testing

@testable import AgentStudio

@Suite("TerminalSearchOverlayView")
@MainActor
struct TerminalSearchOverlayViewTests {
    @Test("overlay emits callbacks for query, navigation, and close")
    func overlayEmitsCallbacks() {
        let overlay = TerminalSearchOverlayView()
        var queries: [String] = []
        var directions: [TerminalSearchOverlayView.NavigationDirection] = []
        var closeCount = 0

        overlay.onQueryChanged = { queries.append($0) }
        overlay.onNavigate = { directions.append($0) }
        overlay.onClose = { closeCount += 1 }

        overlay.simulateQueryChangeForTesting("hello")
        overlay.simulateNavigateForTesting(.next)
        overlay.simulateNavigateForTesting(.previous)
        overlay.simulateCloseForTesting()

        #expect(queries == ["hello"])
        #expect(directions == [.next, .previous])
        #expect(closeCount == 1)
    }

    @Test("update sets result label text")
    func updateSetsResultLabel() {
        let overlay = TerminalSearchOverlayView()
        overlay.update(query: "needle", totalMatches: 12, selectedMatchIndex: 3)
        #expect(overlay.resultLabelTextForTesting == "4 of 12")

        overlay.update(query: "needle", totalMatches: 0, selectedMatchIndex: nil)
        #expect(overlay.resultLabelTextForTesting == "0 of 0")

        overlay.update(query: "", totalMatches: nil, selectedMatchIndex: nil)
        #expect(overlay.resultLabelTextForTesting == "")
    }
}
```

- [ ] **Step 2: Write failing mount view search responder tests**

Create `Tests/AgentStudioTests/Features/Terminal/Hosting/TerminalPaneMountViewSearchTests.swift`:

```swift
import AppKit
import Testing

@testable import AgentStudio

@Suite("TerminalPaneMountView search responders")
@MainActor
struct TerminalPaneMountViewSearchTests {
    @Test("search responders send correct binding actions")
    func searchRespondersSendCorrectActions() {
        let mountView = TerminalPaneMountView(paneId: UUID(), title: "Terminal")
        let performer = FakeSurfaceActionPerformer()
        mountView.installActionPerformerForTesting(performer)

        mountView.performSelector(onMainThread: Selector(("startSearch:")), with: nil, waitUntilDone: true)
        mountView.performSelector(onMainThread: Selector(("findNext:")), with: nil, waitUntilDone: true)
        mountView.performSelector(onMainThread: Selector(("findPrevious:")), with: nil, waitUntilDone: true)

        #expect(performer.actions.contains("start_search"))
        #expect(performer.actions.contains("navigate_search:next"))
        #expect(performer.actions.contains("navigate_search:previous"))
    }
}
```

- [ ] **Step 3: Run tests to confirm failure**

Run:

```bash
SWIFT_BUILD_DIR=".build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8)"
swift test --build-path "$SWIFT_BUILD_DIR" --filter "TerminalSearchOverlayViewTests|TerminalPaneMountViewSearchTests" > /tmp/test-output.txt 2>&1 && echo "PASS" || echo "FAIL"
```

Expected: FAIL

- [ ] **Step 4: Implement TerminalSearchOverlayView**

Create `Sources/AgentStudio/Features/Terminal/Hosting/TerminalSearchOverlayView.swift`. Pure AppKit — `NSSearchField` + result label + navigation buttons + close button. Callbacks via closures. Test helpers for simulation. The overlay is a rounded-corner `NSVisualEffectView` with blur.

- [ ] **Step 5: Add responder methods and search overlay to TerminalPaneMountView**

In `Sources/AgentStudio/Features/Terminal/Hosting/TerminalPaneMountView.swift`, add:

- Private properties: `searchOverlayView: TerminalSearchOverlayView?`, `actionPerformerOverrideForTesting`, `surfaceScrollView: TerminalSurfaceScrollView?`, `scrollToBottomView: ScrollToBottomIndicatorView?`
- `bind(runtime: TerminalRuntime)` method — stores weak runtime ref, starts observation
- `@objc func startSearch(_ sender: Any?)` — shows overlay, sends `start_search`
- `@objc func findNext(_ sender: Any?)` — sends `navigate_search:next`
- `@objc func findPrevious(_ sender: Any?)` — sends `navigate_search:previous`
- `override func cancelOperation(_ sender: Any?)` — sends `end_search`, hides overlay, refocuses surface
- `installActionPerformerForTesting(_:)` — for tests
- Updated `hitTest(_:)` — check search overlay and scroll-to-bottom before error overlay

- [ ] **Step 6: Add Find menu entries in AppDelegate**

In `Sources/AgentStudio/App/Boot/AppDelegate.swift`, read the existing menu setup code. Add a Find submenu under Edit:

```swift
let findMenu = NSMenu(title: "Find")
findMenu.addItem(NSMenuItem(title: "Find…", action: #selector(NSResponder.startSearch(_:)), keyEquivalent: "f"))
findMenu.addItem(NSMenuItem(title: "Find Next", action: #selector(NSResponder.findNext(_:)), keyEquivalent: "g"))
let findPreviousItem = NSMenuItem(title: "Find Previous", action: #selector(NSResponder.findPrevious(_:)), keyEquivalent: "G")
findPreviousItem.keyEquivalentModifierMask = [.command, .shift]
findMenu.addItem(findPreviousItem)
let findMenuItem = NSMenuItem(title: "Find", action: nil, keyEquivalent: "")
findMenuItem.submenu = findMenu
// Add findMenuItem to the Edit menu
```

**Note:** Read `AppDelegate.swift` first to find the exact Edit menu construction code and insert the Find submenu at the correct position.

- [ ] **Step 7: Run tests until they pass**

Run:

```bash
SWIFT_BUILD_DIR=".build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8)"
swift test --build-path "$SWIFT_BUILD_DIR" --filter "TerminalSearchOverlayViewTests|TerminalPaneMountViewSearchTests" > /tmp/test-output.txt 2>&1 && echo "PASS" || echo "FAIL"
```

Expected: PASS

- [ ] **Step 8: Commit search overlay**

```bash
git add \
  Sources/AgentStudio/Features/Terminal/Hosting/TerminalSearchOverlayView.swift \
  Sources/AgentStudio/Features/Terminal/Hosting/TerminalPaneMountView.swift \
  Sources/AgentStudio/App/Boot/AppDelegate.swift \
  Tests/AgentStudioTests/Features/Terminal/Hosting/TerminalSearchOverlayViewTests.swift \
  Tests/AgentStudioTests/Features/Terminal/Hosting/TerminalPaneMountViewSearchTests.swift
git commit -m "$(cat <<'EOF'
feat: add scrollback search overlay and macOS Find menu

cmd+f opens top-center search bar in focused pane. cmd+g / shift+cmd+g
navigate matches. Escape clears and closes. Pure AppKit for responder
chain participation.
EOF
)"
```

---

### Task 5: Scroll-to-Bottom Indicator

**Files:**
- Create: `Sources/AgentStudio/Features/Terminal/Hosting/ScrollToBottomIndicatorView.swift`
- Test: `Tests/AgentStudioTests/Features/Terminal/Hosting/ScrollToBottomIndicatorViewTests.swift`

- [ ] **Step 1: Write failing indicator tests**

Create `Tests/AgentStudioTests/Features/Terminal/Hosting/ScrollToBottomIndicatorViewTests.swift`:

```swift
import AppKit
import Testing

@testable import AgentStudio

@Suite("ScrollToBottomIndicatorView")
@MainActor
struct ScrollToBottomIndicatorViewTests {
    @Test("hidden when pinned to bottom")
    func hiddenWhenPinned() {
        let indicator = ScrollToBottomIndicatorView()
        indicator.applyScrollbarState(
            ScrollbarState(totalRows: 200, firstVisibleRow: 160, visibleRowCount: 40)
        )
        #expect(indicator.isHidden == true)
    }

    @Test("visible when scrolled up")
    func visibleWhenScrolledUp() {
        let indicator = ScrollToBottomIndicatorView()
        indicator.applyScrollbarState(
            ScrollbarState(totalRows: 200, firstVisibleRow: 80, visibleRowCount: 40)
        )
        #expect(indicator.isHidden == false)
    }

    @Test("shows new output indicator when totalRows grows while scrolled up")
    func newOutputIndicator() {
        let indicator = ScrollToBottomIndicatorView()

        // Scroll up
        indicator.applyScrollbarState(
            ScrollbarState(totalRows: 200, firstVisibleRow: 80, visibleRowCount: 40)
        )
        #expect(indicator.hasNewOutputForTesting == false)

        // New output arrives while scrolled up
        indicator.applyScrollbarState(
            ScrollbarState(totalRows: 210, firstVisibleRow: 80, visibleRowCount: 40)
        )
        #expect(indicator.hasNewOutputForTesting == true)

        // Scroll back to bottom — resets indicator
        indicator.applyScrollbarState(
            ScrollbarState(totalRows: 210, firstVisibleRow: 170, visibleRowCount: 40)
        )
        #expect(indicator.isHidden == true)
        #expect(indicator.hasNewOutputForTesting == false)
    }

    @Test("click triggers scroll-to-bottom action")
    func clickTriggersAction() {
        let performer = FakeSurfaceActionPerformer()
        let indicator = ScrollToBottomIndicatorView()
        indicator.actionPerformer = performer

        indicator.applyScrollbarState(
            ScrollbarState(totalRows: 200, firstVisibleRow: 80, visibleRowCount: 40)
        )
        indicator.simulateClickForTesting()

        #expect(performer.actions == ["scroll_to_bottom"])
    }
}
```

- [ ] **Step 2: Run tests to confirm failure**

Run:

```bash
SWIFT_BUILD_DIR=".build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8)"
swift test --build-path "$SWIFT_BUILD_DIR" --filter "ScrollToBottomIndicatorViewTests" > /tmp/test-output.txt 2>&1 && echo "PASS" || echo "FAIL"
```

Expected: FAIL

- [ ] **Step 3: Implement ScrollToBottomIndicatorView**

Create `Sources/AgentStudio/Features/Terminal/Hosting/ScrollToBottomIndicatorView.swift`. Pure AppKit — a rounded button with SF Symbol icon (`chevron.down`). Two states: default icon and new-output icon (add a small dot badge or use `chevron.down.circle.fill`). Track `totalRowsWhenScrolledUp` to detect new output.

- [ ] **Step 4: Run tests until they pass**

Run:

```bash
SWIFT_BUILD_DIR=".build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8)"
swift test --build-path "$SWIFT_BUILD_DIR" --filter "ScrollToBottomIndicatorViewTests" > /tmp/test-output.txt 2>&1 && echo "PASS" || echo "FAIL"
```

Expected: PASS

- [ ] **Step 5: Commit indicator**

```bash
git add \
  Sources/AgentStudio/Features/Terminal/Hosting/ScrollToBottomIndicatorView.swift \
  Tests/AgentStudioTests/Features/Terminal/Hosting/ScrollToBottomIndicatorViewTests.swift
git commit -m "$(cat <<'EOF'
feat: add scroll-to-bottom indicator with new-output badge

Floating button appears when scrolled up. Icon changes when new
terminal output arrives below viewport. Click scrolls to bottom.
EOF
)"
```

---

### Task 6: Compose Views in Mount View and Wire Runtime

**Files:**
- Modify: `Sources/AgentStudio/Features/Terminal/Hosting/TerminalPaneMountView.swift`
- Modify: `Sources/AgentStudio/App/Coordination/PaneCoordinator+ViewLifecycle.swift`
- Modify: `Sources/AgentStudio/Features/Terminal/Ghostty/GhosttySurfaceView.swift`

- [ ] **Step 1: Update displaySurface to compose scroll wrapper**

In `TerminalPaneMountView.displaySurface(_:)`, replace the direct `ghosttyMountView.mount(surfaceView)` with:

```swift
let scrollView = TerminalSurfaceScrollView(actionPerformer: surfaceView)
scrollView.embedSurfaceView(surfaceView)
ghosttyMountView.mountAnyViewForTesting(scrollView) // Use the generic mount, or update GhosttyMountView
surfaceScrollView = scrollView
ghosttySurface = surfaceView
```

Read the current `displaySurface` implementation to understand the exact wiring — the scroll wrapper goes between the mount view and the surface.

- [ ] **Step 2: Add scroll-to-bottom indicator as sibling overlay**

After the scroll wrapper is set up, add the indicator:

```swift
let indicator = ScrollToBottomIndicatorView()
indicator.actionPerformer = surfaceView
indicator.translatesAutoresizingMaskIntoConstraints = false
addSubview(indicator)
NSLayoutConstraint.activate([
    indicator.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
    indicator.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -16),
])
scrollToBottomView = indicator
```

- [ ] **Step 3: Implement bind(runtime:) with observation**

Add to `TerminalPaneMountView`:

```swift
private weak var boundRuntime: TerminalRuntime?
private var runtimeObservationTask: Task<Void, Never>?

func bind(runtime: TerminalRuntime) {
    runtimeObservationTask?.cancel()
    boundRuntime = runtime
    observeScrollbarState()
    observeSearchState()
}

private func observeScrollbarState() {
    guard let runtime = boundRuntime else { return }
    withObservationTracking {
        _ = runtime.scrollbarState
        _ = runtime.cellSize
    } onChange: { [weak self] in
        Task { @MainActor [weak self] in
            guard let self, let runtime = self.boundRuntime else { return }
            if let state = runtime.scrollbarState {
                let cellHeight = runtime.cellSize.height
                self.surfaceScrollView?.applyScrollbarState(state, cellHeight: cellHeight)
                self.scrollToBottomView?.applyScrollbarState(state)
            }
            self.observeScrollbarState()
        }
    }
}

private func observeSearchState() {
    guard let runtime = boundRuntime else { return }
    withObservationTracking {
        _ = runtime.searchState
    } onChange: { [weak self] in
        Task { @MainActor [weak self] in
            guard let self, let runtime = self.boundRuntime else { return }
            if let searchState = runtime.searchState, searchState.isPresented {
                self.ensureSearchOverlay()
                self.searchOverlayView?.update(
                    query: searchState.query,
                    totalMatches: searchState.totalMatches,
                    selectedMatchIndex: searchState.selectedMatchIndex
                )
            } else {
                self.hideSearchOverlay()
            }
            self.observeSearchState()
        }
    }
}
```

- [ ] **Step 4: Wire bind(runtime:) in PaneCoordinator+ViewLifecycle**

Read `Sources/AgentStudio/App/Coordination/PaneCoordinator+ViewLifecycle.swift` to find where the terminal mount view and runtime are both available. After the runtime is registered and the mount view has a surface, call:

```swift
if let terminalView = viewRegistry.terminalView(for: pane.id),
   let runtime = RuntimeRegistry.shared.runtime(for: paneId) as? TerminalRuntime {
    terminalView.bind(runtime: runtime)
}
```

The exact method names and registry access patterns may differ — read the file first.

- [ ] **Step 5: Add mouse cursor observation to GhosttySurfaceView**

In `Sources/AgentStudio/Features/Terminal/Ghostty/GhosttySurfaceView.swift`, add mouse cursor observation. The surface view needs a reference to its runtime to observe `mouseShape` and `mouseVisible`:

```swift
private weak var terminalRuntime: TerminalRuntime?

func bindRuntime(_ runtime: TerminalRuntime) {
    terminalRuntime = runtime
    observeMouseState()
}

private var lastMouseVisible = true

private func observeMouseState() {
    guard let runtime = terminalRuntime else { return }
    withObservationTracking {
        _ = runtime.mouseShape
        _ = runtime.mouseVisible
    } onChange: { [weak self] in
        Task { @MainActor [weak self] in
            guard let self, let runtime = self.terminalRuntime else { return }
            self.updateCursor(shape: runtime.mouseShape)
            self.updateCursorVisibility(visible: runtime.mouseVisible)
            self.observeMouseState()
        }
    }
}

private func updateCursor(shape: GhosttyMouseShape) {
    shape.nsCursor.set()
}

private func updateCursorVisibility(visible: Bool) {
    if visible && !lastMouseVisible {
        NSCursor.unhide()
    } else if !visible && lastMouseVisible {
        NSCursor.hide()
    }
    lastMouseVisible = visible
}
```

- [ ] **Step 6: Build and run full test suite**

Run:

```bash
AGENT_RUN_ID="$(uuidgen | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9' | head -c 12)" mise run test
```

Expected: All tests pass.

- [ ] **Step 7: Commit composition and wiring**

```bash
git add \
  Sources/AgentStudio/Features/Terminal/Hosting/TerminalPaneMountView.swift \
  Sources/AgentStudio/Features/Terminal/Ghostty/GhosttySurfaceView.swift \
  Sources/AgentStudio/App/Coordination/PaneCoordinator+ViewLifecycle.swift
git commit -m "$(cat <<'EOF'
feat: compose scroll wrapper, search overlay, and indicator in mount view

Wire TerminalRuntime observation to scroll view, search overlay, and
scroll-to-bottom indicator. Add mouse cursor management to surface view.
Coordinator binds runtime to mount view after registration.
EOF
)"
```

---

### Task 7: Full Verification and Docs

**Files:**
- Modify: `docs/architecture/ghostty_surface_architecture.md`

- [ ] **Step 1: Run format**

Run:

```bash
mise run format
```

Expected: exit 0

- [ ] **Step 2: Run lint**

Run:

```bash
mise run lint
```

Expected: exit 0, zero violations

- [ ] **Step 3: Run full test suite**

Run:

```bash
AGENT_RUN_ID="$(uuidgen | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9' | head -c 12)" mise run test
```

Expected: All pass. Record pass/fail counts.

- [ ] **Step 4: Update architecture doc**

In `docs/architecture/ghostty_surface_architecture.md`, add a section:

```markdown
## Scrollback UX Boundary

Native scrollbars and scrollback search are a host-side composition boundary.

- Ghostty core owns scrollback state, search state, and cursor shape.
- `GhosttyActionRouter` routes scrollbar, search, and mouse actions into `TerminalRuntime`.
- `TerminalPaneMountView` composes `TerminalSurfaceScrollView`, `TerminalSearchOverlayView`, and `ScrollToBottomIndicatorView`.
- `TerminalSurfaceScrollView` renders native AppKit scrollbars and sends `scroll_to_row:N` back into Ghostty.
- `TerminalSearchOverlayView` renders the macOS search UI and sends `start_search`, `search:<query>`, `navigate_search:*`, and `end_search` back into Ghostty.
- `ScrollToBottomIndicatorView` shows when scrolled up. Click sends `scroll_to_bottom`.
- Mouse cursor shape and visibility are `@Observable` on `TerminalRuntime`, consumed by `GhosttySurfaceView`.
- All new views are pure AppKit — no SwiftUI, no Combine.
```

- [ ] **Step 5: Commit docs**

```bash
git add docs/architecture/ghostty_surface_architecture.md
git commit -m "$(cat <<'EOF'
docs: record terminal scrollback host integration boundary
EOF
)"
```
