# Workspace UI State Segregation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move all workspace-scoped selection and window/layout presentation state out of canonical workspace persistence and into `WorkspaceUIStore` / `workspace.ui.json`, leaving `WorkspaceStore` and canonical models responsible only for actual workspace structure.

**Architecture:** Canonical workspace data answers `what exists`. Workspace UI state answers `what is currently selected` and `how it was being viewed`. That means `activeTabId`, selected pane/arrangement IDs, drawer selection IDs, `sidebarWidth`, `sidebarCollapsed`, and `windowFrame` all belong to `WorkspaceUIStore`. One pure reconciliation helper repairs stale UX IDs against the current canonical UUID sets. The event bus remains a fact transport and is not used for UX writes.

**Tech Stack:** Swift 6.2, AppKit, `@Observable`, Swift Testing, mise build/test/lint

---

## Scope Assumptions

This plan assumes the current single-window-per-workspace model.

That means:
- `windowFrame` is treated as workspace-scoped UX state for now
- `sidebarCollapsed` is treated as workspace-scoped UX state for now

If the product later supports multiple live windows for a single workspace, these fields will need a more specific window-scoped ownership model. That future change is out of scope here.

## Non-Goals

This plan does not change:
- pane runtime / Ghostty sizing behavior
- zmx session lifecycle or protocol
- event bus responsibilities
- canonical layout structure itself
- global app preferences outside workspace-scoped UX

## Why This Plan Exists

The architecture docs already describe three persistence tiers:

- canonical workspace state in `workspace.state.json`
- derived cache in `workspace.cache.json`
- workspace-scoped UI state in `workspace.ui.json`

See:
- [workspace_data_architecture.md](../../architecture/workspace_data_architecture.md)
- [component_architecture.md](../../architecture/component_architecture.md)

But the current code does not actually follow that split.

Direct observations:

- `WorkspaceStore` still owns `activeTabId`, `sidebarWidth`, and `windowFrame` in [WorkspaceStore.swift](../../../Sources/AgentStudio/Core/Stores/WorkspaceStore.swift).
- `WorkspacePersistor.PersistableState` still writes those fields into canonical `workspace.state.json` in [WorkspacePersistor.swift](../../../Sources/AgentStudio/Core/Stores/WorkspacePersistor.swift).
- `Tab` still persists `activeArrangementId` and `activePaneId` in [Tab.swift](../../../Sources/AgentStudio/Core/Models/Tab.swift).
- `Drawer` still persists `activePaneId` in [Drawer.swift](../../../Sources/AgentStudio/Core/Models/Drawer.swift).
- `MainWindowController` persists `windowFrame` to `UserDefaults` in [MainWindowController.swift](../../../Sources/AgentStudio/App/MainWindowController.swift).
- `MainSplitViewController` persists `sidebarCollapsed` to `UserDefaults` in [MainSplitViewController.swift](../../../Sources/AgentStudio/App/MainSplitViewController.swift).
- `WorkspaceUIStore` currently owns only sidebar/filter decoration state in [WorkspaceUIStore.swift](../../../Sources/AgentStudio/Core/Stores/WorkspaceUIStore.swift).

That produces an inconsistent model:

```text
UX state is split across:
- WorkspaceStore
- Tab / Drawer canonical models
- WorkspaceUIStore
- UserDefaults
```

This plan fixes that by making the ownership boundary explicit and complete.

## Design Rules

### Rule 1: Canonical state is structural only

Canonical state is the minimum stable data required to reconstruct the workspace itself.

Allowed in `WorkspaceStore` / `workspace.state.json`:
- panes
- pane UUIDs
- tabs as structural containers
- tab UUIDs
- arrangements as entities
- layouts / split tree / drawer structure
- repo/worktree associations

Excluded from canonical state:
- currently selected tab
- currently selected pane inside a tab
- currently selected arrangement inside a tab
- currently selected drawer pane
- sidebar width
- sidebar collapsed state
- window frame
- any other presentation-only state

### Rule 2: Workspace UI state owns both selection and presentation

Workspace UI state captures how a workspace was last being viewed.

