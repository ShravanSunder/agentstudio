# Terminal Scrollback UX Design Spec

## Problem

Agent Studio's embedded Ghostty terminal has no native scrollbar, no scrollback search, and no visual indicator when the viewport is scrolled away from the bottom. Users working with AI agents frequently need to scroll up to read long command output (build logs, plans, test results) while simultaneously typing follow-up commands. The terminal should support this workflow without fighting the user.

## Scope

### In Scope

| Feature | Detail |
|---------|--------|
| Native scrollbar | Always visible, overlay style. **Deliberate fork from Ghostty** which respects `scrollbar = system\|never` config. Agent Studio hard-codes always-visible as a product choice — no user toggle. Ghostty's own scrollbar is disabled via config override (`scrollbar = never`) to avoid double scrollbars. |
| Follow-bottom | Only auto-follow new output when viewport is already pinned to bottom |
| No keystroke scroll-to-bottom | Typing while scrolled up does NOT yank viewport down. Requires Ghostty config override: `scroll-to-bottom = no-keystroke, no-output`. Without this, Ghostty core auto-scrolls on keypress regardless of host-side wrapper logic. |
| Scroll-to-bottom button | Bottom-right floating button when scrolled up; icon changes when new unread output exists below viewport; follows management mode visual style |
| Scrollback search | `cmd+f` opens top-center overlay in focused pane; `cmd+g` / `shift+cmd+g` navigate matches; Escape clears highlights and closes |
| Find menu | macOS Edit > Find menu entries wired to responder chain |
| Mouse cursor shape | Un-defer `mouseShape` action, set `NSCursor` for links/prompts/default |
| Mouse visibility | Un-defer `mouseVisibility` action, hide cursor while typing |
| Click-to-move-cursor | Already works via Ghostty core — add verification test only |

### Coordination with Deferred Contracts Branch

The `agent-studio.deffered-contracts` worktree is implementing `docs/superpowers/plans/2026-04-06-deferred-pane-runtime-contracts.md` (C15 + C16) in parallel. That plan promotes ALL remaining deferred Ghostty tags to typed events on the bus.

**Overlap:** Both branches promote these 7 tags from `deferredTags` → `explicitlyRoutedTags`: `scrollbar`, `startSearch`, `endSearch`, `searchTotal`, `searchSelected`, `mouseShape`, `mouseVisibility`. Both branches add new `GhosttyEvent` cases and update `ScrollbarState`.

**Merge order:** This branch (`native-scrollbars`) should merge first. The deferred-contracts plan explicitly accounts for 5 of the 7 tags: *"If the scrollbar branch merges first, those 5 tags are done. Skip those and do the remaining 9."* The deferred-contracts plan must ALSO skip `mouseShape` and `mouseVisibility` (total 7 tags to skip, not 5). Flag this to the other agent before they start Task 2.

**`ScrollbarState` shape change:** This branch changes `ScrollbarState` from `{top, bottom, total}` to `{totalRows, firstVisibleRow, visibleRowCount}`. The deferred-contracts branch must adopt the new field names after rebase.

**Exhaustive switch conflicts:** Both branches add cases to `GhosttyEvent`, `GhosttyEvent.actionPolicy`, `GhosttyEvent.eventName`, and `TerminalRuntime.handleGhosttyEvent()`. These will produce merge conflicts on the exhaustive switches that need manual resolution during rebase.

### Out of Scope

- Cross-pane search (`cmd+shift+f`) — future work
- macOS system Find pasteboard integration — add later if requested
- Click-to-move-cursor host-side implementation (already works in Ghostty core)
- Command finished notification UI (event plumbing already landed)
- Scrollbar visibility configuration (always visible, no user toggle)
- Search bar dragging/repositioning

## Architecture

### View Hierarchy

```
TerminalPaneMountView (composition root, responder chain participant)
├── TerminalSurfaceScrollView (NSScrollView wrapper — always visible overlay scrollbar)
│   └── documentView (NSView — height represents total scrollback in pixels)
│       └── GhosttyMountView (thin container)
│           └── Ghostty.SurfaceView (Metal rendering, fills visible rect)
├── TerminalSearchOverlayView (top-center floating, pure AppKit)
├── ScrollToBottomIndicatorView (bottom-right floating, pure AppKit)
├── SurfaceErrorOverlayView (existing)
└── SurfaceStartupOverlayView (existing)
```

