# Demand Admission Regression — Program Design

Requirements: [requirements.md](requirements.md)
Specification: [specification.md](specification.md)

## Integrated Design

The repair keeps the existing domain owners and moves every reduction gate in front of the boundary it is intended to protect. Repo Explorer becomes demand- and key-scoped before it captures. Terminal keeps raw callback contraction in its existing source owners and publishes one deferred latest pane-status fact. Forge keeps request execution private and publishes one current repository presentation projection. `EagerDerivedAtom` becomes true one-active/one-pending execution rather than overlapping cooperative cancellation.

```text
Ghostty callback
  -> GhosttyActionDisposition                       existing source owner
  -> TerminalLocalActionAccumulator / projector    fixed-key contraction
  -> PaneActivityStatusAtom                        keyed latest fact + deferred latest
                                                     |
RepositoryTopologyAtom -- materialized keys --------+ 
RepoCacheAtom ---------- keyed Git/PR facts --------+--> RepoExplorerProjectionAdapter
workspace focus/recency - keyed demanded facts -----+      demand + invalidation owner
                                                            |
                                                            | admitted immutable full/delta request
                                                            v
                                                   EagerDerivedAtomFamily
                                                   one active + one latest pending
                                                            |
                                                            v
                                                   RepoExplorerProjectionWorker
                                                   off-main full/delta projection
                                                            |
                                                            v
                                                   complete rendered equality
                                                   generation/currentness validation
                                                            |
                                                            v
                                                   one compact MainActor read-model binding
                                                            |
                                                            v
                                                   RepoExplorerTableMaterializer
                                                   native visible-row reuse +
                                                   viewport-scoped demand

App RepoExplorerCommandPresentationBatch
  -> visible-worktree generation + favorite/capability/request projection
  -> generation-validated presentation delta
  -> current represented row slots + Repo Explorer toolbar
  -> command execution re-enters AppCommandDispatcher

Forge provider task
  -> validate origin/generation/live scope before state mutation
  -> current PullRequestRepositoryProjection
  -> repository-keyed latest-state coalescing
  -> one atomic MainActor cache apply
  -> relevant Repo Explorer repository invalidation
```

The design adds no service, persistence, compatibility path, feature flag, or general admission framework.

## Current System And Constraint Degree

The system is legacy-ownership-bound, not greenfield:

- The repaired branch already moves observation, capture admission, deadlines, and publication ownership into `RepoExplorerProjectionAdapter`; paired profiling places adapter capture at about 4.6% of Main Thread CPU and the off-main worker at about 2.6% of total CPU.
- [`RepoExplorerView`](../../../Sources/AgentStudio/Features/RepoExplorer/RepoExplorerView.swift) still feeds the complete `rowIndex.entries` collection through SwiftUI `List` and `ForEach`. The paired source/Time Profiler evidence retained by the investigation places about 35.5% of Main Thread CPU in `OutlineListCoordinator`, 20.4% in hosting layout/render, 7.4% in repeated list-entry identity work, and 5.4% in focus-loop rebuilding.
- [`RepoExplorerVisibleRowsBridge`](../../../Sources/AgentStudio/Features/RepoExplorer/RepoExplorerView+VisibleRows.swift) discovers SwiftUI's backing `NSTableView` after materialization and reports its visible row range. It cannot prevent the earlier whole-list identity/diff/layout/focus work and makes viewport demand depend on an implementation detail it does not own.
- [`RepoExplorerListEntry.id`](../../../Sources/AgentStudio/Features/RepoExplorer/Models/RepoExplorerListEntry.swift) constructs interpolated strings on repeated framework reads instead of carrying a stored typed identity produced off-main.
- `RepoExplorerProjectionAdapter` and `EagerDerivedAtomFamily` now own materialized projection state with one-active/one-pending execution; the remaining dominant cost is downstream UI materialization, not the projection worker.
- `TerminalLocalActionAccumulator` and `TerminalActivityProjector` already own bounded raw-signal contraction; `PaneActivityStatusAtom` is the keyed MainActor read owner but discards changed values inside its interval.
- `ForgeActor` already owns demand, freshness, backoff, origin/generation validation, one active provider task, and one pending follow-up. `v0.0.90` exposes its loading edges as separate events and mutates success/publication baselines before final scope validation.
- `RepositoryTopologyAtom` already owns stable-key indexes, but `RepoPresentationItem.init(repo:)` recomputes path-derived keys during hot capture.
- OTLP projection and taxonomy allowlisting are authoritative and remain source-scrubbed.

The AppKit/SwiftUI architecture recommends SwiftUI for dynamic lists as the ordinary implementation default, while explicitly supporting persistent `NSHostingView` instances for custom cells. The measured Repo Explorer path is the justified exception: the generic SwiftUI outline coordinator is the dominant remaining CPU owner, and the selected table retains the existing SwiftUI row components inside reused native cells rather than replacing their product presentation. This exception is feature-local and does not change the repository-wide UI default.

Changed behavior is limited to admission, state-transition order, capture shape, execution overlap, UI materialization ownership, viewport-demand publication, and proof. Existing feature presentation, commands, focus behavior, accessibility, scrolling, and domain authority remain authoritative.

## Structural Crux And Alternatives

The crux is where a source change becomes a consumer-relevant semantic invalidation.

| Alternative | Shape | Gain | Cost / failure | Decision |
| --- | --- | --- | --- | --- |
| Downstream suppression only | Keep broad observation and full capture; improve worker equality/debounce | Small edit | Still pays MainActor capture and filesystem work; cannot meet S2-S4 | Rejected |
| Producer-formatted sidebar rows | Terminal, Core, and Forge produce Repo Explorer row models | Early contraction | Moves consumer policy into sibling/domain owners and creates cross-feature coupling | Rejected |
| Consumer-owned keyed admission over existing domain facts | Domain owners publish compact facts; Repo Explorer observes only demanded keys and emits full/delta invalidations | Preserves ownership, removes work before capture, supports exact proof | More observation bookkeeping and explicit invalidation vocabulary | Selected |
| Keep SwiftUI `List` and tune IDs/focus/animations | Store row IDs, suppress avoidable focus work, and disable unnecessary animation while retaining generic outline materialization | Smallest code change; preserves current native behavior automatically | Cannot remove the measured whole-list `OutlineListCoordinator` and hosting-layout floor; the required action-CPU reduction exceeds the optimizable app-owned share | Rejected as the primary correction; stored IDs remain required hygiene |
| SwiftUI `ScrollView` + `LazyVStack` | Materialize only lazy visible/near-visible rows and publish viewport demand from row lifecycle | Small implementation surface; removes `OutlineListCoordinator` | Must recreate native table accessibility, focus/key-loop behavior, exact viewport demand, scroll anchoring, and sidebar row behavior; lazy retention makes visible demand approximate | Rejected for the first cut because UX preservation is P0 |
| Feature-owned view-based `NSTableView` | Consume immutable rows through a direct table data source, reuse hosted visible cells, apply precomputed update scope, and own the exact visible range | Removes generic outline diffing while preserving native scrolling, focus, accessibility, row reuse, and exact viewport demand | Larger feature-local AppKit boundary and cell lifecycle to maintain | Selected for UI materialization |
| New generic derived-state scheduler | Central admission/deadline/control service | Uniform mechanics | New authority/control plane, broad migration, and scope beyond the confirmed goal | Rejected |

The selected direction spends complexity in two feature-owned boundaries: the existing projection adapter bears key-observation/capture policy, and the table materializer bears visible-row lifecycle and native presentation. Domain owners continue to bear semantic equality and currentness. No generic UI framework is introduced. Revisit `LazyVStack` only if the direct table cannot preserve measured action performance or existing SwiftUI row composition without excessive hosting churn; revisit a broader scheduler only if at least three unrelated consumers require the identical invalidation/deadline semantics and the local owners cannot share the existing primitives without duplicating policy.

