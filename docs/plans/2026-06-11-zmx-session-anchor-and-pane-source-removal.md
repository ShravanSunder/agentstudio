# zmx Session Anchor + Pane Source Removal

Date: 2026-06-11
Branch context: `issues-with-persistance` (plan authored here; execution continues here)
Status: in execution — plan-review-swarm completed, accepted revisions folded in. T0/T1/T2/T3/T4 committed, T5 implemented with proof gates green in the current changeset. Next implementation step starts at T5b.

## Execution State (handoff, 2026-06-11)

T0/T1 landed in commit `0026a7b8` (`Anchor terminal zmx session ids in pane storage`). T2 landed in commit `0636adf4` (`Capture zmx session anchors at pane creation`). T3 landed in commit `7e6232d1` (`Prefer stored zmx session anchors on restore`). T4 landed in commit `73e4ddb0` (`Tolerate dangling pane facet refs on save`). T5 is implemented in the current changeset (`Hydrate zmx anchors before orphan cleanup`). Next implementation step starts at T5b.

Done — T0 (all green, characterization evidence captured):
- `Tests/AgentStudioTests/Core/Stores/WorkspaceCoreRepositoryPaneSourceLatchTests.swift` (new) — 3 tests pinning the save-latch throws (`worktreeNotFoundInWorkspace`, `paneSourceFacetWorktreeMismatch`). These were the red→green pivots for T4.
- `Tests/AgentStudioTests/Features/Terminal/Restore/TerminalRestoreRuntimeTests.swift` — added `zmxSessionId_followsLiveFacets_whenPaneRoamsToAnotherWorktree` pinning facet-following derivation (pivot for T3).
- Verified: `mise run test -- --filter "PaneSourceLatch|TerminalRestoreRuntime"` → all pass against pre-change code.

Done — T1 implementation (verified red first: `table pane_content_terminal has no column named zmx_session_id` across terminal-writing suites before the migration was added):
- `Sources/AgentStudio/Core/Models/PaneContent.swift` — `TerminalState.zmxSessionId: String?` added with an explicit initializer default (`zmxSessionId: String? = nil`); do not use a property `= nil` default because SwiftLint flags `implicit_optional_initialization`.
- `Sources/AgentStudio/Core/State/MainActor/Persistence/WorkspaceCoreRepository+PaneGraph.swift` — record case is now `.terminal(provider:lifetime:zmxSessionId:)` plus a `static func terminal(provider:lifetime:)` factory so the ~14 existing test call sites compile unchanged.
- `Sources/AgentStudio/Core/State/MainActor/Persistence/WorkspaceCoreRepository+PaneGraphMutation.swift` — insert writes `zmx_session_id`.
- `Sources/AgentStudio/Core/State/MainActor/Persistence/WorkspaceCoreRepository+PaneGraphCodecs.swift` — `decodeTerminalContent` selects + returns `zmx_session_id`.
- `Sources/AgentStudio/Core/State/MainActor/Persistence/WorkspaceSQLiteStoreBackend.swift` — both bridge directions map `TerminalState.zmxSessionId ↔ record`.
- `Sources/AgentStudio/Core/State/MainActor/Persistence/WorkspaceCoreMigrations.swift` — `008_add_zmx_session_id` appended (ALTER TABLE ADD COLUMN, nullable).
- `Tests/AgentStudioTests/Core/Stores/WorkspaceCoreZmxSessionAnchorMigrationTests.swift` (new) — column presence + roundtrip + anchor-less NULL tests.
- `Tests/AgentStudioTests/Core/Stores/WorkspaceCoreMigrationTests.swift` — identifier list extended with `008_add_zmx_session_id`.

**T1 proof gates complete:**
1. Scoped Swift proof: `swift build --build-tests --build-path .build-agent-t1 && AGENT_STUDIO_BENCHMARK_MODE=off swift test --skip-build --build-path .build-agent-t1 --filter "WorkspaceCoreZmxSessionAnchorMigrationTests|WorkspaceCoreMigrationTests|WorkspaceCoreTabGraphLayoutRepairMigrationTests"` — build complete; 24 tests in 3 suites passed after 0.031s.
2. Lint proof: `mise run lint` — swift-format OK; swiftlint 0 violations in 1014 files; Core boundary import check passed; release script verification passed.
3. Full default test proof: `mise run test` — exit 0; default E2E and Zmx E2E lanes skipped by `SWIFT_TEST_INCLUDE_E2E=0` and `SWIFT_TEST_INCLUDE_ZMX_E2E=0`.

