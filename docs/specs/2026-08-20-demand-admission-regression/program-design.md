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
                                                   one compact MainActor binding

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

- `RepoExplorerView` currently owns observation and constructs a complete request on MainActor before request equality. Live sampling of `v0.0.89` places the dominant main-thread stack in this path.
- `RepoExplorerProjectionAdapter` and `EagerDerivedAtomFamily` already own materialized projection state, but execution is latest-wins with potentially overlapping cooperative cancellation.
- `TerminalLocalActionAccumulator` and `TerminalActivityProjector` already own bounded raw-signal contraction; `PaneActivityStatusAtom` is the keyed MainActor read owner but discards changed values inside its interval.
- `ForgeActor` already owns demand, freshness, backoff, origin/generation validation, one active provider task, and one pending follow-up. `v0.0.90` exposes its loading edges as separate events and mutates success/publication baselines before final scope validation.
- `RepositoryTopologyAtom` already owns stable-key indexes, but `RepoPresentationItem.init(repo:)` recomputes path-derived keys during hot capture.
- OTLP projection and taxonomy allowlisting are authoritative and remain source-scrubbed.

Changed behavior is limited to admission, state-transition order, capture shape, execution overlap, and proof. Existing feature presentation and domain authority remain authoritative.

## Structural Crux And Alternatives

The crux is where a source change becomes a consumer-relevant semantic invalidation.

| Alternative | Shape | Gain | Cost / failure | Decision |
| --- | --- | --- | --- | --- |
| Downstream suppression only | Keep broad observation and full capture; improve worker equality/debounce | Small edit | Still pays MainActor capture and filesystem work; cannot meet S2-S4 | Rejected |
| Producer-formatted sidebar rows | Terminal, Core, and Forge produce Repo Explorer row models | Early contraction | Moves consumer policy into sibling/domain owners and creates cross-feature coupling | Rejected |
| Consumer-owned keyed admission over existing domain facts | Domain owners publish compact facts; Repo Explorer observes only demanded keys and emits full/delta invalidations | Preserves ownership, removes work before capture, supports exact proof | More observation bookkeeping and explicit invalidation vocabulary | Selected |
| New generic derived-state scheduler | Central admission/deadline/control service | Uniform mechanics | New authority/control plane, broad migration, and scope beyond the confirmed goal | Rejected |

The selected direction spends complexity in one feature-owned controller and explicit domain state transitions. Repo Explorer bears key-observation bookkeeping; domain owners bear semantic equality and currentness. Revisit a broader scheduler only if at least three unrelated consumers require the identical invalidation/deadline semantics and the local owners cannot share the existing `EagerDerivedAtom`/`CoalescingBusApplier` primitives without duplicating policy.

## Components, Ownership, And Interfaces

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
ForgeActor -> changed repository projection event
WorkspaceCacheCoordinator -> atomic RepoCache apply
Repo Explorer/toolbar -> keyed RepoCache reads
```

Forbidden:

```text
Terminal/Core/Forge -> Repo Explorer row formatting
RepoExplorerView -> filesystem/Git/provider work or broad observation lifecycle
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
source atom change
  -> RepoExplorerView broad observation callback
  -> [removed] full MainActor request construction
  -> request equality
  -> EagerDerivedAtom admit; cancel predecessor + start overlapping successor
  -> worker
  -> incomplete rendered equality
  -> MainActor binding

TARGET
source keyed fact change
  -> [changed] RepoExplorerProjectionAdapter key-specific observation
  -> demand/equality admission + invalidation union
  -> [changed] affected-key or demanded full capture from materialized values
  -> EagerDerivedAtom one-active/one-pending execution
  -> worker full/delta projection
  -> [changed] complete rendered-model equality
  -> generation/currentness validation
  -> one MainActor binding
```

Unchanged and preserved: source state owners, immutable request/result boundary, off-main worker, cancellation checkpoints, row IDs/index, and final SwiftUI consumption.

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
- **Telemetry sink loss:** application remains fail-open. Strict proof fails when stage evidence or zero-drop condition is absent.

## Cutover

This is a hard in-process cutover with no persisted schema or version skew:

1. The new keyed admission/controller path becomes the only Repo Explorer projection path; broad View observation and the 60-second fleet loop are removed.
2. `EagerDerivedAtom` adopts one-active/one-pending semantics for all consumers; overlapping behavior is not retained.
3. Pane activity distinct-drop state is replaced by committed-plus-latest-pending state; no migration is needed because it is runtime-only.
4. Separate Forge loading events are removed. The changed repository projection is the sole Forge presentation publication; cache application is atomic.
5. Hot stable-key derivation is removed; topology index materialization is authoritative immediately on hydration/mutation.

Rollback is binary rollback to the preceding app version, not a runtime dual path. No candidate build may mix old and new projection/loading authority.

## Performance, Observability, And Proof Architecture

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
materialize: published / equal / revoked
deadline: scheduled / rescheduled / fired / cancelled
```

