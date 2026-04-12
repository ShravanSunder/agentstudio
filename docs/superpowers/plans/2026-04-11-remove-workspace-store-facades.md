# Remove WorkspaceStore Facades Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove `WorkspaceStore` facade reads and forwarding mutations so live workspace state is consumed through atoms and `derived`, while `WorkspaceStore` remains only the persistence wrapper that hydrates atoms, observes dirtiness, and flushes state.

**Architecture:** `WorkspaceMetadataAtom`, `WorkspaceRepositoryTopologyAtom`, `WorkspacePaneAtom`, `WorkspaceTabLayoutAtom`, and `WorkspaceMutationCoordinator` remain the canonical live state surfaces. Cross-atom read logic moves into explicit `derived` helpers instead of `WorkspaceStore` convenience methods. `WorkspaceStore` keeps restore/flush/debounce responsibilities only, and boot wiring may still own a `WorkspaceStore` instance for persistence lifecycle, but UI, runtime, command, and coordinator code read atoms or `derived` directly.

**Tech Stack:** Swift 6.2, Observation, SwiftUI, AppKit, Swift Testing

**Status:** Implemented on the current branch and verified with `mise run lint` plus full `mise run test`. The checklist boxes below were not maintained live during inline execution; use current branch state and verification evidence as the authoritative completion record.

---

## Execution Constraints

- Do not begin **Task 3** until **Task 2 Step 4** is complete. `atom(\.workspaceLookup)`, `atom(\.workspaceFocus)`, and `atom(\.tabDisplay)` must exist before the UI and controller migrations start.
- `derived` helpers in this plan are pure/stateless. Consumers that need reactive updates must keep touching the owning atoms inside `withObservationTracking` or SwiftUI body evaluation before calling the `derived` helper.
- Expect intermediate red tests during Tasks 2 through 6. Run only the task-local test slices during migration. The full suite runs only in **Task 7**.

---

## End-State Rule

At the end of this refactor:

- `WorkspaceStore` is allowed to own:
  - atom references
  - persistence restore / flush
  - debounce / dirtiness observation
  - scan lifecycle state that is part of persistence orchestration
- `WorkspaceStore` is not allowed to expose:
  - read aggregate properties like `repos`, `tabs`, `activeTabId`
  - lookup helpers like `pane(_:)`, `tab(_:)`, `repoAndWorktree(containing:)`
  - forwarding mutation helpers like `createPane(...)`, `appendTab(...)`, `removeTab(...)`
- all read-side code uses atoms or `derived`
- all mutation code calls the owning atom or `WorkspaceMutationCoordinator` directly
- `WorkspaceFocusContextAtom` is removed. Focus becomes pure `WorkspaceFocusDerived`, read via `atom(\.workspaceFocus)`

---

## Atom Replacement Checklist

### Replace these `WorkspaceStore` facades with atoms

| Current facade | Replace with |
|---|---|
| `store.repos`, `store.watchedPaths`, `store.unavailableRepoIds`, `store.repo(_:)`, `store.worktree(_:)`, `store.repo(containing:)`, `store.repoAndWorktree(containing:)` | `atom(\.workspaceRepositoryTopology)` plus `WorkspaceLookupDerived` for cross-atom path lookup |
| `store.panes`, `store.pane(_:)`, `store.panes(for:)`, `store.paneCount(for:)`, `store.isWorktreeActive(_:)`, `store.orphanedPanes` | `atom(\.workspacePane)` plus `WorkspaceLookupDerived` where tab/layout ownership matters |
| `store.tabs`, `store.activeTabId`, `store.activeTab`, `store.activePaneIds`, `store.tab(_:)`, `store.tabContaining(paneId:)` | `atom(\.workspaceTabLayout)` plus `WorkspaceLookupDerived` for tab ownership queries |
| `store.workspaceId`, `store.workspaceName`, `store.sidebarWidth`, `store.windowFrame`, `store.createdAt` | `atom(\.workspaceMetadata)` |
| `store.createPane(...)`, `store.updatePaneTitle(...)`, `store.updatePaneCWD(...)`, `store.updatePaneWebviewState(...)`, `store.syncPaneWebviewState(...)`, `store.setResidency(...)` | `atom(\.workspacePane)` |
| `store.removePane(...)`, `store.backgroundPane(...)`, `store.reactivatePane(...)` | `atom(\.workspaceMutationCoordinator)` |
| `store.appendTab(...)`, `store.setActiveTab(...)`, `store.insertPane(...)`, `store.removeTab(...)`, `store.moveTab(...)`, `store.renameTab(...)`, `store.switchArrangement(...)`, drawer/tab layout mutations | `atom(\.workspaceTabLayout)` or `atom(\.workspaceMutationCoordinator)` depending on ownership |

