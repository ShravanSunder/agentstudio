# Terminal Scrollbar Convergence

Status: Reviewed; ready for implementation planning

## Product Intent

Restore reliable terminal scrollbar/thumb synchronization and scroll-to-bottom
behavior after the terminal pressure-reduction work, without undoing that
work's MainActor-pressure improvements.

The terminal scrollbar has two independent responsibilities:

1. Ghostty owns authoritative scrollback state.
2. Agent Studio owns the mounted AppKit scrollbar presentation.

The host presentation must converge to the latest admitted Ghostty state even
when a `TerminalRuntime` is temporarily unavailable and when a changed
scrollbar state arrives during an AppKit live-scroll gesture.

## User-Visible Success

- Dragging the terminal scrollbar thumb leaves the thumb and rendered viewport
  at the latest Ghostty state received for that gesture.
- Dragging the thumb to the host scrollbar's bottom requests Ghostty's
  authoritative bottom rather than a row calculated from a potentially stale
  host total.
- A scrollbar state already detached by the compact drain reaches the host
  cache before that batch begins terminal activity projection.
- A mounted terminal surface continues receiving host scrollbar presentation
  updates during a temporary runtime-registration gap.
- High-rate Ghostty scrollbar callbacks remain contracted before MainActor
  scheduling.

## Scope

This spec owns only terminal scrollbar state delivery and post-live-scroll
presentation reconciliation.

It does not change:

- scrollbar width, visual styling, or macOS `AppleShowScrollBars` handling;
- Ghostty source or the vendored Ghostty revision;
- terminal activity heuristics, quiet timers, or Inbox behavior;
- surface-title cache or title-metadata routing, which remain runtime-gated;
- EventBus admission or replay;
- the fixed-key accumulator's coalescing/statistics contract;
- the off-main `TerminalActivityProjector`;
- general-purpose queue, mailbox, or task-scheduling infrastructure.

The fat/native-looking scrollbar is a separate presentation investigation and
must not expand this correctness change.

## Current Contract

PR #202 (`c0c2047f`, merged as PR #202 through `53a979a8`) replaced one
MainActor task per high-rate Ghostty callback with:

```text
Ghostty callback
  -> synchronous fixed-key per-surface accumulator
  -> at most one scheduled MainActor drain per live surface
  -> one compact presentation/runtime apply
  -> off-main terminal activity projection
```

That contraction is required and remains the baseline.

Ghostty's scrollbar callback is change-driven:

- the renderer compares terminal scrollbar state with its cached scrollbar
  state during a draw;
- it emits only when that cached state changes;
- `scroll_to_row` changes terminal scroll state and requests a render;
- an additional identical callback is not guaranteed.

Therefore the host cannot rely on a later duplicate callback to repair a
presentation update it discarded or intentionally suppressed.

## Source-Proven Convergence Gaps

The following gaps are direct observations in current source. Their occurrence
in the reported live failure has not yet been instrumented, so the change and
proof stay limited to these falsifiable paths.

### Mounted host presentation is gated by optional runtime lookup

The current drain validates the mounted surface and pane, begins a batch, then
requires a `TerminalRuntime` before applying
`SurfaceView.hostScrollbarState`.

A missing runtime is not evidence that the mounted surface lifetime is invalid.
Retiring the surface's local actions at this point can discard the only
change-driven scrollbar callback, including a newer callback offered while the
current batch is draining.

`GhosttyActionDisposition` classifies scrollbar changes as local activity
evidence, so this accumulator drain is the live scrollbar host-cache route.
The generic exact-action `updateSurfaceHostCache` scrollbar switch case does
not mitigate this path.

Before PR #202, host scrollbar cache application happened before runtime
routing. Runtime lookup failure could drop runtime observation, but it did not
drop mounted AppKit presentation.

### Live-scroll suppression has no end reconciliation for received state

During AppKit live scrolling, Agent Studio intentionally updates document
extent and reflects the scroller without programmatically repositioning the
clip view. This prevents Ghostty callbacks from fighting the user's drag.

At `didEndLiveScroll`, the current implementation only clears
`isLiveScrolling`. If the final Ghostty callback was already admitted and
cached while live scrolling was active, Ghostty may not emit another identical
callback. The host then misses its opportunity to apply the acknowledged final
position.

