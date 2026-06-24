# Bridge Transport Streaming Goal Details

goal_id: 2026-06-22-bridge-transport-streaming
Created: 2026-06-22

## Current State

Current workflow: `shravan-dev-workflow:implementation-execute-plan`
Next workflow: `shravan-dev-workflow:implementation-execute-plan`

Reason:

- Ticket 04 Worktree/File browser/dev-server implementation reached mandatory
  implementation review at `f5701c94`.
- The first review-fix pass at `6724fae3` closed the original scroll/loading
  proof issues, but Ticket 04 re-review returned `not_ready`.
- Accepted re-review findings were in-flight invalidation stale completion,
  invalidation-only tree state loss, stale flow missing explicit refresh/body
  continuity, changed-file symlink escape in the Vite dev provider, and missing
  ticket-local red proof.
- Those accepted findings were patched and proven. A second focused re-review
  then accepted one proof-only blocker: stale invalidation and explicit refresh
  needed browser-level proof, not jsdom only.
- Browser proof is now added and green, including post-refresh rendered-DOM
  scrubbing for `agentstudio://resource` capability URLs at `9141c177`.
  Two focused re-review lanes found no blocker or important findings. Route to
  `shravan-dev-workflow:implementation-execute-plan` for Ticket 05 cleanup /
  hard cutover before PR readiness or final goal closeout.

Current Ticket 03 checkpoint status:

- Native Worktree/File active-source retention, live status patches, live file
  invalidations, reset frames, replacement descriptors, resource body serving,
  and automatic filesystem/status watcher fanout are implemented and covered by
  focused Swift tests.
- Ticket 03 fanout implementation review is recorded at
  `tmp/plan-workflows/2026-06-22-bridge-transport-streaming-implementation-plan/implementation-review-ticket-03-fanout/report.md`
  with verdict `ready_with_fixes`.
- The current code should route next to
  `shravan-dev-workflow:implementation-execute-plan` for Ticket 04 browser
  Worktree/File materializer/dev-server work, carrying the accepted follow-up
  for negative fanout proof.
- Ticket 04 still owns browser-side Worktree/File response seeding,
  materialization, strict shared frame fixtures/Zod schemas, and the scroll
  extent canary against the dev server.
- Ticket 04 initial browser contracts are now in progress: Worktree/File
  browser schemas, demand policy, and open-file session state primitives are
  implemented with focused unit proof and BridgeWeb quality proof. Remaining
  Ticket 04 work includes materializer/body registry integration, app routing,
  surface UI, dev-server replacement, browser integration, benchmark/canary, and
  the accepted negative fanout proof follow-up before PR readiness.
- Ticket 04 browser materializer descriptor-registration/reset semantics are now
  implemented and proven with focused unit proof and BridgeWeb quality proof.
  Remaining Ticket 04 work includes body registry/executor integration into the
  surface runtime, app routing, surface UI, dev-server replacement, browser
  integration, benchmark/canary, and the accepted negative fanout proof follow-up
  before PR readiness.
- Ticket 04 Worktree/File surface runtime, app routing, dev-provider frame
  projection, and Vite worktree dev URL cutover are now implemented and proven.
  The live worktree URL loads Worktree/File frames, reserves tree extent from
  provider facts, and fetches selected file content through descriptor-backed
  Worktree/File resources with no file bodies in surface metadata. Remaining
  Ticket 04 work includes the full browser integration suite, objective scroll
  extent canary/benchmark proof, binary/oversized behavior, renderer-boundary
  telemetry proof, accepted negative fanout follow-up, and implementation review
  before PR readiness.
- Ticket 04 now also has the first real browser scroll-extent canary for the
  Worktree/File surface. The canary failed red when the tree exposed provider
  size metadata but did not reserve real browser scroll extent, then passed
  after `WorktreeFileApp` rendered bounded tree/file scroll owners with inner
  extent elements sized from provider facts and file descriptor extent metadata.
  Remaining extent work still includes huge-worktree churn, anchor preservation
  diagnostics, benchmark artifacts, and binary/oversized cases.
- The accepted Ticket 03 review follow-up for negative coordinator fanout proof
  is now closed in Ticket 04. The focused Swift suite proves nonmatching
  Worktree/File Bridge controllers do not receive filesystem invalidation or
  git status intake frames for another worktree.

Historical context:

- Latest transition after authority-boundary reconvergence routes from
  `shravan-dev-workflow:implementation-execute-plan` to
  `shravan-dev-workflow:implementation-review-swarm`: Ticket 02 should no
  longer chase host-only page-message provenance, and native
  lease/scheme-handler authority proof is green under the corrected closed-app
  boundary.
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
- Review of `4c4c7773` / `aa6fd8da` returned `not_ready`. Accepted findings
  covered the scheme-handler final emission gate checking revocation without
  proving the exact active lease still matched, targeted revoke / filtered reset
  missing exact resource tombstones and revocation revision protection, and a
  missing HEAD no-emission proof.
- The third post-review follow-up is committed at
  `55c2689c fix: harden bridge lease emission authority`. It adds exact
  resource tombstones for targeted revokes and filtered resets, requires direct
  registration to clear the matching tombstone with the current revocation
  revision, gates response/body/HEAD emission through actor-isolated
  `performWhileLeased`, removes the superseded sync helper, and splits
  scheme-handler content authority tests.
- Review of `55c2689c` / `7bed47d9` returned `not_ready`. Accepted findings
  covered missing GET-body and HEAD authority-loss proof, missing filtered-reset
  stale re-registration proof, and `replace` clearing exact tombstones without
  advancing the revision.
- The fourth post-review follow-up is committed at
  `2d55eef2 fix: close bridge lease proof gaps`. It preserves non-installed
  exact tombstones across replacement, advances the scope revision after
  replacement, proves stale registration after filtered reset and replacement,
  and proves GET body / HEAD response authority loss with bounded gates.
- Review of `2d55eef2` / `00e68163` returned `not_ready` with one accepted P2
  proof robustness finding: the GET-body proof could hang if the stream exited
  after response emission but before the body hook.
- The fifth post-review follow-up is committed at
  `f892f007 test: bound bridge body emission proof`. It makes the emission step
  gate stream-finished aware and makes the GET-body test fail immediately if
  the body hook is not reached.
- Re-review of `f892f007` / `29955968` returned `ready` with no accepted
  findings across proof-helper reliability, docs/workflow-state mapping, and
  trust-boundary regression smoke lanes.
- Checkpoint 2 / ticket 02 is now in progress. The first contract slice added
  generic BridgeWeb demand primitives, Review protocol schemas/materializer/
  policy, a descriptor-backed Review content demand adapter, and Swift
  ReviewProtocol snapshot frame descriptor attachment.
- The second ticket 02 pass cut the live Review path further: Swift
  `DiffPackageMetadataSlice` now carries a ReviewProtocol snapshot frame,
  `BridgeApp` registers descriptors from accepted snapshot frames, selected and
  visible content hydration use descriptor-backed demand, and browser dev/test
  push helpers attach protocol frames.
- The browser/dev-server blocker was fixed in this pass. The root cause was a
  priority inversion where a visible-lane hydration failure could mark the
  selected canvas unavailable before selected demand won, plus delta pushes that
  updated package items without registering descriptors for newly added handles.
  Selected unavailability is now owned by selected content demand, and both
  browser dev/test and Swift delta slices carry ReviewProtocol snapshot frames
  for the resulting revision.
