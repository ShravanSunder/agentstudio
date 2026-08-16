# RESULT: Sidebar grouping polish and round 3

Status: the toggle-refinement implementation, automated proof, three selected-state captures, By Repo unknown-sync suppression capture, and marker-scoped runtime verification are complete on the current source. The requested visible native tooltip capture is blocked because Computer Use provides no pointer-hover action; the typed tooltip contract is verified in source and tests. The branch remains attached to draft PR #296 and must not be merged from this task.

## 2026-08-16 toggle refinement round

### Delivered behavior

- Selected grouping segments now use the shared primary chrome-toolbar foreground, fill, and stroke palette. Unselected segments use the same palette's standard icon foreground. The muted-primary blue token remains confined to By Tab group-header icons.
- The selected segment expands to its icon plus `By Repo`, `All Panes`, or `By Tab`; unselected segments remain icon-only. Selection changes use the app's standard ease-in-out duration.
- Every mode continues through the typed `.controlHelp(segment.tooltipValue)` contract, with `textOverride: groupingMode.title`, so the tooltip names the exact mode.
- By Repo now suppresses `.unknown` sync metadata instead of rendering `↑?·↓?` on every unknown row.

### Red/green and quality proof

- Red-first focused run: exit 1; the mounted controls had equal widths, the segmented control still used its private selected-fill token, and `.unknown` still returned `true` for sync-chip presentation.
- Final focused command: `swift test --build-path .build-agent-1 --filter 'SidebarToolbarControlVisualStateTests|RepoExplorerWorktreeRowTests|SidebarSurfaceConvergenceTests|AppCommandSidebarCommandsTests' --skip WebKitSerializedTests --skip E2ESerializedTests --skip ZmxE2ETests`.
- Final focused result: exit 0; 35 tests in 4 suites passed.
- `mise run format`: exit 0.
- `mise run lint`: exit 0; swift-format passed, SwiftLint reported 0 violations across 2,032 files, architecture lint passed, and release-script verification passed.
- Current-source full gate: `SWIFT_TEST_TIMEOUT_SECONDS=2700 SWIFT_TEST_PREBUILD_TIMEOUT_SECONDS=1800 mise run test` exited 0 in 297.02 seconds. BridgeWeb unit, integration, browser, packaged E2E, Swift, serialized WebKit, and general E2E lanes passed.
- Two unchanged full-gate attempts first exposed a Bridge development-server integration timeout. The exact isolated test reproduced once, then passed in 1.45 seconds; the next unchanged complete gate passed. No Bridge source or configuration was changed.
- `git diff --check`: exit 0.

### Current-source Computer Use proof

- Exact app: `Agent Studio Debug jp6s` (`com.agentstudio.app.debug.djp6s`), PID `99956`, marker `debug-observability-jp6s-1786895858-97734`.
- Accessibility inspection confirmed exactly one selected mode at a time and the selected labels `By Repo`, `All Panes`, and `By Tab`.
- By Repo accessibility rows contained no `↑?·↓?` text, and the captured unknown-sync rows rendered no chip.
- `mise run verify-debug-observability` exited 0 for the exact launch: LaunchServices, background activation, authenticated IPC, and `app.did_finish_launching.succeeded` from VictoriaLogs.
- Exact PID `99956` was terminated after capture and confirmed absent. No other AgentStudio process was touched.
- Fresh current-source captures under `tmp-screenshots/toggle/`:
  - `01-by-repo-selected.png`
  - `02-all-panes-selected.png`
  - `03-by-tab-selected.png`
  - `05-by-repo-no-unknown-sync-chips.png`
- Tooltip visual-proof boundary: Computer Use exposes click and completed drag actions but no mouse-move or held-hover action. Those actions did not reveal the native macOS help tag, so no tooltip screenshot is claimed. Adding a product-specific tooltip overlay solely to work around the proof tool would violate the app's typed native tooltip ownership. The automated contract check proves that every segment remains wired through the typed source with its mode title.

## Delivered behavior

