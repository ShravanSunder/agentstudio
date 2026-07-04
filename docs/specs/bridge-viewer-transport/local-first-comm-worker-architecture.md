# Local-First Comm Worker Architecture

Date: 2026-07-04
Status: normative increment after
[performance-demand-lanes.md](performance-demand-lanes.md) R32-R40 and its
Constants Annex
Parent: [performance-demand-lanes.md](performance-demand-lanes.md)

This file defines the next BridgeViewer transport boundary. It does not define
implementation order.

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

The architecture assumes these WebKit constraints:

- All named `WKScriptMessageHandler` handlers for one `WKWebView` share one IPC
  delivery lane. Splitting command, telemetry, and demand across handler names
  provides routing semantics only, not isolation or independent backpressure.
- Message-handler delivery is treated as default-run-loop-mode traffic. Gesture
  tracking may starve it; this starvation remains an empirical-confirm open
  decision, not a settled proof claim.
- `WKURLSchemeHandler` intercepts worker-initiated `fetch()` for registered
  schemes. WebKit TestWebKitAPI `FileSystemAccess.mm` and
  `IndexedDBPersistence.mm` are the source-grounded research anchors for the
  worker custom-scheme path.
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
        streamId, generation, sequence, staleness, retries/backoff/pacing,
        telemetry batching, Swift reconnect resync
  exposes: local slice updates to FE; client requests/subscriptions to Swift
  forbidden: relying on FE for protocol truth or on Swift liveness for paint

CLIENT/SERVER transport boundary
  worker -> Swift: async request/response, subscription open/close,
                   content fetches, telemetry POST batches
  Swift -> worker: subscription pushes, descriptor/content responses,
                   reset/unhealthy facts

Swift server
  owns: metadata plane, content scheme handler, BridgeContentDemandAdmission,
        provider/source authority
  exposes: disposable service endpoint; reconnect rebuilds worker truth
  forbidden: FE-observable server lifetime or UI paint coupling
```

## Truth Ownership Table

Every datum has exactly one truth owner.

| Datum | Truth owner | Readers | Notes |
| --- | --- | --- | --- |
| `streamId` | comm worker | FE read-only via diagnostics, Swift request validation | FE does not store it. |
| `generation` / R37 epoch | comm worker | Swift request validation, worker tests | Collapses today's manually synced generation authorities. |
| `sequence` | comm worker | Swift server, worker tests | Gaps recover through worker/server resync. |
| staleness classification | comm worker | FE receives only visible health/render facts | No FE stale predicates. |
| content-demand membership | comm worker reconciler | executor/cache inside worker | R32 stays authoritative inside the worker. |
| content bytes / byte cache | comm worker | worker parse/window/diff/highlight | FE never receives raw body text. |
| paint-ready rows/runs/extents | comm worker produces; FE slice store owns current render copy | components | Transferable payloads; no protocol metadata required by components. |
| selected row/file/item | FE local slice | comm worker as fact input | Click writes local slice synchronously and sends intent. |
| telemetry queue | comm worker | Swift telemetry endpoint | Not on interactive RPC. |
| metadata plane | Swift | comm worker subscriptions | Untouched by this spec. |

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

### R42. Every datum has exactly one truth owner.

The worker is the single authority for protocol and cache truth: stream
identity, R37 generation epochs, sequence, staleness, cache membership,
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

Native telemetry obligations:

- single-pass decode;
- admission and byte/count validation before expensive work;
- rejection/drop facts for invalid or over-budget batches;
- no raw paths, raw URLs, payload text, prompts, tokens, or raw errors.

R43 bans the verified shared-channel compounding path
(`tmp/debug-workflows/2026-07-04-agent-studio-luna338-scroll-placeholder-survivor/debug-investigation.md:166`)
and applies the Constants Annex rule that every cap protects exactly one class
(`docs/specs/bridge-viewer-transport/performance-demand-lanes.md:315`).

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

### R45. FE render store is sliced.

FE components subscribe to row-, item-, selection-, viewport-, and
panel-scoped slices. Root-snapshot subscriptions that make one interaction
rebuild package-shaped state are contract violations. O(package) work inside
interaction handlers is a contract violation.

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
- bounded per frame by time and unit count;
- input-yielding between chunks;
- resumable without redoing completed units;
- stale-safe if worker or Swift advances generation while units are pending.

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

- tests FE against a fake worker;
- proves synchronous local render reads, optimistic click paint, slice
  subscription boundaries, no protocol state in FE, and frame-budgeted apply
  behavior;
- cannot prove WebKit IPC delivery, worker/server protocol correctness,
  Swift admission, worker content fetch, native telemetry decode, or live
  momentum starvation.

Worker seam:

- tests the comm worker against a hostile mock server that is never politer than
  live Swift: out-of-order pushes, stale generations, dropped responses,
  reconnects, oversized telemetry, slow content, persistent fetch failures,
  and backpressure;
- proves stream/generation/sequence/staleness authority, R32-R40 membership,
  R34 backoff/pacing, R37 epoch reset, R39 rank into worker pools, R43 telemetry
  batching/shedding, R44 content streaming, and reconnect resync;
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
- Victoria-backed proof remains required for performance samples and telemetry
  admission;
- existing R32-R40 proof seams remain required and are not replaced
  (`docs/specs/bridge-viewer-transport/performance-demand-lanes.md:277`).

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
