# Fresh production and beta discriminator

This page records the later stable samples and the current-code beta launch. It exists to keep a workload-dependent ranking separate from the earlier production window.

## Stable production: second sample

Runtime identity:

- `/Applications/AgentStudio.app`
- version `0.0.74`, build `115`
- PID `95537`
- sample: [/tmp/AgentStudio_2026-08-07_194425_Cqt5.sample.txt](/tmp/AgentStudio_2026-08-07_194425_Cqt5.sample.txt:1)
- 25 seconds, 14,737 sampled intervals; physical footprint about 1.9 GB

Active-stack ranking in this window:

| Lane | Intervals | Approximate one-core share | Boundary |
| --- | ---: | ---: | --- |
| Repo Explorer SwiftUI outline diff | 2,998 | 20.3% | MainActor/UI presentation |
| Ghostty renderer work | 2,838 | 19.3% | renderer/Metal worker |
| libgit2 status reads | 444 | 3.0% | off-main Git provider |
| OTLP dispatch | 249 | 1.7% | utility/export path |
| SQLite snapshot writers | 149 | 1.0% | background persistence |

The main thread was mostly waiting in AppKit, but 3,064 SwiftUI update cycles entered `OutlineListCoordinator.diffRows`; 2,922 of those recursively diffed rows and 2,868 traversed `ForEachList` ([sample lines 1993–2021](/tmp/AgentStudio_2026-08-07_194425_Cqt5.sample.txt:1993)). The concrete row identity was `RepoExplorerListEntry` ([sample lines 2024–2031](/tmp/AgentStudio_2026-08-07_194425_Cqt5.sample.txt:2024)). The 2,998 diff intervals over 25 seconds are approximately 120 diff passes per second, matching the display cadence on this machine. That makes the immediate defect shape “the sidebar list is being revisited at frame rate,” not merely “one expensive atom write.” The mutation or animation that keeps the list in the frame loop is still unidentified.

The renderer thread was mostly waiting in its kqueue loop, with the active slices entering `Renderer.updateFrame`, `Renderer.drawFrame`, `RenderPass.begin`, Metal command-buffer commit, and glyph work ([sample lines 7493–7506](/tmp/AgentStudio_2026-08-07_194425_Cqt5.sample.txt:7493)). This is real renderer activity, but the sample does not identify which terminal surface or whether the work is driven by a specific UI invalidation.

The earlier stable sample had a different active mix: Git status about 21.2%, Repo Explorer diff about 8.2%, and Ghostty renderer work about 5.2% ([earlier sample](/tmp/AgentStudio_2026-08-07_183104_Gsnw.sample.txt:14)). The two windows therefore establish a workload/state-dependent pressure set:

```text
Git-heavy window                 RepoExplorer/renderer-heavy window
  full libgit2 status              SwiftUI outline diff
  unchanged snapshot dedup         Ghostty Metal frame work
  low Git publication               Git still recurring, but smaller
```

The stable process was not a persistent MainActor stall in either window. MainActor/UI work is nevertheless a credible jank source in the second window because the expensive stack is the SwiftUI outline diff itself, not merely a tiny atom apply.

## Stable production: fresh high-CPU sample

The same stable PID was sampled again while Activity Monitor showed a high-CPU
state:

- PID `95537`, `/Applications/AgentStudio.app`, version `0.0.74` build `115`;
- 15 seconds, 8,359 continuously present main-thread intervals;
- artifact: [stable-highcpu-primary-95537.sample.txt](/tmp/AgentStudio_2026-08-07_stable-highcpu-primary-95537.sample.txt:1).

The main thread entered `OutlineListCoordinator.diffRows` 4,642 times (55.9%
of its continuously present samples), with 4,525 recursive row-diff intervals
and 4,396 `ForEachList` traversals ([main-thread stack](/tmp/AgentStudio_2026-08-07_stable-highcpu-primary-95537.sample.txt:45)). Concurrent worker
categories included 2,628 libgit2 blocking-read intervals (31.4%) and 2,611
active Ghostty renderer intervals (31.2%). The Git stack remained in
`LibGit2AgentStudioGitLocalClient.status` → `LibGit2StatusReader.status`, with
filesystem calls such as `lstat`, `open`, and `getdirentries` ([Git stack](/tmp/AgentStudio_2026-08-07_stable-highcpu-primary-95537.sample.txt:9168)). The renderer stack included glyph rebuild, `RenderPass.begin`, `updateFrame`, and `drawFrame` ([renderer stack](/tmp/AgentStudio_2026-08-07_stable-highcpu-primary-95537.sample.txt:7646)).

