# Bridge Review Comparison Target Loading — Program Design

Requirements: [User Requirements](./user-requirements.md)

Specification: [Specification](./specification.md)

## The correction is two complete flows

The existing Bridge transport already separates control, pushed metadata,
requested content, and scheduling. The correction uses those owners as designed:

```text
CURRENT COMPARISON                         SELECTABLE TARGETS

Review initializes                        Comparison picker opens
        │                                         │
        ▼                                         ▼
resolve one default ref                    typed query command
load durable target                               │
publish default identity                          ▼
        │                                  single-use reservation
        ▼                                         │
compact metadata                                 ▼
active target                          content.open registers task
basis / attempt / snapshot                        │
repository default identity                      ▼
stale or current                    focused catalog producer actor
                                                   │
                                                   ▼
                                          bounded Git capture
                                          encode / truncate / hash
                                                   │
                                                   ▼
                                          virtualized selector
```

The catalog leaves pane presentation. One focused, injected computation service
produces it only after content demand. No cache, database state, persistent or
cross-pane service, watcher, metadata subscription, producer framework, or
fourth physical route is added.

## Current system evidence and constraints

The merged comparison-target work already establishes the foundation this
follow-up preserves:

- compact `repositoryDefaultTarget` state is pushed independently from the
  catalog in both packaged and development hosts;
- `review.comparisonTargets.query` already returns a typed result, and
  `review.comparisonTargets` already uses descriptor-authorized
  `content.open`, `.selected` demand, finite content frames, worker validation,
  and a virtualized selector;
- `agentstudio-git` already owns constant default resolution and bounded,
  scheduled comparison-target capture;
- native control dispatch intentionally finishes and replay-caches an exact
  response after provider dispatch begins, even if the originating URL task
  closes; and
- the existing producer registry already creates a request `Task` for an
  accepted content producer and owns its cancellation/lifecycle residue.

The remaining defect is the current query-control sequence:

1. `BridgeProductSession.beginValidatedControl` stores the session's sole
   `pendingControl`; another command is rejected while it remains present.
2. `BridgeProductSchemeControlDispatcher` awaits the complete provider response.
3. `BridgePaneProductSchemeProvider.response` awaits
   `queryReviewComparisonTargets()`.
4. `BridgePaneProductComparisonTargetQuerySource` acquires foreground admission,
   computes capture time/cutoff, awaits bounded Git capture, maps the catalog,
   encodes/truncates it, and computes SHA-256.
5. The provider stores the completed body and exact descriptor, returns the
   response, and only then can the session settle `pendingControl`.
6. A later `content.open` merely claims and replays those buffered bytes through
   the producer-registry task.

Swift actor reentrancy means an awaited Git call does not by itself prove a
blocked thread or permanently occupied actor executor. The evidenced defect is
protocol head-of-line blocking: the session's control state remains pending for
the full production duration. Control-plane serialization must not span
independent, potentially long-running data production.

Current package authority is `agentstudio-git` revision
`474bf34210dd8e176f9b3585b061161a8e8b50d4`. Its bounded capture and scheduler
contracts remain authoritative; this follow-up changes when Agent Studio invokes
them, not the upstream Git API or scheduler class.

## Structural crux and selected direction

The crux is where a finite, explicitly requested catalog lives between capture
and presentation.

| Direction | Gain | Cost or failure | Decision |
| --- | --- | --- | --- |
| Keep catalog in metadata | no new application call | Review startup and every presentation copy scale with repository history | rejected |
| Return rows directly in the command result | removes metadata abuse | turns the control/replay response into bulk-data transport and bypasses content scheduling | rejected |
| Command captures the body, then returns one exact content descriptor | preserves the current exact descriptor shape | the session's only pending control spans Git capture and body materialization | rejected |
| Command reserves one content response; `content.open` invokes a focused producer | settles control before production while reusing content framing, cancellation, bounds, and demand admission | one small reservation plus one focused producer boundary | selected |

The selected cost is paid by the pane-scoped query owner and producer: the
provider retains at most one small authorization reservation, and a focused
producer actor performs the duration-bearing work only after a matching open.
The producer is injected through one narrow async protocol so a test double or
another conforming actor can replace it without a registry or plugin system. A
TTL, eviction service, cross-pane sharing, catalog persistence, generic producer
host, or runtime producer routing would add machinery without serving an
accepted requirement.

## Owners and dependency direction

