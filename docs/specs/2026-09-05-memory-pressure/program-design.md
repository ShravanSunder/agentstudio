# Memory Pressure Track — Program Design

Structural realization of [specification.md](specification.md) for the needs in
[requirements.md](requirements.md). Source anchors are `origin/main` at `57c49d0e3` and pinned
Ghostty `v1.3.1` (`332b2aef`).

## How the fixed contract is satisfied, in one screen

```text
canonical workspace atoms ─┐            WindowLifecycleAtom.presentationFacts
 (tab, arrangement, drawer,│                     (visible / miniaturized / occluded;
  zoom, minimized, residency)                     equal writes suppressed)
           │                                               │
           ▼  StoreVisibilityTierResolver (exists; 3 edits) ▼
   WorkspaceSurfaceCoordinator+RendererVisibility  ◄── observation-tracked (same shape as
      effective(pane) = windowShown && tier == .p0Visible   +RepositoryFactDemand); re-arms on
           │                                                every read atom + on manager
           │ reconcileAttachedVisibility { paneID in effective(paneID) }   membership change
           ▼
   SurfaceManager (exists)  ── owns membership, close-undo, and the per-surface
      │  lastDeliveredVisibility record; delivers ONLY on change; admits focus-on only
      │  for a visible first responder; detach(.close) accepts hidden membership;
      │  publishes `released` counts before dropping its last reference
      ▼  SurfaceRendererStateDelivery (new 30-line seam; live impl = the two C calls)
   ghostty_surface_set_occlusion / ghostty_surface_set_focus         (pin, fixed)

   WorkspaceSurfaceCoordinator.unregisterHostedView / registerHostedView (exist)
      └─ retire the EXACT prior PaneHostView: unmount content, remove from container,
         mount view drops its Ghostty.SurfaceView  ──►  ARC ──►  SurfaceView.deinit
                                                              └► ghostty_surface_free
                                                              └► recorder.recordRendererFreed()
   every undo restore path (pane, tab, drawer child, floating) ── reuses the retained
      surface for its pane before any fresh creation
   AgentStudioPerformanceTraceRecorder (exists) ── run-scoped counters
      created / released / freed + last populations → one low-volume lifecycle record
```

What changes: two edges are added (projection → manager visibility reconciliation; host
retirement on permanent unregister/replacement), one edge is reordered (detach delivers before
removal), `detach(.close)` accepts hidden membership, undo restore reuses the retained surface
on every path, focus-on is admitted only for a visible first responder, one record is added to
`ManagedSurface`, the resolver gains a zoom-drawer clause and a minimized-parent guard and reads
structural facts, the manager's collections leave Observation, and one telemetry event is
added. What stays: every owner, the Ghostty pin, the undo grace and repair's use of it, the view
hierarchy, the atoms. The per-surface steady-state cost (RC1, ~58 MB) is out of this track and
depends on the approved follow-up Ghostty pin bump.

## Components and ownership

