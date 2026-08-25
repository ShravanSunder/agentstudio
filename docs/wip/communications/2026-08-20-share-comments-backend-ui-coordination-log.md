# Share Comments Backend/UI Coordination Log

Append-only coordination record for the PR1 Share-comments backend and UX
lanes. Add new timestamped entries at the end. Do not rewrite or delete earlier
entries; correct an earlier statement with a later superseding entry.

## Entry format

```text
### YYYY-MM-DD HH:MM TZ — <agent/lane>

State: active | blocked | complete | superseded
Head: <commit SHA observed by this entry>
Owns: <paths or contract boundary>
Changed: <commits/files or none>
Proof: <commands, counts, exit codes or not run>
Needs from other lane: <exact dependency or none>
Next: <next action>
Notes: <risks, conflicts, or corrections>
```

## Log

### 2026-08-20 14:00 EDT — Share-comments UX lane

State: blocked on backend contract
Head: `f6fee0a893fb2996726b49688ffaa5a24c08d353`
Owns: BridgeWeb Share presentation, interaction state, message-level New/All
projection, later File/Review integration after strict backend types land
Changed: `2b56ebd97` presentation; `98a167c27` interaction state;
`1c6522767` pure Share projection; governing design checkpoint `6f873250b`
Proof: focused browser 2 files / 4 tests passed; projection unit 3 passed;
`pnpm --dir BridgeWeb run check` passed
Needs from other lane: durable message `handled`; strict projection facts for
handled/New/All; projection/session/source-fenced `output.scope.commit`;
`output.handled.clear`; exact success/failure/cancel/partial/unknown reduction
Next: consume the landed strict contract, integrate both viewer headers and
Pierre filtering, remove old Popover/checklist, prove S2-S4
Notes: do not restore manual selection; locked is independent of New/handled
and remains output-eligible. Full backend packet:
`tmp/review-handoffs/2026-08-20-agent-studio-review-comments-share-backend/implementation-handoff.md`

### 2026-08-20 14:00 EDT — Backend lane request

State: active request
Head: `f6fee0a893fb2996726b49688ffaa5a24c08d353`
Owns: Swift/SQLite WorktreeAnnotations domain, repository, service, output
coordinator, transport contracts; matching BridgeWeb comm-worker strict
schemas/routing/tests
Changed: none recorded for Share backend contract yet
Proof: current source scan confirms only
`output.selection.begin/chunk/commit/cancel`; no handled/scope/unhandle contract
Needs from other lane: none; UX primitives and pure filtering are committed
Next: implement the backend contract described in the handoff, commit at a
proof-bearing checkpoint, then append the commit SHA, exact wire shapes, tests,
and integration notes here
Notes: preserve three physical routes, immutable output formats/history,
latest-generation command/convergence separation, and unrelated PR2 files.

### 2026-08-20 15:01 EDT — Backend/comm-worker reliability lane

State: active
Head: `f6fee0a893fb2996726b49688ffaa5a24c08d353`
Owns: Swift Bridge transport/backend, WorktreeAnnotations persistence/service/
output contracts, matching BridgeWeb comm-worker contracts, and backend
reliability proof; no viewer UI ownership
Changed: no production changes since `f6fee0a89`; created a temporary read-only
F8 contract inventory helper under ignored `tmp/`
Proof: current worktree and HEAD verified; canonical v6 plan, full governing
Requirements/Specification/Program Design, validated implementation review,
and resumed-session log re-read; F8 inventory in progress
Needs from other lane: do not edit backend/comm-worker transport or persistence
owners; append any required contract correction here before depending on it
Next: read the Share backend handoff, reconcile it with the admitted F8/M8/
R-BLO-014 frontier, then implement the smallest proof-bearing backend slice
without UI or security expansion
Notes: preserve the three untracked PR2 research files; no polling, new
transport, Atom/SQLite refresh authority, compatibility shim, or security/auth
expansion

### 2026-08-20 15:08 EDT — Backend/comm-worker reliability lane

State: active
Head: `f6fee0a893fb2996726b49688ffaa5a24c08d353`
Owns: B0 durable handled storage and strict projection contract under
`tmp/plan-workflows/2026-08-20-worktree-annotation-share-comments-backend.md`
Changed: migration/domain/repository/projection/comm-worker contract work in
progress; three existing annotation test fixtures receive only required
`handled: false` literals to restore strict compilation
Proof: red migration test confirmed missing handled column; focused comm-worker
contract unit 1 file / 5 tests passed; first Swift rerun stopped at the expected
typed fixture compile gaps before Swift test execution
Needs from other lane: do not edit the three named fixture literals or strict
message-entry schema until this B0 checkpoint lands
Next: finish B0 repository restart/save-reset and Swift-to-TS projection proof,
then publish the backend checkpoint SHA and exact contract shape
Notes: no Share component, viewer header, Pierre adapter, or UI behavior was
changed

### 2026-08-20 15:30 EDT — Backend/comm-worker reliability lane

State: active; strict contract ready for UI consumption, hard-cut cleanup pending
Head: `f6fee0a893fb2996726b49688ffaa5a24c08d353` plus uncommitted backend work
Owns: durable handled reduction, fenced scope output, exact unhandle, strict
Swift/comm-worker contracts, and removal of obsolete backend candidate/selection
Changed: projection message now requires `handled: boolean`; new operation
`output.scope.commit` requires `scope: new|all`, `outputKind`, `sessionId`,
`displayedProjectionRevision`, `expectedSessionRevision`, `sourceGeneration`;
new operation `output.handled.clear` requires `attemptId`,
`expectedSessionRevision`; output history requires
`canMarkNotHandled: boolean`
Proof: migration 7/7; repository 11/11 plus focused success/unhandle red-green;
projection cursor 8/8; strict JSON 6/6; Swift transport contract 7/7; Swift
transport adapter 8/8; TypeScript strict call/projection contracts 15/15
Needs from other lane: consume only the shapes above; remove manual selection,
candidate query, checklist, and old `output.selection.*` calls under UI S2/S3;
do not edit Swift/backend/comm-worker core files while backend cleanup continues
Next: backend removes the old candidate query and completes partial/unknown,
history, format/lint, full focused suites, then publishes a checkpoint SHA
Notes: stale scope returns exact conflict with zero attempt/effect/history/lock/
handled change; known success locks editable members and marks exact current
revisions handled; unhandle never unlocks, changes history bytes, or repeats an
effect

### 2026-08-20 15:44 EDT — Backend/comm-worker reliability lane

State: active; backend/comm-worker hard cut compiled, UI consumption pending
Head: `f6fee0a893fb2996726b49688ffaa5a24c08d353` plus uncommitted backend work
Owns: Swift backend/SQLite/Bridge transport and BridgeWeb comm-worker only
Changed: removed the obsolete Swift candidate query/selection assembler and
comm-worker candidate command/event/query path; preserved the new strict
scope/unhandle contract; corrected the existing batch projector so locked saved
messages remain output-eligible as the design requires
Proof: comm-worker focused contract/runtime tests 4 files / 39 tests passed;
Swift transport contract 5/5; transport adapter 8/8; output repository 9/9;
SQLite repository 11/11; partial-finalization and recovered-unknown both lock
without handling or an output event; stale unhandle conflicts, repeated clear is
idempotent, exact attempt/event remains equal, and later known success re-handles
Needs from other lane: remove UI-owned `annotationOutputCandidatesPage`,
`annotationOutputCandidatesQuery`, `output.selection.*`, and candidate/checklist
consumers in app/file render controllers, browser test support, output controls,
selection helpers, and surface client; add required `canMarkNotHandled` fixture
facts. These are the only current `pnpm --dir BridgeWeb typecheck` failures
Next: backend runs scoped format/lint and complete focused Swift/comm-worker
proof; after UI consumption restores the integrated typecheck, run backend/Vite
real effect proof and publish the checkpoint SHA
Notes: no UI component/controller/surface-client fix was made here; no security,
polling, new transport, compatibility, queue, or authority expansion

### 2026-08-20 15:51 EDT — Backend/comm-worker reliability lane

State: backend contract checkpoint complete; integrated UI/B3 proof blocked on UI consumption
Head: `3eac7a5d1` (`feat(annotations): cut over share output scope`)
Owns: committed Swift backend/SQLite/Bridge transport, comm-worker hard cut,
and three required strict fixture literals; no UI behavior
Changed: durable `handled`; strict `output.scope.commit` and
`output.handled.clear`; history `canMarkNotHandled`; exact success/partial/
unknown reduction; removed backend/comm-worker candidate and selection transfer
paths; locked saved messages remain New/All output-eligible
Proof: post-format direct Swift filter 64 tests / 8 suites passed; comm-worker
4 files / 39 tests passed; product-contract typecheck passed; `mise run format`
passed; `mise run lint` passed with swift-format OK, SwiftLint 0 violations,
architecture lint OK, and release scripts passed; `git diff --check` passed
Needs from other lane: consume commit `3eac7a5d1` by completing the previously
listed UI hard cut; current full BridgeWeb typecheck and standard
`mise run test:swift` remain blocked before Swift execution only by those
UI-owned old-protocol references
Next: after UI reports typecheck green, backend runs the real development
backend + Vite New/All/copy/unhandle/restart/two-pane proof and integrated gates,
then resumes reliability v6 at F8/M8/R-BLO-014
Notes: commit is unsigned only because two 1Password signing attempts failed
with `failed to fill whole buffer`; hooks ran and passed on every attempt; PR2
research files remain untracked and untouched

### 2026-08-20 15:58 EDT — Backend/comm-worker reliability lane

