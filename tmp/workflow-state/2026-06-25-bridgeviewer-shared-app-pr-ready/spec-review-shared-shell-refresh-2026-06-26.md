# Spec Review Reducer: Shared Shell Refresh

Date: 2026-06-26
Goal: `2026-06-25-bridgeviewer-shared-app-pr-ready`
Reviewed target:

- `docs/specs/bridge-viewer-transport/spec.md`
- `docs/specs/bridge-viewer-transport/review-protocol.md`
- `docs/specs/bridge-viewer-transport/worktree-file-surface-protocol.md`
- `tmp/plan-workflows/2026-06-22-bridge-transport-streaming-implementation-plan/worktree-devserver-product-e2e-precursor-plan.md`
- `tmp/workflow-state/2026-06-25-bridgeviewer-shared-app-pr-ready/details.md`

## Coverage

- Parent loaded `spec-review-swarm`, `orchestrator-goal`, and selected review
  lane references.
- Parent inspected fresh screenshots and geometry:
  `tmp/bridge-viewer-design-proof/2026-06-26T03-04-21-148Z/`.
- DeepWiki was asked about `pierrecomputer/pierre`; answer confirmed that
  Pierre `CodeView` supports mixed file/diff items and that File and diff
  rendering share the Shiki/worker path when wrapped by the worker-pool context.
- Three reviewer agents ran bounded spec-review lanes and read the target
  artifacts directly from disk.

## What Held

- Option C is the accepted shared-shell layout:
  content header only over the left content region, title/source on the left,
  `Files | Review` plus content actions on the right, and independent top-aligned
  Pierre FileTree/right rail.
- `ReviewViewer` and `FileViewer` are modes in one `BridgeViewerApp`, not
  separate apps.
- Browser/native visible UX proof cannot be replaced by jsdom, JSON-only, DOM
  attribute-only, or screenshot-only proof.
- Fresh screenshots prove the shared-shell geometry but do not close content
  loading: the Files screenshot still shows `Loading file`.

## Accepted Findings

1. Review file-target identity needed to be promoted into the parent contract.
   The parent spec now models `reviewComparison` source refs and states the
   Review-context file-target invariant. The proof matrix now requires accepted
   comparison id, source identity, review item id or resolved file ref, version,
   target kind, and active context.

2. Inactive viewer context side effects needed a proof row. The parent proof
   matrix now requires browser/native proof that hidden contexts do not emit new
   foreground fetches, route-level foreground telemetry, visible
   loading/selection mutations, or mark-viewed-style user-visible side effects.

3. Files provenance wording could have reintroduced a second Files-only top row.
   The Worktree/File protocol and plan now bind provenance to the shared
   content-header title slot or right-rail toolbar.

4. FileViewer click latency needed a canonical ready boundary. The Worktree/File
   protocol and plan now define click-to-ready as browser-actionability-checked
   click/refresh through selected file identity plus non-loading Pierre
   CodeView/File lines for that target.

5. Workflow-state ordering could skip file-load/preload proof. `details.md` now
   lists file-load responsiveness/preload proof before native Agent Studio
   Bridge/WKWebView proof.

## Deferred Or Rejected Findings

- Broad durable-spec history cleanup is valid but not blocking the next
  implementation slice. The immediate blocker is mis-specified contracts/proof,
  not the existence of checkpoint history in later sections.
- Review diff-route item selection remains bootstrap-only for Gate 0.a unless a
  proof explicitly uses a visible browser-actionable review selection. Internal
  dispatch may support bootstrap/protocol proof but cannot be claimed as user
  interaction proof.

## Phase Result

phase_result: needs_revision addressed
evidence: spec/protocol/plan/workflow-state patches in this checkpoint
recommended_next_workflow: shravan-dev-workflow:implementation-review-swarm
recommended_transition_reason: The spec review findings that could mis-steer the
next implementation slice have been incorporated; review the resulting code/proof
state before resuming implementation on FileViewer content-load/preload and
native Bridge proof.