```text
BridgePaneController / BridgeDevelopmentProductHost
  owns: host-specific Review attempts and default-target lookup initiation
  consumes: the same default resolver through the shared Git data client

BridgePaneRefreshAdmissionCoordinator
  owns: compact current presentation for both production-backed hosts
  consumes: compact default-identity updates from either host

BridgePaneProductSchemeProvider
  owns: pane/session command authorization, one comparison-target reservation,
        atomic reservation consumption, and content framing coordination
  contains: at most one pending unclaimed reservation
  consumes: live read-only repository/current-target projection

BridgeReviewComparisonTargetCatalogProducing
  owns: the narrow async production contract
  consumers: BridgePaneProductSchemeProvider content-open path

BridgeReviewComparisonTargetCatalogProducer actor
  owns: capture-time/cutoff calculation, bounded Git capture, Bridge mapping,
        JSON encoding, byte truncation, and SHA-256 for one consumed request
  conforms to: BridgeReviewComparisonTargetCatalogProducing
  consumes: BridgeReviewSourceProvider and product capacity policy

AgentStudioGitBridgeReviewDataClient
  owns: Bridge-to-agentstudio-git mapping and Git scheduler admission
  consumes: agentstudio-git default resolution and bounded capture

BridgeProductProducerRegistry request task
  owns: consumed request lifetime, cancellation, framing, and terminal cleanup
  invokes: the injected catalog producer actor

Comm worker comparison-query controller
  owns: native call/content sequence, decoding, AbortController, request and
        work-admission identity

React comparison picker
  owns: remembered Branch/Commit mode, focus, search, and visible query state
  consumes: compact current metadata plus request-scoped query results
```

Allowed dependencies follow this order. The query-control path may read the
native pane repository and current target through one consumer-owned read-only
projection at authorization; the web request does not supply either value. It
may construct and store a reservation, but it cannot see Git capture, encoder,
truncation, or digest dependencies and cannot invoke the producer. After content
registration succeeds, the registry-created task atomically consumes the exact
pending reservation through the provider as its first comparison-target
operation, before accepted framing or producer invocation. The immutable
consumed value then belongs only to that task; the provider retains no claimed
lifecycle state. The producer cannot construct command responses, mutate
provider reservation state, or touch `BridgeProductSession.pendingControl`.

The provider must not capture an initial target during composition because it
outlives later comparison-target mutations. Pane metadata must not depend on
query state, and target selection continues through `review.comparison.update`
rather than trusting a captured catalog OID. There is deliberately no generic
actor that hosts arbitrary producers: unrelated producer capabilities must not
gain a shared serialization bottleneck or an unowned routing layer.

The injected producer contract is behavioral rather than a generic execution
wrapper:

```text
produceComparisonTargetCatalog(request) async throws → produced body

request
  repository authority
  current symbolic branch, nullable
  recency window, maximum rows, maximum encoded bytes

produced body
  UTF-8 JSON bytes bounded by maximum encoded bytes
  observed byte length and SHA-256
  catalog capture/cutoff facts encoded in those bytes

errors
  cancellation propagates from the producer-registry request task
  Git, mapping, encoding, or capacity failure remains content-local
```

The producer has no retained catalog state and makes no command-response or
reservation decision. A conforming actor may replace the concrete actor at
composition time; runtime selection and arbitrary producer dispatch are not
part of the contract.

## Compact current-comparison flow

### Native current truth

Review initialization and comparison refresh perform a constant-scope default
lookup whether the pane has restored target intent or needs automatic
initialization:

```text
Review initialization
        │
        ├─ read target intent from core.sqlite
        │
        ├─ resolve refs/remotes/origin/HEAD and peel only its target
        │
        ├─ no intent + resolvable default
        │      └─ existing pane-intent mutation initializes the target
        │
        └─ publish the resolved remote-tracking symbolic identity
               └─ React compares it with the active or displayed target
                      ├─ same symbolic identity → show Default
                      └─ different or absent    → no marker
```

Before the asynchronous lookup, the host captures repository authority together
with the current Review generation, product admission, and foreground-work
admission. Starting a new lookup clears the prior compact default identity. A
completion may publish only if the repository and all three admissions still
match. This follows the existing `isReviewPackageLoadCurrent` pattern rather
than adding another generation. A stale completion writes nothing. A resolver
failure that is still current leaves the identity absent; it must not preserve a
formerly resolved default after the designation changes or becomes unavailable.

The comparison presentation carries
`repositoryDefaultTarget: BridgeReviewComparisonDefaultTargetIdentity?`.
That transport value contains only `remoteName` and `branchName`; it carries no
catalog rows, target OID, comparison basis, or durable intent.
`BridgePaneRefreshAdmissionCoordinator` remains the owner of the compact
presentation containing:

```text
activeTarget
repositoryDefaultTarget
attempt
displayedSnapshot
native activity / refresh facts
```

The identity is derived current truth and is never persisted. The UI compares
symbolic names rather than target OIDs or basis values, so `origin/main` remains
the same default identity as its commit moves while local `main` remains a
different identity. The same compact fact can classify the active target or the
displayed snapshot target without carrying a targetless boolean across a target
change. If the default ref is missing, malformed, dangling, or points outside
the supported remote-tracking namespace, the identity is absent and automatic
initialization does not fabricate a target.

### Both production-backed hosts use the compact flow

The packaged controller uses the constant resolver above in
`adoptInitialContributionTargetIfEligible`. It
clears the previous compact identity at lookup admission, revalidates through
`isReviewPackageLoadCurrent`, publishes the resolved symbolic identity, and uses
that same resolved target for automatic initialization only when durable intent
is still absent.

