# Pane Arrangement State System — Design

**Date:** 2026-05-02 (last edited 2026-05-10)
**Status:** Draft (awaiting user review)
**Branch:** drawer-empty-shortcut-diagnostics (spec drafted here; implementation
            will live on its own branch)

**Source session:**
- Session ID: `22280aad-8c90-4aba-a02d-0add40634a2b`
- Resume: `claude --resume 22280aad-8c90-4aba-a02d-0add40634a2b`
- Transcript: `~/.claude/projects/-Users-shravansunder-Documents-dev-project-dev-agent-studio-drawer-improvements/22280aad-8c90-4aba-a02d-0add40634a2b.jsonl`

**Companion specs (pending):**
- `2026-05-10-drawer-grid-layout-redesign-design.md` — new grid layout
  + sizing/resize/minimize/drag matrix; covers Issue B (LUNA-371) and
  the column-major refactor (LUNA-372). Stub created in same commit.

---

## 1. Goal

Make every pane arrangement a complete VIEW over a single source of DATA, with no asymmetry between main panes and drawer panes. Eliminate `visiblePaneIds` as stored state. Move per-arrangement drawer behavioral state (layout, minimize, active child) under `PaneArrangement` so switching arrangements correctly switches drawer state too. (Drawer.isExpanded stays GLOBAL per drawer — Q4.) Add a per-arrangement `showsMinimizedPanes` toggle (and per-drawer equivalent).

## 2. Motivation

Today's model is asymmetric:

- Main panes: `PaneArrangement.minimizedPaneIds` is per-arrangement and persisted.
- Drawer panes: `Drawer.minimizedPaneIds` is a single set per drawer, transient (reset on decode), and lives in `WorkspacePaneAtom` not `WorkspaceTabArrangementAtom`.

Same asymmetry exists for drawer layout, expanded state, and active child — all are drawer-scoped, not arrangement-scoped. This causes:

1. Switching tab arrangements does not restore the drawer's layout / minimize / active state for that view. Users see "wrong" drawer state after every arrangement switch.
2. Drawer minimize is lost across app restart (transient).
3. Mental model is inconsistent: "is X per-arrangement or not?" depends on whether X is a main pane property or a drawer property.

Additionally, `PaneArrangement.visiblePaneIds` today serves double duty — both as stored membership for "subset arrangements" and as a "what's visible right now" concept that the name suggests. The two collide, and the stored field can drift from `layout.paneIds`.

## 3. Mental model — DATA vs VIEW

Two layers, hard separation:

```
DATA (lives once, owned by Tab / Drawer)
  ▸ which panes exist in the tab
  ▸ which drawer panes exist inside each drawer
  ▸ pane content, identity, drawer attachment

GLOBAL VIEW (lives once, owned by Drawer — NOT per arrangement)
  ▸ Drawer.isExpanded — whether the drawer panel is open
    (Q4 decision: simple, no per-arrangement memory of panel
     expand state; toggleDrawer in arrangement A is visible
     in arrangement B)

PER-ARRANGEMENT VIEW (many views over the same data)
  ▸ position / order of panes in the layout
  ▸ minimize state per pane (which panes are minimized)
  ▸ show-minimized toggle (whether minimized panes appear at all
    in this arrangement, or are hidden entirely)
  ▸ drawer active child
  ▸ active pane (per arrangement, not per tab)
```

Every arrangement contains every pane the tab owns. No subsets, no membership variance. Arrangements differ only in how the same data is presented.

### 3.1 Operation classification

```
DATA operations               affect Tab / Drawer + ALL arrangements
  ▸ add pane to tab               → calibrate every arrangement
  ▸ remove pane from tab          → strip from every arrangement
  ▸ cross-tab pane move           → strip source, calibrate dest
  ▸ add drawer pane               → calibrate every drawerView
  ▸ remove drawer pane            → strip from every drawerView
  ▸ detach drawer pane (separate command, not drag)

GLOBAL VIEW operations         affect Drawer struct directly
  ▸ toggle drawer expand          → mutates Drawer.isExpanded
  ▸ collapseAllDrawers            → mutates Drawer.isExpanded
                                    for every drawer

PER-ARRANGEMENT VIEW operations affect only the active arrangement
  ▸ rearrange (drag within tab)   → active arrangement layout only
  ▸ minimize / unminimize         → active arrangement
  ▸ toggle showsMinimizedPanes    → active arrangement
  ▸ resize divider                → active arrangement layout
  ▸ set active pane               → active arrangement
  ▸ set active drawer child       → active arrangement drawerView
  ▸ create / rename / delete arrangement
  ▸ switch active arrangement
```

The validator gates every command against this classification.

> **Atom-naming note.** `WorkspaceTabLayoutAtom` is the public seam
> referenced in CLAUDE.md — it COMPOSES `WorkspaceTabShellAtom`
> (tab list, activeTabId) and `WorkspaceTabArrangementAtom`
> (arrangement state). When this spec talks about the data atom
> for arrangements, it means `WorkspaceTabArrangementAtom` (the
> internal data atom). New derived atoms / consumers should reach
> in via `WorkspaceTabLayoutAtom` per the canonical seam pattern,
> matching `AttendedPaneAtom`'s usage.

## 4. Current state shape (as of 2026-05-14)

```
WorkspacePaneAtom (Atoms/WorkspacePaneAtom.swift)
  panes: [UUID : Pane]
    Pane.kind = .layout(drawer: Drawer)
      Drawer
        paneIds: [UUID]                    drawer pane membership (DATA)
        layout: DrawerGridLayout           drawer grid positions  (VIEW today)
        activeChildId: UUID?               (VIEW today)
        isExpanded: Bool                   (VIEW today)
        minimizedPaneIds: Set<UUID>        (VIEW today, transient)

WorkspaceTabArrangementAtom (Atoms/WorkspaceTabArrangementAtom.swift)
  arrangementStates: [TabArrangementState]
    TabArrangementState
      tabId: UUID
      allPaneIds: [UUID]                   tab pane membership (DATA)
      arrangements: [PaneArrangement]
      activeArrangementId: UUID
      activePaneId: UUID?                  PER TAB (today)
      zoomedPaneId: UUID?                  transient

      PaneArrangement
        id, name, isDefault
        layout: Layout                     main pane positions (VIEW)
        visiblePaneIds: Set<UUID>          stored membership (drift-prone)
        minimizedPaneIds: Set<UUID>        main pane minimize (VIEW)
```

## 5. Proposed state shape

```
WorkspacePaneAtom (DATA + drawer-global view state)
  panes: [UUID : Pane]
    Pane.kind = .layout(drawer: Drawer)
      Drawer (identity + DATA + global view state)
        drawerId: UUID                     stable identity
        parentPaneId: UUID                 explicit parent link
        paneIds: [UUID]                    drawer pane membership (DATA)
        isExpanded: Bool                   GLOBAL view state, not per-
                                           arrangement (kept simple per
                                           user decision Q4)

WorkspaceTabArrangementAtom (per-arrangement VIEW)
  arrangementStates: [TabArrangementState]
    TabArrangementState
      tabId: UUID
      allPaneIds: [UUID]                   tab pane membership (DATA)
      arrangements: [PaneArrangement]
      activeArrangementId: UUID
      zoomedPaneId: UUID?                  transient (unchanged)
      // NOTE: activePaneId removed from TabArrangementState
      //       moved into PaneArrangement (per-arrangement)

      PaneArrangement
        id, name, isDefault
        layout: Layout                     main pane positions (VIEW)
        minimizedPaneIds: Set<UUID>        main pane minimize (VIEW)
        showsMinimizedPanes: Bool          NEW — view toggle (default true)
        activePaneId: UUID?                NEW (moved from per-tab)
        drawerViews: [drawerId : DrawerView]  NEW — per-drawer view state
                                              ONLY for non-empty drawers
                                              (see §9 calibration)

        // REMOVED: visiblePaneIds — derived from minimize + show toggle
        // (see §6.2 derivation rule)

      DrawerView (NEW — per arrangement, per non-empty drawer)
        layout: DrawerGridLayout           drawer grid positions
        activeChildId: UUID?
        minimizedPaneIds: Set<UUID>        now persisted
        showsMinimizedPanes: Bool          per-drawer view toggle
                                            (default true)
        // NOTE: isExpanded NOT here — stays on Drawer (Q4 decision)
```

