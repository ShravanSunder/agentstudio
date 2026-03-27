# Ghostty Event Routing Expansion Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Wire all domain-significant Ghostty actions through `GhosttyAdapter` → `TerminalRuntime` → `@Observable` + `EventBus`, replacing the current silent-drop behavior for ~50 unhandled action tags. High-frequency visual events and feature-gated events are intentionally deferred (YAGNI). Every routed event follows the existing multiplexing rule: `@Observable` mutation first (sync), bus post only when other components care.

**Architecture:** All Ghostty events route through `TerminalRuntime.handleGhosttyEvent()` — one path, no exceptions. The runtime applies the multiplexing rule per event. Surface-local visual events (`mouseShape`, `mouseVisibility`, `render`) are explicitly deferred, not silently dropped. This plan does NOT add UI features — it wires the plumbing so events reach the runtime with typed payloads. UI features (search bar, scrollbar, progress indicator) are separate work that consumes the state this plan provides.

**Tech Stack:** Swift 6.2, AppKit, Ghostty/libghostty, Swift Testing, mise, swift-format, swiftlint

---

## Preconditions

This plan starts after both the universal `PaneHostView` / `TerminalPaneMountView` / `GhosttyMountView` cutover and the Ghostty runtime isolation split have landed. The `GhosttyActionRouter` from the isolation split is the entry point for all action routing changes in this plan.

If the isolation split has not landed, this plan can still proceed against the current `Ghostty.App.handleAction` switch — but the file targets change accordingly.

## Relationship To Existing Architecture

This plan operates entirely within the C7 contract (Ghostty FFI boundary) and the multiplexing rule from the EventBus design doc:

```
C callback → @Sendable trampoline → MainActor
  → GhosttyAdapter.translate(actionTag, payload) → GhosttyEvent
  → TerminalRuntime.handleGhosttyEvent(event)
    → SYNC: @Observable mutation (if event has observable state)
    → ASYNC: eventChannel.emit() (if domain-significant — other components care)
```

Events that are `@Observable`-only (no bus post) use `persistForReplay: false` on the event channel.

### Replay Persistence Decision Tree

The `persistForReplay` flag determines whether a late-joining subscriber sees the event via catch-up replay. Apply these rules:

- `persistForReplay: true` when the event represents **mutable runtime state** that a late-joiner needs to reconstruct current state (`readOnly`, `secureInput`, `sizeConstraints`).
- `persistForReplay: false` when the event is a **one-shot action** where replay would cause side effects (duplicate notifications, re-opening URLs) or is meaningless after the fact (`openURL`, `undo`, `desktopNotification`, `promptTitle`).
- `persistForReplay: false` when the event is **@Observable-only** with no bus post — replay is irrelevant since no bus subscriber receives it (`progressReport`, `cellSize`, `rendererHealth`).

## Event Classification

### NEED NOW — Route through runtime

Domain-significant, low-frequency events that earn their routing cost. Each goes through the runtime and follows the multiplexing rule.

