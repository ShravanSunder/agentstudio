# AtomLib V2 Actor + Metrics Refresh

Date: 2026-06-13
Repo: agent-studio.performance-issues
Stage: refreshed design source for plan-create

## Problem

Agent Studio's slow paths are no longer one single git-sweep problem. Current
`main` already has the git-refresh redesign and a partial repo-cache content
gate, but hot UI surfaces can still observe and rebuild from fleet-sized state:

- `RepoEnrichmentCacheAtom` still exposes whole observable dictionaries.
- Tab bar, sidebar, command bar, pane display, tab display, and persistence still
  read or bridge those dictionaries in hot paths.
- `Derived` and `DerivedSelector` still recompute on every read.
- Some slow interactions are not AtomLib problems at all: sidebar resize, pane
  split resize, and Ghostty geometry sync are layout/runtime lanes.

Spec A remains the right structural direction, but its implementation contract
must be stricter: keep canonical observed state on `MainActor`, move rebuildable
fleet work to actors, and prove user-facing wins through VictoriaMetrics.

## Goals

1. Make observed atom writes conditional, granular, and transaction-shaped.
2. Replace fleet-sized observable dictionaries with per-entity observable slots
   where the UI reads one repo/worktree/pane/session row.
3. Add memoized derived state only where metrics show recompute remains a real
   bottleneck after entity granularity.
4. Preserve the repo's `@MainActor` canonical state model while preventing
   expensive projection/index/search work from living in atoms or derived
   compute.
5. Prove correctness with deterministic Swift tests and prove workload behavior
   with VictoriaMetrics, not JSONL fallback.

## Non-Goals

- Do not move canonical SwiftUI/Observation atoms off `MainActor`.
- Do not make AtomLib a cross-actor state runtime.
- Do not emit generic metrics from every atom read/write.
- Do not solve sidebar resize, pane split resize, or Ghostty geometry storms in
  the first AtomLib row.
- Do not rewrite git/filesystem scheduling. That is the companion refresh lane.

## Ownership Model

### MainActor Atom Ownership

`@MainActor` atoms own canonical UI-observed facts:

- workspace topology, pane graph, tab graph, cursors, scalar UI state
- repo/worktree enrichment cache as the final observable UI cache
- session status facts consumed by views
- aggregate revisions and per-slot registrars
- final application of compact actor results

MainActor atom methods may do small state updates and small read-model assembly.
They must not own fleet-scale path normalization, indexing, search, subprocess
work, disk I/O, or long-running filtering.

### Off-Main Actor Ownership

Actors own rebuildable or external work:

- filesystem event ingestion and batching
- git status scheduling, subprocesses, and admission control
- SQLite connection/repository serialization
- canonical path normalization at fleet scale
- rebuildable search, presence, and projection indexes
- expensive diff/filter passes over repos, worktrees, panes, tabs, or terminal
  surfaces

Actor outputs cross to `MainActor` as `Sendable` snapshots, compact deltas, or
intent structs. Off-main actors must not import SwiftUI/Observation, own atoms,
or access `AtomScope`.

### Store Actor Ownership

Persistence wrappers may observe `MainActor` state and schedule saves, but disk
and SQLite work belongs in store actors. Row 1 may change `RepoCacheStore`
observation to aggregate revisions and snapshots; it must not make
`RepoCacheStore` the repo-cache state owner.

## Actor Placement Gate

Every adoption row must answer this before code changes:

| Question | Required placement |
| --- | --- |
| Is this canonical UI-observed state? | `@MainActor` atom |
| Does it scale with repos/worktrees/panes/tabs? | off-main actor, or measured MainActor exception |
| Does it canonicalize paths? | off-main actor unless proven tiny |
| Does it perform git/filesystem/SQLite/process work? | runtime/store actor |
| Does it assemble a single row from already-observed facts? | MainActor slot/read method is acceptable |
| Does a SwiftUI row need to wake only for one key? | `AtomEntityMap` slot |

If a row needs a measured MainActor exception, the plan must name the surface,
the expected size, and the VictoriaMetrics event that proves it stays within
budget.

## Primitive Contracts

### `AtomValue`

