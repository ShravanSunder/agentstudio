# Ticket 03 Fanout Implementation Review

Date: 2026-06-23
Reviewed commit: `dfe30792f11d03aa3f1930c2af2ad679efd1b8ba`
Parent commit: `58338314358be972600c72b4e9012c09755b3545`
Mode: implementation review

## Verdict

`ready_with_fixes`

Reason: no blocker or important findings survived reducer verification. The
automatic Worktree/File filesystem/status fanout checkpoint may advance toward
Ticket 04, but the review accepted one non-blocking proof-hardening follow-up:
add negative fanout tests for non-matching Bridge panes.

## Accepted Findings

### 1. Follow-up: fanout boundary proof only covers the happy path

Severity: follow-up

Evidence:

- `Sources/AgentStudio/App/Coordination/WorkspaceSurfaceCoordinator+FilesystemSource.swift:156`
  filters mounted Bridge controllers by repo/worktree metadata before calling
  Worktree/File live publish methods.
- `Tests/AgentStudioTests/App/WorkspaceSurfaceCoordinatorBridgeFilesystemRefreshTests.swift:113`
  and `:220` prove matching filesystem and git snapshot fanout.
- The current tests do not register a second non-matching Bridge pane and assert
  that it stays silent.

Scenario:

A future regression could broaden fanout to unrelated Bridge panes while the
current positive tests still pass, even though the checkpoint's main contract is
bounded repo/worktree fanout.

Smallest useful fix:

Add coordinator-level negative tests that register a second Bridge pane with a
different repo/worktree and assert its intake sink stays empty while the matching
pane receives the filesystem invalidation and git status patch. If convenient,
also cover a mounted Bridge pane with no active Worktree/File source.

Proof:

Extend `WorkspaceSurfaceCoordinatorBridgeFilesystemRefreshTests` with negative
filesystem and git fanout cases.

Confidence: high

Sources: spec/proof/contracts reviewer lane and parent reducer verification.

## Rejected Or Deferred Candidates

No blocker or important candidate findings were accepted.

Parent-side concern reviewed:

- Concern: the Worktree/File fanout currently runs after pane-projection
  freshness guards in `handleFilesystemEnvelopeIfNeeded`.
- Current decision: not accepted as a blocker in this review packet. The commit
  wires the fanout through the same accepted coordinator path and the publish
  methods are generation-guarded by active Worktree/File source identity. This is
  still worth watching during Ticket 04 dev-server pressure proof, where dropped
  live updates would be visible as stale content or missing refresh marks.

## Review Proof

Implementation proof checked against the current commit:

- Focused coordinator gate: parent recorded
  `SWIFT_TEST_TIMEOUT_SECONDS=120 SWIFT_TEST_PREBUILD_TIMEOUT_SECONDS=180 mise run test-fast -- --filter 'AgentStudioTests.WebKitSerializedTests/WorkspaceSurfaceBridgeFilesystemRefreshTests'`
  as green with 3 tests in 2 suites.
- Combined native/coordinator gate: parent recorded
  `SWIFT_TEST_TIMEOUT_SECONDS=120 SWIFT_TEST_PREBUILD_TIMEOUT_SECONDS=180 mise run test-fast -- --filter 'BridgeWorktreeFileSurfaceTransportTests|BridgeSchemeHandlerWorktreeFileResourceTests|BridgeWorktreeFileSourceProviderTests|BridgeWorktreeFileSurfaceTests|BridgeWorktreeFileSurfaceNativeTests|AgentStudioTests.WebKitSerializedTests/WorkspaceSurfaceBridgeFilesystemRefreshTests'`
  as green with 40 tests in 7 suites.
- The spec/proof/contracts reviewer independently reran both commands and
  reported the same pass counts.
- Changed-file SwiftLint, `git diff --check`, and `mise run lint` were already
  recorded in the checkpoint event log.

Weakened or relabeled proof lanes found: none.

Red/green evidence status: acceptable for this native fanout checkpoint. The
accepted follow-up strengthens negative boundary coverage but does not contradict
the existing positive proof.

Exceptions: none.

## Swarm Coverage

Completed lane:

- Spec compliance + implementation proof + contracts/tests reviewer:
  completed, no blocker/important findings, one accepted follow-up.

Unavailable lanes:

- Code quality + reliability/performance + regression reviewer:
  closed while still running after timeout.
- Security and trust-boundary reviewer:
  closed while still running after timeout.

Parent reducer coverage:

- Inspected current implementation and tests directly.
- Verified the completed reviewer finding against the code.
- Classified the missing negative fanout proof as a follow-up because the code
  already filters by repo/worktree and the checkpoint is native-only.

## Routing Follow-through

Accepted follow-up route:

- Route to Ticket 04 or the next native proof-hardening pass before final PR
  readiness.

Next workflow recommendation:

- `shravan-dev-workflow:implementation-execute-plan` for Ticket 04 browser
  Worktree/File materializer/dev-server proof, carrying the negative fanout test
  follow-up as a proof-hardening item.

Do not mark the full goal complete. PR-ready proof remains open.