| Component | Owns | Exposes | Consumers | Changes when |
| --- | --- | --- | --- | --- |
| `WorkspaceSurfaceCoordinator` (+RendererVisibility, new file) | Composition of window facts × pane projection into per-attached-surface effective visibility; when to reconcile; recording each reconciliation's counts and MainActor duration | `bindRendererVisibility(toOwningWindowId:)`, `stopRendererVisibilityObservation()` | AppDelegate boot (same place `bindPullRequestDemand` is bound) | The projection model gains a dimension |
| `StoreVisibilityTierResolver` (exists; edited) | What "in the visible projection" means | `tier(for:)` | coordinator (restore today; visibility now) | Product projection rules change. Edits: (1) during zoom, a drawer child of the zoom source whose drawer is expanded, in layout, and not drawer-minimized is `.p0Visible`; (2) a drawer child of a minimized parent is `.p1Hidden`; (3) reads `paneStructuralFacts`/`isDrawerExpanded` instead of `pane(_:)` so the tracked dependency set excludes repository enrichment |
| `SurfaceManager` (exists; edited) | Exact membership (active/hidden/close-undo) with `@ObservationIgnored` collections, last-delivered visibility per surface, focus admission, permanent release with ordered telemetry | `attach/detach/move/undoClose/requeueUndo/destroy` (unchanged signatures, `detach(.close)` now accepts hidden membership); new `reconcileAttachedVisibility(_:)`, `setAttachedBindingsChangeHandler(_:)`, `acceptCreatedSurface(_:metadata:)` (extraction of the accept step so creation delivery is testable) | coordinator, `TerminalPaneMountView`, tab controller (`syncFocus`) | Lifecycle policy changes |
| `SurfaceRendererStateDelivery` (new protocol + `LiveSurfaceRendererStateDelivery`) | The two native calls behind one substitutable boundary | `deliverVisibility(_:to:) -> Bool`, `deliverFocus(_:to:) -> Bool` | `SurfaceManager` only | libghostty API changes |
| `PaneHostView` (exists) | Its container cycle and mounted content | new `retire()` = unmount content, remove self from `swiftUIContainer` | coordinator (+ViewLifecycle) | Host composition changes |
| `TerminalPaneMountView` (exists) | Strong `ghosttySurface` while mounted; its focus-on request goes through the manager | existing `removeSurface()`; conforms to new `PaneMountedContent.paneHostWillRetire()` (default no-op) | `PaneHostView.retire()` | Mount composition changes |
| `Ghostty.SurfaceView` (exists; edited) | The native handle; the only `ghostty_surface_free` caller; its responder focus-on request goes through the manager | deinit additionally reports `freed`; new `package init(managedSurfaceID:appCommandDispatcher:)` that builds a view with no native handle (test construction seam; invariant `surface == nil` so every native call is a no-op) | recorder; tests | Vendor API changes |
| `WindowLifecycleAtom` (exists; edited) | Window presentation facts | `recordWindowPresentation` gains an equal-write guard | coordinator | — |
| `AgentStudioPerformanceTraceRecorder` (exists) | Run-scoped lifecycle counters + emission; OTLP allowlist rows in `AgentStudioOTLPTraceProjection` | `recordRendererLifecycle(action:active:hidden:closeUndo:)`, `recordRendererFreed()`, `recordRendererVisibilityReconciliation(applied:equal:missing:elapsed:)` | manager, surface view, coordinator | Telemetry schema changes |

Dependency direction is unchanged: App (coordinator, hosts) → Terminal (`SurfaceManager`,
`SurfaceView`) → Infrastructure (recorder). Terminal never reads workspace or window atoms;
the coordinator never calls a `ghostty_*` function; views never decide visibility.

Forbidden edges and how they are caught: `SurfaceManager` reading `WorkspaceStore` or
`WindowLifecycleAtom` (import graph + review); any `ghostty_surface_set_occlusion` call outside
`LiveSurfaceRendererStateDelivery`, and any `ghostty_surface_set_focus(…, true)` outside it
(source-scan architecture test in the `SurfaceManagerHotPathArchitectureTests` family); manager
collections observable (same test asserts `@ObservationIgnored`); SwiftUI `dismantleNSView`
deciding permanent lifetime (it stays a log line).

## The structural choices and why

### Choice 1 — who decides effective visibility

| Option | Shape | Serves | Costs / falsifier |
| --- | --- | --- | --- |
| **A (selected)** coordinator derives from canonical atoms via the tier resolver × window facts, observation-tracked | one new coordinator extension mirroring `+RepositoryFactDemand`; manager delivers on change | R1–R3, R6 with one predicate; every projection dimension the app already models; restore and visibility agree by construction | one MainActor re-evaluation per changed structural atom, O(attached) reads; budget 1 ms at 30 surfaces recorded per reconciliation; falsifier: a pane hidden by a SwiftUI-only mechanism the resolver does not model → revisit toward Option C for that dimension |
| B: hook each transition site (tab switch, arrangement, drawer, zoom, minimize, window) | many call sites in tab controller + executor | same obligations if complete | missed sites are silent (the 2026-08 attempt found four missing dimensions this way); rejected |
| C: `PaneHostView`/mount view derive from AppKit truth (`viewDidHide/Unhide`, `viewDidMoveToWindow`, window occlusion) | view-local, no atom join | uniform over unknown hiding mechanisms | depends on AppKit hidden-propagation semantics nobody has verified under this SwiftUI/AppKit mix; contradicts the repo rule that views do not derive shared state; kept as the fallback for Option A's falsifier |

Performance classification (CLAUDE.md lane directive): input class is a latest-state projection;
mechanism is distinct-until-changed at the delivery point plus one MainActor hop coalescing all
atom writes of a turn into one re-evaluation (the `Task { @MainActor }` re-arm already used by the
sibling observation). Admitted reads are structural only: the resolver reads
`paneStructuralFacts`, `isDrawerExpanded`, tab layout/arrangement/minimized state, zoom
presentation, and window facts; it does not read `pane(_:)`, whose derivation pulls repository
topology and enrichment into the tracked set. The manager's collections are `@ObservationIgnored`
so health, CWD, and delivered-state rewrites inside `SurfaceManager` never re-arm the observation.
No debounce, timer, or cache type is introduced. Each reconciliation records `applied`, `equal`,
`missing`, and `elapsed_ms`.

