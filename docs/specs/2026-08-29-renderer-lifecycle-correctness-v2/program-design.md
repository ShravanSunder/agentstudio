# Renderer Lifecycle Correctness v2 — Program Design

This design realizes the observable contract in [specification.md](specification.md)
without changing its meaning. It separates four lifetimes that currently overlap:

```text
canonical pane/session lifetime
  owned by existing workspace state and durable zmx identity

mounted host lifetime
  owned by ViewRegistry plus the AppKit host/container graph

renderer manager lifetime
  owned by SurfaceManager as attached, hidden, close-undo, or released

native draw authority
  owned per exact ManagedSurface by its last delivered Ghostty visibility
```

The correction stays inside existing owners. `WorkspaceSurfaceCoordinator`
composes workspace and window projection truth. `SurfaceManager` owns exact
renderer membership and native lifecycle delivery. `ViewRegistry` remains the
pane-to-host registry. `AgentStudioPerformanceTraceRecorder` remains the
process-scoped synchronized telemetry owner. No atom, store, bus, cache,
persistence contract, vendor change, or second lifecycle subsystem is added.

## The selected structure

```text
one workspace window
  WorkspaceWindow
    owns: the AppKit ordering completion hook for this exact window instance
    reports: one synchronous callback after NSWindow ordering returns

  MainWindowController
    owns: AppKit presentation ingress for the existing exact window identity,
          including resampling after WorkspaceWindow ordering completes
    writes: WindowLifecycleAtom.presentationFacts
    consumed by: WorkspaceSurfaceCoordinator visibility projection

  canonical workspace atoms
    own: residency, active tab and arrangement, minimized sets,
         drawer expansion/layout/minimize, zoom presentation
    expose: keyed structural facts and existing derived tab/arrangement reads
    consumed by: StoreVisibilityTierResolver

  WorkspaceSurfaceCoordinator
    owns: composition of attached renderer membership with pane and window truth
    exposes: direct renderer-visibility reconciliation through SurfaceManager
    also owns: exact host replacement/unregistration and teardown disposition

  ViewRegistry
    owns: pane-lifetime PaneViewSlot identity and current PaneHostView reference
    does not own: renderer release policy or temporary projection lifetime

  SurfaceManager
    owns: exact ManagedSurface membership, close-undo retention,
          last native-delivered visibility, native focus admission,
          permanent ownership release
    observation boundary: exact membership/delivered-state collections are
          @ObservationIgnored; public counts may remain observable
    exposes: membership-change callback, active projection reconciliation,
             user-close undo, permanent release

  Ghostty.SurfaceView
    owns: exact native ghostty_surface_t handle
    holds: weak exact-instance focus requester installed by its owning manager
    terminal boundary: MainActor isolated deinit -> synchronous
          ghostty_surface_free -> post-free telemetry

  AgentStudioPerformanceTraceRecorder
    owns: one lock-serialized, process-run renderer-lifecycle metric state
    exposes: delta counter events and current population gauges
```

Dependency direction remains:

```text
workspace/window facts -> WorkspaceSurfaceCoordinator -> SurfaceManager -> Ghostty C API
                                            |                 |
                                            v                 v
                                      ViewRegistry       lifecycle recorder

Ghostty.SurfaceView MainActor isolated deinit
  -> synchronous ghostty_surface_free
  -> post-free observation --------------------------------> lifecycle recorder
```

Forbidden edges are SwiftUI/AppKit dismantle deciding permanent lifetime; views
deriving visibility or calling native occlusion; `SurfaceManager` reading
workspace/window truth; reconciliation touching hidden/undo members; focus-true
bypassing the manager; repair entering close undo; registry replacement
inferring renderer disposition; and OTLP exporting exact pane, surface, host,
path, command, title, or terminal-content identity.

These rules are enforced by narrow interfaces and focused behavior tests. The
existing module DAG remains authoritative: App composition may depend on Core,
Terminal, and Infrastructure; Terminal must not depend on App.

### Behavioral interfaces between the existing owners

`SurfaceManager.reconcileAttachedVisibility` is a synchronous MainActor
operation whose caller supplies one pane-ID-to-effective-visibility decision
closure. It invokes that closure for exact attached surfaces only, applies the
per-instance equality and handle guards, and returns bounded
applied/equal/missing counts. The closure receives no view/handle and cannot
mutate membership. `SurfaceManager` remains `@Observable`, but its exact
attached, hidden, and close-undo membership collections—and therefore the
per-instance delivered state stored in those collections—are
`@ObservationIgnored`. Calling reconciliation inside `withObservationTracking`
does not subscribe the projection to manager-private health, CWD, membership,
or delivered-state rewrites. Existing public population counts may remain
observable for their current consumers, but the visibility projection does not
read them.

`SurfaceManager` exposes one replaceable attached-population-change callback to
App composition. It fires synchronously after the exact attached binding set
changes, including same-count replacement. It carries no product state; the
coordinator only restarts observation and rereads existing truth owners. This
callback is the sole visibility-projection invalidation edge for manager
membership. Health changes, manager-local CWD/metadata changes, close-undo
rewrites, and delivered-visibility updates do not fire it.

`WorkspaceWindow` is the concrete `NSWindow` subclass used only for the owned
workspace window. It overrides AppKit's central
`order(_:relativeTo:)` boundary, calls `super` synchronously, and then invokes
one optional ordering-completion callback. `MainWindowController` installs a
weak-self callback on that exact window. After each completed ordering call it
resamples the complete `WindowPresentationFacts` tuple—`isVisible`,
`isMiniaturized`, and `isOccluded`—from the same window and forwards it through
the existing `ApplicationLifecycleMonitor` ingress. It does not patch only the
visibility field and does not infer state from key, miniaturization, occlusion,
or close callbacks. One idempotent teardown used by `shutdown` and controller
`isolated deinit` clears the callback. No notification observer, token, KVO,
timer, polling loop, atom, or second presentation owner is added. Another
window cannot enter this instance-bound path.

The native proof observes ordering and occlusion as distinct ingress edges
without assuming AppKit keeps their values unchanged across one public ordering
operation. Immediately after `orderOut` or `orderFront` returns, the diagnostic
captures the tuple already published by the synchronous ordering callback and
requires the expected `isVisible` value with miniaturization unchanged. It then
allows AppKit's existing occlusion callback to converge the complete tuple and
validates the cumulative exact-surface delivery against the final effective
visibility. A later occlusion wake that leaves effective visibility unchanged
must be equality-suppressed. The separate cover-window scenario continues to
prove occlusion ingress directly.

`Ghostty.SurfaceView` is a MainActor AppKit UI owner and the pinned libghostty
surface API remains MainActor-bound. Its `isolated deinit` synchronously calls
`ghostty_surface_free` while `self` and the pass-unretained userdata still live,
then emits exactly one post-free observation after the native call returns. It
never schedules or captures the raw handle for later execution.

`Ghostty.SurfaceView` holds one weak, class-bound Terminal-module focus-request
interface installed by the exact `SurfaceManager` that creates it. A request
carries the immutable managed surface ID and the view's `ObjectIdentifier`.
The manager verifies both against its reverse map and current exact
`ManagedSurface` before applying focus. This avoids the production singleton,
supports injected managers, and avoids a manager↔view retain cycle. The link
exists through attached, hidden, and close-undo ownership; permanent release
clears it before dropping ownership. Missing/stale owner or identity rejects
focus true and logs locally; focus false may still go directly to the live
handle as a fail-safe.

`SurfaceManager.requestFocus` accepts true only for that verified exact
attached instance when its last delivered visibility is true. `syncFocus`
applies the same admission to its chosen target. Rejection is idempotent and
cannot change projection or session state.

`SurfaceManager.permanentlyRelease` accepts an exact surface ID and one bounded
reason. It removes an owned exact instance once, cancels its expiry, clears
reverse/health state, emits release accounting, and returns released. An absent
instance returns not-owned with no delta. It never creates workspace mutation
or close-undo state.

`SurfaceManager.restoreClosedSurface(forPaneID:)` is the only coordinator undo
lookup. On MainActor it first expires every entry due at the injected current
time, then removes the most recent still-eligible entry whose original pane
attachment matches the requested pane. It cancels only that task and preserves
every nonmatching entry's relative order, original close time, deadline, and
task. No global pop/mismatch/requeue path remains. An explicit surface-ID attach
performs the same due-expiry guard before consulting close undo.

`registerHostedView` and `unregisterHostedView` remain synchronous coordinator
operations. They may retire only the exact host reference captured before the
slot mutation. Registration replaces the slot once after retiring a prior
host; unregistration retires then clears the slot. Neither operation accepts a
surface disposition or performs delayed pane-ID lookup.

`AgentStudioPerformanceTraceRecorder` accepts renderer creation, manager
population, permanent release, native-delivery, equal-suppression, and
post-free observations into one locked run state and emits one ordered
aggregate snapshot, with no callback into product owners and no lifecycle
dependence on a sink. The recorder remains synchronized for callers that may be
off-main; the post-free observation specifically originates on MainActor only
after `Ghostty.SurfaceView`'s synchronous native free returns.

## Why this structure is the smallest credible correction

The structural crux is not whether hidden panes should be retained. That is
fixed. The crux is where three decisions belong:

