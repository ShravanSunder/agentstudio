# Ghostty Runtime Isolation Split Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Split the AgentStudio Ghostty host wrapper by isolation contract so C callback trampolines, app handle ownership, action routing, and focus synchronization no longer live in one mixed-responsibility type.

**Architecture:** Keep `Ghostty.shared` as the subsystem entrypoint and keep `Ghostty.swift` as a thin, boring composition root. Extract the current `Ghostty.App` responsibilities into four focused `Ghostty`-namespaced types: `Ghostty.AppHandle`, `Ghostty.CallbackRouter`, `Ghostty.ActionRouter`, and `Ghostty.AppFocusSynchronizer`. Callback trampolines remain nonisolated and capture only stable identity before hopping to `@MainActor`; lifecycle and action routing remain `@MainActor`. This is a post-host-cutover cleanup and must remain behavior-preserving: no pane host, mount, or event-routing expansion semantics change in this PR.

**Tech Stack:** Swift 6.2, AppKit, Ghostty/libghostty, Swift Testing, mise, swift-format, swiftlint

---

## Preconditions

This follow-up starts only after the universal `PaneHostView` / `TerminalPaneMountView` / `GhosttyMountView` cutover has landed and passed full verification. Do not interleave the two plans.

## Hard-Cutover Rules

1. Keep `Ghostty.shared` as the subsystem entrypoint, but do not keep the old mixed `Ghostty.App` internals alive. `Ghostty.App` may survive only as a thin composition root.
2. No plain `nonisolated async` methods used as fake background boundaries.
3. No `Task.detached` unless intentionally escaping structured concurrency is required and documented inline.
4. Tests should verify observable routing behavior and compile-safe structure, not runtime "is main actor" helper flags.
5. **Preserve `action_cb` Bool return semantics exactly.** The `Bool` return from `handleAction` is a contract with libghostty: `true` means "I handled it, skip your default"; `false` means "I didn't handle it, apply your default behavior." The current code deliberately returns `false` for many unhandled tags to preserve Ghostty's built-in defaults (e.g., color handling, renderer health). The extraction must preserve the exact return value for every action tag unless a behavioral change is intentional and documented inline.
6. **Preserve `.app` vs `.surface` target discrimination.** Some actions target `GHOSTTY_TARGET_APP` (app-wide), others target `GHOSTTY_TARGET_SURFACE` (per-surface). The current code guards `target.tag == GHOSTTY_TARGET_SURFACE` before resolving surface views. The extraction must not lose this distinction.
7. **Preserve current routing behavior exactly.** `showChildExited`, `shouldForwardUnhandledActionToRuntime`, injected `RuntimeRegistry` fallback behavior, and current surface-creation behavior all stay as-is in this PR. Routing expansion belongs to `2026-03-26-ghostty-event-routing-expansion.md`.
8. **`Ghostty.swift` must end as composition-only.** No callback trampolines, no action-tag switch, no focus observation logic, no clipboard handling, and no close-surface handling remain in the root file.

## Boundary And Visibility Rules

1. No `public` or `package` visibility for the extracted host types. Keep them internal to the AgentStudio module.
2. Keep the extracted types under the `Ghostty` namespace to reinforce subsystem ownership: `Ghostty.AppHandle`, `Ghostty.CallbackRouter`, `Ghostty.ActionRouter`, `Ghostty.AppFocusSynchronizer`.
3. Make extracted types `final`.
4. `Ghostty.App` is the only type that composes the extracted pieces. No other caller should construct routers or the focus synchronizer directly.
5. Prefer `private` helper methods and stored properties inside the extracted files. Expose only the minimal methods needed for composition and behavior tests.
6. Future event-routing work lands in `Ghostty.ActionRouter` plus adapter/runtime layers. It must not leak callback or focus logic back into `Ghostty.swift`.

## File Structure Map

### New files

