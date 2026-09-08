# Astra fresh pruning review

> Historical evidence. The current execution tree is [App-only reliability wrap-up](../2026-09-08-app-only-reliability-wrapup.md). Superseded specs/plans mentioned below have been removed; do not execute their old instructions.

Date: 2026-09-07. Result: **requested pruning verified; no remaining pruning finding**.
The named and subsequently identified deletions succeeded. The application/build boundary contains no vendor delta. This is
a complete candidate-only review of the requested pruning boundary, not product acceptance.
The parent must verify and disposition these candidates. No source, test, vendor, configuration,
Git, build, or process state was changed by this reviewer. This report is the sole authorized write.

## Snapshot and authority

- Branch: `takeover/remaining-performance-memory`.
- HEAD: `293cc48c7f57c3835bfb42b467eafc71355eaa67`.
- Local `origin/main`: `6cbbee4a4422c25b10c1bcf1c6a511f5393a0b0c`; no fetch performed.
- Final rechecked combined tracked diff: 184 paths; 23 untracked paths including this report; index empty.
- User boundary: app-only pane/session reliability, unchanged Ghostty/zmx, preserve the durable
  three-table journal, 300-second grace, ten-close capacity, restart and other owners, and existing
  pane/visibility/attention/observation tests. Remove obsolete work without throwing away unrelated
  work backups. No full runtime review or proof generation authorized in this lane.
- Read `AGENTS.md`, the initial [207-entry review](astra-full-review.md),
  [takeover state](takeover-state.md), `repair-sequence.md` (subsequently removed as superseded), current reliability
  Requirements/Specification/Program Design and withdrawn ignored implementation plan.
- The plan explicitly says `revision-requested`. Formal implementation acceptance remains
  `blocked-input`; the direct pruning request independently authorizes this inventory/review.
  No remediation count or ready-plan authority is inferred from historical receipts.

## Verified completed pruning

| Check | Current observation |
| --- | --- |
| Held custom framework | `tmp/takeover-2026-09-05/app-boundary-proof/held-GhosttyKit.xcframework` absent |
| Native prototype document | `docs/wip/2026-09-06-session-retirement/native-retirement-prototype.md` and its parent directory absent |
| Accidental filename | No root `.join...` artifact remains |
| Initial 207-entry ledger | 184 of 186 tracked paths remain changed; the two historical WIP additions were removed; 19 of 21 initial untracked paths remain; the only missing untracked entries are the named prototype document and accidental file |
| Newly inventoried paths | Four current audit documents: `astra-full-review.md`, `takeover-state.md`, `repair-sequence.md`, and this report |
| Accidental whole-file loss | No initial source/test path missing; no tracked deleted path in the combined `origin/main` diff |
| Vendor/pin/build boundary | Empty combined and committed-range diffs for `vendor`, `Frameworks`, `Package.swift`, `Package.resolved`, `.gitmodules`; empty `git diff HEAD -- vendor` |
| Shared outputs | Framework link points to primary `agent-studio/Frameworks/GhosttyKit.xcframework`; `vendor/zmx/zig-out` points to primary prepared output; local Ghostty mount is an empty directory |
| Pins | Ghostty `332b2aefc6e72d363aa93ab6ecfc86eeeeb5ed28`; zmx `0d787cfc113b13eac9be313cf5b75917806e5f18` |
| Root task delta | `.mise.toml` adds only the application renderer-population sampler; no new custom vendor build dependency |
| Active vendor prescriptions | Requirements now prohibit vendor changes; Program Design withdraws custom lifecycle APIs and marks native/missing-session uncertainty; ignored plan withdraws vendor mechanics and cannot be executed as ready |

The existence of ordinary pre-existing `build-ghostty-local.sh` / `--use-local-vendors` support in
the repository is not a new experiment dependency. Those paths have no relevant branch delta.
Searches found no custom lifecycle API calls or prototype-file references in app/source/test/build
registration paths. Historical references in audit documents are not executable wiring.

## Documentation correction: verified

The parent corrected the identified active descriptions during this review. Re-read the resulting
Requirements and architecture diffs against current source:

- Requirements now describes the journal, explicit stock native free, unfinished process executor
  and outstanding native proof. The old in-memory/deinit/native-prototype starting point is gone.
- Component architecture now describes durable Undo, atomic close/restore, attachment-based remount,
  and direct ownership commits separately from ordinary autosaves.
- Session lifecycle now names journal recovery, distinguishes its conceptual pendingUndo state from
  a live pane row, preserves ownership after native creation failure, and separates autosaves from
  direct ownership commits.
- Surface architecture's file table no longer assigns Undo expiry to the renderer-state extension.

These corrections match `WorkspaceSurfaceCoordinator.swift:178–180,406–426`,
`WorkspaceUndoComposition.swift:63–64`, `WorkspaceSQLiteSaveCoordinator.swift:172–233,262–300`,
`WorkspaceCoreRepository+UndoClose.swift:58–87`, and `GhosttySurfaceView.swift:487–517`.
The app-only native/missing-session uncertainties remain explicit; R8/R9/R10 were not weakened.