- Current ticket 02 proof so far:
  - BridgeWeb focused unit/integration gate: exit 0, 11 files passed, 57
    tests passed before the final selected/delta fix; current focused gate is
    exit 0, 11 files passed, 58 tests passed. Existing jsdom ResizeManager warnings and the known filter
    test `flushSync` warning remain.
  - Browser integration gate:
    `pnpm --dir BridgeWeb run test:browser:integration --
    src/review-viewer/test-support/bridge-viewer-browser.integration.browser.test.tsx`:
    exit 0, 1 file passed, 30 tests passed. Existing React `flushSync` warnings
    remain in two filter/chip tests.
  - Dev-server mock gate: `pnpm --dir BridgeWeb run test:dev-server`: exit 0
    for `http://127.0.0.1:5173/?fixture=large-diffshub&workers=on&scenario=scroll`.
  - Dev-server worktree gate:
    `BRIDGE_VIEWER_WORKTREE_DEV_SERVER_URL='http://127.0.0.1:5173/?fixture=worktree&workers=on&scenario=current-worktree'
    pnpm --dir BridgeWeb run test:dev-server:worktree`: exit 0. Selected
    content reached `ready` for `.github/workflows/ci.yml`.
  - `pnpm --dir BridgeWeb run check`: exit 0.
  - `mise run format`: exit 0.
  - `pnpm --dir BridgeWeb run fmt`: exit 0.
  - `mise run lint`: exit 0; SwiftLint 0 violations, AgentStudio architecture
    lint OK, release script verification passed.
  - `git diff --check`: exit 0.
  - `SWIFT_TEST_TIMEOUT_SECONDS=60 SWIFT_TEST_PREBUILD_TIMEOUT_SECONDS=180
    mise run test-fast -- --filter BridgeReviewProtocolFrameBuilderTests`:
    exit 0, 3 Swift tests passed. This lane rebuilt BridgeWeb assets and wrote
    `tmp/bridge-web-assets/latest-app-asset-audit.json`.
- Next step is to continue ticket 02 with markdown click/reveal proof,
  telemetry/benchmark gates, and implementation review. Do not advance beyond
  checkpoint 2 until the full ticket 02 proof gates and implementation review pass.
- The current ticket 02 review-fix pass has now closed the first four accepted
  blockers from the latest implementation review: `review.delta` is a real
  protocol frame in Swift, browser dev/test, schema, builder, materializer, and
  app admission; `review.invalidate` and standalone `review.reset` have schema,
  materializer, and Swift builder coverage; Review frame authority is
  host-published instead of self-authenticated from incoming frames; reset
  revokes descriptor authority before the next load; and delta materialization
  failures fail closed by clearing stale descriptor refs.
- Current ticket 02 review-fix proof:
  - `pnpm --dir BridgeWeb run fmt`: exit 0.
  - `pnpm --dir BridgeWeb run check`: exit 0.
  - `pnpm --dir BridgeWeb exec vitest run
    src/features/review/models/review-protocol-models.unit.test.ts
    src/features/review/protocol/review-snapshot-frame-builder.unit.test.ts
    src/features/review/materialization/review-materializer.unit.test.ts
    src/app/bridge-app.integration.test.tsx
    src/review-viewer/test-support/bridge-viewer-mocked-backend.unit.test.ts
    --reporter verbose`: exit 0, 5 files passed, 61 tests passed. Existing
    jsdom ResizeManager warnings remain.
  - `mise run format`: exit 0.
  - `SWIFT_TEST_PREBUILD_TIMEOUT_SECONDS=120 mise run test -- --filter
    BridgeReviewProtocolFrameBuilderTests`: exit 0, 7 Swift tests passed. A
    prior run with the default 60s prebuild watchdog timed out after the build
    completed in 63.26s, so the rerun widened only the prebuild margin.
- Remaining ticket 02 accepted findings before renewed review/checkpoint:
  scheduler/executor queue and cancellation ownership, changeset-cluster
  metadata parity, Swift frame build failure surfacing, demand-runtime proof
  accounting, and markdown security proof accounting.

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
committed; the fifth-review fifth post-review follow-up is proven and reviewed
ready.

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
- ticket 01 fifth-review third post-review follow-up commit:
  `55c2689c fix: harden bridge lease emission authority`
- ticket 01 fifth-review fourth post-review follow-up commit:
  `2d55eef2 fix: close bridge lease proof gaps`
- ticket 01 fifth-review fifth post-review follow-up commit:
  `f892f007 test: bound bridge body emission proof`
- ticket 01 final bounded-proof docs commit:
  `29955968 docs: record bounded bridge proof fix`
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

- none for ticket 01 review; checkpoint 2 / ticket 02 can begin
- keep broad Swift health open until the unrelated CommandBar title mismatch is
  fixed in a separate scope or final milestone proof passes

Checkpoint 2: Review vertical with descriptor-backed demand

- Review frames attach descriptors before demand runtime becomes authoritative.
- Implement/prove Review materializer, Review demand policy, core scheduler and
  executor through Review.
- Preserve Worktree dev proof until replacement exists.
- Commit only after proof gates pass.
- Run implementation review before moving to Worktree/File.
- Current status: implementation proof gates are complete as of 2026-06-23.
  Browser integration covers markdown click/reveal and streaming append delta;
  dev-server proof covers normal and exact current-worktree URLs; telemetry
  canary and browser/non-browser benchmark gates are green. Remaining action
  before checkpoint completion is implementation-review-swarm and any accepted
  review fixes.
- 2026-06-23 review follow-up: implementation-review-swarm/browser lanes found
  ticket 02 was not ready despite earlier proof. Accepted blockers were real
  Swift-to-browser integrity mismatch for non-sha256 host hashes, partial
  descriptor materialization rollback, stale/foreign descriptor admission, raw
  visible-hydration fallback, and demand identity collapse across stream/cursor
  boundaries.
- 2026-06-23 current fix/proof pass: Swift and TS frame builders now emit
  `previewOnly` integrity for non-sha256 host hashes; Review materialization
  rolls back registered descriptors on later rejection; BridgeApp validates
  attached descriptors against the accepted package handles before installing
  fetch authority; visible hydration requires the descriptor-backed loader; and
  selected/visible demand share one BridgeApp scheduler instance.
- 2026-06-23 proof after review fixes:
  `pnpm --dir BridgeWeb run check` exit 0;
  focused Vitest subset exit 0 with 5 files and 48 tests passed;
  focused ticket 02 Vitest subset exit 0 with 11 files and 68 tests passed;
  `mise run test --filter BridgeReviewProtocolFrameBuilderTests` exit 0 with 4
  Swift tests passed after one prebuild timeout retry; and
  `BRIDGE_VIEWER_WORKTREE_TARGET_PATH='BridgeWeb/src/bridge/bridge-page-handshake.ts'
  pnpm --dir BridgeWeb run test:dev-server:worktree` exit 0 with selected
  content `ready`, 178 selected lines, and worker pool `ready`.
- Remaining before checkpoint 2 acceptance: rerun implementation-review-swarm
  against the fixed worktree, decide whether smoothness parity is acceptable for
  this checkpoint or belongs in a follow-up ticket, then commit/checkpoint only
  if review accepts the proof.
- 2026-06-23 second review-fix pass after the renewed Ticket 02 review:
  accepted findings around stale selected body replay, terminal pressure
  failures, protocol-frame lineage, unsafe mocked-backend URL parsing, and
  low-priority executor backlog interference are fixed in the current worktree.
  The final browser benchmark root cause was foreground-vs-visible queue
  interference: visible hydration could build a low-priority pending backlog in
  the shared executor and delay selected failure materialization by about 2s.
  Executor queue admission now allows only `foreground` and `active` lanes to
  queue under transient pressure; `visible`, `nearby`, and `speculative` remain
  opportunistic.
- 2026-06-23 fresh proof after the second review-fix pass:
  `pnpm --dir BridgeWeb run fmt` exit 0;
  `pnpm --dir BridgeWeb run check` exit 0;
  focused Web gate exit 0 with 12 files and 78 tests passed;
  browser integration exit 0 with 1 file and 30 tests passed;
  `pnpm --dir BridgeWeb run test:dev-server` exit 0 for the normal large
  fixture URL;
  exact worktree URL gate exit 0 for
  `http://127.0.0.1:5173/?fixture=worktree&workers=on&scenario=current-worktree`
  with selected `.github/workflows/ci.yml` ready, worker pool ready, and
  revision 39;
  `pnpm --dir BridgeWeb run test:benchmark:browser` exit 0 with artifact
  `tmp/bridge-viewer-browser-benchmark/2026-06-23T09-50-55-779Z`;
  `failure-content-unavailable` recovered from failing p95
  `2092.400000035763ms` to passing p95 `28.5ms`;
  `mise run format` exit 0;
  `SWIFT_TEST_TIMEOUT_SECONDS=60 SWIFT_TEST_PREBUILD_TIMEOUT_SECONDS=180 mise run
  test-fast -- --filter BridgeReviewProtocolFrameBuilderTests` exit 0 with 4
  Swift tests passed;
  `mise run lint` exit 0; and `git diff --check` exit 0.
