# PR 2 — EagerDerivedAtom and Tab Bar Implementation Plan

> **For agentic workers:** Use subagent-driven development or executing-plans task by task. Every step below is a checkbox and every implementation delegate receives its paths, proof gate, and stop condition.

**Goal:** Replace synchronous MainActor Tab Bar fleet reconstruction with one total, cancellation-only `EagerDerivedAtom` and one coherent off-main projection, stacked on PR 1.

**Architecture:** `TabBarAdapter` captures immutable Core and Inbox facts, synchronously revokes stale work from Observation's leading edge, and admits one generation to a retained latest-wins node. Core and Inbox own pure policy; App owns tab grouping, notification color mapping, and the final projection. Each window owns and stops its adapter.

**Tech stack:** Swift 6.2 strict concurrency, Swift Observation, Swift Testing, existing ArchitectureLint, trace runtime, Victoria workload, debug IPC, and LaunchServices runner.

## Scope guard

- Only the total cancellation-only eager primitive and Tab Bar adoption are authorized.
- No SQLite, Repo Explorer/Inbox worker migration, Command Bar, pane/tab families, target split, fallible mode, scheduler/queue/retry system, second projection, new proof framework, or foreground UI control.
- Preserve one output authority: remove synchronous `refresh()` in the same cutover; do not add fallback or compatibility paths.
- Stop for a new ownership/public contract, reverse target edge, product type in Infrastructure, or proof-framework expansion.

## Requirement and proof matrix

| Requirement | Implementation seam | Required proof |
|---|---|---|
| RS-09, RS-10 | `EagerDerivedAtom` admission and coherent output | deterministic latest-wins, equal-output currentness, push admission |
| RS-11, RS-12 | `Sendable` request/result/projector and detached CPU work | strict build, compile-negative transfer fixture, Core/App parity |
| RS-13, RS-14 | revocation epoch, generation admission, irreversible stop | pre-successor invalidation, overlap, cancellation-ignoring stale completion, shutdown |
| RS-21–RS-23 | generic Infrastructure node; Core/Inbox policy; App composition | ArchitectureLint, target builds, no product names in AtomLib |
| RS-24–RS-26 | existing trace queue/recorder/workload/comparator | lazy disabled path, queue completeness, matched provenance and distributions |
| RS-27, RS-28 | one host and window-owned lifecycle | focused/full tests, detached LaunchServices interaction and state read-back |

---

### Task 1: Total latest-wins `EagerDerivedAtom`

**Files:**
- Create `Sources/AgentStudio/Infrastructure/AtomLib/EagerDerivedAtom.swift`
- Create `Tests/AgentStudioTests/Infrastructure/AtomLib/EagerDerivedAtomTests.swift`
- Create `Tests/AgentStudioTests/Fixtures/AtomLibCompileFailures/EagerDerivedAtomNonSendableRequest.swift.fixture`
- Create `scripts/verify-atomlib-compile-failures.sh`
- Create `Tests/AgentStudioTests/Scripts/AtomLibCompileFailureScriptTests.swift`
- Modify `.mise.toml` to add `test:atomlib-compile-negative` to the existing aggregate; do not treat excluded fixtures alone as proof.

**Interface:** `@MainActor @Observable package final class EagerDerivedAtom<Request: Sendable, RequestIdentity: Equatable & Sendable, Value: Sendable>` with `init(requestIdentity:isValueEqual:project:)`, `nonisolated sourceDidInvalidate()`, `admit(_:)`, idempotent irreversible `stop()`, `value`, `freshness`, and `revision`. `project` is `@Sendable (Request) throws(CancellationError) -> Value`; freshness is `idle`, `running(identity)`, `invalidated(identity)`, `current(identity)`, or `stopped`.

- [ ] Add tests using continuations/gates, never sleeps, for initial publication, equal request no-op, successor cancellation, stale completion that ignores cancellation, equal current completion preserving value/revision, synchronous invalidation before successor admission, repeated invalidation, stop-before-completion, repeated stop, and rejected post-stop admission.
- [ ] Run `mise run test:swift -- --filter EagerDerivedAtom`; expect RED because the type is absent.
- [ ] Implement one `Synchronization.Mutex` revocation epoch, one MainActor generation, one retained user-initiated detached task, off-main equality against the previous `Sendable` value, and MainActor admission requiring generation, identity, and epoch. `sourceDidInvalidate()` advances correctness synchronously; its bounded MainActor bookkeeping may mirror `.invalidated(identity)` only when that admitted epoch is still stale.
- [ ] Keep freshness bookkeeping separate from output observation; only unequal current output changes `value`, first publication keeps revision `0`, and each later unequal publication advances it once.
- [ ] Run the focused tests and `mise run test:atomlib-compile-negative`; expect GREEN only when the fixture is rejected for violating `Request: Sendable`.
- [ ] Commit `feat: add eager derived atom lifecycle`.

