# Local-First Comm Worker Architecture

Date: 2026-07-09
Status: accepted; plan-ready. Implementation and proof are not complete.
Extends [performance-demand-lanes.md](performance-demand-lanes.md) R32-R40 and
its Constants Annex. It supersedes only the clauses named under Explicit
Supersessions below.
Parent: [performance-demand-lanes.md](performance-demand-lanes.md)

This file defines the BridgeViewer product, transport, worker-ownership, and
performance boundary. It does not define implementation order. The boundary is
a hard cutover contract: Review and File View each have one product path, one
ownership model, and one proof set inside one pane-owned comm-worker session.

R32-R40 say the browser owns content-demand initiative. This increment splits
that browser ownership: the FE render surface owns only local render slices;
the comm worker owns protocol truth, demand truth, cache truth, retries,
health, continuation, and Swift synchronization. When telemetry is enabled, a
separate telemetry worker owns the observability pipeline so telemetry cannot
consume the main or comm-worker interactive event loop.

## Evidence Anchors

AgentStudio source and committed documents in this section are pinned to
`f19929798a43ea1e0f9d8e75b239f6020299b945`. Pierre `origin/main` evidence is
pinned to fetched commit `4f94a5e765195b27e1e4188b943aab2ae44613cb`;
released-baseline evidence is pinned to tag `diffs-v1.2.12` at
`9466c467ae6fc03501b6bca74c12f717d70293a7`. A mutable checkout or ignored
`tmp/` artifact cannot satisfy a durable evidence claim.

- The committed causal and transport reviews identify the click/root-snapshot
  floor, synchronous File View work, shared WebKit delivery tail, and required
  native proof (`docs/wip/2026-07-04-cold-architecture-review-bridge-demand-system.md`).
- Load ceilings and copy counts: browser main thread full-package parsing,
  Swift MainActor encode/drain pressure, one shared delivery tail, and one
  file's journey carrying about 8 byte copies, 3 full hash passes, and 7
  serialize/validate passes
  (`docs/wip/2026-07-04-cold-architecture-review-bridge-demand-system.md:41`,
  `docs/wip/2026-07-04-cold-architecture-review-bridge-demand-system.md:69`).
- Existing R32-R40 contract: one reconciler, no membership truncation, no
  parked demand states, generation as one derivation epoch, rank surviving the
  worker boundary, and separated retention/byte-cache tiers
  (`docs/specs/bridge-viewer-transport/performance-demand-lanes.md:148`,
  `docs/specs/bridge-viewer-transport/performance-demand-lanes.md:307`).
- Original product contract: a DiffsHub-class Review viewer with Trees,
  CodeView, search/facets, selection/reveal, hunk expansion, markdown, and
  large-diff proof
  (`docs/superpowers/specs/2026-06-15-bridge-codeview-trees-viewer.md:309`,
  `docs/superpowers/specs/2026-06-18-bridgeweb-large-diff-fast-loop-spec.md:637`).
- 2026-07-09 re-baseline at `f1992979`: four independently created comm
  workers, native product intake landing on main, no production streamed
  subscription route, multiple ready-to-loading gates, clone-only Pierre jobs,
  split telemetry owners, and insufficient three-sample browser proof
  (`docs/wip/communications/2026-07-09-bridge-click-fileview-workers-implementation-handoff.md:1`).
- Pierre public API check: BridgeWeb pins `@pierre/diffs` `1.2.10`; released
  `1.2.12` and fetched `origin/main` still define string-backed `FileContents`,
  whole-item `CodeViewHandle` updates, and worker dispatch without transfer lists
  (`BridgeWeb/package.json:27`,
  `packages/diffs/src/types.ts:24`,
  `packages/diffs/src/react/CodeView.tsx:88`,
  `packages/diffs/src/worker/WorkerPoolManager.ts:1043` in the pinned Pierre
  revision).

## Normative Product And Success Contract

The worker architecture is a means to the product contract. R41-R66 cannot be
declared complete while Review or File View is functionally wrong, even when an
individual worker, schema, or unit-test seam passes.

The complete product obligations in
`docs/superpowers/specs/2026-06-15-bridge-codeview-trees-viewer.md` and
`docs/superpowers/specs/2026-06-18-bridgeweb-large-diff-fast-loop-spec.md`
remain normative unless this increment explicitly supersedes a clause. This
increment changes transport, state ownership, continuation representation, and
proof strength; it does not silently delete a user journey.

Review MUST:

- support the 3,420+ file and 100,000-line selected-diff fixture floor;
- preserve deep tree navigation, search, filter/facets, reveal, selection,
  collapse/expand, hunk expansion, added/modified/deleted/renamed files, and
  sanitized markdown presentation;
- keep the file rail and CodeView independently scrollable and responsive;
- demand, render, and paint later windows across the entire selected diff; and
- produce zero blank/wrong windows, snapback, stale flash, content
  disappearance, or wedged selections.

File View MUST:

- support streamed tree metadata, search/filter, selection, refresh, stale
  repair, and explicit binary/unavailable states;
- render one selected first window bounded by BOTH 2 MiB and 10,000 actual
  payload lines; metadata line counts must not fabricate blank payload lines;
  and
- stop explicitly at that envelope. File View continuation is not promised.

Product traceability:

| Retained journey | Contract in this increment | Required live proof |
| --- | --- | --- |
| normal, guided, and plans/specs Review modes; search and composed status/class/path/language facets | one worker-owned projection truth; local intent remains synchronous | real-worker browser plus semantic-IPC packaged-native journey |
| deep tree select/reveal, independent rail/CodeView scroll, collapse, stable header | R41-R46, R56, R61 | correct row/header/content and no blank, snapback, or cross-scroll ownership |
| added, modified, deleted, renamed, binary, unavailable, and markdown items | R44, R59, R61 plus original sanitized-render rules | deterministic content/checksum and unsafe-markdown corpus in browser and native |
| hunk expansion and 100,000-line traversal through the final real hunk | released Pierre window contract in R57/R61 | window ids/checksums, stable anchor/header, and final-window paint in both runtimes |
| File View tree/search/select/refresh/stale repair and bounded real prefix | R42-R49, R61 | UTF-8/binary/truncation corpus with no fabricated padding in both runtimes |
| source reset, reconnect, worker restart, mode switch, pane isolation, teardown | R42, R49, R63-R65 | hostile worker/server seams plus real two-pane packaged journey |
| telemetry on, off, and failure | R43, R62, R66 | product parity; telemetry failure is product-fail-open and proof-fail |

Explicit supersessions:

- R32-R39 and R40's retention/cache separation remain normative. This
  increment replaces only R40's size-overflow presentation rule: ordinary
  Review content MUST split/window/continue and MUST NOT become terminal solely
  for size. File View normal text instead renders one real bounded prefix plus
  explicit truncation and has no continuation.
- The original main-thread Zustand, direct page/native product traffic,
  whole-item Pierre update, and multi-worker ownership descriptions are replaced
  by R42, R49, R54-R57, and R61. Their product behavior remains required.

The performance floor is:

| Metric | Controlled dev server | Packaged native WKWebView |
| --- | ---: | ---: |
| local selection feedback | p99 < 32 ms | p99 < 32 ms |
| fresh warm-cache readable content | p99 < 32 ms | p99 < 32 ms |
| selected readable content | p95 < 50 ms, p99 < 100 ms | p95 < 100 ms, p99 < 200 ms |
| file-rail scroll response | p95 < 50 ms, p99 < 100 ms | p95 < 100 ms, p99 < 200 ms |
| CodeView scroll response | p95 < 50 ms, p99 < 100 ms | p95 < 100 ms, p99 < 200 ms |

Internal stop lines apply in both environments:

- selected comm-worker queue wait p95 < 16 ms and p99 < 32 ms;
- complete main-to-Pierre public window submission p95 < 4 ms and p99 < 8 ms;
- every owned main/comm synchronous slice has a hard maximum of 8 ms;
- main-thread tasks at or above 50 ms: zero;
- blank/wrong windows, wedges, disappearance, stale paint: zero; and
- required telemetry loss, sequence gaps, or lifecycle-correlation gaps: zero.

One gated benchmark cell fixes runtime, family, source/cache state, telemetry,
fixture, viewport, machine profile, commit, bundled Pierre version, and worker
mode. Every cell runs in three fresh browser/app process
launches with one excluded warmup and at least 100 attempted measured actions
PER LAUNCH: at least 300 attempted samples per pooled cell. Every launch and the
pooled cohort must pass p95/p99; the maximum per-launch percentile is the
reported worst launch and launch percentiles are never averaged. Percentiles
use nearest-rank without interpolation. Warmup correctness failures fail the
launch. Failures remain numeric samples under R62 and are never excluded.

The applicability manifest is closed. EVERY row/state runs in BOTH
`controlled_dev_chromium` and `packaged_wkwebview`, with telemetry BOTH off and
on. `surface` below is the stimulus -> painted endpoint, so rail clicks that
paint CodeView are not ambiguous.

| Required family | Stimulus -> endpoint | Required source/cache states |
| --- | --- | --- |
| Review selection feedback | Review rail select -> Review rail chrome/selected placeholder | fresh display, worker cache, cold miss |
| Review selected readable | Review rail select -> Review CodeView readable | fresh display, worker cache, cold miss |
| Review terminal availability | Review rail select -> Review CodeView terminal | cached terminal, cold terminal |
| Review rail scroll | Review rail gesture -> rail motion + correct rows | resident rows |
| Review CodeView scroll | CodeView gesture -> motion + checksum window | resident window, continuation miss |
| File selection feedback | File rail select -> File rail chrome/selected placeholder | fresh display, worker cache, cold miss |
| File selected readable | File rail select -> file content readable | fresh display, worker cache, cold miss |
| File terminal availability | File rail select -> file terminal/truncation | cached terminal, cold terminal |
| File rail scroll | File rail gesture -> rail motion + correct rows | resident rows |
| File content scroll | file-content gesture -> motion + correct prefix rows | resident prefix |

No required row/state is `not_applicable`. Extra exploratory families are
report-only and cannot satisfy a gate. Different cells or fixed invariants
cannot pool; one action may emit distinct family rows under one interaction id.

True fresh-launch evidence is the first eligible action after a real process
launch. It remains separate and report-only until at least 100 actual launches
exist; no fresh-launch p99 claim is permitted below that count.

The thresholds are floors. Measured headroom may strengthen them. They must not
be weakened without explicit user agreement.

## WebKit Constraints

The architecture uses these WebKit constraints and gates:

- All named `WKScriptMessageHandler` handlers for one `WKWebView` share one IPC
  delivery lane. Splitting command, telemetry, and demand across handler names
  provides routing semantics only, not isolation or independent backpressure.
- Message-handler delivery is treated as default-run-loop-mode traffic. Gesture
  tracking may starve it; this starvation remains an empirical-confirm open
  decision, not a settled proof claim.
- `WKURLSchemeHandler` is expected to intercept worker-initiated `fetch()` for
  registered schemes. WebKit TestWebKitAPI `FileSystemAccess.mm` and
  `IndexedDBPersistence.mm` are source-grounded research anchors, not a closed
  production proof for this app. Native WKWebView proof of worker custom-scheme
  fetch and streamed scheme responses is REQUIRED before cutover. If worker
  fetch or streaming fails, stop and revise the native carrier or this
  architecture. A page fetch/relay is not a production fallback because it
  would restore main as a product-protocol participant.
- A live `MessagePort` is not entangled with native for ordinary WKWebView page
  content. `MessageChannel` is page-to-worker only for this design.
- `SharedArrayBuffer` requires cross-origin isolation headers on every scheme
  response. Safari lacks the `credentialless` shortcut. This design must not
  require SAB; `fetch()`, `ReadableStream`, and transferables are sufficient.

## Boundary / Separability Map

```text
Bridge pane composition root
  owns: one comm-worker lifetime, optional telemetry-worker lifetime, ports,
        session capability handoff, teardown
  forbidden: product protocol/cache/demand truth

FE/main presentation
  owns: local UI intent, bounded display copies, Trees/CodeView adapters,
        frame-budgeted DOM apply, opaque Pierre courier, render dispositions
  exposes: surface-scoped intent facts and disposition receipts
  forbidden: Swift product traffic, protocol/session truth, raw bytes, demand,
             retry/cache truth, telemetry batching, Pierre payload transforms

ONE PER-PANE COMM WORKER
  owns: Review/File product sessions, surface-scoped stream/epoch/sequence,
        projection, demand, byte/paint cache, retry/backoff, health,
        Review continuation, File View first-window preparation
  exposes: bounded slice patches/jobs to main; product requests/streams to Swift
  forbidden: DOM work, telemetry pipeline work, FE/native fallback ownership

Swift product server
  owns: provider/source authority, sourceGeneration, metadata/content service,
        product scheme endpoints, leases, stream production/admission
  exposes: disposable pane-scoped call/metadata/content POST service

main producer port + comm producer port
  -> OPTIONAL PER-PANE TELEMETRY WORKER
       owns: telemetry validation, credits, buffer, bytes, shedding, batching,
             encode, sequence, retry/outbox, telemetry scheme POST
       forbidden: product commands/content/cache/demand/health authority

main -> Pierre public API -> Pierre/Shiki workers
  main is an opaque bounded courier; Pierre owns its render/highlight runtime
```

Zustand is the comm-worker-local data store for Bridge viewer data. React/main
must not own a Zustand Bridge data store after cutover. React/main uses typed
worker RPC lifecycle helpers and non-Zustand render-slice hooks for
frame-critical display copies. The synchronization boundary is typed RPC/DTO
messages, not store mirroring: no Zustand snapshot, query/cache entry, store
action/function, class instance, DOM object, `AbortController`, or other
non-cloneable local state shape may cross the worker boundary.

Exactly one `BridgePaneCommWorkerSession` exists per Bridge pane and survives
Review/File mode mounts and switches. Review and File View are surface-scoped
clients of that session, not worker factories. The worker owns independent
Review and File source/stream/`workerDerivationEpoch` contexts under one ranked
scheduler; one global epoch must not let one surface invalidate the other.

## Truth Ownership Tables

Every datum has exactly one truth owner.

Identity lineage is split into semantic, UI, worker, and native planes:

| Value | Mint | Validate | Reset | Observe |
| --- | --- | --- | --- | --- |
| `sourceGeneration` and metadata lineage | Swift/native provider source authority | Swift rejects stale source requests; worker treats it as source fact, never as worker cache epoch authority | Swift rotates on accepted source change, resets metadata stream/gates, and revokes stale source leases | comm worker subscriptions, server seam, native proof |
| `semanticDocumentRevision` | comm worker from algorithm-tagged content digests and document kind/ordered roles | worker and Pierre manifest/payload validation | changes only when semantic source content changes | display cache, continuation, proof oracles |
| `uiIntentRevision` | FE, monotonic per surface | comm worker accepts/supersedes intent and echoes the accepted value | surface remount/page session reset | FE render copies and worker intent receipts only |
| `workerInstanceId` | Swift/native, freshly for each comm-worker lifetime | Swift product session and main reset barrier | every comm-worker restart | product frames, reset proof, diagnostics |
| `workerDerivationEpoch` | comm worker per surface/source context | worker stamps demand, fetch, cache admission, and publication; Swift validates new admission and echoes it on admitted surface push/lifecycle frames | worker source reset/resync; never minted by main | worker tests and correlated proof |

`semanticDocumentRevision` and its window identities EXCLUDE metadata/package
revision, descriptor retouch, resource lease/cache key, sourceGeneration,
stream/request sequence, worker instance/derivation epoch, active surface, projection mode,
and UI-intent revision. A render-affecting option has its own
`renderSemanticsRevision`; its replacement is atomic and the prior readable
window remains visible until the replacement paints. Transport churn may revoke
a validation lease or stale an in-flight attempt, but unchanged semantic content
does not become a new loading identity.

