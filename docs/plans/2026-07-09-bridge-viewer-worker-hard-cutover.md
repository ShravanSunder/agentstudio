# Bridge Viewer Worker Hard Cutover Implementation Plan

Date: 2026-07-09
Status: accepted after one adversarial pass and narrow carrier/type reconciliation; implementation active
Goal id: `2026-07-09-bridge-click-fileview-workers`
Agent Studio implementation base: `ea7ce82a19fb6b600856a16fbe02866e131cecb6`
Accepted spec: `docs/specs/bridge-viewer-transport/local-first-comm-worker-architecture.md`
Accepted spec SHA-256:
`db903d14310821f2fc10a15ad1f08ade6c01cfcb379042dc545d140a9aae69d8`
Pierre source: `/Users/shravansunder/Documents/dev/open-source/libs-react/pierre`
Pierre planning base: `origin/main` at
`4f94a5e765195b27e1e4188b943aab2ae44613cb`

## Goal

Deliver a functional DiffsHub-class Review diff viewer and File View whose
ordinary product traffic is owned by one comm worker per pane, whose optional
telemetry is owned by a separate telemetry worker, and whose large-diff/file
behavior meets the accepted correctness and p99 gates without blocking the main
event loop.

This plan ends at an Agent Studio PR proven ready but not merged. Upstream
Pierre merge, tag, or npm publication requires explicit release authorization.

## Non-Negotiable Boundaries

- One pane-owned comm worker owns every ordinary Review/File command, stream,
  demand, content request, acknowledgement, retry, cache decision, and write
  intent. A converted surface has no second path.
- That worker owns one reusable `BridgeProductTransport`: constrained generic
  `call`, logical `subscribe`, and independently cancellable `openContent` over
  three typed POST routes. Only its shared module knows routes or product fetch.
- Main owns local intent, bounded display copies, frame-budgeted DOM apply, and
  opaque Pierre courier calls only. It never owns source bytes or product
  protocol/capability/native-subscription state.
- All main/worker/Swift RPC uses closed strict discriminated unions backed by
  constrained registry generics and strict runtime validation. No generic JSON
  payload, catch-all case, feature extension escape hatch, or untyped handler
  survives parser admission.
- Telemetry-off creates no telemetry worker. Telemetry-on creates one separate
  worker per pane; no main/comm fallback pipeline exists.
- Review continues through the final real window of the 100,000-line fixture.
  File View renders one truthful UTF-8 prefix bounded by 2 MiB and 10,000 real
  lines and has no continuation.
- The final Pierre dependency is a released public package. No fork, private
  import, proxy worker, `patch-package`, local-path dependency, or string-clone
  compatibility corridor is permitted.
- Every behavior change is RED first. A slice is not converted while its old
  owner remains live.

## Execution DAG

```text
S0 proof reducers + current native worker-fetch baseline
  |
  +-- S1 Pierre public API + authorized release ---------------------+
  |                                                                 |
  +-- S2a native POST/stream feasibility                             |
  |      -> S2b-e product session, adapter, install, teardown -------+-- G1
  |                                                                 |
  +-- G0 parent freezes shared wire/capability contract              |
         -> S3 pane-worker client + semantic fulfillment ------------+
                    |
                    +-- S4 telemetry sidecar -------------------------------+
                    |
                    +-- S6a Review normalize/index/search off path          |
                                                                          |
G1 = released Pierre + packaged direct worker stream + frozen contracts   |
  |                                                                       |
  +-- S5 File View hard cutover ----------------------+                   |
  |                                                   |                   |
  +-- S6b Review window/Pierre proof -----------------+-- S7 Review cutover|
                                                          |               |
                                                          +---------------+
                                                                  |
                                                                  v
                                                        S8 audit + full proof
                                                                  |
                                                                  v
                                                  implementation review -> PR
```

S1 and S2a may start immediately. G0 is a parent-owned `wireVersion: 2`
TypeScript/Swift wire, capability, bootstrap, and hostile-fixture freeze. This
layout has not shipped, so G0 installs no v1 compatibility path. It replaces the
current recursive JSON payload/resource-GET shell with closed call/subscription/
content registries, byte-exact canonical subscription-interest vectors, strict
raw-member/scalar validation, Zod discriminated unions, and matching strict Swift
`Codable` enums before S2b-e and S3 integrate. A permanent dedicated TypeScript
compile-negative fixture proves unknown registry keys and cross-wired request,
result, event, and content types fail. `unknown` exists only at the immediate
parser input; it cannot enter a handler or stored/wire value. G0 also freezes an
epoch-free pane/session identity plus independent Review/File
`workerDerivationEpoch` values on surface-scoped variants only. S4 starts
after S2 admission and S3 pane-session contracts integrate. S6a may run after S3
without Pierre; S6b, S5, and S7 require G1. S7 requires S5's File deletion gate
and all S6 proof. S8 requires S4 drain/Victoria and S7 Review deletion.

Core-directory work may run in parallel, but root app composition,
`BridgePaneController`/bootstrap, shared unions/fixtures, package/lock changes,
and deletion scans have one parent-owned serialized integration commit per
gate. A start-gate receipt records those predecessors and the shared-file diff
manifest before S4, S5, S7, or S8 begins.

## Slice S0: Make The Proof Honest First

Source: R48, R62 and the benchmark success contract.

Behavior:

