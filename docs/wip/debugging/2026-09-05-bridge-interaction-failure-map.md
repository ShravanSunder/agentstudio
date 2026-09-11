# Bridge interaction reliability: failure and TDD map

This is an investigation map, not a replacement implementation plan or a
readiness claim. Source revalidated at 2026-09-05T21:15:21Z: HEAD `d1bee274d`
with uncommitted transport corrections/tests and concurrent UI work. The running debug and production apps
must be identified independently before their traces are attributed to this source.

## Required behavior

- Backend/worktree freshness continues independently of permission to replace
  the displayed document. Do not introduce another recovery framework.
- File mode: silently apply safe updates; while the user is actively commenting,
  retain the displayed version and offer an update action.
- Review mode: while the user is interacting with the affected content, retain
  it and offer an update action. Header/floating control placement belongs to UI.
- Preserve scroll through refresh, including user movement during asynchronous
  preparation. Do not restore an obsolete pre-fetch scroll position.
- Unrelated tree changes must not blank, reload, or disturb the selected file.
- Markdown and Mermaid need the same continuity as code. First loading a new
  unavailable target differs from preparing a replacement for displayed content.
- Existing pane activity remains independent of app/window keyboard focus;
  inactive-pane work and displayed Pane Zoom work have separate admission rules.

## 2026-09-05 22:15 UTC: current proof and narrowed test-fixture failures

The ordinary annotation-system E2E has now run: its preserved log
`tmp/debug-workflows/2026-09-05-transport-lifecycle-tdd/annotation-system-real-vite-takeover.txt`
records 2/2 tests, exit0, with ordinary native build dependencies. It covers
File/Review Save, gated projection, reload and cold Vite/Swift restart. This
supersedes the earlier statement below that ordinary Save/reload had not run.
It does not close the intermittent first Reply failure in the backpressure journey.

The selected-Review retention Browser witness has not yet reached the target
failure. Its Arrange defects are distinct from application defects: missing
source descriptor identities blocked production range admission; a single-listener
fake worker dropped one of the two real production subscriptions; then an exact
whole-command-list oracle rejected legitimate demand/source/history commands
despite the awaited draft.flush being present. Keep these attempts separately
from target RED evidence. Current first multicast-run output is preserved in
`tmp/debug-workflows/2026-09-05-transport-lifecycle-tdd/review-annotation-save-retention-browser.txt`.
No production retention correction follows from these fixture failures.

F12 source revalidation narrows the old inventory wording: production now calls
`supersedeItem` through `use-bridge-markdown-selection-retirement.ts`, wired in
`bridge-file-viewer-app.tsx` only for the Markdown/non-Pierre selection. The
worker still defers a successor while a predecessor has a render receipt
(`bridge-comm-worker-runtime-protocol.ts:380`). The controller-only test that
directly calls `admitSelection` bypasses that admission guard; its green result
cannot close the rapid code-to-code integration case. A joined production
selection/retirement witness is still required before selecting the correction.

Fresh wire/annotation contract run at App HEAD d1bee274d: 35 tests/3 files passed,
exit0, including content rejection in annotation metadata. HTTP orderly-FIN
and upstream/fork authorization remain unchanged; no dependency mutation made.

## 2026-09-05 21:15 UTC: takeover proof and exact HTTP dependency defect

User authorized the bounded annotation-consumer takeover, SDK gate correction,
and review/merge of relevant SDK changes. SDK gate correction is committed and
pushed as `80480f7`; draft SDK PR #10 remains unmerged. App manifest, resolution,
and actual clean dependency checkout match it. SDK `mise run check` passed
224 tests in 24 filters, zero-violation lint, build and artifact verification.
The downstream package consumer verifier passed. The new ordinary App consumer
gate passed 70 tests in 7 suites with the real frontend build, without dependency
skips. CI passed; independent review is still required.

Canonical UI integration has focused 57-unit and 25-browser-test proof. Parent
verification added RED/GREEN for delayed message/removal receipts, advancing
containing revisions without message changes, control-only non-reconciliation,
projection-before-receipt ordering, and retired complete-content authority.
These do not prove the full real comment journey. Full Node unit layer passed
2,267 tests. The real Vite stress first found an obsolete flat-receipt observer,
now corrected to the strict canonical schema. The next real failure is the
missing Reply control after root Save; bounded DOM/source/ancestor diagnostics
are being captured before any further product edit. Ordinary Save/reload tests
have not run because the required stress prelude failed.