## 6. Derived state — `WorkspaceArrangementViewDerived`

Per Q5: derived view state lives in a dedicated derived atom,
matching the existing pattern (`WorkspaceFocusDerived`,
`KeyboardOwnerDerived`, `WorkspacePaneFocusDerived`,
`WorkspaceLookupDerived`, `TabDisplayDerived`).

This keeps the data/view boundary explicit: stored arrangement
fields are raw values; derived atom assembles cooked values like
`activeVisiblePaneIds` (filtered by minimize + show-toggle) and
applies the management-mode override.

### 6.1 Atom interface

`WorkspaceArrangementViewDerived` (new) at
`Core/State/MainActor/Atoms/WorkspaceArrangementViewDerived.swift`.

**Relation to existing `ArrangementDerived`.** A separate
`ArrangementDerived` type already exists
(`Core/State/MainActor/Atoms/ArrangementDerived.swift`) and is
exposed on `AtomRegistry` as `arrangement: ArrangementDerived`
(`Infrastructure/AtomLib/AtomRegistry.swift:96`). That existing
type owns ARRANGEMENT-PANEL display data (list of arrangements,
which one is active, names) — it's about THE LIST of arrangements,
not the VIEW state within one arrangement.

**Precedent for the pattern.** Several existing atoms follow this
exact "derived `@MainActor @Observable` over multiple source atoms"
shape:
- `WorkspaceFocusDerived`, `KeyboardOwnerDerived`,
  `WorkspacePaneFocusDerived`, `WorkspaceLookupDerived`,
  `TabDisplayDerived` (struct-style derivations recomputed each access)
- `AttendedPaneAtom` (new in main 2026-05-13) — `@Observable` class
  that republishes `attendedPaneId` only when window is key AND
  management layer inactive. Combines `WorkspaceTabLayoutAtom +
  WindowLifecycleAtom + ManagementLayerAtom`. Same shape this spec
  proposes for `WorkspaceArrangementViewDerived`.

The spec follows the struct-style precedent (cheap to recompute,
no stored state, no fan-out subscription needed for the call sites
we expect). If a feature ever needs the `@Observable class +
AsyncStream<UUID?>` shape (like `AttendedPaneAtom`), the derived
atom can graduate later — Pareto-style.

`WorkspaceArrangementViewDerived` is the new sibling — it owns
PER-ARRANGEMENT-VIEW derivation (visible panes, drawer views,
effective show-toggle, focus). The two are independent and DO
NOT overlap.

Registry seam (added in PR 1):
```swift
extension AtomRegistry {
    var arrangement: ArrangementDerived                  // existing
    var arrangementView: WorkspaceArrangementViewDerived  // NEW
}
```

Both names are intentional: `arrangement` = "the list of
arrangements", `arrangementView` = "the per-arrangement view state".
Future evolution: if these turn out to overlap, `ArrangementDerived`
either absorbs `WorkspaceArrangementViewDerived` or composes with
it explicitly. Not part of this spec.

Reads from:
  ▸ `WorkspaceTabLayoutAtom` — composed shell+arrangement public
    seam (matches `AttendedPaneAtom`'s pattern)
  ▸ `WorkspacePaneAtom` — Pane / Drawer identity + paneIds
  ▸ `ManagementLayerAtom` — `isActive` for the showsMinimized
    override

```swift
@MainActor
struct WorkspaceArrangementViewDerived {
    let tabLayoutAtom: WorkspaceTabLayoutAtom
    let paneAtom: WorkspacePaneAtom
    let managementLayerAtom: ManagementLayerAtom

    // ===== Main pane derivation =====

    func activeVisiblePaneIds(forTab tabId: UUID) -> [UUID]
    // Applies §6.2 derivation rule with management override

    func effectiveShowsMinimizedPanes(forTab tabId: UUID) -> Bool
    // Returns true when management is active (override),
    // otherwise activeArrangement.showsMinimizedPanes

    // ===== Drawer pane derivation =====

    func drawerView(forParent parentPaneId: UUID) -> DrawerView?
    // Returns nil if drawer is empty (no DrawerView entry)

    func drawerVisiblePaneIds(forParent parentPaneId: UUID) -> [UUID]
    // Applies §6.2 derivation rule for drawer panes;
    // returns [] if drawer is empty
    // Applies management override for showsMinimizedPanes

    func effectiveShowsMinimizedDrawerPanes(
        forParent parentPaneId: UUID
    ) -> Bool

    // ===== Convenience accessors =====

    func activePaneId(forTab tabId: UUID) -> UUID?
    func activeMinimizedPaneIds(forTab tabId: UUID) -> Set<UUID>
}
```

The struct is recreated each access (no stored state). `@Observable`
propagation works through the underlying atoms — when any source atom
changes, callers re-read via the derived atom and see fresh values.
Matches `WorkspaceTabDerived` (which assembles `Tab` from the
shell + arrangement atoms).

**Threading + management-mode override:** the derived struct is
`@MainActor` (matches all underlying atoms). When
`ManagementLayerAtom.isActive` flips, `@Observable` triggers a
SwiftUI re-render of any view reading through the derived atom.
Each view re-reads `effectiveShowsMinimizedPanes(...)` and the
override takes effect in the SAME render pass — no stale cache,
no separate invalidation step.

The override is COMPUTED, not stored. Exiting management mode
restores the user's per-arrangement preference automatically (the
stored `arrangement.showsMinimizedPanes` is untouched throughout).

Calling pattern for views:
```swift
let visible = atom(\.arrangementView).activeVisiblePaneIds(
    forTab: tabId
)
// re-reads on any change to the underlying atoms, including
// ManagementLayerAtom.isActive
```

### 6.2 visiblePaneIds derivation rule

For main panes (computed by
`WorkspaceArrangementViewDerived.activeVisiblePaneIds`):

```
let effectiveShows =
  managementLayerAtom.isActive
    ? true
    : arrangement.showsMinimizedPanes

visible(arrangement) =
  if effectiveShows
    then arrangement.layout.paneIds                         (all panes)
    else arrangement.layout.paneIds - arrangement.minimizedPaneIds
                                                             (minimized hidden)
```

Same rule applies to drawer (computed by
`WorkspaceArrangementViewDerived.drawerVisiblePaneIds`):

```
let effectiveShows =
  managementLayerAtom.isActive
    ? true
    : drawerView.showsMinimizedPanes

visible(drawerView) =
  if effectiveShows
    then drawerView.layout.paneIds
    else drawerView.layout.paneIds - drawerView.minimizedPaneIds
```

No stored `visiblePaneIds` field. The derived atom computes from
layout + minimize + show-toggle + management-active. This eliminates
the drift class entirely AND respects management mode globally
without mutating saved values (Q1 decision: derived/computed
override, not save/restore).

## 7. Invariants

These must be enforced by validation rules and asserted in tests.

```
I1. Every Tab has at least one PaneArrangement.
I2. Every Tab has exactly ONE PaneArrangement with isDefault == true.
    The default arrangement CANNOT be deleted (validator rejects).
I3. The default arrangement contains ALL of tab.allPaneIds in its
    layout (positions). All non-default arrangements must ALSO
    contain all of tab.allPaneIds in their layouts (every
    arrangement is complete).
I4. arrangement.minimizedPaneIds is a subset of arrangement.layout.paneIds.
I5. arrangement.activePaneId, when non-nil, is a member of
    arrangement.layout.paneIds.
I6. For every pane P in tab.allPaneIds where P has a NON-EMPTY
    drawer (P.drawer.paneIds is not empty):
      every arrangement.drawerViews must contain an entry for
      P.drawer.drawerId. The drawer view's layout contains all
      drawer.paneIds.
    For panes with EMPTY drawers (paneIds.isEmpty):
      no arrangement contains a drawerViews entry for them
      (per Q4 — empty drawers have no per-arrangement view state;
       the only meaningful state is Drawer.isExpanded which is
       global on the Drawer struct).
I7. drawerView.minimizedPaneIds is a subset of drawerView.layout.paneIds.
I8. drawerView.activeChildId, when non-nil, is a member of
    drawerView.layout.paneIds.
I9. Drawer panes never leave their parent drawer via drag.
    Cross-container moves only via the detach command.
    (Saved memory; reaffirmed.)
I10. Tabs cannot be nested. Tab drag within tab bar is a reorder
     only. Tab-into-tab is a validator rejection.
```

