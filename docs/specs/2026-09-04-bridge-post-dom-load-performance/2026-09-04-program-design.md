# Bridge Post-DOM Load Performance — Program Design

Date: 2026-09-04

This design realizes
[2026-09-04-specification.md](./2026-09-04-specification.md), authorized by
[2026-09-04-requirements.md](./2026-09-04-requirements.md).

It depends on, and does not replace, the reliable transport and comments
foundation defined by the current Worktree Annotations and Incremental Review
contracts.

## The structure in one picture

PR B adds no delivery system. It observes and improves the existing path.

```text
Swift pane/open authority
  owns: user-perceived open start and native trace root for real
        command-bearing packaged/native paths
       │
       ▼
Browser navigation timing
  owns: DOMContentLoaded start for the focused metric
       │
       ▼
Existing Bridge page handshake and pane runtime
  own: bootstrap request/acceptance and comm-worker readiness
       │
       ▼
Existing File/Review application consumers
  own: command admission, source, metadata, and initial selection
       │
       ▼
Existing generic content demand and transport
  own: selected-content open, frames, completion, and currentness
       │
       ▼
Existing main render fulfillment
  owns: render commit and exact item-content paint correlation
       │
       ▼
Passive usable-paint observation
  owns: first post-commit frame satisfying the complete surface predicate
       │
       ▼
Existing telemetry and proof reduction
  joins: one load identity, ordered stage timestamps, terminal outcome
  reports: post-DOM, switch, end-to-end, stage, and failure distributions
  reports N/A: Swift-command guardrail in development-browser runs that
               have no Swift command start
```

The optimization loop changes measured work inside the existing owner
responsible for the delay; it does not move that ownership. It does not insert
a coordinator between these owners and does not make telemetry part of product
currentness.

## One outcome decides ownership

| Observed outcome | Owning delivery | What PR B does |
| --- | --- | --- |
| No exact current usable terminal because the server/source, recovery/rebind, foreground pane, generic transport, File/Review delivery, annotations/comments, or settled-work lifecycle failed | PR A reliability/correctness | seals the attempt as failed evidence, blocks the cohort, and performs no performance tuning around the failure |
| Exact current usable terminal succeeds but required timing evidence is missing or unjoinable | PR B measurement/proof | seals a failed evidence attempt; makes no correctness or latency conclusion without separate product evidence |
| Exact current usable terminal succeeds, but the applicable File, Review, or switch distribution exceeds p95 600 ms or p99 1,000 ms | PR B post-DOM performance | attributes elapsed time to measured stages and optimizes work in existing owners without changing PR A semantics |
| Exact current usable terminal succeeds within both thresholds | PR B post-DOM performance | records a passing successful attempt; no reliability ownership changes |

The attempt reducer observes this division but does not decide product truth.
PR A's existing authorities decide whether source, metadata, content,
annotations/comments, and paint are current. A failure classified in a PR B
receipt remains owned by PR A for diagnosis and correction.

## Current path and the missing measurement

The development entrypoint currently waits for the Review shell module before
creating the React root. `BridgeApp` creates the pane runtime, installs the page
handshake, receives a product bootstrap, and installs it into the existing
runtime. File and Review consumers establish source and metadata, select an
item, demand content through the generic product transport, and hand final
render work to the existing main render-fulfillment owner.

The existing cold first-interaction metric starts from a native wall-clock open
anchor when available. Warm viewer interaction starts at a viewer mount. The
existing complete-journey harness also records page-start-relative handshake,
metadata, selected-content, route, and visible-content facts. The visible-paint
predicate already requires the active surface, real metadata/selection,
content readiness, visible geometry, and enabled controls.

What is missing is one attempt record that uses the browser's actual
`DOMContentLoaded` boundary, correlates all required post-DOM stages and the
existing exact usable-paint witness, preserves overlaps, and retains terminal
failures. That missing observation is why current page-start, first-interaction,
and selected-content metrics cannot by themselves prove R-PDL-003.

Current evidence anchors:

