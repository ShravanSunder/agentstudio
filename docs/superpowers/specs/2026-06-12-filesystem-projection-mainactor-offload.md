# Filesystem Projection MainActor Offload

Status: design direction (pre-plan)
Repo: agent-studio
Companion specs:
- `2026-06-11-git-enrichment-refresh-redesign.md`
- `2026-06-11-atomlib-v2-state-primitives.md`

## Problem

Spec B reduced steady-state git refresh pressure, but the debug/Victoria run
still exposes a separate MainActor bottleneck in the filesystem coordinator:

- A startup/watch-folder sync emitted one `performance.coordinator.write` at
  2149.093ms with `registered.count=105`, `activity_write.count=105`, and
  `worktree.count=105`.
- Recurring filesystem projection writes reached 20-60ms with
  `pane.count=17`, `worktree.count=105`, and `derived_envelope.count=0`.
- Terminal geometry was noisy but cheap in the same run
  (`performance.terminal.surface_size` p95 0.019ms,
  `performance.terminal.geometry_sync` p95 0.568ms), so pane resize stutter is
  not explained by Ghostty sizing itself.

The code path matches the trace:

- `PaneCoordinator+FilesystemSource.swift:100-199` computes and applies the
  full filesystem root/activity sync on the MainActor.
- `PaneCoordinator+FilesystemSource.swift:207-218` walks every available repo
  and worktree, calling `worktree.path.standardizedFileURL.resolvingSymlinksInPath()`
  on the MainActor.
- `PaneCoordinator+FilesystemSource.swift:22-46` repeats root lookup for every
  filesystem envelope that needs pane-scoped projection.
- `PaneFilesystemProjectionAtom.swift:55-153` filters pane filesystem and git
  snapshot envelopes on the MainActor.
- `PaneFilesystemProjectionAtom.swift:173-194` and `:221-273` perform fallback
  context creation and canonical path work while isolated to the MainActor.

Spec A will reduce render invalidation and derived recompute fanout after
state changes land. It will not reduce git subprocess cost, path
canonicalization cost, or all-worktree projection work. This spec owns the
actor boundary for filesystem/projection indexing.

## Design Direction

Move fleet-sized filesystem topology normalization and pane projection
filtering into a dedicated actor-owned index. Keep canonical UI state and atom
mutation on the MainActor, but make the MainActor hand over compact snapshots
and receive compact diffs/results.

```
MainActor coordinator
  reads atoms once
  builds Sendable topology/pane snapshots
          |
          v
FilesystemProjectionIndex actor
  normalizes worktree roots
  diffs registered roots/activity
  indexes panes by worktree
  filters filesystem paths against pane cwd
  returns projection intents/deltas
          |
          v
MainActor coordinator / EventBus
  applies small register/activity changes
  publishes derived pane envelopes
  records measured durations
```

The split is deliberately not a new state system. It is a cached projection
index for filesystem runtime routing, owned by the App coordination layer.

## Ownership Boundaries

### MainActor remains owner of canonical state

The following stay MainActor-owned:

- `WorkspaceRepositoryTopologyAtom`
- `WorkspacePaneAtom` / rich `Pane` read model access
- `PaneCoordinator` orchestration fields that mirror what has been registered
  with `FilesystemGitPipeline`
- `PaneFilesystemProjectionAtom` as the observable owner of pane filesystem
  contexts, snapshots, and sequence numbers for this first slice

MainActor is allowed to read these atoms once per sync/request, but not to
perform fleet-sized path canonicalization, per-envelope all-pane filtering, or
all-worktree diff calculation when an actor snapshot can own it.

### `FilesystemProjectionIndex` owns derived runtime indexes

Add an app-coordination actor, tentatively:

`Sources/AgentStudio/App/Coordination/FilesystemProjectionIndex.swift`

It owns only derived, rebuildable runtime state:

- normalized `WorktreeFilesystemContext` by worktree id
- normalized pane projection facts by pane id
- pane ids by worktree id for off-main filtering
- last activity and active-pane worktree facts used to produce source writes
- generation guard for topology/pane snapshots

It must not import SwiftUI or Observation. It must not own atoms. It must not
write disk. It must not run git. It receives value snapshots and returns value
results.

