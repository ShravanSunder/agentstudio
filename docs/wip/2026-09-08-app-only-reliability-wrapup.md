# App-only reliability: goal and complete wrap-up tree

**Goal:** finish the scoped Agent Studio reliability change as one independently reviewed PR,
ready to merge but unmerged, with an isolated debug app the user can test.

This is the current execution tree, replacing the superseded September 7 reliability specs,
old implementation plan and preliminary repair sequence. Historical audit reports are evidence,
not implementation instructions. Worktree: `agent-studio.issues-perf`; branch:
`takeover/remaining-performance-memory`. Last verified HEAD `293cc48c7`, local main `6cbbee4a4`.
Refresh remote state before integration/PR work; do not assume those refs remain current.

## Fixed boundaries

- Application code only. No Ghostty/zmx edits, new vendor files, pin changes, build patches,
  local vendor builds, or custom vendor artifacts. Use the verified shared output symlinks.
- Existing `core.sqlite`, exactly the three agreed journal tables. Ordinary schema setup only.
  No second database, event sourcing, supervisor, lease system, or upgrade framework.
- Startup session cleanup must wait five minutes; queued wakeups cannot bypass that gate.
  This does not rewrite the stored Undo deadline.
- Preserve 300-second Undo, ten available operations per workspace with oldest-first eviction,
  pane/session identities, other live/backgrounded/Undo owners, and previous app fixes/tests.
- An uncertain reboot may add at most one conservative five-minute grace; ordinary relaunch
  must not renew a recovered deadline. No promise that commands survive machine reboot.
- Cleanup is limited to the verified unowned zmx session and its existing PTY process group.
  Unknown/replaced sessions and deliberately detached services stay untouched.
- Preserve unrelated worktree changes/backups; exclude agentstudio-git review-comment work
  and the resolved disk incident. No speculative reactive-state or vendor redesign.

## Tree

Legend: DONE = bounded evidence exists; KEEP = implementation retained, final proof still needed;
TODO = unfinished. A completed child does not make its parent complete.

```text
ONE APP-ONLY PR, READY BUT UNMERGED
|
+-- 1. Clean authority and PR contents
|   +-- DONE: vendor source reset; shared setup and zero vendor diff verified
|   +-- DONE: custom artifact, native prototypes, accidental file, old investigations pruned
|   +-- DONE: first fresh Astra pruning review; app/test paths preserved
|   +-- DONE: superseded reliability specs/plans removed; use only this execution tree
|   +-- DONE: fresh no-fork Astra reviewed this tree/pruning; correction verified, no open finding
|   +-- TODO: explicit scoped staging; exclude unrelated untracked work
|
+-- 2. Finish the actual application behavior
|   +-- KEEP: durable create/close/Undo, writer ordering and publication/slot fixes
|   +-- KEEP: deadline/reboot recovery, capacity, shared-owner query and bounded pruning
|   +-- KEEP: visibility/focus/drawer, attention ordering and observation-lifetime fixes
|   +-- DONE: tested immutable identity and matching-pending completion repository writes
|   +-- KEEP: immediate durable correlation; pending-session evidence and completion writes
|   +-- KEEP: bounded existing-zmx control; two isolated real-process scenarios passed previously
|   +-- KEEP: pending-only consumer; first observation after discard now works (9 tests passed)
|   +-- DONE: five-minute startup gate and production boot wiring, injected-clock proof
|   +-- KEEP: persisted failures, bounded retries, extinction reconciliation and bounded history pruning
|   +-- KEEP: stale native mount rejection and repeated construction protection, scoped tests
|   +-- DONE: remove owned-only observation dead end; preserve ordinary Close/Discard behavior
|   +-- DONE: preserve existing attach-or-create restore; remove unasked missing-session failure UI
|   +-- TODO: resolve any reproduced app-owned native lifetime defect using existing APIs
|
+-- 3. Prove the complete behavior
|   +-- DONE: sampler keypath overcount regression (5 tests passed)
|   +-- DONE: cleanup-storage / ownership / pruning selection (7 tests passed)
|   +-- DONE: zmx harness namespace isolation regression (10 tests passed)
|   +-- DONE: real same-run close/Undo preserved IDs and running PTY processes
|   +-- DONE: real restart retained exact deadline; expiry occurred at original deadline
|   +-- TODO: SQLite rollback, stale writes, duplicates, Undo/expiry race on final state
|   +-- TODO: pane/tab/drawer Undo, eleventh close, discard, cross-workspace/shared owners
|   +-- TODO: real zmx kill, surviving original group, replacement/unknown and detached service
|   +-- TODO: crash after kill, failed/missing identity, transport failure and retry/restart
|   +-- TODO: actual restart-and-Undo UI journey (last attempt blocked by locked GUI)
|   +-- TODO: retained view/layer, in-flight callbacks, creation failure, repeated retire, quit
|   +-- TODO: tab/arrangement/move/zoom/drawer/minimize + bridge/webview preservation
|   +-- TODO: current observation stop/replacement/remove/reinsert/Undo regression suites
|   +-- TODO: fixed-geometry memory cycles, actual 300 seconds, native/thread/process counts
|   +-- TODO: UI responsiveness under normal and busy shutdown; report measured limits
|
+-- 4. Deliver
    +-- TODO: source + shared-library + executable identity recorded for final debug build
    +-- TODO: final mise run lint and mise run test; exact exits/counts and scoped runtime proof
    +-- TODO: fresh independent implementation review; verify and resolve findings
    +-- TODO: scoped commits/push; one PR; CI, comments/threads and mergeability verified
    +-- TODO: leave isolated debug app, exact launch details and short user test checklist
    +-- TODO: clean only identified disposable test sessions; preserve unrelated user sessions
    +-- STOP: PR ready to merge, unmerged; no release/tag or merge implied
```

