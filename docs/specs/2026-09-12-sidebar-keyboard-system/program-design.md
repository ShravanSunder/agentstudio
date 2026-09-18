# Keyboard sidebar program design

[Requirements](../../wip/2026-09-11-keyboard-navigation/requirements.md) → [Specification](specification.md) → this structural design.

## Existing owners, actual focus

The existing App shell moves native focus; the existing RepoExplorer host owns list
interpretation; the detached projection produces navigation metadata. The table renders
selection and scroll, and catalog-derived overlays show the available keys. Committed
pane activation retains the reviewed arrangement path.

    App shell / MainSplitViewController
      owns: sidebar visibility and weak native return target
      calls: stable sidebar host focus; existing active-pane fallback
        |
        v
    RepoExplorerMaterializationHost (full-size, survives empty results)
      owns: native list responder and selected RowID
      consumes: accepted snapshot navigation metadata, local action descriptors
      calls: materializer select/scroll; existing table interaction callbacks
        |                                  |
        v                                  v
    Table / hosted cells               Existing dispatcher / pane focus
      renders selection + hints          owns target authority and reveal
        ^
        |
    Detached projection worker
      owns filter/group/order/navigation-index derivation
      publishes through existing generation/baseline handshake

    Core command catalog -> context-exact shortcut/display projections
    SharedComponents     -> stateless keycap and existing selected-row paint

No new atom/store, event, coordinator, persistent focus mode, or global chord engine.
Local UI interaction state holds selection/focus reporting, not a second KeyboardOwner.

## Responsibility and interface boundaries

MainSplitViewController captures origin on entry from outside the sidebar. It retains
it weakly for the window lifetime and restores it on Escape/hide when still usable.
For a shared field editor, record the owning text control where identifiable rather
than the reusable NSTextView; otherwise fall back to active pane. Repeated sidebar
focus and list/filter switches never replace the origin. The existing bounded focus
request handles host attachment; cancellation/hiding cancels that pending request.

RepoExplorerMaterializationHost accepts first responder while attached and visible.
Its local keyboard state survives content/rowless child replacement. It handles
catalog P/R/F and UI-local arrows/Enter/Escape/digits; content-dependent actions are
no-ops when no accepted content exists. Calls to select/scroll are synchronous and
consume prepared indexes, never a full projection. It rejects ingress unless the
window's actual first responder is itself and effective routing is stable sidebar.
Management, transient surfaces and existing organization popovers suppress ingress.

The feature-local observable interaction value holds a weak host attachment and reports
list/filter/none to the header and existing sidebar-focus publication. Region changes
are tied to real responder/field focus callbacks. A delayed filter resignation clears
only a still-filter-owned region, never newly acquired list focus; actual host focus
wins over a late filter callback. Shell hidden/disposed state clears publication.
The old 1x1 RepoExplorerFocusBridge no longer acts as a list target.

The table materializer owns native selected-row application and scrolling, while its
accepted snapshot is the only data authority. Native selection changes cannot open
rows by themselves. Existing mouse callbacks keep their activation semantics. Hosted
cells receive local selection/hint values separately from row content revisions, so
moving selection does not invalidate content/height caches or force projection work.

## Call-path cutover

    Changed R-S1:
      CmdS -> old showReposSidebar
           -> toggleSidebar -> shell visibility only + actual return if hiding
      CmdShiftS -> old toggleSidebar
                -> new focusSidebar -> Management guard -> reveal -> host responder

    Changed R-S2/R-S3:
      shell focus/filter -> old invisible proxy
                         -> stable materialization host / existing filter callback
      filter onSubmit: old no-op -> preserve query -> make host first responder
      filter Escape: old clear+pane return -> preserve query -> list

    Added R-S4/R-S5:
      host keyDown -> descriptor/context gate -> accepted navigation index
                  -> selected RowID -> table select/scroll
      Enter/digit -> exact accepted row identity -> existing interactions
                  -> worktree AppCommandDispatcher OR targeted pane focus
                  -> authoritative action/reveal operation -> actual native focus
      stale/missing identity -> no operation; no next-row substitution

    Intentionally unchanged:
      pointer row -> existing interaction/dispatcher -> validated target owner
      worker -> candidate/baseline handshake -> accepted materialization generation
      pane focus -> PaneCommittedFocusOperation -> concurrent policy
                 -> select/switch/drawer effects -> revalidate -> exact focus

The table interaction interface already carries onFocusPane/onCommandRequest/
onToggleGroup. Extend it with an explicit desired group-expansion request for
directional keys. Keyboard activation builds the same worktree open request and uses
those callbacks from accepted row data; it does not require a mounted row slot. The
first-nine result may be outside the viewport. Current command authority is checked
by the existing dispatcher; a stale cached row never grants mutation permission.
Mouse cells retain their binding/reuse/command-generation guards.

## Navigation metadata and live changes

The existing detached snapshot construction adds immutable navigation metadata:
selectable row IDs, first destination, next/previous, parent/first-child relationships,
first-nine destination IDs and row-to-number lookup. Group headers are selectable but
not numbered. Section/activity labels, loading, faults and unresolved rows are omitted.
No row data is duplicated in a parallel store; reuse rowIndexByID and accepted rows.