| Event | Payload | Runtime Property | Bus Post? | Replay? | Rationale |
|-------|---------|-----------------|-----------|---------|-----------|
| `progressReport` | `state: start/continue/end/error, progress: 0-100` | `commandProgress: ProgressState?` | No | No | @Observable only until a bus consumer exists. No near-term consumer — workflow engine (C13) is deferred. Promote to bus post when a consumer ships. |
| `readOnly` | `on/off` | `isReadOnly: Bool` | Yes | Yes | Pane chrome indicator; coordinator may gate input commands |
| `secureInput` | `on/off/toggle` | `isSecureInput: Bool` | Yes | Yes | Password mode indicator; security-relevant signal |
| `rendererHealth` | `healthy/unhealthy` | `rendererHealthy: Bool` on runtime; runtime calls `SurfaceManager.shared.updateHealth(surfaceId, healthy:)` directly | No | No | @Observable for UI binding. SurfaceManager updated via direct call from runtime (not bus — SurfaceManager is not a bus subscriber). Existing `SurfaceHealthDelegate` pattern continues to work. |
| `cellSize` | `width, height` (backing pixels) | `cellSize: NSSize` | No | No | Terminal metrics for future scrollbar/size calculations. @Observable only — view concern. |
| `initialSize` | `width, height` | No persistent property — applied at creation | No | No | Size hint during surface creation. Already partially handled on surface. |
| `sizeLimit` | `min/max width/height` | `sizeConstraints: TerminalSizeConstraints?` | No | No | Terminal size constraints. @Observable only — used by layout. |
| `promptTitle` | `surface/tab` | No persistent property — triggers UI flow | Yes | No | OSC title prompt. Triggers a title-edit interaction on the pane. |
| `desktopNotification` | `title: String, body: String` | No persistent property — fire and handle | Yes | No | Route to `UNUserNotificationCenter`. Domain-significant — other components may suppress/badge. |
| `openURL` | `url: String, kind: text/html` | No persistent property — fire and handle | No | No | `NSWorkspace.shared.open()`. Direct action, no coordination needed. |
| `undo` / `redo` | none | No property — forward to responder chain | No | No | Route to `NSUndoManager` via responder chain. |
| `copyTitleToClipboard` | none | No property — fire and handle | No | No | `NSPasteboard.general.setString(runtime.title)`. Trivial. |

### YAGNI — Intentionally deferred

These events are not silently dropped — they are explicitly documented as deferred. The `GhosttyAdapter` translates them to `GhosttyEvent.deferred(tag:)` (or similar) so the runtime can log them at debug level without warning noise. When the feature that needs them ships, the implementer adds a proper payload variant and handler.

| Event | Frequency | Why deferred | Feature that would need it |
|-------|-----------|-------------|---------------------------|
| `scrollbar` | 60fps | No native scrollbar UI. Infrastructure types already exist (`ScrollbarState`). | Native `NSScroller` overlay feature |
| `mouseShape` | Medium | No NSCursor integration. Ghostty cursor works without host intervention. | Custom cursor shape feature |
| `mouseVisibility` | Low | Cursor hide/show. May be handled by Ghostty internally. | Cursor-hide-during-typing feature |
| `mouseOverLink` | Medium | No link preview hover UI exists. | Link preview tooltip feature |
| `render` | 60fps | Ghostty handles rendering via Metal internally. Host never acts on this. | Likely never needed |
| `startSearch` / `endSearch` / `searchTotal` / `searchSelected` | Medium | No search UI. Four events forming a state machine — useless without the UI. | Terminal search bar feature |
| `keySequence` / `keyTable` | Low | No key chord indicator HUD. | Key chord display feature |
| `colorChange` | Rare | No theme-reactive pane chrome. | Terminal-color-aware chrome feature |
| `reloadConfig` / `configChange` | Rare | No live Ghostty config hot-reload support. | Ghostty config hot-reload feature |
### SKIP PERMANENTLY — Intercepted, correct behavior

App-level actions AgentStudio owns, redundant signals already handled by other callbacks, or GTK/Linux-specific actions irrelevant on macOS. Current intercept-and-swallow behavior is correct and documented.

`quit`, `newWindow`, `closeAllWindows`, `toggleMaximize`, `toggleFullscreen`, `toggleTabOverview`, `toggleWindowDecorations`, `toggleQuickTerminal`, `toggleCommandPalette`, `toggleVisibility`, `toggleBackgroundOpacity`, `gotoWindow`, `presentTerminal`, `resetWindowSize`, `floatWindow`, `inspector`, `showGtkInspector`, `renderInspector`, `checkForUpdates`, `showOnScreenKeyboard`, `quitTimer`, `showChildExited`

Notes:
- `quitTimer` — AgentStudio owns quit lifecycle. Intercepted permanently.
- `showChildExited` — Redundant. The `closeSurface` callback already delivers process termination with the same exit code. Routing this separately would cause double-notification.

## Hard-Cutover Rules

