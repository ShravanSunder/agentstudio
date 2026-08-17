# RESULT: Sidebar contract final validation

Status: BLOCKED-ON-DESIGN. Item 5 fails on the origin/main-merged build because the existing terminal activity pipeline carries output geometry, not terminal content. The other recorded contract and chip-matrix results are unchanged.

## 2026-08-16 merged-build checklist

| Item | Evidence file | Result |
|---:|---|---|
| 1 | `tmp-screenshots/contract-final/41-chip-matrix-final-by-repo.png` | PASS — By Repo retains worktree name, branch line, and L3 chips. |
| 2 | `tmp-screenshots/contract-final/42-chip-matrix-final-all-panes.png` | PASS — All Panes groups all three real panes under their repository and orders the activity rows. |
| 3 | `tmp-screenshots/contract-final/35-chip-matrix-by-tab.png` | PASS — By Tab renders the tab header, pane count, muted-primary icon, and all pane rows. |
| 4 | `tmp-screenshots/contract-final/42-chip-matrix-final-all-panes.png`; `tmp-screenshots/contract-final/35-chip-matrix-by-tab.png` | PASS — both pane modes render `Pane <n> · <terminal title>` on L1. |
| 5 | Source trace: `GhosttyActionRouter+ObservedActions.swift`, `TerminalActivityProjector.swift`, `TerminalActivityRouter.swift`, `InboxNotificationRouter.swift`, `InboxPromoter.swift`, `InboxNotificationAtom.swift` | BLOCKED-ON-DESIGN — real shell output never enters the inbox payload. The activity lane contracts scrollbar samples to row counts and timing; settled promotions write `body: nil`, so L2 correctly falls back to `output activity` for every ordinary command. The prior synthetic OSC desktop notification and screenshots are invalid and removed from item-5 evidence. A new admitted terminal-content seam is required before real output can populate L2. |
| 6 | `tmp-screenshots/contract-final/42-chip-matrix-final-all-panes.png`; `tmp-screenshots/contract-final/35-chip-matrix-by-tab.png` | PASS — every pane row has a time pill, the real PR row has `⑂1`, and only the focused Bridge pane has `● active`. |
| 7 | `tmp-screenshots/contract-final/41-chip-matrix-final-by-repo.png` | PASS — real dirty `01-dirty` renders `● +2 -1`; `02-untracked` renders `● untracked`; `04-clean` has no diff chip. |
| 8 | `tmp-screenshots/contract-final/41-chip-matrix-final-by-repo.png` | PASS — real divergent `03-sync` renders `↑1 ↓1`; no zero or unknown sync chip is present elsewhere. |
| 9 | `tmp-screenshots/contract-final/41-chip-matrix-final-by-repo.png`; `tmp-screenshots/contract-final/42-chip-matrix-final-all-panes.png`; `tmp-screenshots/contract-final/35-chip-matrix-by-tab.png`; `Tests/AgentStudioTests/Features/RepoExplorer/RepoExplorerWorktreeRowTests.swift` | PASS — real open PR #296 materializes as `⑂1` in By Repo, All Panes, and By Tab; mounted positive-count automated proof is green. |
| 10 | `tmp-screenshots/contract-final/toggle-burst/repo-to-pane-frame-00.png` through `repo-to-pane-frame-14.png`; `pane-to-tab-frame-00.png` through `pane-to-tab-frame-14.png`; both `*-detail-sheet.png` contact sheets; `SidebarToolbarControlVisualStateTests.swift` | PASS — two PID/window-ID-bound 15-frame bursts on the merged build prove one geometry transaction followed by the delayed label reveal. Repo→pane: 00–03 settled By Repo; 04 outgoing-label fade and width change begins; 05 neighbor interpolation continues; 06–07 pane fill/accent icon complete with incoming text still absent; 08 `All Panes` is partial-opacity/offset; 09–14 fully settled. Pane→tab: 00–02 settled All Panes; 03 outgoing fade begins; 04–05 width/fill and neighbor positions interpolate; 06 tab fill/accent icon is complete with no label; 07 `By Tab` is partial-opacity/offset; 08–14 fully settled. No frame paints incoming text fully in the selection-change frame, no segment double-jumps, and sort/other toolbar items remain pixel-stable. Stable `ForEach` segment identity is retained and the focused red/green transition test passes. |
| 11 | `tmp-screenshots/contract-final/39-sort-ascending.png`; `40-sort-frame-1.png`; `40-sort-frame-2.png`; `40-sort-descending.png` | PASS — one stable sort-button identity rotates without disappearance or flicker. |
| 12 | `tmp-screenshots/contract-final-merged/01-by-repo-settled.png`; `Tests/AgentStudioTests/Features/RepoExplorer/RepoExplorerViewTests.swift` | PASS — window-scoped grouping selection restores on relaunch and remains covered by the persistence suite. |
| 13 | `tmp-screenshots/contract-final/30-empty-by-repo.png`; `31-empty-all-panes.png`; `32-empty-by-tab.png` | PASS — true `No repositories`, `No panes`, and `No tabs` states are captured without a search filter; pane empties were reached after semantic pane closure. |
| 14 | `tmp-screenshots/contract-final/41-chip-matrix-final-by-repo.png`; `42-chip-matrix-final-all-panes.png`; `35-chip-matrix-by-tab.png` | PASS — three-line row height and vertical rhythm match across modes on main's dark styling. |
| 15 | `Tests/AgentStudioTests/Features/RepoExplorer/RepoExplorerViewTests.swift`; full aggregate gate | PASS — existing context menus and typed command routes remain green. |
| 16 | `Tests/AgentStudioTests/Features/RepoExplorer/RepoExplorerViewProjectionHelperTests.swift`; `RepoExplorerWorktreeRowTests.swift`; full architecture lint | PASS — all row values are cached keyed projection reads; no per-row path derivation was introduced. |
| 17 | `tmp-screenshots/contract-final/44-alignment-by-repo-x21.png`; `45-alignment-all-panes-x27.png`; `46-alignment-by-tab-x27.png`; `Sources/AgentStudio/SharedComponents/Sidebar/SidebarTextColumnAlignment.swift` | PASS — headers and rows use the one shared icon-to-text spacing token; annotated crops preserve the same icon/text relationship. |
| 18 | `tmp-screenshots/contract-final/44-alignment-by-repo-x21.png`; `45-alignment-all-panes-x27.png`; `46-alignment-by-tab-x27.png` | PASS — measured guides intersect each representative row's L1/L2/L3 leading edge: source x=21 px in the By Repo hierarchy and source x=27 px in both pane hierarchies; within-row delta is 0 px. |
| 19 | `tmp-screenshots/contract-final/item19-pending-animation/pending-phase-0.png` through `pending-phase-3.png`; corresponding `*-detail.png` and `*-glyph-10x.png`; `RepoExplorerWorktreeRowTests.swift` | FAIL — implementation and pending-animation proof pass: the bare `circle.dotted` uses `.symbolEffect(.variableColor.iterative, options: .repeating.speed(0.35))`, stays secondary/chip-height with no wrapper, and the 0.5-second burst alternates visibly different render phases (frames 0/2 brighter, 1/3 dimmer) without `rotationEffect`, `repeatForever`, or per-frame MainActor work. Known-value branching remains automated: nil renders the glyph, positive renders `⑂N`, zero renders nothing. The required live post-fetch disappearance shot is not yet proven: the real visible `agent-studio/main` row remained pending through the bounded Forge observation, so those attempted samples were removed rather than mislabeled. |

