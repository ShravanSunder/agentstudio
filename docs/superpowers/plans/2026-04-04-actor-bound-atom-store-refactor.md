# Actor-Bound Atom Store Refactor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the DI-driven atom access model with an actor-bound `AtomStore` + `AtomScope` + `@Atom` helper system, then refactor atoms, derived selectors, persistence stores, and boot wiring to use it consistently in one clean implementation pass.

**Architecture:** State atoms stay `@MainActor @Observable` and are owned by a single app-scope `AtomStore`. `AtomScope` provides ambient access to the current store plus scoped test overrides, and `@Atom(\.foo)` is sugar over `AtomScope.store[keyPath:]`. Persistence remains in separate store wrappers with explicit constructor injection for non-state dependencies such as clocks and persistors.

**Tech Stack:** Swift 6.2, Swift Observation, `@MainActor`, `@TaskLocal`, AppKit + SwiftUI

---

## Scope Check

This plan covers one coherent subsystem:

- atom/store access model
- derived selector access model
- persistence wrapper integration
- boot wiring
- test scoping

It does **not** cover:

- generic service DI
- non-UI actor-local store abstractions
- cached selector helper infrastructure
- broader architecture docs beyond the files named here

**Implementation stance:** land the new model fully and remove the old plumbing in the same PR. No backward-compatibility bridge, no parallel old/new access patterns left behind.

**V1 scope note:** `AtomReader`, `Derived<Value>`, and `DerivedSelector<Param, Value>` are part of the v1 infrastructure build. Concrete selectors such as `PaneDisplayDerived` and `DynamicViewDerived` still exist, but they sit on top of those shared primitives rather than replacing them.

## File Structure

### New files

| File | Responsibility |
|------|----------------|
| `Sources/AgentStudio/Core/Atoms/ManagementModeAtom.swift` | Pure state atom for management mode |
| `Sources/AgentStudio/App/State/AtomStore.swift` | App-scope actor-bound store owning live atom instances |
| `Sources/AgentStudio/App/State/AtomScope.swift` | Production store binding + test-scoped override access |
| `Sources/AgentStudio/App/State/Atom.swift` | `@Atom(\.foo)` property wrapper sugar over `AtomScope.store` |
| `Sources/AgentStudio/App/State/AtomReader.swift` | Jotai-like `get` primitive over the current atom scope |
| `Sources/AgentStudio/App/State/Derived.swift` | Zero-input derived primitive |
| `Sources/AgentStudio/App/State/DerivedSelector.swift` | Parameterized derived primitive |
| `Sources/AgentStudio/Core/Atoms/WorkspaceAtom.swift` | Canonical workspace state + mutations extracted from `WorkspaceStore` |
| `Sources/AgentStudio/Core/Atoms/RepoCacheAtom.swift` | Renamed workspace repo cache atom |
| `Sources/AgentStudio/Core/Atoms/UIStateAtom.swift` | Renamed UI state atom |
| `Sources/AgentStudio/Core/Atoms/SessionRuntimeAtom.swift` | Runtime status atom extracted from `SessionRuntime` |
| `Sources/AgentStudio/Core/Atoms/PaneDisplayDerived.swift` | Derived selector over workspace + repo cache |
| `Sources/AgentStudio/Core/Atoms/DynamicViewDerived.swift` | Derived selector for dynamic-view projection |
| `Tests/AgentStudioTests/App/State/AtomScopeTests.swift` | Scope + override invariants |
| `Tests/AgentStudioTests/Core/Atoms/DerivedSelectorObservationTests.swift` | Observation-through-selector validation |

### Modified files