1. No silent drops. Every Ghostty action tag either routes to a handler, is explicitly deferred with debug logging, or is intercepted and documented.
2. No wall-clock tests (`Task.sleep`) in test bodies.
3. All new `GhosttyEvent` variants must have a multiplexing decision documented: `@Observable` + bus, `@Observable` only, or fire-and-handle.
4. The `shouldForwardUnhandledActionToRuntime` suppression list is replaced by explicit per-action routing. No catch-all "forward unhandled" path survives.
5. `ActionPayload` carries typed data for every routed action. No `.noPayload` for actions that have meaningful C payloads.
6. **Preserve `action_cb` Bool return semantics exactly.** `true` = "I handled it, Ghostty skip your default." `false` = "I didn't handle it, Ghostty apply your default." The current code deliberately returns `false` for unhandled tags to preserve Ghostty's built-in behavior (e.g., color handling, renderer health defaults). When adding new handlers, the return value must be intentional: return `true` only if AgentStudio fully replaces the default behavior for that action. YAGNI/deferred events should return `false` to keep Ghostty defaults alive.

## New Types

```swift
// New runtime @Observable properties
struct ProgressState: Sendable, Equatable {
    enum Phase: Sendable, Equatable {
        case started
        case running(percent: Int)  // 0-100
        case completed
        case errored
    }
    let phase: Phase
}

struct TerminalSizeConstraints: Sendable, Equatable {
    let minWidth: UInt32?
    let minHeight: UInt32?
    let maxWidth: UInt32?
    let maxHeight: UInt32?
}
```

## File Structure Map

### Existing files to modify

- Modify: `Sources/AgentStudio/Features/Terminal/Ghostty/GhosttyAdapter.swift` — expand `ActionPayload` enum
- Modify: `Sources/AgentStudio/Features/Terminal/Ghostty/Ghostty.swift` (or `GhosttyActionRouter.swift` post-isolation-split) — route new actions with typed payloads
- Modify: `Sources/AgentStudio/Features/Terminal/Ghostty/GhosttyActionTag.swift` — verify all tags have cases
- Modify: `Sources/AgentStudio/Features/Terminal/Runtime/TerminalRuntime.swift` — handle new events, add properties
- Modify: `Sources/AgentStudio/Core/PaneRuntime/Contracts/PaneKindEvent.swift` — add new GhosttyEvent cases
- Modify: `Sources/AgentStudio/Core/PaneRuntime/Contracts/PaneRuntimeEvent.swift` — add new terminal event cases
- Modify: `Sources/AgentStudio/Core/PaneRuntime/Replay/EventReplayBuffer.swift` — replay decisions for new events
- Modify: `Sources/AgentStudio/App/PaneCoordinator.swift` — handle new bus events (promptTitle, desktopNotification)

### Test files

- Modify: `Tests/AgentStudioTests/Features/Terminal/Ghostty/GhosttyAdapterTests.swift` — translation tests for new payloads
- Modify: `Tests/AgentStudioTests/Features/Terminal/Runtime/TerminalRuntimeTests.swift` — handling + multiplexing tests
- Create: `Tests/AgentStudioTests/Features/Terminal/Ghostty/GhosttyEventRoutingCoverageTests.swift` — exhaustive coverage test

---

### Task 1: Expand Payload Types And Translation Layer

**Files:**
- Modify: `Sources/AgentStudio/Features/Terminal/Ghostty/GhosttyAdapter.swift`
- Modify: `Sources/AgentStudio/Features/Terminal/Ghostty/GhosttyActionTag.swift`
- Modify: `Sources/AgentStudio/Core/PaneRuntime/Contracts/PaneKindEvent.swift`
- Test: `Tests/AgentStudioTests/Features/Terminal/Ghostty/GhosttyAdapterTests.swift`

- [ ] **Step 1: Write failing translation tests for new payload variants**