Target `WorkspaceUIStore` / `workspace.ui.json` fields:
- `activeTabId: UUID?`
- `activePaneIdByTabId: [UUID: UUID]`
- `activeArrangementIdByTabId: [UUID: UUID]`
- `activeDrawerPaneIdByParentPaneId: [UUID: UUID]`
- `sidebarWidth: CGFloat`
- `sidebarCollapsed: Bool`
- `windowFrame: CGRect?`
- existing `expandedGroups`
- existing `checkoutColors`
- existing `filterText`
- existing `isFilterVisible`

### Rule 3: All references use stable UUIDs

Any UX state that points at a workspace entity must reference it by stable UUID only.

Allowed:
- `activeTabId: UUID?`
- `activePaneIdByTabId: [UUID: UUID]`
- `activeArrangementIdByTabId: [UUID: UUID]`
- `activeDrawerPaneIdByParentPaneId: [UUID: UUID]`

Disallowed:
- selected tab index
- pane title strings
- path strings
- visual order numbers

### Rule 4: Computed properties are not persisted fields

This migration must distinguish between:

```text
persisted UX state
vs
computed convenience lookups
```

Examples:
- `activeTabId` is persisted UX state
- `activePaneIdByTabId` is persisted UX state
- `selectedTab(tabs:activeTabId:)` is a computed lookup
- `selectedArrangement(tab:activeArrangementId:)` is a computed lookup
- `selectedLayout(tab:activeArrangementId:)` is a computed lookup

The system must not reintroduce structural ownership of UX state just because a computed convenience accessor is useful.

### Rule 5: One owner for selection repair

Selection validity and repair must have one explicit owner:

```text
WorkspaceUIStore owns the persisted selection IDs.
WorkspaceUISelectionReconciler owns the pure repair logic.
Controllers/coordinators sequence the call, but do not invent policy ad hoc.
```

The reconciler must:
- remove stale tab references
- remove stale pane references
- remove stale arrangement references
- fall back to valid first/default UUIDs where policy requires one
- never mutate canonical structure

Fallback policy is deterministic:

```text
invalid selected tab
  -> first remaining tab or nil

invalid selected arrangement
  -> tab.defaultArrangement.id

invalid selected pane
  -> first pane in the selected arrangement layout or nil

invalid selected drawer pane
  -> first remaining drawer pane or nil
```

### Rule 6: No event bus for UX writes

Correct flow:

```text
AppKit lifecycle / user action
        |
        v
controller or coordinator ingress
        |
        v
WorkspaceUIStore mutation
        |
        v
workspace.ui.json
```

Not:

```text
AppKit notification
  -> event bus
  -> command routing
  -> UI state mutation
```

The event bus remains for runtime/system facts only.

## Target File Ownership

### Canonical state
- `Sources/AgentStudio/Core/Stores/WorkspaceStore.swift`
- `Sources/AgentStudio/Core/Stores/WorkspacePersistor.swift` (`PersistableState`)
- `Sources/AgentStudio/Core/Models/Tab.swift`
- `Sources/AgentStudio/Core/Models/Drawer.swift`
- `~/.agentstudio/workspaces/<id>.workspace.state.json`

### Workspace-scoped UX state
- `Sources/AgentStudio/Core/Stores/WorkspaceUIStore.swift`
- `Sources/AgentStudio/Core/Stores/WorkspaceUISelection.swift`
- `Sources/AgentStudio/Core/Stores/WorkspaceUISelectionReconciler.swift`
- `Sources/AgentStudio/Core/Stores/WorkspacePersistor.swift` (`PersistableUIState`)
- `~/.agentstudio/workspaces/<id>.workspace.ui.json`

