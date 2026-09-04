# Pane And Tab Switching Without MainActor Stalls — Program Design

Date: 2026-09-04

Program Design identity: `PD-2026-09-04-PANE-SWITCH-MAINACTOR-RESIDUALS`

Requirements: [REQ-2026-09-04-PANE-SWITCH-MAINACTOR-RESIDUALS](2026-09-04-pane-switch-mainactor-residuals-requirements.md)

Specification: [SPEC-2026-09-04-PANE-SWITCH-MAINACTOR-RESIDUALS](2026-09-04-pane-switch-mainactor-residuals-specification.md)

## How the system works

A switch writes selection state through the existing pane focus executor. The
Repo Explorer command-presentation batch observes only the facts that decide
capabilities for the rows currently presented, wakes at most once per MainActor
turn, and refreshes at most once per wake. Sidebar content updates that change
no geometry rebind only their changed rows and leave the scroll offset alone.
The presentation coordinator republishes the visible snapshot only when the
snapshot or its consumer changed. One test lane mounts the real composition on
a store bound to the test core atoms, performs switches, and counts refreshes
and applies.

```text
user switch
  |
  v
PaneTabViewController.handlePaneFocusTrigger           [focus owner]
  -> PaneFocusOrchestrator.decide
       content click: already active -> .keep            UNCHANGED
       drawer tap:    already active -> .keep            CHANGED (was re-select)
  -> PaneFocusExecutor.apply -> selectPane / selectDrawerPane
  -> WorkspaceTabLayoutAtom.setActivePane                UNCHANGED (equal writes
                                                          already suppressed)
  |
  | AtomFamilySlot willSet on presented keys only
  v
RepoExplorerCommandPresentationBatch                    [command presentation owner]
  -> one pending wake per MainActor turn                 ADDED coalescing
  -> refresh: tracked reads = presented locations + visible repos
                                                        CHANGED (was all tabs × panes)
  -> resolve only affected requests; publish delta if changed   UNCHANGED
  |
  v
SidebarSurfaceHost -> RepoExplorerView -> RepoExplorerPresentationHostView
  -> Coordinator.update republishes only on snapshot or consumer change
                                                        CHANGED
  -> RepoExplorerTableMaterializer.apply
       content-only plan: reload changed rows, keep offset   CHANGED
       height/membership plan: frame, layout, anchor         UNCHANGED
```

No atom, store, event, coordinator, queue, persisted state, command, or IPC
method is added. The `armedTrackingGeneration` guard and `wake_trigger`
attribute from #323 remain.

## What is wrong in the current structure

1. `RepoExplorerCommandPresentationBatch.observeApprovedCapabilityFacts`
   (`Sources/AgentStudio/App/Windows/RepoExplorerCommandPresentationBatch.swift:373-416`)
   calls `WorkspaceLookupDerived.paneLocationsByWorktreeId`, which iterates
   every tab and every pane in the workspace and validates each association
   (`Sources/AgentStudio/Core/State/MainActor/Atoms/WorkspaceLookupDerived.swift:7-19`),
   then assembles a whole `Tab` per location through
   `WorkspaceTabLayoutDerived.tab(_:)`. The tracked read set is therefore the
   whole workspace: any pane, tab, or arrangement write anywhere wakes a
   refresh, and each refresh recomposes arrangement state for every presented
   tab. Live burst sample: 1,488 of 2,166 refresh samples in this function.
2. Every `onChange` wake schedules its own `Task`; N writes in one turn produce
   N refreshes (`RepoExplorerCommandPresentationBatch.swift:157-162`).
3. `PaneDrawerFocusDecider.decide` returns `.selectDrawerPane` for every
   `.selectPane` trigger with no already-active check
   (`Sources/AgentStudio/Core/PaneFocus/PaneDrawerFocusDecider.swift:9-15`),
   while `PaneContentClickFocusDecider.decide` keeps when
   `context.targetPaneIsAlreadyActive`
   (`Sources/AgentStudio/Core/PaneFocus/PaneContentClickFocusDecider.swift:18-26`).
4. `RepoExplorerTableMaterializer.apply` updates the table frame before every
   plan, `endUpdates` forces two layout passes and rebinds every represented
   cell, and `restore(anchor:)` scrolls and forces two more passes even for a
   content-only plan (`Sources/AgentStudio/Features/RepoExplorer/RepoExplorerTableMaterializer.swift:246-296,437-458,464-497`).
   12:21 production sample: 800 of 4,731 main-thread samples, 610 in
   restoration.