`AtomValue` owns one scalar/content value and fires invalidation only when the
configured equality policy says the value changed.

Required API properties:

- equality is configured at primitive construction, not per write;
- domain/cache payloads require explicit comparators;
- default equality is allowed only through a centrally owned allowlist of trivial
  scalar/value payloads;
- there is no ungated always-fire variant;
- writes require the owning atom's mutation context/token;
- accepted writes mark the active mutation context dirty;
- aggregate revision bumps once when the mutation context commits.

The previous broad `AtomContentEquatable` marker is not sufficient compile-time
safety. If a marker/convenience remains, it must be a narrow allowlist owned by
AtomLib for trivial leaf types. Custom domain structs must use explicit
comparators.

`WorktreeEnrichment` must not use its raw `==` as the cache gate. Its content
comparator remains explicit because `==` and cache-content equivalence are not
the same contract.

### `AtomEntityMap`

`AtomEntityMap<Key, Value>` owns per-key optional observable slots.

Required behavior:

- slot lookup itself is untracked;
- reading an accepted missing key creates a nil slot and subscribes the reader;
- nil-to-value fires that key's slot;
- value-to-nil fires that key's slot;
- topology exit prunes nil slots;
- membership changes use a separate membership revision;
- writes require the owning atom's mutation context/token;
- no public subscript setter;
- compatibility snapshots are read-only migration scaffolding, not a permanent
  API.

The migration proof must be a named hot-surface denylist, not a loose grep.
Row 1 cannot be complete while the named hot files still observe or pass whole
repo-cache dictionaries.

The row-1 cutover must start from a full production-read inventory, not only a
hand-picked hot list. Every production access to
`repoEnrichmentByRepoId`, `worktreeEnrichmentByWorktreeId`, or
`pullRequestCountByWorktreeId` must be classified as one of:

- migrated to a keyed read/facts method;
- moved behind a named snapshot API for persistence or cold bulk work;
- deliberately deferred to a later reviewed plan, with owner and removal gate.

Unclassified production dictionary access is a row-1 blocker. Tests may keep
dictionary assertions while row-1 APIs are being proven, but production code
does not get an implicit compatibility escape hatch.

### Worktree enrichment and PR-count lanes

Row 1 should avoid broad dictionary observation while still avoiding false
dependencies. Worktree enrichment and PR count are separate keyed lanes:

```swift
AtomEntityMap<UUID, WorktreeEnrichment>
AtomEntityMap<UUID, Int> // pull request count
```

Branch-only readers use `worktreeEnrichment(for:)`; PR-only readers use
`pullRequestCount(for:)`. `RepoWorktreeCacheFacts` remains a composed result for
surfaces that genuinely render both branch state and PR count, but it is not the
stored slot that every worktree reader observes.

This is the row-1 answer to the transaction subtlety. Aggregate revisions protect
aggregate-revision consumers; they do not automatically protect direct
multi-slot readers from intermediate invalidations.

### Transactions And Revisions

Each owning atom exposes mutation methods. Internally, a mutation context:

- accepts writes from owned primitives;
- records whether any write actually changed content;
- optionally records a small number of domain metrics;
- bumps the atom aggregate revision once at commit if at least one accepted write
  occurred.

Claims are deliberately narrow:

- aggregate-revision consumers see one revision move per semantic mutation;
- per-slot readers wake only for touched slots;
- multi-source UI readers must consume one owner-built tuple/read model or a
  batched transaction surface.

Tests must include a multi-source reader that would fail if a row sees mixed
facts or wakes through the old whole-dict path.

### `DerivedValue`

`DerivedValue` is a registry-owned memoized read model.

Required behavior:

- stored/lazy instance owned by `AtomRegistry` or an owning atom, not a global;
- explicit input revisions;
- cache hit uses cheap revision comparison;
- recompute happens on read, not write;
- own revision bumps only when recomputed output changes;
- chained deriveds read input `.value` before comparing input `.revision`;
- compute closure cannot access `atom(...)`, `AtomScope`, task-local registry
  state, or helper wrappers that hide those accesses.

Limit:

- lazy pull cuts recompute work and chained recompute work;
- it does not prevent bodies from waking when input revisions fire.

