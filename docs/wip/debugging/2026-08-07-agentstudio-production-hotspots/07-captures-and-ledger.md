# Captures and evidence ledger

## Production baseline

Stable process: `/Applications/AgentStudio.app`, version `0.0.74`, build `115`, PID `95537` during the earlier production window. The process was bursty (0–31% samples) with approximately 117 threads. The unfiltered sample is a local-only artifact at `/tmp/AgentStudio_2026-08-07_183104_Gsnw.sample.txt`, line 14.

A later high-CPU capture sampled the same PID for 15 seconds: local-only artifact `/tmp/AgentStudio_2026-08-07_stable-highcpu-primary-95537.sample.txt`, line 1. It had 8,359 continuously present main-thread sample intervals, with 4,642 in `OutlineListCoordinator.diffRows`; the parallel worker categories included 2,628 libgit2 blocking-read intervals and 2,611 active Ghostty renderer intervals. `/usr/bin/sample` is wall-clock stack sampling, so these are stack-presence shares rather than cycle-accurate CPU attribution.

Accepted production evidence is summarized in [02-git-trigger-status.md](02-git-trigger-status.md), [03-terminal-ghostty.md](03-terminal-ghostty.md), and [04-mainactor-invalidation.md](04-mainactor-invalidation.md).

## Fresh debug capture

- HEAD: `3960f3b22`.
- PID: `85446`.
- Version: `0.0.1-debug+1ge0`, build `2494`.
- Debug code: `1ge0`.
- Marker: `debug-observability-1ge0-1786145377-78486`.
- State: local-only `tmp/debug-observability/latest-observability.env` (line 1).
- Verification: `mise run verify-debug-observability` passed.
- Stack sample: `/tmp/agentstudio-fresh-debug-capture-20260807-85446.sample.txt`.
- Result: idle CPU 0–4%; no Git or atom series; runtime debt/drops zero; sidebar projection max 0.43 ms.

This capture is a valid negative control, not a production workload reproduction.

## Beta status

The installed `/Applications/AgentStudio Beta.app` is `0.0.73-beta.10` and predates PR #251. A current-code local beta bundle was built and launched from this worktree:

- bundle local-only `/Users/shravansunder/.agentstudio-db/beta-observability/0.0.74-beta.3/AgentStudio Beta.app`;
- PID `87376`, marker `beta-observability-1786145960-87306`;
- verifier failed because `app.did_finish_launching.succeeded` was absent;
- five-second sample: local-only `/tmp/agentstudio-beta-startup-hang-87376.sample.txt` (line 23).

The beta process stalled before post-presentation startup at synchronous Ghostty surface creation on the MainActor. This is a current-beta startup blocker, not a replacement for the stable production workload proof. Full evidence is in [09-fresh-production-and-beta.md](09-fresh-production-and-beta.md).

## Disposable workload receipt

- command: `AGENTSTUDIO_PERF_SAMPLE_DURING_WORKLOAD=1 mise run verify-git-refresh-performance-workload`;
- source head: `3960f3b224cb439617b9fd8ded16e750933a94c5`;
- marker: `perf-195024-35905`;
- fixture: 118 repos / 163 worktrees / 14 panes / 5 writers / 60 seconds;
- artifact: local-only `/tmp/asperf/perf-195024-35905/summary.txt` (line 1);
- result: exit 1 only at the required metric-export gate; cleanup stopped the
  script-owned debug app and all writers, and idle preflight passed afterward;
- fresh families: Git tick/admission/status, snapshot dedup, event publication,
  coordinator write, tab-bar refresh, sidebar projection/row index, and
  command-bar items/filter;
- missing family: `performance.topology.repo_and_worktree` (zero Victoria
  metrics, VictoriaLogs records, and JSONL records).

This receipt is valid partial workload evidence. The missing family is an
instrumentation/proof gap, so it is not a green full-workload benchmark.

## Atom-tag diagnostic receipt

- command actually executed: `AGENTSTUDIO_TRACE_TAGS='performance,atoms,app.startup,terminal.startup' AGENTSTUDIO_SIDEBAR_IPC_CYCLES=100 mise run verify-sidebar-performance-workload`;
- marker: `sidebar-a054ad9d0e85b1739b5ab2b0`;
- artifact root: `/tmp/agentstudio-sidebar-performance/sidebar-performance-20260807195853-59560`;
- result: exit 130 after more than 11 minutes at the strict pre-IPC startup
  gate; no 100-cycle receipt or final summary was produced;
- blocker: missing `command_exercised` startup record for
  `sidebar-performance-proof`;
- fresh observations before stop: 11,233 atom reads, 101 atom mutations,
  sidebar request-build about 6.6 ms for 118 repos, MainActor apply about
  0.014–0.044 ms, and no topology lookup records;
- instrumentation warning: OTLP queue drops 7,583 + 5,873 + 3,473 at queue
  size 8,192 with `atoms` enabled; AppKit logged a reentrant NSTableView
  delegate warning;
- cleanup: script-owned PID 63666 was stopped and verified absent; stable and
  beta processes were not changed.

This is diagnostic evidence of atom-read shape and trace-volume perturbation,
not a completed sidebar performance proof.

## Ledger

| Finding | State | Primary evidence | Remaining gap |
| --- | --- | --- | --- |
| Git full-status churn is a recurring high-cost active CPU lane | accepted | two stable stack windows + marker-scoped fixture status/dedup rates | PID-bound production trigger grouping |
| Git result publication drives current UI CPU | refuted for trailing window | status ≈ dedup; Git events = 0 | raw filesystem ingress still needs pairing |
| Terminal title/apply is the steady bottleneck | refuted | terminal coalescing and sub-ms apply timing | per-tag trace cost |
| Startup EventBus pressure exists | accepted | one-second logs: debt 987, drops 212 | subscriber attribution |
| Persistent MainActor apply saturation | refuted | main thread mostly waiting; apply timings tiny | fresh active workload |
| Repo Explorer list diff is a material hotspot in active windows | accepted as presentation hotspot; cause lead | 425 intervals in one window, 2,998 in the later window, 4,642 in the fresh high-CPU sample | invalidation trigger |
| Broad atom DAG amplifies Repo Explorer work | lead | whole topology array + worktree facts snapshot reads | atom telemetry/runtime correlation |
| OTLP is primary CPU cause | refuted | ~1.6% sampled active dispatch | controlled on/off run |
| Current beta startup blocks MainActor in Ghostty surface creation | accepted | PID-bound beta sample; no launch-complete marker | determine why the native open blocks and whether it reproduces in release startup |
| Ghostty renderer/Metal is a current steady hotspot | accepted as window-specific | second stable sample ~19.3% active stack share | map renderer work to surface/frame invalidation |
| Disposable Git workload provides partial workload coverage | unresolved | fresh marker-scoped partial receipt | `performance.topology.repo_and_worktree` exported zero records |
| Atom-tag run provides diagnostic evidence only | unresolved | fresh marker-scoped diagnostic counts | startup `command_exercised` gate blocked before IPC; no final benchmark |