- `BridgeWeb/src/app/bridge-app-dev-bootstrap.tsx` owns the development module
  preload, runtime construction, and React root creation path.
- `BridgeWeb/src/bridge/bridge-page-handshake.ts` owns product-bootstrap
  request correlation and the page-ready acknowledgement lifecycle.
- `BridgeWeb/src/foundation/telemetry/bridge-viewer-first-interaction.ts` owns
  the current cold native-open and warm mount timing behavior.
- `BridgeWeb/src/foundation/diagnostics/bridge-complete-journey-usable-paint.ts`
  owns the current File and Review usable-paint predicates.
- `BridgeWeb/scripts/verify-bridge-viewer-worktree-dev-server/startup-load-timing.ts`
  owns the current page-start-relative development timing collection.
- `BridgeWeb/src/app/bridge-app.tsx` and
  `BridgeWeb/src/foundation/telemetry/bridge-viewer-activation-telemetry.ts`
  own activation sequence and admitted-viewer timing facts.
- `BridgeWeb/src/core/comm-worker/bridge-main-render-fulfillment-coordinator.ts`
  and `BridgeWeb/src/review-viewer/code-view/bridge-code-view-render-fulfillment.ts`
  own exact render-receipt admission, post-render readback, and item-paint
  correlation.
- `BridgeWeb/src/core/comm-worker/bridge-comm-worker-clock.ts` and
  `BridgeWeb/src/core/telemetry-worker/bridge-telemetry-worker-event-adapter.ts`
  establish the current realm time-origin plus monotonic-now event timestamps.
- The Worktree Annotations PR1 Program Design owns the real
  browser/comm-worker/Swift/SQLite proof boundary; the Incremental Review
  Program Design preserves generic transport and demand-driven content.

## Structural crux and selected direction

The crux is whether performance measurement becomes another runtime authority
or remains a passive projection of facts already owned by the loading path.

| Direction | Gain | Cost and disposition |
| --- | --- | --- |
| Infer stages from browser polling | No production instrumentation changes | Poll cadence distorts boundaries, missing stages are guessed, and cross-process authority cannot be proven; rejected |
| Add a load coordinator or performance service | One central object could own every timestamp | Creates a new lifecycle and second interpretation of transport state; prohibited by R-PDL-011 |
| Correlate existing owner-emitted facts in the existing telemetry path | Preserves each runtime owner and measures the real edges | Requires consistent attempt identity and explicit missing-stage handling; selected |

The selected direction records a timestamp where each existing owner already
knows that its stage occurred, then joins those observations outside product
state. The clock never determines whether metadata or content is current. A
lost observation invalidates performance evidence but cannot block, retry, or
alter the product load.

The cost is additional bounded timing events and reduction work during
instrumented proof. The performance harness/operator bears that cost. The
direction must be revisited only if measurement itself materially changes the
stage distributions or if an existing owner cannot expose a required boundary
without changing product semantics.

## Owners and responsibilities

```text
Bridge post-DOM performance proof
  readiness verifier
    owns: exact composition asset-host/Swift/workload preflight result
    consumed by: performance attempt driver
    changes when: the existing readiness contract changes

  browser navigation observer
    owns: navigation identity and DOMContentLoaded timestamp
    consumed by: telemetry reduction
    changes when: browser timing boundaries change

  existing runtime stage emitters
    own: timestamps at their existing authoritative transition
    consumed by: existing telemetry recorder/worker
    change when: the corresponding runtime owner changes

  existing usable-paint witness
    owns: exact File/Review terminal predicate and paint correlation
    consumed by: attempt terminal reduction
    changes when: usable File/Review meaning changes upstream

  performance reducer and verifier
    owns: stage join, missing-stage/failure classification, cohort grouping,
          proof-only attempt expiry, percentiles, before/after comparison,
          immutable run receipt, and report
    consumed by: maintainers and proof gates
    changes when: the specification's measurement contract changes
```

These are responsibilities inside existing readiness, telemetry, diagnostics,
and proof-harness owners. They are not new services, stores, schedulers, or
product coordinators.

## Passive attempt join graph