1. complete effective visibility crosses workspace, window, and renderer
   membership owners, so App composition must join it;
2. native equal-delivery suppression and exact-instance release require the
   renderer owner, so they belong in `SurfaceManager`/`ManagedSurface`;
3. the host retain cycle exists in AppKit hosting, so the coordinator wrapper
   that replaces or clears the registered host must break it synchronously.

### Alternatives and tradeoffs

```text
Alternative                         Gain                         Cost / failure
──────────────────────────────────  ───────────────────────────  ───────────────────────────────
Selected: existing owners, one      complete truth without a    one transition-time attached-
projection observer, per-instance   second source of truth;      fleet projection pass; current
manager state                       exact native suppression     owners gain narrow interfaces
Action-specific calls from every    no observation bridge       every tab/drawer/zoom/window
mutation                                                          path must stay manually aligned;
                                                                  direct state writes remain gaps
SwiftUI dismantle as detach or       follows a framework hook    temporary projection destroys
retirement boundary                                               canonical mounted content; callback
                                                                  timing is not product lifetime
Pane-id delayed host retirement     can wait for UI teardown     same-pane undo/replacement can be
                                                                  retired by stale delayed work
New lifecycle atom/cache/state      centralized vocabulary       duplicate truth, new owner, broader
machine                                                            invalidation and prohibited scope
Vendor upgrade or vendor-visible    stronger creation-time       changes the pinned compatibility
initial-state option                 ordering                     boundary and is not authorized
```

The selected design pays one MainActor projection evaluation when an observed
workspace/window input or the explicit attached-binding callback changes. The
manager's `@ObservationIgnored` exact collections prevent manager-local health,
CWD/metadata, undo, and delivered-state rewrites from becoming accidental
projection inputs. A later canonical `PaneStructuralFacts` update can still pay
one evaluation because the narrowest existing pane fact also carries
CWD/association; that is an intentional workspace-fact edge, not manager
membership observation. Native calls and renderer queue work remain
proportional to changed effective results through the manager equality gate.
The coordinator records the evaluation cost; marker-scoped budget failure is
the revisit signal, not permission to add an unconfirmed state owner.

Two attribution boundaries remain deliberately visible:

- pinned Ghostty initializes renderer-thread visibility and focus to `true` and
  sends an initial wake. App code makes `false` the first host delivery after a
  live handle exists and before attach/display. Required proof covers that
  ordering through deterministic state and native-delivery observation, then
  tests hidden-renderer quiescence through lifecycle conservation and the V7
  graphics-footprint/normalized-pressure soak. Exact Metal command-buffer
  tracing may strengthen attribution of a residual anomaly to the initial-wake
  or commit boundary, but
  its absence does not block the app-side lifecycle result and does not justify
  vendor, Xcode, or host-system changes.
- repository source establishes the window occlusion callback path but not that
  real display sleep invokes it with `isOccluded = true`. A real sleep/wake
  cycle is an optional coverage extension. If it falsifies the occlusion
  assumption, only the display-sleep claim returns for an owner scope decision;
  ordinary projection and window-path fixes remain valid and PR-ready when
  their required proof passes.

## Current and proposed call paths

All current paths below are from Agent Studio
`246c9a81c256ded9431620ae9c8cd99f4a27622d` and Ghostty
`332b2aefc6e72d363aa93ab6ecfc86eeeeb5ed28`.

### Creation, attach, and effective visibility

```text
CURRENT
WorkspaceSurfaceCoordinator.createView*                         [unchanged entry]
  -> SurfaceManager.createSurface                               [current]
     -> Ghostty.SurfaceView.init -> ghostty surface handle      [current external effect]
     -> hiddenSurfaces[id] = ManagedSurface(.hidden)            [current write]
  -> SurfaceManager.attach                                      [current]
     -> hidden -> active                                        [current write]
     -> ghostty_surface_set_occlusion(true)                     [removed effect]
  -> TerminalPaneMountView.displaySurface                       [current]
  -> registerHostedView -> ViewRegistry.register                [current]

Observable result: attach grants native visibility before complete pane and
window projection truth is joined. No owner reconciles every later projection
or window transition.

PROPOSED
WorkspaceSurfaceCoordinator.createView*                         [unchanged entry]
  -> SurfaceManager.createSurface                               [changed]
     -> Ghostty.SurfaceView.init -> live native handle           [unchanged boundary]
     -> deliverVisibility(false) on that exact handle            [added first host delivery]
     -> ManagedSurface(lastDeliveredVisibility: false) accepted  [added exact-instance state]
     -> created delta + current manager gauges                   [added result]
  -> SurfaceManager.attach                                      [changed]
     -> hidden/undo -> attached; no visibility=true              [changed write/effect]
     -> attached-population callback                             [added sync callback]
  -> WorkspaceSurfaceCoordinator re-arms observation            [added]
     -> equal WindowPresentationFacts stop in WindowLifecycleAtom[added source guard]
     -> capture bound window facts + narrowest existing
        PaneStructuralFacts/tab/drawer/zoom projection           [added reads]
     -> canonical pane CWD/association may wake; record cost     [accepted measured edge]
     -> SurfaceManager.reconcileAttachedVisibility               [added direct call]
        -> equal result: no native call                          [added suppression result]
        -> changed result: ghostty_surface_set_occlusion(value)  [changed native effect]
        -> state updates only after live-handle delivery          [added invariant]
        -> false additionally delivers focus=false               [added safety effect]
  <- per-surface result; one failure does not stop other panes    [added containment]
```

Current evidence anchors are
[`WorkspaceSurfaceCoordinator+ViewLifecycle.swift`](../../../Sources/AgentStudio/App/Coordination/WorkspaceSurfaceCoordinator+ViewLifecycle.swift),
[`SurfaceManager.swift`](../../../Sources/AgentStudio/Features/Terminal/Ghostty/SurfaceManager.swift),
and
[`GhosttySurfaceView.swift`](../../../Sources/AgentStudio/Features/Terminal/Ghostty/GhosttySurfaceView.swift).
Pinned Ghostty establishes initial renderer flags and the draw guard in
`src/renderer/Thread.zig`, plus unsuppressed `Surface.occlusionCallback` in
`src/Surface.zig`.

### Temporary projection changes

```text
CURRENT
canonical mutation
  -> some paths call detachForViewSwitch / reattachForViewSwitch
     -> detach removes active membership before lookup-based false delivery
        [changed: current false delivery can be skipped]
     -> attach delivers true unconditionally
        [removed effect]
  -> other paths only mutate workspace/window projection
     [current gap: SurfaceManager remains native-visible]
  -> SwiftUI/AppKit may remove or remount a representable subtree
     [framework callback occurrence is scenario-dependent and not authoritative]

PROPOSED
canonical mutation                                            [unchanged authority]
  -> existing keyed atom invalidation                         [unchanged]
  -> visibility observation callback                         [added]
     -> re-register observation before/with current capture  [added]
     -> recompute complete attached-pane result              [added]
     -> SurfaceManager exact-instance equality gate          [added]
     -> changed native visibility only                       [changed effect]

explicit temporary detach, where retained                    [changed]
  -> deliver false while exact surface is still reachable    [changed order]
  -> deliver focus false                                     [changed order]
  -> active -> hidden membership                             [current state, reordered]
  -> membership callback re-arms observation                 [added]

PaneViewRepresentable.dismantleNSView                        [intentionally unchanged]
  -> diagnostics/testing hook only; no unregister/detach/release
```

### Window order visibility ingress

```text
CURRENT
NSWindow.orderOut / orderFront                                 [unchanged AppKit entry]
  -> NSWindow.order(_:relativeTo:) changes isVisible             [current platform boundary]
  -> ordinary NSWindow has no post-order MainWindowController ingress
                                                               [current gap]

Separate delegate callbacks for key, miniaturization, occlusion, and close
  -> MainWindowController.synchronizeWindowPresentationFacts    [current]
  -> ApplicationLifecycleMonitor.handleWindowPresentationChanged[current]
  -> WindowLifecycleAtom.recordWindowPresentation               [current write]

Observable result: `orderOut`/`orderFront` synchronously change
`NSWindow.isVisible` while miniaturization remains unchanged. AppKit may then
publish a related occlusion transition; no existing callback is guaranteed to
refresh `WindowPresentationFacts` for the preceding visibility transition.

PROPOSED
MainWindowController creates its exact WorkspaceWindow           [changed concrete type]
  -> install weak-self ordering-completion callback              [added instance edge]

WorkspaceWindow.order(_:relativeTo:) on MainActor
  -> super.order(place, relativeTo: otherWindowNumber)           [unchanged AppKit effect]
  -> invoke ordering-completion callback after super returns     [added sync edge]
  -> resample isVisible + isMiniaturized + isOccluded together    [added complete read]
  -> ApplicationLifecycleMonitor.handleWindowPresentationChanged [unchanged ingress]
  -> WindowLifecycleAtom.recordWindowPresentation                [changed: equal guard]
  -> visibility observation callback                             [added dependent edge]
  -> SurfaceManager.reconcileAttachedVisibility                  [added direct call]
     -> changed exact surfaces deliver native visibility         [changed effect]
     -> equal exact surfaces perform no native delivery           [added suppression]

controller shutdown / lifecycle teardown
  -> idempotently clear the WorkspaceWindow callback             [added cleanup]
  -> later ordering cannot mutate window facts                   [added terminal result]
```

