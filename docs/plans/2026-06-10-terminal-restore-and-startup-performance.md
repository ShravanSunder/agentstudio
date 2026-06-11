# Terminal Restore & Startup Performance: Measure First, Then Cut the Verified Costs

Planned at: a80ebb05
Repo: /Users/shravansunder/Documents/dev/project-dev/agent-studio.improve-v1
Status: proposed

## Problem

Restore of N terminal panes is the app's slowest user-visible path, and several
startup costs run on the main thread. The deep-dive audits produced a restore
cost model — `zmx list` once (good: no N+1) + N × serial surface creation on
MainActor — and a set of verified standing costs. Several headline performance
claims from the broad audit were **refuted** and must not be "fixed":
RestoreTrace formatting is `@autoclosure` behind a disabled guard (no
production cost), scroll handling only updates `frame.origin` per tick with
row-dispatch already deduped, workspace saves are SQLite (the prettyPrinted
JSON path is legacy-only), and the 10s launch sleep is a diagnostic watchdog
with recovery.

Verified costs, in priority order:

1. **Serial restore loop.** `restoreAllViews` restores visible panes in a
   plain synchronous loop; hidden panes likewise (with cooperative yields).
   Total restore ≈ N × per-surface creation latency.
2. **Restore start is gated on `zmx list` with the standard retry policy** —
   a failing/slow probe defers *all* visible panes by up to ~700ms.
3. **Worktrunk check can block launch with a modal.** `alert.runModal()` runs
   before the window when Worktrunk is missing, with an AppleScript side
   effect.
4. **Surface health Timer fires every 2s over active *and* hidden surfaces**,
   calling `ghostty_surface_process_exited` per surface regardless of app
   active state.
5. **`Derived`/`DerivedSelector` recompute on every access** — no memoization;
   `WorkspacePaneDerived.panes` walks the whole graph per read, multiplied by
   every UI read per invalidation.
6. **Every debounced save rewrites the full pane/tab graph**
   (delete-not-in + upsert-all inside one transaction) — atomic and correct,
   but O(graph) per keystroke-adjacent mutation burst.

## Current Evidence

- `Sources/AgentStudio/App/Coordination/PaneCoordinator+ViewLifecycle.swift:710-717`
  — `for paneId in visiblePaneIds { restorePaneAndDrawers(...) }` (serial);
  `:730-741` hidden loop with `Task.yield()` every 2; `:705` —
  `await hiddenLiveSessionIds()` gates the loop.
- `Sources/AgentStudio/Core/RuntimeEventSystem/Runtime/ZmxBackend.swift:12-14`
  — standard retry policy (3 attempts, 100/250ms backoffs) used for discovery.
- `Sources/AgentStudio/App/Boot/AppDelegate.swift:168-204` —
  `checkWorktrunkInstallation` builds an `NSAlert` and `runModal()`s;
  `WorktrunkService.shared.isInstalled` is a synchronous probe.
- `Sources/AgentStudio/Features/Terminal/Ghostty/SurfaceManager.swift:619-627`
  — `Timer.scheduledTimer(withTimeInterval: healthCheckInterval, repeats:
  true)`; `:704-710` iterates `activeSurfaces` + `hiddenSurfaces` per tick.
- `Sources/AgentStudio/Infrastructure/AtomLib/Derived.swift:9-11` —
  `var value: Value { compute(AtomReader()) }` (recompute per access);
  `DerivedSelector` likewise.
- `Sources/AgentStudio/Core/State/MainActor/Persistence/WorkspaceCoreRepository+PaneGraphMutation.swift:4-27`
  — full delete-not-in + upsert-all per save (single transaction; correctness
  verified — performance shape only).
- Refuted (do not act on): RestoreTrace autoclosure cost in production
  (`Infrastructure/Diagnostics/RestoreTrace.swift` guard precedes evaluation),
  scroll-tick `sizeDidChange` storms
  (`TerminalSurfaceScrollView.swift:189-255` — `frame.origin` only),
  prettyPrinted JSON on the hot save path (`WorkspaceStore.persistNow`
  routes to SQLite; JSON is the legacy fallback).

## Non-Goals

- No parallelization of Ghostty surface creation in this plan until the
  baseline proves it is wait-bound rather than MainActor-CPU-bound —
  parallelizing MainActor-bound work is a no-op with extra risk.
- No atom-granularity redesign (`WorkspacePaneGraphAtom` split) — only
  measurement that would justify a future plan.
- No incremental-save rewrite of the SQLite pipeline in this plan —
  instrument first; the full-replace is correct and may be cheap enough.
- `SessionConfiguration.detect()` main-thread blocking is owned by
  `2026-06-10-zmx-lifecycle-hardening.md` (task 4) — do not duplicate.

## Scope

Write surfaces:
- `Sources/AgentStudio/App/Coordination/PaneCoordinator+ViewLifecycle.swift` —
  restore instrumentation; discovery deferral.
- `Sources/AgentStudio/Core/RuntimeEventSystem/Runtime/ZmxBackend.swift` —
  per-operation retry policy parameter.
