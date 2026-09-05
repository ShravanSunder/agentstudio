# Memory Pressure Track — Specification

The observable contract for the needs in [requirements.md](requirements.md). It says what must be
true at the boundaries a user, an operator, or a test can see. It does not choose components,
observers, or call paths; those live in [program-design.md](program-design.md).

## The problem as it is observable today

```text
Terminal-user journey                                                     U1 U2 U3 U4 U5
1  Keep 30 agent terminals running across 8 tabs for days.
   Pain: every surface stays Ghostty-visible; hidden tabs draw and
   commit frames on every output wakeup (renderer.Metal addGlyph /
   rebuildRow hot while idle; 25 WindowServer-shared buffers).          ●        ●
2  Switch tabs, collapse drawers, zoom, minimize, occlude the window.
   Pain: none of these reach the renderer; the only path that tries
   (detach for hide/close/move) looks the surface up after removing
   it and delivers nothing.                                             ●  ●     ●
3  Come back to a tab. Expectation: current content, no restart.           ●
4  Close terminals over a working day.
   Pain: the renderer stays reachable through the pane host view cycle;
   undo expiry drops the manager's reference and nothing else lets go.
   ~58 MB + 4 threads per close, forever.                                    ●
5  Ask "how many renderers exist vs how many should" after a bad night.
   Pain: creation is counted; release and free are not.                            ●
```

```text
Context (system opaque)

  Terminal user ──── tabs / drawers / zoom / minimize / window state ───┐
  Machine operator ── memory, compressor, swap, WindowServer cost ──────┤
  Operator telemetry ── VictoriaLogs (scrubbed, run-bound) ◄────────────┤
                                                                        ▼
                                                    ┌──────────────────────────┐
  libghostty v1.3.1 (pinned, protected) ◄── set_occlusion / set_focus /│      Agent Studio        │
                                              surface_free ──────────── │  (one workspace window)  │
  macOS WindowServer ◄── Core Animation commits of IOSurface contents ──│                          │
  zmx / PTY (protected, must continue) ─────────────────────────────────└──────────────────────────┘

  Negative space: no vendor change, no display-sleep channel, no second window,
  no change to undo grace or capacity, no WindowServer mitigation.
```

## Terms

- **Effective visibility.** A pane is effectively visible when its owning window is visible, not
  miniaturized, and not occluded, and the pane is in the visible projection of the active tab
  (active arrangement, not minimized, zoom source if zoomed, drawer child only when its drawer is
  expanded and it is in the drawer layout and not minimized) with active residency.
- **Renderer off / on.** Whether libghostty has last been told the surface is occluded (off) or
  visible (on).
- **Manager-owned populations.** `active` (attached to a displayed host), `hidden` (alive,
  detached), `close_undo` (closed, restorable for 300 s).
- **Released / freed.** Released: the app has given up ownership on purpose (undo expiry,
  explicit destroy, replacement). Freed: `ghostty_surface_free` has run for that surface.

## Outcomes

- **O1** Off-screen surfaces draw nothing and commit nothing while their sessions continue. (U1, U2)
- **O2** Every projection or window transition delivers renderer off/on exactly to the surfaces
  whose effective visibility changed. (U1, U4)
- **O3** Closed surfaces are freed after the undo grace; immediate undo restores the exact
  surface. (U3)
- **O4** Renderer populations are observable per run with a conservation invariant. (U5)

## Normative requirements

### Renderer work follows effective visibility

- **R1** When a pane's effective visibility becomes false, the system MUST deliver renderer off
  to that pane's surface within one MainActor hop of the state change that made it false, and
  MUST NOT terminate, suspend, or disconnect the terminal session, PTY, or zmx attachment. Work
  already in flight at that instant — a frame the renderer thread began before it consumes the
  off message, or a layer-contents commit already queued on the main thread — MAY complete; after
  the renderer consumes the message no new frame MAY start. (U1, U2 → O1)
- **R2** When a pane's effective visibility becomes true, the system MUST deliver renderer on to
  its surface so the next frame reflects the terminal's current content, without recreating the
  surface or restarting the session. (U2 → O1)
- **R3** The following MUST each make a pane not effectively visible: inactive tab; inactive
  arrangement; minimized pane; zoomed tab where the pane is neither the zoom source nor a
  displayed child of the zoom source's expanded drawer; collapsed drawer for a drawer child;
  drawer child outside the drawer layout or drawer-minimized; drawer child whose parent pane is
  minimized; residency other than active; no active tab; owning window hidden, miniaturized, or
  occluded. These are conjunctive: one true dimension never overrides a false one. The zoom
  presentation keeps the source pane's expanded drawer on screen, so its displayed children
  remain effectively visible. (U1, U2 → O1)
- **R4** Detaching a surface for hide, close, or move MUST deliver renderer off to the exact
  surface being detached. A detach that cannot deliver (surface unknown) MUST be observable as a
  skipped delivery, not silently succeed. (U1 → O1)