| File | Responsibility |
|------|----------------|
| `docs/superpowers/specs/2026-04-04-actor-bound-atom-store-design.md` | Source-of-truth spec for this architecture |
| `docs/superpowers/specs/2026-04-02-swift-dependencies-adoption.md` | Historical note only; superseded |
| `docs/superpowers/plans/2026-04-02-atoms-stores-refactor.md` | Mark superseded |
| `Sources/AgentStudio/App/ManagementModeMonitor.swift` | Behavior-only monitor reading `ManagementModeAtom` |
| `Sources/AgentStudio/Core/Stores/WorkspaceStore.swift` | Persistence wrapper only |
| `Sources/AgentStudio/Core/Stores/RepoCacheStore.swift` | Persistence wrapper only |
| `Sources/AgentStudio/Core/Stores/UIStateStore.swift` | Persistence wrapper only |
| `Sources/AgentStudio/Core/RuntimeEventSystem/SessionRuntime.swift` | Behavior type reading `SessionRuntimeAtom` |
| `Sources/AgentStudio/App/AppDelegate.swift` | Boot creates/binds `AtomStore`, passes explicit dependencies |
| `Sources/AgentStudio/App/MainWindowController.swift` | Switch to atom-store access |
| `Sources/AgentStudio/App/MainSplitViewController.swift` | Switch to atom-store access |
| `Sources/AgentStudio/App/Panes/PaneTabViewController.swift` | Switch to atom/selector access |
| `Sources/AgentStudio/Core/Views/*` and `Features/*` readers | Switch from direct store/DI singleton patterns to `@Atom` or explicit `atoms` |
| `Tests/AgentStudioTests/**/*` | Replace singleton/DI assumptions with scoped `AtomStore` setup |

### Explicit removals

| File or pattern | Why |
|-----------------|-----|
| `swift-dependencies` package dependency | No longer used for atoms/state access |
| `Sources/AgentStudio/Infrastructure/DependencyKeys.swift` | Replaced by `AtomStore` + `AtomScope` |
| `ManagementModeTestLock.swift` | Singleton-driven serialization no longer needed after state scoping changes |

### Clock policy

Persistence stores use explicit constructor injection for clocks:

```swift
init(
    persistor: WorkspacePersistor,
    clock: any Clock<Duration> = ContinuousClock()
)
```

Tests inject `TestPushClock` directly through those constructors. Keep `TestPushClock` for this refactor; migrating clock helpers is out of scope.

---

## Task 0: Replace DI Scaffolding With AtomStore Infrastructure

**Files:**
- Modify: `Package.swift` only if `swift-dependencies` is actually present
- Modify: `Package.resolved` only if `swift-dependencies` is actually present
- Create: `Sources/AgentStudio/App/State/AtomStore.swift`
- Create: `Sources/AgentStudio/App/State/AtomScope.swift`
- Create: `Sources/AgentStudio/App/State/Atom.swift`
- Create: `Sources/AgentStudio/App/State/AtomReader.swift`
- Create: `Sources/AgentStudio/App/State/Derived.swift`
- Create: `Sources/AgentStudio/App/State/DerivedSelector.swift`
- Create: `Tests/AgentStudioTests/Helpers/TestAtomStore.swift`
- Test: `Tests/AgentStudioTests/App/State/AtomScopeTests.swift`

- [ ] **Step 1: Check whether `swift-dependencies` is present**

Run:

```bash
rg -n "swift-dependencies|Dependencies" Package.swift
```

If absent, skip package edits.

If present, remove the package and product entries. The atom system is now built in-repo.

- [ ] **Step 2: Write the failing scope test**

Create `Tests/AgentStudioTests/App/State/AtomScopeTests.swift` with a focused test that proves a scoped override wins over production:

```swift
import Testing

@testable import AgentStudio

@MainActor
struct AtomScopeTests {
    @Test
    func overrideStore_winsWithinScopedBlock_only() async throws {
        let production = AtomStore()
        let override = AtomStore()

        AtomScope.setUp(production)
        #expect(AtomScope.store === production)

        await AtomScope.$override.withValue(override) {
            #expect(AtomScope.store === override)
        }

        #expect(AtomScope.store === production)
    }
}
```

- [ ] **Step 3: Run the test to confirm it fails**

Run: `BUILD_PATH=.build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8); swift test --build-path "$BUILD_PATH" --filter AtomScopeTests`

Expected: FAIL because `AtomStore` / `AtomScope` do not exist yet.

- [ ] **Step 4: Create `AtomStore.swift`**

`AtomStore` grows incrementally across the plan.

At Task 0, create the shell only with the atom types that already exist at that point:

- `RepoCacheAtom` and `UIStateAtom` are created in Task 3
- `WorkspaceAtom` is created in Task 5
- `SessionRuntimeAtom` is created in Task 7

