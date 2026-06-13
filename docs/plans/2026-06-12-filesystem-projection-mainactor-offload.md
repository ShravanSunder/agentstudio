# Filesystem Projection MainActor Offload Plan

Status: draft for plan review
Spec: `docs/superpowers/specs/2026-06-12-filesystem-projection-mainactor-offload.md`
Branch: `performance-issues`

## Goal

Move fleet-sized filesystem root normalization, source-sync diffing, and
pane/filesystem projection filtering out of `PaneCoordinator`'s MainActor hot
path while preserving current `FilesystemGitPipeline` behavior and
`PaneFilesystemProjectionAtom` ownership.

## Non-Goals

- Do not change git status cadence, admission, concurrency, or provider
  behavior.
- Do not implement Spec A AtomLib primitives.
- Do not move observable snapshot/sequence ownership out of
  `PaneFilesystemProjectionAtom`.
- Do not touch the user's production AgentStudio process.
- Do not add wall-clock sleeps or new `#if DEBUG` hooks.
- Do not require manual UI smoke actions as first-slice proof.

## File Ownership

New production files:

- `Sources/AgentStudio/App/Coordination/FilesystemProjectionIndex.swift`
  - actor, Sendable DTOs, normalization cache, source-sync diffing,
    pane-worktree index, filesystem path filtering.

Edited production files:

- `Sources/AgentStudio/App/Coordination/PaneCoordinator.swift`
  - add index property injection.
  - forward pane CWD changes and teardown to the index.
- `Sources/AgentStudio/App/Coordination/PaneCoordinator+FilesystemSource.swift`
  - build compact snapshots from atoms.
  - call index actor.
  - apply returned source writes/deltas.
  - add stale generation checks and split timing fields.
- `Sources/AgentStudio/App/Coordination/PaneCoordinatorFilesystemProjectionIndexing.swift`
  - optional extension file if forwarding pane CWD/teardown and applying actor
    results makes `PaneCoordinator.swift` too broad.
- `Sources/AgentStudio/Core/State/MainActor/Atoms/PaneFilesystemProjectionAtom.swift`
  - remain observable owner.
  - expose small apply helpers only if needed.
  - remove or delegate pure filtering helpers when actor owns them.
- `Sources/AgentStudio/Infrastructure/Diagnostics/AgentStudioOTLPTraceProjection.swift`
  - allowlist new low-cardinality coordinator phase/timing fields.

Edited tests:

- `Tests/AgentStudioTests/App/Coordination/FilesystemProjectionIndexTests.swift`
  - new unit tests for actor behavior.
- `Tests/AgentStudioTests/App/Coordination/PaneCoordinatorFilesystemSourceTests.swift`
  - focused integration tests for delegation, convergence, CWD, teardown,
    stale result rejection, and source-write ordering.
- `Tests/AgentStudioTests/Integration/FilesystemSourceE2ETests.swift`
  - existing filtered E2E seam gate.
- `Tests/AgentStudioTests/Infrastructure/Diagnostics/AgentStudioOTLPTraceProjectionTests.swift`
  - new fields survive projection and sensitive fields remain scrubbed.
- Existing script tests only if the workload proof command changes.

No view files should be edited in this slice.

## Implementation Steps

### 1. Red-first index tests

Add `FilesystemProjectionIndexTests` before production code:

- Reconcile normalizes worktree paths and returns deterministic register and
  activity operations.
- Identical reconcile returns no source writes.
- Active worktree and active-pane ordering match current
  `sortWorktreeByPriority` behavior.
- Filesystem changes filter by pane cwd within worktree root.
- No-op changes return no derived envelopes and do not need all-worktree roots
  on the MainActor side.
- Git snapshot projection returns per-pane snapshot deltas and derived
  projection intents; MainActor/atom code remains responsible for envelope
  sequence ownership.
- Incremental CWD update changes the actor cache and invalidates stale filtered
  state.
- Pane removal prunes actor facts.
- Stale reconcile result is discarded when a newer request wins.

Use temporary paths and direct actor calls. No sleeps.

### 2. Implement `FilesystemProjectionIndex`

Add actor and DTOs:

- `FilesystemProjectionTopologyEntry`
- `FilesystemProjectionPaneEntry`
- `FilesystemProjectionPaneUpdate`
- `FilesystemSourceSyncRequest`
- `FilesystemSourceSyncDiff`
- `PaneFilesystemProjectionRequest`
- `PaneFilesystemProjectionResult`
- `PaneFilesystemSnapshotDelta`
- `PaneFilesystemProjectionIntent`

Implementation rules:

- Store canonical worktree path strings and URL values in the actor.
- Cache canonicalization by raw URL path.
- Keep snapshot/sequence/envelope authority out of the actor; return projection
  intents and deltas with request generation. MainActor applies those through
  `PaneFilesystemProjectionAtom`, then builds/publishes envelopes from
  atom-owned sequence state.
- Keep helper methods internal where tests need them; avoid broad public API.
- No imports of SwiftUI or Observation.

### 3. Red-first coordinator integration tests

Add focused `PaneCoordinatorFilesystemSourceTests`:

- Existing in-flight sync convergence remains passing with the actor hop.
- A stale source-sync result does not unregister/register/prune after a newer
  request exists.
- Stale projection result is dropped when topology or pane-context generation
  changes before apply.
- Queued/asynchronous publish cannot post after pane teardown or topology
  removal. Prefer guarded inline publish during the apply phase; if a task is
  retained, it must recheck generations before posting.
- `updatePaneCWDAndResolvedContext` forwards full context upsert/remove data to
  the index and still updates `PaneFilesystemProjectionAtom`.
- CWD moving from one worktree to another updates repo/worktree/cwd together.
- CWD moving outside any tracked worktree removes or clears projection facts
  instead of preserving stale worktree identity.