Done — T2 implementation (verified red first: new zmx panes did not store anchors at creation; immediate and SQLite roundtrip assertions all saw `nil`):
- `Sources/AgentStudio/Core/State/MainActor/Atoms/WorkspacePaneAtom.swift` — computes deterministic spawn-time anchors at the creation/action boundary for worktree, floating, and drawer zmx panes.
- `Sources/AgentStudio/Core/State/MainActor/Atoms/WorkspacePaneGraphAtom.swift` — adds `setTerminalZmxSessionId(_:sessionId:)`, scoped to zmx terminal content.
- `Tests/AgentStudioTests/Core/Stores/WorkspaceSQLiteStoreBridgeTests.swift` — asserts worktree, floating, and drawer panes store the expected `zmx_session_id` immediately and preserve it through SQLite flush.

**T2 proof gates complete:**
1. Red proof: `swift build --build-tests --build-path .build-agent-t2 && AGENT_STUDIO_BENCHMARK_MODE=off swift test --skip-build --build-path .build-agent-t2 --filter "WorkspaceSQLiteStoreBridgeTests/newZmxPanesStoreDeterministicSessionAnchorsAtCreationAndSQLiteFlush"` — failed as expected before implementation with 6 issues: all immediate and stored `zmxSessionId` values were `nil`.
2. Green scoped proof: same command after implementation — build complete; 1 test in 1 suite passed after 0.026s.
3. Broader scoped proof: `swift build --build-tests --build-path .build-agent-t2 && AGENT_STUDIO_BENCHMARK_MODE=off swift test --skip-build --build-path .build-agent-t2 --filter "WorkspaceSQLiteStoreBridgeTests|TerminalRestoreRuntimeTests|PaneCoordinatorTerminalRestoreIntegrationTests|PaneCoordinatorSlotLifecycleTests|WorkspaceStoreDrawer"` — build complete; 87 tests in 5 suites passed after 1.875s.
4. Lint proof: `mise run lint` — swift-format OK; swiftlint 0 violations in 1014 files; Core boundary import check passed; release script verification passed.

Done — T3 implementation (verified red first: a roamed pane still returned the live worktree-B derived id instead of the stored worktree-A spawn anchor):
- `Sources/AgentStudio/Features/Terminal/Restore/TerminalRestoreRuntime.swift` — `zmxSessionId(for:store:)` is stored-first and keeps legacy derivation as a non-persisting fallback for unhydrated rows.
- `Tests/AgentStudioTests/Features/Terminal/Restore/TerminalRestoreRuntimeTests.swift` — flips the roamed-pane characterization to assert stored id wins for `zmxSessionId`, `zmxAttachCommand`, and attach diagnostics.

**T3 proof gates complete:**
1. Red proof: `swift build --build-tests --build-path .build-agent-t3 && AGENT_STUDIO_BENCHMARK_MODE=off swift test --skip-build --build-path .build-agent-t3 --filter "TerminalRestoreRuntimeTests/zmxSessionId_usesStoredSpawnAnchor_whenPaneRoamsToAnotherWorktree"` — failed as expected before implementation with 2 issues: returned session id equaled the roamed facet-derived id.
2. Green scoped proof: same command after implementation — build complete; 1 test in 1 suite passed after 0.005s.
3. Broader scoped proof: `swift build --build-tests --build-path .build-agent-t3 && AGENT_STUDIO_BENCHMARK_MODE=off swift test --skip-build --build-path .build-agent-t3 --filter "TerminalRestoreRuntimeTests|PaneCoordinatorTerminalRestoreIntegrationTests|WorkspaceSQLiteStoreBridgeTests"` — build complete; 39 tests in 3 suites passed after 0.818s.
4. Lint proof: `mise run lint` — swift-format OK; swiftlint 0 violations in 1014 files; Core boundary import check passed; release script verification passed.

Done — T4 implementation (verified red first: source-binding validators rejected legal live-facet states before the tolerance write-path landed):
- `Sources/AgentStudio/Core/State/MainActor/Persistence/WorkspaceCoreRepository+PaneGraphValidation.swift` — removes the save-time `source`/facet/worktree-existence veto while preserving structural pane graph validation: existing pane/drawer ownership, content route/type immutability, placement, drawer membership, and duplicate checks.
- `Sources/AgentStudio/Core/State/MainActor/Persistence/WorkspaceCoreRepository+PaneGraphMutation.swift` — writes topology-verified live durable-facet refs into the existing source columns until migration 009 renames/removes the source concept: existing worktree refs normalize to the worktree's actual repo, missing worktree refs write `(NULL, NULL)`, existing repo-only refs write `(repo_id, NULL)`, missing repo refs write `(NULL, NULL)`.
- `Tests/AgentStudioTests/Core/Stores/WorkspaceCoreRepositoryPaneSourceLatchTests.swift` — flips the three latch repros to assert saves succeed and persist NULL/live refs.
- `Tests/AgentStudioTests/Core/Stores/WorkspaceCoreRepositoryPaneGraphValidationTests.swift` — flips five old source-binding rejection cases to assert tolerated NULL/normalized refs while keeping structural validation tests intact.