So Task 0 may use temporary stubs or a partial `AtomStore` that is expanded in later tasks. Do not block Task 0 on all atom types existing up front.

```swift
import Observation

@MainActor
final class AtomStore {
    // Atoms are added incrementally by subsequent tasks.
    init() {}
}
```

Each later task that creates an atom adds it to `AtomStore` and updates the initializer accordingly.

- [ ] **Step 4b: Create `AtomReader.swift`, `Derived.swift`, and `DerivedSelector.swift`**

Create the v1 derivation primitives:

```swift
@MainActor
struct AtomReader {
    func callAsFunction<Value>(_ keyPath: KeyPath<AtomStore, Value>) -> Value {
        AtomScope.store[keyPath: keyPath]
    }
}

@MainActor
struct Derived<Value> {
    let compute: (AtomReader) -> Value

    var value: Value {
        compute(AtomReader())
    }
}

@MainActor
struct DerivedSelector<Param, Value> {
    let compute: (AtomReader, Param) -> Value

    func value(for param: Param) -> Value {
        compute(AtomReader(), param)
    }
}
```

- [ ] **Step 5: Create `AtomScope.swift`**

```swift
nonisolated enum AtomScope {
    @MainActor
    private static var production: AtomStore!

    @TaskLocal
    static var override: AtomStore?

    @MainActor
    static var store: AtomStore {
        override ?? production
    }

    @MainActor
    static func setUp(_ store: AtomStore) {
        production = store
    }
}
```

- [ ] **Step 6: Create `Atom.swift`**

```swift
@MainActor
@propertyWrapper
struct Atom<Value> {
    private let keyPath: KeyPath<AtomStore, Value>

    init(_ keyPath: KeyPath<AtomStore, Value>) {
        self.keyPath = keyPath
    }

    var wrappedValue: Value {
        AtomScope.store[keyPath: keyPath]
    }
}
```

- [ ] **Step 7: Create `TestAtomStore.swift`**

```swift
import Testing

@testable import AgentStudio

@MainActor
func withTestAtomStore<T>(
    _ body: (AtomStore) throws -> T
) rethrows -> T {
    let atoms = AtomStore()
    return try AtomScope.$override.withValue(atoms) {
        try body(atoms)
    }
}
```

- [ ] **Step 8: Re-run the scope test**

Run: `BUILD_PATH=.build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8); swift test --build-path "$BUILD_PATH" --filter AtomScopeTests`

Expected: PASS

---

## Task 1: Validate Observation Through Struct-Based Derived Selectors

**Files:**
- Create: `Tests/AgentStudioTests/Core/Atoms/DerivedSelectorObservationTests.swift`

- [ ] **Step 1: Write the failing observation test**

```swift
import Observation
import Testing

@testable import AgentStudio

private final class Flag: @unchecked Sendable {
    var fired = false
}

@MainActor
struct DerivedSelectorObservationTests {
    @Test
    func paneDisplayDerived_tracksUnderlyingAtomReads() async throws {
        try await withTestAtomStore { atoms in
            let pane = Pane(source: .floating(launchDirectory: nil, title: nil), title: "Initial")
            atoms.workspace.addPane(pane)

            let flag = Flag()
            let selector = PaneDisplayDerived()

            withObservationTracking {
                _ = selector.displayLabel(for: pane.id)
            } onChange: {
                flag.fired = true
            }

            atoms.workspace.renamePane(pane.id, title: "Updated")

            #expect(flag.fired)
        }
    }
}
```

- [ ] **Step 2: Run the test to verify the current selector model fails or is unimplemented**

Run: `BUILD_PATH=.build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8); swift test --build-path "$BUILD_PATH" --filter DerivedSelectorObservationTests`

Expected: FAIL because `PaneDisplayDerived` and helper plumbing are not migrated yet.

- [ ] **Step 3: Keep this test as a required gate**

Do not broaden selector migration until this test passes. If struct-based selectors fail the observation contract, promote the selector type to a cached or class-based shape before continuing.

---

## Task 2: Extract `ManagementModeAtom` and Remove Monitor-Owned State

**Files:**
- Create: `Sources/AgentStudio/Core/Atoms/ManagementModeAtom.swift`
- Modify: `Sources/AgentStudio/App/ManagementModeMonitor.swift`
- Modify: `Tests/AgentStudioTests/App/ManagementModeTests.swift`
- Delete: `Tests/AgentStudioTests/Helpers/ManagementModeTestLock.swift`