Order-off and order-on are visibility causes independent of miniaturization and
close. They do not require a separate occlusion command, but AppKit may publish
an occlusion change after the ordering callback. Close retains its explicit
forced-hidden write and shutdown path; the subclass hook only closes the
ordinary `orderOut`/`orderFront` visibility-ingress gap. Instance-bound delivery
preserves the existing one-window authority and prevents another AppKit window
from changing this workspace window's facts. Required native proof calls real
`orderOut` and `orderFront`, captures the synchronous post-order visibility
tuple before yielding, then validates eventual complete-tuple convergence and
exact cumulative delivery. Failure to observe the synchronous visibility value
is a design falsifier, not permission to add polling or an undocumented
notification.

### User close, undo, expiry, and permanent replacement

```text
CURRENT USER CLOSE
WorkspaceActionCommand.closePane/closeTab
  -> WorkspaceSurfaceCoordinator snapshot
  -> teardownView(each parent and drawer child)
     -> SurfaceManager.detach(.close)
        -> active membership removed before false/focus lookup [changed defect]
        -> SurfaceUndoEntry(expiresAt: Date + 300 s)
     -> unregisterHostedView -> ViewRegistry.unregister         [changed: cycle remains]
  -> workspace mutation removes pane/tab; workspace undo remains

CURRENT UNDO LOOKUP
restoreView(requested pane)
  -> SurfaceManager.undoClose pops global LIFO                         [removed]
  -> mismatch -> requeueUndo
     -> assigns Date + 300 s again                                    [removed defect]

Observable result: restoring a different pane can extend the mismatched
surface beyond its original exact grace and perturb its order.

PROPOSED USER CLOSE
same canonical close and per-pane traversal                     [intentionally unchanged]
  -> SurfaceManager.closeForUndo
     -> false + focus=false while exact handle is reachable      [changed order]
     -> attached -> closeUndo, retain exact ManagedSurface       [unchanged promise]
     -> exact expiry boundary and existing order/capacity        [clarified invariant]
  -> unregisterHostedView
     -> capture exact current PaneHostView                        [added]
     -> remove that host from its swiftUIContainer                [added cycle break]
     -> clear current registry slot                               [unchanged registry effect]
  -> immediate undo
     -> expire every due entry at the injected current time        [added exact boundary]
     -> select most recent eligible entry matching requested pane  [changed lookup]
     -> remove only that entry; preserve every other order/deadline[added invariant]
     -> attach exact retained surface paused                       [changed attach effect]
     -> new host around same Ghostty.SurfaceView                  [unchanged promise]
     -> projection reconcile may reveal                          [added authority]
  -> t >= 300 s
     -> remove exact undo entry and record permanent release      [changed accounting]
     -> last manager reference ends                              [unchanged ARC mechanism]
     -> after the exact host and any other strong reference end
     -> MainActor isolated SurfaceView.deinit
        -> synchronous ghostty_surface_free
        -> post-free event exactly once                           [changed isolation/accounting]
  -> workspace undo after renderer expiry
     -> create a new renderer and zmx-attach durable session      [unchanged fallback, explicit identity]

CURRENT REPAIR
executeRepair(.recreateSurface)
  -> teardownView(... shouldUnregisterRuntime: false)
  -> SurfaceManager.detach(.close)                                [removed]
  -> create replacement; every direct repair can retain old surface 300 s

PROPOSED REPAIR
executeRepair(.recreateSurface)
  -> teardownView(disposition: permanentReplacement,
                  shouldUnregisterRuntime: false)                 [changed interface]
     -> SurfaceManager.permanentlyRelease(exact surface,
                                          reason: replacement)    [added disposition]
     -> exact host cycle break + registry clear                   [added]
  -> create replacement with same canonical pane/zmx identity    [unchanged continuity]
  -> no close-undo entry, timer, or capacity effect               [added invariant]
```

`TerminalPaneMountView.restartSurface` becomes a request to the coordinator's
repair path. It no longer destroys first and then asks a second owner to tear
down the same pane. `terminateProcess` and creation rollback continue to use
explicit permanent release with their bounded disposition; neither is user
close.

## Host lifetime and the exact cycle break

The stable container is correct for temporary projection. The leak risk comes
from using that same stable topology after permanent replacement/removal:

```text
ViewRegistry.PaneViewSlot.host ──strong──> PaneHostView
                                         │
                                         │ strong lazy property
                                         v
                             ManagementLayerContainerView
                                         │
                                         │ AppKit subviews retain children
                                         └────────strong────────> PaneHostView

PaneHostView -> contentContainerView -> TerminalPaneMountView
             -> scroll/mount wrapper -> Ghostty.SurfaceView
```

`ManagementLayerContainerView.paneHostView` is weak, but that does not break
the cycle because the ordinary AppKit subview relationship is strong. Clearing
only the registry slot does not remove `PaneHostView` from
`swiftUIContainer.subviews`.

The host rule is therefore:

- temporary SwiftUI/AppKit dismantle does nothing;
- `registerHostedView` captures any exact prior host and removes that prior host
  from its superview before registering the replacement;
- `unregisterHostedView` captures the exact current host, removes it from its
  superview, clears the registry slot, then performs the existing zoom recovery
  check;
- no delayed work looks up a pane ID to decide which host to retire;
- registry replacement never decides surface close/release policy.

This covers all three clean-source `unregisterHostedView` callers: the two
fresh terminal creation paths and `finishViewTeardown`. It also covers direct
`registerHostedView` replacement by placeholders, undo remount, nonterminal
mounting, Bridge mounting, and zoom companions. The existing Bridge retirement
guard remains decisive: if the current Bridge controller differs from the
controller whose asynchronous retirement completed, `finishViewTeardown` does
not unregister the replacement. The prior host has already been retired by
exact instance at replacement time.

Tab close needs no second descendant-retirement mechanism. Its existing caller
walks each canonical parent and each parent's drawer children through
`teardownView` before removing the tab. A whole-tab registry traversal would be
duplicate policy and would create replacement races.

## Effective visibility is one conjunctive projection

`StoreVisibilityTierResolver` remains the pane projection owner but its hot
reads narrow to existing source facts:

- `WorkspacePaneGraphAtom.paneStructuralFacts(paneID)` for residency and
  parent/drawer placement instead of `WorkspacePaneAtom.pane`, which also
  derives topology and repo enrichment;
- `WorkspacePaneAtom.isDrawerExpanded(for:)` for the existing keyed drawer
  cursor;
- active-tab ID and active arrangement layout/minimized/drawer-view state from
  the existing tab owners;
- keyed zoom presentation for the active tab.

This is the narrowest existing truth, but it is not a visibility-only fact
family. `PaneStructuralFacts` also contains repo ID, worktree ID, and CWD, and
its `AtomFamily` comparator is whole-value equality. A CWD/association change
therefore legitimately wakes the visibility projection even though visibility
usually remains equal. The design accepts that transition-time MainActor
evaluation rather than adding a prohibited atom or second fact family;
`SurfaceManager` still suppresses all equal native delivery.

The existing performance recorder measures each projection evaluation with
bounded trigger class, attached count, evaluated count, changed count, equal
count, and MainActor elapsed time. A focused marker interval changes only the
canonical pane's `PaneStructuralFacts` CWD/association and must expose the
resulting observed-change evaluation. If marker-scoped evidence crosses the
repository's
MainActor budget, that is the revisit signal for an owner decision about a
narrower existing fact shape; it does not authorize a new atom/store/bus here.

`WindowLifecycleAtom.recordWindowPresentation` adds its ordinary equal-write
guard before assigning the keyed facts. This is warranted because become-key,
resign-key, initial-show, completed window ordering, miniaturization, and
occlusion callbacks can resample identical visible/miniaturized/occluded
values. Manager equality would prevent native delivery but would not avoid the
full projection evaluation. The atom remains the same owner and stores no new
state; focused behavior proves equal presentation writes do not wake observers
while a changed term does.

For an attached terminal surface, effective visibility is:

```text
managerAttached
AND paneResidency == active
AND activeTab exists
AND pane belongs to activeTab
AND (
      zoom absent and (
        layout pane is in active arrangement and not minimized
        OR drawer child whose parent is in active arrangement and not minimized,
           whose drawer is expanded,
           and which is in the active drawer layout and not minimized
      )
      OR zoom present and pane == zoom.sourcePaneId
    )
AND owningWindow.isVisible
AND NOT owningWindow.isMiniaturized
AND NOT owningWindow.isOccluded
```

The Bridge zoom companion is not a Ghostty surface. Its existing Bridge
activity/retirement owners continue to decide its retained-hidden or
retained-visible behavior. The terminal visibility projection uses zoom only
to retain draw authority for the terminal source and remove it from excluded
terminal panes.

`WorkspaceSurfaceCoordinator` binds the visibility projection to the same
explicit one-workspace-window identity pattern already used by Bridge activity
and pull-request demand. Before binding, missing window facts resolve to
`.hidden`. The design does not infer another window, and it does not add
multi-window routing.

The observer is generation-rearmed:

```text
bind/restart or attached-population callback
  -> increment observation generation
  -> withObservationTracking {
       read bound WindowPresentationFacts
       SurfaceManager.reconcileAttachedVisibility { paneID in
         manager exact collections are @ObservationIgnored
         read that pane's narrowest existing projection facts
         return effective visibility
       }
     }
  -> onChange schedules MainActor re-registration only if generation still matches
```

Manager membership is imperative and deliberately excluded from Observation,
so atom observation alone is insufficient. Every operation that actually
changes the exact attached surface/pane binding set synchronously notifies the
coordinator to restart the dependency set. That explicit callback is the sole
membership invalidation edge. A count alone is not used because a same-count
replacement changes which keyed facts must be observed; public counts remain
observable for other consumers but are not read by this projection.

One isolated evaluation-count proof distinguishes the dependency classes:

```text
manager health rewrite                    -> 0 projection evaluations
manager-local CWD/metadata rewrite         -> 0 projection evaluations
delivered-state/equal manager rewrite      -> 0 projection evaluations
exact attached binding-set change          -> 1 membership rearm/evaluation
observed pane structural-fact change       -> 1 observed-change rearm/evaluation
observed zoom-presentation change          -> 1 observed-change rearm/evaluation
observed exact-window presentation change  -> 1 observed-change rearm/evaluation
equal effective result in any evaluation   -> 0 native visibility deliveries
```

A manager-local CWD rewrite may separately cause an existing higher-level
consumer to publish a canonical pane structural fact. If that second owner
actually changes an observed `PaneStructuralFacts` value, the one pane-fact row
applies; the manager collection rewrite itself still creates no observation
edge and no duplicate evaluation.

Only currently attached membership is reconciled. Hidden and close-undo
surfaces cannot be made visible by a stale projection callback. Their path back
to visibility begins with an explicit exact-surface attach, which remains
paused until the rearmed projection decision.

## Native delivered state belongs to the exact managed surface

`ManagedSurface` gains one optional delivered value describing the last
successful host call on its current live native handle. This is renderer
resource state, not a general cache.

```text
requested visibility
  -> require exact surface still in attached membership
  -> compare with ManagedSurface.lastDeliveredVisibility
     -> equal: record suppression; return without C call
     -> changed:
        -> require non-nil ghostty_surface_t
        -> ghostty_surface_set_occlusion(handle, requested)
        -> only now store lastDeliveredVisibility = requested
        -> if false, deliver focus=false on the same live handle
```

Pinned Ghostty's `Surface.occlusionCallback` pushes a renderer-thread
`.visible` message and queues a render on every invocation; it has no equality
guard at this revision. App-side suppression must therefore occur before the C
boundary. Pinned `Thread.drawFrame` returns before drawing while its visible
flag is false. Those source facts establish the pinned boundary; required proof
still measures native delivery, lifecycle conservation, and V7 graphics
footprint plus normalized free-memory pressure rather than claiming direct
observation of exact Metal commits.

Creation makes `false` the first app-side native visibility delivery after a
valid handle is returned and before the surface is accepted into manager
ownership, attached, or displayed. Attach and move mutate membership only;
they never write `true`. Detach and close deliver `false` before
removing the exact surface from the collection through which delivery resolves.

If the native handle is missing, the manager does not update delivered state,
does not report a successful delivery, contains the failure to that surface,
and lets existing health/failure presentation handle it. Other surfaces still
reconcile.

## Focus remains subordinate to visibility

Current surface-focus writers are:

- `Ghostty.SurfaceView.becomeFirstResponder`, `resignFirstResponder`, and
  `viewDidMoveToWindow`;
- `TerminalPaneMountView.becomeFirstResponder` and `resignFirstResponder`;
- `SurfaceManager.setFocus` and `syncFocus`;
- launch-restore focus synchronization;
- pane-focus executors in the coordinator and tab controller;
- `Ghostty.AppFocusSynchronizer`, which writes app-level Ghostty focus rather
  than per-surface focus.

The smallest correction does not create a focus state owner. It makes every
per-surface `focused = true` request use the SurfaceView's weak exact-manager
requester. The requester verifies managed ID plus view identity and admits true
only while that exact instance is attached and last-delivered visibility is
true. It never looks up `SurfaceManager.shared`. False requests may remain
direct because they cannot grant draw authority. `syncFocus` uses the same
manager admission for its target and sends false to the rest.

```text
CURRENT
SurfaceView.becomeFirstResponder -> ghostty_surface_set_focus(true)  [removed bypass]
TerminalPaneMountView / tab focus -> SurfaceManager.shared           [changed routing]
launch/coordinator focus -> injected WorkspaceSurfaceManaging       [current seam]

PROPOSED
SurfaceView.becomeFirstResponder
  -> weak focusRequester(managedSurfaceID, ObjectIdentifier(view))   [added]
  -> exact creating SurfaceManager verifies reverse map + instance   [added guard]
  -> attached && lastDeliveredVisibility == true                     [added guard]
  -> ghostty_surface_set_focus(true) or bounded rejection            [changed effect]

mount, launch, and pane-focus paths -> their injected manager
  -> the same exact-instance admission                               [changed convergence]
```

When visibility becomes false, occlusion false is delivered before focus
false. A later responder callback cannot reassert true while manager-delivered
visibility remains false. When visibility becomes true, focus is not invented;
the existing responder/focus owner may subsequently request it.

Pinned Ghostty focus can restart display-link, cursor, timer, or update work.
This design prevents focus from overriding app visibility, but it does not
claim that focus=true alone commits a hidden frame. Pinned `Thread.drawFrame`
has the visibility guard. Exact commit tracing is optional only when stronger
attribution of a residual graphics anomaly is needed.

Focused proof uses two independently injected managers and surfaces: each
request must reach only its creating manager; replacing or releasing one
surface must clear its requester without affecting the other; deallocating the
manager must nil the weak link; and a missing/stale requester must reject true
without touching the native focus seam. Writer-inventory enforcement keeps
direct focus-true C calls out of SurfaceView and mount/coordinator paths.

## Renderer and host lifecycle states

The following are conceptual combinations of existing manager membership plus
the new delivered value; they are not a second enum or persisted state machine.

```text
State                         Owner             Native visibility   Legal exits
────────────────────────────  ────────────────  ──────────────────  ───────────────────────────
created/hidden/paused         SurfaceManager    false               attach, permanent release
attached/effectively hidden   SurfaceManager    false               reveal, hide, close, release
attached/effectively visible  SurfaceManager    true                hide, close, release
temporarily hidden            SurfaceManager    false               attach, permanent release
close undo                    SurfaceManager    false               immediate undo, expiry,
                                                                  explicit permanent release
released/orphan candidate     recorder algebra  no manager writer   MainActor isolated deinit
freed                         recorder algebra  native free returned terminal/post-free accounting
```

Transition invariants are:

- a true delivery is legal only from attached membership and a current
  projection result of true;
- attach never implies visible;
- temporary hide never creates an undo entry or changes its timer/capacity;
- close undo retains the exact `ManagedSurface` and is still manager-owned;
- at times strictly before close + 300 seconds the entry is eligible; at or
  after the exact boundary it is expired;
- exact-pane restore and explicit undo attach synchronously expire due entries
  before lookup, then consume only the most recent eligible matching entry;
- nonmatching entries keep their original relative order, close time, deadline,
  and expiration task; mismatch never requeues or restarts 300 seconds;
- the existing workspace undo capacity/order and the SurfaceManager's existing
  no-separate-capacity behavior are preserved;
- permanent release removes one exact manager entry at most once; a missing
  entry cannot increment release again;
- the final strong reference may end on any executor, but the exact
  `Ghostty.SurfaceView` transitions from released/orphan to freed only through
  MainActor `isolated deinit`, synchronous native free, and post-free accounting
  in that order;
- the raw native handle and unretained userdata never escape isolated deinit;
- exact-manager focus requester is weak, identity-verified, retained only while
  manager ownership exists, and cleared before permanent release;
- a pane-ID replacement does not mutate the old or new instance by lookup after
  release begins;
- process restart creates new manager, recorder, host, and renderer identities;
  only canonical workspace/zmx restore contracts cross the boundary.

The existing injected delay/clock seam is completed with one corresponding
injected notion of current time. Expiry scheduling and eligibility checks use
the same controlled source. Tests can therefore observe 299 seconds as
eligible and 300 seconds as expired without wall-clock sleeps.

## Scenario and cause matrix

`dismantleNSView` callback occurrence is marked **unproven** wherever repository
source cannot establish a framework callback for a particular transition. No
row depends on that callback for correctness.

Rows that require hidden/off-projection quiescence use deterministic projection,
native delivery/equality, lifecycle conservation, and the V7 graphics-footprint
soak. They do not claim direct observation of exact Metal command buffers.