### New `derived` surfaces to add

| New `derived` type | Responsibility |
|---|---|
| `WorkspaceLookupDerived` | Cross-atom lookups formerly hidden on `WorkspaceStore`: `tabContaining(paneId:)`, `repoAndWorktree(containing:)`, `paneLocations(for worktreeId:)`, ownership and active-state queries |
| `WorkspaceFocusDerived` | Build `WorkspaceFocus` from atoms without a `WorkspaceStore` input |
| `TabDisplayDerived` | Resolve tab titles from `workspacePane`, `workspaceRepositoryTopology`, and `repoCache` without a `WorkspaceStore` parameter |
| `WorkspaceLauncherDerived` | Build launcher/home-card models from atoms and `repoCache` without `WorkspaceStore` |

### Source checklist: migrate to atoms / `derived`

#### Command bar and sidebar

- [ ] `Sources/AgentStudio/Features/CommandBar/CommandBarDataSource.swift`
- [ ] `Sources/AgentStudio/Features/CommandBar/CommandBarDataSource+WorktreeRows.swift`
- [ ] `Sources/AgentStudio/Features/CommandBar/Views/CommandBarView.swift`
- [ ] `Sources/AgentStudio/Features/CommandBar/CommandBarPanelController.swift`
- [ ] `Sources/AgentStudio/Features/Sidebar/RepoSidebarContentView.swift`

#### Tab / pane UI

- [ ] `Sources/AgentStudio/App/Panes/TabBar/TabBarAdapter.swift`
- [ ] `Sources/AgentStudio/App/Panes/WorkspaceLauncherProjector.swift`
- [ ] `Sources/AgentStudio/Core/Views/Splits/ActiveTabContent.swift`
- [ ] `Sources/AgentStudio/Core/Views/Splits/SingleTabContent.swift`
- [ ] `Sources/AgentStudio/Core/Views/Splits/FlatPaneStripContent.swift`
- [ ] `Sources/AgentStudio/Core/Views/Splits/FlatTabStripContainer.swift`
- [ ] `Sources/AgentStudio/Core/Views/Splits/PaneLeafContainer.swift`
- [ ] `Sources/AgentStudio/Core/Views/Splits/PaneManagementContext.swift`
- [ ] `Sources/AgentStudio/Core/Views/Drawer/DrawerPanel.swift`
- [ ] `Sources/AgentStudio/Core/Views/Drawer/DrawerPanelOverlay.swift`
- [ ] `Sources/AgentStudio/App/Windows/MainSplitViewController.swift`
- [ ] `Sources/AgentStudio/App/Windows/MainWindowController.swift`

#### Runtime / command / controller paths

- [ ] `Sources/AgentStudio/App/Commands/ActionExecutor.swift`
- [ ] `Sources/AgentStudio/App/Coordination/PaneCoordinator.swift`
- [ ] `Sources/AgentStudio/App/Coordination/PaneCoordinator+ActionExecution.swift`
- [ ] `Sources/AgentStudio/App/Coordination/PaneCoordinator+FilesystemSource.swift`
- [ ] `Sources/AgentStudio/App/Coordination/PaneCoordinator+TerminalPlaceholders.swift`
- [ ] `Sources/AgentStudio/App/Coordination/PaneCoordinator+Undo.swift`
- [ ] `Sources/AgentStudio/App/Coordination/PaneCoordinator+ViewLifecycle.swift`
- [ ] `Sources/AgentStudio/App/Coordination/WorkspaceCacheCoordinator.swift`
- [ ] `Sources/AgentStudio/App/Panes/PaneTabViewController.swift`
- [ ] `Sources/AgentStudio/App/Panes/GitHubWebviewLaunchResolver.swift`
- [ ] `Sources/AgentStudio/Core/RuntimeEventSystem/Dispatch/RuntimeTargetResolver.swift`
- [ ] `Sources/AgentStudio/Core/RuntimeEventSystem/Runtime/SessionRuntime.swift`
- [ ] `Sources/AgentStudio/Features/Terminal/Restore/TerminalRestoreRuntime.swift`
- [ ] `Sources/AgentStudio/Features/Terminal/Restore/TerminalRestoreScheduler.swift`