- [ ] **Step 1: Write the failing management-mode test update**

Update `ManagementModeTests.swift` to use a fresh scoped `AtomStore()` instead of `ManagementModeMonitor.shared` + test lock.

- [ ] **Step 2: Run the filtered test and verify it fails**

Run: `BUILD_PATH=.build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8); swift test --build-path "$BUILD_PATH" --filter ManagementModeTests`

Expected: FAIL because `ManagementModeAtom` does not exist yet and monitor still owns state.

- [ ] **Step 3: Create `ManagementModeAtom.swift`**

```swift
import Observation

@MainActor
@Observable
final class ManagementModeAtom {
    private(set) var isActive = false

    func activate() { isActive = true }
    func deactivate() { isActive = false }
    func toggle() { isActive.toggle() }
}
```

- [ ] **Step 4: Update `ManagementModeMonitor.swift`**

Move state ownership into the atom. Keep behavior only.

Use:

```swift
@Atom(\.managementMode) private var managementMode
```

Keep the `startKeyboardMonitoring: Bool` test-safety parameter.

- [ ] **Step 5: Re-run the filtered tests**

Run: `BUILD_PATH=.build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8); swift test --build-path "$BUILD_PATH" --filter ManagementModeTests`

Expected: PASS

- [ ] **Step 6: Delete `ManagementModeTestLock.swift` immediately after the migration passes**

Once `ManagementModeMonitor` no longer relies on `.shared`, the lock is dead code. Remove it in this task rather than carrying it forward to Task 9.

---

## Task 3: Rename Existing Small Stores Into Atoms

**Files:**
- Rename: `Sources/AgentStudio/Core/Stores/WorkspaceUIStore.swift` → `Sources/AgentStudio/Core/Atoms/UIStateAtom.swift`
- Rename: `Sources/AgentStudio/Core/Stores/WorkspaceRepoCache.swift` → `Sources/AgentStudio/Core/Atoms/RepoCacheAtom.swift`
- Modify: all references

- [ ] **Step 1: Rename `WorkspaceUIStore` to `UIStateAtom`**
- [ ] **Step 2: Rename `WorkspaceRepoCache` to `RepoCacheAtom`**
- [ ] **Step 3: Update references and filtered tests**

Run:
- `BUILD_PATH=.build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8); swift test --build-path "$BUILD_PATH" --filter WorkspaceUIStoreTests`
- `BUILD_PATH=.build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8); swift test --build-path "$BUILD_PATH" --filter WorkspaceRepoCacheTests`

Expected: PASS after reference updates.

---

## Task 4: Convert Derived Projectors To Ambient Selectors

**Files:**
- Rename: `Sources/AgentStudio/Core/Views/PaneDisplayProjector.swift` → `Sources/AgentStudio/Core/Atoms/PaneDisplayDerived.swift`
- Rename: `Sources/AgentStudio/Core/Stores/DynamicViewProjector.swift` → `Sources/AgentStudio/Core/Atoms/DynamicViewDerived.swift`
- Modify: selector call sites

- [ ] **Step 1: Convert `PaneDisplayProjector` to `PaneDisplayDerived`**

Use:

```swift
@MainActor
struct PaneDisplayDerived {
    @Atom(\.workspace) private var workspace
    @Atom(\.repoCache) private var repoCache
}
```

- [ ] **Step 2: Convert `DynamicViewProjector` to `DynamicViewDerived`**

Use either:

```swift
@MainActor
struct DynamicViewDerived {
    @Atom(\.workspace) private var workspace
    @Atom(\.repoCache) private var repoCache
}
```

or the minimal concrete selector shape justified by the current API surface.

- [ ] **Step 3: Run the observation validation test**

Run: `BUILD_PATH=.build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8); swift test --build-path "$BUILD_PATH" --filter DerivedSelectorObservationTests`

Expected: PASS

---

## Task 5: Split `WorkspaceStore` Into `WorkspaceAtom` + Persistence Wrapper

