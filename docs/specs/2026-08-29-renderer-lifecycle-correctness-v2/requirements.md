# Renderer Lifecycle Correctness v2 — Requirements

This document is the authoritative Requirements identity for renderer-lifecycle
correctness. It records authorized needs, priorities, boundaries, and unresolved
hypotheses. Observable obligations are defined separately in
[specification.md](specification.md).

## Affected people

| Class | Relationship to the problem |
| --- | --- |
| Terminal user | Runs long-lived agent terminals across tabs, arrangements, drawers, background panes, and zoom presentations. Needs those sessions to continue without off-screen render work or disappearing content. |
| Machine operator | Bears machine-wide memory, graphics, compressor, and availability costs and needs production-safe evidence that distinguishes retained surfaces from released surfaces. |
| Implementing and reviewing developers | Consume the contract and its proof obligations. They are not product decision authorities. |

## Authorized needs

All rows below are authorized by the owner packet dated 2026-08-29. Prior
artifacts and incident investigations are evidence only; they do not authorize
new product meaning.

| ID | Need and outcome | Why it matters | Evidence class | Authority state | Priority |
| --- | --- | --- | --- | --- | --- |
| U1 | A terminal pane outside the current visible projection must perform no renderer drawing or compositor commit work. | Production Agent Studio and WindowServer were observed at roughly 120–131 GB within a day and the machine froze. App-side lifecycle defects are source-proven, although their causal share in those incidents is not. | Owner incident observation; clean-source lifecycle trace; pinned Ghostty source | authorized | P0 |
| U2 | Temporary loss of projection must preserve the live terminal process/session, PTY-zmx continuity, current terminal content, and canonical pane membership. | Users deliberately keep work running across inactive tabs, collapsed drawers, arrangements, background panes, minimized panes, and zoom transitions. Renderer visibility is not session lifetime. | Owner decision; current product model | authorized | P0 |
| U3 | Returning a retained pane to the visible projection must show its current content without restarting its durable session, and no temporary transition may make a pane or drawer child go missing. | Instant, lossless return is the reason retained background panes exist. | Owner decision; drawer-host interaction evidence | authorized | P0 |
| U4 | User close retains the existing exact 300-second surface-undo grace and existing undo-capacity semantics. Immediate undo must preserve the retained renderer and session; undo after renderer expiry must still restore the pane when workspace undo remains available. | Accidental-close recovery is an existing user promise and is distinct from temporary hiding and permanent replacement. | Owner decision; clean-source undo paths | authorized | P0 |
| U5 | Permanent close, expiry, and replacement must release the exact retired renderer/host instance without releasing an immediate undo or newly installed replacement. Repair/recreate must not consume close-undo retention or accumulate replaced renderers. | Manager bookkeeping is not deallocation. Repeated repair currently routes old surfaces through the close-undo window and can retain every replaced renderer for 300 seconds. | Owner decision; clean-source repair and ownership trace | authorized | P0 |
| U6 | Reconciliation of an unchanged effective-visibility result must not create avoidable native renderer work at fleet scale. | At the pinned revision each occlusion callback queues renderer work even when the delivered value is unchanged. | Owner decision; exact pinned Ghostty source | authorized | P1 |
| U7 | Operators need scrubbed, run-bound evidence that distinguishes manager-owned active, hidden, and close-undo populations from permanent ownership release and actual deallocation/free. | Creation counts and logical destruction logs cannot identify retained or orphaned renderers. | Owner decision; incident telemetry gap | authorized | P1 |
| U8 | The correction and its proof must remain app-side, isolated, and minimal: keep the Ghostty pin, avoid production mutation, and reuse current owners unless a new owner decision expands scope. | The goal is to remove source-proven Agent Studio lifecycle errors and measure residual behavior, not silently redesign the product or claim an Apple/Ghostty cure. | Owner decision | authorized | P0 |

Priority assigner for every row: product owner. P0 protects user data/session
continuity or machine availability; P1 makes the contract scalable and
operable.

## Confirmed goal boundary

The goal is to eliminate source-proven Agent Studio renderer-lifecycle errors
and make retained versus deallocated renderer populations observable. Success
does not prove that this change explains or fixes every macOS, WindowServer, or
Ghostty resource-growth mechanism.

