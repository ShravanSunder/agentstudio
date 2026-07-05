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
  fetch and streamed scheme responses is REQUIRED before cutover. That same gate
  also gates migration-era main-thread scheme-RPC callers because all
  JavaScript-to-Swift communication shares the same network-shaped bridge. If
  worker fetch fails, the plan must either adopt a page-fetch-and-transfer
  fallback that preserves R44 worker ownership of bytes/cache/retry truth, or
  stop and revise R44 before implementation.
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
  FE -> worker: typed RPC facts and intents, never synchronous paint dependencies
  worker -> FE: typed RPC replies/events, transferable paint-ready structures,
                and slice updates

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

Zustand is the comm-worker-local data store for Bridge viewer data. React/main
must not own a Zustand Bridge data store after cutover. React/main uses TanStack
Query for coarse async worker RPC and non-Zustand render-slice hooks for
frame-critical display copies. The synchronization boundary is typed RPC/DTO
messages, not store mirroring: no Zustand snapshot, TanStack Query cache entry,
store action/function, class instance, DOM object, `AbortController`, or other
non-cloneable local state shape may cross the worker boundary.

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

Percentiles can satisfy R41-R59 only from non-lossy required event streams.
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

R46 bans the Phase-2 severe-freeze class where synchronous frame/projection work
and apply work occupied the main thread
(`tmp/debug-workflows/2026-07-04-agent-studio-luna338-scroll-placeholder-survivor/debug-investigation.md:177`).
It also bans the live round-5 regression where unbudgeted pause-release
promotion produced multi-hundred-ms main-thread tasks blocking tree and clicks:
the budget must sit upstream of the pump, not only at DOM apply.

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
  custom-scheme fetch, streamed scheme responses, migration-era main-thread
  scheme-RPC calls, run-loop starvation, and end-to-end click/scroll budgets;
- worker custom-scheme fetch plus streamed responses must pass native WKWebView
  proof before the R44/R49 cutover. If worker fetch fails, the blocking decision
  is page-fetch-and-transfer fallback versus R44 redesign; if streamed responses
  fail, R49's fallback ordering applies. Implementation must not assume worker
  fetch, streaming, or main-thread scheme-RPC migration until the same native
  gate passes.
- Victoria-backed proof remains required for performance samples and telemetry
  admission;
- existing R32-R40 proof seams remain required and are not replaced
  (`docs/specs/bridge-viewer-transport/performance-demand-lanes.md:277`).

## Channel Topology And Typed Contracts

### R49. The topology has exactly three runtime channels.

The local-first worker design has three channels, each with its own contract.
The server worker named here is the comm worker in R41-R59. The custom-scheme
fetch bridge is the single network boundary: a network-shaped bridge where every
JavaScript-to-Swift call after page-load identity bootstrap uses scheme-handler
RPC, regardless of whether the caller is the server worker or a residual
main-thread migration path.

| Channel | Contract | Required payload shape |
| --- | --- | --- |
| main <-> server worker | typed RPC/event protocol over a `MessageChannel` port owned by the page and server worker, using transferables where payloads can avoid clone cost | typed commands down: `select`, `viewport`, `hover`, `markViewed`, and `mode`; typed replies/events and slice patches up; no store snapshots |
| JavaScript <-> Swift | all Swift communication from server worker and migration-era main-thread callers: typed scheme-handler `POST` request/response RPC through `WKURLSchemeHandler` `fetch()`, plus subscriptions and pushes through long-lived streamed `fetch()` responses while native writes frames into the stream | Swift-side request, response, push, content, availability, telemetry, command-ack, and health frames |
| main <-> Pierre workers | Pierre's own API exclusively | `BridgeWorkerPierreRenderJob` values received from the server worker without parsing, plus `bridgeDemandRank`; any large payload copy/transfer mode at this edge must be separately measured |

The long-lived streamed-response fetch is the decided Swift push mechanism. The
rejected alternative is `WKScriptMessage` push delivery: those pushes land in the
page world, force main into a relay role, share the script-message IPC delivery
lane, and recreate the default-run-loop-mode hazard. It is not a fallback after
cutover. If streamed-response proof fails, fallback ordering is:

1. keep the scheme-handler boundary and prove page-owned scheme `fetch()` plus
   transferable relay only as a temporary migration fallback that preserves
   worker ownership of protocol, cache, retry, and backpressure truth;
2. if that fallback cannot preserve the ownership contract or native proof, stop
   and redesign R44/R49 before implementation.