`BridgeDevelopmentProductHost` performs no construction-time catalog load.
Construction resolves only the designated
default, seeds the shared refresh coordinator with its compact identity, and
retains the supplied pane target intent. Each later comparison attempt clears
and refreshes that identity through the same Git data client while holding the
existing product and foreground admissions. `applyCommittedReviewComparisonUpdate`
and `runReviewComparisonPublication` remain the host's attempt and publication
owners; no packaged-only controller or new shared coordinator is introduced.

### Upstream default resolver

`agentstudio-git` supplies the constant-scope operation equivalent to:

```text
resolveReviewDefaultTarget(repositoryPath)
  → GitReviewComparisonBranchTarget?
```

It opens the repository, looks up only `refs/remotes/origin/HEAD`, validates the
symbolic target, opens that one remote-tracking ref, and peels one commit. It
does not create a branch iterator or call a fetch/write API. The host may use
the resolved branch target for automatic initialization, but pane presentation
projects only its remote and branch names into the compact default identity.

## Request-scoped catalog flow

```text
React picker       Comm worker       Native provider      Producer actor      Git scheduler
     │                  │                    │                   │                   │
     │ picker opens     │                    │                   │                   │
     ├─────────────────►│                    │                   │                   │
     │                  │ query command      │                   │                   │
     │                  ├───────────────────►│ authorize + store  │                   │
     │                  │                    │ reservation        │                   │
     │                  │◄───────────────────┤ descriptor         │                   │
     │                  │                    │ control settled    │                   │
     │                  │ content.open       │                   │                   │
     │                  ├───────────────────►│ register task      │                   │
     │                  │                    │ task consumes      │                   │
     │                  │                    │ reservation once   │                   │
     │                  │                    ├──────────────────►│ capture time      │
     │                  │                    │                   ├──────────────────►│
     │                  │                    │                   │ bounded Git read  │
     │                  │                    │                   │◄──────────────────┤
     │                  │                    │                   │ encode/truncate/  │
     │                  │                    │                   │ hash              │
     │                  │◄───────────────────┤ accepted/data/end  │                   │
     │                  │ validate + decode  │ release           │                   │
     │ ready result     │                    │                   │                   │
     │◄─────────────────┤                    │                   │                   │
```

The query command performs only bounded authorization and reservation work.
The request task created through the existing producer registry owns the
content request lifetime. Registration creates that task before provider state
is touched. As its first operation, the task consumes the exact pending
reservation. Successful consumption permits producer invocation. Failed
consumption still emits accepted framing followed by the exact non-retryable
unsupported-content terminal, and never invokes production. A registration
rejection therefore cannot strand claimed provider state. The task propagates
cancellation into production. The actor is the computation owner; the task is
the sole post-consumption lifetime owner. Neither replaces the existing Git
scheduler, which continues to own Git capacity and fairness.

### Product call

Add `review.comparisonTargets.query` to the exhaustive Swift and TypeScript
call registries. Its request contains no repository path, ref, cutoff, or
capacity override. Pane composition supplies repository authority, current
symbolic target, and product policy through one live read-only projection. The
projection atomically returns the current repository authority and current
symbolic branch/ref identity at query admission. `localDefaultBranch`,
`originDefaultBranch`, `branch`, and branch-backed `ref` targets map to
`currentBranchReference`; an exact commit maps to `nil` because it is not a
branch-catalog row.

Both hosts inject the same projection contract. In the packaged host it reads
the controller's current `bridgePaneState`; in the development host it reads
the host's current `paneState`, including mutations applied after provider
construction. The projection creates no new state owner and cannot mutate pane
intent.

The successful result is a strict `review.comparisonTargets` authorization
descriptor:

```text
content kind
descriptor identity
maximum bytes
```

The existing control and `content.open` envelopes carry pane, session,
Review-surface, and worker authority on the wire. The provider-owned reservation
records the issuing envelope authority and matches it against the existing
`content.open` fields. No authority fields are added to the descriptor itself.
The descriptor can be consumed once. It does not contain capture time, cutoff,
declared byte length, or expected SHA-256 because production has not occurred.
The accepted content header therefore uses the transport's existing unknown
length/digest form bounded by `maximumBytes`; the terminal reports exact
observed byte length and SHA-256. Capture time and cutoff appear in the produced
catalog body. The Swift and TypeScript contracts remain strict and exhaustive
through the dedicated `contentKind` discriminant; these facts are not modeled
as optional fields on the old exact-body descriptor. Catalog rows never appear
in the command response.

### Content kind and native demand mapping

Add `review.comparisonTargets` to the exhaustive content registries and strict
JSON contracts. It uses the existing `content.open` request and
accepted/data/end, reset, and error frames.

Because query content is created by an explicit user action rather than a
metadata subscription, demand is mapped directly:

```text
review.comparisonTargets
  → BridgeContentDemandInterest.selected
  → BridgePaneRefreshWorkAdmissionSource.acquire()
  → ordinary foreground content admission
```

It must not fall through `.unspecified` and must not use
`acquireReviewContentContinuation()`, which is for publication-backed Review
body continuation while a pane is loaded but hidden.

