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

### Task 0: Plan Hygiene (Deprecate + Remove Superseded Plans)

**Files:**
- Delete: `docs/plans/sidebar-repo-metadata-grouping-filtering-spec.md`
- Delete: `docs/plans/sidebar-cwd-dedupe-test-spec.md`
- Delete: `docs/plans/sidebar-cwd-dedupe-requirements.md`
- Delete: `docs/plans/2026-03-01-luna-350-forgeactor-workspace-persistence-segregation-sidebar-rewiring.md`
- Delete: `docs/plans/2026-02-28-luna-349-filesystem-git-actor-split.md`
- Delete: `docs/plans/2026-02-27-luna-349-test-value-plan.md`
- Delete: `docs/plans/2026-02-27-luna-349-fs-event-source-and-runtime-conformers.md`
- Delete: `docs/plans/2026-02-21-pane-runtime-luna-295-luna-325-mapping.md`
- Delete: `docs/plans/2026-02-22-luna-325-contract-parity-execution-plan.md`
- Delete: `docs/plans/2026-02-25-workspace-persistence-segregation.md`

**Step 1: Delete superseded files**

Run: `git rm <each superseded file listed above>`

**Step 2: Verify there are no stale references**

Run: `rg -n "sidebar-repo-metadata-grouping-filtering-spec|luna-349-filesystem-git-actor-split|workspace-persistence-segregation" docs/`
Expected: references only in this consolidated plan (or migration notes if intentionally retained).

**Step 3: Checkpoint**

```bash
git status --short docs/plans
# Commit only if explicitly requested:
# git commit -m "docs(plans): remove superseded plans after consolidation"
```

## Execution Standards

- Use `@superpowers/executing-plans` for task-by-task execution.
- Use `@superpowers/verification-before-completion` before completion claims.
- Set one session build path once and reuse it for all filtered runs:
  `export SWIFT_BUILD_DIR=".build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8)"`.
- Use explicit command timeouts in tool execution (`60000` for test commands, `30000` for build commands).
- Do not commit unless explicitly requested by the user.
- Keep tests deterministic: no sleeps for ordering tests unless required by API contract.

## Locked Review Fixes (Must Ship)

- Remove legacy event bridge entirely: no `PaneEventEnvelope`, no `fromLegacy`, no `toLegacy`, no dual-bus constructor paths.
- Route topology events through `SystemEnvelope` only; system tier must be reachable by producers/consumers.
- `NotificationReducer` must consume `.system` envelopes (no silent discard).
- Split `RuntimeEnvelope.swift` by responsibility so contract/bridge/test-factory concerns are not in one file.
- Add dedicated tests for runtime-envelope ingestion paths (no legacy-only constructor usage in tests).
- Remove silent event drops: log + metric on any dropped emit/translation path.
- Handle replay delivery outcomes (`EventBus.subscribe`) and surface replay gaps.
- Add deterministic shutdown for `EventBus` subscriber continuations.
- Keep drain loops resilient: recoverable errors should log and continue flushing.

### Task 1: Introduce `RuntimeEnvelope` 3-Tier Contract

**Files:**
- Create: `Sources/AgentStudio/Core/PaneRuntime/Contracts/RuntimeEnvelope.swift`
- Create: `Sources/AgentStudio/Core/PaneRuntime/Contracts/RuntimeEnvelopeScopes.swift`
- Modify: `Sources/AgentStudio/Core/PaneRuntime/Contracts/PaneContextFacets.swift`
- Test: `Tests/AgentStudioTests/Core/PaneRuntime/Contracts/RuntimeEnvelopeContractsTests.swift`

**Step 1: Write the failing test**

```swift
@Suite("RuntimeEnvelope contracts")
struct RuntimeEnvelopeContractsTests {
    @Test("topology events use SystemEnvelope")
    func topologyRequiresSystemEnvelope() {
        let event = SystemScopedEvent.topology(.repoDiscovered(repoPath: URL(fileURLWithPath: "/tmp/repo"), parentPath: URL(fileURLWithPath: "/tmp")))
        let envelope = RuntimeEnvelope.system(SystemEnvelope.test(event: event))
        if case .system = envelope {
            #expect(Bool(true))
        } else {
            #expect(Bool(false))
        }
    }
}
```

**Step 2: Run test to verify it fails**

Run: `SWIFT_BUILD_DIR=".build-agent-runtime-envelope"; swift test --build-path "$SWIFT_BUILD_DIR" --filter "RuntimeEnvelopeContractsTests" > /tmp/luna350-task1.log 2>&1; echo $?`
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

Run: `SWIFT_BUILD_DIR=".build-agent-runtime-envelope"; swift test --build-path "$SWIFT_BUILD_DIR" --filter "RuntimeEnvelopeContractsTests" > /tmp/luna350-task1.log 2>&1; echo $?`
Expected: exit code `0`.

**Step 5: Checkpoint**

```bash
git add Sources/AgentStudio/Core/PaneRuntime/Contracts/RuntimeEnvelope.swift \
  Sources/AgentStudio/Core/PaneRuntime/Contracts/RuntimeEnvelopeScopes.swift \
  Sources/AgentStudio/Core/PaneRuntime/Contracts/PaneContextFacets.swift \
  Tests/AgentStudioTests/Core/PaneRuntime/Contracts/RuntimeEnvelopeContractsTests.swift
git status --short
# Commit only if explicitly requested:
# git commit -m "feat(runtime): add 3-tier RuntimeEnvelope contracts"
```

### Task 2: Define Event Namespaces for Hard Cutover (No Compatibility Layer)