- Replace positive-only, single-launch reducers with a closed cell manifest,
  three fresh processes per cell, one correctness warmup, and 100 attempted
  measured actions per launch.
- Preserve timeout, stale, wrong, blank, disappeared, and missing-endpoint
  attempts as deadline-valued percentile samples.
- Record nearest-rank per-launch, pooled, and worst-launch p95/p99 without
  interpolation or averaging launch percentiles.
- Materialize the closed 84-cell manifest (21 family/cache-state rows x two
  runtimes x two telemetry states), 252 fresh launches, and 25,200 measured
  attempts. The reducer asserts those exact floors.
- Shard by immutable cell id. Resume a completed launch only when HEAD, dirty
  state, packaged bundle hash, fixture/checksum, viewport, machine profile,
  Pierre version, telemetry state, and run-manifest hash all match. Any mismatch
  invalidates that launch rather than mixing cohorts.
- Give every launch a bounded startup/action/drain/exit deadline, deterministic
  source/cache-state reset, owned PID/app identity, and event-based readiness.
  No wall-clock sleep establishes readiness.
- Preserve the current marker-scoped worker custom-scheme GET/held-stream result
  only as a labeled historical pre-cutover baseline. It cannot satisfy G1; the
  product carrier proof is the S2a all-POST body/stream/cancellation probe.

Write surface:

- `BridgeWeb/scripts/bridge-viewer-browser-benchmark-runner.ts`
- new `BridgeWeb/scripts/bridge-local-first-proof-contract.ts`
- new browser and native orchestrators/reducers under
  `BridgeWeb/scripts/verify-bridge-local-first-*.ts`
- benchmark fixtures/tests under `BridgeWeb/src/**/test-support/`
- new `scripts/verify-bridge-local-first-headless.sh` and
  `scripts/run-bridge-local-first-native-benchmark.sh`
- `Sources/AgentStudioIPCClientCore/` batch/control result support where the
  native orchestrator needs one bounded typed outer-clock completion seam
- `.mise.toml` tasks and validate-only script tests

The native orchestrator launches only through `run-debug-observability`, reads
and validates its state file/PID/bundle identity, drives typed semantic IPC,
waits for correlated post-paint and telemetry drain, writes raw attempts, sends
`SIGTERM` only to the owned debug PID, and performs a bounded process-exit wait
before the next launch. It never targets stable/beta or copies production state.
The headless driver owns the hostile Swift corpus and raw attempt schema without
making visual claims.

RED proof:

- Reducer tests reject 99 attempts, fewer than three launches, omitted failures,
  nonfinite/negative durations, averaged launch percentiles, stale HEAD/fixture/
  Pierre identity, missing lifecycle stages, missing telemetry drain, and any
  required loss/gap.
- The current benchmark artifact fails the new schema for the expected reasons.
- `--validate-only` tests reject wrong cardinality, stale resumptions, orphaned
  PIDs, missing drain/exit, and composite re-execution.

Checkpoint:

```bash
pnpm -C BridgeWeb exec vitest run scripts/verify-bridge-local-first
mise run observability:up
AGENTSTUDIO_STARTUP_DIAGNOSTIC_ACTION=bridge-worker-fetch-scheme-smoke \
  mise run run-debug-observability -- --detach
mise run verify-bridge-worker-fetch-scheme-smoke
```

The existing smoke proves feasibility only. S2 must extend it to the actual
capability-bound product stream before G1 closes.
`verify-bridge-local-first-performance` is a validate-only aggregate over the
component artifacts; it never launches the 84-cell matrix a second time.

## Slice S1: Release A Public Pierre Window API

Source: R52, R53, R57, R61 and the Pierre conformance corpus.

Behavior:

- Work from a fresh Pierre worktree based on `origin/main`, not the stale local
  `main` checkout.
- Add public byte-backed logical document, manifest, window, oversized-line
  segment, stable anchor, submission/disposition, cancellation, eviction, and
  hunk-expansion contracts.
- Add `CodeViewHandle.submitWindow`, current-state/idempotent admission,
  desired-window events, hunk expansion, cancel, and evict without cumulative
  `updateItem` or pseudo-items.
- Teach `WorkerPoolManager` and worker unions to post declared transfer lists,
  prove sender detachment, preserve Shiki content-addressed caching, and account
  total transferred bytes.
- Preserve header/item/line anchors across apply, replacement, eviction,
  re-entry, and expansion.

Likely Pierre write surface:

- `packages/diffs/src/types.ts` plus new public window modules and exports
- `packages/diffs/src/components/CodeView.ts`
- `packages/diffs/src/react/CodeView.tsx`
- `packages/diffs/src/worker/{types.ts,WorkerPoolManager.ts,worker.ts,index.ts}`
- virtual file/diff renderers and layout/anchor helpers
- new conformance, transfer, cancellation, anchoring, and 100,000-line tests

RED/GREEN proof:

```bash
AGENT=1 moon run diffs:test diffs:typecheck diffs:build
AGENT=1 moon run root:format root:lint
CI= bun publish --cwd packages/diffs --dry-run
```

The shared versioned corpus has explicit manifest/partition, mutation/no-op,
segment, transfer/detachment, cancel, eviction/cache, hunk-event, anchor, and
hostile-input case classes. It includes early/middle/final windows, same-size
different bytes, Unicode segment boundaries, cancellation races,
`already_applied`/`already_painted`, evict/re-demand residency, bad ids/
revisions/offsets/overlaps/checksums, stable anchors, hunk expansion, and sender
detachment. Agent Studio reruns this same corpus against the registry-installed,
locked release before G1.