### Drag-to-bottom predicts an authoritative Ghostty bound from host cache

The scroll wrapper currently turns every thumb position into `scroll_to_row`
using the host-cached `total` and visible-row count.

Ghostty decides whether a row means its active bottom using Ghostty's live
`total_rows`. During sustained output, Ghostty's live maximum row can advance
beyond the host-cached maximum used by the drag. A thumb at the host bottom can
therefore request an interior Ghostty row, leaving the viewport above bottom
and preventing sticky follow-bottom from re-engaging.

## Requirements

### R1 — Preserve callback contraction

Scrollbar callbacks must continue entering the existing synchronous
per-surface accumulator. The change must not restore one MainActor task per
callback or admit raw scrollbar samples to EventBus/replay.

### R2 — Validate surface lifetime before presentation

The MainActor drain must continue validating:

- the `SurfaceManager` lookup resolves the expected surface ID;
- `managedSurfaceID` still matches;
- the surface still maps to the expected pane.

Failure of those lifetime checks retires local actions for that surface.

### R3 — Apply host scrollbar state independently of runtime availability

After a valid batch begins, the drain must apply changed
`batch.presentation.scrollbarState` to the validated `SurfaceView` before
optional runtime lookup.

Temporary absence of a matching `TerminalRuntime` must not:

- prevent host scrollbar cache application;
- retire the valid surface's accumulator state;
- discard a convergent follow-up batch.

Runtime-owned batch state may be applied only when the matching runtime exists.
This restores the pre-#202 separation between mounted host presentation and
runtime observation.

### R4 — Preserve off-main activity projection

Terminal activity aggregation, window derivation, and quiet timers remain owned
by `TerminalActivityProjector`, off MainActor.

An already-detached activity aggregate depends on the validated surface/pane
identity and captured projection context, not on `TerminalRuntime`
availability. When those inputs exist, projection submission proceeds even
during a runtime-registration gap.

This spec does not introduce a projection mailbox or change ordered-control
semantics. Projector round-trip latency is a separate performance hypothesis;
it must be measured before changing that boundary.

### R5 — Express drag-to-bottom as authoritative bottom intent

While translating a live thumb drag:

- an interior position emits `scroll_to_row(row)`;
- when the computed row reaches the maximum row represented by the current
  host scrollbar state, the wrapper emits `scroll_to_bottom` instead.

The host may use cached bounds to recognize that the thumb is at the host
bottom, but it must not use that cached maximum row as the authoritative
Ghostty bottom command.

Repeated live-scroll notifications must be deduplicated by semantic viewport
command identity: the same interior row and repeated bottom intent do not emit
duplicate actions. This dedup record persists across gestures and is distinct
from R6's gesture-local acknowledgement record; starting a gesture must not
clear it. Programmatic synchronization continues to update the persistent
record so a thumb grab that does not change command identity emits nothing.
When synchronized state is pinned to bottom, the recorded identity is bottom
intent rather than the numerically equivalent maximum row.

### R6 — Reconcile only gesture-relevant Ghostty state

For the current live-scroll gesture, the wrapper retains only:

- the latest viewport command it actually sent: none,
  `scroll_to_row(requestedRow)`, or `scroll_to_bottom`;
- whether at least one host scrollbar-state update arrived during the gesture.

This gesture-local record is reset at `willStartLiveScroll` and cleared at
`didEndLiveScroll`. It does not survive the gesture or arbitrate later
programmatic commands.

When AppKit reports `didEndLiveScroll`:

1. live-scroll suppression ends;
2. when no viewport command was sent, a state received during the gesture may
   be synchronized immediately;
3. `scroll_to_row(requestedRow)` is acknowledged only when a state arrived
   during the gesture and the latest cached state's `top` equals
   `requestedRow`;
4. `scroll_to_bottom` is acknowledged only when a state arrived during the
   gesture and the latest cached state is pinned to bottom;
5. without the acknowledgement required by steps 2-4, the wrapper performs no
   drag-end position write and leaves the in-flight/next Ghostty callback on the
   existing normal synchronization path.

