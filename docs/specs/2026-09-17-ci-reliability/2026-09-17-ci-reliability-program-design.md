# CI Reliability — Program Design

How the repository satisfies the [Specification](2026-09-17-ci-reliability.md) (`R`, `C`, `V` identifiers resolve
there). Needs and boundary are in the [Requirements](2026-09-17-ci-reliability-requirements.md). Source anchors are
current as of `origin/main` `bc7cad5f8`; evidence reports are under
[`docs/wip/2026-09-17-ci-reliability-evidence/`](../../wip/2026-09-17-ci-reliability-evidence/).

## How it works, in one view

Four layers. Each removes one way the machine leaks into a test result. They are ordered by dependency: a layer is
only trustworthy once the one above it holds.

```text
┌─ 1. RUNNER ──────────────────────────────────────────────────────────┐
│ bound how many tests execute at once; report the load  (R1, R2)      │
│ owner: test lane runner + CI workflow                                │
└──────────────────────────────────────────────────────────────────────┘
┌─ 2. THREADS ─────────────────────────────────────────────────────────┐
│ nothing blocks a cooperative-pool thread  (R8)                       │
│ owner: each call site that waits on a process, semaphore, or file    │
└──────────────────────────────────────────────────────────────────────┘
┌─ 3. SIGNALS ─────────────────────────────────────────────────────────┐
│ production says "done": quiescence per owner, composed per pipeline  │
│ (R6, R7, C3)   owner: the component that does the work               │
└──────────────────────────────────────────────────────────────────────┘
┌─ 4. WAITS ───────────────────────────────────────────────────────────┐
│ tests await events, observed state, or quiescence; never poll        │
│ (R3-R6, C2)    owner: test support + the lint gate (R11, C4)         │
└──────────────────────────────────────────────────────────────────────┘
        beside them: BridgeWeb harness (R14-R16), standard + hygiene (R10, R12, R13)
```

## What exists today

| Area | Current behavior | Anchor |
| --- | --- | --- |
| Toolchain | CI downgrades the runner's default Xcode 26.6 to 26.3 in five places, and two architecture-lint cache keys hard-code the same version. 26.3's Swift Testing has no parallelism cap. 26.6's has one, but it is off unless `SWT_EXPERIMENTAL_MAXIMUM_PARALLELIZATION_WIDTH` is set: a CI run on 26.6 without it measured the same fan-out as 26.3. The cap gates test-case bodies; a test's start event and its reported duration both precede the cap, so neither shows whether it is working, while the framework's time limit starts after it. The pin worked around zig 0.15.2; the repository is on zig 0.16.0 | `ci.yml:30,46,48,153,274`; `benchmarks.yml:35`; `release.yml:32`; `agent_resources.md:139`; `.mise.toml` |
| Lane execution | One test process per lane run; isolated suites run one per process, four at a time, on a 3-vCPU runner. `--num-workers` is inert for Swift Testing | `scripts/run-swift-test-task.sh`; `scripts/swift-test-helpers.sh`; `lane-swift-runner-starvation.md` |
| Lane hang bound | An output-inactivity watchdog. The same variable defaults to 90 s in one script, 1200 s in `.mise.toml`, and is set to 1200 s in CI; a silent cold compile is killed locally | `run-swift-test-task.sh:20-21`; `.mise.toml:330-331,393`; `ci.yml:384-408` |
| Isolation list | Suites needing process isolation are partly auto-discovered and partly a hand-kept list; one suite is missing beside its listed sibling | `swift-test-helpers.sh:165-167` |
| Waiting | 123 polling helpers, 678 call sites, 162 inline loops. Two shared helpers cover 225 sites | `polling-wait-survey.md`; `Tests/AgentStudioTests/TestSupport/EventBusHarness.swift:150,173` |
| Event-driven doubles | 380 stored-continuation declarations in 122 test files; a reusable recorder already exists | `Tests/AgentStudioTests/Helpers/WorkspaceSurfaceCoordinatorTestHelpers.swift` (`ExactEventAcknowledgement`) |
| Production completion signals | Two quiescence contracts already exist, each with its own hand-rolled waiter array, and both are used by shutdown. The second one's predicate (`deliveryTask != nil`) ignores input held behind a cancelled deadline task, so it is checked against C3 rather than copied. Other completion signals exist but are discarded or miss a path | `RemoteReferenceRefreshActor+ExplicitUpdates.swift:14`; `RepositoryFactDemandCoordinator.swift:212-227`; `WorkspaceCacheCoordinator.swift:293,305,348` (`_ = governor.enqueue`) |
| Bus accounting | A subscriber's `consumedCount` advances when an envelope is pulled, before it is handled | `EventBus.swift:90-94` |
| BridgeWeb E2E | Each fixture gets a fresh Vite cache directory, so the optimizer is cold on every attempt and retry | `bridge-viewer-vite-product-fixture.ts:159,454` |
| Dev-host handoff | An initial bootstrap is refused unless the live session's metadata producers already have retirement barriers; a stream's end reaches the host through task cancellation, asynchronously | `BridgeDevelopmentProductHost.swift:848-881`; `BridgeSchemeHandler+RPC.swift:96-104` |

