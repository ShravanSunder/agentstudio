# Swift CI flake families — root cause per failure

Read-only investigation. No edits, no builds, no test runs, no git-state changes.

Log root (all paths below are relative to it):
`/private/tmp/claude-501/-Users-shravansunder-Documents-dev-project-dev-agent-studio-issues-perf-again/110176da-fb6d-4805-805f-ba5cd8438bbb/scratchpad/flake-inventory/real/`

Every claim is tagged **VERIFIED** (with file:line or a quoted log line I read this
session) or **UNVERIFIED**.

Three already-root-caused failures (Bridge file bootstrap suspension, Bridge
development host review replay `sessionAlreadyOpen`, `WorkspaceCacheCoordinator`
**Integration** `integration_addFolderTopologyConvergesToResolvedRemoteIdentity`)
are not re-derived here.

## Complete failure inventory in the supplied logs

I swept all 30 logs for `recorded an issue` / `✘ Test … failed`. **VERIFIED.** The
only Swift failures present are the nine below plus two already-owned ones:

| Suite / test | Runs |
| --- | --- |
| `BridgeProductRealGitFileAndReviewWebKitTests` "two hosted panes isolate native hidden admission and retain worker state" | 6 (34588581240, 34596792476, 34657945125, 34755706566, 34850913335 — plus the same expectation each time) |
| `BridgeDevelopmentHostReviewReplayTests` `sessionAlreadyOpen` | 1 (34982563057) — already root-caused |

The 6-run `BridgeProductRealGitFileAndReviewWebKitTests` family is **not** in my
assignment and is **not** in the already-root-caused list. It is the single most
frequent Swift failure in this inventory and it is a WebKit-lane failure with a
consistent off-by-one shape:
`(proof.hiddenMetadataSequenceAfterStorm → N) == (proof.hiddenMetadataSequenceBeforeStorm → N-1)`
at `BridgeProductRealGitFileAndReviewWebKitTests.swift:158:13`. **VERIFIED** (log
`34588581240-103228380458.log:27293`, `34596792476:27154`, `34657945125:27767`,
`34755706566:409`, `34850913335:28493`). Flagging it as an unassigned gap — it
belongs to a lane owner.

---

## 1. `WorkspaceCacheCoordinatorTests.startConsuming_coalescesSnapshotChangedBurstBeforeApplyingWorktreeCache`

**Failure lines.** **VERIFIED.** Three runs, identical shape:

- `34601648536-103278960858.log:23281` — `✘ … recorded an issue at WorkspaceCacheCoordinatorTests.swift:846:21: Issue recorded`
- `34601648536-103278960858.log:23282` — `↳ newest snapshot should apply after coalesced flush timed out`
- `34601648536-103278960858.log:23283` — `… at WorkspaceCacheCoordinatorTests.swift:458:9: Expectation failed: didApplyNewestSnapshot`
- `34601648536-103278960858.log:23284` — `failed after 0.011 seconds with 2 issues`
- `34665779346-103477245426.log:23230-23233` — same, `failed after 0.005 seconds`
- `34734857735-103664331790.log:24271-24274` — same at `:903:21` / `:459:9`, `failed after 0.008 seconds`

**Test source.**
`Tests/AgentStudioTests/App/WorkspaceCacheCoordinatorTests.swift:443` (`@Test func startConsuming_coalescesSnapshotChangedBurstBeforeApplyingWorktreeCache`).

**What it waits on and how.** At the failing revision the wait was the file-private
`eventually(_:maxTurns:condition:)` helper — still present at
`Tests/AgentStudioTests/App/WorkspaceCacheCoordinatorTests.swift:920-933`, default
`maxTurns: 100`, body `for _ in 0..<maxTurns { if await condition() { return true }; await Task.yield() }`,
ending in `Issue.record("\(description) timed out")`. **VERIFIED** — that
`Issue.record` string format is the only thing in the repo that produces the exact
log line `↳ newest snapshot should apply after coalesced flush timed out` paired
with `Issue recorded`; `assertEventuallyMain` (`Tests/AgentStudioTests/TestSupport/EventBusHarness.swift:173-191`)
emits `Expectation failed: … timed out` instead. So the budget was **100 cooperative
turns on MainActor**, which the log shows expiring in 5-11 ms of wall time.

The test is otherwise well built: it uses an injected `TestPushClock`
(`Tests/AgentStudioTests/TestSupport/TestPushClock.swift:4`) for the governor tick
and advances it explicitly (`WorkspaceCacheCoordinatorTests.swift:479`).

**Production path from stimulus to asserted state.** Stimulus is
`clock.advance(by: .milliseconds(25))`; asserted state is
`repoCache.worktreeEnrichmentByWorktreeId[worktreeId]?.branch == "new"`. Hops
(all **VERIFIED**):

1. `TestPushClock.advance(to:)` resumes the parked `UnsafeContinuation` of the
   governor's sleep — `TestPushClock.swift:146-163`. Resumption schedules work on
   the **cooperative pool**, not MainActor.
2. `BackgroundFactApplyGovernor.runDrainLoop` resumes out of `try await delay.wait(tickCadence)`
   — `Sources/AgentStudio/App/Coordination/BackgroundFactApplyGovernor.swift:220`.
   This loop runs in an untracked `Task { … }` created in `start()` (`:146-148`).
3. `drainOneTick()` → `takeDrainSnapshot()` under `NSLock` (`:234-299`).
4. `applyPendingFactAndMeasureTiming` → `await prepareApply(key, fact)` (`:303`) —
   one suspension.
5. `await MainActor.run { commit() }` (`:306-311`) — the **MainActor hop**; `commit`
   calls `WorkspaceCacheCoordinator.applyCoalescedEnrichment` (`WorkspaceCacheCoordinator.swift:201-204`).
6. Atom write into `RepoCacheAtom`.

Buffers in the path: the governor's `state.pendingByKey` dictionary +
`pendingOrder` under `NSLock`; the `tickStream` `AsyncStream` with
`bufferingPolicy: .bufferingNewest(1)` (`:131-134`); the tick cadence itself
(25 ms on `TestPushClock`); the per-drain `drainBudget`; and the MainActor job
queue.

**Root cause: POLL-BUDGET.** 100 `Task.yield()` turns on MainActor bought 5-11 ms
of wall time. The remaining work was legitimately in flight on the cooperative
pool (steps 2-5) and needed a pool thread the loaded runner had not yet given it.
The earlier barrier in the same test is already correct and did not fail — the
test waits for `consumedCount == 3 && pendingDeliveryCount == 0` on the bus
(`WorkspaceCacheCoordinatorTests.swift:461-470`), which is exactly the right idea,
just not extended past the bus.

**Missing barrier.** `BackgroundFactApplyGovernor`
(`Sources/AgentStudio/App/Coordination/BackgroundFactApplyGovernor.swift:5`) owns
this. It already has **one half** of the answer and throws it away:

- `enqueue(_:for:)` returns an `Acknowledgement` whose `result()` awaits `.applied`
  or `.superseded` off a per-fact `AsyncStream` (`:13-20`, `:152-184`, `:248-249`).
  That is a genuine per-fact awaitable completion.
- `WorkspaceCacheCoordinator` **discards it**: `_ = governor.enqueue(…)` at
  `WorkspaceCacheCoordinator.swift:348` (repository projection) and the equivalent
  in `enqueueCoalescedEnrichment` (`:274-338`). **VERIFIED.**
- There is no governor-level idle signal at all. The only thing exposed is the
  poll-shaped counter `supersededSinceLastDrainCount` (`:206-213`), whose own
  doc-comment says it exists so "tests can wait for an actual coalescing invariant" —
  i.e. someone already hit this and added a counter to poll rather than a barrier.

What "idle" must mean for the governor: **no pending facts, no tick scheduled, and
no drain in flight** — `state.pendingByKey.isEmpty && !state.isTickScheduled` *and*
the current `drainOneTick()` has completed its last `MainActor.run` commit. A
`waitUntilIdle()` built from stored continuations (the shape
`RemoteReferenceRefreshActor.waitUntilIdle()` already uses) resumed at the end of
`drainOneTick`/`flushAllPendingFacts` when that predicate holds is the barrier.
`WorkspaceCacheCoordinator` then needs a thin forwarder so a test can say "the
enrichment governor has applied everything enqueued so far" without touching the
governor directly.