### AppKit ingress / consumers
- `Sources/AgentStudio/App/MainWindowController.swift`
- `Sources/AgentStudio/App/MainSplitViewController.swift`
- `Sources/AgentStudio/App/Panes/PaneTabViewController.swift`
- `Sources/AgentStudio/App/AppDelegate.swift`
- `Sources/AgentStudio/App/PaneCoordinator+ActionExecution.swift`
- `Sources/AgentStudio/App/PaneCoordinator+ViewLifecycle.swift`
- `Sources/AgentStudio/Core/Views/Splits/ActiveTabContent.swift`
- `Sources/AgentStudio/Core/Views/Splits/TerminalSplitContainer.swift`
- `Sources/AgentStudio/Core/Views/Drawer/DrawerPanel.swift`
- `Sources/AgentStudio/Core/Views/TabBarAdapter.swift`
- `Sources/AgentStudio/Core/Actions/ActionResolver.swift`
- `Sources/AgentStudio/Core/PaneRuntime/Dispatch/RuntimeTargetResolver.swift`

### Tests
- `Tests/AgentStudioTests/Core/Stores/WorkspaceUIStoreTests.swift`
- `Tests/AgentStudioTests/Core/Stores/WorkspacePersistorTests.swift`
- `Tests/AgentStudioTests/Core/Stores/WorkspaceStoreArchitectureTests.swift`
- `Tests/AgentStudioTests/Core/Models/TabTests.swift`
- `Tests/AgentStudioTests/App/PaneTabViewController*`
- `Tests/AgentStudioTests/App/ActionExecutorTests.swift`

---

## Task 1: Add Complete Workspace-Scoped UX State to WorkspaceUIStore

**Files:**
- Modify: `Sources/AgentStudio/Core/Stores/WorkspaceUIStore.swift`
- Create: `Tests/AgentStudioTests/Core/Stores/WorkspaceUIStoreTests.swift` (if missing)

- [ ] **Step 1: Write failing tests for selection and window/layout UX state**

Cover all new fields:
- `activeTabId`
- `activePaneIdByTabId`
- `activeArrangementIdByTabId`
- `activeDrawerPaneIdByParentPaneId`
- `sidebarWidth`
- `sidebarCollapsed`
- `windowFrame`

Example tests:

```swift
@Test("WorkspaceUIStore starts with default selection and window layout state")
func test_defaults() {
    let store = WorkspaceUIStore()

    #expect(store.activeTabId == nil)
    #expect(store.activePaneIdByTabId.isEmpty)
    #expect(store.activeArrangementIdByTabId.isEmpty)
    #expect(store.activeDrawerPaneIdByParentPaneId.isEmpty)
    #expect(store.sidebarWidth == 250)
    #expect(store.sidebarCollapsed == false)
    #expect(store.windowFrame == nil)
}

@Test("WorkspaceUIStore updates selection by stable UUID")
func test_selectionMutators() {
    let store = WorkspaceUIStore()
    let tabId = UUID()
    let paneId = UUID()
    let arrangementId = UUID()
    let parentPaneId = UUID()
    let drawerPaneId = UUID()

    store.setActiveTabId(tabId)
    store.setActivePaneId(paneId, forTabId: tabId)
    store.setActiveArrangementId(arrangementId, forTabId: tabId)
    store.setActiveDrawerPaneId(drawerPaneId, forParentPaneId: parentPaneId)

    #expect(store.activeTabId == tabId)
    #expect(store.activePaneIdByTabId[tabId] == paneId)
    #expect(store.activeArrangementIdByTabId[tabId] == arrangementId)
    #expect(store.activeDrawerPaneIdByParentPaneId[parentPaneId] == drawerPaneId)
}
```

- [ ] **Step 2: Run focused tests to verify failure**

Run:
```bash
SWIFT_BUILD_DIR=".build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8)" swift test --build-path "$SWIFT_BUILD_DIR" --filter "WorkspaceUIStoreTests"
```
Expected: FAIL with missing properties or mutators.

- [ ] **Step 3: Add the new stored fields and mutators**

Required additions in `WorkspaceUIStore.swift`:
- `private(set) var activeTabId: UUID? = nil`
- `private(set) var activePaneIdByTabId: [UUID: UUID] = [:]`
- `private(set) var activeArrangementIdByTabId: [UUID: UUID] = [:]`
- `private(set) var activeDrawerPaneIdByParentPaneId: [UUID: UUID] = [:]`
- `private(set) var sidebarWidth: CGFloat = 250`
- `private(set) var sidebarCollapsed: Bool = false`
- `private(set) var windowFrame: CGRect?`