## 8. Atom-by-atom change spec

### 8.1 WorkspacePaneAtom

`Drawer` shrinks to identity + DATA + isExpanded (kept global per Q4):

```swift
struct Drawer: Codable, Hashable {
    let drawerId: UUID
    let parentPaneId: UUID
    var paneIds: [UUID]
    var isExpanded: Bool      // kept here, NOT per-arrangement (Q4)
    // REMOVED: layout, activeChildId, minimizedPaneIds
    //   (these are per-arrangement → DrawerView)
}
```

Methods that mutate VIEW state (layout, active, minimize) move OUT
of WorkspacePaneAtom and into WorkspaceTabArrangementAtom. `toggleDrawer`
stays on WorkspacePaneAtom because `isExpanded` is global per drawer:

```
MOVED OUT (now in WorkspaceTabArrangementAtom, mutate active arrangement)
  ▸ moveDrawerPane           → moveDrawerPaneInActive
  ▸ resizeDrawerPane         → resizeDrawerPaneInActive
  ▸ equalizeDrawerPanes      → equalizeDrawerPanesInActive
  ▸ minimizeDrawerPane       → minimizeDrawerPaneInActive
  ▸ expandDrawerPane         → expandDrawerPaneInActive
  ▸ setActiveDrawerPane      → setActiveDrawerPaneInActive

KEPT on WorkspacePaneAtom (mutate Drawer.isExpanded — global per Q4)
  ▸ toggleDrawer             → flips Drawer.isExpanded for one drawer
  ▸ collapseAllDrawers       → sets Drawer.isExpanded=false for every
                                drawer (mutates only Drawer struct;
                                does NOT touch any arrangement)

KEPT on WorkspacePaneAtom (DATA mutations)
  ▸ addDrawerPane            → adds to Drawer.paneIds, then asks
                                coordinator to calibrate every arrangement
  ▸ insertDrawerPane         → same, with positional hint for active
  ▸ removeDrawerPane         → removes from Drawer.paneIds, then asks
                                coordinator to strip from every arrangement
  ▸ detachDrawerPane         → cross-container, separate command
  ▸ restoreDrawerPane        → undo path
```

### 8.2 WorkspaceTabArrangementAtom

`PaneArrangement` reshape:

```swift
struct PaneArrangement: Codable, Identifiable, Hashable {
    let id: UUID
    var name: String
    var isDefault: Bool

    // Existing
    var layout: Layout
    var minimizedPaneIds: Set<UUID>

    // NEW
    var showsMinimizedPanes: Bool
    var activePaneId: UUID?
    var drawerViews: [UUID: DrawerView]   // keyed by Drawer.drawerId

    // REMOVED
    // var visiblePaneIds: Set<UUID>  ← derived now (§6.2)
}
```

`DrawerView` (new — only present for non-empty drawers):

```swift
struct DrawerView: Codable, Hashable {
    var layout: DrawerGridLayout
    var activeChildId: UUID?
    var minimizedPaneIds: Set<UUID>
    var showsMinimizedPanes: Bool
    // NOTE: NO isExpanded — kept on Drawer struct (Q4)
}
```

`TabArrangementState` reshape:

```swift
struct TabArrangementState: Equatable {
    let tabId: UUID
    var allPaneIds: [UUID]
    var arrangements: [PaneArrangement]
    var activeArrangementId: UUID
    var zoomedPaneId: UUID?
    // REMOVED: activePaneId — moved to PaneArrangement
}
```

New atom methods (replacing the moved-out drawer mutators):

```
moveDrawerPaneInActive(parentPaneId:, target:, sizingMode:)
resizeDrawerPaneInActive(parentPaneId:, splitId:, ratio:)
equalizeDrawerPanesInActive(parentPaneId:)
minimizeDrawerPaneInActive(drawerPaneId:, parentPaneId:)
expandDrawerPaneInActive(drawerPaneId:, parentPaneId:)
setActiveDrawerPaneInActive(drawerPaneId:, parentPaneId:)
setShowsMinimizedPanesInActive(value:)            // main panes
setShowsMinimizedDrawerPanesInActive(parentPaneId:, value:)
setActivePaneInActive(paneId:)                    // moved from per-tab
```

NOTE: `toggleDrawer` and `collapseAllDrawers` are NOT in this list
— they mutate `Drawer.isExpanded` which stays on `WorkspacePaneAtom`
(global per drawer, not per-arrangement, per Q4).

Each method here targets the ACTIVE arrangement only — that's the
VIEW contract. DATA mutations (add/remove panes) are calibrated
across ALL arrangements; see §9.

### 8.3 WorkspaceMutationCoordinator

Becomes the orchestrator for any mutation that crosses both atoms.

DATA op flow (e.g. "add drawer pane"):

```
1. WorkspacePaneAtom.addDrawerPane(parent, content)
     ▸ creates Pane
     ▸ updates Drawer.paneIds on parent
2. WorkspaceTabArrangementAtom.calibrateForNewDrawerPane(
       drawerId:, drawerPaneId:, parentPaneId:)
     ▸ for every arrangement in every tab where parentPaneId
       appears in arrangement.layout:
         insert drawerPaneId into arrangement.drawerViews[drawerId]
         .layout at default position (append to end of top row)
         not minimized; activeChildId = drawerPaneId in active
         arrangement only
3. EventBus emits .drawerPaneAdded fact
```

DATA op flow (cross-tab pane move) — see §10.

VIEW op flow (e.g. "minimize drawer pane in active arrangement"):

```
1. WorkspaceTabArrangementAtom.minimizeDrawerPaneInActive(
       drawerPaneId:, parentPaneId:)
2. EventBus emits .drawerPaneMinimized fact
```

No coordination needed — VIEW ops touch one atom only.

## 9. Calibration semantics

When a DATA mutation happens, every arrangement that references the
affected pane (or every arrangement in the destination tab, for
cross-tab moves) must be updated in the same atomic operation.

Calibration rules per DATA op:

```
add main pane to tab
  for each arrangement in tab.arrangements:
    append paneId to arrangement.layout (default position: end)
    pane starts unminimized
    if arrangement is active: activePaneId = newPaneId
  (activePaneId in non-active arrangements: unchanged or default)

remove main pane from tab
  for each arrangement in tab.arrangements:
    remove paneId from arrangement.layout
    remove paneId from arrangement.minimizedPaneIds
    if arrangement.activePaneId == paneId:
      arrangement.activePaneId = chooseNewActivePaneId(arrangement)
    drop arrangement.drawerViews[paneId.drawer.drawerId] if any
  remove paneId from tab.allPaneIds

  chooseNewActivePaneId(arr) selection rule (covers all edge cases):
    1. if arr.layout.paneIds is empty:
         return nil  (layout has no panes; tab is conceptually empty
                      until next add; UI shows empty-arrangement
                      placeholder — see Q6 rule below)
    2. else if there is any pane in arr.layout.paneIds NOT in
       arr.minimizedPaneIds:
         return the first such pane (left-to-right in layout)
    3. else (all remaining panes are minimized):
         return arr.layout.paneIds.first
         (still set activePaneId; UI behavior depends on
          showsMinimizedPanes — see empty-visible rule below)

Empty-visible arrangement rule (Q6 / user decision 2026-05-14):

  When an arrangement renders with zero visible panes — either
  because layout is empty (rule 1) OR all panes are minimized AND
  showsMinimizedPanes is false (rule 3 case) — the tab content
  area shows an empty-arrangement PLACEHOLDER, mirroring the
  existing empty-drawer hint.

  No special shortcut or command contract is added for this state.
  Existing global pane-creation commands continue to behave according
  to their existing command contexts, but Spec 1 does NOT introduce an
  empty-arrangement ShortcutContext, a new contextual alternate, or a
  validator guard that prevents reaching this state. For now, the UI
  simply tells the user that no panes are visible; recovery happens
  through the existing arrangement / pane controls.

  Placeholder shape (illustrative; final copy + count display
  owned by the tab content view layer):

      ┌──────────────────────────────────────────────┐
      │                                              │
      │   (empty-arrangement placeholder)            │
      │   "No panes visible"                         │
      │   "Minimized panes are hidden here."          │
      │   optional count of minimized panes when     │
      │   showsMinimizedPanes is false               │
      │                                              │
      └──────────────────────────────────────────────┘

  This is NOT a validator-prevented state. Hiding the last visible
  pane via the showsMinimizedPanes=false toggle (or minimizing the
  last visible pane) is ALLOWED. The placeholder is a UI affordance,
  not a guard.

  Owned by the tab content view layer. The state/model contract
  guarantees:
    - activePaneId computation is well-defined in this case
    - WorkspaceArrangementViewDerived.activeVisiblePaneIds returns
      an empty array
    - the tab is not in a broken state — switching to an arrangement
      with visible panes, toggling showsMinimizedPanes back on, or
      unminimizing snaps it back to a normal render

add drawer pane (parent has drawer; was empty OR already populated)
  Drawer.paneIds.append(drawerPaneId)
  was_empty = (drawer.paneIds.count was 0 before append)
  for each arrangement in tab.arrangements where parentPaneId in
    arrangement.layout.paneIds:
    if was_empty:
      // create fresh DrawerView for this drawer in this arrangement
      arrangement.drawerViews[drawer.drawerId] = DrawerView(
        layout: DrawerGridLayout(topRow: Layout(paneId: drawerPaneId)),
        activeChildId: drawerPaneId,
        minimizedPaneIds: [],
        showsMinimizedPanes: true   // default; user toggle later
      )
    else:
      var view = arrangement.drawerViews[drawer.drawerId]!
      view.layout = view.layout.append(drawerPaneId,
                                      sizingMode: .halveTarget)
      if arrangement is active: view.activeChildId = drawerPaneId
      arrangement.drawerViews[drawer.drawerId] = view
  // Drawer.isExpanded — preserve today's UX: WorkspacePaneAtom
  // .addDrawerPane sets drawer.isExpanded = true (open drawer on
  // add). This is a DATA-side mutation on the Drawer struct, NOT
  // part of per-arrangement calibration. isExpanded is global per
  // Q4, so the new drawer pane is visible across all arrangements.

remove drawer pane
  Drawer.paneIds.remove(drawerPaneId)
  becomes_empty = (drawer.paneIds.count is 0 after removal)
  for each arrangement in tab.arrangements:
    if becomes_empty:
      // drop the per-arrangement DrawerView entry entirely —
      // empty drawers have no view state (Q4)
      arrangement.drawerViews.removeValue(forKey: drawer.drawerId)
    else:
      var view = arrangement.drawerViews[drawer.drawerId]!
      view.layout = view.layout.removing(drawerPaneId,
                                        sizingMode: .proportional)
      view.minimizedPaneIds.remove(drawerPaneId)
      if view.activeChildId == drawerPaneId:
        view.activeChildId = view.layout.paneIds.first
      arrangement.drawerViews[drawer.drawerId] = view
```

Calibration is deterministic and idempotent.

Empty-drawer rule (per Q4): a drawer with `paneIds.isEmpty` has
NO entry in any arrangement's `drawerViews`. The drawer's
`isExpanded` (on `Drawer` struct) still works — user can toggle
the panel even with no children.

**UI affordance for empty drawer (out of scope for state spec).**
When `drawer.paneIds.isEmpty && drawer.isExpanded == true`, the
drawer panel renders the existing empty-drawer placeholder UI
(currently a "press P to add pane" hint — see
`Sources/AgentStudio/Core/Views/Drawer/DrawerPanel.swift`). Spec 1
does NOT modify that placeholder; the drawer panel view layer
owns it. The `WorkspaceArrangementViewDerived.drawerView(forParent:)`
returns `nil` for empty drawers; the drawer panel reads
`Drawer.isExpanded` directly from `WorkspacePaneAtom` for the
panel visibility decision.

## 10. Cross-tab pane move

NEW PaneActionCommand variant:

```swift
case movePaneAcrossTabs(
    paneId: UUID,
    sourceTabId: UUID,
    destTabId: UUID,
    targetPaneId: UUID,
    direction: Layout.SplitDirection,
    position: Layout.Position
)
```

Validator rejects:

- pane is a drawer child (cross-container blocked; use detach
  command instead)
- sourceTabId == destTabId (use within-tab move command)
- destTabId does not exist
- targetPaneId not in destination tab.allPaneIds

Coordinator flow:

```
1. validate (above)
2. capture pane snapshot (Pane + its Drawer if any + drawer panes)
3. SOURCE TAB:
     for each arrangement in source.arrangements:
       remove paneId from arrangement.layout
       remove paneId from arrangement.minimizedPaneIds
       if arrangement.activePaneId == paneId:
         arrangement.activePaneId =
           chooseNewActivePaneId(arrangement)  // see §9
       drop arrangement.drawerViews[anyDrawerOnPane.drawerId]
     remove paneId from source.allPaneIds
     if source.allPaneIds.isEmpty:
       auto-close source tab (Q2 decision)
       emit arrangement.tab_close_committed with
         cause = "cross_tab_move_drained"
       set source_tab_auto_closed = true on the
         cross_tab_move_committed record (step 6)
4. DESTINATION TAB:
     append paneId to dest.allPaneIds
     for each arrangement in dest.arrangements:
       if arrangement is ACTIVE:
         insert paneId into arrangement.layout at targetPaneId/
           direction/position (drag-supplied position)
         arrangement.activePaneId = paneId
       else:
         insert paneId into arrangement.layout at end (default)
         (activePaneId in non-active arrangement unchanged)
       if pane has a drawer AND drawer.paneIds is non-empty:
         create fresh DrawerView entry for drawer.drawerId:
           layout            = DrawerGridLayout.autoTiled(drawer.paneIds)
           activeChildId     = drawer.paneIds.first
           minimizedPaneIds  = []
           showsMinimizedPanes = true
       // empty drawers get no entry per Q4
5. drawer pane snapshots stay attached to the parent — they
   travel with the pane (Pane + Drawer + child Panes)
6. EventBus emits .paneMovedAcrossTabs
```

**Atomicity mechanism.** Steps 2-5 execute within a single
`WorkspaceMutationCoordinator` method invocation on `@MainActor`.
Swift concurrency guarantees no other actor-reentrant mutation
runs between steps. Because both atoms are `@MainActor`-bound,
the partial-mutation window only exists if the coordinator method
throws mid-flight — which we prevent by:

- Validating ALL preconditions before any mutation (§10 step 1).
- Building the destination layout in-memory before applying.
- Treating drawer panes as snapshots captured upfront (step 2).
- Each atom call is a synchronous, total function — no async
  hops between steps 2-5.

If any of steps 2-5 fails an internal invariant assertion in
DEBUG, that's a bug (caught by tests). In RELEASE, the same path
emits `arrangement.invariant_violation` via trace AND surfaces a
log entry, but no rollback is performed — the move is structured
so its individual mutations are independently valid (removal from
source is valid; insertion into dest is valid; combined they
preserve invariants). Best-effort partial-mutation visibility is
acceptable for a path that's exercised by user drag (recoverable).

## 11. Tab drag rules

NEW PaneActionCommand variants:

```swift
case reorderTab(tabId: UUID, newIndex: Int)
```

Validator rejects:

- newIndex out of range
- tab does not exist

There is NO "drag tab into tab" command — that's not a supported
operation. The drag layer must reject this at the source-filter
stage (separate from the validator).

## 12. Validator rules (additions)

```
V1. delete arrangement: rejected if arrangement.isDefault
V2. switch active arrangement: target arrangement must exist
V3. movePaneAcrossTabs: see §10
V4. reorderTab: see §11
V5. drawer pane drag → main: rejected (cross-container — I9)
V6. main pane drag → drawer: rejected (cross-container — I9)
V7. tab drag → tab: rejected at source-filter (I10), validator
    catches if it leaks through
V8. add pane to tab: pane must not already be in another tab
    (panes belong to one tab at a time)
V9. set active pane: pane must be in arrangement.layout.paneIds
```

All validators run in `WorkspaceCommandValidator` against
`ActionStateSnapshot`.

## 13. PaneActionCommand catalog

EXISTING (contract preserved, internals change):

```
.minimizePane(tabId:, paneId:)
.expandPane(tabId:, paneId:)
.minimizeDrawerPane(parentPaneId:, drawerPaneId:)
.expandDrawerPane(parentPaneId:, drawerPaneId:)
.toggleDrawer(parentPaneId:)
.setActiveDrawerPane(parentPaneId:, drawerPaneId:)
.moveDrawerPane(parentPaneId:, drawerPaneId:, target:, sizingMode:)
.resizePane(tabId:, splitId:, ratio:)
.resizeDrawerPane(parentPaneId:, splitId:, ratio:)
.setActivePane(tabId:, paneId:)
... (others unchanged)
```

