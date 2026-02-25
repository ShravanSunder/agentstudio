# Workspace Persistence Segregation Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Split workspace persistence into canonical state, derived cache, UI preferences, and keybindings so stale git lookup data never becomes source-of-truth.

**Architecture:** Introduce atomic persistence stores aligned to domain boundaries: `WorkspaceStore` for canonical model, `WorkspaceCacheStore` for derived git/wt/gh metadata, `WorkspaceUIStore` for workspace-scoped UI prefs, and `PreferencesStore`/`KeybindingsStore` for global preferences. Keep unidirectional flow via `private(set)` state and store-owned mutation methods, with coordinator-owned cross-store sequencing.

**Tech Stack:** Swift 6, `@Observable`, SwiftPM `Testing`, `mise` tasks (`format`, `lint`, `test`), JSON Codable persistence.

---

### Task 1: Add Canonical-vs-Cache Persistence Types

**Files:**
- Create: `Sources/AgentStudio/Core/Stores/WorkspaceCachePersistor.swift`
- Modify: `Sources/AgentStudio/Core/Stores/WorkspacePersistor.swift`
- Test: `Tests/AgentStudioTests/Core/Stores/WorkspacePersistorTests.swift`

**Step 1: Write the failing test**

```swift
@Test
func load_legacySingleFile_splitsCanonicalAndCache() throws {
    // Arrange legacy payload with branch/status-like fields
    // Act load via persistor migration entrypoint
    // Assert canonical + cache are split into separate structures
}
```

**Step 2: Run test to verify it fails**

Run:

```bash
SWIFT_BUILD_DIR=".build-agent-persistence" swift test --build-path "$SWIFT_BUILD_DIR" --filter "WorkspacePersistorTests/load_legacySingleFile_splitsCanonicalAndCache"
```

Expected: FAIL (missing split/migration support)

**Step 3: Write minimal implementation**

- Add cache persistable model with:
  - `workspaceId`
  - `sourceStateUpdatedAt` (or revision)
  - `generatedAt`
  - repo identity metadata dictionary
  - worktree status dictionary
- Add migration decoder path that reads legacy mixed payload and returns split outputs.

**Step 4: Run test to verify it passes**

Run same command as Step 2.

Expected: PASS

**Step 5: Commit**

```bash
git add Sources/AgentStudio/Core/Stores/WorkspaceCachePersistor.swift Sources/AgentStudio/Core/Stores/WorkspacePersistor.swift Tests/AgentStudioTests/Core/Stores/WorkspacePersistorTests.swift
git commit -m "feat: add split persistence models for canonical state and cache"
```

---

### Task 2: Remove Stale-Prone Fields from Canonical Worktree Persistence

**Files:**
- Modify: `Sources/AgentStudio/Core/Models/Worktree.swift`
- Modify: `Sources/AgentStudio/Core/Stores/WorkspaceStore.swift`
- Test: `Tests/AgentStudioTests/Core/Stores/WorkspaceStoreTests.swift`

**Step 1: Write the failing test**

```swift
@Test
func persistNow_doesNotSerializeBranchOrStatusAsCanonicalTruth() throws {
    // Arrange store with worktrees and status values
    // Act persist and decode canonical file
    // Assert stale-prone fields are absent from canonical payload
}
```

**Step 2: Run test to verify it fails**

Run:

```bash
SWIFT_BUILD_DIR=".build-agent-persistence" swift test --build-path "$SWIFT_BUILD_DIR" --filter "WorkspaceStoreTests/persistNow_doesNotSerializeBranchOrStatusAsCanonicalTruth"
```

Expected: FAIL

**Step 3: Write minimal implementation**

- Keep `Worktree` runtime model intact if needed for rendering, but define canonical DTO in persistor without stale fields.
- Ensure `WorkspaceStore.persistNow()` writes canonical DTO, not mixed runtime DTO.

**Step 4: Run test to verify it passes**

Run same command as Step 2.

Expected: PASS

**Step 5: Commit**

```bash
git add Sources/AgentStudio/Core/Models/Worktree.swift Sources/AgentStudio/Core/Stores/WorkspaceStore.swift Tests/AgentStudioTests/Core/Stores/WorkspaceStoreTests.swift
git commit -m "refactor: keep canonical workspace persistence free of stale git lookup fields"
```

---

### Task 3: Introduce WorkspaceCacheStore (Atomic Derived Store)

**Files:**
- Create: `Sources/AgentStudio/Core/Stores/WorkspaceCacheStore.swift`
- Modify: `Sources/AgentStudio/App/MainSplitViewController.swift`
- Test: `Tests/AgentStudioTests/Features/Sidebar/SidebarGitRepositoryInspectorTests.swift`
- Test: `Tests/AgentStudioTests/Features/Sidebar/SidebarRepoGroupingTests.swift`