**Files:**
- Modify: `Sources/AgentStudio/Core/PaneRuntime/Contracts/PaneRuntimeEvent.swift`
- Modify: `Sources/AgentStudio/Core/PaneRuntime/Sources/FilesystemActor.swift`
- Modify: `Sources/AgentStudio/Core/PaneRuntime/Sources/GitWorkingDirectoryProjector.swift`
- Modify: `Sources/AgentStudio/Core/PaneRuntime/Projection/WorkspaceGitWorkingTreeStore.swift`
- Test: `Tests/AgentStudioTests/Core/PaneRuntime/Sources/FilesystemActorTests.swift`
- Test: `Tests/AgentStudioTests/Core/PaneRuntime/Sources/GitWorkingDirectoryProjectorTests.swift`
- Test: `Tests/AgentStudioTests/Core/PaneRuntime/Projection/WorkspaceGitWorkingTreeStoreTests.swift`

**Step 1: Write the failing tests**

```swift
@Test("filesystem actor emits topology only for repo discovered/removed")
func emitsTopologyForRepoLifecycle() async { /* ... */ }

@Test("git projector emits branchChanged under GitWorkingDirectoryEvent")
func emitsGitNamespace() async { /* ... */ }
```

**Step 2: Run tests to verify failure**

Run: `SWIFT_BUILD_DIR=".build-agent-namespace-split"; swift test --build-path "$SWIFT_BUILD_DIR" --filter "FilesystemActorTests|GitWorkingDirectoryProjectorTests|WorkspaceGitWorkingTreeStoreTests" > /tmp/luna350-task2.log 2>&1; echo $?`
Expected: assertions fail on old namespace routing.

**Step 3: Write minimal implementation**

```swift
enum SystemScopedEvent: Sendable { case topology(TopologyEvent), appLifecycle(AppLifecycleEvent), focusChanged(FocusChangeEvent), configChanged(ConfigChangeEvent) }
enum WorktreeScopedEvent: Sendable { case filesystem(FilesystemEvent), gitWorkingDirectory(GitWorkingDirectoryEvent), forge(ForgeEvent), security(SecurityEvent) }
```

Cut over producers directly to scoped events now:
- `worktreeRegistered/worktreeUnregistered` -> `SystemScopedEvent.topology(...)`
- `filesChanged` -> `WorktreeScopedEvent.filesystem(.filesChanged)`
- `gitSnapshotChanged/branchChanged` -> `WorktreeScopedEvent.gitWorkingDirectory(...)`
- Do not add adapters that preserve `PaneEventEnvelope` routing.

**Step 4: Run tests to verify pass**

Run: same command from Step 2.
Expected: exit code `0`.

**Step 5: Checkpoint**

```bash
git add Sources/AgentStudio/Core/PaneRuntime/Contracts/PaneRuntimeEvent.swift \
  Sources/AgentStudio/Core/PaneRuntime/Sources/FilesystemActor.swift \
  Sources/AgentStudio/Core/PaneRuntime/Sources/GitWorkingDirectoryProjector.swift \
  Sources/AgentStudio/Core/PaneRuntime/Projection/WorkspaceGitWorkingTreeStore.swift \
  Tests/AgentStudioTests/Core/PaneRuntime/Sources/FilesystemActorTests.swift \
  Tests/AgentStudioTests/Core/PaneRuntime/Sources/GitWorkingDirectoryProjectorTests.swift \
  Tests/AgentStudioTests/Core/PaneRuntime/Projection/WorkspaceGitWorkingTreeStoreTests.swift
git status --short
# Commit only if explicitly requested:
# git commit -m "feat(events): define scoped event namespaces for hard cutover"
```

### Task 3: Migrate Bus to `EventBus<RuntimeEnvelope>` + Bus Replay Contract

**Files:**
- Modify: `Sources/AgentStudio/Core/PaneRuntime/Events/EventBus.swift`
- Modify: `Sources/AgentStudio/Core/PaneRuntime/Events/EventChannels.swift`
- Modify: `Sources/AgentStudio/Core/PaneRuntime/Reduction/NotificationReducer.swift`
- Modify: `Sources/AgentStudio/Core/PaneRuntime/Runtime/PaneRuntimeEventChannel.swift`
- Modify: `Sources/AgentStudio/Core/PaneRuntime/Contracts/PaneRuntime.swift`
- Modify: `Sources/AgentStudio/App/PaneCoordinator.swift`
- Modify: `Sources/AgentStudio/App/FilesystemGitPipeline.swift`
- Modify: `Sources/AgentStudio/Features/Terminal/Runtime/TerminalRuntime.swift`
- Modify: `Sources/AgentStudio/Features/Webview/Runtime/WebviewRuntime.swift`
- Modify: `Sources/AgentStudio/Features/Bridge/Runtime/BridgeRuntime.swift`
- Create: `Tests/AgentStudioTests/Core/PaneRuntime/Events/EventBusRuntimeEnvelopeTests.swift`

**Step 1: Write failing tests**

```swift
@Test("bus replays up to 256 events per source for late subscribers")
func busReplayBoundedPerSource() async { /* ... */ }

@Test("lossy ordering preserves per-source seq within flush batch")
func notificationReducerOrdering() async { /* ... */ }
```

**Step 2: Run tests to verify failure**

Run: `SWIFT_BUILD_DIR=".build-agent-bus-migration"; swift test --build-path "$SWIFT_BUILD_DIR" --filter "EventBusRuntimeEnvelopeTests|NotificationReducerTests|PaneCoordinatorTests|TerminalRuntimeTests|WebviewRuntimeTests|BridgeRuntimeTests" > /tmp/luna350-task3.log 2>&1; echo $?`
Expected: failure on missing bus replay behavior and envelope type mismatch.

**Step 3: Write minimal implementation**

