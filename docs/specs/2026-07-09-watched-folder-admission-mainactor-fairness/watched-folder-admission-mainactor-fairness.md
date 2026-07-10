# Watched-Folder Admission and MainActor Fairness Spec

Date: 2026-07-09
Revised: 2026-07-10 after adversarial spec review
Status: accepted technical contract after adversarial review
Scope: pre-plan architecture contract
Runtime dominance: unresolved; static mechanisms are source-proven

Parent contract: [AgentStudio Performance Boundaries](../2026-07-10-agentstudio-performance-boundaries/agentstudio-performance-boundaries.md)

## Product Intent

AgentStudio must remain an interactive terminal workspace while it discovers,
watches, and refreshes hundreds of repositories and worktrees. Adding a large
watched parent, reopening a workspace that contains one, or running agents that
continuously mutate `.git` must not make typing, cursor movement, pane switching,
or existing terminal rendering feel frozen.

Responsiveness and correctness are co-primary. AgentStudio may coalesce path
hints and delay background freshness under pressure, but it must not silently
lose repository creation/removal truth or present a partial scan as an
authoritative absence. When overload or FSEvents discontinuity occurs, the
system must enter an observable repair state and converge to the same topology
as a complete authoritative scan after pressure subsides.

The architecture must also be understandable during code review. A developer
must be able to see where work runs, what is bounded, what may be coalesced,
what repairs loss, and what is allowed on MainActor without reconstructing the
answer across callback, bus, reducer, coordinator, and atom call sites.

## User-Visible Success

The contract covers two independent workload shapes:

1. **Add/boot convergence.** Initial discovery and persisted-topology replay can
   process a large fleet without a fleet-sized synchronous MainActor mutation.
2. **Steady-state convergence.** Repeated filesystem and `.git` churn does not
   create an ever-older callback backlog or a repeated full-scan loop.

For both shapes:

- terminal input and cursor feedback remain usable;
- pane selection, focus, and shell controls remain usable;
- last-known topology remains available while repair is in progress;
- topology, Git state, and pane projections converge after churn stops;
- an operator can identify whether latency accumulated in source admission,
  scan scheduling, ownership routing, EventBus delivery, MainActor apply,
  Bridge refresh, or rendering.

Exact latency ceilings remain an open calibration decision until the controlled
watched-versus-control workload records current distributions. The proof must
produce both an absolute interactive ceiling and a maximum regression from its
control; event presence alone is never success.

## Current-State Evidence

All implementation observations below are anchored to `cd47c511` on
`ghostty-performance`.

### Supported

- `DarwinFSEventStreamClient` creates one FSEvent stream and one serial dispatch
  queue per registration, requests file-level `NoDefer` delivery at 100 ms, and
  yields into a default-unbounded `AsyncStream`
  (`DarwinFSEventStreamClient.swift:47-59,70-109,140-200`).
- The FSEvents callback discards event flags and event IDs. The current
  `FSEventBatch` cannot represent `MustScanSubDirs`, `UserDropped`, or
  `KernelDropped` (`FSEventStreamClient.swift:3-10`).
- A watched parent has a synthetic registration, while every discovered
  worktree is also registered. One large parent can therefore create parent
  plus nested-worktree observation (`FilesystemActor.swift:134-157,611-640`).
- Any watched-parent batch containing one `/.git/` path or trailing `/.git`
  awaits a complete depth-bounded scan. The sole ingress loop awaits that scan
  before reading the next callback batch; there is no per-folder single-flight
  or running-plus-dirty collapse
  (`FilesystemActor.swift:306-319,644-700`).
- `RepoScanner` suppresses directory read failures with `try?`. Its result does
  not declare whether traversal was complete. `refreshWatchedFolder` diffs the
  returned set against prior truth and may treat absence as removal
  (`RepoScanner.swift:206-290`; `FilesystemActor.swift:696-749`).
- Repository validation independently catches timeouts and all other failures
  and returns `nil`. A traversal may therefore visit every readable directory
  while still failing to classify one or more encountered `.git` candidates
  (`RepoScanner.swift:40-56,206-290`).
- Every ordinary worktree batch reconstructs `FilesystemRootOwnership` from all
  roots. Root construction and every path route canonicalize filesystem paths;
  ownership selection linearly filters the full root set
  (`FilesystemActor.swift:253-303`; `FilesystemRootOwnership.swift:18-95`).
- Batched repository discovery still loops repositories on
  `WorkspaceCacheCoordinator`, which is MainActor-isolated.
  `performBatchedTopologyMutation` defers one worktree index rebuild but does
  not replace repeated repository lookup, identity resolution, cache writes,
  or per-repository observable mutations with one keyed apply
  (`WorkspaceCacheCoordinator.swift:56-69,105-240`;
  `RepositoryTopologyAtom.swift:42-52,104-132,199-280`).
- Boot replay posts one topology envelope per persisted repository
  (`AppDelegate+WorkspaceBoot.swift:496-525`).
- The current `NotificationReducer` is a MainActor scheduling/coalescing queue,
  not a canonical-state reducer. It owns default-unbounded output streams,
  dictionaries, sorting, visibility lookup, and timers after a broad
  `criticalUnbounded` MainActor intake
  (`NotificationReducer.swift:4-157`;
  `WorkspaceSurfaceCoordinator.swift:323-379`).
- `EventBus` preserves explicit subscriber loss policy and useful yielded,
  consumed, dropped, replay, and high-water-lag diagnostics, but it is topicless
  and appends every admitted fact to replay before yielding to every subscriber.
  Production does not export `diagnosticsSnapshot()`
  (`EventBus.swift:171-314,333-399`).
- `WorkspaceSurfaceCoordinator` awaits Bridge filesystem refresh from its sole
  serial critical consumer. An unrelated fact can wait behind repository load,
  package preparation, and WebKit delivery
  (`WorkspaceSurfaceCoordinator.swift:360-429`).
- The current Git performance workload persists `watchedPaths: []` and verifies
  telemetry presence rather than interaction or convergence budgets
  (`scripts/verify-git-refresh-performance-workload.sh:407-523,1057-1217`).
- `RepositoryTopologyStore` observes topology on MainActor and schedules an
  autosave. Before the datastore await, `WorkspaceSQLiteSaveCoordinator`
  synchronously constructs a full workspace and topology bundle, scanning live
  panes, tabs, repositories, and worktrees on MainActor
  (`RepositoryTopologyStore.swift:72-114`;
  `WorkspaceSQLiteSaveCoordinator.swift:28-42`;
  `WorkspacePersistenceTransformer.swift:260-313`).

### Preserved Current Boundaries

- `FilesystemProjectionIndex` already owns pane/worktree normalization,
  topology generations, indexes, and per-envelope filtering off MainActor.
  This spec preserves that owner; the projection-first June diagnosis is stale.
- Git status uses AgentStudioGit/libgit2, not shell process herds. The current
  projector already has latest-per-worktree pending state, logical concurrency
  limits, equality deduplication, periodic repair, and capacity-retry behavior.
- Native RepoExplorer already uses SwiftUI `List`. Missing native row
  virtualization is not the leading source-proven defect.
- Explicit `BusSubscriberPolicy` remains required. This spec extends producer
  admission and topic interest; it does not restore hidden subscriber defaults.

### Unresolved Runtime Questions

- Which supported mechanism dominates the user's steady-state incident?
- How often do parent and nested-worktree streams observe the same write?
- Does AgentStudio's own libgit2 work create meaningful `.git` watcher feedback?
- How frequently do partial or dropped FSEvents occur in the real workload?
- What share of interaction delay comes from Bridge, sidebar derivation, Git,
  or terminal event amplification after filesystem pressure begins?

No implementation may claim the root cause is proven until the workload in
this spec records those boundaries separately.

## Shared Pressure-Bearing Stream Contract

The parent performance-boundaries spec owns the shared declaration vocabulary.
Every high-cardinality or latency-sensitive asynchronous path must have an
inspectable `PressureStreamContract`. It declares:

| Field | Required meaning |
| --- | --- |
| Owner | The one component allowed to mutate queue state and acknowledge repair. |
| Input | The typed observation, sample, fact, intent, or diagnostic record admitted. |
| Isolation | Callback thread, actor, MainActor, or synchronous caller boundary. |
| Capacity | Maximum items/keys/bytes and whether the bound is hard or diagnostic. |
| Admission | Exact, latest-by-key, accumulated, debounced, sampled, or rejected. |
| Overflow | What is dropped/coalesced and which durable repair obligation replaces it. |
| Ordering | Per-source, per-key, generation, or intentionally unordered. |
| Replay | None, current snapshot, bounded semantic history, or authoritative rebuild. |
| Consumers | Named topics/owners that need the admitted value. |
| Contraction | Expected ratio from input observations to downstream outputs. |
| Generation | Token that makes stale work cheaply rejectable. |
| Sensitivity | Whether paths, identities, content, or secrets may be retained/exported. |
| Telemetry | Count, queue age, high-water, service time, output count, and repair state. |

An actor annotation is not a substitute for this declaration. Actor isolation
prevents data races; it does not bound input, reduce service complexity, ensure
fairness, or repair loss.

## Requirements

### Source Admission and Repair

WF1. The Darwin callback boundary must synchronously produce an owned
`Sendable` observation containing registration identity/generation, monotonic
capture time, unioned inspected flags, first/last event-ID watermarks, and only
the bounded number/bytes of copied path records permitted by the source
contract. Inspected native-record count, copied-path count, copied UTF-8 bytes,
and maximum bytes per path are separate hard bounds. A single callback cannot
allocate, bridge, measure, or iterate native payload without a bound. Array
shape/count mismatch, conversion/arithmetic overflow, an oversized record, or
an uninspected tail records truncation and synchronously advances conservative
source-scoped recovery without dereferencing the tail.

WF2. Callback admission must be nonblocking, memory-bounded, and expected O(1)
for a fixed observation shape regardless of whether 1, 100, or 300 source keys
are registered. It may gather bounded path observations by source/root
generation, but it performs no path dedupe, normalization, routing, subtree
collapse, domain merge, repair join, fleet scan/copy, actor call, or per-callback
task creation. It must not silently discard a correctness obligation.

