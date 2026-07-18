# Local-First Comm Worker Architecture

Date: 2026-07-09; corrected 2026-07-17
Status: recovery contract; product recovery checkpoints accepted; final sharing and proof remain incomplete.
Extends [performance-demand-lanes.md](performance-demand-lanes.md) R32-R40 and
its Constants Annex. It supersedes only the clauses named under Explicit
Supersessions below.
Parent: [performance-demand-lanes.md](performance-demand-lanes.md)

This file defines the BridgeViewer product, transport, worker-ownership, and
performance boundary, not implementation order. Review and File View each have
one product path and proof set inside one pane-owned comm-worker session.

R32-R40 put content-demand initiative in the browser. FE owns only local render
slices; the comm worker owns protocol, demand, cache, retry, health,
complete-item preparation/residency, and Swift synchronization. A separate
optional telemetry worker owns observability off both interactive loops.

## Evidence Anchors

Committed AgentStudio evidence is pinned to `f1992979`; Pierre evidence is
pinned to fetched `4f94a5e7` and released `diffs-v1.2.12` at `9466c467`.
Mutable or ignored artifacts cannot satisfy durable claims.

- The causal review owns the click/root-snapshot, synchronous File, WebKit
  delivery and native-proof evidence
  (`docs/wip/2026-07-04-cold-architecture-review-bridge-demand-system.md`).
- R32-R40 retains one reconciler, no truncation/parking, one derivation epoch,
  ranked worker admission and separated retention/cache tiers.
- The original product specs retain DiffsHub-class Trees/CodeView UX and
  large-diff obligations. Recovery HEAD `38fe66a` is a UX/test oracle only;
  its obsolete worker, main store, package startup and carrier stay rejected.
- Installed `@pierre/diffs` `1.2.10` exposes complete string-backed items and
  public `addItems`, `updateItem`, `updateItemId`, and `scrollTo`; released
  `1.2.12` preserves that model. No sparse source/window API or transfer-list
  guarantee exists. `renderRange` is post-admission virtualization. This is the
  implementation floor; Pierre repository/package changes are forbidden.

## Normative Product And Success Contract

The worker architecture is a means to the product contract. R41-R70 cannot be
declared complete while Review or File View is functionally wrong, even when an
individual worker, schema, or unit-test seam passes.

The complete product obligations in
`docs/superpowers/specs/2026-06-15-bridge-codeview-trees-viewer.md` and
`docs/superpowers/specs/2026-06-18-bridgeweb-large-diff-fast-loop-spec.md`
remain normative unless this increment explicitly supersedes a clause. This
increment changes transport, state ownership, complete-item hydration representation, and
proof strength; it does not silently delete a user journey.

Review MUST:

- support the 3,420+ file and 100,000-line selected-diff fixture floor;
- start every fresh or source-reset tree with every authoritative directory
  expanded; preserve a user's later collapse across same-source metadata
  appends, while newly streamed directories start expanded;
- preserve deep tree navigation, search, filter/facets, reveal, selection,
  collapse/expand, hunk expansion, added/modified/deleted/renamed files, and
  sanitized markdown presentation;
- keep the file rail and CodeView independently scrollable and responsive;
- use one continuous multi-file Pierre `CodeView` whose ordered projected items
  remain truthfully traversable while selected/visible items hydrate as complete
  supported Pierre items;
- reconcile that mounted Pierre `CodeView` back to the complete authoritative
  order when a same-identity retained instance exposes only a selected-item
  subset; React input counts are not proof of live Pierre membership;
- keep steady-state membership validation O(selected + visible delta) by
  checking changed items, their authoritative neighbors and stable boundary
  sentinels; an exact authoritative `setItems` is reserved for a detected
  mismatch or one mounted-instance reconciliation-policy adoption;
- keep directories, disclosure, search, composed facets, reveal, synchronized
  selection, file/hunk collapse, and early/middle/final real content coherent;
  and
- produce zero blank/wrong items, false adjacency, snapback, stale flash, content
  disappearance, or wedged selections.

File View MUST:

- support streamed tree metadata, search/filter, selection, refresh, stale
  repair, and explicit binary/unavailable states;
- start every fresh or source-reset tree with every authoritative directory
  expanded, without remounting the tree or losing its scroll owner; later user
  collapse remains local until another source reset;
- stream, decode, and assemble the complete selected text file off-main;
- supply one complete supported Pierre item for that selected file, with no
  permanent 2 MiB/10,000-line prefix contract; and
- keep both tree and content painted through sustained deep scrolling, with
  final real content reachable and no fabricated payload, whitespace, or line
  extent.

Loading, empty, binary, unsupported encoding, unavailable, failed, stale, and
superseded are explicit typed states. Loading may not impersonate a real empty
file or carry fabricated source text/extent.

Product traceability:

| Retained journey | Contract in this increment | Required live proof |
| --- | --- | --- |
| normal, guided, and plans/specs Review modes; search and composed status/class/path/language facets | one comm-worker-owned applied projection; local draft/intent remains synchronous | Vitest Browser against deterministic and real-worktree Vite backends plus semantic-IPC packaged-native journey |
| deep tree select/reveal, independent rail/CodeView scroll, collapse, stable header | R41-R46, R56, R61 | correct row/header/content and no blank, snapback, or cross-scroll ownership |
| added, modified, deleted, renamed, binary, unavailable, and markdown items | R44, R59, R61 plus original sanitized-render rules | deterministic content/checksum and unsafe-markdown corpus in browser and native |
| hunk expansion and 100,000-line traversal through the final real hunk | released Pierre complete-item contract in R57/R61 | item/source checksums, stable anchor/header, and final real paint in both runtimes |
| File View tree/search/select/refresh/stale repair and complete selected file | R42-R49, R61, R65 | complete UTF-8/empty/binary/unsupported corpus, deep scroll, and final-content checksum in both runtimes |
| source reset, reconnect, worker restart, mode switch, pane isolation, teardown | R42, R49, R63-R65 | hostile worker/server seams plus real two-pane packaged journey |
| telemetry on, off, and failure | R43, R62, R66 | product parity; telemetry failure is product-fail-open and proof-fail |

Explicit supersessions:

- R32-R39 and R40's retention/cache separation remain normative. This increment
  supersedes every sparse-window, fixed File prefix, or fabricated-extent
  interpretation. Review hydrates complete items by demand; File View assembles
  the complete selected text file. Size alone does not authorize a terminal
  state or silent truncation. If measured whole-item physics cannot meet the
  release gates, implementation stops for user reconvergence.
- The original main-thread Zustand, direct page/native product traffic,
  independently authoritative projection worker, package-first startup, and
  multi-worker ownership descriptions are replaced by R42, R49, R54-R57, and
  R61. Whole-item Pierre publication remains required because it is the released
  public API. Product behavior remains required.

Backend parity is normative:
- deterministic Vitest fixtures and the real-worktree Vite provider implement
  the same dev/test source contract;
- every backend supplies canonical path, rename, file, and directory facts
  sufficient for the comm worker to derive the same hierarchy and ordered
  projection. A depth-zero/flat display adapter or provider-owned projected
  tree is not backend parity;
- one dedicated Vite E2E configuration exercises deterministic and disposable
  live-worktree scenarios through the same pane comm worker, restored React
  components, tree, selection, hydration, continuous CodeView, and actual paint
  disposition path;
- ordinary Vitest unit/integration projects and the Node development verifier
  may support that E2E, but neither is a second Vite E2E authority;
- packaged WKWebView exercises the same product contract through the Swift
  `agentstudio-git` provider; and
- no backend may mount a test/dev-only viewer, bypass the comm worker, or use a
  fixture-only presentation adapter.

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
- complete main-to-Pierre whole-item publication/apply-call corridor is measured
  independently and must fit the owned synchronous-slice and interaction p99
  gates; no unmeasured 4/8 ms transfer guarantee is assumed;
- every owned main/comm synchronous slice has a hard maximum of 8 ms;
- main-thread tasks at or above 50 ms: zero;
- blank/wrong items, false adjacency, wedges, disappearance, stale paint: zero; and
- required telemetry loss, sequence gaps, or lifecycle-correlation gaps: zero.

Performance uses two durable representative workloads, not a Cartesian matrix:
- `controlled_dev_chromium`: disposable real-worktree Vite source, production
  pane worker, restored UI and public Pierre; and
- `packaged_wkwebview`: LaunchServices current-worktree app, native
  `agentstudio-git`, custom-scheme streams and the same product path.
Each runs three fresh launches: one correctness/warmup and two measured. The
measured launches cover every required File/Review family/state cohort with at
least 50 attempts per cohort per launch and 100 pooled. Each measured launch
and pooled cohort pass nearest-rank p95/p99 per family/state; states never pool.
Report the maximum launch percentile, never its average. Any correctness
failure remains an R62 sample and fails the workload.
Performance telemetry is required and non-lossy. One fail-open journey per
runtime covers telemetry disabled/unavailable without duplicating performance.
Report startup/cold-package count and maximum, not interaction p99. Memory
records settled baseline, workload peak and post-close/drain state attributed
to shared construction, pane bindings, worker/Pierre copies, in-flight reads
and draining tombstones.
`surface` means stimulus -> painted endpoint; required families/states run
inside each representative journey rather than independent benchmark cells.
| Required family | Stimulus -> endpoint | Required source/cache states |
| --- | --- | --- |
| Review selection feedback | Review rail select -> Review rail chrome/selected placeholder | fresh display, worker cache, cold miss |
| Review selected readable | Review rail select -> Review CodeView readable | fresh display, worker cache, cold miss |
| Review terminal availability | Review rail select -> Review CodeView terminal | cached terminal, cold terminal |
| Review rail scroll | Review rail gesture -> rail motion + correct rows | resident rows |
| Review CodeView scroll | CodeView gesture -> motion + matching real item content | resident item, hydration miss |
| File selection feedback | File rail select -> File rail chrome/selected placeholder | fresh display, worker cache, cold miss |
| File selected readable | File rail select -> file content readable | fresh display, worker cache, cold miss |
| File terminal availability | File rail select -> typed binary/unsupported/unavailable/failure | cached terminal, cold terminal |
| File rail scroll | File rail gesture -> rail motion + correct rows | resident rows |
| File content scroll | file-content gesture -> motion + correct complete-file rows, including final content | resident complete item |

No required family/state is `not_applicable`; exploratory families are report-only.
Family/state invariants cannot pool; one action may emit correlated samples.
Thresholds are floors and cannot weaken without explicit user agreement.

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
  owns: local UI intent/ephemera, bounded display copies,
        restored Trees/CodeView adapters, frame-budgeted DOM apply,
        whole-item Pierre reconciliation ledger, render dispositions
  exposes: surface-scoped intent facts and disposition receipts
  forbidden: Swift product traffic, protocol/session truth, source-byte cache,
             freshness/projection/demand/retry/residency truth,
             telemetry batching, source fetching or body assembly

ONE PER-PANE COMM WORKER
  owns: Review/File product sessions, surface-scoped stream/epoch/sequence,
        accepted metadata/projection/selection, demand, byte/complete-item cache,
        residency, retry/backoff, availability, health, complete-item assembly
  exposes: bounded keyed display patches and complete ready items to main;
           product requests/streams to Swift
  forbidden: DOM work, telemetry pipeline work, FE/native fallback ownership

Swift product server
  owns: synchronous pane product-admission epoch, provider/source authority,
        transactional Review publication, sourceGeneration, metadata/content
        service, product scheme endpoints, stream production/admission
  exposes: disposable pane-scoped call/metadata/content POST service

Swift Review publication boundary
  owns: one active plus optional pending package/descriptor-authority snapshot
        per pane, atomic commit/rollback, dirty/fresh state
  forbidden: transport-subscription, cache, provider-I/O, or UI-position ownership

Swift BridgePaneActivityCoordinator
  owns: canonical pane activity from workspace/pane/tab/window/app facts; exposes
        synchronous activity transitions to product admission and Git scheduling
  forbidden: package, cache, presentation-position, or Git-execution ownership

Swift BridgePaneProductMetadataCoordinator
  owns: subscription/producer install, uninstall, pacing, and frame delivery
  forbidden: package, descriptor, cache, freshness, or presentation authority

Swift Review content loader/cache actor
  owns: provider loading/streaming, validation, in-flight coalescing, bounded cache
  forbidden: canonical package/descriptor authority or synchronous pane admission