| Scenario | Canonical mutation and projected subtree | Actual current caller/callback chain | Host / registry and manager state | Proposed renderer result and recovery | Proof seam |
| --- | --- | --- | --- | --- | --- |
| Tab switch | `selectTab` writes active-tab cursor; `PaneTabViewController` hides/shows persistent tab hosts | command/executor → coordinator → tab atom; tab observation → `updateVisibleTabHost`; representable dismantle is not expected by current focused test, broader framework behavior remains unproven | every pane host/slot persists; terminal surfaces generally remain attached | observer changes old-tab terminals to false and new-tab attached terminals to true; missing new host follows existing restore path | active-tab round trip, exact host/session identity, native delivery/equality deltas, V7 graphics footprint |
| Drawer collapse / expand | drawer cursor toggles; drawer overlay subtree removes/rebuilds visible children | action execution → `WorkspacePaneAtom.toggleDrawer`; expand currently reattaches only a chosen child; collapse has no symmetric full-surface detach; framework dismantle unproven | parent and all child hosts remain registry-owned; some children may be attached, others hidden | every attached child derives false when collapsed; expanded children in active drawer layout and not minimized derive true; hidden members require explicit attach before reconcile | multi-child drawer, canonical membership/host identity, per-child native delivery/equality, V7 graphics footprint |
| Arrangement switch | active-arrangement cursor changes; old layout subtree is replaced by new layout | action execution computes before/after sets → tab atom switch → explicit detach old / reattach new; framework dismantle unproven | detached old surfaces become hidden after false; hosts/slots remain; new surfaces attach paused | observer validates the complete resulting arrangement/minimize/drawer/zoom conjunction; only changed native results deliver | both switch directions, retained content/session, exact changed/equal delivery counts |
| Pane background / reactivate | residency/layout mutation removes or reinserts canonical pane from current layout | `WorkspaceMutationCoordinator.backgroundPane` / `reactivatePane`; background currently has no renderer detach; reactivate may create missing host | background host remains registry-owned; surface can remain attached despite no projection | structural residency false suppresses draw; reactivation true only after active layout/window truth; same surface/session returns | output produced while backgrounded and read after reveal; native false delivery and V7 graphics footprint |
| Zoom enter | keyed zoom presentation replaces normal tab subtree with source and optional Bridge companion | pane command → presentation atom; `SingleTabContent.zoomContent` resolves registry slots; framework dismantle of excluded panes unproven | source host is reused; excluded terminal hosts remain in slots; companion is Bridge-owned, not SurfaceManager | source terminal alone retains visibility; every other attached terminal in tab becomes false | source content identity; excluded-terminal delivery/equality and V7 graphics footprint; companion Bridge state checked separately |
| Zoom exit / retarget | zoom presentation clears or changes source; normal/next zoom subtree returns | tab controller writes presentation; coordinator retains/recovers companion; framework callbacks unproven | same terminal hosts remount from slots; companion retirement uses existing async exact-controller guard | old source/excluded/new source recompute from final projection; no pane-ID-delayed retirement | exit and retarget in flight, no transient true for non-result pane, host/session continuity |
| Zoom companion retirement | companion metadata/resources removed | coordinator → `retireZoomCompanionResources` → Bridge `teardownView` → exact-controller retirement | Bridge host/slot retires; no terminal SurfaceManager member exists for companion | terminal source projection is independent; replacement Bridge host survives stale retirement completion | existing zoom recovery/companion tests plus exact current-controller guard |
| Parent minimize / expand | active arrangement minimized set changes; pane leaf leaves/returns | action execution → tab atom → detach/restore/reattach; dismantle occurrence unproven | minimize moves terminal to hidden after false; host remains registry-owned; expand attaches paused | minimized always false; expand becomes true only after current conjunction | both directions, same host/surface/session, native delivery/equality and V7 graphics footprint |
| Drawer-child minimize / expand | active drawer-view minimized set changes | action execution → drawer arrangement atom → detach/reattach | child host persists; hidden membership cannot be observer-resurrected | same as parent, with parent active/visible and drawer expanded additionally required | parent-visible and parent-hidden combinations; exact child delivery |
| Pane close | workspace snapshot then pane/drawer removal | `executeClosePane` → `teardownDrawerPanes` / `teardownView` → manager close → registry wrapper | exact host cycle breaks now; exact surface moves to close undo false; slot tombstones after subtree stops rendering | no draw; immediate undo can create a new host around exact retained surface | close/undo state, host weak-release, false-before-removal, exact TTL |
| Tab close | tab snapshot then every main pane and each drawer child teardown before tab removal | `executeCloseTab` loops `tab.allPaneIds`, calls drawer teardown and pane teardown, then removes tab | all eligible surfaces enter close undo in existing order; every exact host cycle breaks; no extra descendant scan | all remain false; undo restores matching surface order or fresh after expiry | mixed parent/drawer tab, close order/capacity, every descendant accounted |
| Immediate undo | canonical pane/tab snapshot restored; active tab is selected after view restoration | coordinator undo → `restoreUndoPane` → `restoreClosedSurface(forPaneID:)` → due-expiry pass → exact matching removal → attach → new mount/host | manager reuses only the requested pane's eligible `ManagedSurface`; nonmatching entries keep order/deadline; old host is gone | attach stays false until restored projection/window decision; same renderer/session then reveals | interleaved closes for two panes, exact object identity, unchanged nonmatch deadline/order, no extra creation |
| Undo after surface expiry | workspace undo remains after SurfaceManager entry expires | exact-pane lookup expires due entries before matching; manager releases old entry; later undo → fresh `createViewForContentUsingCurrentGeometry` | old host already gone; old surface reaches deinit/free; new surface/host has new identity | new renderer zmx-attaches the existing durable session; it is never reported as reused | interleaved 299/300 boundaries, old free, new instance, durable session readback |
| Repair / recreate | repair preserves canonical pane/runtime and replaces only renderer/host | `executeRepair(.recreateSurface)` currently calls close teardown; proposed permanent-replacement disposition | old manager ownership ends without undo; exact old host cycle breaks; new host registers only after release path | old surface frees; new created-paused surface attaches and reconciles; zmx continuity preserved | 20 sequential repairs, steady manager/live population, release-before-free orphan interval |
| Launch / app restart | persisted workspace composition and durable zmx sessions are re-admitted in a new process | app boot → prepared content cohort → terminal activation/mount → launch focus tail | new registry/manager/recorder; no prior host/surface/undo identity survives | each new surface begins paused and reconciles from new-run projection; counters begin at zero | new run marker/PID, new instance IDs, durable output continuity only |
| Window `orderOut` / `orderFront` | `NSWindow.isVisible` changes independently of miniaturization and close; AppKit may subsequently co-change occlusion | public ordering enters `NSWindow.order(_:relativeTo:)`; the current concrete `NSWindow` provides no post-order controller ingress, so the presentation tuple can remain stale | hosts and manager membership remain; no session change | `WorkspaceWindow` reports after `super` returns; controller resamples all facts; order-out makes every attached result false, order-front recomputes the full conjunction; later occlusion ingress converges the tuple and equal effective results are suppressed | real `orderOut`/`orderFront` prove synchronous post-order visibility, eventual tuple convergence, cumulative exact atom/evaluation/native-delivery counts, and callback teardown; cover-window proof owns direct occlusion evidence |
| Window miniaturize / restore | `NSWindow.isMiniaturized` changes; visibility/occlusion may also be resampled | `windowDidMiniaturize` / `windowDidDeminiaturize` → controller snapshot → `ApplicationLifecycleMonitor` → `WindowLifecycleAtom` | hosts and manager membership remain; no session change | minimized makes every attached result false; restore recomputes from the complete current tuple | real miniaturize/deminiaturize independently from order-out and close; atom, native delivery/equality, lifecycle conservation, and V7 graphics footprint |
| Window occlude / reveal | `NSWindow.occlusionState` changes | `windowDidChangeOcclusionState` → controller snapshot → `ApplicationLifecycleMonitor` → `WindowLifecycleAtom` | hosts and manager membership remain; no session change | occluded makes every attached result false; reveal recomputes from the complete current tuple | real occlusion/reveal independently from order-out, miniaturization, and close; atom, native delivery/equality, lifecycle conservation, and V7 graphics footprint |
| Real display sleep / wake | assumed AppKit occlusion change; no direct sleep state | expected `windowDidChangeOcclusionState` → existing window-fact chain; callback/value is unproven until runtime | no host/manager lifetime change | if occlusion becomes true, all pause and later reconcile; if it remains visible, only the optional display-sleep claim stops with A1 falsified | optional isolated sleep/wake extension; no invented sleep channel and no effect on ordinary-path readiness |

## Permanent release and deallocation

`SurfaceManager` exposes one permanent-release operation with a bounded reason
classification. It removes the exact instance from attached, hidden, or
close-undo ownership, cancels only that instance's expiry task, clears health
and reverse lookup state, and records permanent release exactly once when an
owned instance was found. Reasons distinguish replacement, undo expiry,
explicit termination, and creation rollback. User close is not a permanent
release until expiry or an explicit permanent action removes the undo entry.

The release call does not claim deallocation. The current-to-proposed terminal
call-path delta is:

```text
CURRENT
last strong reference ends on its releasing executor
  -> plain Ghostty.SurfaceView.deinit                         [removed isolation gap]
  -> ghostty_surface_free(live handle)                       [current synchronous effect]

Observable defect: neither the MainActor UI owner nor the unretained userdata
lifetime is enforced at the native-free call boundary, and there is no ordered
post-free accounting result.

PROPOSED
SurfaceManager exact ownership removal
  -> permanent release total increments
  -> exact surface becomes an orphan candidate while any host/other ref remains
  -> last strong reference may be dropped from any executor
  -> Ghostty.SurfaceView isolated deinit executes on MainActor [changed owner/executor]
     -> ghostty_surface_free(live handle) synchronously while SurfaceView and
        its unretained native userdata are still alive         [changed guarded effect]
     -> only after the free call returns: deinitialized/free total increments
                                                               [added result]
     -> orphan gauge is recomputed and emitted immediately     [added result]
```