WF3. `MustScanSubDirs`, kernel/user drops, wrapped event IDs, root replacement,
callback-capture truncation, callback-gate overflow, registration replacement,
and any internal lossy
admission must receive an exhaustive disposition and create durable repair debt
when continuity or root identity is no longer authoritative.

WF4. Repair debt remains present until every recovery owner declared for that
source kind acknowledges the same `RepairGeneration`. Starting or completing a
scan does not clear debt if topology apply, Git/content rebuild, or another
declared downstream canonical acknowledgement fails, is stale, or is rejected.

WF5. `FilesystemSourceGate` uses the exact state vocabulary `healthy`, `dirty`,
`reconciling`, `reconcilingAndDirty`, `awaitingAcknowledgements`,
`repairFailed`, and `shuttingDown`. These are product/runtime state, not log-only
labels.

WF6. Removing or replacing a watched root invalidates queued observations,
running scans, and repair completions from the old generation.

WF7. Source admission exposes offered, admitted, contracted, rejection-reason,
overflow/recovery-escalation, pending-plus-leased custody, high-water, and
oldest-item/recovery age using the parent's counter algebra. Filesystem actor
diagnostics separately expose gathered inputs, equality duplicates, unique
paths, subtree/root contractions, emitted outputs, and repaired-current results;
mailbox counters never pretend to measure actor-owned semantic coalescing.

WF8. A typed `FSEventFlagDisposition` or equivalent exhaustive policy decides
which paths are ordinary file hints, sentinel paths to ignore, diagnostics-only
records, repair triggers, root-generation invalidations, and unsupported mount
events. Root replacement uses `WatchRoot` or an equivalent canonical-root
revalidation mechanism.

WF9. Repair policy is source-kind-specific. A synthetic watched-parent source
owns repository-membership repair. A registered-worktree source owns content,
Git, and pane/filesystem projection repair as declared by its consumer matrix;
one source kind cannot silently borrow the other's scan as sufficient repair.
Because AgentStudio has no canonical full-file inventory, registered-worktree
content repair uses the coarse invalidation/consumer-transfer contract below;
it never fabricates completeness by replaying an unbounded list of paths.

WF10. Registered-worktree repair consumers register through one
generation-bearing registry. The captured participant set, unregister/
replacement transfer, late registration currentness, acknowledgement receipt,
and retry ownership are exhaustive; disappearing from live UI state cannot
clear repair debt.

### Scan Scheduling and Completeness

WS1. Each watched folder has at most one running discovery scan.

WS2. Triggers received while a scan runs collapse into one newest-generation
dirty obligation. A running scan produces at most one immediate follow-up scan
for the accumulated dirty state.

WS3. Initial add, callback-triggered refresh, manual refresh, fallback refresh,
and overflow repair use the same per-folder scheduler and generation rules.

WS4. One hot folder cannot starve other folders or interactive work. Scheduler
fairness and concurrency must be explicit and measurable at both admission and
actor/scan processing. The actor processes at most one calibrated
contribution/item/byte/service quantum for a ready root before requeueing a
still-dirty root behind other ready roots. Attended-root priority may reduce
latency but uses a finite `maximumAttendedPriorityBurst` policy value and cannot
eliminate background repair service. Ready-root membership is unique and the
baseline queue is round-robin. With `R` roots ready when a quiet root enters the
queue and configured priority burst `P`, that root receives a turn within at
most `(R + 1) * (P + 1)` successful root selections; retries remain ahead of
newer same-root work but rotate behind already-ready unrelated roots. Production
`P` and work quantum sizes are frozen through calibration, while this scheduling
formula is invariant. The 300-source oracle does not depend on wall-clock sleeps.

WS5. A scan result must declare `complete`, `partialTraversal`,
`partialValidation`, `cancelled`, `rootUnavailable`, `permissionDenied`, or an
equivalently precise exhaustive outcome.

WS6. Repository/worktree removal may be inferred only from a complete scan of
the same current root generation. “Complete” requires authoritative traversal
of every in-policy directory and authoritative classification/validation of
every encountered `.git` candidate. A validation timeout or suppressed error
makes the result partial. Partial, failed, cancelled, or stale scans cannot
establish absence.

WS7. A partial scan may merge verified positive discoveries only if it cannot
remove prior canonical truth and the resulting state remains marked dirty.

WS8. Scan telemetry distinguishes queue wait, traversal/validation service
time, completion class, directories visited, repositories validated, stale
completion drops, and follow-up count.

WS9. The scanner records candidate count plus validation success, negative,
timeout, cancellation, and failure counts. A negative result is authoritative
only when the validation provider explicitly established it, not when an error
was converted to `nil`.

### Root Ownership and Filesystem Projection

FI1. Canonical root identity remains host-owned. Raw callback strings,
relative paths, `..`, symlinks, case variation, and stale registration IDs
cannot select another worktree by naive prefix comparison.

FI2. Root canonicalization and ownership index construction happen when
topology changes, not once per FSEvent batch.

FI3. Path routing uses an immutable generation-bearing `RootIndex` snapshot
whose lookup cost does not linearly scan every registered root per path.

FI4. `.gitignore`/policy classification and path deduplication operate after
safe ownership resolution and before global domain publication.

FI5. `FilesystemProjectionIndex` remains the owner of pane/worktree projection.
MainActor may capture immutable source snapshots and apply returned intents; it
does not reimplement path filtering or canonicalization.

FI6. A user-selected canonical root authorizes traversal and watcher creation
inside that root. Git metadata pointing to a clone/common directory outside the
root may inform identity, but it does not create new watcher authority unless
that external path is already independently user-authorized.

FI7. Local canonical roots are the initial authoritative class. A non-local,
removable, disconnected, or permission-volatile root may retain last-known
truth and repair debt, but unavailability alone cannot establish removal until
explicit support defines its disappearance semantics.

### Topology Convergence and MainActor Apply

TA1. Repository scan results cross into topology projection as immutable,
generation-bearing snapshots with explicit completeness plus the canonical
topology revision on which the diff is based.

TA2. Repository identity resolution, existing-versus-discovered joins,
worktree reconciliation construction, removal candidate construction, and
cache mutation construction execute outside MainActor.

TA3. MainActor remains the owner of canonical observable atoms.

TA4. MainActor applies one pre-diffed, keyed `TopologyApplyBatch` per accepted
generation and compatible canonical base revision. Operations are field-scoped
patches owned by discovery, not whole replacement entities. Application cost is
proportional to changed keys, not total fleet size or repeated linear identity
lookup.

TA5. One apply batch produces bounded observation invalidation and at most one
trace-identity refresh request for that batch.

TA6. MainActor apply performs no filesystem I/O, path canonicalization, regex
or JSON work, repository scan, Git read, Bridge package build, fleet join, or
same-bus derived-event loop.

TA7. Every MainActor apply API exposes its domain in its name and accepts a
typed mutation. Generic `submit(envelope)` is not an acceptable canonical-state
mutation surface.

TA8. MainActor instrumentation records queue-to-start delay separately from
synchronous service duration, changed-key count, observation revision count,
and longest run-loop turn attribution. Time suspended across `await` is not
reported as continuous MainActor occupancy.

TA9. The batch contract names field ownership and merge policy for stable IDs,
stable-key/path matching, repo/worktree names and paths, user-owned tags,
availability, cache enrichment, and path-index generation. An incompatible
base revision is rejected and reprojected unless every conflicting field has an
explicit safe merge.

TA10. Cache cleanup and pane orphaning/reassociation patches join the canonical
topology patch in one bounded MainActor transaction. A successful transaction
returns a typed accepted-revision effect record for filesystem root/activity
resync, Git baseline, pane/filesystem projection, Forge scope, persistence,
trace identity, and repair acknowledgements. Downstream failure preserves the
matching repair obligation only for owners named by the source-kind matrix;
independent enrichment/durability/telemetry owners retain their own retry state.

TA11. Ordinary topology persistence receives only the revisioned changed-key
record produced by the accepted topology transaction. Full state is available
only through the bounded paged checkpoint contract for boot, import, export, or
revision-gap recovery. MainActor neither normalizes nor retains a fleet-wide
copy-on-write snapshot merely because a datastore write is about to begin.
SQLite schema and I/O ownership remain unchanged.

### Event Admission, Scheduling, and Replay

EV1. The global runtime EventBus carries semantic domain facts, not raw source
observations, UI samples, render samples, or diagnostic samples.

EV2. Every globally admitted fact declares topic/family, replay policy,
ordering, recovery owner, expected rate class, and named consumers.

EV3. Subscribers declare topic interest at subscription. Topic filtering occurs
before per-subscriber queue admission and consumed/yielded accounting.

EV4. `EventBus` remains a transport owner. Topic matching is routing metadata;
the bus does not perform domain classification, joins, projection, workflow
branching, or UI mutation.

EV5. Explicit `BusSubscriberPolicy`, subscriber attribution, live/replay drops,
yielded/consumed counts, and high-water lag remain intact.

EV6. Replay is admitted by fact policy. Current-state synchronization uses a
snapshot; semantic history uses bounded replay; rebuildable facts name their
authoritative recovery owner.

EV7. A correctness-bearing `criticalUnbounded` consumer must also declare its
pressure signal and recovery strategy. Unbounded lag cannot remain invisible.

EV8. Same-global-bus reposting requires a named derivation and a contraction
budget demonstrating fewer outputs than inputs. Otherwise producer-to-consumer
composition uses a targeted call or internal typed channel.

EV9. `NotificationReducer` is removed from terminal and filesystem paths.
Source-specific mailboxes own contraction, topic-filtered projectors own
semantic scheduling, and named MainActor appliers own final mutation. No generic
MainActor reducer receives these topics.

EV10. The semantic scheduler consumes already-admitted facts, uses an immutable
visibility snapshot for best-effort priority, and yields bounded typed batches
to named MainActor appliers. It does not receive every global topic.

EV11. The first cut preserves one generic runtime EventBus with exhaustive typed
topic interest. Several domain buses are a future measured escape, not an equal
implementation-plan option.

