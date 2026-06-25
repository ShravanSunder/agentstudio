# Bridge Transport Streaming Reconciliation Plan

Date: 2026-06-24
Status: reopened for the 2026-06-24 expanded Bridge transport/review PR-ready
epic. The prior slice 07 proof is invalid for product readiness. Gate 0 is the
first mandatory gate: a blocking precursor ticket must make the exact
`current-worktree` dev URL work as FileViewer inside the shared BridgeViewer
shell before downstream transport, Review, renderer, and PR-ready gates resume.
Source spec:
[spec.md](/Users/shravansunder/Documents/dev/project-dev/agent-studio.bridge-start/tmp/spec-workflows/2026-06-22-bridge-transport-streaming-spec/spec.md:1),
[review-protocol.md](/Users/shravansunder/Documents/dev/project-dev/agent-studio.bridge-start/tmp/spec-workflows/2026-06-22-bridge-transport-streaming-spec/review-protocol.md:1),
[worktree-file-surface-protocol.md](/Users/shravansunder/Documents/dev/project-dev/agent-studio.bridge-start/tmp/spec-workflows/2026-06-22-bridge-transport-streaming-spec/worktree-file-surface-protocol.md:1)

Current precursor ticket plan:
[worktree-devserver-product-e2e-precursor-plan.md](/Users/shravansunder/Documents/dev/project-dev/agent-studio.bridge-start/tmp/plan-workflows/2026-06-22-bridge-transport-streaming-implementation-plan/worktree-devserver-product-e2e-precursor-plan.md:1)

Current red proof artifacts:

- `tmp/bridge-worktree-devserver-proof-recovery/current-worktree-route-after-3s.png`
- `tmp/bridge-worktree-devserver-proof-recovery/current-worktree-route-diagnostics.json`

Goal state:

- [details.md](/Users/shravansunder/Documents/dev/project-dev/agent-studio.bridge-start/tmp/workflow-state/2026-06-24-bridge-transport-review-pr-ready/details.md:1)
- [events.jsonl](/Users/shravansunder/Documents/dev/project-dev/agent-studio.bridge-start/tmp/workflow-state/2026-06-24-bridge-transport-review-pr-ready/events.jsonl:1)

This is not a replacement implementation plan yet. It records why the original
00-05 plan cannot be treated as fully satisfying the reopened spec and names
the next critical plan slices.

This reconciliation is not the whole epic plan. It must feed a checkpointed
plan that covers Gate 0 Worktree/File product proof, Gate 1 generic Bridge
transport/protocol/scheduler implementation, Gate 2 Worktree/File and Review
app protocol implementation, Gate 3 Pierre/Review renderer rewrite/integration,
and Gate 4 PR-ready non-merge wrapup.

## Current Truth

- The branch is green on the narrowed 00-05 implementation scope plus a weak
  2026-06-24 slice 07 visible-text proof.
- The reopened spec is broader than that scope.
- The worktree dev-server route previously rendered raw/gibberish path text even
  though earlier proof passed. That proved the prior proof contract was
  insufficient.
- The current worktree dev-server route can render a tree and file text, but the
  proof does not establish the intended FileViewer product surface. The verifier
  did not block a standalone `WorktreeFileApp` route, a minimal/raw-looking
  file-list plus `<pre>` surface, or a custom renderer that bypasses Pierre
  CodeView/File, Pierre FileTree, Shiki, and workers. It also did not exercise
  search, regex, filters, route provenance, or visual product behavior.
- The old plan's "PR ready" proof is no longer enough to claim architecture
  satisfaction.

## Original Tickets Status

| Ticket | Keep As | Reconciliation Status |
| --- | --- | --- |
| 00 intake carrier proof | historical carrier spike | insufficient for mandatory startup continuous event stream |
| 01 core transport contracts | useful base contracts | must be extended with continuous-event-stream contract and fixtures |
| 02 review protocol vertical | useful Review vertical | must be audited for live changeset runtime contract and renderer cutover |
| 03 worktree/file native provider | useful provider boundary | must be audited against continuous event stream and visible-app proof |
| 04 worktree/file browser surface | useful browser surface | blocked by precursor product E2E proof; current surface/proof is too weak |
| 05 hard-cutover cleanup | useful cleanup | not final cleanup against reopened spec |

## New Critical Plan Slices

### 06P / Gate 0.a Shared FileViewer Renderer Precursor

Status: blocking precursor.

