# PR 2 — Keyed Eager Derivation and Tab Bar Implementation Plan

> **For agentic workers:** Use subagent-driven development or executing-plans task by task. Every step below is a checkbox and every implementation delegate receives its paths, proof gate, and stop condition.

**Goal:** Replace synchronous MainActor Tab Bar item reconstruction with a total, cancellation-only `EagerDerivedAtomFamily` that owns one independently current node per tab, then publish one coherent ordered Tab Bar projection, stacked on PR 1.

**Architecture:** `TabBarAdapter` observes order and active selection globally, captures immutable Core and Inbox facts per tab, synchronously revokes only the changed tab from Observation's leading edge, and admits that key to its stable latest-wins family member. The family owns keyed node lifecycle and readiness. Core and Inbox own pure policy; App owns tab grouping, validation, ordering, the all-current barrier, notification color mapping, and final coherent projection. Each window owns and stops its adapter and family.

**Tech stack:** Swift 6.2 strict concurrency, Swift Observation, Swift Testing, existing ArchitectureLint, trace runtime, Victoria workload, debug IPC, and LaunchServices runner.

## Scope guard

- Only the total cancellation-only eager node, its narrow keyed family, the tab-scoped source-family corrections required for key isolation, and Tab Bar adoption are authorized.
- No SQLite, Repo Explorer/Inbox worker migration, Command Bar, broad pane/tab family migration, target split, fallible mode, scheduler/queue/retry system, second projection, new proof framework, or foreground UI control.
- Preserve one output authority: remove synchronous `refresh()` in the same cutover; do not add fallback or compatibility paths.
- Stop for a new ownership/public contract, reverse target edge, product type in Infrastructure, or proof-framework expansion.

Reorder and active-selection changes reuse current family values without
reprojecting retained tabs. Appending a tab materializes only that key. Removing
a tab stops only that key before publishing the remaining current cohort.

## Requirement and proof matrix

| Requirement | Implementation seam | Required proof |
|---|---|---|
| RS-05, RS-09, RS-10 | `EagerDerivedAtomFamily` identity, keyed admission/readiness, coherent output | stable per-key nodes, unrelated-key isolation, deterministic latest-wins, equal-output currentness, push admission |
| RS-11, RS-12 | `Sendable` request/result/projector and detached CPU work | strict build, compile-negative transfer fixture, Core/App parity |
| RS-13, RS-14 | per-key revocation, generation admission, removal, cohort barrier, irreversible stop | pre-successor invalidation, overlap, cancellation-ignoring stale completion, departed-key rejection, mixed-generation suppression, shutdown |
| RS-21–RS-23 | generic Infrastructure node; Core/Inbox policy; App composition | ArchitectureLint, target builds, no product names in AtomLib |
| RS-24–RS-26 | existing trace queue/recorder/workload/comparator | lazy disabled path, queue completeness, matched provenance and distributions |
| RS-27, RS-28 | one host and window-owned lifecycle | focused/full tests, detached LaunchServices interaction and state read-back |

---

### Task 1: Total latest-wins node and keyed family

**Files:**
- Create `Sources/AgentStudio/Infrastructure/AtomLib/EagerDerivedAtom.swift`
- Create `Sources/AgentStudio/Infrastructure/AtomLib/EagerDerivedAtomFamily.swift`
- Create `Tests/AgentStudioTests/Infrastructure/AtomLib/EagerDerivedAtomTests.swift`
- Create `Tests/AgentStudioTests/Infrastructure/AtomLib/EagerDerivedAtomFamilyTests.swift`
- Create `Tests/AgentStudioTests/Fixtures/AtomLibCompileFailures/EagerDerivedAtomNonSendableRequest.swift.fixture`
- Create `scripts/verify-atomlib-compile-failures.sh`
- Create `Tests/AgentStudioTests/Scripts/AtomLibCompileFailureScriptTests.swift`
- Modify `.mise.toml` to add `test:atomlib-compile-negative` to the existing aggregate; do not treat excluded fixtures alone as proof.

