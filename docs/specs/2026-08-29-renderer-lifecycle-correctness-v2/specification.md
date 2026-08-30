# Renderer Lifecycle Correctness v2 — Specification

This document is the authoritative observable contract for the needs in
[requirements.md](requirements.md). It defines what must be true without
choosing internal components, callback wiring, observer mechanics, storage, or
host methods.

## The observable problem and intended outcome

**P1 — Renderer lifetime, render authority, and user-close retention are not
consistently separated.** Current Agent Studio source admits several independent
lifecycle failures:

- a newly created surface enters manager-owned hidden state without first being
  reconciled to effective projection visibility;
- attach asserts native visibility immediately, before the pane's complete
  projection and owning-window visibility are known;
- detach and undo requeue remove a surface from their lookup collections before
  attempting renderer-off delivery, so delivery can be skipped;
- window presentation facts and the complete pane projection exist, but terminal
  render authority is not reconciled across every tab, arrangement, drawer,
  background, minimize, zoom, nil-active-tab, app, and window transition;
- repair/recreate tears down through the user-close path, placing each replaced
  surface into the 300-second close-undo population before creating another;
- logical manager release and registry unregistration do not prove that the
  exact host and `Ghostty.SurfaceView` deinitialized or that
  `ghostty_surface_free` ran.

The source-proven defects justify correction. They do not prove that these
paths caused all historical WindowServer or system-memory growth.

```text
Terminal-user journey                                             U1 U2 U3 U4 U5

1  Open long-lived agent terminals across tabs, arrangements,
   drawers, background panes, and zoom presentations.
   Observed pain: off-screen lifetime and renderer work are not
   consistently separated; severe machine incidents followed.

2  Move among projections or leave the app/window/display inactive.
   Desired difference: sessions continue, canonical panes remain intact,
   and only the current visible projection may draw or commit.

3  Return to a retained pane.
   Desired difference: current content appears without session restart or
   a missing pane/drawer child.

4  Close, undo, expire, or repair a pane.
   Desired difference: close keeps its exact grace; permanent replacement
   releases only the exact retired renderer; repair never borrows close undo.
```

```text
Observable context                                               U1 U7 U8

 terminal user  ── pane/tab/drawer/arrangement/zoom/window ──┐
 machine operator ── scrubbed lifecycle metrics + soak ──────┤
 macOS/AppKit ── app/window presentation facts ───────────────┤
 pinned Ghostty ── renderer visibility/draw/free boundary ────┤
                                                              ▼
                                                    Agent Studio
                                                    (opaque system)

 Negative space: Ghostty/vendor changes, WindowServer internals,
 production-state mutation, persistence/schema changes, and multi-window
 routing are outside the contract.
```

## Terms

- **Current visible projection**: the set of panes the user can presently see
  in the one workspace window after tab, active arrangement, residency,
  drawer expansion and child selection, minimize, and zoom exclusion are all
  applied. The set is empty when no tab is active.
- **Effectively visible**: a pane is in the current visible projection and its
  owning workspace window is visible, not miniaturized, and not occluded.
- **Temporary retention**: a pane and renderer remain live while the pane is not
  effectively visible, without entering user-close undo.
- **Close-undo retention**: a user-closed renderer remains restorable under the
  existing 300-second grace and capacity semantics.
- **Permanent replacement/release**: an old renderer is no longer a valid
  restore target and ownership must end independently of any renderer installed
  for the same pane.
- **Renderer deallocation**: deinitialization of the exact
  `Ghostty.SurfaceView` instance and execution of its
  `ghostty_surface_free` boundary. Manager bookkeeping is not deallocation.
- **App-observable renderer work or growth**: native visibility delivery and
  equality-suppression outcomes, renderer-lifecycle conservation, and
  run/PID-bound Agent Studio physical/IOSurface/IOAccelerator footprint. It
  does not assert direct observation of exact Metal command buffers unless the
  optional attribution tooling is available.
- **Free-memory pressure**: the pointwise sign-normalized series
  `−(raw free-memory bytes)`. Raw free memory remains required evidence that is
  collected and reported, while free-memory pressure is the series used by the
  common higher-is-worse slope decision.
