# Bridge Transport Streaming Goal Details

goal_id: 2026-06-22-bridge-transport-streaming
Created: 2026-06-22

## Current State

Current workflow: ticket-01-fifth-review-second-post-review-fix-complete
Next workflow: `shravan-dev-workflow:implementation-review-swarm`

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
- Ticket 00 carrier proof is committed at `bbf9e51c`.
- Ticket 01 core transport contracts are committed at `00d22ce0` after scoped
  BridgeWeb, fixture sync, Swift/WebKit, and lint proof.
- Broad Swift health remains open because `CommandBarDataSourceTests/
  test_commandsScope_includesOpenBridgeReview` expects `Open Bridge Review`
  while current command catalog title is `Review`. That failure is outside the
  ticket 01 transport/security write scope and is recorded in the execution
  brief.
- Ticket 01 implementation review completed and returned `not_ready`.
  Accepted blockers are page-world method-only privileged RPC ingress,
  descriptor/lease authority being URL-string based instead of descriptor-bound,
  and implemented core contracts drifting from the accepted spec. Accepted
  important findings cover the legacy scheme route fail-closed gap, TS/Swift
  encoded-slash URL parity, and descriptor registry lifecycle/reset handling.
- Ticket 01 accepted review findings were partially addressed and committed at
  `f09d768a fix: close bridge transport review findings`.
- Fresh implementation-review-swarm on `f09d768a` returned `not_ready`.
  Accepted blockers were Swift lease authority still being URL/pane-based, the
  legacy content route bypassing host lease authority, and descriptor registry
  URL validation not binding opaque resource id. Accepted important findings
  covered OPTIONS/HEAD route mismatch, legacy-route proof gaps, and a hardcoded
  Swift protocol/kind registry.
- A second ticket 01 review-fix implementation pass is committed at
  `10d2b075 fix: bind bridge resource leases to descriptors`. It hard-cutover
  content handles and the browser content parser to
  protocol-scoped resource URLs, makes legacy content routes fail closed, binds
  descriptor ids to URL opaque ids, checks leases against descriptor authority
  and byte limits, injects the Swift protocol/kind registry, and proves HEAD /
  OPTIONS behavior.
- A third ticket 01 review-fix implementation pass is committed at
  `acb4bd3f fix: close bridge content authority gaps`. It closes the accepted
  second-review residuals: dev-server/fixture URL cutover, stable-decoded URL
  rejection parity, metadata-only HEAD responses, atomic lease replacement,
  controller-owned lease registration proof, failed-reload authority revocation,
  teardown cleanup, active-source stale URL sweeps, and WebKit lane inclusion
  for the new controller authority suite.
- Review of the third ticket 01 review-fix pass returned `not_ready`. Accepted
  findings covered content-handle activation using too broad an allowlist and
  ignoring `replace(false)`, in-flight content loads surviving deactivation,
  missing review-viewer allowlist negative proof, teardown post-return lease
  authority, and a refresh-failure proof that revoked old authority while
  keeping old metadata visible.
- A follow-up implementation pass now fixes those accepted findings: content
  activation is content-only and all-or-nothing, store deactivation uses an
  authority revision to reject stale in-flight loads, teardown synchronously
  closes the review/content lease gate, and invalid refresh metadata preserves
  old package plus old leases together.
- Review of `60fb99d7` returned `not_ready`. Accepted findings covered an
  in-flight `loadDiff` re-authorizing after teardown, same-generation refresh
  invalidating preserved in-flight content, filtered reset semantics, weak
  invalid-refresh/teardown proof, and workflow-state transition drift.
- The fourth follow-up pass now fixes those findings with a revocation-revision
  fence for content activation, key/handle-based in-flight content validation,
  filter-accurate lease resets, stronger controller/store/registry tests, and
  corrected workflow event direction.
- Review of `e076fc4b` returned `not_ready`. Accepted findings covered an IPC
  stale-content window after teardown, direct lease registration bypassing the
  revocation-revision contract, same-generation content validation using full
  handle equality instead of authority identity, stale workflow-state text, and
  a green-only fourth-review proof packet.
- The fifth follow-up pass now fixes those findings with lease-first content
  activation, IPC review/content revocation checks, revocation-revision-fenced
  direct registration, explicit content-handle authority identity, and updated
  checkpoint proof notes. A red-proof attempt against `e076fc4b` was blocked by
  the scratch checkout missing `Frameworks/GhosttyKit.xcframework`; that blocker
  is recorded instead of overclaiming red proof.
