# Surface coverage inventory

This inventory prevents the Git/Repo Explorer findings from being mistaken for a complete CPU accounting. The source-side performance recorder defines these measurable families in [AgentStudioPerformanceTraceRecorder.swift](../../../../Sources/AgentStudio/Infrastructure/Diagnostics/AgentStudioPerformanceTraceRecorder.swift:116).

| Surface family | Instrumented signals | Current evidence | Status |
| --- | --- | --- | --- |
| Git/filesystem | admission, tick, status, unavailable, backoff, dedup, event-posted, logical debt, quarantine | Production rates and stack sample | accepted hotspot |
| Terminal/Ghostty | accumulator drain, compact apply, geometry, mount, surface size, force sync | Production rates and apply timings | proportional; source volume high |
| Repo Explorer/sidebar | projection, row index, command presentation, topology lookup | Native list diff stack + marker-scoped fixture timings; topology lookup family was absent in the fixture | secondary lead / proof gap |
| Pane/tab shell | pane-tab layout, pane restore, restore-visible, tab-bar refresh, pane actions | elapsed maxima; no frame-paint attribution | measured but not ranked |
| Runtime delivery | EventBus snapshot, live debt, drops | Startup peak and steady zero | startup-only pressure |
| Atom graph | atom read, mutation, derived | Absent in stable capture; debug idle also absent | proof gap |
| Command bar | filter, items | No current hotspot evidence | unmeasured |
| Bridge | Git read scheduler, worktree product construction | No current Bridge series in production capture | unmeasured |
| Management/AppKit | AppKit state and command | No ranked active stack | unmeasured |
| Process/diagnostics | malloc zone, trace identity | Exported regularly; no CPU attribution | overhead/health only |
| Rendering | no dedicated frame/paint signal | second stable sample showed active Ghostty renderer/Metal work at ~19.3%; fresh high-CPU sample showed 2,611 active renderer intervals (~31.2% of one-core-equivalent samples); WebKit/CoreAnimation surface identity is still missing | accepted as window-specific hotspot |

## Missing correlations

The current recorder does not expose a single causality identifier connecting:

- one FSEvent batch to one Git admission;
- one Git snapshot to one Repo Explorer request;
- one atom mutation to the observation callback that rebuilt a view;
- one SwiftUI list diff to its invalidating input;
- one OTLP record to exporter CPU or queue shedding.

The missing renderer join is now material: the stack sample identifies `Renderer.updateFrame`, `Renderer.drawFrame`, `RenderPass.begin`, and Metal command-buffer work, but no safe surface identifier connects that work to a terminal or invalidating input.

Those are instrumentation/proof gaps, not grounds for inventing a root cause. The collection marks them explicitly so a later fix or telemetry change can target the smallest missing edge.

The disposable fixture makes one gap concrete: the script required
`performance.topology.repo_and_worktree`, but the fresh marker produced zero
Victoria metrics, VictoriaLogs records, and JSONL records for that family while
all other required sidebar/coordinator/Git families were present. This likely
means the workload did not exercise the lookup call (or the call was not
admitted), but the current receipt cannot distinguish those cases.
