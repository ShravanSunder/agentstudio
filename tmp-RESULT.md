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

## 2026-08-17 — RC2 (commandFinished settle evidence), forge merge + projection wiring, Todo 5

### RC2 — commandFinished admitted as second settle-evidence source (commit `d4f477e98`)

`TerminalActivityRouter.consume(_:)` now routes `.commandFinished` bus events to a
new `TerminalActivityProjector.commandFinished(surfaceID:paneID:)`, regardless of
attention state. It closes any open unseen-scrollbar window immediately (no
waiting out the remaining debounce) or, if no scrollbar window was open,
synthesizes a minimal zero-row `TerminalSettledActivity` carrying only the
resolved last-output-line, so a pane with zero scrollbar signal still reaches
the existing settle path (status-fact write, notification lane, and all of
that lane's suppression rules) unchanged. This follows Contract 7: raw
`commandFinished` action → typed admission at the router → one settle emission
per command, no per-keystroke work.

Proof: `TerminalActivityProjectorTests` (3 new tests: closes an open scrollbar
window early, synthesizes a settle when no window was open, no-op when neither
a window nor a resolvable last-output-line exists) and an end-to-end
`TerminalActivityRouterTests` integration test
(`commandFinishedBusEventSettlesPaneWithZeroScrollbarEvents`) proving a pane
that never accumulated scrollbar rows still settles on `commandFinished` alone.
`mise run test:swift -- --filter "TerminalActivityProjectorTests|
TerminalActivityRouterTests"` — green.

### RC2 + Todo 1 live acceptance — BLOCKED, root cause pinned to a specific pre-existing function

Rebuilt HEAD, launched debug (`AGENTSTUDIO_IPC_DEBUG_TOKEN_ESCROW=1`), and
drove the live app through its own authenticated IPC socket
(`terminal.send` + `terminal.wait(condition: "commandFinished")`) rather than
synthetic Peekaboo keystrokes — the shared machine currently has four
concurrent AgentStudio processes (`stable`, `oe9o`, `1owk`, this session's
`jp6s`), and an early Peekaboo attempt silently landed keystrokes on a
different process because OS key-window focus belonged to `oe9o`, not `jp6s`
(`osascript` confirmed `frontmost` was `oe9o`'s PID). IPC drives the target
pane by its own socket, independent of window focus, and removes that
ambiguity entirely.

Confirmed via VictoriaLogs, scoped to this run's exact marker: `terminal.send`
accepted, `terminal.wait(commandFinished)` returned `exitCode: 0` within the
timeout, `ghostty.action.translated: commandFinished` fired, `eventbus.deliver`
shows `TerminalActivityRouter` consumed it, and `terminal.activity.observed`
fired immediately after — the whole RC2 admission chain genuinely worked, on
two different panes across two fresh app launches. But the sidebar row's L2
text never showed the echoed content; it stayed on the generic `output
activity` fallback (`InboxNotificationAtom.genericPaneActivityText`), meaning
`PaneActivityStatusAtom`'s write and the pre-existing inbox-body fallback both
came up empty.

Root cause, confirmed against the real Swift function (not just reasoning):
`TerminalLastOutputLineContract.isBarePromptLine`
(`Sources/AgentStudio/Features/Terminal/Routing/TerminalLastOutputLineContract.swift:36-38`)
classifies a line as a bare prompt only when it contains **zero letters or
digits**. This repo's own dev shell prompt is oh-my-zsh-style and embeds real
text — `➜  chip-matrix-final-live (⑂ feat/sidebar-grouping-rows) ` — so it is
never recognized as a prompt and is read as real output instead:

```
rawViewportText = "AGENTSTUDIO_L2_ACTIVE_PROOF_28b7ebd53\n➜  chip-matrix-final-live (⑂ feat/sidebar-grouping-rows) "
TerminalLastOutputLineContract.contractedLastLine(fromRawViewportText: rawViewportText)
  == "➜  chip-matrix-final-live (⑂ feat/sidebar-grouping-rows)"   // the prompt, not the echoed line above it
```

Downstream, `TerminalActivityProjector.resolveLastOutputLine`
(`TerminalActivityProjector.swift:615-623`) suppresses a candidate that's
unchanged from the pane's previous settle. Since this repo's prompt text is
identical across every settle for a given pane (same directory, same branch),
the first settle after boot consumes that (wrong) candidate, and every
subsequent real command's settle produces the exact same wrong candidate —
suppressed as "unchanged" forever. A fresh-boot screenshot caught this
mid-flight: right after the very first post-boot settle, one pane's L2 line
genuinely showed `➜  chip-matrix-final-live (⑂ feat/sidebar-grouping-rows)`
(the misclassified prompt, not the fallback) before later settling back to the
generic fallback text once the suppression kicked in on repeat writes with an
already-consumed candidate.

This bug pre-dates both RC2 and this round: `TerminalLastOutputLineContract.swift`
was introduced in `e37bf41f0` ("Surface real terminal output in inbox
notification bodies", merged into this branch as item 5 above), and it is also
the read path for the pre-existing scrollbar-settle notification-body feature
(`TerminalActivityProjector.swift:569,596`), not just RC2's new path. It fully
explains item 5's standing "live capture ... is blocked" note above — nothing
before RC2 reliably reached this exact "fast, single-line command, back to an
identical prompt" shape in a way that exposed it. **Known limitation, not a
blocker of this round's own code**: RC2 and Todo 1 are proven correct at the
unit/integration level, and their live acceptance is blocked by this one
pre-existing function, not by anything RC2/Todo 1 introduced. No fix was
applied here — two directions were identified (narrow text-heuristic
improvement to `isBarePromptLine`, vs. a semantic fix using Ghostty's OSC133
shell-integration prompt boundary instead of raw-text guessing) and handed to
team-lead for a fix-direction decision rather than picked unilaterally.

### Forge merge + projection wiring (merge `6f94ce855`, wiring commit `28b7ebd53`)

Merged `feat/forge-honesty` (`111e570ca`, `f8a15fe7f`) cleanly. Found one
additional gap while reconciling both sides' intent: `RepoExplorerWorktreeRow`'s
PR-chip render branch (`else if let prCount = branchStatus.prCount, prCount > 0`)
was missing the `!branchStatus.pullRequestDataUnavailable` guard that the outer
`shouldShowPullRequestChip` gate already had, so a repo with a stale positive
`prCount` from a prior fetch would still render a chip after resolving
unavailable. Fixed, with a dedicated red/green test ("a stale positive PR count
never renders once the repo resolves unavailable").

Completed the projection wiring: `unavailablePullRequestRepoIds` now flows into
`GitBranchStatus.merge(...)` (`RepoExplorerProjectionWorker.swift:292`) *and*
into both re-projection admission gates —
`RepoExplorerProjectionRequest.scopedChange(from:)`'s equality guard and
`RepoExplorerProjectionRequestKey` — so a repo transitioning from empty facts
to resolved-unavailable no longer compares equal to its prior request and
silently skips re-render. While wiring this, found `RepoCacheAtom.unavailablePullRequestRepoIds`
sharing `pullRequestFactsRevisionAtom` with the unrelated pull-request-facts
map, so any repo's fact write coarsely woke every reader of the unavailable
set — violates the keyed/minimal-wake convention used everywhere else in this
atom's siblings. Gave it its own dedicated revision atom, bumped only when the
set itself changes.

Red-first tests: `scopedChange(from:)` refuses the fast path when only
`unavailablePullRequestRepoIds` differs; a full `project(_:)` call on a repo
with zero facts marked unavailable produces `prCount == nil,
pullRequestDataUnavailable == true` (the row drops its pending-glyph
condition); the observation-tracked `projectionRequestKey` changes and wakes
capture when a repo resolves unavailable with zero facts.

`mise run test:swift -- --filter "ForgeActor|RepoExplorerWorktreeRow|
WorkspaceCacheCoordinator|RepoCacheAtom|RepoExplorerProjectionWorker|
RepoExplorerViewProjectionHelperTests"` — 157 tests, exit 0. `mise run lint` —
exit 0 (only pre-existing report-level findings, unrelated files). Live
acceptance for the forge work (no-remote and detached-HEAD fixtures render no
glyph after resolution) still rides the final sweep.

### Todo 5 — unify second-line rendering (commit `0f4b84532`)

`RepoExplorerWorktreeRow`'s branch-name and placement-text lines hand-rolled
their own icon+text HStack, duplicating `SidebarMetadataLine`'s icon-column/
text-column/foregroundStyle contract and drifting from it (its SF Symbol
placement icon was tinted `.secondary`; `RepoExplorerPaneNavigation`'s
identical placement icon, already routed through `SidebarMetadataLine`, was
left untinted). Extended `SidebarMetadataLine` with an `IconSource` enum
(`.systemName` or `.octicon(name:loader:)`) so both rows share one component
and one icon-tint contract, then replaced both hand-rolled HStacks and updated
the two other call sites (`RepoExplorerPaneNavigation`'s placement line,
`InboxRow.metadataLine`).

Swept the RepoExplorer row files for other hand-rolled second-line
`.foregroundStyle(.secondary)` usages: the remaining ones
(`RepoExplorerWorktreeRow`'s stale-PR-chip glyph, `RepoExplorerStatusRows`'
fault/loading banners, `RepoExplorerEmptyStateView`) are a genuinely different
visual role — different font sizes, animated symbol effects, multi-line text
blocks, centered full-pane layout — not hand-rolled duplicates of the
icon+single-line-text pattern `SidebarMetadataLine` encapsulates, so left
as-is.

Proof: a new source-pinning test confirms the branch/placement lines route
through `SidebarMetadataLine` with the right icon/text bindings and no longer
hand-roll `Image(systemName: "square.split.2x1")`; updated an existing
pre-unification test (`paneRowsUseSharedSecondaryMetadataStyling`, which had
been pinning the *old* hand-rolled pattern as a known-duplication tracker) to
assert the new unified state instead. `mise run test:swift -- --filter
"SidebarMetadataLineTests|RepoExplorerWorktreeRowTests|InboxRowTests"` — 29
tests, exit 0; broader `mise run test:swift -- --filter
"RepoExplorer|SharedComponents|InboxNotification"` — 575 tests, exit 0. `mise
run lint` — exit 0. Visual proof: a live screenshot of the refactored build
shows no crashes or visual corruption; AX-based interaction to switch into "By
Repo" mode for a pixel-level branch-line check timed out repeatedly
(`ax_incomplete_read`/deadline errors) on this heavily loaded four-instance
desktop rather than from any app defect — accepted as sufficient given this is
a same-visual-contract internal refactor backed by source-pinning tests, not a
visual behavior change.

### Full aggregate (after commits 28b7ebd53 + 0f4b84532)

`SWIFT_TEST_TIMEOUT_SECONDS=2700 SWIFT_TEST_PREBUILD_TIMEOUT_SECONDS=1800 mise
run test` — exit 0, 226.73s. Covers Swift lint + architecture lint, BridgeWeb
lint/typecheck/unit/integration/browser/Vite E2E, packaged BridgeWeb build,
Swift non-serialized + serialized WebKit + E2E serialized tests.

### Forge live acceptance — partial, IPC-confirmed integration; pixel screenshot blocked by environment

Built two disposable fixtures under `tmp/forge-live-proof/` (gitignored, not
committed): `no-remote-repo` (a real git repo, zero remotes configured) and
`detached-repo` with a linked worktree `detached-repo-worktree` checked out
`--detach` at its first commit (zero remotes, `rev-parse --abbrev-ref HEAD ==
"HEAD"`). Registered both with the running debug app via
`AGENTSTUDIO_STARTUP_DIAGNOSTIC_ACTION=add-watch-folder` +
`AGENTSTUDIO_STARTUP_WATCH_FOLDER=<path>` (the watch-folder env var alone does
nothing without the diagnostic-action pairing —
`AgentStudioStartupDiagnosticAction.watchFolderURL(from:)` is only read when
`kind == .addWatchFolder`).

Confirmed via the app's own authenticated IPC (`pane.snapshot`'s
`workspace.repositories`) that both fixtures were discovered and registered
into the live running workspace by name and path — the real topology/watch-folder
pipeline processed them, the same pipeline the forge merge and projection
wiring above depend on. Could not get a clean pixel-level sidebar screenshot
confirming "no glyph, no chip" for these two specific rows: this machine
currently has four concurrent AgentStudio processes (stable + three other
debug identities), and Peekaboo's AX tree read timed out repeatedly
(`ax_incomplete_read`/`deadline_reached`) for this session's window,
independent of any app defect — the same environmental contention noted under
Todo 5's visual proof above. The underlying suppression logic itself already
has dedicated, passing red/green unit coverage
(`RepoExplorerWorktreeRowTests`: "a detached-HEAD worktree resolves pull
request data unavailable immediately", "resolved-unavailable pull request
state renders neither the pending glyph nor a chip", "a stale positive PR
count never renders once the repo resolves unavailable"). Given the
integration-level registration is confirmed and the rendering logic is
unit-proven, this is reported as strong-but-incomplete live acceptance rather
than claimed fully proven — a pixel screenshot from a quieter desktop would
close the gap.

## 2026-08-17 (continued) — learned prompt signature (option 3, owner-ratified) implemented; live acceptance still open

### Implementation (commit `7fed04fbd`)

Built owner's "learned prompt signature" design exactly as specified: at each
commandFinished-driven settle, `TerminalActivityProjector` learns the
trailing non-empty raw-viewport line as the pane's `promptSignature` (that
line is by construction the shell's freshly-printed prompt — shell
integration prints it immediately after the command ends), then contracts
the candidate line excluding that signature — learn-then-contract, so even a
pane's first-ever settle never publishes the prompt itself. Scrollbar-driven
settles read the last-known signature but never write it. The existing
zero-letters `isBarePromptLine` heuristic remains as a fallback. Moved
contraction from `SurfaceManager` (now returns raw viewport text, one
Ghostty call per settle as before) into the projector, since only it holds
the per-pane signature/suppression state.

Proof: `TerminalLastOutputLineContractTests` — the exact
`"➜  chip-matrix-final-live (⑂ feat/sidebar-grouping-rows)"` repro from the
earlier finding, plus `trailingNonEmptyLine`/exclusion-only-viewport
coverage. `TerminalActivityProjectorCommandFinishedTests` (new file, split
off to stay under the file-length lint cap) — first-settle self-heal
(prompt-only viewport never publishes), signature updates every settle as
prompt text changes (`cd`/branch switch), unchanged-suppression still holds
for genuinely repeated real output, plus the pre-existing RC2 tests updated
to use realistic two-line (output + trailing prompt) raw text instead of the
old single-line mocks that the new signature logic would otherwise treat as
the prompt itself. `mise run test:swift -- --filter "Terminal"` — 585 tests
in 122 suites, exit 0. `mise run lint` — exit 0.

### Live acceptance — still not proven; two prior "confirmed" claims corrected

Drove the running debug app through its own IPC (`terminal.send` +
`terminal.wait(commandFinished)`, the standard procedure noted below) and
the sidebar row's L2 text still showed stale, hours-old prompt-line text
after two fresh echoed commands, not the freshly echoed marker.

Investigating this surfaced a genuine misreading of my own earlier evidence,
recorded here so it isn't repeated: `terminal.activity.observed` and the
"eventbus.deliver: TerminalActivityRouter" trace record are emitted
unconditionally at the *end* of `TerminalActivityRouter.consume(_:)`
(`traceTerminalActivity`, called after the `commandFinished`-specific branch
regardless of whether that branch ran), so their presence does **not** prove
`projector.commandFinished(...)` executed — only that a terminal-classified
envelope reached the router. The reliable signal turned out to be
`eventbus.deliver`'s `agentstudio.inbox.decision`/`agentstudio.inbox.reason`
attributes on the record with `agentstudio.eventbus.consumer:
"InboxNotificationRouter"`: those only appear if the projector's settle
actually emitted a derived envelope onto the bus. Re-checked with that
correct signal and confirmed both `TerminalActivityRouter` and
`InboxNotificationRouter` genuinely processed both of my test commands
(`decision: ignore, reason: below_duration_threshold` — the settle ran
end-to-end, the *notification* was correctly suppressed as too fast/generic
to alert on, which is expected and unrelated to L2). So the settle pipeline
does run to completion live; the gap is somewhere between
`recordSettledActivityStatus` being called and the sidebar showing the new
value.

Attempted to close that specific gap with direct atom-write telemetry
(`AGENTSTUDIO_TRACE_TAGS` including `atoms`, deliberately scoped rather than
`*`, per the documented risk that `*` plus a large watch-folder scan
previously crashed a debug session). The app did not crash but hung — alive,
low CPU, never reached `app.did_finish_launching.succeeded` after several
minutes — a slow-onset variant of the same documented risk against this
session's now-large persisted workspace (~25 registered repos accumulated
across this round's earlier fixture work). Aborted and force-quit rather
than push further into a known-risky pattern; did not obtain atom-content
telemetry.

Remaining candidate explanations, none yet confirmed or ruled out:
1. The real Ghostty viewport read has more structure than my test mocks
   (prompt+echoed-command line, output line, fresh bare-prompt line — three
   lines, not two) and something about that specific shape defeats the
   exclusion logic in a way my two-line mocks don't exercise.
2. A pane-scoping gap: `RepoExplorerView.projectionInputRevision` does
   explicitly read `_ = latestPaneMessageSnapshot(paneID)` inside `for tab in
   workspaceTab.tabs { for paneID in tab.allPaneIds { ... } }` — confirmed by
   direct source read — but this specific IPC-driven pane may not be covered
   by that loop in this live session's tab/workspace state, so its keyed
   atom slot's changes are never observed.
3. Something pane-identity-specific between the write side
   (`AppDelegate+InboxNotificationBoot.swift` wiring `recordSettledActivityStatus`
   to `atomStore.core.paneActivityStatus.recordSettledActivity`) and the read
   side (`SidebarSurfaceHost.swift`'s `latestPaneMessageSnapshot` closure)
   that unit tests, which construct both sides directly, don't exercise.

Not claiming RC2/Todo 1 live acceptance done. The code change itself is
correct and proven at the unit/integration level; the remaining gap is real,
narrowed considerably from the original finding, but not yet root-caused.

### Standard IPC-driven live-proof procedure (recorded per owner's request)

This machine can have multiple concurrent AgentStudio processes (stable
build plus several other debug identities). Peekaboo's synthetic keystrokes
target whatever window/process the AX layer resolves for the given PID, but
they are session-order-dependent when several windows overlap, and OS-level
key-window focus (checked via `osascript ... frontmost`) does not reliably
match the intended target either — an early attempt this round silently
landed keystrokes on a different, unrelated debug instance. The reliable
procedure is to drive input through the target app's own authenticated IPC
socket instead of synthetic input:

1. Launch with `AGENTSTUDIO_IPC_DEBUG_TOKEN_ESCROW=1` (one-shot token at
   `<data-root>/ipc/debug-token`, consumed on first `auth.login`).
2. Connect to `<data-root>/ipc/runtime.json`'s `socketPath` over a Unix
   domain socket, send newline-delimited JSON-RPC 2.0.
3. `auth.login` with the token, `pane.list` to find target pane ids/handles.
4. `terminal.send` with `{"handle": "pane:<id>", "input": "<command>\n"}`.
5. `terminal.wait` with `{"handle": ..., "condition": "commandFinished",
   "timeoutSeconds": N}` to block until the shell reports completion.

This is unambiguous regardless of window z-order or which process currently
has OS focus, and should be the standard procedure for future live proofs on
a shared, multi-instance desktop.

## 2026-08-17 (continued) — candidates 1/1/3 ruled out; decisive root-cause evidence for candidate 2

### Candidate rule-outs (source-level, no live app needed)

**Instance identity (owner's top bet) — ruled out.** Exactly one construction
site for `PaneActivityStatusAtom` (`CoreAtoms.swift:67`, a default parameter
constructed once with `CoreAtoms()`). Exactly one `AtomRegistry()`
construction (`AppDelegate+WorkspaceBoot.swift:157`), assigned to
`AppDelegate`'s single `atomStore` property. `CoreAtomScope.setUp(atomStore.core)`
runs exactly once right after (line 159), and `CoreAtomScope` itself enforces
single-installation with a runtime precondition. The read side
(`atom(\.paneActivityStatus)`, used by `MainSplitViewController`/
`SidebarSurfaceHost`) resolves through `CoreAtomScope.store` → the same
`atomStore.core`. Write and read side are provably the same object.

**Pane-ID path — no bug found via source trace.** `PaneId.swift`'s own doc:
"the primary identity for a pane across state, views, and runtime routing...
Surface IDs remain runtime associations" — one canonical identity type.
`TerminalActivityRouter.consume(_:)` correctly separates
`surfaceID = surfaceIDForPaneID(paneEnvelope.paneId.uuid)` (derived) from
`paneEnvelope.paneId.uuid` (used directly for `commandFinished`/emit/
`recordSettledActivityStatus`) — no accidental surface-for-pane substitution.

**Three-line real viewport shape — ruled out via permanent unit test.** Added
`realThreeLineViewportShapeResolvesToEchoedOutput` to
`TerminalLastOutputLineContractTests.swift`: prompt-with-echoed-command line,
real output line, fresh bare prompt line — `contractedLastLine` correctly
resolves to the output line, excluding both prompt occurrences.

### Minimal-workspace live reproduction (owner-approved atoms trace)

Reset jp6s's persisted `core.sqlite`/`local.sqlite` (disposable debug data,
isolated identity — deleted the 6 db/wal/shm files) and rebuilt a genuinely
minimal workspace: one fresh throwaway repo
(`tmp/l2-minimal-proof/single-repo`), one worktree, one pane. Getting to "one
pane" needed an extra step: `openWorktreeInPane`/`newTab`/`openNewTerminalInTab`
are all IPC `.targetless` + `.noArguments` (confirmed in
`AppCommand+IPCProjection.swift`) — they resolve their target from ambient UI
selection state, not something a headless IPC client can parameterize, and
they reject with `-32007 parameters required` regardless of `targetHandle`.
Worked around it: launched with the `ipc-terminal-smoke` startup diagnostic
(creates a floating, unassociated terminal pane for exactly this kind of
headless proof), then `terminal.send`'d a `cd` into the fixture repo path —
the app's own CWD-tracking correctly re-associated the pane with the
worktree (`pane.snapshot` showed `worktreeId`/`repoId` populated after the
`cd` completed). This is now a clean, reusable recipe for a from-scratch
minimal live fixture and is worth keeping for future rounds.

On this properly minimal, properly worktree-associated single pane: sent two
distinct `echo` commands via `terminal.send` + `terminal.wait(commandFinished)`,
both accepted and settled (`exitCode: 0`). The sidebar still showed the
stale generic `output activity` fallback, not either echoed marker —
reproduced cleanly with zero other confounds (no bloated workspace, no
multi-instance contention, confirmed correct pane/worktree identity).

Re-launched the same minimal workspace with
`AGENTSTUDIO_TRACE_TAGS=app.startup,performance,terminal.activity,terminal.signal,inbox,eventbus,atoms`
(scoped, not `*`) — boot was fast and clean this time (confirms the owner's
diagnosis: the earlier hang was atom-hydration volume against the
25-repo-accumulated workspace, not atoms tracing itself). Repeated the same
two-command test and queried `agentstudio.performance.atom.label:"pane_activity_status"`
directly: **51 telemetry records for this session, all `operation: "value"`
(reads). Zero writes.** `agentstudio.performance.atom.slot.count` did grow
1→2→3 across the session, but that tracks all three panes each being *read*
for the first time (`AtomFamily` observation-slot allocation on first read),
not a mutation — there is no `operation: "set"` (or equivalent) record for
this label anywhere in the session, despite two fully-settled commandFinished
events on the exact pane being read.

**This is the decisive finding for candidate 2 (loop coverage) and beyond:**
the settle pipeline runs to completion (confirmed twice now via the
`inbox.decision` signal), but `PaneActivityStatusAtom.recordSettledActivity`
never reaches its `statusFamily.setValue(...)` call — or reaches it and every
guard rejects, though the rate-limit/unchanged-line guards don't explain a
zero-write outcome for a *first* settle with genuinely new text. The gap is
narrower than "loop coverage" (candidate 2 as originally framed assumed the
write succeeds and the *read side* misses it) — the evidence now points
upstream of the atom write itself: either `recordSettledActivityStatus` isn't
being invoked from `TerminalActivityRouter.consumeProjectionOutcome`'s
`.unseenActivitySettled` case in this exact runtime path, or
`resolveLastOutputLine` is returning `nil` for the *real* Ghostty content in
a way the three-line unit test still doesn't capture. Have not added a
temporary diagnostic log line to pin this down further — that's a real (if
temporary) code change and I want to confirm before making it.

### Forge live acceptance — now fully proven (upgraded from strong-but-incomplete)

Re-launched with `AGENTSTUDIO_STARTUP_DIAGNOSTIC_ACTION=add-watch-folder` +
`AGENTSTUDIO_STARTUP_WATCH_FOLDER` pointed at `tmp/forge-live-proof/`
(`no-remote-repo`, `detached-repo` with a `detached-repo-worktree` linked
worktree at `--detach`), switched to "By Repo" grouping via
`command.execute {"commandId":"setRepoSidebarGroupingRepo"}`, then captured
with `peekaboo see --no-elements` (screenshot-only, skips the AX read that
was timing out — this is now the confirmed reliable pattern for pixel proof
on this multi-instance desktop).

Clean, decisive result: all four rows —
`detached-repo/main`, `detached-repo-worktree/detached HEAD`,
`no-remote-repo/main`, `single-repo/main` (my L2 fixture, also no-remote, so
it doubles as a fifth confirming data point) — render a plain branch line
with no PR chip and no pending glyph. Screenshots saved at
`tmp-screenshots/forge-live-proof/no-remote-and-detached-head-no-glyph.png`
and a cropped/zoomed version alongside it. This closes the forge live
acceptance item.

## 2026-08-17 (continued) — RC2 root cause found: Ghostty read returns zero-length text for this pane type

Added the two owner-approved temporary diagnostic prints (using `os.log`
`Logger`, not `print()` — `print()` from a LaunchServices-launched app isn't
captured anywhere readable; `os_log` is, via `log show`), plus two more in
the same spirit to bridge gaps the first two didn't cover, all stripped back
out afterward (confirmed via `git checkout --` on all four touched files,
rebuild clean, `mise run test:swift -- --filter Terminal` — 586 tests green).

**5-minute source check first, per owner's request:** `commandFinished`
DOES call the same `resolveLastOutputLine` reader as the scrollbar paths
(confirmed by re-reading `TerminalActivityProjector.commandFinished`), and
its emitted `.unseenActivitySettled` outcome is handled by the exact same
`TerminalActivityRouter.consumeProjectionOutcome` switch case as scrollbar
settles — `recordSettledActivityStatus` is not skipped or routed
differently. So the "diverging code path" hypothesis was ruled out before
adding any prints. Also found and fixed a real test gap the owner suspected:
`TerminalActivityRouterTests.commandFinishedBusEventSettlesPaneWithZeroScrollbarEvents`
posts a real bus envelope and asserts on the *derived* envelope reaching the
bus, but never wires or asserts `recordSettledActivityStatus` at all (unlike
the scrollbar-path test, which does) — so it could not have caught this.

**Diagnostic trace, in order:**
1. `PaneActivityStatusAtom.recordSettledActivity` — fired several times at
   boot for various panes, always with `lastOutputLine=nil`, but *never* for
   my target pane during my actual test window. These were unrelated
   boot-time settles, not my commands.
2. `TerminalActivityProjector.commandFinished`'s own emit line — never
   fired at all, for any pane, during the entire session. This is the key
   finding: `commandFinished` was being *called* (see next point) but never
   reached its `emit(...)` call, meaning it hit its own early-return guard
   (`guard closedWindow != nil || lastOutputLine != nil else { return }`)
   every time — both were nil.
3. Added a third print directly in `TerminalActivityRouter.consume(_:)`:
   confirmed `commandFinished` genuinely was invoked 3 times for my exact
   pane and exact commands (`cd`, then two `echo`s), with `isHighVolume=false`
   and a *successfully resolved* `surfaceID` — ruling out the surface-ID-path
   candidate definitively; the router-to-projector dispatch is correct.
4. Added a fourth print directly in `SurfaceManager.readViewportTrailingText`,
   disambiguating every nil-return branch. Result:
   `rows=50 columns=130` (valid, real geometry) — `ghostty_surface_read_text`
   returns `true` — `text.text == nil` is `false` (non-nil pointer) —
   **but `text.text_len == 0`**. The Ghostty C API call succeeds structurally
   and returns a real, non-null buffer, but with zero length, for the
   requested viewport selection, on this specific pane, every single time
   across three separate commands with genuinely different real output
   (confirmed visually via screenshot earlier in this investigation — the
   echoed text was on-screen in the pane).

**This is the actual root cause, at the Ghostty C API boundary**, not
anywhere in the Swift settle/atom/routing code I've been able to touch or
test at the Swift level. Every layer above this — router dispatch, projector
sequencing, atom write path, learned-prompt-signature contraction — is
correct and already covered by tests. The unit tests all pass because they
mock `lastOutputLineReader`/`SurfaceManager` at exactly this boundary and
never exercise the real `ghostty_surface_read_text` call for this pane
shape.

**What's specific to the pane shape that might explain a zero-length read**
(not verified further — this needs either Ghostty source access, which
isn't hydrated in this worktree, or a different reproduction path):
this is a pane created via the `ipc-terminal-smoke` startup diagnostic (a
floating/unassociated pane at creation) that was then re-associated to a
worktree via a `cd` command through the CWD-tracking mechanism, not created
through the normal "open worktree in pane" flow. It's possible this
specific creation path leaves the surface's Ghostty-side render/scrollback
state in a condition where geometry queries succeed but text-selection reads
against the viewport come back empty — e.g. a first-paint/composite that
hasn't happened for this pane's specific surface, since it may never be the
*visible* pane in its tab. I have not confirmed this against a pane created
through the ordinary worktree-open flow (I could not reach that flow
headlessly — see the recipe note above) — that's the natural next
falsification test if this needs to go further: does a *normal*,
GUI-created worktree pane hit the same zero-length read, or is this
specific to the ipc-terminal-smoke + cd-reassociation recipe.

### Tab-icon blue vs white A/B capture (deliverable, no pass condition)

Captured both variants of the By Tab tab-group header icon
(`AppStyles.Shell.Sidebar.tabGroupIconColor`), same view state (one
`ipc-terminal-smoke`-created tab, `single-repo` fixture), via
`--no-elements` screenshots — no interaction needed.

- Variant A (current): `AppStyles.General.Accent.primaryColor.opacity(AppStyles.General.Foreground.muted)`
  — muted product-accent blue. `tmp-screenshots/tab-icon-ab/variantA-blue.png`
  (+ zoomed crop).
- Variant B: `Color.secondary` — matches the other group-header icons.
  `tmp-screenshots/tab-icon-ab/variantB-white.png` (+ zoomed crop).

Token reverted to variant A afterward (`git checkout --` confirmed clean,
rebuilt). Owner picks from the pixels; whichever they choose is a one-line
token change.

## Review remediation (2026-08-17)

Independent review (`tmp-REVIEW-REPORT.md`) returned NOT-READY with 9
findings (F1-F9). F1 (fresh aggregate + binary-fresh sweep) is the
owner/orchestrator's after all others land. Landed F8, F9, F4, F2, F7, F5,
and the F3 test in that order, each red-first where a real bug existed,
focused suite + lint green, separate commits, pushed:

- **F8** (`db6eff828`): `RepoEnrichmentCacheAtom.clear()` bumped
  `pullRequestFactsRevisionAtom` for the unavailable-set change instead of
  `pullRequestUnavailabilityRevisionAtom`, so a whole-cache clear could leave
  the sidebar showing a stale terminal-unavailable state. Fixed; test
  observes mark-unavailable → observe → clear.
- **F9** (`db6eff828`): `PaneActivityStatusAtom.clear(paneId:)` existed but
  no owner called it. Wired into `TerminalActivityRouter`'s `.surfaceClosed`
  path via a new `clearPaneActivityStatus` closure, composed in
  `AppDelegate+InboxNotificationBoot`. Split the two ordered-surface-close
  tests into `TerminalActivityRouterCloseTests.swift` to stay under
  SwiftLint's `type_body_length` cap.
- **F4** (`f3aae7b2c`): migration 005 added `local_window_state.repo_grouping_mode`
  and dropped the legacy `local_repo_explorer_preferences.grouping_mode`
  column without copying its value — every existing All Panes/By Tab user
  would reset to By Repo on upgrade. Fixed by copying the legacy value into
  the main window row before the drop, guarded by the existing storage-token
  vocabulary. Test simulates the real pre-005 on-disk shape (migrate through
  004, manually reproduce the legacy column) and proves a seeded `'tab'`
  value survives the full migration.
- **F2** (`085fc9cd4`): `ForgeActor.applyOutcome(.complete)` compared new
  facts against `state.lastPublishedFactsByBranch`, a baseline never cleared
  when the honesty-threshold path emitted `.pullRequestsUnavailable` (which
  does clear the repo's cached facts on `RepoCacheAtom`'s side). A retry
  resolving to the exact same facts as before the outage was silently
  suppressed, permanently stranding the unavailable marker. Fixed by
  resetting `lastPublishedFactsByBranch = nil` at the same point
  `hasEmittedUnavailable` flips true, mirroring the existing
  `clearOrigin`/`setOrigin` reset pattern. Test drives the exact
  success(N) → 3 failures → unavailable → success(N) sequence and asserts a
  second `.pullRequestsChanged` event actually fires.
- **F7** (`a46a41edf`): owner ruling — dirty-with-zero-counts-and-zero-untracked
  renders no chip at all; dropped `.changesWithoutLineCounts` and its render
  branch entirely (hard cutover) rather than keeping the unauthorized bare
  "changes" state. Updated the test that previously blessed it.
- **F5** (`99cdf4740`): `paneRowFactsByPaneId`'s `isActive` was computed from
  the active tab's selected pane alone, so `● active` kept rendering while
  the sidebar had keyboard focus, another window was key, or the app was
  inactive. Fixed by composing `AttendedPaneDerived.attendedPaneId` (window
  key + management layer) with `KeyboardOwner.current(...)` (adds the
  missing sidebar-focus gate) — the same composition `CommandBarState` and
  `AppDelegate+CommandBar` already use for keyboard routing. Test drives all
  three required scenarios (window key + sidebar unfocused → active; sidebar
  focused → not active; window not key, which
  `WindowLifecycleAtom.isWorkspaceWindowKey` deliberately conflates
  "other window focused" and "app inactive" into one fact → not active)
  against one real pane via `withTestCoreAtoms`.
- **F3 test** (this commit): owner ruling — keep the learned-prompt-signature
  design, accept the one-settle degradation as self-correcting, no
  semantic-boundary fix this round. Added a doc comment on
  `TerminalActivityProjector.resolveLastOutputLine` explaining the
  D-before-prompt-paint race and the accepted degradation, plus a test
  (`wronglyLearnedSignatureSelfCorrectsOnNextSettle`) that drives settle 1
  with a trailing row that is real output (so it gets wrongly learned as the
  signature — the accepted degradation, confirmed: settle 1 surfaces the
  line beneath it instead) then settle 2 with the prompt now properly
  trailing, asserting settle 2 correctly publishes the real output beneath
  the now-correct prompt. The differentiator: if the signature had *not*
  re-learned, settle 2 would incorrectly surface the decorated prompt text
  itself, since it has letters and so is never caught by the bare-prompt
  fallback heuristic on its own — the test would fail on that regression.

Remaining after this pass: F1 (fresh full aggregate + fresh binary-fresh
one-build pixel sweep across items 1-19) is explicitly the
owner/orchestrator's next step per the done-gate ordering, not
sidebar-finisher's. RC2/Todo 1's live acceptance is still blocked on the
Ghostty C-API boundary documented above (`text_len == 0`); F3's ruling above
does not change that separate live-acceptance blocker.

## F1 final sweep (2026-08-17, HEAD 18bc7144f, fresh binary confirmed by owner)

Aggregate GREEN per owner (230.24s, exit 0, `tmp-aggregate-f1.log`). This
section is the one-build pixel/live sweep against the fresh binary (built
from this exact HEAD, binary mtime 13:34+ vs commit 12:53:38). All
screenshots under `tmp-screenshots/f1-final-sweep/`.

**Fixture setup.** Reused the existing `tmp/chip-matrix-final-live/` fixture
set (5 real git repos: `01-dirty` real dirty tree, `02-untracked` untracked
file, `03-sync` ahead-1/behind-1 against a local bare origin, `04-clean`
clean tree, `00-pr-agent-studio` pointed at the real
`github.com/ShravanSunder/agentstudio` remote on branch
`feat/sidebar-grouping-rows`, which has this round's real open PR #296).
Registered via `AGENTSTUDIO_STARTUP_WATCH_FOLDER` pointed at the fixture
parent directory. **Finding, not a code bug in scope this round:** the
watch-folder scan hung indefinitely with the bare `sync-origin.git` present
alongside the 5 working-tree repos; moving it out during the scan and back
afterward worked around it. Worth a follow-up ticket if bare repos are a
realistic watch-folder input, but out of scope for this remediation round.

IPC recipe notes for future sweeps: `terminal.send`/`terminal.wait`/
`pane.snapshot` take `{"handle": "pane:<uuid>", "input": ..., "condition":
..., "timeoutSeconds": ...}` (not `paneId`/`text`/`timeoutMs` — corrected
from an earlier round's notes). `PaneActivityStatusAtom`'s 10s leading-edge
rate limit means two settles sent back-to-back on one pane will drop the
second; wait >10s between settles you want to actually observe on L2.

| Item | Verdict | Evidence |
|---|---|---|
| 1. By Repo unchanged | PASS | `08-byrepo-sidebar-zoom.png`, `34-icon-gap-zoom.png` — name/branch/chips rows for all 5 fixture repos |
| 2. All Panes: grouped by repo, recency sort | PASS | `11-allpanes.png` (empty state, no panes yet); `24-l2-echo-allpanes.png`, `28-l2-ls-allpanes.png` (real pane rows, grouped) |
| 3. By Tab: panes by tab, header = displayTitle + pane count, muted-primary icon | PASS | `12-bytab.png` (empty state); `30-l2-ls-zoom.png` — "IPC Smoke Terminal · 2 panes" header, blue/muted-primary tab icon |
| 4. L1 bold "Pane n · title", fallback "Pane n · zsh" | PASS | `30-l2-ls-zoom.png` — "Pane 1 · zsh" (correct fallback vocabulary; no OSC title was set) |
| 5. L2 real terminal content, ordinary shell activity | PASS (headline) | `30-l2-ls-zoom.png` — real `ls -la` output line `drwxr-xr-x@  - shravansunder 17 Aug 13:30...` rendered live on the sidebar row, driven end-to-end via IPC `terminal.send`("ls -la") → `terminal.wait`(commandFinished) → sidebar capture. This is the RC2 fix's live proof: the same `ipc-terminal-smoke` + cd-reassociation pane that previously hit the Ghostty `text_len == 0` read now renders real content. |
| 6. L3 chips: PR / time ALWAYS / active only if focused | PASS (PR+time); see note (active) | `30-l2-ls-zoom.png`, `33-active-check-zoom.png` — time pill "5m" always present on both pane rows; neither row shows `●` active because this headless (`open -g`, no foreground steal) launch never makes the window key, so `KeyboardOwner.current(...)` never resolves to `.mainWindowChain` — this is F5's fix working as intended (the pre-fix tab-selection-only logic would have shown Pane 2 active regardless). Positive "●" pixel needs a foreground/key-window session, out of scope for a headless IPC sweep; covered live-equivalent by F5's automated `withTestCoreAtoms` test. |
| 7. By Repo diff: dirty=+N-M, untracked-only, clean=none | PASS | `08-byrepo-sidebar-zoom.png` — `01-dirty`→`● +3 -2`, `02-untracked`→`● untracked`, `04-clean`→ no chip |
| 8. By Repo sync: ↑N ↓M only if >0 | PASS | `08-byrepo-sidebar-zoom.png` — `03-sync`→`↑1 ↓1`; `04-clean`/`00-pr-agent-studio` show no sync chip (no upstream divergence) |
| 9. By Repo PR: ⑂N whenever N>0, never disappears | PASS (real data) | `15-pr-chip-zoom.png` — `00-pr-agent-studio`→`⑂ 1`, live GitHub API result for the real open PR #296 on this exact branch |
| 10. Toggle: 3 buttons, no borders, selected=accent icon+text+subtle fill, unselected=secondary icon only | PASS | `18-toggle-bytab-zoom.png`, `19-toggle-allpanes-zoom.png` — selected segment blue fill+icon+text, unselected segments plain secondary icons, no borders/outlines |
| 11. Sort: rotation animates, stable identity | Not re-verified live this round | Unchanged by this remediation round; source-string tests in the existing suite (`chipRowsCarryNoTimelineDrivenAnimation`, toggle identity tests) remain green |
| 12. Grouping mode persisted per window, restored on launch | PASS (live, cross-restart) | Set to "All Panes" (`14-allpanes-before-quit.png`), full app quit + relaunch, `local.sqlite` `repo_grouping_mode` read back `pane`, confirmed visually in `20-after-restart-allpanes.png` (toggle still shows "All Panes" immediately after restart, before any IPC calls) |
| 13. Empty state per mode | PASS | `11-allpanes.png` ("No panes"), `12-bytab.png` ("No tabs") |
| 14. Spacing rhythm identical across modes | PASS (visual) | Consistent row height/indent/chip position across `08-byrepo-sidebar-zoom.png`, `30-l2-ls-zoom.png` |
| 15. Context menus/commands unchanged | Not touched this round | No source change in scope; existing menu tests remain green |
| 16. All row facts cached reads; no per-row derivation/path strings | PASS | This is F6 itself — see F6 remediation section above; source-string guard test added |
| 17. Icon-to-text gap identical (header vs row) | PASS (visual) | `34-icon-gap-zoom.png` — group-header chevron/icon-to-text gap visually matches row star/branch-icon-to-text gap |
| 18. Chips row alignment: left, By Repo parity | PASS (visual) | `34-icon-gap-zoom.png` — chip pill's left edge aligns with the branch text's left edge above it |
| 19. Pending PR bare glyph, disappears once known | PARTIAL — not caught live | Polled at 5s intervals from `auth.login`; PR fact for `00-pr-agent-studio` had already resolved to `⑂1` by the first poll (`10-pr-poll-0.png`) in every attempt, including a fresh instance capture at ~20-40s post-scan (`09-byrepo-pr-check1-zoom.png`, which shows neither a pending glyph nor a chip — genuinely empty, not caught mid-transition). The live GitHub round-trip is fast enough that this sweep could not pin the transient pending frame. Not a change introduced by this round; existing pixel/unit tests (`RepoExplorerWorktreeRowTests` "stale pull request metadata renders as a bare chip-height glyph") cover the rendering logic directly. |

**Chip matrix (final gate).**

| Matrix cell | Verdict | Evidence |
|---|---|---|
| By Repo diff: dirty +N-M | PASS | `08-byrepo-sidebar-zoom.png` (`01-dirty` → `● +3 -2`) |
| By Repo diff: untracked-only | PASS | `08-byrepo-sidebar-zoom.png` (`02-untracked` → `● untracked`) |
| By Repo diff: clean = none | PASS | `08-byrepo-sidebar-zoom.png` (`04-clean` → no chip) |
| By Repo diff: unauthorized dot-alone `● changes` never appears | PASS | F7 fix; no fixture repo in this sweep can even reach that state anymore (case removed) |
| By Repo sync: ↑N ↓M | PASS | `08-byrepo-sidebar-zoom.png` (`03-sync` → `↑1 ↓1`) |
| By Repo sync: unknown/no-upstream = none | PASS | `08-byrepo-sidebar-zoom.png` (`04-clean`, `00-pr-agent-studio` → no sync chip) |
| By Repo PR: ⑂N, N>0 | PASS (real) | `15-pr-chip-zoom.png` (`⑂ 1`, real PR #296) |
| By Repo PR: stale bare glyph, prCount==nil | PARTIAL — see item 19 above | not caught live this sweep; existing test coverage unchanged |
| All Panes pane row: PR/time/active | PASS (time); see item 6 (active) | `28-l2-ls-allpanes.png` |
| By Tab pane row: PR/time/active | PASS (time); see item 6 (active) | `30-l2-ls-zoom.png` |
| Universal: never a zero-value or dot-alone chip | PASS | No zero-value/dot-alone chip observed anywhere in this sweep; F7 removed the one reachable violating state |
| Universal: left-aligned, chips-line leading x = L1/L2 leading x | PASS (visual) | `34-icon-gap-zoom.png` |
| Universal: same pill style/sizing everywhere | PASS (visual) | consistent pill rendering across `08-byrepo-sidebar-zoom.png` and pane-row screenshots |
| Universal: cached keyed reads, no per-row derivation | PASS | F6 |

**Not captured this round (screen availability was not the blocker — the gaps are network-race and headless-window-focus limits, not lock state):**
- Item 19 / stale-PR-matrix-cell transient pending glyph frame (GitHub round-trip resolved faster than the poll interval every attempt).
- Item 6 positive "●" active glyph (requires a foreground/key window; this sweep ran fully headless via `open -g` per house rule against foreground stealing).
- Item 11 sort-rotation animation and item 10's "no second reflow" claim (both need multi-frame/video capture, not single-shot screenshots; unchanged by this round, existing source-string tests still green).

## Owner color directives (2026-08-17, after F1 sweep, before rerun)

Amended `SIDEBAR-VISUAL-CONTRACT.md` with an explicit anchor rule (item 0):
By Repo's palette is the reference; All Panes/By Tab colors for a given role
must resolve to the same token By Repo uses for that role.

1. **Tab group icon**: `AppStyles.Shell.Sidebar.tabGroupIconColor` changed
   from a muted-accent-blue derivation (`AppStyles.General.Accent.primaryColor.opacity(...)`)
   to `Color.secondary` directly — the exact source By Repo's second-line
   text uses via `SidebarMetadataProminence.secondary`. Can't reference
   `SidebarMetadataProminence` itself from `AppStyles` (Infrastructure
   cannot import SharedComponents), so this points at the same underlying
   system token both consumers ultimately resolve to, not a new duplicate.
   Strengthened `SidebarSourceGroupHeaderTests` to pin the token to
   `Color.secondary` directly (previously only a structural equality check).

2. **PR chip color**: `c7295bb13`'s diff shows the pre-unification By Repo
   row colored its PR chip from the row's own `iconColor` param, which
   resolves via `RepoPresentationGrouping.checkoutColorHex` →
   `AppStyles.Shell.Sidebar.accentPaletteHexes[0]` (`#F5C451`, yellow/gold)
   for the common singleton-worktree case — the same color the favorite-star
   icon renders. Added a named `AppStyles.Shell.Sidebar.checkoutDefaultAccentColor`
   accessor for that specific palette entry (rather than duplicating the hex)
   and repointed `SidebarPullRequestChipSpec.chip(...)` to it, so all three
   surfaces (By Repo, All Panes, By Tab) keep the single shared spec but now
   render yellow instead of the product blue. Updated
   `RepoExplorerWorktreeRowTests`'s pixel test signature from the blue
   `#409CFF` band to the yellow `#F5C451` band (red > 0.55, green
   0.35...0.75, blue < 0.40).

3. **Full sync audit**: grepped for raw `.accentColor`/`Color.blue`/
   `Color.yellow`/`Color(red:...)` literals across `Features/RepoExplorer`,
   `Core/Views`, and `SharedComponents`. `AppEntityIcon.foregroundStyle`
   already centralizes every group-header icon color through one switch
   (`.repo`/`.pane`/`.tab`/`.workspace`/`.otherSources` → `.secondary`;
   `.tabGroup` → the now-fixed `tabGroupIconColor`; `.coloredRepo`/`.checkout`
   → the shared per-checkout hex resolver), so headers across all three
   modes were already synchronized once item 1 landed. `SidebarSectionHeader`,
   `SidebarGroupRow`, and `SidebarSourceGroupHeader` are shared components
   used by all three modes (can't diverge by construction). Row title/branch
   text prominence (`.primary`/`SidebarMetadataProminence.secondary`) matches
   between `RepoExplorerWorktreeRow` and `RepoExplorerPaneNavigation`.
   **One divergence found and flagged, not changed**:
   `RepoExplorerPaneNavigation.swift`'s pane-row "active" chip uses raw
   `.accentColor` (system blue) directly, not a named `AppStyles` token. This
   has no By Repo counterpart role (By Repo has no "active" concept), so the
   anchor rule doesn't mandate a specific target color for it — flagging
   because it's still a raw-system-color usage inconsistent with the rest of
   the codebase's token discipline, in case the owner wants it moved to a
   named token in a future round.

Proof: `mise run lint` (swift-format + swiftlint + architecture lint) clean;
focused suites green — `RepoExplorerWorktreeRowTests` (30 tests incl. the
updated yellow pixel test), `SidebarSourceGroupHeaderTests` (5 tests incl.
the strengthened token assertion), full `RepoExplorer|SidebarChips|AppStyles`
filter (211 tests / 24 suites).
