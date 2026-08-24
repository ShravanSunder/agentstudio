# Bridge comm-worker and backend performance investigation

Date: 2026-08-24

## Objective

Find and prove defects in the existing Bridge communication system without
inventing another transport architecture. The owned surfaces are:

- Main-to-worker message admission and batching;
- worker-to-Main response and render-publication ordering;
- Review and File existing-owner backpressure;
- Swift development-backend routing and SQLite comment durability;
- performance under the permanent 1,699-item real-worktree journey.

UI interaction, comment animation, presentation state, and annotation data-model
changes are owned by another agent. This investigation records their effect on
the composed proof but does not edit those surfaces.

## System boundary

The current design intentionally retains one `MessagePort` in each direction.

Main to worker:

1. Urgent actions post directly and are never replaced.
2. Demand remains producer-owned and coalesced.
3. Render dispositions use the existing per-surface FIFO admission.
4. Each disposition batch contains at most 64 receipts.
5. At most one disposition batch is in flight per surface.

Worker to Main:

1. Render jobs and content-ready patches remain individual messages.
2. Review uses its existing three reserved plus nine dynamic positions.
3. Review releases after the correlated queued, rejected, or superseded response
   posts successfully.
4. File keeps A current through queued and applied, then settles A after the
   correlated painted, rejected, or superseded response posts successfully.
5. File B remains the existing latest waiting intent until A settles.

No new port, queue owner, scheduler, coordinator, credit system, generation,
tombstone, security boundary, persistence layer, or proxy is authorized or
needed by current evidence.

## Current evidence — 2026-08-24 18:34 EDT

### Combined-HEAD rerun after concurrent UI/state commit

The UI/state owner committed its current changes at `b75728242`. The unchanged
permanent S5 command was rerun against that HEAD and reproduced the same boundary:

- root create/flush/save committed;
- reply 1 create/flush/save committed;
- the latest reply-2 button received one pointerdown, mousedown, and click on
  the same connected, visible, enabled element;
- no reply-2 composer opened and therefore no reply-2 command entered the comm
  worker or Swift backend;
- no console error or warning occurred;
- owned fixture and server cleanup completed.

This rerun does not identify a transport/backend defect. It keeps S5 RED and
routes the pre-command interaction failure back to the UI/state owner. The
comm-worker, actual-channel, Swift durability, and telemetry lower layers were
rerun independently on the same combined state and remain green.

### Committed implementation checkpoints

| Commit | Evidence owned |
| --- | --- |
| `1de2dff8c` | Existing Review/File owners bound render publication and apply owner effects only after successful correlated response posting. |
| `8206d7d56` | Real `MessageChannel` duplex ordering and non-starvation integration proof. |
| `c2cac7bdc` | Fail-open bounded-state telemetry for disposition admission and Review/File outstanding publications. |
| `948f22587` | Swift HTTP/SQLite root plus five sequential replies, exact identities/ordinals/bodies, restart recovery, and no remaining drafts. |
| `fb221f55c` | UI-owner handoff for the composed sequential-Reply failure. |

Current branch HEAD is `a0108ecb5`. The additional HEAD commit is a separate UI
timeline-connector change and does not replace the checkpoints above.

### Test pyramid already present

Unit/state:

- Review position retention, exact release, stale/foreign receipt rejection,
  invalidation, and high-water observation;
- File A/B waiting, queued/applied retention, painted/terminal settlement, and
  foreign receipt rejection;
- synchronous response-post failure applies no owner effect;
- disposition batch admission, batch ceiling, and telemetry scrubbing.

Integration:

- production codecs and runtime over an actual `MessageChannel`;
- correlated response reaches Main before newly released Review/File work;
- urgent annotation action is not starved by a later disposition batch;
- thrown response post releases neither Review nor File ownership;
- Swift development server receives 18 real HTTP commands and recovers the six
  exact messages from SQLite after composition restart.

End-to-end:

- the permanent uncommitted S5 harness creates a disposable Git worktree with
  1,699 changed files, an isolated data root, a real Swift backend, Vite, the
  production comm worker, and installed Chrome;
- it requires one root plus five replies, exact command outcomes, reload
  durability, and zero-drain bounded telemetry before it may be committed.

### Verified passing evidence

- existing-owner focused behavior: 48/48;
- actual `MessageChannel`: 2/2;
- render-disposition admission: 12/12;
- TypeScript telemetry: 31/31;
- Swift OTLP metrics: 2/2;
- Swift wire schema: 7/7;
- backend durability: 1/1 in 0.290 seconds;
- lint, format, architecture lint, typecheck, and `git diff --check` passed at
  their recorded checkpoints.

### Live telemetry witness

The completed File checkpoint in the 1,699-item journey observed:

- current outstanding publication count: 0;
- outstanding publication high-water mark: 1;
- produced disposition receipts: 3;
- pending receipts after drain: 0;
- admission failures: 0.

This proves the File owner stays bounded in that run. It does not prove the full
Review/comment journey because S5 has not reached its final drain gate.

### Current composed RED

The real S5 journey consistently reaches:

1. exactly 1,699 Review items loaded;
2. root create, flush, save, and visible body;
3. reply 1 create, flush, save, and visible body;
4. reply 2 button visible and enabled;
5. one native pointerdown, mousedown, and click delivered to the same connected
   button;
6. no reply-2 composer.