Host release is separately observable through an exact weak host reference.
Renderer free is separately observable through the deinit/free event. Neither
manager logs nor a `destroy` message substitutes for those boundaries. No task,
closure, queue, or recorder callback may escape the raw native handle beyond
isolated deinit.

## Run-scoped lifecycle telemetry

`AgentStudioPerformanceTraceRecorder` already owns a lock, process-scoped event
queue, OTLP performance projection, and fail-open behavior. It remains the one
synchronized metric owner for MainActor lifecycle calls and other existing
callers that may be off-main. `Ghostty.SurfaceView` free is not such an
off-main boundary: `isolated deinit`, synchronous `ghostty_surface_free`, and
the subsequent post-free observation are ordered on MainActor. The recorder's
renderer-lifecycle state is initialized to zero for each recorder/process run
and is never persisted.

The recorder lock serializes:

```text
successfulCreatedTotal
permanentReleaseTotal
deinitializedFreeTotal
activeCurrent
hiddenCurrent
closeUndoCurrent
visibilityDeliveryTotal
visibilityEqualSuppressedTotal
projectionEvaluationTotal
projectionEvaluatedSurfaceTotal
projectionChangedSurfaceTotal
projectionEqualSurfaceTotal
sampleSequence
```

Every mutation derives and emits:

```text
liveCurrent          = successfulCreatedTotal - deinitializedFreeTotal
managerOwnedCurrent  = activeCurrent + hiddenCurrent + closeUndoCurrent
orphanCandidate      = liveCurrent - managerOwnedCurrent
```

Negative orphan values are emitted as invalid evidence, never clamped. A
permanent release event can legitimately create a short orphan interval; the
release is not settled until the exact free event removes it. Exactly one
post-free observation is emitted from MainActor isolated deinit after the
synchronous native call returns. It emits a new sample under the same lock/order,
so the last sample after free cannot retain the old orphan value.

Successful creation increments by a delta of one only after a live native
surface has been accepted into manager ownership. Failed attempts do not
increment. Permanent release and deinit/free likewise emit one-event deltas.
Projection evaluations emit one-event/count deltas plus an elapsed-time
distribution under bounded `observed_change`, `membership_change`, and
`initial_bind` trigger classes. Focused canonical-pane CWD/association proof
drives the existing `PaneStructuralFacts` input alone and attributes the
resulting `observed_change` evaluation by the marker-scoped interval rather
than adding another observed fact or cache. A manager-local CWD rewrite alone
produces no projection metric event.

The OTLP metric adapter treats these labels as counters. Active, hidden,
close-undo, live, manager-owned, and orphan values are gauges and are not added
to the counter-label set. Emitting a cumulative total as a counter delta is
forbidden because it would double-count.

The trace event may carry the exact managed surface identity for local JSONL
correlation and V5 instance proof. The OTLP projection drops that field and
exports only:

- bounded event/release/retention/delivery classifications;
- aggregate delta counters and current gauges;
- existing scrubbed run marker/resource identity and `process.pid`.

The source-side allowlist and metric mapping explicitly admit only those
fields. Collector absence, rejection, or queue drop cannot block creation,
visibility, release, deinit, terminal I/O, or app launch. Missing required
series invalidates proof, not product operation.

## Failure, overlap, and recovery

```text
Failure / interleaving                 Detection             Containment and recovery owner
─────────────────────────────────────  ────────────────────  ─────────────────────────────────────
missing native handle during delivery exact-handle guard    SurfaceManager leaves delivered state
                                                             unchanged; other surfaces continue;
                                                             existing health UI owns recovery

equal projection wake                  per-instance compare  SurfaceManager suppresses before C;
                                                             records bounded suppression

manager health/CWD/delivered rewrite   ignored collection    no Observation invalidation or projection
                                                             evaluation; explicit nonprojection consumers remain

canonical pane structural-fact wake    projection metric     rearm/evaluate once; equal manager result makes
                                                             no native call

equal AppKit window resample           atom comparator       WindowLifecycleAtom rejects before observer;
                                                             no projection evaluation or native call

membership changes during observation generation mismatch  population callback restarts capture;
                                                             stale onChange task is ignored

same-count surface replacement         exact binding set     population callback re-arms keyed reads;
                                                             count is never the dependency identity

exact binding, pane fact, zoom, or     trigger/evaluation    each distinct trigger rearms/evaluates once;
window fact changes                                           equal effective results make zero native calls

orderOut with miniaturization          exact WorkspaceWindow synchronously publish isVisible=false after super;
unchanged and no close                 ordering callback     later occlusion convergence may re-evaluate but
                                                             an equal effective result makes no native call

orderFront with miniaturization        exact WorkspaceWindow synchronously publish isVisible=true after super;
unchanged and no close                 ordering callback     eventual complete tuple, including any later
                                                             occlusion convergence, decides each renderer

ordering on another window             instance-bound hook   ignored; no facts, evaluation, or native delivery

order callback overlaps close/shutdown MainActor + callback  serialized forced-hidden close remains terminal;
                                                             teardown clears callback and later ordering stops

hidden/undo pane becomes projection-   membership guard      reconcile rejects it; explicit attach is
visible in stale capture                                      the only re-entry

focus request has stale/missing owner  weak exact link       reject true; false remains fail-safe;
or wrong view identity                                        no singleton fallback

interleaved closes undo out of LIFO     exact-pane match      consume newest eligible requested pane;
order                                                         other entries retain order/deadlines

old global-pop mismatch                interface removal     no requeue path exists, so mismatch cannot
                                                             restart the protected grace

close races exact-boundary undo        MainActor + now gate  entry is either eligible before 300 or
                                                             expired/released at 300; never both

expiry timer fires late                synchronous now gate  undo/attach expires due entry before use;
                                                             exact t=300 behavior does not depend on task
                                                             scheduling latency

old Bridge retirement completes after exact controller      existing guard preserves replacement;
replacement                            comparison             no pane-ID delayed host release

replacement creation fails after old  creation result       canonical pane/runtime remain and existing
release                                                       failure/placeholder UI is shown; old release
                                                             is not rolled back into user undo

free is delayed after release          positive orphan       no false completion; operator investigates
                                                             remaining exact host/reference chain

last strong reference is dropped       isolated deinit       deinit executes on MainActor; native free returns
from an off-main task                                          before one post-free observation; replacement lives

attempt to escape raw handle from      interface prohibition no task or closure is created; SurfaceView and its
deinit                                                       unretained userdata stay alive through sync free

telemetry export fails                 sink failure          recorder is fail-open; certification fails
                                                             because series are missing

optional exact Metal trace fails       optional-tool guard   required lifecycle proof continues; only exact
or has no exportable artifact                                residual attribution remains unclaimed; no
                                                             Xcode or host-system repair is authorized

display sleep leaves window visible    A1 runtime probe      stop only the optional sleep claim and request
                                                             owner scope decision; do not add a sleep event;
                                                             ordinary projection/window readiness remains intact
```

All lifecycle, registry, projection, `SurfaceView` deinitialization, and native
free ordering is serialized on MainActor. Releasing the final strong reference
from another executor does not move the isolated destructor or its native call
off MainActor. The recorder lock still protects its state for other callers
that may cross executors; it is not the mechanism that makes deinit/free safe.
Native renderer mailbox ordering remains Ghostty-owned. App code orders
occlusion false before focus false and never follows it with an admitted focus
true while delivered visibility is false.

There is no retry loop for native visibility, release, or free. A missing
handle is a dead-surface failure, not a transient transport error. Recreating a
surface remains an explicit repair decision. There is no queue/backpressure
mechanism in the visibility path: it is latest-state projection plus immediate
distinct-until-changed application on MainActor.

## Compatibility and process cutover

This is one hard in-process cutover. There is no dual path or data migration.

- pane, tab, arrangement, drawer, zoom, runtime, zmx, and persistence formats
  do not change;
- the Ghostty pin does not change;
- internal callback and protocol shapes may change together in one build;
- a running old process and a running new process do not share renderer or
  lifecycle-counter authority;
- process restart discards in-memory renderer undo and metrics by design, then
  rebuilds from canonical workspace and durable zmx state;
- reverting the binary requires no state reconciliation because no schema or
  persisted lifecycle value was written.

## Cross-cutting realization

Reliability is owned per surface. Visibility failure cannot close or restart a
session or affect another surface. Repair preserves runtime/zmx authority while
replacing only renderer/host resources. Release claims fail closed: no exact
free evidence means not complete.

Performance is owned by the manager equality gate and narrow observation
inputs. Raw render callbacks, layout ticks, and per-frame events do not enter
the visibility path. `@ObservationIgnored` manager collections ensure
manager-local health, CWD, undo, and delivered-state rewrites do not enter it
either. A canonical CWD/association change can wake the existing whole
`PaneStructuralFacts` slot; that measured MainActor evaluation is accepted,
while native work remains limited to changed exact surfaces. Equal window-fact
writes are suppressed by `WindowLifecycleAtom` before observation.

