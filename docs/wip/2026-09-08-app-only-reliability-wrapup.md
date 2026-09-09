# App-only reliability: current wrap-up tree

**Goal:** one independently reviewed Agent Studio PR, ready to merge but unmerged,
with an isolated debug app the user can test. Worktree: `agent-studio.issues-perf`;
branch: `takeover/remaining-performance-memory`; PR:
https://github.com/ShravanSunder/agentstudio/pull/335.

Relevance audit HEAD: `95f3c3e44`; audit base: `6cbbee4a4`. Final product corrections
through `d087c8338` have passing mandatory aggregate and bounded independent review.
Always refresh external PR state before merge readiness; recorded refs are not live status.

## Current MainActor correction (2026-09-09)

Read-only inventory of base `6cbbee4a4` through `6d822123a` enumerated all 85 changed
source files and traced the high-risk paths. Parent verified repeated full visibility
reconciliation after each bulk detach, repeated active-tab composition per surface,
and attention FIFO head shifting. Native Ghostty calls retain their supported
MainActor contract; no vendor/API change is authorized. SQLite/zmx I/O and both
deadline sleepers already run off-main. Await duration is not actor occupancy.

Correction: preserve immediate per-surface hide/focus-off while batching bulk membership
publication; compose the active tab once per reconciliation; transfer ordered attention
batches without shifting the array per control. No new worker, persistence boundary,
ownership policy or framework. The historical 162.29 ms sample covers the whole
retirement wrapper, not isolated `ghostty_surface_free` time.

Final-head CI run `34349794864` failed in the Swift fast lane: the filesystem fixture
at `WorkspaceSurfaceCoordinatorTests+Filesystem.swift:320` exhausted a private
200-yield loop after 28 ms. Both overloads ignored their timeout argument. They now use
the existing shared bounded state wait with the exact predicates preserved. Detailed log:
`tmp/pr335-wrapup-proof/final-head-ci-failed.log`. All other jobs passed. Local
aggregate on `6d822123a` passed before these corrections; fresh gates remain required.

Correction proof:

- Bulk red: 20 notifications instead of one. Green: one final notification, all 20
  immediate hide/focus-off deliveries, repeated no-op close emits nothing.
- Six separate focused Swift processes passed, exit 0: 56 tests (3 integration,
  6 visibility, 16 delivery, 2 retirement, 10 attention, 19 coordinator). Includes a
  257-transition blocked attention backlog, later batch, cancellation and restart.
  `mise run lint` passed, exit 0; fresh no-history Astra review found no findings.
- Corrected debug PID 62159, marker `debug-observability-lbim-1788959709-61543`,
  executable UUID `9B745931-5FF4-3F8F-B3AE-583B0F3DA97C` matches tested build and bundle.
  Standard debug observability verifier passed. Same isolated data/session roots.
- Native comparison: same disposable four-pane tab, ten close/Undo pairs and ten
  tab-switch pairs on each build. Every Undo restored four panes. Both windows ended
  with 13 live/managed renderers and no orphan candidate. Across 40 emitted reconciliations
  per build, p95 improved 0.284125→0.02025 ms; maximum 0.318792→0.022167 ms.
  Tab-bar totals were 19.36→18.99 ms; sidebar capture totals 22.86→22.79 ms.
- Broad CPU windows were 15.10 CPU seconds/41.04 wall seconds before and 30.76/60.28
  afterward. They include unequal automation gaps and background work and do not prove
  whole-app CPU regression freedom. The sampled switch workload spent 10,727/12,350
  MainActor samples in its event-loop wait; 1,102 traversed accessibility hierarchy
  copying. The changed visibility functions were not sampled. This does not erase the
  CPU observation or establish a universal latency bound.

Evidence: `tmp/pr335-wrapup-proof/mainactor-*` logs, native windows, comparison,
population, and independent-review receipts. Final mandatory aggregate and hosted gates
must be evaluated against the eventual pushed head; the PR owns current delivery status.

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

## Execution tree and delivery gates

Product code and tests are committed and pushed through `d087c8338`. The required local
aggregate passed on that head. GitHub checks and review-thread state must always be
re-fetched for the current PR head before declaring merge readiness; the PR is the live
CI status source, not this dated proof record.

```text
ONE APP-ONLY PR — STOP READY TO MERGE, UNMERGED
├── Scope and contents — verified
│   ├── Shared vendor inputs restored; no Ghostty/zmx source, pins or setup changes
│   ├── Superseded branch-local design material pruned; historical evidence preserved
│   ├── Frozen 210-file / 779-hunk relevance inventory independently checked
│   └── Unused members/defaults/copy removed; existing test scenarios preserved
├── Product behavior — implemented and reviewed
│   ├── Immediate durable pane/session IDs before publication and launch
│   ├── Three-table close/Undo journal, 300s deadlines, capacity 10, restart/shared owners
│   ├── Five-minute startup gate, identity-verified cleanup, retry and history pruning
│   ├── Extinct-process reconciliation leaves stale/replacement endpoints untouched
│   ├── Native retirement, visibility/focus and observation/attention corrections
│   └── First-open drawer host publication keeps stable SwiftUI pane identity
├── Proof — evidence below, with limits stated
│   ├── Full mandatory mise run test passed; normal commit hooks passed
│   ├── Controlled drawer red/green, early/late registration and real host replacement
│   ├── Actual unlocked first drawer mounts without collapse/reopen
│   ├── Final-build Undo retains original pane/session IDs and shell variable
│   ├── Actual 300s expiry removes test daemon/shell/socket and returns native counts
│   └── Optional full zmx suite has a separate test-harness cleanup-timeout limitation
└── Delivery
    ├── Scoped commits pushed to PR #335; main 6cbbee4a4 integrated
    ├── Current shared-input debug app verified and available for user testing
    ├── Required final gate: matching-head CI, comments/threads, mergeability and quiet re-fetch
    └── No merge, tag or release performed or implied
```