The backend and command path have already committed root plus reply 1 at that
point. Stable thread and compact Pierre browser tests do not reproduce the lost
interaction. This is currently classified as an external UI/state integration
failure, not evidence that the comm-worker or SQLite command path dropped a
message. S5 remains RED and uncommitted until the other owner lands its change
and the complete journey passes.

## Performance observations

### Proven improvements

- The prior main-to-worker receipt backlog is now admission-paced: at most 64
  receipts per batch and one in-flight batch per surface.
- Urgent annotation commands have actual-channel non-starvation proof.
- Review publication is bounded by the existing 3+9 owner positions.
- File publication is bounded by the existing one selected operation.
- Owner release is response-ordered on the existing worker-to-Main FIFO.
- Telemetry observes current count, high-water mark, oldest age, batch size,
  and closed phase without controlling behavior.

### Measured command timings from repeated S5 RED runs

The repeated successful prefix was approximately:

- root flush admission/settlement: 1.02 seconds;
- root save settlement: immediate to tens of milliseconds;
- reply 1 composer open: roughly 0.31–0.50 seconds;
- reply 1 flush admission/settlement: 1.01–1.05 seconds;
- reply 1 save settlement: roughly 0.04–0.07 seconds;
- saved body visibility: roughly 0.005–0.02 seconds after settlement.

The one-second flush duration is the current debounce/admission policy and must
be evaluated separately from the fixed two-second invalidation delay seen in an
older run. Current evidence does not show the former worker-port starvation or
a 47-second urgent-command backlog after the committed correction.

### Environment-only failures seen during proof

- Sandboxed Darwin FSEvent registration can fail with
  `streamStartFailed`; the unchanged scoped E2E starts correctly when allowed
  to create its disposable local FSEvent stream.
- Repeated heavyweight E2E launches produced one isolated Review item-count
  startup timeout and one sandboxed Chrome launch abort. Neither currently has
  repeatable product evidence and neither authorizes code changes.
- The long-running manual Vite/Swift pair remained healthy at the HTTP level
  (`200` Vite, `204` proxied backend health) while one old browser tab waited for
  Review metadata. That manual-loop flake still needs a fresh owned launch and
  marker-scoped evidence before assigning a source owner.

## Open transport/backend questions

1. Does S5 finish with Review outstanding high-water at or below 12, pending
   disposition count zero, and no oldest-age violation after the UI owner change?
2. Do five sequential replies keep urgent command outcomes ahead of later
   disposition batches under the full 1,699-item cadence?
3. Does reload recover all six exact bodies and identifiers from the same
   isolated SQLite data root?
4. Does stopped demand drain both Review and File owners to zero without
   replacement, lease expiry, overload, or amplification?
5. Can a fresh documented manual Vite loop load comparison metadata reliably,
   or is the previous waiting tab stale-session evidence rather than a backend
   defect?

## Next proof steps

1. Wait for the concurrent UI/state/data-model owner to finish and record the
   exact HEAD/diff without editing or staging those files.
2. Run the focused comm-worker unit/state suites to ensure no shared-file drift.
3. Run the actual `MessageChannel` integration test.
4. Run Swift HTTP/SQLite durability integration.
5. Run the exact S5 1,699-item journey once against the combined current state.
6. If S5 passes, require six exact bodies after reload and bounded zero-drain
   telemetry, then commit only the S5 fixture/registration/journey files.
7. Run BridgeWeb typecheck/lint/unit/integration/browser/E2E gates, Swift scoped
   gates, aggregate `mise run test`, packaged WKWebView proof, and independent
   implementation review.
8. If S5 still fails before any new command is issued, return the failure to the
   UI owner. If a command is issued but outcome/order/durability fails, resume
   this investigation at that exact transport/backend boundary.

## Forbidden responses to failure

- no second MessagePort;
- no new generic queue or scheduler;
- no credit/generation/tombstone protocol;
- no higher pending ceilings as a substitute for admission;
- no click retry, force-click, longer UI timeout, or weakened S5 assertion;
- no telemetry-controlled correctness;
- no proxy redesign;
- no UI/state/data-model edit from this lane;
- no protected PR2 file edits or staging.

## Commands

```bash
pnpm --dir BridgeWeb exec vitest --config vitest.config.ts run \
  src/core/comm-worker/bridge-comm-worker-review-demand-ledger.unit.test.ts \
  src/core/comm-worker/bridge-comm-worker-review-demand-scheduling.unit.test.ts \
  src/core/comm-worker/bridge-comm-worker-selected-file-content-operation.unit.test.ts \
  src/core/comm-worker/comm-runtime-protocol.existing-owner-backpressure.unit.test.ts \
  src/core/comm-worker/comm-runtime-protocol.file-product.unit.test.ts \
  src/core/comm-worker/comm-runtime-protocol.render-fulfillment.unit.test.ts

pnpm --dir BridgeWeb exec vitest --config vitest.integration.config.ts run \
  src/core/comm-worker/bridge-comm-worker-duplex-backpressure.integration.test.ts

mise run test:swift -- \
  --filter BridgeDevelopmentAnnotationDurabilityHTTPRoutingTests

pnpm --dir BridgeWeb exec vitest --config vitest.e2e.config.ts run \
  tests/e2e/bridge-viewer-vite-product.e2e.test.tsx \
  -t "1,699-item Review keeps root and five replies responsive and durable"
```
