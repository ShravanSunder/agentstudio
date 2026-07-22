# Spec Review Report - Shared BridgeViewer Gate 0.a

Goal id: `2026-06-25-bridgeviewer-shared-app-pr-ready`
Workflow: `shravan-dev-workflow:spec-review-swarm`
Status: needs plan rewrite against corrected specs
Written at: 2026-06-25T06:54:00-04:00

## Source Of Truth

Durable specs promoted to repo docs:

- [spec.md](/Users/shravansunder/Documents/dev/project-dev/agent-studio.bridge-start/docs/specs/bridge-viewer-transport/spec.md:1)
- [review-protocol.md](/Users/shravansunder/Documents/dev/project-dev/agent-studio.bridge-start/docs/specs/bridge-viewer-transport/review-protocol.md:1)
- [worktree-file-surface-protocol.md](/Users/shravansunder/Documents/dev/project-dev/agent-studio.bridge-start/docs/specs/bridge-viewer-transport/worktree-file-surface-protocol.md:1)

Workflow/orchestration state remains under `tmp/`.

## Review Coverage

Full-load baseline used before review:

- `spec.md`: 1523 lines before edits
- `review-protocol.md`: 594 lines before edits
- `worktree-file-surface-protocol.md`: 895 lines before edits
- `worktree-devserver-product-e2e-precursor-plan.md`: 510 lines before edits
- old workflow details: 1013 lines, historical context only

Reviewer lanes:

- whole-spec coverage
- contract and architecture boundaries
- validation/testability/planning readiness
- spec-difference and stale-language search

## Accepted Findings And Fixes

1. Production navigation was underspecified.

   Fix:
   - Added `BridgeViewerNavigationCommand` and
     `BridgeViewerNavigationOutcome` to the parent spec.
   - Dev query params and Swift production navigation must both reduce to this
     typed command surface.
   - Query params must not select React roots directly.

2. Review file target was too path-only.

   Fix:
   - Review file targets must resolve to typed target identity with comparison id,
     review item id or resolved file ref, version, and active context `review`.
   - Dev URL path remains only a bootstrap hint.
   - Required Review file-target URLs now include `version=<base|head|current>`.

3. Files-to-Review handoff was optional in some specs but required by the goal.

   Fix:
   - Parent spec says the handoff is in current scope.
   - Worktree/File protocol says the current Gate 0.a goal requires the typed
     same-app handoff.
   - Precursor plan adds Slice 06P.2b for:
     `Files selection -> OpenReviewComparisonIntent -> ReviewComparisonSelector
     -> review.openComparison -> accepted/rejected/deferred ->
     BridgeViewerNavigationCommand`.

4. Review comparison authority was split between caller and provider.

   Fix:
   - Review protocol now has `ReviewComparisonSelector` for caller input.
   - Provider resolves selector into authoritative `ReviewComparisonSpec`,
     package identity, source cursors, and stream ids.

5. Files context diff target could weaken Review ownership.

   Fix:
   - Specs now say Files + diff target is future-only and must bind to
     Review/comparison identity.
   - Worktree/File protocol data alone cannot satisfy a diff target.

6. Native Agent Studio proof was too generic.

   Fix:
   - Goal/details now require native Files context, Review diff context, Review
     file-target context, and Files-to-Review handoff.
   - Native proof must inherit shared shell/store, visible layout,
     Pierre/Shiki/worker ownership, stale/refresh, scroll canaries, and negative
     substitute guards.

7. Workflow artifacts allowed weak narrative evidence.

   Fix:
   - Phase-result evidence now requires commands with exit codes, artifact paths,
     findings, or explicit not-run/blocked reasons. Transcript notes are
     supplemental only.

8. Stale FileViewer-only and single-URL language remained.

   Fix:
   - Worktree/File protocol intro now describes the Files-context portion of a
     shared current-worktree route set.
   - Parent spec R11 now names the explicit Files URL and states that full Gate
     0.a also requires Review diff and Review file-target proof.
   - Superseded old orchestrator draft was collapsed to a historical pointer.

## Plan Implication

The next workflow is `shravan-dev-workflow:plan-creation-swarm`.

The plan must be rewritten as vertical slices. Each slice must ship a real
behavior plus proof:

- contract/model/store proof
- provider/protocol/renderer integration proof when touched
- dev-server/browser proof when visible
- native Agent Studio/WKWebView implication when required for PR-ready
- concrete artifacts: command, exit code, screenshots/JSON/logs/metrics, or
  explicit blocked/not-run reason

Do not resume implementation from the old Ticket 02 or FileViewer-only lane.