The page-load bootstrap handshake is the sole exemption to scheme-handler RPC.
It exists only to establish page/view identity before `fetch()` is possible, is
minimal, one-shot, and must not carry commands, telemetry, content, subscription
traffic, or push frames.

The `WKScriptMessage` / `__bridge_command` RPC plane is deprecated by this
contract. Content worlds, nonce listeners, `RPCMessageHandler`, `RPCRouter`, and
all script-message ingress for ordinary commands are deleted by the final cutover
unit's compile-enforced deletion set. They must not survive as a parallel path
beside scheme-handler RPC.

The rationale is one callable carrier from page and workers alike; no
shared-IPC-queue coupling between telemetry, interactive, content, and push
traffic because scheme tasks have their own lane; no `kCFRunLoopDefaultMode`
script-message delivery hazard on the Swift boundary; and one typed contract
module for the whole browser/native boundary.

Current script-message RPC inventory and post-migration carriers:

| Current command or lane | Post-migration carrier |
| --- | --- |
| `review.markFileViewed` | main -> worker port, then worker scheme-POST |
| active viewer mode signal | worker port; worker owns mode truth (R42), then scheme-POST |
| `system.bridgeTelemetry` | replaced; already live as `agentstudio://telemetry/batch` in commit `e009d5fd` |
| worktree-file telemetry sink | same replacement path as `system.bridgeTelemetry` |
| page-control/probe commands | unaffected; native -> page `evaluateJavaScript`, not script-message RPC |
| intake frames | per-unit cutover to worker streamed subscriptions |

No current command irreducibly requires script messages because scheme `fetch()`
is reachable from both page and worker contexts. Content worlds remain only as
bootstrap code-isolation machinery, not an ordinary command, telemetry,
content, subscription, or push transport.

On the Pierre edge, main is a courier, never a processor. Main hands Pierre a
`BridgeWorkerPierreRenderJob` from the server worker and the `bridgeDemandRank`;
it must not parse, classify, window, diff, or highlight the content on that
edge. Main may only wrap the job into the object shape required by Pierre's
public API and invoke that API.

### R50. Channel contracts are typed and constant.

`BridgeWorkerContracts` is the working-name single schema source for channel
[1], the main <-> server-worker `MessageChannel`. Both endpoints compile
against this module. It owns zod-derived types, the versioned wire format, and
runtime validation at the worker boundary. A message shape that is not in this
contract must be a compile error, not an unchecked runtime convention.

The main <-> server-worker channel is typed RPC plus typed events, not a shared
store. Commands carry `requestId`, epoch/revision freshness, payload DTO, and
declared transfer fields. Replies/events correlate to the request or stream they
advance. Fire-and-forget facts are still schema-defined messages with explicit
freshness semantics; no path may send `store.getState()`, a query-cache value, or
another runtime store shape as the protocol payload.

Channel [2] shares vocabulary with the Swift-side contracts through one
scheme-RPC contract module: one named contract vocabulary crosses the
Swift/browser boundary, and page, worker, and server implementation code consume
that vocabulary instead of inventing local frame shapes. No channel may add
ad-hoc message shapes.

### R51. Forbidden edges are part of the contract.

| Forbidden edge | Reason |
| --- | --- |
| main -> Swift through script messages | forbidden after final cutover except the minimal one-shot page-load bootstrap handshake; ordinary commands, telemetry, content, subscriptions, and pushes must use scheme-handler RPC and the script-message RPC plane must be compile-deleted |
| main -> Swift as protocol/backpressure owner | residual main-thread migration callers may use scheme-handler RPC only as typed client calls; ordinary content, subscriptions, retries, cache, and backpressure ownership still moves through the server worker |
| server worker -> DOM/render | the worker owns protocol, cache, parse, window, diff, and slice production, but DOM materialization remains main-thread/Pierre-owned |
| Pierre workers -> any initiator role | Pierre workers are pure compute/apply workers driven through Pierre's API, never demand, fetch, protocol, or Swift initiators |
| any untyped message anywhere | untyped traffic bypasses the schema source, version fence, validation boundary, and proof seams |

### R52. Main is a bounded courier on the content path.

The content path is Swift -> server worker for parse/window/diff and slice
production, then server worker -> main for a typed `BridgeWorkerPierreRenderJob`
hand-off, then main -> Pierre worker for highlighting and DOM-owned apply, then
Pierre/main -> DOM. The main hop is bounded to transfer/clone accounting plus
the Pierre API call because Pierre must be driven from its thread; the no-fork
constraint is not permission to make main parse, diff, classify, or re-window
content.