- Remaining before checkpoint 2 acceptance: rerun implementation-review-swarm
  against this current worktree and resolve any accepted findings. Do not commit
  or advance to Worktree/File until that review is ready.
- 2026-06-23 implementation-review-swarm after the second Ticket 02 review-fix
  pass returned `not_ready`. Report:
  `tmp/plan-workflows/2026-06-22-bridge-transport-streaming-implementation-plan/implementation-review-ticket-02-review-fix/report.md`.
  Accepted blockers: Ticket 02 still emits snapshot-only Review protocol frames
  instead of real `review.delta`, `review.invalidate`, and standalone
  `review.reset`; snapshot descriptor identity is self-authenticated from the
  incoming frame instead of a local pane/stream source of truth; standalone
  reset frames are ignored before descriptor revocation; and delta
  materialization can fail open and reuse stale descriptor refs. Accepted
  important findings: demand queue/cancel ownership is split across scheduler
  and executor, changeset-cluster metadata is narrower than the spec, protocol
  frame builder failures are swallowed with `try?`, and required proof
  accounting is missing for demand-runtime integration and markdown security
  suites or explicit replacements.
- Current route: back to `shravan-dev-workflow:implementation-execute-plan`.
  Do not checkpoint, commit, or advance to Worktree/File until the accepted
  blockers/important findings are fixed, proven, and reviewed again.
- 2026-06-23 current review-fix pass status: accepted implementation-review
  blockers/important findings have been addressed and are ready for renewed
  `shravan-dev-workflow:implementation-review-swarm` reduction.
  Real `review.delta`, `review.invalidate`, and standalone `review.reset`
  now exist across Swift frame building, browser dev/test helpers, Zod schemas,
  TS frame builders, materializer paths, telemetry parent refresh, and
  BridgeApp admission. BridgeApp accepts Review frames only against
  host-published pane/stream authority, native and dev/mock bootstraps publish
  that authority, standalone reset frames revoke descriptor authority before a
  new load, and failed delta materialization clears old descriptor refs instead
  of reusing them. Scheduler/executor pressure now treats only foreground and
  active demand as queueable under transient pressure; visible, nearby, and
  speculative demand stay opportunistic. Selected content demand preserves
  retryable deferred state instead of collapsing transient pressure into
  terminal content unavailable. Mocked deferred content fetches remove their
  pending response when aborted so stale visible requests cannot mask a later
  foreground selected request. The follow-up review-fix pass also keeps
  invalidated cached bodies bypassed until a refetch succeeds, stores Swift
  Review snapshot/delta protocol frames with package/delta facts before content
  authority activation, aligns TS/Swift root/delta metadata descriptor
  `maxBytes`, labels queue/fetch telemetry with selected/visible demand and
  result facts, removes per-content-fetch forced telemetry flushes, and fixes
  the dev-server/benchmark proof harness waits that were brittle under live
  telemetry and worker readiness.
- 2026-06-23 proof for this completed review-fix pass:
  `pnpm --dir BridgeWeb run fmt` exit 0;
  `pnpm --dir BridgeWeb run check` exit 0;
  `pnpm --dir BridgeWeb exec vitest run
  src/core/models/bridge-demand-models.unit.test.ts
  src/core/demand/bridge-demand-scheduler.unit.test.ts
  src/core/demand/bridge-body-registry.unit.test.ts
  src/core/demand/bridge-resource-executor.unit.test.ts
  src/features/review/models/review-protocol-models.unit.test.ts
  src/features/review/materialization/review-materializer.unit.test.ts
  src/features/review/demand/review-demand-policy.unit.test.ts
  src/features/review/protocol/review-snapshot-frame-builder.unit.test.ts
  src/review-viewer/content/review-content-demand-loader.unit.test.ts
  src/review-viewer/content/visible-review-content-hydration.unit.test.tsx
  src/app/bridge-app.integration.test.tsx
  src/review-viewer/test-support/bridge-viewer-mocked-backend.unit.test.ts`:
  exit 0, 12 files passed, 107 tests passed;
  `pnpm --dir BridgeWeb exec vitest run
  src/review-viewer/markdown/bridge-markdown-preview.unit.test.tsx
  src/review-viewer/markdown/bridge-markdown-render-mode.unit.test.ts
  src/review-viewer/workers/markdown/bridge-markdown-render-worker-rpc.unit.test.ts
  --reporter verbose`: exit 0, 3 files passed, 16 tests passed;
  `pnpm --dir BridgeWeb run test:browser:integration --
  src/review-viewer/test-support/bridge-viewer-browser.integration.browser.test.tsx`:
  exit 0, 1 file passed, 30 tests passed after one transient full-run failure
  in the content-unavailable browser case; single-case rerun and full rerun both
  passed;
  `pnpm --dir BridgeWeb run test:dev-server` exit 0 after replacing
  telemetry-brittle `networkidle` waits with `domcontentloaded` plus app-state
  probes;
  `BRIDGE_VIEWER_WORKTREE_DEV_SERVER_URL='http://127.0.0.1:5173/?fixture=worktree&workers=on&scenario=current-worktree'
  pnpm --dir BridgeWeb run test:dev-server:worktree` exit 0 with selected
  `.github/workflows/ci.yml` ready and worker pool ready;
  `pnpm --dir BridgeWeb run test:benchmark:browser` exit 0 with artifact
  `tmp/bridge-viewer-browser-benchmark/2026-06-23T14-14-04-892Z`;
  `mise run format` exit 0;
  `SWIFT_TEST_TIMEOUT_SECONDS=60 SWIFT_TEST_PREBUILD_TIMEOUT_SECONDS=180 mise run
  test-fast -- --filter BridgeReviewProtocolFrameBuilderTests` exit 0 with 11
  Swift tests passed;
  `mise run lint` exit 0; and `git diff --check` exit 0.
- 2026-06-23 manual/dev-server pressure evidence: after fresh-loading,
  scrolling, clicking the exact current-worktree URL, and running the dev-server
  proof gates, Vite dev telemetry stayed healthy with
  `acceptedBatchCount=6466`, `acceptedSampleCount=27859`,
  and `failedBatchCount=0` for marker `vite-dev-ticket02-1782220582`.
  VictoriaLogs for `vite-dev-worktree-current-worktree` were dominated by
  content demand activity: `content_fetch=4061` and `content_queue=3204`,
  while projection/worker/item/highlight counts stayed low. This supports that
  Ticket 02 demand/content loading is the pressure surface, but current
  telemetry does not yet prove why the scrollbar jumps because it lacks
  virtualizer extent fields such as scrollTop before/after, total content
  height, visible range, anchor item/offset, and layout reconciliation reason.
- 2026-06-23 Pierre/DiffsHub source research:
  `/Users/shravansunder/Documents/dev/open-source/libs-react/pierre` shows
  DiffsHub stabilizes the file tree with bounded `pathCount` snapshots and a
  fixed `24px` row-height tree model, not per-file body sizing. DiffsHub
  stabilizes diff/code scroll by parsing streamed patch chunks into
  `FileDiffMetadata` with file/hunk line counts, reserving estimated CodeView
  item heights before DOM render, then reconciling sparse measured deltas with
  scroll anchoring. This is a real design delta for Ticket 03: Bridge has
  descriptor-backed content demand and proof gates, but no equivalent
  virtualized-size contract or scroll-extent telemetry canary yet.