Swift worktree product construction coordinator
  owns: application-scoped worktree freshness, immutable authority-free File
        snapshots and Review templates, exact-key single-flight, consumer leases
  exposes: generation-neutral artifacts each pane rebinds to its own authority
  forbidden: pane/session/source/publication identity, delivery, presentation,
             Git-slot custody, comm-worker state, or heavy work on its actor

Swift Git read execution
  owns: worktree-keyed foreground/background admission plus separately bounded
        metadata/content native-read capacity and true-completion/draining custody
  forbidden: MainActor work, pane presentation, or one global serial Git actor

main producer port + comm producer port
  -> OPTIONAL PER-PANE TELEMETRY WORKER
       owns: telemetry validation, credits, buffer, bytes, shedding, batching,
             encode, sequence, retry/outbox, telemetry scheme POST
       forbidden: product commands/content/cache/demand/health authority

main presentation adapter -> Pierre public complete-item API -> Pierre/Shiki workers
  main is an unavoidable whole-string/object adapter boundary;
  Pierre owns item records, layout, ASTs, render/highlight runtime, and viewport writes
```

The comm worker owns separate worker-local vanilla Zustand store instances for Review and File View. React/main owns neither store after cutover and uses typed worker RPC lifecycle helpers plus non-Zustand
render-slice hooks for frame-critical display copies. The synchronization boundary is typed RPC/DTO messages, not store mirroring: no Zustand snapshot, query/cache entry, store action/function, class instance,
DOM object, `AbortController`, or other non-cloneable local state shape may cross the boundary.

Exactly one `BridgePaneCommWorkerSession` exists per Bridge pane and survives Review/File mode mounts and switches. Review and File View are surface-scoped clients, not worker factories. Shared transport, session,
sequence authority, ranked preparation scheduling, and admission/cache policy remain worker services; each surface store owns its independent source/stream/`workerDerivationEpoch` context. One surface reset or
complete manifest must not prune, invalidate, or supersede the other surface's truth.

## Truth Ownership Tables

Every datum has exactly one truth owner.

Identity lineage is split into semantic, UI, worker, and native planes:

| Value | Mint | Validate | Reset | Observe |
| --- | --- | --- | --- | --- |
| `paneProductAdmissionEpoch` | Swift pane synchronous gate | every native product request before work and after each suspension | pane close increments and permanently closes admission | native lifecycle tests and zero-residue trace only |
| active/pending Review publication | Swift Review publication coordinator | package, descriptor authority, pane presentation, and metadata commit as one transaction | success retires active A after B commits; failure discards B; close revokes both | bounded identity/status facts; never a transport-owned package snapshot |
| pane activity (`foreground | loadedHidden | dormant | closed`) | per-pane `BridgePaneActivityCoordinator` from native workspace, pane residency/controller, tab/arrangement/drawer, window, and app facts | Swift pane admission and Git scheduler | native fact transition only; worker/browser cannot mint it | surface-scoped updating chrome and native transition proof |
| `sourceGeneration` and metadata lineage | Swift/native provider source authority | Swift rejects stale source requests; worker treats it as source fact, never as worker cache epoch authority | Swift rotates on accepted source change, resets metadata stream/gates, and revokes stale handles/admitted work | comm worker subscriptions, server seam, native proof |
| `semanticDocumentRevision` | comm worker from algorithm-tagged content digests and document kind/ordered roles | worker and Pierre item/publication validation | changes only when semantic source content changes | display cache, complete-item residency, proof oracles |
| `uiIntentRevision` | FE, monotonic per surface | comm worker accepts/supersedes intent and echoes the accepted value | surface remount/page session reset | FE render copies and worker intent receipts only |
| `workerInstanceId` | Swift/native, freshly for each comm-worker lifetime | Swift product session and main reset barrier | every comm-worker restart | product frames, reset proof, diagnostics |
| `workerDerivationEpoch` | comm worker per surface/source context | worker stamps demand, fetch, cache admission, and publication; Swift validates new admission and echoes it on admitted surface push/lifecycle frames | worker source reset/resync; never minted by main | worker tests and correlated proof |

`semanticDocumentRevision` and its item/publication identities EXCLUDE metadata/package
revision, descriptor retouch, resource lease/cache key, sourceGeneration,
stream/request sequence, worker instance/derivation epoch, active surface, projection mode,
and UI-intent revision. A render-affecting option has its own
`renderSemanticsRevision`; its replacement is atomic and the prior readable
item remains visible until the replacement paints. Transport churn may revoke
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
| pane product admission | Swift synchronous gate per pane | native call/metadata/content entry points and post-await commit guards | pane creation opens one epoch; teardown synchronously closes it before producer/telemetry drain | none; closed panes cannot reopen | loaded-hidden remains open but reduced; closed rejects immediately |
| active/pending Review package and descriptor authority | Swift Review publication coordinator per pane | pane presentation, metadata source, Review content admission | stage isolated B beside readable A -> atomically commit B before any worker-visible B -> retire A after worker observation/lease settlement | pre-commit failure discards B; post-commit delivery retries B and never rolls back to A | retained while loaded-hidden; dormant has no package; close revokes active/pending |
| native pane activity and package freshness | native workspace/pane lifecycle plus Review publication coordinator | Git admission, refresh coalescer, surface updating presentation | visibility transitions; filesystem events mark loaded-hidden package dirty | foreground performs at most one latest refresh; dormant cold-loads once activated | inactive surface never shows another surface's updating state |
| worktree freshness and shared construction artifacts | application-scoped worktree product construction coordinator | pane File/Review binders | canonical invalidation advances one worktree epoch before pane fan-out; exact semantic keys single-flight immutable construction | stale completion is discarded; one latest foreground request rebuilds; zero consumers drop payload and retain only required draining custody | loaded-hidden retains its pane binding and dirty fact but initiates no refresh |
| Bridge pane attendance recency | native workspace runtime | state-aware worktree command resolver | successful pane attention updates one runtime-only monotonic fact | missing pane removes its fact; no persistence or product authority | default open chooses the most recently attended matching pane |
| Git read permits and physical native slots | application-scoped keyed Git scheduler plus operation-class executor | Swift Review pipeline/content loader | foreground/background ranked request; bounded metadata/content lanes | logical timeout/cancel leaves running native slot draining until true return | loaded-hidden starts no refresh/body work; dirty fact is retained |
| `streamId` | comm worker | FE diagnostics, Swift validation | worker opens/reopens source session | worker/server resync on gap or unhealthy | retained, never FE-writable |
| `sourceGeneration` / metadata lineage | Swift/native | comm worker, server tests | native accepted-source transition | native reset/reopen or unhealthy | native may continue metadata rules; FE sees no protocol state |
| `semanticDocumentRevision` / semantic item identity | comm worker from canonical content descriptors/hashes | display cache, Pierre item, proof | semantic content or deterministic item-role change only | metadata/producer/transport churn revalidates without demoting unchanged ready content |
| `uiIntentRevision` | FE local surface | comm worker | every local selection/mode/filter intent | latest-wins worker acceptance/repair | retained per mounted viewer; grants no protocol authority |
| `workerInstanceId` | Swift/native pane-session bootstrap | main/worker/Swift | every worker creation | reset barrier cancels prior-instance work | one active instance per pane |
| `workerDerivationEpoch` | comm worker, scoped by surface/source context | FE diagnostics, Swift freshness echo, worker tests | worker accepts sourceGeneration/stream tuple | epoch reset clears derived worker truth for that context | retained per pane worker; inactive foreground work demotes/aborts |
| control/stream sequence | control: comm worker per pane/worker; physical metadata: Swift per pane stream; logical subscription: Swift per subscription | opposite endpoint | accepted send order | duplicate/gap/reset rules in R64 | inactive subscriptions retain their sequence; one physical sequence spans Review/File |
| staleness classification | comm worker | FE health/render slices | worker validates source, stream, epoch, and sequence | reset-required -> reopen or unhealthy | inactive stale results cannot mutate active UI |
| content-demand membership | comm worker reconciler | worker executor/cache | worker reconciles selected/viewport/hover/cache facts | re-derive every fact change; no parked membership | inactive selected becomes demoted/aborted, not foreground |
| content bytes / byte cache | comm worker | worker decode/assemble/diff/item preparation | worker `BridgeProductTransport.openContent()` POST | retry/backoff or unavailable slice | retained by worker residency policy; not active foreground |
| projection, hierarchy, and ordered item manifest | comm worker from accepted metadata plus query/facet intent | bounded FE display copies | revisioned projection intent -> deterministic worker kernel -> accepted projection patch | stale result discarded; latest accepted intent reprojects | retained while File is active; never main-canonical |
| complete ready item | comm worker produces; FE adapter owns one bounded render copy; Pierre owns applied item | restored CodeView adapter | complete-item publication keyed by source/item/semantic/render/publication identity | stale publication rejected; current desired item re-demanded | selected/visible protected by worker residency policy |
| paint-ready rows/chrome/extents | comm worker produces; FE slice store owns current render copy | components | bounded keyed worker slice update | stale slice replacement or explicit loading/unavailable/error slice | inactive copies may persist but cannot overwrite active mode |
| selected UI intent, `uiIntentRevision`, and selected display copy | FE local slice | comm worker as fact input | synchronous click/keyboard/programmatic mutation | worker accepts/supersedes by UI revision; never mints worker freshness | each mounted viewer retains local selection memory |
| accepted selected product identity | comm worker, scoped by surface | demand/cache/protocol logic; FE receives display copy | worker accepts a current UI intent under its source context | stale/reset/superseded intent re-derives; main never mints `workerDerivationEpoch` | inactive selection retains memory but has no foreground authority |
| `activeSurfaceUiIntent` | FE app shell | comm worker | local Review/File switch with UI revision | worker acceptance/repair | retained local shell fact |
| accepted `activeSurface` | comm worker | ranked demand/protocol contexts; FE display copy | worker accepts current surface intent | demote/abort inactive foreground and echo repair | only accepted surface has foreground authority |
| `reviewProjectionMode` | comm-worker Review projection state | FE mode control/display slice | worker accepts normal/guided/plans-specs intent | deterministic re-projection; never changes active surface or `workerDerivationEpoch` | retained while File is active |
| `viewport` / rendered range | FE virtualizer slice | comm worker reconciler | rAF/idle-coalesced viewport publication | next viewport fact supersedes; worker re-derives | inactive viewport may be retained but does not create foreground demand |
| `expanded` / collapsed rows | FE local slice | comm worker for visible derivation | fresh/source-reset trees expand every authoritative directory; user toggle writes local UI fact; same-source appends preserve retained collapse and open new directories | source reset clears prior disclosure intent, expands the replacement source and drops invalid row ids; worker publishes availability repairs | retained per viewer until source reset; never inferred from selected-item reveal |
| viewed marks | Swift/native viewed-file command authority | FE render slices, comm worker ack tracking | FE sends write intent through worker to Swift | Swift ack or retry/unhealthy; worker emits ack health slice | inactive mode may queue intent only through worker, never direct native write |
| diff status | Swift/native Review metadata source | FE render slices, comm worker health | revisioned product metadata stream through worker | failed publication rolls back or resets/re-emits active package | retained as last known health; dirty/stale status marked explicitly |
| command acks | comm worker | FE health/render slices, Swift request handlers | worker correlates requests/intents to Swift responses | timeout/backoff/retry or unhealthy | inactive acks may settle but cannot update active selection/content |
| render disposition / fulfillment | main mints structural disposition; comm worker owns fulfillment state | demand reconciler, FE diagnostics | main reports queued/applied/painted/rejected/superseded for a worker item publication | missing/rejected/superseded receipt keeps current selected/visible demand live and re-derivable | inactive receipts may settle but cannot create foreground demand |
| product connectionHealth | comm worker | FE health chrome, Swift diagnostics | worker observes bootstrap, product fetch/stream/delivery failures | reconnect reset, source reopen, or unhealthy slice | inactive mode shows retained health only; no foreground retries |
| write intents | FE creates; comm worker owns queue/dedupe | Swift command handlers, FE ack slices | local intent -> worker queue -> Swift command | worker retries/backoff or fails visibly; no direct FE->native bypass | inactive writes are demoted/queued by policy or rejected visibly |
| telemetry queue / batch sequence / retry outbox | optional telemetry worker | Swift telemetry endpoint, proof tooling | compact samples arrive on port-bound main/comm producer ports | bounded credits, reserved loss summaries, proof failure on required loss | worker survives mode changes; no worker when telemetry is disabled |
| native product metadata production | Swift publication/source owners | comm worker subscriptions | active package -> delivery-only metadata coordinator | rollback active package, reset, reopen, or unhealthy | retained package outlives a worker stream; loaded-hidden starts no refresh |

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
| fresh paint-ready cache hit for the semantic selected/item identity and validation lease | readable selected complete item | treating a later worker confirmation as the first paint |
| cache miss for normal content | selected identity, selection chrome, and protocol-free loading/availability placeholder keyed to the new selection | claiming selection highlight alone satisfies click-to-first-visible-content |
| unchanged semantic identity with stale transport validation | retain readable content with explicit stale connection health until revalidated; do not count a fresh hit | converting metadata/epoch churn into loading or readable success |
| different semantic identity | no old content; render the new selected identity plus loading/stale placeholder | painting old readable content, even briefly |
| binary, unavailable, unsupported encoding, or persistent non-size failure | explicit terminal state keyed to the selected identity | indefinite blank panel, old content, or readable success sample |

R41 defines separate success events:

| Metric | Start | End | Loading counts? |
| --- | --- | --- | --- |
| `local_selection_feedback` | trusted committing event timestamp, or outer control clock before IPC | selected identity/chrome and either matching content or an honest selected placeholder have painted | yes, as feedback only |
| `fresh_warm_cache_readable` | same authoritative action start | current readable content from matching semantic/item/render identity has painted | no |
| `selected_readable_content` | same authoritative action start | current readable selected complete item has painted after worker/Pierre/apply lifecycle | no |
| `selected_terminal_availability` | same authoritative action start | current explicit binary/unavailable/failure state has painted | terminal state only; never reported as readable |

Selection chrome or a loading placeholder may satisfy local feedback. It never
satisfies readable-content latency. A fast placeholder cannot launder a late or
never-completing content lifecycle into a passing sample.

### R42. Every datum has exactly one truth owner.

One pane-owned comm worker is the single authority for Review/File product
protocol, accepted selection, surface-scoped stream/epoch/sequence, staleness,
cache/demand/retry/complete-item residency, and reconnect state. Review, File
View, active mode, and Worktree/File RPC are clients of that worker. Across
File -> Review -> File, no replacement worker is created, every product request
retains one nonempty pane/worker identity pair, and main product egress is
limited to one-shot bootstrap.

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
surface, semantic document/projection/item, publication id, and attempt id;
source generation/`workerDerivationEpoch` validate its envelope and interaction id only
correlates observation. Rejected/superseded/missing receipts keep current demand
re-derivable; telemetry is never the control-plane ack.

A fresh display hit reuses an existing worker-issued painted residency and
validation lease. FE paints first, then MUST send the selection/UI revision;
the worker returns `selectionAccepted` with the reused publication id and no new
publication attempt or disposition. That acknowledgement closes the control
interaction but cannot move the already-recorded readable endpoint. An expired
lease is stale-display, not a fresh hit.

Availability is monotonic for one semantic document/item identity:

```text
absent -> loading -> ready | unavailable | failed
```

`ready -> loading` is forbidden. Only a changed semantic document/item
identity may begin at loading. A metadata/source-generation/lease/stream/worker
epoch or presentation retouch does not mint that identity and cannot demote
ready. Main validates structural envelope/barrier/identity shape and applies
worker transitions; it must not compare route-local descriptor/cache/presentation
keys and synthesize loading. A render-semantics replacement keeps the prior
ready item until the replacement atomically paints.

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
and `postMessage` a compact typed sample. The sole retention exception is the
R66 pre-ready spool: each producer may retain required compact-sample bodies
only before its first matching `producer.ready`, within the native-owned
per-producer count/byte limits, and may calculate only the encoded size needed
to enforce that byte limit. Optional samples and required overflow retain no
body. After the first matching ready, producers must not buffer full samples,
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

Percentiles can satisfy R41-R69 only from non-lossy required event streams.
Lossy telemetry runs are debugging aids, not performance proof.

### R44. Content bytes stream to the worker, not the main thread.

Source bytes are streamed by the comm worker through its worker-local
`BridgeProductTransport.openContent()` facade. The comm worker owns streamed
byte accumulation, strict decode, complete File assembly, complete Review
file/diff assembly, semantic hashing, cache admission, freshness, residency,
and retry. It may chunk or offload compute, but it does not publish a ready
Pierre item until the selected File or selected/visible Review item is complete
for the supported Pierre type.

Main never owns the canonical byte cache or performs source fetch, decode,
classification, line slicing, diff construction, retry, or residency decisions.
The unavoidable final adapter boundary is one complete string/object item from
the comm worker into main and then Pierre's public whole-item API. Main may
retain only the bounded presentation copy and reconciliation facts required by
the mounted viewer. Because Pierre accepts strings/objects and posts whole
requests without a transfer list, R44 promises neither detachment nor zero-copy;
R57 requires measurement of publication bytes, duplicate lifetime, retained
heap, main-thread work, and p99.

This extends R29's worker-backed content-cache requirement and R39's
worker-boundary rank requirement
(`docs/specs/bridge-viewer-transport/performance-demand-lanes.md:680`,
`docs/specs/bridge-viewer-transport/performance-demand-lanes.md:261`).

R44 bans the copy-count/load-ceiling class where whole frames and file journeys
cross too many serialize/validate/copy surfaces
(`docs/wip/2026-07-04-cold-architecture-review-bridge-demand-system.md:69`).

Worker fetch outcomes:

| Outcome | Worker state | FE slice | Re-demand rule |
| --- | --- | --- | --- |
| success, current epoch | bytes enter worker cache; complete-item assembly/diff preparation may continue | keyed loading, ready-item, or availability patch | membership remains until matching `painted` disposition or explicit non-size terminal state if still selected/visible |
| abort from supersession or demotion | in-flight slot frees; no cache write unless completion was already fresh | no error for speculative/nearby; selected may show loading for new identity | reconciler re-derives from current facts |
| transient failure | executor records delivery-failure fact and bounded backoff | health/loading slice with retry state, no FE-owned retry | worker re-demands from membership after backoff |
| persistent non-size failure | worker records terminal availability for current semantic identity | explicit unavailable/error slice keyed to selected/visible identity | membership remains worker-owned; retry only after source/fact reset policy |
| complete item exceeds one compute slice or transport frame | continue bounded stream/assembly or offload subordinate compute while preserving desired membership | honest typed loading; already readable items remain readable | size alone never becomes terminal; no partial item is published as ready |
| measured complete-item heap/main-thread/p99 stop line fails | preserve explicit non-ready diagnostic state and fail the release gate | no fabricated content, silent cap, or false readable state | stop implementation for user reconvergence; do not weaken proof or modify Pierre |
| stale sourceGeneration or workerDerivationEpoch | discard result, count stale drop | no stale content; health slice if user-visible | epoch reset/reconnect drives fresh demand |
| reconnect reset | clear source-bound in-flight/cache memberships as required by epoch reset | connection health/loading slices | worker rebuilds membership from latest FE facts and Swift source |

FE receives render and health slices only. Fetch membership, backoff, retry,
and re-demand are worker facts; FE must not park or restart content demand.

The production worker bootstrap is session-only: pane/session identity, policy,
initial mode, and transferred ports. Main-supplied rows, descriptors, content
metadata, render semantics, telemetry configuration, `reviewSourceUpdate`, and
`fileViewSourceUpdate` are forbidden product bootstrap or update payloads.
Source truth arrives through worker-owned Swift product streams.

Review body hydration is item-granular. Viewport and selection facts let the
worker request, assemble, publish, receive disposition for, and protect complete
selected/visible items across the projected continuous document. Treating a
first 400-line prefix as the fulfilled item is a contract violation.

File View assembles the complete selected text file before ready publication.
Padding a partial payload toward metadata `totalLineCount`, publishing a prefix
as complete, or using metadata to fabricate whitespace/layout height is
forbidden. Total line count remains metadata until verified against complete
decoded content.

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

Every keyed content/display slice includes the worker-issued semantic document,
item, projection, and publication identity plus its structural transport envelope. Source generation,
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
ready entries. Selected/current-item entries promote first; remaining deferred
entries promote in frame-budgeted chunks through the same ranked pump.

The production constants must live in `AppPolicies` or the BridgeWeb policy
module that mirrors `AppPolicies`; tests and verifiers assert observed behavior
against those constants, not duplicated literals. Required policy classes:

| Budget | Class | Proof |
| --- | --- | --- |
| selected apply time/unit cap | execution | selected latency histogram and per-frame applied-unit counter |
| visible non-selected apply time/unit cap | execution | visible apply progress counter increases under selected churn |
| deferred promotion time/unit cap | execution | pause release advances selected/current-item first and drains remaining deferred entries across multiple frames |
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

Each item publication produces at most one disposition transition of each kind.
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

File View frame intake is covered by the apply-pump contract. A permanent
red-first regression MUST reproduce sustained deep tree/content scrolling and
prove both surfaces remain painted through final complete-file content against
an independent source oracle; shallow nonzero metrics cannot satisfy it.

### R48. Proof seams match the runtime boundaries.

Proof preserves boundary honesty:

| Seam | Proves | Cannot prove |
| --- | --- | --- |
| FE with hostile fake worker | synchronous local intent/paint, keyed subscriptions, no FE protocol authority, frame-budgeted apply under delayed/reordered/dropped/duplicate/never-resolving replies | real worker scheduling/clone cost, Swift/WebKit transport, packaged paint |
| comm worker with hostile mock server | stream/epoch/sequence/freshness, demand/backoff, complete File/Review assembly, disposition fulfillment, reset/reconnect under slow/stale/oversized/failing input | DOM paint, WebKit run-loop behavior, Swift provider correctness |
| headless Swift with recorded worker traffic | source authority, metadata/content framing, admission, capability, cancellation, reset, telemetry POST | FE slices, worker cache policy, WebKit delivery, user paint |
| Vitest Browser real workers | restored UI with deterministic fixtures AND real-worktree Vite source; one comm worker and pane/worker identity across File -> Review -> File; bootstrap-only main product egress; worker closure; whole-item/source-to-DOM/motion/long-task/p95/p99 | native scheme/Swift admission, packaged assets/process identity, WebKit momentum, Victoria ingestion |
| telemetry worker hostile seam | producer binding, credit/loss/gap, retry/outbox, restart, drain/close | packaged scheduling isolation |
| packaged current-worktree WKWebView | Swift `agentstudio-git`, custom-scheme worker streams, cancellation/resync, process/bundle identity, real paint/momentum, telemetry on/off | nothing below may substitute for it |

Victoria-backed proof remains required for internal performance samples and
telemetry admission. If direct worker fetch/streaming fails packaged proof, stop
and redesign the native carrier; no main-thread product relay is admitted.
Existing R32-R40 seams remain required
(`docs/specs/bridge-viewer-transport/performance-demand-lanes.md:277`).

## Channel Topology And Typed Contracts

### R49. The topology has three product channel families plus one telemetry sidecar.

The comm worker named here is the single pane-owned product worker in R41-R69.
Every ordinary Review/File web-to-Swift edge originates in that worker. The
telemetry worker is an explicit observability-plane exception and cannot carry
product state or commands.

Existing compatibility type names may retain `Server`, but every normative
`server worker` reference means this same comm worker. No second server/product
worker exists.

| Channel family | Contract | Required payload shape |
| --- | --- | --- |
| main <-> comm worker | one typed RPC/event protocol over the pane-owned `MessageChannel`; all messages are surface/session scoped | UI intents carry UI revision; bounded replies/keyed slices, complete ready-item publications, health, dispositions/reset barriers; no store snapshots or main-minted `workerDerivationEpoch`/sequence |
| comm worker <-> Swift product server | one worker-owned typed product transport over custom-scheme POST bodies and streamed responses | capability-only privileged header; typed call/subscription/content bodies; in-band identity, generation/epoch/sequence, lengths, checksums, acks, resets, and health |
| main <-> Pierre workers | Pierre public complete-item API exclusively, through one shared presentation adapter | complete worker-prepared supported item, identity/version/cache key and bounded reconciliation facts; no source fetch, private Pierre worker traffic, sparse protocol, or transfer guarantee |
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
file/feature. Each demanded descriptor/item/role gets one independent bounded,
cancellable `openContent()` POST response. Content is not eager or multiplexed
with metadata, avoiding head-of-line blocking.

Provider implementations stop behind this product transport boundary.
Deterministic Vitest fixtures and the real-worktree Vite provider feed the same
comm-worker protocol in browser proof; the packaged Swift provider feeds the
same contract using `agentstudio-git`. Provider-specific source acquisition may
not create a second viewer, adapter, projection owner, or hydration path.
`agentstudio-git` is the exclusive production git backend for the Swift/native
Bridge path. TypeScript may invoke CLI `git` only inside explicitly scoped Vite
development or test-fixture utilities; CLI `git` and Worktrunk are forbidden in
production Bridge protocol, source-adapter, and content plumbing.

Direct worker streamed responses are the decided Swift product mechanism.
`WKScriptMessage`, `callJavaScript`, DOM-event intake, page-owned scheme relay,
or feature-owned fetch helpers are rejected production alternatives because
they restore main or a second module as a sequence/backpressure participant. If
direct worker streaming cannot pass native proof, stop and redesign R44/R49.

Direct page/native exceptions are limited to one-shot identity/capability/port
bootstrap, static assets, and typed diagnostics/programmatic-control ingress
that invokes the same FE local-intent seam as user input. They carry no product
egress, intake, cache, demand, retry, acknowledgement, or backpressure traffic;
every product consequence still follows main -> pane comm worker -> Swift.

The `WKScriptMessage` / `__bridge_command` RPC plane and direct main-owned product
scheme callers are compile-dead. Content worlds remain only for bootstrap
isolation and typed control/probe injection.

A future domain such as comments adds closed registry cases, a native handler,
and a worker reducer; it adds no transport route/fetch/cache/retry/IPC pathway.

The retained semantic Agent Studio IPC surface has this closed mapping.
External IPC never exposes raw WebKit evaluation. An internal typed
page-control adapter may inject one bounded command into an isolated content
world, but it is async, validates its result, invokes the same FE local-intent
seam as the corresponding user action, and returns only the bounded typed
result named below.

| External method(s) | Authority and product carrier | Completion and returned data |
| --- | --- | --- |
| `bridge.diff.load`, `bridge.fileView.open`, `bridge.diff.refresh` | native source authority initiates or rotates the source; the resulting source fact/product flow enters the pane comm worker and never becomes a native/main product relay | correlated worker `sourceAccepted`/`sourceResynced` plus the method's required post-paint state; bounded pane/source identity and outcome only |
| `bridge.diff.selectFile`, `bridge.diff.scrollToFile`, `bridge.diff.expandFile`, `bridge.diff.collapseFile`, `bridge.fileTree.search`, `bridge.fileTree.setFilter`, `bridge.fileTree.revealPath`, `bridge.fileView.showMarkdownPreview` | typed native control -> isolated page-control adapter -> the same FE local-intent function used by pointer/keyboard input; every subsequent demand, command, content, acknowledgement, retry, or write goes main -> comm worker -> Swift as required | the action's declared worker acceptance plus correlated post-paint completion when it changes visible state; bounded ids/status/reason only |
| `bridge.diff.getPackage`, `bridge.diff.renderState` | read-only bounded diagnostic/probe projection; never product mutation, subscription, cache authority, or content carrier | bounded metadata, health, identity, counters, and render facts only; no package snapshot, raw body, source text, or worker-owned store state |
| `bridge.fileView.getContent` | read-only content-handle probe against native package metadata; never a body-read path | bounded handle, semantic/item metadata, availability, and MIME facts only; no body bytes or source text |
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
| main -> Swift ordinary Review/File product traffic by any carrier | only bootstrap/assets and native-to-FE local-intent controls are exempt; no FE/main-to-Swift product control is exempt | import/architecture lint, structural carrier scan, packaged protocol trace |
| Swift product push/intake -> main | `callJavaScript`, DOM/content-world/page relays restore main protocol ownership | Swift/TS structural scan plus packaged trace |
| more than one pane comm-worker instance or feature-owned session | fragments protocol/cache/recovery truth | lifecycle type/API boundary, real-worker identity test, packaged identity trace |
| comm worker -> DOM/render | DOM materialization remains main/Pierre-owned | worker import lint and build boundary |
| comm-owned compute pool -> main/Swift | stateless compute returns only to comm worker | disjoint ports/types and hostile reset test |
| Pierre workers -> demand/fetch/protocol initiator | Pierre is render compute only | public-API types, source scan, worker integration test |
| main or comm -> telemetry endpoint/buffer/outbox | compact samples go only to telemetry worker | import lint, structural scan, telemetry failure test |
| telemetry worker -> product endpoint/state | observability has no product authority | disjoint schemas/routes and hostile worker test |
| any untyped message | bypasses schema/version/validation | closed discriminated unions, exhaustive switches, cross-runtime fixture corpus |

### R52. Main is a bounded complete-item presentation adapter.

The sole standard text/diff content route is:

```text
Swift source bytes -> comm-worker canonical byte cache
  -> comm-worker complete-item assembly and identity
  -> BridgeWorkerPierreItemPublication -> main presentation adapter
  -> released Pierre addItems()/updateItem() whole-item API
  -> Pierre-owned worker/layout/DOM apply -> BridgeRenderDisposition