An authoritative digest is `sha256` over complete canonical source bytes. Swift
labels each role digest authoritative or provisional; metadata/status/tree,
mtime, path, lease, and `oversized:<size>` fallbacks are provisional and cannot
authorize ready reuse. The worker hashes a length-prefixed encoding of document
kind, ordered role labels/digests, and diff-semantics version to mint the
document revision. Missing/provisional digests require streamed-byte hashing and
verification before ready. Shared Swift/TS fixtures cover same-size changed
bytes, role/algorithm ambiguity, metadata retouch, and unchanged bytes across
generation churn.

Extended truth ownership:

| Datum | Owner | Readers | Write path | Repair path | Inactive-mode behavior |
| --- | --- | --- | --- | --- | --- |
| `streamId` | comm worker | FE diagnostics, Swift validation | worker opens/reopens source session | worker/server resync on gap or unhealthy | retained, never FE-writable |
| `sourceGeneration` / metadata lineage | Swift/native | comm worker, server tests | native accepted-source transition | native reset/reopen or unhealthy | native may continue metadata rules; FE sees no protocol state |
| `semanticDocumentRevision` / semantic window identity | comm worker from canonical content descriptors/hashes | display cache, Pierre manifest, proof | semantic content or deterministic partition change only | metadata/lease/transport churn revalidates without demoting unchanged ready content |
| `uiIntentRevision` | FE local surface | comm worker | every local selection/mode/filter intent | latest-wins worker acceptance/repair | retained per mounted viewer; grants no protocol authority |
| `workerInstanceId` | Swift/native pane-session bootstrap | main/worker/Swift | every worker creation | reset barrier cancels prior-instance work | one active instance per pane |
| `workerDerivationEpoch` | comm worker, scoped by surface/source context | FE diagnostics, Swift freshness echo, worker tests | worker accepts sourceGeneration/stream tuple | epoch reset clears derived worker truth for that context | retained per pane worker; inactive foreground work demotes/aborts |
| control/stream sequence | control: comm worker per pane/worker; physical metadata: Swift per pane stream; logical subscription: Swift per subscription | opposite endpoint | accepted send order | duplicate/gap/reset rules in R64 | inactive subscriptions retain their sequence; one physical sequence spans Review/File |
| staleness classification | comm worker | FE health/render slices | worker validates source, stream, epoch, and sequence | reset-required -> reopen or unhealthy | inactive stale results cannot mutate active UI |
| content-demand membership | comm worker reconciler | worker executor/cache | worker reconciles selected/viewport/hover/cache facts | re-derive every fact change; no parked membership | inactive selected becomes demoted/aborted, not foreground |
| content bytes / byte cache | comm worker | worker parse/window/diff/highlight | worker `BridgeProductTransport.openContent()` POST | retry/backoff or unavailable slice | retained by retention policy; not active foreground |
| paint-ready rows/runs/extents | comm worker produces; FE slice store owns current render copy | components | transferable worker slice update | stale slice replacement or explicit unavailable/error slice | inactive copies may persist but cannot overwrite active mode |
| selected UI intent, `uiIntentRevision`, and selected display copy | FE local slice | comm worker as fact input | synchronous click/keyboard/programmatic mutation | worker accepts/supersedes by UI revision; never mints worker freshness | each mounted viewer retains local selection memory |
| accepted selected product identity | comm worker, scoped by surface | demand/cache/protocol logic; FE receives display copy | worker accepts a current UI intent under its source context | stale/reset/superseded intent re-derives; main never mints `workerDerivationEpoch` | inactive selection retains memory but has no foreground authority |
| `activeSurfaceUiIntent` | FE app shell | comm worker | local Review/File switch with UI revision | worker acceptance/repair | retained local shell fact |
| accepted `activeSurface` | comm worker | ranked demand/protocol contexts; FE display copy | worker accepts current surface intent | demote/abort inactive foreground and echo repair | only accepted surface has foreground authority |
| `reviewProjectionMode` | comm-worker Review projection state | FE mode control/display slice | worker accepts normal/guided/plans-specs intent | deterministic re-projection; never changes active surface or `workerDerivationEpoch` | retained while File is active |
| `viewport` / rendered range | FE virtualizer slice | comm worker reconciler | rAF/idle-coalesced viewport publication | next viewport fact supersedes; worker re-derives | inactive viewport may be retained but does not create foreground demand |
| `expanded` / collapsed rows | FE local slice | comm worker for visible derivation | user toggle writes local UI fact | source reset drops invalid row ids; worker publishes availability repairs | retained per viewer unless source reset invalidates ids |
| viewed marks | Swift/native viewed-file command authority | FE render slices, comm worker ack tracking | FE sends write intent through worker to Swift | Swift ack or retry/unhealthy; worker emits ack health slice | inactive mode may queue intent only through worker, never direct native write |
| diff status | Swift/native push plane | FE render slices, comm worker health | native status push through worker | failed push clears dedupe and re-emits or marks unhealthy | retained as last known health; stale status marked explicitly |
| command acks | comm worker | FE health/render slices, Swift request handlers | worker correlates requests/intents to Swift responses | timeout/backoff/retry or unhealthy | inactive acks may settle but cannot update active selection/content |
| render disposition / fulfillment | main mints structural disposition; comm worker owns fulfillment state | demand reconciler, FE diagnostics | main reports queued/applied/painted/rejected/superseded for a worker job/window | missing/rejected/superseded receipt keeps current selected/visible demand live and re-derivable | inactive receipts may settle but cannot create foreground demand |
| product connectionHealth | comm worker | FE health chrome, Swift diagnostics | worker observes bootstrap, product fetch/stream/push failures | reconnect reset, source reopen, or unhealthy slice | inactive mode shows retained health only; no foreground retries |
| write intents | FE creates; comm worker owns queue/dedupe | Swift command handlers, FE ack slices | local intent -> worker queue -> Swift command | worker retries/backoff or fails visibly; no direct FE->native bypass | inactive writes are demoted/queued by policy or rejected visibly |
| telemetry queue / batch sequence / retry outbox | optional telemetry worker | Swift telemetry endpoint, proof tooling | compact samples arrive on port-bound main/comm producer ports | bounded credits, reserved loss summaries, proof failure on required loss | worker survives mode changes; no worker when telemetry is disabled |
| metadata plane | Swift/native | comm worker subscriptions | native interest stream and provider scheduler | native reset/reopen/unhealthy | untouched by this spec |

## Requirements

### R41. Paint paths do not await across boundaries.

Nothing in a paint path awaits the comm worker or Swift. FE render reads are
synchronous local slice reads. A click writes the local selected slice
optimistically and paints in the same frame; worker and Swift confirmation may
repair later, but must not gate the click frame.

Contract violations:

- `flushSync` spanning package-shaped React/Pierre work while product delivery
  is in flight; the committed handoff records this click-stall class.
- Paint-follows-push coupling: a visible FE paint that depends on the next
  Swift push, worker response, or handler delivery.
- Any telemetry flush, batch, byte calculation, encode, retry, or fetch on an
  interactive path. At the re-baseline, main and comm recorders still buffer
  while the sink stringifies/fetches and hot adapters can request flush
  (`BridgeWeb/src/core/comm-worker/bridge-comm-worker-telemetry.ts:65`,
  `BridgeWeb/src/bridge/bridge-telemetry-event-sink.ts:14`,
  `BridgeWeb/src/foundation/telemetry/bridge-viewer-telemetry-adapter.ts:291`).

R41 extends R35/R39: selected work still ranks first, but selected paint cannot
wait for the rank machinery to round-trip.

Cold-paint outcomes are part of R41:

| State at click | Required first paint | Forbidden proof claim |
| --- | --- | --- |
| fresh paint-ready cache hit for the semantic selected/window identity and validation lease | readable selected content window | treating a later worker confirmation as the first paint |
| cache miss for normal content | selected identity, selection chrome, and protocol-free loading/availability placeholder keyed to the new selection | claiming selection highlight alone satisfies click-to-first-visible-content |
| unchanged semantic identity with stale transport validation | retain readable content with explicit stale connection health until revalidated; do not count a fresh hit | converting metadata/epoch churn into loading or readable success |
| different semantic identity | no old content; render the new selected identity plus loading/stale placeholder | painting old readable content, even briefly |
| binary, unavailable, unsupported encoding, or persistent non-size failure | explicit terminal state keyed to the selected identity | indefinite blank panel, old content, or readable success sample |

R41 defines separate success events:

| Metric | Start | End | Loading counts? |
| --- | --- | --- | --- |
| `local_selection_feedback` | trusted committing event timestamp, or outer control clock before IPC | selected identity/chrome and either matching content or an honest selected placeholder have painted | yes, as feedback only |
| `fresh_warm_cache_readable` | same authoritative action start | current readable content from matching semantic/window/render identity has painted | no |
| `selected_readable_content` | same authoritative action start | current readable selected window has painted after worker/Pierre/apply lifecycle | no |
| `selected_terminal_availability` | same authoritative action start | current explicit binary/unavailable/failure state has painted | terminal state only; never reported as readable |

Selection chrome or a loading placeholder may satisfy local feedback. It never
satisfies readable-content latency. A fast placeholder cannot launder a late or
never-completing content lifecycle into a passing sample.

### R42. Every datum has exactly one truth owner.

One pane-owned comm worker is the single authority for Review/File product
protocol and cache truth: accepted surface selection, surface-scoped stream
identity, R37 `workerDerivationEpoch`, sequence, staleness, cache membership,
content-demand membership, retry/backoff, continuation, and server reconnect
state. Review, File View, active mode, and Worktree/File RPC are clients of the
same worker instance, not independent worker owners.

FE is the single authority for immediate local UI intent and display copies:
pending selected row/file/item intent, expanded/collapsed local UI facts, local
hover/focus facts, and the current paint-ready slice copy. The comm worker owns
the accepted surface selection and may accept, reject, supersede, or repair the
local intent through typed slice patches. FE components hold zero protocol
state.

Swift remains the authority for provider/source metadata and content service
truth. Swift server lifetime is disposable from FE's perspective; reconnect
resyncs the worker, and FE observes only worker-produced render/health slices.

This bans the committed defect class where R32 existed but demand membership
still had multiple authorities, and the cold-review staleness class where Review
and Worktree/File carried different generation models
(`docs/wip/2026-07-04-cold-architecture-review-bridge-demand-system.md:89`).

Selected/visible demand is fulfilled only by a worker-current painted residency
with a valid lease, a new matching `painted` disposition, or explicit terminal
availability. Worker ready/delivery/queue/submission are intermediate. The
canonical `BridgeRenderDispositionKey` is pane session, worker instance,
surface, semantic document/partition/window, submission id, and attempt id;
source generation/`workerDerivationEpoch` validate its envelope and interaction id only
correlates observation. Rejected/superseded/missing receipts keep current demand
re-derivable; telemetry is never the control-plane ack.

A fresh display hit reuses an existing worker-issued painted residency and
validation lease. FE paints first, then MUST send the selection/UI revision;
the worker returns `selectionAccepted` with the reused submission id and no new
publication attempt or disposition. That acknowledgement closes the control
interaction but cannot move the already-recorded readable endpoint. An expired
lease is stale-display, not a fresh hit.

Availability is monotonic for one semantic document/window identity:

```text
absent -> loading -> ready | unavailable | failed
```

`ready -> loading` is forbidden. Only a changed semantic document/window
identity may begin at loading. A metadata/source-generation/lease/stream/worker
epoch or presentation retouch does not mint that identity and cannot demote
ready. Main validates structural envelope/barrier/identity shape and applies
worker transitions; it must not compare route-local descriptor/cache/presentation
keys and synthesize loading. A render-semantics replacement keeps the prior
ready window until the replacement atomically paints.

R42 is complete only when the extended truth ownership table above is
implemented as code ownership. Adding a second writer for any row is a
contract violation, even if both writers currently agree in tests.

### R43. Telemetry uses a dedicated per-pane worker and transport lane.

When native bootstrap exposes no enabled telemetry scope, the pane creates no
telemetry worker, producer ports, queue, or fallback. When any scope is enabled,
the pane creates at most one lazy telemetry worker. It survives Review/File mode
changes and comm-worker restarts and owns the entire telemetry pipeline:

```text
main compact-sample port ----\
                               -> TELEMETRY WORKER -> telemetry scheme POST
comm compact-sample port ----/
```

Main and comm producers may only check enablement, capture timestamp/duration
and safe correlation, maintain a monotonic producer sequence and granted credit,
and `postMessage` a compact typed sample. They must not buffer full samples,
expand events, calculate encoded bytes, stringify, batch, shed admitted events,
retry, hold an outbox, or fetch. Telemetry-worker failure disables producer
ports and marks the proof run unhealthy; product selection/content/paint remains
fail-open. No telemetry work falls back to main or comm.

The telemetry worker exclusively owns:

- port-bound producer identity and strict per-producer ingress sequence;
- bounded credit admission with reserved control capacity for loss summaries;
- event-contract validation and source scrubbing before buffer admission;
- encoded-byte accounting, drop-oldest optional shedding, and required-loss
  accounting;
- one telemetry-session batch sequence, bounded in-flight/outbox bytes and
  count, bounded retry/backoff, JSON encode, and scheme fetch; and
- explicit `drainAndClose` / acknowledgement for teardown and proof capture.

There is no meaningful total order between the main and comm producer ports.
Lifecycle correlation uses an explicit safe interaction sequence carried by
demand, ready, accept/reject, apply, and paint samples. Producers cannot claim
their own producer identity, telemetry session, scenario, endpoint, or batch
sequence; the telemetry worker stamps those from native bootstrap and port
installation. Native repeats schema, byte/count, session, sequence, and
source-scrubbing validation before admission.

Interactive command, click, scroll, content, and paint paths cannot flush or
await telemetry. Posting one compact sample has its own producer-side hard
maximum of 2 ms and p99 < 1 ms, and telemetry-on product runs must independently
pass every absolute product budget.

Telemetry proof integrity:

| Condition | Proof rule |
| --- | --- |
| required event shed before ingress, in buffer, in outbox, or at native admission | proof fails; retain only as exploratory evidence |
| unexplained producer/batch gap, conflicting duplicate, or reorder | proof fails; an exact idempotent batch retry may return `duplicate` |
| telemetry-worker restart or missing drain acknowledgement | proof fails |
| slow click, reject, abort, stale, unavailable, timeout, or failure sample shed | proof fails; tail/failure samples are required |
| optional/debug event shed | allowed only with exact aggregate counters and explicit lossy-run annotation |

Percentiles can satisfy R41-R66 only from non-lossy required event streams.
Lossy telemetry runs are debugging aids, not performance proof.

### R44. Content bytes stream to the worker, not the main thread.

Source bytes are streamed by the comm worker through its worker-local
`BridgeProductTransport.openContent()` facade. Main never
receives raw strings, full package bodies, or canonical byte-cache entries. Its
only source-bearing value is one bounded R52/R57 Pierre window submission whose
`ArrayBuffer` fields transfer worker -> main, are forwarded unchanged through
Pierre's public API, and are detached before that call returns. Main cannot
retain, decode, split, parse, classify, diff, window, highlight, copy, or
reconstruct them. Every other main hop is a bounded metadata/display structure:
rows, extents, summary/availability facts, and DOM-apply units.

Parse, window selection, diff preparation, highlight preparation, and cache
admission run worker-side. This extends R29's worker-backed content-cache
requirement and R39's worker-boundary rank requirement
(`docs/specs/bridge-viewer-transport/performance-demand-lanes.md:680`,
`docs/specs/bridge-viewer-transport/performance-demand-lanes.md:261`).