The 256 KiB envelope is a product resource policy, not a demonstrated WebKit
ceiling. A first-frame regression proved that reusing the new wire maximum
silently doubled ordinary File chunks. File and buffered Review producers now
use a separate 128 KiB producer policy; focused native 11/11 passed. Metadata
remains body-free. Fresh packaged WebKit proof passed both declarations: all six
capacity cases through 1 MiB, plus the packaged worker's exact maximum frame,
256 KiB POST and abort-causal teardown. This is carrier proof, not the complete
packaged File/Review/annotation/clipboard journey.

F03 has two separate causes/owners. The current HTTP adapter does not reliably
propagate idle FIN to its native producer. The proposed library helper has an
additional upstream EOF bug after `Request.collectBody`:

`HummingbirdCore/Request/RequestBodyMergedWithUnderlyingRequestPartIterator.swift`
loops in `.underlying` until it sees `.head`, but never handles `nil` from the
underlying iterator. FIN therefore loops forever; RST throws and reaches the
inbound-close handler. The signal diagnostic observed both wrapper cancellation
and upstream termination absent, followed by teardown timeout. The original-body
control bypasses the defective merged iterator. GitHub source for latest release
2.26.0 contains the same defect as the pinned 2.23.0. No dependency patch/fork or
new recovery mechanism has been introduced; upstream-fix/pin authority is pending.
The attempted writer handoff was rejected after reading the non-Sendable, mutable
`ResponseBodyWriter` contract. Socket-close-only prototype is not a complete fix.

New evidence lives under `tmp/debug-workflows/2026-09-05-transport-lifecycle-tdd/`:
`sdk-takeover-check.txt`, `sdk-ordinary-app-consumer-unsandboxed.txt`,
`canonical-ui-focused-unit-green.txt`, `canonical-ui-focused-browser-green.txt`,
`canonical-ui-projection-before-receipt-first-red.txt`,
`canonical-ui-content-authority-retirement-first-red.txt`,
`file-chunk-policy-red-unsandboxed.txt`, `file-chunk-policy-green.txt`,
`packaged-webkit-envelope-takeover-second.txt`,
`http-stream-lifetime-signal-diagnostic-1.txt`, and
`annotation-save-real-vite-takeover-second-unsandboxed.txt`.

## 2026-09-05 18:46 UTC: earlier SDK release verification

SDK candidate and actual app-built dependency both match97cf69f; sibling SDK
checkout stayed clean. GitHub main474bf342 is12commits behind (26file delta),
not the older local-main comparison. No candidate-branch PR or current CI
checks/statuses were found; no release action taken.

Package build/lint and downstream umbrella/leaf consumer verifier pass.
Package test passed222tests across23filters before the2Bridge compatibility
tests failed in their generated partial copy of App source. The missing types
are an extraction/harness failure, not an observed SDK Git-result defect.
Real App compiled adapters pass70tests in7suites at the same SDK revision,
including actual LibGit2/filesystem cases. The initial sandbox-only failure
and unchanged permitted retry are separately preserved. These are lower-layer
native proofs with frontend dependencies excluded; the failed package gate,
UI typecheck, aggregate and packaged proof remain required and unproven.

Do not repair the SDK harness by copying more App declarations, drop its gate,
or infer release readiness from the independent consumer proof. A scoped
replacement of the copied-source compatibility mechanism still needs admission
outside the original LFS correction. UI consumer ownership/handoff is also
still unresolved; see TRANSPORT-0037 for exact current state and evidence paths.

## 2026-09-05 18:07 UTC: HTTP envelope parity and live-stream proof gap

The DevServer wrapper retained a duplicate128KiB body cap despite advertising
256KiB. Permanent HTTP worker-admission cases now exercise normal, exact
advertised limit, and+1 requests. Exact-limit RED returned413 instead of200.
The wrapper now consumes the shared native limit (one package-visible constant);
11HTTP-routing declarations, including all3body cases, pass. No content-policy
restriction added; bootstrap8KiB and other unrelated bounds unchanged.
Final native canonical refresh54tests/9suites passed after lint cleanup.
Evidence: `http-envelope-parity-first-red.txt`, `http-envelope-parity-green.txt`,
`canonical-native-final-refresh.txt`; same explicit native-only proof boundary.