### Why Pure AppKit (No SwiftUI Overlays)

Research confirmed that `NSHostingView` does NOT participate in AppKit's responder chain for Find menu actions (`startSearch:`, `findNext:`, `findPrevious:`, `cancelOperation:`). Since the search overlay needs these responder chain methods to integrate with the macOS Edit > Find menu, all new views are pure AppKit `NSView` subclasses.

The existing codebase pattern for overlays (`SurfaceErrorOverlayView`, `SurfaceStartupOverlayView`) wraps SwiftUI in `NSHostingView`, but those don't need responder chain participation. The search overlay does.

### Data Flow

```
Ghostty core (Zig) → C callback → GhosttyActionRouter
  → GhosttyAdapter.translate(actionTag, payload) → GhosttyEvent
  → TerminalRuntime.handleGhosttyEvent()
    → @Observable mutation (scrollbarState, searchState, mouseShape, mouseVisibility)
    → Views observe via withObservationTracking + recursive re-subscribe

User interaction → TerminalSurfaceActionPerforming.performBindingAction()
  → ghostty_surface_binding_action() → Ghostty core
```

This follows the established unidirectional flow pattern. Ghostty core is the source of truth for scrollback and search state. The host-side views are reactive readers that send commands back through binding actions.

### Runtime Injection

`TerminalPaneMountView` currently has no reference to `TerminalRuntime`. The coordinator (`PaneCoordinator+ViewLifecycle.swift`) creates runtimes and mount views separately. To connect them:

- `TerminalPaneMountView` gains a `bind(runtime: TerminalRuntime)` method
- `PaneCoordinator+ViewLifecycle` calls `bind(runtime:)` after both the mount view and runtime are registered
- The mount view stores a `weak` reference to the runtime and starts observation
- On unbind (pane close), observation tasks are cancelled

This follows the existing pattern where `PaneCoordinator` wires together components that don't know about each other at construction time.

### Ghostty Config Overrides

`GhosttyAppHandle.init` (line 15-33) calls `ghostty_config_load_default_files` then `ghostty_config_finalize`. Between these two calls, we inject Agent Studio's config overrides via `ghostty_config_load_file` with a bundled override file:

```
# Agent Studio overrides — loaded after user defaults, before finalize
scroll-to-bottom = no-keystroke, no-output
scrollbar = never
```

- `scroll-to-bottom = no-keystroke, no-output` — disables Ghostty core's auto-scroll on keypress and on new output. The host-side `TerminalSurfaceScrollView` handles follow-bottom via `isPinnedToBottom` state instead.
- `scrollbar = never` — disables Ghostty's built-in scrollbar since Agent Studio renders its own via `TerminalSurfaceScrollView`. Without this, two scrollbars would appear.

The override file is written to the app's temporary directory at startup and loaded via `ghostty_config_load_file`. It runs after `load_default_files` so it overrides user config values.

### Action Router Return Values

When un-deferring scrollbar/search/mouse actions, the `handledResult` passed to `routeActionToTerminalRuntime` must remain `false` for scrollbar and mouse events. This tells Ghostty "I routed it but you should still apply your defaults." Search events (`startSearch`, `endSearch`, `searchTotal`, `searchSelected`) should also return `false` since Ghostty core manages the search thread and match highlighting internally.

### Observation Pattern

All new NSView subclasses observe `TerminalRuntime`'s `@Observable` properties using the established `withObservationTracking` + recursive re-subscribe pattern (matching `ManagementModeDragShield`):

```swift
private func observeRuntime() {
    guard let runtime else { return }
    withObservationTracking {
        _ = runtime.scrollbarState  // track the property
    } onChange: { [weak self] in
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.applyScrollbarState()
            self.observeRuntime()  // re-subscribe
        }
    }
}
```

On macOS 26, NSView's `updateLayer()` gets automatic `@Observable` tracking. The recursive pattern works on both macOS 15+ and macOS 26.