Adoption rule:

- implement and test the primitive, but adopt it into hot UI surfaces only after
  row-1 VictoriaMetrics show derived recompute remains a real bottleneck.

## Row Classification

### Row 1: Repo cache entity granularity

Owner:

- `RepoEnrichmentCacheAtom` stays `@MainActor`.

Change:

- replace whole observable repo/worktree/PR dictionaries with entity maps and
  aggregate revisions;
- expose per-repo and per-worktree slot read methods;
- keep worktree enrichment and PR count as separate keyed lanes, with
  `worktreeFacts(for:)` only as a composed read for surfaces that need both;
- provide snapshot methods for persistence and short-lived migration surfaces;
- remove or fence hot whole-dict observation.

Hot readers that must leave whole-dict observation:

- `TabBarAdapter`
- `RepoExplorerView`
- `RepoCacheStore`
- `CommandBarDataSource`
- `WorkspacePaneDerived`
- `TabDisplayDerived`

### Row 2: Derived memoization

Owner:

- `Infrastructure/AtomLib` owns generic `DerivedValue`;
- `AtomRegistry` owns long-lived derived instances;
- concrete derived structs remain near their current domain owners.

Change:

- add revision-keyed derived cache primitive;
- migrate selected derived surfaces after row-1 reprofile;
- start with the surface metrics identify, likely pane/tab/display read models
  used by command bar or collapsed pane UI.

### Later Rows

Later rows must pass the same actor-placement gate before implementation:

- `SessionRuntimeAtom.statuses`: atom stays `MainActor`; backend runtime protocol
  cleanup is a separate actor-boundary lane.
- `PaneFilesystemProjectionAtom`: final observable facts stay `MainActor`; index
  and canonicalization work stays in `FilesystemProjectionIndex`.
- pane graph, tab graph, topology, and scalar atoms: stay `MainActor`; split only
  rebuildable indexes when metrics justify it.

## Metrics And Proof

### Deterministic Tests

Swift Testing proves primitive semantics:

- comparator acceptance and skip behavior;
- explicit comparator required for domain/cache payloads;
- per-key invalidation isolation;
- nil-then-insert wakeup;
- membership vs value channels;
- aggregate revision batching;
- multi-source tuple behavior;
- derived cache hits and equal-output cutoffs;
- declared-input boundaries;
- compile-negative fixtures;
- lint/boundary ratchets.

No wall-clock sleeps. Use explicit observation counters and bounded event/state
waits.

### VictoriaMetrics Workload Proof

VictoriaMetrics proves user-visible behavior. Use the standard debug runner and
shared local stack:

- `mise run observability:up`
- standard debug observability launcher through existing scripts;
- standard 118 repo / 163 worktree / 14 pane workload where applicable.

JSONL is not an automatic fallback. If Victoria/collector proof is unavailable,
the performance proof is blocked or explicitly skipped with a reason.

Required existing surface events:

- `performance.commandbar.items`
- `performance.commandbar.filter`
- `performance.tabbar.refresh`
- `performance.sidebar.projection`
- `performance.sidebar.row_index`
- `performance.topology.repo_and_worktree`
- `performance.coordinator.write`

Do not require `performance.git.status` subprocess time to improve from Spec A.
Spec A improves MainActor fanout and read-model work, not subprocess latency.

Row-1 performance proof must use the same finalized query/reporting contract for
before and after snapshots. If the existing workload verifier cannot emit the
needed count, p95, or max fields, the proof harness is updated and tested before
the baseline is captured. Baseline and after artifacts must be machine
comparable and stored under a repo-local proof root.

The row-1 success target is at least 2x improvement on targeted fanout surfaces:
either p95 elapsed time reduced by at least 50 percent or event/fanout count
reduced by at least 50 percent under equivalent workload pressure. Targeted
surfaces must include a command-bar interaction proof if the implementation
claims Cmd+P / `#` improvement; a one-time startup command-bar smoke is not
enough for that claim.

### New Metrics Rule

Prefer existing surface events for standard performance comparison. AtomLib may
also expose an opt-in atom diagnostic lane selected only by
`AGENTSTUDIO_TRACE_TAGS=atoms` or `*`.