One proof attempt is rooted by the existing proof marker plus one current
navigation entry for an initial load, or one admitted activation sequence for a
mode switch. It contains no raw path, source text, diff, comment, credential,
or transport payload. Each later observation must connect through the existing
identity in the preceding product edge; neither timestamp proximity nor event
arrival order is an identity link.

Each stage observation contains:

```text
performance attempt identity
stage kind
monotonic timestamp in the emitting clock domain
existing trace/correlation context when crossing a process or worker boundary
viewer or switch direction
terminal outcome or bounded failure reason when applicable
```

The complete passive join is:

| Stage | Current authoritative owner and identity | Exact attempt-link edge | Clock domain and conversion | Stale or unjoinable disposition |
| --- | --- | --- | --- | --- |
| `dom_content_loaded` | Browser Navigation Timing; current document navigation entry | proof marker + current navigation entry + requested viewer | browser-window monotonic; `window.performance.timeOrigin + domContentLoadedEventStart` | missing, zero, duplicate-current, or wrong-document entry rejects the attempt |
| `product_bootstrap_requested` | `installBridgePageHandshakeSession`; product bootstrap request ID | request ID minted by the current document's initial request and attached to its navigation attempt | browser-window monotonic converted with captured window time origin | request from another document, replacement reason, or unrecognized request ID cannot join |
| `product_bootstrap_accepted` | page handshake pending-request admission; same request ID plus accepted worker instance ID | exact request ID must consume the pending ID from the preceding stage; worker instance becomes the next link | browser-window monotonic with the same captured time origin | unsolicited, duplicate, malformed, or different-request result is rejected |
| `comm_worker_ready` | worker runtime produces the matching ready health result and the pane comm-worker session admits it; bootstrap request ID, worker instance ID, and pane session ID | ready request ID must equal the pane session's bootstrap request, accepted bootstrap worker instance must still be current, and pane session must be the attempt's session | browser-window monotonic timestamp when the pane session admits the matching ready result | replaced worker, different request/pane session, or a ready result after retirement cannot join |
| `viewer_command_admitted` | `BridgeApp` navigation admission; navigation command ID/binding revision when present, otherwise initial requested viewer bound to the pane session; activation sequence for switches | initial load joins current navigation + accepted pane session + requested viewer; switch joins exact activation sequence and destination viewer | browser-window monotonic with the attempt's window origin | stale command/binding, wrong destination, or different activation sequence is rejected |
| `source_established` | active File/Review source owner; exact source identity/generation and active-mode session/sequence | source must be the admitted viewer's current source under the same pane/activation; Review also retains exact package/query lineage | source observation uses its emitting main/worker clock and the captured origin relation | retired generation, wrong viewer, wrong active-mode session, or unmappable clock fails the stage |
| `metadata_installed` | File metadata projection or Review candidate/promotion owner; File source generation/revision or exact Review publication identity | installed metadata identity must descend from the established source and be active for the requested viewer | worker/main monotonic converted only through captured finite time origins | reset/replacement from another source, non-current candidate, or clock mismatch cannot join |
| `initial_selection_committed` | File selection owner or Review selection controller; selected item/path identity plus source/publication identity and activation/demand sequence when present | selection must belong to the installed metadata identity and the requested viewer | browser-window monotonic; worker-origin observations require the same explicit origin mapping | selection from stale metadata, another activation, or another item lineage is rejected |
| `selected_content_opened` | generic content-demand operation; operation correlation ID plus exact content descriptor/handle identity | open must be caused by the joined selection and carry its current source/publication identity | worker monotonic mapped by captured worker/window origins | unrelated operation, stale descriptor, duplicate new operation, or missing mapping is rejected |
| `selected_content_completed` | generic content stream terminal; same operation correlation ID and descriptor/handle identity | exact open operation must reach its valid terminal with current content identity | worker monotonic using the same origin mapping as open | incomplete, rejected, superseded, mismatched operation, or invalid terminal fails the attempt |
| `render_committed` | existing main render-fulfillment post-render seam; full render receipt identity | after joined selected content is applied, the first current matching `observePostRender`/readback for that exact receipt and final item commits this stage | browser-window monotonic at the matching post-render readback | queueing, item submission, `queued`, stale readback, disconnected/mismatched item, or item-only paint cannot commit this stage |
| `usable_paint` | passive proof observation using the complete File/Review usable-paint predicate; attempt identity plus current source/publication and render receipt | only frames after `render_committed` are eligible; first matching frame terminates exactly once | browser-window `requestAnimationFrame` timestamp in the same monotonic domain | wrong active viewer, stale source/render receipt, incomplete predicate, late frame, or post-terminal frame is ignored/rejected; expiry owns failure |