## Component Design

### 1. TerminalSurfaceScrollView

**Job:** Wrap the Ghostty surface in an NSScrollView to provide a native macOS scrollbar and translate between AppKit scroll position and Ghostty row coordinates.

**Design stolen from Ghostty's `SurfaceScrollView`:** The same three-layer architecture — `NSScrollView` → `documentView` (height = total rows × cell height) → `surfaceView` (positioned at visible rect origin). The coordinate inversion (AppKit +Y-up vs terminal +Y-down) uses the same math.

**Key differences from upstream:**
- Always-visible scrollbar (upstream respects `scrollbar` config)
- No `NotificationCenter` — observes `TerminalRuntime.scrollbarState` via `@Observable`
- Sends `scroll_to_row:N` back through `TerminalSurfaceActionPerforming` protocol
- Appearance synced to terminal background color (light vs dark `NSAppearance`)

**Follow-bottom behavior:**
- Track `wasPinnedToBottom` before each scrollbar state update
- If previously pinned and new state arrives, programmatically scroll to match new offset (follow output)
- If NOT previously pinned, hold scroll position (user is reading history)
- During live scrolling (user dragging scrollbar), skip all programmatic scroll updates

**Coordinate math (from Ghostty):**
```
documentHeight = (totalRows × cellHeight) + padding
padding = contentHeight - (visibleRows × cellHeight)
offsetY = (totalRows - firstVisibleRow - visibleRows) × cellHeight  // AppKit +Y-up inversion
row = (documentHeight - visibleRect.originY - visibleRect.height) / cellHeight  // reverse for scroll_to_row
```

**Live scroll deduplication:** Track `lastSentRow` — only send `scroll_to_row:N` when the computed row changes. Avoids action spam during smooth scrolling.

### 2. TerminalSearchOverlayView

**Job:** Floating search bar — text field, match counter, next/previous buttons, close button.

**Position:** Top-center of the pane, floating over terminal content with padding. Fixed position, no drag.

**Visual treatment:** Pure AppKit. `NSSearchField` for the query input (standard macOS feel, accessible). Match counter label ("3 of 12"). Navigation buttons (chevron up/down SF Symbols). Close button (x).

**Callbacks (not direct Ghostty coupling):**
- `onQueryChanged: (String) -> Void` — debounced, triggers `search:<query>` binding action
- `onNavigate: (SearchNavigationDirection) -> Void` — triggers `navigate_search:next/previous`
- `onClose: () -> Void` — triggers `end_search`

**Debounce:** Match Ghostty's approach — 300ms debounce for queries < 3 characters, immediate for longer queries.

**Dismiss behavior:** Escape clears all highlights (via `end_search`), closes overlay, returns focus to terminal surface.

**State driven by runtime:** `TerminalRuntime.searchState` (new `@Observable` property) provides `isPresented`, `query`, `totalMatches`, `selectedMatchIndex`. The overlay reads these and updates its labels.

### 3. ScrollToBottomIndicatorView

**Job:** Floating button that appears when scrolled away from bottom. Click scrolls to bottom.

**Position:** Bottom-right of the pane with padding. In management mode, follows management mode visual style.

**Visibility:** Shown when `scrollbarState.isPinnedToBottom == false`. Hidden when at bottom.

**Two visual states:**
- **Default icon** (down arrow / chevron.down) — viewport is scrolled up, no new output below
- **New output icon** (different icon or dot badge) — there IS unread output below the current viewport

**"Has new output" tracking:** When the user scrolls up, record the `totalRows` at that moment. If subsequent scrollbar updates show `totalRows` has grown, the button shows the "new output" indicator. Reset when the user scrolls back to bottom.

**Action:** Click sends `scroll_to_bottom` binding action via `TerminalSurfaceActionPerforming`.

### 4. Mouse Cursor Management

**Un-defer `mouseShape` and `mouseVisibility`** from `GhosttyActionRouter.deferredTags` to `explicitlyRoutedTags`.

**New `@Observable` properties on `TerminalRuntime`:**
- `mouseShape: GhosttyMouseShape` — cursor shape enum (arrow, iBeam, pointer, crosshair, etc.)
- `mouseVisible: Bool` — whether cursor should be visible (hide while typing)