**Interface:** Retain the implemented `@MainActor @Observable package final class EagerDerivedAtom<Request: Sendable, RequestIdentity: Equatable & Sendable, Value: Sendable>`. Add package-internal `@MainActor final class EagerDerivedAtomFamily<Key: Hashable & Sendable, Request: Sendable, RequestIdentity: Equatable & Sendable, Value: Sendable>` with stable `materialize(for:)`, lookup, keyed `admit`, readiness-gated `currentValue(for:)`, removal that stops before erasing, keyed completion forwarding, and idempotent irreversible `stop()`.

- [ ] Add tests using continuations/gates, never sleeps, for initial publication, equal request no-op, successor cancellation, stale completion that ignores cancellation, equal current completion preserving value/revision, synchronous invalidation before successor admission, repeated invalidation, stop-before-completion, repeated stop, and rejected post-stop admission.
- [ ] Add family tests proving same-key stable identity, different-key isolation, admission clearing only that key's readiness, `.published` and `.equal` readiness, superseded/cancelled non-readiness, remove-before-erase, retention until every overlapping cancelled task settles, distinct rematerialization, keyed completion routing, stop-all, and rejected post-stop materialization/admission.
- [ ] Run `mise run test:swift -- --filter 'EagerDerivedAtomTests|EagerDerivedAtomFamilyTests'`; expect the family suite RED because the type is absent.
- [ ] Implement one `Synchronization.Mutex` revocation epoch, one MainActor generation, one retained user-initiated detached task, off-main equality against the previous `Sendable` value, and MainActor admission requiring generation, identity, and epoch. `sourceDidInvalidate()` advances correctness synchronously; its bounded MainActor bookkeeping may mirror `.invalidated(identity)` only when that admitted epoch is still stale.
- [ ] Keep freshness bookkeeping separate from output observation; only unequal current output changes `value`, first publication keeps revision `0`, and each later unequal publication advances it once.
- [ ] Keep source Observation, product ordering, aggregate publication, item validation, telemetry, and scheduling out of the family.
- [ ] Run the focused tests and `mise run test:atomlib-compile-negative`; expect GREEN only when the fixture is rejected for violating `Request: Sendable`.
- [ ] Commit `feat: add keyed eager derived atom lifecycle`.

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

**Interface:** opaque `CoreTabBarProjectionRequest: Sendable` with `@MainActor static capture(tabId:store:repoCache:)`; `CoreTabBarProjector.project(_:cancellationCheck:) throws(CancellationError) -> CoreTabBarProjection`; package-visible Sendable/Equatable single-tab output containing title, arrangement, visibility, minimized, zoom, and pane-group facts.

- [ ] Add parity tests that feed identical facts through current readers and the pure projector for custom/default titles, worktree/enrichment precedence, empty title, arrangements/badges, minimized/zoom, pane capability, ordering, and active-tab fallback.
- [ ] Run `mise run test:swift -- --filter CoreTabBarProjector`; expect RED because the projector is absent.
- [ ] Capture only the selected tab's keyed shell/graph/cursor, pane-graph, topology, enrichment, and zoom facts behind the Core factory; do not call `WorkspaceTabLayoutDerived.tabs`, `WorkspacePaneDerived.panes`, or a fleet snapshot during a hot per-tab capture.
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

### Task 4: Hard-cut `TabBarAdapter` to a keyed eager family and one coherent output

**Files:**
- Create `Sources/AgentStudio/App/Panes/TabBar/TabBarProjection.swift`
- Modify `Sources/AgentStudio/App/Panes/TabBar/TabBarAdapter.swift`
- Modify `Sources/AgentStudio/App/Panes/TabBar/CustomTabBar.swift` only for the visible-result telemetry hook from Task 6.
- Modify `Tests/AgentStudioTests/App/Panes/TabBarAdapterTests.swift`
- Hard-cut the initializer at every current construction site; pass an existing concrete Inbox atom or an explicit fixture atom:
  - `Sources/AgentStudio/App/Boot/AppDelegate+WorkspaceBoot.swift`
  - `Sources/AgentStudio/App/Panes/TabBar/CustomTabBar.swift` preview
  - `Tests/AgentStudioTests/App/ObservableStoreTests.swift`
  - `Tests/AgentStudioTests/App/PaneTabViewControllerCommandTestSupport.swift`
  - `Tests/AgentStudioTests/App/PaneTabViewControllerEditorChooserCommandTests.swift`
  - `Tests/AgentStudioTests/App/PaneTabViewControllerLaunchRestoreTests.swift`
  - `Tests/AgentStudioTests/App/PaneTabViewControllerTabRetentionTests.swift`
  - `Tests/AgentStudioTests/App/Terminal/TerminalPaneMountViewExitBehaviorTests.swift`
  - `Tests/AgentStudioTests/App/Windows/MainSplitViewControllerTestSupport.swift`
  - `Tests/AgentStudioTests/App/Windows/MainWindowControllerInboxToolbarButtonTests.swift`
  - `Tests/AgentStudioTests/App/Windows/MainWindowControllerPresentationFactsTests.swift`

