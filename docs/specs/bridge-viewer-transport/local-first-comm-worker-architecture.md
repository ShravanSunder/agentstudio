# Local-First Comm Worker Architecture

Date: 2026-07-04
Status: normative increment after
[performance-demand-lanes.md](performance-demand-lanes.md) R32-R40 and its
Constants Annex
Parent: [performance-demand-lanes.md](performance-demand-lanes.md)

This file defines the next BridgeViewer transport boundary. It does not define
implementation order. The boundary is a hard cutover contract: one converted
viewer/protocol surface has one path, one ownership model, and one proof set.

R32-R40 say the browser owns content-demand initiative. This increment splits
that browser ownership: the FE render surface owns only local render slices;
the comm worker owns protocol truth, demand truth, cache truth, retries,
telemetry batching, and Swift synchronization.

## Evidence Anchors

- Phase-2 causal map: click stall, root-snapshot floor, synchronous File View
  apply/prune work, backoff-less re-demand, and dormant R32 production wiring
  (`tmp/debug-workflows/2026-07-04-agent-studio-luna338-scroll-placeholder-survivor/debug-investigation.md:156`).
- WebKit transport facts from the same research lane: named script handlers
  share one IPC queue; handler-splitting does not isolate traffic; delivery is
  `kCFRunLoopDefaultMode`-bound and gesture starvation remains empirical-confirm
  required; workers can fetch `WKURLSchemeHandler` schemes; telemetry belongs
  on a dedicated scheme endpoint
  (`tmp/debug-workflows/2026-07-04-agent-studio-luna338-scroll-placeholder-survivor/debug-investigation.md:193`).
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
  fetch is REQUIRED before cutover. If that proof fails, the plan must either
  adopt a page-fetch-and-transfer fallback that preserves R44 worker ownership
  of bytes/cache/retry truth, or stop and revise R44 before implementation.
- A live `MessagePort` is not entangled with native for ordinary WKWebView page
  content. `MessageChannel` is page-to-worker only for this design.
- `SharedArrayBuffer` requires cross-origin isolation headers on every scheme
  response. Safari lacks the `credentialless` shortcut. This design must not
  require SAB; `fetch()`, `ReadableStream`, and transferables are sufficient.

## Boundary / Separability Map

```text
FE render surface
  owns: local render slices, optimistic interaction state, DOM apply budget
  exposes: local-first mutations, viewport/selection facts, paint-ready reads
  forbidden: protocol state, generation/sequence/staleness ownership,
             awaiting worker/native during paint

LOCAL-FIRST message boundary
  FE -> worker: facts and intents, never synchronous paint dependencies
  worker -> FE: transferable paint-ready structures and slice updates

comm worker
  owns: protocol truth, cache truth, content-demand reconciler, R37 epochs,
        streamId, workerDerivationEpoch, sequence, staleness,
        retries/backoff/pacing, telemetry batching, Swift reconnect resync
  exposes: local slice updates to FE; client requests/subscriptions to Swift
  forbidden: relying on FE for protocol truth or on Swift liveness for paint

CLIENT/SERVER transport boundary
  worker -> Swift: async request/response, subscription open/close,
                   content fetches, telemetry POST batches
  Swift -> worker: subscription pushes, descriptor/content responses,
                   reset/unhealthy facts

Swift server
  owns: metadata plane, sourceGeneration/metadata lineage, content scheme
        handler, BridgeContentDemandAdmission, provider/source authority
  exposes: disposable service endpoint; reconnect rebuilds worker truth
  forbidden: FE-observable server lifetime or UI paint coupling
```

## Truth Ownership Tables

Every datum has exactly one truth owner.

Identity lineage is split into two planes:

| Value | Mint | Validate | Reset | Observe |
| --- | --- | --- | --- | --- |
| `sourceGeneration` and metadata lineage | Swift/native provider source authority | Swift rejects stale source requests; worker treats it as source fact, never as worker cache epoch authority | Swift rotates on accepted source change, resets metadata stream/gates, and revokes stale source leases | comm worker subscriptions, server seam, native proof |
| `workerDerivationEpoch` | comm worker when it accepts a new current sourceGeneration/stream tuple | worker stamps demand plans, cache admission, fetches, and slice publications; Swift may echo/validate only as request freshness metadata | worker atomically clears derived demand membership, in-flight maps, paint-ready cache, retry state, and source-bound slice facts | FE diagnostics, worker tests, Victoria proof |