---

## 2. `RepoExplorerProjectionObservationDemandTests` — "sort and grouping changes reuse adapter topology and add only demanded registrations"

**Failure lines.** **VERIFIED.** Two runs:

- `34619261023-103328839051.log:11644` — `… RepoExplorerProjectionObservationDemandTests.swift:199:13: Expectation failed: (capture.paneFactCaptureCount → 2) == (paneFactCaptureCountAfterGrouping → 1)`
- `34619261023-103328839051.log:11645` — `… :209:13: Expectation failed: (capture.fullCaptureCount → 3) == 2`
- `34619261023-103328839051.log:11654` — `failed after 94.933 seconds with 2 issues`
- `34638252247-103391351860.log:17142` — only the second one: `… :210:13: Expectation failed: (capture.fullCaptureCount → 3) == 2`, `failed after 62.811 seconds`

**Test source.** The test was renamed and partially rewritten in `bc7cad5f8`. The
failing body is `git show aae07e0a0:Tests/AgentStudioTests/Features/RepoExplorer/RepoExplorerProjectionObservationDemandTests.swift`,
lines ~186-212. **VERIFIED.** The decisive fragment:

```swift
atoms.workspaceSidebarState.setSidebarSurface(.panes)
preferences.setGroupingMode(.repo, for: .panes)
await assertEventuallyMain("Panes repo grouping installs pane observations") {
    adapter.observationRegistration.paneIDs == [pane.id]
}
let paneFactCaptureCountAfterGrouping = capture.paneFactCaptureCount   // baseline sampled HERE
…
#expect(capture.paneFactCaptureCount == paneFactCaptureCountAfterGrouping)   // line 199
…
#expect(capture.fullCaptureCount == 2)                                       // line 209/210
```

**How it waits.** `assertEventuallyMain`
(`Tests/AgentStudioTests/TestSupport/EventBusHarness.swift:173-191`): dual budget,
`minimumTurns: 200` **and** `timeout: .seconds(10)`, gives up only when both
expire. That budget did **not** expire — the waits succeeded. The failure is what
happened *after* they succeeded.

**Production path.** Two separate MainActor writes to two separately observed
inputs (`workspaceSidebarState` surface, `RepoExplorerSidebarPrefsAtom` grouping
mode). For each observed input the adapter runs (**VERIFIED**,
`Sources/AgentStudio/Features/RepoExplorer/RepoExplorerProjectionAdapter+InputLifecycle.swift`):

1. `withObservationTracking { … } onChange: { Task { @MainActor in await Task.yield(); … } }`
   — `:132-139`. **Hop 1**: a new MainActor `Task` plus an explicit `Task.yield()`.
2. inside it, `enqueueInvalidation(…)` — `:161`, `:166-176`. Inserts into
   `pendingInvalidation` (the **coalescing buffer**) and, if no invalidation task
   is live, spawns `invalidationTask = Task { @MainActor in await Task.yield(); …; processPendingInvalidation() }`
   — **Hop 2**, another MainActor task plus another `Task.yield()`.
3. `processPendingInvalidation()` — `:178-200` — drains `pendingInvalidation` and
   dispatches to `captureFullProjection` / `capturePresentationProjection`.
4. `captureFullProjection` → `installObservationTokens()` (`:103-123`), which is
   what writes `observationRegistration.paneIDs`.

The coalescing window between two writes is therefore **exactly "whatever landed
before the single live `invalidationTask` finished its one `Task.yield()`"**. It is
not a debounce, not a deadline — it is a race with the MainActor job queue.

**Root cause: ORDERING** — with a legitimate late event, not a product
over-capture. Two things make this certain:

- `observationRegistration.paneIDs` is written **inside** a capture
  (`installObservationTokens`, step 4), i.e. it is a mid-pipeline effect, not a
  settle signal. Waiting on it and then sampling `paneFactCaptureCount` samples a
  baseline while the *second* write's invalidation may still be queued at hop 1 or
  hop 2. That second invalidation then lands after the baseline → `2 == 1`.
- The `fullCaptureCount → 3 == 2` failure is the same thing one step later: the
  test comment asserts "One initial Repos capture plus one structural capture for
  the Panes screen switch", i.e. it assumes the surface write and the grouping
  write **coalesce into one structural capture**. Production only coalesces them
  when both `onChange` closures reach `enqueueInvalidation` before the live
  `invalidationTask` resumes. Under contention they do not.

So the extra capture is production behaving as written; the test asserts a
coalescing guarantee production does not make, and samples a counter baseline on a
non-settle signal.

Corroborating context (**VERIFIED**): the test bodies took **94.9 s** and **62.8 s**
inside a `Test run with 4882 tests in 718 suites` — this suite ran inside the big
concurrent fast-lane process. That is the contention that widens the window.

**Barrier.** It **exists as state but not as an awaitable**, on
`RepoExplorerProjectionAdapter` (`Sources/AgentStudio/Features/RepoExplorer/RepoExplorerProjectionAdapter.swift:67-102`).
The sibling test `membershipChangePromotesToFullCapture` already spells out the
correct settle predicate by polling it
(`RepoExplorerProjectionObservationDemandTests.swift:228-240`):

```
adapter.publishedResult != nil
  && adapter.materializedProjection?.hasUnsettledProjectionTasks == false
  && adapter.invalidationTask == nil
  && adapter.pendingInvalidation.isEmpty
```

That is the definition of idle for this owner: **no pending invalidation, no live
invalidation task, no unsettled materialization task, and a published result**.
What is missing is an awaitable form of it — `RepoExplorerProjectionAdapter` needs
a continuation-backed "projection settled" signal resumed at the end of
`processPendingInvalidation` when the predicate holds. Counter assertions that
prove a count did **not** grow are only meaningful behind that barrier.

---

## 3. `PaneTabViewControllerLaunchRestoreTests` — four tests, one run

**Failure lines.** **VERIFIED**, all in `34715932576-103613049989.log`, step
`Test fast lane`:

- `:15153` `aDeferredPaneCompletesOneAdmissionCycleAsTwoFailedCreateSurfaceCallsWhenGeometryArrives()` — `PaneTabViewControllerLaunchRestoreTests.swift:528:9: Expectation failed: await waitUntil { harness.surfaceManager.createdPaneIds.filter { $0 == deferredPane.id }.count == 2 }`
- `:15155` — follow-on `(… .count → 0) == 2`
- `:15164/:15166/:15168` `revealAndPreparedRequeueOverlapCompleteOneAdmissionCycleAsTwoFailedCreateSurfaceCallsWithOneSurfaceIdentity()` — `:591:9`, then `(… .count → 0) == 2`, then `(harness.surfaceManager.createdConfigsByPaneId[overlapPane.id] → nil) != nil`
- `:15171/:15173` `oneVisibilityChangeRevealingMainAndDrawerPanesAdmitsTheFullPromotedBatchInTierOrder()` — `:695:9`, then `(harness.surfaceManager.createdPaneIds → []).firstIndex(of: paneID …) → nil`
- `:15177/:15179/:15185` `theExactStoredZmxSessionIdentityIsUsedAcrossOneAdmissionCycleOfTwoFailedCreateSurfaceCalls()` — `:748:9`, `(… .count → 0) == 2`, `createdConfigsByPaneId[pane.id] → nil`
- `:15195` — `Test run with 15 tests in 1 suite failed after 4.951 seconds with 10 issues`

**Test source.** `Tests/AgentStudioTests/App/PaneTabViewControllerLaunchRestoreTests.swift`,
the four tests at `:497`, `:560`-ish, `:660`-ish, `:730`-ish (current line numbers
have drifted; the failing assertions are the four `waitUntil` sites).

**How it waits.** `waitUntil(iterations:_:)` at
`PaneTabViewControllerLaunchRestoreTests.swift:402-408` — **VERIFIED**:
`for _ in 0..<20_000 { if condition() { return true }; await Task.yield() }`. The
budget is **20,000 MainActor cooperative turns**, no wall-clock component. Each
failing test burned it in 0.54-0.70 s.

Two facts that constrain the diagnosis, both **VERIFIED**:

- The suite is `@MainActor @Suite(.serialized)` (`:18-20`) and the log line
  `Test run with 15 tests in 1 suite` confirms it ran in its **own isolated
  process** via the per-suite runner, not mixed into the 4882-test lane. So this is
  not cross-suite MainActor contention *inside* the process — though up to four such
  processes run concurrently on the runner.
- `LaunchCapturingSurfaceManager.createSurface` is a **synchronous MainActor**
  method that appends to `createdPaneIds` unconditionally (`:877-886`). So
  `count → 0` means the admission never made even its *first* attempt — this is not
  a slow retry.

**Production path.** Stimulus: `harness.store.setActiveTab(deferredTab.id)` +
`harness.executor.restoreVisibleViewsForActiveTabIfNeeded(forceWhenBoundsExist: true)`
(`:531-532`). Asserted state: two `createSurface` calls on the fake manager. Hops
(**VERIFIED** where cited):

1. MainActor geometry re-evaluation →
   `WorkspaceSurfaceCoordinator.preparedTerminalGeometryReevaluationHandler`
   (`Sources/AgentStudio/App/Coordination/WorkspaceSurfaceCoordinator.swift:110`,
   invoked at `WorkspaceSurfaceCoordinator+ViewLifecycle.swift:752` and `:803`).
2. → `TerminalActivationScheduler.acceptLaterGeometry(for:)` —
   `Sources/AgentStudio/Features/Terminal/Restore/TerminalActivationScheduler.swift:239-246`.
   This is an **actor** hop. It calls `admitWaitingMembers` then
   `ensureADrainObservesNewlyQueuedMembers()`.
3. `ensureADrainObservesNewlyQueuedMembers()` — `:278-290`. In the `.settled` case
   it spawns a **bare, untracked** `Task { await self?.runWorker(); await self?.markSupplementalDrainFinished() }`
   with **no waiter list and no completion signal**. In the `.idle`/`.activating`
   case it spawns nothing and relies on the in-flight `activate()` fleet.
4. `runWorker()` → `nextQueuedCandidate()` → `admissionPort.claimPreparedTerminal(proposal)`
   (`:359`) → `admissionPort.activateClaimedTerminal(claim)` (`:365`) — another
   actor hop into `PreparedTerminalMountAdmissionPort`
   (`Sources/AgentStudio/App/Coordination/PreparedTerminalMountAdmissionPort.swift:180`, `:240`).
5. → `mountHandler.mountPreparedTerminalContent(…)` (`PreparedTerminalMountAdmissionPort.swift:263`)
   → MainActor → `createSurface`.

Buffers: `membersByPaneID` execution states inside the scheduler actor;
`claimTrackingByPaneID` / `trustedFrameState` in the admission port; the
`withTaskGroup` worker fleet in `drainWithWorkerFleet` (`:382-394`); and the
untracked supplemental-drain `Task`.

**Root cause: POLL-BUDGET** for the primary classification — 20 k turns is a
turn-count budget with no time component, and every hop after step 2 is off
MainActor on a runner hosting up to four concurrent test processes.

**But I cannot discriminate this from ORDERING without a run — UNVERIFIED.** The
alternative, fully consistent with `count → 0`, is that `acceptLaterGeometry`
returned an empty accepted set because the pane was not in `.waitingForGeometry`
when the reveal fired (`admitWaitingMembers` silently skips any member not in that
state — `:250-267`), in which case no drain is ever started and no budget would
ever have helped. Four tests failing together in one run and passing everywhere
else leans toward starvation, but that is inference, not evidence.

**Decisive evidence needed:** the scheduler already exposes
`memberState(for:)` (`:296-299`) and `diagnostics()` (`:301-307`, including
`yieldCount`). Neither is captured at failure time. Recording member state and the
accepted set from `acceptLaterGeometry` in the failure message would settle it in
one run.

**Missing barrier.** `TerminalActivationScheduler`
(`Sources/AgentStudio/Features/Terminal/Restore/TerminalActivationScheduler.swift`)
owns this and has the barrier **for one path only**:

- `activate()` is a proper settle barrier — it parks late callers in
  `activationWaiters` and resumes them all with the `TerminalActivationSettlement`
  (`:166-210`). **VERIFIED.**
- The **supplemental drain** path (`acceptLaterGeometry` → step 3) has **no
  equivalent**. The `Task` is untracked, `isSupplementalDrainActive` is a private
  flag with no waiter list, and `markSupplementalDrainFinished()` resumes nobody
  (`:292-294`). **VERIFIED.** This is exactly the path every one of these four
  tests exercises.

What "idle" must mean: **no queued member, no attaching member, and no supplemental
drain in flight** — i.e. the same predicate `activate()`'s tail loop already
computes (`while hasQueuedMember()`, `:198-200`), extended to cover the
supplemental drain. `markSupplementalDrainFinished` is the natural resume point.

---

## 4. `GitWorkingDirectoryProjectorVisibleTierTests` — two tests, two runs

**Failure lines.** **VERIFIED:**

- `34753109765-103712860598.log:13999` — `✘ Test "covered worktree visibility change waits for its tier cadence" recorded an issue at GitWorkingDirectoryProjectorVisibleTierTests.swift:273:9: Expectation failed: await visibleTierWaitUntil { await calls.count == 1 }`; `:15745` `failed after 48.018 seconds`; run total `4921 tests in 731 suites … 100.935 seconds`.
- `34754293105-103715939575.log:13227` — `✘ Test "unchanged cadence multiplier composes with visible tier cadence" … :435:9: Expectation failed: await visibleTierWaitUntil { await calls.count == 1 }`; `:14446` `failed after 57.277 seconds`; run total `4881 tests in 716 suites … 132.777 seconds`.

**Test source (failing revision).**
`git show aae07e0a0:Tests/AgentStudioTests/Core/PaneRuntime/Sources/GitWorkingDirectoryProjectorVisibleTierTests.swift`
— `coveredWorktreeVisibilityChangeWaitsForTierCadence` at ~`:273`,
`unchangedResultsLengthenPeriodicCadence` at ~`:435`. **VERIFIED.**

**How it waits.** `visibleTierWaitUntil` at
`aae07e0a0:…GitWorkingDirectoryProjectorVisibleTierTests.swift:899-912` — **VERIFIED**:
wall-clock only, `timeout: .seconds(10)` on `ContinuousClock`, `Task.yield()` per
turn, no turn floor. Ten seconds is not a tight budget; it expired.

**Is the clock injected, and does the test advance it?** Both. **VERIFIED:**

- The projector takes `sleepClock:` and both tests pass `TestPushClock()`
  (failing revision, `:267-274` and `:427-434`). The projector wires it into
  `delay = sleepClock.map(AsyncDelay.clock) ?? .taskSleep` and into
  `deadlineClock = GitRefreshDeadlineClock(sleepClock)` —
  `Sources/AgentStudio/Core/RuntimeEventSystem/Git/GitWorkingDirectoryProjector.swift:146-152`.
- **Neither failing test advanced the clock before the failing wait.** They go
  `await actor.start()` → set attention → `await bus.post(registrationEnvelope)` →
  `visibleTierWaitUntil { calls.count == 1 }`, in real time.

**Production path from stimulus to `calls.count == 1`.** All **VERIFIED**:

1. `bus.post(registrationEnvelope)` → `EventBus` subscriber buffer.
   `start()` awaits `runtimeBus.subscribe(policy: .lossyNewest(subscriptionBufferLimit), …)`
   **before** returning (`GitWorkingDirectoryProjector.swift:173-190`), so the post
   is not lost — I ruled out the "subscribed too late" hypothesis.
2. `subscriptionTask` — an untracked `Task` looping `for await … { await self.handleIncomingRuntimeEnvelope(…) }`
   (`:181-187`) — actor hop into the projector.
3. `applyRegistration(worktreeId:context:timestamp:forceRefresh:)` (`:473`). The
   decisive branch at `:533-541`:
   ```swift
   if isAutomaticEligible(worktreeId: worktreeId) {
       pendingByWorktreeId[worktreeId] = registrationChangeset
       scheduleAutomaticRefresh(worktreeId:, missingBaseline: true,
                                allowsPromptMissingBaseline: demandTier(for: worktreeId) != .background)
   }
   ```
   A worktree that is **not** yet at an attended tier gets `allowsPromptMissingBaseline: false`,
   i.e. its first status compute is **deadline-scheduled on the injected clock** that
   the test never advances.