#### Atoms / helpers that still depend on `WorkspaceStore`

- [ ] `Sources/AgentStudio/Core/State/MainActor/Atoms/WorkspaceFocusContextAtom.swift`
- [ ] `Sources/AgentStudio/Core/State/MainActor/Atoms/TabDisplayNameResolver.swift`

#### Persistence layer to slim down

- [ ] `Sources/AgentStudio/Core/State/MainActor/Persistence/WorkspaceStore.swift`
- [ ] `Sources/AgentStudio/Infrastructure/AtomLib/AtomStore.swift`

#### Additional call sites / helper seams to rescan and update

- [ ] `Sources/AgentStudio/App/Panes/TabBar/CustomTabBar.swift`
- [ ] `Sources/AgentStudio/App/Panes/TabBar/DraggableTabBarHostingView.swift`
- [ ] `Sources/AgentStudio/App/Panes/ViewRegistry.swift`
- [ ] `Tests/AgentStudioTests/Helpers/GitEventPipelineHarness.swift`
- [ ] `Tests/AgentStudioTests/Helpers/PaneCoordinatorTestHelpers.swift`
- [ ] `Tests/AgentStudioTests/App/WorkspaceCacheCoordinatorTests.swift`
- [ ] `Tests/AgentStudioTests/App/WorkspaceCacheCoordinatorIntegrationTests.swift`
- [ ] `Tests/AgentStudioTests/App/WorkspaceCacheCoordinatorRepoMoveTests.swift`
- [ ] `Tests/AgentStudioTests/App/PrimarySidebarPipelineIntegrationTests.swift`
- [ ] `Tests/AgentStudioTests/Integration/FilesystemToPrimarySidebarIntegrationTests.swift`

### Source checklist: allowed to keep `WorkspaceStore` ownership

- [ ] `Sources/AgentStudio/App/Boot/AppDelegate.swift`
  Keep `WorkspaceStore` instance for `restore()`, `flush()`, debounced persistence, and boot-time scan lifecycle only.
- [ ] `Sources/AgentStudio/App/Boot/AppDelegate+LifecycleRouting.swift`
  May still access the `store` property from `AppDelegate`, but its live reads should use atoms directly.
- [ ] `Sources/AgentStudio/Core/State/MainActor/Persistence/RepoCacheStore.swift`
- [ ] `Sources/AgentStudio/Core/State/MainActor/Persistence/UIStateStore.swift`

---

## File Structure

