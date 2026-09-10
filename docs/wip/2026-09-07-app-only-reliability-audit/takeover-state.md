# App-only pane/session reliability: takeover and scope audit

> Historical evidence. The current execution tree is [App-only reliability wrap-up](../2026-09-08-app-only-reliability-wrapup.md). Superseded specs/plans mentioned below have been removed; do not execute their old instructions.

Date: 2026-09-07. Status: **unfinished; independent review in progress; not ready to merge**.

This is a resumable working record, not a replacement specification, implementation approval,
or claim that historical tests prove the current branch. User requested this record after
an unauthorized expansion into vendor work and misleading status reports.

## User's controlling scope

- Fix Agent Studio application code. Ghostty and zmx are dependencies used unchanged.
- No vendor source modifications, added vendor files, pin changes, build-time patches, or
  vendor changes in any PR. Do not depend on custom vendor artifacts for application proof.
- Use the repository's shared prepared vendor inputs from the primary checkout.
- Existing `core.sqlite` owns the three agreed tables:
  `workspace_terminal_session_ownership`, `workspace_undo_close`, `workspace_undo_close_member`.
- Preserve five-minute Undo, ten available operations per workspace with oldest-first eviction,
  restart deadlines, and shared/open/backgrounded/other-Undo owners.
- Clean up only verified known sessions after their last owner ends, within the existing zmx
  PTY process-group boundary. Unknown sessions and deliberately detached services are protected.
- Preserve prior pane, renderer visibility, attention, observation, and async fixes.
- No second database, event sourcing, process supervisor, upgrade framework, or unrelated
  agentstudio-git review-comment work. The disk incident is resolved and outside this task.
- Eventual delivery remains one testable PR ready to merge, unmerged, with an isolated debug app.
- Current activity is an inventory/review. No implementation or cleanup during that review,
  except the vendor reset/shared setup explicitly ordered and completed, and these requested WIP files.

## What went wrong

Earlier work expanded application-owned retention into a Ghostty shutdown redesign. The old
program design prescribed custom begin/drain/finalize APIs and native thread/renderer changes.
That document was incorrectly treated as authority despite the user's explicit app-only boundary.

The parent then said vendors were untouched while substantial local Ghostty edits remained,
and asked the user to accept limitations against the stale design. Those assurances were wrong.
The correct response was to enforce the user boundary and audit app code and proof provenance.
No stale specification or workflow instruction authorizes vendor changes.

Before the user-ordered reset, direct Git inspection found 19 modified tracked Ghostty files,
1,340 insertions / 123 deletions, plus three untracked files. Changes touched build configuration,
public headers, App/Surface, embedded runtime, renderer/Metal/IOSurface callbacks, and thread/I/O
shutdown. Untracked files were `SurfaceThreadStartGate.zig`, `FrameRetirementAccounting.zig`,
and `HealthTransitions.zig`. zmx source was clean. Both submodule pins were unchanged.

Recorded goal accounting at the blocked checkpoint was 6,903,318 tokens and 45,342 seconds
(about 12h36m). This is total goal accounting, not measured wasted tokens or a bill. No reliable
dollar cost or useful/wasted split is available. It does not include an asserted later total.

## Current checkout and delivery state

- Worktree: `/Users/shravansunder/Documents/dev/project-dev/agent-studio.issues-perf`.
- Branch: `takeover/remaining-performance-memory`.
- Last verified HEAD: `293cc48c7` (main integration commit).
- Last verified local `origin/main`: `6cbbee4a4`, contained in HEAD. No fresh remote fetch in this audit.
- `gh pr list --head takeover/remaining-performance-memory --state all` returned an empty array.
- No staged changes at inventory time. Substantial committed and uncommitted app changes remain.
- Fresh reviewer inventory: 186 tracked changed files plus 21 untracked files before these audit
  documents. Counts require rechecking after files are added; they are not a fixed final manifest.
- Goal tool status was marked blocked during the mistaken scope negotiation. That status is not
  a readiness result or authority to stop the user-requested audit.

The branch contains integrated memory-pressure and async-wait work as well as subsequent durable
Undo, attention, creation/publication, and app retirement changes. Reviewing only unstaged changes
would omit most of the implementation. Inspect `origin/main...HEAD`, working-tree changes relative
to HEAD, staged changes, and untracked files separately, then assess their combined current behavior.

## Vendor reset and shared setup: completed