```

Main validates only the publication envelope and current presentation floor,
reconciles it by stable item id/version/cache identity, and calls the supported
whole-item API. It does not fetch, decode, diff, truncate, reclassify, retry, or
decide residency. It may hold the current bounded render copy and a small
reconciliation ledger; those are presentation state, not a source cache.

This boundary is not opaque or zero-copy. `FileContents.contents` is a string,
Pierre retains whole item records, and its worker manager posts whole request
objects without a public transfer-list guarantee. The implementation therefore
measures publication bytes, structured-clone time, adapter/Pierre synchronous
work, duplicate lifetime, and retained heap. No exact copy count, detachment,
zero retained main bytes, or O(visible-metadata) heap claim is valid without
current empirical proof.

Main admission remains bounded by item count, total pending publication bytes,
and the frame-budgeted apply pump. Selected/current work ranks first; offscreen
publications cannot accumulate without worker-owned demand/residency policy.
Every publication has a current disposition or cancellation lease. A policy
ceiling controls scheduling and release eligibility, not source truncation.

### R53. Worker messages are transferable-first.

AgentStudio-owned binary boundaries are transferable-first. Stream chunks,
byte-cache handoffs, compute-pool buffers, large structural tables, and future
persistent-cache byte payloads use declared `ArrayBuffer` transfer fields when
ownership actually moves. Small ids/ranges/enums/health/display DTOs use
structured clone.

The complete Pierre item publication is the explicit exception required by the
released dependency: it carries the supported string/object item through
structured clone to main. It is not mislabeled as transferable, and main does
not convert the string to a byte-backed private Pierre protocol. Runtime schemas
distinguish transferred binary payloads from cloned complete-item publications.

`BridgeWorkerContracts` names every transfer field and every cloned body class.
A binary message with no transfer fields declares an empty transfer list; a
message with transferred buffers declares exact unique field paths and byte
lengths. Runtime validation rejects disagreement between the declared mode and
the values. A complete-item publication records its measured encoded/source
bytes and item class but promises no sender detachment.

```text
sender owns buffer
  │
  ├─► postMessage(payload, transferList)
  │      transferList fields are named by BridgeWorkerContracts
  │
  ├─ sender buffer is detached
  │
  └─► receiver owns that binary buffer, with no O(bytes) clone