| Action | Path | Responsibility |
|---|---|---|
| Create | `Sources/AgentStudio/Core/State/MainActor/Atoms/WorkspaceLookupDerived.swift` | Centralize cross-atom lookups that were formerly hidden behind `WorkspaceStore` convenience APIs |
| Create | `Sources/AgentStudio/Core/State/MainActor/Atoms/WorkspaceFocusDerived.swift` | Build `WorkspaceFocus` directly from atoms |
| Create | `Sources/AgentStudio/Core/State/MainActor/Atoms/TabDisplayDerived.swift` | Resolve tab titles and pane-derived tab labels without `WorkspaceStore` |
| Delete | `Sources/AgentStudio/Core/State/MainActor/Atoms/WorkspaceFocusContextAtom.swift` | Remove the stored focus atom; focus becomes pure `derived` |
| Modify | `Sources/AgentStudio/Core/State/MainActor/Atoms/TabDisplayNameResolver.swift` | Replace `WorkspaceStore` parameter with atom-backed reads or fold into `TabDisplayDerived` |
| Modify | `Sources/AgentStudio/Core/State/MainActor/Persistence/WorkspaceStore.swift` | Delete read aggregate and forwarding mutation APIs; keep restore / flush / dirty tracking |
| Modify | `Sources/AgentStudio/Infrastructure/AtomLib/AtomStore.swift` | Expose new `derived` helpers; remove transitional aliases that encouraged facade-style access |
| Modify | `Sources/AgentStudio/Features/CommandBar/CommandBarDataSource.swift` | Read atoms / `derived` instead of `WorkspaceStore` queries |
| Modify | `Sources/AgentStudio/Features/CommandBar/CommandBarDataSource+WorktreeRows.swift` | Replace worktree presence lookup with atom / `derived` reads |
| Modify | `Sources/AgentStudio/Features/CommandBar/Views/CommandBarView.swift` | Remove `WorkspaceStore` reads from footer/action resolution |
| Modify | `Sources/AgentStudio/App/Panes/TabBar/TabBarAdapter.swift` | Derive tab UI from atoms / `derived`, not `store.tabs` / `store.pane(...)` |
| Modify | `Sources/AgentStudio/App/Panes/WorkspaceLauncherProjector.swift` | Read atoms / `derived` directly |
| Modify | `Sources/AgentStudio/Features/Sidebar/RepoSidebarContentView.swift` | Replace `store.repos` / `store.pane(...)` reads with atoms / `derived` |
| Modify | `Sources/AgentStudio/App/Commands/ActionExecutor.swift` | Build snapshots from atoms, not `WorkspaceStore` facade vars |
| Modify | `Sources/AgentStudio/App/Coordination/*.swift` | Read owner atoms directly, keep mutation sequencing unchanged |
| Modify | `Sources/AgentStudio/Core/RuntimeEventSystem/Dispatch/RuntimeTargetResolver.swift` | Resolve targets from `workspaceTabLayout` / `workspacePane` atoms directly |
| Modify | `Sources/AgentStudio/Features/Terminal/Restore/*.swift` | Remove `WorkspaceStore` lookup usage from restore visibility and zmx diagnostics |
| Modify | `Tests/AgentStudioTests/Core/Stores/WorkspaceStoreArchitectureTests.swift` | Add architecture assertions that `WorkspaceStore` no longer exposes facade reads / writes |
| Create | `Tests/AgentStudioTests/Core/Views/WorkspaceLookupDerivedTests.swift` | Cover cross-atom lookup behavior |
| Create | `Tests/AgentStudioTests/Core/Views/WorkspaceFocusDerivedTests.swift` | Cover focus derivation without `WorkspaceStore` |
| Create | `Tests/AgentStudioTests/Core/Views/TabDisplayDerivedTests.swift` | Cover tab title derivation without `WorkspaceStore` |
| Modify | `Tests/AgentStudioTests/Core/Stores/WorkspaceStoreTests.swift` | Confirm `restore()` and `flush()` still hydrate and persist atom state after the facade removal |
| Modify | Existing command bar / sidebar / tab bar / runtime tests | Update call sites and pin the atom / `derived` paths |

---

### Task 1: Lock the architecture and add failing guardrail tests

**Files:**
- Modify: `Tests/AgentStudioTests/Core/Stores/WorkspaceStoreArchitectureTests.swift`
- Modify: `docs/architecture/component_architecture.md`
- Modify: `docs/architecture/workspace_data_architecture.md`

- [ ] **Step 1: Add failing architecture tests for `WorkspaceStore`**

Add source-level tests that assert `WorkspaceStore.swift` no longer contains the old facade markers:

```swift
#expect(!source.contains("var repos:"))
#expect(!source.contains("var tabs:"))
#expect(!source.contains("func pane(_"))
#expect(!source.contains("func tabContaining("))
#expect(!source.contains("func createPane("))
#expect(!source.contains("func appendTab("))
```

Document in the test file that this guardrail is intentionally coarse source matching. It prevents hard-cutover regressions quickly, but it is complemented by the broader consumer scan in **Task 7 Step 5** because comments or renamed methods can evade or trip string checks.

- [ ] **Step 2: Add doc language that matches the new rule**

Update the architecture docs so they explicitly say:

```markdown
`WorkspaceStore` is a persistence wrapper. Live workspace reads go through atoms or `derived`.
Do not add convenience query or mutation facades to `WorkspaceStore`.
```

- [ ] **Step 3: Run the architecture slice and verify it fails before the implementation**

Run: `SWIFT_BUILD_DIR=.build-agent-store-facades swift test --build-path "$SWIFT_BUILD_DIR" --filter "WorkspaceStoreArchitectureTests" > /tmp/workspace-store-architecture.txt 2>&1; echo $?`