The metadata plane remains native-owned. The worker epoch is a derived browser
cache/demand epoch minted from accepted source changes; it is not a replacement
for native metadata lineage.

Extended truth ownership:

| Datum | Owner | Readers | Write path | Repair path | Inactive-mode behavior |
| --- | --- | --- | --- | --- | --- |
| `streamId` | comm worker | FE diagnostics, Swift validation | worker opens/reopens source session | worker/server resync on gap or unhealthy | retained, never FE-writable |
| `sourceGeneration` / metadata lineage | Swift/native | comm worker, server tests | native accepted-source transition | native reset/reopen or unhealthy | native may continue metadata rules; FE sees no protocol state |
| `workerDerivationEpoch` | comm worker | FE diagnostics, Swift freshness echo, worker tests | worker accepts sourceGeneration/stream tuple | epoch reset clears derived worker truth | retained per mounted worker; inactive foreground work demotes/aborts |
| `sequence` | comm worker | Swift server, worker tests | worker request/subscription order | worker/server resync closes gaps | retained, no inactive FE mutation |
| staleness classification | comm worker | FE health/render slices | worker validates source, stream, epoch, and sequence | reset-required -> reopen or unhealthy | inactive stale results cannot mutate active UI |
| content-demand membership | comm worker reconciler | worker executor/cache | worker reconciles selected/viewport/hover/cache facts | re-derive every fact change; no parked membership | inactive selected becomes demoted/aborted, not foreground |
| content bytes / byte cache | comm worker | worker parse/window/diff/highlight | worker `fetch()` from content scheme | retry/backoff or unavailable slice | retained by retention policy; not active foreground |
| paint-ready rows/runs/extents | comm worker produces; FE slice store owns current render copy | components | transferable worker slice update | stale slice replacement or explicit unavailable/error slice | inactive copies may persist but cannot overwrite active mode |
| `selected` row/file/item | FE local slice | comm worker as fact input | synchronous click/keyboard local mutation plus intent | worker repair may mark unavailable/stale, never block paint | each mounted viewer retains its local selection memory |
| `activeMode` | FE app shell | comm worker as demand fact | mode switch updates local shell slice | worker demotes/aborts inactive foreground; shell can re-emit fact | inactive mode retains memory but has no foreground authority |
| `viewport` / rendered range | FE virtualizer slice | comm worker reconciler | rAF/idle-coalesced viewport publication | next viewport fact supersedes; worker re-derives | inactive viewport may be retained but does not create foreground demand |
| `expanded` / collapsed rows | FE local slice | comm worker for visible derivation | user toggle writes local UI fact | source reset drops invalid row ids; worker publishes availability repairs | retained per viewer unless source reset invalidates ids |
| viewed marks | Swift/native viewed-file command authority | FE render slices, comm worker ack tracking | FE sends write intent through worker to Swift | Swift ack or retry/unhealthy; worker emits ack health slice | inactive mode may queue intent only through worker, never direct native write |
| diff status | Swift/native push plane | FE render slices, comm worker health | native status push through worker | failed push clears dedupe and re-emits or marks unhealthy | retained as last known health; stale status marked explicitly |
| acks | comm worker | FE health/render slices, Swift request handlers | worker correlates requests/intents to Swift responses | timeout/backoff/retry or unhealthy | inactive acks may settle but cannot update active selection/content |
| connectionHealth | comm worker | FE health chrome, Swift diagnostics | worker observes handshake, fetch, push, and telemetry failures | reconnect reset, source reopen, or unhealthy slice | inactive mode shows retained health only; no foreground retries |
| write intents | FE creates; comm worker owns queue/dedupe | Swift command handlers, FE ack slices | local intent -> worker queue -> Swift command | worker retries/backoff or fails visibly; no direct FE->native bypass | inactive writes are demoted/queued by policy or rejected visibly |
| telemetry queue | comm worker | Swift telemetry endpoint | idle batch to dedicated scheme endpoint | drop counters and proof failure on required loss | inactive samples still carry viewer/mode labels |
| metadata plane | Swift/native | comm worker subscriptions | native interest stream and provider scheduler | native reset/reopen/unhealthy | untouched by this spec |