```swift
@Test
@MainActor
func adapter_translatesProgressReportWithTypedPayload() {
    let event = GhosttyAdapter.shared.translate(
        actionTag: GhosttyActionTag.progressReport.rawTag,
        payload: .progressReport(state: .running, progress: 42)
    )
    #expect(event == .progressReport(phase: .running(percent: 42)))
}

@Test
@MainActor
func adapter_translatesReadOnlyWithTypedPayload() {
    let event = GhosttyAdapter.shared.translate(
        actionTag: GhosttyActionTag.readOnly.rawTag,
        payload: .readOnly(isOn: true)
    )
    #expect(event == .readOnlyChanged(true))
}

@Test
@MainActor
func adapter_translatesDesktopNotificationWithTitleAndBody() {
    let event = GhosttyAdapter.shared.translate(
        actionTag: GhosttyActionTag.desktopNotification.rawTag,
        payload: .desktopNotification(title: "Build", body: "Complete")
    )
    #expect(event == .desktopNotification(title: "Build", body: "Complete"))
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `SWIFT_BUILD_DIR=".build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8)" swift test --build-path "$SWIFT_BUILD_DIR" --filter "GhosttyAdapterTests"`
Expected: FAIL with missing payload/event variants.

- [ ] **Step 3: Add new `ActionPayload` variants**

Required new variants:
- `.progressReport(state: UInt32, progress: Int8)`
- `.readOnly(isOn: Bool)`
- `.secureInput(mode: UInt32)`
- `.rendererHealth(healthy: Bool)`
- `.cellSizeChanged(width: UInt32, height: UInt32)`
- `.initialSizeChanged(width: UInt32, height: UInt32)`
- `.sizeLimitChanged(minWidth: UInt32, minHeight: UInt32, maxWidth: UInt32, maxHeight: UInt32)`
- `.promptTitle(scope: UInt32)`
- `.desktopNotification(title: String, body: String)`
- `.openURL(url: String, kind: UInt32)`

- [ ] **Step 4: Add new `GhosttyEvent` cases and translation logic**

Required new cases on `GhosttyEvent`:
- `.progressReport(phase: ProgressState.Phase)`
- `.readOnlyChanged(Bool)`
- `.secureInputChanged(Bool)`
- `.rendererHealthChanged(healthy: Bool)`
- `.cellSizeChanged(NSSize)`
- `.initialSizeChanged(NSSize)`
- `.sizeLimitChanged(TerminalSizeConstraints)`
- `.promptTitleRequested(scope: TitlePromptScope)`
- `.desktopNotification(title: String, body: String)`
- `.openURLRequested(url: String, kind: OpenURLKind)`
- `.undoRequested`
- `.redoRequested`
- `.copyTitleToClipboardRequested`
- `.deferred(tag: UInt32)` — explicit bucket for YAGNI events

- [ ] **Step 5: Run focused tests**

Run: `SWIFT_BUILD_DIR=".build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8)" swift test --build-path "$SWIFT_BUILD_DIR" --filter "GhosttyAdapterTests"`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add Sources/AgentStudio/Features/Terminal/Ghostty/GhosttyAdapter.swift \
  Sources/AgentStudio/Features/Terminal/Ghostty/GhosttyActionTag.swift \
  Sources/AgentStudio/Core/PaneRuntime/Contracts/PaneKindEvent.swift \
  Tests/AgentStudioTests/Features/Terminal/Ghostty/GhosttyAdapterTests.swift
git commit -m "feat: expand ghostty adapter with typed payloads for domain-significant events"
```

---

### Task 2: Wire Action Router To Deliver Typed Payloads

**Files:**
- Modify: `Sources/AgentStudio/Features/Terminal/Ghostty/Ghostty.swift` (or `GhosttyActionRouter.swift` post-isolation-split)
- Test: `Tests/AgentStudioTests/Features/Terminal/Ghostty/GhosttyEventRoutingCoverageTests.swift`

- [ ] **Step 1: Write exhaustive coverage test**

