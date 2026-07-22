# Implementation handoff

Date: 2026-07-09
Stage: in-progress
Repo: `/Users/shravansunder/Documents/dev/project-dev/agent-studio.bridge-start`
Branch/worktree: `luna-338-pierreshikitrees-review-viewer-2`
Base: `origin/luna-338-pierreshikitrees-review-viewer-2` (`5dfb977d`)
Head: `10ba3652`
Source goal: `2026-07-09-bridge-click-fileview-workers`

## What this work is trying to do

Finish the remaining BridgeViewer comm-worker cutover blockers without touching
AgentStudio production state. The current goal narrows the older broad
comm-worker cutover into four live issues:

- Review click-to-visible latency, wedges, and the user-observed bug where
  selected content appears and then disappears.
- File View selected-file loading beyond the accidental 400-line courier cap,
  now explicitly bounded to the first 10,000 lines / 2 MiB. File View does not
  implement continuation; Review mode owns continuation/window-follow.
- R53/R57 transfer/courier correctness: main may courier
  `BridgeWorkerPierreRenderJob` values but must not decode, parse, window, diff,
  highlight, or reconstruct content.
- Trustworthy lifecycle telemetry for Review selected content and File View
  readiness.

The terminal condition is still PR-ready proof, not merge.

## Current state

- Worktree was clean before this handoff was written.
- Current HEAD is `10ba3652 fix(bridge): widen selected file view render window`.
- The branch is ahead of `origin/luna-338-pierreshikitrees-review-viewer-2` by
  two implementation commits:
  - `b610f73b test(bridge): surface selected stale content drops`
  - `10ba3652 fix(bridge): widen selected file view render window`
- The active oq4s marker is
  `debug-observability-oq4s-1783553862-3981`, from
  `tmp/debug-observability/latest-observability.env`.

## Changed files since origin branch

- `BridgeWeb/src/core/comm-worker/bridge-comm-worker-review-preparation.ts`:
  emits selected-content drop telemetry when selected Review preparation becomes
  stale before fetch or before publish.
- `BridgeWeb/src/core/comm-worker/bridge-comm-worker-review-runtime.ts`: records
  selected-content stale drop reasons from runtime fetch/publish gates.
- `BridgeWeb/src/core/comm-worker/bridge-comm-worker-telemetry.ts`: adds
  `performance.bridge.web.selected_content_dropped`.
- `BridgeWeb/src/core/comm-worker/bridge-comm-worker-runtime-protocol.ts` and
  telemetry tests: extend the protocol telemetry surface.
- `Sources/AgentStudio/Features/Bridge/Runtime/Telemetry/BridgeTelemetryBatchValidator+Allowlists.swift`
  and `Tests/AgentStudioTests/Features/Bridge/BridgeTelemetryBatchValidatorTests.swift`:
  allow and validate selected-content drop telemetry.
- `BridgeWeb/src/core/demand/bridge-content-demand-policy.ts`: splits R57
  budgets. Review remains `512 KiB / 400 lines`; selected File View uses
  `2 MiB / 10_000 lines`.
- `BridgeWeb/src/core/comm-worker/bridge-comm-worker-file-view-runtime.unit.test.ts`:
  proves selected File View hydrates a 450-line file and a payload above the old
  512 KiB ceiling but below 2 MiB.
- `BridgeWeb/src/app/bridge-app-native-worktree-file-intake-ready.ts`,
  `BridgeWeb/src/file-viewer/bridge-file-viewer-render-snapshot-controller.ts`,
  and `BridgeWeb/src/app/bridge-app-review-render-snapshot-controller.ts`:
  align callers with the split budget shape.
- `docs/specs/bridge-viewer-transport/local-first-comm-worker-architecture.md`:
  records the R57 budget split and the File View no-continuation boundary.

Diff command:

```bash
git diff --stat origin/luna-338-pierreshikitrees-review-viewer-2...HEAD
git diff origin/luna-338-pierreshikitrees-review-viewer-2...HEAD
```

## What is proven

- Focused BridgeWeb tests passed in this worktree:

```bash
CI=true pnpm -C BridgeWeb exec vitest run \
  src/core/comm-worker/bridge-comm-worker-file-view-runtime.unit.test.ts \
  src/core/comm-worker/bridge-comm-worker-review-preparation.unit.test.ts \
  src/core/comm-worker/bridge-comm-worker-runtime-protocol.telemetry.unit.test.ts
```

Result: 3 test files passed, 18 tests passed, exit code 0.

- File View selected first-window policy is now explicit in code:
  `BridgeWeb/src/core/demand/bridge-content-demand-policy.ts` keeps Review at
  `512 * 1024 / 400` and File View selected at
  `2 * 1024 * 1024 / 10_000`.
- File View still creates a first window from line 1 to the budgeted end line in
  `BridgeWeb/src/core/comm-worker/bridge-worker-file-view-content-ready.ts`.
  That is intentional after the user's correction: no File View continuation.
- The spec now states the same boundary: Review continuation owns the
  `512 KiB / 400` windows; File View selected owns only the bounded
  `2 MiB / 10,000` first window.
- The dev-server proof lane exists but has not been run for this handoff:
  `BridgeWeb/package.json` has `dev`, `test:dev-server`, `test:browser`, and
  `test:browser:integration`. `BridgeWeb/scripts/verify-bridge-viewer-dev-server.ts`
  defaults to
  `http://127.0.0.1:5173/?fixture=large-diffshub&workers=on&scenario=scroll`.

## What is not proven

- Review selected-content disappearance is not fixed. The user observed content
  appearing and immediately disappearing in Review mode.
- Review click-to-visible is still not good enough. Marker-scoped logs show
  selected paint does not keep up with selection commits:
  - last 15 minutes: `selection_commit=9`, `click_to_row_highlight=9`,
    `review_ready=9`, `selected_content_painted=5`, `telemetry_drop=95`.
  - one recent selected paint at `2026-07-09T01:37:06Z` had
    `click_to_paint_ms=36237`, `frame_wait_ms=7`, `materialize_ms=0`,
    `transport=worker`. That means the final paint frame was cheap, but the
    selected content waited about 36 seconds before paint.
- Current marker did not show `performance.bridge.web.selected_content_dropped`
  or `performance.bridge.web.review_content_demand` in the queried windows.
  That leaves the main-side selected lifecycle blind after worker readiness.
- Dev-server / Chrome / Playwright reproduction has not been run yet for the
  disappearance bug. The next agent must add or run this proof, not rely only on
  native oq4s telemetry.
- Full static gates were not run in this handoff turn:
  - `pnpm -C BridgeWeb run typecheck`
  - `pnpm -C BridgeWeb run lint:types`
  - `pnpm -C BridgeWeb run fmt:check`
  - `mise run lint`
- Full native oq4s proof after the latest File View commit has not been rerun.

## Known broken behavior

1. Review mode: clicking files can wedge or take too long to paint selected
   content.
2. Review mode: content can appear and immediately disappear. Current best
   hypothesis is a stale/placeholder overwrite after a worker-prepared item
   briefly reaches the panel.
3. Review mode: `selected_content_painted` is missing for some selection commits.
4. Review mode: telemetry still does not expose the full path between
   worker-ready, main-received, selected-validity gate, panel-apply, and paint.
5. File View: selected file content is intentionally bounded to the first
   `10,000` lines / `2 MiB`; no continuation should be implemented there.
6. R53/R57 transfer/courier proof is incomplete. Main still has to prove it is a
   courier, not a content processor.

## Why implementation diverged from the spec/plan

The comm worker and Pierre worker exist and run, but the hard cutover stopped
short of ownership. The system moved work off-main, but some content decisions
and lifecycle decisions still happen or collapse on main:

- R53 says worker messages must be transferable-first and content bytes should
  move as declared `ArrayBuffer` transfer payloads when ownership moves. That
  proof is incomplete.
- R57 says the comm worker owns content identity, demand rank, window choice,
  payload class, and the Pierre render job; main may only enqueue the typed job.
  Any main-side decode/reconstruct/window/diff/highlight path violates this.