**Step 1: Write the failing test**

```swift
@Test
func cacheStore_applyRefresh_updatesOnlyDerivedMaps() {
    // Arrange cache store with existing values
    // Act apply new refresh snapshot
    // Assert only cache maps changed; no canonical model side effects
}
```

**Step 2: Run test to verify it fails**

Run:

```bash
SWIFT_BUILD_DIR=".build-agent-persistence" swift test --build-path "$SWIFT_BUILD_DIR" --filter "SidebarRepoGroupingTests|SidebarGitRepositoryInspectorTests|cacheStore_applyRefresh_updatesOnlyDerivedMaps"
```

Expected: FAIL

**Step 3: Write minimal implementation**

- Add `@Observable @MainActor WorkspaceCacheStore` with `private(set)` maps.
- Add typed mutation APIs for:
  - replace metadata snapshot
  - patch PR counts
  - patch notification counts
- Wire sidebar readers to use cache store.

**Step 4: Run test to verify it passes**

Run same command as Step 2.

Expected: PASS

**Step 5: Commit**

```bash
git add Sources/AgentStudio/Core/Stores/WorkspaceCacheStore.swift Sources/AgentStudio/App/MainSplitViewController.swift Tests/AgentStudioTests/Features/Sidebar/SidebarGitRepositoryInspectorTests.swift Tests/AgentStudioTests/Features/Sidebar/SidebarRepoGroupingTests.swift
git commit -m "feat: add atomic workspace cache store for derived sidebar metadata and status"
```

---

### Task 4: Add Workspace-Scoped UI Persistence Store

**Files:**
- Create: `Sources/AgentStudio/Core/Stores/WorkspaceUIStore.swift`
- Create: `Sources/AgentStudio/Core/Stores/WorkspaceUIPersistor.swift`
- Modify: `Sources/AgentStudio/Features/Sidebar/RepoSidebarContentView.swift`
- Modify: `Sources/AgentStudio/App/MainSplitViewController.swift`
- Test: `Tests/AgentStudioTests/Features/Sidebar/SidebarRepoGroupingTests.swift`

**Step 1: Write the failing test**

```swift
@Test
func workspaceUIStore_persistsExpandedGroupsAndCheckoutColors_perWorkspace() throws {
    // Arrange store changes
    // Act save + reload
    // Assert values are restored by workspace id
}
```

**Step 2: Run test to verify it fails**

Run:

```bash
SWIFT_BUILD_DIR=".build-agent-persistence" swift test --build-path "$SWIFT_BUILD_DIR" --filter "workspaceUIStore_persistsExpandedGroupsAndCheckoutColors_perWorkspace"
```

Expected: FAIL

**Step 3: Write minimal implementation**

- Move sidebar UI keys from `UserDefaults` to workspace UI persistor file.
- Keep API surface in `WorkspaceUIStore` so views no longer touch persistence directly.

**Step 4: Run test to verify it passes**

Run same command as Step 2.

Expected: PASS

**Step 5: Commit**

```bash
git add Sources/AgentStudio/Core/Stores/WorkspaceUIStore.swift Sources/AgentStudio/Core/Stores/WorkspaceUIPersistor.swift Sources/AgentStudio/Features/Sidebar/RepoSidebarContentView.swift Sources/AgentStudio/App/MainSplitViewController.swift Tests/AgentStudioTests/Features/Sidebar/SidebarRepoGroupingTests.swift
git commit -m "feat: persist workspace-scoped ui preferences outside canonical workspace state"
```

---

### Task 5: Add Global Preferences Store and Migrate @AppStorage Keys

**Files:**
- Create: `Sources/AgentStudio/Core/Stores/PreferencesStore.swift`
- Create: `Sources/AgentStudio/Core/Stores/PreferencesPersistor.swift`
- Modify: `Sources/AgentStudio/App/SettingsView.swift`
- Modify: `Sources/AgentStudio/Core/Views/Drawer/DrawerPanelOverlay.swift`
- Test: `Tests/AgentStudioTests/App/AppCommandTests.swift`

**Step 1: Write the failing test**

```swift
@Test
func preferencesStore_load_migratesLegacyUserDefaultsKeys() throws {
    // Arrange legacy UserDefaults values
    // Act load via preferences store
    // Assert new persisted file + in-memory values are correct
}
```

**Step 2: Run test to verify it fails**

Run:

```bash
SWIFT_BUILD_DIR=".build-agent-persistence" swift test --build-path "$SWIFT_BUILD_DIR" --filter "preferencesStore_load_migratesLegacyUserDefaultsKeys"
```

Expected: FAIL

**Step 3: Write minimal implementation**

- Add global preferences JSON file model.
- Move current `@AppStorage` settings reads/writes behind `PreferencesStore`.
- Keep migration logic from legacy `UserDefaults` keys.