R44 bans the copy-count/load-ceiling class where whole frames and file journeys
cross too many serialize/validate/copy surfaces
(`docs/wip/2026-07-04-cold-architecture-review-bridge-demand-system.md:69`).

Worker fetch outcomes:

| Outcome | Worker state | FE slice | Re-demand rule |
| --- | --- | --- | --- |
| success, current epoch | bytes enter worker byte cache; parse/window/highlight may continue | paint-ready or availability slice | membership remains until matching `painted` disposition or explicit terminal state if still selected/visible |
| abort from supersession or demotion | in-flight slot frees; no cache write unless completion was already fresh | no error for speculative/nearby; selected may show loading for new identity | reconciler re-derives from current facts |
| transient failure | executor records delivery-failure fact and bounded backoff | health/loading slice with retry state, no FE-owned retry | worker re-demands from membership after backoff |
| persistent non-size failure | worker records terminal availability for current semantic identity | explicit unavailable/error slice keyed to selected/visible identity | membership remains worker-owned; retry only after source/fact reset policy |
| Review work exceeds one window/preparation budget | deterministically split/repartition or offload while preserving desired membership | honest loading for missing desired windows; existing windows stay readable | size alone never becomes terminal; demand continues through final manifest window |
| File View reaches byte/line envelope | publish the maximal canonical prefix and truncation facts | readable prefix plus explicit truncation state | no continuation; metadata never pads payload |
| stale sourceGeneration or workerDerivationEpoch | discard result, count stale drop | no stale content; health slice if user-visible | epoch reset/reconnect drives fresh demand |
| reconnect reset | clear source-bound in-flight/cache memberships as required by epoch reset | connection health/loading slices | worker rebuilds membership from latest FE facts and Swift source |

FE receives render and health slices only. Fetch membership, backoff, retry,
and re-demand are worker facts; FE must not park or restart content demand.

The production worker bootstrap is session-only: pane/session identity, policy,
initial mode, and transferred ports. Main-supplied rows, descriptors, content
metadata, render semantics, telemetry configuration, `reviewSourceUpdate`, and
`fileViewSourceUpdate` are forbidden product bootstrap or update payloads.
Source truth arrives through worker-owned Swift product streams.

Review continuation is a product protocol, not a comment on a first-window
constant. Viewport/line-window facts must let the worker request, prepare,
publish, receive disposition for, and retain later windows across the selected
100,000-line diff. Treating a first 400-line `windowed` item as fulfilled is a
contract violation.

File View payload limits apply to actual serialized/rendered payload lines and
bytes. Padding a truncated payload toward metadata `totalLineCount` is forbidden
because it fabricates content, defeats the line bound, and creates unnecessary
Pierre/layout work. Total line count remains metadata, not display content.

### R45. FE render store is sliced.

FE components may subscribe only to the allowed interaction slice shapes:

| Slice | Shape | May contain |
| --- | --- | --- |
| `selectionSlice` | one selected identity and local action state | selected row/file/item, pending local intent, selection availability |
| `viewportSlice` | visible range plus bounded delta | rendered ids/range, scroll activity, look-ahead facts |
| `rowPaintSlice(id)` | one keyed row/item paint model | row chrome, extent, summary, current paint-ready projection |
| `contentAvailabilitySlice(id)` | one keyed content availability fact | cache hit/loading/unavailable/error/currentness facts |
| `panelChromeSlice` | bounded panel-level UI state | active mode, health badge, counts, toolbar affordance state |

Whole-package maps, whole ordered arrays, registry snapshots, and package-shaped
view models are banned from interaction subscribers. A slice named
"panel-scoped" is not compliant if selecting one item invalidates O(package)
state.

Every keyed content/display slice includes the worker-issued semantic document
and window identity plus its structural transport envelope. Source generation,
worker instance/epoch, sequence, and UI revision validate delivery but are not
part of the semantic display-cache key. A route-local descriptor, cache, or
presentation key cannot replace or reinterpret either layer.

Root-snapshot subscriptions that make one interaction rebuild package-shaped
state are contract violations. O(package) work inside interaction handlers is a
contract violation. Proof must show click invalidation cost is
O(selected + visible delta), not O(package), using subscriber counts,
invalidated-key counts, or equivalent instrumentation under large-package
fixtures.

Review's current root-snapshot subscription and propagation shape is the banned
class (`BridgeWeb/src/app/bridge-app-review-viewer-mode.tsx:112`,
`BridgeWeb/src/app/bridge-app-review-viewer-mode.tsx:537`). File View's
separate selectors for root, render, open-file, initial-load, refresh, and
demand-debug state are the in-repo proof direction for narrower subscriptions
(`BridgeWeb/src/file-viewer/use-bridge-file-viewer-store-bindings.ts:38`).

R45 bans the committed flat click-floor class from root-snapshot world-state
rendering.

### R46. Main-thread ready-to-visible work is a frame-budgeted pump.

DOM materialization remains on the main thread. That stage is legitimate only
as the final step of a frame-budgeted ready-to-visible pump:

- rank-ordered, with selected/current target first;
- bounded per frame by AppPolicies-backed time and unit-count caps;
- input-yielding between chunks;
- resumable without redoing completed units;
- stale-safe if worker or Swift advances generation while units are pending;
- no-starvation bounded for visible non-selected apply work while selected
  churn continues.

The frame budget governs the entire ready-to-visible chain, not only DOM/store
apply. Promotion of deferred or parked entries after pause release, result-map
rebuild, resource derivation, unit derivation, and any other per-item
preparation required before visible apply must enter the same ranked pump and
spend the same per-frame budget class. A pause release must not bulk-promote all
ready entries. Selected/current-window entries promote first; remaining deferred
entries promote in frame-budgeted chunks through the same ranked pump.

The production constants must live in `AppPolicies` or the BridgeWeb policy
module that mirrors `AppPolicies`; tests and verifiers assert observed behavior
against those constants, not duplicated literals. Required policy classes:

| Budget | Class | Proof |
| --- | --- | --- |
| selected apply time/unit cap | execution | selected latency histogram and per-frame applied-unit counter |
| visible non-selected apply time/unit cap | execution | visible apply progress counter increases under selected churn |
| deferred promotion time/unit cap | execution | pause release advances selected/current-window first and drains remaining deferred entries across multiple frames |
| ready-item preparation time/unit cap | execution | result-map rebuild and resource/unit derivation stay inside per-frame budget |
| stale-drop scan cap | pacing | pending stale units are cleared without monopolizing a frame |
| no-starvation bound | fairness | at least one visible non-selected apply batch completes within N selected batches, where N is policy-owned |

Applying all ready entries in one microtask, one sync React update, or one
package-shaped Pierre operation is a contract violation. Bulk-promoting parked
or deferred entries before the pump is the same violation upstream of DOM apply.
R46 is the main-thread counterpart to R39: rank survives worker completion,
pause release, ready-item preparation, and DOM apply.

R46 bans the committed severe-freeze class where synchronous frame/projection
and apply work occupied the main thread.
It also bans the live round-5 regression where unbudgeted pause-release
promotion produced multi-hundred-ms main-thread tasks blocking tree and clicks:
the budget must sit upstream of the pump, not only at DOM apply.

Each job/window produces at most one disposition transition of each kind.
Receipts are idempotent and bounded by admitted apply units; rapid selection
churn cannot create an unbounded ack loop. Pending placeholder/materialization
tasks carry the same full identity and generation as their input and are
invalidated when that identity leaves loading or is superseded. After structural
apply, main observes a post-update animation-frame/content check before sending
`painted`; teardown or identity change sends `superseded` instead of silently
dropping fulfillment state.

### R47. File View projection and pruning obey the same frame contract.

File View is not exempt from R41-R46. Frame application, projection, replay,
open-file reconciliation, and DOM apply must be chunked and yielding when their
input can scale with frame/package size.

The historical O(N^2) empty-directory prune was resolved by `cfc65617` before
this contract's pinned base. Its replacement performs bottom-up directory
marking in O(rows + directories). R47 retains that result as a regression
floor; it does not schedule another prune rewrite. The remaining live risk is
scalable frame intake/projection/apply work, which must satisfy the same pump
and event-loop proof as Review.

File View frame intake is likewise covered by the apply-pump contract because
it applies incoming frames from the subscription path synchronously today
(`BridgeWeb/src/file-viewer/use-bridge-file-viewer-frame-intake-controller.ts:70`).

### R48. Proof seams match the runtime boundaries.

Proof must preserve boundary honesty. Each seam proves only its side of the
contract.

FE seam:

- tests FE against a hostile fake worker;
- proves synchronous local render reads, optimistic click paint, slice
  subscription boundaries, no protocol state in FE, and frame-budgeted apply
  behavior;
- cannot prove WebKit IPC delivery, worker/server protocol correctness,
  Swift admission, worker content fetch, structured-clone/transfer cost,
  worker bootstrap/prewarm, real worker scheduling, native telemetry decode,
  payload compatibility, or live momentum starvation.

The FE fake worker must test delayed, reordered, dropped, duplicate, and
never-resolving replies. A polite synchronous fake worker cannot close R41,
R45, or R46 because it hides await coupling, ordering bugs, clone cost, and
cold-cache behavior.

Worker seam:

- tests the comm worker against a hostile mock server that is never politer than
  live Swift: out-of-order pushes, stale generations, dropped responses,
  reconnects, oversized product frames, slow content, persistent fetch
  failures, and backpressure; telemetry hostility belongs only to the separate
  telemetry-worker seam below;
- proves surface-scoped stream/workerDerivationEpoch/sequence/staleness
  authority, R32-R40 membership, R34 backoff/pacing, R37 epoch reset, R39 rank
  into worker pools, R44 content streaming, Review continuation, File View
  first-window bounds, markdown source/compute/patch stages,
  disposition-driven fulfillment, and reconnect resync;
- cannot prove FE paint timing, DOM materialization, WebKit run-loop mode, or
  Swift provider correctness.

Server seam:

- tests Swift against recorded worker traffic;
- proves metadata plane stability, typed content-stream serving,
  `BridgeContentDemandAdmission`, telemetry POST admission, source authority,
  and reset/unhealthy responses;
- cannot prove FE slice correctness, worker cache policy, worker backoff,
  WebKit delivery ordering, or user-perceived paint.

Real-worker browser seam:

- runs the actual pane comm worker, telemetry worker when enabled, and Pierre
  workers against deterministic Review and File View fixtures;
- proves one comm-worker identity across mode switches, direct worker metadata
  and content streams in the controlled environment, structured-clone/transfer cost,
  markdown compute/sanitize/paint, telemetry producer isolation, DOM
  apply/disposition flow, event-loop/long-task evidence, and the controlled
  p95/p99 product budgets; and
- cannot prove native WKWebView custom-scheme behavior, native admission,
  packaged assets, LaunchServices identity, or Victoria ingestion.

Telemetry-worker seam:

- tests hostile producers and hostile native admission: forged producer fields,
  unknown events/attributes, credit exhaustion, optional-versus-required loss,
  batch/producer gaps, bounded retry/outbox, restart, and drain/close; and
- cannot prove that a separate worker or shared native scheme handler is
  scheduling-isolated in packaged WKWebView without the live gate.

Live gates:

- native WKWebView proof remains required for WebKit delivery, worker
  custom-scheme fetch, streamed scheme responses, stream cancellation/resync,
  run-loop starvation, telemetry-on/off behavior, and end-to-end click/scroll
  budgets;
- worker custom-scheme fetch plus streamed responses must pass native WKWebView
  proof before the R44/R49 cutover. If worker fetch or streaming fails, stop and
  redesign the native carrier; no main-thread product relay is admitted;
- Victoria-backed proof remains required for performance samples and telemetry
  admission;
- existing R32-R40 proof seams remain required and are not replaced
  (`docs/specs/bridge-viewer-transport/performance-demand-lanes.md:277`).

## Channel Topology And Typed Contracts

### R49. The topology has three product channel families plus one telemetry sidecar.

The comm worker named here is the single pane-owned product worker in R41-R66.
Every ordinary Review/File web-to-Swift edge originates in that worker. The
telemetry worker is an explicit observability-plane exception and cannot carry
product state or commands.

Existing compatibility type names may retain `Server`, but every normative
`server worker` reference means this same comm worker. No second server/product
worker exists.

| Channel family | Contract | Required payload shape |
| --- | --- | --- |
| main <-> comm worker | one typed RPC/event protocol over the pane-owned `MessageChannel`; all messages are surface/session scoped | UI intents carry UI revision; bounded replies, slices, transferred Pierre windows, health, dispositions/reset barriers; no store snapshots or main-minted `workerDerivationEpoch`/sequence |
| comm worker <-> Swift product server | one worker-owned typed product transport over custom-scheme POST bodies and streamed responses | capability-only privileged header; typed call/subscription/content bodies; in-band identity, generation/epoch/sequence, lengths, checksums, acks, resets, and health |
| main <-> Pierre workers | Pierre public API exclusively, through one shared opaque courier | complete worker-prepared render job, demand rank, identity, window and budget; no AgentStudio main transform or private Pierre worker traffic |
| main + comm -> telemetry worker -> Swift telemetry endpoint | two dedicated producer ports into one optional per-pane telemetry worker, then telemetry-only scheme POST | compact port-bound samples in; validated/scrubbed sequenced batches and exact loss summaries out |

A comm-owned stateless content-compute pool is internal execution, not another
product authority/channel: it receives jobs only from and returns only to the
comm worker and cannot reach main or Swift.

Exactly one `BridgeProductTransport` facade exists inside the pane comm worker:

```ts
call<K extends BridgeProductCallKind>(kind: K, request: BridgeProductCallRequest<K>): Promise<BridgeProductCallResponse<K>>
subscribe<K extends BridgeProductSubscriptionKind>(kind: K, options: BridgeProductSubscriptionOptions<K>): BridgeProductSubscription<K>
openContent<K extends BridgeProductContentKind>(descriptor: BridgeProductContentDescriptor<K>, options: BridgeProductContentOptions): BridgeProductContentStream<K>
```

`BridgeProductContentOptions` requires an `AbortSignal`; the concrete types are
closed registry lookups under R50, not generic JSON. React/main cannot import or
own this facade, a native subscription, the capability, or raw content. It uses
typed domain/pane clients over the installed `MessagePort` and bounded render
slices. Only the shared worker transport module knows product routes or fetches.

One long-lived physical metadata response stream exists per pane. `subscribe()`
multiplexes logical typed subscriptions on it; it never creates a stream per
file/feature. Each demanded descriptor/window/role gets one independent bounded,
cancellable `openContent()` POST response. Content is not eager or multiplexed
with metadata, avoiding head-of-line blocking.

Direct worker streamed responses are the decided Swift product mechanism.
`WKScriptMessage`, `callJavaScript`, DOM-event intake, page-owned scheme relay,
or feature-owned fetch helpers are rejected production alternatives because
they restore main or a second module as a sequence/backpressure participant. If
direct worker streaming cannot pass native proof, stop and redesign R44/R49.

Direct page/native exceptions are exactly:

- one-shot page identity, pane-session capability, policy, and port bootstrap;
- static app/worker assets needed before workers can exist; and
- narrowly typed native diagnostics/programmatic controls that invoke the same
  local UI-intent boundary as a user action.

These exceptions must not carry product intake, push, content, subscription,
cache, retry, acknowledgement, or backpressure traffic. A diagnostic carrier is
not permission for a product bypass; any resulting product action flows through
the comm worker.

The `WKScriptMessage` / `__bridge_command` RPC plane and every direct main-owned
product scheme caller are deleted by the final cutover's compile-enforced
deletion set. Content worlds remain only for minimal bootstrap isolation and
typed control/probe injection. No ordinary product carrier survives beside the
comm-worker path.

A future domain such as comments adds closed registry cases, a native handler,
and a worker reducer; it adds no transport route/fetch/cache/retry/IPC pathway.