Privacy is owned by source-side OTLP projection. Raw IDs and forensic details
remain local-only; OTLP dimensions are bounded lifecycle vocabulary plus
existing scrubbed process/run resources.

Platform compatibility is fixed to macOS 26 behavior as exercised by the
current AppKit callbacks, the `NSWindow.order(_:relativeTo:)` override boundary,
and pinned Ghostty.
Source-backed invisible draw guard, unsuppressed occlusion delivery, and
MainActor synchronous surface free are distinguished from the unproven
display-sleep callback and optional exact attribution of initial-wake or commit
behavior.

Security and accessibility require no new structure. No actor, privilege,
credential, external command, UI control, or interaction vocabulary is added.
Data lifecycle requires no persistence or schema change. Observability data is
run-scoped and follows the existing isolated debug/beta and source-side scrub
boundaries.

## How the requirements are realized and proven

| Requirement | Structural realization | Observable proof seam | Enforcement class |
| --- | --- | --- | --- |
| R1, R2, R3 | complete projection in coordinator; exact manager delivery; instance-bound `WorkspaceWindow` post-order ingress owned by the controller | deterministic projection/native-delivery behavior plus real `orderOut`/`orderFront` with synchronous visibility observation, miniaturization and close held unchanged, eventual occlusion convergence, and cumulative exact delivery; lifecycle conservation and V7 graphics-footprint/normalized-pressure slopes | interface + behavior tests + native window proof + operational soak |
| R4 | create paused, attach/order-front without unconditional true, first complete projection-derived reveal | deterministic creation/delivery order; `orderFront` resamples the complete tuple before reveal; native visibility observation and V7 graphics-footprint/normalized-pressure slopes | runtime guard + integration test + native window proof + operational soak |
| R5 | `@ObservationIgnored` manager collections, explicit exact-binding callback, and per-`ManagedSurface` delivered equality before C boundary | manager health/CWD/delivered rewrites produce zero projection evaluation; exact binding, pane fact, zoom, and window changes each rearm/evaluate once; equal effective results produce zero native delivery | observation boundary + runtime guard + metric test |
| R6 | weak exact-manager focus requester plus delivered-visibility gate | two-manager routing/lifetime tests, writer inventory, native delivery/equality counts, and V7 graphics-footprint/normalized-pressure slopes | interface + source/behavior test + operational soak |
| R7–R8 | temporary dismantle no-op; registry-owned stable host; renderer/session retained | weak/identity checks and zmx output during hidden intervals | interface + native interaction/runtime |
| R9 | exact-pane restore preserves original 300-second deadlines/order; temporary paths do not enter undo | two-pane out-of-LIFO restore and controlled 299/300 boundaries | state guard + deterministic test |
| R10 | matching eligible entry remounts same surface; expiry fallback creates new zmx-attached renderer | same/new identity, untouched nonmatch, and durable output readback | state transition + integration/runtime |
| R11–R12 | exact host cycle break; exact manager release; MainActor isolated deinit/synchronous-free terminal boundary; Bridge replacement guard | weak host; off-main last-reference drop followed by MainActor isolated deinit, synchronous native free, and one post-free accounting event; replacement survival | isolation + instance interface + lifetime integration |
| R13 | repair teardown disposition calls permanent release, never `.close` | no undo delta; 20 sequential repairs return to conserved population | interface + repeated real-renderer proof |
| R14 | recorder/manager/registry are process-run state; canonical/zmx restore only | restart produces new marker, counters, host/surface identity and durable output | process boundary + runtime proof |
| R15–R16 | synchronized recorder deltas/gauges and exact orphan algebra; post-free delta originates on MainActor only after synchronous native free | source projection/metric mapping, ordered release → orphan → isolated deinit/free → one post-free sample, every-sample lifecycle algebra, and the complete V7 run/PID-bound soak series | MainActor free ordering + lock boundary + tests + operational metrics |
| R17 | explicit OTLP allowlist; exact identity JSONL-only; fail-open recorder | projection rejection tests and collector-unavailable operation | allowlist + integration/runtime |
| R18 | ordinary window ordering ingress through the `WorkspaceWindow` override plus the distinct existing occlusion path; real sleep A1 falsifier | required ordinary-window proof exercises real `orderOut`/`orderFront`, proves synchronous post-order visibility independently of miniaturization and close, permits later AppKit occlusion convergence, and validates cumulative exact delivery; optional sleep claim separately requires one real sleep/wake and observed occlusion/result | native window proof + runtime falsifier |
| R19 | existing owners and one-window binding; no prohibited system | source/diff boundary inspection and isolated debug/beta identity | architecture/static review + runtime identity |

The proof architecture consumes V1–V8 without adding an exact-commit gate:

| Proof obligation | Required design observation | Claim boundary |
| --- | --- | --- |
| V1 effective visibility | deterministic coverage of every projection/window term and conjunction; create/attach/reveal ordering; real `orderOut`/`orderFront` with synchronous visibility observation, miniaturization unchanged, no close, eventual complete-tuple convergence, real native false delivery, and equality suppression of an equivalent later occlusion wake; lifecycle conservation; V7 graphics-footprint and normalized-pressure behavior | no direct exact Metal-commit claim is required |
| V2 session continuity | one real zmx-backed session keeps its PTY/session identity, produces output while hidden, and reveals or repairs with that output current | renderer visibility never stands in for session lifetime |
| V3 presentation continuity | native tab, drawer, arrangement, background, zoom, minimize, remount, and reveal interaction preserves every canonical pane and exact content; window proof orders the exact window off and on screen with miniaturization and close unchanged while allowing AppKit's occlusion state to converge | display sleep is not part of ordinary-window completion |
| V4 retention separation | one controlled time source proves temporary retention, immediate undo, 299-second eligibility, exact 300-second expiry, new renderer after expiry, permanent replacement, and restart | nonmatching undo entries retain original order and deadlines |
| V5 lifetime and repair | the exact retired host becomes weakly released; dropping the last old-instance reference from an off-main task causes `SurfaceView` isolated deinit on MainActor, synchronous `ghostty_surface_free`, then exactly one post-free accounting event; repeated repair reaches a conserved steady population | logical release alone is not deallocation; no raw handle escapes deinit; replacement remains intact |
| V6 no redundant work | manager-only health/CWD/delivered rewrites produce zero projection evaluations; exact binding, pane fact, zoom, and window changes each rearm/evaluate once; fleet-scale equal projection produces zero native delivery and changed delivery count equals the changed exact-surface set | exact command-buffer counts are optional attribution only |
| V7 observability and soak | source projection proves OTLP scrub; synchronized lifecycle algebra passes every sample of the fixed 20-surface Agent Studio physical/IOSurface/IOAccelerator, WindowServer, compressor, swap, and raw free-memory soak; verifier derives `free-memory pressure = -(raw free-memory bytes)` and applies the common higher-is-worse slope rule only to the normalized pressure series; final residual slopes pass | missing required series or a strictly positive lower 95% slope bound on any higher-is-worse decision series fails certification without assigning causality |
| V8 scope | current source/diff and isolated run identity preserve the Ghostty pin and exclude atom/store/bus/schema/vendor/production/multi-window/WindowServer/Xcode/host repair | no optional tool failure expands scope |

The accepted user-need identities remain covered without supersession:

```text
U1 -> R1-R4,R6,R18 -> projection owner + exact native state + V7 graphics-footprint/normalized-pressure soak
U2 -> R1,R4,R7,R8,R10,R13,R14 -> stable host/session + zmx continuity
U3 -> R4,R7,R8,R12 -> exact remount/replacement identity + native interaction
U4 -> R9,R10,R13,R14 -> controlled close-undo and process-restart boundaries
U5 -> R11-R13 -> exact host break + permanent release + deinit/free
U6 -> R3,R5,R6 -> narrow observation + manager equality/focus gates
U7 -> R11,R15-R17 -> synchronized run algebra + complete marker/PID-bound V7 metrics
U8 -> R18,R19 -> optional sleep falsifier + isolated, pin-preserving scope
```

### Proof boundaries that must be real

The deterministic projection, equality, state transition, TTL, metric algebra,
and OTLP scrub logic may use substitutable manager/native-delivery seams. The
following boundaries may not be replaced for completion evidence:

- `Ghostty.SurfaceView` construction using the pinned real renderer;
- native `ghostty_surface_set_occlusion` delivery count for changed/equal cases;
- exact `Ghostty.SurfaceView` MainActor `isolated deinit`, synchronous
  `ghostty_surface_free` while its unretained userdata is alive, and post-free
  accounting only after the native call returns;
- a real zmx-backed durable session producing output while hidden and read after
  reveal/recreate;
- a real AppKit workspace window for hide, minimize, occlusion, tab, drawer,
  arrangement, zoom, and native remount interaction, including exact-window
  `orderOut`/`orderFront` with synchronous post-order visibility, unchanged
  miniaturization, no close, and eventual complete-tuple convergence; direct
  occlusion remains separately exercised by a real cover window;
- source-scrubbed OTLP through the current marker/PID-bound shared stack;
- the fixed 20-surface V7 soak with Agent Studio
  physical/IOSurface/IOAccelerator footprint, WindowServer footprint,
  compressor size, swap use, and raw free-memory measurement plus derived
  sign-normalized free-memory pressure.