### Task 2: Pure Sendable Core Tab Bar projection

**Files:**
- Create `Sources/AgentStudio/Core/State/MainActor/Atoms/CoreTabBarProjection.swift`
- Modify `Sources/AgentStudio/Core/Models/ArrangementPanelModels.swift`
- Modify `Sources/AgentStudio/Core/State/MainActor/Atoms/WorkspaceTabLayoutDerived.swift`
- Modify `Sources/AgentStudio/Core/State/MainActor/Atoms/TabDisplayDerived.swift`
- Modify `Sources/AgentStudio/Core/State/MainActor/Atoms/PaneDisplayDerived.swift`
- Modify `Sources/AgentStudio/Core/State/MainActor/Atoms/ArrangementDerived.swift`
- Modify `Sources/AgentStudio/Core/State/MainActor/Atoms/RepositoryTopologyAtom.swift`
- Modify `Sources/AgentStudio/Core/State/MainActor/Atoms/WorkspacePaneDerived.swift`
- Create `Tests/AgentStudioTests/Core/State/CoreTabBarProjectorTests.swift`

**Interface:** opaque `CoreTabBarProjectionRequest: Sendable` with `@MainActor static capture(store:repoCache:)`; `CoreTabBarProjector.project(_:cancellationCheck:) throws(CancellationError) -> CoreTabBarProjection`; package-visible Sendable/Equatable item output containing title, arrangement, visibility, minimized, zoom, pane-group, and active-tab facts.

- [ ] Add parity tests that feed identical facts through current readers and the pure projector for custom/default titles, worktree/enrichment precedence, empty title, arrangements/badges, minimized/zoom, pane capability, ordering, and active-tab fallback.
- [ ] Run `mise run test:swift -- --filter CoreTabBarProjector`; expect RED because the projector is absent.
- [ ] Capture raw stored COW tab-shell/graph/cursor, pane-graph, topology, enrichment, and zoom facts behind the Core factory; do not call `WorkspaceTabLayoutDerived.tabs` or `WorkspacePaneDerived.panes` during MainActor capture.
- [ ] Move reusable policy into nonisolated pure operations and make current actor-bound readers call the same policy. Add `Sendable` only to the existing value models that cross this boundary.
- [ ] Check cancellation at bounded intervals in every variable-cardinality loop and run parity plus existing `TabDisplayDerived`, `PaneDisplayDerived`, and `ArrangementDerived` tests GREEN.
- [ ] Commit `refactor: extract pure tab bar core projection`.

### Task 3: Pure Inbox attention facts

**Files:**
- Create `Sources/AgentStudio/Features/InboxNotification/Models/InboxAttentionProjector.swift`
- Modify `Sources/AgentStudio/Features/InboxNotification/State/MainActor/Atoms/InboxNotificationAtom.swift`
- Create `Tests/AgentStudioTests/Features/InboxNotification/Models/InboxAttentionProjectorTests.swift`

**Interface:** `InboxAttentionFactSnapshot: Equatable & Sendable`; `@MainActor InboxNotificationAtom.captureAttentionFacts()`; nonisolated `InboxAttentionProjector.project(snapshot:groups:cancellationCheck:)` returning group-to-`InboxNotificationClaimLane` facts without knowing tabs or colors.

- [ ] Add parity tests against `attentionLane(forPaneIds:)` for no contribution, each lane, read/dismissed facts, mixed groups, and red-over-amber-over-yellow precedence.
- [ ] Run `mise run test:swift -- --filter InboxAttentionProjector`; expect RED because the snapshot/projector are absent.
- [ ] Make capture retain an immutable COW notification-fact snapshot; move filtering and precedence into the pure projector and make the existing reader reuse it.
- [ ] Run projector and existing `InboxNotificationAtomTests` GREEN.
- [ ] Commit `refactor: extract inbox attention projection`.

### Task 4: Hard-cut `TabBarAdapter` to one coherent output