The allowed capability surface is the existing Agent Studio renderer,
pane-hosting, workspace-projection, window-lifecycle, and diagnostics behavior
for one workspace window. The implementation may change Agent Studio source and
tests only. It must preserve:

- the Ghostty pin at `332b2aefc6e72d363aa93ab6ecfc86eeeeb5ed28`;
- terminal process/session and PTY-zmx continuity while projection visibility
  changes;
- the exact 300-second close-undo grace and existing undo-capacity semantics;
- canonical pane, drawer, arrangement, background, minimized, and zoom state;
- normal fail-open app operation when telemetry is unavailable.

The acceptable complexity is the smallest correction through existing owners.
A new state machine, compatibility shim, cache, vendor change, atom, store, bus,
persistence contract, multi-window topology, or WindowServer mitigation requires
a separate owner decision after evidence shows the current boundary is
insufficient.

Outcome-level evidence must include scoped automated behavior, actual
deinitialization/free evidence, isolated debug or beta runtime proof, scrubbed
run/PID-bound telemetry, and a controlled fleet soak. Exact Metal
command-buffer or commit tracing is optional stronger attribution evidence; its
absence or failure does not block implementation, PR readiness, or app-side
lifecycle completion. No investigation or proof may mutate production state.

## Non-goals

- Proving that Agent Studio alone caused either severe memory incident.
- Eliminating the finite, bounded residency of intentionally live surfaces.
- Releasing pinned-Ghostty resources that the pinned renderer intentionally
  retains while its surface remains alive.
- Changing terminal scrollback, output, shell, PTY, or zmx semantics.
- Changing close-undo duration, capacity, order, or availability policy.
- Adding a direct display-sleep channel before real sleep/wake evidence
  falsifies the current window-occlusion assumption and the owner expands scope.
- Adding multi-window renderer routing; one workspace window is the current
  product boundary.
- Adding vendor, atom, store, bus, persistence, schema, cache, or compatibility
  machinery merely to satisfy this work.
- Mitigating or instrumenting WindowServer internals.
- Repairing or reconfiguring Xcode, Metal tooling, or the host system to obtain
  optional command-buffer attribution evidence.

## Governing-source inventory

| Identity | Class | Current applicability |
| --- | --- | --- |
| Owner renderer-lifecycle v2 packet, 2026-08-29 | normative | Authorizes U1–U8, the goal boundary, protected behavior, scenarios, and scope limits. |
| Agent Studio source at `246c9a81c256ded9431620ae9c8cd99f4a27622d` | observational | Establishes current creation, attach/detach, undo, repair, host ownership, projection, window-fact, and telemetry behavior. It does not authorize desired behavior. |
| Ghostty source at `332b2aefc6e72d363aa93ab6ecfc86eeeeb5ed28` | normative constraint plus observational platform evidence | Fixes the vendor compatibility boundary. `Surface.occlusionCallback` queues visibility and render work without source-side equality suppression; `Thread.drawFrame` returns while invisible; focus can restart display-link/cursor/timer traffic, but that alone does not prove hidden frame commits. |
| User-observed 120–131 GB incidents | observational | Establish severity and the machine-level outcome, not complete process or allocation attribution. |
| Legacy renderer-lifecycle artifacts and errata | advisory/observational | Supply hypotheses, source pointers, disproved claims, and regression evidence. They are not reused as Requirements or Specification authority. |

## Unresolved hypotheses

- The exact allocation/retention path responsible for each historical incident
  remains unproven.
- Window occlusion is assumed to represent real display sleep for this one-window
  product boundary. A real sleep/wake cycle must attempt to falsify it before
  display-sleep coverage is claimed; falsification narrows that claim without
  blocking fixes for separately proven projection and window paths.
- Residual macOS or WindowServer growth may remain after all app-side lifecycle
  obligations pass.
- Without optional Metal command-buffer tracing, app-side proof does not
  directly attribute a residual graphics anomaly to an exact commit boundary.
- Pinned Ghostty may continue bounded per-live-surface residency while invisible;
  bounded residency is not itself a leak.