Expected: non-zero exit because `WorkspaceStore.swift` still exposes facade reads and forwarding methods.

### Task 2: Add shared `derived` replacements for the removed facade queries

**Files:**
- Create: `Sources/AgentStudio/Core/State/MainActor/Atoms/WorkspaceLookupDerived.swift`
- Create: `Sources/AgentStudio/Core/State/MainActor/Atoms/WorkspaceFocusDerived.swift`
- Create: `Sources/AgentStudio/Core/State/MainActor/Atoms/TabDisplayDerived.swift`
- Modify: `Sources/AgentStudio/Infrastructure/AtomLib/AtomStore.swift`
- Create: `Tests/AgentStudioTests/Core/Views/WorkspaceLookupDerivedTests.swift`
- Create: `Tests/AgentStudioTests/Core/Views/WorkspaceFocusDerivedTests.swift`
- Create: `Tests/AgentStudioTests/Core/Views/TabDisplayDerivedTests.swift`

- [ ] **Step 1: Write failing tests for `WorkspaceLookupDerived`**

Cover the former facade queries:

```swift
@Test
func tabContainingPane_returnsOwningTab() { ... }

@Test
func repoAndWorktreeContainingCwd_resolvesNestedPath() { ... }

@Test
func paneLocationsForWorktree_returnsTabAndPaneOrder() { ... }
```

- [ ] **Step 2: Write failing tests for `WorkspaceFocusDerived` and `TabDisplayDerived`**

Cover:
- active tab / active pane / drawer focus requirements
- default `"Tab"` fallback behavior
- worktree-backed branch-aware tab labels

- [ ] **Step 3: Implement the new `derived` helpers**

Add atom-backed helpers shaped like:

```swift
@MainActor
struct WorkspaceLookupDerived {
    func tabContaining(paneId: UUID) -> Tab? { ... }
    func repoAndWorktree(containing cwd: URL?) -> (repo: Repo, worktree: Worktree)? { ... }
    func paneLocations(for worktreeId: UUID) -> [WorktreePaneLocation] { ... }
}
```

```swift
@MainActor
struct WorkspaceFocusDerived {
    func currentFocus() -> WorkspaceFocus { ... }
}
```

```swift
@MainActor
struct TabDisplayDerived {
    func displayTitle(for tab: Tab) -> String { ... }
    func title(for pane: Pane) -> String { ... }
}
```

- [ ] **Step 4: Wire the new `derived` helpers into `AtomStore`**

Expose:

```swift
var workspaceLookup: WorkspaceLookupDerived { WorkspaceLookupDerived() }
var workspaceFocus: WorkspaceFocusDerived { WorkspaceFocusDerived() }
var tabDisplay: TabDisplayDerived { TabDisplayDerived() }
```

- [ ] **Step 5: Run the focused `derived` test slice**

Run: `SWIFT_BUILD_DIR=.build-agent-store-facades swift test --build-path "$SWIFT_BUILD_DIR" --filter "WorkspaceLookupDerivedTests|WorkspaceFocusDerivedTests|TabDisplayDerivedTests" > /tmp/workspace-derived-tests.txt 2>&1; echo $?`

Expected: `0`

### Task 3: Migrate command bar, sidebar, launcher, and tab bar to atoms / `derived`

**Files:**
- Modify: `Sources/AgentStudio/Features/CommandBar/CommandBarDataSource.swift`
- Modify: `Sources/AgentStudio/Features/CommandBar/CommandBarDataSource+WorktreeRows.swift`
- Modify: `Sources/AgentStudio/Features/CommandBar/Views/CommandBarView.swift`
- Modify: `Sources/AgentStudio/Features/CommandBar/CommandBarPanelController.swift`
- Modify: `Sources/AgentStudio/Features/Sidebar/RepoSidebarContentView.swift`
- Modify: `Sources/AgentStudio/App/Panes/WorkspaceLauncherProjector.swift`
- Modify: `Sources/AgentStudio/App/Panes/TabBar/TabBarAdapter.swift`
- Modify: `Sources/AgentStudio/Core/State/MainActor/Atoms/TabDisplayNameResolver.swift`
- Modify: `Tests/AgentStudioTests/Features/CommandBar/CommandBarDataSourceTests.swift`
- Modify: `Tests/AgentStudioTests/Features/CommandBar/CommandBarTabDisplayTitleTests.swift`
- Modify: `Tests/AgentStudioTests/App/WorkspaceLauncherProjectorTests.swift`
- Modify: `Tests/AgentStudioTests/Core/Views/TabBarAdapterTests.swift`

