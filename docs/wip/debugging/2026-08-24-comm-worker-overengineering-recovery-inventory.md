# Comm-Worker Overengineering Recovery Inventory

Date: 2026-08-24

## 2026-08-24 — Inventory before cleanup

This is the pre-cleanup inventory requested by the owner. No source,
Specification, or Program Design cleanup was performed while producing it.
The only write in this phase is this inventory.

Branch: `bridge-review-design-2026-08-14`

HEAD: `df825115c1ff753db8a4da5508ef920da46d2b90`

Protected concurrent work, never edit or stage:

- `docs/specs/2026-08-06-worktree-annotations/pr2-vision-and-product-research.md`
- `docs/wip/2026-08-19-pr2-guided-review-vision-and-prior-art.md`
- `docs/wip/2026-08-19-pr2-pierre-calldiff-coordinate-and-call-graph-research.md`
- UI/comment-animation files owned by the other agent

## Owner-confirmed boundary

Preserve:

- one existing `MessageChannel`;
- direct urgent annotation commands;
- producer-owned and coalesced demand;
- ordered render-disposition queueing and batching;
- one in-flight render-disposition batch per surface;
- fair transport so urgent commands are not starved;
- bounded worker-to-main render production through existing Review and File
  owners;
- existing worker replacement, timeout, probe, and containment behavior;
- source-scrubbed measurements and the real Swift/Vite/worktree/SQLite proof
  journey.

Remove or reject:

- generic publication credits;
- physical-credit tombstones as a second ownership system;
- retained cross-surface release prefixes;
- release generations;
- prevalidate/commit protocols;
- a cross-registry release coordinator;
- new ports, schedulers, job queues, render batching, persistence, native
  interfaces, security work, or UI work.

## Proven current call path

### Main to worker

Urgent actions already bypass render-disposition admission. The RPC client
dispatches immediately, and the ready pane session posts each command directly
to the single worker port:

- `BridgeWeb/src/core/comm-worker/bridge-worker-rpc-client.ts:96`
- `BridgeWeb/src/core/comm-worker/bridge-pane-comm-worker-session.ts:157`
- `BridgeWeb/src/core/comm-worker/bridge-pane-comm-worker-session.ts:282`

Render dispositions have a separate per-surface admission owner. It retains an
ordered pending queue, dispatches one batch, and admits the next batch only
after terminal lifecycle settlement:

- `BridgeWeb/src/core/comm-worker/bridge-main-render-disposition-admission.ts:82`
- `BridgeWeb/src/core/comm-worker/bridge-main-render-disposition-admission.ts:133`
- `BridgeWeb/src/core/comm-worker/bridge-main-render-disposition-admission.ts:170`

Review demand remains producer-owned and latest-state/coalesced. File retains
one latest selected preparation request plus its selected-operation owner:

- `BridgeWeb/src/core/comm-worker/bridge-comm-worker-reconciler.ts:28`
- `BridgeWeb/src/core/comm-worker/bridge-comm-worker-review-demand-ledger.ts:96`
- `BridgeWeb/src/core/comm-worker/bridge-comm-worker-runtime-protocol.ts:171`
- `BridgeWeb/src/core/comm-worker/bridge-comm-worker-runtime-protocol.ts:302`

### Worker to main

The remaining measured failure is producer release timing. At committed HEAD,
Review frees its existing 3 reserved plus 9 dynamic positions when preparation
completes, allowing those positions to cycle through the 1,699-item comparison
while prior render jobs and patches remain in the worker-to-main FIFO.

The existing disposition handler already provides the narrow correction seam:

1. apply the received disposition batch;
2. construct the existing correlated ready/degraded response;
3. post that response synchronously;
4. only after successful post, release the matching existing Review position
   or settle the existing File operation;
5. run the existing preparation drain.