comm worker owns complete supported Pierre item
  │
  └─► structured-clone whole item to main adapter
         unavoidable released-API boundary; measured, never called zero-copy
```

Boundary instrumentation measures clone/transfer duration, bytes, sender
detachment where transfer applies, receiver ownership lifetime, duplicate
lifetime, and retained bytes per message class. Any accidental clone outside
the declared complete-item class is a contract failure. Whole-item cost that
misses the release stop lines blocks cutover and triggers reconvergence; it does
not authorize a silent File cap, sparse fiction, or Pierre modification.

### R54. Zustand moves to the comm worker; React RPC lifecycle is typed and local.

The architecture has one Bridge data store owner: the comm worker. That store is
implemented as a worker-local Zustand vanilla store unless a later spec replaces
it with an equivalent typed worker-local primitive. React/main must not create,
import, subscribe to, or mutate a Zustand store for Bridge viewer data after the
cutover. Existing main-thread Review/File View Zustand stores are legacy
deletion targets as canonical product owners, not implementation options.
Their pure projection algorithms, UI-only state decomposition, component
contracts, and proof may be recovered, but metadata, accepted projection,
freshness, content, demand, retry, and residency move to the comm worker.

React/main has two allowed local surfaces:

- `BridgeWorkerRpcLifecycleStore`, a typed non-Zustand sync store/helper for
  coarse worker RPC lifecycle: open source, refresh, reconnect, search/filter
  command completion, mark-viewed mutation, pending/ack/fail/timeout state, and
  mutation optimism/rollback metadata.
- `BridgeMainRenderSnapshotStore` plus recovered component-local/UI-only state
  for frame-critical display copies and ephemera: pending selected intent,
  active mode, viewport/range, hover/focus, draft search, directory disclosure,
  scroll/reveal bookkeeping, panel chrome, keyed row/content copies, and worker
  health copy. This surface exists only to paint synchronously, emit typed
  intents, and apply worker patches inside the R46 frame budget.

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
| `BridgeWorkerPierreItemPublication` | comm worker -> main presentation adapter -> Pierre API | closed AgentStudio envelope around one supported complete Pierre item | pane/worker/source/projection/item/semantic/render/publication identity, complete item, source/content digest, measured payload class | partial-as-ready content, sparse/window fiction, main-recomputed body, source capability, transfer/zero-copy promise, private Pierre traffic |
| `BridgeReviewPresentationAdapter` | main/React | pure keyed translation plus small Pierre reconciliation ledger | worker display snapshots, UI-only state, stable item id, last applied fingerprint/version/cache key/disposition | fetching, body cache, freshness, accepted projection, demand/residency, retry, source capability |
| `BridgeWorkerMarkdownPatch` | comm worker -> main | bounded structural patch union | semantic/attempt identity, node/depth/count bounds, sanitized inert node batch, final flag | source bytes/HTML, script/style/events/URLs, whole document graph |
| `BridgeRenderDisposition` | main -> comm worker product DTO | bounded idempotent union | pane/worker/surface, interaction/attempt/publication id, semantic document/item, `workerDerivationEpoch`, `queued`/`applied`/`painted`/`rejected`/`superseded`, reason | telemetry-only receipt, content body, main-owned retry decision |
| `BridgeWorkerTransferDescriptor` | wire metadata | explicit transfer-list helper for binary classes | message kind, unique field paths, byte lengths, transfer mode, detached-after-send expectation where applicable | implicit buffers, calling cloned complete-item strings transferable, unmeasured ownership |
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

The FE primitive is `BridgeMainRenderSnapshotStore`, a non-Zustand store exposed
to React through `useSyncExternalStore`. It has exactly
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

### R57. Pierre/Shiki ownership and the complete-item boundary are explicit.

The implementation floor is the installed, pinned public
`@pierre/diffs@1.2.10` API. Pierre accepts complete string-backed file/diff
items, retains whole item records, virtualizes mounted items/rendered lines, and
posts whole worker requests without a transfer list. `renderRange` is internal
rendering virtualization after complete-content admission. `isPartial: true`
is one complete patch-derived diff, not a continuation protocol.

The supported public reconciliation surface includes `addItems`, `updateItem`,
`updateItemId`, and `scrollTo`; controlled/vanilla ownership may also use the
corresponding supported item-set surface. There is no public `submitWindow`,
`cancelWindow`, `evictWindow`, `resetWindowedItem`, `getWindowState`, or
`subscribeWindowEvents`. AgentStudio must not invent those APIs, import private
Pierre modules, proxy its workers, use `patch-package`, fork the repository, or
require a future Pierre release.

The AgentStudio publication envelope is:

```text
BridgeWorkerPierreItemPublication
  pane/session/worker/source/projection identity
  stable item id and item kind
  semantic document + render-semantics revision
  publication revision + attempt id
  source/content digest and measured payload class
  one complete supported Pierre file or diff item