EV12. Filesystem-to-Git invalidation uses the accumulated
`WorktreeGitInvalidationMailbox` with no product replay or global fanout. The global EventBus receives the
deduplicated Git snapshot/transition and only filesystem facts with named
product consumers; it is not an intermediate queue between two owners in one
projection pipeline.

### Bridge and Render-Loop Containment

BR1. A global event consumer may enqueue a generation-bearing Bridge
invalidation and must return without awaiting repository reload, package build,
JSON preparation, WebKit delivery, or React render.

BR2. Bridge refresh ownership is per pane/repository and single-flight with
running-plus-dirty collapse and stale-completion rejection.

BR3. One refresh generation produces either a cold full snapshot or a warm
delta, never both as ordinary steady-state publication.

BR4. Detailed Bridge package normalization, React windowing, and selected-file
content virtualization are a separable follow-up boundary. This spec owns only
the critical-lane enqueue/fairness contract.

BR5. `BridgeFilesystemRefreshRequest` is bounded independently of package size:
it carries generations/revisions, bounded changed IDs or a coarse rebuild
reason, and an off-main source-provider handle. `BridgeRefreshInputProvider`
performs repository/source reads and constructs immutable package input off-main.

BR6. Before a visible Bridge consumer acknowledges stale-content transfer, a
current-generation `BridgeCurrentnessPresentationState` must synchronously
publish a native refreshing/retrying/failed-last-known overlay. JavaScript apply
and React commit remain correlated downstream evidence, not repair
acknowledgements or render-speed claims.

### Native Display Projection Guardrail

NR1. Native SwiftUI rows consume keyed, prederived display facts from the
existing native display-projection owner. `RepoExplorerRowIndex` remains the
owner for repository/worktree rows; another high-cardinality native surface
requires an equivalently named prederived owner. Fleet-wide maps, retained-
notification scans, path normalization, and sorting cannot be hidden in row
builders or broad body recomputation. This preserves the current `List`/row-
index direction; it does not authorize a native sidebar redesign or place
native work in the Bridge slice.

### Responsiveness and Proof

PF1. Add/boot and steady-state churn are separate performance gates.

PF2. Every gate has an explicit scenario manifest: initial state, trigger,
control work, variant work, measurement start, interaction-ready point,
pressure-stop point, convergence predicate, and required evidence.

PF3. Cold boot and settled churn use otherwise-equivalent watched/no-watched
controls. Initial add does not compare discovery/import against a no-op: it uses
the equivalent one-shot scan/import control with watcher registration disabled
defined by `WF-ADD-SCALE-V1`.

PF4. The workload varies repository/worktree fleet, one versus many `.git`
writers, non-repository noise, Bridge closed/background/visible, sidebar
hidden/visible, and terminal idle/interactive/heavy-output states.

PF5. Proof reports throughput plus p50/p95/p99/max latency. Averages and event
presence cannot satisfy an interactive contract.

PF6. Terminal host-input, the terminal spec's `frameLayerPublished` precision
endpoint, and its separate native visible outcome are shared victim metrics.
Layer publication is not labeled physical presentation.

PF7. Candidate topology and Git state must equal an independent fixture-manifest
oracle after all source generations are healthy, repair debt is empty, and no
accepted-generation scan, projection, apply, or required recovery effect is in
flight. Equality normalizes canonical paths and ignores declared ephemeral IDs,
timestamps, and telemetry fields.

PF8. Instrumentation loss, trace queue drops, missing stages, and incomplete
runs fail the proof rather than making the candidate appear faster.

PF9. The shared harness defines the enumerable 34-cell mandatory core: this
child's ten watched convergence cells plus the terminal child's 24 factorial
cells. Other listed dimensions are controlled one-factor/pairwise diagnostics,
not an implicit full Cartesian product.

## Technical Contract

### Boundary / Separability Map

```text
DarwinFSEventStreamClient
  owns: OS registration, callback lifetime, loss-aware observation capture
  exposes: FSEventObservation(registrationGeneration, paths, flags, ids, time)
  does not own: scanning, routing, domain facts, canonical topology

                 bounded observations
                          |
                          v
FilesystemObservationMailbox + AdmissionDoorbell
  owns: declared-key admission, bounded custody, per-key recovery revision,
        logical leases, one payload-free level-triggered wake
  exposes: bounded contribution leases + opaque recovery revisions
  does not own: path semantics, repair policy, actor work, EventBus

                          |
                          v
FilesystemSourceGate
  owns: source currentness, semantic RepairGeneration,
        recovery lifecycle and participant acknowledgement
  exposes: accepted repair custody + source-state transitions

                          |
                          +-------------------------------+
                          v                               v
FilesystemActor / ScanScheduler                   FilesystemRootIndexSnapshot
  owns: path dedupe/reduction, fairness,            owns: canonical registered
        scan policy and bounded actor turns                ownership snapshot
  exposes: reduced hints + ScanResultSnapshot       exposes: routed path hints

                          \                               /
                           \                             /
                            v                           v
                    Filesystem / Topology Projectors
                      own: joins, diffs, filtering, stale rejection
                      expose: domain facts + TopologyApplyBatch

                               |                   |
                      semantic topics              | compact mutation
                               v                   v
                       EventBus                 MainActor atoms
                  owns: selected fact       own: canonical UI state
                  replay/fanout/lag         apply: changed keys only

Bridge subscriber
  consumes: relevant invalidation topic only
  action: enqueue generation and return
```

### Normative Filesystem Types And Owners

The following names and responsibilities are the selected architecture.
Planning maps them to files and existing symbols; it does not choose alternate
actors, queues, indexes, or persistence shapes.

#### Source identity, callback lifetime, and observation schema

```swift
enum FilesystemSourceKind: Sendable {
    case watchedParentMembership
    case registeredWorktreeContent
}

struct FilesystemSourceID: Hashable, Sendable {
    let kind: FilesystemSourceKind
    let rootID: UUID
}

struct FSEventRegistrationToken: Hashable, Sendable {
    let sourceID: FilesystemSourceID
    let registrationGeneration: UInt64
    let rootGeneration: UInt64
}

struct FSEventRecord: Sendable {
    let path: String
    let flags: FSEventFlags
    let eventID: UInt64
}

struct FSEventObservation: Sendable {
    let registration: FSEventRegistrationToken
    let capturedAt: ContinuousClock.Instant
    let totalRecordCount: Int
    let records: [FSEventRecord]
    let unionedInspectedFlags: FSEventFlags
    let firstEventID: UInt64?
    let lastEventID: UInt64?
    let captureWasTruncated: Bool
}
```

`FSEventRegistrationControlBlock` is the stable retained callback userdata. It
owns the token, lexical and resolved root aliases, dispatch queue, open/closing
state, callback leases, capture item/byte limits, and mailbox reference.
Callback entry acquires a short lease and inspects/copies only through those
limits. `unionedInspectedFlags` and event-ID watermarks describe only the
bounded inspected prefix. When the OS count/native-array shape exceeds the
inspection bound, copied count/bytes exceed their bounds, checked arithmetic
fails, or one record is oversized, callback capture records the available total
and prefix watermark without dereferencing/copying the tail, sets
`captureWasTruncated`, and synchronously advances the mailbox's conservative
recovery-required revision before returning. Any loss flag hidden in an
uninspected suffix is therefore subsumed by truncation recovery. It then offers
the bounded observation synchronously, signals the payload-free doorbell only
when requested after mailbox state is unlocked, and releases the callback
lease. It does not reconstruct an unretained client, allocate an unbounded
record array, call an actor, or create a task per callback.

Registration lifecycle is:

```text
open(token)
  -> closing(token): close admission before replacement/unregister
  -> streamInvalidated(token): stop + invalidate selected FSEvent stream
  -> callbackQueueDrained(token): dispatch-queue barrier completed
  -> leasesDrained(token)
  -> released(token)
```

Replacement closes the old generation before publishing the new one. Callback
context storage remains retained through stream invalidation, queue barrier, and
lease drain. No callback from N can be relabeled as N+1 merely because the same
worktree/root ID is registered again.

Flag disposition is exhaustive:

| Flags | Disposition |
| --- | --- |
| `MustScanSubDirs`, `UserDropped`, `KernelDropped`, `EventIdsWrapped` | exact discontinuity; create/upgrade repair debt and treat paths as hints only |
| `RootChanged`, `Mount`, `Unmount` | registration/root identity discontinuity; close currentness and require root revalidation before destructive effects |
| item create/remove/rename/modified/inode/Finder/owner/xattr/cloned/hardlink/type flags | ordinary path hints accumulated by source/root generation |
| `OwnEvent` | retained as provenance/diagnostic; never silently suppressed without separate feedback proof |
| unknown future flag | conservative discontinuity plus unsupported-flag diagnostic; never silent ordinary admission |

Disposition joins every inspected set bit rather than selecting the first
matching row. Root-identity discontinuity outranks ordinary hints; ordinary
paths remain non-authoritative hints. Unknown bits and capture truncation add
conservative recovery without replacing already-known reasons. For example,
`KernelDropped | RootChanged | ItemRenamed` requires both continuity repair and
root revalidation; rename cannot hide either obligation.

Event IDs are retained for provenance, watermark, wrap, and duplicate analysis.
Numerical gaps alone do not prove loss because FSEvent IDs are not a per-stream
contiguous sequence; loss comes from source-defined flags or gate overflow.

#### Filesystem observation mailbox

`FilesystemObservationMailbox` is a domain wrapper over the parent's
`BoundedGatherMailbox<FSEventRegistrationToken, FSEventObservation>`. It is a
synchronous lock-backed custodian, not an actor, accumulator, path set, or
repair owner. It accepts no merge/repair/footprint closures and never uses a
payload-bearing or default-unbounded `AsyncStream`.