**T4 proof gates complete:**
1. Red proof: `swift build --build-tests --build-path .build-agent-t4 && AGENT_STUDIO_BENCHMARK_MODE=off swift test --skip-build --build-path .build-agent-t4 --filter "WorkspaceCoreRepositoryPaneSourceLatchTests|WorkspaceCoreRepositoryPaneGraphValidationTests"` — failed as expected before implementation with 8 issues across `worktreeNotFoundInWorkspace`, `paneSourceFacetRepoMismatch`, `paneSourceFacetWorktreeMismatch`, `repoNotFoundInWorkspace`, and `worktreeRepoMismatch`.
2. Green scoped proof: same command after implementation — build complete; 21 tests in 2 suites passed after 0.037s.
3. Broader scoped proof: `swift build --build-tests --build-path .build-agent-t4 && AGENT_STUDIO_BENCHMARK_MODE=off swift test --skip-build --build-path .build-agent-t4 --filter "WorkspaceCoreRepository|WorkspaceSQLiteStoreBridgeTests|WorkspaceCoreMigrationTests"` — build complete; 130 tests in 15 suites passed after 1.930s.
4. Full default test proof: `mise run test` first hit the runner's 60s wrapper timeout (exit 124) while tests were still passing; rerun as `SWIFT_TEST_TIMEOUT_SECONDS=180 mise run test` — exit 0; default E2E and Zmx E2E lanes skipped by `SWIFT_TEST_INCLUDE_E2E=0` and `SWIFT_TEST_INCLUDE_ZMX_E2E=0`.
5. Lint proof: after `mise run format`, `mise run lint` — swift-format OK; swiftlint 0 violations in 1014 files; Core boundary import check passed; release script verification passed.

Execution discoveries the remaining tasks must respect:
- **Source columns double as facet storage.** `decodePaneRecord` (WorkspaceCoreRepository+PaneGraph.swift:202-213) reads `durableFacets.repoId/worktreeId` FROM `source_repo_id`/`source_worktree_id`. On write, `SQLitePaneGraphStorage.sourceIds` stores source ids for worktree panes and facet ids for floating panes. Consequence for T6/migration 009: those columns are not "dropped" — they are RENAMED/refit as facet columns (`facet_repo_id`, `facet_worktree_id`) written from `durableFacets` for all panes, and `source_kind` is dropped. A facet/source mismatch can never round-trip through the DB (single column) — it exists only in memory, which is consistent with the latch evidence.
- Worktree build setup: this worktree now has `Frameworks/GhosttyKit.xcframework`, `Sources/AgentStudio/Resources/ghostty`, and `vendor/zmx/zig-out/bin/zmx` APFS-cloned from the `agent-studio` main worktree (identical submodule SHAs). `mise trust` already run.
- Test invocation: for scoped suites, use direct `swift test --filter ...` with an explicit build path; the `mise run test` task does not forward arbitrary filters. zsh shadows `log`; use `/usr/bin/log` if unified-log evidence is needed.

## Plan Review Revisions (accepted)

`plan-review-swarm` verdict was **needs revision**, not ready as originally written. Accepted findings changed execution shape:
- Phase A ships the session-anchor and save-latch fix first: T1 → T2 → T3 → T4 → T5, then Phase-A smoke. Phase B removes `TerminalSource`/`PaneMetadataSource` and runs migration 009 after Phase A proves restore/cleanup safety. This keeps the source-removal goal, but reduces destructive-migration blast radius.
- No lazy UI-triggered adoption may run before boot cleanup. Legacy anchor hydration/adoption must be an explicit async pre-cleanup prepass that consumes one discovered live-session set, persists anchors only after validator tolerance is in place, and leaves sync readers pure.
- T3/T5 order is changed from the original draft: any persisted legacy backfill/adoption occurs only after validator tolerance, otherwise the backfill mutation can re-trigger the save latch.
- `launchDirectory` needs a named post-source owner before source deletion. Phase B moves it onto pane metadata / graph metadata as explicit cold-spawn state; classification and worktree membership come only from live facets.
- Cleanup/adoption suffix matching must be kind-aware: main panes match `as-<repo16>-<wt16>-<pane16>`, drawer panes match `as-d--<parent16>--<pane16>`. Suffix alone is not enough.
- Migration 009 backup/rollback must be sidecar-safe: checkpoint before backup; verify backup opens; on restore replace `core.sqlite` and remove stale `core.sqlite-wal` / `core.sqlite-shm`.
- T8 damping is debounced-autosave-only. Explicit `flushAsync()` and termination flushes bypass suppression; first successful save clears it.

## Source Coverage

- Debug investigation (root cause + timeline evidence):
  `tmp/debug-workflows/2026-06-11-agent-studio-issues-with-persistance-workspace-save-failed/debug-investigation.md`
