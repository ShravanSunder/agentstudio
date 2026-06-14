# Ghostty Integration Safety: Action Routing Crash Path + Focus Handle TOCTOU

Planned at: a80ebb05
Repo: /Users/shravansunder/Documents/dev/project-dev/agent-studio.improve-v1
Status: proposed

## Problem

Two verified stability gaps in the embedded Ghostty host:

1. **`preconditionFailure` in the action routing fall-through.** Any Ghostty
   action tag that reaches the end of `handleAction` without a routing decision
   panics the whole app from inside a C callback. This directly violates the
   architecture contract ("one terminal crash must never bring down the app",
   `docs/architecture/ghostty_surface_architecture.md`). The trigger is
   realistic: a vendored ghostty bump that adds or re-routes action tags.
2. **Read→use TOCTOU on the raw app handle in `AppFocusSynchronizer`.**
   `appHandleBits` is an `OSAllocatedUnfairLock`-guarded `UInt` of pointer
   bits. `syncApplicationFocus()` (MainActor) reads the bits, drops the lock,
   reconstructs the pointer, and calls `ghostty_app_set_focus`. The
   `nonisolated clearAppHandleForDeinit()` can clear the bits — and the
   underlying `ghostty_app_t` can be freed — between the read and the use.
   The lock protects each access, not the read→use sequence. Window is
   teardown-only, but the result is a use-after-free into Zig code.

## Current Evidence

- `Sources/AgentStudio/Features/Terminal/Ghostty/GhosttyActionRouter.swift:160`
  — `preconditionFailure("Ghostty action tag \(actionTag) missing routing
  decision")` after the intercepted/workspace/observed handler chain
  (lines 132-158) returns no decision.
- `Sources/AgentStudio/Features/Terminal/Ghostty/GhosttyAppFocusSynchronizer.swift:83-92`
  — `appHandleBits.current()` then `UnsafeMutableRawPointer(bitPattern:)` then
  `focusSetter.setAppFocus(app, ...)`, with no validity coupling;
  `GhosttyAppFocusSynchronizer.swift:51-53` — `nonisolated func
  clearAppHandleForDeinit()` may run concurrently with the MainActor sync.
- Rejected during audit (do not re-report): the claimed
  `SurfaceManager.onWorkingDirectoryChanged` collection-move "race"
  (`SurfaceManager.swift:667-702`) is fully synchronous on MainActor — no
  suspension between snapshot and write-back, so no interleaving is possible.
  Likewise the `withObservationTracking` re-arm in `AppFocusSynchronizer` has
  no await between `syncApplicationFocus()` and re-observation, so transitions
  cannot be missed.

## Non-Goals

- No catch-all panic isolation for Zig-side panics inside Ghostty core (that
  is a separate, much larger effort and likely impossible from Swift).
- No redesign of the AppHandle/CallbackRouter/ActionRouter host split.
- No change to surface health/undo mechanics.

## Scope

Write surfaces:
- `Sources/AgentStudio/Features/Terminal/Ghostty/GhosttyActionRouter.swift` —
  replace the fall-through panic with a logged, health-reported safe return.
- `Sources/AgentStudio/Features/Terminal/Ghostty/GhosttyAppFocusSynchronizer.swift`
  — make the handle read→use atomic with respect to clearing.
- Tests under `Tests/AgentStudioTests/Features/Terminal/` (router decision
  coverage + synchronizer behavior).

Read-only context:
- `Sources/AgentStudio/Features/Terminal/Ghostty/GhosttyActionTag.swift` — the
  tag inventory that must have exhaustive routing decisions.
- `Sources/AgentStudio/Features/Terminal/Ghostty/GhosttyAppHandle.swift` — who
  calls `clearAppHandleForDeinit` and when the C handle is freed.
- `docs/architecture/ghostty_surface_architecture.md` — crash-isolation
  contract.

## Task Sequence

1. **Exhaustiveness test first.** Add a test that iterates every
   `GhosttyActionTag` the router declares as explicitly routed and asserts a
   routing decision is produced by one of the handler chains (intercepted /
   workspace / observed). This converts the runtime panic into a compile-time/
   test-time guarantee — which is the only legitimate job the
   `preconditionFailure` was doing.
2. **Replace the panic.** Change `GhosttyActionRouter.swift:160` to log at
   error level (with raw tag + decoded tag), record a trace event via the
   existing `+Tracing` seam, and return `false` (unhandled) so Ghostty applies
   its default behavior. No precondition in release code paths reachable from
   C callbacks.
3. **Fix the focus-handle TOCTOU.** Move the `setAppFocus` call inside the
   lock's critical section: extend `GhosttyAppHandleBits` with
   `withCurrent(_ body: (ghostty_app_t) -> Void)` executing under
   `lock.withLock`, so clearing cannot interleave between read and use.
   Grounding (researched via deepwiki ghostty-org/ghostty):
   `ghostty_app_set_focus` updates a boolean field on the App struct — no
   allocation, no locks, no callbacks back into the host — so it meets
   Apple's unfair-lock discipline ("keep the body small; do not call out to
   code you do not control" — this call is verified-controlled). Constraint:
   the critical section may contain **only** this verified call; if a future
   change needs another C call in the section, re-verify it to the same bar
   or switch to the generation-counter validation scheme (documented
   fallback). State both the evidence and the constraint in a code comment.
4. **Audit the freeing order.** Confirm `clearAppHandleForDeinit()` is invoked
   strictly before `ghostty_app_free` in `GhosttyAppHandle` teardown; add a
   comment stating the ordering contract at both sites.
5. **Docs.** Note the unhandled-action fallback behavior in
   `ghostty_surface_architecture.md` (one paragraph).

## Proof Gates

- Red/green: exhaustiveness test fails if any routed tag lacks a decision
  (validate by temporarily removing one handler case locally); TOCTOU test via
  the injectable `GhosttyAppFocusSetting` fake — a bounded stress loop
  (N detached `clearAppHandleForDeinit()` tasks racing M `sync` calls, no
  sleeps) asserts the recording setter never receives a zero/cleared handle
  bit-pattern.
- Focused validation: `mise run test -- --filter "GhosttyActionRouter"`,
  `mise run test -- --filter "AppFocusSynchronizer"`.
- Full validation: `mise run test`, `mise run lint` — zero errors.
- Manual: launch debug build, open terminals, background/foreground the app
  repeatedly, quit — no crash, focus follows app activation (verify with
  Peekaboo by PID).

## Stop Conditions

- Resolved during plan review: deepwiki verification shows
  `ghostty_app_set_focus` cannot re-enter Swift (atomic boolean setter). The
  stop condition now applies only if execution-time reading of the vendored
  ghostty source contradicts that finding (e.g. after a ghostty bump).
- Stop if the exhaustiveness test reveals tags whose correct routing is
  ambiguous (product decision needed on default behavior) — list them and ask.

## Risks

- Returning `false` for previously-panicking tags changes behavior from
  "crash" to "ghostty default" — strictly better, but watch logs for
  unexpected-tag noise after ghostty bumps; the error log + trace make this
  visible.
- Calling into C under an unfair lock: keep the critical section to the single
  C call; no Swift allocation or logging inside it.

## Handoff Prompt

```text
Use implementation-execute-plan on this plan.

Repo: /Users/shravansunder/Documents/dev/project-dev/agent-studio.improve-v1
Plan: docs/plans/2026-06-10-ghostty-action-routing-safety.md
Start by validating the plan against current git state before editing files.
Tasks 1-2 (router) and 3-4 (focus synchronizer) are independent slices.
Parent owns integration and final proof (mise run test, mise run lint).
```