```

File View publishes exactly one complete selected text-file item. Review
publishes one complete item for each hydrated selected/visible projected file.
A patch-derived partial diff is permitted only when the product state names it
as such and hunk expansion that needs absent base/head content is explicitly
unavailable; it cannot prove full Review parity. Ordinary full Review items use
complete source roles and `isPartial: false`.

Projection metadata and body readiness are separate. The restored tree may
show every projected path before its body is ready. Loading presentation is
typed and cannot carry source checksum, fabricated whitespace, copied line
extent, or readable disposition. If a header-only CodeView loading record is
used to preserve item order, it is not a ready source item and must remain
visually/semantically distinct from a real empty file.

Reconciliation rules:

- stable Pierre item ids are deterministic per projected source item and item
  kind; one id never changes between file and diff types;
- the worker mints a content-addressed cache identity from item kind, ordered
  authoritative role digests, display name/language, and render algorithm;
- the main adapter mints a monotonic Pierre invalidation `version` per mounted
  CodeView instance/item whenever the final supported item record changes;
- equal final fingerprints are no-ops; stale publication revisions are rejected;
- append-only ready items use `addItems`; same-id complete replacements or
  collapse/presentation changes use `updateItem`; supported id repair uses
  `updateItemId`; explicit reveal uses `scrollTo`; and
- a removal/reorder that Pierre cannot express safely creates a new projection
  layout epoch and controlled remount. The exhaustive triggers are source or
  package identity replacement, render-semantics replacement, or an accepted
  Review projection whose CodeView membership/order changes. Trees-only search
  and status visibility never remount CodeView. Remount waits for active scroll
  to settle, preserves an independently verified anchor when still valid, and
  never uses a private removal API.

Pierre is the only CodeView viewport writer. AgentStudio never writes
`scrollTop`. Active user scrolling vetoes hydration-triggered reveals; only the
current explicit reveal intent may call `scrollTo`. A settled reveal cannot be
silently re-armed by later hydration.

The comm worker owns complete-item assembly, demand, source freshness,
publication identity, and residency. The main adapter owns only reconciliation
facts and the bounded render copy. Pierre owns applied item records, layout,
highlighted ASTs, rendering, and viewport computation. Neither main nor Pierre
may fetch source content or decide Bridge freshness/demand.

There is no sparse geometry API. Continuous Review is therefore an empirical
release obligation, not an assumed property. Browser and packaged WKWebView
proof must establish truthful projected order, far reveal, early/middle/final
traversal, anchor stability during late hydration, no false adjacency, bounded
whole-item residency, and acceptable heap/main-thread/p99. Before measuring,
the implementation plan names its starting admission lanes, eviction
discipline, reset semantics, and anchor protection. Baseline measurement then
fixes numeric item/byte residency and performance gates; they schedule/admit
work and never truncate source.

Failure of complete File View or continuous Review against those gates is a
model break: stop and reconverge with the user. Do not weaken the proof, invent
padding/extent, restore a 2 MiB/10,000-line cap, or modify Pierre.

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
| payload | large binary bytes transfer through declared buffers; the one complete-item string/object class uses declared measured clone, never an accidental clone | ownership-mode validation and clone/transfer duration |
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
  128 KiB before `fetch`; native counts actual `httpBody`, or at most cap + 1
  `httpBodyStream` bytes, before decode/mutation and never trusts/requires
  synthesized `Content-Length`;
- every correlated command response package and logical metadata JSON frame is
  likewise capped by the same 128 KiB control-package constant before decode.
  Binary content is a distinct streamed payload with the separate frame and
  data limits in R64;
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
- receivers validate observable ownership mode, transfer fields/values/lengths,
  identity, and freshness. Only schema-driven sender helpers may post binary
  payloads or complete-item publications. Binary transfer helpers supply the
  transfer list and assert local detachment; the declared complete-item class
  uses measured structured clone and makes no detachment claim. Import/lint
  boundaries forbid undeclared raw-content `postMessage`; receivers cannot
  claim to observe remote detachment;
- browser-supplied display paths never become filesystem authority; content
  opens remain descriptor/lease based and pane/session/generation bound. Before
  any byte read, both Vite and Swift providers reject absolute/traversal/`.git`
  policy violations and canonical ambiguity, then enforce lexical AND
  symlink-resolved containment inside the selected repo/worktree root. One
  shared hostile path corpus covers Unicode variants plus external-file and
  external-directory symlink escapes in both providers;
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

R44 moves stream accumulation, decode, complete-item assembly, diff preparation,
semantic hashing, cache admission, and publication preparation off the main thread. It
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
| `workerComputeSliceMaxMs` | <= 8 ms | worker content-preparation compute slice | every synchronous worker compute slice, including parse/decode/diff/item prep, must yield before this cap |
| `workerContentPrepInlineMaxBytes` | <= 512 KiB by default | worker inline compute chunk | crossing this threshold requires resumable chunking or subordinate compute; it never truncates the final item |
| `workerContentPrepInlineMaxLines` | <= 400 lines by default | worker inline logical-work chunk | crossing this threshold requires yielding/resumption; it never publishes a partial File item as ready |
| R58 worker selected queue-wait p95 | < 16 ms | shared worker selected queue-wait SLO | selected/click facts must not wait behind background content prep |
| R58 worker selected queue-wait p99 | < 32 ms | shared worker selected queue-wait SLO | same budget as R32-R40 foreground queue wait |

Review/File preparation above one compute-slice threshold MUST continue through
resumable chunks or offload bounded compute while the comm worker remains the
authority. The selected item may show honest typed loading while pending; size
cannot produce terminal unavailable or a silently ready prefix. File View emits
one complete item. Review emits a complete item per hydrated selected/visible
file. Speculative work may be demoted; selected/visible membership cannot be
discarded.

Content preparation below the byte/line ceiling is still not automatically safe:
if measured slice duration exceeds `workerComputeSliceMaxMs`, the next revision
must chunk the computation, yield more frequently, or offload that work before the cutover can claim
R60. A large diff/file prepare test is mandatory: while an 18k-line-equivalent
fixture or policy-sized stress fixture is preparing, a selected fact enters the
worker and its queue wait remains under the selected p95/p99 budget.

The comm worker is the single protocol/cache/demand authority and owns
scheduling decisions. Physical compute
may run as local pump slices or in a coordinated compute pool, but no
package-shaped parse/decode/diff/item preparation may run as one
synchronous comm-worker task.

The canonical flow is the R49 channel topology plus the R52 complete-item path:
local intent -> comm-worker demand/source/assembly -> keyed patch or complete
publication -> frame-budgeted presentation/Pierre apply -> disposition. Compact
telemetry samples use only the disjoint R43 sidecar.

Transfer/consumer matrix. Every content-bearing message class has exactly one
consumer and one declared ownership mode; an unlisted or parallel route is forbidden.

| Surface | Payload class | Boundary | Mode | Rule |
| --- | --- | --- | --- | --- |
| Review | select, hover, surface/projection mode, viewport, mark-viewed facts | main -> comm worker | structured clone DTO | Small ids, hashes, ranges, enums, and UI revisions; never `workerDerivationEpoch`/sequence. |
| Review | open/refresh/reconnect/search/filter RPC via typed lifecycle store | main -> comm worker | structured clone DTO | Request keys and variables are cloneable DTOs; optimistic state stays in lifecycle/render hooks, not in worker payload. |
| Review | metadata descriptors, availability, row chrome, tree/projection patches | comm worker -> main | structured clone DTO | Only bounded keyed deltas may cross; full-package snapshots are forbidden. |
| Review | source/diff/content bytes fetched from Swift | Swift -> comm worker | stream/`ArrayBuffer` in worker | Worker consumes `ReadableStream<Uint8Array>`/`arrayBuffer()` and owns the byte cache; main does not receive raw bytes. |
| Review | complete diff/file `BridgeWorkerPierreItemPublication` | comm worker -> main presentation adapter -> Pierre `addItems`/`updateItem` | declared whole-item structured clone, then supported Pierre object call | Sole CodeView body consumer. No prefix-as-ready, sparse protocol, detachment claim, or parallel line/run payload. |
| Review | markdown source/render tree | comm -> optional comm-owned compute -> comm -> main patches | source transfer only inside worker execution; bounded structural DTO patches to main | Sole markdown consumer; raw source never reaches main/Pierre; final patch uses normal disposition. |
| Review/File | render disposition | main -> comm worker | small structured-clone DTO | One idempotent transition per item publication attempt; full identity and reason required; no telemetry dependency or content body. |
| Review/File | telemetry sample | main or comm -> telemetry worker | compact structured-clone DTO on dedicated producer port | Producer timestamps/correlates only. Telemetry worker owns validation, credit, buffer, bytes, sequence, encode, retry/outbox, and POST. |
| File View | open file, select path, expand/collapse, filter/search, viewport facts | main -> comm worker | structured clone DTO | Small path ids/hashes, filter text, row ids, and ranges; never full tree state. |
| File View | tree metadata, descriptor chunks, availability, row paint patches | comm worker -> main | structured clone DTO | Only bounded visible/keyed deltas may cross; full manifest/list snapshots are forbidden. |
| File View | file contents fetched from Swift | Swift -> comm worker | stream/`ArrayBuffer` in worker | Worker owns raw file bytes and decoded/cache truth; main receives availability or paint-ready display payload only. |
| File View | one complete-text `BridgeWorkerPierreItemPublication` | comm worker -> main presentation adapter -> Pierre `addItems`/`updateItem` | declared whole-item structured clone, then supported Pierre object call | Sole text-content consumer; complete selected text, measured cost, no prefix/truncation or separate run payload. |
| File View | binary/unsupported/unavailable result | comm worker -> main | small structured clone availability DTO | No body crosses; explicit typed terminal metadata only. |
| File View | initial load/progress/worker health | comm worker -> main | structured clone DTO | Progress and health are small render-copy facts; no content bytes or raw manifest snapshot. |

### R61. Complete-item hydration and residency are observable product state.

Review projection structure is available independently from body readiness.
The comm worker owns the ordered projected item manifest and current
selected/visible/nearby demand. A selected or visible item remains desired until
its matching complete publication paints or an explicit non-size source state
becomes terminal. Loading, ready, painted, stale, superseded, unavailable, and
released residency are keyed, revision-bound facts.

The 100,000-line/multi-file fixture must prove early, middle, and final real
content checksums, far reveal, directory/file collapse, late hydration without
snapback, and truthful continuous ordering. A synthetic body, whitespace filler,
metadata-derived line extent, prefix replay, or a first chunk reported as a
ready item fails the gate.

File View has one selected complete-item lifecycle. It streams and assembles all
supported text, publishes one complete item, and proves final-content
reachability. Binary, unsupported encoding, unavailable, failed, empty, stale,
and superseded states are explicit. Size alone does not yield truncation or
unavailable. Any required resource safety limit is an unshipped stop line until
measurement and explicit user reconvergence make it a new product decision.

Hydration, complete-item assembly, residency, release, and re-demand are
comm-worker facts. Main/Pierre may render a supplied complete item but cannot
choose demand, pad content, reinterpret readiness, or independently evict
source truth. Selected/visible residency is protected. Any offscreen release is
shippable only after browser and packaged proof demonstrates bounded heap and
stable anchors without fabricated extent.

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

Every readable proof row correlates one selected projected item through its
descriptor, required source roles, content request/lease, provider source
identity, authoritative role/full-content digests, complete-item publication,
Pierre item id/version/cache identity, matching DOM header/body, and terminal
render disposition. Deterministic fixtures use an independent fixture oracle.
The real-worktree Vite browser lane and packaged Swift lane use an independent
live-git/source oracle; worker/store attributes cannot serve as their own oracle.

A workload sample names runtime, surface, interaction, cache state and telemetry
state. Browser timing starts at the trusted committing timestamp before handler delivery;
`input_queue_wait` ends at the first handler instruction. Synthetic DOM
`.click()` is not a timing stimulus. Semantic IPC timing starts on the
controller's monotonic clock before dispatch and ends at correlated post-paint
completion on that same outer clock. Actionability controls cohort eligibility,
never clock reset; cross-clock values are not subtracted without calibration.

| Interaction metric | Required painted endpoint |
| --- | --- |
| selection feedback | selected chrome plus matching readable, terminal, or honest selected placeholder |
| fresh display readable | matching semantic/item/render identity and current validation lease; no worker trip credited |
| selected readable | matching current complete item after worker/Pierre/apply and post-paint check |
| terminal availability | matching binary/unsupported/unavailable/failure state |
| rail/CodeView scroll motion | first confirmed frame with intended nonzero motion |
| rail/CodeView content painted | settled desired rows/item content are correct, checksum-matching, nonblank, and painted |

Published scroll budgets require both motion and correct-content endpoints.
Every attempted row records workload, launch, interaction/attempt id, outcome,
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
| Review item hydration | baseline repeated per desired complete selected/visible item |
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

1. Vitest Browser with real comm, telemetry, and Pierre workers against BOTH
   deterministic fixtures and the real-worktree Vite provider, using the same
   restored product UI; 3,420+ file / 100,000-line Review plus complete large
   File View, screenshots, console checks, scroll motion, source-to-readable-paint
   correlation, long-task/event-loop evidence, and raw benchmark families;
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
real whole-item clone/transfer or scheduling cost; browser proof cannot prove WKWebView
scheme behavior; headless Swift cannot prove UI; screenshots cannot prove p99.
Required telemetry gaps, missing raw samples, omitted failures, wrong content,
blank items, false adjacency, disappearance, wedges, or stale paint fail the run even when the
remaining numeric samples meet percentile budgets.

### R63. Render fulfillment, reset, and worker restart are one state machine.

```text
desired -> preparing -> published(attempt) -> queued -> applied -> painted
   ^             |             | rejected/superseded/lease-expired |
   +-------------+-------------+-----------------------------------+