- Design conversation decisions (this session, 2026-06-11):
  1. Two-concept model: **live facets** (where the pane IS) + **frozen spawn anchor** (how to re-attach its shell). The frozen `source` union is removed entirely — hard cutover, no compatibility shim.
  2. zmx session identity becomes **stored at spawn, never re-derived** from live state. Existing sessions keep their exact ids (zero-rename migration).
  3. Save-time validators stop comparing live state against birth state; dangling facet refs are tolerated per the schema's `ON DELETE SET NULL` intent.
  4. Migrations are append-only and "done right": new identifiers `008+`, never editing applied migrations; destructive schema change uses the rebuild pattern with a pre-migration backup.
  5. TDD throughout: every task lands red test(s) first, then the change.
  6. Observability (log privacy, notification bodies, tracing) is **out of scope** — owned by the separate Victoria-stack observability PR.
- Repo evidence verified live (file:line):
  - Save latch: `Sources/AgentStudio/Core/State/MainActor/Persistence/WorkspaceCoreRepository+PaneGraphValidation.swift:41-96, 293-316`
  - Facet rewrite on cwd: `Sources/AgentStudio/App/Coordination/PaneCoordinator.swift:248-273`, `Sources/AgentStudio/Core/State/MainActor/Atoms/WorkspacePaneGraphAtom.swift:309-335`
  - Orphan keeps source: `WorkspacePaneGraphAtom.swift:447-485`
  - Live-derived session ids: `Sources/AgentStudio/Features/Terminal/Restore/TerminalRestoreRuntime.swift:63-97`
  - Kill path: `Sources/AgentStudio/App/Boot/AppDelegate.swift:250-290`, `Sources/AgentStudio/App/Coordination/ZmxOrphanCleanupPlanner.swift`
  - Session id format + ownership prefix filtering: `Sources/AgentStudio/Core/RuntimeEventSystem/Runtime/ZmxBackend.swift:104, 160-190, 321-341`
  - Terminal content row (anchor home): `pane_content_terminal(pane_id, provider, lifetime)` — `WorkspaceCoreMigrations.swift` 001-007 append-only list
  - `TerminalState { provider, lifetime }`: `Sources/AgentStudio/Core/Models/PaneContent.swift:167-172`
  - Frozen source consumers: CommandBar switches (`Features/CommandBar/CommandBarDataSource.swift:187, 260, 471, 714`), `RuntimeRegistry.findPaneWithWorktree` (`Core/RuntimeEventSystem/Registry/RuntimeRegistry.swift:55-62`), launch_directory write (`WorkspaceCoreRepository+PaneGraphMutation.swift:264`), restore codec (`WorkspaceSQLiteStoreBackend.swift:690-716`)

## Goal

1. zmx session identity is captured once at spawn, persisted in core.sqlite, and read back verbatim for attach/restore/orphan-cleanup — roaming a pane (cwd into another worktree) can never strand or kill its shell session.
2. The frozen `TerminalSource`/`PaneMetadataSource` union is deleted. Live facets are the only pane↔worktree binding. Workspace saves can no longer latch into permanent failure from roamed/orphaned panes.
3. Validated cruft from the old model is removed; resilience belts added (suffix-protect in orphan cleanup, pre-migration backup, save-failure retry damping).

## Non-Goals

- Observability changes (OSLog privacy, notification bodies, trace runtime defaults) — Victoria-stack PR owns these.
- zmx binary/vendor changes — zmx attaches by name and auto-creates; no contract change.
- Multi-workspace semantics, legacy JSON import redesign (only the minimal mapping to keep import green).
- Renaming existing live sessions. Existing compound ids are kept verbatim forever.

## Decided Design Points

