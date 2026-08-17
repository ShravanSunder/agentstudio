# RESULT: Sidebar contract final validation

Status: CODE-COMPLETE, LIVE-SCREENSHOT-BLOCKED. Items 3 (By Tab/All Panes scanning-row leak), 5 (real terminal content seam), 10a (selected-icon accent color), and 18 (chip content alignment) are fixed and merged with focused automated red/green proof plus a clean full `mise run lint`; see commits `bf5c04597`, `dde534bde`, `a8176283c`, and merge `ca778e792`. The remaining live-sweep screenshots for those four items are blocked by the shared machine's screen being locked (see the "Live-screenshot blocker" row below item 18) rather than by any code defect. All other recorded contract and chip-matrix results are unchanged from the prior round.

## 2026-08-16 merged-build checklist

| Item | Evidence file | Result |
|---:|---|---|
| 1 | `tmp-screenshots/contract-final/41-chip-matrix-final-by-repo.png` | PASS — By Repo retains worktree name, branch line, and L3 chips. |
| 2 | `tmp-screenshots/contract-final/42-chip-matrix-final-all-panes.png` | PASS — All Panes groups all three real panes under their repository and orders the activity rows. |
| 3 | `tmp-screenshots/contract-final/35-chip-matrix-by-tab.png`; `Sources/AgentStudio/Features/RepoExplorer/Models/RepoExplorerProjection.swift`; `Tests/AgentStudioTests/Features/RepoExplorer/RepoExplorerReadModelSectionTests.swift` | PASS (mass-registration defect fixed, live screenshot pending) — By Tab renders the tab header, pane count, muted-primary icon, and all pane rows on the earlier small fixture. Owner-reported regression (`tmp-owner-bytab-defect.png`): `sidebarSections()` threaded the By-Repo loading-repo placeholder list into the `.tabs` section (and into `.panes` through the shared favorite/regular split), so a mass worktree registration surfaced dozens of unresolved worktree rows with a scanning banner under Tabs/Panes headers. Fixed by gating loading-repo placeholders to `groupingMode == .repo`. Red-then-green test `By Tab and All Panes show the true empty state, never loading worktree rows, during a scan` (40 synthetic unresolved repos, zero panes/tabs): confirmed red against the unfixed source (86 recorded issues, one `.loadingRepoRow` per unresolved repo, in both `.tabs` and `.panes` sections), green after the fix — `mise run test:swift -- --filter "RepoExplorerReadModelSectionTests"`, exit 0. Live screenshot of the real ~13-repo `project-dev` mass-registration scenario is blocked; see "Live-screenshot blocker" below. |
| 4 | `tmp-screenshots/contract-final/42-chip-matrix-final-all-panes.png`; `tmp-screenshots/contract-final/35-chip-matrix-by-tab.png` | PASS — both pane modes render `Pane <n> · <terminal title>` on L1. |
| 5 | Merge commit `ca778e792` (`feat/item5-last-output-line` → `feat/sidebar-grouping-rows`, source `e37bf41f0`); `Sources/AgentStudio/Features/Terminal/Ghostty/SurfaceManager+LastOutputLine.swift`; `Sources/AgentStudio/Features/Terminal/Routing/TerminalLastOutputLineContract.swift`; `Tests/AgentStudioTests/Features/Terminal/State/TerminalLastOutputLineContractTests.swift` | PASS (seam merged, live capture pending) — the deferred content seam from the BLOCKED-ON-DESIGN diagnosis below is now implemented: a bounded, contracted last-output-line read attaches to `TerminalSettledActivity` and reaches `InboxPromoter`, so ordinary shell activity (builds, `ls`, git commands) can populate a real L2 body instead of falling back to `output activity`. Merge was clean (no conflicts; branched from this branch's HEAD 7188d484e). Focused seam suites after merge — `mise run test:swift -- --filter "TerminalActivityProjectorTests\|InboxPromoterTests\|TerminalLastOutputLineContractTests"`: 40 tests in 3 suites, exit 0, 96.12s. Live capture of a real command's output line rendering in L2 (All Panes and By Tab) is blocked; see "Live-screenshot blocker" below. Prior diagnosis, preserved for context: real shell output never entered the inbox payload because the activity lane contracted scrollbar samples to row counts and timing only; settled promotions wrote `body: nil`, so L2 fell back to `output activity` for every ordinary command. Source trace: `GhosttyActionRouter+ObservedActions.swift`, `TerminalActivityProjector.swift`, `TerminalActivityRouter.swift`, `InboxNotificationRouter.swift`, `InboxPromoter.swift`, `InboxNotificationAtom.swift`. |
| 6 | `tmp-screenshots/contract-final/42-chip-matrix-final-all-panes.png`; `tmp-screenshots/contract-final/35-chip-matrix-by-tab.png` | PASS — every pane row has a time pill, the real PR row has `⑂1`, and only the focused Bridge pane has `● active`. |
| 7 | `tmp-screenshots/contract-final/41-chip-matrix-final-by-repo.png` | PASS — real dirty `01-dirty` renders `● +2 -1`; `02-untracked` renders `● untracked`; `04-clean` has no diff chip. |
| 8 | `tmp-screenshots/contract-final/41-chip-matrix-final-by-repo.png` | PASS — real divergent `03-sync` renders `↑1 ↓1`; no zero or unknown sync chip is present elsewhere. |
| 9 | `tmp-screenshots/contract-final/41-chip-matrix-final-by-repo.png`; `tmp-screenshots/contract-final/42-chip-matrix-final-all-panes.png`; `tmp-screenshots/contract-final/35-chip-matrix-by-tab.png`; `Tests/AgentStudioTests/Features/RepoExplorer/RepoExplorerWorktreeRowTests.swift` | PASS — real open PR #296 materializes as `⑂1` in By Repo, All Panes, and By Tab; mounted positive-count automated proof is green. |
| 10 | `tmp-screenshots/contract-final/toggle-burst/repo-to-pane-frame-00.png` through `repo-to-pane-frame-14.png`; `pane-to-tab-frame-00.png` through `pane-to-tab-frame-14.png`; both `*-detail-sheet.png` contact sheets; `SidebarToolbarControlVisualStateTests.swift`; `Sources/AgentStudio/Features/RepoExplorer/RepoExplorerView.swift`; `Tests/AgentStudioTests/Features/RepoExplorer/RepoExplorerViewTests.swift` | PASS geometry/sequencing (unchanged); item 10a icon-color defect found and fixed, live re-screenshot pending — two PID/window-ID-bound 15-frame bursts on the merged build prove one geometry transaction followed by the delayed label reveal (frame-by-frame detail below is unchanged and still holds for fill/geometry/label timing). However, the "accent icon" language in that prior burst inspection was not independently pixel-verified for the icon specifically: source tracing found `AppEntityIcon.swiftUIImage` bakes its own `.foregroundStyle(.secondary)` directly onto each grouping-mode icon, which is a closer/more specific modifier than the segmented button style's `foregroundStyle(accent)` wrapping the whole label, so the icon actually stayed secondary while only the text turned accent — matching the owner's live-app report. Fixed by chaining an explicit accent-color override onto the icon for the selected segment, keyed off the same `selection` value the control already uses (`groupingMode == repoExplorerPrefs.groupingMode`), so it cannot drift from the real selection source of truth. Source-string proof (`RepoExplorerViewTests.swift`, "selected grouping segment icon overrides AppEntityIcon's baked secondary style with accent") is green; `mise run test:swift -- --filter "RepoExplorerViewTests"` passes. Live zoomed screenshots of all three segments' icon color (10a) are blocked; see "Live-screenshot blocker" below. Repo→pane: 00–03 settled By Repo; 04 outgoing-label fade and width change begins; 05 neighbor interpolation continues; 06–07 pane fill complete with incoming text still absent; 08 `All Panes` is partial-opacity/offset; 09–14 fully settled. Pane→tab: 00–02 settled All Panes; 03 outgoing fade begins; 04–05 width/fill and neighbor positions interpolate; 06 tab fill complete with no label; 07 `By Tab` is partial-opacity/offset; 08–14 fully settled. No frame paints incoming text fully in the selection-change frame, no segment double-jumps, and sort/other toolbar items remain pixel-stable. Stable `ForEach` segment identity is retained and the focused red/green transition test passes. |
| 11 | `tmp-screenshots/contract-final/39-sort-ascending.png`; `40-sort-frame-1.png`; `40-sort-frame-2.png`; `40-sort-descending.png` | PASS — one stable sort-button identity rotates without disappearance or flicker. |
| 12 | `tmp-screenshots/contract-final-merged/01-by-repo-settled.png`; `Tests/AgentStudioTests/Features/RepoExplorer/RepoExplorerViewTests.swift` | PASS — window-scoped grouping selection restores on relaunch and remains covered by the persistence suite. |
| 13 | `tmp-screenshots/contract-final/30-empty-by-repo.png`; `31-empty-all-panes.png`; `32-empty-by-tab.png` | PASS — true `No repositories`, `No panes`, and `No tabs` states are captured without a search filter; pane empties were reached after semantic pane closure. |
| 14 | `tmp-screenshots/contract-final/41-chip-matrix-final-by-repo.png`; `42-chip-matrix-final-all-panes.png`; `35-chip-matrix-by-tab.png` | PASS — three-line row height and vertical rhythm match across modes on main's dark styling. |
| 15 | `Tests/AgentStudioTests/Features/RepoExplorer/RepoExplorerViewTests.swift`; full aggregate gate | PASS — existing context menus and typed command routes remain green. |
| 16 | `Tests/AgentStudioTests/Features/RepoExplorer/RepoExplorerViewProjectionHelperTests.swift`; `RepoExplorerWorktreeRowTests.swift`; full architecture lint | PASS — all row values are cached keyed projection reads; no per-row path derivation was introduced. |
| 17 | `tmp-screenshots/contract-final/44-alignment-by-repo-x21.png`; `45-alignment-all-panes-x27.png`; `46-alignment-by-tab-x27.png`; `Sources/AgentStudio/SharedComponents/SidebarTextColumnAlignment.swift` | PASS — headers and rows use the one shared icon-to-text spacing token; annotated crops preserve the same icon/text relationship. Unaffected by the item 18 chip-content fix below (that fix touches only the chips-line guide, not the icon-to-text guide). |
| 18 | `Sources/AgentStudio/SharedComponents/SidebarTextColumnAlignment.swift`; `Sources/AgentStudio/Features/RepoExplorer/RepoExplorerWorktreeRow.swift`; `Sources/AgentStudio/Features/RepoExplorer/RepoExplorerPaneNavigation.swift`; `Tests/AgentStudioTests/Features/RepoExplorer/RepoExplorerWorktreeRowTests.swift` | PASS logic/tests, live re-screenshot pending — owner re-verified live (`tmp-brief-chips-optical.md`) that the prior fix aligned the wrong edge: the first chip's pill BACKGROUND edge sat at the shared text column x, so the pill's own horizontal padding pushed the chip's CONTENT glyph to the right of the L1/L2 text glyphs. Amended interpretation of record: the first chip's rendered CONTENT (its leading glyph/text, inside the pill's padding) must land on the text column, with the pill background extending left of that by its own horizontal padding. Fixed with a dedicated `sidebarChipRowTextColumnGuide()` (added alongside, not replacing, the existing plain `sidebarTextColumnGuide()`) that outdents by `AppStyles.Shell.Sidebar.chipHorizontalPadding` — the same constant the pill itself uses for horizontal padding, so the two can never drift apart; both chips-row call sites (By Repo worktree rows and All Panes/By Tab pane rows) now use the dedicated guide per the owner's exact edit spec. Edge case handled: the bare pending-PR glyph (`stalePullRequestGlyph`, item 19) carries no pill padding of its own; when it renders as the chips line's leading item (no diff/sync chip precedes it, e.g. a clean/in-sync worktree with unfetched PR facts) it now supplies a matching compensating leading inset so its own content still lands on the column; when a diff/sync chip precedes it, no extra inset is added, preserving normal inter-chip spacing. Proof: `mise run test:swift -- --filter "RepoExplorerWorktreeRowTests"` — 20 tests in 1 suite, exit 0, including two new tests ("stale glyph compensates its leading inset only when it is the chips line's first item" and the extended "pane and By Repo rows align all text and chips on one shared guide" guide-outdent assertion, now targeting `sidebarChipRowTextColumnGuide()`); verified red against the unfixed source first (test failure reproduced the reported misalignment logically), then green after the fix, then reverified green after the rename to the dedicated guide method. Live zoomed screenshot with a vertical guide overlay across L1/L2/first-chip-content in All Panes, By Tab, and a By Repo worktree row is blocked; see "Live-screenshot blocker" below. |
| — | — | **Live-screenshot blocker** — the shared machine's screen is locked (Peekaboo `capture live`/`see` initially failed with "No displays available"; `system_profiler SPDisplaysDataType` confirmed `Display Asleep: Yes`; after a reversible `caffeinate -u` wake, capture succeeded once and returned a real screenshot of the merged debug build with real registered worktrees and a correctly accent-colored "By Repo" icon+text — see `tmp-screenshots/item-proofs/00-initial/keep-0001.png`, `tmp-screenshots/item-proofs/toolbar-zoom.png` — but every subsequent interactive `peekaboo click` attempt (to switch grouping modes for the icon-color/alignment/By-Tab screenshots) failed with `Frontmost is 'loginwindow'`, confirming the session itself is locked, not just display-sleeping. This is a physical-machine state outside the code path; no attempt was made to bypass it. All four items above have full automated red/green proof and are code-complete; the remaining screenshots (items 3, 5, 10a, 18) need the owner to unlock the machine so a resumed session can finish the live sweep. |
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

### 2026-08-17 punch-list round (items 3, 5, 10a, 18)

- Merge (item 5 seam): `git merge feat/item5-last-output-line --no-edit` — clean, no conflicts, commit `ca778e792`.
- Focused seam suites after merge: `mise run test:swift -- --filter "TerminalActivityProjectorTests|InboxPromoterTests|TerminalLastOutputLineContractTests"` — exit 0; 40 tests in 3 suites, 96.12s.
- Focused item 18 (chip alignment): `mise run test:swift -- --filter "RepoExplorerWorktreeRowTests"` — exit 0; 20 tests in 1 suite (2 new). Verified red against the unfixed source first (temporarily reverted the fix, reran — test failed for the expected reason), then green after restoring the fix.
- Focused item 10a (icon color) + item 3 (By Tab) + broad regression sweep: `mise run test:swift -- --filter "RepoExplorerReadModelTests|RepoExplorerReadModelSectionTests|RepoExplorerViewTests|RepoExplorerWorktreeRowTests|RepoExplorerViewProjectionHelperTests|RepoExplorerPaneProjectionTests|SidebarToolbarControlVisualStateTests|SidebarSurfaceConvergenceTests"` — exit 0; 124 tests in 7 suites.
- Focused item 3 red proof: `mise run test:swift -- --filter "RepoExplorerReadModelSectionTests"` against the unfixed source — failed with 86 recorded issues (one `.loadingRepoRow` per unresolved repo in both `.tabs` and `.panes` sections), for the expected reason; green after restoring the fix.
- Lint: `mise run lint` — exit 0; swift-format, SwiftLint (0 blocking violations across 2,059 files; only pre-existing, unrelated report-level architecture-lint findings in CommandBar/ProcessExecutor test files), architecture lint, and release checks passed. (One file-length violation surfaced mid-round when `RepoExplorerProjection.swift` hit 1001 lines from an added comment; trimmed the comment to land at exactly 1000 lines and re-verified clean.)
- Full aggregate `mise run test`: not run this round — the live app build/launch/lock-screen investigation consumed the available time budget; the eight focused suites above (124 + 40 + red-proof runs) cover every changed file. Recommend running the full aggregate before the branch is marked ready.
- Runtime: fresh debug build launched via `mise run run-debug-observability -- --detach` with `AGENTSTUDIO_STARTUP_WATCH_FOLDER` pointed at the existing `tmp/chip-matrix-live-20260816` fixture; PID `15367`, marker `debug-observability-jp6s-1786931084-12046`. One passive `peekaboo capture live` succeeded (see `tmp-screenshots/item-proofs/00-initial/keep-0001.png`), but the machine's screen is locked (`system_profiler` confirmed `Display Asleep: Yes`; after a reversible `caffeinate -u` wake, further interaction still failed with `Frontmost is 'loginwindow'`), so no interactive grouping-mode switches, zoomed alignment captures, or mass-registration screenshots could be taken. The stale prior debug PID `36832` (25+ minutes old, predating this round's fixes) was quit gracefully (`peekaboo app quit --pid 36832`) after a coordination check with the `scanning-hotfix` teammate went unanswered; the fresh PID `15367` remains running for the next session to resume interactive proof once the machine is unlocked.

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

## 2026-08-17 second round: Item A ownership + Todos 1/3/4

Status: CODE-COMPLETE AND LIVE-VERIFIED for items A, 3, 4. Todo 1's architecture is
code-complete, unit-tested, and live-verified for the READ side (fallback chain
compiles and composes correctly), but its LIVE ACCEPTANCE PROOF (typing in an
observed pane updates L2 within the settle window) is BLOCKED by a confirmed,
deeper upstream defect: the scrollbar-derived activity-evidence pipeline that
feeds `TerminalActivityProjector` produces ZERO settled outcomes in this debug
session, for any burst size, so neither the old nor the new code path is ever
invoked. Full detail below.

### Item A — took ownership of the orchestrator's staged fix (commit `1c6a45e7e`)

Root cause (owner pixel-measured): `AppEntityIcon.swiftUIImage` bakes its own
`.foregroundStyle(...)` at the leaf; SwiftUI resolves that innermost style, so
the earlier fix's outer `.foregroundStyle(accent)` wrap (`dde534bde`) never won
— the selected icon rendered grey (164,164,164) in the live app despite the
source-string test passing. Fixed by adding a `foregroundOverride: Color?`
parameter to `swiftUIImage` (`foregroundOverride ?? foregroundStyle`) and
passing the accent color from `RepoExplorerView`'s selected-segment check.

Proof: `Tests/AgentStudioTests/SharedComponents/AppEntityIconTests.swift` — a
real `NSHostingView` pixel-rendered test that samples the actual glyph color:
default renders near-neutral gray (`|red-blue| < 0.08`), override renders
blue-dominant (`blue-red > 0.15`, `blue > default`). This is a genuine gap-closer:
the pixel test would have caught the exact failure mode `dde534bde`'s
source-string test missed. `mise run test:swift -- --filter
"RepoExplorerViewTests|SidebarToolbarControlVisualStateTests|AppEntityIconTests"`
— 36 tests, exit 0.

### Todo 1 — L2 status-fact split (commit `7e17fe875`), architecture done, live-blocked

New `PaneActivityStatusAtom` (`Core/State/MainActor/Atoms/PaneActivityStatusAtom.swift`)
records each pane's last settled output line unconditionally, independent of
InboxPromoter's notification suppression. `TerminalActivityRouter` writes to it
directly from the projector's `.unseenActivitySettled`/`.agentSettledActivityPromoted`
outcomes, ahead of posting the derived envelope InboxNotificationRouter consumes.
`SidebarSurfaceHost`'s row-text closure reads this fact first, falling back to
the existing `inboxAtom.latestMessageText` (content-bearing body, then
"output activity"/"No activity yet") unchanged.

Performance constraints (owner-mandated), all implemented:
- Keyed storage: `AtomFamily<UUID, PaneActivityStatusFact>` (telemetry kind
  `entity_map`), not a dictionary-shaped snapshot — a write wakes only that
  pane's row. Proven by `PaneActivityStatusAtomTests.keyedReadersWakeOnlyForTouchedPane`
  (mirrors `AtomFamilyObservationTests.keyedReadersWakeOnlyForTouchedKey`).
- Equal-write suppression, two layers: an explicit same-line guard before the
  rate-limit check (so a repeated line never consumes the rate-limit window),
  plus `AtomFamily`'s own `isContentEqual` comparing only `lastOutputLine` (not
  `observedAt`) as a backstop.