Browser-window and comm-worker timestamps become comparable only through an
explicit relation captured for that attempt: each realm supplies its finite
`performance.timeOrigin`, and each event supplies its realm-local monotonic
`performance.now()` value. The reducer forms epoch-relative timestamps from
those captured pairs. It rejects a missing origin, a non-finite value, a mapped
time outside the attempt's possible interval, or an ordering that violates a
causal identity edge. It never estimates clock offset from message arrival.

The Swift command start is joined differently because it already crosses the
native/browser boundary through the native viewer-open epoch and traceparent.
Only a real command-bearing packaged/native attempt with that existing
trace/open correlation gets an end-to-end duration. A development-browser
attempt has no Swift command start, reports the guardrail as not applicable,
and never substitutes navigation, preflight, or Vite time.

For an initial navigation, T0 is the current navigation entry's
`domContentLoadedEventStart` expressed in the browser's monotonic time domain.
This remains recoverable when the measurement observer installs after the
event. A missing, zero, or non-current navigation entry invalidates the
attempt. Stages already completed before T0 retain signed negative offsets in
the stage record and the end-to-end view; they contribute no post-DOM wait but
cannot be hidden by clamping them to T0.

The required stage vocabulary is fixed by R-PDL-005:

```text
dom_content_loaded
product_bootstrap_requested
product_bootstrap_accepted
comm_worker_ready
viewer_command_admitted
source_established
metadata_installed
initial_selection_committed
selected_content_opened
selected_content_completed
render_committed
usable_paint
```

Existing operation correlation, activation sequence, publication/source
identity, and render receipt identity remain authoritative within their current
owners. The measurement attempt references those bounded correlations; it does
not replace them with one new product identity.

An interleaved attempt cannot donate a stage merely because its viewer,
timestamp, source generation, or item ID looks compatible. Every join must
follow the exact identity chain above. Supersession closes the earlier attempt;
all later observations carrying its bootstrap request, activation, operation,
publication, or render receipt are late evidence and cannot enter the successor.

## Initial-load sequence

Legend: `[=]` is an intentionally unchanged product edge; `[+]` is added
observation or reduction behavior. Every product result/error edge remains
owned by PR A.

```text
Driver        Browser/App       Handshake/Worker      File/Review       Native/Transport      Main/Paint
  |                |                    |                  |                   |                  |
  |-- preflight ------------------------------------------------------------->| [=] health
  |<-- exact runtime/workload ready ------------------------------------------| [=]
  |-- navigate -->|                    |                  |                   |                  |
  |                | DOMContentLoaded  |                  |                   |                  |
  |                |-- observe T0 ------------------------------------------------------------->| [+]
  |                |-- bootstrap req ->|                  |                   |                  | [=]
  |                |   observe --------|------------------------------------------------------->| [+]
  |                |<-- bootstrap -----|                  |                   |                  | [=]
  |                |   accepted/worker ready observations ------------------------------------>| [+]
  |                |                    |-- command ------>|                   |                  | [=]
  |                |                    |                  |-- source/metadata>|                  | [=]
  |                |                    |                  |<-- current facts -|                  | [=]
  |                |                    |                  |-- select/demand ->|                  | [=]
  |                |                    |                  |<-- content frames-|                  | [=]
  |                |                    |                  |-- content applied ---------------->| [=]
  |                |                    |                  |       matching post-render readback | [=]
  |                |                    |                  |       observe render_committed ---->| [+]
  |                |                    |                  |       next eligible animation frame | [+]
  |                |<----------------------------------------------- full usable predicate true -| [+]
  |                |   stage observations at each owning edge -------------------------------->| [+]
  |<-- success/failure + distributions ---------------------------------------------------------| [+]
```

