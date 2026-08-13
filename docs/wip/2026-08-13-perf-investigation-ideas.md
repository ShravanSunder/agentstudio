# Performance investigation ideas ledger

Living backlog of measured findings and ideas to investigate with subagents.
Each item: evidence → hypothesis → investigation shape. Newest first.
Full analysis: tmp/perf-s5/analysis/2026-08-13-live-session-analysis.md (+ reproducible analyze_live_session.py).

## Ranked fix map (Luna live-session analysis, 2026-08-13 — SUPERSEDES earlier guesses)

1. **Command-bar `#` root-item construction on MainActor** — 5/8 builds at 83–86ms
   over 121 repos/160 worktrees; filter itself 1.4ms; ZERO temporal overlap with
   git (0/8 within ±1s — the git hypothesis was wrong for the command bar).
   Cache exists but invalidation reasons uninstrumented. Owner: CommandBarResultSession/
   CommandBarDataSource. First step: instrument cache hit/invalidation reason; then
   reduce/reuse `#`-scope root work. Small–medium.
2. **Git admission saturation under huge visible set** — s3's gate WORKING AS DESIGNED
   (256 capacity refusals = gate holding; not bypassed), but 160 registered worktrees
   post-folder-add saturate 4 compute slots; 11 real ~1s timeouts; all statuses
   full-scope (no pathspec in this window). Fix: attention-tiered demand + per-tier
   concurrency budget (user's 3-min idea) — but FIRST item 5 (attribution). Medium.
3. **Bulk source-sync staging** — 589ms + 290ms source_sync totals are AWAIT time in
   the filesystem source (MainActor apply <0.001ms — the earlier 'MainActor write
   avalanche' mechanism reading was WRONG; overlap was temporal, not causal).
   Coalesce/stage initial registration (56–105 registrations per write). Medium.
4. **Possible Forge follow-up duplication** — snapshotChanged+branchChanged pair can
   schedule one extra remote PR refresh (bounded: one active + one follow-up).
   #271 verdict otherwise CLEAN: no double local-git system; respects own
   demand/single-flight/180s freshness. Small; needs a blocked-provider test first.
5. **Git trigger attribution gap (PREREQUISITE for item 2)** — admission/status
   records lack demand class, trigger source, cadence tier, correlation ID.
   Add safe categorical attributes + joinable request identity. Small.
6. **Pattern doc: trigger-policy/attention-tier section** — unchanged from before.
7. **Stress baseline** — this session's window is captured and reproducible via the
   analysis script; formalize as the named before-state for items 1–3.

## Superseded readings (kept for honesty)
- 'Git triggers cause command-bar slowness' — disproved (0/8 overlap).
- 'Coordinator writes block the MainActor for 290–841ms' — the totals are awaits;
  MainActor apply is sub-microsecond. The interaction crawl correlates with the
  burst temporally; causal path still needs a correlation ID (fix-map item 5).

## Done / carried into slices
- Title-accumulator equal suppression (s2), git full-scan contraction (s3),
  explorer keyed capture (s4), startup deferral + occluded liveness (s5).
- Rails: perf-report resolvers, workload resets, completion records,
  keyed_wake counters, three-marker design, analyze_live_session.py.
