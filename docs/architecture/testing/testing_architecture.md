# Testing Architecture

This document owns how a test in this repository waits, which lane runs it, what
"done" means for the production components a test awaits, and what to do when a
run comes back red. It is the standard the polling-wait lint gate enforces and
the one `AGENTS.md` routes to.

Source of the requirements behind it:
[CI Reliability — Specification](../../specs/2026-09-17-ci-reliability/2026-09-17-ci-reliability.md).

## The one rule

**A test's verdict is a function of program logic, never of machine speed. The
only elapsed-time bound a test may have is the runner-owned hang bound, and it
is never raised to make a test pass.**

Two weeks of red CI came from ignoring that. The tests were not wrong about the
product; they were wrong about the machine. Here is the machine:

| | A developer Mac (the one this was diagnosed on) | GitHub runner (`macos-26`) |
| --- | --- | --- |
| CPU count | 16 | 3 |
| Swift cooperative-pool threads | one per core: 16 | one per core: 3 |
| Test lane entry point | `mise run test` → [`scripts/run-swift-test-task.sh`](../../../scripts/run-swift-test-task.sh) | the same `mise run test:swift:*` tasks ([`ci.yml`](../../../.github/workflows/ci.yml)) |
| In-process case concurrency | unbounded | unbounded |
| Isolated suite processes at once | `min(ncpu, 4)` = 4 | `min(ncpu, 4)` = 3 |
| `SWIFT_TEST_TIMEOUT_SECONDS` | 600 | 600 |
| Serialized E2E lane | runs (`SWIFT_TEST_INCLUDE_E2E=1`) | not yet; spec R17, PR 2 |

The cooperative pool is the whole story. A test that parks a pool thread — on
process exit, a semaphore, a socket read — removes one of three threads from a
runner that has three. Three such tests at once deadlocked the entire fast lane
with no failure message, only a ten-minute silence. A test that polls with a
"200 turns or 10 seconds" budget gets its turns instantly here and starves
there, because the work it is waiting for is queued behind the loop that is
waiting for it.

