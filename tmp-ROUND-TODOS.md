# Round todo ledger (owner-locked, 2026-08-17)

| # | Item | Owner | Status |
|---|------|-------|--------|
| A | Toggle selected ICON accent (#409CFF), pixel-proven | sidebar-finisher | done (commit 1c6a45e7e; pixel test AppEntityIconTests) |
| B/1 | L2 real terminal output: status-fact split (keyed slots, equal-write suppression, 10s per-pane update cadence, timerless) | sidebar-finisher | code + unit/integration tests done (commit 7e17fe875); live acceptance BLOCKED — see RC2 row |
| RC2 | commandFinished admitted as second settle-evidence source (Contract 7) so attended/fast-completing commands settle without scrollbar bursts | sidebar-finisher | code + unit/integration tests done (commits d4f477e98, 7fed04fbd — learned prompt signature, owner-ratified option 3); live acceptance STILL not proven — instance-identity and pane-ID-path candidates ruled out via source trace, three-line viewport shape ruled out via unit test; decisive telemetry evidence on a genuinely minimal single-repo/single-pane workspace shows the settle pipeline completes (confirmed via inbox.decision) but PaneActivityStatusAtom.recordSettledActivity records ZERO writes (51 telemetry records for pane_activity_status, all operation:"value" reads) — gap is upstream of the atom write itself. Full evidence + recipe in tmp-RESULT.md. Awaiting owner go-ahead on a temporary diagnostic log line to pin down the exact call site. |
| 3 | PR chip parity: ONE glyph AND ONE COLOR everywhere (owner: color not fixed yet) — single shared chip spec (glyph + product accent token, not .accentColor vs octicon mix) | sidebar-finisher | done (commit c7295bb13; SidebarPullRequestChipSpec + pixel test) |
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

## Binary-freshness gate (added 2026-08-17 after two stale-binary incidents)
Before ANY visual validation or owner presentation: verify the running bundle
binary's modification time is NEWER than the branch's last commit time
(command stat on ~/.agentstudio-db/jp6s/apps/.../MacOS/AgentStudio vs git log -1
--format=%ci). Stale → mise run build + relaunch FIRST. No screenshots from a
binary older than the code it claims to demonstrate.