```swift
enum PaneRuntimeEventBus {
    static let shared = EventBus<RuntimeEnvelope>()
}
```

Add bus replay buffer keyed by `EventSource` with cap `256`, adapt reducer consumption to `RuntimeEnvelope` classification, and migrate all runtime bus callsites listed above from `PaneEventEnvelope` to `RuntimeEnvelope`.

**Step 4: Run tests to verify pass**

Run: same command from Step 2.
Expected: exit code `0`.

**Step 5: Checkpoint**

```bash
git add Sources/AgentStudio/Core/PaneRuntime/Events/EventBus.swift \
  Sources/AgentStudio/Core/PaneRuntime/Events/EventChannels.swift \
  Sources/AgentStudio/Core/PaneRuntime/Reduction/NotificationReducer.swift \
  Sources/AgentStudio/Core/PaneRuntime/Runtime/PaneRuntimeEventChannel.swift \
  Sources/AgentStudio/Core/PaneRuntime/Contracts/PaneRuntime.swift \
  Sources/AgentStudio/App/PaneCoordinator.swift \
  Sources/AgentStudio/App/FilesystemGitPipeline.swift \
  Sources/AgentStudio/Features/Terminal/Runtime/TerminalRuntime.swift \
  Sources/AgentStudio/Features/Webview/Runtime/WebviewRuntime.swift \
  Sources/AgentStudio/Features/Bridge/Runtime/BridgeRuntime.swift \
  Tests/AgentStudioTests/Core/PaneRuntime/Events/EventBusRuntimeEnvelopeTests.swift
git status --short
# Commit only if explicitly requested:
# git commit -m "feat(eventbus): migrate to RuntimeEnvelope and add bounded bus replay"
```

### Task 3a: Remove Legacy Envelope Path + Split Runtime Envelope Files

> **Mandatory closure task for branch acceptance.** This task resolves the outstanding review blockers on runtime-envelope migration quality and removes temporary compatibility scaffolding.

**Files:**
- Delete: `Sources/AgentStudio/Core/PaneRuntime/Contracts/PaneEventEnvelope.swift`
- Create: `Sources/AgentStudio/Core/PaneRuntime/Contracts/RuntimeEnvelopeCore.swift`
- Create: `Sources/AgentStudio/Core/PaneRuntime/Contracts/RuntimeEnvelopeMetadata.swift`
- Create: `Sources/AgentStudio/Core/PaneRuntime/Contracts/RuntimeEnvelopeFactories.swift`
- Modify: `Sources/AgentStudio/Core/PaneRuntime/Contracts/RuntimeEnvelope.swift`
- Modify: `Sources/AgentStudio/Core/PaneRuntime/Reduction/NotificationReducer.swift`
- Modify: `Sources/AgentStudio/Core/PaneRuntime/Sources/GitWorkingDirectoryProjector.swift`
- Modify: `Sources/AgentStudio/Core/PaneRuntime/Sources/FilesystemActor.swift`
- Modify: `Sources/AgentStudio/Core/PaneRuntime/Runtime/PaneRuntimeEventChannel.swift`
- Modify: `Sources/AgentStudio/Core/PaneRuntime/Events/EventBus.swift`
- Create: `Tests/AgentStudioTests/Core/PaneRuntime/Contracts/RuntimeEnvelopeHardCutoverTests.swift`
- Modify: `Tests/AgentStudioTests/Core/PaneRuntime/Reduction/NotificationReducerTests.swift`
- Modify: `Tests/AgentStudioTests/Core/PaneRuntime/Events/EventBusRuntimeEnvelopeTests.swift`

**Step 1: Write failing tests**

```swift
@Test("no legacy envelope symbols remain in runtime contract")
func noLegacyEnvelopeSymbolsRemain() { /* ... */ }

@Test("notification reducer consumes system envelopes")
func reducerConsumesSystemTier() async { /* ... */ }

@Test("runtime bus API has no dual-bus compatibility constructors")
func noDualBusCompatibilityPaths() { /* ... */ }
```

**Step 2: Run tests to verify failure**

Run: `SWIFT_BUILD_DIR=".build-agent-hard-cutover"; swift test --build-path "$SWIFT_BUILD_DIR" --filter "RuntimeEnvelopeHardCutoverTests|NotificationReducerTests|EventBusRuntimeEnvelopeTests|FilesystemActorTests|GitWorkingDirectoryProjectorTests" > /tmp/luna350-task3b.log 2>&1; echo $?`
Expected: failures on remaining legacy references and missing system-tier coverage.

**Step 3: Write minimal implementation**

- Hard-remove legacy envelope bridge (`PaneEventEnvelope`, `fromLegacy`, `toLegacy`) and dual-bus initialization paths.
- Split runtime-envelope declarations by responsibility:
  - `RuntimeEnvelopeCore.swift`: 3-tier discriminated union + envelope structs
  - `RuntimeEnvelopeMetadata.swift`: common metadata/context helpers
  - `RuntimeEnvelopeFactories.swift`: test-only builders/factories
- Ensure topology events are emitted/consumed via `SystemEnvelope` (no pane-tier fallback).
- Eliminate silent drops:
  - projector/reducer/channel paths log at warning level when events cannot be emitted.
  - `PaneRuntimeEventChannel.emit` observes post results instead of fire-and-forget drop.
- Harden bus semantics:
  - handle replay result at subscribe time and surface gaps.
  - add deterministic `shutdown()` (or equivalent isolated deinit cleanup) that finishes subscriber continuations.
- Make drain loops resilient (`FilesystemActor`/`GitWorkingDirectoryProjector`): recoverable errors log and continue.

**Step 4: Run tests to verify pass**

Run: same command from Step 2.
Expected: exit code `0`.

**Step 5: Checkpoint**