4. Status task → `StubGitWorkingTreeStatusProvider` → `VisibleTierCallRecorder` actor.

**The tier-admission race.** For `unchangedResultsLengthenPeriodicCadence` the
stimulus that is supposed to put the worktree at the visible tier is
`setSidebarVisibleWorktrees([worktreeId])`, which does **not** admit synchronously:
`GitWorkingDirectoryProjector+DeadlineRefresh.swift:92-101` ends in
`scheduleCoalescedVisibilityAdmission()`, and that method
(`:194-223`) parks a `Task` on `try await delay.wait(coalescingWindow)` where
`coalescingWindow = AppPolicies.GitRefresh.visibilityChangeCoalescingWindow` and
`delay` is the **TestPushClock**. **VERIFIED.** Worse, the pending delta is
computed **at schedule time** and filtered by eligibility that the not-yet-arrived
registration would have granted:

```swift
pendingVisibilityDeltaWorktreeIds =
    sidebarVisibleWorktreeIds
    .subtracting(lastProcessedSidebarVisibleWorktreeIds)
    .filter(isAutomaticEligible(worktreeId:))     // :205
```

So the worktree can be filtered out of its own admission delta because the bus
registration had not yet been consumed. The current (already-rewritten) sibling
test `visibilityChangeAdmitsAfterCoalescingWindow` does it correctly —
`setSidebarVisibleWorktrees` → `await clock.waitForPendingSleepCount(atLeast: 2)` →
`clock.advance(by: AppPolicies.GitRefresh.visibilityChangeCoalescingWindow)` →
`await calls.waitForCount(1)` (current file `:400-403`). **VERIFIED.**

**Root cause.** Two classes, and I cannot separate them from these logs alone:

- **ORDERING** (primary, for `unchangedResultsLengthenPeriodicCadence`): the test
  assumes `setSidebarVisibleWorktrees` admits the tier before the bus-delivered
  registration is consumed. Production admits it through a separately clocked
  coalescing window whose membership is computed at schedule time. **VERIFIED**
  mechanism; **UNVERIFIED** that it is what fired in that specific run.
- **POLL-BUDGET / ENVIRONMENT** (for `coveredWorktreeVisibilityChangeWaitsForTierCadence`,
  whose `setActivity(isActiveInApp: true)` does admit synchronously —
  `GitWorkingDirectoryProjector+DeadlineRefresh.swift:66-76`): a 10 s wall-clock
  wait inside a process running **4921 tests across 731 suites concurrently**, in
  a test body that itself took 48 s.

**Topology note worth acting on. VERIFIED.** `GitWorkingDirectoryProjectorTests`
is explicitly listed as a serial non-WebKit suite
(`scripts/swift-test-helpers.sh:165-166`), but
`GitWorkingDirectoryProjectorVisibleTierTests` is **not** in that list and is not
annotated `@MainActor @Suite(.serialized)`, so it runs inside the fully concurrent
fast-lane process against the same long-lived actor, bus, and real-clock
measurement machinery as its classified sibling. That is a classification gap, not
a budget problem.

**Missing barrier.** `GitWorkingDirectoryProjector`
(`Sources/AgentStudio/Core/RuntimeEventSystem/Git/GitWorkingDirectoryProjector.swift`)
owns it. Today the test support reaches into private-ish state to approximate it:
`waitForVisibleTierStatusCompletion` awaits `projector.worktreeTasks[worktreeId]?.value`
(`Tests/AgentStudioTests/Core/PaneRuntime/Sources/GitWorkingDirectoryProjectorVisibleTierTestSupport.swift:129-135`)
and `advanceVisibleDeadline` reads `automaticRefreshDeadlineByWorktreeId` /
`lastAutomaticStartAtByWorktreeId` directly (`:137-152`). There is no single
projector-owned quiescence point.

What "idle" must mean for the projector: **the coalesced visibility admission has
been applied (`visibilityAdmissionTask == nil` and `pendingVisibilityDeltaWorktreeIds`
drained), no pending changesets, no in-flight `worktreeTasks`, and the deadline
task is parked on a future deadline rather than a past one.** That is the
awaitable the tests actually want before they assert a call count.

**Mixed-clock hazard, separately. VERIFIED.** The projector uses an injected
`sleepClock` for scheduling but a real `envelopeClock: ContinuousClock` for duty
and admission timestamps (`:22`, `:48`, `:394`, `:694`, `:753`). The tests' own
comment names it: *"Status duty uses a real clock, even when scheduling uses
TestPushClock. CI contention can make its required cooldown longer than the base
cadence."* (current test file `:447-448`). Cadence tests that depend on measured
duty cannot be made deterministic while that second clock is real.

---

## 5. `BridgePaneControllerRefreshAdmissionIntegrationTests` — "second File invalidation publishes while Review construction remains blocked"

**Failure lines.** **VERIFIED**, `34598835178-103260906676.log`, step `Test WebKit lane`:

- `:81` — `✘ … recorded an issue at BridgePaneControllerRefreshAdmissionIntegrationTests.swift:554:9: Expectation failed: await waitForStartedComparisonCount(2, gate: comparisonGate)`
- `:84` — `failed after 0.026 seconds with 1 issue`
- `:119` — `Test run with 37 tests in 2 suites failed after 1.084 seconds`

**Test source.**
`Tests/AgentStudioTests/App/WebKit/Bridge/BridgePaneControllerRefreshAdmissionIntegrationTests.swift:517`
(`func secondFileInvalidationPublishesWhileReviewConstructionRemainsBlocked`); the
failing assertion is the final `waitForStartedComparisonCount(2, …)`.

**How it waited.** The free function
`waitForStartedComparisonCount(_:gate:maxTurns:)` at
`git show b52a75a92:Tests/AgentStudioTests/App/WebKit/Bridge/TestSupport/BridgePaneRefreshAdmissionAssertionTestSupport.swift:36-48`
— **VERIFIED**: `maxTurns: 2000` cooperative `Task.yield()` turns, no time
component, returning `Bool`. It burned all 2000 turns in **26 ms**.

That file is a nest of the same pattern: `waitForRetiringReviewRefreshTasksToDrain`
(`maxTurns: 2000`) and a queued-frame poll (`maxTurns: 200`) sit right beside it.
**VERIFIED.**

**Production path.** Stimulus: `controller.handleWorktreeProductInvalidation(.filesChanged(changeset(batchSequence: 44)))`.
Asserted state: the Review lane has *started* its second comparison at the provider
boundary. Hops: MainActor `BridgePaneController` → refresh admission via
`BridgePaneRefreshAdmissionCoordinator`
(`Sources/AgentStudio/Features/Bridge/Runtime/BridgePaneRefreshAdmissionCoordinator.swift:133`;
entry points `acquireForegroundWork()` at
`Sources/AgentStudio/Features/Bridge/Runtime/BridgePaneController+DiffCommands.swift:17`, `:33`)
→ a review refresh `Task` → the review source provider → `BridgeComparisonGate.waitUntilReleased()`,
which increments `startedComparisonCount` (test double). Buffers: the admission
coordinator's pending/dirty fact and `activeRefreshPass`; the retiring-task maps
(`controller.retiringReviewRefreshTaskById`); the File lane's own driver queue.
The first Review attempt is **deliberately blocked** at the gate for the duration
of the test, so the second attempt must be admitted while a predecessor is parked —
the slowest path in the suite, waited on with the smallest budget.

**Root cause: POLL-BUDGET.** 2000 turns / 26 ms against a path that crosses
MainActor admission, a spawned refresh task, and a provider boundary held open by
a gate.

**Barrier.** It **already exists on the test double** and the current code uses it:
`BridgeComparisonGate.waitForStartedComparisonCount(_:)` is continuation-backed
(`Tests/AgentStudioTests/App/WebKit/Bridge/TestSupport/BridgeReviewSourceProviderTestSupport.swift:340-366`)
and the current test body calls it directly with no `#expect` wrapper
(`BridgePaneControllerRefreshAdmissionIntegrationTests.swift:536`, `:550`, `:554`).
**VERIFIED.**