## Storage and ownership

The current schema source is `WorkspaceCoreMigrations+SessionOwnership.swift`. Retain its table
names and ownership constraints; do not add a new persistence abstraction for the worker.

| Table | Stored responsibility |
| --- | --- |
| `workspace_terminal_session_ownership` | session ID; owned/pending/completed; immutable process identity; cleanup request/completion time and controlled failure code |
| `workspace_undo_close` | operation/workspace identity, close order and kind, 300-second UTC/boot/uptime deadline, available/restored/expired/evicted state, versioned snapshot |
| `workspace_undo_close_member` | operation-to-pane/session membership; protects available Undo ownership |

Commit ownership before publishing UI or running destructive effects. Recheck all owners before
retirement. CLI success, a missing socket, manager release, native free and process-group extinction
are distinct observations. Missing evidence remains incomplete; do not label it success.

## Execution and proof discipline

First finish the tree review and storage/control connection, then real process scenarios and native
proof, then final delivery. Use scenario-led red/green tests at the cheapest meaningful boundary;
real SQLite and process interactions cannot be replaced by recorders. Keep shared inputs unchanged.
Storage/control integration and a pending-only cleanup consumer now exist. First process evidence
can be acquired after final owner removal because the session correlation is already durable.
Finish the five-minute startup gate and wire the consumer after boot recovery. No Discard failure
policy, live-session survey, or pre-discard identity barrier is authorized or needed.

Native free currently uses the stock synchronous API on MainActor. Do not infer that UI/layer
safety is proved, move it to an unsupported executor, or reintroduce vendor APIs. Diagnose actual
app paths and measure responsiveness. A real mismatch returns with evidence; it does not authorize
another architecture or silently weaker behavior. GUI lock blocks UI proof only; continue headless work.

Keep final build inputs tied to the executable and launch marker. Historical custom-vendor evidence
does not count. Existing results are historical/scoped until the finished source passes final gates.

## Evidence and review homes

- [Full initial inventory](2026-09-07-app-only-reliability-audit/astra-full-review.md): 207 initial entries.
- [Verified first pruning](2026-09-07-app-only-reliability-audit/astra-pruning-review.md).
- [Detailed takeover/evidence history](2026-09-07-app-only-reliability-audit/takeover-state.md).
- [Fresh Astra tree review](2026-09-07-app-only-reliability-audit/astra-wrapup-tree-review.md): ready as a bounded execution map; implementation and final proof remain unfinished.

Do not delete unrelated old documents merely because of their date. Only this lane's superseded
instructions and identified experiments are cleanup targets. No current full aggregate, production
cleanup execution, native safety or PR-readiness claim exists yet.

## Current advisor disposition and proof