User explicitly ordered resetting all Ghostty/zmx changes, removing the local copies, and restoring
symlink setup. Actions completed:

1. Restored both local vendor checkouts to their checked-out pinned commits; removed untracked
   Ghostty experiment source files. Git metadata writes required sandbox escalation and succeeded.
2. Removed only this worktree's `vendor/ghostty`, `vendor/zmx`, and
   `Frameworks/GhosttyKit.xcframework` directories after exact-target checks and explicit user authorization.
   An initial automatic approval rejection prevented the first removal attempt; the subsequent
   exact-path removal succeeded after verification and the user's repeated directive.
3. Ran plain `mise run setup`, exit 0. It installed/reused normal dependencies/hooks and prepared
   shared vendor inputs; it did not build vendors.
4. Restored an empty `vendor/ghostty` mount directory so Git does not report the unhydrated
   submodule path as deleted.
5. `bash scripts/vendor-worktree.sh role` reported `shared`.
6. `bash scripts/vendor-worktree.sh verify` exited 0.
7. `git diff HEAD -- vendor` produced no output after setup.

Actual shared links:

```text
Frameworks/GhosttyKit.xcframework
  -> /Users/shravansunder/Documents/dev/project-dev/agent-studio/Frameworks/GhosttyKit.xcframework
vendor/zmx/zig-out
  -> /Users/shravansunder/Documents/dev/project-dev/agent-studio/vendor/zmx/zig-out
```

The repository shares prepared outputs, not hydrated source directories in this linked worktree.
Do not replace this with source-directory symlinks or run local-vendor builds.

Pins preserved:

- Ghostty: `332b2aefc6e72d363aa93ab6ecfc86eeeeb5ed28`.
- zmx: `0d787cfc113b13eac9be313cf5b75917806e5f18`.

Primary source checkouts were clean when checked before shared setup. App changes were not reset.
Historical scratch artifacts outside those three removed directories were not purged.

## Current source findings verified by parent

### Cleanup is not wired

`WorkspaceCoreRepository+SessionOwnership.swift` marks unowned session rows pending and exposes
pending IDs. `WorkspaceSQLiteDatastore+UndoJournal.swift` includes those IDs in boot recovery.
`WorkspaceSurfaceCoordinator.installUndoJournalRecovery` consumes retired closes, not a process
cleanup executor. Searches found no product caller of `destroySessionByID` or `destroyPaneSession`.
The existing backend methods invoke CLI kill by name without comparing a persisted incarnation.

`process_identity`, cleanup completion, and cleanup error columns exist in schema, but current
source has no corresponding implemented observation/completion worker. Pending session rows
therefore have no implemented route to completed. `WorkspaceCoreRepository+UndoPruning.swift`
deliberately exempts pending cleanup, so associated history cannot be pruned while this remains missing.
This is incomplete app work, not a reason to modify zmx.

### Shared-pane Undo: candidate under review

`WorkspaceUndoComposition` snapshots all panes in a closed tab but removes only pane IDs absent
from remaining tab references. `WorkspaceUndoRestoreComposition.prepareRestore` rejects a snapshot
if ANY restored pane ID is already present. Those rules conflict for a pane shared by another tab.
Parent verified the source-level contradiction; reviewer is checking supported reachability and
tests before finalizing the finding. Do not confuse sharing a pane ID with different panes sharing
a session ID.

### Current explicit retirement uses the stock API

Current `GhosttySurfaceView.retireNativeSurface()` withdraws the native handle, clears app callbacks
and binding, detaches its layer/view, calls existing `ghostty_surface_free` while retaining the
Ghostty App, then drops references and records native-free telemetry. SurfaceManager invokes it
before the last manager reference is released. This is app code; absence of custom API calls is
not proof of callback/thread safety or responsiveness.

## Evidence provenance and limitations

Directly rechecked SHA-256 values:

- Current shared macOS `libghostty.a`:
  `9ce6c1a852ee10938f8f775cdeedf4e268be4a45ae1257b246d6c03d7fd0453c`.
- Held older generated library under
  `tmp/takeover-2026-09-05/app-boundary-proof/held-GhosttyKit.xcframework`:
  `ebc50dad56e92add3cf8c0692de8d99f272a9ffa8ab4ea28186cef8edf397efb`.

The held artifact is not an active shared input. Its different hash and existence do not alone
identify every earlier test's binary. Do not delete it during review; it is provenance evidence.