State: real development fast-loop backend proof complete; Share interaction still pending UI cutover
Head: `5f8f2db98` with backend contract at `3eac7a5d1`
Owns: live seeded-worktree backend/Vite process and browser validation; no UI edits
Changed: none
Proof: direct real-Darwin post-start Git edit test 1/1 passed; sandboxed
backend correctly failed closed with typed `streamStartFailed`; identical
approved unsandboxed backend started on isolated `/tmp` data and
`127.0.0.1:43872`; health returned 204; bootstrap returned 200 binary / 404
bytes; Vite started on `127.0.0.1:5174`, proxied backend health 204, and a real
browser loaded current Review content from this worktree with no application
console errors; both owned processes then stopped and both ports refused new
connections
Needs from other lane: finish the strict Share UI hard cut before New/All/copy/
unhandle can receive integrated browser/manual proof
Next: rerun full BridgeWeb/typecheck and Share journey immediately after UI
reports consumption; backend continues non-colliding v6 contract inventory
Notes: current real worktree proof displayed the three preserved PR2 research
files but did not modify them; no temporary repo file or direct invalidation was
used

### 2026-08-20 18:23 EDT — Share-comments UX lane

State: active; strict UI cutover behavior green, full unit gate blocked on one backend fixture
Head: `415c3a2702` plus uncommitted UI-lane work
Owns: BridgeWeb Share presentation, File/Review header and inline projection,
output-result presentation, in-flow history, and UI browser fixtures; no
comm-worker strict-schema fixture ownership
Changed: completed the UI hard cut to `output.scope.commit` and
`output.handled.clear`; removed candidate/checklist selection; moved history
out of both rail Popovers into Share layout; fixed success-toast unhandle to
read the latest session revision; partial success now closes with a warning
toast; added File/Review strict-scope browser coverage
Proof: `pnpm --dir BridgeWeb run typecheck` passed; focused Share browser set
5 files / 26 tests passed; new integrated Share surface 1 file / 4 tests
passed; `pnpm --dir BridgeWeb run check` passed. Full unit gate reached 278
files / 1,878 tests: 277 files and 1,870 tests passed; 8 tests in
`bridge-comm-worker-annotation-projection-query-controller.unit.test.ts`
failed because the strict fixture message at lines 481-493 omits required
`handled: boolean`, producing the exact Zod path
`message.message.handled`.
Needs from other lane: add the required `handled` fixture fact in the owned
projection-query-controller unit fixture and rerun the full unit gate; do not
change UI semantics or restore the old candidate/selection protocol
Next: UX lane continues browser/full BridgeWeb proof that does not require
editing the backend fixture, then commits only UI-owned paths after integrated
green proof
Notes: this is an out-of-scope backend fixture gap exposed by the strict schema,
not authority for the UI lane to edit comm-worker tests; unrelated PR2 files
remain untouched

### 2026-08-20 18:31 EDT — Share-comments UX lane

State: UI checkpoint complete; integrated runtime/readiness proof remains blocked
Head: `b65c61c207` (`feat(annotations): share new or all comments`)
Owns: committed BridgeWeb Share mode, both viewer integrations, strict output
presentation, in-flow Other/history sections, and focused UI proof
Changed: checkpoint `b65c61c207` hard-cuts the UI from candidate/checklist and
thread/rail output Popovers to header-owned in-flow New/All sharing; preserves
exact-byte history inspection/repeat; known success closes and offers exact
unhandle; failure/cancel retains; partial closes with warning and no unhandle
Proof: focused unit 4 files / 16 tests passed; focused browser 7 files / 35
tests passed; `pnpm --dir BridgeWeb run check` passed; packaged
`pnpm --dir BridgeWeb run build` passed; integrated screenshot written to
`tmp/bridgeweb-worktree-annotation-share-integrated.png`. Full browser reached
49 passing files / 261 passing tests with only 2 pre-existing Pierre width
assertions failing: source commit `1058646834` changed standalone frames from
600px to `max-w-3xl` (observed 768px), while the older tests still require
`<= 600`; no layout or proof-gate edit was made by this lane.
Needs from other lane: (1) add `handled` to the owned comm-worker projection
query fixture reported at 18:23 and rerun full unit; (2) route the pre-existing
600px-vs-768px Pierre contract mismatch to its UI owner; (3) run the promised
real backend/Vite New/All/copy/export/unhandle/restart/two-pane journey against
`b65c61c207`
Next: after those two external proof blockers are corrected or owner-resolved,
rerun full BridgeWeb integration, real development fast-loop visual/effect
proof, packaged WKWebView proof, and final `mise run test`
Notes: 1Password signing failed once with `failed to fill whole buffer`; the
second signed commit attempt succeeded. PR2 research files remain untracked and
untouched

### 2026-08-20 18:39 EDT — Share-comments UX runtime lane

State: blocked on backend/comm-worker known-success response convergence
Head: `395340a13` with UI checkpoint `b65c61c207`
Owns: real Swift development backend + Vite + browser observation only; no
backend/comm-worker edits
Changed: none; isolated runtime state lives under
`/tmp/agentstudio-bridge-share-proof.OafVz7`
Proof: built the real development server, started it on `127.0.0.1:43873`,
started Vite on `127.0.0.1:5174`, created and saved one real Review annotation,
opened header-owned Share, observed `New (1)` / `All (1)`, switched to All, and
clicked Copy Markdown. Native durable evidence says known success: two repeated
attempts are `state=succeeded`; each has `event_kind=copied`; both exact capture
files exist; the message is `status=locked, handled=1`. React convergence also
observed `New (0)` / `All (1)` and `Output locked`.
Needs from other lane: diagnose why the same
`review.annotations.command` rejects at the comm-worker/UI boundary with
`Bridge comm worker failed to forward review.annotations.command.` after the
native effect and durable known-success transaction completed. Inspect the raw
method result and `bridgeProductWorktreeAnnotationCommandResultSchema.parse`
path, plus product-call correlation/replay after the post-effect response.
Prove one click yields one delivered `succeeded` outcome, Share closes, success
toast offers unhandle, and ordinary retry cannot duplicate an already-known
effect.
Next: backend/comm-worker owner corrects and proves the response convergence;
UX lane then reruns Copy, toast unhandle, restart, and two-pane journeys
Notes: this is a mental-model break, not an ordinary UI failure: the current UI
correctly retained Share on its observed transport failure, while durable truth
had already committed known success. A second All click repeated the real
development clipboard capture, demonstrating the duplicate-effect risk.

### 2026-08-20 20:35 EDT — Share output response correction

State: backend-to-UI success response fixed and live-proven
Head: `563f8a827` plus scoped uncommitted correction
Owns: strict Swift product JSON response vocabulary, real development HTTP
output-response regression, strict terminal-response matrix, and one stale
comm-worker fixture fact
Changed: added the existing output response members `destinationFilename`,
`messageCount`, `selectionError`, `effectError`, `cleanupError`,
`finalizationError`, and `repeatedFromAttemptId` to
`BridgeProductStrictJSON`; added a real `output.scope.commit` HTTP regression;
added strict coverage for every output terminal; added missing `handled: false`
to the projection-query fixture
Proof: the real HTTP test failed red with `request.error(code: internal)` after
durable success, then passed green after the vocabulary fix; strict terminal
matrix 1/1 passed; projection-query controller 13/13 passed; full BridgeWeb
unit 278 files / 1,878 tests passed; BridgeWeb check passed; `mise run format`
passed; `mise run lint` passed with SwiftLint 0 violations, architecture lint
OK, and release scripts passed. Live isolated backend/Vite/Review proof observed
`New (1)` → one Copy → Share closed → `Copied 1 comment` → toast `Mark as not
handled`; SQLite showed exactly one succeeded attempt and one copied event. The
toast action restored `New (1)` while the message remained locked.
Needs from other lane: none for the response fix
Next: commit the scoped correction, then run the remaining integrated/full
readiness gates; the separately recorded Pierre 600px-vs-768px proof mismatch
remains outside this backend correction
Notes: root cause was ordinary handler response validation, not latency or a
new system boundary: Swift encoded a valid output result, then its strict member
vocabulary rejected the result before returning it to the frontend.

### 2026-08-20 20:40 EDT — Share output response correction

State: correction committed and exact-HEAD proof complete
Head: `03b49b832c` (`fix(annotations): return output success responses`)
Owns: completed backend-to-frontend response correction and proof receipt
Changed: commit `03b49b832c`; no further production changes
Proof: exact-HEAD real HTTP output regression passed 1/1; full BridgeWeb unit
278 files / 1,878 tests passed; BridgeWeb check passed; `mise run lint` passed;
live Review journey passed one Copy → one succeeded attempt/event → Share closed
→ success toast/unhandle → New restored without unlock. Complete `mise run test`
reached browser integration with 260/263 passing; two failures are the previously
recorded 600px-vs-768px Pierre width mismatch. The third full-suite saved-range
failure passed immediately in isolated rerun, 2/2, and is classified as a
suite-order flake rather than a response-fix regression.
Needs from other lane: Pierre width contract owner resolves the existing
600px-vs-768px mismatch before branch-wide PR readiness
Next: resume remaining Share S4/package readiness after that independent UI
proof blocker is resolved
Notes: the response correction itself is complete and committed; unrelated PR2
research files remain untracked and untouched

### 2026-08-21 02:00 EDT — Decoded durable-history convergence

