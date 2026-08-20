# Bridge Latest-Generation Operations — Specification

Requirements authority:
[2026-08-18-requirements.md](./2026-08-18-requirements.md)

## Observable contract

Bridge MUST distinguish command completion, current-data convergence, stream
health, content transfer, and render fulfillment. A newer applicable intent
MUST supersede older visible authority immediately; obsolete physical work MAY
drain, but MUST NOT block current authority or publish after supersession.

```text
command request ──► exact terminal receipt

source/demand change ──► current read convergence
  ├─► finite complete install or unavailable
  └─► progressive current coverage or unavailable

metadata/content/render operation ──► exactly one terminal outcome
```

## Terms

- **Current intent**: the newest applicable source, demand, viewer, selection,
  refresh, or explicit retry known to the owning surface.
- **Obsolete work**: work admitted for an intent that is no longer current.
- **Last complete state**: the most recent fully validated and atomically
  installed selected File content/render, Review publication/render, annotation
  projection, or other finite logical result.
- **Progressive File metadata coverage**: the current-fenced changeset, status,
  descriptor, and tree facts applied through the newest admitted File source
  change. It is complete when no known dirty File facts remain unapplied; it is
  not an atomic File snapshot.
- **Terminal outcome**: success, failure, cancellation, or stale/superseded.
- **Retryable failure**: a failure whose cause may resolve without new user or
  source input and for which retrying the same newest authoritative facts is
  safe. A failure is non-retryable for the same operation when unchanged input
  cannot succeed.
- **Projection**: a complete UI-ready read model derived from authoritative
  domain/source data; it is not durable authority.

## Normative requirements

### R-BLO-001 — Newest intent controls visible authority

When a newer applicable intent arrives, Bridge MUST immediately stop attributing
current authority and loading justification to older work. Obsolete work MUST
NOT overwrite current data, clear or re-enable current controls, regress source
identity, or publish a current success.

If obsolete work ignores cancellation, current work MUST still be eligible to
run or queue under the existing bounded capacity owner. Logically cancelled
queued work MUST release its queued admission before current work is admitted.
Obsolete running work MAY drain physically. If obsolete running work prevents
current execution beyond the existing capacity owner's bounded wait policy,
the current operation MUST terminate with a retryable capacity failure and the
surface MUST become unavailable with an explicit retry path; it MUST NOT remain
loading indefinitely. This correction does not authorize
unbounded overcommit or forced preemption of running Git work.

Basis: BLO-U1, BLO-U5.

### R-BLO-002 — Exact command terminal is independent

Every typed mutation command MUST return exactly one correlated terminal result:
success receipt or failure. A success receipt MUST establish that the mutation
committed and MUST end the UI's command-in-progress state.

A subsequent invalidation, projection query, or render operation MUST NOT keep
the command in `saving`, `copying`, `exporting`, or equivalent command-progress
state. If refresh is pending or fails after command success, the UI MUST expose
that as separate read convergence.

Basis: BLO-U2.

### R-BLO-003 — Atomic results and progressive File metadata retain usable state

Each selected File content/render, Review publication/render, annotation
projection, and other finite logical result MUST expose one of:

```text
ready(lastComplete)
refreshing(lastComplete or initial-empty)
unavailable(lastComplete or initial-empty, safe failure)
```

A partial, malformed, stale, cancelled, or failed replacement MUST NOT replace
the last complete state or masquerade as an empty successful state. Only a
complete current replacement MAY restore `ready`.

File metadata MAY publish current-fenced changeset, status, descriptor, and tree
facts progressively. Every emission MUST belong to the current File operation.
If supersession occurs after only part of the dirty File facts were emitted, the
successor MUST re-cover every still-current fact from the earliest unapplied
change through the newest admitted change before File metadata may be presented
as current. Retained progressive metadata MAY remain usable while this coverage
is refreshing or unavailable, but a partial emission set MUST NOT masquerade as
complete current coverage.

Basis: BLO-U3, BLO-U12.

### R-BLO-004 — Every operation has one terminal outcome

Every admitted command, native refresh pass, subscription producer, content
request, projection request, and render job MUST reach exactly one terminal
outcome. Duplicate terminal outcomes MUST be ignored or rejected without a
second visible effect.

