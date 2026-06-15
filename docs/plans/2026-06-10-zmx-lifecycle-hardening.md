# zmx Lifecycle Hardening: Orphan Cleanup, Health Checks, Boot Blocking

Planned at: a80ebb05
Repo: /Users/shravansunder/Documents/dev/project-dev/agent-studio.improve-v1
Status: proposed

## Problem

Three verified stability gaps in the zmx session lifecycle:

1. **Orphan cleanup is fire-and-forget with a raw wall-clock timeout and an
   all-or-nothing skip.** The cleanup task is spawned unowned from
   `applicationDidFinishLaunching`, races the restore path with no ordering
   contract, uses `Task.sleep(nanoseconds: 30_000_000_000)` (untestable,
   bypasses the repo's injected-clock convention), and skips *all* cleanup when
   *any single* main pane cannot resolve stable keys — so one stale pane lets
   orphan daemons accumulate unboundedly across restarts.
2. **Health checks have no per-pane timeout and run serially.** One stalled
   `zmx list` blocks every subsequent pane's check; retry backoff sleeps
   compound the stall.
3. **`SessionConfiguration.detect()` blocks the main thread at boot.** It runs
   `which zmx` (and version probing) via `Process.waitUntilExit()` on
   `@MainActor` — once from `cleanupOrphanZmxSessions()` and once lazily from
   `PaneCoordinator`.

The startup diagnostics added in a80ebb05 observe these paths but do not fix
them; this plan removes the failure modes the diagnostics were chasing.

## Current Evidence

- `Sources/AgentStudio/App/Boot/AppDelegate.swift:260` — orphan cleanup spawned
  as bare `Task { ... }`; no owner, not cancelled at termination, not awaited
  before restore.
- `Sources/AgentStudio/App/Boot/AppDelegate.swift:282` —
  `try await Task.sleep(nanoseconds: 30_000_000_000)` raw wall-clock timeout;
  the repo's own helper (`Duration.nanosecondsForTaskSleep`,
  `Sources/AgentStudio/Infrastructure/Extensions/FoundationExtensions.swift:38`)
  and injected `Delay`/`Clock` patterns exist but are not used here. Only one
  other raw-nanoseconds sleep remains in the app
  (`AppDelegate+LaunchRestore.swift:40`, a diagnostic watchdog).
- `Sources/AgentStudio/App/Coordination/ZmxOrphanCleanupPlanner.swift:26-28,42`
  — any `.main` candidate with nil stable keys sets
  `shouldSkipCleanup = true`; `AppDelegate.swift:248-253` then returns without
  cleaning *anything*.
- `Sources/AgentStudio/App/Boot/AppDelegate.swift:213` —
  `SessionConfiguration.detect()` called on `@MainActor`;
  `Sources/AgentStudio/Core/Models/SessionConfiguration.swift:214-222,273` uses
  `Process` + `waitUntilExit()` synchronously.
  `Sources/AgentStudio/App/Coordination/PaneCoordinator.swift:52` has a second
  `lazy var sessionConfig = SessionConfiguration.detect()` that fires on first
  touch, also on the main actor.
- `Sources/AgentStudio/Core/RuntimeEventSystem/Runtime/SessionRuntime.swift:170-180`
  — `runHealthCheck()` iterates `store.paneAtom.panes` and awaits
  `backend.isAlive(pane:)` serially; no per-pane timeout beyond the executor's
  internal default. `ZmxBackend.executeWithRetry` sleeps between attempts, so a
  stalled CLI compounds across panes.

## Non-Goals

- No change to zmx session-ID naming or the vendored zmx submodule.
- No redesign of `SessionRuntime` status modeling or the runtime event planes.
- The surface-orphan-on-pane-delete edge (SurfaceManager hidden surfaces) is
  out of scope — TTL already bounds it.
- The `AppDelegate+LaunchRestore.swift:40` watchdog sleep stays (it is a
  diagnostic timer with recovery, not a correctness path); only normalize it to
  the safe-sleep helper if touched.

## Scope

Write surfaces:
- `Sources/AgentStudio/App/Boot/AppDelegate.swift` — own/sequence the cleanup
  task, injected clock, termination cancellation.
- `Sources/AgentStudio/App/Coordination/ZmxOrphanCleanupPlanner.swift` —
  per-session skip semantics instead of all-or-nothing.
- `Sources/AgentStudio/Core/Models/SessionConfiguration.swift` — async detect
  seam (keep a cached sync read for steady-state).
- `Sources/AgentStudio/App/Coordination/PaneCoordinator.swift` — consume the
  async-detected config instead of lazy sync detect.
- `Sources/AgentStudio/Core/RuntimeEventSystem/Runtime/SessionRuntime.swift` —
  bounded per-pane health check.
- Tests: `Tests/AgentStudioTests/Core/Stores/ZmxBackendTests.swift`,
  `Tests/AgentStudioTests/.../SessionRuntimeTests.swift`, planner tests.