State: decoded History fix committed, pushed, and scoped proof complete; full
aggregate gate remains red outside the changed path
Head: `8daaae22e` (`fix(annotations): preserve decoded output history`)
Owns: raw-wire versus decoded annotation command-result boundary, downstream
comm-worker/runtime-event contracts, real File/Review History E2E, and the two
governing Program Design clarifications
Changed: the production transport remains the only raw Swift response parser
and timestamp transformer. Product controller, annotation runtime-event, and
worker-event owners now validate the decoded result instead of reapplying the
raw schema. Non-history outcome variants share one schema definition; only the
History timestamp representation differs. The real annotation Save journeys
now cross Copy, Share dismissal, durable History, and History unhandle.
Proof: focused decoded contract/controller/worker 3 files / 21 tests; BridgeWeb
check exit 0; unit 280 files / 1,886 tests; Node integration 3 files / 19 tests;
browser integration 50 files / 263 tests with 5 established skips; real
Vite-to-Swift E2E 2 files / 8 tests. Fresh isolated Review UI proof observed
`New (1)` -> Copy -> Share closed/toast -> `New (0)` / `All (1)` ->
`History (1)` -> Mark as not handled -> `New (1)`. SQLite retained
`status=locked`, `handled=0`, the succeeded attempt, exact revision membership,
and copied event. Files on `.gitignore` showed the Review comment under in-flow
Other saved comments.
Needs from other lane: none for decoded History. Branch-wide readiness still
needs one complete `mise run test`: one aggregate attempt had a saved-range
focus assertion that passed 2/2 immediately alone; the next cleared every
BridgeWeb/package lane and then timed out the broad native-concurrent Swift lane
after the repository watchdog observed 300 seconds without output.
Next: fresh read-only implementation review of `6b841f396..8daaae22e`; do not
change unrelated native runner or PR2 policy under this lane
Notes: `origin/main` is contained exactly (branch 94 ahead / 0 behind). Remote
feature branch is updated to `8daaae22e`. Both manual dev servers were stopped.
Two 1Password signing attempts failed, so the checkpoint used the documented
unsigned fallback with hooks enabled. Unrelated PR2 files remain untracked and
untouched.

Review: fresh read-only complete implementation review
`pr1-decoded-history-implementation-review-2026-08-21` returned no findings for
`6b841f396..8daaae22e`. It independently classified runtime reachability as
live and confirmed raw decode-once ownership, downstream decoded contracts,
non-empty History proof, shared non-history variants, real Swift/Vite/SQLite
E2E, and bounded File pointer retry. Uncovered boundaries remain one complete
green `mise run test` and independent system-clipboard byte inspection; neither
is represented as a decoded-History defect or PR-ready proof.

### 2026-08-21 02:36 EDT — Local aggregate Swift watchdog correction

State: root cause fixed with focused red/green proof; complete gate pending
Head before correction: `840430b3f` (`test(annotations): isolate focus event proof`)
Owns: local top-level pull-request gate inactivity budget only
Changed: the top-level `mise run test` default for
`SWIFT_TEST_TIMEOUT_SECONDS` now matches the established CI fast-lane budget of
600 seconds instead of terminating the live native-concurrent Swift lane at
300 seconds after the preceding Bridge workload. The watchdog remains based on
output inactivity and remains overrideable.
Proof: complete browser integration passed 263 tests with 5 established skips;
the following aggregate Swift lane reproduced exit 124 at 300 seconds while
its live process tree resumed passing tests at the termination boundary. The
same lane passed alone in 162.33 seconds. Rebuilt-source red proof failed on the
exact 300-versus-600 contract mismatch; focused green passed 1/1; the complete
`CIFastLaneWorkflowTests` suite passed 21/21.
Needs from other lane: none
Next: commit this bounded test-harness checkpoint, rerun complete `mise run
test`, then record and push only if the current-HEAD gate exits 0
Notes: no Share product source or proof gate was weakened; unrelated PR2 files
remain untracked and untouched

### 2026-08-21 02:49 EDT — Mainline vendor instruction test convergence

State: stale mainline assertion corrected with isolated and complete-lane proof
Head before correction: `5de076106` (`test(ci): align local Swift inactivity budget`)
Owns: `VendorConsumerWiringScriptTests` active-instruction expectations only
Changed: removed the obsolete requirement that AGENTS duplicate README's
`normally unhydrated in linked worktrees` sentence. AGENTS still must name plain
setup and the explicit local-vendor escape hatch; README still owns the linked
worktree hydration detail; forbidden bootstrap commands remain rejected across
all active instructions.
Proof: the preceding complete gate advanced through the formerly timed-out fast
lane, then reproduced this single failure among 484 large tests. The same
document/test mismatch exists on `origin/main` after AGENTS was shortened in
`623433273`. Rebuilt focused proof passed 1/1. Complete large proof passed
484/484 parallel tests plus 4/4 serial process tests.
Needs from other lane: none
Next: commit this bounded mainline-contract correction and rerun the complete
current-HEAD `mise run test`
Notes: Share production code remains unchanged; unrelated PR2 files remain
untracked and untouched

### 2026-08-21 03:06 EDT — WebKit per-lane refresh proof convergence

State: deterministic stale assertions corrected; complete WebKit lane green
Head before correction: `a86941729` (`test(ci): follow shortened agent instructions`)
Owns: two existing WebKit refresh-pass count assertions only
Changed: both journeys now expect two independently admitted catch-up passes
for filesystem invalidations that dirty File and Review, matching production's
accepted per-lane authority cutover in `0c1c975f8` and the current Bridge
latest-generation Program Design.
Proof: the hosted two-pane failure reproduced in the aggregate gate and alone
with final count 4 versus foreground count 2 plus obsolete 1; rebuilt focused
proof passed after expecting File plus Review. The complete WebKit lane then
identified the same stale one-pass expectation in workspace fan-out; rebuilt
focused proof passed. Final complete serialized WebKit lane exited 0 in 113.02
seconds.
Needs from other lane: none
Next: commit the bounded proof correction, then run the complete current-HEAD
gate once more
Notes: no production code or proof gate changed; unrelated PR2 files remain
untracked and untouched

### 2026-08-21 03:15 EDT — Complete current-HEAD repository gate

State: complete local pull-request gate green
Head: `55659365f` (`test(bridge): follow per-lane refresh passes`)
Owns: final branch-wide proof receipt
Changed: no additional source changes
Proof: fresh unchanged `mise run test` exited 0 on exact HEAD. Swift format,
SwiftLint, architecture lint, release scripts, and architecture-tool tests
passed; SwiftLint reported 0 violations across 2,173 files. BridgeWeb passed
1,886 unit tests, 19 Node integration tests, 263 browser integration tests with
5 established skips, and 8 real Vite-to-Swift E2E tests; packaged build and
asset audit passed. Native fast, process-global, large, serialized WebKit, and
general E2E lanes passed; the Swift task completed in 345.52 seconds and its
general E2E lane passed 6 tests in 3 suites. Final `git diff --check` passed.
Needs from other lane: none
Next: commit this final proof receipt, push without force, then verify local HEAD
equals remote feature HEAD and the branch remains 0 behind `origin/main`
Notes: only the three unrelated PR2 research files remain untracked; they were
not staged or modified

### 2026-08-21 04:48 EDT — Independent-review remediation one

State: three accepted implementation findings corrected; fresh exact-HEAD gate
and replacement independent review still pending
Head before correction: `58e052bdd`
Owns: Repeat recovery authority, Other saved-comment rendering, and packaged
Share proof
Changed: repository Repeat accepts only unknown attempts; terminal History rows
do not offer Repeat; Other saved comments use the safe saved-message Markdown
renderer; the packaged 640px WKWebView journey crosses real Copy and Export
effects with exact clipboard/JSON byte inspection
Proof: red reproduction for succeeded Repeat, terminal Repeat presentation,
and raw Markdown; output repository 9/9; targeted browser 7/7; complete browser
264 passed with 5 established skips; packaged Share journey 1/1; complete
serialized WebKit lane exited 0 in 123.06 seconds
Needs from other lane: none
Next: commit the bounded remediation, run exact-HEAD `mise run test`, then obtain
one fresh complete implementation review before PR creation
Notes: the packaged debug process was stopped; the three unrelated PR2 research
files remain untracked and untouched

### 2026-08-21 05:38 EDT — Independent-review remediation two

State: four implementation findings corrected; one plan-owned telemetry gap
remains before final review
Head before correction: `29de85306`
Owns: finite annotation projection bound, subscription explicit retry, Share
unknown membership, and durable History time presentation
Changed: projection pages declare and enforce a maximum 128-page logical
snapshot; explicit retry reopens an active missing annotation subscription even
before bootstrap; Share renders `New (—)` / `All (—)` with Copy and Export
disabled before the first complete projection; History renders a semantic time
from the durable attempt timestamp
Proof: red comm-worker failures reproduced unbounded page acceptance and inert
pre-bootstrap retry; red browser proof reproduced missing History time, while
the unknown Share case was source-verified and then exercised in the corrected
browser lane. Green: BridgeWeb check exit 0, comm-worker 15/15, focused browser
8/8, Swift formatting/lint 0 violations, and finite projection cursor 9/9
Needs from other lane: none
Next: checkpoint the bounded correction, then return the missing R-BLO-014
annotation stage correlation and marker-scoped proof to `plan-implementation`
Notes: the current convergence plan omitted a frontier explicitly deferred by
the earlier backend reliability plan; this is a plan defect, not authority to
improvise telemetry inside remediation. PR2 research files remain untouched

### 2026-08-21 18:49 EDT — Review refresh classification design closed