The stock Pierre worker-pool API is not assumed to preserve transfer lists. At
the time this spec was amended, `@pierre/diffs` `WorkerPoolManager` dispatches
worker work with `worker.postMessage(task.request)` and no transfer-list
argument. Therefore G may not claim zero-copy main -> Pierre delivery unless it
adds a sanctioned courier/adapter that proves transfer-list use. Without that
adapter, `BridgeWorkerPierreRenderJob` payloads crossing main -> Pierre must be
bounded, cache-keyed, and instrumented for clone/submit duration.

### R53. Worker messages are transferable-first.

All main <-> server-worker `postMessage` payloads prefer structuredClone
TRANSFER over copy when payload size can affect interaction latency. Small
plain DTOs may use normal structured clone. Content bytes, binary indexes,
large paint-ready payloads, and any persistent-cache payload must use
`ArrayBuffer` as the byte representation instead of strings or large object
graphs.

When ownership moves across the boundary, the sender must include the
`ArrayBuffer` (or a typed array's underlying `.buffer`) in the transfer list:
`postMessage(payload, [buffer])` or `structuredClone(payload, { transfer:
[buffer] })`. A transferred buffer detaches from the sender and becomes
unavailable there after send. No sender or receiver path may rely on an O(bytes)
clone to keep a second live copy. If an explicit copy is required for a small or
retained value, that message must declare clone semantics and be measured under
the same per-message boundary instrumentation.

`BridgeWorkerContracts` message types must name transfer fields explicitly. A
message with no transfer fields declares an empty transfer list; a message with
content bytes, large paint-ready payloads, or persistent-cache payloads declares
the exact fields that are transferred or explicitly cloned. Runtime validation
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

Boundary instrumentation follows the Constants Annex rule: measure
serialize/clone/transfer duration and bytes per message class, not as one
aggregate worker number. R53 applies at cutover slice G and to the future
persistent-cache PR; persistent-cache payloads do not get a copy-based
exemption.

### R54. Zustand moves to the comm worker; TanStack Query owns React async RPC.

The architecture has one Bridge data store owner: the comm worker. That store is
implemented as a worker-local Zustand vanilla store unless a later spec replaces
it with an equivalent typed worker-local primitive. React/main must not create,
import, subscribe to, or mutate a Zustand store for Bridge viewer data after the
cutover. Existing main-thread Review/File View Zustand stores are legacy
deletion targets, not implementation options.

React/main has two allowed local surfaces:

- TanStack Query/Mutation adapters for coarse async worker RPC lifecycle: open
  source, refresh, reconnect, search/filter command completion, mark-viewed
  mutation, and mutation optimism/rollback.
- Non-Zustand render-slice hooks for frame-critical display copies: selected
  item, active mode, viewport/range, hover/focus, expanded/collapsed UI intent,
  panel chrome, row paint copies, content availability copies, and worker health
  copy. This surface exists only to paint synchronously and to apply worker
  slice patches inside the R46 frame budget.

React components must import domain hooks or selectors, not raw worker protocol
state and not Zustand. TanStack Query is required for React-side coarse async
worker RPC. It must not become the high-frequency row/content patch stream,
canonical result cache, demand queue, byte cache, or protocol owner.

No store snapshot may cross the worker boundary in either direction. The only
cross-boundary values are `BridgeWorkerContracts` DTOs, scheme-RPC DTOs, and
declared transfer fields.

Required type families:

| Type family | Runtime | May use | Must contain | Must not contain |
| --- | --- | --- | --- | --- |
| `BridgeMainRenderSnapshotStore` | main/React | non-Zustand store with `useSyncExternalStore` React integration | selected id, active mode, viewport/range, hover/focus, expanded/collapsed UI intent, panel chrome, `rowPaintSlice(id)`, `contentAvailabilitySlice(id)`, worker health copy | Zustand store, content bytes, byte cache, demand membership, retry/backoff, stream id authority, worker epoch authority, sequence authority, Swift request ownership, query cache reads |
| `BridgeCommWorkerStoreState` | comm worker | Zustand vanilla | canonical rows/indexes, byte cache, paint-ready cache, demand membership, in-flight/executor queues, retry/backoff, stream/session/protocol state, worker epoch, telemetry buffer | DOM nodes, React state, component refs, direct Pierre worker initiator state, main-thread query cache objects |
| `BridgeWorkerMainToServerMessage` | wire DTO | `BridgeWorkerContracts` zod-derived union | `requestId`, wire version, epoch/revision freshness, command/fact kind, cloneable payload, declared transfer fields | store snapshots, functions, class instances, DOM objects, `AbortController`, non-declared buffers |
| `BridgeWorkerServerToMainMessage` | wire DTO | `BridgeWorkerContracts` zod-derived union | health events, correlated replies, subscription events, slice patches, availability/content events, epoch/sequence freshness, declared transfer fields | canonical worker store, full package snapshots for interaction updates, untyped payloads |
| `BridgeWorkerSlicePatch` | wire DTO applied to main render snapshot | typed patch union | target slice, operation, item id when keyed, epoch/sequence, small cloneable render payload or transfer descriptor | protocol/cache truth, raw content bytes unless explicitly declared as transfer/copy payload |
| `BridgeWorkerPierreRenderJob` | comm worker -> main courier -> Pierre API | `BridgeWorkerContracts` DTO plus a Pierre edge adapter | item id, render kind, content hash/cache key, language/render metadata, `bridgeDemandRank`, bounded Pierre-compatible file/diff payload or transfer descriptor, byte/clone budget class | comm-worker store snapshot, Swift protocol state, functions/classes, DOM objects, main-recomputed text/window/diff, unmeasured unbounded content payload |
| `BridgeWorkerTransferDescriptor` | wire metadata | explicit transfer-list helper | message kind, field path, byte length, `transfer` or explicit `clone`, detached-after-send expectation | implicit large payloads, unmeasured clone cost |
| `BridgeSchemeRpcRequest` / `BridgeSchemeRpcResponse` / `BridgeSchemeStreamFrame` | JavaScript <-> Swift scheme boundary | shared browser/native contract vocabulary | method/path/resource kind, request id, stream id, source generation, byte limits, telemetry/drop counters, health/error frames | script-message command payloads, raw paths/content in telemetry, ad-hoc frame shapes |
| `BridgeWorkerQueryAdapter` | main/React | TanStack Query/mutation | coarse async worker RPC lifecycle for open, refresh, reconnect, search/filter completion, mark-viewed mutation, optimistic update/rollback coordination | high-frequency row patch stream, canonical result cache, byte cache, demand queue, protocol owner |
| `BridgeWorkerRpcClient` | main/React | typed `MessageChannel` client helper | request id creation, timeout/retry policy for coarse RPC, typed send/receive, transfer-list handoff to worker | store access, direct Swift RPC, render-slice mutation outside patch helpers |
| `BridgeWorkerPatchApplier` | main/React | non-Zustand helper | R46-budgeted application of `BridgeWorkerSlicePatch` values to `BridgeMainRenderSnapshotStore` subscriptions | protocol ownership, demand scheduling, unbounded synchronous full-list rebuilds |
| `BridgeWorkerTransferListBuilder` | main and worker | shared helper | declared transfer fields, byte counts, clone-vs-transfer mode, detached-after-send assertions | implicit ArrayBuffer payloads or unmeasured large clones |
| `BridgeCommWorkerCommandHandler` | comm worker | worker-local helper around Zustand store | validate typed commands, update `BridgeCommWorkerStoreState`, enqueue fetch/demand work, publish typed replies/events | DOM/Pierre direct initiator behavior, React state mutation |

### R55. TanStack Query has a Bridge-owned client policy.

TanStack Query is an async RPC/mutation lifecycle adapter, not a freshness,
retry, polling, or render-data authority. A converted Bridge surface must create
or receive a `BridgeWorkerQueryClientPolicy` and all Bridge worker queries must
inherit it. The policy disables library refetch/retry behavior that would create
a second worker-retry authority:

| Option / rule | Required value |
| --- | --- |
| `refetchOnWindowFocus` | `false` |
| `refetchOnReconnect` | `false`; reconnect is an explicit worker command/event |
| `refetchOnMount` | `false` for command-completion queries |
| `retry` / `retryOnMount` | `false` for worker RPC queries; worker owns retry/backoff |
| `query.data` shape | ack/status/progress envelopes only; no row arrays, content windows, byte buffers, demand membership, or canonical cache entries |
| invalidation | only through typed worker protocol events, never focus/reconnect/mount freshness heuristics |

The Bridge policy exists because TanStack Query's useful web defaults are wrong
for this boundary: stale queries may refetch on mount, focus, and reconnect, and
failed queries may retry. Bridge worker RPC already has explicit epoch,
sequence, reconnect, retry, and staleness rules; duplicating those in the query
client is a contract violation. The defaults are grounded in TanStack Query's
official Important Defaults guide
(`https://tanstack.com/query/v5/docs/framework/react/guides/important-defaults`).

Search/filter input is not automatically coarse RPC. Text input, selected
filters, and local preview state are local render intent. FE sends coalesced
worker facts or an explicit submit command; TanStack Query observes only the
ack/completion envelope and mutation lifecycle. It must not turn every
keystroke into an eager query or cache a result list as canonical visible state.

Mutation optimism is also bounded: a TanStack mutation may call
`BridgeMainRenderSnapshotStore` local-intent helpers for frame-1 chrome and may
record rollback metadata for the command lifecycle. It must not mutate query
data as durable visible state. Worker ack/repair remains the only durable result.

### R56. Main render snapshots use one non-Zustand primitive.

OD-LF2 is closed: the FE primitive is `BridgeMainRenderSnapshotStore`, a
non-Zustand store exposed to React through `useSyncExternalStore`. It has exactly
two write inputs:

- local intent helpers for synchronous UI facts: selected, hover/focus, viewport
  range, expanded/collapsed row ids, active mode, and shell chrome; and
- `BridgeWorkerPatchApplier`, which applies typed worker slice patches inside
  the R46 frame budget.

Render paths read only from this snapshot store and component props. They do not
read TanStack Query cache data, comm-worker protocol fields, raw worker messages,
or legacy Zustand state. The snapshot store contains display copies only; losing
it may require repainting, but must not lose bytes, demand membership, epochs,
sequences, retries, stream state, or Swift request state.

Every converted surface has one snapshot primitive. Multiple route-local
mini-stores, mixed React-state/query-cache render reads, or a compatibility
bridge from old Zustand into the snapshot store are contract violations.

### R57. Pierre/Shiki ownership and courier budgets are explicit.

The content/render chain is split by work class:

| Stage | Owner | Owns |
| --- | --- | --- |
| content identity and demand rank | comm worker | item id, source/worker epoch, content hash/cache key, selected/visible rank, stale-drop identity |
| window choice and payload class | comm worker | bounded diff/file/text window, language/render metadata, byte/line budget class, transfer descriptor when possible |
| tokenization/highlighting/render worker execution | Pierre/Shiki worker pool | Shiki tokenization, Pierre render task execution, Pierre internal cache/pool scheduling |
| courier enqueue and DOM apply | main/React | call Pierre API with `BridgeWorkerPierreRenderJob`, record clone/submit cost, apply DOM through R46 pump |

The comm worker must not pre-tokenize with Shiki and then ask Pierre to tokenize
again. Main must not parse, window, diff, decode, highlight, or reconstruct a
Pierre payload. The only sanctioned main-thread content action is
`BridgeWorkerPierreCourier.enqueue(job)`.

Stock Pierre main -> worker delivery is a measured clone edge unless a
sanctioned adapter proves transfer-list delivery. Therefore every
`BridgeWorkerPierreRenderJob` carries a budget class and every converted surface
must define these policy constants in `AppPolicies` or the BridgeWeb policy
mirror:

| Policy | Initial ceiling | Derivation / proof |
| --- | --- | --- |
| `interactivePierreRenderJobMaxBytes` | <= 512 KiB | stays far below `contentMaxBytesPerItem`; protects click queue wait from stock-Pierre clone cost |
| `interactivePierreRenderJobMaxWindowLines` | <= 400 lines | first visible content window, not full-file hydration |
| `pierreCourierCloneSubmitP95Ms` | < 4 ms | at most one quarter of the 16 ms foreground queue-wait p95 budget |
| `pierreCourierCloneSubmitP99Ms` | < 8 ms | leaves the frame budget available for local chrome and R46 apply |

If a job exceeds byte or line policy, the worker splits into smaller windows,
publishes a placeholder/unavailable slice for the overflow, or demotes the
non-selected portion to delayed apply. It must not send an unbounded payload and
hope the main thread survives. If measured stock-Pierre clone/submit exceeds the
p95/p99 budget, Slice G is not green until the windowing policy is tightened or a
transfer-aware Pierre edge adapter lands with proof.

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

Selected/click command handling is O(selected + visible delta). Viewport and
hover handling are O(visible delta) or O(1) per coalesced fact. Source reset may
swap generations atomically, but full-list/index rebuild work must be chunked or
performed behind a new generation so selected foreground work can preempt it.

The worker message loop publishes queue-wait and handler-duration telemetry by
lane and command class. A worker-side giant `Map` clone, full list rebuild,
selector fan-out, or synchronous source reset that delays selected work beyond
the R32-R40 foreground/visible queue budgets is a contract violation even though
it no longer blocks the main thread.

### R59. Scheme RPC and worker DTOs are an explicit trust boundary.

The comm worker is not a trusted native peer merely because it runs in this app.
Every scheme-RPC request, streamed frame, and main/worker DTO is validated at the
boundary that receives it.

Required trust rules:

- requests carry session identity, source generation or worker epoch as
  appropriate, stream/request id, and replay/staleness token;
- stale, replayed, foreign-session, or wrong-epoch frames are rejected before
  state mutation;
- methods, paths, resource kinds, and command names are allowlisted before byte
  decode or expensive validation;
- byte caps are checked before decode and before telemetry projection;
- raw file paths, raw content, command payload bodies, errors containing source
  text, and secret-bearing metadata are scrubbed from telemetry;
- transfer descriptors are validated against actual payload values and declared
  byte lengths;
- hostile worker and hostile server tests cover forged ids, stale epochs,
  oversized bodies, unknown methods, malformed transfer descriptors, and
  duplicate/reordered stream frames.

Content-world/script-message RPC is not a fallback for these rules. After the
one-shot page-load bootstrap exemption, ordinary Swift communication crosses the
scheme-RPC boundary only.

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
        async content fetch/decode/window/rank preparation
        │
        ├─► scheme-RPC fetch/subscribe to Swift when needed
        │
        └─► BridgeWorkerServerToMainMessage
              typed event/reply with slice patches and
              BridgeWorkerPierreRenderJob values
              ArrayBuffer transfer for large payload ownership moves
              │
              ▼
            BridgeMainRenderSnapshotStore subscriptions
              R46 frame-budgeted patch apply and low-cost
              Pierre courier enqueue
```

Transfer mode matrix:

| Surface | Payload class | Boundary | Mode | Rule |
| --- | --- | --- | --- | --- |
| Review | select, hover, mode, viewport, mark-viewed facts | main -> comm worker | structured clone DTO | Small ids, hashes, ranges, enums, and revisions; never transfer list. |
| Review | query/open/refresh/reconnect/search/filter RPC via TanStack Query | main -> comm worker | structured clone DTO | Query key and variables are cloneable DTOs; optimistic state stays in TanStack/render hooks, not in worker payload. |
| Review | metadata descriptors, availability, row chrome, tree/window patches | comm worker -> main | structured clone DTO | Only bounded visible/window deltas may cross; full-package snapshots are forbidden. |
| Review | source/diff/content bytes fetched from Swift | Swift -> comm worker | stream/`ArrayBuffer` in worker | Worker consumes `ReadableStream<Uint8Array>`/`arrayBuffer()` and owns the byte cache; main does not receive raw bytes. |
| Review | large paint-ready runs, line windows, binary preview payloads, persistent-cache payloads | comm worker -> main/Pierre courier | transfer list | Payload uses `ArrayBuffer`; include the buffer in the transfer list when ownership moves. If the worker must retain canonical bytes, send a derived display buffer and measure the copy. |
| Review | `BridgeWorkerPierreRenderJob` for Shiki/diff rendering | comm worker -> main -> Pierre API | transfer to main when possible; measured bounded clone into stock Pierre unless adapter proves transfer | Comm worker prepares all data/rank needed by Pierre. Main may only enqueue through the Pierre API and record clone/submit cost; no main parse/window/diff/highlight. |
| Review | telemetry counters and health/drop summaries | comm worker -> Swift or main | structured clone DTO or scheme POST body | Counters and health summaries are small DTOs; encoded telemetry batches may use `ArrayBuffer` bodies when byte size is material. |
| File View | open file, select path, expand/collapse, filter/search, viewport facts | main -> comm worker | structured clone DTO | Small path ids/hashes, filter text, row ids, and ranges; never full tree state. |
| File View | tree metadata, descriptor windows, availability, row paint patches | comm worker -> main | structured clone DTO | Only bounded visible/window deltas may cross; full manifest/list snapshots are forbidden. |
| File View | file contents fetched from Swift | Swift -> comm worker | stream/`ArrayBuffer` in worker | Worker owns raw file bytes and decoded/cache truth; main receives availability or paint-ready display payload only. |
| File View | large text windows, syntax/token runs, binary preview bytes, persistent-cache payloads | comm worker -> main/Pierre courier | transfer list | Payload uses `ArrayBuffer`; include transferred buffers explicitly and assert sender detachment. |
| File View | `BridgeWorkerPierreRenderJob` for syntax/text rendering | comm worker -> main -> Pierre API | transfer to main when possible; measured bounded clone into stock Pierre unless adapter proves transfer | Comm worker prepares the render payload and rank. Main may only enqueue through the Pierre API and record clone/submit cost; no main content loading, decoding, or line-window work. |
| File View | initial load/progress/worker health | comm worker -> main | structured clone DTO | Progress and health are small render-copy facts; no content bytes or raw manifest snapshot. |

## Action And Event Sequence Contracts

Every user action and system event must preserve the local-first rule: FE may
paint only from local render slices, and worker/native traffic may repair,
subscribe, fetch, or append facts after that paint. Every arrow crossing a
boundary is fire-and-forget or a subscription; no arrow may turn around
synchronously into a paint.

Boundary notation:

```text
main/FE -> server worker     LOCAL-FIRST MessageChannel boundary crossing
JavaScript -> Swift          scheme-handler typed POST/stream fetch boundary
Swift -> JavaScript          streamed push/content/response crossing
server worker -> main/FE     typed slice publication crossing
main/FE -> Pierre worker     Pierre API compute/apply boundary crossing
```

### Action/Event Inventory

| Trigger | Initiating actor | Boundary crossings | Paint rule | Governing requirements |
| --- | --- | --- | --- | --- |
| click cache-hit | user/FE | 0 before content paint; later FE -> server worker intent/fact if needed | frame-1 paints readable selected content from fresh local paint-ready cache | R41, R42, R45, R48, R49 |
| click cold | user/FE | 0 before frame-1; later FE -> server worker demand fact, server worker -> Swift scheme-RPC fetch/subscription, Swift -> server worker streamed content, server worker -> FE slice | frame-1 paints selected identity plus honest loading/availability; selected content applies first within R46 budget when ready | R41, R44, R45, R46, R48, R49, R52 |
| scroll momentum | user/FE/Pierre | one rAF-coalesced FE -> server worker viewport fact per frame while moving; main -> Pierre worker through Pierre API only | Pierre scrolls existing DOM immediately; incoming slices that affect viewport are HELD while momentum continues | R41, R45, R46, R48, R49, R51 |
| scroll settle | FE/Pierre | FE -> server worker settled viewport fact; later server worker -> FE affected slice updates; main -> Pierre worker through Pierre API only | settle frame keeps existing DOM; HELD slices apply by rank after settle inside frame budget | R41, R45, R46, R48, R49, R51 |
| hover | user/FE | 0 before hover paint; later FE -> server worker hover fact if it changes demand | frame-1 paints local hover/focus chrome only; content demand is speculative and cannot block hover | R41, R42, R45, R49 |
| expand/collapse | user/FE | 0 before toggle paint; later FE -> server worker expanded/collapsed fact | frame-1 paints local tree shape and placeholders from slices; server worker repairs invalid ids or supplies content deltas later | R41, R42, R45, R46, R49 |
| mode switch | user/FE app shell | 0 before shell paint; later FE -> server worker activeMode fact | frame-1 paints retained local mode shell/slices; server worker demotes inactive foreground work and repairs availability later | R41, R42, R45, R49 |
| tab/worktree switch | user/FE app shell | 0 before shell paint; later FE -> server worker selected context fact and server worker -> Swift scheme-RPC subscribe/reopen if needed | frame-1 paints retained local shell or honest loading; no visible old-worktree content after identity change | R41, R42, R45, R48, R49 |
| server push/fact | Swift | Swift -> server worker streamed scheme response; server worker -> FE affected slices only | FE paints only after server worker validates stream/epoch/sequence and publishes O(delta) slice patches | R42, R45, R48, R49, R50 |
| content-ready | Swift/server worker executor | Swift -> server worker streamed content response; server worker -> FE paint-ready slice | no direct paint from response; server worker validates current epoch and FE applies rank-first within R46 | R42, R44, R46, R48, R49, R52 |
| generation rotation | Swift source plus server worker epoch authority | Swift -> server worker source fact; server worker atomic epoch reset; server worker -> FE reset slices | one paint observes either old epoch before reset or new epoch after reset; never half-old/half-new | R37, R42, R44, R45, R48, R49 |
| fetch failure | server worker executor/Swift content path | Swift -> server worker failure or server worker local fetch failure; server worker -> FE availability/health slice | selected identity paints explicit retry/unavailable/error state; FE never starts its own retry | R41, R42, R44, R48, R49 |
| reconnect | server worker transport | server worker -> Swift scheme-RPC reopen/subscriptions; Swift -> server worker streamed resync; server worker -> FE health/slice repairs | FE keeps local slices with explicit health/loading; stale incoming results cannot mutate active UI | R42, R44, R45, R48, R49 |
| telemetry flush | server worker | server worker -> Swift dedicated scheme POST only | no user-visible paint; flush runs idle, byte-capped, drop-oldest with lossless counters | R41, R43, R48, R49 |
| startup warm-up | FE activation/server worker | FE -> server worker warm-up fact; server worker may prewarm cache/compute and Swift subscriptions | initial shell paints from retained local slices or honest loading; warm-up cannot block first paint | R41, R42, R44, R48, R49 |

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
  ├─► server worker (optional fact/intent after paint)
  │
  ◄─ server worker repair slice only if epoch/staleness later disagrees
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
  ├─► server worker: selected/content-demand fact
  │      validates current workerDerivationEpoch and ranks selected first
  │
  ├──── server worker ────► Swift: scheme-RPC fetch/subscribe if cache miss
  │                         Swift ────► server worker: content or availability
  │
  ◄─ server worker: selected paint-ready slice
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
  ├─► rAF: FE ─► server worker viewport fact, at most one per frame
  │
  ◄─ server worker slice updates that affect moving viewport
  │      FE marks affected updates HELD while momentum continues
  │
  ▼
settle detected by Pierre/FE
  │
  ├─► server worker settled viewport fact
  │
  ▼
FE apply pump
     releases HELD slices by rank inside R46 budget
```

Server facts, content-ready, fetch failures, and reconnect:

```text
Swift subscription/content plane
  │
  ├─► server worker: streamed push/fact/content/failure/reconnect response
  │
  ▼
server worker
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
  └─► server worker source fact
        │
        ▼
      server worker atomic epoch reset
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
FE/server-worker instrumentation samples
  │
  ▼
server worker telemetry buffer
  │  encoded-byte cap, drop-oldest shedding,
  │  lossless counters by event/lane/result/drop reason
  │
  ├─ scheme-RPC command path: never flushes telemetry
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
- TanStack Query or equivalent async cache as the high-frequency row/content
  patch stream;
- root-snapshot render coupling for interaction paths;
- package-shaped sync work inside click, selection, scroll, or paint handlers;
- handler-splitting as a claim of WebKit IPC isolation.

Compile-enforced deletion sets are required per cutover unit:

| Cutover unit | Delete or make unbuildable | Keep only |
| --- | --- | --- |
| File viewer content protocol | FE raw body/frame package intake, FE generation/sequence/staleness caches for content, FE demand retry/parking fields | FE slices, worker protocol client, native metadata plane |
| Review viewer content protocol | package-first review body loading, root-snapshot selection render path, review prefetch pump, FE cache-membership truth | FE slices, worker reconciler/cache, native metadata plane |
| React Bridge data stores | Review/File View main-thread Zustand store imports, subscriptions, mutations, and action dispatch for Bridge viewer data | TanStack Query adapters for coarse worker RPC; non-Zustand render snapshots/hooks for frame-critical display copies; worker-local Zustand store |
| telemetry transport | interactive RPC telemetry send/force-flush path and shared-command queue telemetry | dedicated scheme POST endpoint and worker batching |
| final browser/native RPC cutover | `WKScriptMessage` / `__bridge_command` ordinary RPC, content-world command listeners, nonce command dispatch, `RPCMessageHandler`, `RPCRouter`, and script-message ingress | minimal one-shot page-load bootstrap; scheme-handler typed POST/stream RPC for all ordinary Swift communication |
| demand membership | legacy staging buffers, membership caps, pending eviction as membership policy, parked retry versions | worker reconciler membership and executor-stage pacing only |

No old and new path may remain live for the same viewer/protocol surface. Any
surface not converted by a cutover unit is explicitly outside R41-R59 proof and
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
