# BridgeWeb CI Reliability — Implementation Plan

Planning result: draft

## Authority and snapshot

- Requirements: [../user-requirements.md](../user-requirements.md)
- Specification: [../2026-08-09-bridgeweb-ci-reliability.md](../2026-08-09-bridgeweb-ci-reliability.md)
- Program Design: [../program-design.md](../program-design.md)
- Planned branch: `fix/bridgeweb-test-quiescence`
- Planned HEAD: `f47ed3b123da32473ecac33941f338d82a5b0385`
- Originating planner: `plan-implementation`

## Goal and limits

Replace File-query fixed-frame settlement with request-correlated completion through accepted render-store publication, and preserve the selected same-file CodeView item until its next generation replaces it. Remove only the superseded query-frame and same-file scroll-recovery mechanisms.

Do not add a generic async framework, sleeps, retry frames, timeout inflation, warning suppression, persistence, telemetry, native protocol changes, worker-scheduling changes, or adjacent Bridge refactors. Keep different-file reset, user scroll-to-top, strict browser failure reporting, and bounded waits for named DOM conditions.

## Change and proof sequence

```text
Slice 1  Exact File-query completion
   │
   ├─ RED: prove an exact projected request remains pending until its
   │       transaction is accepted and published; prove unchanged,
   │       superseded, and disposal outcomes.
   │
   ├─ Add the internal fileQueryOutcome message and request correlation.
   ├─ Add one optional File-query publication observer to render-store
   │  construction through the existing renderStoreFactory seam.
   ├─ Complete the exact waiter only after successful store publication.
   └─ Replace query-specific fixed-frame settlement with one act-scoped
      interaction-and-wait helper.
            │
            ▼ integration gate: real query lifecycle browser coverage
Slice 2  Stable same-file CodeView replacement
   │
   ├─ RED: row-paint reset plus temporary fileItemById absence preserves
   │       only the exact selected CodeView item.
   ├─ RED: real CodeView calls are A@1 → A@2, never A@1 → [] → A@2,
   │       with the same connected scroll owner and viewport.
   ├─ Make rowPaint reset clear row paint only.
   ├─ Let the controller explicitly clear all CodeView items or preserve
   │  the exact selected same-file item.
   ├─ Permit retained-item selection eligibility from current selection
   │  plus item metadata while fileItemById is temporarily absent.
   └─ Remove same-file rAF retarget, second retarget, and late-zero repair.
            │
            ▼ integration gate: same-file, different-file, zero-scroll,
                               and stale-generation browser coverage
Slice 3  Repository closure
   ├─ BridgeWeb formatting, lint, typecheck, unit, integration, browser,
   │  and packaged build through the repository task.
   ├─ Complete `mise run test` on exact HEAD.
   ├─ Run the debug app and exercise File search plus same-file refresh.
   └─ One implementation review/remediation cycle, then PR preparation.
```

## Write surfaces

Slice 1 may change only the File-query worker contract/projection, render-store construction and acceptance observer, browser worker harness, query lifecycle browser coverage, and directly affected unit tests under `BridgeWeb/src/core/comm-worker/` and `BridgeWeb/src/file-viewer/`.

Slice 2 may change only the render snapshot store/controller, CodeView presentation selection, the File Code panel, and their directly affected unit/browser tests under the same two roots.

The design-family documents and this plan are the only documentation writes. No Swift or native Bridge files are in scope.

## Obligation and proof map

| Obligation | Slice | Proof boundary |
| --- | --- | --- |
| R1 / V1 exact query completion | 1 | request-correlated unit and browser lifecycle tests through store publication and `act` return |
| R2 / V2 strict React failure reporting | 1, 3 | unchanged browser failure guard plus warning-free focused/full browser lane |
| R3 / V3 same-file replacement | 2 | store-level preservation test and real CodeView generation/owner/scroll browser assertions |
| R4 / V4 navigation and user zero | 2 | different-file reset, intentional zero, and stale-generation companion tests |
| R5 / V5 proportional cleanup | 1, 2, 3 | removed query fixed frames and same-file recovery code; complete BridgeWeb and repository gates |

## Stops and false-green risks

- Stop and return to Program Design if exact request correlation cannot reach successful store publication through the existing runtime/factory boundaries without a general scheduler or public/native protocol.
- Stop and return to Program Design if preserving one item requires a second retained store or duplicate presentation authority.
- A worker-message drain, elapsed frame, DOM appearance alone, helper-only assertion, or mocked store callback cannot prove R1.
- A final nonzero `scrollTop` alone cannot prove R3; proof must also show no empty CodeView publication and the same connected owner.
- Do not weaken or filter the strict console/React failure guard to make the lane pass.

## Commands

From the repository root:

```bash
pnpm --dir BridgeWeb exec vitest run src/core/comm-worker/bridge-comm-worker-file-query-projection.unit.test.ts src/core/comm-worker/bridge-main-render-snapshot-store.unit.test.ts src/file-viewer/bridge-file-viewer-render-snapshot-controller.unit.test.ts
pnpm --dir BridgeWeb exec vitest --config vitest.browser.config.ts run --project integration-browser src/file-viewer/bridge-file-viewer-query-lifecycle.browser.test.tsx src/file-viewer/bridge-file-viewer-app.browser.test.tsx
pnpm --dir BridgeWeb run check
mise run test:bridge-web
mise run test
```

Manual proof uses the repository debug launcher and existing File Viewer surface; it does not add a proof-only production hook.