## Components, Ownership, And Interfaces

```text
Repo Explorer feature
  RepoExplorerProjectionAdapter
    owns: demand, keyed invalidation, capture admission, current publication
    consumed by: RepoExplorerView
    changes when: source-to-projection admission/currentness policy changes

  RepoExplorerProjectionWorker
    owns: off-main grouping, row content, stored row identity/index, native update plan
    consumed by: adapter and table materializer through immutable result
    changes when: derived sidebar meaning or off-main update planning changes

  RepoExplorerView
    owns: SwiftUI shell composition, filter/toolbar, empty/content selection
    consumed by: SidebarSurfaceHost
    changes when: product composition or interaction wiring changes

  RepoExplorerTableMaterializer
    owns: native table membership application, visible cell reuse, viewport demand
    consumed by: RepoExplorerView and visible-worktree demand callback
    changes when: native materialization, scrolling, focus, or viewport policy changes

  RepoExplorerTableRowCell
    owns: one reusable native cell and persistent SwiftUI row-content slot
    consumed by: table materializer
    changes when: cell reuse/binding or row-host integration changes

App composition
  RepoExplorerCommandPresentationBatch
    owns: visible-worktree capability/favorite/request projection and generation
    consumed by: Repo Explorer toolbar and table materializer through an injected value
    changes when: App-owned command-presentation composition changes
```

Projection truth remains in the adapter/worker result. Native rows are consumers, not a second model. The component split exists because projection policy, shell composition, native viewport lifecycle, and reusable row hosting have different reasons to change and different proof boundaries.

### RepoExplorerProjectionAdapter — demand, invalidation, and binding owner

`RepoExplorerProjectionAdapter` expands its existing role and removes observation lifecycle from `RepoExplorerView`.

It owns:

- current surface demand and grouping mode;
- observation generation and exact observed repository/worktree/pane/tab keys;
- one bounded `RepoExplorerPendingInvalidation` accumulator;
- earliest demanded recency deadline;
- capture admission and current request generation;
- final validated materialized result.

It exposes:

```text
start(demandSource, factSources)
updateDemand(surface, grouping, renderedKeys)
invalidate(scope, cause)
stop()
publishedResult
```

`invalidate` is idempotent and MainActor-fast. It unions affected keys, promotes to membership/full only when a structural input requires it, and schedules at most one capture turn. It does not build a request. If demand is absent, it retains no hot observation registrations and at most one demand-recheck invalidation; the current materialized result remains available for cache-first surface switching.

`RepoExplorerView` becomes a render/interaction consumer of `publishedResult`; it does not own polling, projection execution, or broad observation.

#### Grouping and visibility observation matrix

Membership is the bootstrap authority; rendered keys refine an already established demand set and are never required to obtain the first projection.

| Source fact family | By Repository | By Pane | By Tab | Invalidation scope |
| --- | --- | --- | --- | --- |
| sidebar surface visibility | enter: full bootstrap; leave: unregister hot facts | same | same | demand enter/leave |
| repository/worktree membership and grouping identity | observe | observe | observe | membership/full |
| repository favorite/enrichment and worktree Git/PR/loading facts | observe relevant repository/worktree keys | observe keys represented by pane rows | observe keys represented by tab pane rows | repository/worktree delta; membership/full only when grouping identity changes |
| pane-to-worktree placement and tab membership | observe because repo rows, placement, and menus consume it | observe | observe | affected worktree/repository or membership/full when placement membership changes |
| pane title, note, drawer, activity message, recency, and real-attention focus | do not observe | observe demanded pane keys | observe demanded pane keys | pane delta |
| tab display/group facts | do not observe | do not observe | observe demanded tab keys | tab delta |
| Bridge attendance/capability facts | observe only the exact repository/worktree command-presentation keys declared by the rendered row/menu model | observe exact pane-row keys when rendered | observe exact pane-row keys when rendered | affected command/row key; never implicit full capture |
| grouping, sort, search, collapsed-group inputs | observe | observe | observe | grouping/membership full, or presentation-only delta when structure is unchanged |

On first mount, hidden-to-visible transition, grouping change, or materialized-baseline loss, the adapter reads topology membership IDs and performs one demanded full capture. After publication it registers exact rendered repository/worktree/pane/tab keys for that grouping. While hidden it unregisters every hot fact observer and cancels the recency deadline; a later visible transition always bootstraps from current membership rather than trusting cached rendered keys.

### RepoExplorerPendingInvalidation — bounded consumer scope

This is a feature-private value, not a generic framework or state service:

```text
none
affected repositories: Set<RepoID>
affected worktrees: Set<WorktreeID>
affected panes: Set<PaneID>
affected tabs: Set<TabID>
membership/full
```

Unions preserve required scope. Membership/full subsumes narrower keys. The sets are bounded by current demanded topology; loss of demand clears irrelevant keys. Cause is a bounded diagnostic enum and does not affect equality or authority.

### RepoExplorer capture — full and delta values

The adapter captures one of two immutable `Sendable` values:

- `RepoExplorerFullProjectionRequest` for grouping/query/sort/membership changes;
- `RepoExplorerProjectionDelta` for changed repository, worktree, pane, tab, loading, focus, or recency keys.

The executable work value is closed and self-contained:

```text
RepoExplorerProjectionWork
  full(targetGeneration, completeCapture)
  delta(
    baselineRevision,
    immutableBaselineResult,
    targetGeneration,
    latestFactsByAffectedKey,
    affectedScope
  )
```

The baseline is the adapter's last published immutable result and revision captured on MainActor. The worker reads no mutable UI state. Delta merge is owned by `RepoExplorerProjectionAdapter`: equal baseline revisions union affected scope and retain the newest fact per key; a structural invalidation, different baseline, removal that changes membership, or unsupported combination promotes the pending work to a demanded full capture. Worker completion returns one complete result derived from that baseline. Publication requires both the baseline revision and target generation to remain current; mismatch records `stale_baseline` and re-arms one full invalidation.

Full capture reads only current demanded keys. Delta capture reads only accumulated affected keys. Both consume already-materialized stable keys and domain facts. Neither invokes `StableKey.fromPath`, filesystem APIs, Git, SQLite, process, or network work.

`RepositoryTopologyAtom` remains the stable-identity read owner, but it never produces identity by touching a path. Topology admission carries explicit immutable repository/worktree stable-key facts alongside the admitted models. Persistence hydration supplies the existing stored stable keys; filesystem/runtime discovery canonicalizes and hashes paths before crossing to MainActor. `RepositoryTopologyReplacement` validates the supplied identity maps against model IDs, and the atom stores both `stable key -> ID` and `ID -> stable key` indexes from those facts. `RepoPresentationItem` receives the stored value explicitly. No persistence schema changes, and `StableKey.fromPath` is forbidden in hot capture and MainActor topology-index rebuild.

### EagerDerivedAtom and EagerDerivedAtomFamily — execution owner

Each materialized key owns exactly:

```text
current value
active request/task?       at most one
latest pending request?    at most one
revision / readiness / revocation epoch
```

Admission while idle starts execution. Admission while active replaces the pending request after merging any owner-required scope; it does not start another task. Cancellation requests cooperative stop, but the pending successor begins only after predecessor termination is observed. Completion validates request identity and revocation epoch, then yields `published`, `equal`, `failed`, `cancelled`, or `superseded`; afterward it starts the latest pending request if still demanded.

Each admission increments a per-key accepted generation immediately. Active work retains the generation it began with. Accepting any newer pending request therefore revokes active publication even while cooperative cancellation is still settling: the older completion is always `superseded` and cannot bind. `EagerDerivedAtom` receives an owner-supplied pending-request combiner. Repo Explorer's combiner delegates to the adapter's baseline/scope rule above; Tab Bar requests are complete snapshots and use latest complete replacement with no scope union. The combiner cannot inspect mutable owner state or perform effects.