- 2026-06-23 renewed implementation-review-swarm against the current Ticket 02
  review-fix pass returned `not_ready`. Report:
  `tmp/plan-workflows/2026-06-22-bridge-transport-streaming-implementation-plan/implementation-review-ticket-02-renewed/report.md`.
  Lane artifacts:
  `tmp/plan-workflows/2026-06-22-bridge-transport-streaming-implementation-plan/implementation-review-ticket-02-renewed/lanes/spec-proof.md`,
  `tmp/plan-workflows/2026-06-22-bridge-transport-streaming-implementation-plan/implementation-review-ticket-02-renewed/lanes/reliability-performance.md`,
  and
  `tmp/plan-workflows/2026-06-22-bridge-transport-streaming-implementation-plan/implementation-review-ticket-02-renewed/lanes/security.md`.
  Accepted blockers: Review protocol frame admission is still
  self-authenticated from page-world push data instead of host-only authority,
  and the Ticket 02 proof packet omits or fails to replace slice-required
  demand-runtime and compatibility gates. Accepted important findings:
  `review.delta` rejects spec-legal partial descriptor attachment/lineage reuse,
  scheduler queue pressure can become terminal `descriptor_missing`, Vite dev
  telemetry forwards arbitrary browser attributes to OTLP, selected-content
  retry can spin once per animation frame under sustained deferred pressure,
  and the worker-backed cold benchmark should assert explicit worker-ready
  diagnostics. The contracts/tests lane was still pending at reducer cutoff,
  but the accepted blockers are already decisive.
- Current route: back to `shravan-dev-workflow:implementation-execute-plan`.
  Do not checkpoint, commit, or advance to Worktree/File until these accepted
  blockers/important findings are fixed, proven, and reviewed again.
- 2026-06-23 follow-up execute-plan pass after renewed review:
  - Fixed `review.delta` partial descriptor attachment/lineage reuse. Delta
    frames may now attach only changed/new content descriptors and merge those
    refs into the existing accepted lineage map while validating each attached
    descriptor against the current package handle.
  - Fixed scheduler queue pressure in
    `BridgeWeb/src/review-viewer/content/review-content-demand-loader.ts` so a
    per-role scheduler enqueue rejection returns deferred pressure and rolls
    back partial per-item enqueues instead of degrading into terminal
    `descriptor_missing`. Queue admission now budgets by content-handle size
    rather than charging the full item size for every role.
  - Fixed selected-content deferred retry scheduling with a one-shot
    animation-frame guard matching visible hydration's retry behavior.
  - Fixed Vite dev telemetry OTLP export to reject unsafe browser-supplied
    attribute keys/values before collector export. Canary values include raw
    `/Users/...` paths, `prompt-canary`, and `agentstudio://resource/...`.
  - Added the missing slice-required
    `BridgeWeb/src/core/demand/bridge-demand-runtime.integration.test.ts`
    proving the generic descriptor registry + scheduler + executor + body
    registry seam, including fail-closed unregistered descriptor demand.
  - Fresh proof:
    `pnpm --dir BridgeWeb run fmt`: exit 0.
    `pnpm --dir BridgeWeb run check`: exit 0.
    `pnpm --dir BridgeWeb exec vitest run ...slice-required demand,
    compatibility, markdown/security, dev telemetry, app integration pack...`:
    exit 0, 17 files passed, 135 tests passed. Existing jsdom
    ResizeManager warnings remain.
  - Independent read-only analysis by subagents confirmed the remaining
    host-only Review protocol frame admission blocker is real: current Swift
    dispatches push envelopes into `.page`, the push nonce is exposed through
    page-world handshake/replay, review pane/stream authority is page-visible
    on DOM attributes, and TS-only tests can prove vulnerability or a future
    verifier hook but cannot prove host-only provenance. A genuine fix needs a
    host/bridge-world admission boundary before page-world push dispatch, or a
    reconverged design for how Review materialization crosses that boundary.
  - Current route remains `shravan-dev-workflow:implementation-execute-plan`.
    Do not checkpoint, commit, or advance to Worktree/File until the host-only
    protocol-frame admission boundary is designed, implemented, proven, and
    reviewed, or the spec/plan explicitly accepts a narrower mitigation.
- 2026-06-23 activated-goal proof refresh:
  - Strengthened the new demand-runtime integration proof so it exercises both
    descriptor-backed body cache miss and cache-hit paths, plus fail-closed
    unregistered descriptor demand.
  - Final focused slice proof:
    `pnpm --dir BridgeWeb exec vitest run ...slice-required demand,
    compatibility, markdown/security, dev telemetry, app integration pack...
    --reporter dot`: exit 0, 17 files passed, 135 tests passed.
  - `git diff --check`: exit 0.
  - Decision unchanged: Ticket 02 is improved and currently active, but it is
    not checkpoint-ready because host-only Review protocol frame admission
    still needs a host/bridge-world boundary or an explicit spec/plan
    reconvergence.
- 2026-06-23 reviewer-regression follow-up:
  - A reviewer lane returned `not_ready` for the current follow-up patch with
    three accepted findings: two-sided selected diffs could defer forever when
    each side fit executor bytes but the combined scheduler estimate exceeded
    the queue cap; partial `review.delta` frames could carry stale refs for
    omitted handles whose stable handle lineage changed; and Vite dev telemetry
    rejected BridgeApp telemetry-drop samples because
    `agentstudio.bridge.telemetry.drop_reason` was missing from the allowlist.
  - Fixed the Review content demand loader so synchronous per-role enqueue does
    not charge full body bytes at scheduler queue admission; executor byte caps
    remain the body authority.
  - Fixed partial-delta descriptor lineage so the descriptor ref map is rebuilt
    from the new package handle set: attached refs replace changed handles,
    old refs are carried only when handle lineage is identical, and removed
    handles drop their refs.
  - Fixed the dev-server telemetry allowlist for
    `agentstudio.bridge.telemetry.drop_reason`.
  - Red/green proof:
    `pnpm --dir BridgeWeb exec vitest run
    src/review-viewer/content/review-content-demand-loader.unit.test.ts -t
    "two-sided content" --reporter verbose`: red `deferred` before fix, then
    exit 0.
    `pnpm --dir BridgeWeb exec vitest run
    scripts/dev-server/bridge-dev-telemetry.unit.test.ts -t "drop samples"
    --reporter verbose`: red `false` before fix, then exit 0.
    `pnpm --dir BridgeWeb exec vitest run src/app/bridge-app.integration.test.tsx
    -t "partial delta rejects omitted descriptor refs" --reporter verbose`:
    red old URL fetch before fix, then exit 0.
  - Fresh proof:
    `pnpm --dir BridgeWeb run fmt`: exit 0.
    `pnpm --dir BridgeWeb run check`: exit 0.
    `git diff --check`: exit 0.
    `pnpm --dir BridgeWeb exec vitest run ...slice-required demand,
    compatibility, markdown/security, dev telemetry, app integration pack...
    --reporter dot`: exit 0, 17 files passed, 138 tests passed.
  - Decision unchanged: this closes the reviewer-regression findings, but
    checkpoint 2 is still not ready while host-only Review protocol frame
    admission remains unresolved.
- 2026-06-23 plan-revision follow-up:
  - Added a host/bridge-world Review protocol frame-admission gate to the spec,
    review protocol, main plan, and Ticket 02 slice. The plan now states that
    page-visible nonce, DOM attributes, and sibling payload consistency are not
    sufficient authority for descriptor registration or package-lineage
    replacement.
  - Split the DiffsHub-style stable scroll extent work into two explicit
    deliverables: Ticket 03 provider/frame facts (`treeSizeFacts`,
    `virtualizedExtentKind`, line counts or estimated heights, and scrubbed
    diagnostics schema) and Ticket 04 browser consumption/canary proof
    (anchor-stable reconciliation, bounded drift, and attributed height deltas).
  - Decision unchanged: Ticket 02 is not checkpoint-ready; do not commit,
    checkpoint, or advance to Worktree/File until host-only frame admission is
    implemented, proven, and reviewed. Ticket 03 owns provider extent facts;
    Ticket 04 owns browser scroll-extent behavior.
