# BridgeWeb Frontend Runtime Parity — Implementation Plan

Date: 2026-08-02

## Planning basis

Authoritative sources:

- `../2026-08-02-bridgeweb-frontend-runtime-parity-user-requirements.md`
- `../2026-08-02-bridgeweb-frontend-runtime-parity.md`
- `../2026-08-02-bridgeweb-frontend-runtime-parity-program-design.md`

Current implementation base is `343b33193d9c101901f37cac0be6da0ce9938a2a`.
`origin/main` is one unrelated minimized-pane-resize commit ahead. Before code
execution, re-check the exact base and Bridge source graph; do not merge or
rebase without the required git authorization.

## Goal

Make packaged Bridge and the Vite development surface construct one shared
frontend runtime. They vary only in the request endpoint adapter, the existing
shared admission value, and the platform worker factory. Both environments use
one typed navigation command through product-session metadata, the comm worker,
and `BridgeApp`.

## Non-goals and complexity ceiling

- Do not replace or extract either backend.
- Do not add a Swift server or target, controller, store, coordinator,
  persistence owner, recovery system, compatibility path, or feature flag.
- Do not alter Files, Review, Search, Filters, or View Settings behavior.
- Do not move queueing, admission, retry, decoding, stream consumption,
  response lifetime, or lifecycle into the injected request executor.
- Do not change worker-health, retry, replacement, or public IPC success/error
  semantics while cutting over the frontend path.
- Do not weaken packaged Bridge behavior to accommodate Vite.
- Do not create a second navigation protocol, acknowledgement, or target-render
  receipt.
- Do not edit generated BridgeWeb resources directly.

The request executor is a stateless I/O adapter: map one already-built closed
product route, perform exactly one `fetch`, and return the raw `Response` or
error unchanged.

## Execution strategy

The implementation is intentionally serial. The slices share worker entry,
transport, navigation-contract, and `BridgeApp` files; parallel implementation
would create conflicting ownership and make the hard cut difficult to verify.

```text
gate 0: verify branch, current source, and existing focused tests
  |
slice 1: inject the tiny request executor and shared admission value
  |
slice 1 gate: focused transport/architecture red-green + BridgeWeb check
  |
slice 2: atomically cut Vite and packaged navigation to the shared command
  |
slice 2 gate: TS + Swift contract, Vite, and packaged worker/WKWebView proof
  |
integration gate: inspect the exact diff for hard-cut and scope boundaries
  |
full relevant validation: BridgeWeb, Swift, lint, build, manual runtime proof
  |
implementation-review-swarm
  |
implementation-pr-wrapup
```

## Slice 0 — Re-anchor and establish failing witnesses

Requirements: all; especially R6.

Actions:

1. Record the exact branch, HEAD, and merge base.
2. Re-run searches for the current direct Vite navigation prop, Vite route
   alias, route-derived admission value, and packaged
   `__bridge_select_review_item` event.
3. Identify the smallest existing test file for each behavior before editing.
   Add focused tests rather than growing already-large transport or Vite E2E
   files.
4. Run each new or changed behavior test before production edits and retain its
   expected failure as the red witness.

Checkpoint:

- each material change has a focused red witness;
- the branch differs from the planning base only as explicitly understood; and
- no unrelated Mindle sidecar is staged or edited.

Stop trigger: if current source no longer matches the selected owners or a
required change needs a new owner/public contract, return to program design.

## Slice 1 — One shared runtime with two tiny endpoint adapters

Requirements: R1, R2, R4, R6.

Behavior:

- packaged construction injects the URL-scheme adapter and omits the admission
  value, so shared admission uses twelve;
- Vite construction injects the HTTP adapter and explicitly passes four; and
- the same product-session and transport owners encode, admit, execute, decode,
  retry, cancel, and release requests in both environments.

Implementation steps:

1. Define one closed product-route identity and one required
   `BridgeProductRequestExecutor` callable in the shared comm-worker boundary.
2. Make the shared worker entry a side-effect-free registrar that requires the
   executor and accepts the existing admission maximum with a default of
   twelve.
3. Add thin executable packaged and Vite worker entries. Each constructs only
   its endpoint adapter and platform inputs; Vite also passes four.
4. Thread the executor into the existing product-session authority and product
   transport. Replace their direct environment route fetches with one executor
   call after existing admission.