First-slice ownership rule: `PaneFilesystemProjectionAtom` remains the
authoritative owner of observable pane filesystem contexts, snapshots, and
sequence numbers. The new actor may cache normalized facts for filtering and
diffing, but it must return explicit deltas for the MainActor atom to apply.
Do not split ownership of the same snapshot/sequence state between the actor
and the atom. Spec A row 3 remains the future granular-observation migration
surface for `PaneFilesystemProjectionAtom`.

### `FilesystemGitPipeline` remains git/filesystem source owner

Spec B's pipeline shape stays intact:

- `FilesystemActor` owns filesystem ingestion.
- `GitWorkingDirectoryProjector` owns git status admission, concurrency,
  cadence, dedup, retries, and `GIT_OPTIONAL_LOCKS=0`.
- `PaneCoordinator` remains the bridge from MainActor state to the pipeline.

This spec must not move git status scheduling into the new index actor.

## Data Contracts

The plan should introduce small Sendable value types rather than passing rich
atoms or UI models across actor boundaries:

- `FilesystemProjectionTopologySnapshot`
  - generation
  - worktree id
  - repo id
  - raw worktree URL
  - is unavailable
- `FilesystemProjectionPaneSnapshot`
  - pane id
  - content type
  - repo id
  - worktree id
  - cwd URL
- `FilesystemProjectionPaneUpdate`
  - request generation
  - pane id
  - update kind: upsert/remove
  - repo id, worktree id, cwd URL when upserting
- `FilesystemSourceSyncDiff`
  - request generation
  - register contexts
  - unregister worktree ids
  - activity updates
  - active pane worktree update
  - valid pane ids and valid worktree ids for pruning
- `PaneFilesystemProjectionResult`
  - request generation
  - projection intents: filtered path changes, git summary deltas, and context
    upsert/remove facts
  - pane snapshot/context deltas for `PaneFilesystemProjectionAtom`
  - counts for tracing

URLs may cross the actor boundary as values, but canonical path work belongs
inside the index actor. When possible, the index should store canonical path
strings for filtering and only return URLs where existing APIs require them.

## Execution Model

### Root/activity sync

Current behavior:

```
MainActor:
  read topology atom
  normalize all worktree paths
  compute activity by scanning panes
  diff registered/desired contexts
  call filesystemSource register/unregister/activity one by one
  assert topology
  prune projection store
```

Target behavior:

```
MainActor:
  bump a sync request generation
  read topology + pane facts into value snapshots
  await index.reconcile(topology, panes, activePane)
  discard/retry if a newer sync request exists
  apply returned source writes in priority order
  assert topology with normalized contexts returned by index
  prune MainActor observable state only if needed
```

The await point is intentional: the expensive normalization/diff work yields
the MainActor. The returned mutation phase should be small and measured.
Every returned sync diff must echo its request generation. The coordinator
must not apply register/unregister/activity/prune results from a stale
generation; it should rerun the existing convergence loop instead.

### Pane lifecycle and CWD updates

Current behavior updates projection state immediately when a surface CWD change
arrives: `PaneCoordinator.updatePaneCWDAndResolvedContext` updates pane state
and calls `PaneFilesystemProjectionAtom.updatePaneCwd`. Source sync is not the
only ingress, so the actor cache must also have an incremental update path.

Target behavior:

```
MainActor:
  update pane atom + existing projection atom
  bump pane-context generation
  await index.applyPaneUpdate(upsert/remove pane snapshot)
```

The actor update is derived-cache maintenance only. The existing MainActor
atom remains authoritative for observable context/snapshot/sequence state.
Pane teardown must call the remove path. CWD changes must invalidate cached
filtered state exactly as today's atom clears stale snapshots.

### Per-envelope projection

Current behavior:

```
MainActor:
  for filesystem event, rebuild worktree roots
  read all panes
  filter panes/paths
  update pane snapshots
  publish derived envelopes
```

Target behavior:

```
MainActor:
  assign a projection request generation
  pass relevant envelope to index
  await projection result
  discard stale projection result if pane/topology generation moved
  apply projection intents through PaneFilesystemProjectionAtom
  publish derived envelopes if any
  apply observable snapshot updates through PaneFilesystemProjectionAtom
  only when output changed
```