Most of these change internals from "mutate Drawer struct" to
"mutate active arrangement's drawerView". Exception: `.toggleDrawer`
still mutates `Drawer.isExpanded` because that field stays on
Drawer (Q4 — global per drawer, not per-arrangement). For all of
these, the command CONTRACT stays the same — callers don't
change.

NEW:

```
.movePaneAcrossTabs(paneId:, sourceTabId:, destTabId:,
                    targetPaneId:, direction:, position:)
.reorderTab(tabId:, newIndex:)
.setShowsMinimizedPanes(tabId:, value:)
.setShowsMinimizedDrawerPanes(parentPaneId:, value:)
```

CHANGED SIGNATURE (subset arrangements removed):

```
.createArrangement(tabId:, name:, paneIds:)   ← BEFORE
                  └──── subset of tab.allPaneIds

.createArrangement(tabId:, name:)              ← AFTER
                  └──── new arrangement always contains every pane
                        in tab.allPaneIds; layout seeded by copying
                        from active arrangement (Q3 inheritance);
                        showsMinimizedPanes inherits from active too
```

The `paneIds` parameter is dropped in PR 1. Call sites passing
`paneIds:` will stop compiling — fix them by removing the argument.

**`TabArrangementMutationRules.swift` — what to keep vs change.**
The file owns 9 public functions (`createArrangement`,
`removingArrangement`, `removingUserPane`, `switchingArrangement`,
`minimizingPane`, `expandingPane`, `breakingUpTab`,
`extractingPane`, `merging`). Only ONE of them — `createArrangement`
— has subset-filtering logic. The file is NOT deleted. PR 1
changes happen in-place:

- `createArrangement(...)`: replace the subset-filter branch with
  "new arrangement = copy of active arrangement's layout + show-
  toggle" (Q3 inheritance). Loses the `paneIds: Set<UUID>`
  parameter.
- `minimizingPane` / `expandingPane`: keep as-is for main panes
  (they already operate on the active arrangement). Verify they
  use the new `showsMinimizedPanes` semantic correctly.
- `removingUserPane`: extend to also drop the matching DrawerView
  entry from every arrangement's `drawerViews` map (calibration
  for pane-with-drawer removal — see §9).
- `switchingArrangement`, `removingArrangement`, `breakingUpTab`,
  `extractingPane`, `merging`: unchanged behaviorally, but check
  for any reads of the removed `visiblePaneIds` field.

If, after PR 1, this file ends up being a thin shim, it can be
inlined into `WorkspaceTabArrangementAtom` — but that's a
follow-up cleanup, NOT part of this spec.

REMOVED PaneActionCommand cases: none. (Subset-arrangement creation
is the only feature killed by removing visiblePaneIds; the create
command stays, just loses an argument — see §16.)

## 14. No migration (development stage)

**Decision (2026-05-12):** No migration logic. Pre-launch, no
production users to preserve. Existing persisted workspaces will
not decode under the new schema — that's acceptable.

What this means in practice:

- `Codable` for `Pane`, `Drawer`, `PaneArrangement`,
  `TabArrangementState` uses the NEW shape only.
- No `decodeIfPresent` fallbacks for old field names. No backward-
  compat branches in `init(from:)`.
- On launch, if an old `workspace.state.json` exists, it fails to
  decode → workspace defaults to empty state (same recovery path
  as a fresh install or a corrupt file).
- No schema version bump. The format is just "the new format".
- Defaults for fresh state:
    - `showsMinimizedPanes: true` (matches what migration would
      have preserved)
    - `activePaneId: nil` (set when first pane is added)
    - `drawerViews: [:]` (populated by calibration when drawer
      panes get added)
    - `Drawer.drawerId: UUID()` (fresh on creation)
    - `Drawer.parentPaneId: <owning pane id>` (set on creation)
    - `Drawer.isExpanded: false` (default until user opens it)

Developer workflow: blow away `~/.agentstudio/workspaces/*/
workspace.state.json` on first run under the new schema. Document
this in the PR description, not in code.

**Decode error recovery path (matches current persistence contract):**

The existing persistence layer already has a corrupt-file recovery
contract. The spec uses that contract — no new behavior needed.

```
WorkspacePersistor.load() reads workspace.state.json
   ↓
JSONDecoder fails on old-shape fields (e.g. PaneArrangement
expects "drawerViews" but old file has "visiblePaneIds")
   ↓
WorkspacePersistor catches DecodingError and returns
LoadResult.corrupt(Error)
(see WorkspacePersistor.swift LoadResult enum — .loaded(T)
 | .missing | .corrupt(Error))
   ↓
WorkspaceStore.init handles .corrupt:
  1. calls persistor.quarantineCorruptCanonicalWorkspaceFiles()
     — moves the broken file aside with a .quarantined-<date>
        suffix so we don't try to decode it again
  2. logs the decoding error via workspaceStoreLogger.error(...)
  3. invokes recoveryReporter callback with
     PersistenceRecoveryEvent (.store: .workspace, .recovery:
      .quarantinedAndReset or .quarantineFailed)
  4. emits trace: arrangement.decode_failed (NEW — see §16.5)
  5. continues init with empty state:
     - empty allPaneIds
     - no panes
     - tab list will be empty until the first user action
   ↓
user sees empty workspace on launch (no crash, no error dialog —
existing quarantine-and-reset behavior is unchanged)
```

In production (post-launch) we'd add a one-shot migration path or
a user-facing notification through the recoveryReporter. For now,
dev workflow handles it (and the quarantine preserves the broken
file for inspection).

Tests in `FreshStateDecodeTests` (§18) cover the failure path:
old-shape JSON → load() returns `.corrupt` → init quarantines +
empty state + recoveryReporter called + trace emitted.

## 15. Storage location

All persisted state continues to live in `WorkspaceStore` (the
existing persistence wrapper). Atoms touched:

```
WorkspacePaneAtom
  panes (with shrunken Drawer struct)
  persisted via Pane Codable

WorkspaceTabArrangementAtom
  arrangementStates (with new PaneArrangement shape, drawerViews)
  persisted via TabArrangementState Codable

WorkspaceMutationCoordinator
  in-process orchestrator only — no persistence
```

No new store, no new persistence file. No schema-version bump
either (per §14 no-migration policy — old persisted state simply
fails to decode under the new shape; `currentSchemaVersion` stays
at its current value because we're not adding back-compat
branches that key off it).

### 15.1 Persistence tier alignment

PaneArrangement (and the new `DrawerView`, `showsMinimizedPanes`
field, `activePaneId` field, `drawerViews` dict) are **Tier A
canonical state** — user intent that survives app restart. They
persist via `WorkspaceStore` into `workspace.state.json` per the
three-tier model in [Workspace Data Architecture — Three
Persistence Tiers](../../architecture/workspace_data_architecture.md).

Tier A (canonical) is the source of truth. Tier B (cache,
`workspace.cache.json`) and Tier C (UI prefs, `workspace.ui.json`)
NEVER read from or write to arrangement state. Tier B holds repo
enrichment derived from the event bus; Tier C holds presentation
preferences and sidebar composition state.

**Hard cutover.** No back-compat shim, no schema version bump.
Old persisted state simply fails to decode → empty workspace
(see §14).

## 16. Removed feature: subset arrangements

Today, `PaneArrangement.visiblePaneIds` permits an arrangement to
contain a SUBSET of the tab's panes. After this change, every
arrangement contains every pane in the tab. Custom arrangements
differ from each other only by VIEW state (positions, minimize,
show-toggle, active, drawer view).

This is an intentional simplification. If users genuinely need
subset arrangements in the future, that becomes a new feature
adding back a `hiddenPaneIds: Set<UUID>` field on `PaneArrangement`
and a corresponding UI affordance — but it's a separate spec.

## 16.5 Observability

Every workspace mutation emits OTel/JSONL traces via
`AgentStudioTraceRuntime` (`Sources/AgentStudio/Infrastructure/
Diagnostics/AgentStudioTraceRuntime.swift`). This makes the
validate→commit→calibrate pipeline debuggable end-to-end without
inventing a parallel logging system, and matches the convention
established by LUNA-361 (notification observability) and LUNA-368
(tagged JSONL tracer).