Current source anchors for the preserved path include the development
bootstrap, page handshake, pane runtime, File/Review metadata consumers,
generic content transport, render-fulfillment coordinator, first-interaction
telemetry adapter, complete-journey usable-paint predicate, and Swift-backed
development proof harness. The implementation plan will resolve exact edit and
test files from those owners; this design does not prescribe task order.

## Mode-switch sequence

No DOM boundary occurs during a mode switch. The existing activation command
is the start authority.

```text
Reviewer/native      BridgeApp        Destination consumer     Transport       Paint
      |                  |                     |                    |             |
      |-- activate ----->|                     |                    |             |
      |                  | admit + T0          |                    |             |
      |                  |-------------------->| source/currentness |             |
      |                  |                     |-- demand if needed>|             |
      |                  |                     |<-- content --------|             |
      |                  |                     |-- render ----------------------->|
      |<------------------------------------------------ usable destination -----|
      |                  |                     |                    |   T1/report |
```

Previously mounted or retained destination state may satisfy intermediate work
only when its existing PR A identities prove it current. Mount presence alone
cannot skip source, selection, content, or exact paint checks.

## Render commit and usable paint are different stages

The existing main render-fulfillment coordinator already distinguishes
accepted, queued, applied, post-render readback, and a later animation-frame
paint disposition for an exact render receipt. PR B observes this seam without
changing its product decisions.

`render_committed` is recorded at the first current matching post-render
readback after the selected content has been applied. The readback must resolve
the exact final item and render receipt and must show the connected current
render target. Queue submission, `queued`, item binding, or worker publication
does not qualify.

After that commit, the proof observer schedules one passive
`requestAnimationFrame` observation at a time for the still-current attempt.
On each eligible frame it evaluates the complete File or Review usable-paint
predicate: requested surface active and visible, current metadata and
selection, demanded content ready, visible tree/content geometry, and enabled
navigation/reading controls. It emits `usable_paint` exactly once at the first
satisfying frame, then cancels further observation.

The existing item-specific Pierre `painted` receipt may prove that the selected
content identity reached a connected rendered item. It cannot by itself prove
the requested surface is active, the complete metadata and selection are
current, the view has visible geometry, or controls are enabled. It therefore
supports the final predicate but never substitutes for `usable_paint`.

This animation-frame observation belongs to the proof attempt. It does not
schedule product work, acknowledge transport, alter rendering, retry demand,
or create a product timeout.

## Attempt state and legal transitions

The performance reducer, not the product runtime, owns this ephemeral state.

| State | Stored measurement material | Legal transition |
| --- | --- | --- |
| Not admitted | readiness result only | successful preflight plus navigation/activation creates Attempting |
| Attempting | attempt identity, start, observed stages, one proof-driver expiry handle, optional next-frame observation | joined stage remains Attempting; usable paint becomes Succeeded; explicit fault, supersession, or expiry becomes Failed |
| Succeeded | complete stage record and one usable-paint terminal | immutable; duplicate stages/terminals are classified evidence errors |
| Failed | partial stage record and one bounded failure | immutable; recovery creates a new attempt |

An attempt cannot return from Succeeded or Failed to Attempting. A stage from a
different attempt, stale authority, or incompatible viewer is rejected from
the record and classified. Readiness lost after admission transitions the
attempt to Failed. Readiness absent before navigation remains Not admitted and
is reported as preflight failure rather than latency.

The proof driver owns one 30,000 ms maximum expiry measured from the attempt
start: DCL for an initial load and admitted activation for a switch. Success
cancels expiry and any pending frame observation. Supersession first writes one
failed `superseded` terminal with all completed stages, then cancels expiry and
frame observation. Expiry writes one failed `attempt_expired` terminal with the
last completed stages. Any late stage or usable frame after a terminal is
rejected. The 30,000 ms boundary is proof-evidence lifecycle, not a product
timeout, retry policy, product timer, or product scheduler.