A native RowID is a presentation coordinate, not stable destination identity: it
includes the group for worktrees and several pane representations. The worker also
indexes destination keys, using existing pane UUIDs and worktree UUIDs, to their row
IDs in current result order. Include associated, tab-owned and unassociated pane rows
under the same pane key. Group headers retain their group identity rather than gaining
a synthetic destination.

The worker's update-plan construction prepares selection reconciliation against the
accepted old and new snapshots. For each prior selectable RowID, first retain that
row when it survives; otherwise resolve its prior pane/worktree destination to the
new RowID. If multiple representations exist, prefer the surviving exact row, then
the first representation of that same destination in new result order. Thus pinning,
regrouping, activity-bucket changes and association changes retain the selected target.
Native RowID equality/hashing and materialization ownership remain unchanged.

Only when the destination is absent does reconciliation apply removal fallback:
the next surviving selectable destination/group in prior order, else predecessor,
else the new first destination/group. Translate surviving destinations to their new
RowIDs before building that successor/predecessor lookup. Section labels never become
selection. This remains detached update-plan work; the host keeps one selected RowID
and applies the prepared reconciliation lookup after candidate acceptance. No second
selection store or per-key list scan is introduced, and no fallback activates.

Membership, content and rowless transitions are admitted by existing lifetime, demand
epoch and visible-generation checks. A key captures the accepted target identity at
its handling point; later projection cannot reinterpret its digit. Badges consume that
same accepted mapping, not requested/published-but-unaccepted rows. Equal projection
must preserve navigation equality; native update validation covers new metadata.

## Local state transitions and failure

    outside -- successful focus --> list -- F --> filter
       ^                             ^             |
       | Escape / hide               +-- Enter/Esc-+
       +-----------------------------+

    list content -- accepted empty --> list rowless
    list rowless -- accepted content --> list with initial selection
    any local state -- detach/window loss --> no list eligibility

Vertical arrows change selected identity only. Directional group expansion uses
an idempotent set-expanded request at the existing sidebar cache owner; mouse and
Enter retain intentional toggle. Repeated Right while a new projection is pending
therefore cannot accidentally collapse the group. Filtering keeps its existing
expansion guard. No pending expansion state or second group-state owner is needed.
A pending projection does not move focus away from the stable host. First responder
failure leaves actual ownership unchanged; the bounded shell retry either succeeds
or ends without claiming focus. Closing origin uses active-pane fallback.

Target removal between key and queued action is rejected by existing dispatcher and
committed-focus validation. A target whose reveal partially changed the workspace is
not blindly rolled back; existing action semantics remain authoritative. The list
does not explicitly return to origin after Enter, which would race successful async
activation. It loses ownership when the actual destination receives focus.

## Catalog and overlays

Add focusSidebar as a shell command with exhaustive interactive and IPC classification;
its interactive window-local focus action has no accidental generic headless exposure.
Rebind toggleSidebar to CmdS and focusSidebar to CmdShiftS. Reuse showPanesSidebar,
showReposSidebar and filterSidebar for P/R/F in sidebarList context. Filter keeps its
existing global binding. Local list navigation has one typed action/shortcut descriptor
for interpretation, accessibility and display; no handwritten duplicate key strings.

Make AppShortcut display selection exact and optional for the requested context.
Menus, command bar and general tooltips request global; sidebar hints request
sidebarList. Do not let current primary-trigger fallback leak P/R into NSMenuItem
key equivalents. Preserve emptyDrawer's existing raw P alternate and all other contexts.

The existing SidebarEntityToggle/segmented-control primitive receives optional resolved
shortcut display per segment. Shared keycaps overlay existing control bounds, never
intercept pointer events and do not duplicate accessibility elements. Numbered row
keycaps overlay the leading identity-icon column, preserving title, pins and chips.
The single catalog-backed focus glyph occupies existing leading space in repoToolbarRow.
It and list hints follow effective list eligibility; no new header or help strip.

Leaf selection uses SidebarRowShell's existing isSelected paint. Group header selection
uses the same style through its existing shared header. Native selection/accessibility
remains accurate without competing native and SwiftUI selection paint. Active-pane
play-chip status remains separate. Old/new visible cell chrome updates only; no layout
poll, list-sized anchor scan or output observer is introduced.

## Direct pinned navigation

App command ingress runs previous/next pinned actions through the existing gesture
sequence. At operation start capture the current origin and raw COW pane/tab/activity
state, repository topology snapshot, stored tab order, Panes preference scalars and
reference time. MainActor performs no location enumeration, pin filtering, dictionary
join, title normalization or sort. Add narrow read accessors over existing raw storage,
not new atoms or stored properties. This follows CoreTabBarProjection's capture/derive
separation without reusing its unnecessarily broad snapshot.

