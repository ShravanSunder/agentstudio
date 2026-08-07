# Off-Main Materialization and Lifecycle — Program Design

Governing Requirements:
[Reactive State System Requirements](2026-07-31-reactive-state-system-requirements.md)

Governing Specification:
[Reactive State System Specification](2026-07-31-reactive-state-system-specification.md)

## Implementation Boundary

This document governs PR 2 only:

```text
total cancellation-only eager/off-main EagerDerivedAtom
  └── Tab Bar projection and current-result publication
```

In scope are the total cancellation-only eager primitive, synchronous source
revocation, immutable Tab Bar request capture, pure Core/Inbox projection
policies, off-main fleet reconstruction and equality, current-result admission,
the existing one-time typed host, explicit shutdown, and the smallest
static/semantic/native/performance proof required by this slice.

This PR does not migrate Repo Explorer or Inbox workers, add a fallible eager
branch, change pane-title or persistence authority, implement pane/tab source
families, change Command Bar, split targets, or add a scheduler, worker pool,
retry system, second projection path, or parallel proof framework.

Later sections retain family-wide lifecycle and measurement context. For this
goal, descriptions of existing workers, one-shot preparation, future fallible
adopters, Command Bar, or unrelated infrastructure are non-governing. Only
measurement corrections required to prove this Tab Bar slice may change, and
they remain part of PR 2 rather than a separate implementation slice.

## 1. Decision Summary

AgentStudio will use one narrow reusable lifecycle for replaceable,
CPU-oriented eager derivations:

```text
MainActor source capture
  -> immutable Sendable request with bounded freshness identity
  -> one retained latest-wins task
  -> detached cancellable computation
  -> MainActor freshness admission
  -> equality-gated observable output
```

The reusable primitive owns only one current request, one task, stale-result
rejection, and one materialized output. It is not a task runtime: it has no
queue, worker pool, retries, priority policy, dependency discovery, polling,
service lookup, or persistence behavior.

Product code remains responsible for:

- declaring which source reads form the request;
- constructing an immutable `Sendable` request plus a compact bounded identity;
- implementing pure cancellable projection logic;
- defining the semantic output comparator;
- selecting telemetry through the existing trace tags.

The selected primitive is total apart from cooperative cancellation. A future
fallible product migration must return to Program Design with its product-owned
failure policy before the generic contract gains failed or stale-result states.

One-shot preparation remains structured work owned by its caller and does not
use the latest-wins primitive.

The generic primitive is named
`EagerDerivedAtom<Request, RequestIdentity, Value>`. Together with the sibling
lazy `DerivedAtom<Value>`, the type name makes execution mode visible at
construction and review.

## 2. Structural Crux

The crux is how to guarantee that variable-cost work leaves `MainActor`
without turning every asynchronous operation into a generic orchestration
system.

Current Repo Explorer and Inbox implementations correctly separate capture,
worker execution, cancellation, generation admission, and publication. They
repeat that lifecycle locally. Tab Bar still performs variable-cardinality
fleet reconstruction on `MainActor`.

The selected design extracts only the repeated replaceable-projection
mechanics, then proves it first on Tab Bar. Existing correct feature-local
workers do not migrate merely for uniformity.

### 2.1 Alternatives considered

| Alternative | Benefit | Cost and failure mode | Disposition |
|---|---|---|---|
| Leave every feature to hand-roll task and generation lifecycle | No shared abstraction | Repeated cancellation/admission mistakes remain easy | Rejected for new replaceable projections |
| Build a general task scheduler/runtime | Central policy and queues | New lifecycle authority, complexity, target coupling | Rejected |
| Put variable computation on an actor | Serialization | Does not prove work leaves `MainActor` or provide latest-wins admission | Rejected as the execution guarantee |
| Use unretained detached tasks | Off-main execution | No lifecycle, shutdown, or stale-result ownership | Rejected |
| One constrained latest-wins materialized node | Reuses the exact common semantics while product workers stay explicit | Supports only replaceable CPU projection | Selected |

The constrained primitive should be replaced or widened only if a second
proven workload needs a different ordering policy. It must not accumulate
generic queues, retries, backoff, persistence, or arbitrary job features.

## 3. Current-System Model

### 3.1 Repo Explorer

Current control flow:

```text
observed source or debounced query changes
  -> build RepoExplorerProjectionRequest on MainActor
  -> compare semantic request
  -> cancel and replace retained orchestration task
  -> actor worker creates detached CPU task
  -> forward cancellation
  -> check generation and request facts on MainActor
  -> publish projection and row index
```

This is a valid replaceable-live-projection model. Its source-capture
observation gap is handled by the sibling reactive-atoms design.

### 3.2 Inbox