- Review of `57601c5b` returned `not_ready`. Accepted findings covered teardown
  being able to advance the expected revocation revision while `loadDiff` was
  in flight, cached/coalesced content not being normalized onto the current
  active handle, optional `replace` revocation revisions, and missing in-flight
  IPC stale-content proof.
- The post-review follow-up is committed at
  `b68c70ea fix: harden bridge content authority after review`. It adds a
  review-content authority lifetime fence, normalizes returned content onto the
  active handle and active policy, makes lease replacement require an expected
  revision, and proves in-flight IPC teardown plus active byte-cap invalidation.
- Review of `b68c70ea` returned `not_ready`. Accepted findings covered
  superseding review loads not synchronously revoking previous authority before
  provider comparison, scheme-handler check/yield revocation races, and an
  oversized-content proof gap that did not prove zero emitted response/body
  events.
- The second post-review follow-up is committed at
  `4c4c7773 fix: close bridge authority races`. It synchronously revokes
  review/content authority before superseding review loads can suspend, gates
  scheme-handler response/body yields under the same synchronous authority lock
  used by revocation, and proves zero scheme events before oversized-content
  rejection plus in-flight reload revocation.
- Next step is to route `4c4c7773` back to implementation-review-swarm before
  ticket 02 begins.

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
- `tmp/plan-workflows/2026-06-22-bridge-transport-streaming-implementation-plan/implementation-review-ticket-01-report.md`
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

Status: ticket 00 committed; ticket 01 original checkpoint committed; first
ticket 01 review-fix checkpoint committed but review returned `not_ready`;
second ticket 01 review-fix pass is committed and proven; third ticket 01
review-fix pass returned `not_ready`; fourth and fifth follow-up fixes are
committed; the fifth-review second post-review follow-up is proven and ready
for re-review.

Evidence:

- ticket 00 commit: `bbf9e51c feat: prove bridge intake carrier`
- ticket 01 commit: `00d22ce0 feat: add bridge transport contracts`
- ticket 01 review-fix commit:
  `f09d768a fix: close bridge transport review findings`
- ticket 01 second review-fix commit:
  `10d2b075 fix: bind bridge resource leases to descriptors`
- ticket 01 third review-fix commit:
  `acb4bd3f fix: close bridge content authority gaps`
- ticket 01 third-review follow-up commit:
  `60fb99d7 fix: harden bridge content authority revocation`
- ticket 01 fourth-review follow-up commit:
  `e076fc4b fix: fence bridge content authority after teardown`
- ticket 01 fifth-review follow-up commit:
  `57601c5b fix: close bridge content authority race`
- ticket 01 fifth-review post-review follow-up commit:
  `b68c70ea fix: harden bridge content authority after review`
- ticket 01 fifth-review second post-review follow-up commit:
  `4c4c7773 fix: close bridge authority races`
- ticket 01 fourth-review follow-up report:
  `tmp/plan-workflows/2026-06-22-bridge-transport-streaming-implementation-plan/implementation-review-ticket-01-fourth-review-fix/report.md`
- ticket 01 fifth-review follow-up report:
  `tmp/plan-workflows/2026-06-22-bridge-transport-streaming-implementation-plan/implementation-review-ticket-01-fifth-review-fix/report.md`
- ticket 01 review-fix report:
  `tmp/plan-workflows/2026-06-22-bridge-transport-streaming-implementation-plan/implementation-review-ticket-01-review-fix-report.md`
- ticket 01 second-review-fix response report:
  `tmp/plan-workflows/2026-06-22-bridge-transport-streaming-implementation-plan/implementation-review-ticket-01-second-review-fix/report.md`
- ticket 01 third-review follow-up report:
  `tmp/plan-workflows/2026-06-22-bridge-transport-streaming-implementation-plan/implementation-review-ticket-01-third-review-fix/report.md`
- execution proof ledger:
  `tmp/plan-workflows/2026-06-22-bridge-transport-streaming-implementation-plan/implementation-execute-plan-brief.md`

Open before ticket 02:

- re-review the fixed ticket-01 trust/transport boundary after the
  fifth-review second post-review follow-up fix
- keep broad Swift health open until the unrelated CommandBar title mismatch is
  fixed in a separate scope or final milestone proof passes

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
