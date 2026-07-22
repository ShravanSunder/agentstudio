# Bridge Transport Streaming Plan Review 1.6.29

Date: 2026-06-22
Reviewer: parent reducer using `shravan-dev-workflow:plan-review-swarm` 1.6.29
Verdict: ready for implementation checkpoint execution after accepted plan edits

## Reviewed Artifacts

- `implementation-plan.md` lines 1-325
- `file-organization.md` lines 1-392
- `plan-ledger.md` lines 1-162
- historical `plan-review-report.md` lines 1-319
- `slices/00-carrier-proof.md` lines 1-143
- `slices/01-transport-contracts.md` lines 1-133
- `slices/02-review-protocol-vertical.md` lines 1-255
- `slices/03-worktree-file-native-provider.md` lines 1-145
- `slices/04-worktree-file-browser-surface.md` lines 1-159
- `slices/05-hard-cutover-cleanup.md` lines 1-122
- plan-creation lane files under `lanes/`
- spec packet:
  - `spec.md` lines 1-1124
  - `review-protocol.md` lines 1-458
  - `worktree-file-surface-protocol.md` lines 1-483
  - `spec-review-report.md` lines 1-295
  - `review-1.6.29/spec-review-report.md` lines 1-138

## Lane Coverage

- Ohm: spec-compliance plus testability-validation, answered.
- James: architecture-assumptions plus security-reliability, answered.
- Boole: execution-scope plus adversarial-design, answered.
- Parent reducer: verified candidate findings against current plan text, spec
  anchors, live repo layout, package scripts, Swift Bridge paths, and BridgeWeb
  transport seams.

## What Held

- The serial ticket order remains correct: 00 carrier, 01 transport contracts,
  02 Review vertical, 03 Worktree/File native provider, 04 Worktree/File browser
  surface, 05 cleanup.
- Demand runtime remains proven through Review after attached descriptors exist.
- Worktree/File remains split into provider/native and browser surface tickets.
- Large data stays outside Zustand; app policies own meaning; scheduler and
  executor stay generic.
- The plan now has real per-ticket proof gates, not one broad final gate.

## Accepted Findings And Edits

### A1. Ticket 03 needed legacy Worktree/dev route preservation proof.

Edit:

- Added `BridgeReviewPipelineTests` browseTree/openFile preservation proof when
  transition edits touch ReviewFoundation seams.
- Added conditional `test:dev-server:worktree` preservation proof and handoff
  output.

### A2. Ticket 05 and the final gate needed to rerun the Worktree/File browser suite.

Edit:

- Added the Worktree/File browser integration suite to ticket 05 and the final
  done gate.

### A3. The old plan-review report looked like the active verdict.

Edit:

- Marked historical `plan-review-report.md` as superseded and not the current
  implementation verdict.

### A4. Ticket 04 still allowed raw URL/handle authority on the replacement path.

Edit:

- Added ticket 04 deliverable, red tests, browser proof, handoff output, and
  stop condition requiring descriptor/lease-backed Worktree/File fetches.
- Raw URL parsing may remain only in named legacy fixtures until cleanup.

### A5. Ticket 02 needed markdown inert-rendering and capability-leak proof.

Edit:

- Added Review markdown security proof covering scripts, event handlers, remote
  loads, `javascript:` URLs, and embedded Bridge capability URLs.

### A6. Ticket 04 needed browser source-reset stale-completion proof.

Edit:

- Added source-reset queued/in-flight tree/file stale-drop tests and browser
  proof to ticket 04.

### A7. Ticket 04 needed Worktree/File telemetry canary ownership.

Edit:

- Added Worktree/File telemetry canary ownership to the matrix and ticket 04.
- Ticket 05 remains a rerun/regression gate.

### A8. Swift app methods were placed too deep in generic Transport.

Edit:

- Changed `Transport/Methods` to registry-only glue.
- Moved app-specific method implementation to `Runtime/ReviewProtocol/**` and
  `Runtime/WorktreeFileSurface/**`.

### A9. Ticket 00 needed parser fixture parity and a concrete pressure proof home.

Edit:

- Added Swift/TypeScript intake parser fixture parity.
- Added fixture-sync proof and a named push/WebKit pressure proof location.

### A10. Ticket 03 needed provider canonicalization/containment proof.

Edit:

- Added malicious path/cwd scope, path hint, symlink, traversal, and root-token
  containment tests and handoff output.

### A11. Ticket 02 needed changeset metadata and renderer-boundary proof.

Edit:

- Added Review changeset metadata preservation/non-authority proof.
- Added renderer-boundary proof for Review and Worktree/File.

### A12. Optional Review handoff needed explicit first-epic scope.

Edit:

- Ticket 04 now defers full `OpenReviewComparisonIntent` implementation unless
  the owner explicitly pulls it into the epic.

### A13. Stale coverage counts and fuzzy headings needed cleanup.

Edit:

- Updated source and plan coverage counts.
- Renamed resolved placement decisions.
- Removed the stale generic `bridge-demand-policy.unit.test.ts` proof target.

## Rejected Or Deferred

- Full `OpenReviewComparisonIntent` implementation is deferred; the optional
  handoff remains an intent boundary, not a required first-epic feature.
- Exact final scheduler tuning remains deferred to profiling-backed changes,
  but first implementation constants and a 32 MiB queue/in-flight byte ceiling
  are now explicit and testable.

## Residual Risk

- The first implementation still depends on ticket 00 proving the actual
  carrier in real WKWebView. This is an advancement gate, not a current plan
  blocker.
- Plan artifacts are under ignored `tmp/`; checkpoint commit must force-add or
  promote accepted artifacts.

## Current Recommendation

Proceed to `implementation-execute-plan`, starting at ticket 00. Do not skip
ticket 00, and do not start ticket 01 until the real WKWebView carrier proof
passes or the design reconverges around a different carrier.

phase_result: complete
evidence: revised plan package, this report, subagent lane outputs, parent live-code verification
recommended_next_workflow: shravan-dev-workflow:implementation-execute-plan
recommended_transition_reason: The 1.6.29 plan review accepted and patched all validated blockers/important findings; remaining risks are captured as advancement gates.