Drag-end reconciliation must not emit another `scroll_to_row` or
`scroll_to_bottom` action. It applies state Ghostty already delivered only.

This is intentionally not a persistent scroll-intent state machine. It repairs
the missing reconciliation opportunity without letting unrelated output-growth
callbacks erase a user's history drag and without inventing request IDs,
timeouts, polling, or cross-command arbitration that Ghostty does not expose.

If Ghostty settles an interior row to a different value and emits no later
callback, this focused contract preserves the user's AppKit position rather
than guessing that the differing state acknowledged the drag. Resolving that
ambiguous case would require a request/revision contract that is outside this
spec.

Bottom intent and row intent do not share a delivery lane: Ghostty applies row
intent synchronously under the renderer lock, while bottom intent is queued to
its IO thread. A gesture that reaches bottom and then returns to an interior
row may therefore settle at bottom after the interior row was already
acknowledged at drag end. The existing normal synchronization path is the
accepted repair for that late callback, and the resulting position is
convergent even though the intermediate frame is not. Correlating, cancelling,
or ordering in-flight commands stays out of scope; it would require the
request/revision contract this spec declines.

### R7 — Preserve follow-bottom semantics

Existing sticky-bottom decisions remain based on the pre-update AppKit distance
from bottom and Ghostty row growth.

The change must preserve:

- history viewports staying anchored when total rows grow;
- output growth inside the sticky-bottom buffer requesting
  `scroll_to_bottom`;
- output growth outside the buffer not requesting it;
- a Ghostty state pinned to bottom mapping to AppKit document offset zero.

### R8 — Preserve boundedness and MainActor budget

The existing accumulator remains bounded by live surfaces and its compile-time
key set. The change must add no callback-count-shaped storage.

MainActor work added by this spec is limited to:

- an equality check and host-cache write in the existing compact drain;
- one bounded gesture-local command/receipt record and conditional AppKit
  synchronization at live-scroll end.

## Boundary And Separability Map

```text
Ghostty renderer / terminal
  owns: authoritative total, top, visible-row state
  exposes: change-driven scrollbar callbacks

          scrollbar state          scroll_to_row
                 |                       ^
                 v                       |

TerminalLocalActionAccumulator
  owns: bounded callback contraction and activity statistics
  exposes: latest-value MainActor batch

                 |
                 v

Ghostty.ActionRouter compact drain
  owns: surface-lifetime validation and host/runtime delivery separation
  writes: SurfaceView host cache first; TerminalRuntime when available

                 |
                 v

TerminalSurfaceScrollView
  owns: AppKit document extent, thumb/clip presentation, live-drag suppression
  commands: interior rows or Ghostty-authoritative bottom intent
  reconciles: only Ghostty state acknowledging the gesture command

TerminalActivityProjector
  owns: off-main activity derivation
  does not own AppKit presentation
  retains: current drain-await/follow-up coupling outside this spec
```

## Allowed And Forbidden Dependencies

Allowed:

- the action-router drain writes host scrollbar cache after surface-lifetime
  validation;
- the same batch updates `TerminalRuntime` when available;
- the scroll wrapper reads the host cache through
  `TerminalSurfaceHostStateSource`;
- the scroll wrapper sends Ghostty binding actions through
  `TerminalSurfaceActionPerforming`.

Forbidden:

- AppKit presentation depending on successful runtime lookup;
- a raw scrollbar callback creating its own MainActor task;
- scrollbar samples entering EventBus/replay;
- calculating Ghostty's authoritative bottom command from a host-cached row;
- drag-end reconciliation polling Ghostty or manufacturing a second scroll
  command;
- introducing a generic mailbox, persistent request protocol, or vendor API for
  this fix.

## Alternatives Considered

### Restore direct per-callback MainActor delivery

Rejected. It repairs timing by reversing PR #202's bounded admission contract
and recreating callback-count-shaped MainActor pressure.

### Add an ordered terminal activity projection mailbox

Deferred. It could decouple presentation follow-ups from projector round trips,
but current evidence does not prove that latency is the root cause of the
reported correctness failure. It adds a new ordering and boundedness contract
that this fix does not need.

