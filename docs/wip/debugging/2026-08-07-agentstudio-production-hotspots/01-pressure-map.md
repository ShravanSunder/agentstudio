# Pressure map

```text
external source
  ├─ Ghostty actions ──► local accumulator ──► bounded drain ──► MainActor apply
  ├─ FSEvents/.git ────► FilesystemActor ─────► Git projector ──► libgit2 status
  ├─ timers/hints ─────► Git admission ───────► libgit2 status ─► optional Git event
  └─ runtime envelopes ► EventBus ────────────► coordinators ──► atoms/UI

background compute / queueing
  └──────────────────────────────────────────────► MainActor observation
                                                    ├─ Repo Explorer projection
                                                    ├─ tab/pane presentation
                                                    └─ SwiftUI/AppKit list/layout diff

all measured paths ──────────────────────────────► trace queue ─► OTLP/Victoria
```

## Current classification

| Surface | Current state | MainActor relationship | Atom/invalidation relationship | Confidence |
| --- | --- | --- | --- | --- |
| Git full status | Repeated scans of unchanged snapshots; largest active stack in one window and still recurrent in the next | Raw filesystem envelopes still enter coordinator; Git event publication was zero in the earlier trailing window | Trigger/admission policy reaches expensive work before dedup | accepted as recurring CPU pressure |
| Repo Explorer list | `OutlineListCoordinator.diffRows` was second in one window and ~20.3% in the later window | Native `List`/`ForEach` diffing is presentation work; source trigger is not yet paired | Broad topology array plus snapshot-shaped worktree facts are plausible broad invalidation edges | accepted as window-specific hotspot; atom edge remains lead |
| Ghostty renderer/Metal | ~19.3% active stack share in the later stable window | Renderer worker, not MainActor apply; frame/paint path is not surface-correlated | No atom conclusion | accepted as window-specific hotspot |
| Terminal/Ghostty | High source rate, 88.7% replacement/coalescing | Steady compact apply ~0.12 ms; startup admission delay only | Local accumulator isolates replaceable terminal facts | accepted as proportional |
| EventBus | Startup debt peak 987 and 212 cumulative drops; steady debt zero | Fanout ingress is MainActor-owned at coordinators | Subscriber identity is not present in aggregate telemetry | accepted startup pressure; owner unresolved |
| Rendering | Ghostty renderer stacks ranged from ~5.2% in the earlier sample to ~19.3% in the later one | CoreAnimation/WebKit paint and surface identity are not separately measured | No atom conclusion | accepted as window-specific hotspot |
| Command bar / coordinator | Disposable 118-repo fixture: command-bar item resolution p95 147.5 ms; coordinator write p95 51.3 ms, max 5,013.7 ms | Workload-only timing; no stable PID-bound causal join | Broad topology and composition inputs are possible contributors | workload lead, not production ranking |
| OTLP/diagnostics | ~32.6 logs/s in trailing production capture; dispatch ~1.6% sampled active stacks | Export is detached/utility work | Instrumentation itself creates queue and metric work | overhead supported, causality refuted |

## Main conclusion

The observed production CPU is a mixture of background Git computation and a separate Repo Explorer presentation burst. The available evidence does not support a single “MainActor blocked” explanation. The atom graph is a candidate amplifier for the Repo Explorer branch, not a proven explanation for the Git CPU.