The callback control block receives only a generation-scoped producer port and
doorbell signaler. `FilesystemActor` is the sole owner of the consumer port,
doorbell wait, lease retry/acknowledgement, seal, and post-transfer
invalidation. Lifecycle composition alone may finish the doorbell.
`FilesystemSourceGate` does not drain the generic mailbox; it synchronously
accepts recovery revisions from the actor and owns their semantic repair state.
A separate capacity-one doorbell carries no payload, key, or authority; it wakes
one long-lived drain loop. Mailbox retained state is authoritative and doorbell
signaling is level-triggered/reconstructible: binding or replacing the consumer
atomically observes retained work, and a lost/closed signal cannot strand
accepted contributions or recovery custody.

`FilesystemObservationMailbox` also owns a domain-specific, fixed-size
`FilesystemRecoveryEvidenceRegister` beside—not inside—the generic gather
primitive. It monotonically joins the exhaustive bounded reason bitset for each
source generation: continuity loss, root-identity revalidation, callback
capture truncation, callback admission overflow, and unsupported native flags.
The wrapper's short coordination lock serializes evidence registration with
generic offer/take visibility; the generic mailbox never invokes domain code or
inspects this evidence. Native recovery evidence is registered before its
observation can be contracted. If generic admission contracts the payload, the
wrapper registers callback-admission overflow and couples the returned gather
revision to the evidence revision before signaling the doorbell. A consumer
therefore never observes a recovery revision without the monotonic evidence
needed to choose the strongest applicable source repair.

The coordination critical section performs only fixed-size bitset/revision
updates plus the generic O(1) offer/take operation. Path dedupe, routing,
normalization, subtree collapse, scans, participant selection, and semantic
repair remain actor/source-gate work outside both locks. Evidence clears only
after `FilesystemSourceGate` accepts the matching revision; an older mailbox
acknowledgement cannot clear newer joined evidence.

Capacity dimensions are distinct and exhaustive:

- registered-source cardinality and exact recovery-slot cardinality;
- inspected native records, copied records, copied UTF-8 bytes, and maximum
  bytes for one copied path;
- pending plus leased callback contributions/items/bytes globally;
- pending plus leased contributions/items/bytes per registration key;
- maximum contribution/item/byte lease quantum processed in one actor turn;
- actor-owned transformed unique-path/subtree custody;
- downstream envelope count/bytes, including the independent current
  256-path-per-`filesChanged` transport chunk.

All arithmetic is checked/saturating and every hard-bound exceedance has an
exhaustive typed outcome. Global registration-capacity rejection is explicit in
the configuration receipt; partial registration cannot be reported healthy.
Ordinary global pressure never evicts another source's retained work. The
affected incoming registration contracts its replaceable pending detail and
advances its own exact `GatherRecoveryRevision`. Per-source limits prevent one
noisy root from consuming global ordinary capacity. Recovery slots remain
outside ordinary capacity and are bounded by declared registrations. Production
values are supplied by calibrated `AppPolicies`; the legacy 128 envelope queue
and downstream 256-path chunk are not source-capacity defaults.

`takeDrain` leases one source key and a bounded immutable
contribution/item/byte quantum plus its captured recovery revision without
holding a lock during filesystem work. `FilesystemActor`
owns equality dedupe, flag/reason joins, deepest-root routing, normalization,
latest/OR/count reduction, subtree/root collapse, debounce, and fair bounded
root turns. `FilesystemSourceGate` maps opaque recovery revisions and bounded
native evidence to source-kind-specific `RepairGeneration` and participant
debt. Only after the actor accepts leased observations and the source gate
synchronously accepts every captured recovery revision may mailbox
acknowledgement clear identical custody. A newer revision survives.

Retry/cancellation re-presents the identical immutable lease before newer
same-key contributions, while a retrying key rotates behind unrelated keys that
were already ready; it never merges inside mailbox state. Every drain-owner
exit path retries or leaves the outstanding lease discoverable by the
replacement owner, and consumer rebind reconstructs a wake without another
source event. Timeout-based expiry is never correctness.

Every callback that acquired a valid registration lease remains declared in its
sealed mailbox generation through stream stop/invalidation, callback-queue
barrier, lease drain, and atomic recovery transfer/disposition into
`FilesystemSourceGate`. Only then may that old key/mailbox generation be
invalidated. A late callback without a valid lease is rejected by the control
block; a leased callback that detects loss enters the old mailbox or
synchronously advances conservative old-generation recovery custody.

Topology replacement creates a fresh mailbox generation and seals the old one.
For one source, at most one current and one transferring sealed generation may
coexist. If N is transferring and N+1 is replaced by N+2, N+1 callback admission
closes immediately and its existing mailbox occupies the single current slot in
`sealedAwaitingTransfer`; N+2 is retained only as one bounded newest desired
registration identity and no N+2 stream starts yet. Valid N+1 callback leases
drain through the normal barrier/evidence path. After N transfers, N+1 becomes
the sole transferring generation; its accepted evidence/debt transfers without
being relabeled, and only then may the newest desired identity create/start a
fresh current generation. Additional desired replacements overwrite only that
bounded not-yet-authoritative desired identity. Create/start failure leaves no
new callback authority and keeps the source non-current with exact retry.
`FilesystemActor` serializes drains behind one filesystem-owner doorbell. The
source gate accepts old debt before actor acknowledgement/invalidation and never
relabels old evidence as new-generation evidence.

#### Source configuration boundary

MainActor does not drive serial register/unregister/activity calls. It submits
one immutable configuration operation:

```swift
struct FilesystemSourceConfigurationBatch: Sendable {
    let baseTopologyRevision: UInt64
    let acceptedTopologyRevision: UInt64
    let upserts: [FilesystemSourceRegistration]
    let removals: [FSEventRegistrationToken]
    let activityChanges: [WorktreeActivityChange]
    let activePaneWorktreeID: UUID?
}

struct FilesystemSourceConfigurationReceipt: Sendable {
    let acceptedTopologyRevision: UInt64
    let dispositions: [FilesystemSourceID: FilesystemSourceConfigurationDisposition]
    let currentness: FilesystemSourceConfigurationCurrentness
}

enum FilesystemSourceConfigurationDisposition: Sendable {
    case installed(FSEventRegistrationToken)
    case unchanged(FSEventRegistrationToken)
    case removalComplete
    case deferredBehindTransfer(desiredRootGeneration: UInt64)
    case rejectedCapacity
    case failedCreate
    case failedStart
}

enum FilesystemSourceConfigurationCurrentness: Sendable {
    case current
    case nonCurrent(retrySources: Set<FilesystemSourceID>)
}

enum FilesystemSourceConfigurationResult: Sendable {
    case applied(FilesystemSourceConfigurationReceipt)
    case stale(currentTopologyRevision: UInt64)
}
```

`FilesystemProjectionIndex` remains the off-main pane/worktree projection owner
and may produce this batch from accepted changed keys. Initial boot may use one
full immutable bootstrap snapshot; steady state uses changed-key batches from
the accepted topology transaction. `FilesystemActor.applyConfiguration` owns
registration/filter-load concurrency, token generation, and stale rejection.
Every requested source receives exactly one disposition; an omitted dictionary
entry is invalid. Mixed application is permitted only with explicit
`nonCurrent` retry sources, so accepted topology revision never implies watcher
authority that was not installed. Deferred, capacity-rejected, or create/start-
failed sources retain old safe authority when available and otherwise remain
visibly non-current with exact retry. MainActor applies only the returned compact
receipt/current-state mutation.

#### Persistent root ownership index

`FilesystemActor` owns one in-memory immutable
`FilesystemRootIndexSnapshot` per accepted topology revision. The snapshot is a
path-component radix trie, rebuilt off-main only when registered root identity
changes and atomically swapped after generation validation. It is derived cache,
never persisted watcher authority.

Each `RegisteredRootDescriptor` contains source/root/registration generation,
standardized lexical components, once-resolved canonical components, volume
identity/case policy, and both aliases in the trie. Incoming event routing
standardizes separators and `.`/`..` components without filesystem I/O and
selects the deepest component-complete alias match. It does not lowercase every
path, compare raw string prefixes, scan every root, or call
`resolvingSymlinksInPath()` per event.

Component comparison uses one `FilesystemPathCanonicalizer` with source-
verified volume semantics; unknown/ambiguous case, Unicode, alias, symlink, or
replacement identity rejects exact routing and creates repair debt rather than
guessing. Every routed hint carries index and registration generation and is
revalidated before destructive projection.

#### Scan scheduler and result

`WatchedFolderScanScheduler` is a dedicated actor. It owns global bounded scan
concurrency, a fair ready-root queue, and per-root state:

```text
idle
queued(pending trigger + repair obligations)
running(run generation)
runningAndDirty(run generation, newest trigger + unioned repair obligations)
```

Triggers merge by retaining the newest source/root generation and the union of
unresolved repair obligations. A hot root's follow-up reenters the fair ready
queue; it does not recursively retain a scan slot. Oldest-ready-root age and
per-root repair age are bounded/observable. Scan traversal and Git validation
run outside actor-isolated service and return through a generation-bearing
completion.

```swift
struct WatchedFolderScanRequest: Sendable {
    let source: FSEventRegistrationToken
    let repair: RepairGeneration?
    let trigger: WatchedFolderScanTrigger
    let canonicalRoot: RegisteredRootDescriptor
}

enum ScanCompletionClass: Sendable {
    case completeAuthoritative
    case partial
    case unavailable
    case cancelled
    case failed
}

struct WatchedFolderScanResult: Sendable {
    let request: WatchedFolderScanRequest
    let positiveDiscoveries: [DiscoveredRepoTopologyInfo]
    let removalCandidates: [CanonicalRepositoryIdentity]
    let completion: ScanCompletionClass
    let failures: [ScanFailureReason]
    let counts: ScanResultCounts
    let startedAt: ContinuousClock.Instant
    let completedAt: ContinuousClock.Instant
}
```

`RepoScanner` returns this exhaustive result rather than collapsing traversal,
stat, validation, timeout, cancellation, and permission failures into an empty
array. Only `completeAuthoritative` may authorize absence/removal. Partial
positive discoveries may merge while repair debt remains; negative results do
not delete last-known topology.

#### Topology projection, apply, and currentness