Release gate:

- Upstream CI, public export/type tarball checks, approved merge, version bump,
  `diffs-vX.Y.Z` tag, and npm publication must complete before G1.
- Agent Studio then pins the released version in `BridgeWeb/package.json` and
  `BridgeWeb/pnpm-lock.yaml` and reruns the corpus against the installed package.
- A locally packed tarball may assist uncommitted development only; it cannot be
  committed or satisfy G1.

## Slice S2: Create The Native Product Session And Direct Worker Stream

Source: R44, R49, R59, R63, R64.

Behavior:

- Add a non-MainActor per-pane product-session actor owning `paneSessionId`, the
  freshly native-minted `workerInstanceId`, capability digest, serialized control
  admission, exact retry cache, one metadata producer, logical subscriptions,
  independent Review/File derivation-epoch admission floors, content producers/
  leases, sequence floors, cancellation, resync, and revoke.
  It is the sole worker-lifetime/admission/lease authority. The existing lease
  registry is folded into that actor or becomes a private descriptor index,
  never a second source of truth.
- Add capability-bound POST routes for `/rpc/command`, one long-lived pane
  `/rpc/stream`, and independently cancellable `/rpc/content` requests. Product
  payload/identity lives only in bodies and in-band response frames; the sole
  privileged header is the opaque capability.
- Enforce the shared 256 KiB encoded-request cap sender-side before fetch. Native
  authenticates first, then counts actual `httpBody` or bounded
  `httpBodyStream` bytes before strict decode/provider work. Never require
  `Content-Length`; WebKit pre-handler materialization of this bounded body is
  accepted, while arbitrary large worker-to-Swift upload remains out of scope.
- Implement selected strict Zod unions and closed Swift enums/payload structs.
  Both reject invalid UTF-8, duplicates, non-scalar typed strings, and unknown/
  lookalike keys before typed mutation. TypeScript bounds and duplicate-scans
  before document `JSON.parse`, preserves decoded key spelling, then lets the
  selected strict union close its vocabulary. Swift exact-byte-allowlists decoded
  member names before `JSONDecoder`. Paths/interests use exact UTF-8 byte identity
  without normalization; canonical interest encoding has its own 256 KiB ceiling.
- Keep metadata frames as `u32be bodyLength | strict typed JSON`, with a hard
  256 KiB body cap. Content frames are `u32be bodyLength | u8 tag | u32be
  sequence | tag-specific body`: accepted sequence zero binds full identity;
  data is `u32be offset | raw bytes` with a 128 KiB raw ceiling; terminal JSON
  contains terminal fields only. Content bodies remain universally capped at
  256 KiB and JSON control bodies at 16 KiB. Exact 2 MiB File content is sixteen
  full data frames plus accepted/end; a partial final frame is valid.
- Treat every WebKit chunk boundary as non-semantic. Stage caps precede
  allocation/decode; reference-owned fixed-capacity accumulators avoid COW
  append. One producer owns one `URLSchemeTask` continuation, and any pre-accept,
  cross-stream, gap/duplicate, offset, digest, or post-terminal violation poisons
  without product-state mutation.
- Cap content-producer lifecycle residue at 16 per product session, counting
  active content producers plus pending content lifecycle acknowledgements.
  Cancellation, revoke, disposal, and replacement join one single-flight
  retirement owner for each lease's exact lifecycle nonce. Failed acknowledgement
  retains the residue, and every retry preserves that exact nonce.
- Start producer emission at 128 KiB and benchmark it in packaged WKWebView
  against the existing p99 and <= 8 ms synchronous-slice budgets; change that
  policy only with fresh evidence while retaining the fixed wire ceilings.
- Keep pane/session and metadata-stream open/accepted/error identity epoch-free.
  Closed product kind derives Review/File without a redundant surface field;
  calls, subscription operations, active resync entries, and content opens carry
  their comm-owned `workerDerivationEpoch`. Correlated control acks/errors omit
  it. Same-surface resync entries require one identical epoch; Review/File may
  differ, while conflict rejects the whole resync before mutation. Surface push/
  accepted/lifecycle frames echo the admitted epoch. After a floor advances,
  stale nonterminal frames preserve transport continuity with zero product
  mutation, while cleanup-only frames settle correlation/zero residue. Mixed
  Review/File metadata frames share one contiguous pane-wide `streamSequence`.
- Mint a transferable 32-byte worker-lifetime capability only through typed
  bootstrap. Replacement atomically revokes the old worker's streams and
  leases.
- Keep the scheme handler as an HTTP adapter. Product providers do not run
  through the MainActor semantic IPC dispatcher.

Likely write surface:

- `Sources/AgentStudio/Features/Bridge/Transport/BridgeSchemeHandler*.swift`
- new strict product-session/call/subscription/content-frame Swift types
- `BridgeBootstrap.swift`, `BridgeTransportResourceLeaseRegistry.swift`
- `BridgePaneController.swift` teardown and source-reset coordination
- shared Swift/TypeScript hostile wire fixtures and Bridge scheme tests

RED proof:

- Exact POST body bytes through `httpBody`/`httpBodyStream`; no synthesized
  `Content-Length`; capability-before-body-access; 256 KiB + 1 rejected before
  decode/provider; unknown/extra/cross-wired unions, duplicate raw keys, Kelvin-
  sign key lookalikes, non-scalar strings, and composed/decomposed byte identity;
  no global epoch or redundant surface; exhaustive kind-to-surface mapping;
  epoch-free pane open/accepted/error and correlated ack/error; independent
  Review/File admission floors; per-entry resync epochs; old admitted
  subscription/content terminal cleanup after a newer floor; pane-wide
  Review/File `streamSequence` interleaving;
  atomic interest-delta staging/hash/barrier/reset; exact 128 KiB data and +1;
  exact sixteen-frame 2 MiB segmentation; 1-byte/4 KiB arbitrary fragmentation;
  ingress/relocation/allocation oracle; cross-stream/pre-accept/gap/duplicate/
  offset/digest/post-terminal hostility; abort-causal stop/unregister; the
  16-residue ceiling across active content producers plus pending acknowledgements;
  cancellation/revoke single-flight retirement; exact-nonce retry after failed
  acknowledgement; overflow reserve; resume/snapshot; replacement/reset/restart;
  and zero-residual teardown.
- Epoch-floor RED/GREEN pair: RED fails if stale nonterminal subscription or
  content-accepted/data mutates current truth, or if cleanup is rejected/leaks;
  GREEN consumes stream continuity with zero interests/cache/publication/reset
  mutation and accepts old reset/end/cancel/error cleanup through zero residue.
- Resync RED/GREEN pair: RED fails if cross-surface different epochs are rejected
  or a same-surface epoch conflict partially mutates floors/subscriptions; GREEN
  accepts different Review/File epochs and atomically rejects a same-surface
  conflict before either mutation class.

Ordered S2 gates:

S2a is GREEN from fresh packaged WKWebView plus marker-scoped runtime proof. The
packaged lane accepted exactly 262,144 bytes, collected one warmup plus 100
samples per lane, measured fetch p99 4 ms, Swift admission p99 3.415 ms, and
decode p99 1.737 ms, and proved `stopped -> unregistered -> acknowledged`
cancellation. Marker `debug-observability-oq4s-1783704068-24703` verified the
`bounded_post_stream_abort` path, rejected 262,145 bytes before decode/provider,
recorded four receipts, and left zero producer/task residue. Focused contract/
unit proof or a zero-sample marker alone still cannot close this gate.

1. **S2a feasibility:** packaged WKWebView proves exact bounded POST request
   bytes, capability-first handler admission, actual-body cap before decode/
   provider, split response chunks before completion, and abort-causal URL-
   scheme producer teardown. Missing `Content-Length` is an accepted case, not
   rejection. Exact-cap proof is composite: the packaged WKWebView exact-body
   test supplies cap evidence, while the marker-scoped run supplies runtime/
   telemetry identity; a zero-sample marker run cannot prove the cap alone. If
   actual body bytes cannot be bounded before decode/provider, stop and revise
   the carrier before building the actor.
2. **S2b session core:** actor, digest/replay cache, producer/lease registry,
   terminal reserve, reset/restart, and hostile tests.
3. **S2c scheme adapter:** thin command/metadata/content POST adapter with no
   MainActor product dispatcher or duplicate authority. The current checkpoint
   remains deliberately off-path and unregistered until S2d installs the typed
   capability; it is not a production fallback and cannot independently close G1.
4. **S2d capability install:** typed transferable bootstrap, accepted worker
   instance, and old-capability revoke before replacement acceptance.
5. **S2e lifecycle close:** tracked reload/replacement/teardown awaits producer
   stop, unregister, lease revoke, and terminal acknowledgement. No untracked
   reset task may outlive pane disposal.

Checkpoint:

```bash
mise run test-fast -- --filter BridgeProduct
mise run test -- --filter BridgeSchemeHandler
mise run test-webkit
bash scripts/verify-bridge-product-stream-webkit-feasibility.sh
```

G1 requires the real worker-owned transport: typed call POST, one pane metadata
POST stream with multiplexed logical subscriptions, concurrent per-demand
content POST streams, cancellation, and worker replacement. It proves missing
`Content-Length` succeeds for a bounded body, oversize never reaches decode/
provider, split response frames arrive incrementally, cancellation follows
producer stop/unregister, and teardown leaves zero tasks/leases/post-terminal
frames. The historical resource GET probe cannot satisfy G1.

## Slice S3: Freeze One Pane Worker And The Fulfillment State Machine

Source: R41-R42, R45-R46, R49-R58, R60, R62-R63.

Behavior:

- Define one pane worker session with surface-scoped Review/File clients and a
  single typed contract. The root session scaffold remains off-path until a
  surface cutover; it does not create a second live route.
- Add the worker-only `BridgeProductTransport` facade with constrained generic
  `call`, logical `subscribe`, and AbortSignal-required `openContent`, backed by
  `BridgeProductControlMux`, metadata/binary decoders, and install bootstrap.
  React/main sees only strictly typed domain/pane clients on its port and bounded
  render slices; it cannot import the facade/capability or receive raw content.
- Freeze closed call/subscription/content registry maps and strict Zod unions;
  remove recursive JSON payloads, catch-alls, generic method strings, unknown
  handler values after parse, and feature-local wire shapes. Run one shared
  hostile fixture corpus against the matching strict Swift enums.
- Open exactly one physical metadata stream per pane and multiplex logical
  subscriptions with independent Review/File derivation epochs on it. Each
  demanded descriptor/window/role opens one concurrent independently cancellable
  content POST that does not consume control sequence. Only the shared transport
  module knows product routes or invokes `fetch()`.