- 2026-06-23 plan-review closeout:
  - Wrote
    `tmp/plan-workflows/2026-06-22-bridge-transport-streaming-implementation-plan/plan-review-2026-06-23-host-admission-scroll-report.md`.
  - Accepted and patched review findings for host/bridge-world frame admission,
    real WebKit forged-frame proof, fixture parity, partial `review.delta`
    descriptor attachment, source-scrubbed provider errors, Ticket 03 mandatory
    review, and Ticket 04 benchmark/canary proof.
  - Route is back to `shravan-dev-workflow:implementation-execute-plan` for
    Ticket 02 host-admission implementation. Checkpoint 2 is still not ready.
  - Validation after closeout:
    `git diff --check` for modified docs/workflow/test files exit 0;
    `events.jsonl` parse exit 0 with 36 events; `mise run lint` exit 0.
    Focused
    `SWIFT_TEST_TIMEOUT_SECONDS=120 SWIFT_TEST_PREBUILD_TIMEOUT_SECONDS=180
    mise run test-fast -- --filter
    'AgentStudioTests.WebKitSerializedTests/BridgeTransportIntegrationTests'`
    compiled, passed the first five tests, then failed
    `test_pushPackageMetadata_rendersReviewViewerShell` with
    `Review package unavailable / review_protocol_frame_unavailable`. That is
    the live Ticket 02 host-admission implementation blocker, not a plan-review
    closeout blocker.
- 2026-06-23 implementation-execute-plan lint/proof correction:
  - Fixed the stale WebKit integration fixture payloads in
    `Tests/AgentStudioTests/Features/Bridge/BridgeTransportIntegrationTests.swift`
    so manually pushed `DiffPackageMetadataSlice` values carry the host-built
    Review snapshot protocol frame required by the current Ticket 02 contract.
  - Fixed the SwiftLint `type_body_length` failure by moving test support types
    and helpers out of the `BridgeTransportIntegrationTests` suite body while
    preserving `@MainActor` access for `WebPage` helpers.
  - Asked a bounded docs worker to verify the Ticket 03 stable scroll-extent
    design delta. It made no edits because the plan/spec already anchor
    provider `treeSizeFacts`, `virtualizedExtentKind`, line-count or estimated
    extent metadata, source-scrubbed diagnostics, and the Ticket 04 objective
    canary/fail rules.
  - Validation after this correction:
    `mise exec -- swift-format lint
    Tests/AgentStudioTests/Features/Bridge/BridgeTransportIntegrationTests.swift`
    exit 0; `swiftlint lint --strict
    Tests/AgentStudioTests/Features/Bridge/BridgeTransportIntegrationTests.swift`
    exit 0 with 0 violations; `mise run lint` exit 0 with swift-format OK,
    SwiftLint 0 violations in 1313 files, architecture lint OK, and release
    script verification passed; targeted `git diff --check` exit 0.
  - WebKit proof status:
    `test_pushPackageMetadata_rendersReviewViewerShell` passed in the filtered
    suite after the fixture correction; `test_pushJSON_concurrentBurstDeliversOrderedPageEvents`,
    `test_handleDiffCommandWithSmokeProvider_rendersReviewViewerShell`, and
    `test_contentFetch_realDiffHandlesResolveAndDoNotRejectThroughReviewViewer`
    passed as isolated filters. The full
    `BridgeTransportIntegrationTests` filter still exits via WebKit signal
    5/11 at the transition into the burst test before completing the later
    tests, so checkpoint 2 is still not ready and the suite-level proof remains
    a caveat rather than green.
- 2026-06-23 scroll-extent plan/spec verification refresh:
  - Read-only explorer `019ef560-aae2-7a43-90b4-8f4d88dcb4b6` rechecked the
    scroll-extent concern against `spec.md`, `worktree-file-surface-protocol.md`,
    `implementation-plan.md`, and slices 03/04. It found no required docs patch.
  - Verified anchors: Ticket 03 owns provider/frame facts:
    `treeSizeFacts`, `virtualizedExtentKind`, and line-count or estimated-height
    metadata. Ticket 04 owns browser consumption plus the scroll-extent canary:
    stable anchor, bounded drift, total-height delta attribution, and benchmark
    artifact fields.
  - Current lint proof after the hook-reported stale failure:
    `mise run lint` exit 0 with swift-format OK, SwiftLint 0 violations in 1313
    files, AgentStudio architecture lint OK, and release script verification
    passed.
- 2026-06-23 host-admission implementation refresh:
  - Recovered `BridgeWeb/src/app/bridge-app.integration.test.tsx` after a bad
    broad fixture rewrite by restoring missing baseline tests from
    `tmp/red-proof-e076fc4b`, keeping the newer Ticket 02 demand/protocol tests,
    and converting legitimate descriptor-registering Review package/delta pushes
    to host-admitted protocol-frame fixtures.
  - Implemented a host/bridge-world push admission path in BridgeWeb: Swift
    bridge-world bootstrap publishes a transferred host push `MessagePort`, page
    code receives host envelopes from that port as `host-bridge-port`, and
    descriptor-registering Review frames sent through page-world `__bridge_push`
    are rejected before descriptor registration, package-lineage replacement,
    demand enqueue, or fetch.
  - Kept non-authoritative status/control page events working while host-admitted
    Review snapshot/delta frames materialize descriptors.
  - Fixed `bridge-push-receiver` JSON-string decode error handling so invalid
    page JSON pushes are reported through `onInvalidEnvelope`/`push_decode_failed`
    instead of escaping as unhandled exceptions.
  - Docs worker `019ef57a-39c3-7700-892b-1af5aa7a6b00` updated the spec/plan so
    Ticket 03 explicitly owns DiffsHub-style stable virtualized-size facts
    (`treeSizeFacts`, `virtualizedExtentKind`, exact line/row counts or
    conservative estimated extents) and Ticket 04 owns browser consumption plus
    scroll-extent telemetry canary proof.
  - Fresh proof:
    `pnpm --dir BridgeWeb run fmt`: exit 0.
    `pnpm --dir BridgeWeb run check`: exit 0.
    `pnpm --dir BridgeWeb exec vitest run
    src/bridge/bridge-push-receiver.unit.test.ts --reporter dot`: exit 0, 1
    file passed, 5 tests passed.
    `pnpm --dir BridgeWeb exec vitest run
    src/app/bridge-app.integration.test.tsx --reporter dot`: exit 0, 1 file
    passed, 48 tests passed; existing jsdom ResizeManager warnings remain.
    `pnpm --dir BridgeWeb exec vitest run
    src/bridge/bridge-push-receiver.unit.test.ts
    src/app/bridge-app.integration.test.tsx -t
    "accepts JSON-string|rejects descriptor-registering|partial delta rejects"
    --reporter dot`: exit 0, 2 files passed, 3 tests passed, 50 skipped.
    `mise run test --filter BridgeBootstrapTests`: exit 0, 18 Swift Testing
    tests passed.
    `mise run test --filter WebKitSerializedTests.BridgeTransportPushBoundaryTests`:
    exit 0, 1 WebKit test passed, proving Swift push delivery calls
    bridge-world `__bridgeInternal.applyEnvelopeJSON`.
    `git diff --check`: exit 0.
    Docs-only `git diff --check` for the six spec/plan files touched by the
    docs worker: exit 0.
    `mise run lint`: exit 0 with swift-format OK, SwiftLint 0 violations in
    1313 files, AgentStudio architecture lint OK, and release script
    verification passed.
  - Decision: Ticket 02 is materially closer to checkpoint-ready, and the
    hook-reported lint failure is fixed. Still do not checkpoint, commit, or
    advance to Ticket 03 until renewed implementation review accepts the
    host-admission boundary and the remaining suite-level WebKit caveat from
    `BridgeTransportIntegrationTests` is either resolved, split with an approved
    proof substitute, or explicitly carried as a blocker.

2026-06-23 renewed host-admission review result

- Review reducer artifact:
  `tmp/review-swarms/2026-06-23-ticket-02-host-admission/reducer-report.md`.
- Accepted blocker:
  `host-bridge-port` is still page-forgeable. `bridge-push-receiver.ts`
  accepts a page-visible `window.message` port transfer as `host-bridge-port`,
  and `bridge-app.tsx` treats that admission source as enough to accept
  descriptor-registering Review protocol frames. Existing integration test
  helpers can synthesize this exact path from page code with `MessageChannel`.