RepoExplorer owns the focused detached projector and shared pane organization policy.
Factor that policy from organizedContent so both full sidebar and pinned navigation
consume the same grouping/subgroup/leaf comparator. The focused path stops before
rows, enrichment and materialization. It ignores query, collapse, surface and showsPinned.
All active tab-owned content kinds and drawer members remain eligible.

    terminal shortcut -> App gesture sequence -> raw capture (MainActor)
                      -> focused projector (detached)
                      -> candidate pinned ID
                      -> fresh pin/ownership check (MainActor scalar reads)
                      -> existing non-enqueuing committed-focus operation
                      -> success/failure -> next queued navigation

Do not enqueue and await another gesture from inside the gesture queue. Fresh target
checks reject stale/unpinned candidates without substitute. Sequential keys resolve
from the preceding successful result rather than concurrently from the same old origin.
Empty set is no-op; wrap and absent-origin first/last behavior follow the Specification.
No hidden sidebar adapter demand, activity/history stack or extra persistent cache.

## Visible horizontal pane movement

Normal Option-J/L retains the existing synchronous command and focus path. The
App controller obtains eligibility from WorkspaceArrangementViewDerived, which
already owns active residency, arrangement minimization and Management visibility.
Main-pane movement uses activeVisiblePaneIds; drawer movement uses drawerVisiblePaneIds.
Layout's neighbor lookup accepts that eligibility set and scans in the requested
direction to the first eligible pane. DrawerGridLayout passes eligibility through
to the containing row for horizontal movement; rows are never collapsed or re-paired.

    Option-J/L -> current main/drawer scope -> existing visible-pane projection
               -> eligible neighbor in canonical row -> existing focus trigger
               -> selection + existing content-specific responder policy
    no eligible neighbor -> no trigger -> unchanged focus and visibility

This replaces canonical immediate-neighbor targeting for normal horizontal commands.
It does not enter PaneCommittedFocusOperation or its explicit arrangement reveal.
Existing next/previous cycling, ordinal reveal, drawer Up/Down and Management commands
retain their policies. Eligibility is content-kind independent, including Bridge.
Existing main-row keyboard focus selects nonterminal destinations while preserving
their native responder policy; this visibility correction does not redefine it.
Native responder assertions cover terminal main panes and drawer hosts. Explicit
sidebar activation continues through its separate committed-focus path.

No state, observer, cache, bus signal or async hop is introduced. Reuse the existing
projection rather than duplicating residency/minimization rules in App or deriving
a new renderer grid. The remaining bounded row scan belongs to direct key/focus
dispatch, permitted by the existing EventBus admission table; it neither captures
nor projects the sidebar. The tradeoff is one current local visible-set capture per
capability/execution query rather than a new invalidation-sensitive navigation cache.

Proof covers skipped intervening minimized/backgrounded panes in both directions,
no-neighbor no-op, actual native focus, unchanged arrangement/drawer expansion and
preserved explicit reveal. General detached-drawer renderer repair remains deferred.

## Quality and proof boundaries

All input is local keyboard/UI identity; no new external transport or persisted format.
AppCommandDispatcher and current focus action retain authorization. IPC classification
must be exhaustive, not inherited from UI visibility. Text fields remain text owners.
No typed text or pane content is newly logged; performance markers carry counts/durations
and existing bounded identifiers under the current scrub rules.

| Contract | Owner and proof seam |
| --- | --- |
| R-S1/R-S2/R-S3 | Real MainSplitViewController window + stable host + shared field; observe actual responder through empty/filter/hidden/Management transitions and origin-control reuse |
| R-S4/R-S5 | Pure snapshot/update policy plus real host/materializer/dispatcher integration; accepted-generation digits, destination continuity across regroup/pin/activity/association changes, true removal fallback, offscreen ninth result, group moves and exact pane/worktree actions |
| R-S6 | Native shared controls/hosted rows at narrow and ordinary widths; inspect selection, icon-column overlays, no reflow/click interception, accessible selected row |
| R-S7 | Exhaustive catalog/context/menu/display and terminal/empty-drawer regressions; main/drawer Option-J/L skip minimized/backgrounded neighbors, retain row scope and native focus at edges, preserve arrangement/visibility and explicit reveal |
| R-S8 | Existing performance probe: separate raw capture, detached navigation projection, native selection/apply; demonstrate no full-capture increment on row motion |
| R-S10 | Pure focused/full ordering equivalence and real gesture/reveal integration with hidden sidebar, mixed panes, stale pins and sequential commands; capture/derive timing proof |

Mocks may replace external filesystem/runtime dependencies in pure policy tests, not
native responder transitions or the interaction under test. Native journey proof must
exercise the actual app after source passes, including editor text isolation and the
marked overlay placement. Existing architecture lint enforces module boundaries;
Sendable DTOs and concurrent worker entry enforce derivation separation.

## Held preview composition and ownership

R-S9 is realized as one window-local transient presentation value owned by
`MainSplitViewController` in the existing App composition. The controller already
constructs the sidebar and one
`PaneTabViewController` for the window (`MainSplitViewController.swift:76-199`). The
value is an `@MainActor @Observable` local UI owner, injected into that controller's
existing persistent tab-content roots. It is not an atom, store, workspace mutation,
domain event, or durable focus target.