Inbox uses the same broad lifecycle shape for notification grouping, sorting,
filtering, row indexing, and repo presentation. It already rejects superseded
results by generation and complete key.

### 3.3 Tab Bar

`TabBarAdapter.observeStore()` watches broad pane, tab, zoom, enrichment, and
notification inputs. Every admitted change calls `refresh()`, which maps all
tabs and reconstructs display titles, arrangements, pane visibility,
minimized counts, zoom state, and notification colors on `MainActor`, then
assigns the complete `tabs` array.

```mermaid
flowchart LR
    Mutation["Any observed pane/tab/enrichment/notification change"]
    Wake["TabBarAdapter observation wake"]
    Build["MainActor rebuild every TabBarItem"]
    Assign["Unconditional tabs assignment"]
    UI["SwiftUI tab bar invalidation"]

    Mutation --> Wake --> Build --> Assign --> UI
```

The exact runtime severity is unproven, but the variable-cardinality
MainActor topology directly conflicts with the governing execution boundary.

### 3.4 One-shot preparation

Workspace restore uses structured `async let` preparation and one atomic
MainActor admission. No newer request supersedes it. It must remain separate
from the replaceable latest-wins model.

### 3.5 Current-to-target Tab Bar call-path delta

| Status | Entrypoint-to-effect edge | State/result/error behavior | Evidence or obligation |
|---|---|---|---|
| Removed | Observed source change -> `TabBarAdapter.refresh()` -> map every tab on `MainActor` -> unconditional `tabs` assignment | Variable-cardinality reconstruction and output equality leave the interaction actor. | Current `TabBarAdapter.swift`; RS-09, RS-12 |
| Added | Observed source change -> bounded `Sendable` request capture -> retained `EagerDerivedAtom` -> detached product projector | One successor replaces one retained task; cancellation is cooperative resource control. | C3, RS-09–RS-12 |
| Added | Projector completion -> generation/request-identity admission -> equality-gated materialized output | Superseded completion is discarded; equal current completion advances request identity without changing output revision. | C3, RS-09, RS-13 |
| Changed | Adapter-owned `tabs` and `activeTabId` stores -> one forwarded `TabBarProjection` | Items and active identity publish coherently from one materialized owner; total projection has no product failure branch beyond cancellation/shutdown. | RS-03, RS-14, RS-28 |
| Intentionally unchanged | Controller constructs one `CustomTabBar` and one typed `DraggableTabBarHostingView` | Before first current output, the existing view observes an absent projection and presents no authoritative tab items or active selection; normal Observation publication updates the same host. | Current `PaneTabViewController.makeTabBarHostingView()`; RS-14, RS-28 |
| Intentionally unchanged | Materialized output -> `CustomTabBar`; overflow and drag/drop geometry remain adapter-owned | Existing UI interaction and bounded geometry work stay on `MainActor`. | Current `CustomTabBar`/adapter boundary; RS-28 |

## 4. Target Components and Ownership

| Component | Owner | Responsibility |
|---|---|---|
| Product source observer/capture | Product surface owner on `MainActor` | Observe declared source facts and build the current immutable request plus bounded identity |
| Product request | Product module | Carry only `Sendable` source facts plus a compact bounded semantic or freshness identity |
| `EagerDerivedAtom<Request, RequestIdentity, Value>` | Generic Infrastructure primitive, instantiated and retained by product owner | Own current generation, retained task, output cache/revision, cancellation, and freshness admission |
| Product projector | Product module, nonisolated pure computation | Transform a request into a result with cooperative cancellation |
| Observable publication | Materialized node on owning actor | Publish only current, semantically changed bounded output |
| Product UI adapter/view | App or Feature | Observe already materialized output and own ephemeral UI state only |

```mermaid
flowchart TD
    Source["Core/Feature source atoms"]
    Capture["Product capture owner<br/>MainActor"]
    Node["Materialized derived node<br/>MainActor lifecycle"]
    Worker["Product projector<br/>detached Sendable computation"]
    Output["Observable compact output"]
    UI["UI consumer"]

    Source -->|push invalidation| Capture
    Capture -->|Sendable request| Node
    Node -->|retained cancellable task| Worker
    Worker -->|result + generation| Node
    Node -->|current and unequal only| Output
    Output --> UI
```

## 5. Dependency Direction

Infrastructure owns generic lifecycle mechanics and may not name product
requests, results, atoms, UI types, `CoreAtoms`, `AtomRegistry`, or Feature
state.

Core and Features may define requests and pure projectors using Infrastructure.
App may compose Core and Feature facts into an App-owned materialized result,
such as Tab Bar presentation.

The generic node does not observe `CoreAtomScope` and cannot discover its own
dependencies. The product capture owner supplies every request explicitly.

## 6. `EagerDerivedAtom` Contract

