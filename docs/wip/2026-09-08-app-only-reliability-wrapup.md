# App-only reliability: current wrap-up tree

**Goal:** one independently reviewed Agent Studio PR, ready to merge but unmerged,
with an isolated debug app the user can test. Worktree: `agent-studio.issues-perf`;
branch: `takeover/remaining-performance-memory`; draft PR:
https://github.com/ShravanSunder/agentstudio/pull/335.

Relevance audit HEAD: `95f3c3e44`; audit base: `6cbbee4a4`. Reviewed cleanup and
fixture corrections committed as `40495b2ec` through normal format/lint hooks.
Reviewed cleanup and command-test completion corrections have focused proof and independent
review; full aggregate verification remains required. Refresh remote main before final integration; these are recorded refs,
not a claim that the remote has remained unchanged.

## Fixed boundaries

- App code only. No Ghostty/zmx source, pins, build scripts, local vendor builds, patches or
  custom artifacts. Use the shared prepared framework and zmx output symlinks.
- Existing `core.sqlite`, exactly `workspace_terminal_session_ownership`,
  `workspace_undo_close`, and `workspace_undo_close_member`. Ordinary schema setup only;
  no second database, event sourcing, supervisor, leases or upgrade framework.
- Allocate and persist pane/session correlation before publication and native launch.
- Preserve 300-second Undo, ten available operations per workspace, oldest-first eviction,
  original pane/session identities, restart deadlines and all live/backgrounded/Undo owners.
- Session cleanup waits five minutes after startup. Wakeups cannot bypass this gate;
  the startup delay does not renew stored Undo deadlines. An uncertain reboot may add one
  conservative five-minute grace; no promise that commands survive machine reboot.
- Retire only journal-known unowned sessions after native attachments are gone. Verify recorded
  incarnations and reconcile original processes/group. Protect unknown/replaced sessions and
  deliberately detached services; uncertainty remains pending and retryable.
- Preserve previous app fixes and tests, including dormant Inbox tracker corrections.
  Do not reactivate Inbox. No unrelated atom, observer, vendor or command redesign.
- Preserve existing attach-or-create restore and normal Close/Discard behavior. No missing-session
  failure UI, pre-discard observation barrier, or failed-Discard/recoverable-pane policy.
- Preserve unrelated worktrees/backups/untracked documents. Agentstudio-git review-comment work
  and the resolved disk incident remain out of scope.

## Current tree

DONE means bounded evidence exists; APPLIED means awaiting fresh proof; OPEN remains required.
No child result grants whole-PR readiness.

```text
ONE APP-ONLY PR, READY BUT UNMERGED
├── Scope and contents
│   ├── DONE: unauthorized vendor/prototype material removed; shared inputs restored
│   ├── DONE: obsolete reliability specs/plans removed; this tree owns execution scope
│   ├── DONE: 210-file / 779-hunk relevance inventory and fresh no-history Astra verification
│   ├── DONE: broad test deletion and reversal of preserved fixes rejected
│   └── DONE: reviewed unused-member/default/comment/copy cleanup; no scenarios removed
├── Application behavior retained
│   ├── Immediate durable pane/session identity and ordered command/publication path
│   ├── Three-table durable close/Undo, deadlines, restart recovery, capacity and shared owners
│   ├── Pending-only cleanup, five-minute startup gate, bounded retries and history pruning
│   ├── Recorded-incarnation zmx control with replacement/unknown/detached protection
│   └── App-owned native retirement, host cleanup, visibility/focus and observation corrections
├── Current corrections and proof
│   ├── DONE: five controller suites await command completion; focused gates passed
│   ├── DONE: corrected tests clean up asynchronous harnesses on success or thrown failure
│   ├── DONE: prepared-journal/executor fixtures and joined shutdown; focused gates passed
│   ├── OPEN: diagnose first-open blank drawer using real host/visibility/focus evidence
│   ├── OPEN: resolve or explicitly bound busy-session cleanup and native-free responsiveness
│   └── OPEN: final aggregate rerun, current shared-input runtime proof and native decisions
└── Delivery
    ├── DONE: fresh Astra review and bounded fixture rechecks; no remaining findings
    ├── DONE: initial cleanup committed; remote main 6cbbee4a4 remains integrated
    ├── OPEN: final fixture correction commit/push
    ├── OPEN: PR checks, review comments/threads and mergeability
    ├── OPEN: current debug app, source/input identity and short user test checklist
    └── STOP: ready to merge, unmerged; no release/tag/merge implied
```

## Current correction and audit evidence

The completed audit supports retaining the application behavior and test pyramid. It identified
unused `SurfaceManager.delayScheduler`, an unused visibility accessor and an unused datastore
recovery wrapper; these have been removed with inert test arguments. Required renderer protocol
methods remain, while mock defaults now live in test support. Stale ownership/TTL/future-UndoEngine
comments and close-order descriptions are corrected. The sampler now names all direct child
processes accurately; this is not a zmx process-group census. Parser test naming no longer claims
it executed production-process refusal; meaningful parser scenarios remain.