**Consumer:** `GhosttySurfaceView` observes these properties (via `withObservationTracking`) and calls `NSCursor` APIs. Uses `NSTrackingArea` with `.cursorUpdate` option on the surface view. Override `cursorUpdate(with:)` to set the appropriate `NSCursor` based on `runtime.mouseShape`.

**Mouse visibility:** When `mouseVisible` transitions to `false`, call `NSCursor.hide()`. When it transitions back to `true`, call `NSCursor.unhide()`. Balance hide/unhide calls carefully — unbalanced calls are a common AppKit bug.

### 5. Event Routing Changes

**Move from `deferredTags` to `explicitlyRoutedTags` in `GhosttyActionRouter`:**
- `scrollbar` — route with typed payload to runtime
- `startSearch` — route with query string to runtime
- `endSearch` — route to runtime
- `searchTotal` — route with match count to runtime
- `searchSelected` — route with selected index to runtime
- `mouseShape` — route with cursor enum to runtime
- `mouseVisibility` — route with bool to runtime

**New `GhosttyEvent` cases:**
- `searchStarted(query: String)`
- `searchEnded`
- `searchMatchesUpdated(totalMatches: Int)`
- `searchSelectionChanged(selectedMatchIndex: Int?)`
- `mouseShapeChanged(GhosttyMouseShape)`
- `mouseVisibilityChanged(Bool)`

**Updated `ScrollbarState`:**
Current struct has `top`, `bottom`, `total` — needs alignment with Ghostty's C struct which provides `total`, `offset`, `len`. Update to:
```swift
struct ScrollbarState: Sendable, Equatable {
    let totalRows: Int        // total rows in scrollback + active
    let firstVisibleRow: Int  // offset of first visible row (0 = top of history)
    let visibleRowCount: Int  // number of visible rows (viewport height)

    var isPinnedToBottom: Bool {
        firstVisibleRow + visibleRowCount >= totalRows
    }
}
```

**New `TerminalSearchState`:**
```swift
struct TerminalSearchState: Sendable, Equatable {
    let isPresented: Bool
    let query: String
    let totalMatches: Int?
    let selectedMatchIndex: Int?
}
```

**New runtime `@Observable` properties:**
- `scrollbarState: ScrollbarState?`
- `searchState: TerminalSearchState?`
- `mouseShape: GhosttyMouseShape` (default: `.arrow`)
- `mouseVisible: Bool` (default: `true`)

### 6. TerminalSurfaceActionPerforming Protocol

Small protocol for sending Ghostty binding actions from host-side views back to the surface:

```swift
@MainActor
protocol TerminalSurfaceActionPerforming: AnyObject {
    @discardableResult
    func performBindingAction(_ action: String) -> Bool
}
```

`Ghostty.SurfaceView` conforms by calling `ghostty_surface_binding_action()`. Test doubles implement it by recording actions.

### 7. Find Menu Integration

Add Find submenu under Edit in the main menu bar:
- "Find..." (`cmd+f`) → `startSearch:` responder action
- "Find Next" (`cmd+g`) → `findNext:` responder action  
- "Find Previous" (`shift+cmd+g`) → `findPrevious:` responder action

`TerminalPaneMountView` implements these `@objc` responder methods. They delegate to `TerminalSurfaceActionPerforming`:
- `startSearch:` → show search overlay + `performBindingAction("start_search")`
- `findNext:` → `performBindingAction("navigate_search:next")`
- `findPrevious:` → `performBindingAction("navigate_search:previous")`
- `cancelOperation:` (Escape) → `performBindingAction("end_search")` + hide overlay + refocus surface

### 8. Hit Testing Updates

`TerminalPaneMountView.hitTest(_:)` needs updating to route clicks to the new overlay views:
1. Search overlay (if visible and hit) → search overlay
2. Scroll-to-bottom button (if visible and hit) → button
3. Error overlay (existing) → error overlay
4. Otherwise → Ghostty surface

## Invariants

