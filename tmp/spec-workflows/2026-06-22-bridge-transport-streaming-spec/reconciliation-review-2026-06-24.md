# 2026-06-24 Reconciliation Review Reducer

Status: superseded by the later 2026-06-24 Worktree dev-server product E2E
proof-gap correction. This reducer remains historical evidence only; do not use
its "ready" conclusion as current plan-readiness.

Scope:

- `spec.md`
- `review-protocol.md`
- `worktree-file-surface-protocol.md`
- `reconciliation-plan-2026-06-24.md`
- fresh worktree dev-server proof artifact:
  `tmp/bridge-viewer-worktree-dev-server/2026-06-24T12-05-05-046Z/worktree-dev-server-proof.json`

## Accepted Findings

### Worktree/File Source Open Contract

Finding:
`worktreeFileSurface.openSourceStream` was named but did not define a typed
request/outcome contract, and the surface flow also showed an undefined
`worktreeFileSurface.openFile` RPC.

Resolution:

- Added `WorktreeFileSurfaceOpenSourceOutcome` with `accepted`, `rejected`, and
  `deferred` variants.
- Specified that only `accepted` establishes source identity, event-stream
  lineage, intake-stream lineage, and initial cursor.
- Declared file selection browser-local open-session state over a provider
  descriptor.
- Removed the `openFile` RPC from the Worktree/File surface sequence.

### Worktree Visible Proof Provenance

Finding:
The visible-app proof required correct pixels but did not make Worktree/File
provenance a first-class assertion.

Resolution:

- Parent proof table now requires Worktree/File source identity, event/intake
  lineage, and Worktree frame provenance.
- Worktree/File proof bullets fail if the page is driven by Review
  package/query lineage.
- Reconciliation plan now records Worktree/File source identity and cursor proof
  for slice 07.

### Stale Proof Values

Finding:
The reconciliation plan carried stale slice 07 proof values.

Resolution:

- Updated browser-test proof to 34 tests.
- Updated current-worktree proof to 430 descriptors.
- Updated selected deep file to
  `Tests/AgentStudioAppIPCTests/AgentStudioAppIPCServiceTestSupport.swift`.
- Updated selected-file visible line count to 968.

### Readiness Text

Finding:
Spec status and plan decision text disagreed about whether spec-review reduction
was pending or complete.

Resolution:

- Parent spec, Review protocol, Worktree/File protocol, and reconciliation plan
  now all say reconciliation review is reduced on 2026-06-24.
- Next workflow is plan creation/reconciliation, then plan review, then
  orchestrator-goal execution.

## Result

Superseded result:

The earlier result said the spec set was ready to feed a real checkpointed
implementation plan. That is no longer current. User-visible dev-server evidence
showed the Worktree route proof could pass while still not proving the intended
Worktree/File product surface. The current route is back through the parent spec
and Worktree/File slice for product E2E correction before plan creation.

## 2026-06-24 Local Review After Product E2E Correction

Status: local parent review only. The attempted spec-review-swarm subagent
disconnected before completion, so this is not a completed swarm reduction.

Reviewed artifacts:

- [spec.md](/Users/shravansunder/Documents/dev/project-dev/agent-studio.bridge-start/tmp/spec-workflows/2026-06-22-bridge-transport-streaming-spec/spec.md:1)
- [review-protocol.md](/Users/shravansunder/Documents/dev/project-dev/agent-studio.bridge-start/tmp/spec-workflows/2026-06-22-bridge-transport-streaming-spec/review-protocol.md:1)
- [worktree-file-surface-protocol.md](/Users/shravansunder/Documents/dev/project-dev/agent-studio.bridge-start/tmp/spec-workflows/2026-06-22-bridge-transport-streaming-spec/worktree-file-surface-protocol.md:1)
- [reconciliation-plan-2026-06-24.md](/Users/shravansunder/Documents/dev/project-dev/agent-studio.bridge-start/tmp/plan-workflows/2026-06-22-bridge-transport-streaming-implementation-plan/reconciliation-plan-2026-06-24.md:1)
- [worktree-devserver-product-e2e-precursor-plan.md](/Users/shravansunder/Documents/dev/project-dev/agent-studio.bridge-start/tmp/plan-workflows/2026-06-22-bridge-transport-streaming-implementation-plan/worktree-devserver-product-e2e-precursor-plan.md:1)

Local finding:

- The corrected spec and Worktree/File slice are internally aligned on the main
  requirement: the exact current-worktree dev URL must prove the intended
  product surface, and a minimal file list plus `<pre>` is not sufficient.
- The reconciliation plan now names 06P as the blocking precursor and links the
  detailed ticket plan.
- The current browser evidence is intentionally red: the route loads data and
  renders tree/content after wait, but has no required search, regex, or
  filter/status controls.

Current red proof:

- `tmp/bridge-worktree-devserver-proof-recovery/current-worktree-route-after-3s.png`
- `tmp/bridge-worktree-devserver-proof-recovery/current-worktree-route-diagnostics.json`

Decision:

The spec correction is ready for a real spec-review-swarm retry when the agent
transport is stable. Until then, do not claim the spec has completed swarm
review. Planning may proceed only as draft precursor planning, with 06P still a
blocking gate before downstream implementation resumes.

## 2026-06-24 Expanded Goal Reset Note

The active goal is no longer Gate-0-only recovery. Gate 0 is the first blocker
inside a full PR-ready epic. Reviewers must evaluate whether the current spec
and plan preserve:

- Gate 0 Worktree/File product proof
- Gate 1 generic Bridge transport/protocol/scheduler implementation
- Gate 2 Worktree/File and Review app protocol implementation
- Gate 3 Pierre/Review renderer rewrite/integration
- Gate 4 PR-ready non-merge wrapup

Future review packets must include the prior failure context from
[details.md](/Users/shravansunder/Documents/dev/project-dev/agent-studio.bridge-start/tmp/workflow-state/2026-06-24-bridge-transport-review-pr-ready/details.md:1).
The reviewer should explicitly ask whether the submitted proof can pass while
the user-visible product is still wrong.