## Stage-accounting rules

- Owners timestamp the transition they own; the reducer does not infer an
  earlier stage from a later one.
- Stage timestamps remain absolute within their clock domain so overlap and
  pre-T0 work are visible. Derived intervals are not required to sum to the
  total.
- The report shows the interval between adjacent required observations and an
  explicit unaccounted interval where instrumentation cannot attribute time.
- A missing required observation makes the attempt failed evidence even when
  the page later looks usable.
- Duplicate idempotent observations with the same existing authority may be
  equality-suppressed. Conflicting duplicates fail the attempt record.
- Telemetry backpressure or exporter loss never changes product loading. It
  invalidates the affected performance attempt and is reported as evidence
  loss.
- Deterministic tests drive attempt expiry through the proof driver's
  controlled clock; product code never sleeps or waits on this evidence limit.

## Optimization loop inside existing owners

```text
collect complete stage distributions
             │
             ▼
rank intervals by p95/p99 contribution and failure incidence
             │
             ▼
inspect the existing owner and its current call path
             │
             ├─ redundant work      → remove or equality-suppress it
             ├─ false serialization → overlap existing independent work
             ├─ repeated work       → preserve existing valid residency/identity
             ├─ oversized work      → keep metadata/content demand proportional
             └─ authority failure   → return to PR A reliability, do not tune around it
             │
             ▼
candidate and accepted-baseline receipts with an exact comparability-key match
             │
             ├─ improves without regression → retain
             └─ no contribution/regression  → reject or revise
```

The allowed mechanisms are changes to work already owned by the existing
bootstrap, worker, application consumer, transport, content preparation, and
render paths. Existing bounded caches may be used according to their current
identity and eviction contracts; this design neither adds one nor expands a
cache's correctness authority.

## Failure, recovery, and concurrency

```text
preflight cannot bind exact development Vite/Swift/workload or packaged app/native route
  -> do not admit latency sample
  -> report preflight failure

source dies or authority resets after DOMContentLoaded
  -> fail admitted attempt at last completed stage
  -> PR A may recover/rebind product state
  -> any later measurement is a new attempt

load reaches timeout without usable paint
  -> proof driver expires exactly 30,000 ms after attempt start
  -> one attempt_expired terminal; retain partial stage record
  -> never leave an open measurement or drop it from population

completed demand becomes desired again or work loops after settlement
  -> PR A reliability/correctness failure, not a PR B performance miss
  -> seal failed evidence; PR A owns correction before the cohort can pass

exact current usable terminal succeeds above the latency target
  -> PR B performance miss
  -> retain successful duration and optimize the measured contributing stage
  -> preserve all PR A authority, delivery, recovery, and failure semantics

newer navigation/activation supersedes an attempt
  -> earlier attempt records exactly one superseded failure terminal
  -> cancel its expiry and pending frame observation
  -> stages cannot cross between attempts

late stage or usable frame arrives after success/failure/supersession
  -> reject from the immutable terminal attempt
  -> never reopen or rewrite the attempt

telemetry event is late, duplicated, or out of order
  -> accept only when existing identity and timestamp rules prove one attempt
  -> equality-suppress exact duplicate
  -> conflicting or unjoinable observation fails measurement evidence

telemetry recorder/exporter unavailable
  -> product remains fail-open
  -> performance claim fails closed for that attempt/cohort
```

Several stages may overlap: bootstrap delivery can race application mount,
source work may begin while worker initialization finishes, and metadata may
establish selection before all unrelated metadata work settles. The reducer
preserves timestamps rather than imposing a serial pipeline. Product
currentness remains governed by PR A's subscription, generation, revision,
operation-correlation, publication, and render-receipt identities.

## Immutable run receipts and valid comparisons

The reducer seals one immutable receipt per measured run. Its run identity
includes its own source revision, actual measurement window, method/version,
runtime and workload description, all admitted attempts, terminal outcomes,
stage observations, and distributions. A later source revision always produces
a different receipt.