- [ ] **Step 1: Replace command bar reads**

Use:
- `atom(\.workspaceTabLayout)` for tabs / active tab
- `atom(\.workspacePane)` for pane lookup
- `atom(\.workspaceRepositoryTopology)` for repos / worktrees
- `atom(\.workspaceLookup)` for `repoAndWorktree` and pane-location queries
- `atom(\.workspaceFocus)` for focus visibility and footer/status context

- [ ] **Step 2: Replace sidebar and launcher reads**

Stop passing `WorkspaceStore`-backed queries into `RepoSidebarContentView` and `WorkspaceLauncherProjector`. Use topology atom plus `workspaceLookup` where path resolution is needed.

- [ ] **Step 3: Replace tab bar display reads**

Update `TabBarAdapter` and tab-title helpers to consume `atom(\.tabDisplay)` and direct atoms instead of `store.tabs`, `store.pane(...)`, `store.repo(...)`, and `store.worktree(...)`.

- [ ] **Step 4: Remove `WorkspaceStore` from `WorkspaceFocusContextAtom`**

Delete `WorkspaceFocusContextAtom` entirely and move its callers to:

```swift
atom(\.workspaceFocus).currentFocus()
```

Update any boot wiring or tests that still call `startObserving(store:)`.

- [ ] **Step 5: Run the focused UI/read-side test slice**

Run: `SWIFT_BUILD_DIR=.build-agent-store-facades swift test --build-path "$SWIFT_BUILD_DIR" --filter "CommandBarDataSourceTests|CommandBarTabDisplayTitleTests|WorkspaceLauncherProjectorTests|TabBarAdapterTests" > /tmp/workspace-readside-tests.txt 2>&1; echo $?`

Expected: `0`

### Task 4: Migrate controllers, coordinators, command execution, and runtime helpers off the facade

**Files:**
- Modify: `Sources/AgentStudio/App/Commands/ActionExecutor.swift`
- Modify: `Sources/AgentStudio/App/Coordination/PaneCoordinator.swift`
- Modify: `Sources/AgentStudio/App/Coordination/PaneCoordinator+ActionExecution.swift`
- Modify: `Sources/AgentStudio/App/Coordination/PaneCoordinator+FilesystemSource.swift`
- Modify: `Sources/AgentStudio/App/Coordination/PaneCoordinator+TerminalPlaceholders.swift`
- Modify: `Sources/AgentStudio/App/Coordination/PaneCoordinator+Undo.swift`
- Modify: `Sources/AgentStudio/App/Coordination/PaneCoordinator+ViewLifecycle.swift`
- Modify: `Sources/AgentStudio/App/Coordination/WorkspaceCacheCoordinator.swift`
- Modify: `Sources/AgentStudio/App/Panes/PaneTabViewController.swift`
- Modify: `Sources/AgentStudio/App/Panes/GitHubWebviewLaunchResolver.swift`
- Modify: `Sources/AgentStudio/Core/RuntimeEventSystem/Dispatch/RuntimeTargetResolver.swift`
- Modify: `Sources/AgentStudio/Core/RuntimeEventSystem/Runtime/SessionRuntime.swift`
- Modify: `Sources/AgentStudio/Features/Terminal/Restore/TerminalRestoreRuntime.swift`
- Modify: `Sources/AgentStudio/Features/Terminal/Restore/TerminalRestoreScheduler.swift`
- Modify: `Tests/AgentStudioTests/App/ActionExecutorTests.swift`
- Modify: `Tests/AgentStudioTests/App/PaneCoordinatorTests.swift`
- Modify: `Tests/AgentStudioTests/App/PaneTabViewControllerCommandTests.swift`
- Modify: `Tests/AgentStudioTests/Core/PaneRuntime/Dispatch/RuntimeTargetResolverTests.swift`
- Modify: `Tests/AgentStudioTests/Features/Terminal/Restore/TerminalRestoreRuntimeTests.swift`

