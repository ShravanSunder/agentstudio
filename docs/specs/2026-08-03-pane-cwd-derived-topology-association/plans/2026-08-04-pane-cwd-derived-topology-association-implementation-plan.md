# Pane CWD-Derived Topology Association — Implementation Plan

Status: implementation in progress against a fresh pair-reviewed requirements/program-design identity.

## Planning basis

- Target classification: `general-domain`, `current-pair-ready`.
- Requirements: `../2026-08-03-pane-cwd-derived-topology-association-requirements.md`, 449 lines, SHA-256 `a827c45c843f677ecb377af69bffceec4bf2234fa50f6cca419b67750054fbe9`.
- Program design: `../2026-08-03-pane-cwd-derived-topology-association-program-design.md`, 841 lines, SHA-256 `c0d6efc7a496fbf01791e84b39f4cd8a06139e26888a89e4d959b6019999f392`.
- Pair review: fresh bounded review `READY` against both identities above; the CWD ingress delta is complete and residual unrelated global identity corruption remains the existing strict startup invariant rather than new recovery scope.
- Live source baseline: branch `fix-bugs-save`, HEAD `6e157f6329be6c786ba5f7a40ab13cd4fad18e46`; linked worktree; only the reviewed spec directory was untracked before planning.
- Baseline proof: `mise run setup` passed; `mise run test:swift -- --filter "WorkspaceCoreRepositoryPaneGraphValidationTests"` passed 17/17.

## Goal and non-goals

Remove generic pane repo/worktree UUID persistence so topology removal cannot wedge later workspace saves, derive current association from pane CWD, preserve required pane location behavior and orphan lifecycle, enforce the available-main invariant through current topology owners, and migrate deployed SQLite state without pane/layout loss.

Do not add a mapping table, compatibility writer, feature flag, actor, timer, coordinator, repair queue, public degraded-state UI, pane-table rebuild, zmx change, or unrelated topology/cache cleanup. Production remains read-only. Beta/release work is out of scope.

Security context: filesystem validation remains exact-root, read-only Git discovery; SQLite changes run in the existing GRDB transaction; OTLP exports bounded reason enums only and must reject paths, UUIDs, raw errors, and payloads.

## Execution strategy

The work is serial. Slices S1-S4 overlap the pane graph, state bridge, derived model, topology coordinator, boot snapshots, and integration fixtures. Parallel production edits would require temporary compatibility behavior or conflict-heavy integration, both forbidden by the design. Read-only review may run in parallel with controller validation.

```text
gate 0: current pair READY + linked worktree + baseline focused suite
  |
S0 RED: reproduce direct-unregistration save/restart rollback
  |
S1 CWD-only durable hard cut + migration 015
  |
S2 exhaustive location admission/restore + derived association
  |
S3 topology invariant + atomic unregistration + CWD orphan lifecycle
  |
S4 truthful boot flush/exact-root repair + scrubbed reasons
  |
integration gate: focused suites + diff/source boundary audit
  |
full gate: format + lint + mise run test
  |
runtime gate: isolated debug copied fixture + IPC save/restart + VictoriaLogs
  |
implementation-review-swarm
```

## S0 — RED incident reproduction

Source: PR-01, PR-06, PR-08; journey J-01.

Add the smallest real SQLite integration test in `Tests/AgentStudioTests/Core/State/MainActor/Persistence/WorkspaceSQLiteSaveCoordinatorTests.swift`, reusing the existing GRDB repository/datastore/save coordinator fixtures:

1. Persist a repo, main/linked worktree, Terminal pane whose CWD is under the linked worktree, and baseline layout.
2. Remove the linked worktree through the direct unregistration path and persist topology deletion.
3. Add panes and change drawer membership/order.
4. Flush composition and reload through a fresh datastore/store.
5. Assert the latest panes, drawer membership/order, CWD, and content survive.

Capture current RED as `WorkspaceCoreRepositoryError.worktreeNotFound(removedWorktreeID)` from `resolvedPaneReferenceIds`. Add a sibling scanned-removal case to `Tests/AgentStudioTests/Integration/TopologyEventPipelineIntegrationTests.swift` only if the existing authoritative-removal test cannot assert save/reload convergence.

Checkpoint:

```bash
mise run test:swift -- --filter "WorkspaceSQLiteSaveCoordinatorTests/directWorktreeUnregistrationCommitsLaterWorkspaceSnapshot"
```

Stop if the test fails for setup or a different error rather than the incident path.

## S1 — CWD-only durable hard cut and migration 015

Source: PR-01, PR-08, PR-10, PR-11.

Production write set:

- `Sources/AgentStudio/Core/State/MainActor/Atoms/WorkspacePaneGraphAtom.swift`
- `Sources/AgentStudio/Core/State/MainActor/Atoms/WorkspacePaneAtom.swift`
- `Sources/AgentStudio/Core/State/MainActor/Atoms/WorkspacePaneDerived.swift`
- `Sources/AgentStudio/Core/State/MainActor/Persistence/WorkspaceSQLiteStoreBackend.swift`
- `Sources/AgentStudio/Core/State/MainActor/Persistence/WorkspaceCoreRepository+PaneGraph.swift`
- `Sources/AgentStudio/Core/State/MainActor/Persistence/WorkspaceCoreRepository+PaneGraphMutation.swift`
- `Sources/AgentStudio/Core/State/MainActor/Persistence/WorkspaceCoreMigrations.swift`

Changes:

1. Make `PaneGraphFacets` and repository/bridge durable facet records CWD-only.
2. Make CWD the only pane graph write from boundary `PaneContextFacets`; remove stored-ID-first derivation and graph worktree queries.
3. Remove pane repo/worktree columns and arguments, `resolvedPaneReferenceIds`, `fetchPaneReferenceWorktreeRepoId`, and `paneReferenceRepoExists`.
4. Add `015_drop_pane_topology_facets`: drop four facet triggers, then directly drop both facet columns transactionally.
5. Update all predecessor fixtures and migration identifier assertions in one cut. Do not rebuild `pane`.

Tests:

- Add `WorkspaceCorePaneTopologyFacetMigrationTests.swift`, seeded at migration 014, preserving pane/drawer/tab/arrangement ordering, content, zmx anchor, CWD, launch directory, checkout ref, note, and Bridge source. Include malformed raw legacy facet text so migration proof does not depend on Swift UUID decoding.
- Assert both columns/four triggers absent, `quick_check = ok`, `foreign_key_check` empty, application load/flush/reload succeeds, and migration failure rolls back.
- Replace obsolete repository tests that expect topology-facet rejection with tests that prove missing/deleted topology does not affect pane persistence.
- Turn S0 GREEN.

Focused gates:

```bash
mise run test:swift -- --filter "WorkspaceCorePaneTopologyFacetMigrationTests"
mise run test:swift -- --filter "WorkspaceCoreMigrationTests"
mise run test:swift -- --filter "WorkspaceCoreRepositoryPaneGraphValidationTests"
mise run test:swift -- --filter "WorkspaceSQLiteSaveCoordinatorTests"
```

Design-break trigger: direct `ALTER TABLE ... DROP COLUMN` fails under the repo GRDB/SQLite runtime.

## S2 — Location policy, restore, and derived association

Source: PR-02, PR-03, PR-04, PR-06, PR-07, PR-09, PR-11.

Production write set:

- New pure Core policy beside current pane content models: `PaneFilesystemLocationPolicy.swift`.
- `Sources/AgentStudio/Core/RuntimeEventSystem/Contracts/PaneMetadata.swift`
- current workspace composition preparation/state bridge files discovered from the S1 compiler cut
- `Sources/AgentStudio/Core/State/MainActor/Atoms/RepositoryTopologyAtom.swift`
- `Sources/AgentStudio/Core/State/MainActor/Atoms/WorkspacePaneDerived.swift`
- App pane creation/runtime CWD ingress files under `Sources/AgentStudio/App/Coordination/`

Changes:

1. Exhaustively classify Terminal, Bridge Files/Review, Code Viewer, Webview, and unsupported content.
2. Repair restored required location only from launch directory, Bridge workspace root, or Code Viewer file parent; otherwise retain a saveable degraded-required pane.
3. Resolve context-free Terminal creation to explicit/inherited directory or user home before durable insertion.
4. Treat invalid required-pane runtime samples as no accepted update, preserving the last valid CWD.
5. Make `WorkspacePaneDerived` always resolve from CWD through `RepositoryTopologyAtom`; filter unavailable repos; retain deepest component-boundary matching and deterministic ambiguity handling.

Tests:

- New exhaustive `PaneFilesystemLocationPolicyTests.swift`.
- Update `WorkspaceSQLiteStoreBridgeTests`, `WorkspaceSurfaceCoordinatorCWDIdentityTests`, and Bridge/Code Viewer construction tests.
- Extend `RepositoryTopologyAtomTests`, `WorkspacePaneBoundaryTests`, and `RepositoryTopologyHotPathArchitectureTests` for exact root, descendant, deeper linked worktree, `/repo` versus `/repo-tools`, unavailable/deleted path, CWD change, and re-registration with a new UUID.
- Add a duplicate-depth corrupt-candidate preparation/reconciliation case proving deterministic rejection or tie behavior, one bounded scrubbed ambiguity reason, and zero per-read hot-path emissions; pair it with the OTLP sanitization assertion in S4.