### Item 10 burst frame inspection

| Frame | Repo → All Panes | All Panes → By Tab |
|---:|---|---|
| 00 | Settled By Repo baseline. | Settled All Panes baseline. |
| 01 | Settled By Repo baseline. | Settled All Panes baseline. |
| 02 | Settled By Repo baseline. | Settled All Panes baseline. |
| 03 | Settled By Repo baseline. | Outgoing `All Panes` opacity starts decreasing; geometry begins. |
| 04 | Outgoing `By Repo` opacity decreases; pane segment starts widening. | Outgoing label fades further; tab icon moves left continuously as its segment widens. |
| 05 | Repo segment contracts and pane segment widens in the same interpolation; no incoming label. | Tab fill/width continues to interpolate; no incoming label. |
| 06 | Pane fill and accent icon are selected; incoming label remains absent. | Tab fill and accent icon are selected; incoming label remains absent. |
| 07 | Pane geometry is complete; incoming label remains absent. | `By Tab` begins at partial opacity with the insertion offset. |
| 08 | `All Panes` begins at partial opacity with the insertion offset. | `By Tab` reaches full opacity; geometry does not move again. |
| 09 | `All Panes` reaches full opacity; geometry does not move again. | Settled By Tab. |
| 10 | Settled All Panes. | Settled By Tab. |
| 11 | Settled All Panes. | Settled By Tab. |
| 12 | Settled All Panes. | Settled By Tab. |
| 13 | Settled All Panes. | Settled By Tab. |
| 14 | Settled All Panes; no toolbar flicker. | Settled By Tab; no toolbar flicker. |