The reusable node is a stable `@MainActor` object parameterized by a
`Sendable` request, compact request identity, and output. Its package interface
has this structural shape:

```text
EagerDerivedAtom<
  Request: Sendable,
  RequestIdentity: Equatable & Sendable,
  Value: Sendable
>
  init(
    requestIdentity: @Sendable (Request) -> RequestIdentity,
    isValueEqual: @Sendable (Value, Value) -> Bool,
    project: @Sendable (Request) throws(CancellationError) -> Value
  )
  nonisolated sourceDidInvalidate()
  admit(request)
  stop()
  value: Value?
  freshness: idle | running(RequestIdentity) | invalidated(RequestIdentity) | current(RequestIdentity) | stopped
  revision: Int
```

The node uses one fixed user-interaction execution priority rather than
exposing scheduling policy. Product code cannot configure queues, retries, or
parallelism through this interface.

`sourceDidInvalidate()` is the one synchronous bridge from a leading-edge
Observation callback. It advances a small lock-protected revocation epoch and
is safe to call before the callback schedules post-mutation MainActor capture.
It neither captures product state nor starts work. This closes the interval in
which source state has changed but the successor request cannot yet be built.

### 6.1 Admission

The product owner submits:

- an immutable request;
- a compact fixed-cardinality semantic or freshness identity;
- a `@Sendable` CPU projection closure over that request;
- semantic output equality.

The projector accepts only cooperative `CancellationError` as an early exit and
has no failure-policy argument or failed state.

The owning actor compares only the compact identity, never the
variable-cardinality request or output. Submitting an equal request is a no-op
while that request and its revocation epoch are still running or current. After
`sourceDidInvalidate()`, the next admission is a successor even if a product
mistakenly reuses its compact identity. Submitting a successor:

1. advances the generation;
2. marks any previous output as non-current for the new request;
3. cancels the retained prior task;
4. retains one replacement task.

Admission associates the request with the current revocation epoch. A source
invalidation after admission makes that association stale immediately, even
before a successor reaches `admit(request)`.

### 6.2 Execution

The generic node executes the synchronous CPU projector inside one internally
owned detached task. Request, result, and closure transfer must satisfy Swift
6 concurrency checking.

The task also receives the previously published `Sendable` value, when one
exists. It computes the candidate and performs any variable-cardinality
semantic output comparison off-main. The completion returned to `MainActor`
contains the candidate, its compact request identity and generation, and the
already-computed equality outcome. No MainActor comparison scales with tabs,
panes, rows, files, or result count.

The projector:

- cannot capture `MainActor` product state;
- receives all input through the request;
- performs no UI or atom mutation;
- checks cancellation at bounded intervals in variable-cardinality loops;
- returns one complete `Sendable` result or throws.

This structure makes off-main execution a property of the paved path rather
than a convention at every call site. Async I/O workflows do not use this
primitive; their owning subsystem retains explicit structured or actor-owned
lifecycle.

### 6.3 Publication

Completion returns to the owning actor. The node publishes only if:

- the task was not cancelled;
- its generation and semantic/freshness request identity are still current;
- its admitted revocation epoch still matches the current source epoch;
- the result is complete;
- the off-main semantic comparison reports that the result differs.

A stale or equal result may update aggregate-safe telemetry but does not change
the output revision or wake output-only consumers.

For an equal current result, lifecycle freshness advances to the admitted
request identity without replacing or republishing the equal value. Freshness
bookkeeping is separate from output-only observation.

Lifecycle status and output observation are separate. A UI that reads only the
materialized output does not wake merely because task bookkeeping changed.

## 7. Lifecycle State

```mermaid
stateDiagram-v2
    [*] --> Idle
    Idle --> Running: admit request N
    Running --> Running: admit request N+1 / cancel N
    Running --> Invalidated: sourceDidInvalidate / revoke N
    Running --> Current: N completes current and unequal
    Running --> Current: N completes current and equal / preserve output revision
    Current --> Invalidated: sourceDidInvalidate / preserve renderable value
    Invalidated --> Invalidated: sourceDidInvalidate or stale completion / revoke or discard
    Invalidated --> Running: admit successor
    Invalidated --> Stopped: owner stop
    Current --> Running: admit successor
    Running --> Stopped: owner stop / cancel retained task
    Current --> Stopped: owner stop
```

The state records the request identity associated with every retained output.
A prior value may remain renderable while a successor runs, but it is never
represented internally as current for that successor.

Cancellation caused by a newer request does not become a terminal failure.
Cancellation with no successor during owner shutdown publishes nothing.
`stop()` is idempotent and irreversible: it cancels retained work, rejects
future admissions, and prevents every later completion from publishing.
Successor admission owns ordinary task cancellation; there is no public
reusable `cancel()` operation whose terminal meaning callers must guess.