## Requirements

### R41. Paint paths do not await across boundaries.

Nothing in a paint path awaits the comm worker or Swift. FE render reads are
synchronous local slice reads. A click writes the local selected slice
optimistically and paints in the same frame; worker and Swift confirmation may
repair later, but must not gate the click frame.

Contract violations:

- `flushSync` spanning package-shaped React/Pierre work while RPC delivery is
  in flight; the verified click stall was `flushSync` after RPC post blocking
  WebKit delivery
  (`tmp/debug-workflows/2026-07-04-agent-studio-luna338-scroll-placeholder-survivor/debug-investigation.md:163`).
- Paint-follows-push coupling: a visible FE paint that depends on the next
  Swift push, worker response, or handler delivery.
- Telemetry force-flush on an interactive command path. Current RPC dispatch
  records telemetry and force-flushes on send
  (`BridgeWeb/src/bridge/bridge-rpc-client.ts:99`,
  `BridgeWeb/src/bridge/bridge-rpc-client.ts:116`), and the telemetry sink sends
  through the same RPC client
  (`BridgeWeb/src/bridge/bridge-telemetry-event-sink.ts:14`).

R41 extends R35/R39: selected work still ranks first, but selected paint cannot
wait for the rank machinery to round-trip.

Cold-paint outcomes are part of R41:

| State at click | Required first paint | Forbidden proof claim |
| --- | --- | --- |
| paint-ready cache hit for the selected identity | readable selected content window, with stale-safe generation/epoch match | treating a later worker confirmation as the first paint |
| cache miss for normal content | selected identity, selection chrome, and protocol-free loading/availability placeholder keyed to the new selection | claiming selection highlight alone satisfies click-to-first-visible-content |
| stale cache hit for a prior identity/epoch | no old content; render the new selected identity plus loading/stale placeholder | painting stale readable content, even briefly |
| oversized, binary, unavailable, or persistent failure | explicit unavailable/error state keyed to the selected identity | indefinite blank panel, old content, or success percentile sample |

The first-visible-content proof requires readable selected content or an
explicit selected unavailable/error/loading state from this table. Selection
highlight alone is only action feedback; it does not satisfy the
click-to-first-visible-content budget.

### R42. Every datum has exactly one truth owner.

The worker is the single authority for protocol and cache truth: stream
identity, R37 `workerDerivationEpoch`, sequence, staleness, cache membership,
content-demand membership, retry/backoff, and server reconnect state.

FE is the single authority for render slices: selected row/file/item,
expanded/collapsed local UI facts, local hover/focus facts, and the current
paint-ready slice copy. FE components hold zero protocol state.

Swift remains the authority for provider/source metadata and content service
truth. Swift server lifetime is disposable from FE's perspective; reconnect
resyncs the worker, and FE observes only worker-produced render/health slices.

This bans the Phase-2 defect class where R32 existed but demand membership still
had multiple authorities
(`tmp/debug-workflows/2026-07-04-agent-studio-luna338-scroll-placeholder-survivor/debug-investigation.md:187`)
and the cold-review staleness class where Review and Worktree/File carried
different generation models
(`docs/wip/2026-07-04-cold-architecture-review-bridge-demand-system.md:89`).

R42 is complete only when the extended truth ownership table above is
implemented as code ownership. Adding a second writer for any row is a
contract violation, even if both writers currently agree in tests.

### R43. Telemetry uses a dedicated transport lane.

Telemetry must use a dedicated `WKURLSchemeHandler` POST endpoint with its own
transport lane. It must not use interactive RPC, named script-message handler
traffic, or any queue that can run ahead of interactive commands.

Browser/worker telemetry obligations:

- idle-time batching, equivalent to a `requestIdleCallback` class of policy;
- browser-side encoded-byte cap, not sample-count-only caps;
- drop-oldest shedding when the cap is exceeded;
- no forced flush by interactive commands;
- no telemetry batch queued ahead of command, content, or paint-critical work.
- lossless aggregate counters for every shed sample, keyed by event, lane,
  result, and drop reason;
- monotonic batch sequence numbers per telemetry stream.

Native telemetry obligations:

- single-pass decode;
- admission and byte/count validation before expensive work;
- rejection/drop facts for invalid or over-budget batches;
- no raw paths, raw URLs, payload text, prompts, tokens, or raw errors.

R43 bans the verified shared-channel compounding path
(`tmp/debug-workflows/2026-07-04-agent-studio-luna338-scroll-placeholder-survivor/debug-investigation.md:166`)
and applies the Constants Annex rule that every cap protects exactly one class
(`docs/specs/bridge-viewer-transport/performance-demand-lanes.md:315`).

Telemetry proof integrity:

| Condition | Proof rule |
| --- | --- |
| required event class shed during a proof run | proof fails; the run may be retained only as exploratory evidence |
| batch sequence gap | proof fails unless paired with a matching lossless drop counter and an accepted exploratory label |
| slow click, reject, abort, stale, or unavailable sample shed | proof fails; tail and failure samples are required evidence |
| optional/debug event shed | allowed only with aggregate counters and explicit lossy-run annotation |

Percentiles can satisfy R41-R48 only from non-lossy required event streams.
Lossy telemetry runs are debugging aids, not performance proof.

### R44. Content bytes stream to the worker, not the main thread.

Content bytes are fetched by the comm worker from the content scheme. The main
thread must not receive raw file text, raw diff text, full package bodies, or
body-byte cache entries. FE receives only paint-ready structures: rows, runs,
extents, summary facts, availability facts, and DOM-apply units.

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
| success, current epoch | bytes enter worker byte cache; parse/window/highlight may continue | paint-ready or availability slice | membership remains until UI commit if still selected/visible |
| abort from supersession or demotion | in-flight slot frees; no cache write unless completion was already fresh | no error for speculative/nearby; selected may show loading for new identity | reconciler re-derives from current facts |
| transient failure | executor records delivery-failure fact and bounded backoff | health/loading slice with retry state, no FE-owned retry | worker re-demands from membership after backoff |
| persistent failure or over-budget | worker records terminal availability for current epoch | explicit unavailable/error slice keyed to selected/visible identity | membership remains worker-owned; retry only after source/fact reset policy |
| stale sourceGeneration or workerDerivationEpoch | discard result, count stale drop | no stale content; health slice if user-visible | epoch reset/reconnect drives fresh demand |
| reconnect reset | clear source-bound in-flight/cache memberships as required by epoch reset | connection health/loading slices | worker rebuilds membership from latest FE facts and Swift source |

FE receives render and health slices only. Fetch membership, backoff, retry,
and re-demand are worker facts; FE must not park or restart content demand.

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

R45 bans the verified flat 560ms click floor from root-snapshot world-state
rendering
(`tmp/debug-workflows/2026-07-04-agent-studio-luna338-scroll-placeholder-survivor/debug-investigation.md:173`).

### R46. Main-thread apply is a frame-budgeted pump.

DOM materialization remains on the main thread. That stage is legitimate only
as a frame-budgeted apply pump:

- rank-ordered, with selected/current target first;
- bounded per frame by AppPolicies-backed time and unit-count caps;
- input-yielding between chunks;
- resumable without redoing completed units;
- stale-safe if worker or Swift advances generation while units are pending.
- no-starvation bounded for visible non-selected apply work while selected
  churn continues.

The production constants must live in `AppPolicies` or the BridgeWeb policy
module that mirrors `AppPolicies`; tests and verifiers assert observed behavior
against those constants, not duplicated literals. Required policy classes:

| Budget | Class | Proof |
| --- | --- | --- |
| selected apply time/unit cap | execution | selected latency histogram and per-frame applied-unit counter |
| visible non-selected apply time/unit cap | execution | visible apply progress counter increases under selected churn |
| stale-drop scan cap | pacing | pending stale units are cleared without monopolizing a frame |
| no-starvation bound | fairness | at least one visible non-selected apply batch completes within N selected batches, where N is policy-owned |