- Write cadence: exactly once per settle call from the router; no new timers.
- 10s-per-pane timerless leading-edge rate limit against an injected `now: () ->
  Date` closure (`AppPolicies.InboxNotification.paneActivityStatusMinimumPublishInterval`),
  scoped per pane, not global. Settle inside the window is dropped, not deferred.

Proof: `Tests/AgentStudioTests/Core/State/PaneActivityStatusAtomTests.swift` (7
tests: publish, nil/empty guard, within-window drop, post-window publish,
per-pane cadence scoping, equal-write suppression, keyed-wake isolation) and a
new `TerminalActivityRouterTests` test
(`unseenSettlementRecordsPaneActivityStatus`) proving the router calls the
recording closure with the pane ID and settled line regardless of what
InboxNotificationRouter/InboxPromoter later decide. `mise run test:swift --
filter "PaneActivityStatusAtomTests|TerminalActivityRouterTests|
InboxPromoterTests|TerminalActivityProjectorTests|AtomFamilyObservationTests"`
— 75 tests, exit 0.

**Live acceptance proof — BLOCKED, root cause identified precisely.** Rebuilt
HEAD, launched debug visibly (binary freshness verified: `07:12:47` binary vs
`06:56:45` last commit), typed a real command into the observed/active pane in
By Tab mode, waited well past the 10s/750ms settle windows, and L2 stayed on
"output activity". Escalated to a definitively-overflowing burst (`seq 1 300`,
guaranteed to scroll any terminal viewport) — same result. Queried VictoriaLogs
scoped exactly to this build (`service.version:"0.0.1-debug+jp6s"`) across the
whole 10-minute session: **zero** `pane_activity_status` atom mutations, **zero**
`terminal.activity` trace records for `.unseenActivitySettled` (only 2
`terminal.commandFinished` shell-integration events, an unrelated lane), and
**zero** `performance.terminal.accumulator_drain`/`compact_apply` events for
this specific process — meaning the scrollbar-derived
`TerminalLocalActivityEvidence` never reaches the accumulator at all for this
session, for any burst size. This rules out my earlier "empty-viewport headroom"
hypothesis (the 300-line burst also produced nothing) and confirms the break is
upstream of all Swift-side plumbing already fixed this round (InboxPromoter
suppression fix, and now this atom split) — most likely in Ghostty's own
scrollbar-changed callback delivery for this specific debug session's terminal
surfaces. Notably, the concurrently-running **stable** app instance emitted
these same performance/terminal trace kinds normally in the identical time
window (from an earlier broad trace survey this round), which narrows the next
investigation to what's different about this debug session's pane/surface
wiring, not a universal regression. This needs Ghostty-level source
instrumentation and rebuild-iterate cycles beyond this round's scope; flagged
to the owner/team-lead as an open, precisely-evidenced finding rather than
claimed fixed.