This hard-cuts the prior overlap semantics for both Repo Explorer and Tab Bar. Tab Bar retains its per-tab keys and changed-only collection publication; its existing semantics require explicit regression proof because it shares the primitive.

### RepoExplorerProjectionWorker — off-main structural derivation

The worker retains grouping, branch/status merging, row construction, row indexing, cancellation checkpoints, and reference projection. It accepts full or delta input. Delta application returns a complete immutable result while preserving unchanged row values and stable IDs.

Rendered equality has one source: the complete immutable rendered row model consumed by the view. The parallel incomplete `RepoExplorerRenderedRowContent` comparator is removed. Equality includes every visible field in the current grouping. An equal completion therefore proves R-INV against the same values the view renders.

The worker also prepares the materialization input consumed after publication:

```text
RepoExplorerMaterializationSnapshot
  generation + revision + membership fingerprint
  rows: [RepoExplorerMaterializedRow]
    stored RepoExplorerRowID
    immutable row presentation
    bounded content revision
    stable row layout class + fixed AppStyles metric inputs
    optional represented worktree ID
  rowIndexByID
  rowIDsByWorktreeID + rowIDsByRepoID
  RepoExplorerNativeUpdatePlan
```

`RepoExplorerRowID` is a stored typed identity assembled from existing section/group/repository/worktree/pane identities. It does not interpolate UUID strings during MainActor or framework identity reads. The worker computes row identities, ordering, stable layout classes, fixed metric inputs, row-index maps, repo/worktree occurrence indexes, content revisions, and the complete native update plan off-main. MainActor does not compare, hash, sort, or diff the row fleet. Width-dependent text measurement is deliberately excluded from the worker and is bounded to represented visible rows by the table owner below.

### RepoExplorerNativeUpdatePlan — exact native transaction

The worker emits one closed discriminated value; the planner does not choose diff or index semantics:

```text
equal(oldRevision == newRevision, count, membershipFingerprint)

content(
  oldRevision, newRevision, unchangedCount, membershipFingerprint,
  reloadRowsInNewSpace, heightReloadRowsInNewSpace
)

membership(
  oldRevision, newRevision, oldCount, newCount,
  oldMembershipFingerprint, newMembershipFingerprint,
  removeRowsInOldSpace,
  insertRowsInNewSpace,
  movesFromOldToNewSpace: [(rowID, oldIndex, newIndex)],
  reloadRowsInNewSpace,
  heightReloadRowsInNewSpace
)
```

The plan's private off-main constructor validates bounds, unique row IDs, disjoint remove/insert/move participation, move identity, and that applying the simultaneous old-space removals, new-space insertions, and old-to-new survivor moves produces the exact new ordered membership and fingerprint. Reload and height-reload indexes always address the final new snapshot. The value is immutable and cannot be constructed without that validation.

MainActor preflight is O(1): the plan's old revision/count/fingerprint must equal the accepted snapshot, its new revision/count/fingerprint must equal the candidate snapshot, and its generation must still be current. A stale generation or superseded revision is rejected before AppKit and requests one current replacement plan. A structurally malformed current plan is an internal invariant failure and terminates before entering AppKit; it is not converted into a broad reload.

For `content`, the candidate snapshot becomes the data-source snapshot, represented visible rows in `reloadRowsInNewSpace` are reloaded, represented visible wrapping rows in `heightReloadRowsInNewSpace` are height-invalidated, and the candidate becomes accepted only after both calls return. For `membership`, the host captures scroll/focus/accessibility anchors, exposes the candidate snapshot to the data source, then performs one `beginUpdates`/`endUpdates` transaction: remove the old-space index set, insert the new-space index set, and issue the prevalidated old-to-new moves in ascending destination-index order; after `endUpdates`, it applies final-new-space content and height reloads, restores anchors by row ID, and only then advances the accepted revision/generation and viewport publication. Interaction and viewport callbacks are generation-gated while the candidate is in flight.

No ordinary update calls broad `reloadData`. Initial empty-to-current installation may use the same insertion transaction only after a cell-free pilot proves the API boundary. Objective-C/AppKit consistency exceptions are fatal process conditions, not recoverable Swift returns; correctness is provided by the off-main plan constructor, O(1) preflight, deterministic transaction proof, and the pilot. Before hosted cells or command integration depend on this boundary, the pilot runs the real 150/180/12/36 membership plans with a fixed visible-row count and then doubles offscreen rows. It falsifies the table design if app-owned fleet iteration appears, native membership MainActor p95 exceeds the `AppPolicies` four-millisecond bound, or p95 grows by more than twenty percent when only offscreen membership doubles. A falsifier returns to Program Design rather than permitting `reloadData` or a MainActor diff.

### RepoExplorerTableMaterializer — native visible-row and viewport owner

The materializer replaces the SwiftUI `List`/`ForEach` container and the table-discovery bridge with one feature-owned view-based `NSTableView` boundary hosted by `RepoExplorerView`.

It owns:

- the current immutable `RepoExplorerMaterializationSnapshot` reference;
- native table data source/delegate lifecycle and one sidebar-styled column;
- visible-cell creation, reuse, stable/fixed row geometry, visible wrapping-row measurement, and content-slot binding;
- application of replacement-membership or affected-row update scope;
- the exact visible row range and visible-worktree demand publication;
- scroll-bound sampling used by bounded performance telemetry.

It does not own projection, row meaning, grouping, search, collapse policy, commands, favorite state, focus decisions, or domain facts. Those values arrive in the immutable materialized row or stable injected interaction callbacks.

The materializer receives one stable `RepoExplorerTableInteractions` value when the host is created. It routes typed row identity plus typed action to the existing command/focus/favorite/collapse owners. Cells create action closures only for represented visible rows; no fleet of closures is constructed or retained in the snapshot. Every callback carries the accepted table generation, row ID, and cell reuse token and is ignored unless all three remain current, so reuse cannot turn the table into a second command or selection owner.

Behavioral interface:

```text
apply(snapshot)
  precondition: snapshot generation is the adapter's current published generation
  membership: execute RepoExplorerNativeUpdatePlan.membership exactly
  content: execute RepoExplorerNativeUpdatePlan.content exactly
  equal: no native table, layout, focus, accessibility, or viewport invalidation
  stale generation: reject without changing cells or viewport demand

visibleWorktreeIDs
  exact set represented by the table's current visible row range
  equality-published at most once per coalesced viewport turn
  cleared when the host leaves the window or sidebar demand is absent
```

Native membership application may ask the data source for its O(1) row count, O(1) indexed row facts, stable layout class, fixed metric, and visible cells, but row identity/order, content comparison, membership diff, and index lookup are already materialized. It must not invoke SwiftUI outline diffing, measure every SwiftUI row, or walk projection owners. The transaction creates or rebinds only AppKit-requested represented cells. The scroll anchor is the first fully visible row ID plus its clip-relative offset; focus and accessibility anchors are current row IDs and subcontrol identities. A surviving anchor is restored at the same offset/target. When an anchored row is removed, the plan's prevalidated nearest surviving successor, then predecessor, is used; absence clears only that anchor and follows existing refocus behavior.

### Width-dependent row height — visible-bounded measurement

The worker assigns a stable `RepoExplorerRowLayoutClass`: section header, loading header, loading row, group header, worktree row, pane row, or fault row, plus whether its declared text fields may wrap. Fixed classes use immutable `AppStyles` metrics carried in the snapshot. They never enter SwiftUI measurement. Wrapping classes carry minimum/fallback metrics and a bounded line policy, not a universal precomputed height.

The table's owned clip-view width is the sole width authority. It normalizes width to the current backing-pixel value, distinct-suppresses equal widths, and coalesces a resize burst to one latest width revision per MainActor turn under `AppPolicies.SidebarProjection`. On a new width or newly represented wrapping row, only represented visible wrapping cells are measured. Results are feature-local ephemeral values keyed by `(rowID, contentRevision, widthRevision)`; changed heights are applied through final-current-space `heightReloadRows` while preserving the row-ID scroll anchor. Offscreen rows use their stable fallback metric until AppKit represents them, then receive one bounded correction. No atom, App batch, worker, or table path measures the row fleet.