Source inspection clarifies why lower integration tests cannot close F03:
annotation commands use the in-process Hummingbird router, but their metadata
stream helper calls the native host and response adapter directly, bypassing
the live HTTP request-body lifetime. Preserve their persistence/convergence
evidence, not a socket-disconnect claim. Live cancellation proof remains RED.
Pinned Hummingbird's original-body helper supplies disconnect cancellation, but
explicitly closes the connection on operation completion. Response-head/error
delivery and finite-route keep-alive must be preserved before adopting it;
no blanket wrapper, heartbeat, new handler, or recovery system has been added.

## 2026-09-05 17:47 UTC: canonical native and TS cutover

Native now returns the strict complete-message/origin-context or removal union.
Creation, Reply, flush, Save, edit ownership, and saved Revert carry canonical
messages; empty never-saved flush/Revert carry identity captured in the deletion
transaction, actual committed session revision, and surviving-thread revision/null.
Revision-only receipt model was removed, not retained as a compatibility branch.

Isolated native54tests/9suites passed, including all4removal cases and full
production control-envelope encode/decode with maximal context/correlation.
Largest envelope222838bytes; valid text is preserved. Additional real Swift
HTTP-router/SQLite/filesystem integration6tests passed across three serialized
commands (output/two-pane/restart, located restore, root+five saved replies).
The HTTP client is Hummingbird's in-process `.router`, not socket/browser proof.
Core TS canonical/contract14tests passed; raw/decoded timestamps are converted
once and legacy/mismatched/partial/placement-bearing receipts are rejected.

Native proofs used explicit `mise run --skip-deps test:swift -- --filter ...`:
current Swift prebuild and vendor verification ran, but frontend preparation was
intentionally excluded for these lower-layer native observations. Ordinary
`mise run test:swift` remains blocked by21TypeScript errors in UI-owned legacy
receipt consumers/test factories. No frontend, aggregate, browser, or packaged
gate was waived or claimed green. The unsuccessful `--no-deps` attempt remains
recorded; that flag did not skip the frontend task dependency.

UI cutover is the next dependency, handed off in TRANSPORT-0034/0035. Store's
recordCommandOutcome still records history only; it needs the agreed canonical
overlay and source-fenced inline presentation. Parent has not touched UI-owned
cursor/composer/compact-thread/store files. The one-line packaged diagnostic
digest handshake (TRANSPORT-0031) is also pending. Native app GUI access was last
reported locked by UI-032; not re-proven in this native-only slice.
Independent review, generic budget-document/plan reconciliation, current
ordinary aggregate, real Vite and packaged proof all remain open.

Evidence: `canonical-native-regression.txt`, `canonical-http-output.txt`,
`canonical-http-located.txt`, `canonical-http-durability.txt`,
`canonical-ts-first-red.txt`, `canonical-ts-green.txt`, and the preserved
`canonical-native-...` build/isolation attempts in the lifecycle evidence folder.

## 2026-09-05 16:52 UTC: carrier proof and envelope correction

Owner correction supersedes the proposed precommit-rejection direction below:
valid annotation content must be carried by adjusting sender/receiver envelope
parameters, not rejected to preserve an arbitrary implementation cap.

Real macOS26.5.2 URL-scheme proof:262143,262145,1048576-byte GET→POST→echo
round-trips all preserved exact bytes, with both one-shot and64KiB-chunked
deliveries. Six cases passed twice; final run exit0 with no source warnings.
The first test-only missing-import compile failure is preserved. This proves
the installed carrier handles those cases; it does not prove an unlimited
maximum or production annotation UI correctness.

Sender/receiver candidate now uses256KiB command bodies and262102-byte data
payloads (existing256KiB frame body minus42-byte data header). Metadata128KiB,
content control16KiB, producer4MiB/count64 queue bounds remain unchanged.
The redundant native64KiB MessageEntry guard was removed. No body policy,
SQLite admission, new recovery mechanism, record splitting, or truncation added.
Requirements R-P1-005/R-P1-017 remain full-content guarantees; affected
specification/program-design wording now records envelope capacity rather than
turning the old implementation cap into an additional product restriction.

Fresh proof:

- Native76 declarations in5 suites passed, including real SQLite ordinary,
  escaped, and control-character saved+draft pairs and complete projection
  cursor round-trip. Message/record bytes:33218/33483,65986/66251,
  197058/197323 respectively. The framed control-case record is197353 bytes.
- Full BridgeWeb unit suite:345 files,2241 tests passed, exit0.
- TypeScript typecheck exit0. Scoped Swift format/lint and TS format exit0;
  typed TS lint exit0 with two pre-existing assertions warned in the codec test.
  Final git diff --check exit0. No aggregate/native UI/PR-ready claim.