- **Process restart**: termination of the Agent Studio process and construction
  of a new run. No in-process renderer identity, counter continuity, or
  close-undo retention survives this boundary.

## Outcomes

- **O1 — Render authority follows projection:** only effectively visible panes
  may draw or commit renderer frames. (U1, U6)
- **O2 — Temporary retention is lossless:** visibility changes preserve live
  sessions, canonical content, and prompt reveal. (U2, U3)
- **O3 — Retention classes remain distinct:** temporary retention, close undo,
  permanent replacement, and process restart cannot consume or imitate one
  another. (U4, U5)
- **O4 — Lifetime is accountable:** operators can reconcile creation,
  manager-owned populations, permanent release, actual free, and orphan
  candidates within one run. (U7)
- **O5 — Proof is scoped and falsifiable:** app-side behavior is proven in an
  isolated run without overclaiming platform causality. (U8)

## Normative requirements

### Effective visibility and renderer work

- **R1** — A renderer MUST perform drawing or compositor commit work only while
  its pane is effectively visible. If any effective-visibility term becomes
  false, renderer drawing/commit authority MUST end without terminating,
  suspending, or disconnecting the terminal session. (U1, U2; O1, O2)
- **R2** — The following states MUST make a pane not effectively visible:
  inactive tab; collapsed drawer; drawer child not in the active visible drawer
  layout; inactive arrangement; background residency; minimized layout pane;
  minimized drawer child; zoom-excluded pane; absent active tab; hidden,
  miniaturized, or occluded owning window. The union of these states is
  conjunctive: satisfying one visible dimension MUST NOT override another
  hidden dimension. (U1; O1)
- **R3** — Tab switch, drawer collapse/expand, arrangement switch,
  background/reactivate, zoom enter/exit/retarget/companion, and
  minimize/expand MUST reconcile every affected renderer to the resulting
  effective visibility. Unaffected renderers whose result is unchanged MUST
  remain unchanged. (U1, U6; O1)
- **R4** — Creation, attach, restore, and reveal MUST NOT transiently authorize
  drawing before the pane's effective visibility is known. Once a retained pane
  becomes effectively visible, it MUST be eligible for its next current frame
  without restarting or replacing the durable session. (U1, U3; O1, O2)
- **R5** — Reconciliation that computes the same effective-visibility result as
  the last delivered result MUST NOT invoke another native visibility delivery
  or otherwise enqueue avoidable renderer work for that surface. Work for a
  projection transition MUST scale with renderers whose effective result
  changes, not with the full retained fleet. (U6; O1)
- **R6** — Focus or responder changes MUST NOT grant frame drawing/commit
  authority to a renderer that is not effectively visible. At the pinned
  Ghostty revision, focus can restart display-link, cursor, or timer/update
  traffic, while `Thread.drawFrame` still guards invisible frame drawing;
  neither focus traffic nor equal occlusion delivery may be reported as a
  hidden commit without commit-boundary evidence. (U1, U6; O1)

### Temporary retention and reveal

- **R7** — Temporary disappearance from the visible projection MUST preserve
  the exact canonical pane and mounted terminal content needed for return. It
  MUST NOT unmount or permanently retire a pane merely because SwiftUI/AppKit no
  longer projects it. This applies to parent panes and drawer children across
  tab, arrangement, background, minimize, zoom, and window transitions. (U2,
  U3; O2)
- **R8** — While temporarily retained, the shell/process, PTY-zmx session,
  terminal model, and incoming output MUST continue. On reveal, the same durable
  session MUST present content current through the hidden interval. Finite,
  bounded memory residency for this intentionally live population is permitted
  and MUST NOT by itself be classified as a leak. (U2, U3; O2)

### User close and undo

- **R9** — Pane close and tab close MUST place eligible surfaces into the
  existing close-undo behavior for exactly 300 seconds and MUST preserve the
  existing capacity, ordering, and eligibility semantics. Temporary hiding,
  minimize, drawer collapse, arrangement switch, backgrounding, and zoom MUST
  NOT consume close-undo capacity or restart its timer. (U4; O3)