- Accepted blocker:
  the required real WebKit gate is red. Parent rerun:
  `mise run test-fast -- --filter
  'AgentStudioTests.WebKitSerializedTests/BridgeTransportIntegrationTests'`
  exited 1 after a warm build. First five tests passed, then
  `test_pushPackageMetadata_rendersReviewViewerShell()` failed because the page
  remained on `bridge-review-empty-shell` and did not render
  `review-viewer-shell` or `sidebarPosition == "right"`.
- Low-confidence contracts/tests reviewer output was not counted as proof
  because host file-descriptor pressure prevented direct file inspection in that
  lane.
- Fresh parent verification:
  local source inspection confirmed the MessagePort authority gap at
  `BridgeWeb/src/bridge/bridge-push-receiver.ts:76`,
  `BridgeWeb/src/app/bridge-app.tsx:1685`,
  `Sources/AgentStudio/Features/Bridge/Transport/BridgeBootstrap.swift:49`,
  and `BridgeWeb/src/app/bridge-app.integration.test.tsx:2993`.
- Decision:
  Ticket 02 is `not_ready`. Do not commit, checkpoint, hand off as ready, or
  advance to Ticket 03. The next implementation pass must replace the
  page-visible MessagePort admission with a native/bridge-world authority
  boundary or another primitive that page-world code cannot dispatch, replay, or
  parameterize, then add a permanent forged `MessagePort` regression and make
  the real WebKit gate pass.

2026-06-23 dev-server pressure surface restored, not Ticket 02 authority proof

- Symptom:
  the Vite dev server was alive on `127.0.0.1:5173`, but the worktree fixture
  stayed on `bridge-review-empty-shell`; the worktree verifier timed out waiting
  for `button[data-testid="bridge-review-search-toggle"]`.
- Cause:
  the current Ticket 02 hardening rejects descriptor-registering Review protocol
  frames admitted through the old page-event `__bridge_push` carrier. The
  worktree and normal mock dev fixtures still used that old carrier, so package
  frames were dropped before the Review shell could materialize.
- Local restoration:
  the dev/mock fixtures now use a synthetic dev-only host-port carrier so local
  worktree and normal mock URLs remain usable for pressure testing. This is not
  real host authority and must not be used as checkpoint proof for Ticket 02.
- Proof:
  `pnpm --dir BridgeWeb run test:dev-server:worktree` exited 0 and selected
  `.github/workflows/ci.yml` with `selectedContentState: "ready"`.
- Proof:
  a direct Playwright DOM check for
  `http://127.0.0.1:5173/?fixture=worktree&workers=on&scenario=current-worktree`
  and
  `http://127.0.0.1:5173/?fixture=large-diffshub&workers=on&scenario=scroll`
  found `review-viewer-shell`, `bridge-review-search-toggle`, ready selected
  content, and zero page errors.
- Remaining scroll issue:
  `pnpm --dir BridgeWeb run test:dev-server` reached the loaded mock surface but
  failed the bounded CodeView scroll canary with two large frame deltas. That is
  the Ticket 03/04 stable-extent design delta already captured in the spec/plan:
  Ticket 03 must provide tree/file size facts before body hydration, and Ticket
  04 must consume them and prove anchor-stable scroll extent.
 - Decision:
  dev server loading is restored for pressure testing. Ticket 02 remains
  `not_ready`; this dev/mock carrier does not resolve the accepted real
  host-admission blocker.

2026-06-23 fresh dev-server load check after user reported non-load

- Symptom report:
  user reported that the dev server did not load.
- Current live server state:
  `lsof -nP -iTCP:5173 -sTCP:LISTEN` found the Vite node process listening on
  `127.0.0.1:5173`, started at 09:16:23 local time.
- Fresh worktree proof:
  `BRIDGE_VIEWER_WORKTREE_DEV_SERVER_URL='http://127.0.0.1:5173/?fixture=worktree&workers=on&scenario=current-worktree'
  pnpm --dir BridgeWeb run test:dev-server:worktree` exited 0. The selected
  file was `.github/workflows/ci.yml`, `selectedContentState` was `ready`,
  selected line count was 557, and worker pool state was `ready`.
- Fresh browser-style proof:
  a Playwright fresh Chromium page for the same exact worktree URL rendered
  `review-viewer-shell`, selected `.github/workflows/ci.yml`, reached
  `selectedContentState: "ready"`, and produced no page errors. The only failed
  requests were `net::ERR_ABORTED` speculative content fetches from viewport
  demand changing, which are expected during demand cancellation.
- Normal mock verifier:
  `pnpm --dir BridgeWeb run test:dev-server` exited 1 at the bounded CodeView
  scroll canary with two large frame deltas. This is a load-complete scroll
  extent failure, not an app boot failure.
- Lint proof:
  `mise run lint` exited 0 from current state: swift-format OK, SwiftLint 0
  violations, architecture lint OK, release script verification passed.
- Decision:
  current evidence does not reproduce a fresh-load failure on the worktree URL.
  The reproducible dev-server failure remains the Ticket 03/04 stable virtual
  extent problem. If an already-open user tab is blank or stale, treat it as a
  tab/HMR cache/runtime-state issue unless a fresh reload reproduces it.

2026-06-23 authority-boundary reconvergence

- User decision:
  Agent Studio BridgeWeb is bundled code inside the closed Swift app, not an
  open web service or arbitrary third-party page. Page-world Review frame
  provenance is internal app transport and should not block Ticket 02.
- Revised boundary:
  native descriptor leases and `BridgeSchemeHandler` validation are the byte
  authority. A forged, stale, foreign, revoked, or over-limit page-world Review
  frame may not make unauthorized `agentstudio://resource/...` fetches succeed.
- Deferred hardening:
  HMAC or encryption can be added later for tamper/replay hardening if the
  secret and verifier remain outside page-world. It is not a Ticket 02 gate.
- Docs updated:
  `spec.md`, `review-protocol.md`, `implementation-plan.md`, and
  `slices/02-review-protocol-vertical.md` now use the native lease authority
  checkpoint instead of host-only page-message provenance.
- Decision:
  do not continue chasing unforgeable page-world `MessagePort` provenance for
  Ticket 02. Move forward by proving the native lease/scheme-handler boundary,
  then checkpoint/review Ticket 02 and proceed toward Ticket 03.

2026-06-23 Ticket 02 implementation-review reducer follow-up

- Security/trust-boundary lane:
  no findings under the corrected closed-app boundary. Native descriptor lease
  and `BridgeSchemeHandler` validation remain the byte authority; page-world
  Review frame provenance is not a Ticket 02 security gate.
- Accepted proof gap:
  the combined Swift filter did not run all requested suites. Parent reran
  `BridgeReviewProtocolFrameBuilderTests|BridgeBootstrapTests`: exit 0, 29
  Swift Testing tests passed. Parent reran
  `AgentStudioTests.WebKitSerializedTests/BridgeTransportPushBoundaryTests`:
  exit 0, 1 Swift Testing test passed.
- Accepted integration blocker and fix:
  `BridgeTransportIntegrationTests/test_pushPackageMetadata_rendersReviewViewerShell`
  failed because `BridgeWeb/src/app/bridge-app.tsx` still rejected Review
  protocol frames unless admitted as `host-bridge-port`. Removed that stale
  strong-provenance gate. Focused rerun exited 0, 1 test passed.
- Remaining WebKit suite caveat:
  full
  `AgentStudioTests.WebKitSerializedTests/BridgeTransportIntegrationTests`
  still exits with unexpected signal 5 after the first six tests pass and while
  starting `test_pushJSON_concurrentBurstDeliversOrderedPageEvents`.
  Split proof covers the rest: burst, smoke-provider render, traceparent scheme
  handler, and real descriptor content fetch each pass individually.
- Accepted TS contract update:
  the old app integration test expected forged page-world Review frames to be
  rejected at UI projection admission. It now asserts the corrected boundary:
  page-world Review frames may render projection facts, while unauthorized
  content depends on native fetch rejection and must not materialize body text.