State: three-artifact design ready after one parent-verified remediation; no
implementation started
Head: `0785f29cf` (`docs: define bridge review refresh classification`)
Owns: Bridge Review same-source refresh classification and installation design
Changed: one update pipeline retains ordinary silent installation and promoted
display holding; displayed Review identity is now separate from native/worker
current through a bounded prepare/confirm/abort handshake on the existing
command route; annotations remain pinned to the installed generation; active
plus one candidate bank is the complete presentation bound
Proof: one independent three-artifact review produced 2 blockers, 6 important,
and 4 minor/observation findings; Specification and Program Design received the
single permitted remediation; parent re-read 1,098 artifact lines, verified all
finding anchors, foundation links, whitespace, and staged diff scope; no second
review was run
Needs from other lane: consume the final Specification and Program Design when
planning UI realization; no UI source file was changed here
Next: create the repository-grounded implementation plan before code changes
Notes: unrelated PR2 research files remain untracked and untouched; no security,
route, persistence, polling, queue, or global-interaction expansion was added

### 2026-08-21 20:33 EDT — Refresh install design simplified after closure

State: Specification and Program Design revised by owner decision; prior
independent review does not cover the simplified admission mechanism
Head before revision: `acbd50c9f`
Owns: strong newest-native-complete install guarantee with minimal coordination
Changed: prepare/confirm/abort transition machinery is replaced by
lineage-monotonic `nativeCurrent` and `acknowledgedDisplayed` registers, one
exact install-admission CAS keyed by publication identity, and the existing
`review.publication.applied` receipt moved to post-main installation; affected
context is file-level; editor continuity uses an opaque minimal lease; candidate
representation is no longer prescribed
Proof: parent source validation confirmed existing full-lineage comparison,
serialized product-control admission, current worker-side publication-applied
call, and native retiring-publication leases; artifact whitespace/diff checks
pass
Needs from other lane: do not plan or implement from the earlier handshake text;
consume the revised Specification and Program Design after review coverage is
resolved
Next: obtain explicit permission for a second independent design review, or an
explicit owner decision to proceed on parent self-check alone
Notes: one pipeline, active-plus-one presentation bound, existing physical
routes, and unrelated PR2 ownership remain unchanged

### 2026-08-21 23:11 EDT — Refresh classification S1 checkpoint

State: native lineage authority and strict install-admission contracts committed
Head: `0e15267a9` (`feat(bridge): add review display install admission`)
Owns: backend coordinator, existing product-control contract, app/dev-host
composition, and focused proof only
Changed: exact displayed/candidate CAS admission; lineage-monotonic displayed
receipt over retained publications; bounded displayed/admitted/current/source-
lease retention; strict Swift/TypeScript call corpus; policy values 10 commits,
25 files, and 1,000 changed lines
Proof: retention-bound red reproduced 3 retiring publications and green retained
only displayed A plus admitted B beside current D; focused Swift 52/52 across 6
suites; BridgeWeb check, scoped format/lint/architecture lint, shared-corpus byte
parity, and diff checks passed
Needs from other lane: UI remains untouched; consume typed refresh state only
after the S2/S3 backend state exists, and do not add a parallel refresh path
Next: implement S2 worker applied-receipt cutover and the main active-plus-one
candidate bank on the existing worker/product routes
Notes: no security/auth, persistence, polling, queue, route, PR2, or visual UI
change; the checkpoint used unsigned fallback after two 1Password signing failures

### 2026-08-21 23:42 EDT — Refresh S2 foundation proven; S3 capability break

State: S2 typed foundation is green but intentionally uncommitted and not claimed complete
Head: `06244c1ce`; S2 changes remain in the working tree
Owns: comm-worker receipt cutover, existing-route lifecycle contracts, and the
main active-plus-one normalized Review candidate bank
Changed: worker metadata no longer owns displayed receipt; exact candidate-ready,
install-admit, admission-result, and installed contracts exist; candidate state
is private, lineage-fenced, successor-replacing, atomically promotable, and
discarded on replacement/close
Proof: complete BridgeWeb check exited 0; focused S2 regression set passed 81/81;
runtime protocol is 996 lines, worker contracts 986, main store 775; diff check passed
Needs from other lane: UI remains untouched; do not consume the typed state until
the native impact carrier and installation gate are connected
Next: owner decision is required to add a capped arbitrary-revision commit-count
API to `agentstudio-git` and bump the Agent Studio pin
Notes: the pinned package can compute A-to-C files, rename sides, and line counts,
but has no arbitrary A-to-C commit count; upstream ahead count is not equivalent.
Direct Git CLI, a second scheduler, or always-unknown promotion were rejected.

### 2026-08-22 07:58 EDT — Refresh S3 native impact checkpoint

State: bounded displayed-to-candidate impact classification committed; S2/S4 integration remains active
Head: `d4cc5754b` (`feat(bridge): classify review refresh impact`)
Owns: Agent Studio native Git scheduling, impact policy, retained displayed-publication lookup, and final Review metadata-barrier carriage
Changed: Agent Studio now pins fetchable `agentstudio-git` revision `24ad9238`; same-source refresh measures acknowledged displayed A to candidate C through the existing scheduler, promotes at 10 commits / 25 files / 1,000 changed lines, treats unavailable or unrelated facts as promoted unknown, maps both rename/delete sides to stable Review item identities, and carries the typed result only on the atomic final metadata barrier
Proof: `agentstudio-git` build/lint/focused contracts and 4 real-Git range tests passed; Agent Studio dependency build/pin test passed; focused S3 Swift proof passed 54 tests across 7 suites; scoped SwiftFormat/SwiftLint/diff checks passed
Needs from UI lane: no visual files were changed; consume the typed main-store refresh presentation and actions only after the S2 installation gate is checkpointed. The controller seam will expose semantic-attention identities and Apply-now without prescribing toolbar implementation.
Next: finish exact Review render/Pierre lineage fencing, main installation routing, installed-generation annotations, then hand the stable typed presentation seam to the UI owner
Notes: no security/auth, persistence schema, polling, new route, second scheduler, compatibility path, or PR2 change. The three PR2 research files remain untouched.

### 2026-08-22 09:12 EDT — Refresh backend/UI seam ready

State: S2-S4 backend, comm-worker, main installation, and installed-annotation seam committed; live and packaged proof remain active
Head: `c7e163712` (`fix: bound review refresh impact work`)
Owns: exact Review publication lineage, active-plus-one candidate bank, ordinary/promoted installation gate, post-install applied receipt, installed-generation annotation authority, bounded Git impact facts, and browser fixture parity
Changed: `useBridgeReviewRenderSnapshotController` exposes `reviewRefreshPresentation`, `applyReviewRefreshNow()`, and `setReviewRefreshSemanticAttention(stableFileIdentities)`; exact-active projection patches update active while newer identities stage candidates; Review annotation discovery waits for an installed identity and reruns when that identity changes
Proof: BridgeWeb check passed; unit 1,929/1,929; Node/native integration 19/19; focused Review browser suites 39/39; Swift impact/policy/pin 12/12; installed annotation/coordinator 43/43; Swift format, SwiftLint 0/2,184, architecture lint, and release checks passed
Needs from UI lane: consume the existing typed presentation only—ordinary has no global bar; promoted relevant computation shows `Updating…`; held ready shows `Update ready` plus `Apply now`; relevant failure shows `Update unavailable` plus eligible Retry. Publish semantic attention from the existing Review item/reading/editor owners. Do not add another store, toolbar, refresh route, polling loop, or annotation gate.
Next: UI owner confirms/lands its visual composition; backend lane proves the final combined UI through the real seeded Swift dev backend plus Vite and packaged WKWebView
Notes: complete browser integration has all Review paths green but an unrelated File menu/deep-scroll React `act` warning intermittently fails only under aggregate concurrency and passes in isolation. Protected PR2 files remain untouched.

### 2026-08-22 09:33 EDT — Refresh seam correction and live-proof red

State: S2-S4 focused proof remains green, but the real Swift backend plus Vite
route is red and the prior seam entry overstated controller readiness
Head: `c7e163712`; one backend proof-constant correction is currently uncommitted
Owns: backend/comm-worker investigation only; UI files remain UI-owner controlled
Changed: no visual UI change; the stale TypeScript startup-transcript SHA now
matches the authoritative Swift fixture and its focused contract test passes 28/28
Proof: `pnpm --dir BridgeWeb run test:dev-server:worktree` now reaches the real
browser journey but times out waiting for `review-viewer-shell`; bootstrap,
metadata, and content routes succeed, while no
`review.publication.install.admit` call is emitted. The manual Vite route shows
the same wait and runaway repeated `review_content_ready` work.
Needs from UI lane: do not build against `reviewRefreshPresentation` yet. Current
source exposes `applyReviewRefreshNow()` and
`setReviewRefreshSemanticAttention(...)`, but does not yet return
`reviewRefreshPresentation` from `useBridgeReviewRenderSnapshotController`.
Continue visual work only against already-existing shared primitives; avoid
creating a replacement store or toolbar while backend fixes the typed seam.
Next: backend proves the missing final-barrier/candidate-stage/admission
transition, adds the durable red test, fixes that root cause, then publishes the
actual typed presentation value for UI consumption.
Notes: no security/auth, polling, route, scheduler, persistence, or PR2 change.

### 2026-08-22 10:13 EDT — Refresh seam correction proven; typed seam restored

