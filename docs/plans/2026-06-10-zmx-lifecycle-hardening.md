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

1. **Planner: per-session protection by paneId segment.** Change
   `ZmxOrphanCleanupPlan` to carry `knownSessionIds` +
   `protectedPaneSegments` and drop `shouldSkipCleanup`. Grounding (verified):
   every session-ID format embeds a 16-hex pane segment —
   `sessionId(repoStableKey:worktreeStableKey:paneId:)` ends with
   `paneSessionSegment(paneId)`, and `floatingSessionId`/`drawerSessionId`
   embed pane segments too (`ZmxBackend.swift:165-192`). So even when a main
   pane's repo/worktree stable keys are unresolvable, its `paneId` is always
   known: protect any discovered session whose ID contains that pane's
   segment. Destroy only sessions that (a) match the app's session-ID prefix
   format, (b) are not in the known set, and (c) contain no protected pane
   segment. zmx exposes no session age metadata (verified: `zmx list`
   parsing extracts names only), so no age-based guard is possible — the
   paneId-segment guard replaces it entirely. Log the full session ID before
   every destroy (destroyed sessions are unrecoverable; the log line is the
   only forensic trail). Update planner tests: resolvable-only set,
   unresolvable pane whose segment protects its session, foreign
   (non-app-prefix) sessions never destroyed.
2. **Own the cleanup task.** Store the cleanup `Task` handle on `AppDelegate`,
   cancel it in `isolated deinit` and before
   `flushApplicationStateBeforeTermination` returns. Replace the raw
   `Task.sleep(nanoseconds:)` timeout with the injected `Delay`/clock pattern
   already used by `SessionRuntime` so tests can drive it.
3. **Sequence cleanup vs restore.** Decision: start cleanup only *after*
   launch restore completes (option b). Two corrections this requires:
   (a) the known-set/protected-segments must be computed **inside the cleanup
   task immediately before discovery**, not at `AppDelegate` entry — restore
   mutates `paneAtom` and a set sampled at boot would be stale; (b)
   coordination with the restore-performance plan
   (`2026-06-10-terminal-restore-and-startup-performance.md` task 2 defers
   `zmx list` discovery off the restore critical path) — cleanup-after-restore
   is compatible with that deferral and must not block visible-pane restore
   start; do not choose await-before-restore, which would conflict. Document
   the ordering contract in `session_lifecycle.md`.
4. **Async `SessionConfiguration.detect()`.** Add
   `static func detect() async -> SessionConfiguration` running the probes via
   the existing process-executor seam off the main actor (`@concurrent
   nonisolated` — SE-0461 confirmed: without it, a nonisolated async function
   inherits the caller's actor in Swift 6.2; the attribute is async-only and
   incompatible with actor-isolation annotations). Boot resolves it once
   during `bootWorkspaceServices` and hands the value to `PaneCoordinator`
   (replace the `lazy var` with a constructor/assignment handoff). Ordering
   verification step: confirm `PaneCoordinator` is constructed after the
   await resolves, or that every `sessionConfig` consumer tolerates
   late-resolution — trace the boot sequence before editing. Keep a
   synchronous accessor only for the already-resolved cached value.
5. **Bounded health checks.** Wrap each `backend.isAlive(pane:)` in a timeout
   (injected clock, ~5s, < interval) using a task-group race; mark
   `.unhealthy` on timeout instead of stalling the loop. Keep iteration serial
   (cheap) but now bounded; log when a check exceeds the soft timeout.
6. **Docs.** Update `docs/architecture/session_lifecycle.md` orphan-cleanup and
   health-check sections in the same changeset.

## Proof Gates

- Red/green: new planner tests (unresolvable pane no longer blanket-skips;
  its session protected via paneId segment; foreign sessions untouched),
  cleanup-ordering test via a recording fake backend that captures the call
  sequence (`destroySessionById` timestamps strictly after the
  restore-completion signal — the fake records call order, no wall-clock
  assertions), health-check timeout test with a hung fake backend gated on a
  test-controlled continuation (pane marked unhealthy within the injected
  clock bound, loop proceeds to next pane).
- Focused validation: `mise run test -- --filter "ZmxOrphanCleanupPlanner"`,
  `mise run test -- --filter "SessionRuntime"`,
  `mise run test -- --filter "ZmxBackend"`.
- Full validation: `mise run test` and `mise run lint` (zero errors).
- Manual: launch debug build with a deliberately orphaned zmx session
  (`zmx` session created outside the app), verify it is destroyed at startup
  while live pane sessions survive; quit during cleanup and verify the app
  terminates promptly (< 2s).

## Stop Conditions

- Stop if verification shows any live session-ID format does NOT embed the
  pane segment (the protection guard depends on it) — fall back to keeping
  skip semantics for unresolvable launches and report.
- Stop if making `detect()` async forces a boot-sequence reordering beyond
  `bootWorkspaceServices` (e.g. window presentation depends on it) — report
  before restructuring boot.
- Stop edits if unrelated test lanes fail; report scoped pass/fail.

## Risks

- Aggressive cleanup destroying a user's own zmx sessions: mitigated by
  prefix-format matching + known-set exclusion + pane-id segment protection for
  unresolvable panes. zmx exposes no age metadata, so there is no safety-age
  guard in this design.
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