- **R5** A newly created surface MUST be renderer-off from acceptance until it is attached. A
  surface attached into a pane that is not effectively visible MUST be renderer-off within one
  MainActor hop of the attach; a bounded on-then-off at attach is permitted so that a failure to
  reconcile can only leave a surface drawing, never blank. (U1, U2 → O1)
- **R6** Reconciling a transition MUST deliver renderer off/on only to surfaces whose effective
  visibility differs from the last delivered state; a reconciliation with no changes MUST deliver
  nothing, so native renderer work scales with changed surfaces. The reconciliation itself MAY
  evaluate every attached surface, but it MUST read only structural projection facts (tab,
  arrangement, residency, drawer, minimize, zoom, window facts) and never repository enrichment,
  and its MainActor duration MUST be recorded per reconciliation and stay under the repository's
  1 ms MainActor budget with 30 attached surfaces on the debug bundle. (U4 → O2)
- **R7** Focus on MUST reach a surface only while it is effectively visible and is its window's
  first responder; every focus-on writer is subject to that gate. Focus off is always permitted.
  When a surface becomes effectively visible and is the first responder, focus on MUST be
  delivered; when it becomes not effectively visible, focus off MUST be delivered. (U1 → O1)

### Closed surfaces are freed

- **R8** Closing a pane or tab MUST place its surface in `close_undo` for exactly the existing
  300 s grace with the existing capacity and ordering, whether that surface is currently attached
  or already detached (minimized, arrangement-hidden, drawer-collapsed). Temporary hiding (R3
  transitions) MUST NOT enter `close_undo` or restart its timer. (U3 → O3)
- **R9** An undo within the grace MUST reattach the exact same surface (same libghostty handle,
  same session) on every undo path: pane close undo, tab close undo, drawer-child undo, and
  floating terminals without repository enrichment. Fresh creation is permitted only when no
  retained surface for that pane exists. (U3 → O3)
- **R10** When a surface leaves `close_undo` by expiry or is explicitly destroyed, the app MUST
  hold no reference that prevents its `Ghostty.SurfaceView` from deinitializing, and
  `ghostty_surface_free` MUST run for it within the same run. Permanent host replacement
  (repair/recreate, fresh-surface replacement) MUST immediately release the retired host's
  references to the old surface; the old surface's manager retention is unchanged by this track
  (repair still routes through the existing 300 s close-undo window) and MUST end in
  `ghostty_surface_free` at that expiry. The obligation is on the surface, its renderer/io
  threads, its PTY child, and its `TerminalRuntime`; the small `PaneHostView` object MAY outlive
  them while AppKit or SwiftUI caches reference it. A logical "destroyed" log line does not
  satisfy this. (U3 → O3)
- **R11** Permanent release MUST be instance-exact: retiring an old host or surface for a pane
  MUST NOT unmount, free, or occlude a replacement already installed for the same pane
  identity. (U2, U3 → O3)

### Operational observability

- **R12** Within a run, telemetry MUST expose: `created` (incremented once per surface accepted
  into manager ownership), current `active`, `hidden`, `close_undo`, `released` total, `freed`
  total. From these, `live = created − freed`, `manager_owned = active + hidden + close_undo`,
  `orphan = live − manager_owned`. A negative `orphan` is a telemetry defect and MUST be reported,
  not clamped. (U5 → O4)
- **R13** After a permanent release, its surface MUST count as an orphan candidate until `freed`
  increments; a candidate that persists past a bounded drain (10 s) or grows across close/expiry
  cycles is a lifecycle failure. (U3, U5 → O4)
- **R14** Exported telemetry MUST carry only counts, controlled action names, and scrubbed
  run/process identity — no pane IDs, surface IDs, paths, titles, or terminal content. Collector
  absence MUST be fail-open for the terminal. (U5, U6)

### Boundary

- **R15** The Ghostty pin MUST remain `332b2aef`; no vendor, atom, store, bus, cache type,
  persistence, multi-window, or display-sleep machinery MAY be added. Runtime proof MUST run on
  an isolated debug identity. (U6)

## Observable contracts

### Terminal user surface

| Situation | Must be observable | Must not happen |
| --- | --- | --- |
| Switch away from a tab with N terminals | Those N surfaces receive renderer off once within one MainActor hop; their shells keep running; output continues to accumulate | Any of them starting a new frame after the renderer consumed the off message |
| Zoom a pane whose drawer is expanded | The zoom source and its displayed drawer children stay on; every other pane in the tab goes off | The drawer children going off while still on screen |
| Close a minimized or arrangement-hidden pane, then wait 300 s | Its surface enters undo, then frees like an attached one | The surface staying alive in the hidden population |
| Undo a tab close within 300 s | Every terminal in the tab reappears with its exact surface and session | Fresh surfaces created while retained ones sit in undo |
| Switch back | Surfaces receive renderer on once; first frame shows content current through the hidden interval | Restart, blank frame that persists, session reconnect |
| Collapse / expand drawer, zoom / unzoom, minimize / expand pane | Only the affected panes' surfaces change renderer state | Unaffected panes re-delivered |
| Window occluded, miniaturized, or hidden; then restored | Every displayed surface goes off, then on | Per-surface work when the window state is unchanged |
| Close pane, undo within 300 s | Same terminal content and session reappear | New surface, lost scrollback |
| Close pane, wait 300 s | Renderer thread, IOSurface set, and PTY reader for that surface are gone | Any remaining reference to the surface view |
| Collector down | Terminal behavior unchanged | Blocking, errors, missing frames |