Applying all ready entries in one microtask, one sync React update, or one
package-shaped Pierre operation is a contract violation. R46 is the main-thread
counterpart to R39: rank survives worker completion and survives DOM apply.

R46 bans the Phase-2 severe-freeze class where synchronous frame/projection work
and apply work occupied the main thread
(`tmp/debug-workflows/2026-07-04-agent-studio-luna338-scroll-placeholder-survivor/debug-investigation.md:177`).

### R47. File View projection and pruning obey the same frame contract.

File View is not exempt from R41-R46. Frame application, projection, replay,
open-file reconciliation, and DOM apply must be chunked and yielding when their
input can scale with frame/package size.

The O(N^2) empty-directory prune is a named defect. The current implementation
loops every directory over every row
(`BridgeWeb/src/file-viewer/bridge-file-viewer-state.ts:511`,
`BridgeWeb/src/file-viewer/bridge-file-viewer-state.ts:521`) and was called out
as a severe-freeze co-cause
(`tmp/debug-workflows/2026-07-04-agent-studio-luna338-scroll-placeholder-survivor/debug-investigation.md:178`).

File View frame intake is likewise covered by the apply-pump contract because
it applies incoming frames from the subscription path synchronously today
(`BridgeWeb/src/file-viewer/use-bridge-file-viewer-frame-intake-controller.ts:70`).

### R48. Proof seams match the two boundaries.

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
  reconnects, oversized telemetry, slow content, persistent fetch failures,
  and backpressure;
- proves stream/workerDerivationEpoch/sequence/staleness authority, R32-R40
  membership, R34 backoff/pacing, R37 epoch reset, R39 rank into worker pools,
  R43 telemetry batching/shedding, R44 content streaming, and reconnect resync;
- cannot prove FE paint timing, DOM materialization, WebKit run-loop mode, or
  Swift provider correctness.

Server seam:

- tests Swift against recorded worker traffic;
- proves metadata plane stability, content scheme serving,
  `BridgeContentDemandAdmission`, telemetry POST admission, source authority,
  and reset/unhealthy responses;
- cannot prove FE slice correctness, worker cache policy, worker backoff,
  WebKit delivery ordering, or user-perceived paint.

Live gates:

- native WKWebView proof remains required for WebKit delivery, worker
  custom-scheme fetch, run-loop starvation, and end-to-end click/scroll budgets;
- worker custom-scheme fetch must pass native WKWebView proof before the R44
  cutover. If it fails, the blocking decision is page-fetch-and-transfer
  fallback versus R44 redesign; implementation must not assume worker fetch.
- Victoria-backed proof remains required for performance samples and telemetry
  admission;
- existing R32-R40 proof seams remain required and are not replaced
  (`docs/specs/bridge-viewer-transport/performance-demand-lanes.md:277`).

## Action And Event Sequence Contracts

Every user action and system event must preserve the local-first rule: FE may
paint only from local render slices, and worker/native traffic may repair,
subscribe, fetch, or append facts after that paint. Every arrow crossing a
boundary is fire-and-forget or a subscription; no arrow may turn around
synchronously into a paint.

Boundary notation:

```text
FE -> worker     LOCAL-FIRST message boundary crossing
worker -> Swift  CLIENT/SERVER transport boundary crossing
Swift -> worker  server push/subscription/content response crossing
worker -> FE     worker slice publication crossing
```

### Action/Event Inventory