```swift
@Test
@MainActor
func everyGhosttyActionTag_hasExplicitRoutingDecision() {
    let allTags = GhosttyActionTag.allCases
    let routedTags = GhosttyActionRouter.explicitlyRoutedTags
    let interceptedTags = GhosttyActionRouter.interceptedTags
    let deferredTags = GhosttyActionRouter.deferredTags

    let accounted = Set(routedTags).union(interceptedTags).union(deferredTags)
    let unaccounted = allTags.filter { !accounted.contains($0) }

    #expect(unaccounted.isEmpty, "Unaccounted action tags: \(unaccounted)")
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `SWIFT_BUILD_DIR=".build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8)" swift test --build-path "$SWIFT_BUILD_DIR" --filter "GhosttyEventRoutingCoverageTests"`
Expected: FAIL — many tags unaccounted.

- [ ] **Step 3: Replace catch-all unhandled routing with explicit per-action decisions**

Required behavior:
- Every action tag in the `handleAction` switch has an explicit case
- "NEED NOW" actions extract typed payloads from the C action union and call `routeActionToTerminalRuntime` with the new `ActionPayload` variants
- "YAGNI" actions route with `.deferred(tag:)` — reaches the runtime, logged at debug level, no warning noise
- "SKIP PERMANENTLY" actions are intercepted and return `true`
- `shouldForwardUnhandledActionToRuntime` is deleted — no catch-all path remains
- `routeUnhandledAction` is deleted or reduced to a single-line unknown-tag logger

- [ ] **Step 4: Run focused tests**

Run: `SWIFT_BUILD_DIR=".build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8)" swift test --build-path "$SWIFT_BUILD_DIR" --filter "GhosttyEventRoutingCoverageTests|GhosttyAdapterTests"`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/AgentStudio/Features/Terminal/Ghostty/Ghostty.swift \
  Tests/AgentStudioTests/Features/Terminal/Ghostty/GhosttyEventRoutingCoverageTests.swift
git commit -m "feat: explicit routing decision for every ghostty action tag"
```

---

### Task 3: Handle New Events In Terminal Runtime

**Files:**
- Modify: `Sources/AgentStudio/Features/Terminal/Runtime/TerminalRuntime.swift`
- Modify: `Sources/AgentStudio/Core/PaneRuntime/Contracts/PaneRuntimeEvent.swift`
- Modify: `Sources/AgentStudio/Core/PaneRuntime/Replay/EventReplayBuffer.swift`
- Test: `Tests/AgentStudioTests/Features/Terminal/Runtime/TerminalRuntimeTests.swift`

- [ ] **Step 1: Write failing runtime handling tests**

```swift
@Test
@MainActor
func runtime_progressReport_updatesObservableWithoutBusPost() {
    let harness = makeTerminalRuntimeTestHarness()
    harness.runtime.handleGhosttyEvent(.progressReport(phase: .running(percent: 50)))

    #expect(harness.runtime.commandProgress?.phase == .running(percent: 50))
    #expect(harness.lastBusEnvelope == nil)  // @Observable only — no bus consumer yet
}

@Test
@MainActor
func runtime_cellSize_updatesObservableButDoesNotPostToBus() {
    let harness = makeTerminalRuntimeTestHarness()
    harness.runtime.handleGhosttyEvent(.cellSizeChanged(NSSize(width: 8, height: 16)))

    #expect(harness.runtime.cellSize == NSSize(width: 8, height: 16))
    #expect(harness.lastBusEnvelope == nil)
}

@Test
@MainActor
func runtime_openURL_firesWithoutPersistentState() {
    let harness = makeTerminalRuntimeTestHarness()
    harness.runtime.handleGhosttyEvent(.openURLRequested(url: "https://example.com", kind: .text))

    // No runtime property changed — fire-and-handle
    #expect(harness.openedURLs == ["https://example.com"])
}

@Test
@MainActor
func runtime_deferredEvent_logsAtDebugWithoutWarning() {
    let harness = makeTerminalRuntimeTestHarness()
    harness.runtime.handleGhosttyEvent(.deferred(tag: 999))

    #expect(harness.warningCount == 0)
    #expect(harness.debugLogCount >= 1)
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `SWIFT_BUILD_DIR=".build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8)" swift test --build-path "$SWIFT_BUILD_DIR" --filter "TerminalRuntimeTests"`
Expected: FAIL with missing properties/handlers.

- [ ] **Step 3: Add new `@Observable` properties to `TerminalRuntime`**

New properties:
- `private(set) var commandProgress: ProgressState?`
- `private(set) var isReadOnly: Bool = false`
- `private(set) var isSecureInput: Bool = false`
- `private(set) var cellSize: NSSize = .zero`
- `private(set) var sizeConstraints: TerminalSizeConstraints?`

- [ ] **Step 4: Implement `handleGhosttyEvent` cases with multiplexing decisions**

For each new event, apply the documented multiplexing rule:

| Event | @Observable mutation | Bus post | persistForReplay |
|-------|---------------------|----------|-----------------|
| `progressReport` | `commandProgress = ...` | No | No |
| `readOnlyChanged` | `isReadOnly = ...` | Yes | Yes |
| `secureInputChanged` | `isSecureInput = ...` | Yes | Yes |
| `rendererHealthChanged` | `rendererHealthy = ...` + direct `SurfaceManager.updateHealth()` call | No | No |
| `cellSizeChanged` | `cellSize = ...` | No | No |
| `initialSizeChanged` | No property — applied at creation | No | No |
| `sizeLimitChanged` | `sizeConstraints = ...` | No | No |
| `promptTitleRequested` | No property — delegate to coordinator | Yes | No |
| `desktopNotification` | No property — delegate to notification handler | Yes | No |
| `openURLRequested` | No property — `NSWorkspace.shared.open()` | No | No |
| `undoRequested` | No property — forward to responder chain | No | No |
| `redoRequested` | No property — forward to responder chain | No | No |
| `copyTitleToClipboardRequested` | No property — `NSPasteboard.general.setString()` | No | No |
| `deferred(tag:)` | No property — debug log | No | No |

- [ ] **Step 5: Run focused tests**

Run: `SWIFT_BUILD_DIR=".build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8)" swift test --build-path "$SWIFT_BUILD_DIR" --filter "TerminalRuntimeTests|GhosttyAdapterTests"`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add Sources/AgentStudio/Features/Terminal/Runtime/TerminalRuntime.swift \
  Sources/AgentStudio/Core/PaneRuntime/Contracts/PaneRuntimeEvent.swift \
  Sources/AgentStudio/Core/PaneRuntime/Replay/EventReplayBuffer.swift \
  Tests/AgentStudioTests/Features/Terminal/Runtime/TerminalRuntimeTests.swift
git commit -m "feat: terminal runtime handles domain-significant ghostty events with multiplexing"
```