Before candidate measurement is evaluated, the proof driver names one
inspectable prior receipt as the accepted baseline. Candidate and baseline may
have different source revisions, but the comparison is admitted only when this
entire key is equal:

```text
viewer or switch direction
runtime composition
build mode
hardware class
workload/fixture identity and shape
cache/warmth state
measurement method/version
measurement-window policy
```

The actual window and source revision remain on each receipt; they are not
folded into the cross-revision key. A mismatched key keeps both receipts useful
for diagnosis but yields `not_comparable`, never a contribution or
no-regression result. The reducer does not normalize hardware, workload,
warmth, runtime, or method differences after collection and does not choose a
more favorable baseline after seeing the candidate.

For real command-bearing packaged/native receipts, the reducer joins the
existing native trace/open start to the exact same `usable_paint` terminal and
reports the end-to-end guardrail. Development-browser receipts without a Swift
command record `swift_command_guardrail: not_applicable` with that reason and
carry no substitute start or duration.

## Capacity, privacy, and operability

The attempt record is fixed-size apart from the bounded stage set and one
bounded failure classification. The proof reducer retains only the cohort's
measurement records for the proof window. It stores no source files, metadata
catalog, diff bodies, comments, transport frames, or application state.

Existing telemetry scrubbing remains authoritative. Exported fields are
controlled stage/viewer/runtime/outcome values, durations, counts, and scrubbed
correlation. Raw paths, worktree identifiers, source text, diff text, comments,
credentials, payloads, and errors do not cross the OTLP boundary.

The instrumented path must be measured against an instrumentation-disabled or
minimal-instrumentation control. Material measurement overhead is a failed
proof condition, not a reason to subtract estimated overhead from the result.

## Development and packaged proof topology

The proof path follows production boundaries. Only the driver and observation
sink are proof-owned.

```text
performance driver
  -> real browser or packaged WKWebView
  -> production Bridge application
  -> production comm worker
  -> production generic metadata/content transport
  -> real Swift source and agentstudio-git/filesystem work
  -> production File/Review consumer and renderer
  -> exact production usable-paint witness
  -> existing telemetry sink and cohort reducer
```

Real boundaries: browser/WKWebView, Bridge application, worker, transport,
Swift source, filesystem/Git workload, metadata consumers, demanded content,
and renderer. The workload repository may be a controlled rich fixture, but
its data shape and operations are real. Replaced boundaries are limited to the
human driver and external telemetry collection sink. A one-line in-memory
metadata fixture is not valid performance proof.

The development readiness verifier binds Vite origin/port, Swift
source-server process, and workload health. The packaged verifier binds the
exact app instance, embedded asset, and native product operation route. Neither
composition may reuse a readiness result from a different launch.

At least 100 attempts are collected separately for initial File, initial
Review, Review-to-File, and File-to-Review in each claimed runtime cohort.
Failures remain in the population report. Percentiles use successful terminal
durations only and cannot pass while an unresolved jam or missing terminal is
present.

Each collected run seals its source revision and complete attempt population
before reduction. A contribution or no-regression proof names its accepted
baseline receipt before candidate evaluation and validates the exact
comparability key before calculating any comparison.

## Requirement realization and proof seams