The producer's Git capture uses the existing `.selectedVisibleContent` Git
operation class while the content request holds foreground work admission. No
new Git scheduler class or queue is introduced.

The worker snapshots `workAdmissionGeneration` when it starts the query and
binds the query abort controller to the current pane `workSignal`. A completion
is applicable only while that signal remains live and the generation still
matches. Native query dispatch authorizes only while the pane/session authority
is current. The matching `content.open` acquires the existing foreground work
admission before invoking production and retains that admission through the
request lifetime. Foreground loss cancels the request task and production; it
does not reopen or occupy the already settled query control.

## Bounded agentstudio-git capture

The upstream library replaces its unbounded catalog call with two focused
contracts: the default resolver above and one correlated bounded capture.

```text
GitReviewComparisonTargetCaptureRequest
  repositoryPath
  capturedAt              computed when consumed production begins
  cutoff                  derived from capturedAt and product policy
  maximumRows
  currentBranchReference? native-derived from the reservation, never browser-supplied

GitReviewComparisonTargetCapture
  capturedAt
  cutoff
  isTruncated
  defaultReferenceName?       canonical row identity
  currentReferenceName?       canonical row identity
  rows[]
    canonicalReferenceName    unique row identity
    target: local | remoteTracking + exact tip OID
    tipCommittedAt
```

After the reservation is consumed, the producer computes `capturedAt` and the
30-day cutoff and supplies them to one libgit2 repository scope:

```text
resolve default and current refs
        │
        ▼
iterate local + remote-tracking branches once
        │
        ├─ exclude symbolic remote HEAD aliases
        ├─ peel each usable candidate to a commit
        ├─ read tip commit time
        ├─ retain default/current even before cutoff
        └─ retain ordinary candidates where cutoff ≤ tip time ≤ capturedAt
        │
        ▼
deterministic order
  default row first
  distinct current row second
  remaining rows by tip time descending
  then canonical ref name ascending
        │
        ▼
stop at maximumRows and report truncation
```

Canonical ref name is the unique identity of a catalog row. Default resolution,
current-target resolution, and branch iteration may encounter the same ref, but
they collapse to one row before ordering or capacity accounting. The nullable
default/current fields identify roles within that unique row set; they do not
introduce duplicate rows. The row cap counts distinct canonical identities.

The operation is read-only: no fetch, reference write, worktree mutation, or
Git lock is introduced. A branch may move after capture; selection sends its
symbolic identity through the existing correlated comparison-update path,
which resolves current Git truth again.

`agentstudio-git` owns row production and real-Git contract tests. Agent Studio
owns scheduling, Bridge mapping, wire encoding, picker behavior, and integration
proof. The upstream API must be published and the Agent Studio package revision
advanced before the hard cutover can compile; there is no local shadow API.

## Product capacity policy

Concrete initial limits live in `AppPolicies.Bridge`:

```text
reviewComparisonTargetRecencyWindow       30 days
reviewComparisonTargetMaximumRows         2,000
reviewComparisonTargetMaximumEncodedBytes 1 MiB
```

The producer actor derives the cutoff from the recency window at actual
production start and passes the cutoff and row limit to the correlated Git
capture. Bridge owns the encoded-byte limit because it owns the exact JSON wire
representation. The producer encodes the default row first, the distinct
current row second, then ordered ordinary rows until the next unique row would
exceed 1 MiB, and computes the final body digest. Final `isTruncated` is true
when either the upstream row cap or Bridge byte cap omitted an eligible distinct
row.

The 1 MiB body limit is a product policy below the generic transport ceiling;
the theoretical `UInt32` stream maximum is not a capacity decision. These
values are calibrated through the specified real-repository and browser proof,
not exposed as compatibility promises.

The selector uses `@tanstack/react-virtual` with a local fixed overscan of eight
rows. The virtualization remains comparison-selector-local until another owned
Combobox needs identical semantics.

## Reservation and task lifecycle

The existing `BridgePaneProductSchemeProvider` actor owns one small unclaimed
comparison-target authorization reservation per pane session. The reservation
contains the descriptor identity, content kind, maximum bytes, current
repository/target authority snapshot, and issuing worker/session/surface
identity. It contains no catalog rows, encoded body, digest, capture time,
running task, or producer implementation.

```text
query authorized
      │ provider stores reservation + returns descriptor
      ▼
Pending in provider
   │
   ├─ newer query replaces ───────────────────────────────► Empty
   ├─ new worker session / pane teardown ────────────────► Empty
   │
   └─ content registration succeeds
          │ registry creates request task
          │ task atomically consumes exact reservation first
          ▼
       Empty in provider + immutable task-local request
          │
          ├─ accepted framing → producer → terminal ─────► task complete
          ├─ cancellation / foreground loss ─────────────► task retired
          └─ production error / reset ───────────────────► task retired
```

Rules:

1. At most one unclaimed reservation exists per pane session.
2. A newer successful query atomically replaces the current pending reservation;
   it does not own or replace an older already-running task.
3. The existing session validates and registers `content.open` before any
   provider reservation is consumed. Registration rejection leaves no claimed
   provider state.