- **R10** — An immediate undo while the renderer is still retained MUST restore
  that exact renderer and session. If the renderer's 300-second retention has
  expired but workspace undo is still available, undo MUST restore the pane by
  creating a new renderer and reconnecting the existing durable session when
  that session remains available; it MUST NOT represent the expired renderer as
  reused. (U2, U4; O2, O3)

### Permanent close and replacement

- **R11** — Undo expiry, explicit permanent close, and permanent replacement
  MUST end ownership of the exact retired host and renderer instance. Completion
  is proven only when that `Ghostty.SurfaceView` deinitializes and its
  `ghostty_surface_free` boundary runs. A logical destroy/release record alone
  MUST NOT satisfy this requirement. (U5, U7; O3, O4)
- **R12** — Permanent release MUST be instance-safe. If an undo or replacement
  has already installed a new host/renderer for the same pane identity,
  retirement of the old instance MUST NOT unmount, free, occlude, focus, or
  otherwise alter the replacement. (U3, U5; O2, O3)
- **R13** — Repair/recreate MUST treat the old renderer as permanently replaced:
  it MUST NOT insert the old renderer into close-undo retention, consume undo
  capacity, reset a close-undo timer, or leave more than one replaced renderer
  retained after the replacement settles. The durable terminal session MUST
  continue through repair. User close MUST retain its distinct R9 behavior.
  (U2, U4, U5; O2, O3)

### Process restart

- **R14** — App launch/restart MUST be treated separately from temporary
  retention, close undo, and in-process replacement. A new process run MUST
  rebuild renderer instances and reset run-scoped lifecycle counters. Existing
  workspace and durable zmx restore contracts remain applicable, but no prior
  `SurfaceView` identity, in-memory close-undo renderer, or counter value is
  promised across restart. (U2, U4, U7; O3, O4)

### Operational observability

- **R15** — Within each process run, production-safe telemetry MUST expose:
  successful renderer creation total; current manager-owned active, hidden, and
  close-undo populations; permanent ownership-release total; actual
  deinitialization/free total; orphan-candidate population; and sufficient
  scrubbed run identity plus process PID to bind a controlled soak to the
  observed process. Creation increments exactly once only after one live
  renderer instance has been successfully created and accepted into manager
  ownership; failed attempts do not increment it. (U7; O4)
- **R16** — Telemetry semantics MUST distinguish these events:
  close-into-undo remains manager-owned and does not count as permanent release;
  explicit permanent close, repair replacement, and undo expiry each count as
  permanent release exactly once; actual free increments only at the
  deinit/free boundary. Within one run,
  `live renderer population = created total − deinitialized/free total`,
  `manager-owned population = active + hidden + close-undo`, and
  `orphan candidates = live − manager-owned`. A valid sample MUST satisfy
  `manager-owned ≤ live`; a negative orphan result is a telemetry/proof failure
  and MUST NOT be clamped to zero. After permanent ownership release, the exact
  retired instance remains an orphan candidate until its deinit/free event.
  That release MUST NOT be called settled or complete while its orphan candidate
  remains. Persistent or increasing candidates are a lifecycle failure, not an
  indefinitely transient state. (U5, U7; O4)
- **R17** — OTLP telemetry MUST NOT export raw pane IDs, surface IDs, paths,
  titles, commands, terminal content, prompts, payloads, errors, or tool output.
  Dimensions MUST be bounded lifecycle classifications plus scrubbed run/PID
  identity. Collector absence, rejection, or export failure MUST be fail-open
  for terminal and app behavior. (U7, U8; O4, O5)

### Platform and scope boundary

- **R18** — A real display sleep/wake cycle MUST test the assumption that the
  owning window becomes occluded before display-sleep coverage is claimed. If
  the window remains reported visible during display sleep, display-sleep proof
  MUST stop with the assumption falsified and require an owner scope decision;
  the implementation MUST NOT silently add a display-sleep channel. That result
  MUST NOT block implementation, PR readiness, or lifecycle completion for the
  separately proven projection and ordinary window paths. (U1, U8; O1, O5)
- **R19** — Investigation and runtime proof MUST use an isolated debug or beta
  identity and MUST NOT mutate production application state. The Ghostty pin
  MUST remain unchanged. No vendor, atom, store, bus, persistence, schema,
  cache, multi-window, WindowServer-mitigation, Xcode repair, or host-system
  repair scope may be added without a new owner decision. (U8; O5)