Detailed ticket plan:
[worktree-devserver-product-e2e-precursor-plan.md](/Users/shravansunder/Documents/dev/project-dev/agent-studio.bridge-start/tmp/plan-workflows/2026-06-22-bridge-transport-streaming-implementation-plan/worktree-devserver-product-e2e-precursor-plan.md:1)

Deliverable:
Make the exact dev-server URL render and operate FileViewer inside the shared
BridgeViewer shell, not a Review mock route, not a standalone `WorktreeFileApp`,
and not a minimal raw file-list plus `<pre>` body renderer.

URL:
`http://127.0.0.1:5173/?fixture=worktree&workers=on&scenario=current-worktree`

Required behavior:

- Product surface exposes Worktree/File source or status provenance.
- Primary file/code canvas is on the left and Pierre FileTree/right rail is on
  the right.
- Tree rows are selectable through the shared Pierre FileTree/right rail and
  selection changes the open content.
- Open file content renders through Pierre CodeView/File with Shiki highlighting
  and worker-backed highlighting when `workers=on`.
- Open file content renders ready/loading/stale/unavailable states.
- Search text input exists and changes visible/search state.
- Regex toggle or mode control exists and changes search interpretation/state.
- Filter/status controls exist and change visible tree/file state.
- Large-tree scroll and large-file scroll preserve stable extents.
- Screenshots show the intended product surface before and after interaction.
- Proof artifact records route identity, protocol/source lineage, selected file,
  open content state, control state changes, scroll canaries, and negative
  assertions against Review/mock lineage, `WorktreeFileApp`, route-local custom
  shells, and raw/minimal rendering.

Proof:

- Playwright/dev-server E2E against the exact URL above.
- Parent-inspected screenshot artifacts from that run.
- JSON proof artifact with provenance, controls, interactions, scroll canaries,
  and negative assertions.
- Negative assertions that the route did not mount `WorktreeFileApp`, did not
  render raw `<pre>` content, and did not bypass Pierre/Shiki/workers.
- Parent/human/reviewer inspection checks the screenshots against the product
  expectation before the ticket is marked complete.
- A failed or disconnected subagent review does not satisfy or invalidate this
  gate by itself; the gate is satisfied by inspectable artifacts plus an
  accepted review result.
- Unit/component tests may support this ticket, but cannot replace the
  dev-server E2E proof.
- This Vite/dev-server proof is required first but is not the final native
  proof. The full PR-ready plan must add Agent Studio Bridge/WKWebView runtime
  proof with marker-correlated bridge route, stream/resource, and product-surface
  evidence.

### 06 Continuous Event Stream Backbone

Status: open.

Deliverable:
Implement or prove the pane-scoped continuous event stream contract required by
the spec. The stream is SSE-like in role and MCP-like in command/event
separation: commands stay request/response, compact provider facts stream to
the browser, and heavy bodies stay descriptor-backed.

Proof:
- Actual Swift/WKWebView proof for startup ready, heartbeat, source-status,
  descriptor-available, invalidation, gap, reset, close, stale close, and
  cancellation.
- Browser harness proof may cover parser/component behavior, but it cannot
  replace the WKWebView carrier proof.
- Swift/TypeScript parser fixture parity.
- Bounded memory/backpressure proof.
- No body payloads on the event stream.
- App intake frames bind to event-stream lineage; protocol-local push or
  polling-only refresh fails the slice.

### 07 Worktree Dev-Server Visible-App Proof And Fix

Status: superseded by blocking precursor 06P.

Deliverable:
Fix the current worktree dev-server route so it renders the actual
Worktree/File app from Worktree/File protocol provenance, not Review package or
query lineage, and not raw frame/path text.

Proof:
- Standing browser/dev-server regression fixture for
  `?fixture=worktree&workers=on&scenario=current-worktree`.
- Machine assertions that app root, tree pane, and file pane have visible
  non-zero rects.
- Sampled visible tree entries occupy distinct row boxes.
- Selected exact-line fixture preserves visible file line structure.
- Packaged stylesheet/layout affects the mounted surface.
- `document.body` does not contain raw frame fields, serialized transport
  payloads, or concatenated raw path corpus outside intentional tree/content UI.
- Route proof records Worktree/File source identity and Worktree frames; the
  slice fails if the visible page is still driven by Review package/query
  lineage.
- Screenshot or DOM artifact is supporting evidence, not the pass condition.

Current proof:

- `mise exec -- pnpm --dir BridgeWeb run test:browser:integration -- src/worktree-file-surface/worktree-file-app.browser.test.tsx`
  exited 0 with 2 browser files passed and 34 tests passed.