Observability is in scope for this spec — wire it from the start,
not as a follow-up. Bolted-on instrumentation drifts from reality.

### 16.5.1 New trace tag

Add a single case `arrangement` to `AgentStudioTraceTag` (raw value
`"arrangement"`). The tag matches the convention of existing single-
word lowercase cases: `actions`, `atoms`, `drag`, `eventbus`,
`restore`, `runtime`, `surface` (`Sources/AgentStudio/Infrastructure/
Diagnostics/AgentStudioTraceTag.swift`).

All arrangement-related records use this tag. Record NAMES use a
compound `arrangement.<event>` form (e.g. `arrangement.command_received`)
— this is the record name string, not the tag name. Both share the
prefix for grep-friendliness.

### 16.5.2 Required records

Every PaneActionCommand for an arrangement-state operation produces
two records at the entry point:

```
arrangement.command_received
  arrangement.command_name = "minimizePane" | "moveDrawerPane" |
                             "movePaneAcrossTabs" | "reorderTab" | ...
  arrangement.tab_id = UUID
  arrangement.arrangement_id = UUID  // active arrangement at time of cmd
  arrangement.pane_id = UUID         // when applicable
  arrangement.drawer_id = UUID       // when applicable
  arrangement.op_class = "data" | "view"

arrangement.command_validated
  arrangement.command_name = ...
  arrangement.decision = "accepted" | "rejected"
  arrangement.reason = one of the EXHAUSTIVE set below
```

The `reason` value MUST be exactly one of these strings (a closed
enum). Tests assert this — any unrecognized value fails the test
and indicates a missing case in the validator or a typo in trace
wiring.

```
"ok"                                  (decision == "accepted")
"drawer_pane_cannot_cross_tabs"       (V3: cross-tab move
                                       rejected; drawer pane)
"cross_tab_pane_not_found"            (V3: paneId not in source
                                       allPaneIds)
"cross_tab_same_tab"                  (V3: sourceTabId == destTabId)
"cross_tab_target_not_found"          (V3: targetPaneId not in
                                       dest allPaneIds)
"cross_tab_dest_not_found"            (V3: destTabId does not exist)
"tab_reorder_index_out_of_range"      (V4)
"tab_reorder_tab_not_found"           (V4)
"tab_into_tab_blocked"                (V7)
"main_to_drawer_blocked"              (V6)
"drawer_to_main_blocked"              (V5)
"default_arrangement_undeletable"     (V1)
"arrangement_not_found"               (V2 + V9)
"pane_already_in_another_tab"         (V8)
"pane_not_in_arrangement"             (V9)
```

15 reason values total. Each corresponds to a validator rule from
§12 or §11. If a new rule is added without a reason value here,
the test suite fails — forcing the enum to stay closed.

For ACCEPTED commands, the mutation pipeline emits result records:

```
arrangement.view_op_committed
  arrangement.op = "minimize_pane" | "expand_pane" |
                   "set_active_pane" | "set_active_drawer_pane" |
                   "resize_pane" | "resize_drawer_pane" |
                   "toggle_drawer" | "set_shows_minimized_panes" |
                   "set_shows_minimized_drawer_panes" |
                   "move_drawer_pane" | ...
  arrangement.tab_id = UUID
  arrangement.arrangement_id = UUID
  arrangement.pane_id = UUID         // when applicable
  arrangement.drawer_id = UUID       // when applicable
  arrangement.no_op = true | false   // true if the op was rejected
                                     //   internally (e.g., already
                                     //   minimized) — not a hard fail

arrangement.calibration_started
  arrangement.cause = "add_pane" | "remove_pane" |
                      "add_drawer_pane" | "remove_drawer_pane" |
                      "cross_tab_move_to_dest" |
                      "cross_tab_move_from_source" |
                      "tab_removed"
  arrangement.tab_id = UUID
  arrangement.affected_arrangement_count = Int

arrangement.calibration_applied
  arrangement.cause = ...
  arrangement.tab_id = UUID
  arrangement.affected_arrangement_count = Int   // may be 0 if no-op
  arrangement.elapsed_ms = Double
```

For cross-tab moves specifically:

```
arrangement.cross_tab_move_started
  arrangement.pane_id = UUID
  arrangement.source_tab_id = UUID
  arrangement.dest_tab_id = UUID
  arrangement.target_pane_id = UUID
  arrangement.position = "before" | "after"

arrangement.cross_tab_move_committed
  arrangement.pane_id = UUID
  arrangement.source_tab_id = UUID
  arrangement.dest_tab_id = UUID
  arrangement.elapsed_ms = Double
  arrangement.source_arrangements_calibrated = Int
  arrangement.dest_arrangements_calibrated = Int
  arrangement.source_tab_auto_closed = true | false
                                       // Q2: source tab auto-closes
                                       // when its last pane moves out
```

For tab close (Q7 — explicit record so tab close is greppable):

```
arrangement.tab_close_committed
  arrangement.tab_id = UUID
  arrangement.cause = "user_close" | "cross_tab_move_drained" |
                      "workspace_close"
  arrangement.had_arrangements = Int    // count before close
  arrangement.had_panes = Int           // count before close
```

For invariant assertions (DEBUG-only crash + always-on trace):

```
arrangement.invariant_violation
  arrangement.invariant = "I1" | "I2" | ... | "I10"   // §7
  arrangement.tab_id = UUID
  arrangement.arrangement_id = UUID
  arrangement.detail = String                           // one-line
                                                        //   description
```

For persistence boot-path errors (emitted from WorkspaceStore.init
when LoadResult.corrupt is returned — see §14):

```
arrangement.decode_failed
  arrangement.cause = "schema_mismatch" | "json_invalid" |
                      "file_unreadable" | "unknown"
  arrangement.workspace_id = UUID?    // nil if id couldn't be
                                        //   parsed from filename
  arrangement.quarantine_recovery = "quarantinedAndReset" |
                                      "quarantineFailed"
  arrangement.error_description = String  // redacted; one line
```

This is the only `arrangement.*` record emitted OUTSIDE the
validate-then-commit pipeline (it fires during persistor load
at WorkspaceStore.init time, before any commands are dispatched).
Tests cover it via `FreshStateDecodeTests` (§18).

In DEBUG builds, an invariant violation also fires `assertionFailure`.
In RELEASE, it logs via the trace + os.Logger.error and does not
crash. The trace record is the persistent record of what happened.

### 16.5.3 ServiceContext correlation

Correlation ID is created at the COMMAND DISPATCH ENTRYPOINT, not
inside the resolver (which is a static/pure-ish snapshot builder).
The dispatch entrypoint is `ActionExecutor.execute(_ action:
PaneActionCommand)` (`App/Commands/ActionExecutor.swift:113`).

```
ActionExecutor.execute(_ action: PaneActionCommand)
  ▸ create fresh agentStudioCorrelationID
  ▸ stash on ServiceContext via withValue { ... }
  ▸ call resolver.snapshot(...) inside the scope
  ▸ call validator.validate(...) inside the scope
  ▸ call coordinator.execute(...) inside the scope
  ▸ all downstream traces inherit the correlation ID
```

PaneTabViewController's `dispatchAction(...)` (the other dispatch
surface, `App/Panes/PaneTabViewController.swift:1655`-ish) MUST
route through the same ActionExecutor entrypoint so correlation
is uniform across keyboard, drag, and command-bar inputs. Today
that's already the path; the spec just adds the
correlation-stashing wrapper around it.

All downstream traces (validation, mutation, calibration, atom
mutation, EventBus emission) inherit this correlation ID via
`ServiceContext.current`, so the entire command lifecycle is
traceable end-to-end via a single ID.

This matches the pattern used by GitWorkingDirectoryProjector for
`correlationId` carry-forward (per workspace_data_architecture.md
§ Actor Responsibilities).

Note: WorkspaceCommandResolver is a STATIC enum with
`snapshot(...)` and other pure functions. It is the wrong place
for state-creation (correlation ID). Keep resolver pure.

### 16.5.4 Performance

Tracing is async + JSONL-backed by default. Calibration of every
arrangement on a DATA mutation is the hottest path:

- Trace records are batched by `AgentStudioJSONLTraceWriter` —
  do NOT `await trace.flush()` synchronously inside the calibration
  loop.
- `arrangement.calibration_started` and `_applied` bracket the
  whole calibration; per-arrangement records are NOT emitted for
  each iteration (would be O(arrangements × panes) noise).
