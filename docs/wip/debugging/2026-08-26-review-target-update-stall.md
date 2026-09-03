# 2026-08-26 Review Target Update Stall

## 2026-08-26 09:44 EDT — Current reproduced state

### Bug packet

- Branch and HEAD: `bridge-review-design-2026-08-14` at `3b7e91549`.
- Native proof app: `Agent Studio Debug 1owk`, bundle `com.agentstudio.app.debug.d1owk`, PID `56629`.
- Observability marker: `debug-observability-1owk-1787751452-51804`.
- Symptom: a real current-worktree Review pane remains at `Compare to: origin/main · Updating` and `Review metadata unavailable`.
- Expected: the admitted target selection reaches a terminal result and either installs Review metadata/content or presents a bounded failure without requiring focus restoration or reload.
- Actual: the catalog query succeeds, target selection updates client chrome, but no Review publication lifecycle event appears after the selection and the disabled Updating state persists after returning the app to the foreground.
- Impact: the real Review surface cannot load, so comments/diff/native foreground proof cannot proceed.
- Scope boundary: existing dirty `BridgeWeb` and packaged-proof files are owned by another agent. Investigation is read-only until the earliest missing edge is proven.

### Computer Use reproduction

1. Select the persisted tab `agent-studio.review-comments · bridge-review-design-2026-08-14` containing the Review pane.
2. Observe `Review metadata unavailable` and `Choose target`.
3. Open `Choose target`; observe a successful finite catalog containing `origin/main`, the local current branch at `3b7e91549`, and other recent branches.
4. Select `origin/main`.
5. Observe the control become disabled with `Compare to: origin/main · Updating`.
6. While the update is pending, raise Activity Monitor so Agent Studio is inactive but the same selected tab remains open.
7. Inspect Agent Studio without selecting another tab: the update remains pending.
8. Raise Agent Studio again: the update still remains pending.

This reproduces a terminal-settlement failure. It does not yet prove application inactivity caused it because returning to foreground does not recover it.

### Evidence

- `mise run verify-debug-observability` initially reported PID `56629` absent because sandboxed `kill -0` could not inspect the process. `/usr/sbin/lsof` confirmed the exact executable. The unchanged verifier passed with scoped host permission.
- Marker-scoped verifier result: launch-services, background activation, authenticated IPC, and `app.did_finish_launching.succeeded` all passed.
- The most recent Swift Review metadata lifecycle record is `review_metadata_publication_started` at `2026-08-26T13:38:20.366212Z`. The Computer Use target selection occurred around `13:42Z`; no later started/completed/failed publication record exists.
- Recent telemetry contains frequent background Git/filesystem work and Bridge web frame-jank records. This is correlation only; it is not yet proof that Git admission starved the target command.

### Ranked hypotheses and smallest proof steps

1. The BridgeWeb target-selection request enters local pending state but is not posted through the comm worker/product-call route.
   - Supports: chrome changes immediately; native Review publication never starts.
   - Missing: correlated product-call request/response identity.
   - Proof: trace the click handler to the exact call, pending owner, request identity, and transport post; add or use a focused probe at the first route edge.
2. The command posts but native admission never starts or never records a terminal.
   - Supports: target catalog on the same boundary succeeded; no later Review publication record.
   - Missing: native call receipt and target-selection handler evidence.
   - Proof: inspect the native product-call handler and query the marker for its call outcome/correlation fields.
3. Background Git/filesystem pressure starves the Review metadata operation.
   - Supports: background Git pending count around 50 and repeated filesystem-triggered admissions.
   - Missing: scheduler class, queue wait, and request identity for this Review operation.
   - Proof: correlate the selected target request with existing Git scheduler admission/terminal telemetry; do not infer from global traffic.
4. Application inactivity cancels or pauses admitted work.
   - Supports: the update was pending when focus moved away.
   - Against: it did not resume or settle after foreground restoration; deterministic activity tests are green.
   - Proof: first reproduce the same operation entirely in foreground on a fresh terminal state, then compare the exact native activity and command traces.

### Stop condition

No source fix until the earliest missing edge is evidenced and the root cause is assigned to an existing owner. No new queue, port, scheduler, timeout, coordinator, event, or UI workaround is admitted by this investigation.

## 2026-08-26 09:47 EDT — Earliest missing edge proven

The initial hypotheses are narrowed by correlated telemetry:

- The comm worker handled `reviewComparisonTargetsQuery` at `13:40:36.959741Z` with a 55 ms queue wait.
- The comm worker handled `reviewComparisonUpdate` at `13:41:03.959659Z` with a 9 ms queue wait.
- The comm worker handled the picker-close `reviewComparisonTargetsQueryCancel` at `13:41:03.961140Z` with a 9 ms queue wait.
- Native Review generation 3 emitted pane-presentation revisions 11 and 12 around the update.
- Revision 12 at `13:41:04.871362Z` was the settled terminal presentation, but publication was skipped with `agentstudio.bridge.result_reason=no_active_stream` and `agentstudio.bridge.presentation.has_active_stream=false`.
- Later filesystem-driven Review refreshes continue producing `no_active_stream`; returning Agent Studio to the foreground does not restore the stream.

Corrected sequence:

```text
Review tab is selected and cached chrome is visible
        │
        ├── finite target catalog opens on its separate content-query path
        │
        └── pane presentation stream remains absent
                    │
                    ▼
reviewComparisonUpdate reaches comm worker in 9 ms
                    │
                    ▼
native applies the target and settles Review generation 3
                    │
                    ▼
native tries to publish pane-presentation revision 12
                    │
                    └── skipped: no_active_stream
                                │
                                ▼
BridgeWeb never receives the native target/terminal presentation
                                │
                                ▼
cached chrome remains `Updating`
```

The failure boundary is now selected-tab stream recovery, not command transport, worker admission, Git scheduling, or application-active gating. The next proof step is to identify why switching the persisted Review tab from hidden back to selected does not reopen/replay its pane-presentation stream, and to encode that exact hidden-to-selected transition as RED before editing.

## 2026-08-26 10:05 EDT — Recovery succeeded and exposed strict-contract regression

A fresh current-working-tree debug build used marker
`debug-observability-1owk-1787752814-36225` and PID `37094`.

The interaction-triggered recovery correction worked:

- `Choose target` caused a fresh physical metadata stream to install;
- native pane presentation at `14:00:57.158625Z` enqueued with `has_active_stream=true`;
- `reviewComparisonUpdate` reached the worker at `14:01:19.145503Z`;
- native generation 3 pending pane presentation enqueued while Agent Studio was inactive.

The recovered stream then failed on every Review metadata publication. Source comparison proved the exact
strict-contract mismatch:

```text
Swift checkpoint 32966f140
  adds reviewedSubjectBranchName to BridgeReviewComparisonOrigin Codable JSON
        │
        ▼
Review metadata event carries reviewedSubjectBranchName
        │
        ▼
BridgeWeb bridgeProductReviewComparisonOriginSchema is strict
  but does not declare reviewedSubjectBranchName
        │
        ▼
worker rejects the Review metadata frame and poisons the physical stream
```

RED proof: `bridge-product-review-comparison-contracts.unit.test.ts` rejected the new field as an
`unrecognized_key`. GREEN adds one optional nonempty string to the existing strict origin schema; comparison,
metadata, transport, and recovery tests pass 21/21. This is completion of the already-committed transport
contract, not a new product field or UI behavior.

## 2026-08-26 10:24 EDT — Proof and checkpoint boundary

Checkpoint `d329c9f27` contains only the comm-worker recovery owner, strict TypeScript comparison-origin
contract, and their tests. Two 1Password signing attempts failed, so the repository-authorized unsigned
fallback was used without bypassing hooks.

Proof:

- focused controller/transport/comparison/metadata tests: 36/36 passed;
- scoped type-aware lint: passed;
- scoped format: passed;
- full TypeScript check: passed;
- BridgeWeb Swift/Node integration: 22/22 passed;
- real Vite/Swift stress journey: 1/1 passed in 56.17 seconds;
- ordinary Vite/Swift E2E: 7/8 passed.

The remaining E2E failure is outside this checkpoint and matches the independently identified dirty UI latch:
native comparison status reaches `Update ready`, while the locally pending comparison control remains
`HEAD · Updating` for 127.8 seconds. The failed wait accumulated 250 aborted command observations. The UI
owner must settle that local latch from the exact request lifecycle terminal; the transport lane will not edit
the owned comparison-control files.

The full unit/check/integration gates are also red in concurrently owned files:

- `bridge-main-render-snapshot-store.unit.test.ts` is 1,025 lines over the 1,000-line repository cap;
- `worktree-annotation-pierre-review-publication-continuity.browser.test.tsx` expects the successor origin but
  receives the predecessor origin and also trips the React `act(...)` guard;
- `bridge-review-comparison-control-ux.browser.test.tsx` trips the same React `act(...)` guard.

Final post-fix Computer Use acceptance remains pending. Computer Use reproduced the pre-fix failure and proved
the interaction timing. After rebuilding the corrected bundle, the isolated debug profile restored zero
windows. The real-worktree startup diagnostic then crashed in its helper before Bridge creation with
`duplicateWorktreeStableKey` because the supplied folder was a linked worktree. Those window/topology harness
defects are not transport changes and were not modified.
