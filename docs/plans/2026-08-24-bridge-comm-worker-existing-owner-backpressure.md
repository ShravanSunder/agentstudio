# Bridge Comm-Worker Existing-Owner Backpressure Implementation Plan

Date: 2026-08-24

## Canonical record

- Originating planner: `plan-implementation`
- Planning result: `ready`
- Basis: `reviewed-three-artifact-design`
  - `docs/specs/2026-08-23-bridge-comm-worker-admission-backpressure/2026-08-23-requirements.md`
  - `docs/specs/2026-08-23-bridge-comm-worker-admission-backpressure/2026-08-23-specification.md`
  - `docs/specs/2026-08-23-bridge-comm-worker-admission-backpressure/2026-08-23-program-design.md`
  - owner-confirmed simplification `f7b123142`
  - recovery inventory
    `docs/wip/debugging/2026-08-24-comm-worker-overengineering-recovery-inventory.md`
- Planned at: branch `bridge-review-design-2026-08-14`, HEAD
  `a9509c13623efe6345251c9b9605011f24ae68f7`
- Terminal: `pr-ready-unmerged`
- Grouping: `single:bridge-comm-worker-existing-owner-backpressure`
- PR topology: `one-pr`
- Tracking: `none`

## Goal and boundary

Preserve the existing one-port model:

- Main -> worker: urgent actions direct; demand producer-owned/coalesced;
  ordered render dispositions batched at most 64, one batch in flight per
  surface.
- Worker -> Main: render jobs and patches remain individual; Review uses its
  existing three reserved plus nine dynamic positions and File uses its one
  selected operation plus latest waiting intent.
- Review releases its matching existing demand position only after the
  correlated ready/degraded response containing first exact accepted `queued`
  or terminal `rejected`/`superseded` posts successfully.
- File keeps its selected operation current through `queued` and `applied`, and
  settles it only after the correlated response containing exact `painted` or
  terminal `rejected`/`superseded` posts successfully. A newer File selection
  remains only the existing latest waiting intent until then.
- A thrown response post applies no owner effect. Silent loss remains with the
  existing timeout/probe/pending-ceiling/replacement path.

No new port, worker, delivery queue, render batch, scheduler, coordinator,
generic publication-capacity owner, retained cross-surface release state,
release generation, commit protocol, timeout, persistence, schema, native
interface, security, authentication, authorization, or UI work.

Never edit or stage the three protected PR2 research files or concurrent
UI/comment-animation files.

## Current owners

- `BridgeMainRenderDispositionAdmission` already owns receipt FIFO/batching in
  `bridge-main-render-disposition-admission.ts` (`89f172e8a`).
- Review currently releases its ledger record at preparation completion in
  `bridge-comm-worker-review-demand-scheduling.ts`; capacity is solely the 3+9
  records in `bridge-comm-worker-review-demand-ledger.ts`.
- File currently replaces its operation immediately in
  `bridge-comm-worker-runtime-protocol.ts`; the existing owners are
  `BridgeCommWorkerSelectedFileContentOperationController` and
  `latestSelectedFilePreparationRequest`.
- Runtime currently applies disposition effects before
  `dispatchBridgeCommWorkerRuntimeProductControl` posts the response. Moving
  lifecycle-eligible effects after the synchronous call makes a thrown post
  apply no owner effect and orders later render work behind the response on the
  same FIFO.
- `BridgeWorkerRenderFulfillmentRegistry` remains authoritative for exact
  attempt validation and disposition meaning.

## Slice graph and checkpoints

```text
S1 RED Review/File owner behavior
  -> S2 GREEN complete hold + response-before-owner-effect
  -> S3 actual MessageChannel proof
  -> S4 missing bounded-state telemetry
  -> S5 real 1,699-item comment journey
  -> S6 aggregate + packaged + implementation review + PR readiness
```

S1 and S2 form one red/green checkpoint. Never commit failing tests or a
runtime that stalls after twelve Review publications. Later checkpoints require
their scoped gates and all prior gates green; stage exact paths only.

## S1 — RED existing-owner tests

Add tests only:

- `BridgeWeb/src/core/comm-worker/bridge-comm-worker-review-demand-ledger.unit.test.ts`
- `BridgeWeb/src/core/comm-worker/comm-runtime-protocol.existing-owner-backpressure.unit.test.ts`

Reuse current runtime/file-product test support. Prove current code fails
because: (1) after twelve published Review attempts item thirteen starts before
the queued response; (2) invalidating a published Review item releases early;
(3) File B replaces published A before A's painted or terminal response rather
than waiting through A's queued and applied responses; and (4) a foreign attempt
can never satisfy the expected exact owner effect.

```bash
pnpm --dir BridgeWeb exec vitest --config vitest.config.ts run \
  src/core/comm-worker/bridge-comm-worker-review-demand-ledger.unit.test.ts \
  src/core/comm-worker/comm-runtime-protocol.existing-owner-backpressure.unit.test.ts
```

Retain failure output. Repair fixture-only failures before behavior edits. Do
not commit S1.

## S2 — GREEN complete existing-owner correction

Write surfaces:

- `bridge-comm-worker-review-demand-ledger.ts`
- `bridge-comm-worker-review-demand-scheduling.ts`
- `bridge-comm-worker-review-preparation.ts`
- `bridge-comm-worker-review-runtime.ts`
- `bridge-comm-worker-runtime-protocol.ts`
- `bridge-comm-worker-selected-file-content-operation.ts`
- replace misleading `bridge-comm-worker-render-publication-release.ts` with a
  narrowly named post-response existing-owner settlement module
- S1 and adjacent existing Review/File/render-fulfillment tests

Implementation:

1. Return the exact render receipt identity from a successful Review
   publication and retain it on the existing active ledger record. Preserve
   pre-publication stale/retry/terminal/cancel/teardown behavior.
2. Published Review invalidation removes obsolete intent but keeps the record.
   After response post, the first exact accepted queued or terminal
   rejected/superseded releases it; later applied/painted receipts do not release
   twice, and stale demand is not revived.
3. If File A has published, store B only as the existing latest request. Keep A
   current through its exact queued and applied responses. Only after A's exact
   painted or terminal rejected/superseded response posts and A settles, run the
   existing latest-request currentness check and drain.
4. Apply the batch and construct its current typed response, synchronously call
   `dispatchBridgeCommWorkerRuntimeProductControl`, then apply only exact,
   lifecycle-eligible Review/File effects and request existing drains. Let a
   post throw escape before effects.
5. Preserve fulfillment source/currentness fences and later applied/painted
   transitions. Preserve the existing File operation's install, render, paint,
   file-content, and worker-application lifecycle evidence. Do not split File
   admission from lifecycle or add another owner, state machine, or queue.

```bash
pnpm --dir BridgeWeb exec vitest --config vitest.config.ts run \
  src/core/comm-worker/bridge-comm-worker-review-demand-ledger.unit.test.ts \
  src/core/comm-worker/bridge-comm-worker-review-demand-scheduling.unit.test.ts \
  src/core/comm-worker/bridge-comm-worker-selected-file-content-operation.unit.test.ts \
  src/core/comm-worker/comm-runtime-protocol.existing-owner-backpressure.unit.test.ts \
  src/core/comm-worker/comm-runtime-protocol.file-product.unit.test.ts \
  src/core/comm-worker/comm-runtime-protocol.render-fulfillment.unit.test.ts
pnpm --dir BridgeWeb typecheck
git diff --check
```

Checkpoint only with S1 green, item thirteen starting after one exact Review
release, File B waiting through A queued and applied then starting only after A
painted or terminal rejected/superseded, post throw applying no owner effect,
and the full focused set green. Commit the whole behavior slice; never the hold
without its matching release or settlement.

## S3 — Actual `MessageChannel` integration

Add
`BridgeWeb/src/core/comm-worker/bridge-comm-worker-duplex-backpressure.integration.test.ts`.
Use a real `MessageChannel`, production runtime, and production codecs. Wait on
exact messages/identities; no sleeps, frames, fake FIFO, or direct-handler
ordering oracle.

Prove:

- twelve Review publications cross; thirteen waits;
- the correlated response for the queued batch reaches Main before publication
  thirteen;
- an urgent annotation action admitted before a later receipt batch begins
  worker handling first and its exact outcome is not starved;