### Add a persistent scroll-intent/acknowledgement state machine

Rejected for this slice. Ghostty exposes scrollbar state, not request IDs.
Persistent arbitration would need to define interactions with menu commands,
scroll-to-bottom, prompt jumps, layout, and later callbacks. The reported
no-repeat failure is repaired with a bounded gesture-local acknowledgement
record that is cleared at drag end.

### Treat every callback received during a drag as acknowledgement

Rejected. Sustained output can emit a pinned-bottom growth callback before
Ghostty processes the user's interior-row request. Applying that unrelated
state at drag end would snap the viewport back to bottom and incorrectly re-arm
follow-bottom.

### Poll Ghostty after a drag

Rejected. It adds work to the hot path and compensates for a host presentation
gap that can be repaired from the existing cache.

## Proof Expectations

### Automated behavior proof

The permanent Swift Testing suite must prove:

- a valid mounted surface updates host scrollbar cache when no runtime is
  registered;
- runtime absence does not retire a valid pending/follow-up scrollbar batch;
- a valid no-runtime batch still submits its already-detached activity aggregate
  when its pane identity, projection context, and activity sink exist;
- invalid or replaced surface identity still retires pending local actions;
- an interior thumb drag emits `scroll_to_row`;
- a thumb drag reaching the host maximum emits `scroll_to_bottom` rather than a
  predicted maximum `scroll_to_row`;
- repeated live-scroll notifications deduplicate the same interior-row and
  bottom commands;
- a matching interior-row acknowledgement received during live scrolling is
  applied at drag end;
- a pinned-bottom acknowledgement received during live scrolling is applied at
  drag end;
- a gesture with no emitted viewport command may apply a state received during
  that gesture;
- an unacknowledged interior-row command causes no drag-end position write even
  when unrelated pinned-bottom growth callbacks arrived during the gesture;
- a gesture receiving no Ghostty scrollbar-state update causes no drag-end
  position write;
- drag-end reconciliation emits no additional Ghostty action;
- existing sticky-bottom, history anchoring, document range, and drag-to-row
  tests remain green;
- accumulator boundedness and one-drain-per-surface tests remain green.

The later implementation plan must identify the smallest callback-to-drain
integration seam that can exercise host-cache delivery without relying only on
isolated scroll math.

A narrow internal dependency seam for surface, pane, and runtime lookup is in
scope only if required to make that drain behavior directly testable. It must
not become a public abstraction, general routing framework, or `#if DEBUG`
production hook.

Live-scroll test helpers must allow a host state update to be inserted between
`didLiveScroll` and `didEndLiveScroll`; a helper that bundles the complete
gesture cannot prove R6.

### Quality proof

The scoped implementation must pass repository formatting and linting with no
new warnings or architecture violations.

### Manual proof

Use only the isolated per-worktree debug app identity and data/zmx roots.
Never launch an historical build against production state, focus or terminate
the production Agent Studio process, or copy production databases into debug
state.

Manual proof must demonstrate:

- thumb drag to a known history position;
- drag to bottom during sustained output that advances Ghostty's live total;
- scroll-to-bottom command or indicator behavior;
- continued output while pinned and while viewing history;
- final thumb, viewport, and bottom-indicator convergence.

### Performance preservation proof

Proof must show that scrollbar callback admission still produces at most one
scheduled MainActor drain per live surface with one coalesced follow-up, rather
than one task per callback.

Projector round-trip timing may be observed diagnostically, but changing its
architecture is outside this spec unless a separate investigation proves a
latency defect.

## Security Context

This change is not security-sensitive. It does not add external input formats,
filesystem or network access, subprocesses, secrets, persistence, IPC, or
privileged operations.

The relevant safety boundary is operational: manual proof must remain isolated
from production app processes and production state.

## Planning Readiness

The implementation plan may choose exact test seams and edit sequencing, but
must not redefine:

- host presentation as runtime-owned;
- Ghostty's state as non-authoritative;
- PR #202's callback contraction;
- the authoritative drag-to-bottom action;
- the focused gesture-local command acknowledgement rule;
- the explicit deferral of mailbox/general scheduling work and scrollbar
  styling.

No product decision remains open for this focused correction.