Required mutators:
- `setActiveTabId(_ id: UUID?)`
- `setActivePaneId(_ paneId: UUID?, forTabId tabId: UUID)`
- `setActiveArrangementId(_ arrangementId: UUID?, forTabId tabId: UUID)`
- `setActiveDrawerPaneId(_ paneId: UUID?, forParentPaneId parentPaneId: UUID)`
- `setSidebarWidth(_ width: CGFloat)`
- `setSidebarCollapsed(_ isCollapsed: Bool)`
- `setWindowFrame(_ frame: CGRect?)`

Also update `clear()` so it resets all UX state to defaults.

- [ ] **Step 4: Run focused tests to verify pass**

Run:
```bash
SWIFT_BUILD_DIR=".build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8)" swift test --build-path "$SWIFT_BUILD_DIR" --filter "WorkspaceUIStoreTests"
```
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/AgentStudio/Core/Stores/WorkspaceUIStore.swift \
  Tests/AgentStudioTests/Core/Stores/WorkspaceUIStoreTests.swift
git commit -m "feat: add workspace-scoped selection and window layout ui state"
```

---

## Task 2: Add an Explicit WorkspaceUISelectionReconciler

**Files:**
- Create: `Sources/AgentStudio/Core/Stores/WorkspaceUISelection.swift`
- Create: `Sources/AgentStudio/Core/Stores/WorkspaceUISelectionReconciler.swift`
- Create: `Tests/AgentStudioTests/Core/Stores/WorkspaceUISelectionReconcilerTests.swift`

- [ ] **Step 1: Write failing tests for selection repair**

Tests must prove the reconciler:
- removes stale `activeTabId`
- repairs missing selected pane to the first valid pane in that selected tab
- repairs missing selected arrangement to the default arrangement
- repairs stale drawer pane selection to the first valid drawer pane
- never mutates canonical tab/drawer structure

Example:

```swift
@Test("reconciler repairs stale selection ids without mutating canonical structure")
func test_reconcileSelectionIds() {
    let tabId = UUID()
    let validPaneId = UUID()
    let validArrangementId = UUID()

    let tab = Tab(
        id: tabId,
        name: "Tab",
        panes: [validPaneId],
        arrangements: [/* default arrangement with validArrangementId */]
    )

    let uiState = WorkspaceUISelectionState(
        activeTabId: tabId,
        activePaneIdByTabId: [tabId: UUID()],
        activeArrangementIdByTabId: [tabId: UUID()]
    )

    let repaired = WorkspaceUISelectionReconciler.reconcile(
        uiState: uiState,
        tabs: [tab],
        panesById: [validPaneId: /* Pane */]
    )

    #expect(repaired.activePaneIdByTabId[tabId] == validPaneId)
    #expect(repaired.activeArrangementIdByTabId[tabId] == validArrangementId)
}
```

- [ ] **Step 2: Run focused tests to verify failure**

Run:
```bash
SWIFT_BUILD_DIR=".build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8)" swift test --build-path "$SWIFT_BUILD_DIR" --filter "WorkspaceUISelectionReconcilerTests"
```
Expected: FAIL because reconciler does not exist.

- [ ] **Step 3: Implement the pure reconciler**

Design the reconciler as a pure helper that:
- accepts UI-owned selection state and canonical tabs/panes
- returns repaired UI-owned selection state
- does not touch persistence or stores directly

Do not put this policy in random coordinators.

Also add a dedicated selection-only type in `WorkspaceUISelection.swift`:

```swift
struct WorkspaceUISelection: Codable, Equatable {
    var activeTabId: UUID?
    var activePaneIdByTabId: [UUID: UUID]
    var activeArrangementIdByTabId: [UUID: UUID]
    var activeDrawerPaneIdByParentPaneId: [UUID: UUID]
}
```

This keeps selection repair isolated from unrelated window/filter presentation fields.

- [ ] **Step 4: Run focused tests to verify pass**

Run the same command as Step 2.
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/AgentStudio/Core/Stores/WorkspaceUISelectionReconciler.swift \
  Tests/AgentStudioTests/Core/Stores/WorkspaceUISelectionReconcilerTests.swift
git commit -m "feat: add explicit reconciler for workspace ui selection ids"
```

