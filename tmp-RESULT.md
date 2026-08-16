# RESULT: Sidebar contract final validation

Status: PASS. All 19 contract items and every applicable final chip-matrix cell pass on the origin/main-merged build.

## 2026-08-16 merged-build checklist

| Item | Evidence file | Result |
|---:|---|---|
| 1 | `tmp-screenshots/contract-final/41-chip-matrix-final-by-repo.png` | PASS — By Repo retains worktree name, branch line, and L3 chips. |
| 2 | `tmp-screenshots/contract-final/42-chip-matrix-final-all-panes.png` | PASS — All Panes groups all three real panes under their repository and orders the activity rows. |
| 3 | `tmp-screenshots/contract-final/35-chip-matrix-by-tab.png` | PASS — By Tab renders the tab header, pane count, muted-primary icon, and all pane rows. |
| 4 | `tmp-screenshots/contract-final/42-chip-matrix-final-all-panes.png`; `tmp-screenshots/contract-final/35-chip-matrix-by-tab.png` | PASS — both pane modes render `Pane <n> · <terminal title>` on L1. |
| 5 | `tmp-screenshots/contract-final/42-chip-matrix-final-all-panes.png`; `tmp-screenshots/contract-final/35-chip-matrix-by-tab.png` | PASS — Pane 2 renders the real inbox-pipeline body `Content-bearing inbox proof` in both modes; other panes use `output activity` or `No activity yet`, never `New terminal activity`. |
| 6 | `tmp-screenshots/contract-final/42-chip-matrix-final-all-panes.png`; `tmp-screenshots/contract-final/35-chip-matrix-by-tab.png` | PASS — every pane row has a time pill, the real PR row has `⑂1`, and only the focused Bridge pane has `● active`. |
| 7 | `tmp-screenshots/contract-final/41-chip-matrix-final-by-repo.png` | PASS — real dirty `01-dirty` renders `● +2 -1`; `02-untracked` renders `● untracked`; `04-clean` has no diff chip. |
| 8 | `tmp-screenshots/contract-final/41-chip-matrix-final-by-repo.png` | PASS — real divergent `03-sync` renders `↑1 ↓1`; no zero or unknown sync chip is present elsewhere. |
| 9 | `tmp-screenshots/contract-final/41-chip-matrix-final-by-repo.png`; `tmp-screenshots/contract-final/42-chip-matrix-final-all-panes.png`; `tmp-screenshots/contract-final/35-chip-matrix-by-tab.png`; `Tests/AgentStudioTests/Features/RepoExplorer/RepoExplorerWorktreeRowTests.swift` | PASS — real open PR #296 materializes as `⑂1` in By Repo, All Panes, and By Tab; mounted positive-count automated proof is green. |
| 10 | `tmp-screenshots/contract-final/36-toggle-by-repo-frame-1.png`; `36-toggle-by-repo-frame-2.png`; `36-toggle-by-repo-frame-3.png`; `36-toggle-by-repo-settled.png`; corresponding `37-toggle-all-panes-*` and `38-toggle-by-tab-*` files | PASS — all three settled selections have accent icon plus accent label, no border; frame sequences show stable fill/icon transition followed by delayed soft label reveal. |
| 11 | `tmp-screenshots/contract-final/39-sort-ascending.png`; `40-sort-frame-1.png`; `40-sort-frame-2.png`; `40-sort-descending.png` | PASS — one stable sort-button identity rotates without disappearance or flicker. |
| 12 | `tmp-screenshots/contract-final-merged/01-by-repo-settled.png`; `Tests/AgentStudioTests/Features/RepoExplorer/RepoExplorerViewTests.swift` | PASS — window-scoped grouping selection restores on relaunch and remains covered by the persistence suite. |
| 13 | `tmp-screenshots/contract-final/30-empty-by-repo.png`; `31-empty-all-panes.png`; `32-empty-by-tab.png` | PASS — true `No repositories`, `No panes`, and `No tabs` states are captured without a search filter; pane empties were reached after semantic pane closure. |
| 14 | `tmp-screenshots/contract-final/41-chip-matrix-final-by-repo.png`; `42-chip-matrix-final-all-panes.png`; `35-chip-matrix-by-tab.png` | PASS — three-line row height and vertical rhythm match across modes on main's dark styling. |
| 15 | `Tests/AgentStudioTests/Features/RepoExplorer/RepoExplorerViewTests.swift`; full aggregate gate | PASS — existing context menus and typed command routes remain green. |
| 16 | `Tests/AgentStudioTests/Features/RepoExplorer/RepoExplorerViewProjectionHelperTests.swift`; `RepoExplorerWorktreeRowTests.swift`; full architecture lint | PASS — all row values are cached keyed projection reads; no per-row path derivation was introduced. |
| 17 | `tmp-screenshots/contract-final/44-alignment-by-repo-x21.png`; `45-alignment-all-panes-x27.png`; `46-alignment-by-tab-x27.png`; `Sources/AgentStudio/SharedComponents/Sidebar/SidebarTextColumnAlignment.swift` | PASS — headers and rows use the one shared icon-to-text spacing token; annotated crops preserve the same icon/text relationship. |
| 18 | `tmp-screenshots/contract-final/44-alignment-by-repo-x21.png`; `45-alignment-all-panes-x27.png`; `46-alignment-by-tab-x27.png` | PASS — measured guides intersect each representative row's L1/L2/L3 leading edge: source x=21 px in the By Repo hierarchy and source x=27 px in both pane hierarchies; within-row delta is 0 px. |
| 19 | `tmp-screenshots/contract-final/41-chip-matrix-final-by-repo.png`; `44-alignment-by-repo-x21.png` | PASS — stale rows end with a quiet bare hollow SF Symbol, separate from the pill facts, with no pill/background/border; refreshing remains deferred. |