5. `RepoExplorerPresentationHostView.Coordinator.update` republishes
   `currentVisibleSnapshot` on every SwiftUI update
   (`Sources/AgentStudio/Features/RepoExplorer/RepoExplorerPresentationHostView.swift:136-150`),
   which runs `updateSidebarVisibleWorktrees` and the batch accept guard each
   time.
6. No test mounts `SidebarSurfaceHost` with a store bound to the core atoms;
   the parked probe built a standalone `WorkspaceStore()` while
   `RepoExplorerProjectionInputCapture` reads `CoreAtomScope.store`, so the
   projection saw an empty topology and the batch never engaged.

The rest remains authoritative: the pane focus decision model and executor,
`AtomFamily`/`@Observable` equal-write suppression, `WorkspaceTabArrangementAtom`
write path, the projection worker, `RepoExplorerMaterializationHost` generation
and transaction ownership, `RepoExplorerNativeTransactionApplier`, the native
plan builder's `content` versus `membership` classification, and #323.

## The structural crux and selected tradeoff

The crux is where the batch's knowledge of "which panes belong to presented
rows" comes from. Today it recomputes it from the whole workspace on every
wake. It could instead come from the presented rows themselves, which the
projection worker already computes off-main and the materializer already
holds.

| Alternative | Structure | Gain | Cost and failure mode | Decision |
| --- | --- | --- | --- | --- |
| Keep whole-workspace lookup, add capture equality | Recompute, compare, skip resolve | Fewer resolutions | Recompute is the cost (~1 ms); wakes and cost unchanged; R3 unmet | Rejected |
| Presented-location tracking | Materializer publishes pane locations of presented rows with the visible snapshot; batch reads per-key slots for those locations only, coalesces wakes per turn | Tracked set bounded by presented rows; unpresented writes never wake; refresh cost proportional to presented rows | Visible snapshot grows one field; batch depends on projection-provided locations being current (they are, per generation) | Selected |
| Move command presentation off MainActor | New actor computing capabilities | Removes cost from MainActor entirely | New owner, new actor boundary for MainActor-only dispatcher state; outside acceptable complexity | Rejected |
| Debounce refreshes on a timer | Timer-coalesced refresh | Fewer refreshes under bursts | Adds latency to real capability changes; timer is a mechanism the spec forbids as sole fix; ordering not preserved | Rejected |

The selected design spends complexity only on one added field in the visible
snapshot and a per-key read path in the batch. Revisit only if capability
resolution needs facts that are not per-key addressable.

## Component ownership and dependency direction

| Component | Owns | Consumed by | Changes when |
| --- | --- | --- | --- |
| `PaneDrawerFocusDecider` | Selection, responder, runtime decision for drawer triggers, including the already-active keep rule | `PaneFocusOrchestrator` | Drawer focus policy changes |
| `PaneFocusExecutor` | Applying decisions to store, responder, runtime | `PaneTabViewController` | Focus effect ownership changes |
| `RepoExplorerTableMaterializer` | Table transaction, content-only classification, geometry and anchor policy, viewport publication including presented pane locations | `RepoExplorerMaterializationHost` | Table cost or viewport policy changes |
| `RepoExplorerVisibleWorktreeSnapshot` | Visible worktrees, repositories, settled receipts, presented pane locations, target | Materializer, coordinator, batch | Presented-set contract changes |
| `RepoExplorerPresentationHostView.Coordinator` | Bridging SwiftUI updates to the host; last-published snapshot and consumer token | `RepoExplorerView` | SwiftUI bridging changes |
| `RepoExplorerCommandPresentationBatch` | Tracked read set bounded to presented keys, per-turn wake coalescing, tracking generation, resolution, publication, telemetry | `SidebarSurfaceHost` | Capability presentation policy changes |
| `SidebarSurfaceHostSwitchGuardTests` (lane) | Mounted composition, bound store, switch workload, refresh and apply counts | `mise run test` | Guard bounds change |

Allowed dependency direction:

```text
Core pane focus deciders -> App executor -> Core atoms
Features/RepoExplorer materializer -> visible snapshot -> App batch -> Core atoms per key
App sidebar host -> Features RepoExplorer view -> coordinator -> host/materializer
Tests -> App composition + Core test atoms
```

Forbidden edges:

- The batch must not iterate all tabs or all panes; it reads only slots keyed
  by presented locations, visible worktrees, and visible repositories.
- The materializer must not read atoms to compute locations; it forwards the
  projection-provided destinations of represented rows.