**Files:**
- Create `Sources/AgentStudio/App/Panes/TabBar/TabBarProjection.swift`
- Modify `Sources/AgentStudio/App/Panes/TabBar/TabBarAdapter.swift`
- Modify `Sources/AgentStudio/App/Panes/TabBar/CustomTabBar.swift` only for the visible-result telemetry hook from Task 6.
- Modify `Tests/AgentStudioTests/App/Panes/TabBarAdapterTests.swift`

**Interface:** `TabBarProjectionGeneration: Equatable & Sendable`; `TabBarProjectionRequest` combining generation, Core request, and Inbox snapshot; `TabBarProjection: Equatable & Sendable { items, activeTabID }`; pure cancellable `TabBarProjector.project(_:)`; adapter initializer receives concrete `InboxNotificationAtom` and retains one `EagerDerivedAtom`.

- [ ] Convert existing adapter behavior tests to bounded state/event waits and add RED tests for absent first output, coherent items/active ID, notification parity, unrelated/equal output suppression, leading-edge revocation, latest-wins overlap, and shutdown-before-release.
- [ ] Run `mise run test:swift -- --filter TabBarAdapter`; expect RED because the adapter still synchronously stores two independently assigned outputs and exposes no controllable materialization lifecycle.
- [ ] In `withObservationTracking.onChange`, call `sourceDidInvalidate()` synchronously, coalesce one MainActor post-mutation capture, advance generation once, re-register observation, and admit the newest request.
- [ ] Forward `tabs` and `activeTabId` from `materializedProjection.value`; observe publication only to update bounded overflow state. Delete stored copies, per-tab notification closures, synchronous `refresh()`, and its bootstrap fallback.
- [ ] Assemble every `TabBarItem`, Inbox color, and array equality off-main. Keep drag/drop frames, widths, overflow, and management-layer observation on MainActor.
- [ ] Run `mise run test:swift -- --filter TabBarAdapter` GREEN.
- [ ] Commit `feat: materialize tab bar projection off main actor`.

### Task 5: Window-owned construction and shutdown

**Files:**
- Modify `Sources/AgentStudio/App/Boot/AppDelegate.swift`
- Modify `Sources/AgentStudio/App/Boot/AppDelegate+LifecycleRouting.swift`
- Modify `Sources/AgentStudio/App/Boot/AppDelegate+WorkspaceBoot.swift`
- Modify `Sources/AgentStudio/App/Boot/AppDelegate+MainWindowCreation.swift`
- Modify `Sources/AgentStudio/App/Windows/MainWindowController.swift`
- Modify `Sources/AgentStudio/App/Windows/MainSplitViewController.swift`
- Modify `Sources/AgentStudio/App/Panes/PaneTabViewController.swift`
- Modify `Tests/AgentStudioTests/App/AppBootSequenceTests.swift`
- Modify `Tests/AgentStudioTests/App/Windows/MainWindowControllerPresentationFactsTests.swift`

- [ ] Add RED lifecycle tests proving each controller gets a distinct adapter, close stops the node through `MainWindowController.shutdown()` → split controller → pane controller → adapter, late completion cannot publish, and reopen creates a live fresh adapter.
- [ ] Run `mise run test:swift -- --filter AppBootSequenceTests` and `mise run test:swift -- --filter MainWindowControllerPresentationFactsTests`; expect RED because the adapter is still process-owned and the window controller has no shutdown chain.
- [ ] Remove process-owned `AppDelegate.tabBarAdapter` and boot construction. Construct the adapter inside `makeMainWindowController(dependencies:)` from process-owned store/cache/Inbox/trace dependencies.
- [ ] Make window close, replacement, and application termination call idempotent `MainWindowController.shutdown()` before host release; retain defensive adapter deinit stop without relying on deinit.
- [ ] Run the two lifecycle suites and `TabBarAdapterTests` GREEN.
- [ ] Commit `fix: bind tab bar materialization to window lifetime`.

### Task 6: Minimal existing measurement correction

**Files:**
- Modify `Sources/AgentStudio/Infrastructure/Diagnostics/AgentStudioPerformanceTraceRecorder.swift`
- Modify `Sources/AgentStudio/Infrastructure/Diagnostics/AgentStudioTraceEventQueue.swift`
- Modify `Sources/AgentStudio/Infrastructure/Diagnostics/AgentStudioOTLPTraceProjection.swift`
- Modify their existing tests under `Tests/AgentStudioTests/Infrastructure/Diagnostics/`
- Modify `scripts/verify-git-refresh-performance-workload.sh`, `scripts/compare-atomlib-v2-performance.py`, and `Tests/AgentStudioTests/Scripts/GitRefreshPerformanceWorkloadScriptTests.swift`