What is **missing in production** is the equivalent on the owner:
`BridgePaneRefreshAdmissionCoordinator` exposes only a **poll-shaped**
`diagnosticSnapshot` (`activity`, `refreshPassCount`, `activeRefreshPass`,
`dirtyFact` — read at
`Sources/AgentStudio/Features/Bridge/Runtime/BridgePaneController+IPCProjection.swift:129`
and asserted at `…IntegrationTests.swift:509-513`). There is no awaitable
"admission settled" signal. Precedent that the repo already accepts this shape:
`controller.worktreeRefreshDriver.awaitRetiringFileOperations()` — a real
production awaitable used by
`waitForRetiringFileRefreshTasksToDrain` (`BridgePaneRefreshAdmissionAssertionTestSupport.swift:65-69`).
**VERIFIED.**

What "idle" must mean for the admission coordinator: **no active refresh pass, no
dirty fact retained, and every admitted pass has reached its provider boundary** —
i.e. the point at which `refreshPassCount` is stable and `activeRefreshPass == nil`
cannot be invalidated by work already enqueued.

---

## 6. `DarwinSharedExactItemRealStreamIntegrationTests` — "native shared stream fails exact-item replacements closed"

**Failure lines.** **VERIFIED**, `34752587691-103711500818.log`:

- `:26187` — `✘ Test "native shared stream fails exact-item replacements closed" recorded an issue with 1 argument mutation → .atomicReplacement at DarwinSharedExactItemRealStreamIntegrationTests.swift:106:9: Expectation failed: await fixture.provider.renewExactCleanAuthority(firstAuthority)`
- `:26189` — `with 3 test cases failed after 0.553 seconds with 1 issue`

**Test source.**
`Tests/AgentStudioTests/Core/PaneRuntime/Sources/DarwinSharedExactItemRealStreamIntegrationTests.swift:106-109`.
I resolved the exact line: **VERIFIED**, `:106` is the opening `#expect(` of

```swift
#expect(
    await fixture.provider.renewExactCleanAuthority(firstAuthority)
        == .renewed(firstAuthority)
)
```

The log truncated the `== .renewed(…)` half. Critically this is in the test's
**Arrange** section — *before* `fixture.perform(mutation)`. The behavior under test
(a replacement invalidating the authority) had not happened yet.

**How it waits.** It does not wait at that line at all. The only barrier before it
is `try #require(await fixture.awaitLocalStreamSentinelBarrier())` at `:92`.
**VERIFIED**: that helper
(`Tests/AgentStudioTests/Core/PaneRuntime/Sources/DarwinSharedExactItemRealStreamTestSupport.swift:113-138`)
writes a sentinel file into each repository and waits until the stream reports that
specific path, with `timeout: .seconds(5)`. It proves **arrival of one event**, not
that the stream has drained.

**Production path.** Real FSEvents. `fixture.perform(mutation)` → kernel →
`DarwinFSEventStreamClient` C callback → `DarwinFSEventIngressBuffer` (the
coalescing buffer) → `streamClient.events()` `AsyncStream` → `FilesystemActor` →
worktree batches → exact-clean authority state inside the provider. Buffers on that
path: the FSEvents kernel coalescing window itself, `DarwinFSEventIngressBuffer`
(`Sources/AgentStudio/Core/RuntimeEventSystem/Filesystem/DarwinFSEventIngressBuffer.swift`),
and the `events()` stream.

**Root cause: ORDERING.** An FSEvent generated by fixture setup (the repository
creation writes, and the sentinel write itself, which lands in the same watched
tree) arrived **after** `establishAuthority` and invalidated the freshly minted
authority before the test's Arrange-section renewal. The sentinel barrier cannot
prevent this: seeing event *E* on the stream says nothing about events queued
behind or beside *E*, and FSEvents gives no total order across paths.

Not PRODUCT: failing an authority closed on an unexpected event is the invariant
the suite exists to assert. The fixture just asserted it at a moment when an
unrelated event was legitimately still in flight.

**Barrier — this one already exists in production and the fixture does not use it
as a barrier. VERIFIED.** The stream has a real drain fence:

- `FSEventIngressItem.activityProcessingFence(FSEventActivityProcessingFenceID)` —
  `Sources/AgentStudio/Core/RuntimeEventSystem/Filesystem/FSEventStreamClient.swift:39`, `:50`
- `acknowledgeActivityProcessingFence(_:)` — `FSEventStreamClient.swift:192`,
  `DarwinFSEventStreamClient+ActivityLifecycle.swift:12-15`
- `enqueueActivityProcessingFence()` — `DarwinFSEventIngressBuffer.swift:118`,
  driven from `DarwinFSEventStreamClient.swift:937`
- production consumer: `FilesystemActor.swift:411-413`

The fixture **acknowledges** fences and throws them away — `if case .activityProcessingFence(let fenceID) = ingressItem { streamClient.acknowledgeActivityProcessingFence(fenceID); continue }`
(`DarwinSharedExactItemRealStreamTestSupport.swift:97-100`). **VERIFIED.** It never
enqueues a fence of its own and waits for it to come back, which is precisely the
"everything generated before now has been processed" barrier the Arrange section
needs.

What "idle" must mean: **a fence enqueued at time T has been observed on the
consumer side**, i.e. every event the kernel had already delivered before T has
passed through the ingress buffer. Establish the authority *after* that fence, not
after a single sentinel sighting.

---

## 7. `RepositoryNestedDiscoveryContinuityTests` — "a retained child stays available when a new Git ancestor bounds scanner traversal"

**Failure line, full error.** **VERIFIED**, `34726560694-103648861317.log:22858`:

```
✘ Test "a retained child stays available when a new Git ancestor bounds scanner traversal" recorded an issue at RepositoryNestedDiscoveryContinuityTests.swift:13:6: Caught error: processFailed(AgentStudioGitContracts.GitRemoteProcessFailure(executable: "/usr/bin/git", redactedArguments: ["-c", "protocol.allow=never", "-c", "core.askPass=", "-c", "protocol.file.allow=always", "clone", "--", "/Users/runner/work/agentstudio/agentstudio", "/var/folders/36/tjdph2t965j8snz9_vkdnw0r0000gn/T/nested-discovery-continuity-01A0985E-1467-70D6-9564-604154B25008/watched/container/retained-child"], exitCode: 128, redactedStderr: "Cloning into '/var/folders/.../retained-child'...
Downloading web/.agents/skills/ai-copywriter/assets/banner.png (127 KB)
Error downloading object: web/.agents/skills/ai-copywriter/assets/banner.png (e906bda): Smudge error: Error downloading web/.agents/skills/ai-copywriter/assets/banner.png (e906bda9d5e6e3e7d0399b57fb04cfc6ec1c323d3b756bccd4c696fafbba8a94): error transferring \"e906bda9d5e6e3e7d0399b57fb04cfc6ec1c323d3b756bccd4c696fafbba8a94\": [0] remote missing object e906bda9d5e6e3e7d0399b57fb04cfc6ec1c323d3b756bccd4c696fafbba8a94

Errors logged to '/private/var/folders/.../retained-child/.git/lfs/logs/20260913T012459.515078.log'.
Use `git lfs logs last` to view the log.
error: external filter 'git-lfs filter-process' failed
fatal: web/.agents/skills/ai-copywriter/assets/banner.png: smudge filter lfs failed
warning: Clone succeeded, but checkout failed.
You can inspect what was checked out with 'git status'
and retry with 'git restore --source=HEAD :/'
"))
```

`:22859` — `failed after 2.264 seconds`; `:22861` — `Test run with 1 test in 1 suite failed`.

**Is this a real git invocation failing on the runner, or a race?** A **real git
invocation**, deterministically. Not a race. Chain of **VERIFIED** facts:

1. The fixture clones **the CI checkout itself**:
   `Tests/AgentStudioTests/Integration/RepositoryNestedDiscoveryContinuityTests.swift:72`
   `let sourceCheckout = URL(fileURLWithPath: TestPathResolver.projectRoot(from: #filePath))`,
   used as `remoteURL: sourceCheckout.path` at `:88`. The log's remote is
   `/Users/runner/work/agentstudio/agentstudio` — the workspace root.