4. The registry-created task must match the descriptor and issuing
   worker/session authority, then atomically consume the pending reservation as
   its first comparison-target operation. Consumption precedes accepted framing
   and producer invocation. A descriptor cannot be consumed twice.
   `content.accepted` establishes transport admission for the registered
   operation; it does not assert successful reservation consumption. A failed
   consumption therefore enters accepted framing only to carry the existing
   typed terminal content failure and never invokes the catalog producer.
5. After consumption, the provider is empty. The immutable request value belongs
   only to the registry task, which owns cancellation, framing, terminal cleanup,
   and producer invocation.
6. Worker-session open/replacement explicitly removes an unclaimed reservation
   issued to the old worker through the provider control-response seam. Session
   revocation cancels already-registered tasks. Pane teardown retains its
   existing provider/session drain responsibility.
7. An issued descriptor that is never opened remains only as the single small
   reservation until replacement, worker-session replacement, or pane teardown.

There is no provider-owned claimed state, rollback path for rejected
registration, timer, TTL task, cache index, release RPC, background cleanup
service, or retained precomputed body.

## Worker and picker state

The main-thread/worker protocol adds one Review query command, one correlated
result, and one cancellation intent. These are application messages over the
existing worker boundary, not native transports or metadata events.

The comm worker owns the query `AbortController`, invokes the product call,
opens the returned descriptor with `.selected` demand, validates the content
frames and JSON schema, and returns only the newest correlated result. The
picker owns presentation state:

| State | Enter | Exit and invariant |
| --- | --- | --- |
| idle | picker closed | picker open starts a query |
| loading | picker open or failed-state retry | newest result, failure, close, or supersession |
| ready | newest catalog decoded | select or close; no implicit refresh transition |
| empty | newest catalog has no choices | Commit remains available |
| failed | current query fails | explicit retry or close; current comparison unchanged |

Opening the picker starts one query regardless of remembered mode, while focus
still follows the remembered Branch or Commit input. Switching modes preserves
that in-modal preload; it does not start or cancel another request. Closing,
pane-session replacement, or a newer query makes the older request identity
inadmissible; late results are discarded. Foreground loss aborts through the
same worker `workSignal` and invalidates the captured
`workAdmissionGeneration`; it does not create a second picker lifecycle.

After native provider dispatch begins, the generic control replay contract may
finish the command even when the UI request has become obsolete. In that case
the worker does not open or apply the descriptor. Native state retains at most
the single small reservation until replacement or session teardown; no Git or
body work has started. This preserves generic command replay semantics without
retaining a precomputed catalog.

The Branch selector keeps the owned Base UI/shadcn-style Combobox primitives.
Filtering covers the full returned catalog; `Combobox.useFilteredItems()` feeds
the external virtualizer; item indices and highlight scrolling preserve
keyboard and active-descendant behavior. Each virtual row continues to render
the unambiguous branch name, local or remote-tracking kind, abbreviated target
revision, full assistive revision, and query-snapshot `Default` marker. Capture
cutoff and truncation state remain query data, so every ready or empty result
renders only the concise 30-day explanation adjacent to the list. Truncation
remains available for diagnostics and proof but does not add picker copy. None
of that enters pane metadata.

## Call-path delta

```text
PRESERVED — CURRENT COMPARISON, PACKAGED
Review initialization
  → clear compact default identity
  → capture repository + Review/admission identity
  → provider.resolveReviewDefaultTarget()
  → scheduler(.reviewMetadata)
  → libgit2 opens and peels one designated ref
  ← default target or nil/error
  → controller revalidates repository + Review/admission identity
  → current completion publishes default symbolic identity
  → no durable intent: existing mutation initializes from resolved default
  → refresh coordinator writes compact comparison presentation
  → pane.presentation metadata

PRESERVED — CURRENT COMPARISON, DEVELOPMENT
Host construction or comparison attempt
  → remove construction-time catalog read and clear compact default identity
  → capture repository + product/foreground admission
  → shared Git client resolveReviewDefaultTarget()
  → scheduler(.reviewMetadata)
  → libgit2 opens and peels one designated ref
  ← default target or nil/error
  → development host revalidates repository + admissions
  → refresh coordinator writes compact default symbolic identity
  → existing development presentation publication

CURRENT — REQUESTED CATALOG DEFECT
Comparison picker opens
  → worker review.comparisonTargets.query
  → session stores sole pendingControl
  → dispatcher awaits provider response
  → provider awaits queryReviewComparisonTargets()
  → query source acquires foreground admission and computes capture time/cutoff
  → scheduler(.selectedVisibleContent)
  → libgit2 bounded correlated capture
  ← capture or query-local error
  → query source maps, encodes, truncates, and hashes the body
  → provider stores completed body + exact descriptor
  ← query response; session finally settles pendingControl
  → content.open claims and replays buffered body
  ← catalog frames or reset/error

TARGET — REQUESTED CATALOG
Comparison picker opens
  → worker captures work generation + binds workSignal
  → worker review.comparisonTargets.query
  → provider reads live repository/target projection
  → provider authorizes and atomically installs one reservation
  ← single-use descriptor; query control settles
  → content.open(.selected)
  → session validates/registers content and producer registry creates task
  → task atomically consumes exact provider reservation before accepted framing
  → task acquires/holds foreground admission
  → injected catalog producer computes capture time/cutoff
  → scheduler(.selectedVisibleContent)
  → libgit2 bounded correlated capture
  ← capture or content-local error
  → producer maps, encodes, truncates, and hashes body
  ← catalog frames with exact terminal length/digest, or reset/error
  → worker validation + work-generation/latest-request admission
  → React virtualized rows
```