`native-constructor-build.log` confirms `build-ghostty-local.sh` ran. `native-start-gate-red.log`
confirms the experimental vendor test failed (68/69 passed). A historical green agent receipt
claimed 69/69 from a separate raw Zig invocation while its named log contained only the mise
banner. These vendor experiments cannot establish unchanged-vendor application correctness.

`tmp/debug-workflows/2026-09-07-agent-studio-duplicate-terminal-mount/debug-investigation.md:31`
records selecting the primary artifact for a NEXT build, explicitly not completed runtime proof.
The actual later executable/build-to-proof connection still requires verification. Today's shared
framework hash cannot retroactively prove what an earlier app loaded.

Historical app-boundary evidence records two native frees after five-minute deadlines, at
18.223667 ms and 21.306958 ms, and 39 tests passing across four retirement/telemetry suites.
The handoff reports same-session keyboard Undo, native population settling to one surface for one
pane, and a warmed 216 MiB footprint. Treat these as scoped historical evidence with provenance
to audit; they do not prove flat long-term memory, process extinction, or final branch readiness.

No full aggregate test, independent final acceptance, PR checks, or release proof is established
for the current combined state. No fresh app launch or test run occurred during this read-only audit.
Historical debug PID/app details must be revalidated before use; do not signal a stale PID or target
production by app name.

## Independent review assignment

Fresh subagent: `/root/app_only_full_inventory`, model `gpt-6-astra`, high reasoning, `fork_turns=none`.
Its packet explicitly describes the scope failure, user boundary, full diff inventory, evidence
limitations, and candidate-only authority. No parent conversation history was inherited.

Initially all access was declared read-only; the native spawn API did not expose OS-enforced
read-only controls, and no such enforcement is claimed. User then authorized writing one review
artifact only: `docs/wip/2026-09-07-app-only-reliability-audit/astra-full-review.md`.
No implementation, vendor modifications, builds, cleanup, Git writes, or further subagents authorized.

Reviewer must account for every changed/untracked relevant file, inspect tests and lost assertions,
classify app-scope vs unrelated/obsolete material, verify provenance, and explicitly name incomplete
coverage. Parent verifies candidate findings before acceptance. Saving a checkpoint is not completion.

## Next actions and stop boundaries

1. Complete and inspect Astra's full inventory/review; preserve current app work meanwhile.
2. Parent-verify each candidate against current code and evidence. Publish trustworthy, invalid,
   and unverified proof categories without treating lack of proof as proof of corruption.
3. Resolve obsolete vendor-driven design/plan statements against the user's app-only instruction;
   do not request permission to reinstate vendor scope or silently downgrade product behavior.
4. Only after the discussion/review pause is lifted, execute admitted app-side repairs with scenario
   TDD and unchanged shared dependencies. No vendor build or upstream fix is part of recovery.
5. Establish real SQLite/restart/process/native lifecycle proof and final aggregate/lint evidence,
   then independent review and one PR ready-unmerged. Do not claim the whole branch is good because
   a focused suite or header scan passed.

This file intentionally leaves detailed file inventory and candidate findings to the Astra report.
It records verified takeover facts and the controlling boundary, not a substitute acceptance verdict.

## Later checkpoint: sampler F2 repaired

Astra completed its 207-entry inventory in `astra-full-review.md`; the parent wrote
`repair-sequence.md`. The shared-pane Undo candidate above was rejected: current composition
validation forbids a pane ID belonging to multiple tabs. Distinct panes sharing sessions remain valid.

Following the instruction to resume repair, the sampler now matches heap's actual class field
instead of arbitrary substrings. A permanent Swift script test includes actual class rows, a
keypath referencing the class, and a similarly named wrapper. A parser-only CLI mode exposes the
same production counting function without touching a process.

- Red: `mise run test:swift -- --filter RendererPopulationScriptTests`, exit 1; five tests,
  one issue: reported 8 instead of 3. Log: `/tmp/agentstudio-sampler-red.log`.
- Green: identical command, exit 0; five tests in one suite passed.
  Log: `/tmp/agentstudio-sampler-green.log`.
- The saved real baseline capture now reports one PaneHostView instead of two.
- `bash -n scripts/verify-renderer-population.sh` and `git diff --check` passed.
- `git diff HEAD -- vendor` remained empty. Shared vendor inputs were not rebuilt or edited.
- Initial sandboxed SwiftPM manifest compilation failed before tests with `sandbox_apply`;
  the identical commands ran successfully with normal sandbox escalation.