- Create: `Sources/AgentStudio/Features/Terminal/Ghostty/GhosttyAppHandle.swift` (`Ghostty.AppHandle`)
- Create: `Sources/AgentStudio/Features/Terminal/Ghostty/GhosttyCallbackRouter.swift` (`Ghostty.CallbackRouter`)
- Create: `Sources/AgentStudio/Features/Terminal/Ghostty/GhosttyActionRouter.swift` (`Ghostty.ActionRouter`)
- Create: `Sources/AgentStudio/Features/Terminal/Ghostty/GhosttyAppFocusSynchronizer.swift` (`Ghostty.AppFocusSynchronizer`)

### Existing files to modify

- Modify: `Sources/AgentStudio/Features/Terminal/Ghostty/Ghostty.swift`
- Modify: `Sources/AgentStudio/Features/Terminal/Ghostty/GhosttySurfaceView.swift`
- Modify: `Sources/AgentStudio/Features/Terminal/Ghostty/SurfaceManager.swift`
- Modify: `docs/architecture/ghostty_surface_architecture.md`
- Modify: `docs/architecture/appkit_swiftui_architecture.md`
- Modify: `AGENTS.md`

### Test files

- Create: `Tests/AgentStudioTests/Features/Terminal/Ghostty/GhosttyAppHandleTests.swift`
- Create: `Tests/AgentStudioTests/Features/Terminal/Ghostty/GhosttyCallbackRouterTests.swift`
- Create: `Tests/AgentStudioTests/Features/Terminal/Ghostty/GhosttyActionRouterTests.swift`
- Create: `Tests/AgentStudioTests/Features/Terminal/Ghostty/GhosttyAppFocusSynchronizerTests.swift`
- Modify: `Tests/AgentStudioTests/Features/Terminal/Ghostty/GhosttyAdapterTests.swift`

---

### Task 1: Extract App Handle Ownership

**Files:**
- Create: `Sources/AgentStudio/Features/Terminal/Ghostty/GhosttyAppHandle.swift`
- Modify: `Sources/AgentStudio/Features/Terminal/Ghostty/Ghostty.swift`
- Test: `Tests/AgentStudioTests/Features/Terminal/Ghostty/GhosttyAppHandleTests.swift`

- [ ] **Step 1: Write failing tests for app handle ownership**

```swift
@Test
func appHandle_initializesGhosttyAppAndExposesTick() {
    let handle = try #require(Ghostty.AppHandle.forTesting())
    #expect(handle.hasLiveAppForTesting == true)
}

@Test
func appHandle_exposesStableUserdataPointer() {
    let handle = try #require(Ghostty.AppHandle.forTesting())
    #expect(handle.userdataPointerForTesting != nil)
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `SWIFT_BUILD_DIR=".build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8)" swift test --build-path "$SWIFT_BUILD_DIR" --filter "GhosttyAppHandleTests"`
Expected: FAIL with missing type errors.

- [ ] **Step 3: Implement `Ghostty.AppHandle`**

Required behavior:

- own `ghostty_app_t`
- own config lifetime
- expose `tick()`
- expose stable userdata for callback router composition
- keep lifetime ownership separate from action routing and lifecycle observation
- keep the raw app handle surface as narrow as possible for `SurfaceView` creation

- [ ] **Step 4: Rewire `Ghostty.swift` to compose `GhosttyAppHandle`**

Required behavior:

- `Ghostty.swift` no longer stores raw app/config ownership directly in the mixed type
- app creation / freeing route through `GhosttyAppHandle`
- `Ghostty.shared` still returns the local Ghostty subsystem root after the split

- [ ] **Step 5: Run focused tests**

Run: `SWIFT_BUILD_DIR=".build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8)" swift test --build-path "$SWIFT_BUILD_DIR" --filter "GhosttyAppHandleTests"`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add Sources/AgentStudio/Features/Terminal/Ghostty/GhosttyAppHandle.swift \
  Sources/AgentStudio/Features/Terminal/Ghostty/Ghostty.swift \
  Tests/AgentStudioTests/Features/Terminal/Ghostty/GhosttyAppHandleTests.swift
git commit -m "refactor: extract ghostty app handle ownership"
```

---

### Task 2: Extract Callback And Main-Actor Routers