## 8. Total Projection Boundary

The Tab Bar projector is total over an accepted `TabBarProjectionRequest`; its
only early exit is cooperative cancellation.
Existing tolerant title, arrangement, and active-tab fallbacks are part of that
total projector.

While a successor runs, the node keeps the previous `TabBarProjection`
renderable with its original request identity so navigation does not blank.
That is successor continuity required by RS-28, not a policy for retaining a
failed result. A future genuinely fallible surface must obtain a product failure
decision and a focused Program Design before the generic primitive gains a
fallible constructor or failed/stale lifecycle states.

Repo Explorer and Inbox retain their current product behavior until separately
migrated. Their current output/request-key relationship must be made explicit
before adopting the generic node.

## 9. Target Tab Bar Flow

### 9.1 Title semantics remain unchanged

The first Tab Bar slice changes where display projection runs. It does not
change title authority, precedence, events, or durability. The pure Core
projector and the current actor-bound readers must produce the same title for
the same captured facts:

1. accepted terminal `.titleChanged` and `.tabTitleChanged` events continue to
   update runtime metadata, remain available to replay, and satisfy the current
   IPC title-change wait behavior;
2. a normalized user-defined tab name continues to override pane runtime
   titles;
3. a worktree-backed pane continues to use its repository/worktree label ahead
   of terminal metadata;
4. a pane without either override continues to use its trimmed runtime title
   or the existing `Terminal` fallback; and
5. pane-title metadata continues through the current workspace-persistence
   behavior.

This slice does not decide whether runtime titles should remain durable pane
metadata or whether inactive-arrangement ownership should change. Either change
would alter observable compatibility and persistence behavior and therefore
requires a separate Requirements and Specification decision before Program
Design. Title parity is a hard cutover gate, not an invitation to preserve two
projection implementations.

### 9.2 Request capture

`TabBarAdapter` is the window-scoped App bridge, materialization owner, and
ephemeral UI owner. The App window factory constructs one adapter for each
`MainWindowController` from process-owned Core, Feature, and action
dependencies; it does not retain one observing adapter across controller
replacement. The adapter's source-observation closure captures a
`TabBarProjectionRequest` containing:

- tab shells, tab graph, arrangement cursors, and active-tab identity;
- pane graph and drawer facts required for display;
- topology and repo-enrichment source facts read inside the registered
  Observation boundary and copied into immutable snapshots;
- zoom presentation facts;
- a Feature-owned immutable Inbox attention-fact snapshot;
- one adapter-owned monotonic `TabBarProjectionGeneration`.

The request crosses ownership through three concrete product interfaces:

```text
CoreTabBarProjectionRequest: Sendable
  captured tab, pane, arrangement, topology, enrichment, and zoom facts

CoreTabBarProjector.project(CoreTabBarProjectionRequest)
  -> CoreTabBarProjection: Sendable
     tab identity, titles, arrangement labels/badges, pane visibility,
     minimized count, zoom facts, and active-tab identity

InboxAttentionProjector.project(
  InboxAttentionFactSnapshot,
  groups: [OpaqueGroupID: Set<PaneID>]
) -> [OpaqueGroupID: InboxAttentionLane]
```

Core owns the title, pane-display, arrangement, and zoom policies currently
reached through `TabDisplayDerived`, `PaneDisplayDerived`, and
`ArrangementDerived`. Their reusable policy operations become pure
`nonisolated` functions over the captured Core request; existing MainActor
readers may call the same functions for other surfaces. App does not copy those
rules. Inbox owns attention eligibility and precedence behind its snapshot and
pure projector. App owns only capture, opaque tab grouping, mapping Inbox lanes
to `TabNotificationDotColor`, and assembly of the final `TabBarProjection`.

MainActor capture reads stored value collections using copy-on-write snapshots
and does not reconstruct `TabBarItem` values. Any request-building step whose
work grows through the input fleet is moved into the projector unless it is the
unavoidable bounded capture of a stored collection reference.

`TabBarProjectionGeneration` is the compact admitted-request identity for this
slice. The adapter advances it once for the initial admission and once for each
coalesced `withObservationTracking` callback before capturing the newest source
facts. The same callback first calls `sourceDidInvalidate()` synchronously,
then schedules the post-mutation MainActor capture required by Observation's
leading-edge semantics. Source owners already suppress equal writes; the
adapter does not hash or structurally compare fleet snapshots on `MainActor`.
Several source publications that arrive before callback handling revoke the
old request immediately but produce one new capture of the latest state and
one generation. Re-admitting the same captured generation is a no-op. The
generation plus the node-owned revocation epoch are bounded freshness
bookkeeping for the first Tab Bar slice; they do not require deferred pane/tab
family migrations or new source-owner revisions.