No raw paths, branch/repo names, UUIDs, terminal content, payloads, or errors enter OTLP. High-volume row-body and raw action diagnostics aggregate before the trace queue. Primary performance proof runs without high-volume atom logging and requires zero trace-queue loss.

Each often/heavy domain owns a non-observable fixed-state accumulator before the trace queue. Repo Explorer, Terminal, and Forge do not share policy or state; each stores only its declared fixed outcome counters, bounded scope buckets, and fixed histogram buckets. Recording is synchronous and allocation-bounded at the owning stage. One existing performance-report cadence flushes an immutable aggregate snapshot through `AgentStudioPerformanceTraceRecorder`, then resets interval counters. There is no per-input task or log record. Exact mutation attribution is available only in a narrow opt-in diagnostic mode with an explicit admission limit and controlled marker; the proof compares instrumented and uninstrumented runs and rejects material perturbation.

### Requirement-to-owner-to-proof trace

| Specification | Structural owner | Proof seam |
| --- | --- | --- |
| S1-S5 | RepoExplorerProjectionAdapter, topology stable-key index | deterministic grouping/key invalidation tests; forbidden-call architecture check; marker stage ratios |
| S6-S8 | Ghostty disposition/accumulator/projector, PaneActivityStatusAtom | exact-pressure integration; latest-sequence R-INV; pinned Ghostty tail-read contract; deadline test |
| S9-S12 | ForgeActor repository projection, coalesced coordinator apply, RepoCacheAtom | A→B→A controlled provider; atomic cache observation; unrelated-repo isolation; one-active/one-follow-up |
| S13-S14 | EagerDerivedAtomFamily, projection worker, rendered row model | maximum concurrent execution probe; complete-row equality reference; unaffected-row identity |
| S15 | complete production path | same real-size marker workload against control/faulty/repaired builds; CPU, MainActor wait/held, terminal round trip, interaction proof |
| S16-S18 | owning emitters and OTLP safe projection | outcome-matrix tests, waste ratios, zero-drop verifier, sensitive canary and allowlist tests |

Unit tests may replace clocks/providers/projectors at designed seams. The heavy workload keeps actual topology, pane fleet, MainActor capture, worker, EventBus, cache, OTLP collector, and Victoria paths real. Native UI proof uses the exact debug PID only for visible/interaction behavior, not performance attribution.

## External Boundary Note

DeepWiki inspection of `ghostty-org/ghostty` identifies `ghostty_surface_read_text` as expensive, mutex-protected, caller-freed text extraction and describes viewport-relative bounded selection for trailing visible rows. The local vendor submodule is intentionally not hydrated in this worktree, so the pinned-vendor selection semantics remain a required integration proof seam rather than an assumed implementation detail.

## Requirement Coverage

| Requirement identity | Disposition | Design anchor |
| --- | --- | --- |
| U-PERF-1 | covered | keyed pre-capture admission, bounded execution, real-load proof |
| U-ADMISSION-1 | covered | source disposition, invalidation accumulator, repository projection coalescing |
| U-CURRENTNESS-1 | covered | complete rendered equality, deferred latest pane fact, validate-before-Forge-mutation, atomic cache apply |
| U-ISOLATION-1 | covered | materialized capture, topology-owned keys, off-main worker/provider |
| U-BOUNDS-1 | covered | one active/one pending, bounded invalidation sets, deadline state machines |
| U-OBSERVABILITY-1 | covered | bounded stage evidence, aggregate hot diagnostics, zero-drop proof |
| U-PRESERVATION-1 | covered | explicit preserved mechanisms and unchanged edges in each call path |

## Tradeoffs And Revisit Signals

- Key-specific observations add lifecycle bookkeeping to the adapter. The adapter owns this cost because it alone knows grouping and rendered demand. Revisit only if observation registration itself becomes an often/heavy measured lane.
- Atomic repository projections can coalesce a very short loading interval away; this favors latest honest state over displaying every provider lifecycle edge. Revisit only if an explicit product requirement demands minimum spinner visibility.
- Bounded Ghostty tail selection depends on the pinned vendor contract. If it is unavailable or slower than the measured full-viewport exception, preserve the behavioral interface and choose the lowest-cost proven implementation without moving surface lifetime authority off MainActor.
- Making `EagerDerivedAtom` true single-flight may delay a newest request until cancellation settles. The payer is newest-result latency under expensive non-cooperative work; cancellation checkpoints and maximum termination latency are therefore proof obligations.