**Files:**
- Create: `Sources/AgentStudio/Features/Terminal/Ghostty/GhosttyCallbackRouter.swift`
- Create: `Sources/AgentStudio/Features/Terminal/Ghostty/GhosttyActionRouter.swift`
- Create: `Sources/AgentStudio/Features/Terminal/Ghostty/GhosttyAppFocusSynchronizer.swift`
- Modify: `Sources/AgentStudio/Features/Terminal/Ghostty/Ghostty.swift`
- Modify: `Sources/AgentStudio/Features/Terminal/Ghostty/GhosttySurfaceView.swift`
- Modify: `Sources/AgentStudio/Features/Terminal/Ghostty/SurfaceManager.swift`
- Test: `Tests/AgentStudioTests/Features/Terminal/Ghostty/GhosttyCallbackRouterTests.swift`
- Test: `Tests/AgentStudioTests/Features/Terminal/Ghostty/GhosttyActionRouterTests.swift`
- Test: `Tests/AgentStudioTests/Features/Terminal/Ghostty/GhosttyAppFocusSynchronizerTests.swift`

- [ ] **Step 1: Write failing routing tests**

```swift
@Test
@MainActor
func actionRouter_routesKnownActionToTerminalRuntime() {
    let harness = makeGhosttyActionRoutingHarness()
    harness.deliverTitleChangedAction()
    #expect(harness.routedEvent == .setTitle("demo"))
}

@Test
@MainActor
func focusSynchronizer_pushesLifecycleFocusChangesToGhostty() {
    let harness = makeGhosttyFocusHarness()
    harness.setApplicationActive(false)
    #expect(harness.lastFocusedValue == false)
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `SWIFT_BUILD_DIR=".build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8)" swift test --build-path "$SWIFT_BUILD_DIR" --filter "GhosttyCallbackRouterTests|GhosttyActionRouterTests|GhosttyAppFocusSynchronizerTests"`
Expected: FAIL with missing type errors.

- [ ] **Step 3: Implement `Ghostty.CallbackRouter`**

Required behavior:

- own all C callback statics: `wakeup_cb`, `action_cb`, `read_clipboard_cb`, `confirm_read_clipboard_cb`, `write_clipboard_cb`, `close_surface_cb`
- reconstruct Swift objects from userdata
- capture only stable identity before hopping to `@MainActor`
- remain nonisolated
- keep clipboard and close-surface behavior unchanged in this PR

- [ ] **Step 4: Implement `Ghostty.ActionRouter`**

Required behavior:

- own main-actor action routing currently mixed into `Ghostty.swift`
- keep exhaustive action-tag handling
- route into `SurfaceManager`, `RuntimeRegistry`, and terminal runtime code
- preserve current fallback and unhandled-action behavior exactly; expansion is follow-up work

- [ ] **Step 5: Implement `Ghostty.AppFocusSynchronizer`**

Required behavior:

- observe app lifecycle state via `AppLifecycleStore.isActive`
- call `ghostty_app_set_focus` — app-level focus only
- keep focus synchronization isolated from callback/router code
- **per-surface focus (`ghostty_surface_set_focus`) remains in `GhosttySurfaceView` / `GhosttyMountView`** — this type does NOT absorb surface-level focus. The app/surface focus boundary maps to the host/mount boundary from Plan 1.

- [ ] **Step 6: Recompose `Ghostty.swift` around the new types**

Required behavior:

- `Ghostty.swift` becomes the thin composition root for the handle/router/synchronizer pieces
- no mixed type remains that owns callbacks and lifecycle sync in one place
- callers still enter through `Ghostty.shared`; the split is internal to the subsystem boundary

- [ ] **Step 7: Add integration-style routing seam test**

At least one test must exercise the full lookup chain: registered surfaceView → `SurfaceManager.surfaceId(forViewObjectId:)` → `SurfaceManager.paneId(for:)` → `RuntimeRegistry.runtime(for:)` → `TerminalRuntime.handleGhosttyEvent()`. This proves the extraction didn't break the seams between the callback router, surface manager, and runtime registry.

```swift
@Test
@MainActor
func actionRouter_endToEnd_registeredSurfaceReachesTerminalRuntime() {
    let harness = makeEndToEndActionRoutingHarness()
    // harness registers: surfaceView in SurfaceManager, paneId mapping, runtime in registry
    harness.deliverActionViaCallbackRouter(tag: .setTitle, payload: .titleChanged("test"))

    #expect(harness.runtime.metadata.title == "test")
}