Constraint degree: compatibility-bound for tests (proof strength preserved), platform-bound for the toolchain,
legacy-ownership-bound for waiting (hundreds of private helpers).

## Structural decisions

| # | Decision | Chosen | Why this is enough | Cost, and who pays | Reopen if |
| --- | --- | --- | --- | --- | --- |
| D1 | How to bound concurrent tests | Move CI, benchmarks, and release to the runner's default Xcode and set the width explicitly in the lane runner | The cap exists in 26.6 and the pin blocking it is obsolete, but the cap only takes effect when the width is set, so setting it in the lane runner is the fix itself, not tuning. No new mechanism. The owner decided the release workflow moves in the same change | An `EXPERIMENTAL` environment variable; the test-topology owner re-checks it on each toolchain bump. Swift 6.3.3 compiles the app cleanly with 185 new warnings, and rejects test code in two files so far: three data-race captures in `BackgroundFactApplyGovernorTests` and one `#expect` too complex to type-check in `PreparedBridgeMountTopologyBoundaryTests`. Compilation stops at the first failing module, so the list may grow | Test bundles do not compile on 26.6, or the lane report shows the width is not honored. Fallback: shard the fast inventory across processes in `run-swift-test-task.sh` |
| D2 | Shape of quiescence | Each owner exposes its own `waitUntilIdle()`, following the existing `RemoteReferenceRefreshActor` contract; a pipeline is awaited by composing its stages to a fixed point | Owners already know when they are idle; four of seven already have most of the signal. No global registry, no whole-app idle | One small shared protocol and one waiter-storage helper in Infrastructure. Each owner maintains its idle predicate when it adds a buffer | A second component needs whole-application idle, or owners' predicates drift from their buffers repeatedly |
| D3 | How the bus knows it is idle | Leave every existing counter alone. Track, per subscriber, whether its iterator is suspended waiting for the next envelope. The bus is idle when every live subscriber has pulled everything yielded to it and is suspended | A subscriber between pulling an envelope and asking for the next one is handling it, so it is visibly not idle; no consumer changes and no diagnostic changes meaning | The suspended mark is recorded without an extra hop to the bus actor; the bus is notified of a change only while something is awaiting it. A subscriber that stops iterating ends its stream and is removed, so it cannot hold the bus busy | A consumer hands an envelope to background work without owning its own quiescence |
| D4 | Where test waits live | One set of primitives in `AgentStudioTestSupport`; every private polling helper is deleted | 74% of sites need only two primitives (observed state; signalling double) | A wide mechanical change across about 120 test files | — |
| D5 | How polling is kept out | A rule in `Tools/AgentStudioArchitectureLint`, with a shrink-only baseline during conversion | The gate already runs in `mise run lint`, `mise run test`, and CI | A baseline file exists until conversion finishes; R18 is not met while it is non-empty | The rule produces false positives that reviewers start suppressing |
| D6 | Vite cold start | Warm one throwaway server into a seed cache before any journey clock starts; each fixture copies the seed into its own cache directory | Vite accepts a copied cache: validity is lockfile and config hash, paths in `_metadata.json` are relative, the commit is an atomic rename | Warm-up must load the same surfaces the journeys load, or a runtime-discovered dependency still forces a re-optimize | Vite changes cache validity to include the cache path |
| D7 | Isolation membership | Keep the existing lists. Add a gate that fails when a listed suite no longer exists or is no longer matched by its filter; add the missing visible-tier suite to the list. Same gate for the WebKit suite list | R13 asks that a member cannot silently fall out; a rename or deletion is how that happens, and the gate catches it without rewriting the file that owns test topology | A new suite that needs isolation is still added by hand | A suite that needed isolation is again found running in the concurrent lane |
| D8 | Lane hang-bound defaults | The test script's built-in defaults become the values CI and the aggregate task already set | The instructions that tell agents to raise this timeout after edits exist only because the bare default kills a silent cold compile; R12 removes that instruction, so the default it compensated for has to be sane. No new mechanism | None | A hang is ever mistaken for slow progress again; then measure child CPU progress instead of output bytes |
| D9 | Dev-host handoff | `BridgeProductSchemeSessionRouter`, the existing claim-lifetime owner on every path, holds a nonisolated lock-protected census of stream-route scheme tasks. The scheme handler marks a task terminated in it, synchronously, inside `onTermination`. An initial bootstrap that finds a producer lease with no retirement state consults the census: if any stream is still live it is refused at once; if every stream has terminated it joins the router's stream-claim drain, then re-evaluates the existing barriers and still refuses a failed retirement. Every refusal is typed. A second session requested while the client's first is genuinely still open is refused; the worktree-data integration test that did so closes its first surface first. The Review replay test already closes its first stream and is not changed | `BridgeProductSession` and the router are actors, so a synchronous termination callback cannot record state in either; a lock box hanging off the router is the one place the fact can be written at that instant. The join already exists: the router's drain resolves only after the reply task has finished retiring its producer, and the real app's reload path already uses it. "Live" is today approximated by "a lease exists", which is also true of a dead document until its reply task unwinds; the census records the fact itself. Joining a drain needs no clock | One small lock-protected type beside the router; the scheme handler must finish its census entry on every exit path. Census and join are scoped to stream-route claims, or a live content stream would turn the join into a hang | A supported use needs two concurrent sessions from one client |