No new coordinator, queue, generation, or generic credit registry is required.
The current runtime order is wrong for this boundary: it applies File/lifecycle
effects before `dispatchBridgeCommWorkerRuntimeProductControl` posts the
correlated response. The extracted effect seam must move after successful
response post.

Relevant anchors:

- `BridgeWeb/src/core/comm-worker/bridge-comm-worker-runtime-protocol.ts:744`
- `BridgeWeb/src/core/comm-worker/bridge-comm-worker-runtime-protocol.ts:761`
- `BridgeWeb/src/core/comm-worker/bridge-comm-worker-runtime-protocol.ts:855`
- `BridgeWeb/src/core/comm-worker/bridge-comm-worker-render-disposition-application.ts:21`
- `BridgeWeb/src/core/comm-worker/bridge-comm-worker-render-publication-release.ts:8`

### Recovery boundary

A thrown response `postMessage` error reaches existing Worker error handling
and replacement. Owner-initiated close already occurs during retirement. A
silently closed peer is not independently detectable at this boundary:
`postMessage` may drop silently, Main later times out, and existing
timeout/probe/pending-ceiling containment applies. The cleanup must state that
honestly. It must not add a close detector or coordination protocol unless the
owner separately expands scope.

## Commit inventory

### `89f172e8a` — preserve

This is the requested first correction: ordered render-disposition batching,
one-in-flight admission, semantic-class and queue measurements, and the related
tests/contracts. It reduced measured main-to-worker queue wait and remains the
baseline to preserve.

### `adf0ac2ba` — rewrite, do not revert blindly

| Path | Classification | Recovery action |
| --- | --- | --- |
| `docs/specs/2026-08-23-bridge-comm-worker-admission-backpressure/2026-08-23-specification.md` | REWORK | Preserve observable queueing, batching, fairness, bounded progress, and proof obligations. Remove mechanism-level credit/generation implications and describe silent-loss recovery accurately. |
| `docs/specs/2026-08-23-bridge-comm-worker-admission-backpressure/2026-08-23-program-design.md` | REWORK | Remove credits, tombstones, prefixes, generations, commit coordination, and their failure machinery. Retain measured duplex evidence, one port, existing-owner bounding, smallest call-order change, and proof pyramid. |

Commit size: 662 insertions and 155 deletions across the two artifacts. The
files require forward correction because the aligned obligations and measured
evidence are mixed with the rejected mechanism.

### `df825115c` — preserve extractions selectively

| Path | Classification | Recovery action |
| --- | --- | --- |
| `BridgeWeb/src/core/comm-worker/bridge-comm-worker-command-handler.ts` | KEEP | Behavior-neutral extraction/import of render-disposition application and telemetry wiring. |
| `BridgeWeb/src/core/comm-worker/bridge-comm-worker-render-disposition-application.ts` | KEEP | Narrow receipt-batch application plus existing typed response construction; contains no credit machinery. |
| `BridgeWeb/src/core/comm-worker/bridge-comm-worker-render-disposition-application.unit.test.ts` | KEEP | Covers the extracted application and telemetry behavior. |
| `BridgeWeb/src/core/comm-worker/bridge-comm-worker-render-publication-release.ts` | REWORK | Extraction is useful, but the name and current placement imply release before response post. Rename/reframe as post-response existing-owner effects and invoke only after successful response post. |
| `BridgeWeb/src/core/comm-worker/bridge-comm-worker-review-demand-ledger.ts` | KEEP BASE EXTRACTION | It moved the existing 3+9 Review admission owner out of the large scheduling file. Do not retain dirty generic credit APIs. |
| `BridgeWeb/src/core/comm-worker/bridge-comm-worker-review-demand-scheduling.ts` | KEEP BASE EXTRACTION | Preserve the behavior-neutral split and imports; apply only the minimal published-position retention change later. |
| `BridgeWeb/src/core/comm-worker/bridge-comm-worker-review-demand-scheduling.unit.test.ts` | KEEP BASE MOVE | Preserve the relocation; replace dirty credit-specific additions with focused existing-owner proof. |
| `BridgeWeb/src/core/comm-worker/bridge-comm-worker-runtime-protocol.ts` | REWORK CALL ORDER | Preserve the extraction, but move existing-owner effects after the correlated response post. |