## Current gates

- Focused: `mise run test:swift -- --filter "RepoExplorerWorktreeRowTests|RepoExplorerPaneProjectionTests|RepoExplorerViewTests|RepoExplorerViewProjectionHelperTests"` — exit 0; 76 tests in 4 suites.
- Lint: `mise run lint` — exit 0; swift-format, SwiftLint (0 violations in 2,056 files), architecture lint, and release checks passed.
- Full aggregate: `SWIFT_TEST_TIMEOUT_SECONDS=2700 SWIFT_TEST_PREBUILD_TIMEOUT_SECONDS=1800 mise run test` — exit 0 in 268.72 seconds.
- Runtime: exact merged-build LaunchServices PID `91548`, marker `debug-observability-jp6s-1786923595-88937`; detached/background-only capture; PID terminated with TERM after evidence.

## CHIP MATRIX (final gate)

| Surface / cell | Evidence | Result |
|---|---|---|
| By Repo — dirty diff `● +N -M` | `41-chip-matrix-final-by-repo.png`: `01-dirty` = `● +2 -1` | PASS |
| By Repo — untracked-only | `41-chip-matrix-final-by-repo.png`: `02-untracked` = `● untracked` | PASS |
| By Repo — clean diff absence | `41-chip-matrix-final-by-repo.png`: `04-clean` has no diff pill | PASS |
| By Repo — nonzero sync | `41-chip-matrix-final-by-repo.png`: `03-sync` = `↑1 ↓1` | PASS |
| By Repo — unknown/zero sync absence | `41-chip-matrix-final-by-repo.png`: all non-divergent rows omit sync pills | PASS |
| By Repo — positive PR | `41-chip-matrix-final-by-repo.png`: real PR #296 = `⑂1` | PASS |
| By Repo — stale metadata | `41-chip-matrix-final-by-repo.png`: bare hollow dots follow value pills with no wrapper | PASS |
| All Panes — PR / time / active | `42-chip-matrix-final-all-panes.png`: each row has time, PR-associated panes have `⑂1`, focused pane alone has `● active` | PASS |
| By Tab — PR / time / active | `35-chip-matrix-by-tab.png`: each row has time, PR-associated panes have `⑂1`, focused pane alone has `● active` | PASS |
| Universal — no zero/dot-alone facts | `41-chip-matrix-final-by-repo.png` clean/unknown rows; focused automated row suite | PASS |
| Universal — measured L1/L2/L3 alignment | `44-alignment-by-repo-x21.png`; `45-alignment-all-panes-x27.png`; `46-alignment-by-tab-x27.png` | PASS |
| Universal — same pill style and sizing | `41-chip-matrix-final-by-repo.png`; `42-chip-matrix-final-all-panes.png`; `35-chip-matrix-by-tab.png` | PASS |
| Universal — cached keyed reads | `RepoExplorerViewProjectionHelperTests.swift`; `RepoExplorerWorktreeRowTests.swift`; architecture lint | PASS |
