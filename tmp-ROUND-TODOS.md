# Round todo ledger (owner-locked, 2026-08-17)

| # | Item | Owner | Status |
|---|------|-------|--------|
| A | Toggle selected ICON accent (#409CFF), pixel-proven | sidebar-finisher | done (commit 1c6a45e7e; pixel test AppEntityIconTests) |
| B/1 | L2 real terminal output: status-fact split (keyed slots, equal-write suppression, 10s per-pane update cadence, timerless), live-proven in observed pane | sidebar-finisher | in progress |
| 3 | PR chip parity: ONE glyph AND ONE COLOR everywhere (owner: color not fixed yet) — single shared chip spec (glyph + product accent token, not .accentColor vs octicon mix) | sidebar-finisher | done (commit c7295bb13; SidebarPullRequestChipSpec + pixel test) |
| 4 | Toggle selected fill = shared accent token (match Zoom pill family, intensity via opacity tokens) | sidebar-finisher | done (commit d6ce6fdcd; ChromeToolbarControlPalette.fillColor wired for selected state) |
| 2 | Forge-lane honesty: every outcome terminal; no-remote → no glyph; failure → backoff then nothing; pending only while fetch genuinely expected | forge-fixer | dispatching |
| 2b | Forge update cadence: PR-count refresh at most once per 3 MINUTES per repo/branch (owner policy; AppPolicies constant; verify what the system does today and enforce) | forge-fixer | dispatching |

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

## Binary-freshness gate (added 2026-08-17 after two stale-binary incidents)
Before ANY visual validation or owner presentation: verify the running bundle
binary's modification time is NEWER than the branch's last commit time
(command stat on ~/.agentstudio-db/jp6s/apps/.../MacOS/AgentStudio vs git log -1
--format=%ci). Stale → mise run build + relaunch FIRST. No screenshots from a
binary older than the code it claims to demonstrate.