The final attachment-description correction is also verified: component architecture now names
current/most-recent attachment identity, consistent with `SurfaceManager.undoClose(forPaneId:)`.
The surface detach table explicitly assigns the 300-second deadline to the journal. No remaining
pruning defect is supported in the inspected active ownership descriptions.

## Four obsolete vendor prototype files: removed and rechecked

These were concrete disposable experiment sources/configuration, distinct from raw observation
logs and unrelated branch backups. The parent removed all four; existence checks confirm absence:

| File under `tmp/takeover-2026-09-05/` | Evidence / reason |
| --- | --- |
| `native-prototype.mise.toml` | Lines 1–43 define eleven runnable tasks rooted in local `vendor/ghostty`, including custom `FrameRetirementAccounting` and `SurfaceThreadStartGate` tests and a hard-coded Zig-cache executable |
| `ghostty-layer-release-candidate.patch` | Lines 1–10 patch `src/renderer/metal/IOSurfaceLayer.zig` to alter callback clearing; superseded unauthorized vendor correction |
| `callback-gate-before-negative.zig` | Copied modified IOSurfaceLayer implementation; line 22 allocates custom `DisplayAdmissionGate` and line 40 installs its private field |
| `health-producer-before-negative.zig` | Copied modified Ghostty App implementation, including experiment renderer-health machinery; not Agent Studio source |

All four were ignored by Git. None was referenced by `.mise.toml`, `scripts`, `Package.swift`,
`Sources`, `Tests`, `.github`, or the withdrawn plan. They were never in the PR diff, and their removal does not remove a required app test. The normal
app/build path remains unchanged.

Preserve `agent-studio.memory-issues.patch`, `agent-studio.atom-hygiene.patch`, and
`agent-studio.perf-residuals.patch`: they are unrelated work backups and outside deletion authority.
No blanket `tmp` cleanup is recommended. Raw old logs can remain ignored historical evidence;
they receive no unchanged-vendor acceptance credit.

## Two historical tracked documents: excluded from the current PR tree

The parent removed both documents after the interim review. They are now deleted relative to HEAD
and absent from the combined `origin/main` diff: actual PR-tree exclusion, not merely a staging
intention. Deletions are not staged or committed yet, so committed `origin/main...HEAD` still contains
the historical additions until packaging records these removals. This reviewer did not change Git.

| Exact file | Recommendation and basis |
| --- | --- |
| `docs/wip/2026-09-05-memory-pressure-salvage-assessment.md` | Removed; verified zero combined PR delta. Former 236-line assessment of another branch at `9af9080e7` against old main `57c49d0e3`; contains superseded keep/drop decisions and deinit/retention claims. Useful historical rationale is already represented by current code, architecture and this audit; the whole historical assessment is not needed in the app reliability change |
| `docs/wip/debugging/2026-09-05-release-takeover-investigation.md` | Removed; verified zero combined PR delta. Former 429-line mixed incident/review ledger with obsolete design paths, earlier ownership proposals and a prepared vendor patch prescription at lines 96–100. Later app-observation evidence is useful historically but does not make the entire incident ledger a current design artifact |

`docs/wip/2026-09-06-attention-ordering/program-design.md` is **useful scoped rationale**. Keep its
settled design content: the MainActor settlement task, captured transition queue, single drain,
epoch validation, stop/join and lifecycle chain match retained `TerminalActivityRouter.swift`
and `PaneFocusTracker.swift` code. It explains why raw same-turn mutations are coalesced while
distinct settled turns remain ordered. The parent replaced the other-checkout absolute references
with portable links to current preservation Requirements/Specification, identified the older R IDs,
and explicitly scoped defect descriptions to their historical commit. Those changes were re-read;
this file neither revives old findings nor authorizes an unrelated observation-site sweep.

Keep the three current reliability spec documents, the corrected
architecture documents, and the user-requested audit reports. The withdrawn ignored plan should
remain non-executable evidence until a new admitted plan exists; it is not a PR addition.

## Individual exclusions for unrelated untracked documents

All fourteen remain local/untracked and should stay out of scoped staging. Their current titles,
scope headers and section inventories were inspected, not their historical findings re-proven.
No deletion is recommended in this lane because they represent other work.