- `Sources/AgentStudio/App/Boot/AppDelegate.swift` — Worktrunk check timing
  and presentation.
- `Sources/AgentStudio/Features/Terminal/Ghostty/SurfaceManager.swift` —
  health-check gating.
- `Sources/AgentStudio/Infrastructure/AtomLib/Derived.swift`,
  `DerivedSelector.swift` — memoization, only if measurement justifies.
- `Sources/AgentStudio/Core/State/SQLite/WorkspaceSQLiteDatastore.swift` (or
  trace recorder) — save-duration instrumentation.

Read-only context:
- `Sources/AgentStudio/Infrastructure/Diagnostics/RestoreTrace.swift` — the
  existing opt-in tracing to extend (do not invent a new mechanism).
- `Sources/AgentStudio/Features/Terminal/Restore/TerminalRestoreScheduler.swift`
  — visibility tiering the instrumentation must respect.

## Task Sequence

1. **Baseline instrumentation (gate for everything else).** Extend
   RestoreTrace with per-pane restore timings (start/end per
   `restorePaneAndDrawers`, surface-create duration, zmx discovery duration)
   and a save-duration trace in the datastore (pane/tab counts + ms). Run
   debug build with `AGENTSTUDIO_RESTORE_TRACE=1` at 10 and 30 panes; record
   the baseline table in this plan's PR description.
2. **Defer/trim zmx discovery.** Start visible-pane restore immediately;
   resolve `hiddenLiveSessionIds()` concurrently and await it only before the
   hidden-pane loop. Add a `retryPolicy` parameter to `executeWithRetry` and
   use single-attempt for discovery (destroy/kill keep the standard policy).
3. **Move the Worktrunk check off the launch path.** Run it after the first
   window is visible; replace `runModal()` with a non-blocking presentation
   consistent with the no-toast contract (e.g. a persistent inbox notification
   of kind `approvalRequested`-style or a sheet on explicit user action).
   Drop the synchronous probe from `applicationDidFinishLaunching`.
4. **Gate surface health checks.** Pause the health Timer while
   `AppLifecycleAtom.isActive == false` (resume + immediate check on
   activation), and skip `pendingUndo`/hidden surfaces unless their state can
   change while hidden (verify: zmx-backed hidden surfaces can die — keep them
   but at a slower cadence, e.g. every 5th tick).
5. **Derived memoization — measure, then decide.** Add a debug-only access
   counter to `Derived.value`; capture reads-per-frame during tab switching
   and sidebar interaction at 30 panes. If a hot derived value exceeds ~100
   recomputes/s, add per-`Derived` last-value caching keyed by an atom
   revision counter (bump on mutation) — smallest viable invalidation, no
   general dependency graph. If below threshold, record the numbers and close
   this task as not-justified.
6. **Save-pipeline verdict.** From task 1 numbers: if p95 save duration at 30
   panes is under ~10ms, document "full-replace is fine" in
   `atom_persistence_boundaries.md` and stop; otherwise write a follow-up plan
   for dirty-subtree saves (do not implement here).

## Proof Gates

- Baseline + after table for: launch → first visible terminal (10/30 panes),
  total restore duration, save p50/p95 at 30 panes, idle CPU with 20 panes
  (app backgrounded) before/after task 4.
- Red/green: discovery-deferral test (visible restore proceeds while
  discovery is pending — fake backend with delayed `list`); health-gating test
  (no `isAlive` calls while inactive, immediate check on activation).
- Focused validation: `mise run test -- --filter "SurfaceManager"`,
  `mise run test -- --filter "Restore"`.
- Full validation: `mise run test`, `mise run lint` — zero errors.
- Manual: Peekaboo-verified launch with 10+ restored panes; Worktrunk-missing
  scenario shows the non-modal surface and the window appears immediately.

## Stop Conditions

- Stop task 5 if measurement shows derived reads are not hot — record numbers
  and close; do not memoize speculatively.
- Stop task 3 if the Worktrunk UX replacement needs design input beyond
  "non-modal, post-launch" — propose options and ask (UX-first rule).
- Stop if baseline shows surface creation dominates and is MainActor-CPU-bound
  — parallelization is then a Ghostty-level question; write findings, do not
  refactor restore concurrency here.

## Risks

- Deferring discovery changes hidden-pane attach inputs: hidden restore must
  still see the resolved set — the await-before-hidden-loop preserves this;
  the test in proof gates pins it.
- Slowing hidden-surface health cadence delays dead-session detection for
  hidden panes — bounded by the chosen cadence; surfaces re-check immediately
  on reattach (verify this hook exists; if not, add it in task 4).

## Handoff Prompt

```text
Use implementation-execute-plan on this plan.

Repo: /Users/shravansunder/Documents/dev/project-dev/agent-studio.improve-v1
Plan: docs/plans/2026-06-10-terminal-restore-and-startup-performance.md
Start by validating the plan against current git state before editing files.
Task 1 (instrumentation + baseline numbers) gates everything else — do it
first and record the table. Tasks 2, 3, 4 are then independent slices; tasks
5-6 are measurement-decided. Parent owns integration and final proof
(mise run test, mise run lint, baseline/after table).
```
