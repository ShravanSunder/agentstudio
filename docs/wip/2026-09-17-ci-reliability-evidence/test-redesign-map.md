# Test redesign map: what each problem test claims, and a better way to prove it

Date: 2026-09-17. Branch `fix/ci-reliability` (PR #351). Working document.

This maps the tests behind two weeks of CI flakiness: what each one claims, what it actually checks, exactly how a
slower machine changes its verdict while the product is correct, and a better design for the same claim. It was built
by four read-only lanes reading current code, not by re-reading older reports. Full per-test records, with
`path:line` citations for every statement, are beside this file in [`test-map/`](test-map/):

| Lane | File | Covers |
| --- | --- | --- |
| A | [`lane-a-swift-coordination.txt`](test-map/lane-a-swift-coordination.txt) | Swift state and coordination tests |
| B | [`lane-b-swift-boundaries.txt`](test-map/lane-b-swift-boundaries.txt) | Real FSEvents, child process, transport tests |
| C | [`lane-c-webkit-and-recurring-suites.txt`](test-map/lane-c-webkit-and-recurring-suites.txt) | WebKit journeys; six suites that recur in blocked runs |
| D | [`lane-d-bridgeweb.txt`](test-map/lane-d-bridgeweb.txt) | All 14 BridgeWeb E2E files, browser-integration failures, test-side observers |
| — | [`bridgeweb-backpressure-e2e-diagnosis.txt`](test-map/bridgeweb-backpressure-e2e-diagnosis.txt) | Why the backpressure E2E is red in CI |

Statements marked **(checked)** were re-read in the code by the orchestrator. Everything else is the lane's finding
with its citation in the lane file.

## The one rule

**A test's verdict must be a function of the program's logic, never of the machine's speed.**

Machine speed gets into a verdict through four doors. Every flaky test in this map uses at least one.

| Door | What it looks like | Count found |
| --- | --- | --- |
| The **oracle** | Asserting a convenient number that mixes causes, or a measurement of time | 9 tests |
| The **wait** | Polling for a state with a turn budget or deadline, because the owner never says "done" | 678 call sites repo-wide; 3 owners identified that know and do not say |
| The **observer** | The test rebuilds system state on the side from events, instead of reading the owner | 5 observers in BridgeWeb E2E |
| The **stimulus** | "Send a burst and hope the interleaving appears", instead of forcing the interleaving | 3 tests |

## What a good test looks like here

Three tests already in the repo are the model. Copy them.

| Model | Why it is good |
| --- | --- |
| `BridgePaneProductFileBootstrapSuspensionTests` | Forces the exact interleaving by invalidating admission from inside the acceptance observer. Failed 100% before the fix, passes 100% after. Every seam it uses is a defaulted production init parameter or a protocol production itself consumes; no `#if DEBUG`. |
| `BridgePaneProductMetadataActivityAdmissionTests` `:69-123` **(checked)** | Proves "a hidden pane admits no product data" with owner-reported call counts and `queuedFrameCount == 0`, and forces the hide-between-admission-and-enqueue interleaving with `suspendFileSourceBeforeEmission` / `waitUntilEmissionReady` / `releaseEmission`. No WebKit, no clock. |
| BridgeWeb product E2E "paints complete final File bytes after deep scroll" | The app publishes what it painted (`observedSha256`); the test knows the file's hash; the assertion is that they agree. Zero speed dependence, and no cheaper test can make the claim. |

A test is good when it:
1. states **one invariant in product terms**;
2. reads the value **from the owner of that fact**;
3. **forces** the ordering it is about, or awaits the owner's completion signal;
4. **names what broke** when it fails;
5. lives at the **cheapest layer** that can prove the claim, with one thin journey above it to prove wiring.

## The PR gate has speed checks in it that the repo's own policy says belong elsewhere

**(checked)** `.github/workflows/benchmarks.yml:7-8` states the policy: nightly and post-merge runs keep timing
policies exercised "without putting wall-clock gates in the pull-request lanes". `BridgeWeb/vitest.browser.config.ts`
declares a `stress` tag and `package.json` filters on it (`test:browser` runs `!stress`, `test:browser:stress` runs
`stress`), and `benchmarks.yml` runs the stress set. `BridgeWeb/vitest.e2e.config.ts` has **no `tags` key**, so the
600-second, 1,699-item backpressure journey runs on every pull request through `ci.yml` ("Test BridgeWeb Swift E2E").
The framework exists; the E2E config is the one place that missed it.

| In the PR gate today | Belongs |
| --- | --- |
| Backpressure journey's 4 performance assertions (`longTaskCountDelta == 0`, three ages under the 5,000 ms lease) | Post-merge benchmark lane, compared as p50/p95 against the previous main run on the same runner class |
| `bridge-viewer-vite-interaction-profile.e2e.test.ts`: 40 real interactions per PR; its own comment says the samples "are not a statistically accepted SLO cohort"; it only asserts ten numbers are finite | Post-merge benchmark lane |
| `ArchitectureSwiftLintRulesTests` test 5: spawns a full SwiftPM build of a second package inside a unit test to substring-check 7 rules | Delete: `RuleInventoryTests.swift:7-14` proves all 30 rules with severities in-process, in a lane the aggregate already runs |

## The backpressure journey, taken apart

One 970-line journey, 25 final assertions, four different kinds of claim.

| Kind | Count | Examples | Where it should be proved |
| --- | --- | --- | --- |
| Functional, a user would notice | 2 | six bodies visible after reload; six distinct message ids | **Stays** in a thin journey |
| Wiring | 5 | bootstrap request count, failure count, clean cleanup | **Stays** in the thin journey |
| Flow-control property of one module | 14 | high-water mark ≤ 12; unit bytes ≤ 128 KiB; nothing pending at end | Unit tests. **8 of the 14 are already proved there, two more strictly**: `bridge-metadata-catalog-transfer-packer.unit.test.ts:37-76` proves the exact 128 KiB boundary byte and the +1 rejection; `bridge-comm-worker-review-demand-ledger.unit.test.ts:141-168` proves the exact 12/13 admission transition |
| Performance | 4 | no long tasks; ages under the lease | Benchmark lane |

**(checked)** A clock-injected unit test already runs the same scale:
`bridge-comm-worker-review-demand-ledger.unit.test.ts:191` "releases an exact queued publication while 1,699-item
Review demand is suspended", in microseconds.

Proposed split: a thin journey of about 9 assertions stays in the gate (save six, reload, see six, correct sessions,
clean shutdown); the 6 unproved flow-control properties get unit tests against the real module with a scripted
consumer; the 4 performance numbers move to the benchmark lane.

## Per-test map

Verdicts: **keep** · **fix oracle** · **fix wait** · **force interleaving** · **split and push down** ·
**move to benchmark lane** · **delete (duplicate)**.

### Red in CI now

| Test | Claims | How machine speed flips it | Better design | Verdict | State |
| --- | --- | --- | --- | --- | --- |
| WebKit "two hosted panes isolate native hidden admission" `:158-162` **(checked)** | A hidden pane admits no product data | Asserts the total stream sequence did not move; that counter also counts protocol acknowledgements (`BridgeProductSession.swift:583-586`) that must flow while hidden. The failing run's own diagnostic prints `pane=+0, file=+0, review=+0` | Assert the three product-frame deltas are zero. The invariant itself is already proved deterministically in `BridgePaneProductMetadataActivityAdmissionTests`; the journey is wiring proof | fix oracle now; split later | Fix in progress |
| …same test `:169` | N invalidations cause `+3` refresh passes | Passes merge per lane, so 1 or 2 passes is an interleaving outcome. Not yet seen failing | Assert the policy on the coordinator with a forced sequence; drop the constant from the journey | fix oracle | Recorded, not changed |
| …same test, 7 of 24 assertions | — | Cannot fail: they restate conditions the `require*` helpers already enforce by throwing | Delete; put the diagnosis in the assertion message | delete | Later |
| Backpressure E2E, attempt 1 (journey `:706`) **(checked)** | No acknowledgement is outstanding | The test keeps its own `Set` of in-flight requests. Acknowledgements are POSTs from a Web Worker; on reload Playwright 1.61 gives no terminal event for the destroyed worker's requests. More in flight on a slow runner | Count the current document only (epoch on main-frame navigation), with a deterministic test of the observer. Better still, read the owner: the server already publishes `render_disposition.pending_count` | fix oracle | Fix in progress |
| Save journey, attempt 2 (`save-journey.ts:222-234`) **(checked)** | The demanded projection for the new session arrived | Requires the query's sequence number to exceed `source.refresh`'s, but one `acquireSession` call (`worktree-annotation-surface-client.ts:430-437`) issues both from different threads, so the numbers race. The projection did arrive. **Sequence numbers are a total order, not a causal one** | Anchor to `root.create`, which truly precedes the query | fix oracle | Fix in progress |

### Swift, coordination (lane A)

Four of the seven tests named in the older evidence report were **already fixed** in current code
(`visibleTierWaitUntil` gone, `waitForStartedComparisonCount` continuation-backed, RepoExplorer coalescing assumption
gone). Plan from the code, not the report.

| Test | Finding | Better design | Verdict |
| --- | --- | --- | --- |
| `WorkspaceCacheCoordinatorTests` burst / convergence | Its `consumedCount == 3` barrier is sound only because the coordinator's loop body is synchronous into the governor's lock (`WorkspaceCacheCoordinator.swift:157`). Unwritten premise: make that async and the test silently flakes again. `coordinator.shutdown()` at `:484` is already a complete barrier | Consume the governor's `Acknowledgement`, discarded at `:293`, `:305`, `:348`; comment the premise | fix wait |
| `RepoExplorerProjectionObservationDemandTests` | Seven bare `for _ in 0..<N { await Task.yield() }` loops with no failure on exhaustion: **a timeout becomes a silent pass** | Fail on exhaustion today; adapter idle signal later | fix oracle + fix wait |
| `PaneTabViewControllerLaunchRestoreTests` (4) | Asserts `createSurface` called exactly twice against a manager that always fails: a fake's retry policy, not a product invariant. **Two** untracked tasks sit between stimulus and oracle (`TerminalActivationScheduler` supplemental drain `:285-294`, and `WorkspaceSurfaceCoordinator+ViewLifecycle.swift:718`), so a scheduler-only barrier will not fully fix it | First capture `memberState(for:)` / `diagnostics()` in the failure message (free, separates starvation from an ordering miss); then barrier both tasks | fix wait + fix oracle |
| `GitWorkingDirectoryProjectorVisibleTierTests` | Only `lastAutomaticDuty` is on the real clock; the other three timestamps are already on the injected clock. The test recomputes production's own `max(...)`, so under load it passes **without exercising its claim** | Inject the duty clock; add one `#expect` that makes the silent degradation loud | fix oracle |
| `BridgePaneControllerRefreshAdmissionIntegrationTests` | Coordinator exposes only a poll-shaped snapshot; its sibling driver already ships `awaitRetiringFileOperations()` | Awaitable idle on the coordinator | fix wait (teardown) |
| `BridgeReviewContentLoaderCacheTests` "coalesce one handle load" | `diagnosticSnapshot` reports in-flight **key** count; the test needs attached **waiter** count | Expose the waiter count the claim is about | fix wait (seam missing) |
| `BridgeGitReviewContributionSourceProviderTests` cancellation | Nothing wrong found | — | keep |

### Swift, boundaries (lane B)

| Test | Finding | Better design | Verdict |
| --- | --- | --- | --- |
| Real FSEvents "fails exact-item replacements closed" | The failing line is an Arrange precondition written as `#expect`. Production ships the complete barrier, `DarwinFSEventStreamClient.captureActivityBarrier()` (`:881`); six sibling suites use it; this fixture receives fences and discards them | Use the barrier; demote Arrange checks to `#require` | fix wait |
| `RepositoryNestedDiscoveryContinuityTests` | Not a race: real `git clone` hit a missing LFS object; fixed in-tree with `GIT_LFS_SKIP_SMUDGE` | — | keep; close the entry |
| `PaneAgentLaunchOwnerTests` fd bootstrap | Synchronous test body blocks a cooperative-pool thread on a semaphore for 10 s while the in-process server needs that pool. Its oracle is the child's exit code standing in for "authenticated" | Async body with a continuation; a server-side disposition signal **needs an owner decision (security boundary)** | fix wait |
| Dev-host Review replay (409) | `stop()` awaits the test's own consumer task; the host then checks `metadataRetirementBarriersForReload()`, which is `nil` for a lease with no recorded retirement | Await the host's own post-condition (`BridgeDevelopmentProductHost.swift:866-868`) before the second bootstrap | fix wait |
| `FilesystemActorTests` "active-in-app priority order beats sidebar-only" | Two separate ingress calls; the first schedules a drain that can publish before the second lands. The sibling at `:487` proves a stronger three-tier claim and documents the right stimulus | — | delete (duplicate) |
| `RepoScannerValidationExecutorTests` custody timeout | Order-sensitive array equality over two detached tasks; the file's own set comparator is used three lines earlier | One line | fix oracle |
| Projector "one explicit transition flushes owner telemetry" **(checked)** | **Production defect.** `GitWorkingDirectoryProjector+RefreshAttribution.swift:194-195` and `:233-234` resolve the settlement and *then* record telemetry, so any consumer can observe "settled" before "recorded" | Record, then announce | production fix, in progress |

### WebKit lane and recurring suites (lane C)

| Subject | Finding | Better design |
| --- | --- | --- |
| Serialized WebKit lane membership | Defined by a substring grep (`WebKitTestIsolationArchitectureTests.swift:8-16`). 44 files qualify; **6 actually load the app or run JS in a page** | Distinguish "constructs a `WebPage`" from "navigates one"; cost question, needs a decision |
| "native named surfaces retain independent state" `:124` | `>= +3` on the same contaminated counter; `:125-128` already prove the claim exactly | fix oracle: delete the line |
| `PaneTests` (38), `CommandBarStateTests` (79) | Zero `await`, zero I/O, both `.serialized`. `CommandBarStateTests` mutates process-global `UserDefaults.standard`, where `.serialized` is the wrong tool: it orders only within the suite | Drop the trait where unneeded; inject the defaults store where needed (owner decision) |
| `ArchitectureSwiftLintRulesTests` | Test 5 duplicate (above); test 4 shells out per test, blocking a thread on `waitUntilExit()` | One subprocess per suite, in the script lane |

### BridgeWeb E2E (lane D)

| Test | Verdict | Better design |
| --- | --- | --- |
| Backpressure journey | split and push down | Above |
| Save journey | fix wait | Its design is right (it physically gates the projection route and asserts while held). One flaw: `settleBrowserFrames(page, 2)` at `:304`, a two-frame guess before the two counts that carry the claim |
| Restart journey; annotation edit-reopen; markdown selection; tab ownership; worker-recovery draft reclaim | keep | Owner-reported or event waits throughout |
| Interaction profile | move to benchmark lane | Above |
| Proportional Review refresh | fix oracle | A negative assertion over an open window, read from a bounded telemetry ring |
| Product deep-scroll | **keep** | Best oracle in the lane. Make its timeout report the observed correlations. **Its earlier red (observed hash ≠ fixture hash) is a product signal and is still open** |
| `waitForSelectedReviewReady` (imported by six files) | fix oracle | Walks shadow roots counting rows with non-zero geometry; the File equivalent reads the owner's `data-worktree-open-file-state="ready"`. Give Review the same owner-declared readiness |
| `waitForBackpressureTelemetry` | fix oracle | Polls an OTLP sink and maxes over a **bounded ring**, so the oracle weakens as the machine slows |
| Category filters; git-status filters; stream recovery; worker-recovery replacement | split and push down | Medium confidence; unit overlap to be confirmed per test |
| Markdown scroll retention; share-shelf "preserves All membership" | fix wait | Unbounded or fixed-shape animation waits |

## Patterns that recur

| Pattern | Count | Cure |
| --- | --- | --- |
| The owner knows it is done and does not say | 3 owners (fact-apply governor, terminal activation scheduler's supplemental drain, refresh admission coordinator) | One awaitable completion per owner. Ask "can this be **awaited**?", not "can this be **read**?" — two existing test seams are counters to poll |
| Aggregate counter used as the oracle | 3 (`:158`, `:124`, `:169`) | Assert the invariant's own value |
| Negative assertion with no barrier ("count did not grow") | 5 Swift + 4 BridgeWeb | A negative needs a **stronger** barrier than a positive: settle the owner, then assert once; or restate as a positive fact about owner state |
| Turn loop that falls through on exhaustion | 7 | Exhaustion must fail |
| Test-side reconstruction of owner state | 5 | Read what the owner publishes |
| Sequence number read as causality | 1 found; audit pending | Anchor to the true cause |
| Dead assertions that restate a throwing helper | 7 in one test | Delete; move the diagnosis into the message |
| `.serialized` present where unneeded, insufficient where needed | 2 suites | Trait follows shared state, not habit |
| Performance number as a boolean PR gate | 5 | Benchmark lane, compared to a baseline |

## What lands where

| Pull request 1 (unblocks #350, #345, #348) | Later, by its own plan |
| --- | --- |
| WebKit product-frame assertion | Split the WebKit journey down to wiring |
| Acknowledgement observer epoch + its test | Read `pending_count` from the owner |
| Save journey anchored to `root.create` | Audit other sequence-anchored gates |
| Settlement telemetry recorded before it is announced | — |
| One-line and test-support-only fixes: scanner set comparator, FSEvents activity barrier, delete the duplicate priority test, RepoExplorer loops fail on exhaustion, launch-restore failure diagnostics | Awaitable completion on the three owners; launch-restore barriers |
| Tag the backpressure journey and interaction profile out of the PR gate **(needs the owner's yes)** | Thin backpressure journey + the 6 missing unit tests; performance comparison in the benchmark lane |
| Delete `ArchitectureSwiftLintRulesTests` test 5 (duplicate) | WebKit lane membership rule; `UserDefaults` injection |

## Decisions that are the owner's

1. Move the backpressure journey's speed assertions and the interaction profile out of the PR gate into the existing
   post-merge benchmark lane. The checked-in policy comment already says this; the E2E config never implemented it.
2. Keep the full-scale real-browser backpressure run blocking, or keep a thin journey plus unit proofs.
3. A server-side "helper authenticated" signal for the pane-agent launch test (security boundary).
4. Inject the `UserDefaults` store for `CommandBarStateTests`.
5. Whether the serialized WebKit lane should hold suites that construct a `WebPage` but never navigate one.
6. Who investigates the product deep-scroll content-identity red.