- Accepted scheduler/executor contract update:
  Review selected content may enqueue per-role foreground intents with zero
  scheduler byte estimate. The scheduler orders demand and applies queue
  pressure; the resource executor owns body-byte budgets, active byte caps,
  aborts, stale completion drops, and `byte_budget_exceeded`.
- Accepted Zustand proof gap:
  added a store snapshot unit test proving that after projection plus ready
  hydration status, the Zustand state contains refs/status/facts only and no
  fetched body text, capability URLs, promises, controllers, or worker handles.
- Proof:
  `pnpm --dir BridgeWeb exec vitest run
  src/review-viewer/state/review-viewer-store.unit.test.ts
  src/app/bridge-app.integration.test.tsx
  src/review-viewer/content/review-content-demand-loader.unit.test.ts
  --reporter dot`: exit 0, 3 files passed, 64 tests passed.
- Proof:
  `bash scripts/bridge-web-sync-fixtures.sh --check`: exit 0, 17 fixture files
  in sync.
- Proof:
  after Vite was restarted on `127.0.0.1:5173`,
  `BRIDGE_VIEWER_WORKTREE_DEV_SERVER_URL='http://127.0.0.1:5173/?fixture=worktree&workers=on&scenario=current-worktree'
  pnpm --dir BridgeWeb run test:dev-server:worktree`: exit 0. The selected
  file was `.github/workflows/ci.yml`, `selectedContentState` was `ready`,
  selected line count was 557, and `workerPoolState` was `ready`.
- Proof:
  `pnpm --dir BridgeWeb run check`: exit 0.
- Proof:
  `mise run lint`: exit 0; swift-format OK, SwiftLint 0 violations,
  AgentStudio architecture lint OK, and release script verification passed.
- Proof:
  `git diff --check`: exit 0.
- Decision:
  Ticket 02 is no longer blocked on host-only page-message authority. The
  accepted review findings from this pass are addressed. A checkpoint commit or
  handoff may proceed if the final packet carries the full WebKit-suite signal
  caveat and the Ticket 03/04 scroll canary ownership note.

Checkpoint 3: Worktree/File native provider boundary

- Prove source identity, watcher/status classification, descriptors,
  invalidations, content handles, reset decisions.
- Current native progress:
  source identity, snapshot descriptor leases, tree/status body serving,
  selected-file descriptor/content materialization, active source retention, and
  live status/file-invalidation/reset frame dispatch with replacement
  descriptor materialization are proven by focused Swift gates. Remaining
  native gaps are automatic watcher/status wiring into those dispatch methods
  and the mandatory Ticket 03 implementation review.
- Commit only after native/provider proof passes.
- Review before browser surface work if provider authority changed.

Checkpoint 4: Worktree/File browser surface

- Prove feature models/materializer/demand policy and stale manual refresh UX.
- Current browser progress:
  Worktree/File Zod schemas, materializer, demand policy, state primitives, and
  a non-React surface runtime are implemented and proven. The runtime wires
  materialized descriptors through the generic scheduler, resource executor, and
  body registry; selected-file demand fetches descriptor-backed content without
  putting bodies in state; invalidation marks open files stale without
  auto-fetching; explicit refresh fetches only the latest descriptor; forged
  unmaterialized descriptors fail closed before fetch; source reset prevents
  stale refresh commits; and binary/unavailable descriptors stop at
  metadata-only UI without fetching body bytes.
- Current browser proof:
  `pnpm --dir BridgeWeb exec vitest run
  src/features/worktree-file/models/worktree-file-protocol-models.unit.test.ts
  src/features/worktree-file/materialization/worktree-file-materializer.unit.test.ts
  src/features/worktree-file/demand/worktree-file-demand-policy.unit.test.ts
  src/features/worktree-file/state/worktree-file-state.unit.test.ts
  src/worktree-file-surface/worktree-file-surface-runtime.integration.test.ts
  src/worktree-file-surface/worktree-file-app.integration.test.tsx
  src/app/bridge-app-protocol-router.unit.test.tsx
  scripts/dev-server/bridge-worktree-dev-provider.integration.test.ts
  --reporter verbose`: exit 0, 8 files passed, 36 tests passed.
- Current browser-mode proof:
  `pnpm --dir BridgeWeb run test:browser:integration --
  src/worktree-file-surface/worktree-file-app.browser.test.tsx --reporter
  verbose`: exit 0, 2 browser files passed, 32 tests passed. This includes
  Worktree/File binary unavailable metadata-only behavior and the existing
  Review browser suite.
- Current live scroll-extent proof:
  `BRIDGE_VIEWER_WORKTREE_DEV_SERVER_URL='http://127.0.0.1:5173/?fixture=worktree&workers=on&scenario=current-worktree'
  pnpm --dir BridgeWeb run test:dev-server:worktree`: exit 0 with 419
  descriptors, 420 frames, selected `.github/workflows/ci.yml` ready,
  `treeTotalSizePixels=10056`, and `scrollExtentCanary` reporting
  `treeHeightDeltaPixels=0` and `contentHeightDeltaPixels=0`. The red run
  before the provider/render-line fix failed with
  `contentHeightDeltaPixels=1900`, then `800`, proving the scrollbar jump was
  caused by Worktree/File provider line-count facts using non-empty diff lines
  instead of renderer row lines plus renderer line-box mismatch.
- Current benchmark/artifact proof:
  The same dev-server verifier now writes a JSON proof artifact with
  stable-anchor, exact-size-tolerance, visible-range, before/after scrollTop,
  before/after scrollHeight, before/after virtualizer total size, measured ids,
  and reconciliation reason fields. Latest artifact:
  `tmp/bridge-viewer-worktree-dev-server/2026-06-24T00-50-10-943Z/worktree-dev-server-proof.json`.
- Current renderer-boundary proof:
  Worktree/File React and browser tests assert rendered DOM never contains
  `agentstudio://resource` capability URLs after descriptor-backed content
  opens. Runtime/fetch code may handle resource URLs; renderer markup receives
  paths and body text only.
- Current telemetry canary proof:
  `pnpm --dir BridgeWeb exec vitest run
  scripts/dev-server/bridge-dev-telemetry.unit.test.ts
  src/worktree-file-surface/worktree-file-app.integration.test.tsx --reporter
  verbose`: exit 0, 2 files passed, 7 tests passed. The telemetry sink accepts
  scrubbed Worktree/File extent metrics and rejects raw paths/capability URLs
  before OTLP export.
- Current quality proof:
  `pnpm --dir BridgeWeb run check`: exit 0.
- Current hygiene proof:
  `rg -n "\\bas\\s+(const|[A-Z][A-Za-z0-9_]*|Readonly|Record|unknown|any|\\{)|\\bany\\b|@ts-|eslint-disable|JSON\\.parse" BridgeWeb/src/features/worktree-file BridgeWeb/src/worktree-file-surface`:
  exit 1 with no matches.
- Current app routing progress:
  `BridgeAppProtocolRouter` now Zod-validates the app protocol, defaults to
  Review, fails invalid protocol metadata back to Review, and routes
  `worktree-file` to the first `WorktreeFileApp` mount point. Packaged
  bootstrap now renders the protocol router instead of the Review-only root.
- Current app routing proof:
  `pnpm --dir BridgeWeb exec vitest run
  src/app/bridge-app-protocol-router.unit.test.tsx
  src/features/worktree-file/models/worktree-file-protocol-models.unit.test.ts
  src/features/worktree-file/materialization/worktree-file-materializer.unit.test.ts
  src/features/worktree-file/demand/worktree-file-demand-policy.unit.test.ts
  src/features/worktree-file/state/worktree-file-state.unit.test.ts
  src/worktree-file-surface/worktree-file-surface-runtime.integration.test.ts
  --reporter verbose`: exit 0, 6 files passed, 23 tests passed.
- Current app routing quality proof:
  `pnpm --dir BridgeWeb run check`: exit 0.