- Introduce content-authoritative SHA-256 semantic document/window identity.
  Metadata, cache key, lease, generation, projection, and UI revision are not
  semantic identity.
- Implement desired -> preparing -> published -> queued -> applied -> painted,
  attempt leases, already-applied/already-painted resubmission, monotonic
  dispositions, selected re-demand, `SurfaceSourceEpochReset`, and
  `CommWorkerRuntimeRestart`.
- Implement the post-paint UI-revision fact and `selectionAccepted` response for
  fresh-display/cached-terminal reuse. It reuses painted residency without a new
  publication attempt or disposition.
- Make main snapshot acceptance structural and identity-based. Delete the
  ready-to-loading behavior as part of the later Review cutover, backed now by
  metadata-churn and same-size/different-bytes RED cases.
- Add frame-budgeted patch/disposition apply with selected-first fairness.

Write surface:

- `BridgeWeb/src/core/comm-worker/` contracts/store/runtime/pump
- new pane-session, semantic-identity, fulfillment, and disposition modules
- `BridgeWorkerMarkdownPatch` plus the disjoint comm-owned stateless compute-
  pool port/schema in the shared-contract freeze; S6 owns its implementation
- `bridge-main-render-snapshot-store.ts` and frame-budgeted patch applier
- hostile worker and real-worker contract tests

RED proof includes metadata-only churn retaining ready semantic content,
same-size different bytes rejecting reuse, fresh-display `selectionAccepted`
with no attempt, monotonic receipt retries, one-unacknowledged control admission,
Review/File logical subscriptions sharing one physical stream, concurrent File
content progress without control-sequence advance, strict hostile registry/DTO
rejection, dedicated compile-negative generic pairing proof, and stale worker
denial before provider mutation.

Checkpoint:

```bash
pnpm -C BridgeWeb exec vitest run src/core/comm-worker
pnpm -C BridgeWeb exec vitest --config vitest.browser.config.ts run \
  --project integration-browser src/core/comm-worker
mise run bridge-web-check
```

## Slice S4: Cut Telemetry Onto Its Own Worker

Source: R43, R48-R51, R62, R66.

Behavior:

- Add one optional pane telemetry worker with two dedicated producer ports.
- Mint a distinct telemetry-session capability; product capability reuse is a
  hard rejection. Bind producer identity to its installed port, authenticate
  before body access, rotate/revoke on sidecar replacement, and reject old-port
  traffic.
- Implement sample/control credits, exact producer sequence and loss ranges,
  required-loss proof failure, validation/scrubbing, bounded buffers/outbox,
  idempotent native admission, retry, restart, snapshot, drain, and close
  barriers.
- Map `bridge.telemetry.snapshot` and `bridge.telemetry.flush` to sidecar
  `snapshot` and `drain`; never use `BridgePerformanceTraceRecorder`.
- Delete main/pre-React/comm batching, stringify, fetch, retry, and flush owners
  plus the old telemetry endpoint callers in the same slice. No telemetry
  deletion is deferred to S8.

Write surface:

- new `BridgeWeb/src/core/telemetry-worker/`
- Bridge telemetry producer adapters and app composition
- Swift Bridge telemetry session/admission/validation/projection tests
- static ownership scans and Victoria verifier fields

Checkpoint:

- Telemetry-off constructs no worker or ports.
- Telemetry-on/failure/restart/credit exhaustion/drain-race tests pass.
- Cross-capability/session/producer, capability-before-body-access plus bounded
  actual-body rejection, old-port-after-restart, and product-capability-reuse
  hostile tests pass.
- Product output is identical on/off/failure, while failure is proof-ineligible.
- Marker-scoped Victoria shows no required loss, sequence gap, or missing drain.

## Slice S5: Hard-Cut File View

Source: R41-R49, R52-R53, R58-R61, R63-R65.

Behavior:

- The pane comm worker consumes native File metadata/content streams directly
  and owns rows, search/filter, selection, demand, cache, retry, stale repair,
  refresh, and the canonical UTF-8 prefix.
- File uses only the shared worker `BridgeProductTransport` registries/facade.
  Delete its resource URL parser and feature-specific content `fetch`; adding a
  File kind changes domain contracts/handlers/reducers, not transport mechanics.
- Main receives bounded display patches and forwards one released public Pierre
  window. It does not parse, pad, retry, or own descriptors/content.
- Atomically delete File's native-to-main intake, feature worker factory, FE
  frame protocol/cache/retry owner, loaders, padding, File-specific semantic
  page/DOM handlers, and native/main carrier registration. Classify and remove
  or narrow `file-viewer/state/bridge-file-viewer-store.ts` fields into component-
  local UI intent, the one main render snapshot, or worker truth; it is not a
  Zustand store and must not survive as another product/render authority.

Likely write surface:

- `BridgeWeb/src/core/comm-worker/bridge-comm-worker-file-view-*`
- `BridgeWeb/src/file-viewer/`
- obsolete `BridgeWeb/src/app/bridge-app-native-worktree-file*`
- Swift `Runtime/WorktreeFileSurface/` and resource/lease owners

RED proof:

- Shared Swift/TS UTF-8, CRLF/LF, invalid encoding, NUL/binary, byte/line/both
  truncation, partial scalar, partial final line, empty file, and no-padding
  corpus.