- First combined Swift candidate crashed: fixed17-frame test vector wrongly
  used the increased maximum chunk size. Source-owned fixture correction keeps
  its original128KiB chunks and every17-frame/whole-source assertion. Separate
  maximum-envelope/+1-negative tests exercise the larger budget. First TS run
  caught mirrored corpus and same fixed-vector drift; all failures retained.

Remaining: maximum-context/full canonical command envelope coverage, canonical
message/tombstone DTO and UI consumer cutover, typed-lint baseline disposition,
independent review and old generic transport documentation/plan reconciliation,
producer emission/performance validation, real Vite and packaged annotation proof.
The packaged maximum-frame diagnostic needs the UI-agent handshake for its
one SHA constant (TRANSPORT-0031); it has not been run against the candidate.
Native visual proof is separately GUI-locked per UI-032, not a headless test failure.

Evidence in the lifecycle folder: `url-scheme-capacity-first.txt`,
`url-scheme-capacity-second.txt`, `url-scheme-capacity-final.txt`,
`envelope-matrix-first-red.txt`, `envelope-after-redundant-cap.txt`,
`envelope-ts-parameter-red.txt`, `envelope-ts-fixture-mismatch.txt`,
`envelope-ts-full-unit.txt`, `envelope-ts-full-unit-green.txt`,
`envelope-native-green-attempt.txt`,
`envelope-isolate-BridgeProductContentFrameCodecTests.txt`, `envelope-native-second.txt`.

## 2026-09-05 14:29 UTC: earlier proof and canonical receipt frontier

- Canonical response boundary coordinated in UI-029 / TRANSPORT-0024: complete
  message plus original thread context (no placement); transaction-captured
  tombstone for removed drafts. UI owns the existing source-fenced local slot
  and overlay; native transport owns domain results and application DTO/schema.
  Revision-only production receipts have not yet been replaced.
- Empty `draft.flush` was rejected by the native nonempty-body decoder before
  reaching SQLite's existing removal branch. Permanent contract RED: three
  accepted-empty cases failed `invalidJSON`. Narrow decoder correction: ten
  Swift declarations passed (including all eight parameterized draft cases),
  exit0; TS call-contract suite13/13, exit0. Size/Markdown and create rejection
  remain strict. No UI or generic transport changes for this correction.
- Real service/SQLite RED now proves an accepted saved body and draft can each
  be16KiB but exceed the64KiB complete-message encoding bound after escaping.
  Both durable bodies were re-read successfully; MessageEntry then throws
  `messageEntryExceedsMaximum`. One test failed, exit1. This predates canonical
  receipts and can make the read projection unavailable. Reusing that throwing
  constructor after a commit would also risk misreporting a committed mutation.
  No bound widening, precommit policy, or recovery mechanism has been adopted;
  source-bound advisor consultation is pending before selecting a correction.
- Scoped swift-format lint and SwiftLint with `--no-cache --strict` passed for
  the decoder and two new tests. First SwiftLint attempt was blocked writing its
  cache outside sandbox; rerun disabled cache, not lint rules. Diff check passed.
- Reopened prior green receipts: Markdown selection real E2E2/2 plus typecheck;
  File-bootstrap→Review live activation Swift2/2, DevServer build0, E2E1/1.
  Those are earlier slice evidence, not fresh whole-PR/packaged validation.

Raw current evidence under `tmp/debug-workflows/2026-09-05-transport-lifecycle-tdd/`:
`empty-flush-contract-red.txt`, `empty-flush-contract-green.txt`,
`committed-message-bounds-first-red.txt`. Canonical receipt/tombstone RED files
remain intact. Original failed attempts are not replaced by later successes.

## Failure inventory