| Requirement | Existing owner or boundary | Proof seam |
| --- | --- | --- |
| R-PDL-001 | browser navigation timing plus existing telemetry adapter | current navigation `domContentLoadedEventStart` joined to the attempt's exact usable terminal |
| R-PDL-002 | existing main post-render seam plus passive post-commit frame observer and complete usable-paint predicates | exact render receipt/readback followed by first full-predicate frame; item paint alone is insufficient |
| R-PDL-003 | existing telemetry sink and performance reducer | separate 100-attempt File and Review p50/p95/p99 cohorts |
| R-PDL-004 | existing BridgeApp activation authority and same terminal witness | direction-specific switch distributions |
| R-PDL-005 | twelve owner-bound observations joined through existing product identities and explicit clock-origin relations | complete stage record, overlaps, accounting gaps, cross-realm mapping rejection, and interleaved-attempt isolation |
| R-PDL-006 | proof-driver attempt state and 30,000 ms maximum expiry | controlled-clock expiry plus real source loss, stale, reset, jam, supersession, and late-terminal rejection retained in population |
| R-PDL-007 | existing development/packaged readiness and health boundary | exact port/process/workload preflight plus post-admission loss |
| R-PDL-008 | existing Swift native open trace root for real command-bearing packaged/native paths only | paired end-to-end and post-DOM distributions sharing terminal witness; development-browser receipt explicitly reports N/A without a substitute start |
| R-PDL-009 | rich real-worktree development and packaged compositions plus immutable run receipts | workload census, real source/transport/content/render execution, exact comparison-key admission, and distinct source revisions |
| R-PDL-010 | PR A generic transport, annotations/comments, foreground, and recovery contracts | regression suites plus real Vite and packaged journeys |
| R-PDL-011 | architecture boundaries and existing-owner call paths | diff/source inspection proving no prohibited system or UI redesign |
| R-PDL-012 | owner-stage observation and receipt comparator | named prior baseline selected before evaluation, exact key match, and per-stage before/after contribution |

Cheap deterministic proof owns attempt-state transitions, correlation,
duplicate/out-of-order behavior, percentile reduction, and missing-stage
classification. Integration proof owns real process/worker/transport stage
joining and recovery loss. Development-browser and packaged proof own the
actual workload, complete path, visible terminal, distributions, and
measurement-overhead comparison.

## Dependency and cut line

- PR A remains authoritative for source readiness, backend recovery,
  foreground liveness, generic transport, File/Review consumer correctness,
  demanded-content recovery, annotations/comments, and never-stuck behavior.
- PR B may observe those owners and optimize their measured work; it may not
  redefine their data, currentness, failure, or recovery contracts.
- PR B may change execution cost or overlap inside an existing owner only when
  the owner's PR A observable data, authority, delivery, recovery, and failure
  behavior remains identical. If correctness semantics must change, ownership
  returns to PR A before performance work continues.
- Performance telemetry is downstream observation. It may not admit a command,
  select a source, mark metadata current, request content, acknowledge a frame,
  or declare a render painted.
- Existing product identities remain authoritative. Measurement correlation may
  reference them but cannot replace or broaden them.
- Browser-window and worker clocks may be joined only through captured finite
  time-origin relations. Native command starts may join only through existing
  native trace/open correlation. Message arrival time and fabricated starts are
  forbidden.
- `render_committed` comes from the exact current post-render readback;
  `usable_paint` comes from the first later attempt-bound animation frame where
  the complete surface predicate passes. Item paint never substitutes for the
  full terminal.
- The proof driver's 30,000 ms expiry and animation-frame observation own only
  evidence lifecycle. They may not schedule, time out, retry, acknowledge, or
  mutate product work.
- Run receipts retain their source revision. Comparison requires the exact
  Specification comparability key and one inspectable baseline receipt named
  before candidate evaluation; mismatches cannot prove improvement or no
  regression.
- A PR A reliability failure blocks a passing PR B cohort. PR B does not tune
  around, mask, retry away, discard, or take correction ownership for it. PR B
  owns only a correct successful path whose measured distribution is too slow.
- The two deliveries are linearly dependent: PR B is based on the accepted PR A
  head and does not merge first. There is no compatibility shim or dual
  transport path.

## Revisit signals

This design returns for renewed owner decision if:

- the p95/p99 target cannot be met after measured redundant work and false
  serialization inside existing owners are exhausted;
- meeting the target appears to require a new cache, watcher, queue, worker,
  scheduler, service, persistence layer, transport route, or UI redesign;
- the `DOMContentLoaded` boundary cannot be correlated without changing page
  behavior materially;
- the exact usable-paint witness cannot remain shared by the focused and
  end-to-end clocks; or
- instrumentation overhead materially changes the measured distribution.

Until one of those conditions is proven, the smaller structure—existing owners
plus joined observations—is sufficient.