| Trigger | Initiating actor | Boundary crossings | Paint rule | Governing requirements |
| --- | --- | --- | --- | --- |
| click cache-hit | user/FE | 0 before content paint; later FE -> worker intent/fact if needed | frame-1 paints readable selected content from fresh local paint-ready cache | R41, R42, R45, R48 |
| click cold | user/FE | 0 before frame-1; later FE -> worker demand fact, worker -> Swift fetch/subscription, Swift -> worker content, worker -> FE slice | frame-1 paints selected identity plus honest loading/availability; selected content applies first within R46 budget when ready | R41, R44, R45, R46, R48 |
| scroll momentum | user/FE/Pierre | one rAF-coalesced FE -> worker viewport fact per frame while moving | Pierre scrolls existing DOM immediately; incoming slices that affect viewport are HELD while momentum continues | R41, R45, R46, R48 |
| scroll settle | FE/Pierre | FE -> worker settled viewport fact; later worker -> FE affected slice updates | settle frame keeps existing DOM; HELD slices apply by rank after settle inside frame budget | R41, R45, R46, R48 |
| hover | user/FE | 0 before hover paint; later FE -> worker hover fact if it changes demand | frame-1 paints local hover/focus chrome only; content demand is speculative and cannot block hover | R41, R42, R45 |
| expand/collapse | user/FE | 0 before toggle paint; later FE -> worker expanded/collapsed fact | frame-1 paints local tree shape and placeholders from slices; worker repairs invalid ids or supplies content deltas later | R41, R42, R45, R46 |
| mode switch | user/FE app shell | 0 before shell paint; later FE -> worker activeMode fact | frame-1 paints retained local mode shell/slices; worker demotes inactive foreground work and repairs availability later | R41, R42, R45 |
| tab/worktree switch | user/FE app shell | 0 before shell paint; later FE -> worker selected context fact and worker -> Swift subscribe/reopen if needed | frame-1 paints retained local shell or honest loading; no visible old-worktree content after identity change | R41, R42, R45, R48 |
| server push/fact | Swift | Swift -> worker subscription push; worker -> FE affected slices only | FE paints only after worker validates stream/epoch/sequence and publishes O(delta) slice patches | R42, R45, R48 |
| content-ready | Swift/worker executor | Swift -> worker content response; worker -> FE paint-ready slice | no direct paint from response; worker validates current epoch and FE applies rank-first within R46 | R42, R44, R46, R48 |
| generation rotation | Swift source plus worker epoch authority | Swift -> worker source fact; worker atomic epoch reset; worker -> FE reset slices | one paint observes either old epoch before reset or new epoch after reset; never half-old/half-new | R37, R42, R44, R45, R48 |
| fetch failure | worker executor/Swift content path | Swift -> worker failure or worker local fetch failure; worker -> FE availability/health slice | selected identity paints explicit retry/unavailable/error state; FE never starts its own retry | R41, R42, R44, R48 |
| reconnect | worker transport | worker -> Swift reopen/subscriptions; Swift -> worker resync; worker -> FE health/slice repairs | FE keeps local slices with explicit health/loading; stale incoming results cannot mutate active UI | R42, R44, R45, R48 |
| telemetry flush | comm worker | worker -> Swift dedicated scheme POST only | no user-visible paint; flush runs idle, byte-capped, drop-oldest with lossless counters | R41, R43, R48 |
| startup warm-up | FE activation/worker | FE -> worker warm-up fact; worker may prewarm cache/compute and Swift subscriptions | initial shell paints from retained local slices or honest loading; warm-up cannot block first paint | R41, R42, R44, R48 |

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
  ├─► worker (optional fact/intent after paint)
  │
  ◄─ worker repair slice only if epoch/staleness later disagrees
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
  ├─► worker: selected/content-demand fact
  │      validates current workerDerivationEpoch and ranks selected first
  │
  ├──── worker ────► Swift: fetch/subscribe if cache miss
  │                  Swift ────► worker: content or availability
  │
  ◄─ worker: selected paint-ready slice
  │
  ▼
FE apply pump
     applies selected unit first within R46 time/unit budget
```

Scroll momentum and settle:

```text
User gesture
  │
  ▼
Pierre scrolls existing DOM
  │  no protocol wait, no app-side scrollTop writer
  │
  ├─► rAF: FE ─► worker viewport fact, at most one per frame
  │
  ◄─ worker slice updates that affect moving viewport
  │      FE marks affected updates HELD while momentum continues
  │
  ▼
settle detected by Pierre/FE
  │
  ├─► worker settled viewport fact
  │
  ▼
FE apply pump
     releases HELD slices by rank inside R46 budget