`FilesystemTopologyProjector` is an actor. It consumes accepted scan results,
current immutable topology/field-ownership input, and canonical revision; it
performs normalization, repository/worktree joins, pane/cache reconciliation,
and stale-result rejection off-main. It produces one `TopologyApplyBatch` with
field-scoped inserts/updates/removals, pane/cache patches, currentness, and
ordered post-apply effects.

The projector owns `WorkspaceTopologyProjectionMirror`, a rebuildable off-main
mirror of the discovery-owned repository/worktree fields, user-owned field
markers, pane associations required for orphan/reassociation, and canonical
revision. It is seeded before source admission from
`WorkspaceStateSnapshotPager`, not from a retained fleet-wide copy-on-write
dictionary. The pager acquires one `WorkspaceStateSnapshotLease` at a canonical
base revision and reads that lease's stable indexed membership and raw values in
calibrated item/byte/service-bounded pages. It retains no atom backing buffer.
Each keyed state owner preserves at most the base value or tombstone for a key
first changed while the lease is live; repeated changes do not append versions.
Every
canonical topology mutation returns a compact `TopologyProjectionUpdate` from
the same transaction; `WorkspaceTopologyApplier` sends that update directly to
the projector, which advances only through contiguous accepted revisions. It
does not subscribe to atoms or infer changes from observation. A revision gap
marks the mirror non-current and requests one new bootstrap capture; no scan
result projects against a guessed or stale fleet.

Initial bootstrap completes under a topology-admission barrier. Live gap repair
uses the same versioned lease plus the exact contiguous
`TopologyProjectionUpdate` journal that begins after the lease's base revision;
the actor applies later updates after the last page. Mutation does not restart a
live lease. A missing post-base update rejects mirror acceptance and opens a new
lease only after the current lease drains. Paging performs no
normalization, matching, sorting, filtering, or rich model composition on
MainActor. Mirror construction is off-main. Proof retains each emitted page
while measuring the next MainActor mutation so hidden copy-on-write detachment
cannot satisfy the budget.

`WorkspaceTopologyApplier` is the sole MainActor applier. It revalidates source
and base revision, commits all causally related canonical changes in one
transaction, and returns `TopologyApplyReceipt`. It replaces the topology-
mutation/reconciliation role currently performed from broad EventBus callbacks;
`WorkspaceCacheCoordinator` may retain topic-filtered Git/Forge cache applies
but does not rediscover or reconcile topology. `NotificationReducer` does not
classify filesystem or terminal source traffic; source gates already own
contraction.

Product currentness is exhaustive:

```swift
enum WatchedFolderCurrentness: Sendable {
    case discovering
    case current
    case repairing(lastKnownRevision: UInt64)
    case nonCurrentRetrying(lastKnownRevision: UInt64)
    case repairFailed(lastKnownRevision: UInt64)
    case unavailable(lastKnownRevision: UInt64)
}
```

Last-known state remains usable, but non-current/failed/unavailable state cannot
render indistinguishably from `current`. `watchRequestAccepted`,
`firstUsefulTopology`, and `repairQuiescent` retain the parent meanings and have
separate ceilings.

#### Filesystem-to-Git invalidation

`WorktreeGitInvalidationMailbox` is the only filesystem-to-Git seam. It has one
accumulator per registered worktree generation:

```swift
struct WorktreeGitInvalidation: Sendable {
    let worktreeID: UUID
    let registrationGeneration: UInt64
    let highestSourceSequence: UInt64
    let boundedRelevantHints: Set<GitInvalidationHint>
    let reasons: Set<WorktreeInvalidationReason>
    let needsFullSnapshot: Bool
    let repairGeneration: RepairGeneration?
    let lifecycle: WorktreeInvalidationLifecycle
}
```

Merge is monotonic: reasons/hints union, sequence increases, and uncertainty may
upgrade but never downgrade `needsFullSnapshot`. Register/unregister/replacement
are barriers. `GitWorkingDirectoryProjector` is the sole consumer; Git compute
does not run inline with filesystem ingress. The mailbox has no product replay
or global subscribers; only deduped Git state becomes a `gitState` fact.

#### Revisioned persistence handoff

`WorkspacePersistenceRevisionOwner` is the one process-generation-scoped
MainActor authority for persistence-affecting canonical mutations.
`WorkspacePersistenceCoordinator` is the sole caller of product datastore write
APIs. Existing `WorkspaceStore` and `RepositoryTopologyStore` observation may
request/coalesce persistence, but neither builds a bundle nor writes the
datastore directly after cutover.

Steady-state topology persistence uses one atomic change-set architecture:

```swift
struct WorkspacePersistenceChangeSet: Sendable {
    let processGeneration: UUID
    let expectedPreviousRevision: UInt64
    let committedRevision: UInt64
    let repositoryChanges: [RepositoryPersistenceChange]
    let worktreeChanges: [WorktreePersistenceChange]
    let paneChanges: [PanePersistenceChange]
    let tabChanges: [TabPersistenceChange]
    let tombstones: [WorkspacePersistenceTombstone]
}
```

`TopologyApplyReceipt` obtains the next persistence revision and constructs this
causally complete change set from the same accepted mutation; it never rereads
the fleet to discover changes. `WorkspacePersistenceCoordinator` validates
process generation/revision order, coalesces only when final-state equivalence
is proven, retains tombstones until acknowledgement, and asks
`WorkspaceSQLiteDatastore` to apply one atomic transaction. Every ordinary
non-topology autosave request also carries the revision observed after its
canonical mutation and enters this same arbiter. An older full/checkpoint write
arriving after a newer change set is rejected before datastore replacement. A
revision gap requests one authoritative checkpoint.

Checkpoint recovery is part of this architecture, not a legacy parallel path.
`WorkspaceStateSnapshotPager` captures bounded raw keyed pages for workspace,
pane, tab, repository, and worktree state through one
`WorkspaceStateSnapshotLease` at a fixed persistence revision; it never hands
off or retains a fleet-wide atom backing buffer. While paging runs, each keyed
owner retains at most one base value/tombstone for a key first changed after the
lease began, and all post-base mutations continue into the exact persistence
revision stream. They are admitted contiguously into one
`WorkspacePersistenceCompactedRange`, not retained as one journal entry per
mutation. New keys are excluded from base membership and appear in the compacted
range; removed keys remain readable at base and later apply their tombstone.
Repeated mutation of one key does not grow lease or range storage.

The range records `expectedPreviousRevision`, `committedRevision`, contiguous
covered revision count, and at most one final-state patch or tombstone per
entity key. Merge is permitted only when the next transaction's expected
revision equals the range's committed revision. Whole canonical transactions
merge atomically before becoming visible. A key absent at base and absent at
the range end is removed as net-zero; a base key absent at the end retains one
tombstone; every other key retains only its final value. Memory is therefore
bounded by unique keys whose final state differs from the base plus bounded
transaction metadata, not mutation/revision count. The calibrated item/byte
bound is proportional to base/current canonical state; exceeding the supported
canonical-state envelope marks persistence non-current and fails the workload
rather than dropping revisions or restarting indefinitely.

The current lease runs to completion under sustained mutation. A newer
checkpoint request marks one running-plus-dirty target and starts only after the
current base checkpoint commits or fails; it never cancels/restarts every page
on revision movement. The actor builds and commits the base checkpoint off-main,
then atomically applies the final-state-equivalent compacted range through the
newest committed revision. Missing revision continuity keeps durability
non-current and opens a new current-base lease; it does not overwrite or falsely
acknowledge the gap. One active lease, retained-key/byte high-water, oldest
unsaved revision age, compacted-range key/byte high-water, checkpoint age, and
dirty follow-up are bounded/observable. Boot, import,
export, non-topology coalesced autosave, and gap recovery may use checkpoints.
Ordinary topology changes may not construct a full MainActor snapshot. The
process-local revision protects queued writes; restart has no surviving stale
task and seeds a new process generation from the persisted database. SQLite
schema, transaction, and datastore ownership otherwise remain unchanged.

#### Bridge containment owner

`BridgeRefreshCoordinator` is one actor keyed by pane/repository generation. A
topic-filtered consumer calls `offer(BridgeInvalidation)` and returns. Per key it
owns `idle`, `running`, or `runningAndDirty` state, one newest dirty follow-up,
currentness, stale rejection, and exact retry. Previous content becomes
`nonCurrentRefreshing`, `nonCurrentRetrying`, or `failed(lastKnown)` before the
filesystem repair acknowledgement can transfer retry.

The filesystem-triggered refresh path admits a bounded
`BridgeFilesystemRefreshRequest`. `BridgeRefreshInputProvider` resolves the
source-provider handle and builds immutable package input, package/delta, and
the final JSON envelope off-main. MainActor captures only bounded
generation/revision/request state and performs the generation-checked WebKit
call. `BridgeCurrentnessPresentationState` applies a native overlay before the
consumer transfers retry/acknowledges non-current state. JavaScript/React apply
may be correlated but does not block filesystem repair.
All-source Bridge mutation journals, normalized React state, and list/content
virtualization remain the adjacent Bridge spec defined by the parent.

### Source Gate State

The gate is keyed by source registration and generation. It has these semantic
states, independent of concrete implementation primitives:

```text
healthy
  -- discontinuity / overflow --> dirty(repairGeneration)

dirty
  -- scheduler accepts repair --> reconciling(repairGeneration)
  -- more observations --------> dirty(newestGeneration)

reconciling
  -- new trigger --------------> reconcilingAndDirty(newestGeneration)
  -- complete current result --> awaitingAcknowledgements(repairGeneration)
  -- partial/failure ----------> repairFailed + dirty
  -- stale result -------------> unchanged; repair debt remains

awaitingAcknowledgements
  -- every declared recovery owner commits same generation --> healthy
  -- reject/failure/stale acknowledgement ------------------> dirty
  -- newer observation -------------------------------------> dirty(newestGeneration)
```

Path hints may use latest-by-key contraction. Repair debt and acknowledgement
membership are exact state and cannot be dropped, sampled, or evicted by
ordinary path pressure.