State: initial Review candidate installation works through the real Swift backend
plus Vite; final whole-journey proof remains red at an older Pierre paint gate
Head: `c7e163712`; backend corrections and proof updates remain uncommitted
Owns: backend/comm-worker/controller seam only; no visual UI files changed
Changed: install admission and installed receipt now use the controller's existing
monotonic command epoch instead of publication render epoch; exact-active display
patches advance their render-routing epoch monotonically; the controller now
actually returns `reviewRefreshPresentation` through `useSyncExternalStore`
Proof: command-epoch red expected `101` but received stale `2`; full BridgeWeb unit
lane is green 1,933/1,933 after correction; focused Swift impact/pin proof is green
9/9 across 3 suites, including the >4,096-item symbolic-unknown case; the real
route sends install admission and publication-applied and renders a 19-item Review
Needs from UI lane: the typed seam is now valid to consume:
`reviewRefreshPresentation`, `applyReviewRefreshNow()`, and
`setReviewRefreshSemanticAttention(stableFileIdentities)`. Keep visual ownership
in the UI lane and do not create a second store, route, scheduler, or toolbar.
Next: backend finishes lifecycle telemetry and refresh-specific dev-server
journeys, then validates the combined UI and packaged WKWebView surface
Notes: the repository's broad real-worktree verifier now reaches a deterministic
pre-existing CodeView/Pierre hydration timeout also present before the candidate
bank. Its proof gate is not weakened. No security/auth, polling, persistence,
compatibility, or PR2 change.

### 2026-08-22 10:43 EDT — Refresh lifecycle evidence checkpoint

State: backend lifecycle evidence is implemented and checkpointed; UI composition
and final broad runtime/package proof remain open
Head: `5b0a3a80f` (`fix: complete review refresh runtime proof seams`)
Owns: native classification/source cleanup, main candidate lifecycle, existing
telemetry projection, and worker-replacement cleanup wiring
Changed: the existing Bridge telemetry plane now records scrubbed classification,
ready, held, install intent/terminal, supersession, receipt failure, and cleanup
facts; only class/reason, generation, duration, and aggregate counts cross it.
Worker replacement now notifies the installation gate through one local store
lifecycle subscription. Late admission replies use one dispatch-scoped slot
instead of an accumulating orphan map.
Proof: BridgeWeb check exited 0; unit 1,936/1,936; focused Swift lifecycle/schema/
impact proof 17/17; scoped Swift format, SwiftLint, architecture lint, TypeScript
format/typecheck, and diff checks passed
Needs from UI lane: consume the already-published typed presentation/actions and
publish semantic attention from existing Review owners. Do not add telemetry,
another lifecycle store, route, scheduler, or polling path in the UI lane.
Next: combine UI-owner work, add the refresh-specific real-worktree evidence
sequence, then packaged WKWebView and exact-HEAD aggregate proof
Notes: dev-server OTLP allowlisting for these controlled fields is landing in the
next small proof checkpoint. The broad CodeView/Pierre hydration blocker remains
separate and unchanged.

### 2026-08-22 11:31 EDT — Git performance and late-hunk Review proof checkpoint

State: practical `agentstudio-git` optimization and bounded Review diff-window
repair are committed; full document-replacement lifecycle needs one design
decision before backend implementation continues
Head: `694d4d901`; preceding pin checkpoint `14bacc069`; published
`agentstudio-git` revision `83370ae74f63dda2b7e451089776cde0c603d57c`
Owns: backend/comm-worker/Git package and proof only; no visual UI files changed
Changed: bounded commit traversal uses allocation-free fixed-width OID keys;
Agent Studio pins that revision; Review diff windows now anchor at the first
changed line, retain bounded context, and preserve original hunk coordinates
instead of comparing identical first-400-line prefixes
Proof: `agentstudio-git` commit traversal improves approximately 10–18% CPU at
the 256-visit bound with unchanged ~9.2 MB RSS; library build/lint and commit
range 9/9 plus diff impact 7/7 pass; Agent Studio dependency pin 1/1 passes;
BridgeWeb planner/verifier 60/60 and complete check pass; real worktree hydration
now reaches 35 settled windows instead of timing out
Needs from UI lane: continue consuming only the existing typed refresh seam;
do not work around File→Review reload by adding UI state, a second store, or a
parallel install path
Next: owner concurrence on document replacement semantics. A new main document
has no active bank while native still acknowledges displayed A, so its
`expectedDisplayed = nil` admission is correctly rejected by the current CAS.
The reviewed design covers worker replacement with a retained bank, not loss of
the entire main document bank.
Notes: the remaining raw-DOM order violation is separately classified as proof
drift because Pierre retains sticky/pool hosts outside `getRenderedItems()`;
correct it against Pierre's logical rendered-item range without weakening the
authoritative catalog-order gate. Protected PR2 files remain untouched.

### 2026-08-22 13:48 EDT — Admitted-successor re-exposure backend checkpoint

State: the bounded comm-worker/main successor path is implemented and focused
proof is green; real development-server and packaged proof remain next
Head: `52d5c2ab7`; the L2 backend checkpoint is not yet committed
Owns: comm-worker metadata/product-control completion and the main Review
candidate/install gate only; no visual UI files changed
Changed: an admitted candidate is pinned in the existing one candidate bank;
after native acknowledges installed B, the worker re-exposes only newer active C
as a full reset plus candidate-ready. Admission rejection re-exposes newer D;
admission transport failure retries current C/D once after main receives its
failure terminal. Applied receipts remain request-epoch fenced while rejection
and failure recovery publish current worker state under the current epoch.
Proof: focused BridgeWeb state/runtime/render set passes 65/65; complete
BridgeWeb check passes architecture, format, typecheck, and product contracts;
the composed proof rejects C render/Pierre work while B installs, then accepts
the bounded render retry after C re-exposure and reaches ready availability
Needs from UI lane: no new backend seam. Continue consuming the existing typed
`reviewRefreshPresentation`, `applyReviewRefreshNow()`, and semantic-attention
surface; do not add a second store, route, replay owner, or retry loop
Next: checkpoint L2, extend the real Swift development-host reload/successor
journey, then run Swift backend plus Vite and packaged WKWebView proof
Notes: no security/auth, polling, second bank, raw-message buffer, compatibility,
or PR2 change. The three protected PR2 files remain untouched.

### 2026-08-22 14:00 EDT — Real Swift backend plus Vite reload proof green

State: the existing real-worktree browser journey reaches document generation 2
and passes; stronger operand-level lifecycle assertions and retained-main host
proof remain in progress
Head: `8c289f062`; the verifier traversal correction is currently uncommitted
Owns: backend proof harness only; no visual UI or product behavior changed
Changed: the Review traversal now advances past a selected-only initial viewport
when that selected diff is already painted, windowed/hydrated, taller than the
viewport, and more scroll range exists. It still requires the next non-selected
window to pass the original hydration and paint-correlation checks.
Proof: red unit reproduced the 944 px viewport / 1,188 px selected-host deadlock;
green unit passes 15/15. Real `pnpm --dir BridgeWeb run
test:dev-server:worktree` exits 0 with 238 product routes, document generation 2,
zero legacy routes, zero violations, and clean browser/backend teardown. Both
documents emit install-admission followed by publication-applied calls.
Needs from UI lane: none for this correction. The Vite dependency pre-scan still
warns about unresolved UI-owned alias imports, but on-demand compilation completes
the full journey; backend did not edit those UI files.
Next: add scrubbed operand/result assertions for both browser documents and the
focused real development-host retained-main/B→C lifecycle test, then checkpoint.
Notes: the broad gate was not weakened and no UI, security/auth, route, scheduler,
polling, persistence, compatibility, or PR2 change was made.

### 2026-08-22 14:13 EDT — Real host W1/W2/W3 and B→C lifecycle green

State: the deterministic real development-host lifecycle is green and one
worker-qualified admission leak found by that proof is fixed
Head: `37377ea5e`; this native lifecycle checkpoint is currently uncommitted
Owns: native Review publication coordinator and development-host proof only; no
visual UI or BridgeWeb product code changed
Changed: when an already-acknowledged publication is applied by a fresh worker,
the duplicate path now establishes that worker and clears only its exact matching
`(workerInstanceId, publicationId)` admission before returning. Previously that
lease remained and blocked the next install.
Proof: coordinator display-installation suite passes 7/7. The real development
host route test passes 1/1 and proves W1 null-admit/apply A; fresh W2 authority
rotation and null-admit/apply A; retained-main W3 duplicate-apply A; null B
rejection and exact-A B admission; C commit while B is admitted; B apply; exact-B
C admission/apply; and final coordinator admitted state empty. Scoped Swift
format, SwiftLint, architecture lint, and diff checks pass.
Needs from UI lane: none. This changes no UI seam or presentation behavior.
Next: checkpoint the native lifecycle correction, then add scrubbed operand/result
assertions to the already-green real browser document-1/document-2 transcript.
Notes: no new route, hook, persistence, security/auth, polling, compatibility, or
PR2 change. The three protected PR2 files remain untouched.

### 2026-08-22 14:32 EDT — Packaged backend proof green; Share suite blocker isolated

State: both required packaged backend journeys are green in isolation at exact
HEAD; the broader six-test packaged suite is blocked by the UI-owned Share
journey and its subsequent hidden-document contamination
Head: `98fb22d21`
Owns: packaged backend proof and test composition only; no visual UI or product
behavior changed
Changed: the transactional packaged-WebKit harness now forwards the existing
`review.publication.install.admit` call to the same native coordinator admission
owner used by app and development-host composition. The harness previously used
the provider's explicit default rejection, so its first application could never
complete after install admission became mandatory.
Proof: red suite-qualified test ran 1 and failed with
`initialPublicationDidNotApply`; green rerun ran 1 and passed in 1.104s. At
checkpoint `98fb22d21`, the real-git bundled worker test runs 1/1 in 1.409s and
the transactional replay test is green. Scoped format/lint/architecture checks
pass.
Needs from UI lane: investigate `packaged File and Review Share performs exact
App effects and durable unhandle`, which fails at stage `review-new` with New,
All, and History counts all zero. In the full serialized suite, the next bundled
Review test then observes `document.visibilityState == hidden` and content stuck
in `loading`; that same backend test passes alone at exact HEAD.
Next: UI owner fixes or hands back the Share failure/cleanup contamination; then
rerun the full packaged suite and exact-HEAD aggregate gate.
Notes: backend did not edit UI, Share behavior, security/auth, routes, scheduler,
polling, persistence, compatibility, or PR2 files.

