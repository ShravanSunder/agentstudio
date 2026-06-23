# Plan Creation Ledger

Date: 2026-06-22
Plan: `tmp/plan-workflows/2026-06-22-bridge-transport-streaming-implementation-plan/implementation-plan.md`
Input spec commit: ebad06d2

## Parent Agent Work

- Committed accepted spec artifacts:
  - commit: `ebad06d2`
  - message: `docs: add bridge transport streaming spec`
- Fully loaded accepted spec packet before planning:
  - original planning load: `spec.md` lines 1-1124 after 1.6.29 lifecycle
    metadata sync, `review-protocol.md` lines 1-458,
    `worktree-file-surface-protocol.md` lines 1-483
  - current 2026-06-23 plan-review load after host-admission and scroll-extent
    revisions: `spec.md` lines 1-1160, `review-protocol.md` lines 1-471,
    `worktree-file-surface-protocol.md` lines 1-535
  - `spec-review-report.md` lines 1-295
  - `review-1.6.29/spec-review-report.md` lines 1-138
  - `swarm-ledger.md` lines 1-148
- Re-anchored current implementation with live reads across:
  - `BridgeWeb/src/bridge/*`
  - `BridgeWeb/src/app/*`
  - `BridgeWeb/src/foundation/content/*`
  - `BridgeWeb/src/foundation/review-package/*`
  - `BridgeWeb/src/review-viewer/content/*`
  - `BridgeWeb/src/review-viewer/projections/*`
  - `BridgeWeb/src/review-viewer/state/*`
  - `BridgeWeb/src/review-viewer/test-support/*`
- Ran a refreshed `shravan-dev-workflow:spec-review-swarm` 1.6.29 parent pass:
  - report: `tmp/spec-workflows/2026-06-22-bridge-transport-streaming-spec/review-1.6.29/spec-review-report.md`
  - accepted tiny edit: `spec.md` now clarifies comment/comms resources are
    reserved-disabled in the first implementation and integrity applies to them
    only after a later schema slice enables those resource kinds.
  - parent hygiene sync: spec and app-protocol status lines now route to
    `shravan-dev-workflow:plan-review-swarm`.
  - limitation: spawned spec-review lanes timed out under host file-descriptor
    pressure and were not used as evidence.

## Subagent Lanes

### Halley: Codebase Boundary / Write Surfaces

Status: completed

Key findings accepted into plan:

- Native/browser resource URL contract is mismatched.
- Browser intake is Review-specific and centered in `BridgeApp`.
- Current worktree dev path still fabricates Review packages.
- Pierre boundary is visible and should be mostly untouched in the first slice.
- First write surfaces should be transport/runtime seams, then browser intake/materialization.

### Maxwell: Validation / Proof Gates

Status: completed

Key findings accepted into plan:

- Existing gates are strong enough to anchor phases, but missing tests exist for descriptor handoff, page-world hostile stimuli, scheduler pressure, source reset demand, Zustand boundary, stale-refresh worktree UX, and WKWebView carrier behavior.
- Browser integration is the slowest gate and should be PR-level, not tight-loop.
- Current warning noise: React `flushSync` and ResizeManager warnings.

### Volta: Execution DAG

Status: completed

Key findings accepted into plan:

- Start with a carrier proof spike before protocol migration.
- Do not build Worktree/File on `BridgeReviewPipeline.queryKind = browseTree/openFile`.
- Review should prove the generic runtime before Worktree/File product implementation.
- Stop/reconverge if carrier, descriptor ordering, scheme handler, provider identity, or CodeView remount assumptions break.

### Carson: Security / Reliability

Status: completed

Key findings accepted into plan:

- App asset confinement, content-world isolation, generation stale-drop, and browser telemetry allowlisting already exist.
- Capability URLs remain handle+generation based and need descriptor/lease authority.
- Page-world ready/control events need a stricter authority boundary before demand stimuli exist.
- Stale identity must expand beyond generation.
- Telemetry redaction and scheduler/backpressure need explicit proof gates.

## Revision Lanes After Plan Review

### Laplace: Codebase Boundary

Status: completed

Lane artifact:

- `lanes/codebase-boundary.md`

Accepted into revised plan:

- The revised order is correct, but the work is serial rather than parallel.
- Ticket 02 owns the first app protocol router; ticket 04 extends it.
- Ticket 03 explicitly includes transition edits to existing ReviewFoundation
  browse/open-file files.
- Ticket 04 owns replacement of Review-shaped worktree dev scaffolding.

### Hegel: Validation Proof

Status: completed

Lane artifact:

- `lanes/validation-proof.md`

Accepted into revised plan:

- Ticket 00 needs real WKWebView carrier cases.
- Ticket 01 needs page-world privileged RPC denial, fixture sync, descriptor,
  lease, integrity, and comments/comms fail-closed proof.
- Ticket 02 owns generic demand runtime proof through Review, telemetry canary,
  pressure proof, and Worktree dev proof preservation.
- Ticket 03 needs native Worktree/File provider proof.
- Ticket 04 needs browser stale-refresh proof.
- Ticket 05 reruns telemetry, fixture, regression, and benchmark gates as
  applicable.

### Hume: Execution Order / Security Reliability

Status: completed

Lane artifact:

- `lanes/execution-order-security-reliability.md`

Accepted into revised plan:

- Added explicit advancement gates.
- Added checkpoint review cadence.
- Added checkpoint handoff packet requirements.
- Reinforced that cleanup remains last because it destroys rollback surface.

## Current Plan Decisions

- Reshaped the plan into vertical proof slices after user correction.
- Each slice has source spec references, current code references, red tests,
  implementation tasks, proof gates, and stop/reconverge criteria.
- Slice 00 is a carrier proof spike.
- Slice 01 establishes generic transport contracts.
- Descriptor-backed demand runtime is merged into the Review vertical.
- Ticket 02 migrates Review protocol end-to-end and introduces the first app
  protocol router.
- Ticket 03 implements the Worktree/File native provider boundary.
- Ticket 04 implements the Worktree/File browser surface and replaces
  Review-shaped worktree dev scaffolding.
- Slice 05 performs hard-cutover cleanup.
- Each ticket now names `Ticket Output`, red tests, proof pyramid, and reviewer
  handoff output.
- Next recommended skill is `shravan-dev-workflow:plan-review-swarm`.

## Execution-Time Proof Split

Date: 2026-06-22
Status: accepted by parent controller during ticket 01 execution

Reason:

- Ticket 01 transport/security proof passed focused BridgeWeb, fixture sync,
  focused Swift Bridge, WebKit, and lint gates.
- The broad `mise run test-fast` gate failed in
  `CommandBarDataSourceTests/test_commandsScope_includesOpenBridgeReview`.
- That failure is outside ticket 01's approved transport/security write scope.

Decision:

- Ticket 01 uses ticket-scoped BridgeWeb, fixture sync, focused Swift Bridge,
  WebKit, and quality gates as its checkpoint proof.
- Broad Swift health remains a milestone/final freshness guard.
- A broad Swift failure outside the ticket write scope must be isolated and
  recorded in the checkpoint handoff instead of pulling unrelated CommandBar
  edits into the transport checkpoint.

## Not Done At Plan-Creation Close

- No product code changed.
- No plan-review-swarm rerun on the revised package yet.
- No implementation executed.
- No dev server started or verified in this planning pass.
- No final proof gates run by the parent agent after writing the plan; Maxwell ran read-only validation lanes separately.