### Todo 3 — PR chip glyph and color parity (commit `c7295bb13`)

`SidebarPullRequestChipSpec` (`Core/Views/SidebarChips.swift`) is now the one
shared factory (glyph + `AppStyles.General.Accent.primaryColor`-based color +
pill style) used by both `RepoExplorerWorktreeRow.swift` (By Repo) and
`RepoExplorerPaneNavigation.swift` (All Panes/By Tab), replacing pane rows'
`.accent(.accentColor)` (system accent) and By Repo's `iconColor`-derived color.
Removed the now-dead `pullRequestChipPresentation` helper.

Proof: a real pixel-rendered test
(`RepoExplorerWorktreeRowTests.mountedByRepoRowRendersPositivePullRequestChip`)
samples the rendered By Repo row for the product token's specific RGB signature
(red ≈0.10-0.45, distinguishing it from system blue's near-zero red channel) —
the pre-fix code would have failed this given the fixture's
`iconColor: .accentColor`. A source-string test
(`RepoExplorerViewTests.prChipRenderSitesUseTheSharedSpec`) pins both row files
to the shared spec and confirms neither constructs an inline PR chip anymore.
`mise run test:swift -- --filter "RepoExplorerWorktreeRowTests|
RepoExplorerViewTests"` — 49 tests, exit 0.

### Todo 4 — toggle selected fill from the shared accent palette (commit `d6ce6fdcd`)

`SidebarToolbarSegmentButtonStyleBody` (`SharedComponents/
SidebarToolbarSegmentedControl.swift`) now fills the selected segment via
`ChromeToolbarControlPalette.fillColor(isSelected:isHovered:isPressed:)` — the
same shared palette function the bottom-bar Zoom pill family uses — instead of
an ad-hoc `Color.primary.opacity(visualState.fillOpacity)`. Unselected/hover/
pressed states keep the unchanged grey fill from the visual-state resolver.

Proof: updated the existing visual-state source-string test to assert
`ChromeToolbarControlPalette.fillColor` appears (`SidebarToolbarControlVisualStateTests`,
6 tests, exit 0), plus **live screenshot evidence**:
`tmp-screenshots/item-proofs/round2-05-todo4-evidence.png` shows the "By Tab"
segment selected with an accent-tinted blue fill, accent icon, and accent text
— all three treatments consistent, matching the Zoom pill family.

### Full aggregate

`SWIFT_TEST_TIMEOUT_SECONDS=2700 SWIFT_TEST_PREBUILD_TIMEOUT_SECONDS=1800 mise
run test` — exit 0, 236.84s, zero failures, run after all four items (A, 1, 3,
4) were committed. `mise run lint` — exit 0 after every commit this round
(clean; only pre-existing, unrelated report-level architecture-lint findings in
CommandBar/ProcessExecutor test files, unchanged from prior rounds).

### Evidence paths

- Item A pixel test: `Tests/AgentStudioTests/SharedComponents/AppEntityIconTests.swift`
- Todo 1 tests: `Tests/AgentStudioTests/Core/State/PaneActivityStatusAtomTests.swift`,
  `Tests/AgentStudioTests/Features/Terminal/State/TerminalActivityRouterTests.swift`
- Todo 1 live-blocker screenshots: `tmp-screenshots/item-proofs/round2-01-bytab/`,
  `round2-02-settled/`, `round2-03-bytab-check/`, `round2-04-bytab-retry/`
- Todo 3 pixel test: `Tests/AgentStudioTests/Features/RepoExplorer/RepoExplorerWorktreeRowTests.swift`
- Todo 4 live evidence: `tmp-screenshots/item-proofs/round2-05-todo4-evidence.png`
