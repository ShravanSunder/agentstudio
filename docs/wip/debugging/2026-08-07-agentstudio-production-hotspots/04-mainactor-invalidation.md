# MainActor and invalidation edges

## Measured MainActor cost

Production timing separates awaited/background work from the small apply sections:

- terminal compact apply: roughly 0.12 ms steady average, ~1 ms maximum;
- sidebar projection request construction: ~7 ms average, 10.4 ms maximum;
- sidebar projection worker: ~4.9 ms average, 5.7 ms maximum;
- sidebar projection apply: ~0.03 ms average, 0.048 ms maximum;
- startup source/index and Git projection totals: hundreds of milliseconds, while measured MainActor apply sections were effectively zero;
- pane/tab layout elapsed maximum: 48.8 ms; pane restore maximum: 75.2 ms; these are model/layout probes, not frame paint measurements.

The fresh debug capture was idle: CPU 0–4%, EventBus debt/drops zero, two coordinator writes, and no Git or atom telemetry. It validates the launcher and negative path, but not the production workload.

## Repo Explorer path

`RepoExplorerView` establishes a `withObservationTracking` loop around a projection request at [RepoExplorerView.swift](../../../../Sources/AgentStudio/Features/RepoExplorer/RepoExplorerView.swift:637). Request construction reads the entire topology array at lines 109–111, per-repo enrichment at lines 124–129, and a filtered `worktreeFactsSnapshot()` at lines 155–158. A changed observation schedules a new MainActor observation and cancels the prior worker at lines 639–644 and 707–715.

The stack sample found about 425 intervals in SwiftUI `OutlineListCoordinator.diffRows` and 404 in `ForEachList`, with `RepoExplorerListEntry` identities. This is a material presentation hotspot. The current telemetry window had zero Git events published and zero sidebar projection events, so it is not yet correlated to Git result publication.

A second PID-bound stable sample raised this same presentation lane to 2,998 sampled `OutlineListCoordinator.diffRows` intervals (about 20.3% of one core-equivalent sample intervals), with 2,868 sampled `ForEachList` traversals. Those samples are occupancy observations, not invocation counters, so they do not establish a per-second list-diff rate. The sample also showed active Ghostty renderer/Metal work at about 19.3%, while Git status was about 3.0%. The two samples establish that the expensive lane changes with runtime state; they do not establish that every list diff is caused by an atom mutation. A frame-rate revisit/animation invalidation is an equally live lead.

A fresh high-CPU stable sample makes the same shape more pronounced. PID `95537` (`0.0.74`, build `115`) was sampled for 15 seconds; the continuously present main thread contributed 8,359 sampled intervals. `OutlineListCoordinator.diffRows` appeared in 4,642 sampled intervals (55.9%), with 4,525 recursive row-diff intervals and 4,396 `ForEachList` traversals (local-only sample artifact: `/tmp/AgentStudio_2026-08-07_stable-highcpu-primary-95537.sample.txt`, line 45). The active worker mix in that same sample included 2,628 libgit2 blocking-read intervals (31.4%) and 2,611 aggregate Ghostty renderer intervals (31.2%); those parallel shares can sum above 100% and must not be read as one serialized MainActor stack. The main-thread finding is therefore a strong presentation hotspot, but still not proof of the upstream invalidating mutation.

## Boundary classification

```text
off-main Git/libgit2 work
  └─ raw filesChanged ingress (MainActor)
       ├─ WorkspaceSurfaceCoordinator
       ├─ WorkspaceCacheCoordinator no-op/changed consume
       └─ observation tracking / Repo Explorer list diff
```

`accepted` — persistent MainActor apply saturation is not established.

`lead` — Repo Explorer’s native list diff is likely amplified by a broad invalidation edge, but the causal upstream mutation and recurrence cadence remain unproven.

`unresolved` — whether the diff burst is caused by topology-array replacement, broad enrichment snapshot reads, command-presentation updates, SwiftUI identity churn, or another input.

The current-code beta provides a separate, stronger MainActor finding: its startup completion marker never arrived, and a five-second PID-bound sample put every main-thread interval in synchronous `ghostty_surface_new` → `fs.openDirAbsolute` during terminal activation. That is a startup blocking edge, not evidence of the steady production Repo Explorer cause. See [09-fresh-production-and-beta.md](09-fresh-production-and-beta.md).