Commit size: 386 insertions and 312 deletions across eight paths. No committed
`publicationCredit`, `releaseGeneration`, `releaseCandidate`,
`capacity_unavailable`, or `commitPublicationRelease` implementation exists at
HEAD.

## Current dirty and untracked inventory

| Path | Current delta | Classification | Exact recovery |
| --- | ---: | --- | --- |
| `BridgeWeb/scripts/dev-server/bridge-dev-telemetry-otlp.ts` | +18/-0 | KEEP | Keep allowlisted semantic-class and render-disposition batch measurements; they contain no credit fields. |
| `BridgeWeb/src/core/comm-worker/bridge-comm-worker-command-handler-contracts.ts` | +1/-0 | REMOVE | Remove generic `hasRenderPublicationCapacity`; it exists only for registry credits. |
| `BridgeWeb/src/core/comm-worker/bridge-comm-worker-command-handler.review-metadata-reset.unit.test.ts` | +3/-0 | REMOVE | Remove the credit-specific assertion. |
| `BridgeWeb/src/core/comm-worker/bridge-comm-worker-command-handler.ts` | +5/-0 | REMOVE | Remove generic capacity projection. |
| `BridgeWeb/src/core/comm-worker/bridge-comm-worker-file-view-runtime.ts` | +1/-0 | REWORK | Remove `capacity_unavailable`; bound File through its existing selected-operation/latest-request owner. |
| `BridgeWeb/src/core/comm-worker/bridge-comm-worker-operation-lifecycle.ts` | +1/-0 | REMOVE | Remove the optional-receipt guard introduced only by `capacity_unavailable`. |
| `BridgeWeb/src/core/comm-worker/bridge-comm-worker-review-demand-ledger.ts` | +57/-9 | REWORK | Keep named 3/9 policy values and minimal published-position retention. Remove `commitPublicationRelease`, credit terminology/dependency, registry-owned release behavior, and generation machinery. Preserve stale-demand safety without creating a second owner. |
| `BridgeWeb/src/core/comm-worker/bridge-comm-worker-review-demand-scheduling.ts` | +5/-0 | REWORK | Keep “published does not immediately release the existing position” and exact current-attempt exposure. Replace commit-named API with the post-response existing-owner release. |
| `BridgeWeb/src/core/comm-worker/bridge-comm-worker-review-demand-scheduling.unit.test.ts` | +18/-1 | REWORK | Replace manual registry commit loop with 12-held/13th-blocked-until-response-post proof. |
| `BridgeWeb/src/core/comm-worker/bridge-comm-worker-review-preparation.ts` | +16/-1 | REWORK | Keep published receipt identity and a published settlement. Remove `capacityUnavailable` and external-continuation behavior. |
| `BridgeWeb/src/core/comm-worker/bridge-comm-worker-review-runtime.ts` | +15/-5 | REWORK | Keep published receipt identity return. Remove `capacityUnavailable` result and branch. |
| `BridgeWeb/src/core/comm-worker/bridge-comm-worker-runtime-protocol.ts` | +1/-0 | REMOVE/REWORK | Remove generic File capacity check. Separately reorder the committed extracted response/effect tail during the fix phase. |
| `BridgeWeb/src/core/comm-worker/bridge-worker-render-fulfillment-registry.ts` | +156/-3 | REMOVE DIRTY MACHINERY | Remove publication-credit map, maximum capacity, release-pending array, release generation, snapshots, commit methods, capacity result, and credit JSON key. Restore committed fulfillment semantics. |
| `BridgeWeb/src/core/comm-worker/bridge-worker-render-fulfillment-registry.unit.test.ts` | +162/-18 | REMOVE/RESTORE | Remove credit/capacity/generation/tombstone tests and optional-identity churn; retain committed fulfillment tests. |
| `BridgeWeb/src/core/demand/bridge-content-demand-policy.ts` | +4/-0 | KEEP/REWORD | Keep 3 and 9 as named Review demand-position policies; remove publication-credit wording. |
| `docs/specs/2026-08-23-bridge-comm-worker-admission-backpressure/2026-08-23-program-design.md` | +288/-175 | REWRITE | Replace the 1,017-line coordinator design with the owner-confirmed minimal boundary. |
| `BridgeWeb/scripts/dev-server/bridge-dev-telemetry-render-disposition.unit.test.ts` | untracked | KEEP | Keep source-scrubbing/allowlist proof for requested measurements. |
| `BridgeWeb/src/core/comm-worker/bridge-comm-worker-review-demand-ledger.unit.test.ts` | untracked | REWORK | Prove existing position retention/release after response post; remove commit/generation/foreign-worker protocol framing. |
| `BridgeWeb/src/core/demand/bridge-content-demand-policy.unit.test.ts` | untracked | KEEP/REWORD | Prove the existing 3+9 Review demand-position derivation without credit terminology. |
| three named PR2 research files | untracked | PROTECTED | Never edit, delete, stage, or use as cleanup targets. |