```

Only matching `painted` or explicit non-size terminal availability fulfills
selected/visible membership. `attemptId` is new per publication;
`publicationId` and semantic item identity remain stable. Dispositions are
idempotent, monotonic (`queued -> applied -> painted`), and each kind occurs at
most once per attempt. Conflicting/out-of-order receipts are rejected.

Every published attempt owns a policy-bounded receipt lease. A current desired
item whose lease expires, or whose attempt is rejected/superseded, returns to
desired after bounded backoff and republishes with a new attempt id. Main/Pierre
dedupe by publication/item identity so a lost receipt cannot duplicate DOM.
For `already_painted`, main performs the normal post-frame identity check and
sends `painted` for the NEW attempt; `already_applied` waits for the Pierre paint
event. Thus idempotent no-op closes the receipt lease without inventing a paint.
After a policy-bounded attempt burst, the worker marks transport unhealthy and
starts reset/reconnect; demand membership is never parked or abandoned.

One current semantic item/content fingerprint may have at most one active
publication attempt. A source-update/select race that produces the same job
twice must coalesce before publication; an exact late duplicate is a measured
no-op and cannot emit a second queued/applied/painted chain.

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
| `POST agentstudio://rpc/content` | one demanded descriptor/item/role body | one independently cancellable typed binary content response |

Every route follows R59's actual-body 128 KiB admission. Correlated command
response packages and logical metadata JSON frames have the same 128 KiB
pre-decode ceiling. Binary content response frames use their distinct bounds
below. The authenticated pane session is `wireVersion: 2` plus `paneSessionId`, a freshly native-minted
`workerInstanceId`, and its 256-bit opaque capability. Bootstrap transfers the capability's 32 bytes into the worker and detaches main; only the capability is a privileged header. Replacement revokes old subscriptions/content/leases.
No product identity/length appears in URL or headers, and the capability never appears in body/response/DOM/log/telemetry/error. Static assets and `OPTIONS` remain capability-free. This hard-cut wire has no v1 decoder, fallback, compatibility branch, global `workerEpoch`, or dual path.
No loopback HTTP product carrier exists; product transport stays on these
capability-bound custom-scheme routes.

The authenticated command-route request union is `workerSession.open`, `product.call`, `subscription.open`, `subscription.updateBatch`, `subscription.cancel`,
`stream.frameObserved`, or `workerSession.resync`. `stream.frameObserved` is a strict discriminated request dispatched independently on that physical route before the ordinary `BridgeProductControlMux`; it does not consume or wait behind the mux's single-flight admission. `workerSession.open` carries literal `request: null` and establishes only the authenticated pane/worker lifetime. Each typed
`subscription.open` carries its kind-specific fixed source configuration, where applicable, and establishes revision zero with the kind-specific canonical
empty-interest hash. Mutable interests/path scope move only through nonempty typed delta batches carrying update id, subscription kind/id, base revision/hash, target
revision/hash, batch index/count, total delta count, and the kind-specific delta. Target revision is exactly base + 1. Delta adds are idempotent upserts,
including lane changes; removes delete membership.

Interest hashes use one canonical binary form: `u8 version=1 | u8 kind (review=1, file=2) | u32be interestCount`, then exact-UTF-8-byte-sorted records of
`u32be keyByteLength | key bytes | u8 lane` (`foreground=1`, `active=2`, `visible=3`, `nearby=4`, `speculative=5`, `idle=6`). File state appends
`u32be pathScopeCount` and exact-UTF-8-byte-sorted `u32be pathByteLength | path bytes` records. Fixed source configuration is excluded; no Unicode normalization occurs. SHA-256 covers exactly those bytes, whose canonical encoding is separately capped at 128 KiB; the complete encoded control package's 128 KiB limit remains authoritative. Shared empty, multi-lane, and composed/decomposed vectors bind TypeScript and Swift.

`workerDerivationEpoch` exists only on a surface-scoped request or push frame. Closed call/subscription/content kinds map exhaustively to Review or File; ordinary variants MUST NOT repeat `surface`.
It is required on `product.call`, each subscription open/update/cancel, each active `workerSession.resync` subscription entry, and each content open. Pane/session open, metadata-stream open, and the top-level resync envelope carry none. Swift checks independent Review/File floors only for NEW admission. Active resync entries deriving to one surface MUST share one epoch; Review and File may differ, but a same-surface conflict atomically rejects the whole resync before floor or subscription mutation.
Body-bearing correlated responses are `workerSession.accepted`, `call.completed`, `subscription.openAccepted`, `subscription.updateBatchAccepted`, `subscription.cancelAccepted`, `resync.accepted`, or typed `request.error`.
Frame-observation success is instead HTTP `204` with an empty body. The worker transport maps the validated request plus status into a closed typed local outcome; no `stream.frameObservedAccepted` wire package exists. Rejection uses the closed bounded status mapping and likewise carries no product payload.
These correlated control responses do not repeat `workerDerivationEpoch`: the single pending request supplies any surface and admitted epoch. At most one update id is staged per subscription; another is rejected with
`sequence_conflict` while the worker coalesces newer desired state. Batches start at zero, are contiguous, repeat identical update metadata, and globally
preserve delta uniqueness/count ceilings. Exact batch retry reuses id/sequence/bytes and returns the cached response; changed bytes or reuse of a committed
update id through a new request is fatal. Native commits only when all batches are present, the base revision/hash still match, the resultant state is valid,
and its recomputed hash equals the target. `BridgeProductControlMux` permits one unacknowledged admission for ordinary control work. Frame-observed acknowledgements use independent bounded per-stream gates and MUST NOT head-of-line block interactive commands, the metadata stream, or another content stream.

`resync.accepted` is the sole reconciliation authority. Its `reconciliation`
array has exactly one closed outcome for every worker-reported
`activeSubscriptions` entry, preserves request order, and is capped by the same
64-active-subscription ceiling. Each outcome echoes the claimed subscription
kind/id/epoch so the worker must reject positional or identity mismatch.
`retained` echoes the authoritative revision/hash; `reset` supplies the newly
committed empty-state revision/hash; `cancelled` kills the claimed id without
reopening; and `reopenRequired` kills the claimed id and requires a fresh
`subscription.open` with a new id. Native-only subscriptions absent from the
worker claim set are revoked before commit, leave zero producer residue, and
are omitted from the response. Reconciliation emits no duplicate
`subscription.accepted`, `subscription.reset`, or `subscription.cancelled`
frames. `resumeFromStreamSequence` is the physical metadata barrier captured
after native-only pruning and claimed-subscription reconciliation; subsequent
metadata begins after that barrier. Exact retry replays identical response bytes
without reapplying any mutation.

`BridgeProductSession` owns protocol lifecycle sequencing as part of control
commit. For ordinary subscription open, the final committed update batch, and
cancel, admission of the required `subscription.accepted`,
`subscription.interestsCommitted`, or `subscription.cancelled` frame MUST
succeed before subscription state and exact accepted response bytes commit to
replay. Admission failure commits and caches no success, leaves no half-applied
provider mutation, and forces a typed error/resync path. The pane product
provider owns File/Review metadata and content production, not protocol commit
effects.

One `metadataStream.open` establishes the pane stream. Each logical metadata frame is `u32be frameBodyLength | strict typed UTF-8 JSON body`; `frameBodyLength` counts only the body and has a hard 128 KiB ceiling. WebKit delivery chunks are non-semantic.
`AsyncThrowingStream.Continuation.yield(.enqueued)` proves only admission to a local Swift buffer; it is not evidence that WebKit delivered the bytes or that the comm worker consumed a frame. Swift therefore retains each queued metadata or content frame and permits at most one unobserved frame per physical response stream. The window of one is the normative initial safety policy; a wider window requires packaged throughput evidence and explicit contract reconvergence. Only after the comm worker has assembled, strictly decoded, and committed the exact next frame does it send `stream.frameObserved` through the authenticated command route and await bodyless `204` success. The acknowledgement echoes the full pane/session, worker-instance, physical stream, producer/request or lease, and metadata/content sequence identity. Native accepts only the exact outstanding identity and sequence. An exact replay of the last accepted acknowledgement is idempotent and returns the same `204` without releasing twice; skipped, foreign, stale-instance, changed-reuse, and post-terminal acknowledgements are typed status rejections and release nothing. Native removes that frame and releases the next frame for that stream only after accepting the worker observation; local yield disposition never advances the producer queue.

Metadata and every independently cancellable content response pace separately, so one slow or cancelled stream cannot withhold another stream's frame or an interactive command. Physical transport admission MUST
reserve capacity for the metadata response plus observation/control traffic: on a six-request carrier with one metadata response, at most four content responses may remain open. This is worker-transport admission,
never a Review/File demand-policy cap; queued opens preserve ranked scheduler order, remain independently abortable, and release admission only after terminal settlement or cancellation. Cancellation, reset,
resync, replacement, and producer retirement resolve any outstanding observation gate exactly once under the existing identity fences, discard frames that can no longer commit, and leave zero producer residue.
A terminal response finishes only after its terminal frame is worker-observed or the owning lifecycle is cancelled. No acknowledgement travels through headers, loopback HTTP, React/main, or a fallback carrier.
Fresh `metadataStream.accepted` consumes pane-wide `streamSequence` zero; resume from N consumes N+1 for `resumed`/`snapshot_required`, then continues contiguously. Frame kinds remain `metadataStream.accepted`, `subscription.accepted`, `subscription.interestsCommitted`, `subscription.data`, `subscription.reset`, `subscription.end`, `subscription.cancelled`, `content.cancelled`, and `metadataStream.error`.
All carry wire/pane/worker/stream plus that sequence. Pane-plane accepted/error frames carry no derivation epoch. Every subscription frame carries kind/id, source, its admitted `workerDerivationEpoch`, cursor, interest revision/hash, and subscription sequence; kind derives surface. Mixed Review/File frames interleave on one contiguous pane-wide `streamSequence`. `interestsCommitted` is the ordered barrier resolving `update()`: no new-revision data precedes it and no old-revision data follows it.
Cancel, reset, resync, and replacement discard staged updates. Reset advances revision with canonical empty interests for add-all replay; mismatch uses `interest_mismatch`, not session-fatal failure. `content.cancelled` carries content/request/lease/descriptor/item/role identity plus `stopped | already_terminal` only after zero producer residue; subscription cancel stops only that producer, and reconnect resumes a contiguous suffix or snapshot.
After a floor advances, older `subscription.accepted`, `subscription.interestsCommitted`, and `subscription.data` consume pane-wide sequence continuity but cannot commit interests, admit/cache/publish data, or reset current-epoch state. Cleanup-only `subscription.reset`, `subscription.end`, `subscription.cancelled`, and `content.cancelled` may close producer/request/lease correlation and reach zero residue only; they never mutate current surface truth.
A content response is bound by its accepted epoch. A stale `content.accepted` may bind only the already-admitted response identity for abort/settlement; it and later data cannot admit/cache/publish content. After the floor advances, terminal `content.end`/`content.error`/`content.reset` may settle correlation and discard staging only. Floor gating never rejects cleanup for admitted work.

Each `openContent()` concurrently POSTs a typed content kind, descriptor, lease,
`contentRequestId`, requested item/role identity, authoritative complete-role
length, authoritative expected SHA-256 or `null`, and a maximum equal to that
admitted complete-role length; it does not consume the control sequence. The
maximum is an exact response bound, not a truncation or prefix policy. Providers
must establish the complete length before streaming. Binary response framing is:

```text
u32be frameBodyLength | u8 frameTag | u32be contentSequence | tag-specific body
accepted/end/error/reset: strict typed UTF-8 JSON | data: u32be offsetBytes | raw bytes
```