- The Review selected path has an explicit main validity gate:
  `selectedContentAvailabilityForReviewPackage()` converts raw `ready` back to
  `loading` whenever the selected worker-prepared `BridgeMainCodeViewItem` is
  null.
- The panel delta builder can synthesize a loading item when the worker-prepared
  selected item does not match the current presentation/role. That is a
  plausible "appears then disappears" mechanism.
- Earlier proof was too unit-heavy. Green unit tests did not prove live
  user-visible behavior in oq4s or dev server.
- Telemetry was not sufficient: a selected worker drop event was added, but the
  current live symptom may be main-side selected validity/apply supersession,
  not worker-side stale fetch.

## Source anchors to inspect first

- Goal state:
  `tmp/workflow-state/2026-07-09-bridge-click-fileview-workers/details.md`
- R53/R57 spec:
  `docs/specs/bridge-viewer-transport/local-first-comm-worker-architecture.md`
- Split budgets:
  `BridgeWeb/src/core/demand/bridge-content-demand-policy.ts`
- File View first window:
  `BridgeWeb/src/core/comm-worker/bridge-worker-file-view-content-ready.ts`
- Review selected validity gate:
  `BridgeWeb/src/app/bridge-app-review-render-snapshot-controller.ts`
- Existing unit seam for selected ready -> loading:
  `BridgeWeb/src/app/bridge-app-review-render-snapshot-controller.unit.test.ts`
- Panel selected presentation gate:
  `BridgeWeb/src/review-viewer/code-view/bridge-code-view-worker-prepared-items.ts`
- Panel apply pump:
  `BridgeWeb/src/review-viewer/code-view/bridge-code-view-panel.tsx`
- Dev-server harness:
  `BridgeWeb/scripts/verify-bridge-viewer-dev-server.ts`
  and `BridgeWeb/src/app/bridge-app-dev-bootstrap.tsx`

## Recommended next action

Continue implementation, but do not patch blindly.

1. Add a red-first proof for the Review "appears then disappears" path.
   Best starting seam:
   `BridgeWeb/src/app/bridge-app-review-render-snapshot-controller.unit.test.ts`
   or a browser test that proves a selected worker-prepared item cannot be
   overwritten by stale loading/placeholder state after it becomes visible.
2. Add or extend lifecycle telemetry for the main-side gap:
   worker-ready/main-received -> selected validity accepted/rejected ->
   panel apply queued/applied/superseded -> selected paint.
3. Run Vite/dev-server proof:

```bash
pnpm -C BridgeWeb run dev -- --port 5173
BRIDGE_VIEWER_DEV_SERVER_URL='http://127.0.0.1:5173/?fixture=large-diffshub&workers=on&scenario=scroll' \
  pnpm -C BridgeWeb run test:dev-server
```

4. After a fix, rerun oq4s marker-scoped proof and require selected clicks to
   show selection commit, row highlight, review ready, selected worker materialize,
   selected paint, zero required lifecycle drops, and no content disappearance.
5. Then run focused tests, type/lint/format gates, and an implementation review
   swarm before PR readiness.

## Do not change

- Do not implement File View continuation/streaming. File View selected loads
  only the first `10,000` lines / `2 MiB` envelope.
- Do not touch AgentStudio production state. Use oq4s/debug only.
- Do not revive the rejected R53 attempt that transferred bytes and then decoded
  or reconstructed content on main.
- Do not use Cursor/Grok fast variants. If using external advisors, use only the
  allowed non-fast models/providers from the goal notes.
- Do not claim done from unit tests alone.

## Security state

- Changed trust boundaries: browser worker/main content boundary and native
  telemetry validator allowlist.
- Security findings fixed: none claimed.
- Unvalidated security risks: R53 transfer declarations and payload validation
  are not fully proven; ensure no raw paths, payload text, or unsafe attributes
  are emitted to OTLP.
- Security commands/proofs/reports: no dedicated security scan run.
- Accepted risks/non-goals: File View first-window bounding is intentional;
  unbounded payloads are forbidden.