The tracked dirty diff before this inventory is 751 insertions and 212
deletions across 16 files. `git diff --check` is clean. Untracked-file line
counts are not included in those totals.

## Smallest red/green proof after cleanup is authorized

1. Review ledger unit: fill 3 reserved plus 9 dynamic positions; mark all 12
   published; prove item 13 does not start; post the existing correlated
   response and release one matching existing position; prove item 13 starts.
2. Review invalidation unit: invalidate one published item before response;
   prove it still occupies its position, then disappears without reviving stale
   demand after post-response release.
3. File unit: publish selection A, select B before A's disposition response;
   prove B remains latest intent and does not publish; after response post and A
   settlement, prove B starts.
4. Actual `MessageChannel` integration: receive 12 Review publications, send
   the queued disposition batch, and prove the correlated ready/degraded
   response is observed before publication 13. Inject a thrown response post
   and prove publication 13 never starts.
5. Preserve the existing urgent-action fairness proof and add actual-channel
   coverage so a fake dispatcher is not the only evidence.
6. Run the real 1,699-item Swift/Vite/worktree/SQLite root-plus-five-reply
   journey, reload durability, bounded queue/outstanding counts, quiescent
   drain, typecheck/lint/format, scoped suites, and the aggregate gate.

## Safe cleanup order

1. Checkpoint this inventory only; do not stage protected/unrelated files.
2. Surgically remove dirty generic registry credit/generation changes with
   scoped patches, not `git reset`, `git checkout`, or a broad revert.
3. Preserve measurement-only changes and behavior-neutral `df825115c`
   extractions.
4. Correct the Specification and Program Design to the owner-confirmed
   queue/batching/existing-owner boundary.
5. Add the failing existing-owner admission tests before changing runtime
   behavior.
6. Implement response-post-before-existing-owner-release without a new
   coordinator.
7. Run focused proof, real runtime proof, quality gates, and aggregate proof.
8. Commit only scoped recovery checkpoints after inspecting the staged diff;
   never stage protected PR2/UI work.

## Stop conditions

Stop and return to the owner before code changes if current source disproves
any of these load-bearing assumptions:

- the existing correlated response can be synchronously posted before owner
  release;
- Review's current ledger can retain published work without a second queue;
- File's current selected-operation/latest-request owners can serialize old
  publication and newest intent;
- thrown post failure reaches existing replacement containment;
- the solution requires a new public contract, persistence, native interface,
  port, scheduler, or proof weakening.