`frameBodyLength` counts every byte after its own four-byte prefix. Tags remain `0x01 content.accepted`, `0x02 content.data`, `0x03 content.end`, `0x04 content.error`, and `0x05 content.reset`; there is no separate header-length prefix.
`content.accepted` is sequence zero. Its strict JSON body carries full request/lease/pane/worker-instance/content identity plus the admitted `workerDerivationEpoch`, declared and maximum length, and expected digest, binding this non-multiplexed response stream to one request and producer continuation.
Every later sequence is positive and contiguous. `content.data` carries `u32be offsetBytes` followed by raw bytes; raw length is derived from `frameBodyLength`, never repeated in JSON, and is capped at 128 KiB. Data may not precede acceptance.
`content.end`, `content.error`, and `content.reset` are terminal and carry only small strict JSON terminal fields; stream context comes from acceptance. End reports observed total and SHA-256, verifies authoritative expectation, and lets the worker derive semantic identity before cache admission.
Every content frame body has the universal hostile-input ceiling of 256 KiB;
every content JSON control body has a separate 16 KiB ceiling. Complete source
bodies of any admitted length stream as the necessary number of contiguous
128 KiB-or-smaller data frames; a partial final data frame is valid.
WebKit may split or coalesce bytes arbitrarily. Prefix/stage caps precede allocation/decode, and both decoders use fixed-capacity reference-owned accumulators rather than repeated copy-on-write append.
Each native producer owns exactly one `URLSchemeTask` response continuation. Cross-stream writes, wrong producer identity, pre-accepted data, gaps, duplicates, offset mismatch, overflow, invalid digest, or post-terminal bytes poison that response, discard staged bytes, and perform no product-state mutation.
Native queues retain frame/byte caps, terminal reserve, and a safety ceiling of 16 content-producer lifecycle residues per product session, counted as active content producers plus pending content lifecycle acknowledgements. Abort closes only that response; native stops and unregisters its producer before the pane metadata stream emits correlated `content.cancelled`. Cancellation, revoke, disposal, and replacement join one single-flight retirement owner for each lease's exact lifecycle nonce; a failed acknowledgement retains the residue and every retry reuses that exact nonce. The worker settles only after local fetch abort plus the lifecycle frame and successful acknowledgement of the same zero-residue barrier.
Shared raw TS/Swift vectors cover exact 128 KiB control request, correlated
command response, and metadata JSON bodies with +1 rejection; exact 128 KiB
content data and +1 rejection; complete multi-frame source segmentation,
including a 2 MiB fixture without treating it as a cap; 1-byte/4 KiB arbitrary
fragmentation; cross-stream/terminal hostility; strict JSON/interest semantics;
and checksum/cancel/resume/restart. The reconciliation corpus proves positional
count/order pairing and identity mismatch rejection, exact retry bytes with no
reapply, mixed Review/File epochs, `snapshot_required -> resync ->
reopenRequired`, native-only residue zero, and forced lifecycle-frame admission
failure with no cached success. Shared pacing tests prove that local Swift
buffer admission cannot release a frame, exact worker observation releases
only that stream's next frame, exact replay returns bodyless `204` without a
second release, gap/foreign/changed acknowledgements release nothing,
cancellation resolves a pending observation gate once, and 128 KiB
frames survive arbitrary WebKit splitting/coalescence. An ingress/relocation/allocation oracle proves
bounded linear accumulation and complete multi-frame source assembly without a
fixed total-prefix cap. Packaged benchmarks start at 128 KiB emission and
must satisfy the existing p99 and synchronous-slice budgets before that producer
policy changes.

### R65. File View byte, encoding, line, and completeness semantics are canonical.

Binary/provider-unsupported classification occurs before text publication; a
NUL in the bounded classification prefix is binary. Invalid UTF-8 is
`unsupported_encoding`, never replacement-decoded. Supported text streams to
completion and is decoded with a stateful strict decoder so a UTF-8 scalar split
across transport frames is reconstructed rather than cut or replaced.

LF terminates a line; CRLF is one terminator; trailing LF creates no extra empty
line; empty content has zero lines. Thus `"a\n"` is 1 line and `"a\nb"` is 2.
Arbitrary transport fragmentation, including a split inside the U+20AC scalar
of escaped `"a\u20ACb"`, produces the same complete string and digest as one
contiguous source body.

The complete descriptor carries semantic/item identity, authoritative full
source hash, complete payload byte/line counts, `endsWithNewline`, and `utf-8`.
It carries no prefix hash, `endsMidLine`, or byte/line truncation reason for a
ready text item. Metadata never fabricates bytes, lines, whitespace, or layout
height. TypeScript and Swift share complete, empty, newline, CRLF, multibyte,
binary, invalid-UTF-8, arbitrary-fragmentation, and large multi-frame fixtures.

### R66. Telemetry credits, admission, restart, and drain are explicit.

`BridgePaneTelemetrySession` alone creates/monitors the optional worker. Failure
signals are worker `error`/`messageerror`, bootstrap/port timeout, fatal health,
or missing drain ack. Failure closes producer ports and makes the run
proof-ineligible while product continues. Replacement creates a new telemetry
session; sessions cannot be pooled. Comm-worker restart revokes/replaces only
its producer port and sequence; old-port traffic fails proof.

`producer.install -> producer.ready(initialSampleCredits,
initialControlCredits)` opens a port. Main and comm each have exactly one
producer for the active generation. A producer starts with zero usable credits;
constructors cannot pre-grant authority. The telemetry worker installs the
port-bound runtime generation before sending the first matching
`producer.ready`, and replacement repeats that order on the new comm port.

Before that first matching ready only, each producer owns a bounded FIFO spool
for required compact-sample bodies. Native bootstrap fixes the per-producer
limits at `producerPreReadyBufferMaxSamples = 128` and
`producerPreReadyBufferMaxBytes = 64 KiB`. Every attempted event still advances
the producer sequence. Required samples that fit retain their original sequence
and body; optional samples, individually oversized samples, and required
overflow retain no body and append an exact ordered loss range. Optional and
capacity-overflow loss uses `queue_saturated`; the existing encoded-byte reason
remains `encoded_byte_cap`. Loss ranges and retained samples share one FIFO
order, so a later sample cannot bypass an earlier loss summary.

The first matching `producer.ready` supplies the first real credits and
immediately drains the spool in sequence order. A returned sample or control
credit resumes any blocked drain without an interactive await or flush. A
barrier or close clears every retained body; a barrier accounts any unposted
required entry in its exact pre-seal loss range. The spool cannot reopen after
ready. From that point onward, the existing rule is unchanged: with no sample
credit a producer retains no body and increments bounded aggregate
counters/ranges using `credit_exhausted`.

One sample credit represents one pipeline slot capped by
`compactSampleMaxEncodedBytes`; it is consumed before post and refilled only
after native accepted/duplicate admission or accounted shedding frees that slot,
not merely worker receipt. Reserved control credit is separate and returned only
by control acknowledgement. `loss.summary` uses control credit, is ordered after
its range, and must be acknowledged. Counter-key overflow emits
`loss_counter_overflow` and fails proof. Requiredness derives from event kind:
every R62 lifecycle/gate sample,
abort/stale/unavailable/timeout/reset/retry/failure/jank event, and telemetry
integrity event is required. Required loss anywhere sets `proofEligible=false`;
optional diagnostic loss is exact and marks the run lossy.

Native bootstrap supplies this initial policy inventory:

| Policy | Initial ceiling | Ownership / rule |
| --- | --- | --- |
| `initialSampleCredits` | 128 per producer | usable only after the matching ready or an explicit later grant |
| `initialControlCredits` | 4 per producer | reserved for ordered loss/control messages |
| `producerPreReadyBufferMaxSamples` | 128 per producer | required bodies only before first matching ready |
| `producerPreReadyBufferMaxBytes` | 64 KiB per producer | encoded bytes retained by that same startup-only spool |
| `compactSampleMaxEncodedBytes` | 16 KiB | worker admission ceiling for one compact sample |
| `producerLossKeyCap` | 64 | bounded producer loss aggregation |
| `workerBufferMaxSamples` | 256 | telemetry-worker shared admitted-sample buffer |
| `workerBufferMaxBytes` | 256 KiB | telemetry-worker shared admitted-byte buffer |
| `batchMaxSamples` | 128 | one native telemetry batch |
| `batchMaxBytes` | 64 KiB | exact encoded native batch body |
| `outboxMaxCount` | 4 | retained telemetry-worker batches |
| `outboxMaxBytes` | 256 KiB | retained telemetry-worker outbox bytes |
| `maxRetryAttempts` | 3 | exact-body retry limit |
| `minimumFlushIntervalMilliseconds` | 250 ms | telemetry-worker policy flush cadence |
| `drainTimeoutMilliseconds` | 2,000 ms | producer barrier/settlement and terminal drain deadline |

The telemetry worker still exclusively validates and scrubs after ready and
before admission, sheds optional before required, batches, encodes batch bodies,
sequences batches, retries, owns the outbox, and posts with
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

### R67. Native Review publication is transactional and pane admission closes synchronously.

One pane-owned synchronous `ProductAdmissionGate` guards every product call, metadata producer, and content request. Teardown closes it and advances its epoch before retirement/drain. Post-close requests reject synchronously; in-flight work rechecks after suspension and before cache, metadata, pane-state, or response publication, so late completion cannot reopen admission.

The gate is a short lock/atomic owner, not an actor, and no lock spans `await`. Package/descriptor authority belongs to the per-pane publication coordinator, not `BridgePaneProductMetadataCoordinator`, worker, or cache. Stream uninstall removes delivery only; replacement reopens the accepted native package.

Publication is one transaction:

```text
active A -> stage isolated candidate B beside readable A
  pre-commit failure: discard B; A remains native- and worker-visible
  commit: atomically make B native authority before emitting worker-visible B
  delivery: route and transport-ack each B frame for stream pacing
  application: worker stages complete B, then swaps A -> B at the commit barrier
  receipt: worker sends review.publication.applied for B's exact publicationId
  post-commit failure: retain worker-visible A, reopen/resync Review B; never roll back B
  retire A: after exact B application receipt or settlement of every admitted A lease
  teardown: synchronously invalidate A, B, and retiring leases, then drain
```

Candidate B is invisible to pane presentation and worker render slices until its native commit. Multi-frame B metadata carries one stable native `publicationId` and remains worker-pending until its final commit barrier, so partial B cannot paint. Within one generation/package/query/source lineage, a distinct publication strictly advances revision; equal revision is exact replay and retains the existing `publicationId`. `stream.frameObserved` acknowledges safe transport routing immediately and controls stream pacing only; it never proves Review application and never retires A. The worker application transaction covers projection, runtime indexes, worker store, and the single B-bearing display publication. All fallible construction precedes that critical publication; demand, preparation, ancillary slices, and drain scheduling are post-commit derived effects and cannot roll back an applied B. After the atomic worker swap, the worker sends the typed `review.publication.applied` call with B's exact `publicationId`; native accepts only the current publication and then retires A. If B application fails, the worker keeps A readable, cancels and reopens only the Review subscription, and native replays the currently committed publication without resetting File or the shared metadata stream. A pre-commit delivery reservation may fail and preserve A; after native commit, delivery failure keeps A visibly stale with surface-scoped updating/health while native remains B and repairs/retries B. Pane presentation, descriptor authority, and worker metadata therefore never expose B -> A snapback. `BridgeReviewContentLoaderCache` owns provider I/O, validation, coalescing, cache, and eviction only. Permanent proof injects staging, reservation, commit, partial-delivery, application-receipt, and repair failures; covers immediate and in-flight post-close rejection; and proves worker uninstall/reinstall replays the committed native package.

### R68. Native pane activity controls work without erasing retained product state.

`BridgePaneActivityCoordinator` is the sole mint. Browser visibility and `activeViewerMode` are inputs to neither activity nor native work admission.

| Activity | Concrete native facts | Package/presentation and admitted work |
| --- | --- | --- |
| `foreground` | active residency; controller installed; pane visible in the active tab/arrangement or expanded drawer; not minimized or zoom-excluded; owning window visible, unminiaturized, and unoccluded; app active | retain both surface positions; admit interactive demand plus one latest refresh; key/focus affects rank, not state |
| `loadedHidden` | controller installed and admission open, but any foreground visibility/activity fact is false, including inactive tab/arrangement/drawer, minimized/zoom-excluded pane, hidden/miniaturized/occluded window, inactive app, or backgrounded residency | retain bounded package/cache and both positions; admit no body/prefetch/refresh; collapse invalidations to one dirty fact |
| `dormant` | pane record can be activated, but no Bridge controller, gate, worker, package, or presentation store has been created in this app lifetime | no work and no position owner; first activation creates authority and starts File/Review at canonical defaults |
| `closed` | close/teardown has begun or pane authority was explicitly revoked | reject synchronously; cancel/drain existing work; undo/reopen creates fresh authority |