The user corrected the timing and rejected the proposed failed-Discard/recoverable-pane behavior.
That proposal was never implemented. The prior blocker is withdrawn: process evidence is cleanup
evidence, not the application's pane/session ownership identity. No user decision is pending.

Fresh no-history Astra advisor `reliability_scope_advisor`, assignment
`2026-09-08-reliability-overengineering-review`, inspected source and the prior failure history.
Parent verified these accepted findings:

- IDs are allocated and saved before publication/launch. Keep that ordering and its tests.
- First process observation need not precede final owner removal. A journal-known pending session
  is not an unknown external session. Select only pending rows; remove live-session surveying and
  the non-retrying `missingIdentity` disposition. This correction is implemented.
- Add one five-minute startup gate before any cleanup work; preserve each Undo deadline separately.
- Keep native retirement, live/hidden/Undo owner checks, retries and honest completion evidence.
- Remove the old failed-Discard proposal and startup-readiness speculation from active authority.
- Evaluate simplification of custom zmx wire/process machinery against actual completion and
  recorded-replacement guarantees before removing it. Stock CLI already probes and sends Kill on
  one connection, but CLI exit zero alone is not evidence of completion. This evaluation remains open.

Known limits: no first observation can prove whether an earlier unrecorded incarnation existed.
No-row session IDs never gain cleanup authority. A recorded incarnation is immutable, and current
retirement refuses a mismatch. Missing endpoints/evidence must not be labelled process extinction.

Current evidence (scoped, not whole-app/PR acceptance):

- Correlated cleanup red: six tests / two suites, eleven issues, exit 1 against the owned-only rule.
  `/tmp/agentstudio-correlated-cleanup-red.log`.
- Correlated cleanup green: nine tests / two suites, exit 0. Includes normal disappearance of a
  discarded pane followed by its session cleanup, unrecorded-ID rejection, immutable recorded
  identity, owner/native protection, retry and shutdown.
  `/tmp/agentstudio-correlated-cleanup-green.log`.
- Prior identity/native/real-zmx selection: seven tests / four suites, exit 0.
  `/tmp/agentstudio-zmx-identity-validation-green.log`.
- Prior full lint passed (format, zero SwiftLint violations, architecture, release scripts):
  `/tmp/agentstudio-reliability-lint-final-slice.log`. Re-run for the latest correlation/timing edits.
- Startup 299/300-second and cancellation regression now added using `TestPushClock`; red run pending.
  `/tmp/agentstudio-startup-cleanup-delay-red.log`.
- Shared vendor verification and empty vendor/pin/setup diff passed. No vendor change, commit,
  push, production cleanup activation or new debug-app proof occurred in this continuation.

Execution mistakes remain recorded, not endorsed: unauthorized historical vendor/prototype work
was removed; the sampler had overcounted keypaths; compiler/selection failures were not red proof;
a rejected tracing refactor was removed without widening module access; overlapping lint/test
started an unnecessary second-slot rebuild, which was stopped by its verified process group and
replaced with sequential checks. The advisor was explicitly given that history.

Next: startup gate red/green → boot integration → backend/pruning and real native/process proof →
full sequential gates → final independent review → one unmerged PR and testable isolated debug app.

## Draft PR checkpoint

- User requested PR creation before remaining wrap-up. Open draft, not merge-ready.
- Latest combined scoped run: 44 tests / 9 suites passed, exit 0,
  `/tmp/agentstudio-reliability-scoped-proof.log`.
- Full `mise run test` failed: fast Swift run selected 4508 tests / 640 suites,
  four failing tests / six issues in `ObservabilityDebugVerifierBridgeDiagnosticTests`,
  `DraggableTabBarWindowDragTests`, and `PaneTabViewControllerPaneInboxCommandTests`.
  `/tmp/agentstudio-app-only-startup-grace-aggregate.log`. Do not classify these as
  unrelated or flakes without investigation. Later aggregate phases are incomplete.
- Initial aggregate attempt failed writing SwiftLint cache in the sandbox; the rerun used
  normal cache access. No runner, lint rule, or vendor change was made to bypass it.
- Remote main checked through GitHub: `6cbbee4a4422c25b10c1bcf1c6a511f5393a0b0c`,
  contained in this branch. No merge or tag is authorized by this draft checkpoint.