2. `web/**/*.png` is LFS-tracked: `.gitattributes:5`
   `web/**/*.png filter=lfs diff=lfs merge=lfs -text`.
3. The `swift-test-suite` job's checkout does **not** request LFS —
   `.github/workflows/ci.yml:263-268` has only `persist-credentials: false` and
   `submodules: recursive`. `lfs: true` appears exactly once in the file, at
   `:71`, inside the unrelated `marketing-site-validation` job.
4. So the source checkout holds LFS **pointer files only**; the child clone's
   smudge filter tries to fetch object `e906bda…` from that local remote, which
   does not have it → `remote missing object` → exit 128.
5. The offending asset entered the repo on 2026-08-27 in `5c772b9fd`
   ("Add the Agent Studio marketing website (#314)").

**Root cause: ENVIRONMENT.** Runner checkout configuration, not concurrency.

**Why it appears only once — and why it is already closed. VERIFIED.** The test
file's only commit is `b52a75a92` (2026-09-13 18:24, "Fix watched repository
disappearance, return, and retention (#344)"). The failing run is
2026-09-13T01:24 — i.e. a PR run of that same branch, *before* the merge. The
merged version carries the fix in the same commit:

```swift
// Discovery needs real Git metadata, not hydrated LFS assets from the source checkout.
let remoteClient = SystemGitRemoteClient(
    configuration: .init(
        allowedProtocols: [.file], additionalEnvironment: ["GIT_LFS_SKIP_SMUDGE": "1"]))
```
(`RepositoryNestedDiscoveryContinuityTests.swift:82-85`; `git log -S"GIT_LFS_SKIP_SMUDGE"`
returns only `b52a75a92`.)

**No barrier needed.** This one is resolved. It is not a member of the polling-wait
family and should be closed out of the flake inventory rather than re-investigated.

---

## 8. `GhosttyEventRoutingCoverageTests` — `ghostty.h` could not be opened

**Failure lines.** **VERIFIED**, two runs, identical:

- `34709507968-103595547911.log:19691` and `34717790889-103618023326.log:13772`:
  `✘ Test "upstream action vocabulary has no unmapped values" recorded an issue at GhosttyEventRoutingCoverageTests.swift:10:6: Caught error: Error Domain=NSCocoaErrorDomain Code=260 "The file “ghostty.h” couldn't be opened because there is no such file." UserInfo={NSFilePath=Frameworks/GhosttyKit.xcframework/macos-arm64_x86_64/Headers/ghostty.h, NSURL=… -- file:///Users/runner/work/agentstudio/agentstudio/, …}`
- `34717790889:13783` — `Test run with 3 tests in 1 suite failed after 0.012 seconds`

**How the test locates the header. VERIFIED.**
`Tests/AgentStudioTests/Features/Terminal/Ghostty/GhosttyEventRoutingCoverageTests.swift:12-15`:

```swift
let headerURL = try GhosttyXCFrameworkHeaderResolver.headerURL(
    in: URL(filePath: "Frameworks/GhosttyKit.xcframework", directoryHint: .isDirectory),
    hostArchitecture: GhosttyXCFrameworkHeaderResolver.currentHostArchitecture
)
```

A **process-CWD-relative** path. The same test also reads
`"Sources/AgentStudio/Features/Terminal/Ghostty/GhosttyActionTag.swift"` relatively
(`:34`). The resolver reads the xcframework `Info.plist` and picks the library
whose `SupportedArchitectures` contains the host arch, then appends
`<identifier>/Headers/ghostty.h` (contract pinned by the sibling tests at `:42-61`
and `:63-80`).

**Why CI sometimes lacks it.** `Frameworks/GhosttyKit.xcframework` is **not in the
repository** and **not cached**. It is produced by a distinct CI step. **VERIFIED:**

- `.github/workflows/ci.yml:360-364` — step `Copy XCFramework`, unconditional,
  `mise run --skip-deps copy-xcframework`.
- `.mise.toml:44-55` — that task does
  `rm -rf Frameworks/GhosttyKit.xcframework; mkdir -p Frameworks; cp -R vendor/ghostty/macos/GhosttyKit.xcframework Frameworks/; python3 scripts/normalize-ghostty-xcframework.py`.
- `.github/workflows/ci.yml:326-333` caches only `vendor/ghostty/macos/GhosttyKit.xcframework`
  and `vendor/ghostty/zig-out/share`, under key `ghostty-${{ runner.os }}-${{ ghostty_sha }}`
  — a key also written by `release.yml:80` and `benchmarks.yml:83`.
- `Package.swift:583` consumes `Frameworks/GhosttyKit.xcframework` as a binary
  target, so linking succeeds from the same copy that the test cannot read.
- `scripts/vendor-worktree.sh:6` plus the `setup-shared` branch make
  `Frameworks/GhosttyKit.xcframework` a **symlink** into the primary worktree in
  linked-worktree setups; `scripts/normalize-ghostty-xcframework.py:8-9` explicitly
  refuses to normalize a symlink. CI is the producer, so this is a local-only
  variant — but it means the path's nature is not uniform across environments.

**Hypotheses I ruled out. VERIFIED:**

- *Wrong slice name for a native build.* The CI build uses
  `-Dxcframework-target=native` (`ci.yml:348-352`), which suggests a single-arch
  `macos-arm64` slice. It does not: my local copy, built the same way, has exactly
  one slice `macos-arm64_x86_64` with `Headers/` present and
  `SupportedArchitectures ['arm64','x86_64']`. So the identifier in the error is
  the normal one.
- *Wrong CWD.* Foundation reported the base as
  `file:///Users/runner/work/agentstudio/agentstudio/` — the repo root. CWD was
  correct.
- *Cache-miss correlation.* `34709507968` shows
  `Cache not found for input keys: ghostty-macOS-82232ecd…` (`:455`), but
  `34726560694` also missed the cache (`:449`) and did **not** hit this failure.
  No correlation.

**Root cause: ENVIRONMENT** (build-input provisioning). The precise mechanism by
which `Frameworks/GhosttyKit.xcframework/macos-arm64_x86_64/Headers/ghostty.h`
was absent at test time while the same framework linked successfully is
**UNVERIFIED**. What makes it intermittent is therefore also **UNVERIFIED** — I
could not close it from logs and source alone.

**Decisive evidence needed:** a directory listing of
`Frameworks/GhosttyKit.xcframework` captured in a failing job (e.g. `ls -R` right
after `Copy XCFramework` and again immediately before `Test fast lane`), or making
the resolver's error carry the resolved directory's contents. Note that
`34717790889-103618023326.log` is a **failed-step-only** log (35 KB, one failure
line), so the build-step context for that run is simply not in this inventory —
pulling the full job log for run 34717790889 is the cheapest next step.

**Design note, independent of cause.** This test is the only thing in the suite
that resolves a build input through the **process CWD**. Nothing else in the
process depends on CWD, so nothing else fails when the assumption breaks, and the
failure surfaces as a confusing "no such file" 260 rather than "vendor input
missing". An absolute location handed down from the build (or derived from
`#filePath` the way `TestPathResolver.projectRoot(from:)` already does elsewhere —
see `PaneAgentLaunchOwnerTests.swift:100`, `:117`, and
`RepositoryNestedDiscoveryContinuityTests.swift:72`) removes the CWD variable
entirely. This suite is the outlier; the rest of the repo already uses
`TestPathResolver`.

---

## 9. `PaneAgentLaunchOwnerTests` — "helper authenticates against local server through fd bootstrap"

**Not present in the supplied logs.** **VERIFIED.** I searched all 30 logs for
`helper authenticates`, `did not exit`, `bounded wait`, and `PaneAgentLaunchOwner`.
The test appears in five logs (`34588581240:25980`, `34596792476:25842`,
`34731535116:26961`, `34752587691:25931`, and one more) and **passed every time**,
in 0.068-0.205 s. `34982563057-104451053871.log` contains only the
`BridgeDevelopmentHostReviewReplayTests` failure. The PR #348 report is from a run
outside this inventory, so what follows is source analysis.

**Test source.**
`Tests/AgentStudioTests/App/PaneAgents/PaneAgentLaunchOwnerTests.swift:77-96`.

**How it waits for the child process to exit. VERIFIED**, `:140-167`:

```swift
private func waitForProcessExit(
    processIdentifier: pid_t,
    timeout: DispatchTimeInterval = .seconds(10)
) -> Int32? {
    let semaphore = DispatchSemaphore(value: 0)
    let source = DispatchSource.makeProcessSource(
        identifier: processIdentifier, eventMask: .exit,
        queue: DispatchQueue.global(qos: .userInitiated))
    source.setEventHandler { semaphore.signal() }
    source.resume()
    let waitResult = semaphore.wait(timeout: .now() + timeout)
    source.cancel()
    var status: Int32 = 0
    if waitResult == .timedOut {
        _ = kill(processIdentifier, SIGKILL)
        _ = waitpid(processIdentifier, &status, 0)
        return nil
    }
    let waited = waitpid(processIdentifier, &status, 0)
    return waited == processIdentifier ? status : nil
}
```

**Does that wait block a cooperative-pool thread? Yes. VERIFIED by construction:**

- The test body is `func helperAuthenticatesAgainstLocalServerThroughFDBootstrap() throws`
  — **synchronous**, not `async` (`:78`). Swift Testing runs a synchronous `@Test`
  body on a Swift Concurrency task, i.e. on a **cooperative-pool thread**.
- `DispatchSemaphore.wait(timeout:)` is a **blocking** primitive. It parks that
  cooperative thread for up to **10 seconds**.
- The timeout branch then calls `waitpid(pid, &status, 0)` — blocking, no
  `WNOHANG` — on the same thread.