An owner MUST NOT continue presenting a producer/subscription as active after
its task ends or delivery fails. A loading indicator MUST be derivable from a
current live operation and MUST clear on all terminal outcomes.

Selecting a current File item MUST admit its File-content operation before the
authorized content descriptor is available. Descriptor-wait is that current
operation's preparing state; descriptor arrival continues only the same current
selection. The operation MUST terminate as:

- success after current content and render fulfillment;
- failure with the File-content surface unavailable if current metadata settles
  without a usable descriptor;
- stale/superseded if its source or selection loses current authority;
- cancelled if selection or demand is cleared; or
- failure if current content open, validation, preparation, or render fails.

Descriptor-wait MUST remain event-driven. It MUST NOT introduce polling or an
independent wall-clock watchdog, and it MUST NOT remain visible after its
operation loses its current selection, retry owner, or terminal path.

Basis: BLO-U4, BLO-U12.

### R-BLO-005 — Replacement and late completion

When current work is replaced:

1. the old operation becomes stale/cancelled immediately;
2. the newest operation becomes eligible to start without awaiting indefinite
   physical termination of the old operation;
3. late old success/failure may release resources but MUST NOT publish;
4. the newest operation independently reaches a terminal outcome.

This requirement does not mandate cancelling safe shared immutable
construction that the current operation can join under a current epoch.
Queued obsolete admissions MUST be removed; running obsolete operations may
drain under existing capacity. A current operation that cannot execute within
the capacity owner's bounded wait terminates with a retryable capacity failure;
the surface becomes unavailable with an explicit retry path.

Basis: BLO-U1, BLO-U5, BLO-U11.

### R-BLO-006 — Failure retry and retained work

If current refresh work fails with a retryable failure while dirty work remains,
Bridge MUST perform at most one automatic retry of the latest retained work.
If that retry fails, or if the failure is non-retryable, the surface MUST become
unavailable with its last complete state and an explicit retry action. A new
invalidation, foreground return, or explicit retry starts a new current
operation and supersedes the failure. Bridge MUST NOT retain dirty work while
presenting the surface as current, and automatic retry MUST NOT loop.

A rejection caused by losing or mismatching the operation's current source,
demand, selection, or publication fence MUST terminate `stale/superseded`, not
`failure`, and MUST NOT consume the automatic retry. A stale terminal may keep
the last complete state refreshing only when a named current successor trigger
remains admitted. If no such trigger exists or it fails, the owner MUST expose a
failure or unavailable state rather than retaining ownerless loading.

The current failure families classify as follows:

| Condition | Classification for the same operation |
| --- | --- |
| existing capacity-owner timeout | retryable failure |
| temporarily unavailable current source or projection capture while its authority remains current | retryable failure |
| lost or mismatched current source/demand/selection/publication fence | stale/superseded; successor required |
| descriptor pending while current metadata can still supply it | preparing; not a failure |
| current metadata settles without a usable descriptor | non-retryable failure for the same operation; surface unavailable until a new source/demand change or explicit retry |
| descriptor, cursor, request-authority, page-order, digest, schema, or aggregate-integrity mismatch | non-retryable failure for unchanged input |
| unsupported content or wire value | non-retryable failure for unchanged input |

Basis: BLO-U1, BLO-U4, BLO-U10.

### R-BLO-007 — Subscription failure and reopen

If a metadata or annotation notification producer fails, ends unexpectedly, or
cannot deliver, the owning protocol subscription MUST leave active state. Where
the pane/session remains admitted, Bridge MUST reset/reopen under current
authority and begin with a current snapshot-required/bootstrap fact.

Reopen failure MUST expose unavailable/degraded state and MUST NOT leave a dead
subscription represented as healthy.

Basis: BLO-U4, BLO-U6.

### R-BLO-008 — Overload resets and replays

When bounded metadata delivery cannot admit another ordinary frame, the stream
MUST produce a valid terminal reset or explicit failure under reserved terminal
capacity. It MUST NOT attempt to use another ordinary frame as its overflow
terminal.

After an admitted reconnect, Bridge MUST replay the latest retained pane
presentation and any still-current exact navigation intent. Queue reset MUST NOT
be reported as successful application of the dropped ordinary frame.

Basis: BLO-U6.