5. Replace route-string-derived admission with the construction value. Preserve
   the existing queue, rank, pause/resume, abort-before-fetch, body settlement,
   release, and disposal code in its current shared owner.
6. Point packaged build configuration to the packaged entry and the Vite worker
   factory to the Vite entry. Remove the Vite product-route alias and obsolete
   development route substitution.
7. Extend the existing architecture and packaged-asset checks so shared product
   sources cannot import either endpoint adapter or detect the environment.

Likely write surfaces:

- `BridgeWeb/src/core/comm-worker/bridge-comm-worker-entry.ts`
- `BridgeWeb/src/core/comm-worker/bridge-product-session-authority.ts`
- `BridgeWeb/src/core/comm-worker/bridge-product-transport.ts`
- `BridgeWeb/src/core/comm-worker/bridge-product-content-response-admission.ts`
- the product-route contract and two thin worker-entry modules
- `BridgeWeb/vite.config.ts`
- `BridgeWeb/tsdown.config.ts`
- existing architecture, packaged-asset, transport, and worker-entry tests

Focused red/green proof:

- each adapter maps every closed route, forwards `RequestInit` and abort signal
  unchanged, performs exactly one request, and returns the identical response or
  rejection;
- packaged omission produces twelve and Vite construction produces four;
- a hidden Review waiter remains before the executor call;
- aborting a waiting request performs zero executor calls;
- request failure and response EOF/error/cancel release the shared lease once;
- after queued abort, response settlement, and disposal, fresh requests can
  consume the complete configured capacity with no waiter/lease residue;
- the existing real Vite carrier integration holds four HTTP content responses,
  proves a fifth has not invoked the executor, proves metadata plus
  observation/control progress, then releases content and reaches zero
  residue; and
- source-boundary checks fail on shared imports of endpoint adapters or
  environment tests.

Slice gate:

- focused executor/admission/architecture tests pass;
- `mise run test:bridge-web:check` passes; and
- the executor implementation has no class, state, queue, wrapper, retry,
  decoder, or lifecycle callback.

Split/replan trigger: if the adapter needs to observe response-body settlement
or own a second queue, stop—the implementation has crossed the accepted
boundary.

## Slice 2 — Atomic shared-navigation cutover for Vite and packaged Bridge

Requirements: R1, R3, R4, R5, R6.

Behavior:

- Vite URL intent, including exact `README.md`, enters the existing development
  product-session bootstrap;
- the existing dev carrier binds exact intent to the File or Review source it
  actually accepted and publishes the shared navigation metadata frame;
- the comm worker strictly validates and forwards it; and
- packaged Swift publishes surface-only and exact-Review intent through that
  same frame instead of a direct page event;
- `BridgeApp` admits, remembers, revokes, and applies either producer's command
  using the accepted source tuple before existing Files/Review target owners
  run; and
- the contract changes as one checkpoint. There is no independently green
  state after the TypeScript frame changes and before Swift is updated, and no
  temporary compatibility schema is allowed.

Implementation steps:

1. Move the navigation discriminated union into the shared product-session
   contract. Hard-cut the `initialize` and `restoreMemory` vocabulary into
   `activateContext` and `activateTarget`.
2. Reuse the existing display-path validator in the Vite bootstrap, shared
   TypeScript navigation schema, and Swift navigation encoder/decoder. Reject
   an invalid path before any producer retains or publishes it.
3. Extend the existing metadata and worker-to-main frame; do not add another
   protocol or state owner.
4. Carry deterministic Vite intent in the existing dev bootstrap/session. Bind
   exact targets only after the development adapter exposes the actual accepted
   File or Review source tuple.
5. When opening a Vite subscription, enqueue `subscription.accepted` sequence
   zero before returning control acceptance, then publish navigation through
   the same writer without bypassing its existing per-frame observation gate.
6. Project Review's already-existing accepted metadata source id, Review
   generation, and package id to `BridgeApp`; do not fabricate native stream or
   publication identity.
7. Make `BridgeApp` the single source-admission owner. On source rotation,
   synchronously remove stale child input and remembered target before a
   surface-only activation can restore it.
8. Change existing Files/Review target-owner replay identity from command id
   alone to command id + binding revision + complete source tuple.