| File | Exclusion basis |
| --- | --- |
| `docs/wip/2026-08-27-hotspot-inventory.md` | Old exact-Debug CPU hotspot inventory |
| `docs/wip/2026-08-27-performance-side-issues.md` | Separate Bridge real-Git/WebKit stall |
| `docs/wip/2026-08-27-systemic-issues-and-architecture-amendments.md` | Older broad architecture proposals |
| `docs/wip/2026-08-28-pr2-local-activity-replay.md` | Explicit later-PR repository activity/FSEvents handoff |
| `docs/wip/2026-08-28-shared-ancestor-activity-settlement.md` | Separate shared Git continuity/activity boundary |
| `docs/wip/2026-08-28-shared-git-ancestor-continuity-amendment.md` | Separate Darwin Git ancestor-event design |
| `docs/wip/2026-09-03-fix-validation-and-open-defects.md` | Earlier pane/FSEvents branch validation |
| `docs/wip/2026-09-03-pr-review-findings.md` | Earlier `fix/pane-survives-removed-working-directory` review |
| `docs/wip/communications/2026-08-28-shared-ancestor-continuity-advisor.md` | Other-lane advisor record |
| `docs/wip/debugging/2026-08-27-fsevents-callback-hotspot.md` | Historical FSEvents CPU proof |
| `docs/wip/debugging/2026-09-01-pr1-sidebar-dynamic-stability.md` | Sidebar PR1 acceptance/closure record |
| `docs/wip/debugging/2026-09-03-pane-lifecycle-repair-validation.md` | Historical residency validation |
| `docs/wip/debugging/2026-09-03-pane-tab-switch-spinner.md` | Historical version-specific spinner investigation |
| `docs/wip/debugging/2026-09-03-pr-complete-review.md` | Earlier residency/shared-FSEvents complete review |

## Preservation and sampler correction

No app-source/test removal candidate is supported by this pruning review. In particular, preserve
the five initially untracked app/test files: `WorkspaceSurfaceCoordinator+PaneDiscard.swift`,
`WorkspacePaneDiscardFocusTests.swift`, `WorkspaceSurfaceCoordinatorTests+Filesystem.swift`,
`RepoExplorerProjectionLifetimeTests.swift`, and `SurfaceManagerNativeRetirementTests.swift`.
They are still present, as are the four moved test groups accounted for by the first review.

Current source spot checks establish that the preservation boundaries still exist: three-table
schema/journal files, `AppPolicies.swift:216–217` (10 and 300 seconds), global live/available-Undo
owner predicates (`WorkspaceCoreRepository+SessionOwnership.swift:95–103`), serialized durable
creation/close publication, journal restart/capacity tests, renderer delivery seam and visibility
tests, router/tracker ordering and observation-lifetime tests. These are source-presence checks,
not a rerun of all 186 tracked-file semantics or a claim all tests pass.

The sampler F2 correction is supported. `count_heap_class` now compares the exact fourth heap
field (`scripts/verify-renderer-population.sh:183–186`); both the production sampler at lines
294–296 and new CLI mode at lines 396–398 call that function. The new permanent test invokes
the real parser and retains all four previous tests. Its fixture includes two real class rows,
a keypath reference and a similarly named wrapper. The saved real heap has exact fourth-field
rows for all three counted classes at lines 2392, 2400 and 2480, and the false keypath at 3169.
No new sampler defect found within the changed parsing boundary.

Read-only inspection of `/tmp/agentstudio-sampler-red.log` confirms actual output 8 versus expected
3 and five tests/one issue. The green log confirms five tests in one suite passed. The parent
records command `mise run test:swift -- --filter RendererPopulationScriptTests`, exits 1 and 0;
this reviewer did not rerun it. These receipts support the parser correction only, not native
population correctness, process termination or whole-branch readiness.

## Coverage, commands and uncovered boundary

Coverage: complete initial-to-current path reconciliation; exact deletion targets; current
combined/committed vendor/build/pin boundary; active reliability documents; touched architecture
ownership descriptions; historical tracked/untracked document classification; four identified
prototype files and their verified removal; complete sampler/test correction and its saved red/green evidence. No fresh
native process inspection, source build, test, lint, formatter, setup, fetch or process signal.

Read-only commands used: `git rev-parse`, `git status --short --untracked-files=all`,
`git diff --name-status/--name-only/--numstat origin/main`, committed-range and HEAD vendor/build
diffs, `git diff --cached --stat`, `git ls-tree`, `git ls-files --others --exclude-standard`,
`git check-ignore`, `ls -ld`, `rg`/`rg --files -uuu`, `cat`/`sed`/`nl`/`tail`, and a Python
in-memory set comparison of the initial ledger with current paths, repeated after the parent corrections. `git diff --check` returned
no diagnostics (exit 0). Source/search commands completed normally; no-match searches are not
behavioral proof. No report-generation artifact other than this file was written.

The riskiest pruning assumption was that shared links alone meant every vendor experiment was
gone. It is now resolved: active app/build wiring is clean, the four ignored prototype files are
absent, and the two historical additions are actually excluded from the combined PR tree. Their
unstaged deletions still need to be recorded at the eventual delivery boundary.

Runtime reachability remains partial: pending cleanup is schema/admission without the completed
executor (initial review F1), and native free uses the stock synchronous API with safety and
responsiveness proof still open. A clean vendor diff, a successful launch, or this pruning review
cannot substitute for those missing outcomes. Exact preservation of every pre-pruning byte cannot
be reconstructed from a path-only prior inventory; no snapshot hashes were supplied. Current
source anchors and inventory show no supported accidental app/test deletion, while the first
review remains the detailed semantic coverage record. Product readiness is expressly unverified.