**Step 4: Run test to verify it passes**

Run same command as Step 2.

Expected: PASS

**Step 5: Commit**

```bash
git add Sources/AgentStudio/Core/Stores/PreferencesStore.swift Sources/AgentStudio/Core/Stores/PreferencesPersistor.swift Sources/AgentStudio/App/SettingsView.swift Sources/AgentStudio/Core/Views/Drawer/DrawerPanelOverlay.swift
git commit -m "feat: move global app preferences to dedicated preferences store"
```

---

### Task 6: Add KeybindingsStore with File-Based Overrides

**Files:**
- Create: `Sources/AgentStudio/Core/Stores/KeybindingsStore.swift`
- Create: `Sources/AgentStudio/Core/Stores/KeybindingsPersistor.swift`
- Modify: `Sources/AgentStudio/App/AppCommand.swift`
- Modify: `Sources/AgentStudio/App/AppDelegate.swift`
- Test: `Tests/AgentStudioTests/App/AppCommandTests.swift`

**Step 1: Write the failing test**

```swift
@Test
func commandDispatcher_appliesKeybindingOverridesFromStore() throws {
    // Arrange keybinding override map
    // Act boot dispatcher
    // Assert command definitions use overridden keybindings
}
```

**Step 2: Run test to verify it fails**

Run:

```bash
SWIFT_BUILD_DIR=".build-agent-persistence" swift test --build-path "$SWIFT_BUILD_DIR" --filter "AppCommandTests/commandDispatcher_appliesKeybindingOverridesFromStore"
```

Expected: FAIL

**Step 3: Write minimal implementation**

- Define keybinding file schema keyed by `AppCommand.rawValue`.
- Load and apply overrides at app bootstrap.
- Keep defaults in code as fallback.

**Step 4: Run test to verify it passes**

Run same command as Step 2.

Expected: PASS

**Step 5: Commit**

```bash
git add Sources/AgentStudio/Core/Stores/KeybindingsStore.swift Sources/AgentStudio/Core/Stores/KeybindingsPersistor.swift Sources/AgentStudio/App/AppCommand.swift Sources/AgentStudio/App/AppDelegate.swift Tests/AgentStudioTests/App/AppCommandTests.swift
git commit -m "feat: add keybindings store with json overrides"
```

---

### Task 7: Add Bootstrap Coordinator for Multi-Store Load Order

**Files:**
- Create: `Sources/AgentStudio/App/WorkspaceBootstrapCoordinator.swift`
- Modify: `Sources/AgentStudio/App/AppDelegate.swift`
- Modify: `Sources/AgentStudio/App/MainSplitViewController.swift`
- Test: `Tests/AgentStudioTests/Core/Stores/WorkspaceStoreTests.swift`

**Step 1: Write the failing test**

```swift
@Test
func bootstrap_loadsCanonicalThenUIThenCache_withRevisionGuard() {
    // Arrange mismatched cache revision
    // Act bootstrap
    // Assert cache invalidated and canonical state still loads
}
```

**Step 2: Run test to verify it fails**

Run:

```bash
SWIFT_BUILD_DIR=".build-agent-persistence" swift test --build-path "$SWIFT_BUILD_DIR" --filter "bootstrap_loadsCanonicalThenUIThenCache_withRevisionGuard"
```

Expected: FAIL

**Step 3: Write minimal implementation**

- Coordinator responsibilities:
  - restore canonical store
  - restore workspace UI store
  - restore global prefs + keybindings
  - conditionally restore cache using revision guard
  - schedule async cache refresh

**Step 4: Run test to verify it passes**

Run same command as Step 2.

Expected: PASS

**Step 5: Commit**

```bash
git add Sources/AgentStudio/App/WorkspaceBootstrapCoordinator.swift Sources/AgentStudio/App/AppDelegate.swift Sources/AgentStudio/App/MainSplitViewController.swift Tests/AgentStudioTests/Core/Stores/WorkspaceStoreTests.swift
git commit -m "feat: add bootstrap coordinator for segmented persistence load sequence"
```

---

### Task 8: Route Sidebar Refresh Pipeline into Cache Store + Cache File

**Files:**
- Modify: `Sources/AgentStudio/Features/Sidebar/RepoSidebarContentView.swift`
- Modify: `Sources/AgentStudio/Features/Sidebar/SidebarGitRepositoryInspector.swift`
- Modify: `Sources/AgentStudio/Core/Stores/WorkspaceCacheStore.swift`
- Test: `Tests/AgentStudioTests/Features/Sidebar/SidebarGitRepositoryInspectorTests.swift`

**Step 1: Write the failing test**

```swift
@Test
func prLookup_refresh_updatesCacheAndPersists_withoutMutatingCanonicalRepoState() async {
    // Arrange canonical + cache
    // Act refresh pipeline
    // Assert cache changed, canonical repo model unchanged
}
```