| Edge | Status | Result/error behavior |
| --- | --- | --- |
| Packaged/development compact default resolver → pane presentation | intentionally unchanged | startup remains independent from catalog size; stale completion and failure behavior stay authoritative |
| metadata strict contracts reject `targetCatalog` | intentionally unchanged | catalog remains absent from pushed presentation |
| resolved default → compact symbolic identity → UI target comparison | intentionally unchanged | one pushed fact continues to classify active or displayed symbolic targets |
| Picker open → worker work generation/signal → query command → typed native call | intentionally unchanged | foreground loss or correlated failure affects picker only |
| query command → provider capture/encode/hash → exact descriptor | removed | control no longer spans production or retains a completed body before open |
| native live authority projection → reservation → descriptor | changed | bounded authorization settles without capture, encoding, truncation, or hashing |
| descriptor → content.open → session registration → producer-registry task → atomic reservation consumption | added | registration rejection cannot strand a claim; successful consumption precedes accepted framing and leaves the control lane free |
| producer task → injected catalog producer → Git scheduler → encoding/digest | added | production is content-local, bounded, cancellable, and reports exact terminal facts |
| decoded catalog → virtualized selector | intentionally unchanged | bounded mounted rows; full returned set remains searchable |
| target selection → `review.comparison.update` → `core.sqlite` intent | intentionally unchanged | catalog OID is never mutation authority |
| comparison capture/publication/invalidation/origin flow | intentionally unchanged | PR0 comparison behavior remains authoritative |

Source anchors include
`BridgePaneController+ReviewContribution.swift`,
`BridgePaneRefreshAdmissionCoordinator.swift`,
`BridgeDevelopmentProductHost.swift`,
`BridgeDevelopmentProductHost+ReviewComparison.swift`,
`BridgePaneProductSchemeProvider.swift`,
`BridgeProductSchemeControlDispatcher.swift`,
`BridgeProductSession.swift`,
`BridgePaneProductComparisonTargetQuerySource.swift`,
`BridgePaneProductSchemeProvider+ComparisonTargetContent.swift`,
`BridgeProductProducerRegistry.swift`,
`BridgePaneProductContentDemandAuthority.swift`,
`bridge-comm-worker-product-controller.ts`,
`bridge-worker-rpc-client.ts`, and the pinned
`LibGit2ReviewComparisonTargetReader.swift`.

## Failure, ordering, and cleanup

```text
default resolver unavailable
  → compact default identity remains absent
  → restored current comparison remains eligible to proceed
  → no branch enumeration fallback

query authorization failure
  → no reservation and correlated picker failure
  → current comparison and durable intent unchanged

content registration rejection
  → no provider reservation is consumed
  → existing content rejection; no producer starts
  → pending reservation remains bounded until replacement/session invalidation

reservation consumption mismatch / replacement / second open
  → task emits content.accepted and waits for exact worker observation
  → task emits terminal content.error(unsupported_content, retryable: false)
  → no production begins and provider retains no claimed state
  → picker failure; comparison unchanged

Git capture / encode / admission failure after consumption
  → content reset/error and correlated picker failure
  → task-local request retires; provider is already empty
  → current comparison and durable intent unchanged

oversize / terminal digest / decode failure
  → existing content error or reset
  → request task retires; provider is already empty
  → picker failure; comparison unchanged

close / newer query
  → abort worker content work when possible
  → reject late result by query identity in all cases
  → cancel task-local production, or replace the one pending reservation

foreground loss during Git capture
  → abort worker query through pane workSignal
  → invalidate worker workAdmissionGeneration
  → producer-registry request task cancels production
  → task retires; provider owns no consumed state

worker-session replacement
  → new worker-session open removes an old unclaimed reservation in provider
  → old session revocation cancels registered task-local production

pane close
  → reject old capability and query identity
  → provider/session drain removes pending reservation and cancels tasks
```

Product-control sequencing still serializes native query calls per session, but
that serialization ends after bounded authorization and reservation. The
existing scheme-provider actor provides the atomic pending-to-consumed boundary,
then retains no claimed state.
The focused producer actor isolates comparison-catalog computation from the
provider's communication state; the existing Git scheduler actor still owns Git
capacity and fairness. Existing session, worker derivation epoch, product
admission, content request, query identity, pane `workSignal`, and work-admission
generations provide stale-result rejection. The live repository/target
projection is a read-only view of existing host state, not another authority.
No global generation, mutex, retry scheduler, generic producer actor, or
cross-pane coordinator is added.