So: **a green local run is evidence that the logic works on as many threads as
your Mac has. It is not evidence that CI will pass on three.** The lane reports are how you tell the
difference; see [When a run is red](#when-a-run-is-red).

The concurrency width is opt-in with no default, deliberately. Setting
`SWT_EXPERIMENTAL_MAXIMUM_PARALLELIZATION_WIDTH` made the fast lane hang
intermittently at every width tried — 15 of 28 local runs blocked at widths 3,
8, 16, 17, 64 and 256. Until that is understood the width stays unset; see
[`swift-test-helpers.sh:17-45`](../../../scripts/swift-test-helpers.sh).

## Pyramid as applied here

| Layer | What it proves | Where it lives here |
| --- | --- | --- |
| Unit | Focused logic and state transitions in isolation | The paired module test targets: `AgentStudioInfrastructureTests`, `AgentStudioSharedComponentsTests`, `AgentStudioCoreTests`, `AgentStudio<Feature>Tests` |
| Integration | Real interactions across components, storage, process, filesystem, or protocol boundaries | Paired targets for real boundaries (`AgentStudioAppIPCTests`, `AgentStudioIPCTransportTests`, `AgentStudioBridgeDevelopmentServerTests`) and the executable target for cross-Feature composition |
| E2E | A complete journey through the real system from its entry point | `E2ESerializedTests` and `ZmxE2ETests` inside `AgentStudioTests` |
| Smoke | The runnable system starts and performs essential behavior | Packaged and observability proof; see [Observability — Proof Model](../observability/observability_and_traceability.md#proof-model) |

Machine-speed assertions — "p95 under N milliseconds", "this completed in under
a second" — are never a pull-request gate. They belong to the observability
proof lane, where a marker-scoped probe measures a running app against real
telemetry. A timing assertion inside a unit or integration test is a correctness
budget wearing a performance costume, and it fails on a three-core runner for
reasons that have nothing to do with the change under test.

## Test target ownership

Product modules have paired SwiftPM test targets:

```text
AgentStudioInfrastructureTests     ──► AgentStudioInfrastructure
AgentStudioSharedComponentsTests   ──► AgentStudioSharedComponents
AgentStudioCoreTests               ──► AgentStudioCore + AgentStudioTestSupport
AgentStudio<Feature>Tests          ──► matching Feature + lower modules
AgentStudioTests                   ──► AgentStudio executable + product modules
```

`AgentStudioTestSupport` depends only on `AgentStudioCore`. Its sources live at
[`Tests/AgentStudioTests/TestSupport`](../../../Tests/AgentStudioTests/TestSupport) (a nested path under the executable test
folder, a separate SwiftPM target). It provides Core-level fixtures and helpers
without becoming an App or Feature registry. Infrastructure and SharedComponents
tests do not depend on it. Each paired test target owns unit and module-boundary
tests for its product module.

Additional paired targets cover non-Feature modules:
`AgentStudioBridgeDevelopmentServerTests`, `AgentStudioIPCTransportTests`,
`AgentStudioProgrammaticControlTests`, `AgentStudioAppIPCTests`, and
`AgentStudioIPCClientTests`.

The executable-level `AgentStudioTests` target owns App composition,
cross-Feature integration, executable resources, WebKit integration, zmx
integration, and packaged/runtime proof that cannot be expressed by a lower
module test. This ownership does not replace the existing execution lanes:
`mise run test:swift:fast`, `mise run test:swift:large`,
`mise run test:swift:webkit`, `mise run test:swift:e2e`, and
`mise run test:swift:zmx-e2e` retain their filter, serialization, prebuild,
and timeout semantics. `swift test --filter` selects tests to execute; it
does not redefine module ownership or guarantee that unrelated same-package test
products avoid compilation.

## Lanes and why they are split

One owner: the `mise run test:*` tasks and
[`scripts/run-swift-test-task.sh`](../../../scripts/run-swift-test-task.sh),
which dispatches on a mode and sources
[`scripts/swift-test-helpers.sh`](../../../scripts/swift-test-helpers.sh). CI
calls those same mise tasks; it never recreates a raw `swift test` command.

```text
   mise run test                          CI (.github/workflows/ci.yml)
   ─────────────                          ────────────────────────────
   lint, test:architecture,               test:swift:prebuild
   bridge-web, web, vendors                       │
        │                                         ├─► test:swift:fast
   SWIFT_TEST_INCLUDE_E2E=1                       ├─► test:swift:large
   test:swift ──┬─► fast lane                     └─► test:swift:webkit
                ├─► large lane
                ├─► WebKit lane                   (no E2E lane yet — spec R17,
                └─► E2E serialized                 PR 2)
   git diff --check
```

| Lane | Task | What it holds |
| --- | --- | --- |
| fast | `test:swift:fast` | Everything not claimed by another lane, run concurrently inside one process by Swift Testing itself, then the isolated process-global phases |
| large | `test:swift:large` | `Script`, `SourceScan`, `Smoke`, `Integration` families and named heavy suites (`large_non_webkit_filter_pattern`), then a serial phase for subprocess workload fixtures, then its own isolated process-global phase |
| WebKit | `test:swift:webkit` | Real WKWebView runtime suites, one filter at a time. A teardown signal crash fails the lane and the receipt names the suite and signal; the runner never retries |
| E2E | `test:swift:e2e` | `E2ESerializedTests`; inside `mise run test` only when `SWIFT_TEST_INCLUDE_E2E=1` |
| zmx E2E | `test:swift:zmx-e2e` | `ZmxE2ETests`; opt-in, not a pull-request gate |
| benchmark | `test:swift:benchmark` | The two benchmark suites; post-merge, not a pull-request gate |

**Why process-global suites get a process each.** `@Suite(.serialized)`
serializes tests *within one suite*. It does not isolate that suite from the
other suites sharing the process. A suite that touches AppKit, a MainActor
singleton, a shared datastore, or a long-lived bus therefore needs a process of
its own. The inventory comes from two sources unioned in
`aggregate_serial_non_webkit_suite_filters`: a scan for types annotated with
both `@MainActor` and `@Suite(..., .serialized)`, and an explicit list of
`path:Suite` pairs for suites the annotation cannot express (long-lived actors,
live-socket IPC suites). The runner executes one suite per process, at most
`min(ncpu, 4)` at once, against the already-built test bundle through
`swiftpm-testing-helper` — which avoids SwiftPM's shared build-path lock.

**Why SwiftPM `--parallel` is not a substitute.** `--parallel` and
`--num-workers` govern XCTest process fan-out. Xcode 26.3 still runs Swift
Testing through one helper process, so neither flag isolates a Swift Testing
suite. Do not add `--parallel` to the fast inventory; the concurrency there is
Swift Testing's own.

**Why filters are anchored.** Swift Testing matches `--filter` as a regex with
`contains` over a test's id, and a *function's* id ends with its source
location. A bare `RepoScannerTests` therefore also selects
`RepoScannerClassificationTests/gitDirectoryIsCloneRoot()/RepoScannerTests.swift:430:6`
— a different suite that merely lives in a file named after the first. That is
how two process-global suites ended up sharing one process and SIGSEGVing at
exit. `swift_test_isolated_suite_filter_pattern` anchors the type component as
`\.<Type>(/|$)`, so only the type matches.

## How a test may wait

These are the permitted forms. Anything not in the left column is a poll.

| Situation | Permitted form | Forbidden |
| --- | --- | --- |
| State changes and is observable | Await the observed change until a predicate holds | Re-reading the value in a loop |
| A component or test double knows when something happened | Await its event or completion signal | Polling a counter it keeps |
| Delivery on a stream or the bus | Subscribe before the stimulus, then await the specific element | Polling subscriber counts or received arrays |
| Work finishes but announces nothing | Await the owner's quiescence ([Quiescence](#quiescence)) | Yield-and-hope |
| Something must not happen | Await quiescence, then assert once | "Did not happen in N turns/seconds" |
| Time is the behavior | Advance a controlled clock | Waiting in real time |
| None of the above fits | The production owner is missing a signal; add it | Any poll |

**No correctness budgets.** A test must not decide pass or fail by an
elapsed-time budget, a poll count, or a scheduler-turn count. A wait must
complete because a named event, a completion signal, an observed state change,
or a quiescence signal occurred. The test for whether a wait is a budget: *can
it expire while the awaited work is correct and still in flight?* If yes, it is
a budget.

**One hang bound, never tuned.** The only elapsed-time bound permitted in a test
is the runner-owned hang bound: the framework's time limit on the test, and the
lane's own bound against a hung process. If a hang bound expires, the failure
must identify what was being awaited — a `.timeLimit` trait is a hang bound only
when its failure names the thing that never arrived; otherwise it is a budget
with a friendlier name. A hang bound is never raised to make a correct but slow
test pass. A test that needs a larger bound is telling you it violates the
concurrency, waiting, or blocking rule, not that the bound is wrong.

**Time as subject uses a controlled clock.** Where the behavior under test
depends on time — debounce, cadence, backoff, retention — the test drives that
time through a clock it controls and never waits in real time. Use
[`TestPushClock`](../../../Tests/AgentStudioTests/TestSupport/TestPushClock.swift).
If the component reads more than one clock, every clock that can affect the
asserted outcome must be controllable by the test; injecting one clock and
leaving a second real one inside the component is a diagnosed failure family, not
a detail.

**Proving a negative.** To show something does not happen, first await
quiescence of every component that could cause it, then assert once,
synchronously. "It did not happen during a budget" is not "it does not happen".

**No blocking on the cooperative pool.** Test code, and production code
reachable from tests, must not block a cooperative-pool thread on process exit,
a semaphore, a lock held across long work, or synchronous I/O. On three cores
there are three threads; the in-process IPC server answers every accepted
connection from a `Task` on that same pool, so a test blocking there is starving
the server it is waiting on. Route the block through
[`withoutBlockingCooperativePool`](../../../Tests/AgentStudioTests/TestSupport/BlockingWorkOffCooperativePool.swift),
which lands it on libdispatch. `@concurrent` is not a substitute — it still
draws from the cooperative pool. The
`agentstudio_test_blocking_wait_off_cooperative_pool` lint rule enforces this.

## Quiescence

Awaiting quiescence on a component completes only when every unit of work the
component accepted before the await began has finished and been handed to the
next stage, including work buffered for coalescing, debounce, or a later tick.

- **Applied, not delivered.** When quiescence is reported, every effect of that
  work is visible in the state the component publishes. "The consumer has been
  handed the item" is not quiescence.
- **Work accepted during the await.** Quiescence must not complete while such
  work is unfinished if it was caused by the work being awaited. Whether
  unrelated new work extends the await is left to each owner and documented by
  it.
- **Pipelines.** Quiescence of a pipeline holds only when all of its stages are
  quiescent at the same time; a stage finishing can hand work to a stage that
  was already quiescent.
- **Held work versus a standing schedule.** Work already accepted and merely
  held for a coalescing, debounce, or tick window is unfinished work: the
  component is not quiescent. A standing schedule that will generate work in the
  future (a periodic refresh waiting on its next deadline) is not accepted work
  and does not prevent quiescence.
- **Clocks.** A test that controls the component's clock advances it and then
  awaits quiescence. Awaiting quiescence in a test never completes by letting
  real time pass. A component whose held work is released by a clock therefore
  makes that clock controllable by the test.
- **Dropped delivery.** Quiescence covers work a component accepted. An envelope
  that a bounded, lossy subscription discarded was never accepted, so quiescence
  says nothing about it. A test whose outcome depends on delivery across such a
  subscription asserts that the subscription dropped nothing.
- **Shutdown and cancellation.** If the component shuts down, pending awaits
  complete rather than hang. If the awaiting task is cancelled, the await ends
  promptly and leaves no stored waiter behind.
- **Cost.** With no one awaiting, quiescence adds no work to the hot path beyond
  bookkeeping the component already does.
- **Not promised.** That no future work will arrive; ordering across independent
  pipelines; a whole-application idle signal; any exposure over IPC; suitability
  for measuring performance.

### What exists today

These are production contracts, usable by shutdown, not test-only hooks.

| Seam | What "done" means for that owner |
| --- | --- |
| [`RemoteReferenceRefreshActor+ExplicitUpdates.swift:14`](../../../Sources/AgentStudio/Core/RuntimeEventSystem/Git/RemoteReferenceRefreshActor+ExplicitUpdates.swift) `waitUntilIdle()` | No outstanding physical remote-reference work remains; returns immediately when there was none |
| [`RepositoryFactDemandCoordinator.swift:219`](../../../Sources/AgentStudio/App/Coordination/RepositoryFactDemandCoordinator.swift) `waitUntilIdle()` | No delivery task is in flight; with none, it flushes its performance snapshot and returns |
| [`BridgeProductSchemeSessionRouter.swift:116`](../../../Sources/AgentStudio/Features/Bridge/Transport/BridgeProductSchemeSessionRouter.swift) `waitForDrain()` | Every transport claim is gone — zero residue in the router's snapshot |
| [`BridgeProductSchemeSessionRouter.swift:128`](../../../Sources/AgentStudio/Features/Bridge/Transport/BridgeProductSchemeSessionRouter.swift) `waitForStreamClaimDrain()` | Only the metadata-stream claims are gone; deliberately narrower, because a command or content claim can legitimately outlive a stream. Cancellation-safe and lost-wakeup-free |
| [`RepositoryFactUpdateProgress.swift:69`](../../../Sources/AgentStudio/Core/Models/RepositoryFactUpdateProgress.swift) `settled(_:)` | Every applicable fact source has a terminal result; the progress value moves to `.settled` with no unsettled sources |

### Planned (PR 2)

A composed `QuiescenceAwaiting` protocol and an `awaitQuiescence(of:)` helper
that joins several owners into one await. **Not built.** Do not write a test
against it; await the individual seams above, or add the missing signal to the
production owner.

## Harness catalog

Everything in [`Tests/AgentStudioTests/TestSupport/`](../../../Tests/AgentStudioTests/TestSupport), the `AgentStudioTestSupport` target.

| Harness | What it fakes or controls | The wait it enables |
| --- | --- | --- |
| `BlockingWorkOffCooperativePool.swift` | Nothing; it moves blocking work to a libdispatch thread | Lets a test wait on process exit, a semaphore, or a socket read without parking a cooperative thread |
| `TestPushClock.swift` | A `Clock` the test advances by hand | Time as subject: advance, then await quiescence. Never real time |
| `EventBusHarness.swift` | A real `EventBus` with a recording subscriber and an actor-backed buffer | `RecordedEventBuffer` resumes a stored continuation the moment a matching envelope arrives — await the element, not a count |
| `RuntimeEnvelopeHarness.swift` | Typed envelope records for system, worktree, and pane scopes | Assert on the exact fact that was posted |
| `ControllableFSEventStreamClient.swift` | The FSEvents stream client | Tests inject batches explicitly and read registrations, overflow recovery, and activity fences — no OS callback, no waiting for one |
| `PaneRuntimeProviderStubs.swift` | Git working-tree status providers, pathspec-aware or not | The stub's handler is the completion signal |
| `WorkspaceStoreTestAccess.swift` | A `WorkspaceStore` built from explicitly supplied atom owners, including an injected clock and debounce duration | Drives persistence debounce through the injected clock |
| `TestAtomRegistry.swift` | The ambient `CoreAtomScope` for tests | Deterministic Core atom installation; no shared-scope leakage between suites |
| `PaneArrangementStateTestAdapters.swift` | Convenience `Tab` initializers over arrangements | Construction, not waiting |
| `MockTab.swift` | A `ResolvableTab` of pure UUIDs, no NSViews | Construction, not waiting |
| `ModelFactories.swift` | `Worktree`, `Repo`, and peer fixtures | Construction, not waiting |
| `RepoCachePullRequestFactsTestSupport.swift` | Keyed reads and writes of pull-request facts on `RepoCacheAtom` | Construction, not waiting |
| `FilesystemTestGitRepo.swift` | A real on-disk git repository with seeded changes | Real filesystem and git boundary for integration tests |
| `TestPathResolver.swift` | Project-root resolution from `#filePath` | Construction, not waiting |
| `TestResourceInputs.swift` | Resource and BridgeWeb app root URLs | Construction, not waiting |

### Legacy polling helpers — do not add call sites

These exist, they are held by the lint baseline, and they are being converted
under PR 2. Do not call them from new code.

| Helper | Why it is a poll |
| --- | --- |
| `assertEventuallyAsync` ([`EventBusHarness.swift:150`](../../../Tests/AgentStudioTests/TestSupport/EventBusHarness.swift)) | A loop around `Task.yield()` governed by both a `minimumTurns` count and a wall-clock `timeout`. Both are correctness budgets; having two does not make either one a signal |
| `assertEventuallyMain` ([`EventBusHarness.swift:173`](../../../Tests/AgentStudioTests/TestSupport/EventBusHarness.swift)) | The same dual budget for a `@MainActor` condition |
| Per-file `eventually(...)` | Local re-implementations of the same shape |
| `waitUntil(iterations:)` ([`PaneTabViewControllerLaunchRestoreTests.swift:403`](../../../Tests/AgentStudioTests/App/PaneTabViewControllerLaunchRestoreTests.swift)) | A turn budget with the budget in the signature |
| `.timeLimit(...)` used as a budget | A hang bound only when its failure names what was awaited; otherwise a per-test correctness budget |

A `waitUntilStarted()` or `waitUntilReleased()` on a harness is usually **not** a
poll — those are continuation gates resumed by an event. Read the
implementation before classifying a wait by its name; that is also why the lint
rule matches shape and never names.

## Process-global state and isolation

A suite shares process-global state when it touches AppKit, a MainActor
singleton, a shared datastore, or a long-lived bus. Mark it with both
attributes, in either order:

```swift
@MainActor
@Suite("Repo explorer projection", .serialized)
struct RepoExplorerProjectionTests { }
```

`aggregate_serial_non_webkit_suite_filters` discovers that pair and gives the
suite a process of its own. Suites the annotation cannot express — long-lived
actors, live-socket IPC suites — are listed explicitly as `path:Suite` pairs in
the same function.

That explicit half is hand-kept, and a hand-kept list that test correctness
depends on needs a gate, or a member falls out of it silently. The gate is
[`SwiftLaneIsolationListGateTests`](../../../Tests/AgentStudioTests/Scripts/SwiftLaneIsolationListGateTests.swift):
it checks every hand-kept `path:Suite` entry still names a real declaration, and
it re-discovers the annotated suites independently of the shell script's own
patterns, asserting each one lands in some isolated lane. Writing that gate
against the script's output instead would have proved only that the script
agrees with itself.

The lane `--filter` and `--skip` patterns are anchored to the type; see
[Why filters are anchored](#lanes-and-why-they-are-split).

## When a run is red

**A red run is diagnosed, never rerun.** The point of this whole standard is
that a failure means something. Re-running throws away the evidence and the
signal.

1. **Read the lane report.** Every lane prints `[<lane>] lane-report <label>=…`
   before and after its tests: `cpu_count`, `memory_bytes`,
   `parallelization_width`, `isolated_process_concurrency`, `head_sha`,
   `tree_dirty`, then `exit_status`, `wall_seconds`, `cpu_seconds`,
   `cpu_utilization`, `peak_announced_tests`, `peak_running_parameterized_cases`,
   `failed_isolated_suites`, one `failed_isolated_suite=` line per failure, and
   the receipt identity: `head_sha`, `tree_dirty`, `bundle_state`,
   `bundle_identity`, `receipt_valid`, `verdict`. Low utilization with long wall
   time is blocking; high utilization is saturation. `peak_announced_tests` counts
   tests whose start event was *posted*, which is an announcement, not a running
   test, and does not reflect any cap; `peak_running_parameterized_cases` does,
   over the parameterized subset only.

   **A receipt is evidence only when it is valid.** `receipt_valid=true` means
   this invocation's own prebuild built the bundle (`bundle_state=fresh`) and the
   tree was clean from the opening to the closing receipt. A skipped prebuild
   (`reused_bundle`), a failed one (`unbuilt_bundle`), or uncommitted changes
   (`dirty_tree`) make it `receipt_valid=false reason=…`, and its verdict is
   `unverified` whatever the exit status. The exit status is unchanged, so the
   local edit-test loop still works. `bundle_identity` is the bundle path and
   its modification time: two receipts with the same identity tested the same
   build. CI builds in its own `test:swift:prebuild` step, so its lane receipts
   read `reused_bundle` and are linked to that step's receipt by
   `bundle_identity`.
2. **Download the ledger.** On a lane timeout the runner preserves Swift
   Testing's event-stream JSONL under `tmp/plan-workflows/ci-runs/lane-*.events.jsonl`,
   and CI uploads it as `swift-lane-event-streams-<run_id>`. Compute
   started-without-ended per `payload.testID` from the `testStarted`/`testEnded`
   and `testCaseStarted`/`testCaseEnded` records. That ledger is the
   authoritative account of what was in flight. **The console's "unfinished"
   counts lie** — stdio is block-buffered and stops mid-line at a wedge.
3. **Check for signal deaths.** A test process can die of a signal after its
   last flushed line, so the job log shows a passing run and then nothing. CI
   uploads `swift-crash-reports-<run_id>`; traps raised by libdispatch and
   `os_unfair_lock` report through os_log, so the `.ips` "Application Specific
   Information" field is the only place their reason survives.
4. **Reproduce locally with a short hang bound.**
   `SWIFT_TEST_TIMEOUT_SECONDS=90 mise run test:swift:fast`. When a helper is
   parked, `xcrun swift-inspect dump-concurrency <pid>` lists every parked task
   with its resume function. It is unprivileged, and it is the only tool that
   shows suspended tasks — `sample` cannot. The runner takes this dump itself
   when the hang bound fires, for each sampled test process and before anything
   is terminated. It keeps the dump beside the ledger as
   `lane-*-pid<pid>.task-dump.txt`, and CI uploads it with the ledgers. When the
   tool cannot attach, the receipt says `task_dump=unavailable reason=…`. It
   cannot attach to a binary without `get-task-allow`, and `swift-inspect` exits
   0 even then, which is why the runner judges success by the dump's content.
5. **Classify the owner, then fix it there.** Test oracle (the assertion is
   wrong about what should happen), product (the behavior is wrong), runner
   (the lane, filter, or isolation is wrong), or harness (the fake is wrong).
   Fixing the wrong owner is how a family comes back.

**Forbidden responses to a red run:** rerunning the job; raising a budget or a
hang bound; skipping the test; quarantining it; bumping a `.timeLimit`; removing
an assertion without a replacement that states the invariant at least as
strongly.

## Workarounds and hand-kept lists

A version pin or a note that exists for a workaround must state the condition
under which it is removed, and must be removed once that condition is met.

A hand-maintained list that test correctness depends on — the set of suites that
need process isolation, the lint baselines — must be verified by a gate, so that
a member cannot silently fall out. The isolation list has
[`SwiftLaneIsolationListGateTests`](../../../Tests/AgentStudioTests/Scripts/SwiftLaneIsolationListGateTests.swift).
The polling baseline, `ArchitectureAllowlists.pollingWaitKnownDebt`, is
shrink-only: a file outside it that polls fails the gate, a file inside it
that no longer polls fails the gate until its entry is removed, and a listed
path that no longer exists fails the gate until its entry is removed.

## BridgeWeb

**Cold start is outside the measured window.** A BridgeWeb E2E journey's bounded
steps must not include Vite dependency-optimizer cold start, and a retry must not
repeat a cost that made the first attempt fail. Each live Vite server still owns
its own cache directory; sharing one is how two servers optimize over each
other's dependencies.

**Waits are condition-driven and declared.** A BridgeWeb wait completes because
an application event or a DOM condition occurred. Its time bound is a hang
bound: `testTimeout` is declared once in shared configuration, never left to an
undeclared library default, and never tuned per test to obtain a pass. An awaited
animation is driven to completion by the test or has its cancellation handled;
it is never awaited unbounded or uncaught.

See [`BridgeWeb/AGENTS.md` — Test Waits](../../../BridgeWeb/AGENTS.md#test-waits).

## Key files

| File | Role |
| --- | --- |
| [`scripts/run-swift-test-task.sh`](../../../scripts/run-swift-test-task.sh) | Lane entry point: mode dispatch, hang-bound defaults, lane report |
| [`scripts/swift-test-helpers.sh`](../../../scripts/swift-test-helpers.sh) | Lane inventories, isolation discovery, anchored filters, watchdog, timeout diagnostics |
| [`.mise.toml`](../../../.mise.toml) | `test`, `test:swift*`, `test:architecture` task definitions |
| [`.github/workflows/ci.yml`](../../../.github/workflows/ci.yml) | The CI steps that call those same mise tasks, and the failure artifacts |
| [`TestPollingWaitRule.swift`](../../../Tools/AgentStudioArchitectureLint/Sources/AgentStudioArchitectureLintCore/Rules/TestPollingWaitRule.swift) | `agentstudio_no_polling_wait_in_tests` |
| [`TestBlockingWaitOffCooperativePoolRule.swift`](../../../Tools/AgentStudioArchitectureLint/Sources/AgentStudioArchitectureLintCore/Rules/TestBlockingWaitOffCooperativePoolRule.swift) | `agentstudio_test_blocking_wait_off_cooperative_pool` |
| [`TestTaskSleepRule.swift`](../../../Tools/AgentStudioArchitectureLint/Sources/AgentStudioArchitectureLintCore/Rules/TestTaskSleepRule.swift) | `agentstudio_no_task_sleep_in_tests` |
| [`ArchitectureAllowlists.swift`](../../../Tools/AgentStudioArchitectureLint/Sources/AgentStudioArchitectureLintCore/Paths/ArchitectureAllowlists.swift) | `pollingWaitKnownDebt` and `blockingTestWaitKnownDebt` baselines |
| [`Tests/AgentStudioTests/TestSupport/`](../../../Tests/AgentStudioTests/TestSupport) | The `AgentStudioTestSupport` harnesses |
| [`SwiftLaneIsolationListGateTests.swift`](../../../Tests/AgentStudioTests/Scripts/SwiftLaneIsolationListGateTests.swift) | The isolation-list gate |
| [CI Reliability — Specification](../../specs/2026-09-17-ci-reliability/2026-09-17-ci-reliability.md) | The requirements this document implements |