- [ ] **Step 1: Replace snapshot-building and validation reads in `ActionExecutor`**

Build `ActionStateSnapshot` from:

```swift
let tabLayout = atom(\.workspaceTabLayout)
let topology = atom(\.workspaceRepositoryTopology)
```

instead of `store.tabs`, `store.activeTabId`, and `store.repos`.

- [ ] **Step 2: Replace coordinator read helpers with owner atoms / `derived`**

Where the coordinator reads state, use:
- `store.tabLayoutAtom`
- `store.paneAtom`
- `store.repositoryTopologyAtom`
- `store.mutationCoordinator`

or inject those atoms directly if the `store` property is no longer needed.

- [ ] **Step 3: Replace runtime helpers and target resolvers**

Use direct atom inputs for:
- active tab lookup
- pane existence lookup
- repo/worktree lookup for zmx diagnostics
- restore visibility checks

- [ ] **Step 4: Run the focused command/runtime slice**

Run: `SWIFT_BUILD_DIR=.build-agent-store-facades swift test --build-path "$SWIFT_BUILD_DIR" --filter "ActionExecutorTests|PaneCoordinatorTests|PaneTabViewControllerCommandTests|RuntimeTargetResolverTests|TerminalRestoreRuntimeTests" > /tmp/workspace-runtime-tests.txt 2>&1; echo $?`

Expected: `0`

### Task 5: Migrate remaining core views and remove `WorkspaceStore` plumbing from read-side constructors

**Files:**
- Modify: `Sources/AgentStudio/Core/Views/Splits/ActiveTabContent.swift`
- Modify: `Sources/AgentStudio/Core/Views/Splits/SingleTabContent.swift`
- Modify: `Sources/AgentStudio/Core/Views/Splits/FlatPaneStripContent.swift`
- Modify: `Sources/AgentStudio/Core/Views/Splits/FlatTabStripContainer.swift`
- Modify: `Sources/AgentStudio/Core/Views/Splits/PaneLeafContainer.swift`
- Modify: `Sources/AgentStudio/Core/Views/Splits/PaneManagementContext.swift`
- Modify: `Sources/AgentStudio/Core/Views/Drawer/DrawerPanel.swift`
- Modify: `Sources/AgentStudio/Core/Views/Drawer/DrawerPanelOverlay.swift`
- Modify: `Sources/AgentStudio/App/Windows/MainSplitViewController.swift`
- Modify: `Sources/AgentStudio/App/Windows/MainWindowController.swift`
- Modify: `Tests/AgentStudioTests/Core/Views/PaneManagementContextTests.swift`

- [ ] **Step 1: Replace view-local `store` reads with atoms / `derived`**

Examples:

```swift
let tabLayout = atom(\.workspaceTabLayout)
let workspacePane = atom(\.workspacePane)
let workspaceLookup = atom(\.workspaceLookup)
```

- [ ] **Step 2: Remove `WorkspaceStore` parameters from read-only view constructors where they no longer earn their keep**

If a view only needed `store` for reads, replace the parameter with nothing and read atoms inside the view.

- [ ] **Step 3: Run the focused view slice**

Run: `SWIFT_BUILD_DIR=.build-agent-store-facades swift test --build-path "$SWIFT_BUILD_DIR" --filter "PaneManagementContextTests|TabBarAdapterTests|CommandBarDataSourceTests" > /tmp/workspace-view-tests.txt 2>&1; echo $?`

Expected: `0`

### Task 6: Delete the `WorkspaceStore` facade surface and update tests/harnesses

**Files:**
- Modify: `Sources/AgentStudio/Core/State/MainActor/Persistence/WorkspaceStore.swift`
- Modify: `Tests/AgentStudioTests/Core/Stores/WorkspaceStoreTests.swift`
- Modify: `Tests/AgentStudioTests/Core/Stores/WorkspaceStoreArrangementTests.swift`
- Modify: `Tests/AgentStudioTests/Core/Stores/WorkspaceStoreDrawerTests.swift`
- Modify: `Tests/AgentStudioTests/Core/Stores/WorkspaceStoreOrphanPoolTests.swift`
- Modify: `Tests/AgentStudioTests/Core/ObservableStoreTests.swift`
- Modify: `Tests/AgentStudioTests/App/State/AtomScopeTests.swift`
- Modify: any helper or fixture file still using removed facade APIs

