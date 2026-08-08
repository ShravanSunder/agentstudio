# Atom DAG and invalidation audit

## Intended graph

```text
RepositoryTopologyAtom
  └─ repos: [Repo] / worktrees: [Worktree]
       └─ RepoExplorerSnapshot + row identities

RepoEnrichmentCacheAtom
  ├─ repoEnrichmentMap[repoID]
  ├─ worktreeEnrichmentMap[worktreeID]
  └─ pullRequestCountMap[worktreeID]
       └─ RepoCacheAtom keyed read surface
            └─ Repo Explorer row facts
```

`AtomEntityMap.value(for:)` is the intended keyed slot read. Its storage and per-slot observation implementation lives in [AtomEntityMap.swift](/Users/shravansunder/Documents/dev/project-dev/agent-studio.slowdonw/Sources/AgentStudio/Infrastructure/AtomLib/AtomEntityMap.swift:33). The architecture explicitly says hot consumers should prefer keyed reads and reserve dictionary snapshots for persistence/cold bridges ([component_architecture.md](/Users/shravansunder/Documents/dev/project-dev/agent-studio.slowdonw/docs/architecture/component_architecture.md:151)).

## Current Repo Explorer reads

The view already uses keyed repo enrichment reads at [RepoExplorerView.swift:124](/Users/shravansunder/Documents/dev/project-dev/agent-studio.slowdonw/Sources/AgentStudio/Features/RepoExplorer/RepoExplorerView.swift:124). It does not remain fully keyed for worktree facts: [RepoExplorerView.swift:155](/Users/shravansunder/Documents/dev/project-dev/agent-studio.slowdonw/Sources/AgentStudio/Features/RepoExplorer/RepoExplorerView.swift:155) calls `repoCache.worktreeFactsSnapshot()`, which snapshots both worktree enrichment and PR-count maps before filtering to visible worktrees. The cache implementation is [RepoCacheAtom.swift:98](/Users/shravansunder/Documents/dev/project-dev/agent-studio.slowdonw/Sources/AgentStudio/Core/State/MainActor/Atoms/RepoCacheAtom.swift:98).

The topology owner is also array-shaped: `RepositoryTopologyAtom.repos` is a single observable array at [RepositoryTopologyAtom.swift:7](/Users/shravansunder/Documents/dev/project-dev/agent-studio.slowdonw/Sources/AgentStudio/Core/State/MainActor/Atoms/RepositoryTopologyAtom.swift:7), and `RepoExplorerView.sidebarRepos` maps the whole array at [RepoExplorerView.swift:109](/Users/shravansunder/Documents/dev/project-dev/agent-studio.slowdonw/Sources/AgentStudio/Features/RepoExplorer/RepoExplorerView.swift:109).

## Assessment

`lead` — the Repo Explorer dependency graph is broader than the intended entity-scoped graph: whole topology array + snapshot-shaped cache facts feed one projection request, and any observation change cancels/restarts the worker. This is a credible explanation for list-diff amplification.

The broader composition audit found two additional amplification candidates:

- tab composition loops every tab and reconstructs complete arrangement state, so request-build work grows with tab count × arrangement composition;
- collapsed-pane accent-color reads can rebuild repo presentations for every repo before selecting one pane, creating a collapsed-bars × repos cross-product.

These are source-backed complexity shapes, not measured production CPU shares yet. Anchors are [WorkspaceTabLayoutDerived.swift](/Users/shravansunder/Documents/dev/project-dev/agent-studio.slowdonw/Sources/AgentStudio/Core/State/MainActor/Atoms/WorkspaceTabLayoutDerived.swift:26), [WorkspaceTabArrangementAtom+Projection.swift](/Users/shravansunder/Documents/dev/project-dev/agent-studio.slowdonw/Sources/AgentStudio/Core/State/MainActor/Atoms/WorkspaceTabArrangementAtom+Projection.swift:115), and [CollapsedPaneBar.swift](/Users/shravansunder/Documents/dev/project-dev/agent-studio.slowdonw/Sources/AgentStudio/Core/Views/Panes/CollapsedPaneBar.swift:95).

`not established` — the broad reads did not by themselves prove that every worktree enrichment mutation invalidates this view; Observation tracking through the `@ObservationIgnored` map field and nested slot objects needs a focused runtime trace or test.

There is a subtle opposite risk: `worktreeFactsSnapshot()` reads unobserved map snapshots and filters afterward. A branch/PR-only mutation may fail to wake the projection observer at all, leaving facts stale until another observed dependency changes. This is a correctness/invalidation gap, not evidence that the snapshot itself is the CPU cause.

`accepted` — the Git CPU hotspot does not require a bad atom DAG: repeated full status work happens before cache/UI mutation and remains expensive when snapshots are equal.

## Fresh atom-tag diagnostic

A focused debug attempt enabled `performance,atoms,app.startup,terminal.startup`
against the isolated 118-repo/163-worktree debug data. Marker
`sidebar-a054ad9d0e85b1739b5ab2b0` produced 11,233 `performance.atom.read`
records and 101 `performance.atom.mutation` records before the strict sidebar
startup gate was interrupted. The read labels were dominated by
`repo_enrichment` (4,651), `pane_graph_canonical` (3,974), and
`worktree_enrichment` (1,331); most reads were keyed `entity_map.value`
operations. Mutations were primarily `worktree_enrichment.set` (46) and
`repo_enrichment.set_noop` (24).

The same marker recorded Repo Explorer request construction at about 6.6 ms
for 118 repos, while MainActor apply samples were about 0.014–0.044 ms. No
`performance.topology.repo_and_worktree` record appeared. The main-thread
sample was predominantly AppKit waiting, so these reads do not prove a
MainActor block or a causal list-diff trigger.

This was not a completed sidebar benchmark: the pre-IPC gate repeatedly
reported a missing `command_exercised` startup record for
`sidebar-performance-proof`; the run exited 130 after more than 11 minutes,
and the script-owned PID 63666 was stopped and verified absent. Treat the
counts as fresh diagnostic evidence, not a pass/fail performance result.

## Smallest proof

Run one current debug/beta workload with atom telemetry enabled and correlate:

1. `entity_map` read operation (`value`, `snapshot`, `membership_keys`) by label;
2. projection trigger and cancellation counts;
3. topology replacement/revision events;
4. native list diff samples;
5. Git status/dedup/event publication in the same time buckets.

Also include tab count, arrangement count, collapsed-bar count, topology replacement count, and projection cancellation count so the cross-product candidates can be ranked against actual workload size.

No product fix should be selected until that correlation distinguishes a broad atom subscription from independent SwiftUI list identity/diff work.