Allowed atom event names:

- `performance.atom.read`
- `performance.atom.mutation`
- `performance.atom.derived`

Allowed atom fields:

- `agentstudio.performance.atom.kind`
- `agentstudio.performance.atom.operation`
- `agentstudio.performance.atom.accepted_change.count`
- `agentstudio.performance.atom.slot.count`
- `agentstudio.performance.atom.cached_key.count`
- `agentstudio.performance.atom.input_revision.count`
- `agentstudio.performance.atom.cache_hit`

Forbidden:

- dynamic event names;
- atom instance names as metric labels;
- repo/worktree/pane/tab/session ids;
- raw paths;
- payload text;
- per-key labels;
- automatic JSONL proof.

Metric projection must be allowlist-tested for atom telemetry. The OTLP sink
must prove fixed event names and fixed string/numeric/bool fields, and must
reject dynamic path/id/key-shaped attributes. Standard row-1 workload proof must
exclude `atoms` by default so the measured hot path is not perturbed by
high-volume atom tracing; dedicated atom proof runs may enable `atoms`.

## Hot Path Expectations

### Cmd+P And `#`

Expected first lever:

- row-1 entity granularity and hot reader migration.

Expected second lever:

- row-2 derived memoization only if row-1 metrics still show recompute.

Potential later actor lane:

- command-bar search/presence index if `performance.commandbar.items` remains
  fleet-sized after row 1.

### Sidebar Search

Expected first lever:

- row-1 entity granularity. Keystroke debounce already exists.

Potential later actor lane:

- sidebar search/index actor if `performance.sidebar.projection` or
  `performance.sidebar.row_index` remains hot after row 1.

### Sidebar Resize And Pane Split Resize

Not a row-1 AtomLib problem by default. These need a separate trace/review lane
around AppKit layout and Ghostty geometry metrics.

### Pane Minimize / Restore

Mixed path. Row 2 may help collapsed pane labels/colors/context, but layout and
terminal view detach/geometry remain separate proof lanes.

## File Ownership

Expected implementation homes:

- generic primitives: `Sources/AgentStudio/Infrastructure/AtomLib/`
- repo-cache canonical owner: `Sources/AgentStudio/Core/State/MainActor/Atoms/RepoCacheAtom.swift`
- repo-cache persistence bridge: `Sources/AgentStudio/Core/State/MainActor/Persistence/RepoCacheStore.swift`
- command bar hot readers: `Sources/AgentStudio/Features/CommandBar/`
- sidebar hot readers: `Sources/AgentStudio/Features/RepoExplorer/`
- tab bar adapter: `Sources/AgentStudio/App/Panes/TabBar/`
- pane/tab/display deriveds: `Sources/AgentStudio/Core/State/MainActor/Atoms/`
- diagnostics: `Sources/AgentStudio/Infrastructure/Diagnostics/`
- scripts: `scripts/` plus `.mise.toml` task wiring only when needed
- tests: matching `Tests/AgentStudioTests/...` folders

No new generic runtime folder. Keep concrete state owners in their existing
domain homes.

## Security Context

The primitive design is not security-sensitive by itself. The implementation
will touch security-relevant tooling surfaces:

- local scripts;
- OTLP/Victoria metric export;
- filesystem fixture workload scripts;
- subprocess/test helpers.

Those changes must preserve existing scrubbing and local-only observability
rules:

- no raw paths or payload text in OTLP metrics;
- no repo/worktree/pane/session ids as metric labels;
- no new network destination beyond the existing loopback collector;
- no production debug launcher changes outside the standard runner.

## Open Decisions

1. Exact scalar allowlist for default `AtomValue` equality.
   Recommended: start tiny (`Bool`, integer counters, `UUID`, small strings only)
   and require explicit comparators for all domain/cache structs.

2. First row-2 adoption target.
   Recommended: decide after row-1 VictoriaMetrics. Do not pre-choose a large
   derived migration without proof.

3. Command/sidebar search actor lane.
   Recommended: defer until after row 1. If metrics still show fleet-sized
   search/projection cost, write a focused actor-index spec.