Read-only context:
- `Sources/AgentStudio/Core/RuntimeEventSystem/Runtime/ZmxBackend.swift` —
  retry policy, session-ID derivation, `discoverOrphanSessions`.
- `docs/architecture/session_lifecycle.md` — lifecycle contract to keep in sync.
- `Sources/AgentStudio/App/Boot/AppDelegate+Termination.swift` — termination
  drain pattern to mirror.

## Task Sequence

1. **Planner: per-session skip.** Change `ZmxOrphanCleanupPlan` to carry
   `knownSessionIds` + `unresolvableCount` and drop `shouldSkipCleanup`.
   Cleanup proceeds, but `discoverOrphanSessions(excluding:)` keeps its
   conservative exclusion set; log the unresolvable count. Rationale: an
   unresolvable pane cannot name its session ID, so it cannot protect it — but
   sessions follow a deterministic naming scheme, so any session matching the
   scheme for a *resolvable* pane set is safely classifiable. Add a
   conservative guard: if `unresolvableCount > 0`, only destroy sessions whose
   IDs match the app's session-ID prefix format AND are not in the known set
   AND are older than a safety age (from zmx metadata if available; otherwise
   keep skip behavior for that launch and log loudly). Update planner tests for
   both branches.
2. **Own the cleanup task.** Store the cleanup `Task` handle on `AppDelegate`,
   cancel it in `isolated deinit` and before
   `flushApplicationStateBeforeTermination` returns. Replace the raw
   `Task.sleep(nanoseconds:)` timeout with the injected `Delay`/clock pattern
   already used by `SessionRuntime` so tests can drive it.
3. **Sequence cleanup vs restore.** Either await cleanup completion before
   `restoreAllViews` begins, or (preferred, smaller) start cleanup only *after*
   launch restore completes — the protected-session set is identical, and this
   removes the kill-vs-attach race window outright. Document the ordering in
   `session_lifecycle.md`.
4. **Async `SessionConfiguration.detect()`.** Add
   `static func detect() async -> SessionConfiguration` running the probes via
   the existing process-executor seam off the main actor (`@concurrent
   nonisolated` per SE-0461). Boot resolves it once during
   `bootWorkspaceServices` and hands the value to `PaneCoordinator` (replace
   the `lazy var`). Keep a synchronous accessor only for the already-resolved
   cached value.
5. **Bounded health checks.** Wrap each `backend.isAlive(pane:)` in a timeout
   (injected clock, ~5s, < interval) using a task-group race; mark
   `.unhealthy` on timeout instead of stalling the loop. Keep iteration serial
   (cheap) but now bounded; log when a check exceeds the soft timeout.
6. **Docs.** Update `docs/architecture/session_lifecycle.md` orphan-cleanup and
   health-check sections in the same changeset.

## Proof Gates

- Red/green: new planner tests (unresolvable pane no longer blanket-skips;
  protected set unchanged), cleanup-ordering test (restore completes before
  any destroy issued, or cleanup awaited — match chosen design), health-check
  timeout test with a hung fake backend (pane marked unhealthy within bound,
  loop proceeds to next pane).
- Focused validation: `mise run test -- --filter "ZmxOrphanCleanupPlanner"`,
  `mise run test -- --filter "SessionRuntime"`,
  `mise run test -- --filter "ZmxBackend"`.
- Full validation: `mise run test` and `mise run lint` (zero errors).
- Manual: launch debug build with a deliberately orphaned zmx session
  (`zmx` session created outside the app), verify it is destroyed at startup
  while live pane sessions survive; quit during cleanup and verify the app
  terminates promptly (< 2s).

## Stop Conditions

- Stop if zmx session metadata cannot distinguish app-created sessions from
  user sessions safely — fall back to keeping skip semantics for unresolvable
  launches and report.
- Stop if making `detect()` async forces a boot-sequence reordering beyond
  `bootWorkspaceServices` (e.g. window presentation depends on it) — report
  before restructuring boot.
- Stop edits if unrelated test lanes fail; report scoped pass/fail.

## Risks

- Aggressive cleanup destroying a user's own zmx sessions: mitigated by
  prefix-format matching + known-set exclusion + safety-age guard, and by the
  conservative branch when unresolvable panes exist.
- Async detect changing first-terminal-open latency: config now resolves at
  boot (earlier, off-main), so first open should be faster, but verify the
  PaneCoordinator path never sees a nil config.

## Handoff Prompt

```text
Use implementation-execute-plan on this plan.

Repo: /Users/shravansunder/Documents/dev/project-dev/agent-studio.improve-v1
Plan: docs/plans/2026-06-10-zmx-lifecycle-hardening.md
Start by validating the plan against current git state before editing files.
Tasks 1-2 and 4-5 are independent slices; task 3 depends on task 2. Use bounded
subagents only for independent slices. Parent owns integration and final proof
(mise run test, mise run lint).
```