The adapter starts the first admission during construction and registers one
observation of the node's materialized output. `PaneTabViewController`
keeps the current one-time construction of `CustomTabBar` and its typed
`DraggableTabBarHostingView`. Before first current output, the adapter exposes
an absent renderable projection, and the existing view presents no authoritative
tab items or active selection. Normal Observation publication updates that same
host when current output arrives; no callback, root replacement, type erasure,
or second hosting boundary is introduced. The rest of window composition need
not wait. Because the projector is total, first materialization ends only in
current output, supersession by a newer admission, or owner shutdown. There is
no synchronous fleet-reconstruction bootstrap fallback.

### 9.3 Projection and publication

```mermaid
sequenceDiagram
    participant Sources as Core/Feature atoms
    participant Adapter as TabBarAdapter
    participant Node as EagerDerivedAtom
    participant Worker as Tab bar projector
    participant UI as CustomTabBar

    Adapter->>Adapter: capture initial Sendable request N
    Adapter->>Node: admit N
    Node-->>Worker: detached projection N
    Sources->>Adapter: push relevant leading-edge invalidation
    Adapter->>Node: sourceDidInvalidate() synchronously
    Adapter->>Adapter: post-mutation capture N+1
    Adapter->>Node: admit N+1 and cancel N
    Worker-->>Node: completion N
    Node-->>Node: reject stale N
    Node-->>Worker: detached projection N+1
    Worker-->>Node: result N+1
    Worker->>Worker: compare with prior Sendable projection
    Node->>UI: publish compact changed TabBarProjection
```

The worker constructs one complete `TabBarProjection` off-main:

```text
TabBarProjection
  items: [TabBarItem]
  activeTabID: UUID?
```

The retained `EagerDerivedAtom` is the sole stored authority for both fields.
The adapter's `tabs` and `activeTabId` accessors forward the node's current
renderable projection; they are not independently stored observable copies.
Publication therefore changes items and active identity together. Overflow
calculation and ephemeral drag/drop state remain on `MainActor` because they
depend on current view geometry and are bounded.

### 9.4 Notification facts

App injects the concrete Inbox atom into the Tab Bar capture boundary. Capture
calls one Feature-owned `captureAttentionFacts()` operation that reads the
current notification owner and returns an immutable Sendable
`InboxAttentionFactSnapshot`; it does not call a per-tab MainActor color
provider and App does not interpret notification policy.

Inbox owns a pure `Sendable` `InboxAttentionProjector`. It accepts the fact
snapshot plus App-supplied opaque group IDs and pane-ID sets, then applies the
same contribution filtering and attention-lane precedence as today's
`attentionLane(forPaneIds:)`. The off-main App projector supplies one group per
tab, invokes that Feature-owned pure projection, and maps the returned
`InboxAttentionLane` values to `TabNotificationDotColor`. Feature owns
notification eligibility and precedence; App owns only tab grouping and color
presentation.

The Feature remains the canonical notification owner. App is allowed to depend
downward on the Feature and compose it with Core; neither Core nor the generic
eager primitive names Inbox. No Feature registry or ambient sibling lookup is
introduced.

## 10. Existing Feature Workers

Repo Explorer and Inbox already meet most lifecycle obligations through local
code. They remain authoritative during the first materialization slice.

They return to Program Design before any later adoption. The generic node gains
fallible behavior only if:

- behavior and failure policy are frozen;
- the generic contract removes more lifecycle code than it introduces;
- cancellation and stale-admission tests remain equivalent or stronger;
- the migration does not force cross-feature request/result types into
  Infrastructure.

There is no compatibility adapter or dual worker path. A later adoption is a
hard cut for one feature.

## 11. One-Shot Preparation

One-shot restore and persistence preparation use structured caller-owned
lifetime:

```text
caller captures immutable input
  -> async let or direct awaited @concurrent preparation
  -> await all required results
  -> validate complete candidate
  -> one atomic MainActor admission
```

No generic latest-wins node is introduced because:

- no successor request can supersede the work;
- there is no renderable intermediate output;
- the caller already owns completion and failure;
- structured child cancellation provides the correct lifetime.

This boundary prevents the materialization primitive from becoming a general
task framework.

## 12. Concurrency and Ordering

| Interleaving | Required result |
|---|---|
| Source changes after N admission but before N+1 admission | The synchronous revocation epoch rejects N; the prior accepted value may remain renderable but is not current |
| N completes before any source invalidation | N may publish |
| N+1 admitted before N completes | N completion is discarded regardless of cancellation cooperation |
| N completes current and equal to the prior output | N becomes the current request identity; output revision and output-only observation remain unchanged |
| Cancellation arrives during a long loop | Projector detects it at a bounded checkpoint and exits |
| Projector ignores cancellation and completes | Generation admission still rejects stale output |
| Owner shuts down with work running | Retained task is cancelled and no later completion publishes |
| Telemetry exporter blocks or fails | State lifecycle continues unchanged; telemetry is dropped/fail-open |

