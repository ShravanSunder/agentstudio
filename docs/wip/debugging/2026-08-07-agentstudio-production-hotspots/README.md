# AgentStudio production hotspot collection

Status: evidence collection complete for the available production, debug, beta,
and disposable-workload runs. No product-code changes were made.

Scope: production `0.0.74`, a fresh debug build from this worktree, and a local beta diagnostic when available. The goal is to enumerate observed pressure sources and trace each one through admission, background work, the MainActor boundary, rendering, and the atom/invalidation graph.

This is an evidence collection, not a fix plan. A finding is accepted only when it has a current-source anchor plus fresh runtime evidence; otherwise it remains a lead or unresolved question.

## Collection map

- [00-bug-packet.md](00-bug-packet.md) — symptom, scope, runtime identities, and proof boundaries.
- [01-pressure-map.md](01-pressure-map.md) — source → admission → compute → MainActor → presentation → telemetry map.
- [02-git-trigger-status.md](02-git-trigger-status.md) — Git/FSEvents trigger classes, coalescing, retries, and status cost.
- [03-terminal-ghostty.md](03-terminal-ghostty.md) — Ghostty action volume, drain admission, title/immediate behavior, and apply cost.
- [04-mainactor-invalidation.md](04-mainactor-invalidation.md) — MainActor boundaries, coordinator timing, and UI/list-diff evidence.
- [05-atom-dag.md](05-atom-dag.md) — keyed entity maps, broad snapshots, derived readers, and invalidation risk.
- [06-observability-overhead.md](06-observability-overhead.md) — OTEL volume, queue/export semantics, and measurement caveats.
- [07-captures-and-ledger.md](07-captures-and-ledger.md) — production/debug/beta identities, fresh markers, commands, and evidence ledger.
- [08-surface-coverage.md](08-surface-coverage.md) — complete instrumented surface inventory and missing correlations.
- [09-fresh-production-and-beta.md](09-fresh-production-and-beta.md) — stable samples, current telemetry rollup, and beta startup block.

## Evidence states

- `accepted`: current source and fresh runtime evidence agree.
- `lead`: plausible and source-backed, but runtime attribution is incomplete.
- `refuted`: the available evidence contradicts the hypothesis.
- `unresolved`: the needed probe or telemetry does not exist yet.

## Current headline

The shipped `0.0.74` production samples identify a workload-dependent hotspot set. One window is Git-heavy (full status scans dominate); later windows are Repo Explorer/renderer-heavy (SwiftUI outline diff and Ghostty Metal work dominate), while Git remains recurrent. A fresh 15-second high-CPU sample put `OutlineListCoordinator.diffRows` at 4,642 intervals on the main thread (55.9% of its continuously present samples), with concurrent libgit2 and renderer work on worker threads. Those are one-core-equivalent stack shares, not additive CPU percentages. Persistent MainActor apply saturation is not established, but the current-code beta has a separate startup block inside synchronous Ghostty surface creation on the MainActor.

The atom-DAG hypothesis remains a lead for the Repo Explorer path, not a proven cause of the Git or renderer lanes. Fresh debug is an idle negative control. The disposable Git workload ran to cleanup, but its strict export gate remains blocked because the expected `performance.topology.repo_and_worktree` family emitted no records; the other workload families are fresh and marker-scoped. A separate `atoms`-tag diagnostic produced high atom-read volume and OTLP queue drops, but its startup proof gate failed before the IPC workload, so it is diagnostic evidence rather than a completed benchmark.