9. Remove direct Vite navigation props and fixture-only product paths from the
   React entry/router. Keep test-only fixtures inside test harnesses.
10. Extend the existing Swift navigation model, selection authority, transport
   frame, and metadata coordinator to carry the same surface plus optional
   exact target and complete source tuple.
11. Reuse the existing pane/session/worker binding revision. Exact-Review IPC
   awaits native command binding and publication into the current product
   session, then returns the existing `selected: true` result without waiting
   for the active-viewer receipt or target rendering. Preserve the existing
   package-unavailable, item-not-found, and generic publication-failure mapping;
   add no continuation waiter, deadline, or public failure reason.
12. Replace `selectReviewItemForIPC`'s direct page event with committed-package
    validation followed by the retained shared command. Remove the React
    `__bridge_select_review_item` listener and direct-event tests in the same
    checkpoint.

Likely write surfaces:

- shared product-session and worker contracts/projections
- Vite bootstrap host, dev carrier, and dev session
- `BridgeWeb/src/app/bridge-app.tsx` and existing File/Review mode/controller
  files
- Vite fixture parsing, entry, and router modules
- `BridgePaneSurfaceSelectionAuthority.swift`
- `BridgePaneController+SurfaceSelection.swift`
- `BridgePaneController+IPCProjection.swift`
- existing Swift Bridge product frame/factory/metadata coordinator models
- focused contract, worker integration, browser, and Vite E2E tests
- existing Swift selection, IPC, metadata, and WebKit journey tests

Focused red/green proof:

- strict schema rejects malformed commands before React state changes;
- 4,096-byte File and Review paths are accepted, while 4,097-byte paths are
  rejected before Vite pending-session retention and by Swift encoding/decoding;
- `subscription.accepted` sequence zero is enqueued before a concurrent
  sequence-one update while existing per-frame observation pacing is preserved,
  without a wall-clock test;
- pending exact target waits for the accepted source;
- mismatch and stale revision change neither active surface nor child target;
- File source-id or subscription-generation change revokes pending and
  remembered targets;
- Review metadata-source, Review-generation, or package-id change revokes
  pending and remembered targets;
- Review publication-id-only change does not revoke a valid target;
- Review-first startup preserves the packaged baseline's canonical eager File
  and Review product subscriptions; a pending exact File command may use only
  the existing headless source reporter needed to expose its accepted source;
- identical command/revision/source replay applies once;
- the same logical intent with a newer binding revision and newly accepted
  source applies once;
- old-source replay after rebind changes neither surface nor target;
- the real Vite server opens Files, Review, and exact `README.md` only after the
  metadata/worker path;
- Swift and TypeScript strict frame fixtures agree;
- IPC returns after native binding/publication without waiting for an
  active-viewer receipt, keeps the existing selected/error vocabulary, and
  claims neither React application nor target rendering;
- packaged IPC exact Review traverses Swift authority, metadata, the real comm
  worker, and WKWebView; and
- static inspection finds neither the old frame nor the direct Review-selection
  page event.

Slice gate:

- focused schema, admission, worker, and browser tests pass;
- `mise run test:bridge-web:e2e` passes; and
- focused Swift selection, metadata, and IPC tests pass;
- the packaged real-git File/Review WebKit journey passes with shared-path
  attestation;
- searches find no product entry/router navigation prop, runtime environment
  branch, old navigation frame, or direct page event; and
- `mise run lint` passes for the affected Swift/architecture surface.

Split/replan trigger: if source admission cannot remain in `BridgeApp` plus the
existing target owners, or if IPC cannot preserve its existing result/error
boundary without a waiter or new public failure meaning, stop before adding a
store, coordinator, polling path, deadline, second receipt, or acknowledgement.

## Requirements/proof matrix