## Scenario contract

```text
Scenario                         Retention class       Required observable result
───────────────────────────────  ────────────────────  ─────────────────────────────
tab switch                       temporary             old tab stops draw/commit;
                                                        new tab reveals current content
drawer collapse / expand         temporary             children remain canonical and
                                                        mounted; draw authority follows view
arrangement switch               temporary             only resulting arrangement draws;
                                                        return preserves exact pane/session
background / reactivate          temporary             background pane remains live and
                                                        reappears with current content
zoom enter / exit / retarget     temporary             source/companion/excluded panes
and companion                                            follow the resulting projection
minimize / expand                temporary             minimized parent/child does not draw;
                                                        expansion preserves content/session
pane close                       close undo             exact 300 s behavior; immediate undo
                                                        reuses retained renderer
tab close                        close undo             every eligible descendant follows the
                                                        same close/undo contract
undo after surface expiry        close undo → new       pane restores with new renderer and
                                 renderer               durable session when still available
repair / recreate                permanent replacement  old instance frees; no undo entry or
                                                        replaced-renderer accumulation
launch / app restart             process restart        new run and renderer identities;
                                                        durable restore only
window hidden / minimized /
occluded                         temporary              every pane stops draw/commit
real display sleep / wake        optional coverage      required before sleep coverage;
                                 extension               falsification narrows the claim
```

## Observable surface contracts

### Terminal user surface

- Normal: only currently visible content renders; retained terminals continue
  producing output; reveal shows current content.
- Boundary: no active tab, collapsed or empty drawer, all panes minimized, or
  zoom retarget in flight produces no transient visibility assertion for a
  pane whose resulting projection is not yet known.
- Failure: failure to reconcile one renderer MUST NOT restart, close, or corrupt
  another renderer or its durable session. A missing/dead renderer may surface
  the existing failure UI, but it does not authorize silent replacement of
  canonical pane state.
- Partial success: unaffected panes preserve their previous effective state;
  only failed panes remain unavailable.
- Compatibility: user close/undo and durable session behavior remain as stated
  in R9–R10; internal APIs and callback shapes have no compatibility promise.

### Operator telemetry surface

- Normal: one run/PID-bound scrape can distinguish every population, evaluate
  R16 conservation, report raw free memory, and derive the sign-normalized
  free-memory pressure used by the V7 slope decision.
- Invalid: manager-owned population greater than live population is a telemetry
  correctness failure, even when a clamped orphan calculation would display
  zero.
- Boundary: counters reset on process restart; gauges describe only the current
  run. Cross-run counter continuity is undefined and MUST NOT be inferred.
- Failure: missing telemetry is not application failure, but a run without the
  required series cannot certify lifecycle correctness or the soak.
- Attribution boundary: unavailable or failed Metal System Trace / exact
  command-buffer tracing does not make a required lifecycle series missing. It
  limits only a stronger claim that a residual graphics anomaly was causally
  attributed to an exact Metal commit boundary.
- Partial success: source-side JSONL may aid local forensics, but stale files,
  screenshots, generic health, or unmarked rows cannot substitute for current
  marker/PID-bound metric proof.
- Compatibility: lifecycle field/dimension additions remain subject to the
  existing source-side OTLP allowlist and scrub contract.

### Pinned Ghostty boundary

- Agent Studio may rely on invisible `Thread.drawFrame` returning without a
  frame draw at the pinned revision.
- Agent Studio MUST account for `Surface.occlusionCallback` queuing work even
  when the requested visibility equals the prior request; native equal delivery
  is therefore not a no-work contract.
- Focus can restart display-link/cursor/timer activity, but actual hidden frame
  commits require separate commit-boundary evidence. Exact Metal command-buffer
  tracing is optional for that stronger attribution claim, not an app-side
  completion gate. The specification forbids the commit outcome; it does not
  mislabel generic update traffic as a commit or claim direct zero-commit
  observation when that optional evidence is unavailable.
- No behavior from a newer Ghostty revision is part of this contract.

## Cross-cutting obligations

- **Reliability:** visibility reconciliation and telemetry failures are
  contained per renderer and fail open for terminal I/O. Permanent release is
  fail-closed for completion claims: no free evidence means not released.