### 2026-08-22 14:58 EDT — Installed Review annotation projection restored

State: the comm-worker/backend Review annotation projection blocker is fixed;
the complete BridgeWeb gate is green
Head: `26f89e06a`
Owns: installed Review identity adaptation and backend proof harnesses only; no
visual UI product files changed
Changed: the comm worker now projects the parsed
`reviewPublicationInstalled` command to its exact five-field annotation identity
before strict product transport. Previously the compile-time `Pick` retained the
seven command-envelope keys at runtime, causing strict projection-query
validation to fail locally before HTTP. Test harnesses now also model one
identity-stable multi-window candidate with one final ready barrier, and the
static hydration-order assertion identifies the intended post-initial traversal.
Proof: installed-source red test observed 12 keys and now passes with exactly
five; focused Review annotation Swift-backend + Vite + Chrome E2E passes through
projection query/content and reload; focused browser burst passes 1/1; static
router contract passes 28/28. Complete `mise run test:bridge-web` passes 1,950
unit, 19 Node integration, 265 browser integration, and 8 real Vite E2E tests.
Needs from UI lane: the earlier packaged Share journey failure at `review-new`
still needs the UI owner's correction; the backend annotation projection path is
no longer blocking it.
Next: rerun the full packaged WKWebView suite after the UI lane lands, then the
exact-HEAD aggregate gate and independent implementation review.
Notes: no new route, retry, polling, state bank, compatibility, security/auth,
persistence, or PR2 change.

### 2026-08-22 15:10 EDT — Backend and packaged Review proof settled; UI unhandle remains

State: backend/comm-worker, real Vite, and packaged Review lifecycle proof are
settled; one UI-owned packaged Share unhandle assertion remains
Head: `124d77806`
Owns: packaged WebKit proof isolation only; no UI product source changed
Changed: the shared packaged carrier retains at most one empty host window next
to its already-retained prior page, and retires that empty window only after the
next proof window is front. This removes the zero-window gap that caused later
WebKit documents to start hidden with RAF stopped; product session/controller
resources are still torn down before retention.
Proof: scoped Swift format, SwiftLint, and architecture lint pass. In the full
six-test suite, bundled real-git File/Review passes in 1.526s, transactional
failure/replay passes, clean empty Review passes, two-pane lifecycle passes, and
named-surface lifecycle passes. Share now receives projection (All=1,
History=1, New=0), confirming the backend fix, but intermittently remains
handled at stage `review-unhandle`.
Needs from UI lane: fix or explain the packaged Share `review-unhandle` state;
the failure is in the first suite test before any prior retained window exists.
Do not change backend identity, projection, admission, or window handoff to work
around it.
Next: after the UI correction lands, rerun this six-test suite, then exact-HEAD
`mise run test` and independent implementation review.
Notes: backend has no remaining known functional failure. Protected PR2 files
remain untouched.

### 2026-08-22 15:13 EDT — Share unhandle race source diagnosis

State: the sole remaining packaged failure is a source-proven UI coordination
race; native handled-state CAS is correct and must not be weakened
Head: `0654ce11d` plus packaged isolation checkpoint `124d77806`
Observed: clipboard output succeeds and marks the saved message handled; output
history can become visible before the independent annotation projection carries
the output's new session semantic revision. History's “Mark as not handled”
reads the projection revision at click time. If clicked in that window it sends
stale `expectedSessionRevision`; native rejects the conflict, leaving All=1,
History=1, New=0. The packaged test reaches this window intermittently.
Evidence: Review annotation invalidation/query/content and installed identity are
green; the output history result carries attempt/session identity but no session
revision; `clearOutputHandled` correctly requires exact session revision.
Needs from UI lane: preserve CAS and choose the smallest UI-owned settlement:
gate the history action until the output-triggered projection converges, or on
the one explicit revision-conflict wait for the newer projection and reissue the
same exact attempt action once. Do not add a wire field, backend retry loop, or
loosen native admission for this race.
Next: land the UI-owned correction, then rerun the six-test packaged suite and
exact-HEAD aggregate gate.

### 2026-08-22 20:29 EDT — Share conflict recovery committed; packaged host visibility under investigation

State: the Share unhandle coordination race is fixed and independently bounded;
the remaining failed gate is serialized packaged WebKit host visibility, not
annotation/native admission or product UI behavior
Head: `613de26a8`
Changed: both existing unhandle controls now send the current exact session
revision, retry only one typed `conflict` after the same session projection
advances, and terminate without retry if that session disappears. Native CAS
remains authoritative; no protocol, backend retry, polling, compatibility, or
new bank was added.
Proof: focused browser Share suite passes 8/8; complete BridgeWeb quality check
passes; focused packaged Share/unhandle passes. A fresh bounded reviewer reports
no blocker or important finding.
Open gate: the six-test packaged suite can leave the later bundled document at
`visibilityState=hidden` with RAF scheduled but not fired while native streams
remain healthy. The failing bundled and two-pane cases pass alone. Three
test-host visibility hypotheses were tried, failed, and removed; fresh
read-only root-cause investigation is active.
Needs from UI lane: none. Do not change UI product behavior for this harness
failure.
Next: prove and correct only the packaged WebKit lifecycle owner, rerun the six
packaged cases, then exact-HEAD aggregate and independent implementation review.
Notes: protected PR2 files remain untouched.

### 2026-08-22 20:52 EDT — Packaged aggregate blocker localized to SwiftPM GUI host

State: no remaining known product/backend failure; local aggregate packaged
proof is blocked by the SwiftPM test helper's GUI activation capability
Head: `613de26a8` plus one diagnostic-only assertion change
Evidence: on the repeated bundled failure, native transport and metadata are
healthy, mount and hosting views are attached at 960 x 720, but the host reports
`appActive=false`, `windowKey=false`, `occlusionVisible=false`; WebKit therefore
reports `document.visibilityState=hidden` and suspends RAF. Focused packaged
Share passes, focused two-pane passes, and clean+bundled can pass in an active
host run. Attempts to adopt accessory policy, finish launching, activate, front,
and key a test-only window were rejected by this SwiftPM helper environment and
were fully removed.
Changed: only the existing bundled failure message now includes the already
captured host snapshot so future failures identify this boundary directly.
Needs from UI lane: none.
Exact unblock: rerun the packaged/aggregate gate from a macOS GUI test context
that can make the SwiftPM helper window occlusion-visible, or provide the repo's
canonical GUI-capable runner if one exists. Do not change product rendering,
timeouts, native admission, or UI behavior to compensate.
Notes: no security, protocol, polling, compatibility, second-bank, or PR2 change.

### 2026-08-23 08:55 EDT — Real-worktree Chrome inventory finds refresh presentation unwired

State: backend and comm-worker refresh state exist at `af7ffaf955`, but the
promoted-refresh user workflow is not reachable from the production Review UI
at this HEAD
Evidence: `useBridgeAppReviewRenderSnapshotController` exposes
`reviewRefreshPresentation`, `applyReviewRefreshNow`, and
`setReviewRefreshSemanticAttention`; a production-source search finds no
consumer outside that controller/store and no production literal for
`Updating…`, `Update ready`, `Apply now`, or `Update unavailable`. Only unit
tests inject semantic attention or call Apply now.
Needs from UI lane: wire the existing controller outputs into the agreed stable
Review chrome and existing Review attention/first-visible-item owners. Preserve
one pipeline, the controller/store ownership, and the no-blocking interaction
contract. Do not add another refresh engine, route, bank, polling loop, or
global interaction manager.
Backend proof context: an isolated Swift backend and Vite are healthy against
the disposable linked worktree under `/tmp`; ordinary refresh, annotations,
comparison, and exact output-capture workflows remain available for Chrome
proof. Copy/Export in the development host intentionally writes exact bytes to
the isolated data root rather than claiming clipboard/save-panel authority.
Next: UI owner lands the bounded consumer; backend lane reruns the promoted hold,
Apply now, focus-leave auto-install, comment-continuity, and newest-candidate
real-worktree journeys without changing UI source.

### 2026-08-23 09:12 EDT — Share treats unavailable retained projection as confirmed zero

State: real Chrome + Vite + Swift backend exposed one backend wire defect and
one separate UI-owned availability projection defect
Head: `af7ffaf955` plus an uncommitted scoped Swift encoder correction in the
backend lane
Primary cause: Swift omitted required-nullable `activeEditToken` when a durable
draft had released its edit token. The comm worker correctly rejected that
strict wire record. Backend lane has a deterministic red test and the bounded
custom encoder correction; UI source was not changed.
UI finding: after the demanded projection becomes unavailable, the projection
store retains its last complete header-only snapshot and sets `readStatus` to
unavailable. `WorktreeAnnotationShareHeaderControl` and
`WorktreeAnnotationShareSurface` use only `projection.revision === null` to
decide membership unknown/ready. They ignore unavailable/refreshing read status,
derive the retained empty thread array, and visibly report `New (0)` / `All (0)`
as current. This contradicts R-P1-010 and the confirmed no-fabricated-zero
contract.
Needs from UI lane: make Share membership truth incorporate the existing
projection read status and last-known/current distinction. Reuse the current
projection store and Share row; do not add state, retry, polling, a new route,
or another projection owner.
Next: after both scoped owners land, rerun full-document reload with a released
draft token and verify the draft returns, the lifecycle reaches ready, and Share
never reports a failed/unknown membership as current zero.

## 2026-08-23 09:51 EDT — Backend lane: permanent Chrome RED for root-draft release