Preserved: the dual turn/time wait correction, small helpers in their existing owners, all journal
and renderer tests, the null-native view seam, and the hidden→visible→tab-switch sequence that
proves dynamic observation registration. No suite consolidation, scheduler abstraction or live
behavior redesign is authorized by this cleanup.

Full local audit artifacts remain ignored under `tmp/pr335-relevance-audit/`, including
`summary.md`, the exact manifest/diff, final per-hunk dispositions and `astra-inventory-review.md`.
They do not enlarge the PR. The first generated ledgers contained semantic classification errors;
parent and fresh Astra rejected those entries before any pruning. The recurring failure was logged
in the workflow failure log. Scope accounting is not a current correctness or runtime proof claim.

The latest pre-correction aggregate on `95f3c3e44` exited 1:
`/tmp/agentstudio-pr335-aggregate-final.log`. BridgeWeb checks and the Swift main lane
(4,484 tests / 638 suites) passed. `PaneTabViewControllerRepoFavoriteCommandTests` had one issue;
`PaneTabViewControllerQuickOpenDirectoryTests` had three. Both read state immediately after
queued dispatch; their assertions now join the existing queue. Later aggregate phases were not
reached. Focused correction log: `/tmp/agentstudio-pr335-pruning-command-tests.log`: exit 0, 50 tests / 10 suites.
A subsequent aggregate passed lint, architecture and BridgeWeb, then found 18 issues in the
unchanged TabContextMenu/TargetedPane command suites. Their 12 failing tests now await the
existing queue with outcomes preserved; focused rerun passed 33 tests / 2 suites, exit 0:
`/tmp/agentstudio-pr335-targeted-command-completion.log`. That full rerun found two remaining Zoom command consumers; their queue joins passed 22/1.
Further fast-lane failures exposed unprepared journal fixtures and missing executor composition;
these now use the existing real objects, retain original assertions, and join shutdown. Focused
terminal-exit 11/1, runtime-dispatch 16/1, and slot/topology 9/2 selections passed. The runtime-dispatch
no-op/boundary tests now wait for an observable ordered result instead of passing before delivery.
The final isolated direct-close suites also needed standard Core atom scope initialization;
both now pass 6 tests / 2 suites, exit 0, in
`/tmp/agentstudio-pr335-publication-scope-proof.log`. No test body or SQL failure trigger changed.
The committed-HEAD aggregate on `40495b2ec` reached the large Swift lane and exited 1:
`/tmp/agentstudio-pr335-committed-aggregate.log`. DrawerCommandIntegrationTests had five
failing scenarios / 11 issues: its fixture used a store without the SQLite save coordinator
required by terminal creation/discard/close. It now uses the existing prepared-journal
fixture and joins executor/coordinator shutdown on success, early return and throw.
All 20 original scenario bodies, 46 expectations and 12 requirements remain; Astra
found no issue in the bounded correction. Focused proof passed 20 tests / one suite,
exit 0: `/tmp/agentstudio-pr335-drawer-fixture-proof.log`. Drawer correction committed
as `f06fdcdc9` through normal hooks. The large-lane follow-up passed the drawer suite
and then found two prepared terminal restore scenarios failing with five issues. Their
standalone accepted panes had never been installed in the canonical pane graph; production
applies that graph before returning accepted composition. The existing currentness guard
correctly rejects absent/deleted panes. First-three fixture setup now inserts the exact
accepted panes, preserving empty repository/tab topology and frozen descriptor/frame/session
assertions; joined shutdown is local to those tests. No production guard changed.
Astra independently verified the cause and correction. Focused restore/durability/architecture
proof passed 30 tests / three suites, exit 0:
`/tmp/agentstudio-pr335-restore-fixture-proof.log`. The large lane passed all619 tests;
restore correction committed as `d2a659756`. The subsequent full aggregate passed fast,
isolated and large Swift phases, then failed one Bridge topology replay WebKit case
(seven issues; nine sibling cases passed). PR routing uses the workspace command queue,
but that case had no executor. Its local fixture now installs the real executor, joins
the queue before each existing retirement drain, and cleans up on success/throw.
Astra verified all assertions and the other nine cases are unchanged. Correctly scoped
WebKit proof passed ten tests / two suites, exit0:
`/tmp/agentstudio-pr335-bridge-nested-authorized.log`. Earlier attempts selected zero tests
or failed SwiftPM sandbox setup; neither counts as passing proof. Full WebKit follow-up
and final committed aggregate remain required.
Final aggregate on the final committed correction remains required; no aggregate success is claimed.

## Prior bounded proof retained

These are prior observations, not a substitute for final-source proof:

- Startup cleanup: four pending sessions were still pending at 4:41 and completed by 5:13;
  original daemon/terminal processes were absent and the live pane remained owned.
- Six real close/Undo cycles retained pane/session identities and one surface/mount/host/
  renderer/I/O pair. Footprint 565→575 MiB; graphics fields stayed stable.
  `/tmp/agentstudio-pr335-renderer-{baseline,after-undo}.json`.