Current script-message RPC inventory and post-migration carriers:

| Current command or lane | Post-migration carrier |
| --- | --- |
| `review.markFileViewed` | main -> worker port, then worker scheme-POST |
| active viewer surface signal | FE UI intent -> worker port; worker owns accepted surface (R42), then scheme-POST |
| `system.bridgeTelemetry` | main compact sample -> telemetry worker -> `agentstudio://telemetry/batch` |
| worktree-file telemetry sink | same telemetry-worker path; no pre-React page recorder |
| page-control/probe commands | typed isolated native -> page adapter; bounded command/result only, with product consequences entering the comm worker |
| intake frames | per-unit cutover to worker streamed subscriptions |

The retained semantic Agent Studio IPC surface has this closed post-cutover
mapping. External IPC never exposes raw WebKit evaluation. An internal typed
page-control adapter may inject one bounded command into an isolated content
world, but it is async, validates its result, invokes the same FE local-intent
seam as the corresponding user action, and returns only the bounded typed
result named below.

| External method(s) | Authority and product carrier | Completion and returned data |
| --- | --- | --- |
| `bridge.diff.load`, `bridge.fileView.open`, `bridge.diff.refresh` | native source authority initiates or rotates the source; the resulting source fact/product flow enters the pane comm worker and never becomes a native/main product relay | correlated worker `sourceAccepted`/`sourceResynced` plus the method's required post-paint state; bounded pane/source identity and outcome only |
| `bridge.diff.selectFile`, `bridge.diff.scrollToFile`, `bridge.diff.expandFile`, `bridge.diff.collapseFile`, `bridge.fileTree.search`, `bridge.fileTree.setFilter`, `bridge.fileTree.revealPath`, `bridge.fileView.showMarkdownPreview` | typed native control -> isolated page-control adapter -> the same FE local-intent function used by pointer/keyboard input; every subsequent demand, command, content, acknowledgement, retry, or write goes main -> comm worker -> Swift as required | the action's declared worker acceptance plus correlated post-paint completion when it changes visible state; bounded ids/status/reason only |
| `bridge.diff.getPackage`, `bridge.diff.renderState` | read-only bounded diagnostic/probe projection; never product mutation, subscription, cache authority, or content carrier | bounded metadata, health, identity, counters, and render facts only; no package snapshot, raw body, source text, or worker-owned store state |
| `bridge.fileView.getContent` | read-only content-handle probe against native lease metadata; never a body-read path | bounded handle, semantic/window metadata, availability, and MIME facts only; no body bytes or source text |
| `bridge.telemetry.snapshot` | typed control -> telemetry-worker `snapshot` | bounded counters/session/proof-eligibility state only; never the legacy native recorder |
| `bridge.telemetry.flush` | typed control -> telemetry-worker `drain` | correlated terminal drain acknowledgement and bounded counts/state; never the legacy native recorder |

Telemetry-off benchmarks use this same typed outer-control clock and correlated
post-paint completion. They do not restore telemetry, inspect a worker store, or
use untyped evaluation as a timing shortcut.

### R50. Channel contracts are typed and constant.

`BridgeWorkerContracts` is the single schema source for main <-> comm-worker
`MessageChannel`; both endpoints compile against its zod-derived versioned wire
types and runtime validators. An absent message shape is a compile error.

Every product API/wire is closed, correlated, and strictly typed at compile time
AND runtime. Closed `BridgeProductCallRegistry`, `BridgeProductSubscriptionRegistry`,
and `BridgeProductContentRegistry` maps use constrained generic lookups to derive
requests, results, options, descriptors, frames, and terminals. Strict Zod schemas
form closed discriminated unions for all call/ack/error, subscription control/data,
content accepted/data/end/error/reset/cancel, and main <-> comm DTO variants;
switches are exhaustive.

Forbidden: `any`; `unknown` fields/retained untyped JSON; `method: string` plus
`Record<string, unknown>`; recursive JSON-value payloads; catch-all variants;
declaration-merging/plugin augmentation; or an unvalidated escape hatch. `unknown`
is allowed only as immediate untrusted parser input and must synchronously become
a closed union, never stored/transport/post-parse handler/API data. Strict object
schemas reject extra/mismatched fields, invalid bounds, and unsupported versions.
Registry requests/results with no data use literal `null`; `{}` is forbidden.

The main <-> comm-worker channel is typed RPC/events, not a shared store. Each
discriminant selects exact correlated identity/freshness and request/result DTOs.
Even fire-and-forget facts are closed; store/query snapshots and generic payloads
are forbidden.

Channel [2] shares the closed vocabulary in TypeScript and Swift. Swift uses
closed `Codable` enums, typed associated structs, and strict coding-key checks.
One versioned hostile corpus proves parity and rejects unknown/extra/missing,
mismatched, oversized, and stale cases in both runtimes; no local frame shapes.

`BridgeTelemetryWorkerContracts` separately owns telemetry bootstrap, port-bound
sample/control unions, credit/loss/health, and drain/close acknowledgements. It
follows the same closed rules but shares no product registry, DTO, or capability.

### R51. Forbidden edges are part of the contract.

| Forbidden edge | Reason | Required enforcement classes |
| --- | --- | --- |
| main -> Swift ordinary Review/File product traffic by any carrier | only bootstrap/assets/typed controls are exempt | import/architecture lint, structural carrier scan, packaged protocol trace |
| Swift product push/intake -> main | `callJavaScript`, DOM/content-world/page relays restore main protocol ownership | Swift/TS structural scan plus packaged trace |
| more than one pane comm-worker instance or feature-owned session | fragments protocol/cache/recovery truth | lifecycle type/API boundary, real-worker identity test, packaged identity trace |
| comm worker -> DOM/render | DOM materialization remains main/Pierre-owned | worker import lint and build boundary |
| comm-owned compute pool -> main/Swift | stateless compute returns only to comm worker | disjoint ports/types and hostile reset test |
| Pierre workers -> demand/fetch/protocol initiator | Pierre is render compute only | public-API types, source scan, worker integration test |
| main or comm -> telemetry endpoint/buffer/outbox | compact samples go only to telemetry worker | import lint, structural scan, telemetry failure test |
| telemetry worker -> product endpoint/state | observability has no product authority | disjoint schemas/routes and hostile worker test |
| any untyped message | bypasses schema/version/validation | closed discriminated unions, exhaustive switches, cross-runtime fixture corpus |

### R52. Main is a bounded courier on the content path.

The sole standard text/diff content route is:

```text
Swift source bytes -> comm-worker canonical byte cache
  -> transferred BridgeWorkerPierreWindowSubmission -> main courier
  -> released Pierre submitWindow() -> transferred Pierre worker payload
  -> Pierre-owned layout/DOM apply -> BridgeRenderDisposition
```

Main may structurally validate the outer identity, bounds, and transfer
descriptor, then call `submitWindow()` exactly once with the received object.
Pierre gathers transfer fields internally and detaches every accepted payload
buffer before returning. Main retains no source buffer, string, decoded line,
or submission object after the synchronous call and cannot copy or reconstruct
one. The complete validation + public-call + worker-submit corridor satisfies
p95 < 4 ms and p99 < 8 ms independently for Review and File View.

Courier admission is credit-bounded. At most one call executes synchronously;
pending main ownership is bounded by the selected window plus one visible
window, and every buffer reference has a disposition or cancellation lease.
After accepted submission, retained main source bytes and duplicate main source
bytes are both zero. Repeated add/replace/evict traversal keeps main retained
heap O(visible-window metadata), never O(document lines).

### R53. Worker messages are transferable-first.

All content-bearing main <-> comm-worker messages use transferable
`ArrayBuffer` representations. Transfer is mandatory, not preferred. Small
ids/ranges/enums/health/display DTOs may use structured clone. Strings or large
object graphs cannot carry file/diff/markdown bodies, line tables, binary
indexes, Pierre window payloads, or persistent-cache content.

