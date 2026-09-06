# Memory Pressure Track — Requirements

Authorized needs, outcomes, priorities, and limits for stopping off-screen terminal renderer work
and releasing closed terminals in Agent Studio. Observable obligations live in the separate
[specification.md](specification.md); structural realization lives in
[program-design.md](program-design.md).

## Affected people

| Class | Relationship |
| --- | --- |
| Terminal user (the owner) | Runs 30–50 long-lived agent terminals across 8+ tabs, drawers, and arrangements for days. Needs sessions to keep running off-screen and to reappear instantly with current content. Direct user and decision authority. |
| Machine operator (same person) | Bears machine-wide memory, compressor, swap, and compositor cost. Two incidents (2026-08-27, 2026-08-28) ended in forced reboots. |
| Operators reading telemetry | Need run-bound, scrubbed evidence that separates intentionally retained renderers from leaked ones without a forensic investigation. |
| Implementing and reviewing agents | Consume this contract; hold no product authority. |

## Authorized needs

Authority for every row is the owner packet delivered by the team lead on 2026-09-05
("memory-pressure track") together with the owner decisions recorded in the 2026-08-29 renderer
lifecycle packet that remain applicable (Ghostty pin kept, 300 s undo grace kept, app-side only,
no new atoms/stores/buses, isolated proof identity, fail-open telemetry). Evidence rows come from
the live investigation in
[debug-investigation.md](../../../tmp/debug-workflows/2026-09-05-agent-studio-fix-memory-pressure-memory-pressure/debug-investigation.md)
and the [salvage assessment](../../wip/2026-09-05-memory-pressure-salvage-assessment.md).

| ID | Need and outcome | Why it matters | Evidence | Authority | Priority |
| --- | --- | --- | --- | --- | --- |
| U1 | A terminal pane that is not part of what the user can currently see must not draw frames or commit them to the compositor. | Today every one of 29 surfaces is Ghostty-visible regardless of tab or window state; each output wakeup draws and commits an IOSurface for a layer nobody sees, and WindowServer maps one buffer per hidden surface. | Live sample and vmmap of production 0.0.93; `SurfaceManager`, `PaneTabViewController`, `WindowLifecycleAtom` readers | authorized | P0 |
| U2 | Leaving the visible projection must never stop, restart, or disconnect the terminal session or lose its content; returning must show current content without a restart. | Off-screen continuity is the whole reason surfaces stay alive; agents run unattended in inactive tabs. | Existing product behavior; owner statement 2026-08-29 | authorized | P0 |
| U3 | A closed terminal must actually be freed after the existing 300 s undo grace, and an undo inside that grace must restore the exact same surface. | Current close leaves the renderer reachable through an AppKit view cycle; nothing can ever free it. Each leaked terminal costs ~58 MB, four threads, and a PTY reader forever. | Source trace on origin/main (`PaneHostView`, `ViewRegistry`, `WorkspaceSurfaceCoordinator+ViewLifecycle`) | authorized | P0 |
| U4 | Renderer hide/show transitions must not create avoidable work at fleet scale. | Pinned Ghostty queues a render on every occlusion call even when the value is unchanged; a naive "re-send to everything" reconciliation would wake 29 renderers per tab switch. | Ghostty v1.3.1 `Surface.zig:3248–3257` | authorized | P1 |
| U5 | Within one process run, an operator must be able to read how many renderers exist, how many the app intends to keep (active, hidden, pending undo), and how many have been released and freed. | Creation was counted; destruction and deallocation never were, so the incidents could not be diagnosed. | Telemetry inventory in the debug artifact | authorized | P1 |
| U6 | The correction stays app-side, keeps the Ghostty pin, adds no atom/store/bus, and proves itself on an isolated debug identity without touching production. | Owner boundary; a vendor bump is a separate decision. | Owner packets 2026-08-29 and 2026-09-05 | authorized | P0 |

Priority assigner: product owner. P0 protects machine availability and session continuity;
P1 makes the fix scale and stay observable.

## Confirmed goal boundary

- **Goal.** Off-screen terminal surfaces stop drawing and committing; closed surfaces are freed
  after undo expiry; the renderer population is observable. Success is measured on the debug
  bundle with the fleet workload the owner actually runs, not by a green unit suite alone.
- **Foundation to reuse.** `SurfaceManager` lifecycle ownership, `WindowLifecycleAtom`
  presentation facts, `StoreVisibilityTierResolver` (already the authority for what restore builds),
  `ViewRegistry`, and the existing performance trace recorder / OTLP pipeline.
- **Permitted change surface.** `Sources/AgentStudio` (Features/Terminal, App coordination and
  hosting, Infrastructure/Diagnostics), tests, and one proof script under `scripts/`.
- **Protected.** The Ghostty pin `332b2aefc6e72d363aa93ab6ecfc86eeeeb5ed28`; the 300 s undo grace
  and ten-entry workspace undo capacity; PTY/zmx continuity; canonical pane, tab, drawer,
  arrangement, zoom, and minimized state; fail-open behavior when the collector is absent.
- **Acceptable complexity.** The smallest correction through existing owners. A new atom, store,
  bus, cache type, persistence contract, vendor change, or WindowServer mitigation reopens scope
  and needs a new owner decision.

## Non-goals

- Reducing the bounded steady-state graphics residency of live surfaces (~58 MB each at the pin).
  That requires a Ghostty pin bump to include upstream `683d8db`; recommended as a separate PR.
- Proving that Agent Studio alone caused the 2026-08-27/28 incidents.
- Changing the repair/recreate path's use of the close-undo window (bounded to 300 s once U3
  holds; follow-up).
- Adding a display-sleep channel. Window occlusion is assumed to cover sleeping displays; the
  assumption is observed, not engineered around, in this track.
- Multi-window renderer routing.
- Changing scrollback, shell, PTY, or zmx semantics.

## Unresolved hypotheses

- Whether the 131 GB events were WindowServer-side accumulation, app-side IOSurface accumulation,
  or unrelated co-pressure. U1 removes the app's hidden commit traffic, which is also the
  cheapest experiment; the passive watcher records app and WindowServer slopes.
- Whether `NSWindow.occlusionState` reports non-visible while the display sleeps on this machine.
- The owner of the malloc oscillation (209→411→267 MB) in production 0.0.93.