- Hostile refresh/gap/reset/stale/abort cases and real browser/native
  search-select-render journeys.

Checkpoint: focused unit/Swift tests, real-worker browser File View, packaged
native File View, installed-Pierre detachment proof, and a static scan showing
the old File product owners/carriers/direct fetches are compile-dead. The
packaged trace shows one pane-worker identity, one metadata stream, demanded
content streams only, and zero page/native File product relays.

## Slice S6: Prove The Review Engine Off Path

Source: R42, R44, R58, R60-R63 and the retained product journeys.

Behavior:

- **S6a, after S3:** build worker-owned Review package normalization, tree
  indexes, search/facets, projection, selection, visible demand, and stale
  classification without importing Pierre.
- **S6b, after G1:** add semantic manifests/windows, continuation, hunk
  expansion, eviction/re-entry, and bounded markdown compute/sanitize patches
  against only the registry-installed locked Pierre version.
- Build the comm-owned stateless markdown/content compute pool behind the S3
  port/schema. Hostile reset tests prove it cannot reach main or Swift and that
  main receives only bounded `BridgeWorkerMarkdownPatch` values.
- Exercise it through hostile worker/server tests and the released Pierre API
  without connecting a second production Review route.

Write surface:

- worker Review runtime/preparation/pump/window modules and tests
- shared Review wire fixtures
- no root app or current Review production-owner edits in this slice

Checkpoint: 3,420-file O(delta) projection tests plus early/middle/final
checksums across the 100,000-line fixture, stable anchors, no prefix replay,
unsafe markdown corpus, preemption, and 8 ms synchronous-slice ceiling.

## Slice S7: Atomically Hard-Cut Review

Source: all retained Review journeys plus R41-R64.

Behavior:

- Connect Review to the same pane comm worker and direct native product stream.
- Review uses only the same shared `BridgeProductTransport` registry/facade as
  File. Delete its resource URL parser and feature-specific content `fetch`;
  no Review transport/cache/retry mechanism survives outside the shared module.
- Start only after the S5 File compile-dead receipt and S6a/S6b proof receipts.
- Main keeps local selection/viewport/chrome and bounded display residency only;
  the worker owns package/projection/demand/content/continuation truth.
- Route all selection, reveal, scroll, collapse, hunk, markdown, mark-viewed,
  search, filter, and viewport consequences through the worker.
- Delete the Review feature worker factory, native/main intake, canonical main
  package/store ownership, projection worker, package body loader, ready-to-
  loading gates, stale placeholders, main payload reconstruction, receipt-only
  courier, first-window-as-complete behavior, private Pierre traffic, remaining
  product `callJavaScript`/DOM push, post-bootstrap product script-message RPC,
  native/main product relays, shared product router registrations, and extra
  comm-worker creation sites. Route the retained Review semantic IPC methods
  through the S3 typed local-intent seam before deleting their legacy handlers.
- Classify `review-viewer/state/review-viewer-store.ts` fields into component-
  local intent, the one main render snapshot, or worker truth; it must not remain
  a second product/render authority.

Likely write surface:

- `BridgeWeb/src/app/bridge-app-review-*`
- `BridgeWeb/src/review-viewer/`
- shared comm-worker Review contracts/runtime
- Swift Review metadata/provider/resource/stream owners

Checkpoint:

- Repeated cold/warm/metadata-churn clicks never disappear or wedge.
- Deep tree select/reveal, search/facets, collapse, independent rail/CodeView
  scroll, all change kinds, binary/unavailable, markdown, hunk expansion, and
  final-window traversal pass in real-worker browser and packaged WKWebView.
- Static scans show old Review product owners are compile-dead.
- Packaged mode-switch/two-pane/restart/teardown traces show one comm-worker
  identity and one metadata stream per pane, only demanded content streams, and
  zero page/native product relays.

## Slice S8: Audit Semantic IPC And Prove The Product

Source: R48-R51, R62-R66 and the closed semantic IPC mapping.

Behavior:

- Audit all 16 retained Bridge semantic IPC methods against their specified
  native authority, isolated typed local-intent adapter, bounded diagnostic,
  handle probe, or telemetry-sidecar control. File routes were closed in S5,
  telemetry routes in S4, and final Review/shared routes in S7.
- Run zero-result deletion scans. If S8 finds a product/telemetry bypass or old
  owner to delete, the owning cutover failed and returns to S4, S5, or S7; S8
  does not perform cleanup migration work.
- Assert only the shared worker transport module contains product scheme route
  literals or product `fetch()`: Review/File use one facade; no resource GET,
  feature fetch, page relay, script-message product carrier, shim, or fallback.
- Run the full benchmark applicability manifest and product journey matrix.

Closed semantic IPC routing ledger:

| Methods | Owning cutover | S8 zero-result audit |
| --- | --- | --- |
| `bridge.fileView.open`, `bridge.fileView.getContent` | S5 | source initiation enters File worker; content returns handle/metadata only |
| `bridge.diff.load`, `bridge.diff.refresh` | S7 | native source authority -> worker accepted/resynced -> required paint |
| `bridge.diff.selectFile`, `bridge.diff.scrollToFile`, `bridge.diff.expandFile`, `bridge.diff.collapseFile` | S7 | typed local-intent seam -> worker acceptance -> correlated paint |
| `bridge.fileTree.search`, `bridge.fileTree.setFilter`, `bridge.fileTree.revealPath`, `bridge.fileView.showMarkdownPreview` | S7 | typed local-intent seam; no product work on the page/native adapter |
| `bridge.diff.getPackage`, `bridge.diff.renderState` | S7 | bounded read-only metadata/render probes; no raw bodies/store snapshots |
| `bridge.telemetry.snapshot`, `bridge.telemetry.flush` | S4 | telemetry-worker snapshot/drain; no native recorder fallback |