Rejected: a larger runner (hides every defect, and the large macOS runner is Intel); sharding the 4,900-test fast lane
as the primary bound (about 2 s of process start per helper, and it leaves polling in place); a test-only scoping
trait that throttles tests with a semaphore (a second concurrency system beside the framework's own); a global
quiescence registry (a new ambient lookup, against the repository's composition rules); retaining any deadline-based
`eventually` (it is still a correctness budget, R3).

## Components

```text
Infrastructure
  QuiescenceAwaiting            protocol: waitUntilIdle(), acceptedWorkGeneration
    consumers: owners below, test support, shutdown paths
    changes when: the meaning of "idle" in C3 changes
  IdleWaiters                   stored waiters; cancellation-safe; resumes all when told idle
    consumers: every owner that implements QuiescenceAwaiting
    changes when: waiter storage or cancellation semantics change

Owners that gain or complete quiescence (each: owns its own idle predicate)
  EventBus                          Core    idle = every subscriber pulled everything and is suspended (D3)
  BackgroundFactApplyGovernor       App     idle = nothing pending, no drain in flight
  WorkspaceCacheCoordinator         App     idle = its subscription drained AND its governors idle
  GitWorkingDirectoryProjector      Core    idle = no pending changesets, no worktree task, no held admission
  RepoExplorerProjectionAdapter     Feature idle = no pending invalidation, no invalidation task, projection settled
  TerminalActivationScheduler       Feature idle = nothing queued or attaching, no supplemental drain in flight
  BridgePaneRefreshAdmissionCoordinator  Feature idle = no active pass, no retained dirty fact
  Pane-agent IPC server             App     conditional: only if the family persists once R8 is applied
  DarwinFSEventStreamClient         Core    existing activity fence; callers stop discarding it

Test support (AgentStudioTestSupport)
  awaitObserved                 await @Observable MainActor state until a predicate holds
  EventRecorder                 generalizes ExactEventAcknowledgement; doubles signal instead of counting
  awaitFact                     subscribe to a bus, then await one matching envelope
  awaitQuiescence               fixed-point composition over [QuiescenceAwaiting]
  AwaitedDescription            names what is being awaited, for hang reports (R4)

Tooling
  ArchitectureLint rule         no polling waits under Tests/, with shrink-only baseline (D5)
  lane runner                   width, preflight, lane report, sane default bounds (D1, D8)
  isolation list gate           listed suites must exist and match their filter (D7)

BridgeWeb harness
  Vite seed cache               vitest global setup warms once; fixtures copy (D6)
  animation settle              one helper; the unbounded sibling is deleted
  explicit poll bound           one declared hang bound in shared config (R15)

Development host and scheme handler
  terminated-stream census (router); bootstrap joins the router's stream-claim drain; typed refusals (D9)
```

Dependency direction follows the repository's import rule: the protocol and helper live in Infrastructure; Core, App,
and Feature owners conform; test support depends on Core. No Feature learns about another Feature. Forbidden: a
production type reading test support; a quiescence API compiled only in debug; an owner's idle predicate implemented
outside the owner; a second waiting convention in tests. The lint gate enforces the last; code review and the
existing import lint enforce the rest.

## Interfaces

### `QuiescenceAwaiting`

Owner: the conforming component. Consumers: tests, shutdown, pipeline composition.

- `waitUntilIdle() async` — returns when the owner's idle predicate holds. If it already holds, returns without
  suspending. If the owner is shut down, returns. If the awaiting task is cancelled, returns promptly and removes its
  waiter. Never throws.
- `acceptedWorkGeneration` — a counter the owner advances each time it accepts a unit of work. Monotonic. Read by
  pipeline composition to detect work that arrived during a pass.
- An owner marks a unit finished only after it has handed the result on and the next stage has accepted it
  (`await bus.post` returned; `governor.enqueue` returned; the MainActor commit ran). This is what makes "work is always
  accounted for in at least one stage" true.
- Not provided: ordering across owners, a promise that no work arrives later, a timeout.

Representative use, a test proving a negative:

```swift
await bus.post(unrelatedEnvelope)
await awaitQuiescence(of: [projector, bus, cacheCoordinator])
#expect(repoCache.repoEnrichmentByRepoId[repo.id] == nil)   // asserted once
```

### `IdleWaiters`

A value the owner holds inside its own isolation (actor state, or under the owner's existing lock). Operations: add a
waiter, remove a waiter by identity on cancellation, take all waiters. The owner calls "take all and resume" at every
point its idle predicate can become true; resumption happens outside any lock. It owns no policy: it never decides
what idle means.

### Idle predicates per owner

| Owner | Idle means | Work buffered inside it today | Already has |
| --- | --- | --- | --- |
| `EventBus` | Every live subscriber has pulled everything yielded to it and its iterator is suspended | Per-subscriber stream buffers | Yielded and consumed counters, unchanged; the suspended mark is new (D3) |
| `BackgroundFactApplyGovernor` | `pendingByKey` empty and no drain turn in flight, including its last MainActor commit | Pending facts under its lock; tick stream; carried facts | Per-fact `Acknowledgement`; `flushPending()` |
| `WorkspaceCacheCoordinator` | Its bus subscription is drained, no direct consume is in flight, and both governors are idle | The detached consume loop; two governors | Calls `flushPending()` before direct consumes |
| `GitWorkingDirectoryProjector` | No pending changesets, no in-flight worktree task, no visibility admission held for its window, **and no changeset deferred behind a status backoff or a capacity retry**; a parked periodic deadline does not count | `pendingByWorktreeId`; `worktreeTasks`; visibility admission task; `deferredStatusBackoffChangesetByWorktreeId`; `capacityRetryWorktreeIds` | Nothing awaitable. Its deferred work is released by its deadline clock, which tests already inject and must advance |
| `RepoExplorerProjectionAdapter` | No pending invalidation, no invalidation task, projection has no unsettled tasks, a result is published | `pendingInvalidation`; single `invalidationTask` | The same predicate, written as a poll in a sibling test |
| `TerminalActivationScheduler` | No queued or attaching member and no supplemental drain in flight | Worker fleet; an untracked supplemental `Task` | `activate()` covers startup only; the supplemental drain becomes tracked |
| `BridgePaneRefreshAdmissionCoordinator` | No active refresh pass and no retained dirty fact | Pending/dirty fact; active pass | A sibling `awaitRetiringFileOperations()` of the right shape |

The predicates above are a starting inventory, not the contract. The contract is C3: every place an owner can hold
accepted work counts. Each owner's seam is therefore built from an audit of that owner's buffers, and its proof
includes the buffers found. A seam is added only when a diagnosed family's corrected test needs it.

The FSEvents client needs no new signal: it keeps its existing activity fence, and the exact-item fixture awaits the
fence it currently acknowledges and discards. The pane-agent server is conditional. Its family's blocking wait is
verified; that the blocking wait is the cause is not. R8 is applied first. Only if the family persists does the
server gain an awaitable terminal disposition per bootstrap.

Adding these seams is a new responsibility on each owner. The repository requires the owner's approval for new
coordinator responsibilities; approval was given for quiescence seams as a class (U6), and the list above is the
concrete set it applies to.

### Test waiting primitives

| Primitive | Replaces | Behavior |
| --- | --- | --- |
| `awaitObserved(_ read, until:)` | Category A: 327 sites | Iterates `Observations { read() }` on the MainActor and returns the first value satisfying the predicate, checking the current value first. No re-arm bookkeeping of its own, so it cannot leak trackings |
| `EventRecorder<Event>` | Category B: 177 sites | A double records an event; `next(where:)` returns a recorded match or suspends until one arrives. Replaces counters read in a loop |
| `awaitFact(on:where:)` | Category C: 71 sites | Subscribes before the stimulus runs, returns the first matching envelope |
| `awaitQuiescence(of:)` | Yield-and-hope; negative waits | Repeats: read generations, await every stage idle, read generations; stops when a full pass saw no generation change |
| Stream element await | Category D: 51 sites | `for await` on the real callback stream; no helper needed |
| `AwaitedDescription` | — | Every primitive takes a description. When the awaiting task is cancelled (the runner's hang bound fired), the primitive records an issue naming the description and, for `awaitQuiescence`, which stage was not idle |

Category E (27 AppKit and SwiftUI view-state sites) has no single primitive. Each is resolved against the view's own
signal (layout completion, first responder change notification, or an observed model value); where none exists the
site is triaged individually during conversion. Category G (22 sites) is triaged the same way.

### Lane runner

Before tests: print CPU count, memory, width, process count; verify vendor inputs (the Ghostty header and
XCFramework) exist and fail by name if not. Run the lane under `/usr/bin/time -l`. After tests: print wall, CPU, and
utilization. The width is `min(2 x CPU, a policy ceiling)`; isolated-suite process concurrency becomes the CPU count
rather than a constant four. The script's built-in hang-bound defaults equal the values CI sets (D8).

### Polling-wait lint rule

Flags, under `Tests/`: a `for`, `while`, or `repeat` whose body contains `Task.yield()`, `Task.sleep`, or a comparison
against a clock's `now`; and any parameter named for a turn or yield budget. Reports file, line, rule identifier, and
the standard's path. Baseline: a checked-in list of files; the rule fails on a violation outside it and on a listed
file with no violation.

## Call paths, current and proposed

### A test waits for the cache pipeline

```text
CURRENT                                         PROPOSED
test ── post ─► EventBus                        test ── post ─► EventBus              (unchanged)
test ── loop: read atom, Task.yield x100        test ── awaitQuiescence([projector,   (changed)
        (gives up after 100 turns)  [removed]            bus, coordinator])
                                                  ├─► projector.waitUntilIdle()        (added)
projector (actor) ── await bus.post             │     idle only after bus.post returned
EventBus ── yield ─► subscriber stream          ├─► bus.waitUntilIdle()               (added)
  consumedCount++ at pull (unchanged)           │     idle only when every subscriber is suspended
coordinator (detached) ── next()                └─► coordinator.waitUntilIdle()       (added)
  ── _ = governor.enqueue(...)     [changed]          subscription drained + governors idle
governor ── tick ─► MainActor commit                 governor idle after MainActor commit
atom write (MainActor)                          test ── assert once                   (changed)
result: expectation fails under load            result: returns when applied; hang bound only on a real hang
```

Evidence: `WorkspaceCacheCoordinatorIntegrationTests.swift:108-116` (the failing call site, default budget of 100 turns; helper at `:820-834`), `WorkspaceCacheCoordinator.swift:115-170`,
`EventBus.swift:90-94`, `BackgroundFactApplyGovernor.swift:152-205`. Unchanged and preservation-critical: the
coordinator still flushes governors before a direct consume (ordering), and the governor's tick and coalescing
behavior is untouched; idle is observed, never forced.

### A hidden pane during a storm

Unchanged production path. Changed assertion only: the test stops comparing total metadata sequence
(`BridgeProductRealGitFileAndReviewWebKitTests.swift:158-162`) and compares the pane, file, and review product-frame
deltas its proof already computes. Preservation-critical: `BridgeProductSession.swift:583-586` continues to admit the
protocol lifecycle frame with the control completion, independent of pane visibility.

### Stream end to successor bootstrap, in process

```text
CURRENT                                          PROPOSED
consumer cancelled                               consumer cancelled
 ─► continuation.onTermination (sync closure)     ─► continuation.onTermination (sync closure)
      ─► task.cancel()                                 ─► mark stream terminated, keep its reply task   (added;
                                                          scheme handler's lock, not the session actor)
                                                       ─► task.cancel()                                 (unchanged)
 ... reply task scheduled later ...               ... reply task scheduled later ...
 ─► pump.cancel()                                  ─► pump.cancel()                                     (unchanged)
 ─► session.beginProducerRetirement()              ─► session.beginProducerRetirement()                 (unchanged)
 ─► transportClaim.finish()                        ─► transportClaim.finish(); clear the record         (changed)

successor: issueBootstrap(.initial)              successor: issueBootstrap(.initial)
 ─► validateBootstrapTransition                    ─► validateBootstrapTransition
 ─► metadataRetirementBarriersForReload()          ─► metadataRetirementBarriersForReload()
      nil while the hop is pending                      nil AND stream marked terminated                (added)
      ─► throw sessionAlreadyOpen  [removed          ─► await that reply task's completion
                                    for this case]      ─► re-read barriers ─► await them ─► granted
                                                       nil AND stream NOT terminated
                                                        ─► typed refusal: live session in use           (changed: typed)
```

Evidence: `BridgeSchemeHandler+RPC.swift:96-104` (termination only cancels the task), `BridgeProductSession.swift:8`
(actor), `BridgeProductSchemeFramePump.swift:130-137`, `BridgeProductSession.swift:304-317`,
`BridgeDevelopmentProductHost.swift:848-881`. Preservation-critical: a genuinely live session still refuses a second
initial request. The test-side deadline poll written for this during diagnosis is not part of the design.

### CI lane

```text
CURRENT                                   PROPOSED
select Xcode 26.3            [removed]    use runner default Xcode, version printed
swift test (unbounded fan-out)            swift test with explicit width               (changed)
isolated suites x4 processes              isolated suites x CPU-count processes        (changed)
no load report                            preflight + time -l + lane report            (added)
hand-kept isolation list                  same list, verified by a gate                (changed)
```

## Instruction and tooling corrections

What R10, R12, and R13 change, from the audit in `lane-instructions-and-config-audit.md`. Each row is an existing
surface that today teaches, permits, or hard-codes a pattern the standard forbids.

| Surface | Today | Becomes | Anchor |
| --- | --- | --- | --- |
| Sleep-only lint rule | Errors on `Task.sleep` in tests and says "wait for explicit events", but detects nothing else; yield loops replaced sleeps and stayed invisible | Joined by the polling-wait rule (D5), shipped together with the primitives so the rule names an alternative that exists | `Tools/AgentStudioArchitectureLint/.../TestTaskSleepRule.swift` |
| Blocking-I/O lint rule | Severity `report`; cannot fail a build | Severity `error`, once the existing violations are fixed (R8) | `.../NonisolatedAsyncBlockingIORule.swift:5` |
| Workflow test asserting the pin | `CIFastLaneWorkflowTests` requires a step named for Xcode 26.3 and that version string | Asserts the toolchain step's contract without naming a version that a workaround chose | `Tests/AgentStudioTests/Scripts/CIFastLaneWorkflowTests.swift:34-44` |
| Xcode and zig workaround notes | Nine sites keep the 26.3 workaround alive after its stated removal condition was met | Deleted; the doctor script's baseline updated | `README.md`; `docs/guides/agent_resources.md:30,139`; `scripts/doctor-mac.sh`; workflows, including the architecture-lint cache key and restore key at `ci.yml:46,48` |
| "No Wall-Clock Tests" | Forbids `Task.sleep`; silent on scheduler-turn loops and dual turn-and-time budgets | Names them as forbidden and points to the standard | root `AGENTS.md` |
| Fast-lane concurrency rule | Says concurrency is left to Swift Testing; written for a toolchain with no cap | States the explicit width and why `--parallel` and `--num-workers` are not used | root `AGENTS.md` |
| `SWIFT_TEST_NUM_WORKERS` plumbing | Passed by script and CI; inert for Swift Testing | Deleted | `scripts/swift-test-helpers.sh`; `ci.yml` |
| Timeout guidance for agents | Tells agents tests finish in about 15 s and to use a 60 s timeout; elsewhere to raise a timeout after edits | Removed; the script's default bound is made sane instead (D8) | `docs/guides/agent_resources.md` |
| Hook claim | Says a `.claude/hooks/check.sh` hook formats Swift after edits; no such hook exists | Removed, or the hook is restored; the instruction matches reality either way | root `AGENTS.md` |
| WebKit suite list | A hand-kept filter list; a WebKit suite absent from it runs in no lane and CI stays green | Verified by the same gate as isolation membership (D7) | `scripts/swift-test-helpers.sh` |
| CI versus the local gate | `mise run test` runs the serialized E2E lane; CI never does, while instructions describe it as gated | The lane is added to CI in the second pull request, by the owner's decision. Removing it from the local gate would delete a proof gate and is not an option | `.mise.toml`; `ci.yml` |
| BridgeWeb E2E `retry: 1` | Repeats the cold cost that failed the first attempt | Deleted once the seed cache lands (R14) | `BridgeWeb/vitest.e2e.config.ts` |
| WebKit lane retry on helper crash | Retries when the test helper crashes during teardown after assertions pass | Kept for now and recorded as debt: it masks a real teardown crash | `scripts/swift-test-helpers.sh` |

## State

`IdleWaiters` inside an owner:

| State | Event | Next | Guard or note |
| --- | --- | --- | --- |
| idle, no waiters | work accepted | busy | generation advances |
| idle | `waitUntilIdle()` | idle | returns immediately |
| busy | `waitUntilIdle()` | busy, waiter stored | — |
| busy, waiters | last unit handed on | idle | take all, resume outside the lock |
| busy, waiters | awaiting task cancelled | busy | that waiter removed and resumed; others stay |
| any | owner shut down | closed | take all, resume; later awaits return immediately |

Illegal: resuming a waiter twice (prevented because "take all" and "remove by identity" both remove before resuming);
resuming while holding the governor's lock.

Polling baseline: `seeded` (every currently violating file listed) → `shrinking` (entries only leave) → `empty` → file
and baseline support deleted. No entry may be added after seeding.

## Failure, cancellation, and concurrency

| Situation | Behavior | Owner |
| --- | --- | --- |
| Awaited work never finishes (a real bug) | The runner's hang bound cancels the test; the primitive records what was awaited and which stage was busy | Test support |
| Pipeline never quiet because a periodic source keeps producing | A standing schedule is not accepted work (C3); if a stage still never idles, that is reported as above and is a test-design error, not masked by a budget | Test author |
| Owner shuts down while awaited | Waiters resume; the test proceeds to its assertion and fails there if state is wrong | Owner |
| Waiter cancelled concurrently with idle | Both paths remove-then-resume under the owner's isolation; exactly one resumes | `IdleWaiters` |
| Work arrives at a stage already observed idle in this pass | Its generation advanced, so `awaitQuiescence` runs another pass | Test support |
| Governor enqueue races its drain | Unchanged; idle is evaluated after the drain's MainActor commit under the existing lock | Governor |
| Vite seed warm-up fails | The E2E lane fails before any journey, naming the warm-up; no journey runs cold by accident | Vitest global setup |
| Seed misses a runtime-discovered dependency | Vite re-optimizes and reloads; the lane report for that journey shows it. The warm-up surface list is corrected; no retry is added | BridgeWeb harness owner |
| A lossy subscription drops envelopes during a burst | Quiescence is silent about them (C3). The test reads the bus's existing per-subscriber drop count and asserts zero; no new drop machinery | Test author |
| Vendor input missing in CI | Lane fails in preflight by name | Lane runner |

No new retry or time budget is introduced anywhere in this design. The one new lock guards the router's
terminated-stream census (D9).

## Cross-cutting realization

| Obligation | Realization |
| --- | --- |
| No hot-path cost without an awaiter | Owners already track their buffers; the additions are one integer increment per accepted unit and one empty-array check when a unit finishes |
| Lane wall time stays explainable | The lane report gives utilization before and after; isolated-suite concurrency drops from four to the CPU count |
| Observability | Log lines only; nothing new is exported over OTLP |
| Security of handoff | The handoff change is in-process; any "same viewer" proof is deferred with the open decision and would reuse the session capability the client already holds, never a new credential |
| Compatibility | Benchmarks and release workflows move with CI in the same change; the stale Xcode note is deleted, not amended |

## How each requirement is realized and proven

| Requirement | Realized by | Proof seam | Real or replaced |
| --- | --- | --- | --- |
| R1, R2 | Lane runner, workflows | CI log of a real run | All real |
| R3, R11 | Test primitives; lint rule | Lint unit tests with seeded violations; lint on the tree | Real sources |
| R4 | `AwaitedDescription` | A test that awaits a never-firing event under a short suite time limit and asserts the recorded issue text | Real framework time limit |
| R5 | Second clock injected into the projector; tests advance it | Visible-tier suite with both clocks controlled | Clocks replaced, projector real |
| R6, R7, C3 | `QuiescenceAwaiting` on each owner | Per owner: not idle while buffered or in flight; idle after publish; resumes on shutdown; cancellation leaves no waiter. Pipeline: real projector, bus, coordinator, governors | Git status provider stubbed; everything else real |
| R8 | Blocking waits moved off the pool | Pane-agent helper test; lane utilization | Real child process |
| R9 | The per-family table below | Corrected test; deterministic reproduction where one exists | Per family |
| R10, R12, R13 | Standard document; instruction and config corrections; isolation and WebKit list gate | Audit checklist; a gate test that every listed suite exists and is matched by its filter | Real scripts |
| R14 | Seed cache | CI log: no optimizer cold start inside a bounded step | Real Vite, real backend |
| R15 | One animation-settle helper; explicit poll bound | Browser tests | Real browser |
| R16, C5 | Terminated-stream census on the router; bootstrap joins the router's stream-claim drain; typed refusals | Swift replay suite; integration through the real development server | All real |
| R18 | — | Ten consecutive first-attempt green runs with lane reports; empty baseline | Real CI |

### Each failure family, and what fixes it

| Family | Fixed by | Pull request |
| --- | --- | --- |
| File source context leak | `open` owns one release boundary around `bootstrapInstalledContext`; a test invalidates admission from the acceptance observer. Present on this branch | 1 |
| Hidden pane admits a frame | Assertion compares product-frame deltas, not total sequence | 1 |
| Cache coordinator convergence; coalesced burst | `awaitQuiescence` over projector, bus, coordinator; the burst test also asserts zero drops on the projector's lossy subscription | 1 |
| Launch-restore surface creation | `TerminalActivationScheduler` quiescence, with the supplemental drain tracked | 1 |
| Refresh admission comparison | `BridgePaneRefreshAdmissionCoordinator` quiescence | 1 |
| Repo explorer capture count | The test takes its baseline after `RepoExplorerProjectionAdapter` is idle, not from a value written mid-capture. The adapter's idle predicate and this row are the same signal: a capture that has finished | 1 |
| Visible-tier cadence | The projector's duty-measurement clock becomes injectable beside its scheduling clock; tests advance both | 1 |
| Exact-item FSEvents stream | The fixture awaits the activity fence it currently discards | 1 |
| Pane-agent helper exit | The blocking wait moves off the cooperative pool (R8); a server signal only if that is not enough | 1 |
| Review replay | Terminated-stream census on the router; a bootstrap that finds every stream terminated joins the stream-claim drain, a live stream is still refused (D9). The test is correct and unchanged | 1 |
| Worktree-data integration (HTTP 409) | The test closes its first surface before opening the second; refusals are typed | 1 |
| BridgeWeb backpressure E2E | Diagnosed 2026-09-17: the acknowledgement observer counted requests of a document destroyed by reload (Playwright gives a worker's in-flight requests no terminal event), so its wait could not end. The observer now counts the current document only and has its own deterministic test. Seed cache (D6) and deleting `retry: 1` remain | 1 |
| BridgeWeb share-shelf timeouts | One animation-settle helper; the unbounded one deleted | 1 |
| BridgeWeb annotation E2E `source.refresh` | Diagnosed 2026-09-17 (closes H5): the save journey required the demanded projection query's request sequence to exceed `source.refresh`'s, but one `acquireSession` call issues both from different threads, so the numbers race. Sequence numbers are a total order, not a causal one. The gate is anchored to `root.create` | 1 |
| Ghostty header not found | Lane preflight names the missing vendor input | 1 |

## Cutover

One authority per phase; nothing runs two ways at once.

| Phase | Becomes true | Authority for "how a test waits" | Rollback |
| --- | --- | --- | --- |
| 1. Runner and threads | Bounded concurrency, lane report, preflight, sane default bounds, isolation list gate, blocking waits off the pool | Unchanged (existing helpers) | Reverting the workflow change restores CI and benchmarks. It does not withdraw a release already tagged from the new toolchain, so the first such release follows the existing release smoke before it is relied on |
| 2. Signals | Bus handled semantics; quiescence on the listed owners; discarded signals consumed | Unchanged | Per owner; each is additive |
| 3. Diagnosed families and BridgeWeb | Every row of R9 dispositioned; seed cache; animation settle; stream-end handoff | New primitives for converted tests; baseline seeded; lint rule active | Per family |
| 4. Conversion | Remaining polling sites converted by category; baseline shrinks to empty; helpers and baseline support deleted; the serialized E2E lane joins CI | New primitives only | Not applicable; shrink-only |
| 5. Standard and hygiene | Standard published and routed; contradicting instructions and stale notes removed | — | — |

Phases 1, 2, 3, and 5 form the first pull request and are sufficient to unblock PR #350. It merges under the
repository's existing pull-request gate once "CI / Test" has passed on its head twice in a row on the first attempt;
PR #350 merges after it. Phase 4 is the second pull request, stacked behind the first; it is the bulk of the mechanical
change and is what R18 waits on. Lane reports are collected from every run from the first pull request onward.

## Accepted debt

| Debt | Payer | Revisit when |
| --- | --- | --- |
| Width is set through an `EXPERIMENTAL` environment variable | Test-topology owner | Swift Testing stabilizes the option or changes its default |
| Category E and G sites have no single primitive | Whoever converts them | A third site needs the same bespoke signal; then it becomes a primitive |
| 185 new compiler warnings on Swift 6.3.3 | Deferred; no owner under this goal | Any becomes an error in a later toolchain |
| Lint detects loops, not every disguised poll | Reviewers | A disguised poll reaches `main` |
| WebKit lane still retries a test-helper crash during teardown | WebKit lane owner | The crash is diagnosed; then the retry is deleted |