Focused gates:

```bash
mise run test:swift -- --filter "PaneFilesystemLocationPolicyTests"
mise run test:swift -- --filter "WorkspaceSQLiteStoreBridgeTests"
mise run test:swift -- --filter "WorkspaceSurfaceCoordinatorCWDIdentityTests"
mise run test:swift -- --filter "RepositoryTopologyAtomTests"
mise run test:swift -- --filter "WorkspacePaneBoundaryTests"
```

Stop if truthful degraded restore requires a new public UI/state contract rather than the reviewed content-plus-nil-CWD representation.

## S3 — Main-worktree invariant, atomic mutation, and orphan lifecycle

Source: PR-04, PR-05, PR-06, PR-09, PR-11.

Production write set:

- `WorkspacePersistenceTransformer.swift`
- `RepositoryTopologyReplacement.swift`
- `WorkspaceMutationCoordinator+RepositoryTopology.swift`
- `WorkspaceMutationCoordinator.swift`
- `WorkspaceCacheCoordinator.swift`
- `WorkspaceSurfaceCoordinator.swift`
- `WorkspaceStore.swift`
- `RepositoryTopologyAtom.swift`

Changes:

1. Normalize a unique repo-path worktree as main while preserving UUID; mark missing/ambiguous repo-path topology unavailable without filesystem guesses.
2. Reject available zero-main, multiple-main, or wrong-path-main replacements recoverably.
3. Add one existing-owner atomic unregistration operation that prepares remaining worktrees plus unavailable membership, validates/applies one replacement, and returns accepted delta or typed rejection.
4. Prevent `.notScanned` from clearing missing-main degradation; forward accepted deltas from direct/scanned registration, unregistration, and reassociation.
5. Orphan by removed-path/CWD containment only when no replacement currently contains CWD; restore active/backgrounded residency from current containment after initial topology application in `WorkspaceStore` and after every accepted delta; delete UUID-specific restoration.

Tests:

- `WorkspacePersistenceTransformerTests`
- `RepositoryTopologyAtomTests`
- `WorkspaceCacheCoordinatorTests` and integration tests
- `TopologyEventPipelineIntegrationTests`
- `WorkspaceSurfaceCoordinatorFilesystemEffectsTests`
- `WorkspaceStoreOrphanPoolTests` cold-load restoration after re-registration with a new UUID
- orphan removal/re-addition with a new UUID through direct and scanned paths

Focused gates:

```bash
mise run test:swift -- --filter "WorkspacePersistenceTransformerTests"
mise run test:swift -- --filter "WorkspaceCacheCoordinatorTests"
mise run test:swift -- --filter "WorkspaceCacheCoordinatorIntegrationTests"
mise run test:swift -- --filter "TopologyEventPipelineIntegrationTests"
mise run test:swift -- --filter "WorkspaceSurfaceCoordinatorFilesystemEffectsTests"
mise run test:swift -- --filter "WorkspaceStoreOrphanPoolTests"
```

## S4 — Truthful boot persistence, exact-root repair, and diagnostics

Source: PR-05, PR-09, PR-12.

Production write set:

- `Sources/AgentStudio/App/Boot/WorkspaceBootSequence.swift`
- `Sources/AgentStudio/App/Boot/AppDelegate+WorkspaceBoot.swift`
- `Sources/AgentStudio/Core/State/MainActor/Persistence/RepositoryTopologyStore.swift`
- `Sources/AgentStudio/Infrastructure/RepoScanner.swift` only to expose existing scan through package visibility
- existing trace/recovery and OTLP projection owners

Changes:

1. Arm `WorkspaceStore` and `RepositoryTopologyStore`, explicitly flush normalized/degraded topology, then start the existing deferred topology task.
2. On initial flush failure: retain in-memory degradation, keep canonical observers armed, skip exact-root repair, run independent cache/local observer/prune completion, emit the bounded failure reason, and retain existing lifecycle/termination flush eligibility.
3. In the existing deferred lane, exact-root `RepoScanner.scan(maxDepth: 0)` only unavailable repos missing a valid main; accept only complete canonical clone-root evidence and compose the accepted delta through existing effect ownership.
4. Emit bounded repair/degradation/save phase reasons; allowlist only controlled enums in OTLP and reject paths, UUIDs, raw errors, and payloads. No per-read lookup-miss logs.
5. Prove the pane-association ambiguity reason is emitted once from preparation/reconciliation for corrupt duplicate-depth input, is scrubbed in OTLP, and is never emitted from ordinary reads.
6. Emit bounded `topology_normalization_rejected` telemetry before the existing strict residual topology invariant stops startup. This adds diagnosis, not a new recovery or quarantine owner; residual unrelated global identity corruption remains outside this Pane CWD/save-loss change.