- File B waits behind published A through A's queued and applied responses;
  after A's painted or terminal rejected/superseded response, Main observes
  that response before B publishes;
- using the existing injectable port only for synchronous throw, a failed
  Review queued/terminal response starts no Review thirteen, and a failed File
  painted/terminal response starts no File B; neither failure requests a drain.
  Do not label this peer-close detection.

```bash
pnpm --dir BridgeWeb exec vitest --config vitest.integration.config.ts run \
  src/core/comm-worker/bridge-comm-worker-duplex-backpressure.integration.test.ts
pnpm --dir BridgeWeb exec vitest --config vitest.config.ts run \
  src/core/comm-worker/bridge-pane-runtime-render-disposition-admission.unit.test.ts \
  src/core/comm-worker/bridge-main-render-disposition-admission.unit.test.ts
git diff --check
```

Checkpoint only with real FIFO response-before-owner-effect proof and all S2
gates green.

## S4 — Missing bounded-state telemetry only

Add only worker-to-Main published-but-unsettled current count, high-water mark,
oldest age, surface, and the closed response-post-before-owner-effect phase.
Derive it from held Review records and the selected File operation; telemetry
must remain fail-open and must never control an owner effect.

Write surfaces:

- `BridgeWeb/src/core/comm-worker/bridge-render-disposition-telemetry.ts`
- S2 Review/File owners only at their existing transitions
- `BridgeWeb/scripts/dev-server/bridge-dev-telemetry-otlp.ts`
- `BridgeWeb/scripts/dev-server/bridge-dev-telemetry-render-disposition.unit.test.ts`
- `Sources/AgentStudio/Infrastructure/Diagnostics/BridgeRenderDispositionTelemetryContract.swift`
- `BridgeTelemetryWireSchema+Allowlists.swift`
- `BridgeTelemetryWireSchema+AuxiliaryContracts.swift`
- `AgentStudioOTLPPerformanceMetrics.swift`
- adjacent existing Swift diagnostics tests

Allow only closed counts/durations/phases/results/surface; reject identity,
path, body, selection, payload, raw error, capability, and secret fields.

```bash
pnpm --dir BridgeWeb exec vitest --config vitest.config.ts run \
  scripts/dev-server/bridge-dev-telemetry-render-disposition.unit.test.ts \
  src/core/comm-worker/bridge-comm-worker-review-demand-ledger.unit.test.ts \
  src/core/comm-worker/comm-runtime-protocol.existing-owner-backpressure.unit.test.ts
mise run test:swift -- --filter AgentStudioOTLPRenderDispositionPerformanceMetricsTests
mise run test:swift -- --filter BridgeTelemetryWireSchemaTests
mise run lint
git diff --check
```

Checkpoint only when scrubbing tests pass and S3 proves correctness without
using telemetry as its oracle.

## S5 — Permanent 1,699-item root-plus-five-reply journey

Write surfaces:

- parameterize `BridgeWeb/tests/e2e/bridge-viewer-vite-product-fixture.ts` so
  routine tests keep 16 changed files and this journey requests 1,699;
- add
  `BridgeWeb/tests/e2e/bridge-viewer-vite-annotation-backpressure-journey.ts`;
- register it from
  `BridgeWeb/tests/e2e/bridge-viewer-vite-product.e2e.test.tsx`;
- extend existing dev telemetry parsing only for S4 observations.

The permanent test creates a disposable real Git worktree and isolated SQLite
roots; starts owned Vite plus the Swift development backend; loads exactly
1,699 Review items through the production worker/channel; creates one root and
five sequential replies; awaits every generated `reply.create`, `draft.flush`,
and `draft.save` exact outcome; remains semantically inspectable; reloads and
verifies all six bodies from durable projection; stops demand and waits for
receipt and Review/File state to drain. Fail on admission-caused timeout, lease
expiry, amplification, overload, replacement, unbounded count/age, or wrong
response/publication order. Use bounded protocol waits, never sleeps.

```bash
pnpm --dir BridgeWeb exec vitest --config vitest.e2e.config.ts run \
  tests/e2e/bridge-viewer-vite-product.e2e.test.tsx \
  -t "1,699-item Review keeps root and five replies responsive and durable"
mise run test:bridge-web:e2e
```