```

Server facts, content-ready, fetch failures, and reconnect:

```text
Swift subscription/content plane
  │
  ├─► worker: push/fact/content/failure/reconnect response
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
  └─► worker source fact
        │
        ▼
      worker atomic epoch reset
        │  mint new workerDerivationEpoch
        │  clear derived demand, in-flight maps, cache memberships,
        │  retry state, stale source-bound slices, and pending applies
        │
        └─► FE reset/availability slices
              paint is all-old before reset or all-new after reset;
              half-old/half-new paint is forbidden
```

Telemetry:

```text
FE/worker instrumentation samples
  │
  ▼
comm worker telemetry buffer
  │  encoded-byte cap, drop-oldest shedding,
  │  lossless counters by event/lane/result/drop reason
  │
  ├─ interactive command path: never flushes telemetry
  │
  └─ idle flush
       │
       └─► Swift dedicated telemetry scheme endpoint
             not the interactive channel, never ahead of commands
```

## Migration Constraints

What stays:

- `WKURLSchemeHandler` content path;
- `BridgeContentDemandAdmission` as a Swift/native serving-side pacing valve;
- native metadata plane: interest stream, metadata lane scheduler, manifest
  index, provider/source authority;
- R32-R40 content-demand contract and Constants Annex;
- main-thread DOM materialization, bounded by R46.

What dies:

- telemetry on the interactive RPC channel;
- FE protocol state: generations, sequences, stream identity, staleness,
  cache-membership truth, retry state, and demand membership truth;
- root-snapshot render coupling for interaction paths;
- package-shaped sync work inside click, selection, scroll, or paint handlers;
- handler-splitting as a claim of WebKit IPC isolation.

Compile-enforced deletion sets are required per cutover unit:

| Cutover unit | Delete or make unbuildable | Keep only |
| --- | --- | --- |
| File viewer content protocol | FE raw body/frame package intake, FE generation/sequence/staleness caches for content, FE demand retry/parking fields | FE slices, worker protocol client, native metadata plane |
| Review viewer content protocol | package-first review body loading, root-snapshot selection render path, review prefetch pump, FE cache-membership truth | FE slices, worker reconciler/cache, native metadata plane |
| telemetry transport | interactive RPC telemetry send/force-flush path and shared-command queue telemetry | dedicated scheme POST endpoint and worker batching |
| demand membership | legacy staging buffers, membership caps, pending eviction as membership policy, parked retry versions | worker reconciler membership and executor-stage pacing only |

No old and new path may remain live for the same viewer/protocol surface. Any
surface not converted by a cutover unit is explicitly outside R41-R48 proof and
cannot satisfy the local-first comm-worker contract. Compatibility shims,
feature flags, or dual readers for one converted surface are contract
violations unless the old path is compile-dead in that unit.

## Non-Goals

- No Pierre fork.
- No claim that DOM materialization moves off the main thread.
- No `SharedArrayBuffer` requirement.
- No merge of the native metadata plane into the comm worker.
- No new browser-side diff/repo authority.
- No server lifetime surfaced to FE as user-visible protocol state.
- No implementation phase plan in this document.

## Open Decisions

OD-LF1. Worker topology.

One comm worker may own protocol, cache, telemetry, and lightweight compute, or
a comm worker may coordinate a compute pool. The invariant is unchanged: the FE
sees one local-first worker contract, and exactly one worker-side authority owns
protocol truth.

OD-LF2. FE slice-store library.

Zustand slices are the current likely fit because the repo already uses Zustand
and needs scheduler-owned, main-thread-local render slices. Another store
library may be selected only if it preserves synchronous local reads,
fine-grained subscriptions, and no protocol ownership in FE.

React Query is rejected for this boundary because it centers main-thread cache
ownership and async request state, while this design requires worker-owned
protocol/cache truth plus FE-owned render slices.

OD-LF3. WebKit run-loop starvation proof.

The research lane marks `kCFRunLoopDefaultMode` delivery and gesture starvation
as plausible and source-grounded, but still empirical-confirm-required for this
app. Native proof must measure command/telemetry/content delivery under
gesture tracking before any final run-loop starvation claim is closed.