Tests:

- `AppBootSequenceTests` plus behavioral deferred topology repair/flush failure coverage in the narrowest existing App test seam.
- `RepositoryTopologyStoreTests` if the failure/retry contract is not already directly injectable.
- `RepoScannerCompletenessTests` for exact-root result acceptance.
- `WorkspaceTopologyBootRepairIntegrationTests` for degraded persisted topology -> exact-root scan -> production reassociation -> flush -> fresh-datastore reload.
- existing OTLP projection/sanitization and trace runtime tests.

Focused gates:

```bash
mise run test:swift -- --filter "AppBootSequenceTests"
mise run test:swift -- --filter "RepositoryTopologyStoreTests"
mise run test:swift -- --filter "RepoScannerCompletenessTests"
mise run test:swift -- --filter "WorkspaceTopologyBootRepairIntegrationTests"
mise run test:swift -- --filter "AgentStudioOTLPTraceProjection"
```

PR-09 checkpoint: add negative-path coverage for malformed legacy facet UUIDs, missing topology targets, missing required CWD, missing-main topology, and termination-flush success truthfulness. Perform a scoped source/architecture audit proving those recoverable states cannot reach `preconditionFailure`, force unwraps, or the boot `.topologyRejected` trap. Unrelated invariant traps remain out of scope and must not be removed merely to satisfy this gate.

## Requirements and proof matrix

| Requirements | Owning slice | Proof layer | Required evidence | Freshness guard | RED/GREEN |
| --- | --- | --- | --- | --- | --- |
| PR-01, PR-06, PR-08 | S0-S1 | real SQLite integration | direct removal then later save/reload preserves full graph | fresh store/DB at current HEAD | required |
| PR-02, PR-03, PR-07, PR-09 | S2 | unit + restore integration | exhaustive policy, invalid sample latch, repaired/degraded round trip | literal content table and fresh fixture | required |
| PR-04, PR-06, PR-11 | S2-S3 | unit + state integration | deepest component containment; cold/live/new-UUID equality; unavailable excluded | topology generation and fresh atom | required |
| PR-05, PR-06, PR-09 | S3-S4 | topology/boot integration | normalization, atomic main removal, `.notScanned` preservation, exact-root scan heal, production reassociation, persist, fresh-datastore reload, flush failure | fresh 014/topology fixtures | required |
| PR-01, PR-07, PR-10, PR-11 | S1 | migration + restore integration | direct drop from malformed raw legacy facets, row invariants, quick/FK checks, rollback, application load/flush/reload | seed migration 014 every run | required |
| PR-08, PR-09, PR-12 | S4 | producer + projection + runtime observability | positive producer delivery for bounded repair/degradation/rejection reasons, no raw identifiers/paths/errors, marker-scoped logs | fresh debug marker/PID/HEAD | required |

## Integration and completion gates

After each slice, inspect the diff and run its focused tests. Before any readiness claim:

```bash
mise run format
mise run lint
mise run test
git diff --check
```

Then use only an isolated debug data root and copied/synthetic production-shaped migration-014 database:

```bash
mise run observability:up
AGENTSTUDIO_IPC_DEBUG_TOKEN_ESCROW=1 mise run run-debug-observability -- --detach
mise run verify-debug-observability
```

Exercise Terminal, Bridge Files, Bridge Review, Code Viewer, and locationless Webview; remove/re-register a disposable worktree; flush, terminate, restart, and compare pane/drawer/tab/order/content/zmx/CWD/topology snapshots. Query marker-scoped VictoriaLogs for controlled reasons and zero sentinel path/UUID hits. Never point debug at stable data.

Completion requires implementation review after all automated and runtime gates. If the 45-minute target expires, report completed slices with their exact proof and continue unless a design break or destructive risk requires user input; time does not waive migration, incident RED/GREEN, full `mise run test`, or isolated runtime proof.

## Rollback and stop conditions

Before deployment the branch is the rollback boundary. Migration failure is transactional and remains under the existing database quarantine/recovery owner. After a deployed hard cut, do not add a backward compatibility writer; forward-fix through the same canonical schema.

Stop and return to design if implementation needs a new lifecycle owner, actor, timer, coordinator, persistence store, mapping/cache authority, pane-table rebuild, public degraded-state contract, scanner ownership change, or proof-gate weakening. Split/replan if a focused proof cannot pass without unrelated infrastructure changes.