**Step 2: Run test to verify it fails**

Run:

```bash
SWIFT_BUILD_DIR=".build-agent-persistence" swift test --build-path "$SWIFT_BUILD_DIR" --filter "SidebarGitRepositoryInspectorTests/prLookup_refresh_updatesCacheAndPersists_withoutMutatingCanonicalRepoState"
```

Expected: FAIL

**Step 3: Write minimal implementation**

- Ensure metadata/status/PR refresh mutates cache store only.
- Persist cache store with throttled write.
- Keep worktree discovery as canonical update only when path identity changes.

**Step 4: Run test to verify it passes**

Run same command as Step 2.

Expected: PASS

**Step 5: Commit**

```bash
git add Sources/AgentStudio/Features/Sidebar/RepoSidebarContentView.swift Sources/AgentStudio/Features/Sidebar/SidebarGitRepositoryInspector.swift Sources/AgentStudio/Core/Stores/WorkspaceCacheStore.swift Tests/AgentStudioTests/Features/Sidebar/SidebarGitRepositoryInspectorTests.swift
git commit -m "refactor: route sidebar git metadata refresh through cache store"
```

---

### Task 9: Migrate Remaining UserDefaults Scattered Keys

**Files:**
- Modify: `Sources/AgentStudio/Features/CommandBar/CommandBarState.swift`
- Modify: `Sources/AgentStudio/Features/Webview/URLHistoryService.swift`
- Modify: `Sources/AgentStudio/App/MainWindowController.swift`
- Modify: `Sources/AgentStudio/App/MainSplitViewController.swift`
- Test: `Tests/AgentStudioTests/Features/CommandBar/CommandBarStateTests.swift`
- Test: `Tests/AgentStudioTests/Features/Webview/URLHistoryServiceTests.swift`

**Step 1: Write the failing tests**

```swift
@Test
func commandBarRecents_persistThroughWorkspaceUIStore() { }

@Test
func urlHistory_persistsThroughDedicatedJsonStorage() { }
```

**Step 2: Run tests to verify they fail**

Run:

```bash
SWIFT_BUILD_DIR=".build-agent-persistence" swift test --build-path "$SWIFT_BUILD_DIR" --filter "CommandBarStateTests|URLHistoryServiceTests/.*persist.*"
```

Expected: FAIL

**Step 3: Write minimal implementation**

- Move command bar recents to workspace UI persistence.
- Move webview history/favorites to dedicated files.
- Decide window frame/sidebar collapsed ownership and move to workspace UI or canonical state consistently.

**Step 4: Run tests to verify they pass**

Run same command as Step 2.

Expected: PASS

**Step 5: Commit**

```bash
git add Sources/AgentStudio/Features/CommandBar/CommandBarState.swift Sources/AgentStudio/Features/Webview/URLHistoryService.swift Sources/AgentStudio/App/MainWindowController.swift Sources/AgentStudio/App/MainSplitViewController.swift Tests/AgentStudioTests/Features/CommandBar/CommandBarStateTests.swift Tests/AgentStudioTests/Features/Webview/URLHistoryServiceTests.swift
git commit -m "refactor: migrate remaining userdefaults keys into segmented persistence stores"
```

---

### Task 10: Full Verification and Documentation Closure

**Files:**
- Modify: `docs/architecture/component_architecture.md`
- Modify: `docs/architecture/README.md`

**Step 1: Verify formatting and lint**

Run:

```bash
mise run format
mise run lint
```

Expected: both exit `0`

**Step 2: Run targeted test groups**

Run:

```bash
SWIFT_BUILD_DIR=".build-agent-persistence" swift test --build-path "$SWIFT_BUILD_DIR" --filter "WorkspacePersistorTests|WorkspaceStoreTests|SidebarGitRepositoryInspectorTests|SidebarRepoGroupingTests|AppCommandTests|CommandBarStateTests|URLHistoryServiceTests"
```

Expected: all pass

**Step 3: Run full test suite**

Run:

```bash
mise run test
```

Expected: exit `0` (respect project skip flags for E2E/serialized suites if configured)

**Step 4: Final docs pass**

- Ensure architecture docs reflect:
  - file responsibilities
  - ownership boundaries
  - load and refresh sequencing
  - migration and compatibility behavior

**Step 5: Commit**

```bash
git add docs/architecture/component_architecture.md docs/architecture/README.md
git commit -m "docs: finalize segmented persistence architecture and verification notes"
```

---

## Notes for Execution

- Keep all Swift commands strictly sequential (no parallel/background SwiftPM processes).
- Use one stable `SWIFT_BUILD_DIR` per execution session.
- No destructive git commands.
- Coordinator methods must sequence stores only; domain decisions remain inside owning stores.
