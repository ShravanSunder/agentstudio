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

Make every pane arrangement a complete VIEW over a single source of DATA, with no asymmetry between main panes and drawer panes. Eliminate `visiblePaneIds` as stored state. Move all drawer behavioral state (layout, minimize, expand, active child) under `PaneArrangement` so switching arrangements correctly switches drawer state too. Add a per-arrangement `showsMinimizedPanes` toggle (and per-drawer equivalent).

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

VIEW (per arrangement — many views over the same data)
  ▸ position / order of those panes in the layout
  ▸ minimize state per pane (which panes are minimized)
  ▸ show-minimized toggle (whether minimized panes appear at all
    in this arrangement, or are hidden entirely)
  ▸ drawer expand / collapse
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

VIEW operations               affect only the active arrangement
  ▸ rearrange (drag within tab)   → active arrangement layout only
  ▸ minimize / unminimize         → active arrangement
  ▸ toggle showsMinimizedPanes    → active arrangement
  ▸ resize divider                → active arrangement layout
  ▸ expand / collapse drawer      → active arrangement drawerView
  ▸ set active pane               → active arrangement
  ▸ set active drawer child       → active arrangement drawerView
  ▸ create / rename / delete arrangement
  ▸ switch active arrangement
```

The validator gates every command against this classification.

## 4. Current state shape (as of 2026-05-02)

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

Reads from:
  ▸ `WorkspaceTabArrangementAtom` — arrangement state
  ▸ `WorkspacePaneAtom` — Pane / Drawer identity + paneIds
  ▸ `ManagementLayerAtom` — `isActive` for the showsMinimized
    override

```swift
@MainActor
struct WorkspaceArrangementViewDerived {
    let tabArrangementAtom: WorkspaceTabArrangementAtom
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
I6. For every pane P in tab.allPaneIds where P has a drawer:
      every arrangement.drawerViews must contain an entry for
      P.drawer.drawerId. The drawer view's layout contains all
      drawerPaneIds.
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
  ▸ collapseAllDrawers       → collapseAllDrawersInActive (also touches
                                isExpanded on WorkspacePaneAtom — see §8.3)
  ▸ setActiveDrawerPane      → setActiveDrawerPaneInActive

KEPT on WorkspacePaneAtom
  ▸ toggleDrawer             → mutates Drawer.isExpanded (global)
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
      arrangement.activePaneId = first unminimized remaining pane
    drop arrangement.drawerViews[paneId.drawer.drawerId] if any
  remove paneId from tab.allPaneIds

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
  // Drawer.isExpanded (on Drawer struct) — set to true for the
  // active drawer toggle path; calibration does NOT touch it
  // (Q4 — isExpanded is global, controlled by toggleDrawer)

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
         arrangement.activePaneId = first unminimized remaining
       drop arrangement.drawerViews[anyDrawerOnPane.drawerId]
     remove paneId from source.allPaneIds
     if source.allPaneIds.isEmpty: tab is closed (separate concern)
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
       if pane has a drawer:
         create fresh DrawerView entry for drawer.drawerId
         seed view.layout with all drawer.paneIds (default arrangement)
5. drawer pane snapshots stay attached to the parent — they
   travel with the pane (Pane + Drawer + child Panes)
6. EventBus emits .paneMovedAcrossTabs
```

Atomic: either the whole move succeeds or none of it does.

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

These all change semantics from "mutate Drawer struct" to "mutate
active arrangement's drawerView" — but the command contract stays
the same. Callers don't change.

NEW:

```
.movePaneAcrossTabs(paneId:, sourceTabId:, destTabId:,
                    targetPaneId:, direction:, position:)
.reorderTab(tabId:, newIndex:)
.setShowsMinimizedPanes(tabId:, value:)
.setShowsMinimizedDrawerPanes(parentPaneId:, value:)
```

REMOVED: none. (Subset-arrangement creation was the only feature
killed by removing visiblePaneIds; see §16.)

## 14. Migration — decoding existing user workspaces

On decode of old persisted state:

```
PaneArrangement old → new
  layout              → layout (unchanged)
  minimizedPaneIds    → minimizedPaneIds (unchanged)
  visiblePaneIds      → DISCARDED (derived now)
  showsMinimizedPanes → true  (default preserves today's behavior:
                              minimized panes shown as collapsed bars.
                              Q1 fix — earlier draft had `false` which
                              would break by hiding minimized panes.)
  activePaneId        → seeded from old TabArrangementState
                        .activePaneId for the active arrangement;
                        nil for others
  drawerViews         → seeded from each parent pane's old Drawer:
                          for each pane in arrangement.layout where
                          pane.drawer != nil AND pane.drawer.paneIds
                          is non-empty:
                            drawerViews[pane.drawer.drawerId] =
                              DrawerView(
                                layout: pane.drawer.layout (old),
                                activeChildId: pane.drawer.activeChildId,
                                minimizedPaneIds: [],  // was transient
                                showsMinimizedPanes: true   // Q1
                              )
                          // empty drawers get NO entry (Q4)

Drawer old → new
  paneIds             → paneIds (unchanged)
  layout              → DROPPED (moved to drawerViews per arrangement)
  activeChildId       → DROPPED (moved to drawerViews)
  minimizedPaneIds    → DROPPED (was transient anyway)
  isExpanded          → KEPT on Drawer (Q4 — global, not per-
                        arrangement)

Drawer (new) gains
  drawerId            → seeded with a fresh UUID on first decode;
                        persisted afterwards
  parentPaneId        → seeded from owning Pane's id
```

Migration runs once on first decode under the new schema. After
that, the new shape is canonical. No backward-compat shim.

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

No new store, no new persistence file. The schema version on
`WorkspaceStore` increments to indicate the new shape.

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

Schema version on `WorkspaceStore` increments. **Hard cutover, no
back-compat shim** (per CLAUDE.md "hard cutover, no backward
compatibility"). Migration runs once on first decode of the new
schema (§14).

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
  arrangement.reason = "ok" | "drawer_to_main_blocked" |
                       "main_to_drawer_blocked" |
                       "tab_into_tab_blocked" |
                       "default_arrangement_undeletable" |
                       "cross_tab_pane_not_found" |
                       "drawer_pane_cannot_cross_tabs" | ...
                       (string enum, must be one of the recognized
                        values — fail tests on unrecognized reason)
```

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

In DEBUG builds, an invariant violation also fires `assertionFailure`.
In RELEASE, it logs via the trace + os.Logger.error and does not
crash. The trace record is the persistent record of what happened.

### 16.5.3 ServiceContext correlation

When a PaneActionCommand enters `WorkspaceCommandResolver`, it
generates a fresh `agentStudioCorrelationID` and stashes it on
`ServiceContext`. All downstream traces (validation, mutation,
calibration, atom mutation, EventBus emission) inherit this
correlation ID via `ServiceContext.current`, so the entire command
lifecycle is traceable end-to-end via a single ID.

This matches the pattern used by GitWorkingDirectoryProjector for
`correlationId` carry-forward (per workspace_data_architecture.md
§ Actor Responsibilities).

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
    rendering when false
  ▸ per-drawer toggle does the same for drawer panes
  ▸ derived visiblePaneIds matches the rule in §6.2

VisiblePaneIdsDerivationTests
  ▸ given (layout, minimized, showsMinimized), derived
    visiblePaneIds matches §6.2 rule

WorkspacePaneAtomDrawerStrippedTests
  ▸ Drawer struct only carries identity + paneIds
  ▸ moveDrawerPane / resizeDrawerPane / etc. are removed from
    WorkspacePaneAtom (moved to TabArrangementAtom)
  ▸ remaining DATA methods (addDrawerPane / removeDrawerPane /
    detachDrawerPane / restoreDrawerPane) work as before

MigrationTests
  ▸ old persisted state with subset arrangements decodes:
      visiblePaneIds dropped, layout retained
  ▸ old Drawer.layout/activeChildId/isExpanded migrated into
    DrawerView in default arrangement
  ▸ old transient minimizedPaneIds (drawer) starts empty (no change)
  ▸ schema version bumped, old version unsupported

ObservabilityTests
  ▸ minimizePane emits arrangement.command_received +
    arrangement.command_validated(decision=accepted) +
    arrangement.view_op_committed
  ▸ rejected commands emit .command_validated with decision=rejected
    AND a recognized reason string (test against the enum of
    allowed reason values — fail on unrecognized)
  ▸ cross-tab move emits .cross_tab_move_started +
    .cross_tab_move_committed with non-zero source/dest calibration
    counts
  ▸ adding a drawer pane emits .calibration_started +
    .calibration_applied with affected_arrangement_count >= 1
  ▸ correlation_id propagates from received → validated → committed
    (assert via captured trace records that all share the same
    agentstudio.correlation_id attribute)
  ▸ invariant violation in DEBUG fires assertionFailure AND emits
    arrangement.invariant_violation; in RELEASE only emits trace
  ▸ tracing default-off: no records emitted unless
    AGENTSTUDIO_TRACE_TAGS includes "arrangement" (or "*")
```

## 19. Implementation order

Suggested phasing (one-PR-each-phase to keep diffs reviewable):

```
Phase 1: schema-only changes + trace tag wiring (types, no behavior)
  ▸ add Drawer.drawerId, Drawer.parentPaneId
  ▸ add PaneArrangement.showsMinimizedPanes, .activePaneId,
    .drawerViews
  ▸ add DrawerView struct
  ▸ add AgentStudioTraceTag case `arrangement` (raw value
    "arrangement")
  ▸ Codable forward (read old, write new)
  ▸ migration on decode (emit arrangement.calibration_applied
    with cause="migration_decode" so first-run migrations are
    diagnosable)
  ▸ NO behavior changes yet — old code paths still work
  ▸ tests: migration + invariant assertions + trace records on
    migration path

Phase 2: WorkspaceArrangementViewDerived + HARD cutover of visiblePaneIds
  ▸ create WorkspaceArrangementViewDerived atom (§6.1)
  ▸ replace every read of arrangement.visiblePaneIds with
    derived atom calls
  ▸ DELETE the visiblePaneIds field entirely (Q5 — hard cutover,
    no soft transitional phase)
  ▸ delete ALL writes to visiblePaneIds in same PR
  ▸ wire ManagementLayerAtom into the derived atom for the
    showsMinimized override (Q1 derived/computed approach)
  ▸ tests: derivation correctness + management override behavior

Phase 3: move drawer VIEW state mutators atom-to-atom
  ▸ implement *InActive methods on WorkspaceTabArrangementAtom
    (NOT toggleDrawer — that stays on WorkspacePaneAtom per Q4)
  ▸ rewire PaneCoordinator+ActionExecution.swift to call new
    methods
  ▸ leave Drawer struct fields in place but unused for VIEW
  ▸ wire arrangement.command_received / .command_validated /
    .view_op_committed records at the resolver / validator /
    coordinator boundaries
  ▸ wire ServiceContext.agentStudioCorrelationID at command
    resolver entry point
  ▸ tests: switching arrangements correctly switches drawer
    state + trace assertions on view ops

Phase 4: shrink Drawer struct, calibration coordinator
  ▸ remove Drawer.layout / .activeChildId / .minimizedPaneIds
    (KEEP Drawer.isExpanded — Q4)
  ▸ implement WorkspaceMutationCoordinator calibration
  ▸ rewire DATA mutators (addDrawerPane / removeDrawerPane)
    to call calibration
  ▸ delete activePaneId from TabArrangementState
    (NOTE: visiblePaneIds was already deleted in Phase 2)
  ▸ wire arrangement.calibration_started / .calibration_applied
    records around every calibration cycle (single record per
    cycle, NOT per arrangement — see §16.5.4)
  ▸ wire arrangement.tab_close_committed for tab close paths
    (cause: "user_close" or "cross_tab_move_drained")
  ▸ tests: full system test — DATA + VIEW operations end-to-end +
    calibration trace assertions (record count = 1 per cycle,
    affected_arrangement_count matches actual mutations)

Phase 5: cross-tab pane move + tab drag rules + auto-close
  ▸ add movePaneAcrossTabs command
  ▸ add reorderTab command
  ▸ implement validator rules V1-V9
  ▸ wire drag layer
  ▸ wire source-tab auto-close when last pane moves out (Q2)
  ▸ wire arrangement.cross_tab_move_started / _committed records
    (with source_tab_auto_closed flag)
  ▸ tests: cross-tab + tab drag scenarios + cross-tab trace
    assertions (source_arrangements_calibrated,
    dest_arrangements_calibrated, and source_tab_auto_closed flag)

Phase 6: showsMinimizedPanes UI
  ▸ add toggle in arrangement panel UI
  ▸ persist per-arrangement
  ▸ tests: UI interaction
```

Phases 1-4 ship the state-shape change. Phases 5-6 ship the
new behaviors that the new shape enables.

## 20. Open questions / future work

None blocking. All design decisions made above. Spec 2 will pick
this up as foundation.

---

**Reviewer checklist before approval:**

- [ ] DATA vs VIEW classification (§3.1) matches your mental model
- [ ] Drawer.isExpanded stays GLOBAL per drawer (Q4) — empty drawers
      have NO drawerView entry; the panel-expand state is on Drawer
- [ ] Q1 management mode override is computed-only (no save/restore
      dance) — derived atom reads ManagementLayerAtom.isActive
- [ ] Invariants (§7) are complete and correct
- [ ] visiblePaneIds removal (§16) is acceptable (subset
      arrangements feature loss); HARD cutover in Phase 2
- [ ] showsMinimizedPanes default = true on migration (preserves
      today's behavior)
- [ ] WorkspaceArrangementViewDerived (§6.1) — new derived atom
      placement matches existing pattern (WorkspaceFocusDerived,
      etc.)
- [ ] Cross-tab move (§10) auto-closes source tab if it drains
      to zero panes (Q2)
- [ ] Migration strategy (§14) safely handles existing user state
- [ ] Persistence tier alignment (§15.1) — Tier A canonical is
      the right home (vs Tier B cache or Tier C UI)
- [ ] Observability (§16.5) — trace tag, records (incl.
      tab_close_committed), correlation, and performance approach
      are right; reasons enum is complete
- [ ] Phased implementation (§19) is the right granularity
- [ ] Test surface (§18) covers the right scenarios