When ownership moves across the boundary, the sender must include the
`ArrayBuffer` (or a typed array's underlying `.buffer`) in the transfer list:
`postMessage(payload, [buffer])` or `structuredClone(payload, { transfer:
[buffer] })`. A transferred buffer detaches from the sender and becomes
unavailable there after send. No sender or receiver path may rely on an O(bytes)
clone. If the comm worker must retain canonical cache bytes, it creates one
derived window buffer inside the worker, accounts that allocation, and transfers
ownership; main never owns canonical and derived copies.

`BridgeWorkerContracts` message types must name transfer fields explicitly. A
message with no transfer fields declares an empty transfer list; a message with
content bytes, large paint-ready payloads, or persistent-cache payloads declares
the exact fields that are transferred. Runtime validation
must reject a payload whose declared transfer fields and values disagree.

```text
sender owns buffer
  │
  ├─► postMessage(payload, transferList)
  │      transferList fields are named by BridgeWorkerContracts
  │
  ├─ sender buffer is detached
  │
  └─► receiver owns buffer, with no O(bytes) clone
```

Boundary instrumentation measures clone/transfer duration, bytes, sender
detachment, receiver ownership lifetime, and retained duplicate bytes per
message class. R53 applies to this cutover and the future persistent-cache PR;
there is no content-bearing clone exception.

### R54. Zustand moves to the comm worker; React RPC lifecycle is typed and local.

The architecture has one Bridge data store owner: the comm worker. That store is
implemented as a worker-local Zustand vanilla store unless a later spec replaces
it with an equivalent typed worker-local primitive. React/main must not create,
import, subscribe to, or mutate a Zustand store for Bridge viewer data after the
cutover. Existing main-thread Review/File View Zustand stores are legacy
deletion targets, not implementation options.

React/main has two allowed local surfaces:

- `BridgeWorkerRpcLifecycleStore`, a typed non-Zustand sync store/helper for
  coarse worker RPC lifecycle: open source, refresh, reconnect, search/filter
  command completion, mark-viewed mutation, pending/ack/fail/timeout state, and
  mutation optimism/rollback metadata.
- Non-Zustand render-slice hooks for frame-critical display copies: selected
  item, active mode, viewport/range, hover/focus, expanded/collapsed UI intent,
  panel chrome, row paint copies, content availability copies, and worker health
  copy. This surface exists only to paint synchronously and to apply worker
  slice patches inside the R46 frame budget.

React components must import domain hooks or selectors, not raw worker protocol
state and not Zustand. The RPC lifecycle store must not become an async cache,
high-frequency row/content patch stream, canonical result cache, demand queue,
byte cache, retry owner, refetch owner, or protocol owner.

No store snapshot may cross the worker boundary in either direction. The only
cross-boundary values are closed `BridgeWorkerContracts` DTOs, closed product
transport variants, and declared transfer fields.

Required type families:

| Type family | Runtime | May use | Must contain | Must not contain |
| --- | --- | --- | --- | --- |
| `BridgeMainRenderSnapshotStore` | main/React | non-Zustand store with `useSyncExternalStore` React integration | selected id/ui revision, active-surface intent/accepted copy, Review projection mode copy, viewport/range, hover/focus, expanded UI intent, keyed paint/availability, health | Zustand, source bytes, cache/demand/retry/stream/epoch authority, query cache reads |
| `BridgeCommWorkerStoreState` | comm worker | Zustand vanilla | surface-scoped canonical rows/indexes, byte cache, paint-ready cache, demand membership, in-flight/executor queues, retry/backoff, stream/session/protocol state, `workerDerivationEpoch`, fulfillment state | DOM nodes, React state, component refs, telemetry buffer/outbox, direct Pierre worker initiator state, main-thread query cache objects |
| `BridgeWorkerMainToServerMessage` | main -> comm wire DTO | `BridgeWorkerContracts` zod-derived union | wire version, UI intent revision or request id, command/fact kind, small cloneable payload, declared transfer fields | main-minted `workerDerivationEpoch`/sequence, store snapshots, functions/classes/DOM/`AbortController`, undeclared buffers |
| `BridgeWorkerServerToMainMessage` | wire DTO | `BridgeWorkerContracts` zod-derived union | health events, correlated replies, subscription events, slice patches, availability/content events, epoch/sequence freshness, declared transfer fields | canonical worker store, full package snapshots for interaction updates, untyped payloads |
| `BridgeWorkerSlicePatch` | wire DTO applied to main render snapshot | typed patch union | target slice, operation, item id when keyed, epoch/sequence, small cloneable metadata/display payload | protocol/cache truth, source content bytes, parallel Pierre content route |
| `BridgeWorkerPierreWindowSubmission` | comm worker -> main courier -> Pierre API | public released window DTO | stable item/document/window identity, rank, manifest/checksum, bounded transferred UTF-8/table buffers, byte/line class, Pierre version | strings/source cache, main-recomputed payload, clone mode, private Pierre traffic |
| `BridgeWorkerMarkdownPatch` | comm worker -> main | bounded structural patch union | semantic/attempt identity, node/depth/count bounds, sanitized inert node batch, final flag | source bytes/HTML, script/style/events/URLs, whole document graph |
| `BridgeRenderDisposition` | main -> comm worker product DTO | bounded idempotent union | pane/worker/surface, interaction/attempt/submission id, semantic document/window, `workerDerivationEpoch`, `queued`/`applied`/`painted`/`rejected`/`superseded`, reason | telemetry-only receipt, content body, main-owned retry decision |
| `BridgeWorkerTransferDescriptor` | wire metadata | explicit transfer-list helper | message kind, unique field paths, byte lengths, transfer mode, detached-after-send expectation | implicit content, content clone mode, unmeasured ownership |
| `BridgeProductTransport` plus closed call/subscription/content registries | comm worker <-> Swift product scheme boundary | worker-only facade and shared browser/native contract vocabulary | constrained generic `call`/`subscribe`/`openContent`, correlated typed variants, byte limits, product sequence/reset/health/error frames | React/main imports, feature fetches, generic payloads, URL/header product identity, telemetry DTOs, ad-hoc frame shapes |
| `BridgeWorkerRpcLifecycleStore` | main/React | non-Zustand store/helper with `useSyncExternalStore` React integration | request id, command kind, lifecycle state, timeout state, progress envelope, optimistic intent id, rollback metadata, correlated worker ack/repair references | row arrays, content windows, byte buffers, demand membership, canonical cache entries, refetch/retry authority, worker protocol truth |
| `BridgeWorkerRpcClient` | main/React | typed `MessageChannel` client helper | request id creation, timeout policy, explicit command correlation, typed send/receive, transfer-list handoff to worker | store access, retry/backoff authority, direct Swift RPC, render-slice mutation outside patch helpers |
| `BridgeWorkerPatchApplier` | main/React | non-Zustand helper | R46-budgeted application of `BridgeWorkerSlicePatch` values to `BridgeMainRenderSnapshotStore` subscriptions | protocol ownership, demand scheduling, unbounded synchronous full-list rebuilds |
| `BridgeWorkerTransferListBuilder` | main and worker | shared helper | declared transfer fields, byte counts, detachment assertions | implicit buffers, content clones, retained main source refs |
| `BridgeCommWorkerCommandHandler` | comm worker | worker-local helper around Zustand store and `BridgeProductTransport` | validate typed commands, update `BridgeCommWorkerStoreState`, enqueue demand/content work, publish typed replies/events | direct product fetch/routes, DOM/Pierre direct initiator behavior, React state mutation |
| `BridgePaneCommWorkerSession` | pane composition root plus worker port | one lifecycle/port coordinator | one active worker instance id, pane session, surface clients, bootstrap/install/reset/restart/dispose, telemetry-port replacement | product protocol/cache/demand truth, per-feature worker creation, main-minted `workerDerivationEpoch` |
| `BridgeTelemetryWorkerContracts` | main/comm producer ports and telemetry worker | separate typed wire unions | compact samples, producer credit/sequence, loss summaries, worker health, drain/close | product commands/content/cache/demand/health DTOs, producer-selected endpoint/session/batch sequence |
| `BridgeTelemetryBatchRequest` / `BridgeTelemetryBatchResponse` | telemetry worker <-> Swift telemetry scheme boundary | separate browser/native telemetry contract vocabulary | native-minted telemetry session, batch sequence, scrubbed bounded samples, exact loss summaries, admission response | product command/content/stream/cache/demand DTOs, producer-selected endpoint/session, raw paths/content |
| `BridgeTelemetryWorkerRuntime` | optional telemetry worker | isolated worker-local state | validation, credit admission, buffer, encoded-byte cap, shedding, sequence, bounded retry/outbox, encode/fetch | product state, DOM state, main/comm fallback ownership |

### R55. React RPC lifecycle is not an async cache.

`BridgeWorkerRpcLifecycleStore` is a typed lifecycle surface for worker command
requests, not a freshness, retry, polling, or render-data authority. It exists
because React needs an inspectable request lifecycle and optimistic rollback
surface, while the comm worker remains the only durable data/protocol owner.

Required rules:

| Rule | Required value |
| --- | --- |
| request state | pending, acked, failed, timed out, or superseded envelopes keyed by request id and command kind |
| data shape | ack/status/progress envelopes only; no row arrays, content windows, byte buffers, demand membership, or canonical cache entries |
| retry/refetch | no library-owned retry, focus refetch, reconnect refetch, mount refetch, polling, or invalidation authority |
| reconnect | explicit worker command/event only |
| invalidation | only through typed worker protocol events; render data changes arrive as worker slice patches |
| optimism | may call `BridgeMainRenderSnapshotStore` local-intent helpers and record rollback metadata only |
| durable result | worker ack/repair slice remains the only durable result |

Search/filter input is not automatically coarse RPC. Text input, selected
filters, and local preview state are local render intent. FE sends coalesced
worker facts or an explicit submit command; the lifecycle store observes only
the ack/completion envelope and mutation lifecycle. It must not turn every
keystroke into eager worker RPC or cache a result list as canonical visible
state.

No converted Bridge surface may introduce TanStack Query, `QueryClient`,
`useQuery`, `useMutation`, SWR, Apollo, or an equivalent async cache to manage
Bridge worker RPC lifecycle or visible Bridge data. A tiny typed promise/RPC
client plus `BridgeWorkerRpcLifecycleStore` is the required primitive.

### R56. Main render snapshots use one non-Zustand primitive.

OD-LF2 is closed: the FE primitive is `BridgeMainRenderSnapshotStore`, a
non-Zustand store exposed to React through `useSyncExternalStore`. It has exactly
two write inputs:

- local intent helpers for synchronous UI facts: selected, hover/focus, viewport
  range, expanded/collapsed row ids, active mode, and shell chrome; and
- `BridgeWorkerPatchApplier`, which applies typed worker slice patches inside
  the R46 frame budget.

Render paths read only from this snapshot store and component props. They do not
read async cache data, comm-worker protocol fields, raw worker messages, or
legacy Zustand state. The snapshot store contains display copies only; losing it
may require repainting, but must not lose bytes, demand membership, epochs,
sequences, retries, stream state, or Swift request state.

Every converted surface has one snapshot primitive. Multiple route-local
mini-stores, mixed React-state/query-cache render reads, or a compatibility
bridge from old Zustand into the snapshot store are contract violations.

### R57. Pierre/Shiki ownership and courier budgets are explicit.

Current Pierre cannot satisfy R52/R53/R61: it accepts complete string-backed
items, updates whole items, dirties downstream layout, and posts worker requests
without transfer lists. Cutover therefore REQUIRES a released, pinned public
`@pierre/diffs` byte-backed window API. Cumulative `updateItem`, pseudo-items,
private imports, proxy workers, `patch-package`, local paths, or an AgentStudio
fork are not alternatives.

The released API owns these public concepts:

```text
WindowIdentity:
  semanticDocumentRevision, partitionRevision, windowId, windowRevision,
  payloadChecksum, renderSemanticsRevision
WindowDescriptor:
  ordinal, displayRange, optional context/side ranges,
  estimated split/unified rows, optional sealed payload-segment manifest
SegmentDescriptor:
  segmentId, ordinal, UTF-8 byte range, checksum, stable logical-line id
TransferableUtf8Lines:
  format, bytes:ArrayBuffer, lineStartByteOffsets:ArrayBuffer
WindowedItem:
  one stable item/header plus immutable manifest, total logical extent,
  manifest checksum, and windowed-file or windowed-diff kind
```

`CodeViewHandle` publicly exposes `submitWindow`, `cancelWindow`, `evictWindow`,
`resetWindowedItem`, `setHunkExpansion`, `getWindowState`, and
`subscribeWindowEvents`. `submitWindow` performs synchronous outer validation,
collects every payload buffer internally, posts with a transfer list, and
detaches accepted buffers before returning. Pierre exports worker-safe encoders
and validators; AgentStudio may call them in the comm worker, never on main.
These names express required public capabilities, not frozen upstream spelling.
A pinned release is accepted only when one versioned AgentStudio/Pierre
conformance corpus passes manifest/partition, mutation/no-op, segment, transfer/
detachment, cancel, eviction/cache, hunk-event, anchor, and hostile-input cases.

Coordinates and partitioning are normative:

- file and diff logical ranges are zero-based and half-open;
- a diff context line consumes one logical row; a change block consumes
  `max(deletions, additions)` logical rows; collapsed unchanged lines retain
  logical rows; headers/separators consume none;
- ordered `displayRange` values form a gap-free, non-overlapping document
  partition; tokenizer `contextRange` may overlap, but only display rows render;
- side ranges map logical rows to deletion/addition lines; window ids derive
  deterministically from document/partition/ordinal/display range; and
- a manifest is sealed. Repartitioning requires `resetWindowedItem`, not append
  or whole-item replacement.

`partitionRevision` hashes document revision, algorithm version, and byte/row
policy; split/unified presentation does not repartition. From logical row zero,
each descriptor takes the maximal
next display prefix within BOTH limits with deterministic earliest-boundary
tie-breaking. Context is added then deterministically trimmed to the remaining
budget. `submissionByteLength` is encoded envelope bytes PLUS every unique
transferred content/context/offset/row/hunk/segment buffer; the ceiling applies
to that total. A logical line over budget has a sealed ordered segment manifest;
each checked segment submission stays under budget, Pierre reconstructs one
logical row worker-side, and partial segments never paint.

Submission semantics are deterministic. First payload adds; identical identity
and checksum returns typed `already_applied` or `already_painted` state without
DOM duplication; higher window revision atomically replaces
that descriptor; lower is stale; equal revision with different checksum is a
protocol error. Out-of-order windows place by manifest. Invalid ids, revisions,
offsets, ranges, overlaps, or checksums cause no visible mutation. Coverage is
complete only after every descriptor/segment has applied once. It is historical
diagnostic state, not a preload or performance gate; early/middle/final checksum
and final-window proof are the required traversal gates.

Eviction removes window bytes/AST/render content while retaining descriptor
extent, stable header/item, hunk expansion, and logical anchor; visible, pinned,
or in-flight targets reject eviction. Pierre preserves an anchor of stable item
plus logical row or side/line and viewport offset through add, replace, eviction,
estimate correction, and expansion. AgentStudio never writes `scrollTop`.
Hunks use stable `hunkId`, survive eviction, demand missing descriptor ids,
apply cross-window expansion atomically, preserve the anchor, and never use
blank filler. A partial source that lacks expansion bytes reports typed
`expansion_unavailable`, not empty content.

Pierre owns transferred worker request/response unions, rank-aware scheduling,
cooperative cancellation between bounded decode/token/render slices,
stale-result rejection, byte-bounded per-window cache accounting, layout,
anchors, and window events. AgentStudio owns semantic identities/checksums,
deterministic continuation demand/partition choice, comm-worker encoding,
worker-to-main transfer, one opaque public call, and event-to-disposition mapping.

Every converted surface defines these policy constants in `AppPolicies` or the
BridgeWeb policy mirror:

| Policy | Initial ceiling | Derivation / proof |
| --- | --- | --- |
| `reviewInteractivePierreRenderJobMaxBytes` | <= 512 KiB | Review selected/visible continuation window; Review owns follow-up windows past this ceiling |
| `reviewInteractivePierreRenderJobMaxWindowLines` | <= 400 lines | Review selected/visible continuation window; Review owns follow-up windows past this ceiling |
| `fileViewSelectedPierreRenderJobMaxBytes` | <= 2 MiB | File View selected first bounded window; File View does not promise continuation past this ceiling |
| `fileViewSelectedPierreRenderJobMaxWindowLines` | <= 10,000 lines | File View selected first bounded window; File View does not promise continuation past this ceiling |
| `pierreWindowSubmissionP95Ms` | < 4 ms | main receive/validate/public-submit through transferred worker dispatch |
| `pierreWindowSubmissionP99Ms` | < 8 ms | same corridor, leaving frame budget for local chrome/apply |
| `pierreAnchorLandingMaxErrorPx` | <= 4 px | add/replace/evict/expansion anchor proof |
| `pierreMainRetainedSourceBytesAfterSubmit` | 0 | detachment and reference-lifetime proof |

Review over-budget work splits into manifest windows or offloads preparation;
size never becomes terminal. File View publishes only its canonical bounded
prefix. Representative and maximal-policy jobs, out-of-order/replacement,
cancellation, cache eviction, cross-window hunk expansion, final 100,000-line
window traversal, sender detachment, bounded heap, and anchor error must pass.
Any cumulative whole-item clone/update, repeated header, non-detached buffer,
unbounded worker task, O(total-lines) main memory, or failed latency/slice/
long-task/correctness stop line blocks cutover; thresholds are not weakened.

### R58. Worker-local Zustand is normalized and O(delta).

Moving Bridge data Zustand to the comm worker removes main-thread stalls, but it
does not permit package-shaped worker work. A comm worker is still one
JavaScript event loop; a 100-500 ms synchronous worker action can delay the
selected fact, availability repair, content demand, and tree state even while the
main thread paints local selection chrome.

The worker-local store is normalized:

| Store area | Shape |
| --- | --- |
| rows/tree | `rowById`, `orderedIds`, `indexById`, `childrenByParentId` |
| local facts | `selectedId`, `viewportRange`, `visibleIds`, hover/focus facts |
| demand/execution | `demandByKey`, `inFlightByKey`, per-lane queues |
| cache/render | `byteCache`, `paintReadyByItemId`, `availabilityByItemId` |

Forbidden store shape:

```text
rootSnapshot: { allRows, allContent, allDemand, allStatus }
setRootSnapshot(newEverything)
getState() -> send whole state to main
every click creates new Map(allRows)
```

It must not use a full `getState()` snapshot as a message payload, update input,
or render output.

Every hot action has a bounded touch set:

| Action | Allowed touch set | Forbidden work |
| --- | --- | --- |
| `applySelectedFact(itemId)` | selected id, previous/next row paint, selected demand entry, selected availability | rebuild all rows, clone all row maps, re-sort full package, recalculate all availability |
| `applyViewportFact(range)` | viewport range, entering ids, leaving ids, visible demand entries | full ordered-list derivation, full manifest patch |
| `applyContentReady(itemId, contentKey)` | byte/cache entry for that key, `paintReadyByItemId[itemId]`, `availabilityByItemId[itemId]` | all-content recompute, full paint-ready map publication |
| `applySourceReset(sourceGeneration)` | epoch swap first, stale membership clear, chunked index/list rebuild behind new epoch | synchronous source reset that blocks selected facts |

The threshold classes are policy-owned stop lines:

| Threshold class | Rule | Proof |
| --- | --- | --- |
| worker selected queue wait | selected/click facts satisfy the R32-R40 foreground queue-wait budget: p95 < 16 ms, p99 < 32 ms | lane queue-wait histogram by command class |
| worker hot task duration | one hot action slice must not consume the selected queue-wait budget; initial cap <= 8 ms | handler-duration histogram and long-task counter |
| mutation size | one hot action may touch only selected + visible delta entries | touched-key counter per action |
| patch size | worker publishes bounded delta patches, never full package/list snapshots | patch item/byte counters and source scan |
| source reset | large reset swaps epoch immediately and rebuilds indexes/lists in chunks | reset chunk progress plus selected-preemption test |
| payload | large bytes transfer as declared `ArrayBuffer` payloads or split windows, never accidental clone | transfer descriptor validation and clone/transfer duration |
| derived list | full tree/list derivation is source-reset-only, never scroll/click/hover/content-ready | derivation cause telemetry and unit source scans |

R58's worker hot-task duration class protects worker-local store mutation
slices. It is intentionally distinct from R60's content-preparation compute
slice class; both may start at <= 8 ms, but they have separate owner code and
separate handler-duration histograms. R58's selected queue-wait SLO is shared by
all worker work classes, including R60 content preparation; do not define a
second selected queue-wait budget for worker compute.

Selected/click command handling is O(selected + visible delta). Viewport and
hover handling are O(visible delta) or O(1) per coalesced fact. Source reset may
swap generations atomically, but full-list/index rebuild work must be chunked or
performed behind a new generation so selected foreground work can preempt it.

The worker message loop measures queue wait and handler duration by lane and
command class and posts compact samples to its dedicated telemetry port. It does
not aggregate, encode, flush, retry, or fetch telemetry. A worker-side giant
`Map` clone, full list rebuild,
selector fan-out, or synchronous source reset that delays selected work beyond
the R32-R40 foreground/visible queue budgets is a contract violation even though
it no longer blocks the main thread.

### R59. Product transport and worker DTOs are an explicit trust boundary.

The comm worker is not a trusted native peer merely because it runs in this app.
Every product POST, streamed frame, and main/worker DTO is validated at the
boundary that receives it.

Required trust rules:

- native mints separate per-worker-lifetime product and per-telemetry-session
  capabilities, binds them to pane/page/instance, transfers bootstrap bytes, and
  rotates/revokes them on replacement/reload/disposal; assets are capability-free;
- the sole privileged header is the opaque product capability; no product
  payload/envelope/identity/cursor/descriptor/length is in headers or URL.
  Native authenticates before body access, decode, lease, or provider work;
- every product request is one complete typed POST body. Worker rejects encoded bodies over
  256 KiB before `fetch`; native counts actual `httpBody`, or at most cap + 1
  `httpBodyStream` bytes, before decode/mutation and never trusts/requires
  synthesized `Content-Length`;
- WebKit may materialize that small body before the scheme handler sees it, so
  native admission starts at body access. Large worker -> Swift uploads are out
  of scope;
- worker global scope accepts exactly one typed install-port bootstrap; ordinary
  commands arrive only on the installed port;
- pane-plane requests carry pane/session/instance/version plus stream/request and replay identity. Surface-scoped variants carry source plus
  `workerDerivationEpoch`; their closed product kind derives Review or File, so ordinary variants never repeat `surface`;
- both runtimes reject invalid UTF-8, duplicate object members, non-scalar typed
  strings, and unknown or Unicode-lookalike keys before typed handler/state mutation.
  TypeScript enforces byte/depth/member bounds, fatal UTF-8 decode, and duplicate
  scanning before syntactic document `JSON.parse`; JavaScript preserves exact decoded
  key spelling, then the selected strict Zod union rejects non-scalar strings and unknown/Kelvin-sign keys before returning typed data. Those union schemas own the vocabulary; no duplicate global TypeScript key registry is required;
- Swift bounds and scans raw bytes, then compares every decoded member name's exact UTF-8 bytes with the closed ASCII product-key allowlist before `JSONDecoder`; it never relies on canonically equivalent `String` equality for key admission;
- path/interest identity, uniqueness, and ordering use exact UTF-8 byte identity in both runtimes. Shared composed/decomposed vectors prove no normalization enters canonical state;
- streamed frames are length-delimited and versioned; declared length is capped
  before allocation/decode; native producer queues are bounded and overflow
  produces reset-required rather than silent loss;
- stream gaps, duplicates, malformed frames, or wrong-epoch NEW admissions cause explicit rejection/reset. Already-admitted producers may finish with their
  admitted epoch after its floor advances; fetch abort, page disposal, and worker restart still cancel and unregister native production;
- raw file paths, raw content, command payload bodies, errors containing source
  text, and secret-bearing metadata are scrubbed from telemetry;
- telemetry producer identity is port-bound; samples cannot claim producer,
  session, endpoint, scenario, or batch sequence, and unknown attributes are
  rejected before buffering;
- receivers validate observable transfer fields/values/lengths/class/budget/
  identity/freshness. Only the schema-driven sender helper may post content; it
  supplies the transfer list and asserts sender `byteLength == 0` after send.
  Import/lint boundaries forbid raw content `postMessage`; receivers cannot
  claim to observe remote detachment;
- browser-supplied display paths never become filesystem authority; content
  opens remain descriptor/lease based and pane/session/generation bound;
- repository markdown, filenames, code, and worker-rendered output are untrusted
  display input; markdown keeps raw HTML disabled and is main-sanitized with
  scripts, network-capable/interactive elements, event attributes, SVG/MathML,
  unsafe CSS, and external fetches forbidden, with input/output/node/depth caps;
- hostile seams cover forged ids/epochs, body caps/streams, absent or misleading
  `Content-Length`, strict variants/fields, transfer descriptors, and reordered
  or duplicate metadata/content frames.

Typed diagnostics/programmatic controls are method-allowlisted, bounded, and
limited to the same local selection/reveal/search/filter/scroll/probe intent
surface as user actions. They cannot carry product content/intake/push or return
session capabilities. Content-world/script-message RPC is not a fallback for
these rules. If privileged scheme requests cannot be session-bound before body
access/decode, content cancellation cannot bound native production, or an
unbounded payload must decode before its cap, the design is blocked.

### R60. Worker content preparation is budgeted and preemptible.

R44 moves parse, decode, window selection, diff preparation, highlight
preparation, cache admission, and render-job preparation off the main thread. It
does not permit those steps to become one package-shaped synchronous task inside
the comm worker. The R44 -> R58 seam is explicit: store mutations and content
preparation share the same worker event loop unless preparation is chunked or
offloaded, so both work classes must preserve selected preemption.

All worker-side content preparation enters a `WorkerContentPreparationPump`.
The pump is rank-ordered with selected/current work first, cooperatively yields
between slices, and records queue-wait plus handler/compute duration by lane,
work kind, source epoch, and payload class. JavaScript cannot preempt a running
synchronous task; selected preemption is only a valid claim when every
background/visible compute unit yields before the selected queue-wait budget is
spent.

Markdown source stays inside the comm-worker execution boundary. The pump parses
it in bounded slices or transfers it to a comm-owned stateless compute pool;
that pool has no main/Swift/product port or authority. It returns bounded inert
render-tree batches to the comm worker, which emits `BridgeWorkerMarkdownPatch`
values for R46 final main sanitization/apply. Jobs carry semantic/worker/attempt
identity, cancel on surface/runtime reset, and close with the normal painted
disposition after the final batch. Raw markdown never reaches main.

Worker-internal component:

| Component | Runtime | Owns | Must not own |
| --- | --- | --- | --- |
| `WorkerContentPreparationPump` | comm worker | rank-ordered prep queue, yield points, selected preemption, resumable chunk bookkeeping, stale-epoch aborts, prep-slice telemetry | canonical store state outside `BridgeCommWorkerStoreState`, Pierre/Shiki execution, main render state, Swift protocol authority |

Initial worker compute policy:

| Policy | Initial ceiling | Constants Annex class | Rule |
| --- | --- | --- | --- |
| `workerComputeSliceMaxMs` | <= 8 ms | worker content-preparation compute slice | every synchronous worker compute slice, including parse/window/diff/highlight prep, must yield before this cap |
| `workerContentPrepInlineMaxBytes` | <= 512 KiB by default | worker inline preparation payload | Review continuation windows and non-selected prep stay on this default; selected File View first-window prep uses the R57 File View 2 MiB safety envelope |
| `workerContentPrepInlineMaxLines` | <= 400 lines by default | worker inline preparation slice | Review continuation windows and non-selected prep stay on this default; selected File View first-window prep uses the R57 File View 10,000-line safety envelope |
| R58 worker selected queue-wait p95 | < 16 ms | shared worker selected queue-wait SLO | selected/click facts must not wait behind background content prep |
| R58 worker selected queue-wait p99 | < 32 ms | shared worker selected queue-wait SLO | same budget as R32-R40 foreground queue wait |

Review preparation above one window/slice ceiling MUST split into manifest
windows or offload bounded compute while the comm worker remains the authority.
The selected window may show honest loading while pending; size cannot produce
terminal unavailable. File View may chunk/offload compute internally but emits
only one canonical bounded prefix, not continuation windows. Speculative work
may be demoted; selected/visible membership cannot be discarded.

Content preparation below the byte/line ceiling is still not automatically safe:
if measured slice duration exceeds `workerComputeSliceMaxMs`, the next revision
must chunk, reduce the window, or offload that work before the cutover can claim
R60. A large diff/file prepare test is mandatory: while an 18k-line-equivalent
fixture or policy-sized stress fixture is preparing, a selected fact enters the
worker and its queue wait remains under the selected p95/p99 budget.

OD-LF1 is closed at the ownership level: the comm worker is the single
protocol/cache/demand authority and owns scheduling decisions. Physical compute
may run as local pump slices or in a coordinated compute pool, but no
package-shaped parse/window/diff/highlight preparation may run as one
synchronous comm-worker task.

Canonical data flow:

```text
user click / key / hover / scroll
  │
  ├─► BridgeMainRenderSnapshotStore hooks
  │     synchronous local paint of selected/hover/viewport chrome
  │
  └─► BridgeWorkerMainToServerMessage
        typed RPC/fact DTO, small structured-clone payload
        │
        ▼
      comm-worker store
        canonical demand/cache/protocol update
        WorkerContentPreparationPump for fetch/decode/window/rank prep
        │
        ├─► BridgeProductTransport call/subscribe/openContent when needed
        ├─► compact measurement sample to telemetry-worker port
        │
        └─► BridgeWorkerServerToMainMessage
              typed event/reply with slice patches and
              BridgeWorkerPierreWindowSubmission values
              transferred for every content-bearing ownership move
              │
              ▼
            BridgeMainRenderSnapshotStore subscriptions
              R46 frame-budgeted patch apply and low-cost
              Pierre courier enqueue
              │
              ├─► BridgeRenderDisposition back to comm worker
              └─► compact measurement sample to telemetry-worker port
```

Transfer/consumer matrix. Every content-bearing message class has exactly one
consumer and one ownership mode; an unlisted or parallel route is forbidden.

| Surface | Payload class | Boundary | Mode | Rule |
| --- | --- | --- | --- | --- |
| Review | select, hover, surface/projection mode, viewport, mark-viewed facts | main -> comm worker | structured clone DTO | Small ids, hashes, ranges, enums, and UI revisions; never `workerDerivationEpoch`/sequence. |
| Review | open/refresh/reconnect/search/filter RPC via typed lifecycle store | main -> comm worker | structured clone DTO | Request keys and variables are cloneable DTOs; optimistic state stays in lifecycle/render hooks, not in worker payload. |
| Review | metadata descriptors, availability, row chrome, tree/window patches | comm worker -> main | structured clone DTO | Only bounded visible/window deltas may cross; full-package snapshots are forbidden. |
| Review | source/diff/content bytes fetched from Swift | Swift -> comm worker | stream/`ArrayBuffer` in worker | Worker consumes `ReadableStream<Uint8Array>`/`arrayBuffer()` and owns the byte cache; main does not receive raw bytes. |
| Review | diff/text `BridgeWorkerPierreWindowSubmission` | comm worker -> main -> Pierre `submitWindow` -> Pierre worker | transfer at both ownership moves | Sole CodeView content consumer. Main forwards once; accepted buffers detach before return; no separate line/run payload. |
| Review | markdown source/render tree | comm -> optional comm-owned compute -> comm -> main patches | source transfer only inside worker execution; bounded structural DTO patches to main | Sole markdown consumer; raw source never reaches main/Pierre; final patch uses normal disposition. |
| Review/File | render disposition | main -> comm worker | small structured-clone DTO | One idempotent transition per job/window state; full identity and reason required; no telemetry dependency or content body. |
| Review/File | telemetry sample | main or comm -> telemetry worker | compact structured-clone DTO on dedicated producer port | Producer timestamps/correlates only. Telemetry worker owns validation, credit, buffer, bytes, sequence, encode, retry/outbox, and POST. |
| File View | open file, select path, expand/collapse, filter/search, viewport facts | main -> comm worker | structured clone DTO | Small path ids/hashes, filter text, row ids, and ranges; never full tree state. |
| File View | tree metadata, descriptor windows, availability, row paint patches | comm worker -> main | structured clone DTO | Only bounded visible/window deltas may cross; full manifest/list snapshots are forbidden. |
| File View | file contents fetched from Swift | Swift -> comm worker | stream/`ArrayBuffer` in worker | Worker owns raw file bytes and decoded/cache truth; main receives availability or paint-ready display payload only. |
| File View | one text-prefix `BridgeWorkerPierreWindowSubmission` | comm worker -> main -> Pierre `submitWindow` -> Pierre worker | transfer at both ownership moves | Sole text-content consumer; exact canonical prefix, detachment asserted, no separate run/window payload. |
| File View | binary/unsupported/unavailable result | comm worker -> main | small structured clone availability DTO | No body crosses; explicit terminal/truncation metadata only. |
| File View | initial load/progress/worker health | comm worker -> main | structured clone DTO | Progress and health are small render-copy facts; no content bytes or raw manifest snapshot. |

### R61. Review continuation and File View bounds are observable product state.

Review's 512 KiB / 400-line values are per-window courier/preparation ceilings,
not a selected-diff product cap. The worker contract includes current desired
CodeView logical ranges and the sealed R57 manifest. Desired selected/visible
windows remain demand members until matching paint or non-size terminal source
failure. Windows may arrive out of order and merge only into their descriptor;
eviction preserves extent/header/anchor and re-entry re-demands the same window.
`coverageComplete` means every manifest window painted at least once, including
the terminal real hunk. The 100,000-line fixture must prove early, middle, and
final checksums without cumulative whole-item update, blank filler, or prefix
replay.

File View has no continuation state machine. It publishes one real prefix whose
serialized content is bounded by both 2 MiB and 10,000 actual payload lines.
The item may expose `totalLineCount` and explicit truncation/window metadata, but
must not append whitespace/newlines to reserve full-file height or imply that
unloaded lines are content. Binary, unsupported encoding, unavailable, and
truncated states are explicit and stable; size alone yields readable truncation,
not unavailable.

Window selection, line slicing, continuation membership, and truncation
classification are comm-worker facts. Main/Pierre may render the supplied
window but cannot choose, pad, or reinterpret it.

### R62. End-to-end proof is correlated, layered, and failure-preserving.

One safe interaction id connects:

```text
local intent -> worker demand -> Swift request/stream -> worker ready
  -> main accepted/rejected -> Pierre queued -> DOM applied -> painted/superseded
```

The product control plane uses typed commands, patches, and dispositions.
Telemetry observes the same ids but cannot complete or repair the lifecycle.
Every required stage emits accepted/rejected/superseded state so a gap has a
named owner rather than an unmeasured wait.

A benchmark cell is the Cartesian product of runtime, surface, interaction,
cache class, and telemetry state named in the success contract. Browser timing
starts at the trusted committing event timestamp before handler delivery;
`input_queue_wait` ends at the first handler instruction. Synthetic DOM
`.click()` is not a timing stimulus. Semantic IPC timing starts on the
controller's monotonic clock before dispatch and ends at correlated post-paint
completion on that same outer clock. Actionability controls cohort eligibility,
never clock reset; cross-clock values are not subtracted without calibration.

| Interaction metric | Required painted endpoint |
| --- | --- |
| selection feedback | selected chrome plus matching readable, terminal, or honest selected placeholder |
| fresh display readable | matching semantic/window/render identity and current validation lease; no worker trip credited |
| selected readable | matching current window after worker/Pierre/apply and post-paint check |
| terminal availability | matching binary/unsupported/unavailable/failure state |
| rail/CodeView scroll motion | first confirmed frame with intended nonzero motion |
| rail/CodeView window painted | settled desired rows/window are correct, checksum-matching, nonblank, and painted |

Published scroll budgets require both motion and correct-window endpoints.
Every attempted row records cell, launch, interaction/attempt id, outcome,
duration, and a deadline fixed before execution:
`max(1000 ms, 5 * applicable p99 budget)`. Success uses endpoint minus start;
detected wrong/stale/blank/disappeared/superseded uses detection minus start;
timeout/wedge/missing endpoint uses the deadline. Every failure enters the
nearest-rank percentile array and independently fails correctness. Nonfinite or
negative duration invalidates the artifact.

Telemetry-on baseline publication stages are:

```text
stimulus_issued -> main_intent_received -> local_intent_committed
 -> local_feedback_painted -> worker_intent_received -> demand_issued
 -> content_source_resolved -> [swift_request_issued -> swift_response_received]
 -> worker_ready -> main_job_received -> main_validity_decided
 -> apply_queued -> pierre_queued -> dom_applied
 -> readable_painted | terminal_availability_painted
 -> render_disposition_received -> attempt_closed
```

The lifecycle catalog is closed:

| Variant | Required control path / fulfillment |
| --- | --- |
| fresh display or cached terminal | local paint -> mandatory worker intent -> `selectionAccepted` -> reuse current painted residency/terminal ref -> close; no new attempt/disposition |
| worker cache | baseline path without Swift stages; new publication/painted disposition |
| cold miss | full baseline path |
| cold terminal | through worker/main terminal patch -> terminal paint/disposition; no Pierre |
| markdown | demand/source -> markdown compute queued/completed -> bounded patches -> DOM paint/disposition; no Pierre |
| continuation | baseline repeated per desired window |
| republish | lease expired/rejected -> replacement attempt -> already-painted acknowledgement or normal apply/paint |
| surface reset/runtime restart | barrier/ack -> facts re-emitted -> resync/re-demand -> one normal terminal path |

Stale, timeout, wrong, disappearance, and failure close with that exact outcome.
Telemetry-off has no telemetry worker or
producer ports and proves only external input-to-paint, correctness, motion,
console, and event-loop/frame gaps. It cannot close internal stage SLOs.

The owned main-loop measurement window spans stimulus through one confirmed
frame after endpoint/deadline. Chromium requires zero overlapping Long Tasks
`>= 50 ms` and reports rAF gaps. WKWebView, which lacks that API, runs a
foreground sentinel at nominal cadence `<= 8 ms`, requires zero consecutive
callback gaps `>= 50 ms`, and reports rAF gaps over 16/33/50 ms. Startup and
unrelated background time are separate scenarios.

Required proof layers are distinct:

1. deterministic dev server with real comm, telemetry, and Pierre workers,
   3,420+ file / 100,000-line Review plus large File View, browser automation,
   screenshots, console checks, scroll motion, long-task/event-loop evidence,
   and raw benchmark families;
2. headless Swift provider/manifest, scheduler, product stream,
   generation/reset/security, capability, cancellation, sequence, queue, and
   telemetry-admission proof without visual claims;
3. packaged current-worktree Agent Studio WKWebView using real
   `agentstudio://` workers/product streams/content/telemetry, semantic Agent
   Studio IPC stimuli, and marker-scoped VictoriaLogs/VictoriaMetrics;
4. Peekaboo visible/manual proof for correct selection/content persistence and
   momentum scrolling; Peekaboo is not the timing oracle; and
5. static negative proof, type/lint/format/tests, implementation review, and PR
   checks/comments/threads/mergeability.

Lower seams do not substitute for higher claims. A fake worker cannot prove
real clone/transfer or scheduling cost; browser proof cannot prove WKWebView
scheme behavior; headless Swift cannot prove UI; screenshots cannot prove p99.
Required telemetry gaps, missing raw samples, omitted failures, wrong content,
blank windows, disappearance, wedges, or stale paint fail the run even when the
remaining numeric samples meet percentile budgets.

### R63. Render fulfillment, reset, and worker restart are one state machine.

```text
desired -> preparing -> published(attempt) -> queued -> applied -> painted
   ^             |             | rejected/superseded/lease-expired |
   +-------------+-------------+-----------------------------------+
```

Only matching `painted` or explicit non-size terminal availability fulfills
selected/visible membership. `attemptId` is new per publication;
`submissionId` and semantic window identity remain stable. Dispositions are
idempotent, monotonic (`queued -> applied -> painted`), and each kind occurs at
most once per attempt. Conflicting/out-of-order receipts are rejected.

Every published attempt owns a policy-bounded receipt lease. A current desired
window whose lease expires, or whose attempt is rejected/superseded, returns to
desired after bounded backoff and republishes with a new attempt id. Main/Pierre
dedupe by submission/window identity so a lost receipt cannot duplicate DOM.
For `already_painted`, main performs the normal post-frame identity check and
sends `painted` for the NEW attempt; `already_applied` waits for the Pierre paint
event. Thus idempotent no-op closes the receipt lease without inventing a paint.
After a policy-bounded attempt burst, the worker marks transport unhealthy and
starts reset/reconnect; demand membership is never parked or abandoned.

A routine source/stream reset is `SurfaceSourceEpochReset(surface, oldEpoch,
newEpoch, barrierId)`: the worker instance and other surface context survive;
main cancels only old-epoch work for that surface and acks before its new-epoch
publication. Worker error/`messageerror`, bootstrap timeout, or pane-lifetime
health failure instead creates `CommWorkerRuntimeRestart(oldInstance,
barrierId)`: main raises its instance floor, cancels all old work, acks, and
rejects late receipts. The replacement gets a native-authorized instance lease,
reopens/resyncs, re-mints epochs, and receives re-emitted FE facts, never product
rows/content. Missing ack/repeated restart becomes visibly unhealthy; no fallback
appears.

### R64. Swift product requests and streams are framed, capable, and cancellable.

The comm worker alone uses three fixed product routes:

| Route | Request | Response |
| --- | --- | --- |
| `POST agentstudio://rpc/command` | one closed call/session/subscription control body | one closed correlated result/ack/error body |
| `POST agentstudio://rpc/stream` | one pane metadata-stream open/resume body | one continuous length-prefixed typed metadata response |
| `POST agentstudio://rpc/content` | one demanded descriptor/window/role body | one independently cancellable typed binary content response |

Every route follows R59's actual-body 256 KiB admission. The authenticated pane session is `wireVersion: 2` plus `paneSessionId`, a freshly native-minted
`workerInstanceId`, and its 256-bit opaque capability. Bootstrap transfers the capability's 32 bytes into the worker and detaches main; only the capability is a privileged header. Replacement revokes old subscriptions/content/leases.
No product identity/length appears in URL or headers, and the capability never appears in body/response/DOM/log/telemetry/error. Static assets and `OPTIONS` remain capability-free. This not-yet-installed wire has no v1 decoder, fallback, compatibility branch, global `workerEpoch`, or dual path.

The command union is `workerSession.open`, `product.call`, `subscription.open`, `subscription.updateBatch`, `subscription.cancel`, or
`workerSession.resync`. `workerSession.open` carries literal `request: null` and establishes only the authenticated pane/worker lifetime. Each typed
`subscription.open` carries its kind-specific fixed source configuration, where applicable, and establishes revision zero with the kind-specific canonical
empty-interest hash. Mutable interests/path scope move only through nonempty typed delta batches carrying update id, subscription kind/id, base revision/hash, target
revision/hash, batch index/count, total delta count, and the kind-specific delta. Target revision is exactly base + 1. Delta adds are idempotent upserts,
including lane changes; removes delete membership.

Interest hashes use one canonical binary form: `u8 version=1 | u8 kind (review=1, file=2) | u32be interestCount`, then exact-UTF-8-byte-sorted records of
`u32be keyByteLength | key bytes | u8 lane` (`foreground=1`, `active=2`, `visible=3`, `nearby=4`, `speculative=5`, `idle=6`). File state appends
`u32be pathScopeCount` and exact-UTF-8-byte-sorted `u32be pathByteLength | path bytes` records. Fixed source configuration is excluded; no Unicode normalization occurs. SHA-256 covers exactly those bytes, whose canonical encoding is separately capped at 256 KiB. Shared empty, multi-lane, and composed/decomposed vectors bind TypeScript and Swift.

`workerDerivationEpoch` exists only on a surface-scoped request or push frame. Closed call/subscription/content kinds map exhaustively to Review or File; ordinary variants MUST NOT repeat `surface`.
It is required on `product.call`, each subscription open/update/cancel, each active `workerSession.resync` subscription entry, and each content open. Pane/session open, metadata-stream open, and the top-level resync envelope carry none. Swift checks independent Review/File floors only for NEW admission. Active resync entries deriving to one surface MUST share one epoch; Review and File may differ, but a same-surface conflict atomically rejects the whole resync before floor or subscription mutation.
Responses are `workerSession.accepted`, `call.completed`, `subscription.openAccepted`, `subscription.updateBatchAccepted`, `subscription.cancelAccepted`, `resync.accepted`, or typed `request.error`.
These correlated control responses do not repeat `workerDerivationEpoch`: the single pending request supplies any surface and admitted epoch. At most one update id is staged per subscription; another is rejected with
`sequence_conflict` while the worker coalesces newer desired state. Batches start at zero, are contiguous, repeat identical update metadata, and globally
preserve delta uniqueness/count ceilings. Exact batch retry reuses id/sequence/bytes and returns the cached response; changed bytes or reuse of a committed
update id through a new request is fatal. Native commits only when all batches are present, the base revision/hash still match, the resultant state is valid,
and its recomputed hash equals the target. `BridgeProductControlMux` permits one unacknowledged admission.

One `metadataStream.open` establishes the pane stream. Each logical metadata frame is `u32be frameBodyLength | strict typed UTF-8 JSON body`; `frameBodyLength` counts only the body and has a hard 256 KiB ceiling. WebKit delivery chunks are non-semantic.
Fresh `metadataStream.accepted` consumes pane-wide `streamSequence` zero; resume from N consumes N+1 for `resumed`/`snapshot_required`, then continues contiguously. Frame kinds remain `metadataStream.accepted`, `subscription.accepted`, `subscription.interestsCommitted`, `subscription.data`, `subscription.reset`, `subscription.end`, `subscription.cancelled`, `content.cancelled`, and `metadataStream.error`.
All carry wire/pane/worker/stream plus that sequence. Pane-plane accepted/error frames carry no derivation epoch. Every subscription frame carries kind/id, source, its admitted `workerDerivationEpoch`, cursor, interest revision/hash, and subscription sequence; kind derives surface. Mixed Review/File frames interleave on one contiguous pane-wide `streamSequence`. `interestsCommitted` is the ordered barrier resolving `update()`: no new-revision data precedes it and no old-revision data follows it.
Cancel, reset, resync, and replacement discard staged updates. Reset advances revision with canonical empty interests for add-all replay; mismatch uses `interest_mismatch`, not session-fatal failure. `content.cancelled` carries content/request/lease/descriptor/window/role identity plus `stopped | already_terminal` only after zero producer residue; subscription cancel stops only that producer, and reconnect resumes a contiguous suffix or snapshot.
After a floor advances, older `subscription.accepted`, `subscription.interestsCommitted`, and `subscription.data` consume pane-wide sequence continuity but cannot commit interests, admit/cache/publish data, or reset current-epoch state. Cleanup-only `subscription.reset`, `subscription.end`, `subscription.cancelled`, and `content.cancelled` may close producer/request/lease correlation and reach zero residue only; they never mutate current surface truth.
A content response is bound by its accepted epoch. A stale `content.accepted` may bind only the already-admitted response identity for abort/settlement; it and later data cannot admit/cache/publish content. After the floor advances, terminal `content.end`/`content.error`/`content.reset` may settle correlation and discard staging only. Floor gating never rejects cleanup for admitted work.

Each `openContent()` concurrently POSTs a typed content kind, descriptor, lease, `contentRequestId`, requested window/role coordinates, declared exact length or `null`, authoritative expected SHA-256 or `null`, and mandatory maximum bytes; it does not consume the control sequence. Binary response framing is:

```text
u32be frameBodyLength | u8 frameTag | u32be contentSequence | tag-specific body
accepted/end/error/reset: strict typed UTF-8 JSON | data: u32be offsetBytes | raw bytes
```

`frameBodyLength` counts every byte after its own four-byte prefix. Tags remain `0x01 content.accepted`, `0x02 content.data`, `0x03 content.end`, `0x04 content.error`, and `0x05 content.reset`; there is no separate header-length prefix.
`content.accepted` is sequence zero. Its strict JSON body carries full request/lease/pane/worker-instance/content identity plus the admitted `workerDerivationEpoch`, declared and maximum length, and expected digest, binding this non-multiplexed response stream to one request and producer continuation.
Every later sequence is positive and contiguous. `content.data` carries `u32be offsetBytes` followed by raw bytes; raw length is derived from `frameBodyLength`, never repeated in JSON, and is capped at 128 KiB. Data may not precede acceptance.
`content.end`, `content.error`, and `content.reset` are terminal and carry only small strict JSON terminal fields; stream context comes from acceptance. End reports observed total and SHA-256, verifies authoritative expectation, and lets the worker derive semantic identity before cache admission.
Every content frame body has the universal hostile-input ceiling of 256 KiB; every content JSON control body has a separate 16 KiB ceiling. Exactly 2 MiB of File content is sixteen full 128 KiB data frames plus accepted/end; a partial final data frame is valid.
WebKit may split or coalesce bytes arbitrarily. Prefix/stage caps precede allocation/decode, and both decoders use fixed-capacity reference-owned accumulators rather than repeated copy-on-write append.
Each native producer owns exactly one `URLSchemeTask` response continuation. Cross-stream writes, wrong producer identity, pre-accepted data, gaps, duplicates, offset mismatch, overflow, invalid digest, or post-terminal bytes poison that response, discard staged bytes, and perform no product-state mutation.
Native queues retain frame/byte caps and terminal reserve. Abort closes only that response; native stops/unregisters its producer before the pane metadata stream emits correlated `content.cancelled`. The worker settles only after local fetch abort plus that lifecycle frame; disposal/replacement awaits the same zero-residue barrier.
Shared raw TS/Swift vectors cover exact 128 KiB data and +1 rejection, exact 2 MiB segmentation, 1-byte/4 KiB arbitrary fragmentation, cross-stream/terminal hostility, strict JSON/interest semantics, and checksum/cancel/resume/restart. An ingress/relocation/allocation oracle proves bounded linear accumulation. Packaged benchmarks start at 128 KiB emission and must satisfy the existing p99 and synchronous-slice budgets before that producer policy changes.

### R65. File View byte, encoding, line, and truncation semantics are canonical.

Binary/provider-unsupported classification occurs before decode; a NUL in the inspected prefix is binary. Invalid UTF-8 is `unsupported_encoding`, never
replacement-decoded. Supported text is the maximal prefix satisfying BOTH 2 * 1024 * 1024 bytes and 10,000 payload lines. A byte cut backs up to the last
complete UTF-8 scalar; a partial final source line is displayed/counts and sets `endsMidLine`.

LF terminates a line; CRLF is one terminator; trailing LF creates no extra empty
line; empty content has zero lines. Thus `"a\n"` is 1 line, `"a\nb"` is 2, a
2-line cap of `"a\nb\nc"` is exactly `"a\nb\n"`, and a cut inside the U+20AC
scalar of escaped `"a\u20ACb"` retains only `"a"`.
The descriptor separately carries semantic identity, prefix hash, payload byte/
line counts, optional total line count, `byte_limit | line_limit | both | none`,
`endsMidLine`, `endsWithNewline`, and `utf-8`. Metadata never fabricates bytes,
lines, whitespace, or layout height. TypeScript and Swift share these fixtures.

### R66. Telemetry credits, admission, restart, and drain are explicit.

`BridgePaneTelemetrySession` alone creates/monitors the optional worker. Failure
signals are worker `error`/`messageerror`, bootstrap/port timeout, fatal health,
or missing drain ack. Failure closes producer ports and makes the run
proof-ineligible while product continues. Replacement creates a new telemetry
session; sessions cannot be pooled. Comm-worker restart revokes/replaces only
its producer port and sequence; old-port traffic fails proof.

`producer.install -> producer.ready(initialSampleCredits, controlCredits)` opens
a port. One sample credit represents one pipeline slot capped by
`compactSampleMaxEncodedBytes`; it is consumed before post and refilled only
after native accepted/duplicate admission or accounted shedding frees that slot,
not merely worker receipt. Reserved control credit is separate and returned only
by control acknowledgement. Every attempted event advances producer sequence,
including pre-ingress loss. With no sample credit, a producer retains no body;
it increments bounded aggregate counters/ranges. `loss.summary` uses control
credit, is ordered after its range, and must be acknowledged. Counter-key
overflow emits `loss_counter_overflow` and fails proof. Requiredness derives
from event kind: every R62 lifecycle/gate sample,
abort/stale/unavailable/timeout/reset/retry/failure/jank event, and telemetry
integrity event is required. Required loss anywhere sets `proofEligible=false`;
optional diagnostic loss is exact and marks the run lossy.

Native bootstrap supplies policy classes for sample/control credits, producer
loss-key cap, worker sample/byte buffer, batch count/bytes, minimum flush,
single in-flight batch, outbox count/bytes, retry/backoff, and drain deadline.
The worker validates/scrubs before admission, sheds optional before required,
encodes, sequences, retries, and posts with
`X-AgentStudio-Bridge-Telemetry-Capability`.

Native replies `accepted`, `duplicate`, `accepted_with_loss`, or `rejected`,
with telemetry session/batch sequence, next expected sequence, accepted/loss
counts, and retryability/delay when rejected. Admission is idempotent by session,
sequence, and native body digest; retry reuses identical bytes/sequence; conflict
is non-retryable; rejection admits zero; empty success is forbidden. Required
native loss/rejection or retry exhaustion fails proof.

Typed `snapshot`, `drain`, and `drainAndClose` address the sidecar. Drain revokes
sample credits, sends ordered producer barriers, seals each producer at an
acknowledged sequence/loss high-watermark, admits every required sample/summary
through those marks, then either reopens with new grants or closes/revokes ports.
It returns only counters/state/proof eligibility plus admitted batch and terminal
ack. Main may courier control but cannot inspect bodies or flush. A racing event,
missing barrier/loss/native/close ack, or post-seal required event fails proof.
The semantic IPC methods `bridge.telemetry.snapshot` and
`bridge.telemetry.flush` are adapters to `snapshot` and `drain` respectively;
they cannot read or drain `BridgePerformanceTraceRecorder` or another native
fallback pipeline.

## Action And Event Sequence Contracts

Every user action and system event must preserve the local-first rule: FE may
paint only from local render slices, and worker/native traffic may repair,
subscribe, fetch, or append facts after that paint. Every arrow crossing a
boundary is fire-and-forget or a subscription; no arrow may turn around
synchronously into a paint.

Boundary notation:

```text
main/FE -> comm worker       pane MessageChannel product boundary
comm worker -> Swift         typed product call/metadata/content POST boundary
Swift -> comm worker         streamed push/content/response boundary
comm worker -> main/FE       typed slice/job publication boundary
main/FE -> comm worker       typed render-disposition boundary
main/comm -> telemetry worker dedicated compact-sample producer ports
telemetry worker -> Swift    telemetry-only scheme POST boundary
main/FE -> Pierre worker     public Pierre API compute/apply boundary
```

### Action/Event Inventory

| Trigger | Initiating actor | Boundary crossings | Paint rule | Governing requirements |
| --- | --- | --- | --- | --- |
| click cache-hit | user/FE | 0 before content paint; mandatory post-paint UI-revision fact -> comm worker -> `selectionAccepted` residency ref | frame-1 paints readable selected content; later ack closes control only | R41, R42, R45, R48, R49, R62 |
| click cold | user/FE | 0 before frame-1; later FE -> comm worker demand, comm -> Swift fetch/subscription, Swift -> comm content, comm -> FE job/slice, FE -> comm disposition | frame-1 paints selected identity plus honest loading; readable success occurs only after current content paint and matching receipt | R41, R42, R44, R46, R49, R52, R62 |
| scroll momentum | user/FE/Pierre | one rAF-coalesced FE -> comm worker viewport fact per frame while moving; main -> Pierre worker through Pierre API only | Pierre scrolls existing DOM immediately; incoming slices that affect viewport are HELD while momentum continues | R41, R45, R46, R48, R49, R51 |
| scroll settle | FE/Pierre | FE -> comm worker settled viewport fact; later comm worker -> FE affected slice updates; main -> Pierre worker through Pierre API only | settle frame keeps existing DOM; HELD slices apply by rank after settle inside frame budget | R41, R45, R46, R48, R49, R51 |
| hover | user/FE | 0 before hover paint; later FE -> comm worker hover fact if it changes demand | frame-1 paints local hover/focus chrome only; content demand is speculative and cannot block hover | R41, R42, R45, R49 |
| expand/collapse | user/FE | 0 before toggle paint; later FE -> comm worker expanded/collapsed fact | frame-1 paints local tree shape and placeholders from slices; comm worker repairs invalid ids or supplies content deltas later | R41, R42, R45, R46, R49 |
| hunk expansion | user/FE -> Pierre `setHunkExpansion` | Pierre missing-window event -> main typed desired-window fact -> comm continuation -> `submitWindow` -> atomic Pierre expansion/disposition | affordance paints locally; expansion content appears atomically with stable anchor, never blank filler | R42, R46, R57, R61, R63 |
| surface switch | user/FE app shell | 0 before shell paint; later FE -> comm worker `activeSurfaceUiIntent` with UI revision | frame-1 paints retained local shell; worker accepts `activeSurface`, demotes inactive foreground, and repairs later | R41, R42, R45, R49 |
| tab/worktree switch | user/FE app shell | 0 before shell paint; later FE -> comm worker selected context fact and comm worker -> Swift product-stream subscribe/reopen if needed | frame-1 paints retained local shell or honest loading; no visible old-worktree content after identity change | R41, R42, R45, R48, R49 |
| server push/fact | Swift | Swift -> comm worker streamed product response; comm worker -> FE affected slices only | FE paints only after comm worker validates stream/epoch/sequence and publishes O(delta) slice patches | R42, R45, R48, R49, R50 |
| content-ready | Swift/comm worker executor | Swift -> comm worker streamed content response; comm worker -> FE paint-ready slice | no direct paint from response; comm worker validates current epoch and FE applies rank-first within R46 | R42, R44, R46, R48, R49, R52 |
| Review continuation window | FE/Pierre viewport | FE -> comm desired line/window fact; comm -> Swift content as needed; comm -> FE bounded window; FE -> comm disposition | existing DOM scrolls immediately; later real window applies without prefix replay/blank filler and demand remains until painted | R42, R44, R46, R57, R61 |
| generation rotation | Swift source plus comm-worker epoch authority | Swift -> comm worker source fact; comm worker atomic epoch reset; comm worker -> FE reset slices | one paint observes either old epoch before reset or new epoch after reset; never half-old/half-new | R37, R42, R44, R45, R48, R49 |
| fetch failure | comm-worker executor/Swift content path | Swift -> comm worker failure or comm-worker local fetch failure; comm worker -> FE availability/health slice | selected identity paints explicit retry/unavailable/error state; FE never starts its own retry | R41, R42, R44, R48, R49 |
| reconnect | comm-worker transport | comm worker -> Swift product-stream reopen/subscriptions; Swift -> comm worker streamed resync; comm worker -> FE health/slice repairs | FE keeps local slices with explicit health/loading; stale incoming results cannot mutate active UI | R42, R44, R45, R48, R49 |
| telemetry batch | telemetry worker | main/comm compact samples -> telemetry worker; telemetry worker -> Swift telemetry POST | no user-visible paint; no product await/flush; required loss or gap fails proof | R41, R43, R48, R49, R62 |
| startup warm-up | FE activation/comm worker | FE -> comm worker warm-up fact; comm worker may prewarm cache/compute and Swift subscriptions | initial shell paints from retained local slices or honest loading; warm-up cannot block first paint | R41, R42, R44, R48, R49 |

### Normative Sequences

Click, cache-hit:

```text
User
  │
  ▼
FE local click handler
  │  writes selected identity + reads fresh paint-ready cache
  │  boundary crossings before readable content: 0
  ▼
frame-1 paint
  │  selected chrome + readable selected content
  │
  ├─► comm worker: mandatory selection/UI-revision fact after paint
  │
  ◄─ `selectionAccepted` + reused painted residency, or repair if stale
```

Click, cold:

```text
User
  │
  ▼
FE local click handler
  │  writes selected identity
  │  boundary crossings before frame-1: 0
  ▼
frame-1 paint
  │  selected chrome + honest loading/availability for selected identity
  │
  ├─► comm worker: selected/content-demand fact
  │      validates current workerDerivationEpoch and ranks selected first
  │
  ├──── comm worker ────► Swift: product fetch/subscribe if cache miss
  │                       Swift ────► comm worker: content or availability
  │
  ◄─ comm worker: selected paint-ready slice
  │
  ▼
FE apply pump
     applies selected unit first within R46 time/unit budget
  │
  ├─ rejected/superseded ─► comm worker re-derives current membership
  │
  └─ applied then post-update paint check
       └─► comm worker: painted disposition
             retires matching selected fulfillment only
```

Scroll momentum and settle:

```text
User gesture
  │
  ▼
Pierre scrolls existing DOM
  │  no protocol wait, no app-side scrollTop writer
  │
  ├─► rAF: FE ─► comm worker viewport fact, at most one per frame
  │
  ◄─ comm-worker slice updates that affect moving viewport
  │      FE marks affected updates HELD while momentum continues
  │
  ▼
settle detected by Pierre/FE
  │
  ├─► comm worker settled viewport fact
  │
  ▼
FE apply pump
     releases HELD slices by rank inside R46 budget
```

Server facts, content-ready, fetch failures, and reconnect:

```text
Swift subscription/content plane
  │
  ├─► comm worker: streamed push/fact/content/failure/reconnect response
  │
  ▼
comm worker
  │  sole authority for streamId, workerDerivationEpoch, sequence, staleness
  │  validates freshness before any FE publication
  │
  ├─ stale: drop/count/repair or reopen, no FE content mutation
  ├─ failure: publish explicit availability/health slice
  └─ current: patch only affected slices, O(delta)
       │
       └─► FE slice store
             next render observes local slices only
```

Generation rotation:

```text
Swift accepts sourceGeneration change
  │
  └─► comm-worker source fact
        │
        ▼
      SurfaceSourceEpochReset for that surface only
        │  mint workerDerivationEpoch; other surface/worker instance survive
        ├─► main raises surface epoch floor, cancels old work, acks barrier
        └─► worker clears/rebuilds that surface truth, then publishes
              paint is all-old before barrier or all-new after acknowledgement
```

Telemetry:

```text
main compact sample port ----\
                              -> telemetry worker
comm compact sample port ----/     validate + credit + byte cap
                                   shed/account + encode + sequence
                                   bounded retry/outbox
                                            │
                                            └─► Swift telemetry endpoint

product paths never flush, await, batch, encode, retry, or fetch telemetry
```

## Migration Constraints

What stays:

- `WKURLSchemeHandler` as the shared POST product-stream adapter;
- `BridgeContentDemandAdmission` as a Swift/native serving-side pacing valve;
- native metadata plane: interest stream, metadata lane scheduler, manifest
  index, provider/source authority;
- R32-R40 content-demand contract and Constants Annex;
- one pane-owned comm-worker product session with surface-scoped contexts;
- optional separate pane telemetry worker and telemetry-only endpoint;
- main-thread DOM materialization, bounded by R46.

What dies:

- multiple feature-owned comm-worker instances and bootstraps seeded with
  main-owned Review/File source packages;
- all main-owned Review/File product intake, buffering, sequencing,
  materialization, readiness, reopen/retry, and frame-protocol decisions;
- native product `callJavaScript`/DOM-event push and every page fetch/relay;
- telemetry buffers, batching, JSON encoding, retry/outbox, sinks, or scheme
  fetch on main or the comm worker;
- the `WKScriptMessage` / `__bridge_command` RPC plane after page-load
  bootstrap, including content-world command listeners, nonce command
  dispatch, `RPCMessageHandler`, `RPCRouter`, and script-message ingress;
- FE protocol state: generations, sequences, stream identity, staleness,
  cache-membership truth, retry state, and demand membership truth;
- React/main-thread Zustand stores for Bridge viewer data in converted Review
  and File View surfaces;
- main-thread store or query cache as canonical Bridge data/cache/demand owner;
- cross-boundary store mirroring, `store.getState()` payloads, or query-cache
  payloads as protocol;
- async cache libraries as worker RPC lifecycle owner or high-frequency row/content
  patch stream;
- root-snapshot render coupling for interaction paths;
- package-shaped sync work inside click, selection, scroll, or paint handlers;
- main-side ready-to-loading semantic gates and uncancelled stale placeholder
  work;
- Review first-window-as-complete behavior and File View payload-line padding;
- Pierre native-content fetch capability and receipt-only couriers;
- handler-splitting as a claim of WebKit IPC isolation.
- feature-specific product fetch helpers, resource URLs/GETs, route constants,
  and recursive JSON payload bags outside `BridgeProductTransport`;

Compile-enforced deletion sets are required per cutover unit:

| Cutover unit | Delete or make unbuildable | Keep only | Enforcement floor |
| --- | --- | --- | --- |
| pane comm-worker topology | feature worker factories; main-seeded product bootstrap/updates | one pane worker/session and surface clients | type/import lint + real browser/native identity |
| File content protocol | FE body/frame protocol/cache/retry/padding | display slices, canonical prefix, worker/native owners | schema/state tests + static scan + native bytes |
| Review content protocol | package body loading, root selection semantics, prefetch/cache truth, prefix completion | worker continuation plus display slices | state tests + full-window browser/native oracle |
| React Bridge data stores | main Review/File Zustand imports/mutations | RPC lifecycle, render snapshot, worker Zustand | import/architecture lint + subscription proof |
| telemetry transport | page/pre-React/comm pipeline/fetch/flush/retry | producer ports, telemetry worker/endpoint | disjoint-schema scan + loss/failure/native tests |
| browser/native product carrier | script-message RPC, product `callJavaScript`/DOM/page relays/router, feature fetch/resource GET | bootstrap/assets/typed controls and worker-only call/metadata/content POST transport | structural scan + packaged trace |
| render fulfillment | semantic ready rejection, silent drops, stale placeholders | structural apply, semantic identity, R63 dispositions/barrier | state-machine tests + repeated live clicks |
| Pierre courier | receipt-only/direct payload/main reconstruction/private traffic | one released transferred `submitWindow` courier | public types + detachment/memory/anchor proof |
| demand membership | staging caps/eviction/parked retry | reconciler membership and executor pacing | compile deletion + hostile demand proof |

No old and new path may remain live for the same viewer/protocol surface. Any
surface not converted by a cutover unit is explicitly outside R41-R66 proof and
cannot satisfy the local-first comm-worker contract. Compatibility shims,
feature flags, or dual readers for one converted surface are contract
violations unless the old path is compile-dead in that unit.

Cutover readiness rule:

- A typed worker shell, shared DTO module, lifecycle helper, or snapshot helper is
  not a converted surface by itself. It is scaffolding until the old owner for
  that viewer/protocol surface is compile-dead.
- Dev-server, Vitest Browser, Playwright, or Chrome proof may close FE-seam
  claims only: local render slices, hostile fake-worker behavior, DOM apply, and
  browser interaction timing. It cannot close WebKit `agentstudio://` scheme
  fetch, streamed-response push, native admission, or Swift/source authority.
- Native debug-app proof remains mandatory for the JavaScript <-> Swift scheme
  boundary. If source scans still find extra comm-worker creation sites, a live
  main/native product carrier, main-thread Bridge data Zustand owner, FE
  retry/demand/cache owner, main/comm telemetry pipeline, package-first body
  loader, or Pierre native fetch for a converted surface, that surface is
  unconverted and no R41-R66 performance or ownership claim may be made for it.

## Non-Goals

- No Pierre fork.
- No private Pierre worker protocol, proxy worker, local-path dependency, or
  `patch-package`; a required upstream change lands as a general public release.
- No claim that DOM materialization moves off the main thread.
- No `SharedArrayBuffer` requirement.
- No merge of the native metadata plane into the comm worker.
- No new browser-side diff/repo authority.
- No server lifetime surfaced to FE as user-visible protocol state.
- No File View continuation beyond 2 MiB / 10,000 actual payload lines.
- No shared cross-pane comm or telemetry worker.
- No implementation phase plan in this document.

## Open Decisions

OD-LF1. Worker topology. CLOSED by R60 at the ownership level.

The comm worker is the single protocol/cache/demand authority and scheduler. It
may execute lightweight compute as local `WorkerContentPreparationPump` slices
or coordinate a compute/Pierre pool for heavier work. The invariant is
unchanged: FE sees one local-first worker contract, and no package-shaped
parse/window/diff/highlight preparation may run as one synchronous comm-worker
task.

OD-LF2. FE render snapshot primitive. CLOSED by R56.

The FE primitive is `BridgeMainRenderSnapshotStore`: a non-Zustand store exposed
to React through `useSyncExternalStore`, written only by local intent helpers and
`BridgeWorkerPatchApplier`.

OD-LF3. WebKit run-loop starvation proof.

The research lane marks `kCFRunLoopDefaultMode` delivery and gesture starvation
as plausible and source-grounded, but still empirical-confirm-required for this
app. Native proof must measure command/telemetry/content delivery under
gesture tracking before any final run-loop starvation claim is closed.

OD-LF4. Durable single-writer content cache.

The comm worker's single-writer ownership of protocol/cache truth enables a
later separate PR for a persistent content cache, likely OPFS or IndexedDB with
content-addressed keys and generation-epoch invalidation. This increment does
not need a separate coordination design for durable cache ownership, and durable
cache implementation remains out of scope here.

OD-LF5. Pierre transferable/window boundary. CLOSED by R52/R53/R57.

A released, pinned public byte-backed window API is mandatory before cutover.
There is no final string-clone corridor or whole-item compatibility path.

OD-LF6. Telemetry worker topology. CLOSED by R43/R49.

Each pane creates no telemetry worker when disabled and at most one isolated
telemetry worker when enabled. Main and comm are compact-sample producers only;
no fallback pipeline exists on either interactive loop.