### RepoExplorerTableRowCell — reusable SwiftUI row-content host

Each visible native row uses one reusable `NSTableCellView` containing one persistent `NSHostingView` and one feature-private observable row slot. The hosting root persists, while the row-content subtree is keyed with `.id(rowID)` or an equivalent explicit identity-reset boundary. `prepareForReuse` first clears the slot, reuse token, hover/menu/gesture state, measurement cache attachment, and callbacks; installing another row creates a fresh row-identity subtree before interaction becomes ready. Same-row content-revision changes may retain identity-local state, but a changed row ID cannot retain SwiftUI `@State`, hover, focus, accessibility, or callback state from the prior row.

The hosted row view composes the existing Repo Explorer row components, context menus, hover behavior, chips, accessibility labels, and command callbacks. It receives direct row values and callbacks only. It reads no atoms, topology, cache, or projection owner. Reuse clears the prior row binding before installing the next identity so an offscreen or reused cell cannot dispatch an action for stale content.

The table remains view-based and native:

- source-list appearance, transparent background, row spacing/insets, and variable row heights preserve current visuals;
- stored layout metrics preserve section/header/row geometry without fleet SwiftUI measurement;
- row buttons and the existing Repo Explorer focus bridge preserve activation, keyboard traversal, escape/refocus, and sidebar focus semantics;
- native table/row accessibility plus the existing row accessibility labels and actions preserve VoiceOver order and navigation;
- context menus, hover controls, collapse disclosure, scroll position/anchor, and command dispatch continue through their existing owners;
- table selection is presentation-neutral and cannot become a second product-selection owner.

### App-owned command presentation — generation-validated row route

`RepoExplorerCommandPresentationBatch` remains App-owned composition truth. The Feature does not observe App atoms or resolve capabilities. The native viewport publishes a typed `RepoExplorerVisibleWorktreeSnapshot(materializationGeneration, visibleRevision, worktreeIDs)`. The App batch observes that value plus its existing favorite, active-tab, management, pane-structure, zoom, drawer, and command-capability inputs and emits one immutable `RepoExplorerCommandPresentationDelta` containing:

```text
commandGeneration
targetMaterializationGeneration + targetVisibleRevision
complete current RepoExplorerCommandPresentationSnapshot
affected worktree IDs + affected repository IDs
union of old/new favorite and capability request identities
toolbarChanged
```

The batch advances generation only after it has resolved the complete current request set. A visible-set-only generation change may reuse equal results but still retargets them to the new materialization generation. App injects the delta into `RepoExplorerView`; no App type or state moves into the Feature.

The table accepts a command delta only when its target materialization generation and visible revision match the accepted table/viewport and its command generation is newer than the last accepted command generation. Using the worker's `rowIDsByWorktreeID`, `rowIDsByRepoID`, and per-row request identities, it intersects the affected IDs with represented visible slots and rebinds only those occurrences. Favorite changes include both the former and current add/remove-favorite request identities; capability changes include the current worktree request set. Toolbar changes update the toolbar from the same complete snapshot independently of table visibility. A stale delta is rejected and causes the App batch to observe the current visible snapshot; it never rebinds old capabilities. Hidden/offscreen rows perform no update and resolve the latest accepted complete snapshot when reused. Presentation is advisory only: every enabled row or toolbar action re-enters `AppCommandDispatcher`, which performs current targeting and authority validation.

### RepoExplorerViewportDemand — bounded visible-set projection

Viewport demand is part of the table materializer rather than a separate view that searches for SwiftUI's private backing table. It observes the owned scroll view's clip bounds, asks the owned table for its visible row range, maps only those bounded rows through the precomputed optional worktree IDs, and equality-publishes the resulting set.

Scroll callbacks are a burst of samples. One latest pending viewport calculation is retained per MainActor turn; intermediate bounds callbacks coalesce. Work is bounded by visible rows, not fleet size. The owner publishes no change when the worktree set is equal and clears demand on teardown, sidebar hide/collapse, or generation replacement before stale callbacks can bind.

### PaneActivityStatusAtom — keyed latest-state publication

The atom remains the MainActor keyed read owner. Per pane it owns:

```text
unknown
committed(value, publishedAt)
committed(value, publishedAt) + pending(latestValue, eligibleAt)
```

Equal input is suppressed without consuming eligibility. A changed input that is eligible commits immediately. A changed ineligible input replaces the one pending value and schedules the earliest pending eligibility through one reschedulable task for the atom, using the injected clock/delay seam. At the deadline the latest pending value commits if still distinct. Clear removes committed and pending state for the pane and recomputes the next deadline.

The atom reports `equal`, `published`, `deferred`, `replaced`, `deadline_fired`, and `cleared`; it never reports a distinct drop as equality.

### Terminal source owners — exact settle and bounded tail read

`GhosttyActionDisposition` remains the mandatory first decision. Diagnostic trace selection runs after disposition and uses its volume class. Raw `setTitle` receipt traces are equal/rate-admitted per surface or aggregated; they do not enqueue one OTLP record per callback.

The source-delivered ordered `commandFinished` control reaches `TerminalActivityProjector` through the existing private action-input binding/accumulator path before any lossy coordination subscriber. Its ordinary semantic EventBus fact remains available to other consumers, but pane settlement does not depend on that bus delivery.

`TerminalLastOutputLineReader` becomes a behavioral boundary:

- one admitted read per settle generation;
- at most the policy-bounded trailing visible row window and byte count;
- one controlled result: `value`, `empty`, `surface_stale`, `read_failed`, or `oversized`;
- duration/row/byte buckets reported without content or identifiers.

Upstream Ghostty documents viewport-relative selection and labels text extraction expensive. The pinned vendor contract must prove its trailing-row selection semantics. If the pinned API cannot preserve selection order for the bounded window, the reader may retain a full-visible-viewport implementation only as an explicitly measured MainActor exception whose maximum cells, bytes, and duration satisfy the same interface; exceeding the policy fails admission/proof rather than silently expanding work.

### ForgeActor and PullRequestRepositoryProjection — execution versus published state

Forge keeps provider lifecycle private. Per repository it distinguishes:

```text
execution state: demand, origin, generation, active request, latest follow-up,
                 freshness and backoff
published projection: unknown | loading(previous facts) |
                      ready(current facts) | unavailable(previous facts)
```

Provider start may change the published projection to `loading`; provider completion constructs a candidate projection but does not mutate successful freshness or last-published equality state until origin, generation, live membership, and publication scope validate.

Stable and transient presentation state are explicit:

```text
PullRequestStablePresentation
  unknown
  ready(confirmedFacts)          // an empty fact set is confirmed empty
  unavailable(previousConfirmedFacts?)

PullRequestRepositoryProjection
  stable(PullRequestStablePresentation)
  loading(baseline: PullRequestStablePresentation, requestIdentity)
```

Loading always wraps the exact stable baseline; unknown, confirmed empty, ready facts, and unavailable are never inferred from an empty collection.

One changed `PullRequestRepositoryProjection` event carries the current loading state plus the facts/invalidation delta needed for atomic materialization. Loading false is never a separate event preceding its facts. Equality compares with the last projection actually accepted for emission, not a computed or rejected candidate.

After all currentness checks, Forge synchronously commits active-request completion, freshness/backoff, the accepted-for-emission projection baseline, and the captured follow-up decision before its first external await. It then emits the captured event. After emission it re-reads generation, demand, active state, and pending intent before admitting a follow-up; an older completion cannot overwrite a newer state. A rejected candidate mutates none of the success, freshness, or accepted-publication baselines.

Loading transitions are exhaustive:

| Event | Transition |
| --- | --- |
| admitted start from stable S | `stable(S) -> loading(S, request)` |
| valid success | `loading(S, request) -> stable(ready(confirmedFacts))` atomically with facts |
| ordinary failure or rate limit | restore `stable(S)`; retain existing confirmed facts and apply existing backoff |
| terminal current-origin unavailability | `stable(unavailable(previous confirmed facts from S, if any))` |
| cancellation, validation rejection, or demand loss | restore `stable(S)` unless a successor is actually admitted |
| supersession with admitted successor | remain `loading(S, successor)`; no intermediate stable publication |
| origin change/loss | invalidate prior-origin S, then become `stable(unknown)` or current-origin unavailable as the existing contract decides |
| repository removal | remove projection and keyed cache facts |

Loading may remain after a terminal path only when a concrete successor request has already been admitted. Every non-success path emits at most one coherent changed projection when the restored state differs from the last accepted projection.

### WorkspaceCacheCoordinator and RepoCacheAtom — coalesced atomic apply

Actual topology/Git/Forge domain facts keep their EventBus path. Raw provider start/stop work intent does not.

Repository projections use the existing consumer-side coalescing pattern keyed by repository. Latest projection replaces obsolete pending projection before MainActor application. One bounded MainActor batch applies loading state and facts/invalidation in one `AtomMutationContext`, so consumers observe one coherent revision.

`RepoCacheAtom` retains keyed `RepoBranchKey -> PullRequestFacts` and repository-loading slots. It exposes keyed reads and atomic projection application. Hot Repo Explorer capture never requests `loadingPullRequestRepoIds` or another whole-family snapshot.

## Allowed And Forbidden Dependencies

Allowed:

```text
Terminal owners -> compact Core pane-status fact
Core/App fact projections -> injected Repo Explorer read interfaces
Repo Explorer adapter -> Core keyed reads and feature worker
Repo Explorer worker -> immutable materialization snapshot and update scope
RepoExplorerView -> feature-owned table materializer
table materializer -> reusable row cell slots + visible-worktree demand callback
table materializer -> typed visible-worktree generation snapshot -> App command-presentation batch
App command-presentation batch -> injected generation-validated delta -> Feature table/toolbar
ForgeActor -> changed repository projection event
WorkspaceCacheCoordinator -> atomic RepoCache apply
Repo Explorer/toolbar -> keyed RepoCache reads
```

Forbidden:

```text
Terminal/Core/Forge -> Repo Explorer row formatting
RepoExplorerView -> filesystem/Git/provider work or broad observation lifecycle
MainActor/table host -> fleet diff, sort, identity construction, content comparison, or projection-owner reads
reusable row cell -> atoms, topology/cache lookup, projection policy, or stale-row actions
viewport demand -> private SwiftUI backing-view discovery, per-row geometry fleet scan, or uncoalesced bounds publication
Feature table/cell -> App composition state or capability resolution
App command batch -> direct row mutation, Feature ownership, or command execution bypass
width change -> fleet SwiftUI measurement or unbounded height invalidation
raw Ghostty callback -> MainActor/EventBus/OTLP before typed disposition
provider loading edge -> separate global work-intent event
hot capture -> whole cache/topology/loading snapshot
rejected Forge result -> freshness or last-published mutation
cooperative cancellation -> overlapping successor execution for one key
```

Architecture lint/tests enforce imports and forbidden hot-path calls. Behavioral tests enforce state and sequence contracts. Runtime telemetry proves cadence and cost.

## State And Concurrency

### Derived execution per key

| Current state | Input | Transition | Output |
| --- | --- | --- | --- |
| idle/current | admitted request | running(request) | execution started |
| running generation A | newer request B | advance accepted generation; running A + pending B; request A cancellation | A publication revoked; retained pending count one |
| running A + pending B | newer request C | merge/replace pending through owner combiner; advance accepted generation | one complete pending intent retained |
| running A, no newer accepted generation | completion current/changed | idle/current(new) | published |
| running A, no newer accepted generation | completion current/equal | idle/current(existing) | equal |
| running A | completion after B/C accepted | current unchanged | superseded; cannot bind |
| running | cancelled/superseded/failed | idle/current(existing) | exact terminal outcome |
| any completion + pending demanded | terminal predecessor observed | running(pending) | successor starts |
| any | stop/removal | revoked; cancel then drain | no later binding |

No two executions for one key overlap. Different keys may execute concurrently under their existing family bounds.

### Native row materialization

| Current state | Input | Transition | Output |
| --- | --- | --- | --- |
| no snapshot | valid initial membership plan | expose candidate; execute insertion transaction; restore anchors; accept after completion | read model bound; represented cells requested from current rows |
| accepted revision R | valid content plan R→R+1 | expose candidate; reload final-space represented rows/heights; accept after completion | unaffected rows/cells retain identity; bounded visible update |
| accepted revision R | valid membership plan R→R+1 | capture anchors; expose candidate; exact batch transaction; final-space reload; restore; accept | only AppKit-requested represented cells bind; viewport recomputed once |
| generation G | equal snapshot | no state change | no table/layout/focus invalidation |
| generation/revision mismatch | stale plan or command delta | reject and request current owner output | accepted cells, anchors, and viewport unchanged |
| any | bounds burst | replace one pending viewport calculation | one latest visible-worktree set per coalesced turn |
| represented wrapping row + new width revision | measure that cell; height-reload its current index; restore scroll anchor | no offscreen/fleet measurement |
| any | cell reuse | `prepareForReuse`; clear identity state; install fresh keyed subtree | no stale state, action, focus, or accessibility value |
| any | hide/teardown | cancel pending viewport turn; clear visible demand; detach observers | cached projection remains outside the host |

The immutable snapshot is the consistency boundary. Table membership, cells, and viewport demand always refer to one accepted generation. MainActor application is serialized; off-main work cannot mutate a live cell. Snapshot acceptance is the **read-model binding** boundary. The subsequent membership call, represented-cell slot changes, AppKit layout/focus/accessibility work, and viewport publication are the **visible UI update** boundary; their outcomes and durations are never reported as binding.

### Pane activity publication per pane

| State | Input | Result |
| --- | --- | --- |
| unknown | non-empty value | commit now |
| committed X | X | equal, no deadline change |
| committed X, eligible | Y | commit Y |
| committed X, ineligible | Y | pending Y at eligibility |
| committed X + pending Y | Z | replace pending with Z, keep eligibility |
| committed X + pending Y | deadline | commit Y if still distinct |
| any | clear | remove committed/pending and reschedule global earliest deadline |

This is a deferral gate: first demanded checkpoint equals the ungated latest sequence.

### Forge completion order

```text
provider result
  -> derive candidate against captured request
  -> validate origin + generation
  -> intersect with live membership
  -> validate current publication scope
  -> derive complete repository presentation projection
  -> compare with last accepted-for-emission projection
  -> synchronously commit completion + freshness/backoff + accepted baseline
     and capture the current follow-up decision before any await
  -> emit the captured changed projection
  -> re-read/revalidate actor state after the await
  -> admit latest follow-up only if demand remains eligible and no newer work owns the state

validation failure
  -> leave success/freshness/accepted-publication baselines unchanged
  -> restore the exact loading baseline unless a successor is admitted
  -> retain/admit latest pending follow-up under current demand
```

Actor isolation serializes state. The provider task performs external work outside the actor. Reentry after every await revalidates captured identity.

## Current-To-Target Call Paths

### Repo Explorer invalidation and publication