`MainSplitViewController` passes the same reference to `PaneTabViewController`; the
tab controller passes it from `buildTabContentHost` into every `SingleTabContent`.
The App composition also supplies that reference to the existing
`WorkspaceSurfaceCoordinator` renderer-visibility binding and Bridge-activity
observation. `PaneTabViewController.observeForTabSelectionState` reads the reference
alongside its existing tab facts and re-runs `updateVisibleTabHost` through the same
observation rearm. `observeRendererVisibility` and
`observeBridgePaneActivityInputs` read it inside their existing
`withObservationTracking` closures, so each transition re-arms those loops. No new
coordinator, event, poll, timer, or observation family is introduced.

The sidebar remains the input owner. `RepoExplorerMaterializationHost` is the native
list responder and owns the accepted selected row (`RepoExplorerMaterializationHost.swift:6-72,
408-508`). Its existing `RepoExplorerKeyboardInteraction` callback seam reports
Space down/up, selected pane target changes, focus loss, and pre-commit invalidation
through `RepoExplorerView` and `SidebarSurfaceHost`; App composition owns the
presentation transition. Space is a transient gesture and does not become an
`AppCommand`. Enter and digits continue through the existing activation callbacks.

The presentation owner carries only the transient session and validated target:

```text
HeldPanePreviewState
  idle(nextGeneration)
  held(generation, requestedTarget: optional ValidatedPanePreviewTarget)
  suppressedUntilSpaceRelease(generation)

ValidatedPanePreviewTarget
  paneID, owningTabID, provider/session identity captured for validation

HeldPanePreviewPresentation (same owner)
  requestedTarget: optional ValidatedPanePreviewTarget
  presentedTarget: optional target whose presentation mount is ready
```

`held.requestedTarget` and `held.presentedTarget` are separate values in that same
window-local owner. The requested target follows the selected row immediately;
the presented target is set only after its existing presentation mount is ready.

`target == nil` is meaningful while held: a selected group or worktree keeps the
canonical presentation visible. A requested pane target is validated against current
workspace membership, owning tab, and provider/session identity before preparation.
Its presentation is consumed by the initiating window's matching tab host only when
the presentation mount is ready; the host may be absent while existing preparation
runs. Terminal readiness means an attached usable terminal mount; Bridge and other
nonterminal readiness means an installed mount/controller, after which product
content may continue loading through its normal owner.
Each preparation or host callback carries the held generation and exact requested
target identity; late callbacks can remain warm but cannot publish an older or
different target.

The current application has one `AppDelegate.mainWindowController` at a time and
replaces/shuts the old controller when recreating the main window (`AppDelegate.swift:198-205,
491-500`). Each controller has a `workspaceWindowId` and a per-window persistent
tab-host tree (`MainWindowController.swift:20-105`; `PersistentTabHostView.swift:6-31`),
while `ViewRegistry` slots are pane keyed. The supported current path therefore has
one initiating workspace window and one matching `PaneTabViewController`; U15's
all-pane scope is not narrowed by a hypothetical second window.

Current source has no simultaneous main-window path or pane-to-window owner for a
cross-window target. The current one-window composition therefore supplies the only
source/target window path in this slice; no second host or shared-slot reparenting is
introduced.

## State transitions and the sole presentation branch

The held-session lifecycle is:

| State/transition | Guard and owner action | Resulting presentation |
| --- | --- | --- |
| `idle` → `held(g, requestedTarget?)` | Arrow selection while the actual first responder is the eligible list; mint one generation and resolve the current selected row | Canonical set until the requested pane's presentation mount is ready; a non-pane request stays `nil` |
| `held(g, requestedTarget?)` → `held(g, requestedTarget?)` | Accepted selection or snapshot reconciliation replaces the requested target; clear the presented target until the new presentation mount is ready; Space autorepeat does not mint `g+1` | The requested target with a ready mount replaces the presented set; `nil` returns to canonical presentation |
| `held(g, requestedTarget)` → `suppressedUntilSpaceRelease(g)` | Enter or digit invalidates the requested and presented targets synchronously before invoking its existing activation effect | Canonical presentation while `PaneCommittedFocusOperation` owns committed reveal/focus |
| `held`/`suppressed` → `idle` | Matching Space key-up, list focus loss, host detach, sidebar hide, Management/transient takeover, window resign, or window close | Current canonical presentation; no durable rollback |
| any held target → canonical | Pane removal, stale generation, provider/session mismatch, missing bounds, or preparation failure | No substitute row/pane; the canonical set remains visible |

`SingleTabContent` currently selects exactly one Zoom or ordinary arrangement branch
(`SingleTabContent.swift:75-129`). Add the preview branch before those branches only
for the presentation's `owningTabID` and only when the presented target's mount is
ready. It
reads the target's existing `viewRegistry.slot(for:).host`; a missing or unusable
mount keeps canonical content visible until the existing owner registers an actual
mounted host. Once the mount is ready, the branch renders that host's one stable
`swiftUIContainer` through `PaneViewRepresentable`, preserving the existing slot/host/container custody
(`ViewRegistry.swift:68-90, 240-289`; `PaneViewRepresentable.swift:16-42`). Preview
does not become a keyboard owner; existing pane hit behavior remains unchanged. If
an existing pointer interaction changes the first responder, the same responder-loss
cancellation path invalidates preview. There is no click-to-commit behavior.
The held-preview affordance reuses the existing compact keycap presentation and inserts
no Space hint to pane-row metadata/chip composition; held preview remains an input-only
no header row, help panel, or workspace dimming.