- [ ] **Step 1: Delete the read aggregate and forwarding mutation sections from `WorkspaceStore.swift`**

The remaining public surface should look like:

```swift
final class WorkspaceStore {
    let metadataAtom: WorkspaceMetadataAtom
    let repositoryTopologyAtom: WorkspaceRepositoryTopologyAtom
    let paneAtom: WorkspacePaneAtom
    let tabLayoutAtom: WorkspaceTabLayoutAtom
    let mutationCoordinator: WorkspaceMutationCoordinator

    func restore() { ... }
    func flush() -> Bool { ... }
}
```

- [ ] **Step 2: Remove compatibility aliases that kept the old shape alive**

Delete:

```swift
var catalogAtom: WorkspaceRepositoryTopologyAtom
var graphAtom: WorkspacePaneAtom
var interactionAtom: WorkspaceTabLayoutAtom
```

unless a test proves one of them is still load-bearing for the new architecture.

Also delete the transitional convenience initializer:

```swift
convenience init(
    catalogAtom: WorkspaceRepositoryTopologyAtom,
    graphAtom: WorkspacePaneAtom,
    interactionAtom: WorkspaceTabLayoutAtom,
    ...
)
```

and update all fixtures/tests to pass the canonical parameter names or construct `AtomStore`/atoms directly.

- [ ] **Step 3: Update store-focused tests to validate the new narrow role**

Add assertions that:
- persistence still hydrates atoms
- flush still serializes atom state
- `WorkspaceStore` no longer acts as a query service
- boot/restore behavior is unchanged after the facade removal

- [ ] **Step 4: Run the focused persistence slice**

Run: `SWIFT_BUILD_DIR=.build-agent-store-facades swift test --build-path "$SWIFT_BUILD_DIR" --filter "WorkspaceStoreTests|WorkspaceStoreArrangementTests|WorkspaceStoreDrawerTests|WorkspaceStoreOrphanPoolTests|ObservableStoreTests|AtomScopeTests|WorkspaceStoreArchitectureTests" > /tmp/workspace-store-tests.txt 2>&1; echo $?`

Expected: `0`

### Task 7: Full verification and cleanup

**Files:**
- Modify: all files touched above

- [ ] **Step 1: Run the full test suite**

Run: `mise run test`

Expected: exit code `0`

- [ ] **Step 2: Run lint**

Run: `mise run lint`

Expected: exit code `0`

- [ ] **Step 3: Run format if needed, then rerun lint**

Run: `mise run format && mise run lint`

Expected: both exit code `0`

- [ ] **Step 4: Review the final source tree for forbidden patterns**

Run: `rg -n "var repos:|var tabs:|func pane\\(|func tab\\(|func repo\\(|func worktree\\(|func createPane\\(|func appendTab\\(" Sources/AgentStudio/Core/State/MainActor/Persistence/WorkspaceStore.swift`

Expected: no matches

- [ ] **Step 5: Review remaining `WorkspaceStore` consumers**

Run: `rg -n "WorkspaceStore|\\bstore\\." Sources/AgentStudio | sort`

Expected:
- remaining matches are limited to persistence lifecycle, boot wiring, or explicit test harnesses that exercise restore/flush
- no command bar, sidebar, tab bar, runtime resolver, or read-only SwiftUI view still depends on `WorkspaceStore` facade APIs

---

## Self-Review

### Spec coverage

- remove facades on all stores
  Covered by Tasks 1, 2, 6, and the end-state rule
- replace live reads with atoms
  Covered by Tasks 2 through 5 and the atom replacement checklist
- use `derived`, not “projections”
  Covered throughout the plan vocabulary and the new helper types
- provide the comprehensive checklist
  Covered by the atom replacement checklist and source-file migration checklist

### Placeholder scan

- No `TODO`, `TBD`, or “implement later” placeholders remain
- Each task names exact files and exact commands
- New helper types are named consistently before they are referenced later

### Type consistency

- `WorkspaceLookupDerived`, `WorkspaceFocusDerived`, and `TabDisplayDerived` are introduced once and reused consistently
- `WorkspaceStore` end-state is consistent across the header, checklist, and Task 6