The common no-op case from the Victoria run (`derived_envelope.count=0`) must
avoid all-worktree root rebuilding and all-pane filtering on the MainActor.
The stale-result guard is required because moving projection behind an actor
adds an async hop that the current synchronous `consume` path does not have.
The actor must not fabricate `RuntimeEnvelope` sequence numbers. Envelope
creation remains MainActor-side through the atom-owned sequence state.

## Relationship To Spec A

This spec and Spec A are separate layers:

- This spec reduces MainActor work before/while state changes are prepared.
- Spec A reduces observation invalidation and derived recomputation after state
  changes land.

They compose, but neither replaces the other. Implementing Spec A first would
not remove the 105-worktree path normalization spike or `git status` cost.
Implementing this spec first does not solve fleet-sized observable dictionary
fanout.

This spec does not supersede Spec A row 3. If a later design moves
`PaneFilesystemProjectionAtom` snapshot/sequence ownership fully into an actor,
that must explicitly amend Spec A so there is one state owner.

## Relationship To Spec B

This spec is Spec B-adjacent and should be planned as either a follow-up slice
or a late amendment to the current performance PR:

- It does not change the git refresh cadence, admission budget, or status
  provider contract.
- It should preserve current Spec B trace fields and add attribution where
  needed, such as `agentstudio.performance.coordinator.phase`.
- It should improve the workload gates where adding a watch folder and
  resizing/toggling panes occur after the repo fleet is present.

## Observability Contract

Keep the production-safe tracing rules:

- Stable builds remain no-op unless explicit trace tags are set.
- Debug/beta observability uses the existing OTLP/Victoria stack and marker.
- No raw paths, UUIDs, prompts, payloads, errors, or tool output over OTLP.
- JSONL may remain as local debug fallback, but PR proof should use
  marker-scoped VictoriaLogs when the stack is healthy.

Required new or normalized fields:

- `agentstudio.performance.coordinator.phase`
  - `source_sync`
  - `filesystem_projection`
  - `git_snapshot_projection`
- `agentstudio.performance.coordinator.mainactor_apply_elapsed_ms`
- `agentstudio.performance.coordinator.filesystem_source_elapsed_ms`
- `agentstudio.performance.coordinator.worktree.count`
- `agentstudio.performance.coordinator.pane.count`
- `agentstudio.performance.coordinator.derived_envelope.count`
- `agentstudio.performance.coordinator.registered.count`
- `agentstudio.performance.coordinator.activity_write.count`
- `agentstudio.performance.coordinator.index_elapsed_ms`
- `agentstudio.performance.coordinator.total_elapsed_ms`

The `phase` field is a low-cardinality string and safe for Victoria.
Acceptance queries must gate on `mainactor_apply_elapsed_ms` or a dedicated
apply event, not on total elapsed time. Total time may still include actor
index work and awaits into `FilesystemGitPipeline`; the purpose of this spec is
to make MainActor occupancy separately provable.

## Test Strategy

Use Swift Testing only. No wall-clock sleeps. No new `#if DEBUG` hooks.

Unit tests:

- Index reconciliation normalizes/diffs topology off MainActor and returns
  deterministic register/unregister/activity operations.
- Reconciliation is idempotent: identical snapshots produce no source writes
  and no topology assertion churn beyond the expected generation contract.
- Stale reconciliation results are discarded or rerun when a newer sync request
  exists before apply.
- Active worktree and pane activity priority are preserved.
- Incremental CWD updates update the actor cache and preserve current
  `PaneFilesystemProjectionAtom.updatePaneCwd` invalidation behavior.
- Pane teardown removes the actor's pane projection facts.
- Per-envelope projection filters changed paths by pane cwd and worktree root.
- No-op filesystem changes return zero derived envelopes without requiring an
  all-worktree root rebuild on the MainActor-facing path.
- Stale projection results are discarded when pane/topology generation moves
  during the actor await.
- Git snapshot projection updates per-pane summary state and sequence numbers.
- Prune removes stale pane/worktree state.

Integration tests:

- `PaneCoordinator` sync delegates to the index actor and applies returned
  writes in the same observable order as current behavior.
- Filesystem envelope handling does not call the legacy
  `workspaceWorktreeContextsById()` path for per-envelope projection.