The prior Space keycap display path is removed; `LocalActionSpec.previewPane` remains the input owner without a row-local presentation. Numbered hints remain right-aligned through existing row presentation and recency remains in composition. Worktree rows do not gain preview affordances. The old preview shortcut display and trailing overlay paths are removed together.

`RepoExplorerPaneRowContent` keeps the numbered keycap in its existing right-aligned row presentation
(`RepoExplorerPaneNavigation.swift`, `RepoExplorerPaneRowContent.body`), while
`SidebarShortcutHint` remains fixed-size, accessibility-hidden and non-pointer-interactive where used elsewhere. No Space affordance consumes row width, changes row height, hides recency, or changes input eligibility; the pane row retains existing alignment and dense metadata behavior.

The preview branch also participates in the existing rendered-surface union. It
registers a stable preview surface identity with
`viewRegistry.surfaceRenderedIds(_:ids:)`, reports the current presented target, and
updates that set on target replacement. When the branch leaves, it calls
`unregisterSurface(_:)`; stale or removed targets therefore leave the union before
their slot can be retired. This reuses the existing tab, drawer, and Zoom
registration pattern and adds no parallel custody ledger
(`ViewRegistry.swift:290-341,403-413`).

The custody invariant remains one pane identity → one `PaneViewSlot` → at most one
`PaneHostView`/stable container and one live branch; an overlay or second representable
is not permitted.

## Existing-pane preparation and trusted full-area geometry

Preview preparation adds one narrow App-facing entry at the existing
`WorkspaceActionExecutor` → `WorkspaceSurfaceCoordinator` mount owner. It validates
the pane, provider/session identity, and owning tab. A slot is usable for a terminal
only when it contains a `TerminalPaneMountView` with a surface that is actually
attached to `SurfaceManager`; `slot.host` alone is insufficient because a host can
refer to a surface in `hiddenSurfaces` (`SurfaceManager.swift:321-360`;
`SurfaceManager+RendererState.swift:84-107`). It does not mutate the workspace graph
or claim prepared custody. `ViewRegistry` remains the sole
`pending`/`deferredGeometry`/`mounting`/`completed` ledger.

For a cold or released target, capture only the current requested target's pane,
owning tab, provider/session identity, held generation, and trusted non-empty
`terminalContainerBounds` on MainActor. That bounds value is the real full-area
`initialFrame`; preview initialization performs no active-arrangement, drawer-layout,
or all-tab frame derivation. A pane that is absent from the active custom layout,
including a drawer child whose parent is absent from that layout, receives the same
full-area frame. The result is accepted only when the exact current pane,
owning tab, generation, provider/session identity, and captured bounds still match;
a non-empty check or hold generation alone is insufficient because selection changes
share the hold generation.

Cold targets enter `createViewForContent(pane:initialFrame:)` directly through the
existing surface coordinator, without relying on `restoreVisiblePaneIfNeeded` or its
durable active-tab gate (`WorkspaceSurfaceCoordinator+ViewLifecycle.swift:55-118`;
`WorkspaceSurfaceCoordinator+ViewHelpers.swift:128-174`). The existing prepared
visibility signal is recorded with `currentVisibleQueuedSet(includingAtLeast:)`
before any deferred geometry requeue, preserving the revision-before-await ordering
in `reevaluatePreparedTerminalGeometry()` (`WorkspaceSurfaceCoordinator+ViewLifecycle.swift:755-803`).
The current requested target, rather than the currently presented target, remains in
that existing `preparedContentVisibilitySignalHandler` input while it is preparing;
canonical presentation remains visible until the presented target's mount is ready. A
selection replacement updates the requested target in the same held generation and
refreshes that existing `currentVisibleQueuedSet(includingAtLeast:)` input. No new
queue or cache is introduced.

For an already-created terminal whose surface is hidden, the same coordinator's
existing reattachment owner performs `surfaceManager.attach(surfaceId, to: paneId)`
and `terminal.displaySurface(surfaceView, geometryVerificationReason:)` as in
`reattachForViewSwitch` (`WorkspaceSurfaceCoordinator+ViewLifecycle.swift:534-560`),
but preview does not first invoke the active-tab-only restore step. Reattachment is
the only transient change; there is no preview-acquired attachment rollback ledger.
The attached resource may remain warm after release while canonical visibility hides
it as needed. General detached-drawer renderer repair remains deferred.