- **Performance:** effective visibility is latest-state projection; unchanged
  results are suppressed, and a transition's native work is proportional to
  changed renderers. Required app-side proof combines native visibility
  delivery/equality counts, lifecycle conservation, graphics-footprint slope
  evidence, and direction-normalized system-pressure slope evidence. No
  per-frame, per-layout-tick, or fleet-wide equal redelivery is permitted.
- **Privacy:** OTLP exports only bounded lifecycle vocabulary, aggregate counts,
  and scrubbed run/PID identity.
- **Platform compatibility:** macOS window occlusion and pinned Ghostty behavior
  are explicit, versioned assumptions with R18 as the display-sleep falsifier.
- **Accessibility:** not applicable; this program adds no user-interface
  controls or interaction vocabulary.
- **Security:** no new actor, trust boundary, privilege, credential, or external
  command surface is authorized.
- **Data lifecycle:** no persisted data or schema change is authorized.

## Requirement-to-proof coverage

```text
U     P   O   R              Contract surface                 V / evidence modality
────  ──  ──  ─────────────  ───────────────────────────────  ─────────────────────────
U1    P1  O1  R1–R4,R6,R18   user + Ghostty + AppKit          V1 state/native delivery;
                                                                V7 graphics/pressure slopes
                                                                + sleep claim
U2    P1  O2  R1,R4,R7,R8,   terminal session                 V2 automated continuity;
               R10,R13,R14                                      runtime output/readback
U3    P1  O2  R4,R7,R8,R12   pane/drawer/zoom presentation    V3 automated transitions;
                                                                native visual interaction
U4    P1  O3  R9,R10,R13,R14 close/undo/restart               V4 deterministic retention;
                                                                same/new-instance inspection
U5    P1  O3  R11–R13         permanent lifetime              V5 instance-bound deinit/free;
                                                                repeated repair soak
U6    P1  O1  R3,R5,R6        renderer delivery               V6 call/work-count measurement
U7    P1  O4  R11,R15–R17     operator metrics                V7 marker/run/PID metric proof;
                                                                conservation, normalized-pressure,
                                                                and scrub checks
U8    P1  O5  R18,R19         proof and change boundary       V7 falsifiable isolated soak;
                                                                V8 pin/scope inspection
```

### Proof obligations

- **V1 — Effective visibility:** automated behavior covers every R2 dimension,
  conjunctive combinations, nil active tab, attach/reveal ordering, and changed
  versus unchanged populations. Required evidence proves visibility-false
  delivery, equality suppression, and the absence of app-observable renderer
  work or growth through deterministic source/native-delivery observations,
  lifecycle conservation, and V7 graphics-footprint and normalized-pressure
  measurement. When optional Metal command-buffer tooling is unavailable, this
  evidence does not claim direct observation of exact zero commits or identify
  an exact residual commit boundary.
- **V2 — Session continuity:** while each temporary state is active, a durable
  terminal session continues producing output; reveal and repair show that
  output without a new zmx/PTY/session identity.
- **V3 — Presentation continuity:** native interaction exercises tab switch,
  drawer collapse/expand, arrangement switch, background/reactivate, zoom
  enter/exit/retarget/companion, and parent/drawer-child minimize/expand. Every
  canonical pane remains present and returns with its exact content.
- **V4 — Retention separation:** controlled-clock behavior distinguishes
  temporary retention, immediate close undo, retention through 299 seconds, the
  exact 300-second expiry, undo after renderer expiry, permanent replacement,
  and process restart.
- **V5 — Lifetime and repair:** instance-bound observation proves the exact old
  host becomes weakly released and its `Ghostty.SurfaceView` reaches deinit
  followed by `ghostty_surface_free`, while an immediate undo or same-pane
  replacement remains intact. Repeated repair reaches a steady manager-owned
  and live population rather than accumulating one renderer per invocation.
- **V6 — No redundant work:** a fleet-scale workload measures native
  visibility delivery counts, equality suppression, and app-observable renderer
  work for equal and changed projections. Equal reconciliation produces zero
  native delivery; changed work tracks only changed renderers. Exact Metal
  command-buffer counts are optional stronger attribution evidence and are not
  required by this gate.