## Final proof record

- Required `mise run test` on `d087c8338`: exit 0. Includes Swift lint (zero violations),
  architecture, BridgeWeb, marketing site, fast/isolated/large Swift, 244 WebKit tests
  and six aggregate E2E tests. Log: `tmp/pr335-wrapup-proof/merge-candidate-aggregate.log`.
- Existing command fixtures now await their real queue; durable fixtures use prepared
  SQLite and join shutdown. The default test convenience store allocated an **unprepared**
  datastore, not absent SQLite. No assertions or runner isolation rules were weakened.
- First-open drawer root cause: outer identity changed with slot.host availability while
  the child also observed that slot and returned the same cached AppKit container.
  Removing the redundant outer identity preserves stable pane identity and the existing
  host-instance replacement identity. Actual DrawerPanel/window regression: early host
  registration passed and late registration failed before; both passed after. Replacement
  and retirement/slot coverage passed 26 tests / 4 suites. Earlier inconclusive controller
  harness experiments were discarded. Native first-open drawer attached and displayed
  terminal content without an agent collapse/reopen. Astra reviewed the final delta.
- Extinct-session regression: observe a real zmx daemon/leader, retire normally, verify
  process-family extinction, leave a bound-then-closed Unix socket, reopen pending SQLite,
  retry cleanup. Old code threw unavailable; corrected code completes and preserves
  socket inode. Identity, ownership, native-attachment and replacement guards remain.
  Initial identity fixtures wait for an actual daemon response rather than socket existence.
- Optional real-zmx suite limitation: scenario assertions passed, but some full-suite exits
  failed in the unchanged harness's0.5-second CLI cleanup timeout, including an empty root.
  These runs are not claimed green. Exact leftovers were inspected; the one remaining
  test session received normal zmx kill in its isolated root, followed by empty inventory
  and absent PID. No timeout inflation, gate change or vendor workaround was made.
  Relevant logs: `stale-socket-red-compiled.log`, `stale-socket-green.log`,
  `stale-socket-final-focused.log`, `verified-cleanup-scoped-proof.log` under the proof folder.
- Final debug PID 47414: standard isolated launch, observability and signature verification
  passed. Tested executable and app bundle UUID: 435467AD-60C2-3BC1-8A87-8B60664397BC.
  Marker: debug-observability-lbim-1788953664-46748. Source/input identity is frozen to
  the tested build; later documentation changes do not require replacing its executable.
- Final native cycle used a newly created test-only tab. Undo restored the original pane
  and session IDs, and the shell printed `PR335_UNDO=retained`. Second close recorded an
  exact 300s deadline. Before expiry: available/owned. After expiry: expired/completed,
  original daemon 60448 and shell 60449 absent, socket absent. Other five sessions stayed owned.
  Evidence: `real-expiry-start.json`, `undo-restored-identity.json`, `undo-retained-shell.png`,
  `real-expiry-result.json` in the proof folder.
- Native counts during grace→after expiry: surfaces6→5, renderer/I/O6→5, mounts5→5,
  hosts5→5. Footprint 1099→919 MiB, compared with 918 MiB before the extra pane. This proves
  the measured cycle, not zero leaks in every workload. Graphics residency remains vendor
  dependent. Captures: `before-expiry-renderers.json`, `after-expiry-renderers.json`.
- The historical wedged debug daemon/child disappeared during external cleanup; its
  journal row later completed on the prior build. Do not attribute that event to the new
  reconciliation fix. No forced-retirement mechanism was added. Unverifiable live sessions
  continue pending under the accepted safety policy.

## Debug app and short user checklist

App: `~/.agentstudio-db/lbim/apps/AgentStudio Debug lbim.app`.
Bundle ID:`com.agentstudio.app.debug.dlbim`; data:`~/.agentstudio-db/lbim`;
zmx root:`~/.agentstudio-db/lbim/z`. Production and beta remain isolated.

Standard launch from this worktree: `mise run run-debug-observability -- --detach`.
The existing shared collector must be available; the launcher refuses duplicate instances.
For a prepared current build, the verified invocation used `--skip-build --build-path .build-agent-1`.

1. Open a new terminal and add its first drawer: prompt/content should appear immediately.
2. Switch tabs, toggle drawer, Zoom and minimize/restore: existing terminal state should survive.
3. Set a shell variable, close its tab, then Undo within five minutes: same session and variable.
4. Close a disposable tab and leave it closed beyond five minutes: its processes should end;
   live/backgrounded/Undo-owned panes remain protected.

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

## Historical limits and preserved records

Earlier busy native frees measured162.29 ms and34.752 ms; this is not a worst-case latency
bound. A shutdown-stalled vendor daemon was observed historically; no vendor change or
forced process mechanism is part of this PR. Old `/tmp` captures may have been removed by
user disk cleanup; current proof is retained under checkout-local ignored
`tmp/pr335-wrapup-proof/`. Disk cleanup was performed by the user, not attributed to an
inferred agent cause.

Four requested historical records remain unchanged:
[initial review](2026-09-07-app-only-reliability-audit/astra-full-review.md),
[pruning review](2026-09-07-app-only-reliability-audit/astra-pruning-review.md),
[takeover history](2026-09-07-app-only-reliability-audit/takeover-state.md), and
[tree review](2026-09-07-app-only-reliability-audit/astra-wrapup-tree-review.md).
They do not override the current scope. The 14 unrelated untracked historical WIPs remain
untouched. Relevance accounting is not a whole-PR correctness or leak-free certification.