Released terminal content uses normal restore with `treatAsRestoredSessionStart: true`;
if the old zmx endpoint has ended, the standard attach command may create a fresh
shell under the same durable pane/session identity (`TerminalRestoreRuntime.swift:25-42`;
`ZmxBackend.swift:177-204`). No attach-only zmx operation, vendor change,
or new pane identity is required; a fresh shell under the same identity is allowed.
Bridge, Webview, and CodeViewer
targets use their existing nonterminal mount owners. A late mount after release may
remain registered and warm, but only the current presented target can render it.

After the stable host enters the preview branch, the persistent tab host fills the
full `terminalContainer` by the same fill pattern as the canonical
`PaneLeafContainer`: `PaneViewRepresentable` receives
`.frame(maxWidth: .infinity, maxHeight: .infinity)` before the host's normal layout
(`PaneLeafContainer.swift:238-248`; `PaneHostView.swift:72-91`).
`TerminalPaneMountView.layout` and `forceGeometrySync` remain the native allocation
and report/verify seams (`TerminalPaneMountView.swift:192-228`). The full-area result
is a proof obligation, not a claim of current native proof. Bridge remains edge-pinned
through its existing mount view and needs no second geometry model.

## Presentation, renderer, and Bridge call-path delta

The preview behavior has no current end-to-end predecessor. The following compact
delta pairs each source-anchored current path with the proposed path and names the
preserved owners:

| Behavior | Current source path | Proposed path and delta |
| --- | --- | --- |
| Space/selection input | `RepoExplorerMaterializationHost.keyDown` → `handleListKeyboardAction` → selection/activation; no Space key-up or semantic target callback (`RepoExplorerMaterializationHost.swift:57-72, 408-508`) | **Added:** host key-down/up and selection reconciliation → existing keyboard callback chain → window-local requested target. The current requested target keeps the existing prepared visibility signal while the presented target waits for a ready mount. **Changed:** Enter/digits invalidate preview before the unchanged activation effect. Sync callbacks; exact target and generation checks reject stale results. |
| Pane presentation | `PaneTabViewController.buildTabContentHost` → `SingleTabContent` → Zoom or ordinary arrangement (`PaneTabViewController.swift:1241-1284`; `SingleTabContent.swift:75-129`) | **Added:** injected presentation → owning-tab preview branch → slot host → one stable representable. **Changed:** `updateVisibleTabHost` selects the preview owning tab while its mount is ready. **Unchanged/preservation-critical:** Zoom/ordinary mutual exclusion and `ViewRegistry` slot custody. |
| Cold existing pane | `restoreVisiblePaneIfNeeded` requires durable active tab, resolves all-tab frames, then `createViewForContent` (`WorkspaceSurfaceCoordinator+ViewHelpers.swift:128-174`) | **Added:** target/provider/session validation → trusted bounds and identity capture → existing full-area preparation/custody owner → slot registration. **Changed:** preview uses the current full `terminalContainerBounds` directly and does not use active-tab restore or per-layout frame derivation; the requested target remains in the existing prepared visibility signal while pending. **Unchanged:** `createViewForContent` terminal/nonterminal authority and error return. |
| Hidden terminal surface | `reattachForViewSwitch` restores through the active-tab helper before calling `SurfaceManager.attach` and `TerminalPaneMountView.displaySurface` (`WorkspaceSurfaceCoordinator+ViewLifecycle.swift:534-560`) | **Added/changed:** preview's existing-pane preparation calls the same attach/display owner for a validated hidden surface without the active-tab restore step. **Unchanged/preservation-critical:** `SurfaceManager.attach` moves the surface to `activeSurfaces`; release leaves the attached resource warm and canonical visibility controls delivery. |
| Terminal visibility | `bindRendererVisibility` → observation-tracked canonical visibility tier → `SurfaceManager.reconcileAttachedVisibility` (`WorkspaceSurfaceCoordinator+RendererVisibility.swift:30-69`) | **Changed:** same observer reads the presentation and chooses canonical visibility while the requested mount is preparing, then the exact ready-target replacement, never their union. **Unchanged/preservation-critical:** owning-window visible/non-miniaturized/non-occluded guard, reconciliation owner, equality suppression, and `effectiveRendererVisibility`. |
| Bridge activity | `captureBridgePaneActivityInputs` → `BridgePaneActivityCoordinator.update` → controller activity (`WorkspaceSurfaceCoordinator+BridgePaneActivity.swift:90-190`; `BridgePaneActivityCoordinator.swift:63-102`) | **Changed:** add the explicit transient structural presentation input through the existing owner; a ready, installed, active-residency target uses normal foreground admission, covered installed peers become `loadedHidden` like Zoom, and closed/dormant/no-controller/inactive authorities retain their stronger guards. **Unchanged:** activity coordinator, existing work-admission token, and controller application owners; no privilege bypass or new refresh mechanism. |
| Uncommitted release | No preview lifecycle exists | **Added:** matching key-up or existing responder/demand/sidebar/Management/window lifecycle ingress → one local generation invalidation → current canonical presentation → renderer/Bridge canonical projections. Warm completion is retained but cannot publish. |

The target presentation precedence is exact:

```text
idle / held(requested=nil) / suppressedUntilSpaceRelease -> canonical presented set
held(requested=P, presented-ready=P)                      -> presented set exactly {P}
held(requested=P, presented-ready=nil while preparing)    -> canonical set until P's mount is ready
```

For terminals, the owning-window gate is evaluated first; an occluded,
miniaturized, or hidden window remains renderer-hidden even when a preview target is
held. `SurfaceManager.reconcileAttachedVisibility` remains the only Ghostty
visibility delivery owner (`WorkspaceSurfaceCoordinator+RendererVisibility.swift:31-53`).
For Bridge, the transient fact is an explicit input to the existing activity
projection. While a target with an installed mount is presented, that target is foreground and every
other Bridge pane is `loadedHidden`; held-without-target, preparation, suppression,
and release use canonical facts. The input does not falsify residency, active-tab,
arrangement, drawer, or minimization facts and does not add window occlusion to
Bridge's established activity contract. Keeping a covered canonical foreground
peer foreground would contradict the existing Zoom-style structural exclusion:
content that no longer occupies the presented place must not continue foreground
refresh work. The preview input therefore uses the same existing activity/admission
owner, with no focus-, browser-, or window-based foreground bypass. The existing
`isAuthorityClosed`/closed and dormant latches, controller-installed check, and
active-residency guard run before the transient presentation branch; a missing or
inactive authority is never promoted merely because it is selected.

## One local cancellation transition

`MainSplitViewController` owns the window-local `cancelIfHeld` transition beside
sidebar composition. Existing ingress owners call that one transition: the
materialization host's `RepoExplorerKeyboardInteraction.listDidResignFirstResponder`
and `detach`, `RepoExplorerView`'s `isProjectionDemanded` loss callback,
`MainSplitViewController.collapseSidebar`, `PaneTabViewController`'s existing
Management/transient-surface observation plus the `canInterpretListInput` routing
gate, and `MainWindowController.windowDidResignKey`.
The callback chain passes no new event; each path synchronously invalidates the held
generation and clears the presented target. `windowWillClose` already invokes
`shutdown`; teardown of the local owner is sufficient and does not need a second
close callback. The next window receives a fresh local presentation value.

## Failure, ordering, and custody rules

- **Generation wins.** One Space hold mints one generation. Autorepeat is consumed;
  selection replacements and all preparation, host, renderer, Bridge, and geometry
  callbacks compare that generation before publishing.
- **Current structure wins.** Before preparation and before presentation, validate
  pane membership, provider/session identity, owning tab, and non-retired slot.
  Removed or stale targets are rejected without selecting a successor or opening a
  substitute pane; the preview surface registration is cleared before the slot can
  retire.
- **Commit wins before key-up.** Enter/digit first transitions to
  `suppressedUntilSpaceRelease` and clears the transient presentation, then invokes
  the existing `activateSelectedRow`/`activateNumberedDestination` effect and its
  `PaneCommittedFocusOperation`. A later key-up is idempotent.
- **Focus loss cancels.** List resign, host detach, sidebar collapse or surface loss,
  Management/transient takeover, window resign, and window close all use the same
  generation invalidation and canonical-presented transition. The sidebar remains
  first responder while preview is shown.
- **Preparation failure is contained.** Missing trusted bounds, failed restore, a
  missing host, or a replaced provider leaves canonical presentation visible. The
  existing prepared scheduler may finish or remain warm; preview never cancels,
  settles, or steals its custody ledger.
- **No durable rollback.** Release does not restore a captured layout or focus owner.
  It re-reads canonical state at release time, so concurrent arrangement, drawer,
  minimization, or active-tab changes remain authoritative.
- **Current window boundary.** The current source has one workspace window at a time,
  so source and target windows cannot diverge in this slice. No shared `PaneViewSlot`
  is mounted into a second visible host and no native view is reparented across
  windows.

These rules make overlap deterministic: selection callbacks may arrive while target
preparation is awaiting existing mount or scheduler work, and
late completions may only warm the slot. Renderer and Bridge observers are
observation-tracked existing loops; preview adds no poll, timer, debounce, event bus
case, or detached-drawer invariant repair.

## Preview proof seams and remaining boundary

The design's proof map extends the existing quality table as follows:

| Contract | Structural proof seam |
| --- | --- |
| R-S9 held lifecycle | Pure transition coverage for begin/repeat/replace/release, optional non-pane target, stale generation, invalid target, commit-before-key-up, and canonical-on-release. |
| R-S9 sidebar boundary | Real AppKit window and materialization host: Space down/up, selection follow, accepted snapshot replacement/removal, Enter/digit ordering, list focus retention, and cancellation on detach/focus loss. |
| R-S9 single mount | Existing composition harness with loaded and late-registered hosts: preview/Zoom/ordinary mutual exclusion, target replacement, same stable container identity, and no second rendered host. |
| R-S9 existing-pane restore | Real mounted terminal, hidden attached terminal, prepared cold terminal absent from the active custom layout, drawer child whose parent is absent from that layout, ended-session normal restore, and cold Bridge; inspect pane/provider/session identity, slot custody, existing attach/display path, durable arrangement, and warm completion after release. |
| R-S9 visibility/activity | Recording renderer reconciliation plus Bridge activity projection: canonical while the requested mount prepares, exact ready-mount target replacement, covered installed peers `loadedHidden`, closed/dormant/no-controller/inactive guards, canonical restoration on release, equality suppression, and terminal window occlusion/miniaturization. |
| R-S9 geometry | Real allocation and `forceGeometrySync` for the trusted full-pane-area frame and release resize, including background-tab and drawer targets; keep frame proof separate from renderer visibility proof. |
| R-S6/U16 Space chip | Native associated and unassociated pane rows at 250- and 320-point widths with `Space` first in the metadata/chip row and the simultaneous leading digit hint when eligible; inspect recency retained in composition, title/digit separation, unchanged row height and pointer behavior. At 250 points, dense trailing metadata may clip while the leading identity and `Space` remain visible and non-overlapping. |