| ID | Starting state and action | Expected outcome | Evidence and current status | Owning seam / test |
| --- | --- | --- | --- | --- |
| F01 | File is fully rendered; edit its real worktree file | Current descriptor and bytes without another click | Reproduced directly through Vite/Swift; native changeset invalidated old descriptor without renewal. Candidate now reaches new exact painted SHA. Not complete because F02 remains. | Native File source; `BridgePaneProductFileDescriptorRenewalTests`; `bridge-viewer-vite-stream-recovery.e2e.test.ts` |
| F02 | Same File refresh, observe each browser frame | Retain visible previous body until replacement is ready | Original hidden-wrapper defect has an uncommitted UI-owned correction. Fresh direct run reaches new exact painted SHA but fails unchanged probe: at 564.8 ms, visible wrapper, 58 DOM lines, 948 px height, correct retained path, missing diagnostic paint stamp. Actual content/scroll continuity versus stamp continuity still requires discrimination. | UI-owned `bridge-file-viewer-code-panel.tsx:394`; transport-owned frame-aligned retention probe; TRANSPORT-0006 |
| F03 | Established metadata stream is disconnected | Retire obsolete producer, reconnect, restore current demand | Reproduced: read failure detected, replacement opens, HTTP 409. Native log identifies duplicate producer. | HTTP adapter / producer retirement; live idle-disconnect Swift test remains RED |
| F04 | Select a new file during repository changes | Load selected current content or explicit terminal error | User-reported “waiting for content”; exact current-source sequence not yet reproduced | Chrome exploration and trace lane |
| F05 | Choose Markdown/documentation filter | Expected document rows remain addressable | User-reported missing documentation; app/build and exact file set still need binding | File classification/filter/source discovery; Chrome exploration |
| F06 | File README Markdown/Mermaid fully renders; select docs/diagram.md | Correct active mode and document; no stuck preparation | Original RED retained. UI adapter now supplies honest completion through existing renderer-neutral coordinator; real Vite/Swift Markdown→Markdown and Markdown→code cases2/2 pass. Committed d1bee274d. Does not close rapid supersession, refresh/scroll, failure, or packaged cases. | Main selected-renderer completion / worker admission; `bridge-viewer-vite-markdown-selection.e2e.test.ts`; `markdown-adapter-real-replay.txt` |
| F07 | Refresh while scrolling or after scrolling | Preserve user's current location | Requirement; broad current-runtime proof absent | Code/Markdown scroll owner; frame-aligned exploration then permanent regression |
| F08 | Source changes while commenting in File | Retain displayed version and editor; offer update | User-confirmed requirement; current end-to-end hold behavior not yet established | Existing annotation interaction and File presentation owners; UI coordination required |
| F09 | Source changes while interacting in Review | Hold affected displayed content; offer update | Existing Review presentation gate has attention/held-candidate behavior; full requested interaction matrix not yet proven | Review installation gate and semantic attention |
| F10 | Background app/window or enter/retarget Pane Zoom | Keep structurally active pane live; suspend excluded pane work | 8 activity tests and 14 correctly selected nested composition tests passed. Does not prove full live document update in native zoom. | Existing pane activity and workspace composition; packaged replay remains |
| F11 | Plus activation or multiline annotation selection immediately after scrolling | Exact range opens one stable composer | UI-004 reports a Chromium red/green for Pierre pointer admission during scroll; transport has not independently verified UI proof. Not classified as a transport failure. | UI-owned CodeView options and annotation pointer tests; packaged UI proof outstanding |
| F12 | Select another code file after A is queued but before A paints | Retire abandoned work and admit current selection; late A callbacks cannot affect B | Source exposure localized: production never invokes main supersedeItem, while worker retains receipt-bearing predecessor. No dedicated rapid-code runtime reproduction yet. | Existing main supersession / selected operation settlement; joined main-worker regression required |
| F13 | File-only bootstrap, then activate Review | Live Review metadata and selected content; return to retained Markdown | Development composition omitted active-mode callback; first correction populated replay only. Existing live reserve/commit/deliver task now used. Swift2/2 and real E2E1/1 green; repeated/failure and native app paths separate. | DevelopmentProductHost composition/ReviewComparison; `file-review-live-publication-green.txt` |
| F14 | Save commits while projection remains unavailable; start another root | Saved canonical content visible, editor released, next annotation allowed | Native complete-message/removal and strict TS schema cutover now pass lower-layer proof. UI-022 RED and old UI consumers remain; canonical overlay/renderer/composer integration and real browser proof not complete. | Native adapter/domain/DTO + UI-owned surface overlay/composer |
| F15 | Clear a never-saved draft and flush | Empty mutation reaches repository removal semantics | Native decoder mismatch corrected after focused RED. Swift contract10/10 green and TS13/13 green. Removal receipt still absent; no whole-flow completion claim. | OperationContracts.validatedBody; DraftFlushContractTests |
| F16 | Save maximum escaped body, then edit another maximum escaped draft | Durable committed message remains serializable and readable | Original RED preserved. Sender/receiver envelope candidate passes ordinary/escaped/control-character real SQLite and complete projection round-trip; body admission unchanged. Full-context/canonical command/UI and packaged proof still open. | Complete MessageEntry/cursor plus shared native/TS envelope constants; CommittedMessageBoundsTests |

## Execution lanes