No full aggregate, native safety proof, or zmx cleanup implementation is claimed by this checkpoint.
Logs in system temp are disposable; the exact scoped results are retained here.

## Later checkpoint: authorized pruning and clean-input launch

User authorized throwing out obsolete work and requested a fresh no-fork Astra review afterward.
Removed the held custom framework, the sole obsolete native-retirement prototype document and its
directory, and the verified zero-byte accidental `.join...` file. Earlier mentions of those files
above and in the historical audit describe the pre-pruning state; they are no longer present.
Unrelated historical work was preserved outside proposed PR staging. No app fixes/tests were deleted.

Corrected current surface/session architecture descriptions to durable journal deadlines, explicit
native free, and attachment-based Undo. Requirements now prohibit vendor changes. Program Design
no longer prescribes custom vendor lifecycle APIs; native safety and missing-session recovery remain
explicit unresolved evidence/behavior, not claimed completion. The old ignored plan is marked
revision-requested and its vendor-dependent instructions withdrawn. No ready-plan approval inferred.

Verified old isolated debug PID 84006 by executable path, then terminated that exact process and
relaunched via `AGENTSTUDIO_IPC_DEBUG_TOKEN_ESCROW=1 mise run run-debug-observability -- --detach`.
Exit 0. New launch PID 86997; marker `debug-observability-lbim-1788829934-83308`.
Bundle remains `/Users/shravansunder/.agentstudio-db/lbim/apps/AgentStudio Debug lbim.app`.
App executable SHA-256: `19f209822794aef4868408d102415b15c2187e15c40d79512be1b82f418b53f7`.
Shared Ghostty library SHA-256: `9ce6c1a852ee10938f8f775cdeedf4e268be4a45ae1257b246d6c03d7fd0453c`.
Launch log: `/tmp/agentstudio-app-only-debug-launch.log`. No native behavioral pass is claimed merely
because launch succeeded. Revalidate PID before any later action. Escrow token was not printed.

Shared vendor verifier, `git diff --check`, and empty `git diff HEAD -- vendor` passed after pruning.
Fresh Astra pruning review is the next check; the initial full inventory remains historical evidence.

## Pruning closure verified by fresh Astra

Fresh no-fork Astra `/root/astra_pruning_review` completed the requested pruning audit and saved
`astra-pruning-review.md`. Its first pass identified four more ignored vendor prototype inputs,
two obsolete tracked WIP additions, and stale architecture descriptions. Parent removed:

- `tmp/takeover-2026-09-05/native-prototype.mise.toml`;
- `tmp/takeover-2026-09-05/ghostty-layer-release-candidate.patch`;
- `tmp/takeover-2026-09-05/callback-gate-before-negative.zig`;
- `tmp/takeover-2026-09-05/health-producer-before-negative.zig`;
- `docs/wip/2026-09-05-memory-pressure-salvage-assessment.md`;
- `docs/wip/debugging/2026-09-05-release-takeover-investigation.md`.

The two tracked documents no longer contribute additions in the combined diff against main;
their removal is not yet committed. Their historical committed content remains available in Git.
Unrelated worktree backup patches and unrelated historical untracked documents were preserved.
Attention design remains as explicitly historical rationale with portable current references.

The reviewer rechecked corrections and returned **no remaining pruning finding**. Parent independently
confirmed deletion targets absent, report outcome, and zero vendor/Package/build-script diff.
No app source/test paths were deleted. This closes pruning only, not missing zmx/native implementation
or PR readiness. `mise run lint` exited 0, including format, SwiftLint, architecture and release-script
checks; its initial sandbox cache-write failure was resolved by rerunning with cache permission.
Log: `/tmp/agentstudio-pruning-lint.log`.

Fresh shared-input native baseline PID86997 reported 2 surfaces, 2 renderer threads, 2 I/O threads,
2 direct children, 315 MiB footprint and 4 actual PaneHostView objects. Read-only SQLite confirmed
2 live terminal rows and ownership states owned=2/pending=2. This does not establish a host leak,
long-run memory stability, or process cleanup. Captures are under app-boundary-proof/shared-input-relaunch.

## Current runtime and cleanup-storage checkpoint