```bash
git add Sources/AgentStudio/Core/PaneRuntime/Contracts/RuntimeEnvelope.swift \
  Sources/AgentStudio/Core/PaneRuntime/Contracts/RuntimeEnvelopeCore.swift \
  Sources/AgentStudio/Core/PaneRuntime/Contracts/RuntimeEnvelopeMetadata.swift \
  Sources/AgentStudio/Core/PaneRuntime/Contracts/RuntimeEnvelopeFactories.swift \
  Sources/AgentStudio/Core/PaneRuntime/Reduction/NotificationReducer.swift \
  Sources/AgentStudio/Core/PaneRuntime/Sources/GitWorkingDirectoryProjector.swift \
  Sources/AgentStudio/Core/PaneRuntime/Sources/FilesystemActor.swift \
  Sources/AgentStudio/Core/PaneRuntime/Runtime/PaneRuntimeEventChannel.swift \
  Sources/AgentStudio/Core/PaneRuntime/Events/EventBus.swift \
  Tests/AgentStudioTests/Core/PaneRuntime/Contracts/RuntimeEnvelopeHardCutoverTests.swift \
  Tests/AgentStudioTests/Core/PaneRuntime/Reduction/NotificationReducerTests.swift \
  Tests/AgentStudioTests/Core/PaneRuntime/Events/EventBusRuntimeEnvelopeTests.swift
git rm Sources/AgentStudio/Core/PaneRuntime/Contracts/PaneEventEnvelope.swift
git status --short
# Commit only if explicitly requested:
# git commit -m "refactor(runtime): hard-cut legacy envelope path and split runtime envelope contracts"
```

### Task 3b: Split Contaminated Repo/Worktree Model Structs

> **Prerequisite for Task 4.** The current `Repo` and `Worktree` structs mix canonical identity, discovered state, and runtime state. This task splits them into tier-appropriate models before persistence can be segregated.

**Files:**
- Create: `Sources/AgentStudio/Core/Models/CanonicalRepo.swift`
- Create: `Sources/AgentStudio/Core/Models/CanonicalWorktree.swift`
- Create: `Sources/AgentStudio/Core/Models/RepoEnrichment.swift`
- Create: `Sources/AgentStudio/Core/Models/WorktreeEnrichment.swift`
- Modify: `Sources/AgentStudio/Core/Models/Repo.swift`
- Modify: `Sources/AgentStudio/Core/Models/Worktree.swift`
- Test: `Tests/AgentStudioTests/Core/Models/CanonicalModelTests.swift`

**Step 1: Write failing tests**

```swift
@Suite("Canonical model tier separation")
struct CanonicalModelTests {
    @Test("CanonicalRepo contains only identity and user-intent fields")
    func repoHasNoEnrichmentFields() {
        let repo = CanonicalRepo(id: UUID(), name: "test", repoPath: URL(fileURLWithPath: "/tmp"), createdAt: Date())
        // These fields must NOT exist on CanonicalRepo:
        // organizationName, origin, upstream, updatedAt, worktrees
        #expect(repo.id != UUID())  // identity is stable
    }

    @Test("WorktreeEnrichment holds all git-derived fields")
    func enrichmentHoldsDerivedData() {
        let enrichment = WorktreeEnrichment(worktreeId: UUID(), repoId: UUID(), branch: "main")
        #expect(enrichment.branch == "main")
        // agent and status are runtime-only — not in enrichment
    }
}
```

**Step 2: Run tests to verify failure**

Run: `SWIFT_BUILD_DIR=".build-agent-model-split"; swift test --build-path "$SWIFT_BUILD_DIR" --filter "CanonicalModelTests" > /tmp/luna350-task3a.log 2>&1; echo $?`
Expected: missing `CanonicalRepo`, `WorktreeEnrichment` symbols.

**Step 3: Write minimal implementation**