- **Anchor representation**: `TerminalState` gains `zmxSessionId: String?`; persisted as nullable `zmx_session_id TEXT` on `pane_content_terminal`. We store the *final id string*, not ingredients — ingredients invite re-derivation. `launch_directory` stays on `pane` as the cold-spawn directory.
- **New-session naming**: unchanged format. Worktree-born panes mint `as-<repo16>-<wt16>-<pane16>` from *birth* facets at spawn; drawer panes keep `as-d--…`; floating keep launch-dir stable key. The name is provenance, frozen at spawn; `zmx list` readability is retained.
- **Capture boundary**: worktree-pane ids are captured at the action/caller boundary that already has `Repo` + `Worktree` stable keys, not inside low-level graph atoms that only know `TerminalSource`. Floating and drawer ids are captured at their creation boundaries where launch directory or parent pane id is available. This is deterministic prediction before first attach, not a zmx CLI side effect: `createPaneSession` only builds the same handle string.
- **Backfill/adoption**: not lazy inside sync `zmxSessionId(for:store:)`. Phase A adds an async anchor hydration prepass that discovers live sessions once, resolves every persisted zmx pane, performs kind-aware adoption for unique live matches, persists anchors after validator tolerance is in place, then boot cleanup uses the hydrated stored ids. Sync readers remain stored-first pure functions with a non-persisting legacy fallback only for unhydrated rows.
- **Validator tolerance**: `validatePaneSource`'s source checks and `validateWorktreeSourceFacets` are deleted with the source union. Facet refs are validated as *references*: a facet repo/worktree id not present in the snapshot topology is written as NULL (mirroring `ON DELETE SET NULL`), never an error. Structural validation (drawer/placement/content-type/duplicates) is unchanged.
- **Orphan-cleanup belt**: boot cleanup first runs the same anchor hydration/adoption resolver over all persisted zmx panes. Known ids are stored ids only after hydration; legacy derived fallbacks are not allowed to make cleanup destructive. In addition, never destroy a session whose kind-aware pane segment matches a persisted pane id (`as-...-<pane16>` for main, `as-d--<parent16>--<pane16>` for drawer). `shouldSkipCleanup` stays for unresolvable states.
- **Post-source launch directory owner**: Phase B deletes `TerminalSource` / `PaneMetadataSource`, but keeps `launchDirectory` as explicit cold-spawn metadata on pane metadata / graph metadata. Live worktree membership, command-bar classification, and runtime worktree lookup derive only from facets. No frozen worktree/repo provenance remains outside the stored zmx session id and launch directory.
- **Migrations**: `008_add_zmx_session_id` (additive, `ALTER TABLE pane_content_terminal ADD COLUMN`); `009_drop_pane_source_binding` (rebuild `pane` table without `source_kind`, refitting `source_repo_id/source_worktree_id` into `facet_repo_id/facet_worktree_id`, keeping `launch_directory`; recreate triggers/indexes; copy data). Before applying 009 at boot, the backend factory detects pending 009 before `migrate()`, checkpoints WAL, writes and verifies a sidecar-safe sibling backup `core.sqlite.pre-009-backup`, then migrates. Rollback restores the backup while removing stale `core.sqlite-wal` / `core.sqlite-shm`. Identifiers append-only.

## Requirements / Proof Matrix

| # | Requirement / claim | Task | Proof gate | Layer | Red/green | Sized to pass? |
|---|---------------------|------|-----------|-------|-----------|----------------|
| R1 | Current session-id derivation is frozen as golden behavior (worktree, drawer, floating-launchDir, cwd-fallback, home-fallback) | T0 | new characterization suite passes against unmodified code | unit | green-only (characterization) | yes |
| R2 | Save latch is reproducible: roamed pane (facet≠source) and orphaned pane (missing worktree) make `replaceWorkspaceSnapshotStaged` throw | T0 | failing-state tests assert today's throw; flipped to "save succeeds" in T4 | integration (in-memory GRDB) | red now, green at T4 | yes |
| R3 | `zmx_session_id` column exists, round-trips through save/restore codecs | T1 | migration test on fixture DB at 007 → 008; codec roundtrip test | unit + integration | red→green | yes |
| R4 | Spawn captures and persists the session id exactly once for every shape; restart reads stored id verbatim | T2 | separate worktree, floating, and drawer creation tests assert immediate stored `zmx_session_id`; datastore roundtrip asserts it survives | integration | red→green | yes |
| R5 | Sync attach/diagnostics readers are stored-first pure functions and do not perform async live discovery | T3 | TerminalRestoreRuntime tests prove stored id wins after roaming; attach command reads stored anchor without invoking discovery | unit | red→green | yes |
| R6 | Legacy anchor hydration/adoption runs before boot cleanup and cannot re-trigger the save latch | T5 | async resolver test with one discovered live-session set; first-upgraded-launch cleanup test for legacy roamed pane; no saveFailed/persistence throw | integration | red→green | yes |
| R7 | Saves succeed with roamed panes, orphaned panes, and dangling facet refs (refs written as NULL) | T5 | R2 tests flipped green + new dangling-ref write test asserting NULL columns | integration | red→green (R2 reds flip) | yes |
| R8 | `TerminalSource`/`PaneMetadataSource` deleted; command bar/registry/creation flows derive from facets; migration 009 rebuilds `pane` without source columns; pre-009 backup written | T6 | build green with type deleted; command-bar + RuntimeRegistry roamed-pane behavior tests; migration test 008→009 on populated fixture preserving every pane column; sidecar-safe backup/rollback test | unit + integration | red→green | yes — Phase B gate |
| R9 | Legacy JSON fallback/import still materializes panes through explicit legacy DTO mapping (source → facets + launch directory) | T7 | existing import/fallback tests + new mapping test | integration | red→green | yes |
| R10 | Identical consecutive save failures are damped for debounced autosave only; explicit flush/termination saves bypass damping | T8 | WorkspaceStore test with injected failing datastore + TestPushClock; explicit flush succeeds after autosave suppression and clears suppression | unit | red→green | yes |
| R11 | Validated cruft removed (e.g., `PaneSessionHandle.hasValidId` 3-segment check, dead TerminalSource helpers); each removal carries deadness proof (no references) | T9 | grep-zero evidence recorded in PR + build/test green | unit | green-only | yes |
| R12 | Full e2e: real app + real zmx — create sessions (incl. deliberately roamed pane), quit, relaunch: scrollback intact, no session killed, saves green in fresh instance | T10 | scripted smoke on isolated `AGENTSTUDIO_DATA_DIR` + manual peekaboo verification | smoke/e2e | n/a (behavioral gate) | yes |
| R13 | Docs updated in same changeset: session_lifecycle identity section, atom persistence boundaries, AGENTS.md component table | T11 | doc diff reviewed | n/a | n/a | yes |