These are parallel one-core-equivalent stack-presence shares from `sample`, so
they can sum above 100%. The capture confirms three concurrent pressure lanes;
it does not prove that Git or Ghostty caused the SwiftUI diff, nor that the
diff itself blocked all MainActor work. The exact invalidation edge remains the
smallest missing correlation.

## Current stable telemetry rollup

Fresh VictoriaLogs window: `2026-08-07T23:30:00Z`–`2026-08-08T00:00:00Z` (30 minutes, generic marker `trace`). It contained 49,146 records, approximately 27.3 records/second. The generic stable marker is not PID-specific and was also used by the preceding stable process; the stable launcher state is `launch_failed` with an invalid trace name. Treat this as a current stable-channel rollup, not as a unique PID-bound workload receipt. The stack samples above are the PID-bound evidence.

Notable families:

- `ghostty.action.received`: 29,825
- `performance.terminal.accumulator_drain`: 3,167
- `performance.terminal.compact_apply`: 3,167
- `performance.git.logical_debt`: 2,753
- `performance.git.admission`: 1,244
- `performance.git.status`: 742
- `performance.git.snapshot_dedup`: 738
- `performance.git.tick`: 662
- `performance.git.status_unavailable`: 502
- `performance.git.backoff`: 286
- `performance.coordinator.write`: 134
- `performance.process.malloc_zone` and `performance.runtime_delivery.snapshot`: 969 each

Git status in this interval was 647 full scans and 35 pathspec scans. Successful status elapsed time averaged about 224 ms, p50 about 114 ms, p95 about 823 ms, and max about 1,397 ms. Unavailable results were 309 `read_capacity_exceeded`, 164 `timeout`, and 29 `read_already_in_flight`.

The highest-admission worktree hash was `acdb0ed8bf7bfb00` (69 admissions, 52 successful statuses, 17 unavailable); `809c4428faf0d071` followed (44 admissions, 17 successful statuses, 27 unavailable). These are safe deterministic hashes, not raw paths. This is the first fresh grouping evidence that a small set of worktrees contributes a disproportionate share of Git pressure.

Terminal accumulation remained proportional: 29,492 offered facts, 26,379 replacements (89.4% coalesced), 3,111 scheduled drains, 2 follow-up drains, and 3,113 MainActor tasks. Title-deadline drains were 2,914; immediate drains were 199. Queue age averaged about 877 ms (p50 942 ms, p95 945 ms), while compact apply averaged about 0.103 ms (p95 0.315 ms, max 3.355 ms).

EventBus pressure was low in this steady window: 962 snapshots, maximum active delivery debt 5, maximum total pending 5, six subscribers, no new live drops (cumulative remained 212), and no replay or retired-undelivered drops. The earlier startup peak of 987 remains a startup-only finding.

## Current-code beta launch

Runtime identity:

- local bundle: `/Users/shravansunder/.agentstudio-db/beta-observability/0.0.74-beta.3/AgentStudio Beta.app`
- version `0.0.74-beta.3`, build `2494`
- PID `87376`
- marker `beta-observability-1786145960-87306`
- state: [`tmp/beta-observability/latest-observability.env`](/Users/shravansunder/Documents/dev/project-dev/agent-studio.slowdonw/tmp/beta-observability/latest-observability.env:1)

The beta verifier correctly failed because no `app.did_finish_launching.succeeded` record was exported. This was not a Victoria query-window problem: through `2026-08-07T23:46:42Z`, the marker had `app.did_finish_launching.started = 1`, `app.did_finish_launching.succeeded = 0`, and no failure event. The last startup records were `terminal.startup.zmx_attach_prepared` and `terminal.startup.surface_create_started`.

A five-second sample of the still-running beta process shows the MainActor task blocked through terminal activation and synchronous Ghostty surface creation:

```text
TerminalActivationScheduler.activate
  → PreparedTerminalMountAdmissionPort.activate
  → WorkspaceSurfaceCoordinator.mountPreparedTerminalContent
  → createTopologyIndependentTerminalView
  → SurfaceManager.createSurface
  → Ghostty.SurfaceView.init
  → ghostty_surface_new
  → fs.openDirAbsolute / openat
```