Split per the [contamination table](../architecture/component_architecture.md#22-repo--worktree):

```
CanonicalRepo: id, name, repoPath, createdAt
  (removed: organizationName, origin, upstream → RepoEnrichment)
  (removed: worktrees → CanonicalWorktree is a separate collection)
  (removed: updatedAt → was bumped by derived data)

CanonicalWorktree: id, name, path, isMainWorktree
  (removed: branch → WorktreeEnrichment)
  (removed: agent, status → derived from pane state at query time)

RepoEnrichment: repoId, organizationName?, origin?, upstream?, stableKey
WorktreeEnrichment: worktreeId, repoId, branch, stableKey
```

If temporary aliases are introduced to unblock compilation, remove them before Step 4 passes. End-of-task state is hard cutover: no persistent compatibility alias/shim remains.

**Step 4: Run tests to verify pass**

Run: same command from Step 2.
Expected: exit code `0`.

**Step 5: Checkpoint**

```bash
git add Sources/AgentStudio/Core/Models/CanonicalRepo.swift \
  Sources/AgentStudio/Core/Models/CanonicalWorktree.swift \
  Sources/AgentStudio/Core/Models/RepoEnrichment.swift \
  Sources/AgentStudio/Core/Models/WorktreeEnrichment.swift \
  Sources/AgentStudio/Core/Models/Repo.swift \
  Sources/AgentStudio/Core/Models/Worktree.swift \
  Tests/AgentStudioTests/Core/Models/CanonicalModelTests.swift
git commit -m "refactor(models): split contaminated Repo/Worktree into canonical + enrichment tiers"
```

### Task 4: Add Cache/UI Stores and Persistence Segregation

> **Depends on Task 3b.** Uses `CanonicalRepo`, `CanonicalWorktree`, `RepoEnrichment`, `WorktreeEnrichment` models from the model split. `WorkspaceCacheStore` stores enrichment models. `WorkspaceUIStore` stores sidebar/UI preferences. `WorkspacePersistor` writes three separate JSON files.

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

Run: `SWIFT_BUILD_DIR=".build-agent-persistence-split"; swift test --build-path "$SWIFT_BUILD_DIR" --filter "WorkspacePersistorTests|WorkspaceCacheStoreTests" > /tmp/luna350-task4.log 2>&1; echo $?`
Expected: failure due to missing cache/UI stores and file split.

**Step 3: Write minimal implementation**

```swift
// workspace.state.json (canonical), workspace.cache.json (derived), workspace.ui.json (preferences)
```

Implement load/save APIs for all three files and keep existing workspace restore path deterministic.

**Step 4: Run tests to verify pass**

Run: same command from Step 2.
Expected: exit code `0`.

**Step 5: Checkpoint**

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

Run: `SWIFT_BUILD_DIR=".build-agent-cache-coordinator"; swift test --build-path "$SWIFT_BUILD_DIR" --filter "WorkspaceCacheCoordinatorTests" > /tmp/luna350-task5.log 2>&1; echo $?`
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

**Step 5: Checkpoint**

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

Run: `SWIFT_BUILD_DIR=".build-agent-discovery"; swift test --build-path "$SWIFT_BUILD_DIR" --filter "RepoScannerTests|FilesystemActorTests" > /tmp/luna350-task6.log 2>&1; echo $?`
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

**Step 5: Checkpoint**

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

Run: `SWIFT_BUILD_DIR=".build-agent-forge"; swift test --build-path "$SWIFT_BUILD_DIR" --filter "ForgeActorTests" > /tmp/luna350-task7.log 2>&1; echo $?`
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

**Step 5: Checkpoint**

```bash
git add Sources/AgentStudio/Core/PaneRuntime/Sources/ForgeActor.swift \
  Sources/AgentStudio/App/FilesystemGitPipeline.swift \
  Sources/AgentStudio/App/PaneCoordinator.swift \
  Tests/AgentStudioTests/Core/PaneRuntime/Sources/ForgeActorTests.swift
git commit -m "feat(forge): add event-driven forge actor with polling fallback"
```

### Task 7a: Wire Concrete FSEventStreamClient in Production

> **Closes the LUNA-349 gap.** `FilesystemActor` and `FilesystemGitPipeline` default to `NoopFSEventStreamClient`. Without production wiring, the entire enrichment pipeline (filesystem → git → forge) cannot trigger from real OS events. Tests use `enqueueRawPathsForTesting` seams, but the app runs with live events disabled.

**Files:**
- Create: `Sources/AgentStudio/Core/PaneRuntime/Sources/DarwinFSEventStreamClient.swift`
- Modify: `Sources/AgentStudio/App/FilesystemGitPipeline.swift`
- Modify: `Sources/AgentStudio/App/AppDelegate.swift` (composition root)
- Test: `Tests/AgentStudioTests/Core/PaneRuntime/Sources/DarwinFSEventStreamClientTests.swift`

**Step 1: Write failing tests**

```swift
@Suite("DarwinFSEventStreamClient")
struct DarwinFSEventStreamClientTests {
    @Test("conforms to FSEventStreamClient protocol")
    func conformsToProtocol() {
        let client = DarwinFSEventStreamClient()
        #expect(client is any FSEventStreamClient)
    }

    @Test("start/stop lifecycle is idempotent")
    func lifecycleIdempotent() async {
        let client = DarwinFSEventStreamClient()
        // Double-start, double-stop should not crash
        await client.start(paths: ["/tmp"], callback: { _ in })
        await client.start(paths: ["/tmp"], callback: { _ in })
        await client.stop()
        await client.stop()
    }
}
```

**Step 2: Run tests to verify failure**

Run: `SWIFT_BUILD_DIR=".build-agent-fsevents"; swift test --build-path "$SWIFT_BUILD_DIR" --filter "DarwinFSEventStreamClientTests" > /tmp/luna350-task7a.log 2>&1; echo $?`
Expected: missing `DarwinFSEventStreamClient` symbol.

**Step 3: Write minimal implementation**

Implement `DarwinFSEventStreamClient` wrapping macOS `FSEventStream` C API. Wire in `FilesystemGitPipeline` and `AppDelegate` composition root:

```swift
// AppDelegate or composition root:
let fsClient = DarwinFSEventStreamClient()
let pipeline = FilesystemGitPipeline(
    bus: PaneRuntimeEventBus.shared,
    fseventStreamClient: fsClient  // replaces NoopFSEventStreamClient
)
```

Remove the `TODO(LUNA-349)` warning log from `FilesystemActor.init`.

**Step 4: Run tests to verify pass**

Run: same command from Step 2.
Expected: exit code `0`.

**Step 5: Checkpoint**

```bash
git add Sources/AgentStudio/Core/PaneRuntime/Sources/DarwinFSEventStreamClient.swift \
  Sources/AgentStudio/App/FilesystemGitPipeline.swift \
  Sources/AgentStudio/App/AppDelegate.swift \
  Tests/AgentStudioTests/Core/PaneRuntime/Sources/DarwinFSEventStreamClientTests.swift
git commit -m "feat(filesystem): wire DarwinFSEventStreamClient for live OS events"
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

Run: `SWIFT_BUILD_DIR=".build-agent-repo-move"; swift test --build-path "$SWIFT_BUILD_DIR" --filter "WorkspaceStoreOrphanPoolTests|WorkspaceCacheCoordinatorRepoMoveTests" > /tmp/luna350-task8.log 2>&1; echo $?`
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

**Step 5: Checkpoint**

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

Run: `SWIFT_BUILD_DIR=".build-agent-sidebar-rewire"; swift test --build-path "$SWIFT_BUILD_DIR" --filter "RepoSidebarContentViewTests|SidebarRepoGroupingTests|PaneCoordinatorTests" > /tmp/luna350-task9.log 2>&1; echo $?`
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

**Step 5: Checkpoint**

```bash
git add Sources/AgentStudio/App/MainSplitViewController.swift \
  Sources/AgentStudio/Features/Sidebar/RepoSidebarContentView.swift \
  Sources/AgentStudio/Features/Sidebar/SidebarGitRepositoryInspector.swift \
  Tests/AgentStudioTests/Features/Sidebar/RepoSidebarContentViewTests.swift \
  Tests/AgentStudioTests/Features/Sidebar/SidebarRepoGroupingTests.swift \
  Tests/AgentStudioTests/App/PaneCoordinatorTests.swift
git commit -m "refactor(sidebar): remove direct store mutations and route intents through coordinator"
```

### Task 9a: Migrate WorkspaceGitWorkingTreeStore → WorkspaceCacheStore

> **Removes LUNA-349 interim projection store.** `WorkspaceGitWorkingTreeStore` was a temporary projection store for sidebar git status. `WorkspaceCacheStore` (Task 4) supersedes it. All consumers must migrate.

**Files:**
- Remove: `Sources/AgentStudio/Core/PaneRuntime/Projection/WorkspaceGitWorkingTreeStore.swift`
- Modify: `Sources/AgentStudio/App/PaneCoordinator.swift` (remove `workspaceGitWorkingTreeStore` property)
- Modify: `Sources/AgentStudio/Features/Sidebar/RepoSidebarContentView.swift` (read from `WorkspaceCacheStore` instead)
- Test: `Tests/AgentStudioTests/Features/Sidebar/RepoSidebarContentViewTests.swift`

**Step 1: Write failing tests**

```swift
@Test("sidebar reads git status from WorkspaceCacheStore, not WorkspaceGitWorkingTreeStore")
func sidebarUsesNewCacheStore() {
    // Assert RepoSidebarContentView has no dependency on WorkspaceGitWorkingTreeStore
    // Assert it reads WorktreeEnrichment.branch from WorkspaceCacheStore
}
```

**Step 2: Run tests to verify failure**

Run: `SWIFT_BUILD_DIR=".build-agent-store-migration"; swift test --build-path "$SWIFT_BUILD_DIR" --filter "RepoSidebarContentViewTests" > /tmp/luna350-task9a.log 2>&1; echo $?`
Expected: assertion failure on old dependency.

**Step 3: Write minimal implementation**

- Replace `workspaceGitWorkingTreeStore: WorkspaceGitWorkingTreeStore` with `cacheStore: WorkspaceCacheStore` in `RepoSidebarContentView`
- Replace `WorktreeSnapshot` reads with `WorktreeEnrichment` reads from cache store
- Remove `WorkspaceGitWorkingTreeStore` from `PaneCoordinator` constructor
- Delete `WorkspaceGitWorkingTreeStore.swift`

**Step 4: Run tests to verify pass**

Run: same command from Step 2.
Expected: exit code `0`.

**Step 5: Checkpoint**

```bash
git add Sources/AgentStudio/App/PaneCoordinator.swift \
  Sources/AgentStudio/Features/Sidebar/RepoSidebarContentView.swift \
  Tests/AgentStudioTests/Features/Sidebar/RepoSidebarContentViewTests.swift
git rm Sources/AgentStudio/Core/PaneRuntime/Projection/WorkspaceGitWorkingTreeStore.swift
git commit -m "refactor(sidebar): migrate from WorkspaceGitWorkingTreeStore to WorkspaceCacheStore"
```

### Task 9b: Update DynamicViewProjector Input Types

> **Adapts projector to canonical + cache models.** `DynamicViewProjector.project()` currently takes `repos: [Repo]` (contaminated). After model split, it must read from canonical repos + enrichment cache.

**Files:**
- Modify: `Sources/AgentStudio/Core/Stores/DynamicViewProjector.swift`
- Modify: callers of `DynamicViewProjector.project()` (grep for callsites)
- Test: existing `DynamicViewProjectorTests.swift`

**Step 1: Write failing tests**

```swift
@Test("projector groups by repo using CanonicalRepo + RepoEnrichment")
func projectByRepoUsesCanonicalModels() {
    let repo = CanonicalRepo(id: UUID(), name: "test", repoPath: URL(fileURLWithPath: "/tmp"), createdAt: Date())
    let enrichment = RepoEnrichment(repoId: repo.id, organizationName: "org")
    let projection = DynamicViewProjector.project(
        viewType: .byRepo,
        panes: [:],
        tabs: [],
        repos: [repo],
        repoEnrichments: [repo.id: enrichment]
    )
    #expect(projection.groups.isEmpty)  // no panes → no groups
}
```

**Step 2: Run tests to verify failure**

Run: `SWIFT_BUILD_DIR=".build-agent-projector"; swift test --build-path "$SWIFT_BUILD_DIR" --filter "DynamicViewProjector" > /tmp/luna350-task9b.log 2>&1; echo $?`
Expected: signature mismatch.

**Step 3: Write minimal implementation**

Update `DynamicViewProjector.project()` signature:
```swift
static func project(
    viewType: DynamicViewType,
    panes: [UUID: Pane],
    tabs: [Tab],
    repos: [CanonicalRepo],
    repoEnrichments: [UUID: RepoEnrichment],
    worktreeEnrichments: [UUID: WorktreeEnrichment]
) -> DynamicViewProjection
```

Update grouping logic to join canonical + enrichment data. Update all callsites.

**Step 4: Run tests to verify pass**

Run: same command from Step 2.
Expected: exit code `0`.

**Step 5: Checkpoint**

```bash
git add Sources/AgentStudio/Core/Stores/DynamicViewProjector.swift \
  Tests/AgentStudioTests/Core/Stores/DynamicViewProjectorTests.swift
git commit -m "refactor(projector): update DynamicViewProjector to use canonical + enrichment models"
```

### Task 9c: Migrate repoWorktreesDidChangeHook → Bus Subscription

> **Removes imperative hook.** `PaneCoordinator+FilesystemSource.swift` uses `store.repoWorktreesDidChangeHook` to sync filesystem roots when repos change. After the event bus migration, this should be driven by topology events on the bus, not a store hook.

**Files:**
- Modify: `Sources/AgentStudio/App/PaneCoordinator+FilesystemSource.swift`
- Modify: `Sources/AgentStudio/Core/Stores/WorkspaceStore.swift` (remove hook property)
- Test: `Tests/AgentStudioTests/App/PaneCoordinatorTests.swift`

**Step 1: Write failing tests**

```swift
@Test("filesystem source sync reacts to topology events, not store hook")
func filesystemSyncViaTopologyEvents() async {
    // Post a SystemEnvelope(.topology(.repoDiscovered(...)))
    // Assert FilesystemActor.register() was called
    // Assert store.repoWorktreesDidChangeHook is nil / removed
}
```

**Step 2: Run tests to verify failure**

Run: `SWIFT_BUILD_DIR=".build-agent-hook-migration"; swift test --build-path "$SWIFT_BUILD_DIR" --filter "PaneCoordinatorTests" > /tmp/luna350-task9c.log 2>&1; echo $?`
Expected: failure on hook removal assertion.

**Step 3: Write minimal implementation**

- Remove `repoWorktreesDidChangeHook` property from `WorkspaceStore`
- In `PaneCoordinator+FilesystemSource.swift`, replace `setupFilesystemSourceSync()` hook installation with a bus subscription that listens for topology events
- `WorkspaceCacheCoordinator` already handles topology → canonical mutations (Task 5). The coordinator's `syncScope_*` methods handle actor registration. Verify no duplicate registration path.

**Step 4: Run tests to verify pass**

Run: same command from Step 2.
Expected: exit code `0`.

**Step 5: Checkpoint**

```bash
git add Sources/AgentStudio/App/PaneCoordinator+FilesystemSource.swift \
  Sources/AgentStudio/Core/Stores/WorkspaceStore.swift \
  Tests/AgentStudioTests/App/PaneCoordinatorTests.swift
git commit -m "refactor(coordinator): replace repoWorktreesDidChangeHook with bus topology subscription"
```

### Task 9d: Wire App Boot Sequence

> **Composes the full startup pipeline.** The [architecture spec](../architecture/workspace_data_architecture.md#app-boot) defines a 10-step boot sequence. This task wires it in `AppDelegate`.

**Files:**
- Modify: `Sources/AgentStudio/App/AppDelegate.swift`
- Modify: `Sources/AgentStudio/App/PaneCoordinator.swift`
- Test: `Tests/AgentStudioTests/App/AppBootSequenceTests.swift`

**Step 1: Write failing tests**

```swift
@Suite("App boot sequence")
struct AppBootSequenceTests {
    @Test("boot loads canonical, cache, and UI state in order")
    func loadsThreeTiers() async {
        // Assert WorkspaceStore loaded from workspace.state.json
        // Assert WorkspaceCacheStore loaded from workspace.cache.json
        // Assert WorkspaceUIStore loaded from workspace.ui.json
    }

    @Test("boot starts actors and coordinator after stores are loaded")
    func startsActorsAfterStores() async {
        // Assert EventBus started
        // Assert FilesystemActor started
        // Assert GitWorkingDirectoryProjector started
        // Assert ForgeActor started
        // Assert WorkspaceCacheCoordinator consuming
        // Assert FilesystemActor triggers initial parent folder rescan
    }
}
```

**Step 2: Run tests to verify failure**

Run: `SWIFT_BUILD_DIR=".build-agent-boot"; swift test --build-path "$SWIFT_BUILD_DIR" --filter "AppBootSequenceTests" > /tmp/luna350-task9d.log 2>&1; echo $?`
Expected: failure on missing boot sequence.

**Step 3: Write minimal implementation**

Wire the 10-step boot sequence from the architecture spec:

```swift
// In AppDelegate or a dedicated BootComposer:
// 1. Load config → WorkspaceStore
// 2. Load cache → WorkspaceCacheStore (sidebar renders immediately if valid)
// 3. Load UI state → WorkspaceUIStore
// 4. Start EventBus
// 5. Start FilesystemActor → reads watchedPaths
// 6. Start GitWorkingDirectoryProjector → subscribes to bus
// 7. Start ForgeActor → subscribes to bus
// 8. Start WorkspaceCacheCoordinator → subscribes to bus
// 9. FilesystemActor triggers initial rescan of parent folders
// 10. Pipeline fills cache → sidebar updates reactively
```

**Step 4: Run tests to verify pass**

Run: same command from Step 2.
Expected: exit code `0`.

**Step 5: Checkpoint**

```bash
git add Sources/AgentStudio/App/AppDelegate.swift \
  Sources/AgentStudio/App/PaneCoordinator.swift \
  Tests/AgentStudioTests/App/AppBootSequenceTests.swift
git commit -m "feat(app): wire 10-step boot sequence for event-driven workspace pipeline"
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

Run: `SWIFT_BUILD_DIR=".build-agent-e2e-pipeline"; swift test --build-path "$SWIFT_BUILD_DIR" --filter "FilesystemGitPipelineIntegrationTests|FilesystemSourceE2ETests|WorkspaceCacheCoordinatorE2ETests" > /tmp/luna350-task10.log 2>&1; echo $?`
Expected: failing assertions on chain/enrichment behavior until implementation lands.

**Step 3: Write minimal implementation adjustments**

Adjust fixtures and helpers to emit/consume `RuntimeEnvelope` and new stores.

**Step 4: Run tests to verify pass**

Run: same command from Step 2.
Expected: exit code `0`.

**Step 5: Checkpoint**

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

Run: `rg -n "EventBus<PaneEventEnvelope>|FilesystemActor.*git status|SUBSCRIBES TO: ALL WorktreeEnvelope events" docs/architecture/*.md`
Expected: zero stale matches (pre-work should have eliminated these).

**Step 2: Verify code samples match implemented types**

After Tasks 1-3 land new Swift types, update any code samples in architecture docs that show old type names or missing fields. Focus on:
- Contract 3 examples should only reference `RuntimeEnvelope` tiered contracts (no legacy envelope examples in normative sections)
- Contract 3 "Target" section - should match the actual `RuntimeEnvelope.swift`
- EventBus design actor inventory — should match actual actor files

**Step 3: Run markdown sanity check**

Run: `rg -n "TODO\(LUNA-350\)|TBD|NEEDS SPEC" docs/architecture/*.md docs/plans/*.md`
Expected: no unresolved placeholders for this scope.

**Step 4: Commit**

```bash
git add docs/architecture/pane_runtime_architecture.md \
  docs/architecture/pane_runtime_eventbus_design.md \
  docs/architecture/workspace_data_architecture.md \
  docs/architecture/component_architecture.md
git commit -m "docs(architecture): final sync after runtime envelope implementation"
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
Expected: exit code `0` with the default test suite passing. Run `mise run test-e2e` and `mise run test-zmx-e2e` for full-surface verification.

**Step 4: Final architecture invariants check**

Run the following checks (all should return zero matches):
```bash
# No direct store mutations from sidebar/controller
rg -n "updateRepoWorktrees\(|repoWorktreesDidChangeHook" Sources/AgentStudio

# No stale projection store references
rg -n "WorkspaceGitWorkingTreeStore" Sources/AgentStudio

# No NoopFSEventStreamClient in production composition (test files OK)
rg -n "NoopFSEventStreamClient" Sources/AgentStudio --glob '!*Tests*' --glob '!*Test*'

# No TODO markers for this scope
rg -n "TODO\(LUNA-349\)|TODO\(LUNA-350\)" Sources/AgentStudio

# No contaminated model usage in new code (DynamicViewProjector, sidebar should use CanonicalRepo)
rg -n "repos: \[Repo\]" Sources/AgentStudio/Core/Stores/DynamicViewProjector.swift Sources/AgentStudio/Features/Sidebar/
```
Expected: zero matches for all checks.

**Step 5: Checkpoint**

```bash
git add -A
git commit -m "chore(luna-350): final verification pass and contract cleanup"
```

---

## Acceptance Checklist

**Event Architecture:**
- [ ] All event-plane producers emit `RuntimeEnvelope` with correct tier scoping.
- [ ] Topology events are `SystemEnvelope` and never require `repoId`.
- [ ] Filesystem/git/forge events are `WorktreeEnvelope` with required `repoId`.
- [ ] Bus replay policy (256 events/source) is documented and implemented consistently.
- [ ] Legacy envelope path removed completely: no `PaneEventEnvelope`, `fromLegacy`, `toLegacy`, or dual-bus constructors.
- [ ] `RuntimeEnvelope` contracts are split by responsibility (core, metadata, factories), not monolithic.
- [ ] `NotificationReducer` handles `.system` envelopes with tested behavior (no silent discard).

**Model & Persistence:**
- [ ] `Repo`/`Worktree` structs split into canonical + enrichment tiers (no contamination).
- [ ] Persistence writes to three files: `workspace.state.json`, `workspace.cache.json`, `workspace.ui.json`.
- [ ] `WorkspaceCacheCoordinator` is sole event-driven mutator for canonical/cache split.

**Production Pipeline:**
- [ ] Concrete `DarwinFSEventStreamClient` wired in production composition root (no more `NoopFSEventStreamClient` in production).
- [ ] Boot sequence follows the 10-step order from architecture spec.
- [ ] `repoWorktreesDidChangeHook` removed; filesystem sync driven by bus topology events.

**Sidebar & Consumers:**
- [ ] Sidebar is pure reader; direct `updateRepoWorktrees` mutations removed from all UI callsites.
- [ ] `WorkspaceGitWorkingTreeStore` removed; sidebar reads from `WorkspaceCacheStore`.
- [ ] `DynamicViewProjector` reads from canonical + enrichment models, not contaminated `Repo`.

**Lifecycle:**
- [ ] Repo-move/orphan/relink lifecycle works with stable UUID identity semantics.

**Quality Gate:**
- [ ] `mise run format`, `mise run lint`, and `mise run test` all pass.
- [ ] No `TODO(LUNA-349)` or `TODO(LUNA-350)` markers remain in production source.
- [ ] `EventBus` shutdown/deinit closes subscriber continuations deterministically.
- [ ] Replay subscribe outcomes are checked and replay gaps are observable in logs/tests.

---

## Execution Handoff

Plan complete and saved to `docs/plans/2026-03-01-luna-350-runtime-envelope-workspace-persistence-sidebar-consolidated.md`.

Two execution options:

1. Subagent-Driven (this session) - I dispatch a fresh subagent per task, review between tasks, and keep fast iteration loops.
2. Separate Session (not parallel) - Open a new session with `superpowers:executing-plans` after stopping this session's Swift commands.

Which approach?
