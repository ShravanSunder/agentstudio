# Bridge Transport Streaming Goal Details

goal_id: 2026-06-22-bridge-transport-streaming
Created: 2026-06-22

## Current State

Current workflow: implementation-plan-accepted
Next workflow: `shravan-dev-workflow:implementation-execute-plan`

Reason:

- Accepted spec exists and is committed at `ebad06d2`.
- Draft implementation plan existed and plan review returned `needs revision`.
- The revised implementation plan now folds in the accepted review blockers:
  carrier proof, content-world RPC boundary, Review-owned demand sequencing,
  Worktree/File split, integrity/telemetry/comments proof, and checkpoint
  gates.
- A refreshed `spec-review-swarm` 1.6.29 parent pass found and fixed one small
  spec contradiction around reserved-disabled comment/comms resources.
- The revised implementation plan passed `shravan-dev-workflow:plan-review-swarm`
  1.6.29 after accepted plan edits for carrier proof, containment, raw URL
  authority, markdown security, renderer boundary, Worktree/File telemetry, and
  final browser proof.
- Implementation may begin at ticket 00 under the checkpoint gates. Ticket 01
  must not start until ticket 00 proves the real WKWebView carrier or the design
  reconverges.

## Key Artifacts

- `tmp/spec-workflows/2026-06-22-bridge-transport-streaming-spec/spec.md`
- `tmp/spec-workflows/2026-06-22-bridge-transport-streaming-spec/review-protocol.md`
- `tmp/spec-workflows/2026-06-22-bridge-transport-streaming-spec/worktree-file-surface-protocol.md`
- `tmp/spec-workflows/2026-06-22-bridge-transport-streaming-spec/spec-review-report.md`
- `tmp/spec-workflows/2026-06-22-bridge-transport-streaming-spec/review-1.6.29/spec-review-report.md`
- `tmp/plan-workflows/2026-06-22-bridge-transport-streaming-implementation-plan/implementation-plan.md`
- `tmp/plan-workflows/2026-06-22-bridge-transport-streaming-implementation-plan/file-organization.md`
- `tmp/plan-workflows/2026-06-22-bridge-transport-streaming-implementation-plan/plan-review-report.md`
- `tmp/plan-workflows/2026-06-22-bridge-transport-streaming-implementation-plan/plan-review-1.6.29-report.md`
- `tmp/plan-workflows/2026-06-22-bridge-transport-streaming-implementation-plan/orchestrator-goal-draft.md`
- `tmp/plan-workflows/2026-06-22-bridge-transport-streaming-implementation-plan/plan-ledger.md`
- `tmp/plan-workflows/2026-06-22-bridge-transport-streaming-implementation-plan/lanes/codebase-boundary.md`
- `tmp/plan-workflows/2026-06-22-bridge-transport-streaming-implementation-plan/lanes/validation-proof.md`
- `tmp/plan-workflows/2026-06-22-bridge-transport-streaming-implementation-plan/lanes/execution-order-security-reliability.md`

## Requirements / Proof Matrix

Requirement / claim:
Plan is revised into checkpointed vertical implementation tickets.
Proof source:
Revised plan files plus `shravan-dev-workflow:plan-review-swarm` verdict.
evidence source:
Plan artifacts and plan-review report.
freshness guard:
Full plan package must be reloaded before review; accepted findings must be
resolved or explicitly carried as bounded residual risks.

Requirement / claim:
Each implementation checkpoint uses pyramid/TDD proof.
Proof source:
Ticket-local red tests, unit proof, integration/boundary proof, highest
applicable browser/dev-server/Swift/WKWebView/benchmark proof.
evidence source:
Implementation-execute-plan phase result, commands, test output, benchmark or
visual/runtime artifacts where required.
freshness guard:
Proof commands must run from current worktree state after the checkpoint patch.

Requirement / claim:
No checkpoint advances while required proof gates fail.
Proof source:
Phase result footer plus parent verification of proof output.
evidence source:
Commands, artifacts, review report, or explicit blocker note.
freshness guard:
Parent orchestrator must verify phase evidence before writing a transition.

Requirement / claim:
Checkpoint commits capture verified slices.
Proof source:
Git commit after each verified lifecycle checkpoint when scoped files changed
and repo policy permits.
evidence source:
Git commit hash plus proof report for the checkpoint.
freshness guard:
Do not stage unrelated files; commit is not proof by itself.

Requirement / claim:
Review cycle happens at meaningful checkpoints.
Proof source:
`shravan-dev-workflow:implementation-review-swarm` for substantial completed
implementation slices or milestone groups.
evidence source:
Review report and accepted/rejected findings disposition.
freshness guard:
Accepted implementation findings route back to `implementation-execute-plan`
before advancing.

Requirement / claim:
Final terminal is PR-ready, not merged.
Proof source:
`shravan-dev-workflow:implementation-pr-wrapup`.
evidence source:
PR URL/state, checks, review-thread state, mergeability/readiness report.
freshness guard:
Fresh PR/check/thread state must be reported after final implementation review.

## Checkpoints

Checkpoint 0: revised plan

- Revise plan with:
  - `BridgeWeb/src/core/**` common models/runtime.
  - `BridgeWeb/src/core/bridge-host/**` browser host adapters.
  - `BridgeWeb/src/features/**` Review and Worktree/File features.
  - Demand runtime merged into Review vertical.
  - Worktree/File split into native/provider and browser/surface tickets.
  - Exact proof gates per ticket.
- Run plan review.
- Commit accepted revised plan artifacts if scoped files changed.

Status: done; evidence is `plan-review-1.6.29-report.md`.

Checkpoint 1: intake carrier and core transport contracts

- Prove selected intake carrier in real WKWebView.
- Prove core resource/RPC contracts, content-world privileged RPC boundary,
  descriptor/lease authority, fixture sync, integrity, and preview-only rules.
- Commit only after proof gates pass.
- Review if the slice changes trust/transport boundaries substantially.

Checkpoint 2: Review vertical with descriptor-backed demand

- Review frames attach descriptors before demand runtime becomes authoritative.
- Implement/prove Review materializer, Review demand policy, core scheduler and
  executor through Review.
- Preserve Worktree dev proof until replacement exists.
- Commit only after proof gates pass.
- Run implementation review before moving to Worktree/File.

Checkpoint 3: Worktree/File native provider boundary

- Prove source identity, watcher/status classification, descriptors,
  invalidations, content handles, reset decisions.
- Commit only after native/provider proof passes.
- Review before browser surface work if provider authority changed.

Checkpoint 4: Worktree/File browser surface

- Prove feature models/materializer/demand policy and stale manual refresh UX.
- Prove dev-server worktree URL works without Review package scaffolding.
- Commit only after proof gates pass.
- Review before cleanup.

Checkpoint 5: hard cutover cleanup

- Remove superseded Review-package scaffolding and old authority paths.
- Re-run final proof gates.
- Commit cleanup only after regression/canary gates pass.

Checkpoint 6: implementation review and PR-ready wrapup

- Run implementation review swarm.
- Address or explicitly reject findings.
- Open/update PR and prove readiness.
- Do not merge unless separately authorized.

## Stop Conditions

- Stop and route back to plan creation if a ticket cannot be independently
  proven.
- Stop and reconverge if implementation reality contradicts the accepted spec or
  file-organization boundary.
- Stop before editing unrelated infrastructure when a proof failure is outside
  the scoped ticket.
- Stop before advancing when any required checkpoint proof gate fails.

## Blocked Condition

Blocked only when the same blocking condition repeats under Codex host blocked
rules and no meaningful progress can be made without user input or external
state change.