@Test
@MainActor
func callbackRouter_closeSurface_reachesSurfaceViewCloseHandler() {
    let harness = makeEndToEndCallbackHarness()
    harness.deliverCloseSurfaceCallback(processAlive: false)

    #expect(harness.closeCallbackReceived == true)
}
```

- [ ] **Step 8: Run focused tests**

Run: `SWIFT_BUILD_DIR=".build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8)" swift test --build-path "$SWIFT_BUILD_DIR" --filter "GhosttyCallbackRouterTests|GhosttyActionRouterTests|GhosttyAppFocusSynchronizerTests|GhosttyAdapterTests"`
Expected: PASS

- [ ] **Step 9: Commit**

```bash
git add Sources/AgentStudio/Features/Terminal/Ghostty/GhosttyCallbackRouter.swift \
  Sources/AgentStudio/Features/Terminal/Ghostty/GhosttyActionRouter.swift \
  Sources/AgentStudio/Features/Terminal/Ghostty/GhosttyAppFocusSynchronizer.swift \
  Sources/AgentStudio/Features/Terminal/Ghostty/Ghostty.swift \
  Sources/AgentStudio/Features/Terminal/Ghostty/GhosttySurfaceView.swift \
  Sources/AgentStudio/Features/Terminal/Ghostty/SurfaceManager.swift \
  Tests/AgentStudioTests/Features/Terminal/Ghostty/GhosttyCallbackRouterTests.swift \
  Tests/AgentStudioTests/Features/Terminal/Ghostty/GhosttyActionRouterTests.swift \
  Tests/AgentStudioTests/Features/Terminal/Ghostty/GhosttyAppFocusSynchronizerTests.swift
git commit -m "refactor: split ghostty callbacks and lifecycle routing"
```

---

### Task 3: Docs And Verification

**Files:**
- Modify: `docs/architecture/ghostty_surface_architecture.md`
- Modify: `docs/architecture/appkit_swiftui_architecture.md`
- Modify: `AGENTS.md`
- All files modified in Tasks 1-2

- [ ] **Step 1: Update docs for the new Ghostty runtime structure**

Required doc outcomes:

- document `GhosttyAppHandle`, `GhosttyCallbackRouter`, `GhosttyActionRouter`, and `GhosttyAppFocusSynchronizer`
- document that `Ghostty.shared` / `Ghostty.App` remains the subsystem entry seam while behavior lives in the extracted namespaced types
- describe nonisolated callback trampolines vs `@MainActor` routing
- keep Swift 6.2 concurrency guidance aligned with the code

- [ ] **Step 2: Run focused tests**

Run: `SWIFT_BUILD_DIR=".build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8)" swift test --build-path "$SWIFT_BUILD_DIR" --filter "GhosttyAppHandleTests|GhosttyCallbackRouterTests|GhosttyActionRouterTests|GhosttyAppFocusSynchronizerTests|GhosttyAdapterTests"`
Expected: PASS

- [ ] **Step 3: Run full test suite and lint**

Run:

```bash
AGENT_RUN_ID=ghostty-runtime-split mise run test
AGENT_RUN_ID=ghostty-runtime-split mise run lint
```

Expected: PASS, zero failures, zero lint errors.

- [ ] **Step 4: Commit**

```bash
git add docs/architecture/ghostty_surface_architecture.md \
  docs/architecture/appkit_swiftui_architecture.md \
  AGENTS.md
git commit -m "docs: update ghostty runtime isolation architecture"
```

---

## Notes For The Implementer

- This follow-up should happen immediately after the host/mount cutover, not in the same changeset.
- Prefer compile-time-safe structure and observable behavior over runtime actor-isolation helper tests.
- Keep callback trampolines tiny and deterministic.
- Do not let this plan reopen any host/mount or placeholder design decisions from the previous plan.
