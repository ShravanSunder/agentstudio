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

Gate: all items land → full aggregate + lint → merged build → pixel validation (orchestrator) → owner review. #296 stays draft until owner approves.

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