---

## Task 3: Move UI Persistence Into PersistableUIState

**Files:**
- Modify: `Sources/AgentStudio/Core/Stores/WorkspacePersistor.swift`
- Modify: `Tests/AgentStudioTests/Core/Stores/WorkspacePersistorTests.swift`

- [ ] **Step 1: Write failing persistence tests for the expanded UI snapshot**

Add tests that verify `PersistableUIState` round-trips:
- `activeTabId`
- `activePaneIdByTabId`
- `activeArrangementIdByTabId`
- `activeDrawerPaneIdByParentPaneId`
- `sidebarWidth`
- `sidebarCollapsed`
- `windowFrame`
- existing UI fields

- [ ] **Step 2: Run focused persistor tests and verify failure**

Run:
```bash
SWIFT_BUILD_DIR=".build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8)" swift test --build-path "$SWIFT_BUILD_DIR" --filter "WorkspacePersistorTests"
```
Expected: FAIL with missing UI fields or mismatched encoding.

- [ ] **Step 3: Extend PersistableUIState and remove UX fields from PersistableState**

In `WorkspacePersistor.swift`:

Add to `PersistableUIState`:
- `activeTabId: UUID?`
- `activePaneIdByTabId: [UUID: UUID]`
- `activeArrangementIdByTabId: [UUID: UUID]`
- `activeDrawerPaneIdByParentPaneId: [UUID: UUID]`
- `sidebarWidth: CGFloat`
- `sidebarCollapsed: Bool`
- `windowFrame: CGRect?`

Remove from `PersistableState`:
- `activeTabId`
- `sidebarWidth`
- `windowFrame`

Do not add compatibility shims that persist the same field in both files.

- [ ] **Step 4: Run focused persistor tests and verify pass**

Run the same command as Step 2.
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/AgentStudio/Core/Stores/WorkspacePersistor.swift \
  Tests/AgentStudioTests/Core/Stores/WorkspacePersistorTests.swift
git commit -m "feat: persist complete workspace ui state in workspace ui file"
```

---

## Task 4: Remove Selection Ownership From Canonical Models

**Files:**
- Modify: `Sources/AgentStudio/Core/Models/Tab.swift`
- Modify: `Sources/AgentStudio/Core/Models/Drawer.swift`
- Modify: `Tests/AgentStudioTests/Core/Models/TabTests.swift`
- Modify: any drawer model tests

- [ ] **Step 1: Write failing model tests for canonical-only structure**

Add tests proving:
- `Tab` no longer persists `activeArrangementId`
- `Tab` no longer persists `activePaneId`
- `Drawer` no longer persists `activePaneId`
- canonical `Tab` still persists arrangements/layout entities themselves

- [ ] **Step 2: Run focused model tests to verify failure**

Run:
```bash
SWIFT_BUILD_DIR=".build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8)" swift test --build-path "$SWIFT_BUILD_DIR" --filter "TabTests|Drawer"
```
Expected: FAIL because canonical models still carry selection state.

- [ ] **Step 3: Remove persisted selection fields from `Tab` and `Drawer`**

In `Tab.swift`:
- remove stored properties:
  - `activeArrangementId`
  - `activePaneId`
- update initializers
- update `CodingKeys`
- remove computed helpers that hide selection ownership:
  - `activeArrangement`
  - `paneIds`
  - `isSplit`
  - `layout`
  if they depend on selected arrangement state

Replace them with canonical-only helpers such as:
- `defaultArrangement`
- `arrangement(id:)`
- `defaultPaneIds`

In `Drawer.swift`:
- remove persisted `activePaneId`
- update coding keys and initializers

- [ ] **Step 4: Add explicit computed selection helpers in a non-owning location**

Create or extend a helper file so selected-view convenience is explicit and parameterized. Prefer a dedicated helper such as:
- `Sources/AgentStudio/Core/Models/SelectedWorkspaceView.swift`

Add helpers such as:
- `selectedTab(tabs:selectedTabId:)`
- `selectedArrangement(tab:selectedArrangementId:)`
- `selectedPaneId(tab:selectedPaneId:selectedArrangementId:)`
- `selectedDrawerPaneId(drawer:selectedPaneId:)`

These helpers must accept UI selection IDs as input rather than reading hidden store-owned state.

- [ ] **Step 5: Run focused model tests and verify pass**

Run the same command as Step 2.
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add Sources/AgentStudio/Core/Models/Tab.swift \
  Sources/AgentStudio/Core/Models/Drawer.swift \
  Tests/AgentStudioTests/Core/Models/TabTests.swift
git commit -m "refactor: remove selection ownership from canonical tab and drawer models"
```