A `RepairGeneration` contains source ID/kind, registration/root generation,
loss/discontinuity watermark, trigger class, and the named recovery owners that
must acknowledge. Watched-parent membership repair and registered-worktree
content/Git/pane repair use different owner sets.

The initial owner matrix is normative:

| Source kind / discontinuity | Authoritative recovery | Required acknowledgements before `healthy` | Side effects with independent retry, not source-debt acknowledgements |
| --- | --- | --- | --- |
| synthetic watched-parent membership | current-generation complete discovery plus revision-compatible topology patch | scan scheduler acceptance; canonical topology commit; cache/pane removal reconciliation; filesystem source-registration sync; current Git baseline for added/affected worktrees | Forge enrichment, persistence durability, trace identity |
| registered-worktree content | current-generation coarse root invalidation plus consumer-owned authoritative rebuild/current-invalid state and current Git snapshot | content-repair projector; every registered content consumer captured by the repair generation; Git projector; pane/filesystem projection owner | Forge refresh, Bridge visual/render completion after its refresh owner accepts invalidation, telemetry export |
| registration/root replacement | canonical root revalidation, new registration generation, then the source-kind recovery above | registration owner plus every required owner for the replacement generation | old-generation cleanup after it can no longer affect truth |

Repository membership removal is authorized only by the watched-parent complete
scan path. A registered-worktree repair may rebuild content/Git/pane state but
cannot infer that the repository disappeared. Conversely, a topology commit
cannot declare worktree content/Git/pane repair complete without those owners'
same-generation acknowledgements.

### Registered-Worktree Discontinuity Repair

AgentStudio does not own a canonical full-file inventory. After a registered-
worktree discontinuity, the source therefore emits one generation-bearing
`WorktreeContentInvalidation`, not an invented list of every file. It contains
the repair/root generations, canonical root identity,
controlled reason, and the content-consumer set captured when repair begins. It
contains no raw path expansion.

`WorktreeContentRepairConsumerRegistry` is the actor that owns the dynamic
consumer set. Registration returns a generation-bearing
`ContentRepairConsumerToken`; replacement closes the old token before the new
one becomes visible. Starting a repair atomically snapshots the applicable
tokens and current invalidation generation. A late registrant receives the
latest current/non-current snapshot before it can publish content.

```swift
enum ContentRepairAcknowledgement: Sendable {
    case rebuiltCurrent(revision: UInt64)
    case markedNonCurrent(retry: ContentRepairRetryToken)
    case notApplicable
    case withdrawnNoRetainedState
    case transferredToReplacement(ContentRepairConsumerToken)
    case staleGeneration
    case rejected(ContentRepairRejectionReason)
}
```

Only the matching token may acknowledge. Unregister during repair must either
prove `withdrawnNoRetainedState` or atomically transfer exact retry/currentness
to a replacement token; disappearing from the registry is not an
acknowledgement. `staleGeneration` and `rejected` retain source repair debt.
The registry, not live UI discovery, decides the captured acknowledgement set.

One off-main content-repair projector owns delivery and acknowledgement. For
the same generation:

- the pane/filesystem projection owner clears any latest changed-path batch,
  advances a content-invalidation generation, and publishes a targeted
  root-invalidated state to applicable panes;
- the Git projector performs and commits a full current working-tree snapshot;
- each registered content consumer, including a live Bridge refresh owner when
  applicable, either commits an authoritative same-generation rebuild or
  atomically marks its prior product state non-current and accepts a non-
  evictable same-generation retry obligation;
- a consumer with no applicable current state acknowledges `notApplicable`
  rather than manufacturing a refresh.

The source can become `healthy` only after the projector records every captured
consumer disposition plus the pane-projection and Git commits. A transferred
retry may outlive source repair only when stale content is visibly/non-
ambiguously marked non-current and the consumer owns exact retry state. Bridge
package generation and visual rendering need not block the source consumer,
but Bridge must accept the invalidation and stop presenting the old package as
current before acknowledging. A consumer registered after the acknowledgement
set was captured receives the latest invalidation/current-state snapshot on
registration and cannot resurrect old path batches.

This contract forbids full-tree path-event replay, empty-path sentinel
overloading, and Git-only acknowledgement. Proof mutates ordinary non-Git files
during a forced discontinuity, verifies bounded one-per-root invalidation,
cleared path-derived snapshots, Git convergence, every consumer disposition,
and either authoritative consumer equality with an independent fixture manifest
or explicit non-current state with retained retry.

### Scan Result Contract

A scan result contains:

- watched-root ID and root generation;
- trigger/repair generation;
- normalized positive discoveries;
- removal candidates only when traversal was authoritative;
- completion class and structured traversal/validation failure reasons;
- encountered candidate count plus validation success, negative, timeout,
  cancellation, and failure counts;
- start/end timestamps and whether cancellation was observed.

Only the scheduler that owns the matching root generation can accept a result.
The topology projector revalidates source generation and canonical topology
revision before producing field-scoped patches. MainActor revalidates both
before applying the mutation. Recovery owners acknowledge the repair generation
only after their canonical effect commits. These repeated checks are
intentional: queueing and concurrent user mutation can make work stale at every
boundary.

### MainActor Last-Mile Apply Contract

MainActor methods in this path are mutation sinks. They may:

- validate source generation and canonical base revision;
- apply already-keyed inserts, updates, removals, and availability changes;
- update a bounded number of revisions/cursors;
- return one typed ordered post-apply effect result;
- publish already-derived presentation state.

They may not discover, normalize, join, scan, serialize, classify raw events,
own retry loops, build a full persistence snapshot, or wait inline for Bridge
work. If a mutation needs fleet context to be correct, that context belongs in
the off-main projection input and result, not in an opaque MainActor reducer.

`TopologyApplyBatch` never replaces a whole current `Repo` or `Worktree` merely
because discovery observed it. The contract distinguishes discovery-owned
fields from user-owned tags and concurrent availability/cache facts. A stale
base revision either reprojects or applies only a proven conflict-free patch.

The post-apply result names the accepted revision and changed IDs plus required
cache cleanup, pane orphaning, filesystem root/activity resync, Forge scope,
persistence, trace-identity, and repair acknowledgements. One sequencing owner
applies those effects in the declared order; failures remain observable and do
not falsely clear correctness-bearing repair debt.

The declared dependency order is:

1. Revalidate source generation and canonical base revision. Rejection exposes
   no partial mutation and schedules reprojection while repair debt remains.
2. In one bounded MainActor transaction, apply discovery-owned topology patches,
   remove invalid cache entries, apply pane orphaning/reassociation patches, and
   publish the new canonical topology revision. Observers cannot see a removed
   worktree while a pane still canonically references it.
3. Return an immutable accepted-revision effect record. Filesystem source/root
   registration, Git baseline, and pane/filesystem projection consume only this
   accepted record and reject a superseded revision.
4. Forge scope/enrichment, persistence request, and trace-identity refresh start
   only after canonical commit. They coalesce and own their own failure/retry;
   they do not roll back accepted topology or clear source repair debt.
5. The source gate clears a repair generation only after the normative owner
   matrix above acknowledges the same accepted generation. Persistence, Forge,
   Bridge rendering, and telemetry completion are not used as substitutes.

### Persistence Change-Set And Checkpoint Contract

Ordinary topology mutation produces the revisioned
`WorkspacePersistenceChangeSet` from the same accepted transaction. It does not
authorize synchronous fleet reconstruction, a retained fleet copy-on-write
snapshot, or a full workspace snapshot on MainActor. The one persistence
revision owner and coordinator arbitrate topology changes, non-topology
checkpoint requests, and datastore replacement writes. The coordinator applies
revisions atomically, retains tombstones through acknowledgement, rejects stale
checkpoint delivery, and requests the paged checkpoint path only for boot,
import, export, non-topology coalesced autosave, or a detected revision gap.

The checkpoint pager copies bounded raw keyed pages from one versioned snapshot
lease without retaining atom backing storage; normalization and datastore
bundle construction run off-main. A live lease is not invalidated by ordinary
mutation; post-base change sets advance the persisted result after the base
checkpoint commits.
The boundary records enqueue delay, every MainActor page/apply service, page
bytes/entities, first subsequent mutation service/allocation, off-main
checkpoint/change-set preparation, revision gaps, retries, and datastore
service separately.

This contract changes steady-state handoff and checkpoint preparation, not the
SQLite schema or datastore transaction/I/O owner.

### Event Topic and Recovery Contract

Topic selection uses the parent `RuntimeFactBus`/`RuntimeTopic` contract. The
existing generic EventBus machinery remains underneath, but a subscriber that
receives all topics and ignores most cases is not acceptable for a steady
production path.

This contract deliberately revises the older “topicless dumb fanout” decision.
The bus remains dumb about domain meaning, but it no longer creates queue work
for a subscriber that declared no interest in that topic. Multiple domain buses
require future measured ordering/recovery evidence and a new design decision.
The dedicated filesystem-to-Git invalidation seam is an internal composition
channel, not a second product EventBus; it transfers current-generation dirty
work directly to the Git projector and exposes only deduped product results
globally.

## Ownership Map

| Owner | Owns | Explicitly does not own |
| --- | --- | --- |
| `DarwinFSEventStreamClient` | OS stream lifecycle and complete callback capture | scan policy, topology, MainActor state |
| `FilesystemSourceGate` | semantic repair debt, currentness, and participant acknowledgements | generic mailbox drain or UI state |
| `WatchedFolderScanScheduler` | single-flight, dirty collapse, fairness, generations | scan implementation or canonical atoms |
| `RepoScanner` | bounded traversal and repository validation result | scheduling, deletion policy, state apply |
| `FilesystemRootIndexSnapshot` | topology-updated canonical ownership lookup | global fanout or pane projection |
| `FilesystemActor` | sole mailbox drain lifecycle, filesystem-domain reduction/orchestration, and fact production | MainActor mutation |
| `FilesystemProjectionIndex` | pane/worktree projection and stale rejection | source admission or UI ownership |
| content-repair projector | generation-bearing coarse invalidation, captured consumer set, acknowledgement/retry transfer | full-tree path enumeration, Git snapshots, visual rendering |
| `WorktreeContentRepairConsumerRegistry` | generation-bearing consumer registration, repair snapshot, acknowledgement and retry transfer | live UI discovery, content rebuilding |
| topology projector | immutable discovery-to-mutation diff | canonical observable state |
| domain MainActor appliers | field-scoped canonical mutations and typed post-effects | backlog, projection, I/O, serialization |
| `WorkspacePersistenceRevisionOwner` + `WorkspacePersistenceCoordinator` | one write sequence, changed sets, paged checkpoints, stale-write rejection | SQLite schema, canonical UI mutation |
| `RuntimeFactBus` | topic-aware semantic replay/fanout and diagnostics | raw samples, domain joins, UI work |
| Bridge refresh owner | invalidation collapse and package generation | blocking global consumer |
| `RepoExplorerRowIndex` / native display-projection owner | keyed/prederived row facts and stable row identity | Bridge packages, filesystem scans, view-body fleet transforms |