---

### Task 4: Wire Bus Consumers For New Events

**Files:**
- Modify: `Sources/AgentStudio/App/PaneCoordinator.swift`
- Modify: existing bus consumer code (NotificationReducer, etc.)

- [ ] **Step 1: Wire coordinator handling for promptTitle**

Required behavior:

`promptTitleRequested(scope:)` arrives on the bus with the originating `paneId`. The coordinator resolves the pane's current title from the runtime and presents an inline title-edit interaction. The scope discriminant (`.surface` vs `.tab`) determines whether the edit targets the pane's terminal title or the containing tab's display title.

```swift
// Concrete handler shape:
case .terminal(.promptTitleRequested(let scope)):
    guard let runtime = runtimeForPane(envelope.paneId) as? TerminalRuntime else { break }
    let currentTitle = runtime.metadata.title
    // Present title-edit sheet/popover anchored to the pane's host view.
    // On confirm: store.updatePaneTitle(envelope.paneId.uuid, title: newTitle)
    // On cancel: no-op.
```

This is a coordinator-owned interaction because it crosses the runtime → store boundary (updating `PaneMetadata.title` in `WorkspaceStore`).

- [ ] **Step 2: Wire coordinator handling for desktopNotification**

Required behavior:

`desktopNotification(title:body:)` arrives on the bus. The coordinator (or `NotificationReducer`) creates a `UNNotificationRequest` with the pane's context (pane title, tab index) so the notification identifies its source. Tapping the notification should focus the originating pane.

```swift
// Concrete handler shape:
case .terminal(.desktopNotification(let title, let body)):
    let paneTitle = store.pane(envelope.paneId.uuid)?.metadata.title ?? "Terminal"
    let content = UNMutableNotificationContent()
    content.title = title
    content.body = body
    content.userInfo = ["paneId": envelope.paneId.uuid.uuidString]
    let request = UNNotificationRequest(
        identifier: UUID().uuidString,
        content: content,
        trigger: nil  // deliver immediately
    )
    try? await UNUserNotificationCenter.current().add(request)
```