---

## Task 5: Remove UX Ownership From WorkspaceStore

**Files:**
- Modify: `Sources/AgentStudio/Core/Stores/WorkspaceStore.swift`
- Modify: `Tests/AgentStudioTests/Core/Stores/WorkspaceStoreArchitectureTests.swift`
- Modify: any existing `WorkspaceStoreTests` that assume `activeTabId` ownership

- [ ] **Step 1: Write failing architecture tests for canonical-only ownership**

Add tests that enforce:
- canonical restore does not depend on `activeTabId`, `sidebarWidth`, `windowFrame`
- canonical persistence excludes those keys
- structural mutations do not own UI selection policy

- [ ] **Step 2: Run focused architecture tests and verify failure**

Run:
```bash
SWIFT_BUILD_DIR=".build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8)" swift test --build-path "$SWIFT_BUILD_DIR" --filter "WorkspaceStoreArchitectureTests"
```
Expected: FAIL because canonical still owns UX fields.

- [ ] **Step 3: Remove persisted UX fields and mutators from WorkspaceStore**

In `WorkspaceStore.swift`:
- remove stored properties:
  - `activeTabId`
  - `sidebarWidth`
  - `windowFrame`
- remove mutators:
  - `setSidebarWidth(_:)`
  - `setWindowFrame(_:)`
- update `restore()` to stop reading those values from canonical state
- update `persistNow()` to stop writing those values into `PersistableState`

Structural methods must stop choosing selected tab as a hidden side effect.

- [ ] **Step 4: Change structural methods to return structural outcomes only**

For methods that currently mutate structure and selection together:
- `appendTab`
- `closeTab`
- `selectTab`
- restore/prune helpers
- tab merge/split flows

make them return enough information for the caller to sequence UI selection updates, for example:
- removed tab id
- surviving tab ids
- suggested default/fallback tab id if the canonical operation naturally computes one

Do not let `WorkspaceStore` mutate `WorkspaceUIStore` directly.

- [ ] **Step 5: Run focused WorkspaceStore tests and fix downstream assumptions**

Run:
```bash
SWIFT_BUILD_DIR=".build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8)" swift test --build-path "$SWIFT_BUILD_DIR" --filter "WorkspaceStore"
```
Expected: initial failures across architecture/restore tests; update tests until PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources/AgentStudio/Core/Stores/WorkspaceStore.swift \
  Tests/AgentStudioTests/Core/Stores/WorkspaceStoreArchitectureTests.swift \
  Tests/AgentStudioTests/Core/Stores/WorkspaceStoreTests.swift