- The coordinator must not call the batch directly; it publishes through the
  existing closures only when snapshot or consumer token changed.
- Deciders must not read atoms; already-active facts come from
  `PaneFocusContext`.
- No timer, poll, or new observer anywhere in this design.

## Behavioral interfaces

### Drawer selection idempotence

`PaneDrawerFocusDecider.decide(.selectPane(parentPaneId, drawerPaneId))`
returns `selection: .keep` when `context.activeDrawer?.parentPaneId ==
parentPaneId && context.activeDrawer?.paneId == drawerPaneId`. Responder and
runtime actions for that case are the same as today's `.selectDrawerPane`
outcome (`.focusPaneHost(paneId: drawerPaneId)`, `.preserveRuntimeFocus`), so
focus reconciliation is unchanged and only the selection write disappears.
`PaneFocusExecutor.apply` is unchanged; `.keep` already writes nothing.

### Presented pane locations in the visible snapshot

`RepoExplorerVisibleWorktreeSnapshot` gains
`presentedPaneLocations: Set<RepoExplorerPresentedPaneLocation>` where a
location is `(worktreeID, tabID, paneID)`, derived by the materializer in
`publishVisibleRows` from the `paneDestinations` of represented rows
(`RepoExplorerMaterializationSnapshot.swift:21,39`). It changes only when the
represented set changes, so it takes part in the existing
`advanceVisibleTarget` comparison and never produces a new target on its own.
Equality includes it. Existing consumers that ignore it are unaffected.

### Bounded tracked reads in the batch

`observeApprovedCapabilityFacts(visibleWorktreeIDs:)` becomes
`observeApprovedCapabilityFacts(locations:)`. For each presented location it
reads, per key: the tab shell (`tabShellAtom.tabShell(tabID)`), the tab's
active arrangement and active pane through the cursor atom, zoom presentation
for that tab, structural facts for that pane, and drawer expansion for that
pane when it owns a drawer. It no longer calls `paneLocationsByWorktreeId` or
`WorkspaceTabLayoutDerived.tab(_:)`. The fingerprint keeps today's meaning
(active tab, management layer, per-location capability facts) with the
`tab: Tab?` field replaced by the per-key facts the dispatcher's repo-explorer
capability resolution reads; the planner proves the field set against
`AppCommandDispatcher.repoExplorerCommandPresentationSnapshot` and
`PaneTabViewController.targetedPaneExternalCommandCapability` with a test that
mutates each fact and asserts re-resolution. Visible-repo progress, topology
worktree/repo slots, favorite state, prefs sort order, and management layer
remain tracked as today.

### Per-turn wake coalescing