The new exact Chrome → Vite → production comm-worker → Swift development-server journey now
reproduces a UI-owned edit-token release failure. After `root.create` commits and the draft is
visible, both clicking outside and pressing Escape collapse/flush the root composer but no
`draft.edit.release` command reaches `/__bridge-product/command`; the exact response wait times out
after 120 seconds. Three isolated runs reproduced it. The Swift strict-wire test and real HTTP
restart test remain green, so this is separate from the fixed required-nullable
`activeEditToken: null` encoder defect.

The likely seam is duplicate registration of the same new-message edit token in
`useBridgeCodeViewWorktreeAnnotations` and `WorktreeAnnotationNewMessageComposer`. Composer teardown
queues deferred release, but the registry can still report the parent registration active and skip
release. Please validate and correct that UI lifecycle without changing native contracts. The
permanent RED is `restores a released Review root draft after a full document reload` in
`BridgeWeb/tests/e2e/bridge-viewer-vite-annotation-save-journey.ts`.

## 2026-08-23 10:03 EDT — Backend lane: Review-head to File placement is GREEN

The native source evaluator now admits only this cross-view compatibility: on the File surface,
immutable `reviewHead` origins may be evaluated against current working-tree `.file` material.
`reviewBase` remains rejected, Review-surface matching remains exact-role only, and
repository/worktree lineage fencing is unchanged. Located and whole-file RED assertions failed as
`outdated` before the correction and now pass; the real `agentstudio-git` working-tree material
integration also passes.

UI lane still needs the thin File Pierre correction: an exact/relocated context with immutable
`sourceRole === 'review_head'` must be eligible on File when its current path/lines already came from
the native File projection. Do not rewrite the origin role and do not admit `review_base`. After that
lands, the backend lane will extend the real Chrome Review → Files journey and require the same
canonical messages to render visibly on the selected current file.

## 2026-08-23 10:16 EDT — Correction to 10:03 entry

Before checkpointing, the backend lane removed the dormant whole-file compatibility change. The
committed native correction at `9ef5053f9` covers only shipped located threads. Whole-file behavior
remains unchanged. The located `reviewHead` RED/green, `reviewBase` guard, real `agentstudio-git`
material integration, and projection-source suites are green (16 tests total).

## 2026-08-23 10:29 EDT — Backend lane: composed output and multi-message Chrome proof GREEN

The permanent real Chrome/Vite/comm-worker/Swift save journey now uses distinct File and Review
message bodies and runs both against one real fixture. The combined run passed 2/2 and proves both
messages coexist without command conflict. For each output it requires one newly created isolated
capture; Markdown is checked for the authored body, one generated H1, and no absolute worktree
path. JSON is checked for schema/version, contiguous batch ordinals, unique message IDs, and the
current authored body. The second surface truthfully exported both canonical messages. History
contained both attempts and New membership was restored before reload.

Current UI-owned REDs remain unchanged: root-draft collapse does not release its edit token;
File Pierre still needs exact/relocated `review_head` eligibility; promoted refresh presentation is
not production-wired. The backend lane has not changed UI source to compensate.

## 2026-08-23 10:33 EDT — Backend lane: real annotation restart journey GREEN

A permanent E2E now authors distinct File and Review messages through Chrome, stops the exact owned
Swift backend, starts a new backend over the same isolated Core/local SQLite root, opens a fresh
Chrome document, and verifies the File message in File plus the Review message in Review. The new
backend PID must differ and both process cleanups remain ownership-safe. Exact focused result: 1/1
passed, 7 skipped, 17.02 seconds. This closes the canonical annotation process-restart gap without
mocking persistence or treating a page reload as a backend restart.

## 2026-08-23 10:38 EDT — Backend lane: permanent Review-origin to File Chrome RED

The restart journey now continues from proven native/SQLite recovery into File View for the exact
Review-origin path. File content reaches ready for the requested path, but the recovered Review
message never becomes visible and the exact locator times out. This is the full composed RED for the
thin File Pierre predicate already requested above: native placement is green and immutable
`review_head` reaches the File projection; File rendering still drops it. No backend or protocol
change is needed. After the UI predicate lands, this same permanent journey must turn green.

## 2026-08-23 10:47 EDT — Backend lane: permanent promoted-hold Chrome RED

The permanent promoted journey now creates exactly ten sequential commits in the disposable real
worktree while the changed Review file remains selected. The package changes before any
`Update ready` presentation: observed outcome is `installedWithoutHold`, expected `updateReady`.
This proves the missing production semantic-attention wiring materially changes behavior, not just
chrome. The test then owns the future Apply-now and unaffected-file automatic-install assertions.
Exact RED fails in 7.52 seconds, so the UI owner has a bounded feedback loop and does not need the
earlier 120-second timeout.

## 2026-08-23 10:49 EDT — Backend lane: root-draft RED feedback bounded

The permanent released-draft journey still fails at the exact missing `draft.edit.release` response,
but that wait is now capped at 30 seconds while ordinary Save retains its existing ceiling. The
focused real Chrome run reproduced the same missing release in 46.29 seconds end-to-end. Typecheck,
format, and scoped type-aware lint pass; only the pre-existing ordered browser-loop warnings remain.

## 2026-08-23 11:15 EDT — Backend lane: released draft and cross-view composed proof GREEN

Checkpoint `43d776ac3` fixes the two previously bounded annotation UI seams. Root-composer teardown
now releases from its exact committed command cursor even before projection convergence, while a
newer trustworthy projection cursor may supersede it; File Pierre admits only exact/relocated
`review_head` alongside native File origins and continues rejecting `review_base`.

Parent verification passed the full Pierre Chrome file 7/7, the real Chrome/Vite/comm-worker/Swift
released-Review-draft reload journey 1/1, and the cold-restart Review-origin-to-File convergence
journey. The promoted-refresh path remains the active RED. Its program-design correction is under
independent review; no heuristic chrome or second refresh pipeline has been added.

## 2026-08-23 12:21 EDT — Backend lane: classified candidate lifecycle GREEN

Checkpoints `1c54c2a52` and `d2260b77a` record the reviewed source-corrected Program Design;
`1ec20cd99` records the truthful real-worktree E2E harness; `9c0f8f7f6` records S1/S2 production
carriage and the bounded main state machine.

The production sequence is now exact `reviewCandidateStarted → reviewDisplayPatch →
reviewCandidateReady`. Same-source classification is known before worker presentation construction;
main clones one candidate bank from displayed A, rejects geometry without an exact start, keeps
unknown affectedness symbolic, and fences ready/failure by both publication identity and worker
epoch. Exact current failure retains only bounded promoted facts; ordinary/replacement failure stays
non-global; stale B cannot affect newer C; worker replacement/attention leave/close clean state.

Parent proof passed Swift 27/27, focused TypeScript 80/80, typecheck, and installed-Chrome controller
consumers 17/17. The pinned `agentstudio-git` bounded-diff suite passed 7/7, including oversized
fuzzy/exact rename cases. UI lane may now consume `reviewRefreshPresentation`, semantic-attention,
and Apply-now contracts; do not reintroduce final-barrier classification or infer promoted state from
generic provisional geometry.

## 2026-08-23 13:44 EDT — Backend lane: composed promoted refresh GREEN

The permanent Chrome/Vite/production-comm-worker/Swift-dev-server/real-Git-worktree journey now
passes both promoted cycles. Ten imported commits hold the selected affected Review at `Update ready`;
Enter on Apply now installs the exact target OID. The harness requires the real
`review.publication.applied` completion before advancing again, ignores unrelated same-OID ordinary
catch-up generations, then proves a second ten-commit candidate remains held until selection moves to
an unaffected file and installs automatically. Held telemetry is bound to each installed generation
with promotion reason `commits`.

The missing telemetry was a stale-recorder bug: Review integration captured the startup no-op recorder
before async telemetry bootstrap replaced the ref. It now resolves the existing recorder ref at event
time; no new path, timer, observer, or state owner was added. Focused proof is Swift 38/38, TypeScript
unit/harness 16/16, installed Chrome 28/28, composed real E2E 1/1, and BridgeWeb typecheck green.

## 2026-08-23 14:16 EDT — Backend/UI coordination: held Review interaction GREEN

The composed comment-continuity cap exposed one presentation drift: same-source refresh progress used
the generic comparison `loadingPrevious` state, and Review shell made visible active A inert and
pointer-blocked as though the user had requested a target replacement. Native/display identity was
correct; the candidate remained staged.

Review mode now derives a presentation-only settled state while bounded same-source candidate/failure
authority exists. Raw comparison state remains unchanged for telemetry, target identity, Retry, and
package matching; initial load and explicit target replacement remain blocking. The hardened E2E fails
immediately if the active canvas is inert and bounds its endpoint-utility wait.

Real Chrome now drags a range during `Update ready`, opens the endpoint `+`, creates and saves a new
root against displayed A, observes exact root-create/draft-save receipts, preserves the saved body
after Apply now, and then proves the second promoted update auto-installs after moving to an unaffected
file. Final proof: installed Chrome 30/30, composed E2E 1/1, typecheck/format/type-aware lint green.

## 2026-08-24 17:35 EDT — Backend lane: sequential Reply live-interaction blocker

The committed comm-worker correction is green through existing-owner Review/File bounds, actual
`MessageChannel` ordering, and bounded publication telemetry (`1de2dff8c`, `8206d7d56`,
`c2cac7bdc`). The permanent 1,699-file Vite/production-worker/Swift/SQLite journey now reaches a
precise UI-owned RED after root plus reply 1 create/flush/save all commit: opening reply 2 times out.