Required proof commands:

```bash
mise run verify-bridge-local-first-browser-benchmark
mise run verify-bridge-local-first-headless
mise run verify-bridge-local-first-native-benchmark
mise run verify-bridge-local-first-performance
mise run bridge-web-check
mise run bridge-web-test
mise run bridge-web-browser-test
mise run bridge-web-build
mise run bridge-web-audit
mise run test
mise run test-large
mise run test-webkit
mise run lint
```

Native evidence uses the standard debug observability launcher, current-worktree
bundle identity, semantic IPC stimuli, and marker-scoped Victoria queries.
Peekaboo proves visible persistence and momentum with PID/window targeting; it
is not the latency oracle.

Raw artifacts live under:

```text
tmp/bridge-local-first-proof/{browser,native}/<run>/<cell>/<launch>/
  attempts.jsonl
  launch.json
  cell-reduction.json
tmp/bridge-local-first-proof/<runtime>/<run>/manifest.json
tmp/bridge-local-first-proof/visual/<run>/
```

Every required cell runs telemetry off and on in both controlled Chromium and
packaged WKWebView. Each launch and pooled cohort must pass. Required telemetry
loss/gaps, wrong/blank/stale/disappeared content, wedges, and main-loop tasks at
or above 50 ms are all zero.

## Requirements / Proof Matrix

| Source obligations | Owner | Required proof and exact floor | Freshness / task fit |
| --- | --- | --- | --- |
| R41, R45-R46 local paint, sliced reads, frame pump | S3/S5/S7/S8 | selection/fresh-display p99 <32 ms; owned main/comm slice <=8 ms; tasks >=50 ms zero; selected first with visible fairness | current raw interaction chain in browser/native; fits surface slice |
| R42, R49-R56 one owner/worker, shared strictly typed transport, courier | G0/S3/S4/S5/S7 | one comm worker/metadata stream per pane; independent Review/File derivation epochs; only shared transport owns three POST routes/fetch; closed TS/Swift corpus; zero main/native relays; Pierre p95 <4/p99 <8 ms | source scan plus packaged protocol/worker identity |
| R43, R66 telemetry isolation, credits, drain | S4/S8 | zero required loss/gaps; on/off/failure product parity; exact drain high-watermarks | current telemetry session/marker; S4 must close before S8 |
| R44, R52-R53, R57, R60-R61 bytes, transfer, Pierre windows, continuation | S1/S3/S5/S6b/S7 | sender detached; queue p95 <16/p99 <32 ms; Review final checksum; File truthful prefix; no clone/prefix replay | registry version equals lock/bundle; installed corpus |
| R47 scalable File projection/apply | S5/S8 | bottom-up prune regression remains linear; frame intake/projection/apply slices <=8 ms | large current File fixture; no duplicate prune task |
| R48, R62 correlated proof | S0/S8 | exactly 84 cells, 252 launches, >=25,200 measured attempts; every launch/pooled cohort passes; failures retained | immutable manifest, HEAD/bundle/PID/fixture/machine identity |
| R58 normalized O(delta) worker state | S3/S5/S6a/S7 | click invalidation O(selected + visible delta), selected preemption, no starvation | subscriber/key counters from current large fixture |
| R59, R64 trust/capability/typed call-subscribe-content/cancel | G0/S2/S3 | epoch-free pane plane; kind-derived surface; same-surface resync epoch agreement; stale nonterminal zero mutation; old cleanup zero residue; contiguous mixed-surface stream; bounded strict POST/frame/data proof | packaged WKWebView plus shared hostile raw-byte corpus |
| R63 semantic fulfillment/reset/restart | S3/S5/S7 | monotonic attempts/dispositions, fresh-display `selectionAccepted`, no stale/blank/disappeared/wedged result | same semantic/window/attempt chain; repeated live clicks |
| R65 canonical File bytes/encoding/lines | S5 | shared Swift/TS literal byte/checksum/truncation oracle | identical corpus/version in both runtimes |
| retained File/Review journeys and 16 IPC methods | S4/S5/S6/S7/S8 | all actions, full 3,420-file/100,000-line Review, mode switch, two-pane, restart, teardown; dev p95 <50/p99 <100, native p95 <100/p99 <200 | current run, early/middle/final checksums and routing ledger |
| no bypass/dual owner; PR ready, no merge | each cutover/S8 | per-slice compile-dead scan; final zero-result audit; review/checks/threads/mergeability | current HEAD, packaged assets, fresh PR head SHA |

## Per-Slice Test Proof

Project proof-layer definitions come from `AGENTS.md`: unit, integration, real
smoke/e2e, native/observability, then PR. Every row is RED before production
edits; execution records failing command/output and later GREEN exit code.