Generation/request identity and the synchronously advanced revocation epoch are
the final correctness guards. Cancellation is a resource optimization, not the
stale-result guarantee.

For the first product slice, window close, controller replacement, and
application termination invoke `MainWindowController.shutdown()`. It calls
`MainSplitViewController.shutdown()` -> `PaneTabViewController.shutdown()` ->
`TabBarAdapter.stop()` before releasing the host. That idempotently stops the
retained node and rejects every later admission. Adapter deinitialization
performs the same stop defensively, but deinitialization is not the primary
lifecycle trigger.

Canonical Core and Feature state survives window replacement. The stopped
adapter's materialized cache and transient drag, overflow, and geometry state
do not. Reopening constructs a fresh adapter and node through the App window
factory and starts a fresh first admission. A headless process does not retain
or run a process-owned Tab Bar adapter observation.

## 13. Telemetry and Capacity

Selected materialized nodes report through the existing trace-tag system:

- admission count;
- request-identity no-op count;
- MainActor capture duration;
- worker duration;
- MainActor publication duration;
- cancellation count;
- stale-discard count;
- semantic output-change count;
- input and output cardinality.

No request identity, key, UUID, path, title, terminal content, notification
body, or error payload is exported. Attributes are allowlisted and bounded.

The node admits at most one retained running task per product instance.
Rapid input changes cancel and replace rather than queue an unbounded backlog.
Equal identities remain no-ops while running or current.

## 14. First Migration Slice and Workload

Tab Bar is the first eager-materialization slice because:

- the current callback performs fleet reconstruction on `MainActor`;
- the output is already a compact value array;
- the adapter already owns observation and UI publication;
- existing `performance.tabbar.refresh` telemetry provides a direct-work
  baseline, but not an end-to-end visible-latency seam;
- it composes App, Core, and Feature facts without moving their ownership.

The current measurement boundary is insufficient for RS-24–RS-26 acceptance:
`performance.tabbar.refresh` ends after adapter refresh work rather than after
visible presentation or focused-input readiness; hot telemetry attributes can
construct rich values before an enabled-tag rejection; and the bounded trace
queue does not report dropped records or a high-water mark. A matched
distribution from those records can therefore omit pressure or measure the
wrong boundary.

Within PR 2, the following measurement corrections must land before Tab Bar
performance acceptance:

```text
Lazy hot attributes; disabled tags do no rich work ─────────┐
Trace-queue drop and high-water accounting ─────────────────┤
Capture, worker, and publication durations ─────────────────┼──> Tab Bar
Interaction to visible/current-result boundary ─────────────┤    acceptance
Source, executable, workload, and event provenance ─────────┘
```

This proof work extends the existing trace queue, Victoria workload, and
comparator. It is not a new telemetry framework or a third implementation
slice. Correctness implementation may proceed before it, but no performance
acceptance or improvement claim may pass without it.

Before candidate results exist, the slice freezes:

- tab activation and navigation;
- pane-title and repo-enrichment changes;
- notification-dot changes;
- zoom/arrangement changes;
- typing and scrolling continuity while those updates occur;
- tab-bar invalidation/admission count;
- MainActor capture and publication duration;
- end-to-end tab-bar refresh/visible-update latency;
- tab, pane, repo, and worktree cardinality;
- event-continuity and final rendered-state oracles.

After these measurement corrections exist, the event hard cut preserves an
exact comparison mapping:

- the existing `performance.tabbar.refresh` baseline event maps to one
  terminal record for every candidate request admission, including
  `published`, `equal`, `superseded`, and `cancelled` outcomes;
- separate bounded phase events record capture, worker, and publication
  duration, correlated by a non-sensitive run-local sequence rather than a
  product identifier;
- successful-publication count is never used as the issued-work denominator;
- the controlled driver records issued interactions independently and reads
  back final tab/active-tab state independently of performance telemetry.

The existing performance comparator remains the one admission authority. It is
extended to require exact source/executable/workload/trace-tag provenance,
the frozen event set, terminal outcome completeness, issued-interaction
continuity, and final-state equivalence before comparing distributions. The
existing OTLP allowlist and fail-open tests cover the new bounded fields; no
parallel benchmark or telemetry framework is introduced.

The large watched-folder/open-source workload is reused so topology and
enrichment pressure occur while Tab Bar remains interactive. The existing
comparison rule that requires an arbitrary fixed fraction or universal 50%
improvement is not authoritative for this slice. Regression boundaries come
from the frozen provenance-matched baseline variability or an already
governing budget.