At the failure there is one expanded thread, two exact saved bodies, and two visible/enabled Reply
buttons. The selected latest button receives exactly one pointerdown, mousedown, and click on the
same still-connected marked DOM node and receives focus, but no Reply composer appears. There are no
console warnings/errors, and the next exact annotation-projection response does not change the
result. The stable thread browser harness and the Pierre Review browser harness both pass the same
sequential-reply flow; the RED requires the live native/comm-worker projection cadence under the
large Review.

UI owner request: diagnose the live event-delegation/portal interaction at the Pierre Review boundary
without changing comm-worker admission. Preserve the S5 test and turn its `reply.2.composer.opening`
milestone green. Do not add click retries or force-click in the harness; those would hide a lost user
interaction. Backend evidence and cleanup are complete; every diagnostic run stopped its owned server
and disposed its isolated fixture.

## 2026-08-24 18:02 EDT — UI lane: separate inbound New from outbound Pending

The current PR1 `New = current saved revision && !handled` label conflicts with conventional blue-dot
attention semantics and cannot identify future agent replies. The owner has now separated the two
observable states:

- `Pending` is outbound workflow state. It applies only to the human-authored current saved revision
  while its handled boundary is unset. Successful output clears Pending; viewing never does. A later
  human edit creates a new current saved revision that is Pending again. UI uses the existing warning/
  amber semantic role for Pending.
- `New` is inbound attention state. It applies only to an agent-authored current saved revision that
  the reviewer has not deliberately viewed. It uses the existing primary blue dot plus text, both at
  thread summary and exact expanded-message presentation. Output never clears New.
- Deliberately expanding a multi-message thread clears the current New agent revisions in that thread.
  Clicking/focusing a one-message agent thread clears that message. Passive projection, scrolling,
  Share mode, Copy, and Export do not clear New. An agent edit whose current revision has not been seen
  becomes New again.
- Header language is `● N new · M pending · K messages · latest … · Open`. Zero-valued states are
  omitted. Expanded human Pending messages show amber `Pending`; expanded agent New messages show a
  blue dot plus `New`. Human messages are never New; agent messages are never Pending.
- Share scope changes from `New | All` to `Pending | All` and retains the existing handled-membership
  semantics. The UI must not reinterpret `handled` as read state.

Backend owner: please publish the per-current-revision inbound seen/new fact and one durable, revision-
fenced operation for the explicit thread/message view boundary. Return the exact committed result before
the UI removes New. Choose internal schema and operation naming in the backend lane, then record the
public projection field and operation contract here. Do not change React presentation files. The UI lane
will implement Pending now from `authorKind` plus `handled`, and will wire New only after this contract is
returned.

## 2026-08-24 18:34 EDT — Backend lane: combined-HEAD S5 remains pre-command RED

The exact permanent 1,699-item journey was rerun after UI/state checkpoint `b75728242`. Root and reply 1
again completed create/flush/save through the production comm worker and Swift/SQLite backend. Reply 2
again stopped before any command was issued: its current visible/enabled connected Reply button received
one pointerdown, mousedown, and click, but no composer opened. There were no console errors or warnings;
the owned fixture and server cleaned up successfully.

Current backend proof on the same shared state remains green: comm-worker owner/runtime unit tests 52/52,
actual `MessageChannel` integration 2/2, Swift root-plus-five-reply HTTP/SQLite restart 1/1, OTLP render-
disposition metrics 2/2, wire schema 7/7, forbidden overengineering-symbol scan clean, and `git diff
--check` clean. Please keep the UI/state fix at the pre-command interaction boundary; no transport retry,
new queue/port, click retry, force-click, or timeout increase is justified.

The inbound New/seen request is a separate product/data contract from the admitted backpressure goal and
must not be silently folded into this transport remediation. Pending can proceed from current handled
semantics; durable New/seen needs its own owner-confirmed requirement and design before backend schema or
operation work begins.

## 2026-08-24 18:42 EDT — Backend lane: S5 proves producer amplification, not queue backlog

The S5 failure path now captures the existing scrubbed telemetry status once before cleanup. Before any
reply-2 command was issued, Review had already produced 10,104 render-disposition receipts. The complete
initial 1,699-item render requires 5,097 receipts (`1,699 × queued/applied/painted`). Admission was not
backlogged: pending returned to 0, pending high-water was 18, and the captured oldest pending age was at
most 0.6 ms. This is roughly 2x producer amplification while the comm-worker queue drains promptly.

The narrow source candidate is the current Review annotation effect at
`use-bridge-code-view-worktree-annotation-effects.ts:23-46`, which maps every current Review item,
increments every item version, and applies every item update for each annotation projection. Root/reply
body revisions do not inherently change all Pierre placement descriptors. UI/state owner: please
classify and correct this producer-side republish boundary. Backend/comm-worker must not compensate with
higher limits, another queue/port, render batching, or receipt dropping. Required proof is the same S5
with semantic work no longer amplified, urgent outcomes still non-starved, pending zero, lease ages
bounded, and the full root-plus-five-reply durability journey green.

## 2026-08-24 19:00 EDT — Correction: annotation suppression rejected; S5 oracle needs design owner

The prior producer-amplification handoff was too strong. A bounded UI-owner correction suppressed
unchanged annotation-placement item updates and passed its focused Chrome RED/GREEN, but the full S5
still failed at the identical reply-2 pre-command boundary. Receipt production fell only from 10,104 to
9,483; the correction removed 621 receipts and did not restore interaction. It has been fully reverted,
and all three UI/test files match HEAD.

The remaining 4,386-receipt delta equals 1,462 additional queued/applied/painted attempts. Progressive
placeholder-to-hydrated Review delivery can legitimately create a second attempt, while current scrubbed
aggregate telemetry intentionally omits attempt/generation identity. Therefore the S5 exact lifetime
oracle (`1,699 × 3 = 5,097`) and the runtime disagree, but current evidence cannot call every additional
attempt a defect. Comm-worker admission still drains to pending zero with low age.

This reaches the comm-worker plan's explicit stop/replan condition: the corrected 1,699-item run remains
unbounded relative to an unproven oracle. Program Design must choose and justify exact lifetime attempts,
exact final-generation attempts, or a bounded progressive-attempt ceiling plus zero-pending/lease/failure
invariants. Do not add identity-bearing telemetry, render batching, another queue/port, higher ceilings,
receipt dropping, or another UI optimization before that decision. The separate reply-2 interaction RED
also remains with the UI/state owner.

## 2026-08-24 19:08 EDT — Correction: Specification already owns the S5 receipt proof

No design-cycle decision is needed for lifetime receipt count. R-CWA-010 explicitly says receipt-command
count alone is insufficient and requires bounded published-but-unsettled count/age, correlated outcomes,
and acknowledgement ordering. R-CWA-011 requires exact annotation outcomes, no lease expiry, interactive
inspectability, durable reload, bounded drain, and acknowledgement-before-newly-released-render ordering.
Neither requires exactly one lifetime attempt per item.

The S5 harness had invented the exact `5,097` lifetime oracle. It is corrected to retain the legitimate
initial-render minimum, enforce every specified pending/high-water/age/failure/order/durability gate, and
require produced count to remain unchanged after demand stops. This does not permit unbounded attempts and
does not change Requirements, Specification, or Program Design. The corrected final telemetry gate remains
unreachable until the separate reply-2 pre-command UI interaction RED is fixed.

## 2026-08-24 19:13 EDT — Backend lane: UI remediation exhausted; exact external blocker

A final bounded UI-state hypothesis proved that identical `activateSavedThread` focus activation caused a
redundant context render, and semantic equal-write suppression passed focused Chrome 2/2. The full S5 still
failed at the identical reply-2 pre-command boundary. That patch was fully reverted; the interaction owner
and its test exactly match HEAD. The earlier annotation-placement suppression attempt was also reverted.

No UI experiment remains. Comm-worker/backend lower layers remain green, the corrected S5 proof harness is
ready, and the fresh manual Vite/Swift loop loads the real worktree. The only remaining S5 blocker is the
external UI/state owner finding why a connected visible enabled Reply control receives one native gesture
without opening its composer under the 1,699-item live cadence. Backend lane will not add a third UI guess,
click workaround, timing change, transport mechanism, or weakened proof.

## 2026-08-24 22:33 EDT — Backend lane: delivery/paint retry loop fixed; Reply 2 remains UI-only

Checkpoint `96e255b40` corrects the worker lifecycle discovered in the live Vite loop. An accepted exact
`queued` disposition now ends the five-second delivery lease without fabricating `applied` or `painted`;
offscreen Review work remains eligible for later ordered paint instead of retrying every five seconds.
Disposition application also carries per-receipt accepted/duplicate/rejected results through the existing
synchronous command turn, so rejected raw inputs cannot apply post-response Review/File owner effects.

Proof is green at the corrected boundaries: focused unit 68/68, actual `MessageChannel` 3/3, broad
BridgeWeb product unit 1,998/1,998, typecheck, and `git diff --check`. A real `origin/main` comparison with
about 697 changed files loaded in Vite/Chrome and stayed stable across two former lease windows: produced
receipts 706 -> 706, pending 0, degraded 0, generation 3. No new port, queue, scheduler, timeout, UI
workaround, security work, or relaxed identity fence was added.

The fresh isolated 1,699-item S5 rerun now loads metadata, commits root create/flush/save, and commits Reply
1 create/flush/save. It fails only at `reply.2.composer.opening`, before any Reply 2 command enters the comm
worker. At failure, Review outstanding work stayed bounded at high-water 9, queued response ages were about
0.6-1.9 ms, and there was no timeout, overload, replacement, or degraded batch. UI/state owner: continue
only the pre-command Reply-control/portal interaction diagnosis. Backend lane will not add click retries,
force-clicks, longer waits, or transport changes to compensate.