No red/green exceptions requested.

## Task Sequence

### Phase A — Session Anchor + Save-Latch Fix

- **T0 — Characterization + latch repro (TDD net)**
  Golden tests for `ZmxBackend.sessionId/floatingSessionId/drawerSessionId` and `TerminalRestoreRuntime.zmxSessionId` across all pane shapes; in-memory GRDB tests reproducing the save latch (R2) marked as expected-current-behavior. No product code changes.
- **T1 — Migration 008 + codec plumb** (`zmx_session_id` nullable; row codec read/write; `TerminalState.zmxSessionId`)
- **T2 — Spawn-time capture** (creation/action boundaries persist deterministic id before first attach; new panes always anchored)
  Anchors: `ZmxBackend.createPaneSession` builds the same handle string without a CLI call (`ZmxBackend.swift:208+`). Do not compute worktree ids inside low-level graph atoms that only know `TerminalSource`; compute at the caller/action boundary that already has `Repo` + `Worktree` stable keys, then thread `zmxSessionId` into pane creation. Floating panes use `floatingSessionId(launchDirectory:paneId:)` at the launch-directory creation boundary; drawer panes use `drawerSessionId(parentPaneId:drawerPaneId:)` in `WorkspacePaneAtom.addDrawerPane`. Red tests first: worktree, floating, and drawer pane creation each persist the expected id immediately, and the SQLite roundtrip keeps it.
- **T3 — Stored-first sync reader cutover, no persisted legacy backfill yet**
  `TerminalRestoreRuntime.zmxSessionId(for:store:)` remains synchronous and pure: return `pane.terminalState?.zmxSessionId` if set; otherwise derive today's legacy fallback without writing. `zmxAttachCommand` / diagnostics read the stored id without live discovery. Flip `zmxSessionId_followsLiveFacets_whenPaneRoamsToAnotherWorktree`: after a stored id exists, roaming must not change the session id.
- **T4 — Validator tolerance** (delete source-vs-facet comparisons; dangling facet refs → NULL at write; R2 reds flip green)
  Anchors: `WorkspaceCoreRepository+PaneGraphValidation.swift:41-96` (`validatePaneSource`, `validateWorktreeSourceFacets`) and `requireWorktreeExists:293-316`. Write-side NULLing happens in `paneStatementArguments` (`+PaneGraphMutation.swift:249-279`): resolve facet repo/worktree ids against the topology rows already written in the same transaction; write NULL when missing. Flip the 3 tests in `WorkspaceCoreRepositoryPaneSourceLatchTests.swift` to assert success + NULLed columns (rename them accordingly — they document the fix from then on).
- **T5 — Async anchor hydration/adoption + cleanup belt**
  Add a resolver/prepass that discovers live zmx sessions once, then resolves every persisted zmx pane before boot orphan cleanup. Stored ids win. Missing ids are derived through today's fallback, then optionally adopted only when exactly one live session of the same kind matches: main `as-<repo16>-<wt16>-<pane16>`, drawer `as-d--<parent16>--<pane16>`. Persist anchors only after T4 validator tolerance. `ZmxOrphanCleanupPlanner` consumes hydrated stored ids and kind-aware suffix protection; no destructive cleanup may rely on stale derived ids for legacy rows. Existing `ZmxOrphanCleanupPlannerTests` characterize current behavior — extend, don't weaken.

  Implementation note: T5 keeps the sync restore reader pure (`TerminalRestoreRuntime.zmxSessionId` is stored-first with legacy fallback only). Boot cleanup performs the async hydration/adoption pass once, persists any adopted/derived anchors through `WorkspacePaneAtom.setTerminalZmxSessionId`, flushes SQLite, and only then computes destroyable orphan sessions. If anchor persistence fails, destructive cleanup is skipped for that launch.
- **T5b — Phase-A smoke**
  Run a focused real-zmx smoke before Phase B: isolated data dir, create/restore anchored panes, roam a pane, relaunch, assert the stored session id is still used and cleanup does not destroy the live session. If this cannot be bounded, stop and report the blocker instead of entering source deletion.

### Phase B — Source Union Removal + Migration 009