Command Bar remains outside the first slice. Its demand cache and scope
behavior require independent workload evidence before deciding between lazy
cached composition and eager materialization.

## 15. Cutover

The Tab Bar cutover has one output authority at every point:

- before cutover, `TabBarAdapter.refresh()` owns materialized items;
- after cutover, the retained `EagerDerivedAtom` owns the complete current or
  successor-pending `TabBarProjection`, and the adapter only forwards it;
- the synchronous fleet-reconstruction path is removed in the same slice.

No feature flag, dual computation, or fallback-to-old-refresh path remains.
Rollback is source rollback before dependent work builds on the new contract,
not a permanent runtime compatibility branch.

## 16. Cross-Cutting Realization

| Obligation | Structural realization | Failure/degradation |
|---|---|---|
| Responsiveness | Variable-cardinality projector and output equality run in internally detached task | Previous projection remains renderable while a successor runs |
| Freshness | MainActor generation/request admission plus synchronous source-revocation epoch | Source change rejects old work even before deferred successor capture; cancellation failure cannot publish stale output |
| Reliability | One retained task, bounded output, explicit irreversible shutdown | Tab Bar has no failure branch beyond cancellation or shutdown; fallible adoption is deferred |
| Target readiness | Generic node owns no product type; App owns cross-feature composition | No reverse target edge or ambient registry |
| Privacy | Allowlisted aggregate telemetry only | Exporter failure is fail-open |
| Operability | Existing performance trace tags and debug identity | Missing event continuity invalidates comparison |
| Platform safety | `Sendable` request/result/closure and strict Swift 6 checks | Compile-negative proof distinguishes compiler claims from lint |

## 17. Proof Architecture

| Requirement set | Structural seam | Proof class |
|---|---|---|
| RS-09–RS-10 | Admission, retained task, request freshness, output revision | Deterministic latest-wins, equal-result currentness, equality, and push-admission tests |
| RS-11–RS-12 | Sendable request/result and internally detached projector | Compiler harness plus source/behavior proof that variable work is outside `MainActor` |
| RS-13–RS-14 | Generation admission, synchronous source revocation, and owner shutdown | Controlled cancellation, pre-successor stale completion, overlap, and cleanup tests without wall-clock sleeps |
| RS-21–RS-23 | Narrow generic interface and product-owned request/projector | Architecture rules and target-build proof |
| RS-24–RS-26 | PR 2 measurement corrections plus trace events and controlled Tab Bar workload | Lazy disabled-path attributes, trace-queue completeness, phase and interaction-to-visible boundaries, provenance equality, independent continuity oracle, distributions, and frozen regression boundary |
| RS-27–RS-28 | Real adapter and isolated debug app | Unit/integration/runtime pyramid plus launch, tab navigation, typing, scrolling, animation, and state-change proof |

The cancellation harness uses explicit gates or continuations to hold N,
admit N+1, and release completions in either order. It never sleeps for an
assumed scheduler interval.

A separate leading-edge harness holds N, mutates one observed source, confirms
the callback revokes N while successor capture is still gated, then releases N
before admitting N+1. N must not publish or become current. Releasing the gate
admits N+1 from post-mutation state, and only N+1 may become current. This proof
uses callbacks and continuations, not scheduler timing.

The native gate uses the existing authenticated debug IPC path for semantic
Tab Bar actions and independent state read-back, plus the existing native UI
inspection path for rendered interaction evidence. It sets
`AGENTSTUDIO_REQUIRE_LAUNCHSERVICES=1`; the debug runner's
`direct_executable` fallback is telemetry-only and cannot satisfy native
interaction or visible-performance acceptance.

Core projection parity feeds identical captured facts through the current
`TabDisplayDerived`, `PaneDisplayDerived`, and `ArrangementDerived` policies and
the pure Core projector, then compares every title, arrangement label/badge,
pane visibility, minimized count, zoom fact, and active-tab result. A
first-materialization integration gate holds the projector and proves the one
existing host/view presents no authoritative tab items or active selection,
then releases one current result and observes that same host render it.
Shutdown before release must suppress every later result without replacing the
host or resetting its view state.

Title parity additionally covers runtime and tab-title events, custom-tab-name
precedence, worktree-label precedence, empty-title fallback, IPC/replay
behavior, and save/relaunch behavior. It proves compatibility through the one
new projector; it does not retain the synchronous fleet projector as a second
authority.

Inbox projection parity tests feed identical immutable facts and pane groups to
the current `attentionLane(forPaneIds:)` behavior and the new pure projector.
They cover every lane, dismissed/non-contributing facts, mixed groups, and
precedence before the current per-tab MainActor provider is removed.

## 18. Source Inventory