### Operator telemetry surface

One low-volume lifecycle record per transition (created, attached, hidden, closed_for_undo,
undo_restored, released, freed) carrying the current populations from R12 plus the scrubbed
run/PID identity already used by the performance recorder. Population counts in a `released`
record MUST already exclude the released surface, and that record MUST be emitted before the
app drops its last reference, so a `freed` record can never precede its `released` record and
`orphan` is never negative under correct operation. Renderer-visibility deliveries are counted
per reconciliation (`applied`, `equal_suppressed`, `missing`, `elapsed_ms`) not per surface.

### Pinned Ghostty boundary (external, fixed)

`set_occlusion(false)` stops frame draws and Core Animation commits but keeps the swap chain
allocated; `set_occlusion` has no equality guard and queues a render per call; `set_focus(true)`
starts the display link regardless of visibility; `ghostty_surface_free` is the only release.
These facts bound R1, R6, R7, and R10 and are not changed by this track.

## Failure and partial behavior

- If a surface's native handle is nil (creation failed, already freed), delivery is skipped and
  counted as `missing`; the manager state still transitions.
- If reconciliation runs before the window is registered or before any tab is active, every
  attached surface is treated as not effectively visible (R3: no active tab).
- If an undo arrives after expiry, the pane is restored with a new surface and the existing
  session reconnect; the expired surface is not represented as reused (existing behavior kept).
- If `orphan` is non-zero after the drain, the telemetry says so; the app does not attempt to
  force-free anything.

## Cross-cutting obligations

- **Privacy.** R14. Existing scrub rules of the OTLP projection apply unchanged.
- **Reliability.** No transition may leave a displayed surface renderer-off (R2); no temporary
  transition may unmount content (U2).
- **Performance.** R6; a tab switch in a 30-surface workspace delivers to at most the surfaces
  in the two tabs involved.
- **Compatibility.** Undo grace, capacity, and ordering unchanged (R8). No public API change.
- **Security, accessibility.** Not applicable; no new input surface or UI.

## Requirement coverage and proof

| U | P | O | R | Contract | Proof modality (V) |
| --- | --- | --- | --- | --- | --- |
| U1 | hidden surfaces draw and commit | O1 | R1, R3, R4, R5, R7 | user surface rows 1, 2, 4; Ghostty boundary | V1 automated behavior through a recording delivery seam: create → attach (off until visible) → tab switch delivers off once → switch back delivers on once; per-dimension resolver cases incl. zoom source drawer children visible, drawer child of minimized parent hidden; focus-on refused while off; V2 runtime `sample` of the debug app after a quiescence interval: renderer threads for hidden tabs show no `updateFrame`→`drawFrame` past the visibility gate and no `IOSurfaceLayer.setSurface` dispatch (a `drawFrame` frame alone is not evidence, it contains the early return) |
| U2 | continuity | O1 | R1, R2, R11 | rows 2, 5 | V3 automated: session/PTY handles unchanged across off→on; V4 manual on debug app: hidden tab keeps producing output, reveal shows it |
| U3 | closed surfaces never free | O3 | R8–R11 | rows 5–8 | V5 automated red-first: close → unregister → drop references → weak host and content nil; close of a hidden surface enters undo; tab-close undo reuses the exact surface; expiry → `freed` increments; V6 runtime: close 20 (some minimized) → 300 s → renderer thread count and IOSurface regions return to baseline (external `sample`/`vmmap`) |
| U4 | fleet-wide redelivery | O2 | R6 | rows 3, 4 | V7 automated: equal reconciliation delivers nothing; transition delivers only changed surfaces; manager-local health/CWD writes trigger zero reconciliations; runtime: `elapsed_ms` per reconciliation under 1 ms at 30 attached surfaces on the debug bundle |
| U5 | no release/free evidence | O4 | R12–R14 | telemetry surface | V8 automated invariant tests incl. negative-orphan reporting; V9 log/trace observation in VictoriaLogs scoped by proof marker |
| U6 | scope | — | R15 | — | V10 diff inspection: pin unchanged, no new atom/store/bus |

Gaps: display-sleep coverage (A1) is observed, not proven, by one manual sleep/wake on the debug
app; if `occlusionState` stays visible during display sleep, that is reported to the owner and
does not block this track.