```text
CURRENT
source keyed fact change
  -> RepoExplorerProjectionAdapter key-specific observation
  -> demand/equality admission + invalidation union
  -> affected-key or demanded full capture
  -> EagerDerivedAtom one-active/one-pending execution
  -> worker full/delta projection
  -> complete rendered equality + currentness validation
  -> one MainActor publishedResult binding
  -> RepoExplorerView List { ForEach(all rowIndex.entries) }
  -> SwiftUI OutlineListCoordinator fleet identity/diff/focus/layout
  -> private backing NSTableView
  -> RepoExplorerVisibleRowsBridge discovers table and publishes visible worktrees

TARGET
source keyed fact change
  -> [intentionally unchanged] RepoExplorerProjectionAdapter keyed admission
  -> [intentionally unchanged] EagerDerivedAtom + worker full/delta projection
  -> [changed] worker emits stored typed row IDs, occurrence indexes, layout classes,
               and exact RepoExplorerNativeUpdatePlan
  -> [changed] one MainActor immutable read-model snapshot binding
  -> [removed] generic SwiftUI List/OutlineListCoordinator fleet diff
  -> [added] RepoExplorerTableMaterializer executes exact native transaction,
              represented-row reload, visible-only height measurement, and anchor restore
  -> [added] reusable native cells host row-ID-reset SwiftUI content
  -> [changed] viewport publishes materialization generation + visible revision + worktrees
  -> [added] App command batch returns generation-validated affected presentation delta
  -> [added] current represented slots/toolbar rebind; actions re-enter dispatcher
  <- current visible rows / focus / accessibility / commands, or stale-generation rejection
```

Unchanged and preserved: source state owners, immutable request/result boundary, keyed admission, off-main worker, cancellation checkpoints, complete rendered equality, row appearance, row commands/context menus, sidebar focus target, and cached projection behavior. Removed edges eliminate only generic outline materialization and private backing-table discovery.

### Terminal pane activity

```text
CURRENT
Ghostty action
  -> trace received before disposition
  -> typed disposition / accumulator / projector
  -> commandFinished EventBus
  -> lossy TerminalActivityRouter subscriber
  -> full viewport MainActor read
  -> changed line
  -> PaneActivityStatusAtom may drop distinct value for 10s
  -> broad Repo Explorer wake

TARGET
Ghostty action
  -> typed disposition
  -> disposition-bounded diagnostic aggregation
  -> accumulator/projector ordered local settle control
  -> bounded measured tail read
  -> changed latest pane-status fact
  -> PaneActivityStatusAtom equal-or-defer-latest
  -> demanded pane-key Repo Explorer invalidation
```

Unchanged and preserved: exact semantic EventBus fact for other consumers, sufficient-statistics scrollbar aggregation, projector generation/lifetime guards, and keyed status storage.

### Forge loading and facts

```text
CURRENT v0.0.90
provider start -> loading=true event -> direct MainActor cache apply
provider completion -> mutate success/published baseline
                    -> loading=false event -> direct MainActor cache apply
                    -> late current-scope validation
                    -> facts event -> direct MainActor cache apply
                    -> whole loading-set sidebar capture

TARGET
provider start/completion -> private execution state
completion candidate -> validate before owner-state mutation
changed current repository projection
  -> repository-keyed latest coalescing
  -> one atomic MainActor loading+facts apply
  -> relevant repository-key sidebar invalidation
```

Unchanged and preserved: demand projection, active/follow-up bound, provider batching, backoff/freshness deadline, origin/generation/live-membership checks, and confirmed-fact retention.

## Failure And Recovery

- **Lost demand:** adapter removes hot observations and cancels/dequeues work after active termination; materialized rows/facts remain cached. Returning demand revalidates sources and captures current keys before display.
- **Cancellation:** exact `cancelled` outcome; never equality. Pending latest starts only after predecessor termination. Stop/revocation prevents late binding.
- **Unknown equality:** owner retains one invalidation or executes. It never suppresses on absence of proof.
- **Terminal read failure/oversize/stale surface:** status remains last confirmed; controlled outcome is reported; a later settle can recover. No empty value overwrites confirmed content.
- **Exact settle pressure:** the private ordered control is not lossy. Duplicate controls are idempotent by settle generation; out-of-order/stale surface generations are rejected.
- **Forge stale completion:** candidate is discarded before freshness/accepted baseline mutation; the exact stable loading baseline is restored unless a successor is admitted, and latest follow-up remains eligible.
- **Forge failure/rate limit:** current facts remain; loading restores the exact pre-loading stable state for ordinary failure/rate limit, while terminal current-origin unavailability uses the explicit unavailable state; existing backoff and next-deadline owner recovers.
- **Atomic cache apply failure:** no partial loading/facts revision is committed. The next changed repository projection or demand refresh can recover from Forge's authoritative current state.
- **Stale materialization snapshot:** generation mismatch is rejected before backing snapshot or cells change. The adapter's current published snapshot remains authoritative and the next current publication can recover.
- **Native plan rejection versus fatal inconsistency:** stale revision/generation is rejected before AppKit and recovers through one current replacement plan. A malformed current plan fails its constructor or MainActor invariant precondition. An AppKit consistency exception is fatal and has no recoverable return path; the cell-free pilot and transaction tests prevent shipping that condition. No path falls back to `reloadData` or SwiftUI `List`.
- **Cell reuse race:** `prepareForReuse` clears the prior slot and identity-keyed subtree before installing the next row. Delayed hover, accessibility, measurement, or command callbacks validate generation, row ID, and reuse token and otherwise do nothing.
- **Width/height race:** a measurement carries row ID, content revision, and width revision. Mismatch is discarded; a current changed height invalidates only the represented current row and restores the row-ID scroll anchor.
- **Command-presentation race:** a delta with stale materialization generation, visible revision, or command generation is rejected. Current visible demand re-arms the App batch. Offscreen rows bind the latest accepted complete presentation on reuse, and dispatcher execution remains authoritative.
- **Viewport callback after replacement/teardown:** pending work carries the accepted generation and host lifetime; mismatch cancels publication and teardown clears visible-worktree demand.
- **Accessibility or focus regression:** candidate materialization fails native proof and does not ship. Recovery is implementation correction inside the selected native host, not restoration of the measured generic-list path.
- **Telemetry sink loss:** application remains fail-open. Strict proof fails when stage evidence or zero-drop condition is absent.

## Cutover

This is a hard in-process cutover with no persisted schema or version skew:

1. The new keyed admission/controller path becomes the only Repo Explorer projection path; broad View observation and the 60-second fleet loop are removed.
2. `EagerDerivedAtom` adopts one-active/one-pending semantics for all consumers; overlapping behavior is not retained.
3. Pane activity distinct-drop state is replaced by committed-plus-latest-pending state; no migration is needed because it is runtime-only.
4. Separate Forge loading events are removed. The changed repository projection is the sole Forge presentation publication; cache application is atomic.
5. Hot stable-key derivation is removed; topology index materialization is authoritative immediately on hydration/mutation.
6. `RepoExplorerTableMaterializer` becomes the only non-empty Repo Explorer row container. SwiftUI `List`, `RepoExplorerVisibleRowsBridge` backing-table discovery, and computed string row identity are removed together; no runtime old/new UI path remains.

Rollback is binary rollback to the preceding app version, not a runtime dual path. No candidate build may mix old and new projection/loading authority.

## Performance, Observability, And Proof Architecture

### Separate acceptance populations

One real-size fixture identity contains 150 repositories, 180 worktrees, 12 tabs, and 36 panes. Performance phases use fresh markers and isolated data roots but the same deterministic fixture facts, candidate binary, hardware, power mode, trace selection, and sampler. Startup and fixture construction end before any acceptance population begins.

`AppPolicies.SidebarPerformanceProof` owns one immutable versioned descriptor with these exact values:

| Policy field | Immutable value |
| --- | --- |
| fixture | 150 repositories, 180 worktrees, 12 tabs, 36 panes; query `worktree`; two populated fixture tab identities |
| CPU gates | idle nearest-rank p99 `<10%`; action nearest-rank p95 `<20%` |
| sampling and floors | one-second intervals; 1,000 usable samples per idle variant; at least 100 successful actions/cycles and 200 complete action-bearing samples per action class |
| action boundary | first production input exactly on a sampler boundary; after settlement, next action on the first eligible boundary and no later than one interval |
| search cadence | eight native text-entry events at exactly 100 milliseconds per character; clear through the same control with no hold |
| quiescence and timeout | five consecutive seconds of unchanged capture/execute/publish/bind/visible-update/export state; five-second semantic+native readback timeout per action |
| host envelope | unrelated host CPU at or below 20%; normal memory pressure; nominal thermal state; AC power with Low Power Mode off and unchanged; no agent, terminal command/output producer, build, test, or profiler; maximum sampler gap 1.25 seconds |
| standard tags | exactly `performance,app.startup,terminal.startup` |
| diagnostic perturbation | paired diagnostic minus standard process-CPU p95 at most 5 percentage points and interaction-time p95 at most 10% |
| native-table pilot | membership MainActor p95 at most 4 milliseconds and at most 20% p95 growth when only offscreen rows double |

The descriptor is safely projected through the existing startup diagnostic with a policy version/hash and controlled values only, so the verifier binds evidence to the candidate's actual policy identity instead of duplicating or overriding it through environment values. Timing, threshold, admission, and validity constants have no environment override.

The descriptor includes one predeclared host-validity envelope: the allowed unrelated-host CPU ceiling, required memory-pressure class, required thermal class, required and unchanged power mode, maximum sampler gap, and forbidden concurrent workload classes (agent, terminal command/output producer, build, test, and profiler except during the separate attribution marker). Those values are fixed before the faulty/control/candidate series begins. The verifier may reject a population when any bound is breached, but cannot trim samples, relax a value, or substitute a new descriptor after seeing a result. App behavior and acceptance thresholds have no runtime environment override; diagnostics may select an authorized phase, never rewrite its policy.

The verifier owns a host-pressure precondition and concurrent validity guard. It records logical core count, load average, total system CPU, memory/compression pressure, power source/mode, and thermal state. A run with excessive external pressure, a sampler gap beyond policy, a candidate identity mismatch, or another build/test/profiler process is invalid and retained as evidence; it is neither a product pass nor a product failure. The candidate's own CPU remains inside the product measurement.

Quiescence is positive, not a wall-clock guess. After the startup diagnostic completes, the verifier requires projection capture/execution/publication/read-model-binding/visible-UI-update counters and trace-export backlog to remain unchanged for the policy quiescence interval while the mounted UI remains demanded. The acceptance window starts only after this observation succeeds.

```text
settled zero-PTY marker
  deterministic real-size workspace + Repo Explorer visible
  no mounted terminal process, no agent work
  positive quiescence
  >= 1,000 usable one-second samples
  gate: nearest-rank process CPU p99 < 10%

settled quiescent-PTY marker
  same workspace and visible sidebar
  mounted idle terminals, zero commands/output, no agent work
  positive quiescence
  >= 1,000 usable one-second samples
  gate: nearest-rank process CPU p99 < 10%

four independent ordinary-action markers
  search type/clear | grouping switch | sidebar hide/show | tab switch
  no terminal commands/output and no agent work
  >= 100 successful state-changing actions/cycles and >= 200 complete action-bearing samples per marker
  exact semantic and visible final-state readback per action
  gate: process CPU p95 < 20% for every marker
```

Idle and action distributions never combine. Search, grouping, visibility, and tab switching never combine with each other. A no-op, failed readback, delayed/missing publication, hidden sidebar during the visible-idle phase, or slowed-beyond-policy action does not count toward the sample/action floor.

Each action population follows the Specification's immutable attribution rule: its first input starts on a sampler boundary; every complete one-second interval intersecting input-through-generation-matched settlement belongs to the action; idle pacing intervals do not; and the next action begins on the first eligible boundary. The population is accepted only after both floors are met. Any no-op, failed/timeout command or input, wrong semantic or table generation, absent native readiness, partial/overlapping interval, sampler gap, cross-class sample, or policy/host breach invalidates the whole population without replacement or trimming.

Grouping, hide/show, and tab selection use their existing production `AppCommandDispatcher` paths. Search first uses the existing Filter Sidebar command, then a debug-proof-only native input driver under the existing debug automation principal locates the actual focused search control and delivers the fixed key events; it has no arbitrary query mutation, stable/beta availability, public IPC projection, or product command identity. A paired read-only proof observation reports the adapter's semantic generation and settled query/grouping/demand state plus the table's accepted generation/revision, transaction readiness, represented row IDs, field value, and accessibility/focus disposition. These are bounded debug-proof facts under the current marker, not a second product state owner.

The standard acceptance runs use exactly `performance,app.startup,terminal.startup` and exclude atom, exact row-body, raw-action, and per-mutation tracing. Only these standard populations establish the absolute CPU verdicts. Exact-attribution profiles run under separate diagnostic markers using the same fixture and action script. One paired standard-versus-diagnostic population reports CPU-distribution and interaction-time deltas and binds them to the descriptor's five-percentage-point/ten-percent limits. A diagnostic run beyond either limit remains useful only for qualitative stack attribution; it cannot supply, replace, or be pooled with an acceptance percentile or quantitative waste ratio.

The historical `v0.0.88` and faulty-release evidence remains diagnostic comparison only. Absolute 10%/20% gates, correct final state, zero delivery/trace/collector drops, and bounded stage ratios are independently required.

Proof path and real/fixed boundaries:

```text
verifier
  -> fixed deterministic fixture description          fixed input, not mocked runtime
  -> standard isolated debug launcher                 real production composition
  -> App startup diagnostic                           real topology/store/UI construction
  -> Repo Explorer adapter + worker                   real
  -> table materializer + viewport demand             real
  -> existing command dispatcher                      real grouping/hide-show/tab routes
  -> debug-only native search input driver            actual focused field + key events
  <- semantic generation + native table generation/readiness observation
                                                     liveness/correctness evidence

external low-overhead process sampler
  -> candidate PID CPU distribution                   real process boundary
  -> host pressure / thermal / sampler-gap validity   measurement validity

real owner telemetry -> OTLP collector -> Victoria
  <- marker-scoped stage counts, durations, drops, quiescence

paired sample / Instruments
  -> same PID + marker during named phase
  <- attribution only; never substitutes for CPU acceptance distribution
```

No projection, materializer, viewport, command, OTLP, or UI owner is mocked in acceptance. Disposable repository/worktree identities avoid mutating user data, but their size and relationships are fixed and recorded. A script-only canned metrics response remains limited to verifier unit tests and cannot satisfy runtime proof.

### Native UX and visible-update proof

The native table cutover is accepted only through the packaged debug app bound to the current marker and exact PID. The proof uses the real row host and verifies every existing behavior through its production owner:

| UX contract | Required native observation |
| --- | --- |
| content and grouping | By Repository, By Pane, and By Tab show the same ordered rows, counts, sections, loading/empty states, and collapse results as the bound projection |
| search and switching | fixed native type/clear, grouping, sidebar hide/show, and tab switching use the specified production drivers and reach generation-matched semantic/table readiness within policy |
| row interaction | worktree/pane activation, favorite and disclosure controls, context menus, hover controls, and command dispatch target the current generation/row/reuse token; recycled identity state is absent |
| focus and keyboard | filter focus, down-arrow exit, escape/refocus, key-loop order, row activation, and active-pane focus match the existing sidebar behavior without fleet focus-loop rebuilding |
| scrolling | wheel/trackpad scrolling, row-ID/offset anchoring across content/membership/visible-height updates, and generation-stamped visible-worktree demand remain current without jumps or stale demand |
| accessibility | table/row roles, order, labels, header traits, actions, enabled state, and VoiceOver navigation match the existing semantic tree |
| appearance | source-list background, row geometry/insets, section spacing, icons, chips, text, recency color, selection neutrality, and loading/fault presentation match the existing surface |