- `mise exec -- pnpm --dir BridgeWeb run test:dev-server:worktree` exited 0.
  The proof reported first-load ready content for `.github/workflows/ci.yml`
  with 275 lines before any verifier click; visible app, tree pane, and content
  pane rects; 430 descriptors; selected deep file
  `Tests/AgentStudioAppIPCTests/AgentStudioAppIPCServiceTestSupport.swift`; 968
  visible selected-file lines; distinct sampled tree rows; packaged CSS layout
  proof; Worktree/File source identity and cursor proof; no raw
  frame/resource/path-corpus text outside intentional UI; stable content and
  tree scroll extent canaries.
- `mise run bridge-web-check` exited 0.
- `mise run lint` exited 0.

Correction:

This proof is not enough. It proved content and some layout facts, but not the
intended FileViewer surface inside the shared BridgeViewer shell. Do not use it
as a completion gate for the reopened spec. Keep only the useful lower-level
assertions and replace the completion gate with Gate 0.a precursor 06P.

### 08 Victoria Scheduler And Transport Tuning

Status: open.

Deliverable:
Use dev-server and Swift/WKWebView telemetry to tune scheduler and resource
executor budgets.

Proof:
- Victoria metrics/logs/traces collected for large worktree scroll/click in both
  dev-server and Swift/WKWebView paths with shared scenario/marker correlation.
- Scheduler lane counts, queue depth, in-flight work, stale drops, aborts,
  byte-budget outcomes, and content loading latency are visible.
- Event-stream gaps/resets, descriptor-available counts, and scroll-extent
  canary fields are visible.
- Production constants are justified by measured data or explicitly marked
  provisional.

### 09 Review Handoff From Worktree/File

Status: open.

Deliverable:
Implement typed `OpenReviewComparisonIntent` handoff for any included
Worktree/File UX that opens Review. If the checkpoint excludes Review-opening UX,
that UX must be explicitly out of scope and absent/disabled; the plan cannot
defer the contract while keeping the affordance.

Proof if implemented:
- Worktree/File selection emits typed intent.
- Review returns accepted/rejected/deferred outcome.
- Accepted path validates and builds `ReviewComparisonSpec`.
- Provider computes/materializes the comparison package.
- Worktree/File does not become the diff engine.

### 10 Renderer Cutover / Pierre Integration

Status: open.

Deliverable:
Prove the new materialization system actually drives Pierre/CodeView/tree
rendering for the relevant Review and Worktree/File paths, or explicitly name
the remaining renderer gap with owner approval.

Proof:
- Same-lineage updates avoid incompatible full remount.
- Stable extent facts are consumed by renderer path before content body hydrate.
- Bridge URLs/descriptors are absent from renderer-visible DOM.
- Scroll canary remains stable under large fixture and current worktree.
- PR-ready requires hard cutover for every in-scope renderer entry path.
  A named residual renderer gap can justify non-PR-ready status only.
- Proof includes a negative assertion that covered routes cannot reach the
  legacy renderer/remount bypass.

### 11 Changeset Runtime Contract

Status: open.

Deliverable:
Implement or fixture-prove the required runtime fields for live/closed/pinned
changeset clusters even if the first automatic grouping algorithm remains open.

Proof:
- Stable provider-issued cluster id.
- Live, closed, and pinned lifecycle.
- Confidence/degraded metadata, cursors/checkpoints, stale-drop behavior.
- Reset behavior when comparison authority, baseline, source cursor, or
  clustering authority changes.
- Browser never mints cluster authority.

## Plan Decision

Do not keep executing the old 00-05 plan as if it is current. The prior
spec-review reduction is reopened by the expanded PR-ready epic scope and the
Worktree dev-server product E2E proof gap. The right next step is:

1. Run spec-review-swarm on the corrected full epic contract, with the reviewer
   failure context from the goal-state details.
2. Convert this reconciliation file into a real checkpointed implementation
   plan only after the spec review accepts the Gate 0 blocker language and the
   downstream Gate 1-4 scope.
3. Execute precursor 06P before slice 06 or any downstream implementation claim.
4. Keep precursor 06P's Playwright/dev-server product E2E proof as a standing
   gate while later transport, scheduler, renderer, and telemetry slices are
   implemented.
5. Add Agent Studio Bridge/WKWebView runtime proof before PR-ready wrapup.
6. After plan review passes, route execution under the orchestrator goal.