## Enforcement Contract

### Compile-Time Type Separation

- Raw filesystem observations cannot conform to the global domain-fact
  envelope contract.
- Ordinary changed-path hints and coarse worktree-content invalidations are
  distinct types; a discontinuity cannot be encoded as an empty/sentinel path
  batch.
- Every scan and projection request/result carries root/topology generation.
- Every topology projection carries canonical base revision and field ownership.
- Partial and complete scan results are distinct exhaustive cases.
- MainActor apply APIs accept typed mutation batches, not raw envelopes.
- Event subscriptions require explicit topics and `BusSubscriberPolicy`.
- Repair acknowledgement is typed by source kind, generation, and recovery owner.

### Architecture Lint

The repo-owned SwiftSyntax linter must approximate these rules:

- exactly one closed `PressureStreamID` manifest exists, every case has an
  exhaustive static telemetry name, and production code cannot construct a
  pressure-stream dimension from raw strings, runtime IDs, paths, or content;
- shared admission custody types cannot declare stored callback/closure fields,
  domain merge/repair/footprint algebra, or filesystem/terminal/Bridge imports;
  only domain wrappers may own semantic reduction and recovery evidence;
- production `AsyncStream` construction requires an explicit buffering policy
  or a narrow allowlisted exact/recovery contract;
- MainActor files/types cannot call `resolvingSymlinksInPath`, directory
  enumeration, Git/network/process APIs, large JSON serialization, or known
  fleet transforms without a named allowlist exception;
- production `.criticalUnbounded` subscriptions require an allowlisted owner,
  pressure diagnostic, and recovery rationale;
- MainActor persistence coordinators are flagged when they construct or
  normalize full fleet snapshots, retain atom COW backing, or bypass the paged
  capture/sole-writer contract;
- global subscribers must declare topics and cannot implement large
  ignore/default case groups for unrelated topics;
- same-bus reposting from a subscription consumer requires an allowlisted
  derived-fact contraction descriptor;
- `for` loops that post one envelope at a time are flagged when a bulk fact or
  batch API is available;
- SwiftUI row/body code is flagged for fleet dictionary snapshots, sorting,
  filtering, path normalization, JSON, regex creation, or retained-log scans.

Static lint is an approximation. Runtime latency, fairness, scan collapse, and
contraction remain benchmark obligations.

## Benchmark and Observability Contract

### Fixed Workloads

Use generated, versioned corpora and an isolated debug data root. Reuse the
standard debug app identity, marker-scoped Victoria collection, fixture repo
construction, and source-scrubbing rules. Do not touch stable/beta user state.

The shared parent harness owns one run identity and acceptance report. This
child contributes the following coverage dimensions; they are divided into a
small mandatory core matrix and controlled one-factor/pairwise diagnostics, not
multiplied into one full Cartesian product.

| Dimension | Values |
| --- | --- |
| fleet | 10, 100, and 300 repositories/worktrees |
| watch mode | prepopulated control; identical persisted watched parent |
| phase | initial add; cold boot; settled steady-state churn |
| churn | one worktree; many `.git` writers; non-repository noise |
| UI | terminal only; sidebar visible; Bridge background; Bridge visible |
| terminal | idle; deterministic echo/cursor; saturated output |

Warmups and measured trials use identical fixture shapes and build settings.
Trials do not run competing benchmarks in parallel. Report medians for stable
throughput comparison and tail distributions for interaction/fairness.

The shared mandatory core has ten watched convergence cells on the selected
product build, in addition to the terminal child's 24 factorial cells:

| Scenario ID | Fixed workload | Cells |
| --- | --- | --- |
| `WF-ADD-SCALE-V1` | 10, 100, and 300 one-repository/one-worktree fixtures; at each size, one watcher-disabled authoritative one-shot scan/import control and one user-equivalent watched-parent add variant | 6 |
| `WF-COLD-BOOT-V1` | identical persisted 300-repository/worktree topology; no-watched-parent control and persisted-watched-parent variant | 2 |
| `WF-HUGE-STEADY-V1` | one local canonical parent containing 300 settled repositories/worktrees; identical watcher-disabled control and watched variant execute 32 concurrent count-driven `.git` writers on distinct worktrees, 256 ordered mutation batches per writer, plus one count-driven non-repository producer with 8,192 mutations | 2 |

All ten cells hold sidebar hidden, Bridge closed, and one deterministic echo/
caret victim terminal. `interactionReady` is recorded before the watched/add,
boot-pressure, or churn trigger and always satisfies the parent's terminal-
bearing definition; no nonterminal readiness marker reuses that name. All
mutation traces, seeds, operation
counts, fixture shape, and build/configuration identities are versioned and
digest-recorded. `WF-HUGE-STEADY-V1` starts pressure only after topology/source
health and the interaction-ready marker; pressure stops after every count-
driven producer acknowledges its final operation. Its completion predicate is
all current source generations healthy, no repair debt or accepted-generation
work in flight, and the independent topology/Git/content-consumer oracle equal
or explicitly current-invalid-with-retry as allowed by the repair contract.

The terminal child's loaded-workspace and combined-pressure rows use the
watched variant of `WF-HUGE-STEADY-V1` as composite stress gates. Idle/no-watch
and terminal-pressure/no-watch rows are not watcher-factor controls and no
watcher attribution is made from those comparisons. The selected-product-build
pair in this child is the sole watcher-factor comparison because its control
executes the identical writers/noise trace with watching disabled.

Each phase also has a scenario contract:

| Phase | Initial state | Control | Variant | Completion |
| --- | --- | --- | --- | --- |
| initial add (`WF-ADD-SCALE-V1`) | empty canonical topology plus generated fixture manifest | one-shot authoritative scan/import with watcher registration disabled | user-equivalent watched-root add | accepted topology revision, required effects acknowledged, healthy source |
| cold boot (`WF-COLD-BOOT-V1`) | identical persisted topology and fixture | no watched parent | persisted watched parent | interaction ready plus healthy/converged background state |
| steady churn (`WF-HUGE-STEADY-V1`) | identical settled topology | exact writers/noise trace with watch disabled | same trace with watch enabled | producers stopped, all repair debt cleared/transferred per contract, independent oracle equal |

Every scenario names exact start, interaction-ready, pressure-stop, and
convergence markers. A control that skips the useful work performed by the
variant cannot support a relative regression claim.

### Stage Ledger

Every run records:

```text
source       callbacks, inspected/copied/truncated records, paths/bytes, flags, registrations
admission    offered/admitted/contracted/rejected, pending+leased custody, oldest age, recovery revisions
reduction    gathered inputs, equality duplicates, unique paths, subtree/root contractions, outputs
scan         triggers, starts, dirty collapses, follow-ups, outcomes, duration
routing      roots, paths, unique/projected/suppressed, queue wait, service
content      coarse invalidations, captured consumers, rebuild/current-invalid/retry acknowledgements
topology     snapshot size, changed keys, stale results, MainActor apply
git          logical/physical reads, active/background fairness, dedup
event bus    posts by topic, deliveries, replay, drops, high-water lag
bridge       invalidations, refreshes, full/delta packets, critical wait
render       native display-projection rebuilds and row/body recomputes; Bridge apply/commit where enabled
persistence  request, MainActor capture, entities copied, preparation, datastore
interaction  input handoff, frame-layer publication, native visible outcome, pane switch
```

The contraction report includes:

```text
source observations
  -> admitted keys / repair obligations
  -> scans
  -> domain facts
  -> subscriber deliveries
  -> MainActor mutation batches
  -> Bridge pushes / UI commits
```

Every expansion greater than one requires a product reason in the run report.
The final record also contains the fixture-manifest oracle, compared normalized
fields, source/repair quiescence predicate, expected-stage manifest, admitted/
recorded/dropped counts, sequence gaps, evidence drain outcome, and run-validity
decision. It is non-evictable or written out of band from the measured lossy
trace queue.

### Proof Expectations

Deterministic proof must cover:

- admission saturation with bounded memory and preserved repair debt;
- callback admission touching only one source slot and maintained counters at
  1/100/300 registrations, with no payload/domain closure, fleet scan/copy,
  actor call, or per-callback task;
- exact-bound/bound-plus-one, integer-near-maximum, oversized-single-path,
  duplicate-heavy, pending-plus-leased, per-source noisy/global quiet, and
  recovery-slot-outside-ordinary-capacity cases for every declared limit;
- level-triggered doorbell and lease custody across cancellation before take,
  after take, during processing, before acknowledgement, and consumer rebind,
  without another source event or timeout expiry;
- one current plus one transferring sealed generation under repeated
  replacement, including stream create/start failure, delayed callback, queue
  barrier, callback lease drain, debt transfer, and shutdown;
- one oversized callback is bounded before record-array construction and
  atomically creates repair debt;
- bounded native prefix inspection across count/array mismatch, uninspected
  tail, unknown bits, arithmetic overflow, and every joined combination of
  FSEvents discontinuity/root/item flags;
- source-kind repair matrices and acknowledgement failure after a successful
  scan;
- registered-worktree discontinuity during ordinary non-Git changes produces
  bounded coarse invalidation, clears path-derived snapshots, transfers exact
  current-invalid retry where needed, and cannot become healthy after Git-only
  acknowledgement;