- `arrangement.elapsed_ms` is captured with `ContinuousClock` —
  not wall-clock — to avoid clock-skew confusion across sleep/wake.

### 16.5.5 Configuration

Tracing is opt-in via environment variable
`AGENTSTUDIO_TRACE_TAGS=arrangement`. Default is off — no
performance cost in normal runs. CI may enable the tag for
integration tests. Selectors support `*` (all) and `prefix.*`
(future-proofing if we ever split the tag).

## 17. Out of scope (explicitly)

The following are NOT addressed in this spec — they have their own
specs:

- **Sizing / minimize / drag matrix** (Spec 2). How dragging a pane
  next to a minimized pane should behave. How resize math handles
  minimized siblings. What "preserve source size" means. Issue B
  (LUNA-371). This spec just makes sure the STATE is in the right
  place; behavior is Spec 2's job.

- **Drawer column-major refactor** (Spec 3 / LUNA-372). Replacing
  `DrawerGridLayout` (row-major) with a column-major layout.
  Independent of arrangement state location. Ships after Spec 2.

## 18. Test surface

EXISTING tests that must change:

- All tests that read `arrangement.visiblePaneIds` — must use
  the derived computation (or `tab.activeVisiblePaneIds`).
- All tests that mutate `Drawer.layout` / `.activeChildId` /
  `.isExpanded` / `.minimizedPaneIds` directly — must mutate
  through the new atom methods (or assert via `arrangement
  .drawerViews[drawerId]`).
- Tests asserting "drawer minimize is transient" — flip to
  asserting it's persisted.
- Tests that assume `tab.activePaneId` is per-tab — adjust to
  read from active arrangement.

NEW test suites:

```
PaneArrangementInvariantTests
  ▸ I1-I10 from §7 enforced as test cases
  ▸ adding pane to tab calibrates every arrangement
  ▸ removing pane from tab strips every arrangement
  ▸ default arrangement undeletable

DrawerStatePerArrangementTests
  ▸ switching arrangement A → B switches drawer layout, minimize,
    active child correctly
  ▸ minimizing drawer pane in arrangement A leaves it expanded
    in arrangement B (showing per-arrangement isolation)
  ▸ Drawer.isExpanded is SHARED across arrangements (Q4) —
    toggling drawer expand in arrangement A is visible in
    arrangement B
  ▸ empty drawer (paneIds.isEmpty) has NO entry in any
    arrangement.drawerViews
  ▸ adding first pane to empty drawer creates DrawerView entries
    in every arrangement that contains the parent pane
  ▸ removing last pane from drawer drops DrawerView entries
    from every arrangement (drawer.isExpanded preserved on Drawer)

ManagementModeOverrideTests
  ▸ showsMinimizedPanes = false, management inactive →
    effective = false (minimized panes hidden)
  ▸ showsMinimizedPanes = false, management active →
    effective = true (override; minimized panes shown as bars)
  ▸ exiting management mode does NOT mutate stored
    showsMinimizedPanes — it returns to the user's preference
  ▸ same applies to drawer's showsMinimizedPanes per drawerView

EmptyArrangementPlaceholderTests (Q6 — model-side only)
  ▸ arrangement with empty layout → activeVisiblePaneIds == []
    AND activePaneId == nil
  ▸ arrangement with all panes minimized AND showsMinimizedPanes
    == false → activeVisiblePaneIds == [] AND activePaneId is
    one of the minimized panes (not nil)
  ▸ same scenario with management mode active → activeVisible-
    PaneIds == arrangement.layout.paneIds (override restores)
  ▸ minimizing the LAST visible pane is NOT rejected by the
    validator (no V-rule prevents it; UI placeholder handles it)
  ▸ unminimizing a pane in the empty-visible state correctly
    repopulates activeVisiblePaneIds

CrossTabPaneMoveTests
  ▸ movePaneAcrossTabs strips source ALL arrangements
  ▸ movePaneAcrossTabs adds to destination ALL arrangements
  ▸ active destination arrangement places at drag position
  ▸ non-active destination arrangements append to end
  ▸ drawer panes travel with parent
  ▸ rejected if pane is a drawer child
  ▸ rejected if cross-container (drag-side filter)

TabReorderTests
  ▸ reorderTab moves tab in tab bar
  ▸ tab-into-tab rejected at validator AND at drag source-filter

ShowsMinimizedPanesTests
  ▸ per-arrangement toggle hides minimized panes from layout
    rendering when false (via WorkspaceArrangementViewDerived)
  ▸ per-drawer toggle does the same for drawer panes
  ▸ derived visiblePaneIds matches the rule in §6.2
  ▸ ships in PR 1

ShowsMinimizedPanesUITests (PR 2)
  ▸ UI toggle control in arrangement panel mutates active
    arrangement's showsMinimizedPanes via PaneActionCommand
    .setShowsMinimizedPanes
  ▸ UI toggle control in drawer header mutates active
    arrangement's drawerView via PaneActionCommand
    .setShowsMinimizedDrawerPanes
  ▸ ships in PR 2 (depends on PR 1's per-arrangement
    persistence)

EmptyArrangementPlaceholderUITests (PR 2)
  ▸ when activeVisiblePaneIds is empty, tab content renders the
    empty-arrangement placeholder instead of a broken/blank layout
  ▸ placeholder copy communicates "no panes visible" and does NOT
    advertise a new shortcut
  ▸ toggling showsMinimizedPanes back on or unminimizing a pane
    restores the normal pane render

VisiblePaneIdsDerivationTests
  ▸ given (layout, minimized, showsMinimized), derived
    visiblePaneIds matches §6.2 rule

WorkspacePaneAtomDrawerStrippedTests
  ▸ Drawer struct carries identity + paneIds + isExpanded only
    (no layout / no activeChildId / no minimizedPaneIds — Q4)
  ▸ Drawer VIEW mutators removed from WorkspacePaneAtom and
    moved to WorkspaceTabArrangementAtom as *InActive methods:
    moveDrawerPane, resizeDrawerPane, equalizeDrawerPanes,
    minimizeDrawerPane, expandDrawerPane, setActiveDrawerPane
  ▸ toggleDrawer + collapseAllDrawers STAY on WorkspacePaneAtom
    (they mutate Drawer.isExpanded which is global per Q4)
  ▸ remaining DATA methods (addDrawerPane / removeDrawerPane /
    detachDrawerPane / restoreDrawerPane) work as before

FreshStateDecodeTests
  ▸ new schema decodes round-trip cleanly (encode → decode →
    equal)
  ▸ workspace.state.json with old shape returns LoadResult.corrupt
    from WorkspacePersistor.load() (not nil — matches existing
    contract)
  ▸ WorkspaceStore.init handles .corrupt by:
      - calling quarantineCorruptCanonicalWorkspaceFiles()
      - logging via workspaceStoreLogger.error
      - invoking recoveryReporter with PersistenceRecoveryEvent
        (.store: .workspace, .recovery: .quarantinedAndReset)
      - emitting arrangement.decode_failed trace
      - starting with empty state
  ▸ default values applied correctly for fresh state
    (showsMinimizedPanes=true, drawerViews={}, etc.)
  ▸ quarantined file is preserved on disk with .quarantined-<ts>
    suffix (existing persistor behavior — not changed)

ObservabilityTests (split across PR 1 and PR 2)

  PR 1 — records wired in this PR
    ▸ minimizePane emits arrangement.command_received +
      arrangement.command_validated(decision=accepted) +
      arrangement.view_op_committed
    ▸ rejected commands emit .command_validated with
      decision=rejected AND a recognized reason string (test
      against the enum of allowed reason values — fail on
      unrecognized)
    ▸ adding a drawer pane emits .calibration_started +
      .calibration_applied with affected_arrangement_count >= 1
    ▸ correlation_id originates at ActionExecutor.execute(_:)
      and propagates from received → validated → committed
      (assert via captured trace records that all share the same
      agentstudio.correlation_id attribute)
    ▸ invariant violation in DEBUG fires assertionFailure AND
      emits arrangement.invariant_violation; in RELEASE only
      emits trace
    ▸ corrupt persisted state emits arrangement.decode_failed at
      WorkspaceStore.init (NOT inside the command pipeline);
      correlation_id is null on that record (boot path, no
      command in flight)
    ▸ tracing default-off: no records emitted unless
      AGENTSTUDIO_TRACE_TAGS includes "arrangement" (or "*")

  PR 2 — records added in this PR
    ▸ cross-tab move emits .cross_tab_move_started +
      .cross_tab_move_committed with non-zero source/dest
      calibration counts and the source_tab_auto_closed flag
    ▸ tab close emits .tab_close_committed with a recognized
      cause string ("user_close" | "cross_tab_move_drained" |
      "workspace_close")
    ▸ tab reorder emits the right view_op_committed without
      triggering calibration
```