- The sidebar grouping picker is now a three-segment toolbar control using the existing repository, pane, and tab row-vocabulary icons. Each segment uses the typed command-tooltip contract, selected accent fill, and the existing window-scoped persisted grouping owner.
- All Panes and By Tab use the same two-line row anatomy and vertical rhythm as By Repo. Line one is identity plus the trailing `PR count · time · active dot` cluster; time is always present, PR count is suppressed only at zero, and the active state is a dot rather than a text chip.
- Path-shaped live terminal titles are unavailable activity information. Empty titles, absolute paths, home paths, cwd-equal/cwd-prefixed paths, and abbreviated path presentations (`.../` and `…/`) render `zsh — <cwd leaf>` when the shell is known. Meaningful command and agent-step titles render unchanged.
- By Repo suppresses zero-value diff, ahead/behind, and PR chips, including no-upstream placeholders.
- The sort-button spinner regression came from resolving only one of the two sort command destinations during asynchronous presentation refresh. The request now retains both destinations and resolves the next current command from the completed batch, eliminating the transient empty/flickering state while preserving the shared spinning presentation.
- By Tab group headers use the new `AppStyles` muted-primary blue token (RGB `0.38, 0.57, 0.78`). It is neither yellow nor secondary gray; pane leaf glyphs remain monochrome.
- Pane display and ordering now share one nonoptional effective recency date. A never-focused pane falls back to its creation date for both the visible time and All Panes ordering instead of displaying `Now` while sorting as infinitely old.

## Source delivery

- Branch: `feat/sidebar-grouping-rows`
- Toggle-refinement implementation commit: `1c35fed75` — `Refine sidebar grouping toggle states`
- Current remediation commit: `4abb00448` — `Align pane sorting with displayed recency`
- Main implementation commit: `2edc3c77d` — `Polish sidebar grouping controls and activity rows`
- Final gallery commit: `8fa7a3641` — `Add final sidebar grouping proof gallery`
- Earlier feature commits retained in the branch:
  - `c66c12a41` — persisted sidebar grouping in window UI state
  - `c5522513c` — All Panes and By Tab activity projections
  - `ad8bb3427` — initial visual proof
- Draft PR: https://github.com/ShravanSunder/agentstudio/pull/296
- Base: `main`
- Merge: not requested and not performed

## Automated proof

- Focused Swift gate:
  - Command: `swift test --build-path .build-agent-1 --filter 'RepoExplorerViewProjectionHelperTests|RepoExplorerCommandPresentationBatchTests|RepoExplorerPaneProjectionTests|RepoExplorerWorktreeRowTests|SidebarSourceGroupHeaderTests|SidebarSurfaceConvergenceTests|RepoExplorerHotPathArchitectureTests' --skip WebKitSerializedTests --skip E2ESerializedTests --skip ZmxE2ETests`
  - Result: exit 0; 69 tests in 7 suites passed.
- Lint gate:
  - Command: `mise run lint`
  - Result: exit 0; swift-format passed, SwiftLint reported 0 violations across 2,032 files, architecture lint passed, and release-script verification passed.
- Full local PR gate:
  - Command: `SWIFT_TEST_TIMEOUT_SECONDS=2700 SWIFT_TEST_PREBUILD_TIMEOUT_SECONDS=1800 mise run test`
  - Result: exit 0 in 308.73 seconds.
  - BridgeWeb: 1,713 unit, 22 integration, 194 browser passed with 5 skipped, and 4 Vite E2E tests passed.
  - Swift: 5,954 fast-lane tests in 781 suites, 477 aggregate tests in 70 suites, 4 serial process tests, all serialized WebKit tests, and all general E2E tests passed.
- Diff integrity: `git diff --check` exited 0.
- One prior unchanged full-gate attempt hit an unrelated transient BridgeWeb comparison-control browser-test timeout. The exact focused file immediately passed 14/14, and the required complete command above then passed without source changes.

## Native computer-use proof

- Exact app: `Agent Studio Debug jp6s` (`com.agentstudio.app.debug.djp6s`).
- Display: second monitor, identical 1× capture scale for all full gallery frames.
- Positive PR fixture: the real `agent-studio.sidebar-grouping` worktree on `feat/sidebar-grouping-rows`, whose cached PR count was 1.
- All Panes exposed `agent-studio.sidebar-grouping · Pane 1, zsh — agent-studio.sidebar-grouping, 1 pull requests, <time>, Active` in the accessibility tree and rendered `PR 1 · time · active dot` in the trailing cluster.
- By Tab exposed the same positive PR count on its pane row beneath the muted-blue tab header.
- By Repo showed both clean/synced rows without zero chips and dirty rows with non-zero chips; the positive fixture rendered PR count 1.
- The title decision is visible across the pane modes: path-only titles render shell/cwd-leaf fallbacks rather than raw or abbreviated paths.
- Sort interaction was exercised twice on exact jp6s PID `69452`; the same accessible `repoSidebarSortButton` remained mounted while its typed help value changed `Sort descending` → `Sort ascending` → `Sort descending`, with no empty/flickering control state observed. That exact PID was then terminated and confirmed absent.
- Persistence restart: By Tab was selected on PID `35491`; that exact PID was terminated, the same jp6s app relaunched as PID `61978`, and accessibility still reported the By Tab segment selected before any mode interaction.
- Fresh runtime marker: `debug-observability-jp6s-1786888500-52189`.
- `mise run verify-debug-observability` exited 0 for PID `61978`, launch method LaunchServices, background activation, authenticated IPC, and `app.did_finish_launching.succeeded` from VictoriaLogs.
- Exact PID `61978` was terminated after capture and verification and confirmed absent. No other AgentStudio process was touched.