- Trace attributes include phase and counts, with sensitive fields scrubbed
  from OTLP projection tests.
- OTLP projection tests prove `coordinator.phase`, apply/index/source/total
  timing fields, and count fields survive into Victoria-safe output.
- Filtered E2E lane runs `E2ESerializedTests.FilesystemSourceE2ETests` because
  this slice changes the coordinator/filesystem runtime seam.

Smoke/proof gates:

- Launch debug/beta observability by PID/marker, never the user's production
  AgentStudio.
- Preserve the PID-scoped JSONL artifact even when the collector is healthy;
  Victoria is the primary aggregate proof, not the only proof. The existing
  `scripts/verify-git-refresh-performance-workload.sh` satisfies this contract
  when `AGENTSTUDIO_PERF_TRACE_BACKEND=both`; otherwise add a dedicated helper
  with the same isolated-data, JSONL, marker-scoped Victoria, and script-test
  guarantees before claiming the proof gate.
- Use an existing automated workload surface for the first slice:
  - run the git refresh performance workload with reduced duration/repo counts
    for local iteration and production-scale counts for PR proof when resource
    pressure allows,
  - run startup command-bar repo filter smoke through that harness,
  - collect marker-scoped coordinator/git/command-bar events.
- Manual sidebar resize, pane minimize/restore, and pane split/resize may be
  used as exploratory evidence, but are not first-slice required gates until a
  PID-targeted event-based automation harness exists for them.
- Query VictoriaLogs by marker and compare against the current baseline:
  - startup/watch-folder source sync should move the 2149ms cost out of
    `mainactor_apply_elapsed_ms`; off-actor `index_elapsed_ms` may still show
    the indexing cost.
  - recurring projection writes with `derived_envelope.count=0` should not
    show 20-60ms `mainactor_apply_elapsed_ms`.
  - `performance.git.status` p95 may remain dominated by subprocess latency;
    that is Spec B/provider territory, not this spec's success condition.
- If the collector is unhealthy, report OTLP/Victoria proof as skipped/blocked
  and keep JSONL-only proof separate; do not treat fallback JSONL as passing
  the Victoria gate.

## Implementation Boundaries

Preferred file placement:

- `Sources/AgentStudio/App/Coordination/FilesystemProjectionIndex.swift`
  - actor and value DTOs
- `Sources/AgentStudio/App/Coordination/PaneCoordinator+FilesystemSource.swift`
  - snapshot construction and applying returned diffs/results
- `Sources/AgentStudio/Core/State/MainActor/Atoms/PaneFilesystemProjectionAtom.swift`
  - remain the observable owner of contexts/snapshots/sequences for this slice;
    expose small mutation helpers if needed so actor results apply without
    duplicating ownership
- `Tests/AgentStudioTests/App/Coordination/FilesystemProjectionIndexTests.swift`
  - actor unit tests
- `Tests/AgentStudioTests/App/Coordination/PaneCoordinatorFilesystemSourceTests.swift`
  - coordinator integration tests
- `Tests/AgentStudioTests/Infrastructure/Diagnostics/*`
  - trace projection tests for new low-cardinality fields

Do not put this under `Infrastructure/AtomLib`: the index is app coordination,
not a generic atom primitive. Do not put it under `Core/State/MainActor`: the
point is to remove fleet-sized runtime projection work from that boundary.

## Open Questions

1. Should source sync apply register/activity calls serially or allow bounded
   parallel awaits into `FilesystemGitPipeline`? Recommendation: keep the
   current serial order in the first slice; measure before introducing another
   concurrency policy.
2. Should the index actor own path canonicalization caches with invalidation by
   raw URL string, or simply normalize during reconciliation? Recommendation:
   cache inside the actor because root URLs are stable and the watch-folder
   spike is exactly repeated canonicalization at fleet size.
3. Should coordinator timing use one event with separate timing fields or
   separate index/apply/source events? Recommendation: start with one
   low-cardinality event plus explicit fields so existing Victoria queries stay
   simple, but the plan may split events if tests show the recorder shape is
   cleaner.

## Non-Goals

- No changes to git status provider behavior.
- No changes to Spec A AtomLib primitives.
- No new production debug hooks.
- No production dependency on Victoria.
- No broad UI redesign.
- No direct interaction with the user's running production AgentStudio.