All 3,738 sample intervals on the main thread followed this chain ([sample lines 23–48](/tmp/agentstudio-beta-startup-hang-87376.sample.txt:23)). Current source confirms the synchronous call is made while the `@MainActor` mount path creates `Ghostty.SurfaceView` ([WorkspaceSurfaceCoordinator+ViewLifecycle.swift:217](/Users/shravansunder/Documents/dev/project-dev/agent-studio.slowdonw/Sources/AgentStudio/App/Coordination/WorkspaceSurfaceCoordinator+ViewLifecycle.swift:217), [WorkspaceSurfaceCoordinator+ViewLifecycle.swift:255](/Users/shravansunder/Documents/dev/project-dev/agent-studio.slowdonw/Sources/AgentStudio/App/Coordination/WorkspaceSurfaceCoordinator+ViewLifecycle.swift:255), [SurfaceManager.swift:186](/Users/shravansunder/Documents/dev/project-dev/agent-studio.slowdonw/Sources/AgentStudio/Features/Terminal/Ghostty/SurfaceManager.swift:186), [GhosttySurfaceView.swift:390](/Users/shravansunder/Documents/dev/project-dev/agent-studio.slowdonw/Sources/AgentStudio/Features/Terminal/Ghostty/GhosttySurfaceView.swift:390)).

This is an accepted beta startup blocker and a direct MainActor boundary defect. It is not yet proof of the steady production CPU mix: the stable samples did not show this startup stack, and the beta launch never reached the post-presentation completion marker. It is also not an atom-DAG issue; the blocking edge is synchronous native terminal creation inside MainActor startup.

Beta telemetry was otherwise a negative control for ongoing pressure: 96.7% of records were once-per-second process/malloc and runtime-delivery samplers; EventBus debt/drops stayed zero; Git and atom families were absent; and sidebar projection was one short 4.383 ms startup burst over 121 repos. The beta run therefore did not exercise the production Git/Repo Explorer workload before it stalled.

## Disposable Git workload

The standard fixture workload was run through the repo-owned performance
verification path at the current source head
`3960f3b224cb439617b9fd8ded16e750933a94c5`:

- command: `AGENTSTUDIO_PERF_SAMPLE_DURING_WORKLOAD=1 mise run verify-git-refresh-performance-workload`
- marker: `perf-195024-35905`
- artifact summary: [/tmp/asperf/perf-195024-35905/summary.txt](/tmp/asperf/perf-195024-35905/summary.txt:1)
- fixture: 118 repositories, 163 worktrees, 14 active panes, 5 concurrent
  writers, 60-second busy interval
- app: script-owned debug PID 50013; cleanup stopped the app and all five
  writer PIDs, and the post-run debug-idle preflight passed
- sample: [/tmp/asperf/perf-195024-35905/main-sample.txt](/tmp/asperf/perf-195024-35905/main-sample.txt:1)

Fresh marker-scoped evidence was present for Git ticks (75 metric / 128 log
records), admissions (511 / 564), status (503 / 556), snapshot deduplication
(245 / 298), event publication (376 / 376), coordinator writes (539 / 539),
tab-bar refresh (15 / 15), sidebar projection (437 / 437), sidebar row index
(93 / 93), and command-bar items/filter (23 / 23 each). Git status elapsed
time in this fixture was mean 5.231 ms, p95 15.321 ms, and max 54.488 ms;
coordinator writes reached p95 51.312 ms and max 5,013.726 ms; sidebar
projection reached p95 8.413 ms; command-bar item resolution reached p95
147.5 ms.

The script exited 1 at its required-export gate because
`performance.topology.repo_and_worktree` produced zero Victoria metrics,
VictoriaLogs records, and JSONL records. This is an observability coverage
blocker, not evidence that topology work was absent. It prevents this run from
being called a complete performance proof. It does, however, provide a clean
workload receipt for the other lanes and does not show Git status-unavailable
events in the fixture.

## Disposition

- `accepted`: Repo Explorer list diff and Ghostty renderer are material current production hotspots in both the second stable sample and the fresh high-CPU sample.
- `accepted`: Git full status remains a recurring high-cost lane, but its rank varies by workload window.
- `accepted`: current beta has a startup MainActor block at synchronous Ghostty surface creation.
- `lead`: the Repo Explorer diff is amplified by broad invalidation/row identity churn; source evidence is strong, trigger correlation is still missing.
- `lead`: the disposable fixture shows coordinator and sidebar projection work under Git writers, but the run does not establish causality between Git events and the frame-rate Repo Explorer diff.
- `unresolved`: renderer-to-surface identity, exact SwiftUI invalidating mutation, and a fixture run with the topology metric family instrumented (and, separately, atom tags enabled).