1. **Ghostty core is source of truth** for scrollback position, search matches, and cursor shape. Host views are reactive readers.
2. **No programmatic scroll during live drag** — when `isLiveScrolling == true`, skip all `scrollView.contentView.scroll(to:)` calls.
3. **Follow-bottom is state-based, not event-based** — determined by `isPinnedToBottom` on the previous scrollbar state, not by a separate flag.
4. **One `scroll_to_row` per row change** — deduplicate via `lastSentRow` to avoid action spam.
5. **Search overlay lifecycle follows runtime state** — shown when `searchState.isPresented`, hidden when `searchState == nil`. No overlay-local presentation state.
6. **NSCursor hide/unhide must be balanced** — track visibility state transitions, not absolute values.
7. **All new views are pure AppKit** — no NSHostingView, no SwiftUI, no Combine for new code.

## Testing Strategy

**Unit tests (testable without Ghostty surface):**
- `TerminalSurfaceScrollView` coordinate math: row↔pixel translation, follow-bottom logic, live scroll dedup
- `TerminalSearchOverlayView` callbacks: query change, navigation, close
- `ScrollToBottomIndicatorView` visibility: shown/hidden based on pinned state, new-output indicator
- `TerminalRuntime` search state machine: started→matches→selection→ended transitions
- `GhosttyAdapter` translation: scrollbar/search/mouse payloads map to correct events
- `GhosttyActionRouter` tag classification: scrollbar/search/mouse tags in explicitlyRoutedTags

**Integration tests:**
- Mount view search responder chain: `startSearch:` → `findNext:` → `findPrevious:` → `cancelOperation:` produce correct binding action sequences
- Runtime→view observation: scrollbar state changes propagate to scroll view position
- Click-to-move-cursor verification: mouse events forwarded to surface, cursor movement observed

**No wall-clock tests.** All async coordination tested via explicit state transitions and injected clocks.

## File Structure

### Create
- `Sources/AgentStudio/Features/Terminal/Hosting/TerminalSurfaceActionPerforming.swift`
- `Sources/AgentStudio/Features/Terminal/Hosting/TerminalSurfaceScrollView.swift`
- `Sources/AgentStudio/Features/Terminal/Hosting/TerminalSearchOverlayView.swift`
- `Sources/AgentStudio/Features/Terminal/Hosting/ScrollToBottomIndicatorView.swift`
- `Tests/AgentStudioTests/Features/Terminal/Hosting/TerminalSurfaceScrollViewTests.swift`
- `Tests/AgentStudioTests/Features/Terminal/Hosting/TerminalSearchOverlayViewTests.swift`
- `Tests/AgentStudioTests/Features/Terminal/Hosting/ScrollToBottomIndicatorViewTests.swift`
- `Tests/AgentStudioTests/Features/Terminal/Hosting/TerminalPaneMountViewSearchTests.swift`

### Modify
- `Sources/AgentStudio/Features/Terminal/Ghostty/GhosttyActionRouter.swift` — move tags from deferred to routed
- `Sources/AgentStudio/Features/Terminal/Ghostty/GhosttyAdapter.swift` — add search/mouse payload translations
- `Sources/AgentStudio/Features/Terminal/Runtime/TerminalRuntime.swift` — add scrollbar/search/mouse observable state
- `Sources/AgentStudio/Core/RuntimeEventSystem/Contracts/PaneRuntimeEvent.swift` — add search/mouse event cases, update ScrollbarState
- `Sources/AgentStudio/Features/Terminal/Hosting/TerminalPaneMountView.swift` — compose new children, add responder methods
- `Sources/AgentStudio/Features/Terminal/Ghostty/GhosttySurfaceView.swift` — add performBindingAction, observe mouse shape/visibility
- `Sources/AgentStudio/App/Boot/AppDelegate.swift` — add Find menu entries

### Modify Tests
- `Tests/AgentStudioTests/Features/Terminal/Ghostty/GhosttyAdapterTests.swift`
- `Tests/AgentStudioTests/Features/Terminal/Ghostty/GhosttyActionRouterTests.swift`
- `Tests/AgentStudioTests/Features/Terminal/Runtime/TerminalRuntimeTests.swift`