- Worktree identity changes request root/activity resync so active/activity
  facts do not go stale.
- `teardownView` removes pane facts from the index and still clears the atom.
- Filesystem envelope projection no longer invokes the all-worktree root
  rebuild path on MainActor. Use an injected index harness/counting seam rather
  than wall-clock timing.
- A delayable index harness proves stale reconcile results are discarded before
  any unregister/register/activity/assertTopology/prune side effect.
- Source write order matches current behavior: unregisters, re-registers,
  registers, activity updates, active-pane update, topology assertion, prune.

### 4. Wire coordinator to the index

Production changes:

- Add `filesystemProjectionIndex` dependency to `PaneCoordinator` initializer,
  defaulting to `FilesystemProjectionIndex()`.
- Replace `workspaceWorktreeContextsById()` use in per-envelope projection
  with actor projection requests.
- Keep `workspaceWorktreeContextsById()` only if needed for temporary source
  sync snapshot construction, then shrink it to raw snapshot extraction with
  no symlink resolution.
- Add generation fields:
  - `filesystemSyncRequestGeneration`
  - `filesystemProjectionRequestGeneration`
  - `paneContextGeneration`
  - `appliedTopologyGeneration`
- Apply stale-result checks before source writes, pruning, atom deltas, or
  bus publishing.
- Include `paneContextGeneration` and `appliedTopologyGeneration` in projection
  requests/results. Recheck both before atom apply and before event-bus publish.
- Preserve current serial source write order first.

### 5. Preserve atom ownership

Update `PaneFilesystemProjectionAtom` only as needed:

- Keep `contextsByPaneId`, `snapshotsByPaneId`, and `nextSequenceByPaneId`
  authoritative.
- Add an apply method for actor-produced deltas if direct field mutation would
  duplicate logic.
- Replace the cwd-only update path with a full context apply helper carrying
  repo id, worktree id, and cwd together; preserve stale snapshot invalidation.
- Keep tests proving `context(for:)` behavior used by existing E2E/tests.
- Do not add AtomLib primitives in this slice.

### 6. Trace field split

Update `AgentStudioPerformanceTraceRecorder` call sites:

- Keep event body `performance.coordinator.write` unless implementation proves
  separate events are cleaner.
- Add low-cardinality `agentstudio.performance.coordinator.phase`.
- Record all relevant timings:
  - `index_elapsed_ms`
  - `mainactor_apply_elapsed_ms`
  - `filesystem_source_elapsed_ms`
  - `total_elapsed_ms`
- Keep existing count fields.
- Ensure trace work remains gated by recorder enabled state where the hot path
  would otherwise allocate/clock unnecessarily.

Update OTLP projection tests for:

- `coordinator.phase` survives.
- timing/count fields survive.
- raw paths/UUIDs still do not survive.

### 7. Focused verification

Run focused tests first:

```bash
source scripts/swift-build-slot.sh debug
swift test --build-path "$SWIFT_BUILD_DIR" --filter "FilesystemProjectionIndexTests|PaneCoordinatorFilesystemSourceTests|AgentStudioOTLPTraceProjectionTests"
```

Then lint:

```bash
mise run lint
```

Then run the changed workload proof if the app builds:

```bash
mise run observability:status
AGENTSTUDIO_PERF_TRACE_BACKEND=both \
AGENTSTUDIO_PERF_DURATION_SECONDS=30 \
scripts/verify-git-refresh-performance-workload.sh
```

Use the workload artifact summary and marker-scoped VictoriaLogs for:

- coordinator records with `phase`
- `mainactor_apply_elapsed_ms`
- `index_elapsed_ms`
- `derived_envelope.count`
- git status counts for separation-of-concerns proof

Preserve JSONL artifact proof separately. If this harness needs changes, update
its script tests in the same slice.

Run the filtered filesystem E2E seam gate:

```bash
SWIFT_TEST_INCLUDE_E2E=1 swift test --build-path "$SWIFT_BUILD_DIR" --filter "E2ESerializedTests.FilesystemSourceE2ETests"
```

Repo default gate before PR-ready claim:

```bash
mise run test
mise run lint
```

`mise run test` excludes E2E by default. If the filtered E2E or workload smoke
is not run, report that layer as skipped/blocked and do not claim the
filesystem runtime seam is fully proven. If resource pressure makes full test
impractical, report focused pass and full test not run; do not claim full done.

## Review Gates

Plan review before code:

- Actor boundary reviewer: check ownership, stale generations, CWD/teardown.
- Proof reviewer: check no wall-clock tests, OTLP field proof, realistic smoke.

Implementation review before PR update:

- Review full diff after focused tests and lint pass.
- Fix accepted P0-P2 findings.
- Re-run affected tests.

## PR Cleanup

Before commit:

- `git status --short`
- ensure no runtime JSONL/log/proof output outside ignored `tmp/`
- no checked-in proof scripts unless they are intentional harness changes

Commit and push:

```bash
git add <scoped files>
git commit -m "Offload filesystem projection indexing"
git push origin performance-issues
```

PR update:

- If GitHub GraphQL is rate-limited, use REST or retry after rate reset.
- Comment with:
  - spec/plan links
  - focused test results
  - lint result
  - Victoria marker/query summary
  - any skipped gates with reason

## Acceptance Criteria

- MainActor no longer performs symlink-resolving all-worktree root rebuilds
  during per-envelope projection.
- Source sync actor hop has stale-result protection.
- CWD changes and pane teardown keep projection caches correct.
- `PaneFilesystemProjectionAtom` remains the first-slice observable owner.
- Victoria/OTLP can distinguish MainActor apply time from index/source/total
  time.
- Focused tests and lint pass.
- No production AgentStudio process is touched.