- [ ] Add RED tests proving disabled trace tags do not evaluate rich attribute builders and a bounded queue reports dropped-record count plus high-water mark.
- [ ] Run `mise run test:swift -- --filter AgentStudioPerformanceTraceRecorder`, `mise run test:swift -- --filter AgentStudioTraceEventQueue`, and `mise run test:swift -- --filter GitRefreshPerformanceWorkloadScriptTests`; expect RED because attributes are eager, queue completeness is absent, and the comparator still accepts incomplete provenance while requiring a universal 50% win.
- [ ] Make `record`/`recordDuration` attributes lazy until after tag admission. Add bounded events for Tab Bar capture, worker, publication, terminal outcome (`published`, `equal`, `superseded`, `cancelled`), and interaction-to-current/visible result, correlated only by run-local sequence.
- [ ] Extend the existing OTLP allowlist and fail-open tests for aggregate counts/durations only; export no UUID, title, path, request, or notification content.
- [ ] Extend the existing workload summary/comparator to require source and executable digest, workload fingerprint, trace tags, LaunchServices mode, issued-interaction count, one terminal outcome per admission, queue completeness, and independent final tab/active-tab equivalence before distributions are compared.
- [ ] Replace the comparator's universal 50% win with a frozen matched-baseline regression boundary recorded before candidate observation; keep missing/mismatched provenance as a hard rejection.
- [ ] Run recorder, queue, OTLP, and workload-script tests GREEN.
- [ ] Commit `test: make tab bar performance evidence complete`.

### Task 7: Final local proof on current HEAD

- [ ] Run plain `mise run setup`.
- [ ] Run focused filters for `EagerDerivedAtom`, `CoreTabBarProjector`, `InboxAttentionProjector`, `TabBarAdapter`, `AppBootSequenceTests`, `MainWindowControllerPresentationFactsTests`, `AgentStudioTraceEventQueue`, `AgentStudioPerformanceTraceRecorder`, and `GitRefreshPerformanceWorkloadScriptTests`; record commands, counts, and exit codes.
- [ ] Run `mise run test:architecture`, `mise run lint`, then the complete PR gate `mise run test`; require exit 0 on current HEAD.
- [ ] Start the shared stack, launch with `AGENTSTUDIO_IPC_DEBUG_TOKEN_ESCROW=1 mise run run-debug-observability -- --detach`, and verify with `AGENTSTUDIO_REQUIRE_LAUNCHSERVICES=1 mise run verify-debug-observability`.
- [ ] Without taking foreground focus, use existing authenticated IPC/state read-back to exercise tab navigation plus title, notification, zoom/arrangement updates; prove the same host reaches the final coherent items/active ID and typing/scroll continuity remains valid.
- [ ] Run the existing watched-folder workload once for the PR 1 parent baseline and once for the exact PR 2 candidate with identical frozen controls. Run the existing comparator; report provenance, issued/terminal continuity, queue loss/high-water, cardinalities, phase/end-to-end distributions, final-state oracle, and regression result. Make no improvement claim if acceptance is not proven.
- [ ] Inspect `git diff a4eb93c40...HEAD`, `git diff --check`, and excluded-path inventory; preserve unrelated work and stage only PR 2 files.

### Task 8: Stack, publish, and later review gate

- [ ] Commit any verified final scoped changes, push `feat/eager-derived-tabbar`, and open/update one draft PR based on `fix/atom-observation-followup`; do not merge either PR.
- [ ] Record exact PR 1 parent SHA, PR 2 HEAD, proof receipts, performance artifacts, CI, comments/threads, and mergeability in the PR.
- [ ] Only after both PRs are proof-ready, hand off to the one authorized independent Claude Opus 5/high plus `gpt-5.6-sol`/high review cycle with no inherited conversation. Parent-reduce findings, perform one bounded remediation pass, rerun affected and final gates, and do not dispatch a second review cycle without authorization.

## Completion boundary

PR 2 is review-ready only when the synchronous Tab Bar projector is gone, one window-owned node is the sole coherent output authority, every stale/shutdown interleaving is deterministic, current behavior is preserved, the complete local PR gate and detached LaunchServices proof pass, and the existing workload produces provenance-valid evidence. Failed or incomplete performance proof must be reported as failed; it cannot be converted into a readiness claim.