### Choice 2 — where the last-delivered record lives

In `ManagedSurface.lastDeliveredVisibility: Bool?` inside `SurfaceManager`, written only by the
manager's private `deliverVisibility(surfaceId, visible)`. Both writers (lifecycle transitions
and projection reconciliation) pass through it, so it cannot go stale; equal deliveries are
suppressed there, which is what pinned Ghostty needs (`occlusionCallback` has no equality guard).
Alternative rejected: a coordinator-side cache keyed by surface id (goes stale when lifecycle
delivers without the coordinator seeing it — the exact defect the prior attempt hit).

### Choice 3 — attach semantics (fail-safe over strictness)

`attach` keeps delivering visible=true immediately (today's behavior). Reconciliation then
delivers false to surfaces attached into hidden tabs, because membership change re-arms the
observation. Rationale: if reconciliation is late or broken at attach time, the failure mode is
"renders like today", never "blank terminal". The specification's R5 permits this bounded
transient. Limit of the fail-safe: once a surface has been turned off, a later reconciliation
defect would leave it off until the next membership change or atom write re-arms observation;
the debug-bundle proof (tab switch away and back, window occlude and reveal) is what guards that
case, not the attach transient.

### Choice 4 — host retirement point

Retire the exact prior host inside the coordinator's `unregisterHostedView(for:)` and inside
`registerHostedView` when a different host already occupies the slot. Not in SwiftUI
`dismantleNSView` (fires for temporary disappearance; the prior attempt regressed drawer panes
that way) and not on a delayed pane-id lookup (undo can install a replacement under the same
pane id within the delay). Host retirement releases the host's references only; surface
ownership ends separately when the manager releases (expiry, destroy). Repair therefore retires
the old host immediately while its surface waits out the existing 300 s close-undo window, then
frees.

### Choice 5 — focus follows responder truth, gated by visibility

Focus-on has three writers today: `GhosttySurfaceView.becomeFirstResponder` (direct native call,
`GhosttySurfaceView.swift:538`), `TerminalPaneMountView.becomeFirstResponder`
(`SurfaceManager.shared.setFocus(…, true)`, `TerminalPaneMountView.swift:785`), and
`SurfaceManager.syncFocus` (tab controller and launch restore). Programmatic focus
(`PaneFocusExecutor` → `window.makeFirstResponder`) reaches the first two, so focus-on is not
confined to user interaction with displayed content. The selected policy:

- every focus-on request routes through `SurfaceManager.setFocus(surfaceId, focused: true)`;
  `GhosttySurfaceView.becomeFirstResponder` calls it instead of the native function (both types
  live in the Terminal module; `GhosttySurfaceView+Input` already uses the shared manager);
- the manager admits focus-on only when `lastDeliveredVisibility == true` for that surface;
  focus-off is always delivered directly (fail-safe, cheap, equality-guarded in Ghostty);
- no intent is stored. When a visibility delivery turns a surface on, the manager checks
  responder truth (`surfaceView.window?.firstResponder === surfaceView`) and delivers focus-on
  only if true; when it turns a surface off, it delivers focus-off. Responder truth cannot go
  stale the way a recorded intent can.

Rejected: a weak per-view focus-requester link installed by the creating manager (the abandoned
branch) — more machinery for the same admission decision; the shared manager is already the
focus writer these views use.

### Choice 6 — close from hidden membership

`detach(.close)` today guards on `activeSurfaces` (`SurfaceManager.swift:303`). A pane that was
minimized, arrangement-switched, or whose drawer collapsed has its surface in `hiddenSurfaces`
(via `detachForViewSwitch`), so closing that pane or its tab logs "Surface not found" and the
surface stays in `hiddenSurfaces` forever — a second unbounded leak alongside the host cycle.
Selected: `detach(.close)` and `requeueUndo` look up `activeSurfaces[id] ?? hiddenSurfaces[id]`,
deliver off (a no-op at the delivery record if already off), move the surface to `closeUndo` with
one 300 s deadline, and remove it from whichever collection held it. `.hide`/`.move` from hidden
membership remain no-ops (already hidden).

### Choice 7 — undo reuses the retained surface on every path

`restoreView(for:worktree:repo:)` reuses the retained surface (`+ViewLifecycle.swift:570–591`),
but `undoTabClose` calls `restoreUndoPane(pane, worktree: nil, repo: nil)` (`+Undo.swift:56–61`),
which falls through to `createViewForContentUsingCurrentGeometry` → fresh creation, leaving the
retained surface in undo until expiry. Floating terminals take the same branch. Selected: the
retained-surface lookup moves to the front of `restoreUndoPane` for terminal content: obtain
the retained surface for the pane (`undoClose()`/`requeueUndo` LIFO as today, since panes are
restored in reverse close order), and if found, mount it through the same path `restoreView`
uses, resolving worktree/repo from the pane when present and using the topology-independent
mount otherwise. Fresh creation only when no retained surface matches. No undo-API cutover; the
abandoned branch's `restoreClosedSurface(forPaneID:)` rewrite is not adopted.

## Interfaces as behavior

**`SurfaceManager.reconcileAttachedVisibility(_ effective: (UUID) -> Bool) -> SurfaceVisibilityReconciliationResult`**
Caller: coordinator, MainActor, synchronous. For each surface in `activeSurfaces` with
`state == .active(paneId)`: `desired = effective(paneId)`; if `desired != lastDeliveredVisibility`,
deliver and count `applied`; else count `equal`; a nil native handle counts `missing`. Hidden and
close-undo surfaces are never touched (their off state is owned by lifecycle transitions). On a
delivery that turns a surface on, if that surface view is its window's first responder, deliver
focus-on; on a delivery that turns it off, deliver focus-off. Postcondition: every active
surface's record equals `effective(paneId)`. No ordering guarantee between surfaces. Idempotent.

**`SurfaceManager.setAttachedBindingsChangeHandler(_ handler: (() -> Void)?)`**
Invoked synchronously after any change to the set of `(surfaceId → paneId)` active bindings
(attach, detach, move, swap, destroy). The coordinator uses it to re-arm observation. Exactly one
handler; setting nil clears.

**`SurfaceManager.detach(_:reason:)`** (contract tightened, signature unchanged): resolves the
surface in `activeSurfaces` or `hiddenSurfaces`; delivers visible=false and focus=false **while it
is still looked up** (no-ops at the delivery record if already off); then moves membership. For
`.close` from hidden membership the surface enters `closeUndo` with a single deadline exactly as
from active. `requeueUndo` likewise. `.hide`/`.move` on an already-hidden surface are no-ops.

**`SurfaceManager.setFocus(_:focused:)`** (contract tightened): focus-on is delivered only when the
surface is in `activeSurfaces` and `lastDeliveredVisibility == true`; otherwise it is dropped and
counted. Focus-off is always delivered when the surface is known. `syncFocus(activeSurfaceId:)`
applies the same rule per surface.

**`SurfaceManager.acceptCreatedSurface(_ surfaceView:metadata:) -> Result<ManagedSurface, SurfaceError>`**
The accept step split out of `createSurface`: delivers visible=false, records
`lastDeliveredVisibility = false`, registers the surface in `hiddenSurfaces`, records `created`.
`createSurface` calls it after `ghostty_surface_new` succeeds; tests call it with a bare view.

**`SurfaceManager.destroy(_:)` and undo expiry** (ordering contract): compute the populations
with the surface removed, emit `released` with those counts, then remove the entry from its
collection and drop the reference. The `released` record therefore always precedes any `freed`
record for the same surface, and `orphan` cannot go negative under correct operation.

**`SurfaceRendererStateDelivery`**: `deliverVisibility(_ visible: Bool, to: Ghostty.SurfaceView) -> Bool`
returns false when the native handle is nil (no side effect). Same for `deliverFocus`.

**`PaneHostView.retire()`**: calls `paneHostWillRetire()` on mounted content, unmounts it, removes
self from `swiftUIContainer`, clears `onAttachedToWindow`. Idempotent. After return, the only
strong references to the host are held by whoever called `retire()`.

**`PaneMountedContent.paneHostWillRetire()`** (new protocol requirement with default no-op
extension): `TerminalPaneMountView` implements it as `removeSurface()` so the mount view drops
its `Ghostty.SurfaceView` even if some other object still retains the mount view. Bridge and
webview content keep the default.

**`StoreVisibilityTierResolver.tier(for:)`** (contract extended): during zoom, `.p0Visible` for
the source pane and for a drawer child whose parent is the source, whose drawer is expanded, and
which is in the drawer layout and not drawer-minimized; `.p1Hidden` for any other pane. Outside
zoom, a drawer child additionally requires its parent not to be in `activeMinimizedPaneIds`.
Reads are structural (`graphAtom.paneStructuralFacts`, `isDrawerExpanded`, tab layout state, zoom
presentation), never `pane(_:)`.

**Recorder**: `recordRendererLifecycle(action:, active:, hidden:, closeUndo:)` increments
`created`/`released` for those actions and emits one record with all counters;
`recordRendererFreed()` increments `freed` and emits with the last known populations; both are
lock-serialized and callable from any thread. `recordRendererVisibilityReconciliation(applied:,
equal:, missing:, elapsed:)` emits only when `applied + missing > 0`, carrying `elapsed_ms`;
all-equal reconciliations add to an `equal_since_last_emit` counter carried on the next record.
Attribute keys and controlled action strings are allowlisted in `AgentStudioOTLPTraceProjection`.

## State

### Renderer visibility per surface (owner: `SurfaceManager`)

| Membership | `lastDeliveredVisibility` after transition | Written by |
| --- | --- | --- |
| created → `hidden` | `false` (delivered at acceptance; Ghostty defaults to visible) | `acceptCreatedSurface` |
| `hidden` → `active` (attach, move, undo restore) | `true` (fail-safe), then reconciled | `attach`/`move`, then `reconcileAttachedVisibility` |
| `active` (projection changed) | `effective(paneId)`; focus follows responder truth | `reconcileAttachedVisibility` |
| `active` → `hidden` (detach `.hide`/`.move`) | `false`, focus `false` | `detach` (before membership removal) |
| `active` → `closeUndo` (detach `.close`, requeue) | `false`, focus `false` | `detach`/`requeueUndo` (before membership removal) |
| `hidden` → `closeUndo` (detach `.close` from hidden) | unchanged (`false`) | `detach` |
| `closeUndo` → `hidden` (undoClose) | unchanged (`false`) | — |
| any → released | `released` emitted with post-removal counts, then record dropped | `destroy`/expiry |

Illegal: delivering to a surface not in `active`/`hidden` (the current detach bug). The private
`deliverVisibility` asserts membership in debug builds and counts `missing` in release.
Focus-on to a surface whose record is `false` is refused, never delivered.

### Host lifecycle (owner: coordinator via `ViewRegistry` slot)

| Trigger | Host operation | `slot.host` after | Mounted content after | Surface ownership |
| --- | --- | --- | --- | --- |
| SwiftUI dismantle (drawer collapse, arrangement switch, backgrounding) | none (log only) | unchanged | mounted | unchanged |
| pane close (`teardownView` → `finishViewTeardown` → `unregisterHostedView`) | `retire()` on the captured exact host | nil | unmounted; terminal mount view dropped its surface | `closeUndo` 300 s |
| fresh-surface replacement (`createViewForContent` paths call `unregisterHostedView` first) | `retire()` old host | new host registered | new mount | old surface per its path |
| repair/recreate (`executeRepair` → `teardownView` → `detach(.close)`) | `retire()` old host immediately | new host | new mount | old surface in `closeUndo` 300 s (unchanged behavior), then freed |
| `registerHostedView` over a different existing host (placeholder → real, zoom companion, bridge) | `retire()` the existing host, then register | new host | new mount | — |
| bridge retirement guard trips (`currentController !== retiring`) | nothing (existing behavior) | replacement kept | replacement kept | — |
| undo within 300 s (any path) | new host built around the retained `SurfaceView` | new host | same `SurfaceView` remounted | back to `active` |

## Call paths, current and proposed

### Tab switch (representative projection transition)

```text
current  PaneTabViewController.selectTab → store.tabLayoutAtom.setActiveTab
           → updateVisibleTabHost: host.isHidden = tabId != activeTabId        (AppKit only)
           → executor.restoreVisibleViewsForActiveTabIfNeeded
           → SurfaceManager.syncFocus(activeSurfaceId)                          (focus only)
         ✗ no edge to ghostty_surface_set_occlusion for any surface

proposed (added edges marked +)
         store.tabLayoutAtom.setActiveTab  ── observation onChange ──►
         + coordinator.observeRendererVisibility (one MainActor hop per turn)
         +   withObservationTracking { manager.reconcileAttachedVisibility { paneID in
         +       windowShown && tierResolver.tier(for: paneID) == .p0Visible } }
         +   manager: for changed surfaces → delivery.deliverVisibility(v, to: surface)
         +            → ghostty_surface_set_occlusion(v)   [pin: mailbox message; renderer
         +              consumes it on its own thread; drawFrame returns while !visible]
         +            → off ⇒ focus-off; on ⇒ focus-on iff view is window.firstResponder
         +   recorder.recordRendererVisibilityReconciliation(applied, equal, missing, elapsed)
         SurfaceManager.syncFocus(activeSurfaceId)  (unchanged call; now visibility-gated)

R1 boundary: the app's obligation ends when set_occlusion(false) is called within one MainActor
hop; a frame the renderer thread already started, or an IOSurfaceLayer.setSurface block already
dispatched to main, may complete; no new frame starts after the renderer thread consumes the
message (Thread.zig:353–376, 494–496).
```

### Window occlusion / miniaturize / hide

```text
current  MainWindowController.windowDidChangeOcclusionState → synchronizeWindowPresentationFacts
           → ApplicationLifecycleMonitor.handleWindowPresentationChanged
           → WindowLifecycleAtom.recordWindowPresentation                        (dead end)
proposed same ingress; + equal-write guard in the atom; + the atom read is inside the tracked
         closure, so the same onChange → reconcile path as above delivers off/on to every
         displayed surface exactly once. Assumption carried to runtime proof: AppKit posts
         didChangeOcclusionState for an ordered-out window (unverified from source).
```

### Detach for hide / close / move (bug fix, reordered and widened)

```text
current  detach: activeSurfaces.removeValue ──► setOcclusion(false) ✗ lookup fails ──► noop
         detach(.close) on a hidden surface ──► "Surface not found" ──► surface leaks in hidden
proposed detach: managed = active[id] ?? hidden[id]
                 ──► deliverVisibility(false) + deliverFocus(false) [no-op if already off]
                 ──► remove from its collection ──► hidden / closeUndo ──► bindings handler
         requeueUndo: same lookup and reordering.
```

### Pane close → undo expiry → free (new edges +)

```text
current  teardownView → detach(.close) → undo entry (300 s) → finishViewTeardown
           → viewRegistry.unregister (slot.host = nil)                          ✗ host cycle alive
         expiry → expireUndoEntry → entry dropped → "ARC will clean up"           ✗ never deinits
proposed teardownView → detach(.close) [now really delivers off; accepts hidden] → finishViewTeardown
         + → unregisterHostedView: let host = viewRegistry.view(for:); unregister; host.retire()
         +     → TerminalPaneMountView.paneHostWillRetire() → removeSurface()
         +     → host.unmountContentView(); host.removeFromSuperview()
         expiry → + recorder.recordRendererLifecycle(.released, counts-without-this-surface)
                → expireUndoEntry → entry dropped → last strong ref gone
         + → Ghostty.SurfaceView.deinit → ghostty_surface_free → recorder.recordRendererFreed()
```

### Undo restore (tab close, pane close, drawer child, floating)

```text
current  undoPaneClose → restoreUndoPane(pane, worktree, repo) → restoreView → undoClose() reuse ✓
         undoTabClose  → restoreUndoPane(pane, nil, nil) → createViewForContentUsingCurrentGeometry
                          ✗ fresh surface; retained one sits in undo until expiry
proposed restoreUndoPane (terminal):
         + → surfaceManager.undoClose() → metadata.paneId == pane.id ? reuse : requeueUndo
         + → reuse: TerminalPaneMountView(worktree/repo if resolvable, else topology-independent)
         +          → attach(retained) → displaySurface(retained) → registerHostedView
         → else fresh creation (unchanged)
```

### Creation

```text
current  createSurface → ManagedSurface(state: .hidden) → hiddenSurfaces[id]     (Ghostty visible)
proposed createSurface → ghostty_surface_new → + acceptCreatedSurface:
           deliverVisibility(false) → hiddenSurfaces[id] → record .created
         attach → activeSurfaces[id] → deliverVisibility(true) (as today) → + bindings handler
```

## Failure, partial success, recovery

- **Native handle nil** (creation failed, or post-free): delivery returns false, counted
  `missing`, membership still transitions. No retry; the surface is unusable anyway and the
  existing health path reports it.
- **In-flight renderer work at the off transition** (MP-01): the renderer thread may finish a
  frame it already began and a `setSurface` block already on the main queue may commit. This is
  inside R1's boundary; proof samples after a quiescence interval, not at the instant of the
  transition.
- **Observation fires before the window is registered or before any tab is active:** window
  facts default `.hidden` and the resolver returns `.p1Hidden` → all attached surfaces go off.
  When facts arrive they come back on. This is the intended R3 "no active tab" behavior; the
  startup-visible proof on the debug bundle guards against a stuck-off regression.
- **Reconciliation defect after a surface was turned off:** the surface stays off until the next
  re-arm (membership change or structural atom write). This is the real failure mode of the
  design; it is why the debug-bundle proof exercises away-and-back transitions rather than
  trusting the attach fail-safe.
- **Reconciliation exception safety:** the closure is pure reads; delivery is two C calls.
  Nothing async, nothing to roll back.
- **Retire called twice or on an already-detached host:** idempotent.
- **Undo after `retire()` but within the grace:** a new host is built and the retained
  `SurfaceView` (unparented by `removeSurface()`) is remounted; its runtime binding is
  re-established by the existing `bind(runtime:)` call.
- **Bridge controller replacement race:** the existing guard in `finishViewTeardown` skips
  `unregisterHostedView` when the current controller differs; the old host was already retired
  by `registerHostedView` when the replacement was installed.
- **Focus-on requested for an off surface** (programmatic focus into an occluded window, or a
  responder change while hidden): refused and counted; when the surface turns on, responder
  truth decides whether focus-on is delivered.
- **Last reference dropped inside `destroy`/expiry:** the `released` record is emitted before
  the removal that could drop the last reference, so `freed` follows it.
- **Recorder unavailable (nil weak reference):** counters are skipped; lifecycle behavior is
  unchanged (fail-open, R14).

## Concurrency and consistency

Everything here is MainActor-serialized: atoms, coordinator, manager, hosts. The only
cross-thread participants are `Ghostty.SurfaceView.deinit` reporting `freed`, which the recorder
accepts under its existing lock, and the Ghostty renderer thread consuming the occlusion mailbox
message asynchronously (R1 boundary above). Observation re-arm uses the generation counter
pattern already in the coordinator, so a stale onChange after `stopRendererVisibilityObservation`
is dropped. Delivery order across surfaces within one reconciliation is unspecified and
irrelevant (the renderer threads are independent). Telemetry order for one surface is fixed:
`created` → … → `released` → `freed`.

## Cross-cutting

| Obligation | Owner | Mechanism | Failure behavior | Proof seam |
| --- | --- | --- | --- | --- |
| Privacy (R14) | recorder + `AgentStudioOTLPTraceProjection` | counts + controlled action enum only, allowlisted keys; reuse existing scrubbed run/PID attributes | export failure ignored | projection test asserts attribute set and that a surface id never survives projection |
| Reliability (R2, U2) | manager + coordinator | fail-safe attach; retire only on permanent paths; SwiftUI dismantle untouched; zoom-drawer children stay on | worst case = today's behavior at attach; stuck-off after a defect is covered by away-and-back proof | coordinator tests for temporary transitions keep `slot.host` and mounted content |
| Performance (R6) | manager delivery record + resolver reads | deliver on change; structural-only reads; `@ObservationIgnored` collections; `elapsed_ms` per reconciliation | — | reconciliation counts in tests; zero re-arms on manager-local writes; `elapsed_ms` under 1 ms at 30 surfaces on the debug bundle |
| Compatibility (R8) | manager | undo TTL/capacity code untouched | — | existing undo tests stay green |
| Observability (R12–R13) | recorder | run-scoped counters, orphan computed at emit, ordered `released` before `freed`, negative reported as `invariant_violation=true` | — | recorder tests; VictoriaLogs query by proof marker |

## Proof architecture

| Requirement | Owner | Seam | What is real / replaced | Observation |
| --- | --- | --- | --- | --- |
| R1, R3, R6 | coordinator + manager | `WorkspaceSurfaceManaging` mock recording `reconcileAttachedVisibility` closures; `SurfaceRendererStateDelivery` recording fake inside a real `SurfaceManager` | atoms, resolver, manager real; native calls replaced | delivered (surfaceID, visible) sequence; `applied/equal` counts; per-dimension resolver contracts incl. zoom-source drawer child and minimized-parent child |
| R4, R5, R8 | manager | recording delivery + bare `Ghostty.SurfaceView` (no native handle) via `acceptCreatedSurface` | manager real | delivery observed while surface still attached; close from hidden membership enters undo |
| R7 | manager | same | — | focus-on refused while record is off; delivered on turn-on only when first responder |
| R9 | coordinator | existing coordinator harness with a mock manager returning a retained `ManagedSurface` from `undoClose()` | — | tab-close undo and floating undo attach the retained surface, no fresh `createSurface` call |
| R10, R11 | coordinator + hosts | existing coordinator harness (`WorkspaceStore`, `ViewRegistry`, real `PaneHostView`, sentinel `PaneMountedContent`) with `weak` references and an autorelease drain | AppKit views real | weak host/content nil after close+unregister; still non-nil after temporary transitions; replacement untouched |
| R10 runtime | whole app | debug bundle + external `sample`/`vmmap`/`footprint` | everything real | renderer-thread count and IOSurface regions return to baseline 300 s after closing N panes, N including minimized ones |
| R1 runtime | whole app | debug bundle + `sample` after quiescence | everything real | hidden-tab renderer threads show no `updateFrame`→`drawFrame` past the gate and no `IOSurfaceLayer.setSurface` dispatch |
| R6 runtime | whole app | debug bundle + VictoriaLogs | everything real | `elapsed_ms` p95 under 1 ms with 30 attached surfaces across tab switches |
| R12–R14 | recorder | unit tests; VictoriaLogs | in-process | counter arithmetic, `released`-before-`freed` ordering, negative-orphan flag, attribute allowlist |

Enforcement classes: type/interface for the delivery seam and the mounted-content hook;
automated tests for ordering, retention, and undo reuse; source-scan architecture assertions
that `ghostty_surface_set_occlusion` and `ghostty_surface_set_focus(…, true)` appear only in the
live delivery type and that manager collections are `@ObservationIgnored`.

## Requirement → design → proof trace

| R | Scenario | Realizing owner | Proof |
| --- | --- | --- | --- |
| R1, R2 | tab switch away / back | coordinator reconciliation → manager delivery | V1 (recorded deliveries), V2 (`sample` after quiescence), V4 (manual reveal) |
| R3 | each dimension incl. zoom-source drawer, minimized parent | `StoreVisibilityTierResolver` × window facts | V1 per-dimension cases |
| R4 | detach hide/close/move, incl. from hidden | manager lookup + reorder | V1 "delivered while attached", "close from hidden enters undo" |
| R5 | creation | `acceptCreatedSurface` delivers off | V1 |
| R6 | equal reconciliation; structural-only reads | manager delivery record; resolver reads; `@ObservationIgnored` | V7 counts; zero re-arm on manager writes; `elapsed_ms` runtime |
| R7 | focus writers | manager `setFocus` gate; responder truth on turn-on | V1 focus cases |
| R8 | close/undo incl. hidden | manager | V5 |
| R9 | every undo path | coordinator `restoreUndoPane` reuse | V5 same-instance assertion for tab and floating undo |
| R10, R11 | expiry / replacement / repair | host retirement in coordinator; manager release ordering | V5, V6 |
| R12–R14 | telemetry | recorder + projection allowlist | V8, V9 |
| R15 | boundary | — | V10 |

## Source anchors

`SurfaceManager.swift:302–360, 425–470, 779–815`; `WorkspaceSurfaceCoordinator+ViewLifecycle.swift:45–56, 150–175, 398–475, 566–592`;
`WorkspaceSurfaceCoordinator+Undo.swift:46–61, 112–128, 154–175`;
`WorkspaceSurfaceCoordinator+RepositoryFactDemand.swift:28–45, 118–127` (pattern);
`WorkspaceSurfaceCoordinator+ActionExecution.swift:298–307, 369–374` (`detachForViewSwitch` callers);
`PaneHostView.swift:13–21, 92–108, 160–166`; `PaneViewRepresentable.swift:38–46`;
`ViewRegistry.swift:217–232`; `PaneTabViewController.swift:1464–1468`; `MainWindowController.swift:160–200`;
`TerminalRestoreScheduler.swift:41–115`; `ZoomPresentationContainer.swift:172, 395–419`;
`DrawerPanelOverlay.swift:181–197`; `TerminalPaneMountView.swift:446–458, 782–800`;
`GhosttySurfaceView.swift:472–486, 533–556`; `AppDelegate+MainWindowCreation.swift:120–127`;
Ghostty `src/Surface.zig:3248–3275`, `src/renderer/Thread.zig:353–376, 494–512, 596–620`,
`src/renderer/generic.zig:1029–1066`, `src/renderer/metal/IOSurfaceLayer.zig:49–79`.