The batch keeps `pendingObservationRefresh: Bool`. `onChange` (generation
checked as in #323) sets it and schedules one `Task { @MainActor }` only when
it was false; the task clears it and calls `refresh(trigger: .observation)`.
A wake arriving while a refresh is pending folds into it. A wake arriving
during a running refresh schedules the next one. Ordering is preserved because
refresh always reads current atom state.

### Content-only application policy in the materializer

`apply` classifies the plan before mutating:

- `membership` or `content` with non-empty `heightReloadRowsInNewSpace`, or
  any reload row whose new `layout.requiresVisibleWidthMeasurement` is true:
  `requiresGeometryUpdate = true` (today's behavior: frame update, forced
  layout passes, height notes, anchor restoration, rebind all represented).
- otherwise `requiresGeometryUpdate = false`: no `updateTableFrame`, no forced
  layout pass, no anchor restoration; `endUpdates` reloads only the represented
  intersection of `reloadRowsInNewSpace`, rebinds only those rows, and stamps
  the readback for the represented set.

Counters `tableFrameUpdateCount`, `forcedLayoutPassCount`,
`explicitScrollRestorationCount` become `private(set)` observables for proof.
Width-measured rows are conservative: a changed row that requires visible
width measurement is treated as height-affecting.

### Coordinator republication

`Coordinator.update` receives `visibleSnapshotConsumerToken: UUID?` (the batch's
identity, passed by `SidebarSurfaceHost` through `RepoExplorerView`). It
republishes `currentVisibleSnapshot` only when the snapshot differs from
`lastPublishedVisibleSnapshot` or the token differs from
`lastPublishedConsumerToken`; both are updated on publish. Materializer-driven
publications continue to flow immediately through `publishVisibleWorktreeSnapshot`.
`applyCommandPresentationDelta` is called as today.

### Switch guard lane

`SidebarSurfaceHostSwitchGuardTests` (App/Windows tests) constructs the store
as `WorkspaceStore(catalogAtom: atoms.workspaceRepositoryTopology, graphAtom:
atoms.workspacePane, interactionAtom: atoms.workspaceTabLayout)` inside
`withAsyncTestCoreAtoms`, adds three repositories, two tabs and three panes
bound to worktrees, mounts `SidebarSurfaceHost` in a window, waits for the
first `command_presentation` record (engagement gate), performs one active-pane
switch and one tab switch, pumps bounded yields, and asserts refreshes per
switch ≤ 2 and materializer applies per switch ≤ 1 from the JSONL recorder and
`nativeTransactionApplyCount`. It runs in the fast Swift lane, therefore in
`mise run test`. A seeded regression (temporarily restoring per-update
republication) must fail it.

## State and lifecycle

Runtime-only state changes:

| State | Owner | Transition | Guard |
| --- | --- | --- | --- |
| `pendingObservationRefresh` | batch | false → true on wake; true → false when the refresh task starts | generation check precedes |
| `armedTrackingGeneration` | batch | unchanged from #323 | |
| `lastPublishedVisibleSnapshot`, `lastPublishedConsumerToken` | coordinator | set on publish | publish only on difference |
| `presentedPaneLocations` | visible snapshot (value) | recomputed per viewport publication | participates in target advance |
| drawer selection | arrangement atoms | unchanged; `.keep` performs no write | already-active predicate |

No persisted state changes. Illegal transitions: a refresh scheduled by a
stale generation is dropped (existing); a republish with an unchanged snapshot
and token is dropped (new); a content-only plan that later measures a height
change is not possible because width-measured rows are classified as
height-affecting.

## Current-to-proposed call-path deltas

```text
1. Drawer tap on the active drawer pane

CURRENT
PaneLeafContainer.onTapGesture -> handlePaneFocusTrigger(.drawer(.selectPane))
  -> PaneDrawerFocusDecider.decide -> .selectDrawerPane        REMOVED for active target
  -> PaneFocusExecutor.applySelection -> selectDrawerPane
  -> WorkspaceTabArrangementAtom.setActiveDrawerPane           REMOVED for active target
  -> responder .focusPaneHost                                   UNCHANGED

PROPOSED
  -> PaneDrawerFocusDecider.decide -> .keep                     CHANGED
  -> responder .focusPaneHost                                   UNCHANGED
Evidence: PaneDrawerFocusDecider.swift:9-15; PaneFocusExecutor.swift:106-128.
Result: no selection write, no coordinator write, no wake.
```

```text
2. Tracked-atom write -> batch refresh

CURRENT
AtomFamilySlot.acceptValue (any pane/tab/arrangement key)
  -> willSet -> batch onChange -> Task -> refresh                N tasks for N writes
  -> observeApprovedCapabilityFacts
       -> paneLocationsByWorktreeId (all tabs × all panes)       REMOVED
       -> WorkspaceTabLayoutDerived.tab per location (compose)   REMOVED
  -> resolve/publish                                              UNCHANGED

PROPOSED
AtomFamilySlot.acceptValue (presented key only wakes)
  -> willSet -> batch onChange -> generation check                UNCHANGED (#323)
  -> pendingObservationRefresh gate -> one Task per turn          ADDED
  -> refresh -> per-key reads for presentedPaneLocations          CHANGED
  -> resolve/publish                                              UNCHANGED
Evidence: RepoExplorerCommandPresentationBatch.swift:120-165,373-416;
WorkspaceLookupDerived.swift:7-19; live sample /tmp/agentstudio-storm-loop-4.sample.txt.
Result: unpresented writes wake nothing; presented writes cost one bounded refresh.
```

```text
3. Content-only sidebar update

CURRENT
materializer.apply -> updateTableFrame -> applier -> endUpdates
  -> layoutSubtreeIfNeeded ×2 -> reloadData(visible) -> rebindRepresentedCells
  -> restore(anchor) -> scroll -> layoutSubtreeIfNeeded ×2       REMOVED for content-only

PROPOSED
materializer.apply -> classify plan
  content-only: applier -> endUpdates -> reloadData(changed ∩ represented)
                -> rebind changed rows -> stamp readback           CHANGED
  geometry:     today's path                                       UNCHANGED
Evidence: RepoExplorerTableMaterializer.swift:246-296,437-497.
Result: scroll offset preserved; counters stay flat for content-only plans.
```

```text
4. SwiftUI update of the presentation host

CURRENT
updateNSView -> Coordinator.update -> onVisibleWorktreeSnapshotChange(current)   REMOVED when unchanged
  -> applyCommandPresentationDelta                                               UNCHANGED

PROPOSED
updateNSView -> Coordinator.update
  -> publish only if snapshot != lastPublished || token != lastToken            CHANGED
  -> applyCommandPresentationDelta                                               UNCHANGED
Evidence: RepoExplorerPresentationHostView.swift:136-150; SidebarSurfaceHost.swift:73-111.
Result: a new batch still receives the current snapshot once; steady updates publish nothing.
```

```text
5. Switch guard lane (proposed-only, no predecessor)

withAsyncTestCoreAtoms -> bound WorkspaceStore -> repos/tabs/panes
  -> NSHostingView(SidebarSurfaceHost) in NSWindow -> engagement gate
  -> setActivePane / setActiveTab -> bounded yields -> JSONL counts
Evidence: parked probe (scratchpad) failed only because the store was unbound;
RepoExplorerViewActivePaneFocusTests.swift:30-41 shows the bound-store form.
Result: fails on refreshes per switch > 2, applies per switch > 1, or no engagement.
```

## Failure, recovery, and partial success

| Condition | Detection | Containment | Recovery | Observable |
| --- | --- | --- | --- | --- |
| Presented locations stale after a projection race | Generation on the visible snapshot | Batch resolves against current atoms; stale locations only widen the tracked set until the next publication | Next viewport publication replaces them | At most one extra refresh |
| A capability fact not in the per-key set changes | Proof seam test mutating each fact | Fingerprint miss → stale presentation until next affected wake | Planner adds the missing key; test fails until then | Test failure, not runtime corruption |
| Content-only misclassification (height actually changed) | Conservative rule on width-measured rows; height cache | Row re-measured on next geometry plan | Existing `noteHeightOfRows` path | Visible only as a one-frame height lag, bounded |
| Coordinator token missing (batch nil) | `nil` token | Publish once when the batch appears (token changes nil → id) | Existing lifecycle | Batch receives snapshot exactly once |
| Wake during refresh | `pendingObservationRefresh` | One follow-up refresh | Same path | No lost update |

## Concurrency and consistency

All owners are MainActor. Ordering: atom writes are synchronous; the batch's
single pending task runs after the current turn, reading current state, so
coalescing never observes a torn intermediate. The materializer publishes
viewport changes through its existing sequence/cancellation. No new actors,
locks, or async boundaries.

## Compatibility and cutover

Hard internal cutover, runtime-only. No persisted, IPC, command, or schema
change. Rollback is code-only. #323 stays.

## Cross-cutting realization

| Obligation | Owner and mechanism | Degradation | Proof seam |
| --- | --- | --- | --- |
| Performance R1/R2/R3/R5 | Bounded tracked set, per-turn coalescing, content-only policy, republish suppression | One extra refresh on stale locations | Refresh and apply counts per switch; materializer counters; tab-bar queue wait |
| Responsiveness | Same | Same | Debug-app switch workload, production comparison |
| Observability R8 | `wake_trigger` (#323) plus existing stage snapshots | Fail-open exporter | OTLP projection test; VictoriaLogs by service.version |
| Reliability R9 | No persisted change | — | Install/downgrade round trip |
| Privacy | No new attributes with paths or content | — | Attribute allowlist |
| Accessibility | No UI change | — | Existing focus tests |

## How each requirement is realized and verified

| Requirement | Realization | Proof seam | Enforcement |
| --- | --- | --- | --- |
| R1 switch budget | Deltas 1–4 together | Tab-bar queue wait in debug workload and production | Runtime measurement |
| R2 refreshes per switch bounded, age-invariant | #323 generation + per-turn coalescing + presented-key tracking | Lane counts after 200 prior publications | Lane test |
| R3 unpresented facts no refresh | Presented-key tracking | Test: write to unpresented pane/tab → 0 observation refreshes; presented → 1 | Batch unit test |
| R4 re-selection no-op | Drawer decider keep rule | Decider test + executor test: no write, no refresh | Unit tests |
| R5 content-only cost | Materializer classification | Counters flat, offset unchanged, only changed rows rebound | Materializer tests |
| R6 republish suppression | Coordinator token + last-published | Host view test: N identical updates → 0 publications; new token → 1 | Host view test |
| R7 gate lane | Switch guard lane in fast Swift lane | Seeded regression fails | `mise run test` |
| R8 telemetry | #323 | Projection test (exists) | — |
| R9 compatibility | No persisted change | Round trip | Manual |