Each action readback proves the bound projection generation first, then the visible table generation and expected represented row/accessibility state. This keeps semantic correctness, read-model binding, and visible UI update independently attributable. Screenshots or visual feel alone cannot prove focus, accessibility, command targeting, generation currentness, or CPU.

### Bounded stage evidence

Each owner records a controlled stage/outcome and aggregate numeric scope/duration:

```text
observe/project: input class, demanded key counts
distinct: equal / changed / unknown
coalesce: retained / replaced, retained scope count
admission: admitted / deferred / rejected / capacity-limited
execute: started / completed / failed / cancelled / superseded + duration
validate: current / stale-generation / stale-origin / stale-scope
publish: changed / equal / invalidated
bind: changed / equal / revoked / stale
visible_update: membership_applied / affected_visible_rows / equal / stale / failed
deadline: scheduled / rescheduled / fired / cancelled
```

No raw paths, branch/repo names, UUIDs, terminal content, payloads, or errors enter OTLP. High-volume row-body and raw action diagnostics aggregate before the trace queue. Primary performance proof runs without high-volume atom logging and requires zero trace-queue loss.

Each often/heavy domain owns a non-observable fixed-state accumulator before the trace queue. Repo Explorer, Terminal, and Forge do not share policy or state; each stores only its declared fixed outcome counters, bounded scope buckets, and fixed histogram buckets. Recording is synchronous and allocation-bounded at the owning stage. One existing performance-report cadence flushes an immutable aggregate snapshot through `AgentStudioPerformanceTraceRecorder`, then resets interval counters. There is no per-input task or log record. Repo Explorer records publication, read-model binding, and visible UI update through separate counters even when one MainActor turn contains both. Exact mutation attribution is available only in a narrow opt-in diagnostic mode with the `AppPolicies` admission limit and controlled marker; the paired standard/diagnostic rule above determines whether its quantitative attribution is valid.

### Requirement-to-owner-to-proof trace

| Specification | Structural owner | Proof seam |
| --- | --- | --- |
| S1-S5 | RepoExplorerProjectionAdapter, topology stable-key index | deterministic grouping/key invalidation tests; forbidden-call architecture check; marker stage ratios |
| S6-S8 | Ghostty disposition/accumulator/projector, PaneActivityStatusAtom | exact-pressure integration; latest-sequence R-INV; pinned Ghostty tail-read contract; deadline test |
| S9-S12 | ForgeActor repository projection, coalesced coordinator apply, RepoCacheAtom | A→B→A controlled provider; atomic cache observation; unrelated-repo isolation; one-active/one-follow-up |
| S13-S14 | EagerDerivedAtomFamily, projection worker, rendered row model, native update plan, table materializer, App command-presentation batch | maximum concurrent execution probe; complete-row equality reference; off-main plan equivalence; cell-free AppKit pilot; unaffected-row/cell identity; command-generation routing; visible-only height/row hosting |
| S15 | idle fixture, quiescence detector, host-pressure guard, process sampler | separate zero-PTY and quiescent-PTY markers; complete distributions; p99 gate; scheduled-background-work and zero-drop evidence |
| S16 | existing command dispatch, debug-only native search driver, semantic/table readiness observation | separate search/grouping/visibility/tab markers; 100-action and 200-sample floors; boundary attribution; nearest-rank p95; whole-population invalidation |
| S17 | immutable versioned `AppPolicies.SidebarPerformanceProof` descriptor and verifier | exact tags/pacing/timeout/host envelope/perturbation; external-load and sampler-gap rejection; historical comparison without threshold substitution |
| S18-S20 | owning emitters and OTLP safe projection | outcome-matrix tests, binding-to-visible-update ratios, perturbation comparison, zero-drop verifier, sensitive canary and allowlist tests |

Unit tests may replace clocks/providers/projectors at designed seams. Performance acceptance keeps actual topology, pane fleet, adapter, worker, native table materializer, viewport demand, MainActor read-model binding, EventBus, cache, process sampler, OTLP collector, and Victoria paths real. Native UI proof binds the exact debug PID and verifies appearance, scrolling, hover, collapse, context menus, commands, focus/key loop, and accessibility. Paired stack sampling and Instruments bind the same marker/PID mid-idle and mid-action for attribution; visual feel alone is never performance proof.

## External Boundary Note

DeepWiki inspection of `ghostty-org/ghostty` identifies `ghostty_surface_read_text` as expensive, mutex-protected, caller-freed text extraction and describes viewport-relative bounded selection for trailing visible rows. The local vendor submodule is intentionally not hydrated in this worktree, so the pinned-vendor selection semantics remain a required integration proof seam rather than an assumed implementation detail.

## Requirement Coverage

| Requirement identity | Disposition | Design anchor |
| --- | --- | --- |
| U-PERF-1 | covered | keyed pre-capture admission, visible-only native materialization, separate idle/action CPU gates |
| U-ADMISSION-1 | covered | source disposition, invalidation accumulator, repository projection coalescing |
| U-CURRENTNESS-1 | covered | complete rendered equality, deferred latest pane fact, validate-before-Forge-mutation, atomic cache apply |
| U-ISOLATION-1 | covered | materialized capture, topology-owned keys, off-main worker/update planning, visible-bounded MainActor table apply |
| U-BOUNDS-1 | covered | one active/one pending, bounded invalidation sets, deadline state machines |
| U-OBSERVABILITY-1 | covered | bounded stage evidence, aggregate hot diagnostics, zero-drop proof |
| U-PRESERVATION-1 | covered | explicit preserved mechanisms and unchanged edges in each call path |

## Tradeoffs And Revisit Signals

- Key-specific observations add lifecycle bookkeeping to the adapter. The adapter owns this cost because it alone knows grouping and rendered demand. Revisit only if observation registration itself becomes an often/heavy measured lane.
- The feature-owned table replaces a concise generic `List` with explicit AppKit cell and viewport lifecycle. Repo Explorer pays that maintenance cost because the generic outline owner consumes the measured CPU budget and cannot express affected-row application. Revisit `LazyVStack` only if direct table hosting cannot preserve existing row composition or misses the action CPU target after visible-only updates.
- Full grouping, sort, search, or membership replacement uses the exact off-main `RepoExplorerNativeUpdatePlan`; AppKit receives prevalidated old/new index spaces while cells remain visible-bounded. This increases plan proof and anchor complexity, paid by Repo Explorer. The mandatory cell-free pilot is the falsifier: failure returns to design rather than licensing broad reload or MainActor diff.
- Stable layout classes avoid fleet measurement, while wrapping rows pay one represented-visible width measurement and possible anchored height correction. Repo Explorer owns the small correction risk; offscreen eager measurement is forbidden.
- The App command-presentation batch remains a separate App-owned projection and therefore adds generation/visible-revision routing into the Feature. App pays that composition bookkeeping; Feature rows stay direct-value consumers and dispatcher execution remains authoritative.
- Viewport demand from native visible rows is exact but MainActor-bound because AppKit geometry is MainActor-owned. It is coalesced once per turn and bounded by visible rows. Revisit only if scroll proof shows this bounded calculation exceeds its performance classification.
- Separate zero-PTY and quiescent-PTY idle runs increase proof time. The cost is borne by the verifier because combining the variants would hide idle-shell or empty-app false greens.
- Atomic repository projections can coalesce a very short loading interval away; this favors latest honest state over displaying every provider lifecycle edge. Revisit only if an explicit product requirement demands minimum spinner visibility.
- Bounded Ghostty tail selection depends on the pinned vendor contract. If it is unavailable or slower than the measured full-viewport exception, preserve the behavioral interface and choose the lowest-cost proven implementation without moving surface lifetime authority off MainActor.
- Making `EagerDerivedAtom` true single-flight may delay a newest request until cancellation settles. The payer is newest-result latency under expensive non-cooperative work; cancellation checkpoints and maximum termination latency are therefore proof obligations.