- Actual 300-second expiry: renderer/I/O/direct-child/mount/host counts zero, owned graphics
  0 MiB, footprint 165 MiB; one inert SurfaceView wrapper remained.
  `/tmp/agentstudio-pr335-renderer-after-expiry.json`. Historical sampler child count was labeled
  PTY although it counted all direct children; original zmx processes were checked separately.
- Restart preserved the exact saved deadline; real UI Undo restored original pane/session identity
  and a running shell variable. `/tmp/agentstudio-pr335-restart-deadline-{before,after}.txt`.
- Real zmx plus file-backed SQLite recovery deliberately omitted completion after Kill, reopened
  SQLite and reconciled; an actual replacement daemon remained alive. Seven tests / three suites
  passed with hosting corrections: `/tmp/agentstudio-pr335-recovery-and-tabproof.log`.
- A deliberately detached test service survived original-session cleanup; it was later retired by
  its exact verified process identity. No unrelated process was signaled.
- Existing-policy parity correction passed 66 tests / five suites and advisor review: single hidden
  pane closes preserve main's Undo eligibility, whole-tab/last-pane Undo remains available, and
  unavailable closes do not consume capacity. `/tmp/agentstudio-pr335-close-policy-parity.log`.

## Open native observations

The busy drawer journey retired native surfaces after its real close grace. Renderer/I/O/direct
child/mount/host counts reached zero; footprint 186 MiB, owned graphics 5.672 MiB, two inert
wrappers. Native free durations were 162.29 ms and 34.752 ms. The 162 ms MainActor pause is a
measured limitation, not a worst-case responsiveness guarantee.
`/tmp/agentstudio-pr335-renderer-after-busy.json` and `...-busy-native-free.jsonl`.

One recorded session remained `pending/processUnverifiable`. The sampled unchanged zmx daemon
was in `main.Daemon.ensureSession → __wait4` with an exiting shell; process inspection returned
ESRCH for the shell while it was still listed. `/tmp/agentstudio-pr335-pending-daemon-sample.txt`.
Revalidate current process identities before further observation. Do not mark completion from
uncertainty, introduce process supervision, or alter vendors to resolve it.

First Add Drawer Pane showed a blank overlay despite a created child surface/socket and initial
output. Collapse/reopen displayed the prompt and focus. Creation had nonempty geometry; the cause
remains unproven. Compare actual first-open host/window/frame/visibility/focus using existing restore
trace and an isolated current debug app. A later locked GUI observation does not explain the earlier
blank drawer. Candidate 98546 retired gracefully. Candidate 94273 launched from the newly compiled shared-input
build, marker `debug-observability-lbim-1788919635-93643`; its standard observability verifier passed.
Current empty baseline: 103 MiB, zero surfaces/mounts/hosts/renderer/I/O/direct children/owned graphics.
This is not a cycle proof. Subsequent aggregate work relinked the build output, so refresh the final
candidate after gates. Exact PID/window capture explicitly reports the macOS GUI session locked;
unlock request is pending. Target exact PID/path, never production by name.
Fresh capture on 2026-09-09 at 03:52Z still reports locked GUI. The same candidate's
03:54Z idle sampler reports 97 MiB, zero surfaces/mounts/hosts/renderer/I/O/direct children
and owned graphics, with no capture errors: `/tmp/agentstudio-pr335-empty-idle-followup.json`.
This is an idle follow-up, not final-source cycle or drawer proof.

## Current process-mechanism boundary

Fresh sampling at 22:13 confirms the same daemon still in wait4 with PTY master fd6 open;
the child remains in exiting state. Pinned zmx shutdown calls handleKill, then waits for the
child before closing that descriptor. The daemon has left its protocol loop, so normal retries
cannot finish this state. The exact child/kernel dependency is unproven. Do not relax process
inspection and call this resolved. A verified out-of-band retirement fallback is a new mechanism;
user concurrence was requested and remains pending. No such fallback, PID signal or vendor
change has been applied. Local evidence: `tmp/debug-workflows/2026-09-08-pr335-native-wrapup/`.

## Execution discipline and history

Fresh Astra verified the applied cleanup and subsequent fixture corrections in
`tmp/pr335-relevance-audit/applied-cleanup-review.md`; original scenarios/assertions and suite
identities remain. The user explicitly resumed applying/resolving the audited candidates and remaining proof issues.
This is continuation of the reviewed tree, not a new design cycle. Historical implementation
remediation count remains unknown; do not invent a zero count or rely on superseded plans.
Use scenario-led tests, preserve assertions and suite isolation, use one build slot sequentially,
and run `mise run test` before PR updates. Diagnose source/log evidence before changing behavior.
A genuine ownership/contract break returns to the user; ordinary scoped corrections continue.

Historical requested records remain:
[initial review](2026-09-07-app-only-reliability-audit/astra-full-review.md),
[pruning review](2026-09-07-app-only-reliability-audit/astra-pruning-review.md),
[takeover history](2026-09-07-app-only-reliability-audit/takeover-state.md), and
[tree review](2026-09-07-app-only-reliability-audit/astra-wrapup-tree-review.md).
They record earlier errors and proof boundaries; they do not override this scope or current source.