### Item 5 real terminal-content pipeline diagnosis

The owner-visible failure is deterministic: builds, `ls`, and Git commands update terminal scrollback, but their output text never reaches an inbox notification.

Current path:

1. Ghostty's observed action path carries text only for explicit `.desktopNotification(title:body:)` actions. Normal terminal rendering emits scrollbar state and command-finished metadata, not output bytes or rendered lines.
2. `TerminalActivityProjector` contracts high-frequency scrollbar samples into `TerminalSettledActivity`. That value contains row counts, timestamps, thresholds, and pinned-to-bottom state; it has no text field.
3. `TerminalActivityRouter` posts the same text-free settled activity through the runtime bus.
4. `InboxNotificationRouter` admits the settled event, and `InboxPromoter.promoteSettledActivity` deliberately constructs the notification with `body: nil` and title `New terminal activity`.
5. `InboxNotificationAtom.recalculateLatestPaneMessages` accepts only content-bearing notification bodies. With no body, it materializes the keyed row fallback `output activity`.

What carries content today:

- Explicit Ghostty desktop notifications (OSC notification payloads) carry caller-supplied title/body text.
- Agent RPC notifications carry their supplied body.
- Some semantic events synthesize metadata bodies, for example command exit code and duration. They do not contain terminal output.

What drops content:

- No existing event drops a meaningful output line, because no existing production seam captures one. The terminal activity ingress observes only scrollbar geometry; the settled activity contraction and inbox promotion therefore have no content to preserve.
- The prior `Content-bearing inbox proof` evidence was an injected OSC desktop notification. It proved the existing body renderer, not the normal terminal-output pipeline, and is not product evidence.

Design seams requiring owner ratification:

- Settled-burst snapshot: at the existing quiet-boundary admission, ask the terminal owner for one bounded rendered-line snapshot, normalize ANSI/control content off MainActor, then attach the contracted result to `TerminalSettledActivity`. This minimizes sampling but requires a new Ghostty read API, thread-safety/currentness rules, content privacy limits, and typed failure behavior.
- PTY/zmx output contraction: admit terminal bytes before rendering and maintain a per-pane bounded meaningful-line projector. This covers arbitrary output but creates a new high-volume lane with ANSI parsing, prompt/progress-line replacement semantics, backpressure, secret/privacy handling, lifecycle cleanup, and equality suppression.
- Shell-integration semantic emission: have supported shells emit a bounded completed-command/output summary through an explicit control sequence. This is lower volume and typed, but incomplete for unsupported shells/programs and requires a trustworthy definition of which line represents the command result.

No implementation was attempted because all three options create a new terminal-to-state content lane or extend terminal integration authority. The contract requires owner-approved source, admission, contraction, privacy, and publication semantics first.

## Current gates

- Focused item 19: `mise run test:swift -- --filter "RepoExplorerWorktreeRowTests"` — exit 0; 19 tests in 1 suite after a red run failed on the missing dotted symbol/effect.
- Focused item 10: `mise run test:swift -- --filter "SidebarToolbarControlVisualStateTests"` — exit 0; 6 tests in 1 suite, including the red/green delayed-label transition contract.
- Prior focused sidebar projection gate: `mise run test:swift -- --filter "RepoExplorerWorktreeRowTests|RepoExplorerPaneProjectionTests|RepoExplorerViewTests|RepoExplorerViewProjectionHelperTests"` — exit 0; 76 tests in 4 suites.
- Lint: `mise run lint` — exit 0; swift-format, SwiftLint (0 violations in 2,056 files), architecture lint, and release checks passed.
- Full aggregate: `SWIFT_TEST_TIMEOUT_SECONDS=2700 SWIFT_TEST_PREBUILD_TIMEOUT_SECONDS=1800 mise run test` — exit 0 in 224.03 seconds on the item-19 implementation.
- Runtime: exact merged-build LaunchServices PID `63971`, marker `debug-observability-jp6s-1786925576-63062`; Peekaboo mapped the PID to on-screen window `106078`; grouping changes used authenticated read-back; capture remained detached/background-only; PID terminated with TERM after evidence.

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