The required proof path is:

```text
controlled projection/window transitions
  -> deterministic effective-visibility and equality results
  -> real native visibility-delivery/equality counts
  -> zmx/PTY/session and native presentation continuity
  -> exact host weak release and SurfaceView deinit/free
  -> synchronized lifecycle conservation and source-scrubbed OTLP
  -> fixed 20-surface run/PID-bound graphics and system-pressure soak,
     deriving free-memory pressure as the negation of collected raw free memory
  -> residual-slope gate
```

### Optional residual-anomaly attribution

Metal System Trace, `xctrace`, or equivalent exact command-buffer tracing may
be used only as stronger attribution when required proof leaves a residual
WindowServer, Metal, or graphics-footprint anomaly. Tool unavailability,
capture/export failure, or lack of an exact commit observer limits only a claim
that the anomaly was caused at a specific command-buffer boundary. It does not
block implementation, PR readiness, or app-side lifecycle completion, and it
does not authorize Xcode, host-system, vendor, or production-state repair.

### Boundary cases and fleet certification

Required controlled-clock cases close at least two panes at different times,
restore them out of global-LIFO order, prove the nonmatching entry retains its
original order/deadline, observe eligibility at 299 seconds, exact expiry at
300, and create a new renderer after expiry. Required instance cases are
same-pane replacement, old-host release without new-host damage, and free after
expiry/replacement. The lifetime case drops the old instance's final strong
reference from an off-main task and observes, in order and exactly once,
MainActor isolated deinit, synchronous native free, and post-free accounting;
the installed replacement remains alive and unchanged. Required performance
cases include manager-only health/CWD/delivered rewrites with zero projection
evaluation, one rearm/evaluation for each exact binding, pane-fact, zoom, and
window trigger, equal projection with zero native delivery, and changed
projections whose native delivery count equals the changed surface set.
Required ordinary-window cases call `orderOut` and `orderFront` on the exact
workspace window while miniaturization is held unchanged and close is not
invoked. Each call must synchronously publish the expected visibility value,
then allow AppKit's existing occlusion ingress to converge the complete tuple.
The cumulative changed-surface/native-delivery count must equal the exact
effective-visibility delta; any later equal occlusion wake performs no native
delivery. Every renderer/session identity remains stable. Direct occlusion is
proved separately with the real cover-window scenario.

The certification workload remains exactly the Specification's V7 soak: one
fresh isolated debug or beta process with 20 zmx-backed surfaces across at
least two tabs, two arrangements, one multi-child drawer, minimized panes, and
a zoom companion; bounded initial output followed by quiescence; a 10-minute
warm-up sampled at least every 10 seconds; 20 cycles of every specified
projection/window transition; 20 sequential repairs; 10 close/immediate-undo
operations; 10 closes observed at 299 seconds and through the exact 300-second
renderer expiry; and a final 30-minute quiescent measurement window at the same
cadence.

Every sample must bind the current app PID/run marker and contemporaneous
WindowServer PID and contain the required manager populations, lifecycle
counters, orphan algebra, native visibility-delivery and equality-suppression
counts, Agent Studio physical/IOSurface/IOAccelerator footprint, WindowServer
footprint, compressor size, swap use, and raw free-memory series. The verifier
derives free-memory pressure pointwise as `-(raw free-memory bytes)` and retains
and reports both series. Missing, stale-marker, wrong-PID, negative-orphan, or
equal-delivery evidence fails certification. Off-projection surfaces must
remain visibility-false and show no app-observable renderer work or sustained
graphics-footprint growth; repair and
close/expiry populations must return to their expected conserved count with no
release called complete before free.

For every higher-is-worse decision series—each footprint, compressor size,
swap use, and normalized free-memory pressure—the verifier reports the ordinary
least-squares slope and its 95% confidence interval over the final 30-minute
quiescent window. It does not apply that common positive-growth rule to raw free
memory, whose direction is inverse. A strictly positive lower confidence bound
on a decision series is a residual growth anomaly that fails the required soak
and blocks PR readiness and app-side lifecycle completion under this program.
It does not by itself attribute the anomaly to Agent Studio or an exact
graphics boundary.

Synthetic verifier cases lock the direction before fleet certification:

```text
raw free memory constant
  -> normalized free-memory-pressure slope is zero
  -> no positive-growth failure

raw free memory increasing
  -> normalized free-memory-pressure slope is negative
  -> recovery passes the common higher-is-worse gate

raw free memory decreasing
  -> normalized free-memory-pressure slope is positive
  -> worsening fails when its lower 95% confidence bound is strictly positive
```

Display-sleep coverage is a separate optional extension. A real sleep/wake
cycle may add the same visibility, lifecycle, and graphics evidence plus the
owning-window occlusion transition. If occlusion does not change, only that
sleep claim fails and returns for the R18 scope decision; the already-proven
projection and ordinary-window result remains valid.

## Source anchors

The current ownership and call paths are grounded in:

- [`SurfaceManager.swift`](../../../Sources/AgentStudio/Features/Terminal/Ghostty/SurfaceManager.swift),
  [`SurfaceTypes.swift`](../../../Sources/AgentStudio/Features/Terminal/Ghostty/SurfaceTypes.swift),
  [`GhosttySurfaceView.swift`](../../../Sources/AgentStudio/Features/Terminal/Ghostty/GhosttySurfaceView.swift),
  and [`TerminalPaneMountView.swift`](../../../Sources/AgentStudio/Features/Terminal/Hosting/TerminalPaneMountView.swift) for the `@Observable` manager collections, renderer membership, focus, unretained native userdata, mount, release, and free;
- [`WorkspaceSurfaceCoordinator+ViewLifecycle.swift`](../../../Sources/AgentStudio/App/Coordination/WorkspaceSurfaceCoordinator+ViewLifecycle.swift),
  [`WorkspaceSurfaceCoordinator+ActionExecution.swift`](../../../Sources/AgentStudio/App/Coordination/WorkspaceSurfaceCoordinator+ActionExecution.swift),
  and [`WorkspaceSurfaceCoordinator+Undo.swift`](../../../Sources/AgentStudio/App/Coordination/WorkspaceSurfaceCoordinator+Undo.swift) for creation, teardown, close descendants, undo, and restore;
- [`ViewRegistry.swift`](../../../Sources/AgentStudio/App/Panes/ViewRegistry.swift),
  [`PaneHostView.swift`](../../../Sources/AgentStudio/App/Panes/Hosting/PaneHostView.swift),
  and [`PaneViewRepresentable.swift`](../../../Sources/AgentStudio/App/Panes/Hosting/PaneViewRepresentable.swift) for registry identity, cycle topology, and dismantle;
- [`TerminalRestoreScheduler.swift`](../../../Sources/AgentStudio/Features/Terminal/Restore/TerminalRestoreScheduler.swift),
  [`PaneStructuralFacts.swift`](../../../Sources/AgentStudio/Core/State/MainActor/Atoms/PaneStructuralFacts.swift),
  [`WorkspacePaneGraphAtom.swift`](../../../Sources/AgentStudio/Core/State/MainActor/Atoms/WorkspacePaneGraphAtom.swift),
  and [`AtomFamily.swift`](../../../Sources/AgentStudio/Infrastructure/AtomLib/AtomFamily.swift) for projection truth and whole-struct CWD/association invalidation;
- [`ApplicationLifecycleMonitor.swift`](../../../Sources/AgentStudio/App/Lifecycle/ApplicationLifecycleMonitor.swift),
  [`WindowLifecycleAtom.swift`](../../../Sources/AgentStudio/Core/State/MainActor/Atoms/WindowLifecycleAtom.swift),
  and [`MainWindowController.swift`](../../../Sources/AgentStudio/App/Windows/MainWindowController.swift) for the existing exact-window owner, complete fact snapshot, delegate ingress, and current ordinary-ordering gap; AppKit's macOS 26.2
  `NSWindow.h` declarations for `orderOut:`, `orderFront:`, and
  `orderWindow:relativeTo:` define the public ordering boundary realized by the
  added `WorkspaceWindow` override;
- [`AppKit/SwiftUI Architecture — Swift 6 Concurrency`](../../../docs/architecture/hosting/appkit_swiftui_architecture.md#swift-6-concurrency)
  establishes the repository's Swift 6.2 `isolated deinit` rule for MainActor
  UI owners;
- [`AgentStudioPerformanceTraceRecorder.swift`](../../../Sources/AgentStudio/Infrastructure/Diagnostics/AgentStudioPerformanceTraceRecorder.swift),
  [`AgentStudioOTLPPerformanceMetrics.swift`](../../../Sources/AgentStudio/Infrastructure/Diagnostics/AgentStudioOTLPPerformanceMetrics.swift),
  and [`AgentStudioOTLPTraceProjection.swift`](../../../Sources/AgentStudio/Infrastructure/Diagnostics/AgentStudioOTLPTraceProjection.swift) for synchronized metrics and scrubbing;
- pinned Ghostty `include/ghostty.h`, `src/apprt/embedded.zig`,
  `src/Surface.zig`, and `src/renderer/Thread.zig` at
  `332b2aefc6e72d363aa93ab6ecfc86eeeeb5ed28` for synchronous surface free,
  occlusion/focus delivery, and the invisible draw guard.