- single-flight and exactly one dirty follow-up under a trigger burst;
- partial traversal, partial validation, timeout, cancellation,
  permission-denied, root-missing, and stale scan results;
- no false removals from incomplete results;
- canonical path containment across nested roots, relative paths, `..`,
  symlinks, case variation, and stale registrations;
- changed-key topology apply, canonical revision conflict, user-tag preservation,
  ordered post-effects, and stale-generation rejection;
- topic filtering before subscriber queue admission;
- exactly one global `RuntimeFactBus` exists; retained pane runtime channels are
  local-only and no production path posts `RuntimeEnvelope` globally;
- internal filesystem-to-Git invalidation creates no global replay/fanout and
  only deduped Git/product facts reach global topics;
- EventBus lag/drop/pressure export with safe dimensions;
- Bridge invalidation enqueue without critical-lane waiting;
- filesystem Bridge refresh captures bounded request state independent of
  package size, builds input/envelope off-main, and applies the native
  non-current overlay before repair acknowledgement;
- native keyed/prederived row projection remains separate from Bridge and view-
  body fleet transforms are rejected by structure plus recompute evidence;
- bounded MainActor persistence capture with off-main snapshot normalization;
- stale checkpoint/full-save delivery after a newer topology change set cannot
  overwrite it, and all datastore writes pass one revision arbiter;
- a revision-gap checkpoint completes while count-driven concurrent mutations
  continue, then applies contiguous post-base changes without restart
  starvation; maximum unsaved revision/checkpoint age remains within its
  approved bound;
- the same workload proves post-base retention is bounded by unique final-state
  keys/bytes rather than mutation count, including repeated updates and
  create/remove net-zero churn;
- retained bootstrap/checkpoint pages do not force a fleet-sized copy in the
  first subsequent MainActor mutation;
- final topology/Git equivalence with an independent fixture-manifest oracle;
- 300 ready sources with one continuously noisy source, bounded root-turn
  service for every quiet ready source, and zero unresolved quiet-root debt at
  quiescence;
- forced trace-queue loss invalidating the run through independent evidence
  accounting;
- terminal interaction fairness during the watched-parent variant.

Profiling/sample capture runs separately from latency gates so profiler overhead
does not contaminate the claimed latency distribution.

### Requirements / Proof Trace

| Requirement group | Contract | Proof modality | Owning slice |
| --- | --- | --- | --- |
| WF1-WF10 | source gate, flag disposition, repair generation, consumer registry | deterministic callback/loss/state/registration-race tests plus pressure metrics | source admission |
| WS1-WS9 | scan scheduler and authoritative completion | injected scanner/clock tests plus fixture traversal | scan scheduling |
| FI1-FI7 | canonical containment and authority | path/property cases plus external-link/non-local fixtures | root ownership |
| TA1-TA11 | revisioned patch apply, post-effects, persistence handoff | race/state tests, MainActor spans, scaling workload | topology apply |
| EV1-EV12 | topic-aware semantic transport | structural lint/tests, replay/order/lag pressure plus internal-channel isolation | semantic transport |
| BR1-BR6 | enqueue-only global boundary, bounded input, visible currentness | focused coordinator/Bridge integration plus stage traces | Bridge containment |
| NR1 | keyed/prederived native display input | architecture lint plus native row-index/recompute proof | native display projection |
| PF1-PF9 | scenario/oracle/evidence validity | shared native workload and acceptance report | shared harness |

## Security and Trust Context

Watched folders are user-authorized scopes, not trusted contents. A local
process can generate adversarial event rates, path shapes, repository trees,
symlink changes, and transient access failures.

Assets are canonical repository/worktree identity, user-owned tags and
availability, watcher authority, pane/worktree association, filesystem and
Forge scope, interaction availability, and trustworthy local proof. Entry
points are FSEvent callbacks/flags, scanned directory entries, `.git` files and
metadata, validation responses, persisted watched roots, repair
acknowledgements, and generated workload fixtures.

Privileged effects include establishing absence, removing or marking topology
unavailable, registering a watcher, orphaning a pane, changing filesystem/Forge
scope, and clearing repair debt. Only the typed owner and current generation/
revision contracts may authorize those effects.

- Canonical host-owned root identity decides attribution.
- `.gitignore` is a projection policy, not an authorization boundary.
- A failed or partial scan cannot destructively establish absence.
- Local canonical roots are initially authoritative. Non-local/removable/
  permission-volatile unavailability is non-destructive until explicitly
  supported.
- Git metadata outside the selected canonical subtree is identity evidence, not
  automatic watcher authority.
- OTLP exports only safe aggregate counts, durations, controlled reason enums,
  deterministic repo/worktree hashes, and bounded dimensions. Raw paths,
  roots, UUIDs, errors, prompts, payloads, and terminal content remain local.
- Instrumentation itself is bounded and cannot become a second high-volume
  event pipeline.

## Alternatives and Tradeoffs

### Minimal: keep current topology and add only scan debounce

Gain: small diff and fast delivery.

Cost: leaves unbounded callback admission, lost overflow flags, partial-scan
false-removal risk, per-batch root-index rebuild, quadratic MainActor import,
topicless fanout, and opaque MainActor scheduling. Rejected because it cannot
satisfy correctness or interaction requirements.

### Clean boundary: separate buses and owners for every domain

Gain: strongest type separation and independent backpressure.

Cost: broad migration, duplicated transport mechanics, and potential ordering
complexity before measured need. Deferred as the default shape; typed topics
and pressure contracts provide most of the separability without requiring a
bus per event family.

### Pragmatic selected direction

Keep current proven projection/datastore actors and explicit subscriber
policies. Add the bounded loss-aware mailbox, dedicated fair scan actor,
persistent path-component root index, immutable revisioned topology projector,
field-scoped `WorkspaceTopologyApplier`, revisioned change-set/checkpoint
persistence, accumulated FS-to-Git mailbox, topic-aware fact fanout, and
`BridgeRefreshCoordinator`. This is a hard semantic cutover at each touched
boundary; no old/new dual event path remains indefinitely.

Tradeoff: more explicit types and generations. The added ceremony is accepted
because it makes overflow correctness, stale rejection, queue ownership, and
MainActor work reviewable and independently testable.

## Non-Goals

- No implementation sequence, task graph, or exact validation command list.
- No claim that static analysis proves the dominant live hotspot.
- No actor-per-pane migration.
- No replacement of `FilesystemProjectionIndex`.
- No Git status provider rewrite or return to shell Git.
- No full Bridge package/React redesign in this spec.
- No native sidebar visual redesign.
- No SQLite schema or datastore-actor redesign. Bounded paged raw-state capture,
  the global persistence revision arbiter, and off-main preparation remain in
  scope; retained fleet-wide MainActor snapshots do not.
- No new watcher authority outside persisted user-selected roots.
- No copied Ghostty buffer sizes, spin constants, or gather timings.

## Slice Routing Map

These are separable ownership contracts, not implementation phases:

| Slice | Maintained contract |
| --- | --- |
| source admission | FSEvent observation, capacity, flags, repair debt |
| scan scheduling | single-flight, dirty collapse, completeness, generations |
| root ownership | topology-updated canonical index and path containment |
| content repair | coarse root invalidation, captured consumer acknowledgement, exact retry transfer |
| topology apply | immutable diff plus bounded MainActor mutation |
| semantic transport | topics, replay admission, lag/pressure export |
| coordinator fairness | explicit scheduler and named domain appliers |
| Bridge containment | enqueue-only global boundary and refresh ownership |
| native display projection | keyed/prederived row inputs and render-loop guardrail |
| workload proof | fixed corpus, stage ledger, final-state and interaction gates |

The Ghostty callback, terminal sample, agent-state, geometry, and presentation
contracts are owned by the companion terminal-interaction spec.

## Calibration And Revisit Gates

The architecture is closed. These remaining values are calibrated before
candidate acceptance:

| Gate | Owner / evidence | Required disposition |
| --- | --- | --- |
| source registration, native-inspection/copy, per-source/global pending+leased custody, lease-quantum, transformed-path, and downstream-envelope limits | performance owner using fixed burst/overflow workloads | each distinct bounded value appears in the calibration manifest; ordinary overflow advances exact affected-source recovery custody and never borrows the legacy 128 or downstream 256 constants |
| scan concurrency, `maximumAttendedPriorityBurst`, and per-turn work quantum | performance owner using mixed hot/cold root fixtures | values are frozen in `AppPolicies`; the invariant `(R + 1) * (P + 1)` root-turn bound passes and one root cannot monopolize slots |
| root-index rebuild and memory envelope | filesystem performance owner using scale/case/symlink fixtures | component-trie routing remains component-bound and rebuild stays outside MainActor |
| absolute and control-relative interaction/currentness ceilings | human owner from baseline/control distributions before candidate acceptance | no done claim until approved; stale/non-current beyond its ceiling is failure |
| per-operation MainActor service/scaling ceilings | human/performance owner from fixed changed-key work across 10/100/300 fleets | topology apply, persistence page, Bridge capture/WebKit send, and first post-page mutation each pass independently of end-to-end latency |

The first cut keeps one physical FSEvent stream per registration behind the
mailbox; stream consolidation is not a planner option. Revisit it only when
measured duplicate delivery, stream count, CPU, or drop rate materially violates
the approved workload. The path-component radix trie, positive-only partial
merge with retained repair debt, internal accumulated FS-to-Git mailbox,
revisioned change-set persistence, local-root authority, non-destructive non-
local behavior, and external Git-link authority are resolved here. Changing
them requires spec reconvergence.

## Design Decision

This revision selects generation-safe FSEvent registrations, the bounded source
mailbox, persistent component trie, fair scan actor, exhaustive scan results,
off-main topology projector, typed MainActor applier, exact repair
acknowledgement, accumulated FS-to-Git invalidation, revisioned persistence,
currentness states, Bridge containment, and enumerable scenario controls. It
passed fresh adversarial spec review and is ready for implementation planning.
Runtime dominance and final human-approved ceilings remain proof obligations,
not planner assumptions.