git commit -m "refactor: remove workspace ui ownership from WorkspaceStore"
```

---

## Task 6: Route AppKit and Command Selection/Window UX Through WorkspaceUIStore

**Files:**
- Modify: `Sources/AgentStudio/App/MainWindowController.swift`
- Modify: `Sources/AgentStudio/App/MainSplitViewController.swift`
- Modify: `Sources/AgentStudio/App/Panes/PaneTabViewController.swift`
- Modify: `Sources/AgentStudio/App/AppDelegate.swift`
- Modify: `Sources/AgentStudio/App/PaneCoordinator+ActionExecution.swift`
- Modify: `Sources/AgentStudio/App/PaneCoordinator+ViewLifecycle.swift`
- Modify: `Sources/AgentStudio/App/ActionExecutor.swift`
- Modify: `Sources/AgentStudio/Core/Views/TabBarAdapter.swift`
- Modify: `Sources/AgentStudio/Core/Views/Splits/ActiveTabContent.swift`
- Modify: `Sources/AgentStudio/Core/Views/Splits/TerminalSplitContainer.swift`
- Modify: `Sources/AgentStudio/Core/Views/Drawer/DrawerPanel.swift`
- Modify: `Sources/AgentStudio/Core/Actions/ActionResolver.swift`
- Modify: `Sources/AgentStudio/Core/PaneRuntime/Dispatch/RuntimeTargetResolver.swift`
- Test: targeted App tests already covering launch/sidebar/tab selection behavior

- [ ] **Step 1: Write failing tests for AppKit ingress writing UX state through WorkspaceUIStore**

Add tests for:
- selecting a tab updates `WorkspaceUIStore.activeTabId`
- selecting a pane updates `WorkspaceUIStore.activePaneIdByTabId`
- switching arrangement updates `WorkspaceUIStore.activeArrangementIdByTabId`
- selecting a drawer pane updates `WorkspaceUIStore.activeDrawerPaneIdByParentPaneId`
- sidebar collapse/expand updates `WorkspaceUIStore.sidebarCollapsed`
- sidebar divider changes update `WorkspaceUIStore.sidebarWidth`
- window move/resize updates `WorkspaceUIStore.windowFrame`

- [ ] **Step 2: Run focused tests and verify failure**

Run:
```bash
SWIFT_BUILD_DIR=".build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8)" swift test --build-path "$SWIFT_BUILD_DIR" --filter "PaneTabViewController|MainSplitViewController|MainWindowController|ActionExecutorTests"
```
Expected: FAIL because call sites still read/write old ownership paths.

- [ ] **Step 3: Remove UserDefaults-based workspace-scoped UX persistence**

In `MainWindowController.swift`:
- remove `windowFrameKey`
- stop writing workspace window frame to `UserDefaults`
- write to `WorkspaceUIStore.setWindowFrame(...)`

In `MainSplitViewController.swift`:
- remove `sidebarCollapsedKey`
- stop reading/writing sidebar collapsed state from `UserDefaults`
- read/write through `WorkspaceUIStore`

If a value is truly global, move it into a dedicated global preferences path instead of leaving it ad hoc in `UserDefaults`.

- [ ] **Step 4: Move all selection writes to WorkspaceUIStore**

Any place that currently changes:
- selected tab
- selected pane
- selected arrangement
- selected drawer pane

through canonical state must instead:
- mutate structural data in `WorkspaceStore` if needed
- mutate UX selection in `WorkspaceUIStore`

- [ ] **Step 5: Sequence structural mutation and UI reconciliation in one synchronous `@MainActor` path**

For flows like “close active tab”:

```text
WorkspaceStore structural mutation
  ->
WorkspaceUISelectionReconciler.reconcile(...)
  ->
WorkspaceUIStore mutation
```

Do not insert `Task.yield()` or async hops between those steps.
Do not let observers, NotificationCenter callbacks, or deferred Tasks choose fallback selection policy.

- [ ] **Step 6: Add startup restore/load sequencing for the UI store**

At app/workspace bootstrap:
- load canonical workspace state first
- load workspace UI state second
- run the selection reconciler against current canonical tabs/panes/arrangements/drawers
- write repaired UX state back into `WorkspaceUIStore`

Do not let UI restore mutate canonical structure.

- [ ] **Step 7: Run focused controller tests and verify pass**

Run the same command as Step 2.
Expected: PASS

- [ ] **Step 8: Commit**

```bash
git add Sources/AgentStudio/App \
  Sources/AgentStudio/Core/Views \
  Sources/AgentStudio/Core/Actions \
  Sources/AgentStudio/Core/PaneRuntime \
  Tests/AgentStudioTests/App