Mocks may replace external filesystem/runtime dependencies at pure policy seams;
native responder, custody, renderer, Bridge, and allocation proof remains real. The
supported current composition has one workspace window and no cross-window preview
path; preview adds no second host or shared-slot reparenting.

## Source map

- [Stable host](../../../Sources/AgentStudio/Features/RepoExplorer/RepoExplorerMaterializationHost.swift) and [native materializer](../../../Sources/AgentStudio/Features/RepoExplorer/RepoExplorerTableMaterializer.swift): lifetime, accepted generation and native row rendering.
- [Shell focus](../../../Sources/AgentStudio/App/Windows/MainSplitViewController.swift) and [current filter/proxy bridge](../../../Sources/AgentStudio/Features/RepoExplorer/RepoExplorerView+VisibleRows.swift).
- [Snapshot construction](../../../Sources/AgentStudio/Features/RepoExplorer/Models/RepoExplorerMaterializationSnapshot.swift), [update planning](../../../Sources/AgentStudio/Features/RepoExplorer/Models/RepoExplorerNativeUpdatePlan.swift) and [pane organization](../../../Sources/AgentStudio/Features/RepoExplorer/Models/RepoExplorerProjection+Organization.swift).
- [Shortcut context/display](../../../Sources/AgentStudio/Core/Actions/Commands/AppShortcut.swift) and [dispatch policy](../../../Sources/AgentStudio/Core/Actions/Commands/AppShortcutDispatchPolicy.swift).
- [Row shell](../../../Sources/AgentStudio/SharedComponents/SidebarRowShell.swift), [surface toggle](../../../Sources/AgentStudio/SharedComponents/SidebarEntityToggle.swift) and [toolbar](../../../Sources/AgentStudio/Features/RepoExplorer/RepoExplorerView+CommandToolbar.swift).
- [Pane row](../../../Sources/AgentStudio/Features/RepoExplorer/RepoExplorerPaneNavigation.swift), [sidebar chips](../../../Sources/AgentStudio/Core/Views/SidebarChips.swift), and [shortcut hint](../../../Sources/AgentStudio/SharedComponents/SidebarShortcutHint.swift): existing leading digit anchor and ordered metadata/chip row.
- [Committed focus](../../../Sources/AgentStudio/App/Panes/PaneCommittedFocusOperation.swift) remains the arrangement effect owner.
- [Persistent tab host](../../../Sources/AgentStudio/App/Panes/PersistentTabHostView.swift), [view registry](../../../Sources/AgentStudio/App/Panes/ViewRegistry.swift) and [pane representable](../../../Sources/AgentStudio/App/Panes/Hosting/PaneViewRepresentable.swift) preserve pane-lifetime host/container custody.
- [Terminal geometry](../../../Sources/AgentStudio/Features/Terminal/Restore/TerminalPaneGeometryResolver.swift), [terminal restore](../../../Sources/AgentStudio/Features/Terminal/Restore/TerminalRestoreRuntime.swift) and [zmx backend](../../../Sources/AgentStudio/Core/RuntimeEventSystem/Runtime/ZmxBackend.swift) provide the canonical geometry foundation and same-identity normal restore/fresh-shell behavior.
- [Renderer visibility](../../../Sources/AgentStudio/App/Coordination/WorkspaceSurfaceCoordinator+RendererVisibility.swift) and [Bridge activity](../../../Sources/AgentStudio/App/Coordination/WorkspaceSurfaceCoordinator+BridgePaneActivity.swift) remain the existing replacement owners for terminal visibility and Bridge activity.
- [Surface manager](../../../Sources/AgentStudio/Features/Terminal/Ghostty/SurfaceManager.swift) and [renderer state](../../../Sources/AgentStudio/Features/Terminal/Ghostty/SurfaceManager+RendererState.swift) own hidden-surface reattachment and attached-surface visibility reconciliation.
- [Main window](../../../Sources/AgentStudio/App/Windows/MainWindowController.swift), [main split](../../../Sources/AgentStudio/App/Windows/MainSplitViewController.swift) and [window creation](../../../Sources/AgentStudio/App/Boot/AppDelegate+MainWindowCreation.swift) establish per-window composition and the current one-main-window lifecycle.