### R-BLO-009 — Finite snapshot contract

Each finite logical response MUST declare or enforce:

- logical snapshot identity;
- page ordering and final-page condition;
- total page and/or total byte ceiling;
- expected record/entity counts where applicable;
- aggregate integrity;
- source/session/surface authority.

The consumer MUST accept any valid page count within the bound, including three
or more pages, and MUST reject duplicated, skipped, reordered, mixed-snapshot,
mixed-source, or over-bound sequences. Installation MUST be atomic after final
validation.

Basis: BLO-U7.

### R-BLO-010 — Valid wire values round-trip

Every valid current request and response variant emitted by Swift MUST pass the
same strict validation used at its production ingress/settlement boundary and
MUST be accepted by the matching BridgeWeb contract. The inverse MUST hold for
valid BridgeWeb requests.

Unknown members and invalid variants MUST still fail closed. Adding a current
field or variant MUST make missing Swift vocabulary or TypeScript shape support
an automated failure before runtime.

Basis: BLO-U8.

### R-BLO-011 — Explicit timestamp units

Annotation product-transport timestamps MUST use required integer Unix
milliseconds with these wire members where applicable:

```text
createdAtUnixMilliseconds
updatedAtUnixMilliseconds
completedAtUnixMilliseconds
authoredAtUnixMilliseconds
```

The epoch is `1970-01-01T00:00:00Z`; the unit is milliseconds; values must fit
the product safe-integer and supported platform `Date` range. Swift and
BridgeWeb MUST convert explicitly. Relative and absolute presentation of the
same instant MUST agree. This correction does not change PR1 exported batch
JSON `createdAt`, whose version-1 contract remains RFC 3339.

Basis: BLO-U8.

### R-BLO-012 — Bounded correlation and resource cleanup

Out-of-order request/result rendezvous state MUST exist only until both sides
settle and MUST be bounded against orphan inputs. Subscriptions, observers,
descriptors, content reservations, cancellation handles, artifact custody, and
pending resolvers MUST be released on terminal outcome, replacement, close, or
restart according to their owner.

Basis: BLO-U9.

### R-BLO-013 — Scoped invalidations and current queries

Annotation notification events MUST be the strict union:

```text
snapshotRequired(notificationRevision)
sessionChanged(notificationRevision, sessionID, semanticRevision)
discoveryChanged(notificationRevision)
recoveryChanged(notificationRevision)
```

Normal session mutations use `sessionChanged`; discovery-set changes use
`discoveryChanged`; recovery admission changes use `recoveryChanged`;
bootstrap/reset uses `snapshotRequired`. `snapshotRequired` supersedes narrower
pending facts. Multiple pending invalidations MAY coalesce to the newest current
fact while durable transactions remain independently committed.

`notificationRevision` orders one notification subscription only. It MUST NOT
be used as the File/Review source-generation fence for a projection query.

If an annotation projection query is rejected as stale because notification
delivery preceded the current File/Review presentation source generation, the
next current presentation source-generation update MUST supersede that attempt
and start the successor query. The stale rejection MUST NOT make the projection
unavailable or consume its automatic retry. If that successor update cannot be
delivered, the applicable producer failure/reset contract MUST settle the wait.

An invalidation MUST contain no bulk body required from the finite content
route.

Basis: BLO-U1, BLO-U6, BLO-U7.

### R-BLO-014 — Stage-correlated operational evidence

For one current operation, operational evidence MUST distinguish:

```text
intent/invalidation admitted
native work started and terminal
metadata enqueue and delivery terminal
worker application terminal
projection/content validation terminal
main-thread install terminal
render/paint terminal
```

Every stage-start MUST have a terminal or a bounded missing-terminal diagnostic.
Stable production telemetry MUST provide sufficient scrubbed evidence to assign
a stuck interaction to one stage family without requiring private content.

Basis: BLO-U10.

### R-BLO-015 — Existing routes and authorities remain singular

The correction MUST preserve the existing command, metadata stream, and finite
content physical routes. SQLite/repositories remain annotation durability
authority; native source/Git owners remain source authority; surface-local
worker/main stores remain presentation owners. No Atom, second transport,
durable in-flight task database, polling loop, or compatibility shim becomes a
parallel source of truth.