- **T6 — Source union removal + migration 009** (delete `TerminalSource`/`PaneMetadataSource`; facets-derived classification in CommandBar (`worktreeId == nil` → floating presentation) and `RuntimeRegistry`; creation/template/drawer-inherit flows take explicit facets + launch directory; restore codec stops building source; `pane` table rebuild; pre-009 backup)
  Anchors: consumers to cut over: `CommandBarDataSource.swift:187,260,471,714` (switch on `pane.source` → derive from `pane.worktreeId == nil`), `RuntimeRegistry.swift:55-62` (`metadata.source.worktreeId` → `metadata.facets.worktreeId`), `WorkspaceSQLiteSnapshotDiagnostics.swift:121-141`, `PaneTabViewController.swift:3196-3204`, `PaneCoordinator+ViewLifecycle.swift:189-202,296-320,585-599`, `Templates.swift:38-92`, `WorkspacePaneAtom.swift:329-340` (drawer-child inheritance), `Pane.swift:109-125`, `PaneMetadata.swift:5-106`, and test helpers that construct source-bearing panes (`ModelFactories.swift`, `WorkspaceStoreTestAccess.swift`, `WorkspaceSQLiteStoreBridgeTests.swift`). Migration 009 (rebuild pattern, append-only): new `pane` table with `facet_repo_id`/`facet_worktree_id` (copied from `source_repo_id`/`source_worktree_id`), `launch_directory` kept as explicit cold-spawn metadata, `source_kind` dropped; recreate `pane_source_repo_matches_workspace`-style triggers against facet columns; copy rows; FK check + row-count assertion plus exact value preservation for every retained pane column. Pre-009 sibling backup `core.sqlite.pre-009-backup` is written by `WorkspaceSQLiteStoreBackendFactory` before migrate when 009 is pending (WAL-checkpoint first, backup opens successfully, rollback removes stale sidecars). Restore codec (`decodePaneSourceRecord` in `+PaneGraphCodecs.swift`, `paneMetadataSource` in `WorkspaceSQLiteStoreBackend.swift:840+`) is replaced by facet/launch-directory decoding; `PaneMetadataRecord.source` field is deleted.
  Behavioral proof required: command-bar classification and `RuntimeRegistry.findPaneWithWorktree` follow live facets after roaming; birth worktree no longer wins. Grep-zero after T6: `TerminalSource`, `PaneMetadataSource`, `metadata.source`, and `pane.source` in `Sources/AgentStudio` except intentional legacy DTO/import names.
- **T7 — Legacy import mapping** (Legacy payload `source` → facets + launch directory at importer boundary)
  Keep legacy JSON fallback supported via explicit legacy DTOs until that fallback is intentionally retired in a separate decision. Old `source` payloads map to live facets + explicit launch directory at the import/fallback boundary.
- **T8 — Save-failure retry damping** (debounced autosave only; injected clock)
  Use `TestPushClock` and existing debounce-test patterns. Suppress repeated identical debounced autosave attempts after 3 consecutive failures; re-arm on atom mutation; explicit `flushAsync()` and termination flushes bypass suppression; first success clears suppression.
- **T9 — Validated cruft sweep** (deadness-proven removals only; enumerate during execution)
- **T10 — E2E smoke** (isolated data dir, real zmx; roamed-pane scenario; orphan cleanup non-destructive)
  Concrete recipe required before claiming this gate: launch debug app with isolated `AGENTSTUDIO_DATA_DIR`, create two worktrees, create a zmx pane, print marker `AS_ZMX_ANCHOR_MARKER_<timestamp>`, roam with `cd` into the second worktree, persist/quit, relaunch, assert `zmx list` still contains the same stored id, the marker remains visible/restored, no `Workspace save failed` recovery notification/log appears, and Peekaboo PID-targeted capture records the restored terminal. Store transcript under `tmp/debug-workflows/<date>-zmx-session-anchor-e2e/`.
- **T11 — Docs/AGENTS updates** (same changeset as T5/T6 boundary changes)

Dependencies: T1→T2→T3→T4→T5 strictly ordered for Phase A. T4 must land before any persisted legacy backfill/adoption. Phase-A smoke (T5b) gates Phase B. T6 after T5 (stored ids + cleanup protection must be in place before `source.launchDirectory` disappears). T7 with/after T6; T8 may land after T4 and before final E2E; T10 after T6; T11 rides T4/T6 boundary changes.

## Write Surfaces