Human checkpoint: use the documented Fast UI Loop with a fresh `mktemp` data
root, `--seed-worktree "$PWD"`, `--seed-target HEAD`, and
`pnpm --dir BridgeWeb run dev`; provide the exact localhost Review URL and owned
PIDs. Verify loaded count and one manual save without touching stable app data.
Commit only when the permanent journey passes and that committed HEAD is
human-testable.

## S6 — PR-ready-unmerged proof

On exact candidate HEAD:

```bash
mise run format
mise run lint
pnpm --dir BridgeWeb typecheck
mise run test:bridge-web
mise run bridge-web-build
mise run test:swift:webkit
mise run test
git diff --check
mise run run-bridge-packaged-product-journey
mise run verify-bridge-packaged-product-journey
```

The packaged WKWebView proof must cover the same product route, comment
settlement, retirement/replacement clearing, and marker-scoped telemetry; DOM
fixtures are not packaged proof. Then run one bounded independent implementation
review on exact HEAD. Remediate only parent-validated in-scope findings, rerun
affected gates plus `mise run test`, and prepare one PR without merging.

## Obligation/proof map and integration gates

| Obligation | Slice and proof |
| --- | --- |
| One port, direct actions, producer demand | S2-S3 diff/static absence plus production runtime/channel |
| <=64, one receipt batch in flight | preserved baseline plus S3 regression |
| Review 3+9 and File A/B bound | S1-S3 state tests plus actual-channel order |
| Post throw applies no owner effect | S2-S3 injected synchronous failure |
| Source/currentness truth | S2-S3 hostile identity and fulfillment tests |
| Bounded counts/age/order | S4 scrubbing plus S5 fresh marker-scoped run |
| Root + five replies + reload | S5 real Vite/Swift/worktree/SQLite E2E |
| Packaged and repository health | S6 packaged verifier, aggregate, exact-HEAD review |

Earliest integration gates: S2 joins owner state to runtime call order; S3 joins
both FIFO directions; S5 joins browser/worker/Swift/Git/SQLite; S6 joins the
packaged WKWebView boundary.

## False-green risks

- Ledger/fake-dispatch tests cannot prove FIFO; S3 must observe a real channel.
- Applying an owner effect before response post can pass state tests while
  ordering later work ahead of its acknowledgement.
- Review release on applied/painted holds longer than its confirmed delivery
  boundary; Review releases after first exact queued or terminal
  rejected/superseded response.
- File settlement on queued/applied breaks its existing lifecycle owner; File
  remains current until painted or terminal rejected/superseded response.
- A 16-file fixture, mocked backend, visible text without exact outcomes, or no
  reload cannot satisfy S5.
- Telemetry ingestion time is not application latency and telemetry is not the
  FIFO correctness oracle.
- Focused green is not packaged or aggregate readiness.

## Scope checks after every checkpoint

```bash
rg -n 'publicationCredit|releaseGeneration|releaseCandidate|capacity_unavailable|commitPublicationRelease|pendingPublicationRelease|cross-surface prefix|physical tombstone|release-pending-ACK' \
  BridgeWeb/src/core/comm-worker BridgeWeb/src/core/demand BridgeWeb/scripts/dev-server \
  Sources/AgentStudio/Infrastructure/Diagnostics Tests/AgentStudioTests/Infrastructure/Diagnostics
git status --short
git diff --cached --name-only
git diff --check
```

`rg` must return no match. Protected files stay untracked and unstaged.

## Stop/replan conditions

Stop with exact source/test evidence if the existing response cannot post
synchronously before settlement; Review cannot retain its exact published
attempt without a second owner; File cannot serialize A/B without losing a
required lifecycle contract; post throw misses existing replacement
containment; Review queued/terminal release weakens fulfillment identity, or
File cannot remain current through queued/applied and settle on painted/terminal
without a new owner; the change requires a new public/product contract, port,
queue, scheduler, persistence, native/security boundary, timeout, or proof
weakening; or the corrected 1,699-item run remains unbounded. In the last case return its
marker-scoped counts, ages, timeouts, and call path to Program Design—do not add
render batching or another queue from implementation.
