# Round todo ledger (owner-locked, 2026-08-17)

| # | Item | Owner | Status |
|---|------|-------|--------|
| A | Toggle selected ICON accent (#409CFF), pixel-proven | sidebar-finisher | done (commit 1c6a45e7e; pixel test AppEntityIconTests) |
| B/1 | L2 real terminal output: status-fact split (keyed slots, equal-write suppression, 10s per-pane update cadence, timerless) | sidebar-finisher | code + unit/integration tests done (commit 7e17fe875); live acceptance BLOCKED — see RC2 row |
| RC2 | commandFinished admitted as second settle-evidence source (Contract 7) so attended/fast-completing commands settle without scrollbar bursts | sidebar-finisher | DONE, including live acceptance. Ghostty `text_len == 0` root cause fixed (commit b351992f0, ancestor of remediated HEAD). F1 sweep (2026-08-17) proved it live: real `ls -la` output rendered on the sidebar row of an `ipc-terminal-smoke` + cd-reassociated pane — the exact recipe that previously hit the zero-length read. `tmp-screenshots/f1-final-sweep/30-l2-ls-zoom.png`. Full trace in tmp-RESULT.md. |
| Review | Independent review (tmp-REVIEW-REPORT.md) NOT-READY findings F1-F9 | sidebar-finisher | F2, F4, F5, F6, F7, F8, F9 code+tests DONE (commits db6eff828..18bc7144f). F3 = owner ruling applied, self-correction proven by test, no code fix. F1 (fresh aggregate + fresh-binary sweep) = DONE this round: aggregate green on HEAD 18bc7144f (owner-verified, tmp-aggregate-f1.log), one-build live sweep of contract items 1-19 + chip matrix in tmp-RESULT.md "F1 final sweep" section, screenshots under tmp-screenshots/f1-final-sweep/. Two evidence gaps noted honestly (not blockers, not regressions): item 19's transient pending-glyph frame resolved faster than the poll interval every attempt (GitHub API round-trip), and item 6's positive "●" active glyph needs a foreground/key window this sweep intentionally didn't take (headless `open -g` launch, per house rule). Reviewer re-audit is next. |
| 3 | PR chip parity: ONE glyph AND ONE COLOR everywhere | sidebar-finisher | done, color now FINAL (commits c7295bb13 structure, c009a3311 color). Owner directive: By Repo's palette is the reference (new contract anchor rule, item 0). PR chip repointed from product blue to `AppStyles.Shell.Sidebar.checkoutDefaultAccentColor` (`#F5C451` yellow/gold, the same token By Repo's favorite star already renders for the common case) — matches what By Repo rendered before the unification commit. Live-proven: `tmp-screenshots/f1-final-sweep-v2/14-prchip-yellow-final.png` (real `⑂1`, PR #296). Pixel test RGB band updated. |
| Color-sync | Tab group icon color + full By Repo/All Panes/By Tab color-sync audit | sidebar-finisher | done (commit c009a3311). Tab-group icon changed from muted-accent-blue to `Color.secondary` (same source as By Repo's own second-line text). Live-proven: `tmp-screenshots/f1-final-sweep-v2/15-tabicon-final-zoom.png`. Audit found one adjacent divergence (pane row's "active" chip uses raw `.accentColor`, no By Repo role to sync against) — flagged in tmp-RESULT.md, not changed. |
| 4 | Toggle selected fill = shared accent token (match Zoom pill family, intensity via opacity tokens) | sidebar-finisher | done (commit d6ce6fdcd; ChromeToolbarControlPalette.fillColor wired for selected state) |
| 2 | Forge-lane honesty: every outcome terminal; no-remote → no glyph; failure → backoff then nothing; pending only while fetch genuinely expected | forge-fixer | DONE, including live acceptance. Merged (commits 111e570ca, f8a15fe7f via feat/forge-honesty → 6f94ce855); projection re-render wiring completed by sidebar-finisher (commit 28b7ebd53); live acceptance PROVEN (pixel screenshot 2026-08-17): no-remote-repo/main, detached-repo/main, detached-repo-worktree/detached HEAD all render clean branch lines with no PR chip and no pending glyph. `tmp-screenshots/forge-live-proof/no-remote-and-detached-head-no-glyph.png`. |
| 2b | Forge update cadence: PR-count refresh at most once per 3 MINUTES per repo/branch (owner policy; AppPolicies constant; verify what the system does today and enforce) | forge-fixer | merged via feat/forge-honesty (see #2) |
| 5 | Unify second-line rendering: extend SidebarMetadataLine for octicon support, replace RepoExplorerWorktreeRow's hand-rolled branch/placement HStacks, sweep for other hand-rolled second-line `.foregroundStyle(.secondary)` usages | sidebar-finisher | done (commit 0f4b84532; 29+575 tests green incl. source-pinning tests; sweep found no other genuine duplicates — remaining `.foregroundStyle(.secondary)` sites are a different visual role: stale-PR-chip glyph, status/loading banners, empty-state view) |
| Follow-up (tracked, NOT this round) | Watch-folder scan hangs indefinitely when a bare repo (a `.git` directory with no working tree, e.g. a local push/pull target) sits alongside working-tree repos under the same scanned parent | unowned | Found during the F1 sweep fixture setup (2026-08-17): `AGENTSTUDIO_STARTUP_WATCH_FOLDER` pointed at a directory containing 4 working-tree repos plus one bare `sync-origin.git` never completed scanning ("Scanning ... / Looking for git folders..." stuck indefinitely, `repo` table stayed empty). Removing the bare repo from the directory let the scan complete instantly; re-adding it reproduced the hang. Not investigated further (out of scope for the color/review remediation round) — root cause and fix location unknown, needs its own ticket if bare repos are a realistic watch-folder input. Worked around for the sweep by relocating the bare repo out of the scanned directory during capture. |

Gate: all items land → full aggregate + lint → merged build → pixel validation (orchestrator) → owner review. #296 stays draft until owner approves.

## Ledger note: color-directive delta re-capture already complete (2026-08-17)

The owner's "OWNER COLOR DIRECTIVES" message and team-lead's later "sweep
accepted, but that message still applies" message crossed with work already
done: items 1-3 (tab-group icon, PR chip yellow, full sync audit) landed in
commit `c009a3311`, and the delta re-capture (fresh binary, PR chips in all
reachable views, tab-group header) landed in commit `17ece6593` — both
pushed before the "still applies" message arrived. See ledger rows "3" and
"Color-sync" above for the full writeup, and `tmp-RESULT.md` sections "Owner
color directives" and "F1 sweep rerun on final colors" for evidence.

**Superseded**: `tmp-screenshots/f1-final-sweep/` (v1) PR-chip and
tab-group-icon shots show the pre-directive blue colors — superseded by
`tmp-screenshots/f1-final-sweep-v2/14-prchip-yellow-final.png` and
`15-tabicon-final-zoom.png`.

**Still valid, not redone** (unaffected by the color-only change; matches
team-lead's explicit instruction not to redo structural/behavioral proofs):
L2 live real-terminal-content proof, grouping-mode persistence across
restart, icon-to-text spacing/chip alignment, toggle border/fill geometry,
empty states per mode, diff/sync chip matrix values — all from the v1 sweep
(`tmp-screenshots/f1-final-sweep/`), same HEAD lineage, source files
unchanged by the color commit.

Item 6's positive "●" active glyph remains explicitly deferred to team-lead's
own foregrounded validation pass, per their message.

## Done-gate (owner-ordered, 2026-08-17)
1. Finisher completes stack + aggregate green.
2. INDEPENDENT SOL REVIEW (fresh session, no shared history): review the worktree
   diff against SIDEBAR-VISUAL-CONTRACT.md + this ledger, item by item — code
   correctness, requirement satisfaction, evidence quality. Findings back to
   orchestrator; failures loop before any done claim.
3. Orchestrator pixel validation on the built app (icon color sampled, alignment
   measured, L2 live-typed proof, no eternal pending).
4. ONLY THEN owner review of #296. No merge without owner approval.

## Full aggregate (2026-08-17, after commits 28b7ebd53 + 0f4b84532)

`SWIFT_TEST_TIMEOUT_SECONDS=2700 SWIFT_TEST_PREBUILD_TIMEOUT_SECONDS=1800 mise
run test` — exit 0, 226.73s. Covers Swift lint + architecture lint, BridgeWeb
lint/typecheck/unit/integration/browser/Vite E2E, packaged BridgeWeb build,
Swift non-serialized + serialized WebKit + E2E serialized tests. Done-gate step
1 (finisher completes stack + aggregate green) satisfied for everything on the
stack except RC2/Todo 1's live acceptance (blocked, reported to owner) and the
forge no-remote/detached-HEAD live acceptance (rides this same sweep once
unblocked).

## Full aggregate rerun (2026-08-17, after commits b567b0649 + 3ee4f16de + 2b5097bfe)

`SWIFT_TEST_TIMEOUT_SECONDS=2700 SWIFT_TEST_PREBUILD_TIMEOUT_SECONDS=1800 mise
run test` — exit 0, 218.38s. Forge live acceptance is now closed (see item 2
above). Only remaining open item is RC2/Todo 1's live acceptance — root cause
narrowed to zero writes reaching PaneActivityStatusAtom despite a confirmed
end-to-end settle pipeline; awaiting owner go-ahead on a temporary diagnostic
log line to pin the exact call site (see tmp-RESULT.md).

## Binary-freshness gate (added 2026-08-17 after two stale-binary incidents)
Before ANY visual validation or owner presentation: verify the running bundle
binary's modification time is NEWER than the branch's last commit time
(command stat on ~/.agentstudio-db/jp6s/apps/.../MacOS/AgentStudio vs git log -1
--format=%ci). Stale → mise run build + relaunch FIRST. No screenshots from a
binary older than the code it claims to demonstrate.

## Re-audit round 2 (N1-N6, N5/F1 final gate) — 2026-08-17

| Item | Owner | Status |
|---|---|---|
| N6 | sidebar-finisher | done. SIDEBAR-VISUAL-CONTRACT.md item 3 amended to match item 0's anchor rule (tab icon = By Repo second-line text shade), owner ruling noted inline. |
| N1 | sidebar-finisher | done. Migration 005's grouping-mode copy now deterministic (`ORDER BY updated_at DESC LIMIT 1`, documented rationale: the active-workspace selection that would resolve this lives in a separate database — core.sqlite — this local migration cannot reach). Test seeds two legacy workspace rows with different modes, proves the newer one wins. |
| N2 | sidebar-finisher | done. (a) `projectionInputRevision` now reads the same `KeyboardRoutingContext`/`attendedPane` facts `paneRowFactsByPaneId` depends on, so a focus-only transition admits a reprojection — proven via the exact `withObservationTracking` wiring production uses. (b) `paneRowFactsByPaneId` now uses `KeyboardRoutingContext.current(...)` (adds `isStableMainWindowChain`, a new accessor) instead of raw `KeyboardOwner.current(...)`, so an open command bar drops the active dot — proven live in a unit test. |
| N3 | sidebar-finisher | done. `TerminalActivityRouterCloseTests` F9 regression test replaced with a real `PaneActivityStatusAtom` integration: seeds a fact, closes through the router, asserts keyed removal, and proves the rate-limit dictionary itself was reset by republishing a different line at the identical fixed timestamp. |
| N4 | sidebar-finisher | done. All flagged bare `UUID()` sites replaced with `UUIDv7.generate()`. |
| N5/F1 final gate | sidebar-finisher | PARTIAL — aggregate + binary done, pixel sweep BLOCKED. Fresh aggregate run SHA-stamped to HEAD `0d5d413eb84c8de38c48101b73702d758795a292` (commit time 2026-08-17 14:59:06-0400): exit 0, 215.04s, `tmp-aggregate-n5-0d5d413eb.log`. Fresh binary built and verified (mtime 2026-08-17 15:07:20 > commit time). Started the one-build sweep (auth'd, switched grouping modes, began the PR-chip patient poll) but the physical displays went to sleep mid-run ("Display Asleep: Yes" on both the external DELL and the built-in display, confirmed via `system_profiler SPDisplaysDataType`) — every `peekaboo see` call failed with "No displays available for window capture" and produced zero screenshot files. Quit the debug app cleanly rather than leave it running or attempt to wake the display. Per house rule (never bypass a locked/unavailable screen), stopped pixel work and reported the blocker rather than guessing. **The already-built binary (mtime 15:07:20, HEAD 0d5d413eb) remains valid for the sweep once a display is available — no rebuild needed, just relaunch.** All non-pixel work for this gate (source fixes N1-N6, aggregate, binary freshness) is complete. |

Blocked deliverable when displays are available: ONE complete pixel sweep on
the 0d5d413eb binary covering every contract item and matrix cell, including
the previously-split cells (final-yellow pane-row PR chip in All Panes/By
Tab, diff/sync chips, empty states, icon-to-text alignment, toggle
border/fill geometry, sort-rotation motion). The two cells team-lead already
claimed for their own foregrounded validation pass (positive active glyph,
pending-glyph transition) remain deferred to that pass, same SHA/binary.

## N5/F1 sweep completed (2026-08-17, HEAD 34e1815ad)

Owner verified the session genuinely unlocked via the authoritative `ioreg
-n Root -d1 -a | grep IOConsoleLocked` probe (`false` — this is the correct
check going forward, not the frontmost-app heuristic that misled an earlier
attempt where a real lock screen was captured). Ran the sweep under
`caffeinate -d` holding the display awake. HEAD had advanced to
`34e1815ad1f2b75efe9569c8daa5dad8868571a3` (a docs-only child of the
0d5d413eb aggregate/binary commit — `git diff 0d5d413eb...34e1815ad --
Sources Tests` confirmed empty, so that aggregate result still applies) by
the time of this pass; rebuilt fresh (binary mtime 16:46:04), still newer
than the commit.

Full evidence table in tmp-RESULT.md under "N5/F1 final gate: complete
one-build sweep". Headline: the previously-split "final-yellow pane-row PR
chip" cell is now closed — proven live in both All Panes and By Tab on this
one binary (`tmp-screenshots/n5-final-gate-sweep/17-allpanes-pr-chip-zoom.png`,
`18-bytab-pr-chip-zoom.png`). Persistence-across-restart, L2 real content,
By Repo chip matrix, toggle geometry, and icon-to-text alignment all
recaptured fresh on the same binary.

Two items not recaptured, both with a stated reason (not silently dropped):
(13) empty state — `closePane` rejected via IPC with `-32007 parameters
required` despite being in the durable-pane-target command group; did not
debug the IPC contract further this round, relying on unchanged v1 evidence
instead. (10b/11) toggle no-second-reflow and sort-rotation motion — static
screenshots structurally cannot prove motion; relying on the existing
source-string tests, unchanged this round.

Deferred to the orchestrator's own foregrounded pass on this same binary
(34e1815ad, mtime 16:46:04), per the owner's plan: item 6's positive "●"
active glyph (needs real key-window focus) and item 19's pending-glyph
transition (a live-network race no headless capture has caught in any
sweep so far).

## Pass 3 residuals (2026-08-17)

| Item | Owner | Status |
|---|---|---|
| N1 tie-breaker | sidebar-finisher | done. Migration 005's `ORDER BY updated_at DESC` alone left the winner unspecified when two legacy rows share an identical `updated_at` (same-batch/import write). Added `workspace_id DESC` as a deterministic secondary key; updated the migration comment. New test decouples insertion order from workspace_id ordering (inserts the lesser id last) so a naive/unfixed query — which in this SQLite build happened to favor the most-recently-inserted row on ties — cannot coincidentally pass; confirmed genuinely red against the unfixed query (`repoGroupingMode == "pane"` vs expected `"tab"`) before restoring the fix. Full `WorkspaceLocalMigrationTests` suite (13 tests) green, `mise run lint` exit 0 with zero findings in either changed file. Commit `525f7dafd` (unsigned — two 1Password sign attempts failed with "failed to fill whole buffer", falling back per house AFK policy), pushed to `feat/sidebar-grouping-rows`. |
| F6 boundary | sidebar-finisher | RULING (no code change, pass-3 residual): the view-owned memoization stands for this round as an explicit re-spec. Tracked follow-up: **F6 boundary: move title/shell derivation into owning caches publishing keyed facts — perf-program follow-up, reviewer pass-3 residual.** |
| Final binary | sidebar-finisher | done — see "Final binary (pass 3)" section below. |

## Final binary (pass 3, 2026-08-17)

HEAD: `525f7dafdc361ff9f0ef258cb2e836971e065c31` (commit time 2026-08-17
17:51:24-0400, the N1 tie-breaker commit). Rebuilt via `mise run build` then
relaunched via `mise run run-debug-observability -- --detach` (which rebuilds
again as part of its own flow — same HEAD, no intervening commit). Binary
mtime `Aug 17 17:52:53 2026` > HEAD commit time 17:51:24 — freshness
confirmed. PID `43907`, launched background via LaunchServices (`open`-based,
no foreground steal), debug code `jp6s`, marker
`debug-observability-jp6s-1787003571-42930`. Launched and left running per
instruction — no screenshots or IPC interaction taken after this launch. The
remaining evidence cells (empty state via GUI pane-close, sort/toggle motion
burst, positive active glyph, pending-glyph transition via fresh-repo
registration) are reserved for the orchestrator's own foregrounded pass on
this exact binary/PID.
