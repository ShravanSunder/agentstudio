You are continuing an implementation handoff.

Repo: `/Users/shravansunder/Documents/dev/project-dev/agent-studio.bridge-start`
Branch/worktree: `luna-338-pierreshikitrees-review-viewer-2`
Stage: in-progress
Base: `origin/luna-338-pierreshikitrees-review-viewer-2` (`5dfb977d`)
Head at handoff: `10ba3652`

Objective:
Finish the remaining BridgeViewer comm-worker cutover blockers. The immediate
bug is Review selected content that can appear and then disappear, plus slow or
wedged Review clicks. File View continuation is explicitly out of scope: File
View selected content loads only the first `10,000` lines / `2 MiB` window.
Review mode owns continuation/window-follow behavior.

Read first:
- `docs/wip/communications/2026-07-09-bridge-click-fileview-workers-implementation-handoff.md`
- `tmp/workflow-state/2026-07-09-bridge-click-fileview-workers/details.md`
- `docs/specs/bridge-viewer-transport/local-first-comm-worker-architecture.md`
- `BridgeWeb/src/app/bridge-app-review-render-snapshot-controller.ts`
- `BridgeWeb/src/review-viewer/code-view/bridge-code-view-worker-prepared-items.ts`
- `BridgeWeb/src/review-viewer/code-view/bridge-code-view-panel.tsx`
- `BridgeWeb/scripts/verify-bridge-viewer-dev-server.ts`

Current state:
- Two implementation commits exist after `origin/luna-338-pierreshikitrees-review-viewer-2`:
  `b610f73b` adds selected-content stale/drop telemetry, and `10ba3652`
  splits Review vs File View selected R57 budgets.
- Focused BridgeWeb tests passed:
  `CI=true pnpm -C BridgeWeb exec vitest run src/core/comm-worker/bridge-comm-worker-file-view-runtime.unit.test.ts src/core/comm-worker/bridge-comm-worker-review-preparation.unit.test.ts src/core/comm-worker/bridge-comm-worker-runtime-protocol.telemetry.unit.test.ts`
  -> 3 files / 18 tests passed, exit code 0.
- The latest oq4s marker is
  `debug-observability-oq4s-1783553862-3981`.
- Marker data still shows the Review selected path is broken:
  last 15 minutes had `selection_commit=9`, `review_ready=9`,
  `selected_content_painted=5`, and one selected paint waited about 36 seconds
  before a cheap final frame.

Next action:
Add red-first proof for Review selected content disappearing or being replaced
by loading/placeholder state after worker readiness. Start with the selected
validity gate in `bridge-app-review-render-snapshot-controller.unit.test.ts`
or a browser/dev-server test if that is the smallest behavior seam. Then fix the
actual production path, add main-side lifecycle telemetry for
worker-ready/main-received -> validity accepted/rejected -> panel apply
queued/applied/superseded -> paint, and prove it in both dev server and oq4s.

Dev-server proof to include:

```bash
pnpm -C BridgeWeb run dev -- --port 5173
BRIDGE_VIEWER_DEV_SERVER_URL='http://127.0.0.1:5173/?fixture=large-diffshub&workers=on&scenario=scroll' \
  pnpm -C BridgeWeb run test:dev-server
```

Constraints:
- Do not implement File View continuation.
- Do not touch AgentStudio production state; use oq4s/debug only.
- Do not use Cursor/Grok fast variants.
- Do not decode, parse, window, diff, highlight, or reconstruct content on main
  to satisfy R53/R57. Main is only a typed Pierre courier.
- Strong TypeScript types only; use zod-derived discriminated unions for worker
  contracts where relevant.
- Red-first proof is required for behavior changes.
- Unit/browser proof is not enough: user-visible fixes need marker-scoped oq4s
  Victoria proof.

Return:
- What changed
- Tests/commands run with exit codes
- Dev-server proof status
- oq4s proof status
- Remaining blockers or risks

This is a manual handoff prompt. Do not assume access to previous chat. If any
referenced file is missing or branch state differs, stop and report the mismatch
before reviewing or editing.