| Slice | Public seam / boundary and invariant | Guard + independent oracle | Exact RED target; GREEN / deferred higher layer |
| --- | --- | --- | --- |
| S0 | proof contract/reducer; every attempt and fixed cell is represented | schema rejects omissions; literal 84/252/25,200 manifest oracle | `pnpm -C BridgeWeb exec vitest run scripts/bridge-local-first-proof-contract.unit.test.ts`; GREEN same plus `--validate-only`; runtime matrix deferred S8 |
| S1 | released Pierre `CodeViewHandle` window API and worker transport | validators reject hostile manifests; literal conformance/checksum/anchor oracle | `AGENT=1 moonx diffs:test -- CodeView.windowConformance.test.ts`; GREEN full S1 Moon/Bun gates; registry install deferred authorized release |
| S2 | product-session actor + call/metadata/content POST routes | paired identity/epoch vectors prove cross-surface-different acceptance, same-surface-conflict atomic rejection, stale nonterminal zero mutation, old cleanup zero residue, and mixed stream order; exact cap/segmentation oracle | `mise run test-fast -- --filter BridgeProductSession`; GREEN focused Bridge + `test-webkit` + packaged 128 KiB incremental/fragmented/abort benchmark |
| S3 | worker-only generic transport facade, mux, identity, fulfillment reducer | closed registries/discriminated transitions reject conflicts; shared TS/Swift fixtures, dedicated `tsc` negative fixture, and semantic traces | `pnpm -C BridgeWeb exec tsc --noEmit -p tsconfig.product-contract.json` plus `pnpm -C BridgeWeb exec vitest run src/core/comm-worker/bridge-pane-comm-worker-session.unit.test.ts`; GREEN core unit + real Worker browser; surface/native deferred S5/S7 |
| S4 | telemetry worker ports + native telemetry session | credit/capability/sequence guards; exact sample/loss/high-watermark oracle | `pnpm -C BridgeWeb exec vitest run src/core/telemetry-worker/bridge-telemetry-worker-runtime.unit.test.ts` + `mise run test-fast -- --filter BridgeTelemetrySession`; GREEN hostile browser/native + Victoria drain; full parity S8 |
| S5 | File worker surface + installed Pierre window + native stream | R65 schemas; literal bytes/hash/line/truncation and DOM text | File RED files `bridge-file-prefix-corpus.unit.test.ts` and `bridge-file-viewer-local-first-cutover.browser.test.tsx` + Swift `--filter BridgeFilePrefix`; GREEN packaged File journey + compile-dead scan; full p99 S8 |
| S6 | off-path Review engine, windows, compute-pool port | schemas reject overlap/stale/cross-port traffic; reference tree/checksum/anchor corpus | RED files `bridge-comm-worker-review-window-runtime.unit.test.ts` and `bridge-review-worker-continuation.browser.test.tsx`; GREEN 3,420-file/100,000-line real Worker proof; production/native deferred S7 |
| S7 | Review surface through one pane worker and semantic IPC | identity/lifecycle guards; DOM/current-window + native frame/checksum oracle | RED `bridge-review-local-first-cutover.browser.test.tsx` + Swift `--filter BridgeProductReviewStream`; GREEN packaged full Review journey + compile-dead scan; full p99 S8 |
| S8 | four authoritative proof tasks and zero-result audits | artifact/routing schemas reject stale/bypass/loss; raw outer-clock/Victoria/DOM oracles | each component `--validate-only` fails stale fixture; GREEN four tasks, full static suites, review and PR gates |

Test public seams are the typed worker contracts, product-session actor, Pierre
public API, semantic IPC methods, and real user DOM/packaged app journeys.
Independent oracles are byte/checksum fixtures, DOM text/window identity,
protocol frame recordings, Victoria sequence/loss queries, and outer-clock raw
attempts. Mock-only assertions cannot close browser/native rows.

## Ownership And Parallelism

- Parent owns shared contracts, root composition, state-machine integration,
  cross-repo version decisions, slice review, and final claims.
- Pierre implementer owns only the Pierre worktree and upstream tests.
- Native implementer owns the product session, scheme routes, bootstrap, and
  Swift tests; root Swift composition returns to the parent for integration.
- Telemetry implementer owns the telemetry-worker directory, Swift telemetry
  session/admission files, and telemetry tests.
- File and Review implementers work only after shared unions freeze. They do
  not edit the same root worker/app files concurrently.
- Browser, observability, and native UI sidekicks own harness lifecycle and
  evidence collection, never product truth or done claims.
- Claude Fable xhigh remains a read-only advisor at the plan and major
  implementation checkpoints. Parent verification accepts or rejects findings.

Each verified slice receives a scoped checkpoint commit. Do not stage unrelated
changes. Run an implementation review after S8, address accepted findings, then
use PR wrap-up to prove checks, threads, comments, and mergeability. Do not
merge.

## Stop / Split Triggers

Stop and return to the owning design/plan boundary if any of these occurs:

- WKWebView requires a page/main product relay for worker traffic.
- WKWebView cannot expose bounded actual POST body bytes before native decode or
  provider work, or cannot incrementally stream/cancel a response.
- A product kind requires generic JSON, an open-ended method registry, a
  feature-owned route/fetch helper, or a second physical metadata stream.
- The native stream cannot cancel and unregister production before ack.
- Pierre requires a fork/private import or transferred buffers do not detach.
- A converted surface still has an old product owner or compatibility path.
- Semantic identity cannot distinguish same-size different bytes without
  metadata churn invalidating unchanged content.
- Required proof cannot retain failures, correlate lifecycle stages, or bind
  artifacts to the current process/package/commit.
- A validation failure is outside this plan's write scope; report it separately
  rather than editing unrelated infrastructure.