- **V7 — Observability and soak:** source projection tests prove OTLP scrubbing
  and metric semantics. The minimum certification run is one fresh isolated
  debug or beta identity with exactly 20 zmx-backed terminal surfaces spanning
  at least two tabs, two arrangements, one multi-child drawer, minimized panes,
  and a zoom companion. Give every surface bounded initial content, then stop
  workload output so the lifecycle lane is isolated. Bind the Agent Studio PID,
  run marker, contemporaneous WindowServer PID, and required system-pressure
  series before sampling.

  Warm for 10 minutes, sampling at least every 10 seconds. Then exercise 20
  cycles each of tab switch, drawer collapse/expand, arrangement switch,
  background/reactivate, zoom enter/exit/retarget, parent and drawer-child
  minimize/expand, window minimize/restore, and window occlude/reveal. Exercise
  20 sequential repair/recreate operations, 10 close/immediate-undo operations,
  and 10 closes observed at 299 seconds and through the exact 300-second
  renderer expiry. After all populations settle, retain the quiescent fleet for
  a final 30-minute measurement window at the same cadence.

  Every sample requires the active/hidden/undo/release/free/orphan series,
  successful-creation total, native visibility-delivery and equality-suppression
  counts, Agent Studio physical/IOSurface/IOAccelerator footprint, WindowServer
  footprint, compressor size, swap use, and free memory. Missing, stale-marker,
  or wrong-PID required series fails certification. R16 algebra MUST be valid at
  every sample; equal reconciliation MUST produce zero native visibility
  delivery; off-projection surfaces MUST have visibility false and show no
  app-observable renderer-work or sustained graphics-footprint growth; repair
  and close/expiry populations MUST return to their expected conserved count
  with no release called complete before free.

  For the common higher-is-worse slope decision, use each footprint series,
  compressor size, swap use, and free-memory pressure. Compute free-memory
  pressure pointwise as `−(raw free-memory bytes)` before regression; retain and
  report the raw free-memory series, but do not apply the common positive-growth
  rule to that inverse-pressure raw series. For every decision series, report
  the ordinary least-squares slope and its 95% confidence interval over the
  final 30-minute quiescent window. A strictly positive lower confidence bound
  is a residual growth anomaly that fails the required soak and blocks PR
  readiness and app-side lifecycle completion under this program. Increasing
  raw free memory is recovery and passes this slope gate; declining raw free
  memory is worsening and fails when the lower 95% confidence bound of its
  normalized free-memory-pressure slope is strictly positive. A failure does
  not, by itself, attribute the anomaly to Agent Studio; attribution still
  requires run-correlated causal evidence at the responsible boundary.

  Display-sleep coverage is a separate extension of this certification run. To
  claim it, perform one real display sleep/wake cycle and observe the owning
  window's occlusion transition plus the same required visibility, lifecycle,
  and graphics evidence. If occlusion does not change, the sleep claim fails and
  returns for the R18 scope decision; the already-proven app-side projection and
  ordinary-window result remains valid.

  Metal System Trace or equivalent exact command-buffer tracing MAY strengthen
  attribution of a residual WindowServer/Metal anomaly to a commit boundary.
  Tool unavailability, capture failure, or xctrace failure MUST NOT block
  implementation, PR readiness, or app-side lifecycle completion and MUST NOT
  trigger Xcode or host-system repair. Its absence blocks only that stronger
  causal-attribution claim.
- **V8 — Scope:** current diff/source inspection proves no vendor pin, atom,
  store, bus, persistence/schema, production-state, multi-window, or
  WindowServer-mitigation expansion, and no Xcode or host-system repair.

## Remaining evidence gap

The display-sleep mapping is deliberately unresolved until the V7 extension
records a real sleep/wake cycle. This does not block implementation, PR
readiness, or app-side lifecycle completion for proven projection and ordinary
window paths. R18 blocks only a display-sleep coverage claim and requires an
owner scope decision when the occlusion assumption is falsified.

Without optional exact Metal command-buffer tracing, a residual graphics anomaly
cannot be claimed as causally attributed to an exact commit boundary. This is an
attribution gap, not an app-side lifecycle completion gap.