Basis: BLO-U11, BLO-U12.

## Observable state relationships

```text
Command
  idle → inFlight → succeeded(receipt) | failed(error)

Read model
  ready(N) → refreshing(N) → ready(N+1) | unavailable(N)

Progressive File metadata
  current(coveredThrough N)
    → refreshing(retainedThrough N, dirty through M)
    → current(coveredThrough M) | unavailable(retainedThrough N)

Replaceable work
  running(10) → stale/cancelled(10) + running(11)

Producer
  opening → active → resetting/failed/closing → active or closed

Render
  desired → fetching → rendering → presented | failed | stale
```

These states are independent. Command success does not mean projection ready;
projection ready does not mean render presented; render failure does not undo a
committed command; stream reset does not erase durable truth or last complete
presentation.

## Failure and partial-success contract

| Condition | Required observable result |
| --- | --- |
| command rejected before commit | exact failure; durable and projected state unchanged |
| command commits, refresh fails | command succeeded; read state unavailable/refreshable; last complete retained |
| selected File descriptor is pending | current File-content operation remains preparing under the same selection; descriptor arrival continues it |
| current File metadata settles without a usable descriptor | File content unavailable with retained presentation and a new-demand/explicit-retry path; no ownerless loading |
| progressive File operation is superseded after partial emissions | retained metadata remains usable; successor re-covers all still-current unapplied facts before current status |
| newer intent arrives | old authority ends immediately; newest becomes eligible; late old completion cannot publish |
| old work ignores cancellation | newest remains eligible under capacity; old drains and cleans up only |
| projection query loses its source fence before current presentation generation arrives | stale terminal; no failure retry or unavailable flash; presentation generation starts successor |
| native refresh fails with dirty work retained | at most one automatic retry for retryable failure, then unavailable with last complete and explicit retry; non-retryable failure is unavailable immediately |
| producer ends unexpectedly | subscription leaves active; reset/reopen or unavailable |
| metadata queue overload | terminal reset/failure, reconnect, latest retained replay |
| finite response incomplete/mixed/over-bound | private replacement discarded; last complete retained |
| render receipt stale | stale terminal; cannot clear or commit current render |
| timestamp unit unknown | reject or classify invalid; never display a guessed instant |
| restart | no in-flight operation is assumed successful; durable truth is queried and current streams bootstrap anew |

## Compatibility and cutover

This is a hard lifecycle cutover inside the existing versioned Bridge product
transport. Existing documented current payload meaning remains compatible unless
this Specification explicitly corrects it. Defective pre-release PR1 contracts
MAY cut over in place. Existing File/Review user behavior and physical routes
remain unchanged.

## Negative space

- No guarantee that physical cancellation is instantaneous.
- No guarantee that every lane uses identical internal state types.
- No automatic infinite retry.
- No durable replay of in-flight operations across restart.
- No requirement that independent File and Review work serialize together.
- No license to broaden metadata into bulk content.
- No new user-facing operation-history UI.

## Proof obligations

| Requirements | Evidence class that distinguishes pass from fail |
| --- | --- |
| R-BLO-001/005 | deterministic 10/11/12 interleavings with cancellation ignored and late old completion; real source-change integration |
| R-BLO-002/003 | real command commit plus failed/delayed projection; progressive File supersession and re-coverage; UI state inspection preserving last usable state |
| R-BLO-004/006/007 | selected File descriptor pending/arrival/absence terminals; stale-fence-before-presentation successor; retryability-family state tests; supervised producer and real end/reopen integration with residue inspection |
| R-BLO-008 | real bounded producer/session saturation, terminal reset, reconnect, retained replay |
| R-BLO-009 | unit property/matrix for pages and integrity plus real multi-page content carrier |
| R-BLO-010/011 | exhaustive Swift/TypeScript vectors and fixed-epoch Swift-to-browser fixture |
| R-BLO-012 | repeated operation/resource-state inspection and close/restart cleanup |
| R-BLO-013 | two-observer/two-pane convergence with scoped/coalesced invalidations and reset bootstrap |
| R-BLO-014 | fresh marker-scoped stable/debug operational transcript joining every named stage |
| R-BLO-015 | architecture/static enforcement plus real File/Review/annotation regression journeys |