| Source | Identity | Authority and applicability |
|---|---|---|
| Governing Requirements | [Reactive State System Requirements](2026-07-31-reactive-state-system-requirements.md) | Normative Why and authorized boundary |
| Governing Specification | [Reactive State System Specification](2026-07-31-reactive-state-system-specification.md) | Normative eager execution, lifecycle, proof, and scope obligations |
| Current repository | Git `f7a01132f9ac5d02981e00856750936f80acb61f` (`origin/main`) | Current implementation and workload evidence baseline |
| [`RepoExplorerProjectionWorker.swift`](../../../Sources/AgentStudio/Features/RepoExplorer/Models/RepoExplorerProjectionWorker.swift) and [`RepoExplorerView.swift`](../../../Sources/AgentStudio/Features/RepoExplorer/RepoExplorerView.swift) | Current source at repository identity above | Existing correct replaceable worker pattern and source-capture boundary |
| [`InboxNotificationListProjectionWorker.swift`](../../../Sources/AgentStudio/Features/InboxNotification/Models/InboxNotificationListProjectionWorker.swift) and Inbox sidebar view | Current source at repository identity above | Existing second replaceable worker pattern |
| [`TabBarAdapter.swift`](../../../Sources/AgentStudio/App/Panes/TabBar/TabBarAdapter.swift) | Current source at repository identity above | Selected variable-cardinality MainActor path |
| [`TabDisplayDerived.swift`](../../../Sources/AgentStudio/Core/State/MainActor/Atoms/TabDisplayDerived.swift), [`WorkspacePaneGraphAtom.swift`](../../../Sources/AgentStudio/Core/State/MainActor/Atoms/WorkspacePaneGraphAtom.swift), [`TerminalRuntime.swift`](../../../Sources/AgentStudio/Features/Terminal/Runtime/TerminalRuntime.swift), and [`AgentStudioIPCRuntimeAdapter.swift`](../../../Sources/AgentStudio/App/IPCComposition/AgentStudioIPCRuntimeAdapter.swift) | Current source at repository identity above | Title authority, precedence, replay, IPC, and compatibility behavior preserved by the first Tab Bar slice |
| [`InboxNotificationAtom.swift`](../../../Sources/AgentStudio/Features/InboxNotification/State/MainActor/Atoms/InboxNotificationAtom.swift) | Current source at repository identity above | Feature-owned contribution and attention-lane policy preserved behind the pure projection seam |
| [`WorkspaceSQLiteSaveCoordinator.swift`](../../../Sources/AgentStudio/Core/State/MainActor/Persistence/WorkspaceSQLiteSaveCoordinator.swift) and restore preparation | Current source at repository identity above | Existing one-shot `@concurrent`/structured counterexample |
| [`AgentStudioPerformanceTraceRecorder.swift`](../../../Sources/AgentStudio/Infrastructure/Diagnostics/AgentStudioPerformanceTraceRecorder.swift) and existing workload scripts | Current source at repository identity above | Existing telemetry and controlled debug proof seams |
| [MainActor runtime pressure investigation](https://github.com/ShravanSunder/agentstudio/blob/aa0a1de06963089a7ec449f6a382dac89dac46cd/docs/wip/debugging/2026-08-05-mainactor-runtime-pressure.md) | Git `aa0a1de06963089a7ec449f6a382dac89dac46cd` observational report over release `0.0.72` | Measurement-boundary defects and ranked MainActor paths; observational, not normative |
| SE-0461, SE-0466, and SE-0430 | Accepted Swift proposals applicable to Swift 6.2.4 | Executor isolation and checked-transfer feasibility |

Scoped completeness covers all production `Task.detached` and `@concurrent`
sites through the governing inventory, the two mature live-projection paths,
the selected Tab Bar path, one-shot preparation, relevant telemetry, and the
debug/performance harness. Exact runtime improvement remains unclaimed.

## 19. Accepted Debt and Revisit Signals

- Repo Explorer and Inbox retain feature-local lifecycle until a separate
  hard-cut migration proves the generic node simplifies them.
- MainActor capture must still read stored collection references. If measured
  capture grows beyond the frozen budget, the source owner needs a more
  compact revisioned snapshot; the node is not widened into a background
  state reader.
- The primitive supports replaceable CPU projection only. A second ordering
  policy or async I/O use case requires a new design decision rather than
  silent generalization.

## 20. Negative Space

This design does not:

- create a scheduler, task pool, job queue, retry system, or actor framework;
- prebuild a fallible eager API before a selected fallible product migration;
- make `Task.detached` itself the correctness guarantee;
- run SQLite, filesystem I/O, or network work through the materialized node;
- discover dependencies ambiently;
- persist materialized results as new authority;
- move ephemeral view geometry off `MainActor`;
- migrate all current workers in one change;
- assert a performance win from static code shape.