- `Core/Models/`: `TerminalSource.swift` (deleted), `PaneContent.swift` (TerminalState), `Templates.swift`
- `Core/Models/Pane.swift`: delete source projection; keep launch-directory/read-model access through explicit metadata owner.
- `Core/RuntimeEventSystem/`: `Contracts/PaneMetadata.swift`, `Registry/RuntimeRegistry.swift`, `Runtime/ZmxBackend.swift` (handle shape only; id functions untouched), `Runtime/SessionRuntime.swift`
- `Core/State/MainActor/Atoms/`: `WorkspacePaneGraphAtom.swift`, `WorkspacePaneAtom.swift`
- `Core/State/MainActor/Persistence/`: `WorkspaceCoreMigrations.swift` (008, 009 append), `WorkspaceCoreRepository+PaneGraph*.swift`, `SQLitePaneGraphStorage.swift`, `WorkspaceSQLiteStoreBackend.swift`, `WorkspaceStore.swift` (T8), legacy importer
- `App/`: `Coordination/PaneCoordinator*.swift`, `Coordination/ZmxOrphanCleanupPlanner.swift`, `Boot/AppDelegate.swift`
- `Features/`: `CommandBar/CommandBarDataSource.swift`, `Terminal/Restore/TerminalRestoreRuntime.swift`
- Diagnostics/test surfaces: `Core/State/SQLite/WorkspaceSQLiteSnapshotDiagnostics.swift`; source-dependent helpers such as `Tests/AgentStudioTests/Helpers/ModelFactories.swift`, `WorkspaceStoreTestAccess.swift`, and `WorkspaceSQLiteStoreBridgeTests.swift`.
- Tests colocated per repo convention; docs per T11.

## Validation Gates

- Per task: targeted Swift test command with an actual `swift test --filter ...` invocation (not `mise run test -- --filter`, which this task wrapper ignores), red→green evidence, then `mise run lint` zero errors.
- Migration gates: fixture DB built at 007/008 (and a populated copy of a real-shaped dataset) migrated to 008/009; `PRAGMA foreign_key_check` empty; trigger behavior asserted; every retained pane column value preserved; pre-009 backup file exists, opens, and rollback is sidecar-safe.
- Repo-wide: `mise run test` and `mise run lint` green at T4, T6, and end.
- Smoke/e2e (T10): debug build on isolated `AGENTSTUDIO_DATA_DIR`; scripted zmx session creation/roam/restart; assert via `zmx list` + scrollback marker; peekaboo for UI verification. Report this layer explicitly; if the harness can't bound it, name the blocker rather than relabeling lower layers.

## Risks, Rollback, Recovery

- **009 is destructive** (drops columns). Mitigations: rebuild-pattern migration with exact retained-column preservation assertions plus row-count + FK assertions inside the migration transaction; automatic `core.sqlite.pre-009-backup` created after WAL checkpoint and verified before migrate; recovery = restore backup and remove stale `core.sqlite-wal` / `core.sqlite-shm`, then run a build at 008.
- **Mixed-version risk**: a pre-009 binary opening a post-009 DB fails its column reads; stable/beta use separate data dirs, but a downgrade on the same channel requires the backup. Called out in release notes for the version shipping 009. Backup is retained indefinitely until a later explicit schema-backup cleanup decision; no time-only GC in this plan.
- **Adoption misfire** (T5): suffix collision is ~impossible (16 hex of UUIDv7 tail), but adoption only fires on *exactly one* live match of the same session kind and only when derivation disagrees; otherwise falls back to derivation. Adoption is centralized in the async hydration prepass for easy disable.
- **Behavioral change**: command-bar classification of a roamed worktree-born pane shifts from birth worktree to current location — accepted as the design intent (decided in session).
- **Behavioral change**: `RuntimeRegistry.findPaneWithWorktree` and other worktree-targeted lookups shift from birth worktree to current live facets. Add roamed-pane tests so this semantic loss is explicit and not a surprise.
- **Save-failure damping (T8)** must not mask failures: damping only suppresses debounced autosave retries, not the first failure per distinct state and not explicit flush/termination saves; recovery event still emitted (notification dedup already coalesces).

## Security Assumptions

- Filesystem writes limited to the app's own data dir (backup file) and repo test fixtures.
- `zmx list`/destroy subprocess surface unchanged; cleanup becomes strictly more conservative (suffix belt).
- No new parsing of untrusted input; session ids are app-minted hex.

## Open Questions

Resolved by plan review:
1. T8 damping policy: stop debounced autosave after 3 identical consecutive failures, re-arm on atom mutation, and bypass for explicit flush/termination saves.
2. Pre-009 backup is retained indefinitely until a later explicit schema-backup cleanup decision; no 7-day GC in this plan.
3. Adoption ships enabled in the Phase-A hydration prepass only; it is same-kind, exact-one-match only.

## Next

Execution was started in this worktree (`issues-with-persistance`) and intentionally paused for cost handoff. The implementing agent should:

1. Read this plan top to bottom (it is self-contained; the debug artifact under `tmp/debug-workflows/2026-06-11-...workspace-save-failed/` has the root-cause evidence if more context is needed).
2. If the T0/T1 commit has not landed yet, commit the current verified T0/T1 changes first.
3. Proceed T2 → T11 in order, TDD red/green per task, committing per task or per coherent pair.
4. Honor the repo guardrails: append-only migrations, no wall-clock test sleeps, `mise run test` / `mise run lint` gates, no `#if DEBUG` production hooks, never `pkill AgentStudio`, PID-targeted peekaboo for T10.
5. T8 policy is resolved by plan review: damp debounced autosave after 3 identical consecutive failures, re-arm on atom mutation, bypass explicit flush/termination saves.