**Files:**
- Create: `Sources/AgentStudio/Core/Atoms/WorkspaceAtom.swift`
- Modify: `Sources/AgentStudio/Core/Stores/WorkspaceStore.swift`
- Modify: workspace call sites

### What moves into `WorkspaceAtom`

- all canonical workspace state
- all workspace mutation methods
- all query methods
- all undo snapshot types and helpers
- `hydrate(...)`
- transient UI fields already living on the old store and read by views

### What stays in `WorkspaceStore`

- `WorkspacePersistor`
- injected `clock`
- dirty/debounce state
- `restore()`
- `flush()`
- `persistNow()`
- `withObservationTracking` setup and re-registration
- any pre-persist hook

### Observation pattern for persistence stores

The persistence wrapper must use the re-registration pattern:

```swift
func startObserving() {
    func observe() {
        withObservationTracking {
            workspace.readTrackedProperties()
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                self?.scheduleDebouncedSave()
                observe()
            }
        }
    }
    observe()
}
```

`startObserving()` is called only after `hydrate(...)` completes.

### Workspace tracked vs excluded fields

| Field | Observe for save? | Why |
|------|-------------------|-----|
| `repos` | yes | canonical persisted state |
| `tabs` | yes | canonical persisted state |
| `panes` | yes | canonical persisted state |
| `activeTabId` | yes | canonical persisted state |
| `watchedPaths` | yes | canonical persisted state |
| `workspaceId` | yes | canonical persisted state |
| `workspaceName` | yes | canonical persisted state |
| `sidebarWidth` | yes | canonical persisted state |
| `unavailableRepoIds` | yes | canonical persisted state |
| `createdAt` | yes | canonical persisted state |
| `updatedAt` | no | written during save, would create feedback loop |
| `windowFrame` | no | flush-only, not debounced |

- [ ] **Step 1: Write failing workspace persistence/restore tests if missing**
- [ ] **Step 2: Extract `WorkspaceAtom`**

Move:
- canonical state
- mutation methods
- query methods
- undo snapshot logic
- `hydrate(...)`

Remove persistence lifecycle from the atom.

Add explicit `hydrate(...)` with the full persisted surface:

```swift
func hydrate(
    workspaceId: UUID,
    workspaceName: String,
    repos: [Repo],
    panes: [UUID: Pane],
    tabs: [Tab],
    activeTabId: UUID?,
    sidebarWidth: CGFloat,
    windowFrame: CGRect?,
    watchedPaths: [WatchedPath],
    unavailableRepoIds: Set<UUID>,
    createdAt: Date,
    updatedAt: Date
) {
    self.workspaceId = workspaceId
    self.workspaceName = workspaceName
    self.repos = repos
    self.panes = panes
    self.tabs = tabs
    self.activeTabId = activeTabId
    self.sidebarWidth = sidebarWidth
    self.windowFrame = windowFrame
    self.watchedPaths = watchedPaths
    self.unavailableRepoIds = unavailableRepoIds
    self.createdAt = createdAt
    self.updatedAt = updatedAt
}
```

Grep for `markDirty` in the old store and remove all remaining calls from the atom extraction. Do not trust stale counts.

- [ ] **Step 3: Rewrite `WorkspaceStore` as persistence-only**

Use explicit constructor injection:

```swift
@MainActor
final class WorkspaceStore {
    let persistor: WorkspacePersistor
    let clock: any Clock<Duration>

    @Atom(\.workspace) private var workspace
}
```

`WorkspaceStore.restore()` should:

1. load persisted state
2. call `workspace.hydrate(...)`
3. run prune/repair/invariant validation still owned by workspace state
4. call `startObserving()`

- [ ] **Step 4: Re-run focused workspace tests**

Run the existing workspace store suites plus any new focused persistence tests.

---

## Task 6: Create `RepoCacheStore` and `UIStateStore`

**Files:**
- Create: `Sources/AgentStudio/Core/Stores/RepoCacheStore.swift`
- Create: `Sources/AgentStudio/Core/Stores/UIStateStore.swift`
- Modify: `Sources/AgentStudio/App/AppDelegate.swift`

- [ ] **Step 1: Move cache/UI persistence out of `AppDelegate`**
- [ ] **Step 2: Implement `RepoCacheStore` with explicit `persistor` + `clock` injection**

Add explicit `RepoCacheAtom.hydrate(...)` covering:

```swift
func hydrate(
    repoEnrichmentByRepoId: [UUID: RepoEnrichment],
    worktreeEnrichmentByWorktreeId: [UUID: WorktreeEnrichment],
    pullRequestCountByWorktreeId: [UUID: Int],
    notificationCountByWorktreeId: [UUID: Int],
    recentTargets: [RecentWorkspaceTarget],
    sourceRevision: UInt64,
    lastRebuiltAt: Date?
) {
    self.repoEnrichmentByRepoId = repoEnrichmentByRepoId
    self.worktreeEnrichmentByWorktreeId = worktreeEnrichmentByWorktreeId
    self.pullRequestCountByWorktreeId = pullRequestCountByWorktreeId
    self.notificationCountByWorktreeId = notificationCountByWorktreeId
    self.recentTargets = recentTargets
    self.sourceRevision = sourceRevision
    self.lastRebuiltAt = lastRebuiltAt
}
```

- [ ] **Step 3: Implement `UIStateStore` with explicit `persistor` + `clock` injection**

Add explicit `UIStateAtom.hydrate(...)` covering:

```swift
func hydrate(
    expandedGroups: Set<String>,
    checkoutColors: [String: String],
    filterText: String,
    isFilterVisible: Bool
) {
    self.expandedGroups = expandedGroups
    self.checkoutColors = checkoutColors
    self.filterText = filterText
    self.isFilterVisible = isFilterVisible
}
```

- [ ] **Step 4: Add/adjust focused tests**

Run:
- `BUILD_PATH=.build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8); swift test --build-path "$BUILD_PATH" --filter WorkspacePersistorTests`

Expected: PASS with new store wrappers in place.

---

## Task 7: Extract `SessionRuntimeAtom` and Move Runtime Files

**Files:**
- Create: `Sources/AgentStudio/Core/Atoms/SessionRuntimeAtom.swift`
- Modify: `Sources/AgentStudio/Core/Stores/SessionRuntime.swift`
- Move: `Sources/AgentStudio/Core/Stores/SessionRuntime.swift` → `Sources/AgentStudio/Core/RuntimeEventSystem/SessionRuntime.swift`
- Move: `Sources/AgentStudio/Core/Stores/ZmxBackend.swift` → `Sources/AgentStudio/Core/RuntimeEventSystem/ZmxBackend.swift`

- [ ] **Step 1: Write/update focused `SessionRuntimeTests`**
- [ ] **Step 2: Extract `SessionRuntimeAtom`**
- [ ] **Step 3: Update `SessionRuntime` to read/write the atom via `@Atom`**
- [ ] **Step 4: Move files and fix references**
- [ ] **Step 5: Re-run filtered runtime tests**

---

## Task 8: Rewrite Boot Wiring Around `AtomStore`

**Files:**
- Modify: `Sources/AgentStudio/App/AppDelegate.swift`
- Modify: `Sources/AgentStudio/App/WorkspaceBootSequence.swift`
- Modify: long-lived object initializers that currently expect direct store/cache/UI objects