The controlling interleaving is explicit:

```text
query A authorization     reserve A ──► descriptor A ──► control A settled
content.open A            register task ──► consume A ──► producer A held
unrelated control B       admitted ──► completed while producer A remains held
content A resumes         encode/hash ──► frames/terminal ──► retire task A
```

Provider reentrancy is not the correctness claim. The invariant is that
`BridgeProductSession.pendingControl` no longer spans catalog production.

## Cross-cutting realization

- Performance and capacity: `AppPolicies.Bridge` owns the capture window and
  row/byte bounds; the Git scheduler, content admission, producer actor, and
  virtualizer enforce them at their respective boundaries. Production telemetry
  distinguishes authorization, reservation wait, Git queue/capture, encoding,
  and terminal delivery.
- Reliability: compact comparison metadata is independent from query success;
  product/session identities and the reservation lifecycle contain late,
  cancelled, or malformed results.
- Accessibility: the owned Combobox remains the semantic control; external
  virtualization preserves active-descendant, keyboard highlight, selection,
  scroll-to-highlight, full assistive revisions, and distinguishable local and
  remote-tracking rows rather than replacing them with custom rows.
- Trust and containment: the browser cannot choose a repository path or product
  capacity, strict schemas validate the call, descriptor, and body, and the
  existing pane capability and session authority gate both physical routes. No
  new secret, privilege, or external actor is introduced.
- Data lifecycle and privacy: the catalog is local repository metadata retained
  only in ephemeral picker state while content is open. The provider retains
  only one small authorization reservation; neither is persisted or exported.
- Platform parity: packaged WKWebView and the Swift development backend compose
  the same native providers and differ only at the existing URL mapping.

## Structural enforcement and observability

The separation is enforced at three layers without a capability-token system:

1. **Type and dependency boundary.**
   `BridgeReviewComparisonTargetCatalogProducing: Sendable` exposes one async
   production operation. The concrete producer actor owns the Git source and
   encoder dependencies. Query authorization receives only the live authority
   projection, policy needed to construct a reservation, and reservation state;
   it cannot see production dependencies. The content-open path receives the
   injected protocol existential and may invoke any conforming actor or test
   implementation. There is no `ProducerContext`, factory, registry, or dynamic
   plugin API.
2. **Targeted architecture lint.**
   A SwiftSyntax rule scoped specifically to the comparison-target query
   control-response path rejects direct calls to
   `captureReviewComparisonTargets`, catalog body encoding/truncation, body
   SHA construction, and producer invocation from that path. The same calls
   remain legal in the focused producer/content path. Good and bad fixtures plus
   rule-inventory/parity coverage keep the rule narrow and executable.
3. **Behavioral and contract proof.**
   Continuation-gated tests prove query authorization returns while capture
   invocation count remains zero; matching `content.open` starts capture exactly
   once; unrelated control B completes while A production is held; second open,
   replacement, foreground loss, session teardown, retryable content failure,
   and exact terminal byte/digest behavior preserve the lifecycle. Strict
   Swift/TypeScript contract parity proves the authorization descriptor cannot
   carry precomputed-body facts.

Telemetry follows the same ownership split under the existing `performance`
trace tag and `performance.bridge.swift.comparison_target_catalog` event
namespace. It adds no environment selector, exporter, service, or parallel
per-frame event stream:

| Stage | Emitting owner | Safe observation |
| --- | --- | --- |
| query authorization | `BridgePaneProductSchemeProvider` around the existing authorization closure | duration plus controlled `success \| unavailable` outcome |
| reservation consumption | the comparison-specific registered request task immediately after its provider claim attempt | reservation age when claim succeeds plus controlled `claimed \| inactive` outcome |
| Git scheduling | existing `BridgeGitReadScheduler` capacity telemetry for `.selectedVisibleContent` | existing queue-wait duration; no duplicate scheduler event |
| scheduled capture | `BridgeReviewComparisonTargetCatalogProducer` around `captureReviewComparisonTargets` | end-to-end scheduled-capture duration plus controlled `success \| cancelled \| failed` outcome |
| encode and truncate | the same focused producer around `produceCatalog` | duration, input/output row counts, observed encoded bytes, and truncation boolean |
| content terminal | the comparison-specific request task at its existing terminal decision | controlled `complete \| unsupported_content \| production_failed \| cancelled` outcome and observed bytes when complete |

Stage samples emitted while a native reservation is available use its query
request sequence as a controlled numeric correlation value. An inactive claim
with no reservation emits no sequence: the wire descriptor does not carry it,
and the provider does not retain a correlation tombstone after consumption.
The current debug-run marker and worktree resource identity provide run scope.
Events and OTLP attributes MUST NOT contain raw repository paths, Git refs,
descriptor IDs, pane/session/worker IDs, payloads, digests, errors, or
safe-message text.
Existing transport frame telemetry remains authoritative for delivery; the
terminal stage records only the application outcome and aggregate byte count.

