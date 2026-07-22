Ticket 04 Review-Fix Implementation Review Packet
==================================================

Mode: implementation

Role / mode: read-only implementation-review lane

Edit boundary: read-only

Review scope:
- Commit range: `f5701c94..HEAD`
- Focus commit: `6724fae3 Fix worktree scroll canary review findings`
- Diff stat command: `git diff --stat f5701c94..HEAD`
- Diff command: `git diff f5701c94..HEAD -- <changed files>`

Changed files:
- `BridgeWeb/scripts/dev-server/bridge-worktree-dev-provider.integration.test.ts`
- `BridgeWeb/scripts/dev-server/bridge-worktree-dev-provider.ts`
- `BridgeWeb/scripts/verify-bridge-viewer-worktree-dev-server.ts`
- `BridgeWeb/src/worktree-file-surface/worktree-file-app.browser.test.tsx`
- `BridgeWeb/src/worktree-file-surface/worktree-file-app.integration.test.tsx`
- `BridgeWeb/src/worktree-file-surface/worktree-file-app.tsx`
- `tmp/workflow-state/2026-06-22-bridge-transport-streaming/details.md`
- `tmp/workflow-state/2026-06-22-bridge-transport-streaming/events.jsonl`

Intent:
Ticket 04 previously completed Worktree/File browser/dev-server implementation
but implementation review found proof and correctness gaps. This review-fix
batch should close those accepted findings before the ticket can advance:

1. The live scroll canary must exercise a deep/non-zero scrolled worktree item,
   not only a top-of-list item.
2. The verifier must compare loading extent against ready extent, not only
   ready against ready.
3. Provider `lineCount`/extent facts must match rendered file rows, including
   trailing-newline semantics.
4. Fast consecutive selections must not allow stale earlier file-content
   completions to overwrite the current selected file.
5. Worktree invalidation frames for the open file must mark the view stale and
   adopt the new descriptor extent.
6. Proof artifacts must not leak absolute user paths or capability URLs.
7. The workflow state must honestly route back to implementation review.

Constraints:
- Bridge is generic; Worktree/File semantics belong to the Worktree/File app
  protocol.
- Large file bodies must stay out of Zustand/React state where practical; store
  references/facts and keep bodies in the materialization path.
- Use strict TypeScript style: no `any`, no casual casts, no suppressions, no
  unchecked `JSON.parse`, no weakened proof lanes.
- Scroll smoothness is a contract: provider virtualized extent facts must be
  available before bytes hydrate, and proof must capture stable anchor/extent
  telemetry.
- Telemetry/proof artifacts must be source scrubbed: no raw `/Users/...` paths,
  capability URLs, prompts, comments/comms, or large payload bodies.

Security context: applicable
- Attack surface is local dev/test proof and browser-rendered Worktree/File
  content. The key trust-boundary checks are no capability URL/body leakage to
  DOM or artifacts and no broadening of local filesystem/resource authority.
- Do not broaden into unrelated bridge transport security unless this commit
  introduces a concrete regression.

Implementation proof claimed:
- `pnpm --dir BridgeWeb run fmt`: exit 0.
- `pnpm --dir BridgeWeb run check`: exit 0.
- `pnpm --dir BridgeWeb exec vitest run src/worktree-file-surface/worktree-file-app.integration.test.tsx src/worktree-file-surface/worktree-file-surface-runtime.integration.test.ts scripts/dev-server/bridge-worktree-dev-provider.integration.test.ts scripts/dev-server/bridge-dev-telemetry.unit.test.ts --reporter verbose`: exit 0, 4 files passed, 24 tests passed.
- `pnpm --dir BridgeWeb run test:browser:integration -- src/worktree-file-surface/worktree-file-app.browser.test.tsx --reporter verbose`: exit 0, 2 files passed, 32 tests passed.
- `BRIDGE_VIEWER_WORKTREE_DEV_SERVER_URL='http://127.0.0.1:5173/?fixture=worktree&workers=on&scenario=current-worktree' pnpm --dir BridgeWeb run test:dev-server:worktree`: exit 0. Artifact `tmp/bridge-viewer-worktree-dev-server/2026-06-24T01-11-16-655Z/worktree-dev-server-proof.json` reported:
  - target `Sources/AgentStudioIPCClientCore/AgentStudioIPCClientArguments.swift`
  - `descriptorCount=419`
  - `frameCount=420`
  - `treeScrollTopBeforeSelection=2372`
  - `treeScrollTopAfterReady=2372`
  - `treeHeightDeltaPixels=0`
  - `contentHeightDeltaPixels=0`
  - `selectedLineCount=317`
  - `contentDeclaredTotalSizePixelsAfterReady=6340`
  - `stableAnchorPass=true`
  - `exactSizeTolerancePass=true`
- `rg -n "/Users/|agentstudio://resource" tmp/bridge-viewer-worktree-dev-server/2026-06-24T01-11-16-655Z/worktree-dev-server-proof.json || true`: exit 0 with no matches.
- `git diff --check`: exit 0.
- Worktree/File touched TS hygiene grep for casual casts, `any`,
  suppressions, and `JSON.parse`: no matches.
- `mise run lint`: exit 0.

Source-of-truth inputs:
- `tmp/spec-workflows/2026-06-22-bridge-transport-streaming-spec/spec.md`
- `tmp/spec-workflows/2026-06-22-bridge-transport-streaming-spec/worktree-file-surface-protocol.md`
- `tmp/spec-workflows/2026-06-22-bridge-transport-streaming-spec/review-protocol.md`
- `tmp/plan-workflows/2026-06-22-bridge-transport-streaming-implementation-plan/implementation-plan.md`
- `tmp/plan-workflows/2026-06-22-bridge-transport-streaming-implementation-plan/file-organization.md`
- `tmp/workflow-state/2026-06-22-bridge-transport-streaming/details.md`
- `tmp/workflow-state/2026-06-22-bridge-transport-streaming/events.jsonl`

Non-goals:
- Do not edit files.
- Do not broaden into Ticket 05 cleanup unless the review-fix commit creates a
  concrete blocker.
- Do not accept findings as truth; parent reducer verifies all candidates.

Requested lanes:
- Spec/proof compliance.
- Reliability/performance.
- Contracts/tests/code quality.
- Security/trust boundary.

Output contract:
Return candidate findings only. For each finding include severity, evidence,
failure scenario, smallest fix, proof/test, and confidence. If there are no
findings, still return lane-level confidence and remaining uncertainty. Include
a completion receipt with source anchors.