The notification handler (AppDelegate or dedicated handler) should resolve `paneId` from `userInfo` and dispatch `PaneActionCommand.focusPane` when the user taps the notification.

- [ ] **Step 3: Verify existing bus consumers handle new event cases**

Required behavior:
- `EventReplayBuffer` replay decisions match the table in Task 3
- `PaneCoordinator` bus subscription handles new terminal events without warning
- `NotificationReducer` classifies new events appropriately:
  - `readOnlyChanged` → `.critical` (state change, don't coalesce)
  - `secureInputChanged` → `.critical`
  - `promptTitleRequested` → `.critical` (one-shot request)
  - `desktopNotification` → `.critical` (one-shot, don't drop)
- All new `PaneRuntimeEvent.terminal(...)` cases have exhaustive switch handling in every consumer

- [ ] **Step 3: Run focused tests**

Run: `SWIFT_BUILD_DIR=".build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8)" swift test --build-path "$SWIFT_BUILD_DIR" --filter "PaneCoordinatorTests|TerminalRuntimeTests"`
Expected: PASS

- [ ] **Step 4: Commit**

```bash
git add Sources/AgentStudio/App/PaneCoordinator.swift \
  Sources/AgentStudio/Core/PaneRuntime/Replay/EventReplayBuffer.swift
git commit -m "feat: bus consumers handle new ghostty terminal events"
```

---

### Task 5: Full Verification

**Files:**
- All modified files from Tasks 1-4

- [ ] **Step 1: Run targeted suites**

Run:

```bash
SWIFT_BUILD_DIR=".build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8)" swift test --build-path "$SWIFT_BUILD_DIR" --filter "GhosttyAdapterTests|GhosttyEventRoutingCoverageTests|TerminalRuntimeTests|PaneCoordinatorTests"
```

Expected: PASS

- [ ] **Step 2: Run full test suite and lint**

Run:

```bash
AGENT_RUN_ID=ghostty-event-routing mise run test
AGENT_RUN_ID=ghostty-event-routing mise run lint
```

Expected: PASS, zero failures, zero lint errors.

- [ ] **Step 3: Verify no silent drops remain**

Run:

```bash
rg -n "routeUnhandledAction|shouldForwardUnhandledActionToRuntime" Sources/
```

Expected: zero matches — these catch-all paths are replaced by explicit per-action routing.

- [ ] **Step 4: Verify no wall-clock tests were introduced**

Run:

```bash
rg -n "Task\\.sleep|sleep\\(" Tests/AgentStudioTests
```

Expected: zero matches in tests added or modified by this plan.

---

## Notes For The Implementer

- This plan is plumbing only. It wires events to the runtime with typed payloads and applies the multiplexing rule. It does NOT build UI features (progress bars, search UI, scrollbar).
- Every event follows one path: `C callback → GhosttyAdapter → TerminalRuntime → @Observable + optional bus post`. No exceptions, no shortcuts.
- YAGNI events route as `.deferred(tag:)` — they reach the runtime, get debug-logged, and are explicitly documented as deferred. This is better than silent drops because it's auditable.
- The exhaustive coverage test in Task 2 is the regression gate. If Ghostty adds a new action tag, the test fails until someone makes an explicit routing decision.
- `openURL`, `undo/redo`, `copyTitleToClipboard` are fire-and-handle: no persistent runtime state, no bus post. The runtime delegates to the appropriate system service.
- `desktopNotification` and `promptTitle` go through the bus because the coordinator (or notification reducer) needs to handle them — they're not purely terminal-local.
- `progressReport` is `@Observable`-only for now — no near-term bus consumer. Promote to bus post when the workflow engine (C13) or a progress UI feature ships.
- `rendererHealth` updates the runtime `@Observable` property AND calls `SurfaceManager` directly — SurfaceManager is not a bus subscriber and doesn't need to be.
- The `persistForReplay` decision tree is documented in the Relationship To Existing Architecture section. Apply it to any new events added in the future: mutable state → persist, one-shot actions → don't persist, @Observable-only → don't persist.