- Current dev-provider progress:
  The Vite worktree dev provider now builds Worktree/File protocol data beside
  the transition Review package path: `worktree.snapshot` plus
  `worktree.fileDescriptor` frames with provider source identity, tree size
  facts, file exact-line-count extent facts, and descriptor-backed content.
  File bodies stay out of metadata frames and are served by
  `loadWorktreeFileContent` using descriptor id, subscription generation, and
  source cursor.
- Current dev-provider proof:
  `pnpm --dir BridgeWeb exec vitest run
  scripts/dev-server/bridge-worktree-dev-provider.integration.test.ts
  --reporter verbose`: exit 0, 1 file passed, 10 tests passed.
- Current dev-provider quality proof:
  `pnpm --dir BridgeWeb run check`: exit 0.
- Current dev-server cutover status:
  Vite middleware and browser dev bootstrap consume Worktree/File frames for the
  worktree URL, and the exact current-worktree URL has been proven with
  descriptor-backed content.
- Remaining Ticket 04 gaps:
  implementation re-review before PR readiness.
- Commit only after proof gates pass.
- Review before cleanup.

Current Ticket 04 review-fix follow-through proof:

- Re-review reducer report:
  `tmp/plan-workflows/2026-06-22-bridge-transport-streaming-implementation-plan/implementation-review-ticket-04-review-fix/report.md`.
- Red proof:
  `pnpm --dir BridgeWeb exec vitest run
  src/worktree-file-surface/worktree-file-app.integration.test.tsx
  scripts/dev-server/bridge-worktree-dev-provider.integration.test.ts
  --reporter verbose`: exit 1 before the follow-through fix, with expected
  failures for symlink escape, invalidation-only tree loss, and in-flight
  invalidation stale completion.
- Focused red-to-green gate:
  `pnpm --dir BridgeWeb exec vitest run
  src/worktree-file-surface/worktree-file-app.integration.test.tsx
  scripts/dev-server/bridge-worktree-dev-provider.integration.test.ts
  --reporter verbose`: exit 0, 2 files passed, 16 tests passed.
- Focused Worktree/File gate:
  `pnpm --dir BridgeWeb exec vitest run
  src/worktree-file-surface/worktree-file-app.integration.test.tsx
  src/worktree-file-surface/worktree-file-surface-runtime.integration.test.ts
  scripts/dev-server/bridge-worktree-dev-provider.integration.test.ts
  scripts/dev-server/bridge-dev-telemetry.unit.test.ts --reporter verbose`:
  exit 0, 4 files passed, 26 tests passed.
- Browser integration gate:
  `pnpm --dir BridgeWeb run test:browser:integration --
  src/worktree-file-surface/worktree-file-app.browser.test.tsx --reporter
  verbose`: exit 0, 2 files passed, 33 tests passed. This now includes
  browser-mode stale-with-body, no auto-fetch, explicit Refresh, latest content
  commit, and preserved tree row after invalidation.
- Live current-worktree dev-server gate:
  `BRIDGE_VIEWER_WORKTREE_DEV_SERVER_URL='http://127.0.0.1:5173/?fixture=worktree&workers=on&scenario=current-worktree'
  pnpm --dir BridgeWeb run test:dev-server:worktree`: exit 0.
  Latest artifact:
  `tmp/bridge-viewer-worktree-dev-server/2026-06-24T01-45-24-843Z/worktree-dev-server-proof.json`.
  Key canary values: `descriptorCount=421`, `targetPath=Sources/AgentStudioIPCClientCore/AgentStudioIPCClientCore.swift`,
  `treeScrollTopBeforeSelection=2396`, `treeScrollTopAfterReady=2396`,
  `treeHeightDeltaPixels=0`, `contentHeightDeltaPixels=0`,
  `contentDeclaredTotalSizePixelsAfterReady=9300`, `selectedLineCount=465`,
  `stableAnchorPass=true`, `exactSizeTolerancePass=true`.
- Artifact leakage check:
  `rg -n "/Users/|agentstudio://resource"
  tmp/bridge-viewer-worktree-dev-server/2026-06-24T01-45-24-843Z/worktree-dev-server-proof.json || true`:
  exit 0 with no matches.
- Quality gate:
  `pnpm --dir BridgeWeb run check`: exit 0.
- Repo lint gate:
  `mise run lint`: exit 0.

Checkpoint 5: hard cutover cleanup

- Remove superseded Review-package scaffolding and old authority paths.
- Re-run final proof gates.
- Commit cleanup only after regression/canary gates pass.

Current Ticket 05 cleanup proof:

- Red proof:
  `pnpm --dir BridgeWeb exec vitest run
  scripts/check-bridgeweb-architecture.unit.test.ts --reporter verbose`:
  exit 1 before the checker update, with the expected failure that Worktree dev
  Review-package scaffolding was not reported.
- Architecture guard:
  `scripts/check-bridgeweb-architecture.ts` now rejects generic core imports of
  app protocol/viewer modules, raw bodies/runtime handles in state modules, and
  Worktree dev Review-package scaffolding in the dev backend/provider/Vite route.
- Hard cutover:
  Worktree dev provider and Vite route now expose Worktree/File surface frames
  and descriptor-backed file content only. The Worktree dev path no longer
  exports or consumes Review package push/package/content routes.
- Focused proof:
  `pnpm --dir BridgeWeb exec vitest run
  scripts/check-bridgeweb-architecture.unit.test.ts
  scripts/dev-server/bridge-worktree-dev-provider.integration.test.ts
  scripts/bridge-worktree-vite-route.unit.test.ts --reporter verbose`:
  exit 0, 3 files passed, 29 tests passed.
- Quality gate:
  `pnpm --dir BridgeWeb run check`: exit 0.
- Repo lint gate:
  `git diff --check && mise run lint`: exit 0. SwiftLint found 0
  violations, AgentStudio architecture lint passed, and release script
  verification passed.
- Live current-worktree dev-server gate:
  `pnpm --dir BridgeWeb run test:dev-server:worktree`: exit 0.
  Latest artifact:
  `tmp/bridge-viewer-worktree-dev-server/2026-06-24T02-27-09-000Z/worktree-dev-server-proof.json`.
  Key canary values: `descriptorCount=423`,
  `targetPath=Sources/AgentStudioProgrammaticControl/IPCContracts.swift`,
  `selectedContentState=ready`, `selectedLineCount=381`,
  `treePathCount=423`, `treeTotalSizePixels=10152`,
  `treeHeightDeltaPixels=0`, `contentHeightDeltaPixels=0`,
  `stableAnchorPass=true`, `exactSizeTolerancePass=true`,
  `packageForbiddenTextAbsent=true`.
- Live port check:
  `lsof -nP -iTCP:5173 -sTCP:LISTEN || true`: exit 0, node PID 35384
  listening on `127.0.0.1:5173`.
- Live route shape check:
  `/__bridge-worktree/surface?scenario=current-worktree` returns Worktree/File
  frames, while `/__bridge-worktree/package?scenario=current-worktree` no longer
  returns a Review JSON package.

Checkpoint 6: implementation review and PR-ready wrapup

- Run implementation review swarm.
- Address or explicitly reject findings.
- Open/update PR and prove readiness.
- Do not merge unless separately authorized.

Current Ticket 05 review attempt:

- Report:
  `tmp/plan-workflows/2026-06-22-bridge-transport-streaming-implementation-plan/implementation-review-ticket-05-cleanup/report.md`.
- Result: `not_ready`.
- Cause: reviewer lanes did not return. Two broad read-only lanes timed out
  after 5 minutes, remained running after another 2 minute wait, and were
  closed. A focused fallback reviewer also timed out after 5 minutes and was
  closed. The security/reliability lane could not spawn because the reviewer
  role was unavailable.
- Parent verification did not find a scoped Worktree dev old-route regression:
  the old-symbol scan across `bridge-app-dev-worktree.ts`,
  `bridge-worktree-dev-provider.ts`, `vite.config.ts`, the Vite route helper
  test, and provider integration test exited 0 with no matches.
- Next route: re-run Ticket 05 implementation review in a fresh or
  lower-concurrency context before PR-ready wrapup.

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