## 19. Implementation order — 2 PRs

User decision (2026-05-12): no migration logic, no schema phasing.
Compact the work into 2 PRs. PR 1 is the state-shape refactor +
internal plumbing; PR 2 is the new user-facing behaviors enabled
by the shape change.

```
PR 1 — State shape refactor + derived atom + calibration
       (the foundation; no new user-visible commands)

  Schema (hard cutover, no migration)
    ▸ Drawer shrinks to {drawerId, parentPaneId, paneIds,
      isExpanded}. Old fields removed entirely.
    ▸ PaneArrangement gains showsMinimizedPanes, activePaneId,
      drawerViews. visiblePaneIds REMOVED.
    ▸ DrawerView struct added.
    ▸ TabArrangementState loses activePaneId (moved to
      PaneArrangement).
    ▸ Codable uses new shape only — no decodeIfPresent fallback.

  Derived atom
    ▸ WorkspaceArrangementViewDerived created
      (Core/State/MainActor/Atoms/).
    ▸ Reads WorkspaceTabArrangementAtom + WorkspacePaneAtom +
      ManagementLayerAtom.
    ▸ Provides activeVisiblePaneIds, drawerView, drawerVisible-
      PaneIds, effectiveShowsMinimizedPanes (with management
      override), etc.

  Mutator moves
    ▸ Drawer VIEW mutators move from WorkspacePaneAtom to
      WorkspaceTabArrangementAtom as *InActive methods
      (moveDrawerPaneInActive, resizeDrawerPaneInActive,
      minimizeDrawerPaneInActive, expandDrawerPaneInActive,
      setActiveDrawerPaneInActive, equalizeDrawerPanesInActive,
      setActivePaneInActive, plus the two setShowsMinimized*
      methods).
    ▸ toggleDrawer + collapseAllDrawers STAY on
      WorkspacePaneAtom (mutate Drawer.isExpanded — global).
    ▸ PaneCoordinator+ActionExecution.swift rewired to call
      new methods.
    ▸ Existing PaneActionCommand contracts preserved — only
      internals change. Callers don't change.

  Calibration
    ▸ WorkspaceMutationCoordinator gains calibration for
      add/remove drawer pane.
    ▸ Empty drawers get no DrawerView entry; first pane add
      creates entries in every arrangement; last pane removal
      drops entries.

  Observability (in same PR — wire from the start)
    ▸ AgentStudioTraceTag case `arrangement` added.
    ▸ Records wired: command_received, command_validated,
      view_op_committed, calibration_started/applied,
      invariant_violation.
    ▸ ServiceContext.agentStudioCorrelationID propagated.

  Tests in same PR
    ▸ PaneArrangementInvariantTests (I1-I10)
    ▸ DrawerStatePerArrangementTests (isExpanded shared, empty
      drawer behavior)
    ▸ ManagementModeOverrideTests
    ▸ ShowsMinimizedPanesTests (per-arrangement behavior)
    ▸ VisiblePaneIdsDerivationTests
    ▸ EmptyArrangementPlaceholderTests (model-side Q6 behavior)
    ▸ WorkspacePaneAtomDrawerStrippedTests
    ▸ FreshStateDecodeTests (round-trip; old shape fails decode)
    ▸ ObservabilityTests (records emitted, correlation
      propagated, reasons enum complete)

PR 2 — New user behaviors enabled by PR 1

  Cross-tab pane move
    ▸ Add PaneActionCommand.movePaneAcrossTabs(...)
    ▸ Validator rules V1-V9 (reject drawer pane, reject same-
      tab, reject if dest doesn't exist, etc.)
    ▸ Source-tab auto-close when last pane drains (Q2)
    ▸ Drawer panes travel with parent pane
    ▸ Trace: arrangement.cross_tab_move_started / _committed
      with source_tab_auto_closed flag

    Retire the existing hidden cross-tab path:
      ▸ ActionResolver currently routes single-pane cross-tab
        drops via .insertPane(source: .existingPane(...))
        (Core/Actions/ActionResolver.swift around line 176-182
         — `.existingPane(paneId:, sourceTabId:)` case).
      ▸ PaneCoordinator+ActionExecution executes that as a
        non-atomic remove-then-insert sequence
        (App/Coordination/PaneCoordinator+ActionExecution.swift
         around line 818-840 — `.existingPane` case in the
         insertPane handler).
      ▸ Delete (or redirect to .movePaneAcrossTabs) in this PR.
        The new path is the only cross-tab path going forward.
      ▸ The InsertPaneSource.existingPane enum case stays for now
        (no harm — it has other uses) but the routing to it from
        cross-tab drag is removed.

  Tab drag rules
    ▸ Add PaneActionCommand.reorderTab(...)
    ▸ Tab-into-tab blocked at drag source-filter (validator
      catches if it leaks through)
    ▸ Trace: arrangement.tab_close_committed for the auto-close
      path AND for explicit tab close (cause enum)

  showsMinimizedPanes UI toggle
    ▸ Add toggle control in arrangement panel UI
    ▸ Per-arrangement persistence (already wired in PR 1)
    ▸ Per-drawer toggle in drawer header UI

  Empty visible arrangement placeholder
    ▸ Tab content view renders the empty-arrangement placeholder
      whenever WorkspaceArrangementViewDerived.activeVisiblePaneIds
      returns [] for the active arrangement
    ▸ No new shortcut context or command alternate is introduced
      for this placeholder in Spec 1

  Drag layer wiring
    ▸ Cross-tab drag handling in drag coordinator
    ▸ Source-filter rejects forbidden cross-container moves

  Tests in same PR
    ▸ CrossTabPaneMoveTests
    ▸ TabReorderTests
    ▸ ShowsMinimizedPanesUITests (toggle in UI)
    ▸ EmptyArrangementPlaceholderUITests
    ▸ Trace assertions for cross-tab + tab close paths
```

PR 1 is invisible to the user (existing commands behave
identically; only internals change). PR 2 ships the actual new
capabilities. This split keeps each diff scoped to one concern.

If the user wants a single PR instead, collapse PR 1 + PR 2 into
one — there's no technical dependency that forces the split. The
2-PR split is a review-friendliness preference.

## 20. Open questions / future work

None blocking. All design decisions made above. The new grid
layout / sizing matrix work (Spec 2/3 stub at
`2026-05-10-drawer-grid-layout-redesign-design.md`) picks this up
as foundation.

---

**Reviewer checklist before approval:**

- [ ] DATA vs VIEW classification (§3.1) matches your mental model
- [ ] Drawer.isExpanded stays GLOBAL per drawer (Q4) — empty drawers
      have NO drawerView entry; the panel-expand state is on Drawer
- [ ] Q1 management mode override is computed-only (no save/restore
      dance) — derived atom reads ManagementLayerAtom.isActive
- [ ] Invariants (§7) are complete and correct
- [ ] visiblePaneIds removal (§16) is acceptable (subset
      arrangements feature loss); hard cutover via PR 1
- [ ] showsMinimizedPanes default = true for fresh state
      (matches today's "show minimized as collapsed bars" behavior)
- [ ] WorkspaceArrangementViewDerived (§6.1) — new derived atom
      placement matches existing pattern (WorkspaceFocusDerived,
      etc.)
- [ ] Cross-tab move (§10) auto-closes source tab if it drains
      to zero panes (Q2)
- [ ] No-migration approach (§14) acceptable for development stage
      — old persisted state fails to decode and defaults to empty
- [ ] Persistence tier alignment (§15.1) — Tier A canonical is
      the right home (vs Tier B cache or Tier C UI)
- [ ] Observability (§16.5) — trace tag, records (incl.
      tab_close_committed), correlation, and performance approach
      are right; reasons enum is complete
- [ ] PR split (§19) — PR 1 internal refactor, PR 2 new user
      behaviors — right granularity, or do you want a single PR
- [ ] Test surface (§18) covers the right scenarios