**Interface:** `TabBarProjectionGeneration: Equatable & Sendable`; per-tab `TabBarProjectionRequest` combining generation, Core request, and keyed Inbox attention lane; one-item `TabBarProjection`; pure cancellable `TabBarProjector.project(_:)`; adapter initializer receives concrete `InboxNotificationAtom` and retains one `EagerDerivedAtomFamily<UUID, ...>`.

- [ ] Convert existing adapter behavior tests to bounded state/event waits and add RED tests for absent first output, coherent items/active ID, notification parity, owning-tab-only projection, unrelated/equal output suppression, leading-edge revocation, latest-wins overlap, append-only-new-key projection, reorder reuse, removed-key rejection, out-of-order cohort completion, equal-completion barrier release, and shutdown-before-release.
- [ ] Run `mise run test:swift -- --filter TabBarAdapter`; expect RED until keyed eager lifecycle is family-owned and current behavior passes.
- [ ] Observe only ordered IDs and active selection globally. Install one `withObservationTracking` capture per tab; its callback calls that stable child's `sourceDidInvalidate()` synchronously, schedules post-mutation capture, re-registers only that tab, advances generation, and admits only that key.
- [ ] Replace `materializedProjectionByTabId`, `admittedProjectionGenerationByTabId`, `readyProjectionGenerationByTabId`, and `itemByTabId` with the family. Keep only product observation generation, ordered IDs, requested active ID, aggregate publication, and UI bookkeeping in the adapter.
- [ ] Validate one matching item from each readiness-gated family value, order by current IDs, and publish only when every retained key is current. Preserve the prior coherent aggregate while any required key is pending; `.equal` completion must release the barrier without replacing its value.
- [ ] Assemble each `TabBarItem`, Inbox color, and per-tab equality off-main. Reorder and active selection reuse current materialized items. Keep aggregate ordering/equality, drag/drop frames, widths, overflow, and management-layer observation on MainActor.
- [ ] Require a concrete `InboxNotificationAtom` at every constructor call. Do not add a default atom, compatibility initializer, notification closure, or second projection path.
- [ ] Run `mise run test:swift -- --filter TabBarAdapter` GREEN.
- [ ] Commit `feat: materialize keyed tab bar projections off main actor`.

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

- [ ] Add RED lifecycle tests proving each controller gets a distinct adapter, close stops the family and every child through `MainWindowController.shutdown()` → split controller → pane controller → adapter, late completion cannot publish, and reopen creates a live fresh adapter and family.
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
- [ ] Run focused filters for `EagerDerivedAtom`, `EagerDerivedAtomFamily`, `CoreTabBarProjector`, `InboxAttentionProjector`, `WorkspaceTabGraphAtom`, `WorkspaceArrangementCursorAtom`, `TabBarAdapter`, `AppBootSequenceTests`, `MainWindowControllerPresentationFactsTests`, `AgentStudioTraceEventQueue`, `AgentStudioPerformanceTraceRecorder`, and `GitRefreshPerformanceWorkloadScriptTests`; record commands, counts, and exit codes.
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

PR 2 is review-ready only when synchronous Tab Bar item projection is gone, one window-owned family is the sole per-tab materialization/readiness authority, `TabBarAdapter` is the sole coherent ordered-output authority, every keyed stale/removal/shutdown interleaving is deterministic, current behavior is preserved, the complete local PR gate and detached LaunchServices proof pass, and the existing workload produces provenance-valid evidence. Failed or incomplete performance proof must be reported as failed; it cannot be converted into a readiness claim.
