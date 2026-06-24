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