1. Source and OTel traces: read-only Markdown/File-stall delegate, bind process,
   app version, marker and request progression; return hypotheses separately from
   confirmed causes. Never modify running apps or expose credentials/payloads.
2. Chrome exploration: use a disposable worktree with real Swift/Vite, code,
   multiple Markdown documents, a scrollable guide and Mermaid. Record exact
   clicks, selected file/mode, visible result, and screenshot/trace anchors.
3. Parent native verification: reproduce each accepted case in WebKit/Swift,
   map it to a focused regression, then correct only the evidenced existing owner.

The browser explorer must not edit source files, change preferences, restart
Chrome, or operate unrelated tabs. The parent owns fixture mutations and cleanup.

## Evidence discipline

Each new observation must record app/source identity, initial state, exact action
sequence, expected/observed outcome, first failure, recovery attempt (if any),
and owning regression. A successful rerun does not erase the first failure.
Use `reported`, `reproduced`, `localized`, `candidate-fixed`, or `verified`;
`verified` requires the complete applicable proof, not only a unit result.

Existing detailed TDD evidence and failed attempts are in
`tmp/debug-workflows/2026-09-05-transport-lifecycle-tdd/`.

## 2026-09-05 11:26 UTC: validated findings and next proof seams

The first Markdown failure output is retained in
`tmp/debug-workflows/2026-09-05-transport-lifecycle-tdd/markdown-selection-first-red.txt`.
Chrome's independent receipt is in
`tmp/research-workflows/2026-09-05-bridge-interactions/browser-exploration/interaction-exploration-receipt.md`.
Narrow fixture lifecycle evidence is in
`tmp/debug-workflows/2026-09-05-transport-lifecycle-tdd/markdown-fixture-lifecycle-red.json`.

This is a missing completion connection, not evidence that the metadata stream
stopped. A queued receipt is excluded from receipt-lease expiry. Supersession can
honestly retire abandoned selection A, but does not mean still-selected Markdown
success: accepted rejection/supersession currently publishes unavailable and retry.
Follow-up source verification established that the generic main rendered-element
readback already supports honest Markdown success without a new API or message.
UI-006 accepted a UI-owned adapter through this existing coordinator, with exact
committed article/source identity and frame-time validation. Stale readback must
be null, not merely readableContentMatchesItem=false. Mermaid remains progressive
and does not gate readable document paint. Abandoned-selection/failure terminals
still need their own existing-owner wiring and tests. No timeout, fake Pierre
paint, new receipt kind, or new recovery service has been adopted.

Proof pyramid for this failure family:

- Unit: exact current/late/duplicate terminal transitions; obsolete A cannot
  settle B; preserved authority and selection fences.
- Boundary integration: join actual main publication admission, product selection
  dispatch and worker operation owner. Queue A without Pierre paint, select B,
  exercise honest retirement and reject late A callbacks. A test that manually
  calls supersedeItem alone does not prove missing production wiring.
- Renderer integration: real Markdown mount/failure/abandonment plus existing
  fulfillment coordinator; no invented Pierre post-render callback.
- Real Swift/Vite: preserve the two-document red and extend to Markdown-to-code,
  code-to-Markdown, filters, mode switching, changed source and scroll continuity.
- Packaged: replay on an independently identified current WKWebView build. Vite
  using real Swift is not packaged proof, and an older debug app is not this HEAD.

The first expanded Chrome matrix used separate fresh tabs on one origin. Parent
source inspection found that each bootstrap replaces the development host's one
pane session, so those cases could interfere with each other. They are quarantined
as observations, not accepted independent product findings. Original single-tab
Markdown evidence and its separate one-page E2E remain valid. Corrected replay
uses one active tab per independent host/pane/data root, recording every reset.
Current replay origins are 56696 (filter), 56803 (Markdown-to-code), and 56918
(code-to-Markdown-to-Review). Each health endpoint returned 204 before dispatch.

Communication has two single-writer append-only logs:

- Transport: `docs/wip/communications/2026-09-05-pr-a-transport-agent-comms.md`
- UI: `docs/wip/communications/2026-09-05-bridge-ui-agent-log.md`

Tail, validate, then acknowledge by stable entry ID before overlapping work.

## Current boundaries

- No new heartbeat, recovery service, queue, store, scheduler, or periodic
  connection-closing policy has been adopted.
- The protected UI lane owns code-panel visibility, refresh controls and paint.
- Scoped tests do not establish aggregate, packaged, release or PR readiness.
- No merge or release action has been taken by this investigation.