## Measured spacing parity

The side-by-side artifact uses 2× sidebar crops made from equal-size 1× full-monitor captures. Measurements use the shared crop coordinate space:

- Section header baseline: y=84–85 px across the three modes; maximum spread 1 px.
- First group-label baseline: y=101 px in all three modes; spread 0 px. Leading x=35–36 px; spread 1 px.
- First child title baseline: y=120–123 px; maximum spread 3 px. Leading x=22–25 px; maximum spread 3 px.

Those differences are glyph rasterization/row-content bounds within the same AppStyles spacing tokens; no mode-specific vertical spacing remains.

## Final gallery

- `01-all-panes-second-monitor.png` / `01-all-panes-sidebar.png` — All Panes, including the positive PR row and path-title fallback.
- `02-by-repo-dirty-clean-second-monitor.png` / `02-by-repo-dirty-clean-sidebar.png` — dirty-versus-clean By Repo rows and zero suppression.
- `03-by-repo-pr-chip-second-monitor.png` / `03-by-repo-pr-chip-sidebar.png` — filtered positive PR fixture in By Repo.
- `04-by-tab-second-monitor.png` / `04-by-tab-sidebar.png` — By Tab with muted-primary header icon and positive PR trailing cluster.
- `05-by-tab-persistence-restart-second-monitor.png` / `05-by-tab-persistence-restart-sidebar.png` — By Tab selected after the fresh-process restart.
- `06-three-mode-spacing-comparison.png` — labeled, identical-scale All Panes / By Repo / By Tab comparison used for the measurements above.
- `07-by-tab-header-token-close-up.png` — muted-primary tab-header icon close-up.
- `08-by-repo-pr-chip-close-up.png` — positive PR chip close-up.
- `09-by-repo-dirty-clean-close-up.png` — dirty-versus-clean zero-suppression close-up.
- `10-by-tab-pr-chip-second-monitor.png` — dedicated positive-PR By Tab full-monitor frame.
- `11-all-panes-pr-chip-second-monitor.png` — dedicated positive-PR All Panes full-monitor frame.

All files are under `tmp-screenshots/final/`. `tmp-screenshots/initial-capture/` and `tmp-screenshots/polish/` are prior local working galleries and are intentionally excluded from delivery.

## Review disposition

- Accepted and fixed: abbreviated `.../` and `…/` path-shaped titles now take the fallback path, with permanent tests.
- Accepted and proven: positive PR chips are present in native All Panes and By Tab captures using a real count of 1.
- Accepted and fixed red-first: never-focused panes now use the same effective recency date for display and activity ordering. The new test failed against the nullable sort fact and passed after the nonoptional fact cutover.
- Rejected as outside the agreed contract: rewriting the already keyed, cached, equality-suppressed projection into a new single-row recomputation owner. The named hot-path architecture tests pass and the brief did not require a new ownership seam.
- Rejected as contrary to the repository hard-cut rule: migrating the retired repository-scoped grouping preference into the new window-scoped owner. The new owner persists steady-state selection and the restart proof passes; there is no compatibility lane.

## PR handoff

- Commit `1c35fed75` was pushed to `origin/feat/sidebar-grouping-rows`, updating draft PR #296.
- Remote head matched `1c35fed75998856b0de1f8f1ebcdfe0ca542c61d`; the PR was `MERGEABLE` against `main` and remained draft.
- CI run `31957373649` completed green: Code quality 3m50s, BridgeWeb validation 4m06s, BridgeWeb Swift backend 9m01s, and Swift test suite 23m06s.
- The PR had no comments, reviews, or review threads requiring action at final inspection.
- Merge was not requested and was not performed.