- Current debug-runtime memory proof, remaining failure investigation, final independent
  implementation review and CI remain required before readiness.

## PR #335 continuation: current evidence

Draft URL: https://github.com/ShravanSunder/agentstudio/pull/335. Head `863b3bd7b`.
Only two test files currently differ: tab-drag and targeted pane-inbox command tests now await
the existing command queue and use required MainActor suite isolation. Production is unchanged.
Isolated reproduction: Bridge verifier 7 passed; drag 14 tests with 1 failure; inbox 11 tests
with 3 issues. Awaited-command correction: 25 tests / 2 suites passed, exit 0 at
`/tmp/agentstudio-command-completion-green.log`. Full aggregate rerun remains in progress at
`/tmp/agentstudio-pr335-aggregate-command-waits.log`.

Fresh debug proof uses PID 32315, standard lbim bundle, marker
`debug-observability-lbim-1788911249-31215`. Existing build launched with `--skip-build`
after verifying no app instance; authenticated IPC, shared OTLP verifier passed.
- Four journal sessions were pending at 4:41 after startup and completed with process evidence
  by 5:13. All eight recorded daemon/terminal PIDs were absent on read-only checks.
- The live test terminal remained owned. Pane `01A0836E-C055-7C26-B54B-C70A4642F130`,
  session `01A0836E-C055-7553-A753-9E2F5123EA34` survived six close/Undo cycles unchanged.
- Initial real close produced an available 300-second Undo entry; Undo restored it.
- Renderer sampler before/after six cycles: one surface, one mount, one host, one renderer
  thread and one I/O thread; graphics fields unchanged; footprint 565 -> 575 MiB.
  `/tmp/agentstudio-pr335-renderer-baseline.json`,
  `/tmp/agentstudio-pr335-renderer-after-undo.json`. This is bounded evidence, not zero-leak proof.
- Final test pane closed again for actual 300-second expiry; outcome pending.
- Full independent implementation reviewer `pr335_implementation_review` is inspecting the
  exact diff with no parent history. No final acceptance result exists yet.

### Actual expiry and restart proof completed

- After the real 300-second close deadline, the entry became expired and the session completed.
  Both recorded original processes were absent. `/tmp/agentstudio-pr335-renderer-after-expiry.json`
  reports renderer/I/O/PTY/mount/host counts all zero, owned graphics 0 MiB, footprint 165 MiB.
  One inert SurfaceView wrapper remained; native resources were released.
- A new test session was created, a shell variable set, and the pane closed. Normal app quit
  completed, then standard isolated launcher restarted as PID22151, marker
  `debug-observability-lbim-1788912226-20619`.
- Before/after deadline records compare identically at
  `/tmp/agentstudio-pr335-restart-deadline-{before,after}.txt`. Real UI Undo restored pane
  `01A08378-FD26-75B7-BD26-1F4F4E283D7E` and session
  `01A08378-FD26-7362-A7A5-9426B6E9BF37`; terminal printed `AFTER_RESTART=retained`.
- Independent complete reviewer returned no supported product-code finding, one documentation
  finding D1: cleanup availability, async command ordering, and commit/prepublication teardown
  diagram were stale. Parent verified and corrected those exact docs. Final correction recheck
  pending; reviewer did not grant PR readiness.
- Remaining proof includes final aggregate/CI, real detached-service/replacement/crash-retry,
  extended native transition/capacity/shared-owner and busy-shutdown scenarios.

### Aggregate shutdown blocker

The aggregate passed the browser integration tests (211 passed, 5 existing skips) but Vitest
did not exit for over eleven minutes. Parent verified exact issues-perf process PID87641
under aggregate59595 at 0%CPU; it retained no TCP listener. Parent sent TERM only to that
verified process to release the stalled run. The gate is failed/incomplete, not passed.
No BridgeWeb runner/source/test policy changes were made. Other worktree test processes
were untouched. Aggregate log: `/tmp/agentstudio-pr335-aggregate-command-waits.log`.
Independent implementation review D1 documentation finding is resolved by source-backed recheck;
no product finding was reported. Remaining proof gaps listed above still prevent readiness.
Current testable debug app is PID22151 under the lbim app path; normal restart/Undo proof passed.