| Requirement | Owning slice | Proof modality and layer | Evidence source | Freshness guard | Red/green |
| --- | --- | --- | --- | --- | --- |
| R1 shared runtime | 1–2 | architecture unit + real Vite E2E + packaged WebKit integration/manual journey | current source scanner, owned Vite server, freshly packaged app | exact final HEAD and freshly built assets | required |
| R2 injected transport | 1 | callable unit + shared-admission unit/integration | adapter counters, real shared admission owner, transport tests | no route-derived limit; real default 12 and explicit 4 | required |
| R3 shared navigation | 2 | schema unit + real-worker integration + browser + Swift/WebKit | strict frame tests, comm worker, accepted source facts, packaged authority | bind target to the source produced in the same run | required |
| R4 environment boundary | 1–2 | architecture/static negative tests | current import/source graph | scan current production graph, not frozen manifest | required |
| R5 Vite/HMR | 2 | real Vite browser E2E and manual browser observation | existing owned Vite server and shared product | observe update from the current server/runtime | required |
| R6 hard cut/no PR2 | 0–2 | static negatives + accepted-base-to-final diff inspection | parent inspection and implementation review | exact final diff and `Package.swift`/server-target check | required |

## Final validation ladder

Run focused red/green commands during each slice. At integration, run from the
repository root:

```text
mise run test:bridge-web:check
mise run test:bridge-web:unit
mise run test:bridge-web:integration
mise run test:bridge-web:e2e
mise run bridge-web-build

mise run test:swift -- --filter BridgePaneSurfaceSelectionContractTests
mise run test:swift -- --filter WebKitSerializedTests/BridgePaneControllerIPCProjectionTests
mise run test:swift -- --filter WebKitSerializedTests/BridgeProductRealGitFileAndReviewWebKitTests
mise run lint

mise run test
```

Manual Vite HMR proof uses the existing development server, not a new harness:

1. Start the existing Vite development server and open the shared product
   journey.
2. Record the current worker/runtime identity and document navigation state.
3. Apply and immediately reverse one harmless frontend source edit.
4. Observe a Vite HMR update without full-page navigation.
5. Re-run exact `README.md` navigation and confirm the shared runtime remains
   functional.
6. Confirm the final diff contains no proof-only edit.

Manual/native packaged proof uses the existing exact tasks:

```text
mise run observability:up
mise run run-bridge-packaged-product-journey
mise run verify-bridge-packaged-product-journey
```

Require current bundle/asset attestation, authenticated exact Review selection,
matching native/DOM selected identity, and PID-targeted visual observation. The
verifier's bounded state polling is not itself a product change; do not rewrite
it unless a demonstrated in-scope failure prevents the journey.

Record each command, exit code, and pass/fail count. Browser proof does not
substitute for packaged WKWebView/native proof, and a packaged test does not
substitute for the manual runtime journey.

## Final scope and quality inspection

Before implementation review:

1. Search for direct Vite navigation props, Vite route aliases, runtime
   environment checks, route-derived admission, and
   `__bridge_select_review_item`.
2. Inspect the exact accepted-base-to-final diff for a new backend, server
   target, controller, store, lifecycle owner, response wrapper, compatibility
   path, or generated-resource edit.
3. Confirm packaged uses the omitted default twelve and only Vite supplies
   four.
4. Confirm the executor contains only endpoint mapping and one network call.
5. Confirm navigation uses the existing display-path validator and the Vite
   subscription-open path preserves sequence zero before sequence one.
6. Confirm no unrelated Mindle sidecar is staged.

## Security and reliability boundary

Security context: applicable because capability-bearing requests cross the
injected network adapter.

The executor forwards method, headers, body, credentials, and abort signal
without logging, persisting, reinterpreting, or retrying them. Existing strict
schemas, capability checks, source authority, cancellation, and failure
classification remain unchanged. No authentication or authorization contract
change is permitted.

## Rollback and recovery

This is a hard cut, so rollback is commit-level rather than a runtime fallback.
Each atomic checkpoint must be green before the next checkpoint. Slice 2 may
use internal serial steps, but it has only one gate after both TypeScript and
Swift producers/consumers cut over. If a checkpoint cannot meet its proof gate
without widening ownership, revert only that uncommitted checkpoint and return
to the owning design artifact; do not add a compatibility branch.

## Completion route

After implementation and all proof gates:

1. run `shravan-dev-workflow:implementation-review-swarm` against the exact
   branch diff and validate every finding;
2. address only confirmed in-scope issues through
   `shravan-dev-workflow:implementation-execute-plan`; and
3. run `shravan-dev-workflow:implementation-pr-wrapup` to open/update the PR,
   monitor checks, validate bot conversations, and prove PR readiness.

The default terminal is PR-ready and unmerged. Merge requires separate explicit
authorization.
