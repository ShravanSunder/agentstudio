# LUNA-350 Runtime Envelope + Workspace Persistence + Sidebar Rewire Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Ship the new event-driven workspace architecture end-to-end: 3-tier runtime envelopes, canonical/cache/UI persistence split, sequential filesystem->git->forge enrichment, and sidebar rewiring with zero direct store mutations.

**Architecture:** This implementation uses one typed `EventBus<RuntimeEnvelope>` fan-out channel with strict envelope scoping (`SystemEnvelope`, `WorktreeEnvelope`, `PaneEnvelope`) and per-source sequencing. Topology and enrichment flow through `WorkspaceCacheCoordinator`, which is the only consumer allowed to mutate canonical/cache stores from event-plane inputs. Sidebar becomes a pure reader of `WorkspaceStore`, `WorkspaceCacheStore`, and `WorkspaceUIStore`.

**Tech Stack:** Swift 6.2, AppKit + SwiftUI, `@Observable`, `AsyncStream`, Swift Testing (`@Suite`, `@Test`), `mise` tasks, `gh`/GitHub API integration via actor boundary.

---

## Architecture References (Authoritative)

- [Pane Runtime Architecture - Three Data Flow Planes](../architecture/pane_runtime_architecture.md#three-data-flow-planes)
- [Pane Runtime Architecture - Contract 3: Event Envelope](../architecture/pane_runtime_architecture.md#contract-3-event-envelope) (current `PaneEventEnvelope` + target `RuntimeEnvelope`)
- [Pane Runtime Architecture - Envelope Invariants](../architecture/pane_runtime_architecture.md#envelope-invariants-normative)
- [Pane Runtime Architecture - Contract 6: Filesystem Batching](../architecture/pane_runtime_architecture.md#contract-6-filesystem-batching)
- [Pane Runtime Architecture - Contract 14: Replay Buffer](../architecture/pane_runtime_architecture.md#contract-14-replay-buffer)
- [Pane Runtime Architecture - Event Scoping Invariants](../architecture/pane_runtime_architecture.md#event-scoping)
- [Pane Runtime Architecture - Architectural Invariants (A10: Replay)](../architecture/pane_runtime_architecture.md#replay--recovery)
- [Pane Runtime EventBus Design - The Multiplexing Rule](../architecture/pane_runtime_eventbus_design.md#the-multiplexing-rule)
- [Pane Runtime EventBus Design - Bus Enrichment Rule](../architecture/pane_runtime_eventbus_design.md#bus-enrichment-rule)
- [Pane Runtime EventBus Design - Actor Inventory](../architecture/pane_runtime_eventbus_design.md#actor-inventory)
- [Pane Runtime EventBus Design - Threading Model](../architecture/pane_runtime_eventbus_design.md#threading-model)
- [Workspace Data Architecture - Three Persistence Tiers](../architecture/workspace_data_architecture.md#three-persistence-tiers)
- [Workspace Data Architecture - Enrichment Pipeline](../architecture/workspace_data_architecture.md#enrichment-pipeline)
- [Workspace Data Architecture - Event Namespaces](../architecture/workspace_data_architecture.md#event-namespaces)
- [Workspace Data Architecture - Ordering, Replay, and Idempotency](../architecture/workspace_data_architecture.md#ordering-replay-and-idempotency)
- [Workspace Data Architecture - Direct Store Mutation Callsites (12 total)](../architecture/workspace_data_architecture.md#direct-store-mutation-callsites-12-total)
- [Workspace Data Architecture - Migration from Current Models](../architecture/workspace_data_architecture.md#migration-from-current-models)
- [Workspace Data Architecture - Sidebar Data Flow](../architecture/workspace_data_architecture.md#sidebar-data-flow)
- [Component Architecture - Section 2.2: Contamination Table](../architecture/component_architecture.md#22-repo--worktree)

---

## Supersedes

This plan replaces and consolidates:
- `docs/plans/sidebar-repo-metadata-grouping-filtering-spec.md`
- `docs/plans/sidebar-cwd-dedupe-test-spec.md`
- `docs/plans/sidebar-cwd-dedupe-requirements.md`
- `docs/plans/2026-03-01-luna-350-forgeactor-workspace-persistence-segregation-sidebar-rewiring.md`
- `docs/plans/2026-02-28-luna-349-filesystem-git-actor-split.md`
- `docs/plans/2026-02-27-luna-349-test-value-plan.md`
- `docs/plans/2026-02-27-luna-349-fs-event-source-and-runtime-conformers.md`
- `docs/plans/2026-02-21-pane-runtime-luna-295-luna-325-mapping.md`
- `docs/plans/2026-02-22-luna-325-contract-parity-execution-plan.md`
- `docs/plans/2026-02-25-workspace-persistence-segregation.md`

## Execution Standards

- Use `@superpowers/executing-plans` for task-by-task execution.
- Use `@superpowers/verification-before-completion` before completion claims.
- Keep commits frequent: one commit per task.
- Keep tests deterministic: no sleeps for ordering tests unless required by API contract.

### Task 1: Introduce `RuntimeEnvelope` 3-Tier Contract

**Files:**
- Create: `Sources/AgentStudio/Core/PaneRuntime/Contracts/RuntimeEnvelope.swift`
- Modify: `Sources/AgentStudio/Core/PaneRuntime/Contracts/PaneEventEnvelope.swift`
- Modify: `Sources/AgentStudio/Core/PaneRuntime/Contracts/PaneContextFacets.swift`
- Test: `Tests/AgentStudioTests/Core/PaneRuntime/Contracts/RuntimeEnvelopeContractsTests.swift`

**Step 1: Write the failing test**

```swift
@Suite("RuntimeEnvelope contracts")
struct RuntimeEnvelopeContractsTests {
    @Test("topology events use SystemEnvelope")
    func topologyRequiresSystemEnvelope() {
        let event = SystemScopedEvent.topology(.repoDiscovered(repoPath: URL(fileURLWithPath: "/tmp/repo"), parentPath: URL(fileURLWithPath: "/tmp")))
        let envelope = RuntimeEnvelope.system(SystemEnvelope.makeForTest(event: event))
        #expect(envelope.systemEnvelope != nil)
    }
}
```

**Step 2: Run test to verify it fails**

Run: `SWIFT_BUILD_DIR=".build-agent-runtime-envelope" swift test --build-path "$SWIFT_BUILD_DIR" --filter "RuntimeEnvelopeContractsTests" > /tmp/luna350-task1.log 2>&1; echo $?`
Expected: non-zero exit, missing `RuntimeEnvelope`/`SystemEnvelope` symbols.

**Step 3: Write minimal implementation**

```swift
enum RuntimeEnvelope: Sendable {
    case system(SystemEnvelope)
    case worktree(WorktreeEnvelope)
    case pane(PaneEnvelope)
}
```

Add concrete structs (`SystemEnvelope`, `WorktreeEnvelope`, `PaneEnvelope`) with required/optional fields from [Workspace Data Architecture - Event Namespaces](../architecture/workspace_data_architecture.md#event-namespaces) and [Pane Runtime Architecture - Contract 3: Event Envelope](../architecture/pane_runtime_architecture.md#contract-3-event-envelope). Include base fields on all tiers: `eventId`, `source`, `seq`, `timestamp`, `schemaVersion`, plus optional `correlationId`, `causationId`, `commandId`.

**Step 4: Run test to verify it passes**

Run: `SWIFT_BUILD_DIR=".build-agent-runtime-envelope" swift test --build-path "$SWIFT_BUILD_DIR" --filter "RuntimeEnvelopeContractsTests" > /tmp/luna350-task1.log 2>&1; echo $?`
Expected: exit code `0`.

**Step 5: Commit**

```bash
git add Sources/AgentStudio/Core/PaneRuntime/Contracts/RuntimeEnvelope.swift \
  Sources/AgentStudio/Core/PaneRuntime/Contracts/PaneEventEnvelope.swift \
  Sources/AgentStudio/Core/PaneRuntime/Contracts/PaneContextFacets.swift \
  Tests/AgentStudioTests/Core/PaneRuntime/Contracts/RuntimeEnvelopeContractsTests.swift
git commit -m "feat(runtime): add 3-tier RuntimeEnvelope contracts"
```

### Task 2: Split Event Namespaces by Producer Boundary

**Files:**
- Modify: `Sources/AgentStudio/Core/PaneRuntime/Contracts/PaneRuntimeEvent.swift`
- Modify: `Sources/AgentStudio/Core/PaneRuntime/Sources/FilesystemActor.swift`
- Modify: `Sources/AgentStudio/Core/PaneRuntime/Sources/GitWorkingDirectoryProjector.swift`
- Test: `Tests/AgentStudioTests/Core/PaneRuntime/Sources/FilesystemActorTests.swift`
- Test: `Tests/AgentStudioTests/Core/PaneRuntime/Sources/GitWorkingDirectoryProjectorTests.swift`

**Step 1: Write the failing tests**

```swift
@Test("filesystem actor emits topology only for repo discovered/removed")
func emitsTopologyForRepoLifecycle() async { /* ... */ }

@Test("git projector emits branchChanged under GitWorkingDirectoryEvent")
func emitsGitNamespace() async { /* ... */ }
```

**Step 2: Run tests to verify failure**

Run: `SWIFT_BUILD_DIR=".build-agent-namespace-split" swift test --build-path "$SWIFT_BUILD_DIR" --filter "FilesystemActorTests|GitWorkingDirectoryProjectorTests" > /tmp/luna350-task2.log 2>&1; echo $?`
Expected: assertions fail on old namespace routing.

**Step 3: Write minimal implementation**

```swift
enum SystemScopedEvent: Sendable { case topology(TopologyEvent), appLifecycle(AppLifecycleEvent), focusChanged(FocusChangeEvent), configChanged(ConfigChangeEvent) }
enum WorktreeScopedEvent: Sendable { case filesystem(FilesystemEvent), gitWorkingDirectory(GitWorkingDirectoryEvent), forge(ForgeEvent), security(SecurityEvent) }
```

Route:
- `.repoDiscovered/.repoRemoved` -> `SystemEnvelope(.topology(...))`
- `.filesChanged` -> `WorktreeEnvelope(.filesystem(...))`
- `.snapshotChanged/.branchChanged/.originChanged/.worktreeDiscovered/.worktreeRemoved` -> `WorktreeEnvelope(.gitWorkingDirectory(...))`

**Step 4: Run tests to verify pass**

Run: same command from Step 2.
Expected: exit code `0`.

**Step 5: Commit**

```bash
git add Sources/AgentStudio/Core/PaneRuntime/Contracts/PaneRuntimeEvent.swift \
  Sources/AgentStudio/Core/PaneRuntime/Sources/FilesystemActor.swift \
  Sources/AgentStudio/Core/PaneRuntime/Sources/GitWorkingDirectoryProjector.swift \
  Tests/AgentStudioTests/Core/PaneRuntime/Sources/FilesystemActorTests.swift \
  Tests/AgentStudioTests/Core/PaneRuntime/Sources/GitWorkingDirectoryProjectorTests.swift
git commit -m "feat(events): split topology filesystem git namespaces"
```

### Task 3: Migrate Bus to `EventBus<RuntimeEnvelope>` + Bus Replay Contract

**Files:**
- Modify: `Sources/AgentStudio/Core/PaneRuntime/Events/EventBus.swift`
- Modify: `Sources/AgentStudio/Core/PaneRuntime/Events/EventChannels.swift`
- Modify: `Sources/AgentStudio/Core/PaneRuntime/Reduction/NotificationReducer.swift`
- Modify: `Sources/AgentStudio/Core/PaneRuntime/Runtime/PaneRuntimeEventChannel.swift`
- Create: `Tests/AgentStudioTests/Core/PaneRuntime/Events/EventBusRuntimeEnvelopeTests.swift`

**Step 1: Write failing tests**

```swift
@Test("bus replays up to 256 events per source for late subscribers")
func busReplayBoundedPerSource() async { /* ... */ }

@Test("lossy ordering preserves per-source seq within flush batch")
func notificationReducerOrdering() async { /* ... */ }
```

**Step 2: Run tests to verify failure**

Run: `SWIFT_BUILD_DIR=".build-agent-bus-migration" swift test --build-path "$SWIFT_BUILD_DIR" --filter "EventBusRuntimeEnvelopeTests|NotificationReducerTests" > /tmp/luna350-task3.log 2>&1; echo $?`
Expected: failure on missing bus replay behavior and envelope type mismatch.

**Step 3: Write minimal implementation**

```swift
enum PaneRuntimeEventBus {
    static let shared = EventBus<RuntimeEnvelope>()
}
```

Add bus replay buffer keyed by `EventSource` with cap `256`, and adapt reducer consumption to `RuntimeEnvelope` classification.

**Step 4: Run tests to verify pass**

Run: same command from Step 2.
Expected: exit code `0`.

**Step 5: Commit**

```bash
git add Sources/AgentStudio/Core/PaneRuntime/Events/EventBus.swift \
  Sources/AgentStudio/Core/PaneRuntime/Events/EventChannels.swift \
  Sources/AgentStudio/Core/PaneRuntime/Reduction/NotificationReducer.swift \
  Sources/AgentStudio/Core/PaneRuntime/Runtime/PaneRuntimeEventChannel.swift \
  Tests/AgentStudioTests/Core/PaneRuntime/Events/EventBusRuntimeEnvelopeTests.swift
git commit -m "feat(eventbus): migrate to RuntimeEnvelope and add bounded bus replay"
```

### Task 4: Add Cache/UI Stores and Persistence Segregation

**Files:**
- Create: `Sources/AgentStudio/Core/Stores/WorkspaceCacheStore.swift`
- Create: `Sources/AgentStudio/Core/Stores/WorkspaceUIStore.swift`
- Modify: `Sources/AgentStudio/Core/Stores/WorkspacePersistor.swift`
- Modify: `Sources/AgentStudio/Core/Stores/WorkspaceStore.swift`
- Test: `Tests/AgentStudioTests/Core/Stores/WorkspacePersistorTests.swift`
- Create: `Tests/AgentStudioTests/Core/Stores/WorkspaceCacheStoreTests.swift`

**Step 1: Write failing tests**

```swift
@Test("persists canonical, cache, and ui state to separate files")
func persistsThreeTierState() throws { /* ... */ }
```

**Step 2: Run tests to verify failure**

Run: `SWIFT_BUILD_DIR=".build-agent-persistence-split" swift test --build-path "$SWIFT_BUILD_DIR" --filter "WorkspacePersistorTests|WorkspaceCacheStoreTests" > /tmp/luna350-task4.log 2>&1; echo $?`
Expected: failure due to missing cache/UI stores and file split.

**Step 3: Write minimal implementation**

```swift
// workspace.state.json (canonical), workspace.cache.json (derived), workspace.ui.json (preferences)
```

Implement load/save APIs for all three files and keep existing workspace restore path deterministic.

**Step 4: Run tests to verify pass**

Run: same command from Step 2.
Expected: exit code `0`.

**Step 5: Commit**

```bash
git add Sources/AgentStudio/Core/Stores/WorkspaceCacheStore.swift \
  Sources/AgentStudio/Core/Stores/WorkspaceUIStore.swift \
  Sources/AgentStudio/Core/Stores/WorkspacePersistor.swift \
  Sources/AgentStudio/Core/Stores/WorkspaceStore.swift \
  Tests/AgentStudioTests/Core/Stores/WorkspacePersistorTests.swift \
  Tests/AgentStudioTests/Core/Stores/WorkspaceCacheStoreTests.swift
git commit -m "feat(stores): split workspace persistence into canonical cache ui tiers"
```

### Task 5: Add `WorkspaceCacheCoordinator` Consolidation Consumer

**Files:**
- Create: `Sources/AgentStudio/App/WorkspaceCacheCoordinator.swift`
- Modify: `Sources/AgentStudio/App/PaneCoordinator.swift`
- Modify: `Sources/AgentStudio/App/AppDelegate.swift`
- Create: `Tests/AgentStudioTests/App/WorkspaceCacheCoordinatorTests.swift`

**Step 1: Write failing tests**

```swift
@Test("coordinator consumes system topology and worktree enrichment envelopes")
func consumesAllRequiredEnvelopeTiers() async { /* ... */ }

@Test("topology handling mutates WorkspaceStore while enrichment mutates WorkspaceCacheStore")
func routesMutationsByMethodGroup() async { /* ... */ }
```

**Step 2: Run tests to verify failure**

Run: `SWIFT_BUILD_DIR=".build-agent-cache-coordinator" swift test --build-path "$SWIFT_BUILD_DIR" --filter "WorkspaceCacheCoordinatorTests" > /tmp/luna350-task5.log 2>&1; echo $?`
Expected: missing coordinator symbols/handlers.

**Step 3: Write minimal implementation**

```swift
@MainActor
final class WorkspaceCacheCoordinator {
    func startConsuming() { /* subscribe RuntimeEnvelope stream */ }
    func handleTopology(_ envelope: SystemEnvelope) { /* WorkspaceStore mutations */ }
    func handleEnrichment(_ envelope: WorktreeEnvelope) { /* WorkspaceCacheStore writes */ }
    func syncScope(_ change: ScopeChange) async { /* register/unregister actor scope */ }
}
```

**Step 4: Run tests to verify pass**

Run: same command from Step 2.
Expected: exit code `0`.

**Step 5: Commit**

```bash
git add Sources/AgentStudio/App/WorkspaceCacheCoordinator.swift \
  Sources/AgentStudio/App/PaneCoordinator.swift \
  Sources/AgentStudio/App/AppDelegate.swift \
  Tests/AgentStudioTests/App/WorkspaceCacheCoordinatorTests.swift
git commit -m "feat(app): add workspace cache coordinator consolidation consumer"
```

### Task 6: Parent Folder Discovery + Worktree Registration Flow

**Files:**
- Modify: `Sources/AgentStudio/Infrastructure/RepoScanner.swift`
- Modify: `Sources/AgentStudio/Core/PaneRuntime/Sources/FilesystemActor.swift`
- Modify: `Sources/AgentStudio/App/PaneCoordinator+FilesystemSource.swift`
- Test: `Tests/AgentStudioTests/Infrastructure/RepoScannerTests.swift`
- Test: `Tests/AgentStudioTests/Core/PaneRuntime/Sources/FilesystemActorTests.swift`

**Step 1: Write failing tests**

```swift
@Test("parent folder rescan stops at first .git and respects maxDepth 3")
func scanStopsAtGitBoundary() { /* ... */ }

@Test("repo discovered emits SystemEnvelope topology event")
func emitsRepoDiscoveredTopology() async { /* ... */ }
```

**Step 2: Run tests to verify failure**

Run: `SWIFT_BUILD_DIR=".build-agent-discovery" swift test --build-path "$SWIFT_BUILD_DIR" --filter "RepoScannerTests|FilesystemActorTests" > /tmp/luna350-task6.log 2>&1; echo $?`
Expected: failure on discovery semantics and envelope category.

**Step 3: Write minimal implementation**

```swift
enum WatchedPathKind: String, Codable { case parentFolder, directRepo }
// parent folder: trigger rescan (maxDepth 3, stop descending when .git found)
```

Implement trigger-based parent scanning and deep worktree watch registration separately.

**Step 4: Run tests to verify pass**

Run: same command from Step 2.
Expected: exit code `0`.

**Step 5: Commit**

```bash
git add Sources/AgentStudio/Infrastructure/RepoScanner.swift \
  Sources/AgentStudio/Core/PaneRuntime/Sources/FilesystemActor.swift \
  Sources/AgentStudio/App/PaneCoordinator+FilesystemSource.swift \
  Tests/AgentStudioTests/Infrastructure/RepoScannerTests.swift \
  Tests/AgentStudioTests/Core/PaneRuntime/Sources/FilesystemActorTests.swift
git commit -m "feat(filesystem): add topology discovery flow with depth-capped rescans"
```

### Task 7: Implement `ForgeActor` as Event-Driven Enrichment Source

**Files:**
- Create: `Sources/AgentStudio/Core/PaneRuntime/Sources/ForgeActor.swift`
- Modify: `Sources/AgentStudio/App/FilesystemGitPipeline.swift`
- Modify: `Sources/AgentStudio/App/PaneCoordinator.swift`
- Create: `Tests/AgentStudioTests/Core/PaneRuntime/Sources/ForgeActorTests.swift`

**Step 1: Write failing tests**

```swift
@Test("forge actor reacts to branchChanged and originChanged via bus subscription")
func reactsToGitProjectorEvents() async { /* ... */ }

@Test("forge actor polling fallback emits refreshFailed on transport error")
func pollingFallbackErrorPath() async { /* ... */ }
```

**Step 2: Run tests to verify failure**

Run: `SWIFT_BUILD_DIR=".build-agent-forge" swift test --build-path "$SWIFT_BUILD_DIR" --filter "ForgeActorTests" > /tmp/luna350-task7.log 2>&1; echo $?`
Expected: missing `ForgeActor` implementation.

**Step 3: Write minimal implementation**

```swift
actor ForgeActor {
    func start() async { /* subscribe to RuntimeEnvelope stream */ }
    func register(repoId: UUID, remoteURL: String) async { /* scope */ }
    func refresh(repoId: UUID) async { /* command-plane explicit refresh */ }
}
```

Emit `WorktreeEnvelope(.forge(.pullRequestCountsChanged/...))`; do not scan filesystem or run local git status here.

**Step 4: Run tests to verify pass**

Run: same command from Step 2.
Expected: exit code `0`.

**Step 5: Commit**

```bash
git add Sources/AgentStudio/Core/PaneRuntime/Sources/ForgeActor.swift \
  Sources/AgentStudio/App/FilesystemGitPipeline.swift \
  Sources/AgentStudio/App/PaneCoordinator.swift \
  Tests/AgentStudioTests/Core/PaneRuntime/Sources/ForgeActorTests.swift
git commit -m "feat(forge): add event-driven forge actor with polling fallback"
```

### Task 8: Repo Move Lifecycle + Orphan/Relink Behavior

**Files:**
- Modify: `Sources/AgentStudio/Core/Stores/WorkspaceStore.swift`
- Modify: `Sources/AgentStudio/App/WorkspaceCacheCoordinator.swift`
- Test: `Tests/AgentStudioTests/Core/Stores/WorkspaceStoreOrphanPoolTests.swift`
- Create: `Tests/AgentStudioTests/App/WorkspaceCacheCoordinatorRepoMoveTests.swift`

**Step 1: Write failing tests**

```swift
@Test("repoRemoved marks panes orphaned and prunes cache while preserving canonical identities")
func repoRemovedOrphansPanes() async { /* ... */ }

@Test("re-association preserves UUID links and recomputes stable keys")
func relocateRepoPreservesIdentity() async { /* ... */ }
```

**Step 2: Run tests to verify failure**

Run: `SWIFT_BUILD_DIR=".build-agent-repo-move" swift test --build-path "$SWIFT_BUILD_DIR" --filter "WorkspaceStoreOrphanPoolTests|WorkspaceCacheCoordinatorRepoMoveTests" > /tmp/luna350-task8.log 2>&1; echo $?`
Expected: failure due to missing move/relink lifecycle behavior.

**Step 3: Write minimal implementation**

```swift
// On repo remove: mark pane residency orphaned, unregister actor scopes, prune cache.
// On locate: update repoPath, recompute stableKey, refresh worktree paths, restore pane residency.
```

Include `git worktree list --porcelain -z` and `git worktree repair` handling in coordinator workflow.

**Step 4: Run tests to verify pass**

Run: same command from Step 2.
Expected: exit code `0`.

**Step 5: Commit**

```bash
git add Sources/AgentStudio/Core/Stores/WorkspaceStore.swift \
  Sources/AgentStudio/App/WorkspaceCacheCoordinator.swift \
  Tests/AgentStudioTests/Core/Stores/WorkspaceStoreOrphanPoolTests.swift \
  Tests/AgentStudioTests/App/WorkspaceCacheCoordinatorRepoMoveTests.swift
git commit -m "feat(workspace): implement repo-move orphan and re-association lifecycle"
```

### Task 9: Sidebar Rewire to Pure Reader (Remove 12 Direct Mutations)

**Files:**
- Modify: `Sources/AgentStudio/App/MainSplitViewController.swift`
- Modify: `Sources/AgentStudio/Features/Sidebar/RepoSidebarContentView.swift`
- Modify: `Sources/AgentStudio/Features/Sidebar/SidebarGitRepositoryInspector.swift`
- Test: `Tests/AgentStudioTests/Features/Sidebar/RepoSidebarContentViewTests.swift`
- Test: `Tests/AgentStudioTests/Features/Sidebar/SidebarRepoGroupingTests.swift`
- Test: `Tests/AgentStudioTests/App/PaneCoordinatorTests.swift`

**Step 1: Write failing tests**

```swift
@Test("sidebar does not call updateRepoWorktrees directly")
func sidebarNoDirectStoreMutation() { /* assert command dispatch path */ }

@Test("grouping/filtering read from canonical+cache+ui stores only")
func sidebarProjectionUsesStores() { /* ... */ }
```

**Step 2: Run tests to verify failure**

Run: `SWIFT_BUILD_DIR=".build-agent-sidebar-rewire" swift test --build-path "$SWIFT_BUILD_DIR" --filter "RepoSidebarContentViewTests|SidebarRepoGroupingTests|PaneCoordinatorTests" > /tmp/luna350-task9.log 2>&1; echo $?`
Expected: failure on direct mutation expectations.

**Step 3: Write minimal implementation**

```swift
// Replace:
//   store.updateRepoWorktrees(...)
// With:
//   coordinator.handle(.refreshRepoTopology(repoId: ...))
```

All sidebar operations become intent dispatches; coordinator/event pipeline does the mutation.

**Step 4: Run tests to verify pass**

Run: same command from Step 2.
Expected: exit code `0`.

**Step 5: Commit**

```bash
git add Sources/AgentStudio/App/MainSplitViewController.swift \
  Sources/AgentStudio/Features/Sidebar/RepoSidebarContentView.swift \
  Sources/AgentStudio/Features/Sidebar/SidebarGitRepositoryInspector.swift \
  Tests/AgentStudioTests/Features/Sidebar/RepoSidebarContentViewTests.swift \
  Tests/AgentStudioTests/Features/Sidebar/SidebarRepoGroupingTests.swift \
  Tests/AgentStudioTests/App/PaneCoordinatorTests.swift
git commit -m "refactor(sidebar): remove direct store mutations and route intents through coordinator"
```

### Task 10: End-to-End Pipeline and Regression Verification

**Files:**
- Modify: `Tests/AgentStudioTests/Integration/FilesystemGitPipelineIntegrationTests.swift`
- Modify: `Tests/AgentStudioTests/Integration/FilesystemSourceE2ETests.swift`
- Create: `Tests/AgentStudioTests/Integration/WorkspaceCacheCoordinatorE2ETests.swift`

**Step 1: Write failing integration tests**

```swift
@Test("filesystem->git->forge chain updates cache store and sidebar projection")
func sequentialEnrichmentPipeline() async throws { /* ... */ }
```

**Step 2: Run tests to verify failure**

Run: `SWIFT_BUILD_DIR=".build-agent-e2e-pipeline" swift test --build-path "$SWIFT_BUILD_DIR" --filter "FilesystemGitPipelineIntegrationTests|FilesystemSourceE2ETests|WorkspaceCacheCoordinatorE2ETests" > /tmp/luna350-task10.log 2>&1; echo $?`
Expected: failing assertions on chain/enrichment behavior until implementation lands.

**Step 3: Write minimal implementation adjustments**

Adjust fixtures and helpers to emit/consume `RuntimeEnvelope` and new stores.

**Step 4: Run tests to verify pass**

Run: same command from Step 2.
Expected: exit code `0`.

**Step 5: Commit**

```bash
git add Tests/AgentStudioTests/Integration/FilesystemGitPipelineIntegrationTests.swift \
  Tests/AgentStudioTests/Integration/FilesystemSourceE2ETests.swift \
  Tests/AgentStudioTests/Integration/WorkspaceCacheCoordinatorE2ETests.swift
git commit -m "test(integration): verify sequential enrichment and cache/sidebar convergence"
```

### Task 11: Architecture Docs Final Sync (Single Source of Truth)

> **Pre-work completed:** The following doc alignment was done during the LUNA-350 design session (before implementation begins):
> - Contract 3 updated from `PaneEventEnvelope` to `Event Envelope` with both current and target `RuntimeEnvelope` models including `eventId`/`causationId`
> - Bus Enrichment Rule rewritten to show 3-actor pipeline (FilesystemActor → GitWorkingDirectoryProjector → ForgeActor)
> - Threading table updated: FilesystemActor description corrected, GitWorkingDirectoryProjector row added
> - Coordinator subscription scope fixed to `RuntimeEnvelope` (system + worktree tiers)
> - Replay buffer constant aligned to 256 events per source (A10 matched to workspace_data_architecture.md)
> - Envelope invariants expanded for 3-tier model with per-tier scope rules
> - Contamination table expanded to all 18 fields in component_architecture.md
> - Cross-references made bidirectional across all architecture docs

**Files:**
- Modify: `docs/architecture/pane_runtime_architecture.md`
- Modify: `docs/architecture/pane_runtime_eventbus_design.md`
- Modify: `docs/architecture/workspace_data_architecture.md`
- Modify: `docs/architecture/component_architecture.md`

**Step 1: Run consistency check for remaining stale references**

Run: `rg -n “EventBus<PaneEventEnvelope>|FilesystemActor.*git status|SUBSCRIBES TO: ALL WorktreeEnvelope events” docs/architecture/*.md`
Expected: zero stale matches (pre-work should have eliminated these).

**Step 2: Verify code samples match implemented types**

After Tasks 1-3 land new Swift types, update any code samples in architecture docs that show old type names or missing fields. Focus on:
- Contract 3 “Current” section — should match the actual `PaneEventEnvelope.swift`
- Contract 3 “Target” section — should match the actual `RuntimeEnvelope.swift`
- EventBus design actor inventory — should match actual actor files

**Step 3: Run markdown sanity check**

Run: `rg -n “TODO\\(LUNA-350\\)|TBD|NEEDS SPEC” docs/architecture/*.md docs/plans/*.md`
Expected: no unresolved placeholders for this scope.

**Step 4: Commit**

```bash
git add docs/architecture/pane_runtime_architecture.md \
  docs/architecture/pane_runtime_eventbus_design.md \
  docs/architecture/workspace_data_architecture.md \
  docs/architecture/component_architecture.md
git commit -m “docs(architecture): final sync after runtime envelope implementation”
```

### Task 12: Full Verification Gate

**Files:**
- Modify (if needed from failures): any files touched above

**Step 1: Format**

Run: `mise run format`
Expected: exit code `0`.

**Step 2: Lint**

Run: `mise run lint`
Expected: exit code `0`.

**Step 3: Full test suite**

Run: `mise run test`
Expected: exit code `0` with all test suites passing.

**Step 4: Final architecture invariants check**

Run: `rg -n "updateRepoWorktrees\\(|repoWorktreesDidChangeHook" Sources/AgentStudio`
Expected: no direct sidebar/controller mutation callsites remain in active flow.

**Step 5: Commit**

```bash
git add -A
git commit -m "chore(luna-350): final verification pass and contract cleanup"
```

---

## Acceptance Checklist

- [ ] All event-plane producers emit `RuntimeEnvelope` with correct tier scoping.
- [ ] Topology events are `SystemEnvelope` and never require `repoId`.
- [ ] Filesystem/git/forge events are `WorktreeEnvelope` with required `repoId`.
- [ ] Bus replay policy is documented and implemented consistently.
- [ ] `WorkspaceCacheCoordinator` is sole event-driven mutator for canonical/cache split.
- [ ] Sidebar is pure reader; direct `updateRepoWorktrees` mutations removed from UI callsites.
- [ ] Repo-move/orphan/relink lifecycle works with stable UUID identity semantics.
- [ ] `mise run format`, `mise run lint`, and `mise run test` all pass.

---

## Execution Handoff

Plan complete and saved to `docs/plans/2026-03-01-luna-350-runtime-envelope-workspace-persistence-sidebar-consolidated.md`.

Two execution options:

1. Subagent-Driven (this session) - I dispatch a fresh subagent per task, review between tasks, and keep fast iteration loops.
2. Parallel Session (separate) - Open a new session with `superpowers:executing-plans` and run the plan with checkpointed batch execution.

Which approach?