git commit -m "refactor: route workspace selection and window layout ux through WorkspaceUIStore"
```

---

## Task 7: Update Documentation to Match Reality

**Files:**
- Modify: `docs/architecture/workspace_data_architecture.md`
- Modify: `docs/architecture/component_architecture.md`

- [ ] **Step 1: Update the property-to-file contract**

Document the new truth explicitly:

**Canonical (`workspace.state.json`)**
- panes
- pane ids
- tabs as structural containers
- arrangements as structural entities
- layouts / drawer structure
- no `activeTabId`
- no `activePaneId`
- no `activeArrangementId`
- no `drawer.activePaneId`
- no `sidebarWidth`
- no `windowFrame`

**Workspace UI (`workspace.ui.json`)**
- `activeTabId`
- `activePaneIdByTabId`
- `activeArrangementIdByTabId`
- `activeDrawerPaneIdByParentPaneId`
- `sidebarWidth`
- `sidebarCollapsed`
- `windowFrame`
- existing workspace UI preferences

- [ ] **Step 2: Update migration notes**

Replace the generic migration note with explicit statements that:
- scattered `UserDefaults` workspace UX keys are removed
- all workspace-scoped selection and window/layout UX lives in `workspace.ui.json`
- only app-global preferences belong in global prefs files

- [ ] **Step 3: Sanity-read docs against code**

Read docs and code side-by-side and verify there is no remaining contradiction around:
- `activeTabId`
- `activePaneId`
- `activeArrangementId`
- `drawer.activePaneId`

- [ ] **Step 4: Commit**

```bash
git add docs/architecture/workspace_data_architecture.md \
  docs/architecture/component_architecture.md
git commit -m "docs: align workspace ui state ownership with implementation"
```

---

## Task 8: Full Verification

**Files:**
- No code changes expected unless verification reveals issues

- [ ] **Step 1: Run formatting**

Run:
```bash
mise run format
```
Expected: success, exit code 0

- [ ] **Step 2: Run lint**

Run:
```bash
mise run lint
```
Expected: success, exit code 0

- [ ] **Step 3: Run full test suite**

Run:
```bash
mise run test
```
Expected: all tests pass, exit code 0

- [ ] **Step 4: Build app**

Run:
```bash
AGENT_RUN_ID=$(uuidgen | tr 'A-Z' 'a-z' | tr -cd 'a-z0-9' | head -c 12) mise run build
```
Expected: success, exit code 0

- [ ] **Step 5: Manual verification of persistence split**

Verify all of the following against a real workspace:

1. Delete `workspace.ui.json`
   - workspace still opens with panes/tabs/arrangements/layout intact
   - selected tab/pane/arrangement and window/sidebar presentation reset only

2. Delete `workspace.state.json`
   - UI file alone cannot reconstruct the workspace

3. Change selected tab, selected pane, arrangement, sidebar width, sidebar collapse, and window frame
   - verify only `workspace.ui.json` changes
   - verify `workspace.state.json` does not change unless structural data changed

4. Reorder tabs, add pane, close pane, change layout, add/remove arrangement
   - verify `workspace.state.json` changes appropriately
   - verify UI file changes only for selection/presentation state

- [ ] **Step 6: Final commit for verification fixes if needed**

```bash
git add -A
git commit -m "test: verify workspace ui state segregation end-to-end"
```

---

## Notes for Implementers

### Keep this migration strict

Do not leave compatibility shims where both canonical state and UI state own the same concept.

Bad:
```text
WorkspaceStore.activeTabId + WorkspaceUIStore.activeTabId
Tab.activePaneId + WorkspaceUIStore.activePaneIdByTabId
```

Good:
```text
WorkspaceStore owns structure
WorkspaceUIStore owns selection and presentation
```

### Be careful with computed properties

A computed helper is fine only if it makes the source explicit.

Good:
```swift
func selectedTab(tabs: [Tab], selectedTabId: UUID?) -> Tab?
func selectedArrangement(tab: Tab, selectedArrangementId: UUID?) -> PaneArrangement
```

Suspicious:
```swift
var activeTab: Tab?
var activeArrangement: PaneArrangement
var layout: Layout
```

if they hide where the selected IDs come from.

### Stable IDs only

If the UI store points at a tab, pane, arrangement, or drawer pane, it must do so by UUID.
Never by index.