- [ ] **Step 1: Create one app-scope `AtomStore` at boot**
- [ ] **Step 2: Bind it with `AtomScope.setUp(atoms)`**
- [ ] **Step 3: Pass explicit constructor-injected non-state dependencies (`persistor`, `clock`, actor services`)**
- [ ] **Step 4: Remove any DI-framework/context propagation assumptions**
- [ ] **Step 5: Re-run boot/integration tests**

Run:
- `BUILD_PATH=.build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8); swift test --build-path "$BUILD_PATH" --filter AppBootSequenceTests`
- `BUILD_PATH=.build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8); swift test --build-path "$BUILD_PATH" --filter WorkspaceCacheCoordinator`

---

## Task 9: Replace Remaining Call Sites And Tests

**Files:**
- Modify: SwiftUI views, AppKit controllers, coordinators, and tests still assuming old store/cache/singleton access

Use these grep commands to drive the migration:

```bash
rg -l "ManagementModeMonitor.shared" Sources/ Tests/
rg -l "WorkspaceStore|WorkspaceRepoCache|WorkspaceUIStore|PaneDisplayProjector|DynamicViewProjector" Sources/ Tests/
```

### Call-site migration rules

- SwiftUI/AppKit/state readers that need atoms or selectors: switch to `@Atom(\.foo)`
- Persistence stores: use `@Atom(\.foo)` for state atoms, constructor injection for clocks/persistors
- Runtime/background actors: do **not** keep atom references; keep fact/delta flow explicit
- Tests: create a fresh scoped `AtomStore()` via `withTestAtomStore`

Representative file buckets:

- Management mode readers:
  - `Sources/AgentStudio/App/ManagementModeToolbarButton.swift`
  - `Sources/AgentStudio/Core/Views/ManagementModeDragShield.swift`
  - `Sources/AgentStudio/Core/Views/CustomTabBar.swift`
  - `Sources/AgentStudio/Core/Views/DraggableTabBarHostingView.swift`
  - `Sources/AgentStudio/Core/Views/Splits/PaneLeafContainer.swift`
  - `Sources/AgentStudio/Features/CommandBar/Views/CommandBarView.swift`
  - `Sources/AgentStudio/Features/Webview/WebviewPaneController.swift`
  - `Sources/AgentStudio/Features/Webview/Views/WebviewPaneMountView.swift`
  - `Sources/AgentStudio/Features/Bridge/Runtime/BridgePaneController.swift`
  - related tests under `Tests/AgentStudioTests/App/` and `Tests/AgentStudioTests/Core/Views/`

- Workspace/repo/UI readers:
  - `Sources/AgentStudio/App/MainSplitViewController.swift`
  - `Sources/AgentStudio/App/MainWindowController.swift`
  - `Sources/AgentStudio/App/Panes/PaneTabViewController.swift`
  - `Sources/AgentStudio/Core/Views/TabBarAdapter.swift`
  - `Sources/AgentStudio/Features/Sidebar/RepoSidebarContentView.swift`
  - `Sources/AgentStudio/Features/CommandBar/CommandBarDataSource.swift`
  - related tests under `Tests/AgentStudioTests/Core/` and `Tests/AgentStudioTests/Features/`

- [ ] **Step 1: Replace direct old-store reads with `@Atom` or ambient selector access**
- [ ] **Step 2: Replace non-view constructor threading with the new atom access rules**
- [ ] **Step 3: Replace singleton-based tests with `withTestAtomStore` or equivalent scoped override**
- [ ] **Step 4: Delete any now-obsolete helpers that remain after the earlier task removals**

---

## Task 10: Docs And Verification

**Files:**
- Modify: `docs/superpowers/specs/2026-04-04-actor-bound-atom-store-design.md` if implementation details clarified
- Modify: architecture docs touched by the refactor
- Modify: `CLAUDE.md`
- Verify: old DI-driven docs are marked superseded

- [ ] **Step 1: Run the focused validation suites**

Run:
- `BUILD_PATH=.build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8); swift test --build-path "$BUILD_PATH" --filter AtomScopeTests`
- `BUILD_PATH=.build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8); swift test --build-path "$BUILD_PATH" --filter DerivedSelectorObservationTests`

- [ ] **Step 2: Run the full suite**

Run: `mise run test`

Expected: PASS

- [ ] **Step 3: Run lint**

Run:
```bash
mise trust
mise run lint
```

Expected: PASS

- [ ] **Step 4: Verify old docs are superseded and new docs are the source of truth**

Expected:
- `docs/superpowers/specs/2026-04-04-actor-bound-atom-store-design.md` is current
- `docs/superpowers/specs/2026-04-02-swift-dependencies-adoption.md` is historical/superseded
- `docs/superpowers/plans/2026-04-02-atoms-stores-refactor.md` points to this plan as superseded
- `CLAUDE.md` reflects the AtomStore / AtomScope / @Atom architecture, including how views vs non-view code access atoms

---

## Notes For The Implementing Agent

- Do not reintroduce a DI framework for atom access as a shortcut.
- Keep `@MainActor` on atoms/selectors/stores unless a pure helper explicitly does not touch live state.
- Use constructor injection for clocks/persistors/services.
- If struct-based derived selector observation fails the validation test, stop and revise the selector implementation before proceeding.
- Avoid broadening the scope into generic service DI, cached selector frameworks, or non-UI actor-local store abstractions in the first pass.