A loaded pane does not transition to `dormant` in this recovery increment; hidden loaded panes stay `loadedHidden`. Position retention covers surface switches and foreground <-> loaded-hidden transitions. Dormant cold activation does not invent native UI-position persistence.

Returning dirty paints retained state immediately, shows only the active surface's inline `Updating files...` or `Updating review...`, and performs at most one latest refresh without switching modes. Both surfaces retain independent selection, tree, and content/continuous-diff positions.

Successful tab activation, pane focus, default jump, or new-tab creation records one runtime-only monotonic attendance ordinal; visibility and background refresh do not. `showBridgeReview`/`showBridgeFiles` choose the matching pane with the greatest ordinal, activate it, and select the command's named Review/File surface. A currently active match wins an ordinal tie; restored/never-attended ties use stable workspace tab then pane-layout order. With no match they create the named surface. Labels resolve `Open` versus `Go to` from the same resolver. `openBridgeReviewInNewTab`/`openBridgeFilesInNewTab` always create independent authority/query/presentation. Future commit comparison still uses native `agentstudio-git`.

### R69. Git reads use bounded worktree-keyed admission and true physical completion.

Git diff/tree/descriptor/content reads, hashing, package projection/encoding, cache work, and streaming never execute on `MainActor`. Synchronous libgit2 bodies run on a dedicated blocking queue, never the caller actor or Swift cooperative pool. Scheduler operation-class slots bound physical capacity and retain custody through true return; the queue owns execution, not admission.

One application-scoped, activity-ranked, worktree-keyed scheduler gives Review metadata and selected/visible content separate operation classes so a large diff scan cannot block a selected file. Logical timeout or cancellation ends the caller wait but never claims a synchronous native call stopped: its physical slot remains `draining` until libgit2 actually returns, continues consuming its operation-class physical capacity, and permits no replacement/backfill before true return. Late output is discarded by admission/publication epochs. No UUID ordering, one global serial Git actor, or unbounded replacement task may define fairness.
Watched-folder discovery, routine status, fetch/pull, checkout/worktree lifecycle,
and mutations retain their independently calibrated capacities and owners.

Proof covers five repositories with several worktrees, intentional duplicate
panes, a deliberately blocked native read, background event storms, and selected
foreground work. It reports bounded queue/physical/draining counts, zero producer
residue, MainActor/event-loop heartbeat, slow-worktree isolation, and applicable
foreground p95/p99. Concrete capacities are accepted only from this workload;
discovery/status budgets cannot be copied without measurement.

### R70. File and Review source construction is shared per worktree without sharing pane authority.
One application-scoped `BridgeWorktreeProductConstructionCoordinator` actor
owns worktree freshness, exact-key single-flight, consumer leases, and bounded
artifact accounting. Heavy work executes outside it through R69; this is one
registry with keyed entries, not an actor per worktree.
`BridgeSharedFileSnapshotBuild` publishes append-only immutable row windows and
then one completed snapshot containing canonical selectors, ignore/status facts,
ordered rows and freshness. Each pane binder owns source identity, subscription
generation, cursors and delivery. A pane opening mid-build replays retained
windows then tails independently; a slow pane cannot backpressure construction
or another pane. Completed snapshots serve later binders without enumeration.
`BridgeSharedReviewPackageTemplate` contains resolved base/head source identities,
semantic descriptor cores, ordered membership, groups/summaries and immutable
content locators. It contains no query/package/publication id, review generation,
pane timestamp, admission or lease. Descriptor semantic version is source-derived,
never pane generation. `BridgePaneReviewPackageBinder` stamps the pane overlay
and handle/publication leases without rewriting shared descriptor collections.
The registry entry owns the shared provider/client and locators; locator lifetime
is the union of artifact leases and R67 retiring-A leases. Content validates by
artifact lease plus digest, not equality with one latest pane generation.
File keys include canonical repo/worktree/root, cwd/path scope, status/ignore
semantics and freshness. Review keys include those owners, query/comparison
semantics, resolved base/head OID/content identities, path/file target and every
package-affecting filter/group/provenance/checkpoint field. Every new or refreshed
request resolves symbolic refs under R69 before template keying; ref motion yields
a new key even without a watched-root event. Transient ids, labels, timestamps,
pane activity and presentation are excluded. Equality/collision vectors bind this.
Canonical invalidation advances the worktree epoch before pane fan-out. A
completion may cache only under its captured current epoch; obsolete output
publishes nowhere. Exact duplicate foreground panes join one build, bind
independently, and fail independently. Hidden panes retain their old binding
and dirty fact without joining refresh. Consumer leases carry an entry nonce
and epoch. Closing one pane cannot affect another. Zero consumers cancel logical
waiters and drop payload immediately, while started native calls remain
draining under R69 until true return. Reopen never joins the coordinator entry
or payload tombstone; scheduler coalescing with the same physical read is allowed
when the worktree epoch and semantic identity are unchanged, and its result must
pass the reopened entry's current fences. Failures are not cached and the initial
policy retains nothing speculatively after the final lease.
Limits cover queued/live entries, materialized/in-flight bytes and draining
tombstones. S10 calibrates numbers; unbounded admission is forbidden. Proof
covers key equality/collision, progressive duplicate File open, ref motion,
invalidation, same- and cross-pane old-A locator safety, close/reopen, pane
independence, blocked return, owner-attributed retained bytes, build counts and
zero residue. Types structurally forbid pane authority in shared artifacts.
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
Swift -> comm worker         streamed metadata/content/response boundary
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
| expand/collapse | source reset or user/FE | source reset expands the complete authoritative tree locally; user toggle crosses 0 boundaries before paint, then FE -> comm worker publishes the expanded/collapsed fact | fresh/reset source paints fully expanded; later manual collapse paints in frame 1 and survives same-source appends; comm worker repairs invalid ids or supplies content deltas later | R41, R42, R45, R46, R49 |
| hunk expansion | user/FE/Pierre supported hunk control | complete full-source item expands through Pierre's supported item/render behavior; patch-derived partial item reports typed expansion unavailable when required source roles are absent | affordance paints locally; expansion is source-backed with stable anchor, never blank filler or a missing-window protocol | R42, R46, R57, R61, R63 |
| surface switch | user/FE app shell | 0 before shell paint; later FE -> comm worker `activeSurfaceUiIntent` with UI revision | frame-1 paints retained local shell; worker accepts `activeSurface`, demotes inactive foreground, and repairs later | R41, R42, R45, R49 |
| pane foreground | native workspace lifecycle | native activity -> pane admission/scheduler; retained worker stream repairs only when installed | retained active surface paints immediately; one dirty refresh may show only that surface's inline updating state | R42, R49, R67-R69 |
| pane loaded-hidden | native workspace lifecycle or tab switch | native activity -> pane admission/scheduler; filesystem invalidations collapse to one dirty fact | no remount, body demand, prefetch, or package refresh; both surface positions remain retained | R42, R63, R67-R69 |
| pane dormant/closed | native restore or close | dormant crosses no product boundary; close synchronously revokes admission before async cancellation/drain | dormant paints after first activation; closed work never paints or caches late output | R42, R63, R67-R69 |
| worktree open/jump | user/native command system | named show command resolves deterministic most-recent matching pane and records attendance; explicit new-tab allocates independent pane authority | jump selects Review or File as named while preserving both surfaces' positions; explicit duplicate starts independent presentation | R42, R67, R68 |
| Review publication A -> B | Swift source/publication coordinator | isolated B stages; native commits before worker-visible B; worker swaps only at complete commit barrier; post-commit delivery retries B | one paint belongs wholly to A or B; partial B, failure, or stream uninstall never produces B -> A snapback or revokes native B | R42, R63, R67 |
| product metadata/fact | Swift | Swift -> comm worker streamed product response; comm worker -> FE affected slices only | FE paints only after comm worker validates stream/epoch/sequence and publishes O(delta) slice patches | R42, R45, R48-R50, R67 |
| content-ready | Swift/comm worker executor | Swift -> comm worker streamed content response; comm worker -> FE paint-ready slice | no direct paint from response; comm worker validates current epoch and FE applies rank-first within R46 | R42, R44, R46, R48, R49, R52 |
| Review item hydration | FE/Pierre viewport | FE -> comm selected/visible item facts; comm -> Swift complete required roles as needed; comm -> FE complete ready item; FE -> comm disposition | existing DOM scrolls immediately; later complete item applies without prefix replay/filler and demand remains until painted | R42, R44, R46, R57, R61 |
| generation rotation | Swift source plus comm-worker epoch authority | Swift -> comm worker source fact; comm worker atomic epoch reset; comm worker -> FE reset slices | one paint observes either old epoch before reset or new epoch after reset; never half-old/half-new | R37, R42, R44, R45, R48, R49 |
| fetch failure | comm-worker executor/Swift content path | Swift -> comm worker failure or comm-worker local fetch failure; comm worker -> FE availability/health slice | selected identity paints explicit retry/unavailable/error state; FE never starts its own retry | R41, R42, R44, R48, R49 |
| reconnect | comm-worker transport | comm worker -> Swift product-stream reopen/subscriptions; Swift -> comm worker streamed resync; comm worker -> FE health/slice repairs | FE keeps local slices with explicit health/loading; stale incoming results cannot mutate active UI | R42, R44, R45, R48, R49 |
| telemetry batch | telemetry worker | main/comm compact samples -> telemetry worker; telemetry worker -> Swift telemetry POST | no user-visible paint; no product await/flush; required loss or gap fails proof | R41, R43, R48, R49, R62 |
| startup warm-up | FE activation/comm worker | FE -> comm worker warm-up fact; comm worker may prewarm cache/compute and Swift subscriptions | initial shell paints from retained local slices or honest loading; warm-up cannot block first paint | R41, R42, R44, R48, R49 |

### Boundary Sequence Invariant

The inventory above is normative. Local intent paints immediately from local
presentation state; accepted product truth, source fetch/stream, complete-item
publication, Pierre apply, and disposition then cross their typed boundaries in
that order. A source or epoch reset raises the applicable floor before new
publication. Stale work never mutates current UI. Pierre scrolls existing DOM
without protocol waits or app-side `scrollTop` writes, and active momentum
vetoes programmatic reveal. Telemetry observes this sequence on disjoint ports
and is never awaited by it.

## Migration Constraints

The cutover is atomic by authority, not by file age. Keep the custom-scheme POST
adapter, native source authority, pane worker, optional telemetry worker, and
bounded main/Pierre presentation. Historical UX/projection code is evidence,
never permission to restore a transport or truth owner. Compile-delete competing
carriers, feature workers, main/React data stores, page/native relays, resource
URL/GET paths, package-first loaders, flat/selected-only Review, FE product
owners, private Pierre traffic, and main/comm telemetry pipelines.

One converted surface has one reader, writer, projection, hydration path, and
emitter; no fallback or dual live path survives. Browser proof closes browser
claims only. Packaged proof must close streaming, admission, publication,
visibility, bounded Git execution, and Swift authority.

## Non-Goals

- No Pierre fork.
- No private Pierre worker protocol, proxy, local-path dependency, or `patch-package`; upstream changes ship as public releases.
- No claim that DOM materialization moves off the main thread.
- No `SharedArrayBuffer` requirement.
- No merge of the native metadata plane into the comm worker.
- No new browser-side diff/repo authority.
- No server lifetime surfaced to FE as user-visible protocol state.
- No permanent File View prefix/cap without measured failure evidence, user reconvergence, and a separately accepted contract.
- No shared cross-pane comm or telemetry worker.
- No global serial Git actor or actor-per-worktree execution owner; R70 is one
  application registry whose heavy work remains outside its actor.
- No commit-comparison UX in this recovery increment.
- No implementation phase plan in this document.

## Empirical Release Gates

Native gesture proof measures command, metadata, content, and telemetry delivery;
Pierre proof covers truthful order, far reveal, anchors, final traversal, bounded
heap/main work, and p99. Multi-worktree proof includes one blocked native read
without foreground starvation. Failure triggers reconvergence, never weaker proof,
fabricated extent, a silent File cap, or a Pierre modification.