This is the exact pattern CLAUDE.md's *Swift Concurrency* section forbids
(`@concurrent nonisolated` for blocking I/O; "blocking I/O called from inside an
actor blocks that actor's serial executor"), applied to the shared pool rather
than a named actor.

**Production path, and why the wait is self-defeating.** Stimulus:
`owner.launchPaneAgent(boundPaneId:boundWorkspaceId:)` (`:91`) — spawns the real
helper binary with a remapped bootstrap fd. Asserted state: the helper exits 0,
which it only does **after** authenticating against `fixture.server`, an
**in-process** `PaneAgentLiveServerFixture` server started at `:85`. That server's
accept/handle path is Swift Concurrency work that needs cooperative-pool threads.
The test then blocks one of those threads for the entire wait.

Under a loaded runner — four concurrent test processes, pool width bounded by core
count — parking a pool thread in a semaphore while the work that must complete to
release that semaphore needs the same pool is a **self-starvation** shape. The
narrower the pool, the likelier the helper never gets authenticated, never exits,
and the wait reports "helper process did not exit within the bounded wait".

**Root cause: POLL-BUDGET**, with the aggravating and unusual property that the
wait mechanism itself removes a thread from the pool that the awaited work needs.
I have **no failing log for this test**, so the attribution of the PR #348 report
to this mechanism is **UNVERIFIED**; the blocking-wait facts above are verified
from source.

**Missing barrier. Two, at different levels:**

1. *Mechanical.* There is no non-blocking process-exit wait in the test support.
   `DispatchSource.makeProcessSource` can be bridged with
   `withCheckedContinuation` so the wait **suspends** the task instead of blocking
   a thread, with the `async` test body that requires. This is a prerequisite for
   anything else here: as long as the wait blocks, no barrier downstream can help.
2. *Semantic.* Process exit is the wrong fact to wait on. The invariant under test
   is "the helper authenticated against the local server through the fd
   bootstrap". The owner of that fact is the local IPC server behind
   `AgentStudioPaneAgentBootstrapProvider` (`:87`) / `PaneAgentLiveServerFixture`.
   It exposes no awaitable "a pane-agent session completed authentication for
   bound pane X" signal, so the test infers it from an OS-level side effect two
   hops away. What "idle" must mean there: **the bootstrap issued for pane X has
   been consumed and its session has reached the authenticated state (or been
   rejected)** — a terminal disposition, resumable to a waiter. Exit status then
   becomes a secondary assertion rather than the only observable.

---

## Synthesis

### Grouped by root-cause class

**POLL-BUDGET — a turn-count or deadline poll expired while work was legitimately in flight (4, plus 1 unverified):**

| # | Test | Budget that expired | Wall time burned |
| --- | --- | --- | --- |
| 1 | `WorkspaceCacheCoordinatorTests.startConsuming_coalescesSnapshotChangedBurst…` | 100 `Task.yield()` turns (`eventually`, MainActor) | 5-11 ms |
| 3 | `PaneTabViewControllerLaunchRestoreTests` ×4 | 20 000 `Task.yield()` turns (`waitUntil`) | 0.54-0.70 s |
| 5 | `BridgePaneControllerRefreshAdmissionIntegrationTests` "second File invalidation…" | 2 000 `Task.yield()` turns (`waitForStartedComparisonCount`) | 26 ms |
| 9 | `PaneAgentLaunchOwnerTests` "helper authenticates…" | 10 s `DispatchSemaphore` on a **blocked cooperative thread** | 10 s — **UNVERIFIED** (no log) |
| 4b | `GitWorkingDirectoryProjectorVisibleTierTests` "covered worktree visibility change…" | 10 s `ContinuousClock` (`visibleTierWaitUntil`) | 10 s of a 48 s test |

Shared shape: every one waits on a **downstream side effect** (a cache value, a
`createSurface` count, a comparison count, a process exit) rather than on a
**completion fact owned by the component that does the work**.

**ORDERING — test assumes an order production does not guarantee (3):**

- **#2** `RepoExplorerProjectionObservationDemandTests`: samples a counter baseline
  on `observationRegistration.paneIDs`, which is written *mid-capture*; and asserts
  that two adjacent atom writes coalesce into one structural capture, which
  production only achieves when both `onChange` closures beat one `Task.yield()`.
- **#4a** `GitWorkingDirectoryProjectorVisibleTierTests` "unchanged cadence
  multiplier…": assumes `setSidebarVisibleWorktrees` admits the tier before the
  bus-delivered registration is consumed; production defers admission behind a
  clocked coalescing window whose membership is filtered by eligibility **at
  schedule time** (`GitWorkingDirectoryProjector+DeadlineRefresh.swift:205`).
- **#6** `DarwinSharedExactItemRealStreamIntegrationTests`: treats "one sentinel
  event observed" as "the FSEvents stream is drained", then establishes an
  authority that a still-in-flight setup event closes.

**ENVIRONMENT (2):**

- **#7** `RepositoryNestedDiscoveryContinuityTests` — `swift-test-suite` checkout
  lacks `lfs: true`, so a `file://` clone of the workspace hits a missing LFS
  object. **Already fixed** in the same commit that introduced the test
  (`GIT_LFS_SKIP_SMUDGE=1`, `b52a75a92`). Close it.
- **#8** `GhosttyEventRoutingCoverageTests` — CWD-relative resolution of a build
  input that lives outside the repo and outside the cache. Class is certain;
  mechanism **UNVERIFIED**.

**PRODUCT: none.** No failure in this set shows production violating the invariant
under test. #2 is the closest call and resolves the other way: production is doing
what it is written to do, and the test asserts a coalescing guarantee that was
never made.

**Cross-cutting topology observations (both VERIFIED, both outside the barrier work):**

- `GitWorkingDirectoryProjectorVisibleTierTests` is **not** in
  `aggregate_serial_non_webkit_suite_filters` while its sibling
  `GitWorkingDirectoryProjectorTests` is explicitly listed
  (`scripts/swift-test-helpers.sh:165-166`). It shares the same long-lived actor,
  bus, and real-clock measurement machinery, and it failed inside a
  `4921 tests in 731 suites` concurrent process with 48 s and 57 s test bodies.
- The `RepoExplorerProjectionObservationDemandTests` failures took **94.9 s** and
  **62.8 s** in the same fully concurrent lane. Whatever the barrier work
  achieves, test bodies at that duration mean the lane's concurrency is itself a
  variable in these results.

### Distinct production types needing an awaitable quiescence barrier

De-duplicated across the nine. Each row names the owner, where it lives, what
"idle" must mean, and what currently buffers work inside it with no exit signal.

| Owner | File | "Idle" must mean | What buffers work inside it today |
| --- | --- | --- | --- |
| `BackgroundFactApplyGovernor` | `Sources/AgentStudio/App/Coordination/BackgroundFactApplyGovernor.swift:5` | No pending facts, no tick scheduled, and the in-flight `drainOneTick` has completed its last `MainActor.run` commit | `state.pendingByKey` + `pendingOrder` under `NSLock` (`:29-30`); `tickStream` `AsyncStream(bufferingNewest(1))` (`:131-134`); the tick cadence; `drainBudget` carry-over via `requeueCarriedFacts` (`:319-340`). **Half-present already:** per-fact `Acknowledgement.result()` (`:13-20`, `:248`) is awaitable but `WorkspaceCacheCoordinator` discards it (`WorkspaceCacheCoordinator.swift:348`). No governor-level idle signal; only the poll-shaped `supersededSinceLastDrainCount` (`:206-213`). Serves #1. |
| `RepoExplorerProjectionAdapter` | `Sources/AgentStudio/Features/RepoExplorer/RepoExplorerProjectionAdapter.swift:67` | `pendingInvalidation.isEmpty && invalidationTask == nil && materializedProjection?.hasUnsettledProjectionTasks == false && publishedResult != nil` | `pendingInvalidation` (`:101`); the single live `invalidationTask` (`:102`) whose coalescing window is one `Task.yield()` (`+InputLifecycle.swift:170-176`); the per-token `onChange` `Task { await Task.yield(); … }` hop (`:135-139`); `recencyDeadlineTask` (`:99`, `:367`). The predicate exists as four readable properties and is polled by a sibling test; it is not awaitable. Serves #2. |
| `TerminalActivationScheduler` | `Sources/AgentStudio/Features/Terminal/Restore/TerminalActivationScheduler.swift` | No queued member, no attaching member, **and no supplemental drain in flight** | `membersByPaneID` execution states; the `withTaskGroup` fleet in `drainWithWorkerFleet` (`:382-394`); the untracked supplemental `Task` in `ensureADrainObservesNewlyQueuedMembers` (`:285-289`) whose `markSupplementalDrainFinished()` (`:292-294`) resumes nobody. `activate()` **already is** this barrier for the startup path (`activationWaiters`, `:171-173`, `:203-208`); the `acceptLaterGeometry` path has no equivalent. Serves #3. |
| `GitWorkingDirectoryProjector` | `Sources/AgentStudio/Core/RuntimeEventSystem/Git/GitWorkingDirectoryProjector.swift` | Coalesced visibility admission applied (`visibilityAdmissionTask == nil`, `pendingVisibilityDeltaWorktreeIds` drained), no pending changesets, no in-flight `worktreeTasks`, deadline task parked on a future deadline | `pendingByWorktreeId`; `worktreeTasks` + generations; the clocked `visibilityAdmissionTask` (`+DeadlineRefresh.swift:209-222`) whose delta membership is filtered at schedule time (`:205`); the `.lossyNewest(subscriptionBufferLimit)` bus subscription (`:176-180`); `immediateRefreshWorktreeIds` / `coalescingWorktreeIds`. Test support reaches into `worktreeTasks` and the deadline maps directly today (`…VisibleTierTestSupport.swift:129-152`). Serves #4. |
| `BridgePaneRefreshAdmissionCoordinator` | `Sources/AgentStudio/Features/Bridge/Runtime/BridgePaneRefreshAdmissionCoordinator.swift:133` | No active refresh pass, no retained dirty fact, and every admitted pass has reached its provider boundary — i.e. `refreshPassCount` cannot still be incremented by already-enqueued work | The admission coordinator's pending/dirty fact and `activeRefreshPass`, readable only through the poll-shaped `diagnosticSnapshot` (`BridgePaneController+IPCProjection.swift:129`); `controller.retiringReviewRefreshTaskById`; the spawned review-refresh tasks. **Precedent in the same object graph:** `worktreeRefreshDriver.awaitRetiringFileOperations()` is a real production awaitable (used at `BridgePaneRefreshAdmissionAssertionTestSupport.swift:65-69`) — the admission side simply lacks its twin. Serves #5. |
| `DarwinFSEventStreamClient` / `DarwinFSEventIngressBuffer` | `Sources/AgentStudio/Core/RuntimeEventSystem/Filesystem/DarwinFSEventStreamClient.swift:937`, `DarwinFSEventIngressBuffer.swift:118` | A fence enqueued at time T has been observed by the consumer — every event the kernel had already delivered before T has passed through the ingress buffer | The FSEvents kernel coalescing window; `DarwinFSEventIngressBuffer`'s queue and its `pendingActivityProcessingFence` (`:20-21`). **The barrier fully exists in production** (`FSEventStreamClient.swift:39`, `:50`, `:192`; `DarwinFSEventStreamClient+ActivityLifecycle.swift:12-15`; consumed at `FilesystemActor.swift:411-413`); the fixture acknowledges fences and discards them instead of enqueueing one and awaiting it (`DarwinSharedExactItemRealStreamTestSupport.swift:97-100`). Serves #6. |
| Pane-agent local IPC server (behind `AgentStudioPaneAgentBootstrapProvider`) | `PaneAgentLaunchOwnerTests.swift:87` names the provider; server type is `PaneAgentLiveServerFixture.server` | The bootstrap issued for pane X has been consumed and its session reached a terminal disposition — authenticated or rejected | No awaitable session-state signal at all; the test infers authentication from OS process exit two hops away, via a wait that blocks a cooperative-pool thread the server needs. Serves #9. **UNVERIFIED** attribution. |

**Seven distinct owners.** Two of them (`TerminalActivationScheduler`,
`DarwinFSEventStreamClient`) already ship a working barrier that simply does not
cover the path under test; one (`BackgroundFactApplyGovernor`) ships a per-fact
acknowledgement that the only caller throws away; one
(`BridgePaneRefreshAdmissionCoordinator`) sits next to a sibling that has the
right shape. Only `RepoExplorerProjectionAdapter`,
`GitWorkingDirectoryProjector`, and the pane-agent server need one built from
nothing — and for the first two the predicate is already written down in code, as
a poll.

### Time-behavior tests that should use an injected clock

- **`GitWorkingDirectoryProjectorVisibleTierTests` — both failing tests, and the
  suite's cadence tests generally.** The suite **already** injects `TestPushClock`
  for scheduling, so this is not "adopt a clock" but "finish the job": the
  projector keeps a **second, real** clock —
  `envelopeClock: ContinuousClock` (`GitWorkingDirectoryProjector.swift:22`, `:134`,
  `:145`) feeding `admissionStartedAtByWorktreeId` (`:48`), the registration
  timestamp (`:394`), `computeStart` (`:694`), and `statusCompletion` (`:753`).
  The tests' own comment concedes the consequence: *"Status duty uses a real clock,
  even when scheduling uses TestPushClock. CI contention can make its required
  cooldown longer than the base cadence."* (current test file `:447-448`).
  **VERIFIED.** Any assertion about cadence composition or adaptive multipliers is
  non-deterministic while duty measurement reads wall time. Injecting the duty
  clock alongside the sleep clock is the fix; that is a production change, so it
  needs owner sign-off.
- **`WorkspaceCacheCoordinatorTests.startConsuming_coalescesSnapshotChangedBurst…`
  — already correct on this axis.** It injects `TestPushClock` and advances it
  explicitly (`:446`, `:479`). Its residual problem is purely the missing apply
  barrier (#1), not timekeeping. Recording it here so it is not "fixed" a second
  time by adding another clock.
- **`RepoExplorerProjectionObservationDemandTests`** is *not* a time-behavior test
  and should not acquire a clock. Its coalescing window is a single `Task.yield()`,
  not a duration (`RepoExplorerProjectionAdapter+InputLifecycle.swift:171`). It
  needs the settle barrier, not a clock. The one genuinely time-shaped thing in
  the adapter, `recencyDeadlineTask`, is already injectable and is already faked
  by the sibling test with
  `recencyDelay: AsyncDelay { _ in throw CancellationError() }`
  (`RepoExplorerProjectionObservationDemandTests.swift:216`). **VERIFIED.**
- **`PaneTabViewControllerLaunchRestoreTests`** is not time-shaped either — the
  admission retry is driven by claim outcomes, not a delay. Its need is the
  supplemental-drain barrier (#3).