Focused recorder tests prove the event names, controlled outcomes, durations,
counts, correlation value, and forbidden-field absence. Marker-scoped debug
proof queries VictoriaLogs for each new stage under one request sequence and
the current launch marker, and uses the existing scheduler event to observe its
queue wait. VictoriaMetrics proof is required only for an existing mapped
metric series; these stage events do not create a new metrics projection.

## Hard cutover and documentation invariants

The established Agent Studio hard cutover keeps `targetCatalog` absent from
native/TypeScript presentation schemas, strict-key corpora, worker projections,
fixtures, and UI props, with compact `repositoryDefaultTarget` as the pushed
identity. This follow-up hard-cuts the comparison-target descriptor from an
exact precomputed-body contract to the strict authorization contract; no legacy
exact-body query variant or dual producer path remains. Existing `core.sqlite`
target intent requires no migration and remains the only durable comparison
selection.

The Swift development backend composes the same default resolver, compact
presentation owner, reservation owner, injected catalog producer, Git client,
admission, command, and content contracts as the packaged scheme provider; it
only maps the physical routes to HTTP for Vite. Host-specific attempt methods
remain separate composition roots, but neither host owns a different
comparison-target contract.

The permanent Bridge architecture must distinguish:

```text
publication-backed exact-body descriptors
  File and Review bodies authorized by committed metadata/publication
  may declare exact length and digest before open

request-scoped production descriptors
  finite data authorized by an explicit typed query result
  declare only maximum bytes before open; accepted/terminal frames carry
  observed production facts
```

Accordingly, the native invariant becomes “publication-backed content follows
metadata publication for that generation”; it must not claim that
request-scoped query descriptors require metadata publication. Demand docs
also record the explicit mapping from query content to native `.selected`
interest rather than implying all content priority is subscription-derived.

## How each requirement is realized and proved

| Requirement | Structural owner and realization | Proof seam |
| --- | --- | --- |
| CT-R1 | per-host repository/admission snapshot, constant default resolver, currentness revalidation, compact default symbolic identity, and shared comparison presentation | native/metadata interleavings prove one default lookup, no catalog enumeration in either host, identity clearing, stale completion rejection, current failure → absent, and correct active/displayed marker derivation |
| CT-R2 | call registry, provider-owned reservation, strict authorization descriptor, content registry, worker query controller | strict contract parity and production-backed command → descriptor → content transcript proving capture count is zero until open |
| CT-R3 | bounded agentstudio-git capture with canonical-ref deduplication plus the focused producer actor's Bridge encoder | real-Git upstream tests and Agent Studio integration cover cutoff and capture-time bounds including a future-dated tip, collapsed default/current roles, ordering, distinct-row capacity, both caps, and no fetch/write |
| CT-R4 | owned Combobox plus external virtualizer and picker state | browser and visual proof cover one query on picker open in either remembered mode, immediate preloaded rows after switching Commit to Branch, focus, row labels/kinds/revisions/accessibility, mounted-row bound, search, keyboard, selection, always-visible concise recency text, and empty state |
| CT-R5 | worker request/work-admission identity and abort plus provider pending-reservation replacement/invalidation and producer-task cancellation | interleaving tests cover registration rejection without consumption, close, mode switches that preserve the in-modal preload, foreground loss before open and during production, supersession, late command/content results, worker replacement, and teardown residue |
| CT-R6 | live current-target projection plus explicit packaged/development compact-current paths and unchanged pane intent, comparison update, publication, and origin owners | both-host initialization and mutation-after-construction coverage, SQLite restart, development-server transcript, and packaged-app regression proof |
| CT-R7 | bounded provider authorization, registration-before-consumption ordering, task-first atomic reservation consumption, existing producer-registry lifetime, injected focused producer actor, and unchanged session control sequencing | continuation-gated transcript proves query A settles before capture; content A attempts consumption before accepted framing; successful consumption invokes production exactly once; stale, replaced, and second-open failures emit sequence 0 `content.accepted` then terminal `unsupported_content` with `retryable: false` and zero producer invocation; unrelated control B completes while A is held; every terminal/cancel/error path leaves zero provider/task residue |

The `agentstudio-git` repository owns public-contract and real-libgit2 proof for
its two reads. Agent Studio must use the published pinned revision in its
production-backed development-server proof; a local fake or TypeScript Git
utility cannot satisfy that boundary.

## Complexity spent and revisit signals

Spent:

- two focused upstream Git reads: constant default resolution and bounded
  catalog capture;
- one application query call and one content kind over existing routes;
- one pane-scoped, single-pending authorization reservation;
- one narrow injectable producer protocol and one focused catalog producer
  actor;
- one targeted architecture-lint rule with fixtures;
- one worker query lifecycle and one standard virtualized selector.

Not spent:

- persistence, caching, cross-pane sharing, pagination, watcher invalidation,
  background warming, network fetch, a new transport, capability tokens, a
  generic producer actor, new producer registry/framework, dynamic plugins, TTL
  cleanup, or a generalized Git browser.

Revisit only if measured Branch-activation latency remains unacceptable after
bounded capture, or if product requirements expand from recent target
selection to complete branch/history browsing. Those signals may justify
pagination or caching later; they do not justify either in this correction.
