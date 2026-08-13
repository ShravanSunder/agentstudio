# Performance investigation ideas ledger

Living backlog of measured findings and ideas to investigate with subagents.
Each item: evidence → hypothesis → investigation shape. Newest first.

## Open (from the 2026-08-13 live stress session, marker debug-observability-vagx-1786581785)

1. **Attention-tiered demand admission** — demand is currently binary
   (visible|active|explicit → admit); after a heavy folder-add, "visible" ≈
   everything → fleet-parallel statuses → slot saturation (17 × uniform
   1066ms timeouts). Idea: tiers (active pane / visible sidebar / open pane /
   background) each with own cadence (~fast/~medium/~3min/deferred) AND
   concurrency share. Check whether the #271 PR-facts system already models
   this; if so promote its policy shape into the pattern doc.
2. **Discovery/enrichment application coalescing** — Add Folder burst:
   42 coordinator writes in one second, single write up to 841ms, 4.1s
   cumulative MainActor. Application side needs latest-value coalescing +
   bounded keyed batches + yields.
3. **MainActor decoupling audit** — under-100% CPU with MainActor crawl =
   wait-bound: find interactive paths awaiting congested actors (tab switch,
   command bar); they should consume last-published materialized facts
   instead. Luna write-attribution pending.
4. **#271 × slice-3 double-trigger check** — do both systems react to the
   same filesystem/git events; does #271 respect s3 admission? (Luna item 3.)
5. **Command-bar item build cost** — commandbar.items p95 98ms; what does
   open/keystroke rebuild read? Keyed reads per s4 idiom? (Luna item 4.)
6. **Pattern doc: trigger-policy section** — when triggers fire (event vs
   cadence vs attention-change), per-tier cadence + budget, coalescing per
   tier. Extends demand_driven_derived_state_refresh.md.
7. **Stress baseline capture** — snapshot this session's window as the named
   before-state that items 1-3 fixes must demonstrably improve.

## Done / carried into slices
- Title-accumulator equal suppression (s2), git full-scan contraction (s3),
  explorer keyed capture (s4), startup deferral + occluded liveness (s5).
- Rails: perf-report resolvers, workload resets, completion records,
  keyed_wake counters, three-marker design.
