# Bridge Transport Streaming Reconciliation Plan

Date: 2026-06-24
Status: checkpoint reconciliation plan after 2026-06-24 spec-review reduction.
Slice 07 is completed and proved in the current worktree; slices 06 and 08-11
remain open plan work.
Source spec:
[spec.md](/Users/shravansunder/Documents/dev/project-dev/agent-studio.bridge-start/tmp/spec-workflows/2026-06-22-bridge-transport-streaming-spec/spec.md:1),
[review-protocol.md](/Users/shravansunder/Documents/dev/project-dev/agent-studio.bridge-start/tmp/spec-workflows/2026-06-22-bridge-transport-streaming-spec/review-protocol.md:1),
[worktree-file-surface-protocol.md](/Users/shravansunder/Documents/dev/project-dev/agent-studio.bridge-start/tmp/spec-workflows/2026-06-22-bridge-transport-streaming-spec/worktree-file-surface-protocol.md:1)

This is not a replacement implementation plan yet. It records why the original
00-05 plan cannot be treated as fully satisfying the reopened spec and names
the next critical plan slices.

## Current Truth

- The branch is green on the narrowed 00-05 implementation scope plus the
  2026-06-24 slice 07 visible-app proof repair.
- The reopened spec is broader than that scope.
- The worktree dev-server route previously rendered raw/gibberish path text even
  though earlier proof passed. That proved the prior proof contract was
  insufficient.
- The current worktree dev-server route now renders the Worktree/File app and
  has a standing machine-checkable visible-app verifier.
- The old plan's "PR ready" proof is no longer enough to claim architecture
  satisfaction.

## Original Tickets Status

| Ticket | Keep As | Reconciliation Status |
| --- | --- | --- |
| 00 intake carrier proof | historical carrier spike | insufficient for mandatory startup continuous event stream |
| 01 core transport contracts | useful base contracts | must be extended with continuous-event-stream contract and fixtures |
| 02 review protocol vertical | useful Review vertical | must be audited for live changeset runtime contract and renderer cutover |
| 03 worktree/file native provider | useful provider boundary | must be audited against continuous event stream and visible-app proof |
| 04 worktree/file browser surface | useful browser surface | extended by slice 07 visible-app proof repair |
| 05 hard-cutover cleanup | useful cleanup | not final cleanup against reopened spec |

## New Critical Plan Slices

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

Status: completed in current worktree.

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

Do not keep executing the old 00-05 plan as if it is current. The
spec-review reduction is complete for this recovery checkpoint. The right next
step is:

1. Convert this reconciliation file into a real checkpointed implementation
   plan.
2. Resume implementation with slice 06 or split a smaller precursor slice for
   the continuous event stream backbone.
3. Keep slice 07's verifier as a standing gate while later transport,
   scheduler, renderer, and telemetry slices are implemented.
4. After plan review passes, route execution under the orchestrator goal.