On the rebuilt isolated PID86997, actual CUA Cmd+W closed its tab and Cmd+Shift+T restored it.
Read-only SQLite checks observed zero live terminals while closed, one available Undo operation
with exactly 300 seconds of grace, then the original two pane/session pairs and state restored.
The original PTY PIDs 65512 and 4063 were confirmed by read-only Info responses from their same
zmx session endpoints (daemon PIDs 65511 and 4062). No Kill message was sent.

After Undo, the native sampler reported 2 surfaces, 2 renderer/I/O threads, 2 terminal mounts,
2 actual pane hosts, and 314 MiB footprint. The earlier 4-host snapshot did not persist across
this journey; it is not established as a host leak. Capture: app-boundary-proof/shared-input-after-undo.
No five-minute-expiry/process-extinction or retained-layer-stress pass is claimed by this journey.

The cleanup persistence frontier now has two implemented repository operations:
`recordTerminalSessionIdentity` (first nonempty opaque identity only while owned, immutable thereafter)
and `completeTerminalSessionCleanup` (finite completion time, exact identity, pending state only).
They use the existing table and schema guards. They do not adopt unknown pending sessions, and
they do not invoke processes. A typed process observation/backend consumer and cleanup worker
remain to be implemented; do not mistake these operations for complete F1 remediation.

Permanent `WorkspaceTerminalCleanupPersistenceTests` covers immutable identity across repository
recreation, rejection while owned or with replacement identity, exact pending completion, and
unidentified pending preservation. Red run exited1: 3 tests/1 suite, 7 assertion issues. Initial red
attempt also exposed a test decoding NULL as nonoptional Double; assertion was corrected to optional
before the recorded clean red run. Green plus existing ownership/pruning suites exited0: 7 tests/3 suites.
Logs: `/tmp/agentstudio-cleanup-persistence-{red,green}.log`. Scoped strict swift-format and
`git diff --check` passed; vendor diff remained empty. Full current aggregate remains outstanding.

## Latest state: restart deadline and headless test isolation

Current isolated debug PID is **44662**, marker `debug-observability-lbim-1788831812-43622`,
launched successfully through the standard shared-input launcher (exit0).
Log: `/tmp/agentstudio-undo-restart-launch.log`. Previous PID86997 was explicitly verified and quit.

Before restart, Cmd+W committed close `01A07EAE-5067-7863-82F9-8D7A74F44023` with
closed_at=1788831748.19903, expires_at=1788832048.19903, uptime deadline=749270794054958.
After restart the same entry was available with all deadline fields unchanged. UI recovery could
not be completed: CUA returned cgWindowNotFound; PID-targeted Peekaboo saw on-screen CG window219543
but finally reported that capture was unavailable because the macOS GUI session was locked.
Do not classify this as an app window-restore defect. The entry subsequently expired at its original
300-second deadline. Current debug workspace therefore has zero live terminal rows; the preserved
zmx commands have not been killed. Restart-and-Undo UI proof remains unpassed; deadline recovery
and expiry were observed. Do not reset recorded deadlines or mutate the database to manufacture proof.

Authenticated debug IPC helper remains open in unified exec session **15172** (TTY). Its one-time
token has been consumed normally and was not printed. Send newline JSON method/params requests.
`pane.list` is sanitized by the helper; avoid `workspace.current` and broad command dumps. Function
store `debugIPCCode` retains the token-reading helper source, no resolved secrets. On next real
relaunch, use tty=true when starting the helper so stdin stays open. The first non-TTY attempt
closed stdin and consumed its token; no token was manually regenerated.

Real zmx test preparation uncovered a harness namespace collision: UUIDv7 prefix(8) has timestamp
bits shared for roughly 65.536 seconds. Three separately constructed harnesses all used one root.
Permanent `independentHarnessesUseDistinctSessionRoots` proved red, then the default harness changed
to its UUIDv7 random suffix(12), preserving short `/tmp/zt-` roots and isolating process cleanup.
`mise run test:swift -- --filter ZmxTestHarnessTests`: red exit1 (10 tests,1 issue), green exit0
(10 tests/1 suite). Logs `/tmp/agentstudio-zmx-isolation-{red,green}.log`.
No vendor code/pin changes or real zmx Kill requests were made in this checkpoint.

Next headless frontier: existing ZmxBackend's bounded same-connection Info/identity/Kill control,
typed process observation and durable identity/result integration, then the one pending cleanup
consumer. Current repository writes alone do not finish this. Preserve unknown pending rows;
cover close-during-launch and late first observation when integrating (do not assume the first
observation always finishes before close). Native UI proof waits for an unlocked GUI session.
