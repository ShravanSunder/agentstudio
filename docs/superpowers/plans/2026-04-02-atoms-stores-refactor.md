# Atoms & Stores Refactor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Align the codebase to the Jotai-inspired state management model: atoms own state with `private(set)`, stores observe atoms via `@Observable` and handle persistence, derived computations are pure functions.

**Architecture:** Split each fused "store+state" class into an atom (pure `@Observable` state + mutations) and a store (persistence wrapper that observes the atom and saves/restores). Atoms expose a `hydrate()` method for stores to populate state during restore — this preserves the `private(set)` boundary. Stores use `withObservationTracking` to detect changes and schedule debounced saves. Transient state (zoom, minimize) stays on the `Tab` model — it's already excluded from `PersistableState` encoding.

**Tech Stack:** Swift 6.2, `@Observable`, `@MainActor`, `withObservationTracking`

---

## Mental Model

```
PRIMITIVE ATOMS (Core/Atoms/)
  @Observable, private(set), own state, mutation methods.
  No persistence. No callbacks. No event interception. No resource management.
  Atoms expose hydrate() for stores to populate state during restore.
  Atoms have ZERO knowledge of whether they are persisted.

  WorkspaceAtom        ← tabs, panes, repos, worktrees, layouts, mutations, undo snapshots
  RepoCacheAtom        ← branch names, git status, PR counts
  UIStateAtom          ← expanded groups, colors, sidebar filter
  ManagementModeAtom   ← isActive: Bool
  SessionRuntimeAtom   ← runtime statuses per pane (injected, not singleton)

DERIVED (Core/Atoms/)
  Read-only. Pure functions from atoms. No owned state.

  PaneDisplayDerived   ← reads WorkspaceAtom + RepoCacheAtom → display labels
  DynamicViewDerived   ← reads WorkspaceAtom → tab groupings

STORES (Core/Stores/)
  Persistence wrappers. Compose atoms by holding references.
  Observe atoms via @Observable — when atom state changes, schedule debounced save.
  Call atom.hydrate() during restore. Read atom properties during save.

  WorkspaceStore       ← observes WorkspaceAtom, saves → workspace.state.json
  RepoCacheStore       ← observes RepoCacheAtom, saves → workspace.cache.json
  UIStateStore         ← observes UIStateAtom, saves → workspace.ui.json

BEHAVIOR (stays in App/, Features/)
  AppKit event interception, resource lifecycle, C API bridges.
  Reads/writes atoms but doesn't own state.

  ManagementModeMonitor ← keyboard interception, first responder mgmt
                          reads/writes ManagementModeAtom
  SessionRuntime        ← backend coordination, health checks
                          reads/writes SessionRuntimeAtom

NOT TOUCHED
  WorkspacePersistor   ← shared file I/O mechanics, used by stores
  SurfaceManager       ← surface types (ManagedSurface, SurfaceHealth) are in Features/Terminal/,
                          Core can't import them. Two count properties don't earn an atom.
  AppLifecycleStore    ← already in-memory only, already in App/
  WindowLifecycleStore ← already in-memory only, already in App/
```

### How stores observe atoms

**CRITICAL:** `withObservationTracking` fires when ANY property read in the tracking closure changes. The tracking closure MUST read EVERY persisted property. If a property is missing, mutations to it won't trigger saves — silent data loss.

The tracking closure must match the `hydrate()` parameter list exactly. If hydrate takes it, the observation must read it.

```swift
@MainActor
final class WorkspaceStore {
    @ObservationIgnored @Dependency(\.workspaceAtom) var atom
    private let persistor: WorkspacePersistor

    func startObserving() {
        func observe() {
            withObservationTracking {
                // MUST read ALL persisted properties — missing = silent data loss
                _ = atom.repos
                _ = atom.tabs
                _ = atom.panes
                _ = atom.activeTabId
                _ = atom.watchedPaths
                _ = atom.workspaceId
                _ = atom.workspaceName
                _ = atom.sidebarWidth
                _ = atom.windowFrame
                _ = atom.unavailableRepoIds
                _ = atom.createdAt
                // NOTE: Do NOT observe atom.updatedAt — it is set by persistNow()
                // during save. Observing it would create a save → mutate → save loop.
                // Similarly, windowFrame is flush-only (not debounced), so observing
                // it is optional — it won't cause a loop but adds noise.
            } onChange: { [weak self] in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.scheduleDebouncedSave()
                    observe()  // re-register for next change
                }
            }
        }
        observe()
    }
}
```

**Timing:** `startObserving()` is called at the END of `restore()`, AFTER `atom.hydrate()` completes. This is synchronous — `hydrate()` sets properties, then `startObserving()` registers. No async gap between them.

**Test clock:** Tests use `TestPushClock` (existing helper at `Tests/Helpers/TestPushClock.swift`). Use `clock.waitForPendingSleepCount(atLeast: 1)` to wait for the debounce to register, then `clock.advance(by:)` to trigger it. No wall-clock sleeps.
```

### How atoms are hydrated during restore

Atoms use `private(set)` on all properties. Stores can't assign directly. Instead, atoms expose a `hydrate()` method:

```swift
@Observable
final class WorkspaceAtom {
    private(set) var repos: [Repo] = []
    private(set) var tabs: [Tab] = []
    // ...

    /// Populate state from persisted data. Called by WorkspaceStore during restore.
    func hydrate(
        repos: [Repo], tabs: [Tab], panes: [UUID: Pane],
        activeTabId: UUID?, /* ... all persisted fields */
    ) {
        self.repos = repos
        self.tabs = tabs
        self.panes = panes
        self.activeTabId = activeTabId
        // ...
    }
}
```

This preserves `private(set)` — external code mutates through domain methods, stores hydrate through `hydrate()`.

### Composability

```
WorkspaceAtom ──── observed by ──── WorkspaceStore ──── saves to .state.json
RepoCacheAtom ──── observed by ──── RepoCacheStore ──── saves to .cache.json
UIStateAtom ────── observed by ──── UIStateStore ────── saves to .ui.json

ManagementModeAtom ──── no store ──── in-memory only (singleton)
SessionRuntimeAtom ──── no store ──── in-memory only (injected per SessionRuntime)
```

---

## Scope & Exclusions

### In scope
- Split `WorkspaceStore` → `WorkspaceAtom` + `WorkspaceStore`
- Rename `WorkspaceRepoCache` → `RepoCacheAtom`, create `RepoCacheStore`
- Rename `WorkspaceUIStore` → `UIStateAtom`, create `UIStateStore`
- Extract `ManagementModeAtom` from `ManagementModeMonitor`
- Extract `SessionRuntimeAtom` from `SessionRuntime`
- Rename `PaneDisplayProjector` → `PaneDisplayDerived`, `DynamicViewProjector` → `DynamicViewDerived`
- Move `SessionRuntime` + `ZmxBackend` from `Core/Stores/` to `Core/PaneRuntime/`
- Update CLAUDE.md and architecture docs

### NOT in scope — do not touch
- `SurfaceManager` — surface types (`ManagedSurface`, `SurfaceHealth`) live in `Features/Terminal/`, Core can't import them. Two count properties don't earn an atom.
- `WorkspacePersistor` — shared I/O mechanics, used by stores unchanged
- `AppLifecycleStore`, `WindowLifecycleStore` — already in-memory, already in `App/`
- Event bus projectors (`GitWorkingDirectoryProjector`, etc.) — real event subscribers, not derived atoms

### Transient state decision
Transient state (`Tab.zoomedPaneId`, `Tab.minimizedPaneIds`) stays on the `Tab` model. It's already excluded from `PersistableState` encoding. No `WorkspaceTransientAtom` — not worth a separate type when the data is tab-scoped and already handled correctly.

---

## Task Order

**Phase 0:** Add `swift-dependencies` package, create dependency keys (Task 0).
**Phase 1:** Create `Core/Atoms/`, establish pattern (Tasks 1-3).
**Phase 2:** Rename derived computations (Task 4).
**Phase 3:** Split WorkspaceStore, create RepoCacheStore + UIStateStore (Tasks 5-6).
**Phase 4:** Extract remaining atoms, move files (Tasks 7-8).
**Phase 5:** Tests + docs (Tasks 9-10).
**Phase 6:** Final verification (Task 11).

---

## File Structure

### New files

| File | What it is |
|------|-----------|
| `Core/Atoms/ManagementModeAtom.swift` | `isActive: Bool`, `toggle()`, `deactivate()` |
| `Core/Atoms/UIStateAtom.swift` | Renamed from `WorkspaceUIStore` |
| `Core/Atoms/RepoCacheAtom.swift` | Renamed from `WorkspaceRepoCache` |
| `Core/Atoms/WorkspaceAtom.swift` | State + mutations from `WorkspaceStore`, with `hydrate()` |
| `Core/Atoms/SessionRuntimeAtom.swift` | Runtime statuses from `SessionRuntime` |
| `Infrastructure/DependencyKeys.swift` | All atom dependency key registrations |
| `Core/Atoms/PaneDisplayDerived.swift` | Renamed from `PaneDisplayProjector` |
| `Core/Atoms/DynamicViewDerived.swift` | Renamed from `DynamicViewProjector` |
| `Core/Stores/RepoCacheStore.swift` | Persistence wrapper for `RepoCacheAtom` |
| `Core/Stores/UIStateStore.swift` | Persistence wrapper for `UIStateAtom` |

### Modified files

| File | Change |
|------|--------|
| `Core/Stores/WorkspaceStore.swift` | Becomes persistence wrapper — observes `WorkspaceAtom` |
| `App/ManagementModeMonitor.swift` | Behavior only — state moves to `ManagementModeAtom` |
| `Core/Stores/SessionRuntime.swift` | Moves to `Core/PaneRuntime/`, delegates state to `SessionRuntimeAtom` |
| `Core/Stores/ZmxBackend.swift` | Moves to `Core/PaneRuntime/` (not a store) |
| ~72 source files | Update type references |
| ~41 test files | Update type references |

### Unchanged files (explicit)

| File | Why |
|------|-----|
| `Core/Stores/WorkspacePersistor.swift` | Shared I/O — used by stores, not refactored |
| `Features/Terminal/Ghostty/SurfaceManager.swift` | Core can't import Features types |

---

## Task 0: Add `swift-dependencies` and create dependency keys

**Files:**
- Modify: `Package.swift`
- Create: `Sources/AgentStudio/Infrastructure/DependencyKeys.swift`

- [ ] **Step 1: Add swift-dependencies to Package.swift**

Add the package dependency:
```swift
.package(url: "https://github.com/pointfreeco/swift-dependencies", from: "1.12.0"),
```

Add `Dependencies` to the target's dependencies array.

- [ ] **Step 2: Build to verify package resolution**

Run: `SWIFT_BUILD_DIR=".build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8)" swift build --build-path "$SWIFT_BUILD_DIR" > /tmp/build-output.txt 2>&1 && echo "PASS" || echo "FAIL"`

Expected: PASS — package resolves, existing code compiles. No new types yet.

**Note:** `DependencyKeys.swift` is NOT created in this task. Each subsequent task registers its own dependency key alongside the atom it creates. This avoids forward-referencing types that don't exist yet.

- [ ] **Step 3: Commit**

```bash
git add Package.swift
git commit -m "chore: add swift-dependencies package, create DependencyKeys scaffold"
```

---

### swift-dependencies usage rules

These rules apply to ALL subsequent tasks. Verified against source code at `pointfreeco/swift-dependencies`.

**In production code:**

1. **`@ObservationIgnored @Dependency(\.atomName)`** — MANDATORY in `@Observable` classes. Without `@ObservationIgnored`, the dependency backing property triggers spurious observation.
2. **Never put `@Dependency` on `static` properties** — Task Locals are captured at first access, producing stale values.
3. **Use `withDependencies(from: self)` when creating child objects** — propagates the parent's dependency context.
4. **`liveValue` creates the singleton-equivalent instance** — cached in `CachedValues` dictionary, one per app lifecycle.

**In tests (Swift Testing, NOT XCTest):**

5. **Use `@Suite(.dependencies { })` for suite-level isolation:**
   ```swift
   @Suite(.dependencies {
       $0.workspaceAtom = WorkspaceAtom()
       $0.managementModeAtom = ManagementModeAtom()
   })
   struct MyTests {
       @Test func testSomething() {
           // Gets fresh isolated atoms — no singleton leakage
       }
   }
   ```

6. **Use `@Test(.dependency(\.atom, value))` for per-test overrides:**
   ```swift
   @Test(.dependency(\.continuousClock, .immediate))
   func testDebounce() { ... }
   ```

7. **Cache resets between tests** — `CachedValues` is keyed by test identifier, reset on test start. Fresh instances per test.

8. **`ManagementModeTestLock` can be deleted** — the custom serialization actor exists solely because of singleton state sharing. With dependency injection, each test is isolated by construction.

9. **`TestPushClock` can be replaced** — `swift-clocks` (transitive dependency) provides `TestClock` and `ImmediateClock`. Use `ImmediateClock` for simple cases, `TestClock` for precise timing control.

---

## Task 1: Create `Core/Atoms/` and extract `ManagementModeAtom`

Simplest atom — one `Bool`. Establishes the pattern.

**Files:**
- Create: `Sources/AgentStudio/Core/Atoms/ManagementModeAtom.swift`
- Modify: `Sources/AgentStudio/App/ManagementModeMonitor.swift`

- [ ] **Step 1: Create the atom**

```swift
import Observation

/// Atom: management mode state.
/// Pure state — no keyboard interception, no first responder management.
@Observable
@MainActor
final class ManagementModeAtom {
    // NO static let shared — instantiated by DependencyKey
    private(set) var isActive: Bool = false

    init() {}

    func toggle() {
        isActive.toggle()
    }

    func deactivate() {
        isActive = false
    }

    func activate() {
        isActive = true
    }
}
```

- [ ] **Step 2: Update ManagementModeMonitor — delegate state to atom**

```swift
import Dependencies

@MainActor
@Observable
final class ManagementModeMonitor {
    // NO static let shared — this is now a dependency itself

    @ObservationIgnored @Dependency(\.managementModeAtom) var atom

    var isActive: Bool { atom.isActive }

    init() {
        startKeyboardMonitoring()
    }

    func toggle() {
        atom.toggle()
        if atom.isActive {
            resignPaneFirstResponder()
        }
    }

    func deactivate() {
        atom.deactivate()
    }

    // ... keyboard monitoring + first responder code unchanged ...
}
```

**Register ManagementModeMonitor as a dependency** in `DependencyKeys.swift`:

```swift
struct ManagementModeMonitorKey: DependencyKey {
    static let liveValue = ManagementModeMonitor()
    static let testValue = ManagementModeMonitor()
}

extension DependencyValues {
    var managementModeMonitor: ManagementModeMonitor {
        get { self[ManagementModeMonitorKey.self] }
        set { self[ManagementModeMonitorKey.self] = newValue }
    }
}
```

**Migrate all 18 call sites** from `ManagementModeMonitor.shared` to `@Dependency`:

```bash
rg -l "ManagementModeMonitor.shared" Sources/ Tests/
```

For each file:
- If it's an `@Observable` class: add `@ObservationIgnored @Dependency(\.managementModeMonitor) var monitor`
- If it's a non-observable class: add `@Dependency(\.managementModeMonitor) var monitor`
- Replace `ManagementModeMonitor.shared.isActive` → `monitor.isActive`
- Replace `ManagementModeMonitor.shared.toggle()` → `monitor.toggle()`

**Delete `ManagementModeTestLock`** — no longer needed. Tests use `@Suite(.dependencies { })` for isolation.

Uncomment `ManagementModeAtomKey` and `ManagementModeMonitorKey` in `DependencyKeys.swift`.

- [ ] **Step 3: Build and test**

Run: `SWIFT_BUILD_DIR=".build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8)" swift test --build-path "$SWIFT_BUILD_DIR" --filter "ManagementMode" > /tmp/test-output.txt 2>&1 && echo "PASS" || echo "FAIL"`

- [ ] **Step 4: Commit**

```bash
git add Sources/AgentStudio/Core/Atoms/ManagementModeAtom.swift Sources/AgentStudio/App/ManagementModeMonitor.swift
git commit -m "refactor: extract ManagementModeAtom from ManagementModeMonitor"
```

---

## Task 2: Rename `WorkspaceUIStore` → `UIStateAtom`

47 lines. Rename + move.

**Files:**
- Rename: `Core/Stores/WorkspaceUIStore.swift` → `Core/Atoms/UIStateAtom.swift`
- Modify: ~5 files

- [ ] **Step 1: Rename file and class**

```bash
git mv Sources/AgentStudio/Core/Stores/WorkspaceUIStore.swift Sources/AgentStudio/Core/Atoms/UIStateAtom.swift
```

Rename `class WorkspaceUIStore` → `class UIStateAtom`. Doc comment: "Atom: UI preferences state. Persisted by UIStateStore."

- [ ] **Step 2: Update all references**

```bash
rg -l "WorkspaceUIStore" Sources/ Tests/
```

Find and replace `WorkspaceUIStore` → `UIStateAtom`.

- [ ] **Step 3: Build and test, commit**

---

## Task 3: Rename `WorkspaceRepoCache` → `RepoCacheAtom`

60 lines. Same pattern.

**Files:**
- Rename: `Core/Stores/WorkspaceRepoCache.swift` → `Core/Atoms/RepoCacheAtom.swift`
- Modify: ~20 files

- [ ] **Step 1: Rename file and class**

```bash
git mv Sources/AgentStudio/Core/Stores/WorkspaceRepoCache.swift Sources/AgentStudio/Core/Atoms/RepoCacheAtom.swift
```

Rename `class WorkspaceRepoCache` → `class RepoCacheAtom`. Doc comment: "Atom: repo enrichment cache. Persisted by RepoCacheStore."

- [ ] **Step 2: Update all references** (~20 files)

- [ ] **Step 3: Build and test, commit**

---

## Task 4: Rename derived computations → `*Derived`

- [ ] **Step 1: `PaneDisplayProjector` → `PaneDisplayDerived`**

```bash
git mv Sources/AgentStudio/Core/Views/PaneDisplayProjector.swift Sources/AgentStudio/Core/Atoms/PaneDisplayDerived.swift
```

Rename enum. Update ~14 files.

- [ ] **Step 2: `DynamicViewProjector` → `DynamicViewDerived`**

```bash
git mv Sources/AgentStudio/Core/Stores/DynamicViewProjector.swift Sources/AgentStudio/Core/Atoms/DynamicViewDerived.swift
```

Rename enum. Update ~3 files.

- [ ] **Step 3: Build and test, commit**

---

## Task 5: Split `WorkspaceStore` → `WorkspaceAtom` + `WorkspaceStore`

The big task. 1981 lines split into ~1500 line atom + ~400 line store.

### What goes where

**WorkspaceAtom** — ALL state + mutations + queries + undo + helpers:
- All `private(set) var` properties (repos, tabs, panes, activeTabId, etc.)
- All query methods (`pane(_:)`, `tab(_:)`, `repo(_:)`, etc.)
- All mutation methods. Remove every `markDirty()` call — atom doesn't know about persistence
- Undo methods (`snapshotForClose`, `restoreFromSnapshot`, etc.)
- Private helpers (`findTabIndex`, `canonicalRepos`, `pruneInvalidPanes`, `validateTabInvariants` — make these `internal` so store can call them during restore)
- NEW: `hydrate()` method for store to populate state during restore
- `init()` becomes parameterless

**WorkspaceStore** — persistence only:
- Properties: `atom: WorkspaceAtom`, `persistor`, `isDirty`, debounce state, clock
- `restore()` — loads from disk, calls `atom.hydrate()`, then calls `startObserving()`
- `startObserving()` — `withObservationTracking` on atom's persisted properties
- `scheduleDebouncedSave()` — debounce logic
- `flush()`, `persistNow()` — read from atom, write via persistor
- `prePersistHook`

**Files:**
- Create: `Sources/AgentStudio/Core/Atoms/WorkspaceAtom.swift`
- Modify: `Sources/AgentStudio/Core/Stores/WorkspaceStore.swift`
- Modify: ~72 source + test files

- [ ] **Step 1: Create `WorkspaceAtom.swift`**

1. Copy `WorkspaceStore.swift` to `Core/Atoms/WorkspaceAtom.swift`
2. Rename class: `WorkspaceStore` → `WorkspaceAtom`
3. Delete persistence section: `persistor`, `isDirty`, `debouncedSaveTask`, `clock`, `persistDebounceDuration`, `prePersistHook`, `restore()`, `markDirty()`, `flush()`, `persistNow()`, `tabPersistenceSummary()`, `layoutRatioSummary()`
4. Delete every `markDirty()` call (49 sites). The 3 methods with `// Do NOT markDirty()` already don't call it — no change needed there.
5. Simplify init: `init() {}`
6. Make `pruneInvalidPanes` and `validateTabInvariants` `internal` (not `private`) so store can call them during restore
7. Add hydrate method:

```swift
/// Populate state from persisted data. Called by WorkspaceStore during restore.
/// This is the only way to bulk-set private(set) properties from outside.
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

- [ ] **Step 2: Rewrite `WorkspaceStore.swift` as persistence wrapper**

See the "How stores observe atoms" and "How atoms are hydrated" sections above for the pattern. The implementing agent must:
1. Read the current `restore()` (lines ~1438-1507) and copy the logic, using `atom.hydrate(...)` instead of direct property assignment
2. Copy post-restore validation: `atom.pruneInvalidPanes(...)`, `atom.validateTabInvariants()`
3. Call `startObserving()` AFTER restore — not in init
4. Read the current `persistNow()` and copy the logic, reading from `atom.*` instead of `self.*`

- [ ] **Step 3: Move nested undo types to WorkspaceAtom**

`WorkspaceStore` currently has nested types: `TabCloseSnapshot`, `PaneCloseSnapshot`, `CloseEntry`. These are undo logic — they belong on `WorkspaceAtom`. Move them and update references in `PaneCoordinator`, `ActionExecutor`, and related files.

Find all references:
```bash
rg "WorkspaceStore\.TabCloseSnapshot\|WorkspaceStore\.PaneCloseSnapshot\|WorkspaceStore\.CloseEntry" Sources/ Tests/
```

Update to `WorkspaceAtom.TabCloseSnapshot`, etc.

- [ ] **Step 4: Update all call sites**

This is NOT just "add `.atom`". Two categories of call sites:

**Views and services that READ state** — these should hold `WorkspaceAtom` directly, not `WorkspaceStore`. `WorkspaceStore` is NOT `@Observable` anymore, so SwiftUI observation won't track through it.

```swift
// BEFORE
struct TabBarAdapter {
    let store: WorkspaceStore  // was @Observable
    var tabs: [Tab] { store.tabs }
}

// AFTER — views hold the atom directly
struct TabBarAdapter {
    let workspace: WorkspaceAtom  // @Observable
    var tabs: [Tab] { workspace.tabs }
}
```

**App/coordinator code that needs persistence** — these hold `WorkspaceStore` and access `store.atom` for state:

```swift
// App-level code that needs both state + persistence
let store: WorkspaceStore
store.atom.appendTab(tab)  // mutate state
store.flush()               // persist
```

Find all call sites:
```bash
rg -l "WorkspaceStore" Sources/ Tests/
```

For each file, decide: does this code need persistence (`store.restore()`, `store.flush()`)? If no → switch to `WorkspaceAtom`. If yes → keep `WorkspaceStore`, access state via `store.atom`.

**~72 files total.** Most views/services → `WorkspaceAtom`. App-level coordinators → keep `WorkspaceStore`.

- [ ] **Step 4: Build incrementally, fix errors, run full tests, commit**

---

## Task 6: Create `RepoCacheStore` and `UIStateStore` persistence wrappers

Both `RepoCacheAtom` and `UIStateAtom` are already persisted today via `WorkspacePersistor` (loaded/saved in `AppDelegate`). Create proper store wrappers so persistence isn't scattered in AppDelegate.

**Files:**
- Create: `Sources/AgentStudio/Core/Stores/RepoCacheStore.swift`
- Create: `Sources/AgentStudio/Core/Stores/UIStateStore.swift`
- Modify: `Sources/AgentStudio/App/AppDelegate.swift` — move persistence wiring to stores

- [ ] **Step 1: Read how AppDelegate currently loads/saves these**

Read `Sources/AgentStudio/App/AppDelegate.swift` lines ~83 and ~513 to understand the current persistence wiring for `WorkspaceRepoCache` and `WorkspaceUIStore`.

- [ ] **Step 2: Create `RepoCacheStore`**

Same pattern as WorkspaceStore but simpler — smaller atom, same observation approach.

```swift
@MainActor
final class RepoCacheStore {
    @ObservationIgnored @Dependency(\.repoCacheAtom) var atom
    private let persistor: WorkspacePersistor
    private let workspaceId: UUID  // needed for file path: {workspaceId}.workspace.cache.json

    init(persistor: WorkspacePersistor, workspaceId: UUID) {
        self.persistor = persistor
        self.workspaceId = workspaceId
    }

    func restore() {
        // Current: persistor.loadCache(for: workspaceId) in AppDelegate
        // Move that logic here, call atom.hydrate(...) with loaded data
        startObserving()
    }

    func flush() {
        // Current: persistor.saveCache(workspaceId: ...) in AppDelegate
        // Move that logic here, read from atom
    }

    private func startObserving() {
        // withObservationTracking on atom's persisted properties
    }
}
```

**Important:** The current persistence API uses workspace ID for file paths:
- `persistor.loadCache(for: store.workspaceId)` → `{uuid}.workspace.cache.json`
- `persistor.saveCache(workspaceId: ...)` → same

The implementing agent MUST read `AppDelegate.swift` lines ~83 and ~518 to understand the full load/save wiring before writing the store.

Add a `hydrate()` method to `RepoCacheAtom` for the `private(set)` boundary.

**Migrate readers:** Views that currently reference `RepoCacheAtom` (formerly `WorkspaceRepoCache`) directly for observation should use `@Dependency(\.repoCacheAtom)` instead. Check:
```bash
rg -l "RepoCacheAtom\|WorkspaceRepoCache" Sources/
```

Key files: `RepoSidebarContentView.swift`, `CommandBarDataSource.swift`, `PaneDisplayDerived.swift`.

- [ ] **Step 3: Create `UIStateStore`** — same pattern, same `workspaceId` requirement

Migrate readers: `MainWindowController.swift`, `MainSplitViewController.swift` reference `UIStateAtom` directly for observation. These should use `@Dependency(\.uiStateAtom)`.

- [ ] **Step 4: Update AppDelegate** — replace inline persistence wiring with store calls

Move `loadCache`/`saveCache`/`loadUI`/`saveUI` calls from AppDelegate into the stores. AppDelegate creates stores and calls `store.restore()` / `store.flush()`.

- [ ] **Step 5: Build, test, commit**

---

## Task 7: Extract `SessionRuntimeAtom` from `SessionRuntime`

**Files:**
- Create: `Sources/AgentStudio/Core/Atoms/SessionRuntimeAtom.swift`
- Modify: `Sources/AgentStudio/Core/Stores/SessionRuntime.swift`

- [ ] **Step 1: Create atom**

```swift
/// Atom: runtime status per pane.
/// NOT a singleton — injected into SessionRuntime so tests get isolated state.
@Observable
@MainActor
final class SessionRuntimeAtom {
    private(set) var statuses: [UUID: SessionRuntimeStatus] = [:]

    init() {}

    func setStatus(_ status: SessionRuntimeStatus, for paneId: UUID) {
        statuses[paneId] = status
    }

    func removeStatus(for paneId: UUID) {
        statuses.removeValue(forKey: paneId)
    }

    func status(for paneId: UUID) -> SessionRuntimeStatus? {
        statuses[paneId]
    }
}
```

- [ ] **Step 2: Update SessionRuntime to use `@Dependency`**

```swift
@MainActor
final class SessionRuntime {
    @ObservationIgnored @Dependency(\.sessionRuntimeAtom) var atom

    // ... existing init unchanged, remove statuses property ...
    // Replace all self.statuses[paneId] with atom.setStatus(...) / atom.status(for:)
}
```

Register the dependency key alongside the atom file:

```swift
struct SessionRuntimeAtomKey: DependencyKey {
    static let liveValue = SessionRuntimeAtom()
    static let testValue = SessionRuntimeAtom()
}
extension DependencyValues {
    var sessionRuntimeAtom: SessionRuntimeAtom {
        get { self[SessionRuntimeAtomKey.self] }
        set { self[SessionRuntimeAtomKey.self] = newValue }
    }
}
```

Tests get fresh atoms via `@Suite(.dependencies { $0.sessionRuntimeAtom = SessionRuntimeAtom() })`.

- [ ] **Step 3: Build, test, commit**

---

## Task 8: Move `SessionRuntime` + `ZmxBackend` to `Core/PaneRuntime/`

They're behavior/backends, not stores. `Core/Stores/` should only have persistence wrappers after this refactor.

- [ ] **Step 1: Move files**

```bash
git mv Sources/AgentStudio/Core/Stores/SessionRuntime.swift Sources/AgentStudio/Core/PaneRuntime/SessionRuntime.swift
git mv Sources/AgentStudio/Core/Stores/ZmxBackend.swift Sources/AgentStudio/Core/PaneRuntime/ZmxBackend.swift
```

- [ ] **Step 2: Build, test, commit**

---

## Task 9: Tests for store observation

Test that the observation-based persistence works correctly. Use injected clocks — no wall-clock sleeps.

**Files:**
- Modify: `Tests/AgentStudioTests/Core/Stores/WorkspaceStoreTests.swift`

- [ ] **Step 1: Test atom mutations trigger store save**

Tests use `withDependencies` to inject a fresh atom. The store resolves it via `@Dependency(\.workspaceAtom)`. `persistor` and `clock` are infrastructure — passed via constructor.

```swift
@Test
func test_atomMutation_triggersStoreSave() async {
    let persistor = WorkspacePersistor(workspacesDir: tempDir)
    let clock = TestPushClock()

    let store = withDependencies {
        $0.workspaceAtom = WorkspaceAtom()  // fresh, isolated
    } operation: {
        WorkspaceStore(
            persistor: persistor,
            persistDebounceDuration: .milliseconds(100),
            clock: clock
        )
    }
    store.restore()

    // Mutate the atom via the store's dependency-resolved reference
    let pane = store.atom.createPane(source: .floating(launchDirectory: nil, title: nil))
    let tab = Tab(paneId: pane.id)
    store.atom.appendTab(tab)

    // Wait for debounce, advance clock
    await clock.waitForPendingSleepCount(atLeast: 1)
    clock.advance(by: .milliseconds(150))

    // Verify save happened
    switch persistor.load() {
    case .loaded(let state):
        #expect(state.tabs.count == 1)
    case .missing, .corrupt:
        Issue.record("Expected loaded state after atom mutation")
    }
}
```

- [ ] **Step 2: Test restore does NOT trigger saves**

```swift
@Test
func test_restore_doesNotTriggerSave() async {
    let persistor = WorkspacePersistor(workspacesDir: tempDir)

    // Save initial state
    let store1 = withDependencies {
        $0.workspaceAtom = WorkspaceAtom()
    } operation: {
        WorkspaceStore(persistor: persistor)
    }
    let pane = store1.atom.createPane(source: .floating(launchDirectory: nil, title: nil))
    store1.atom.appendTab(Tab(paneId: pane.id))
    store1.flush()

    // Restore into fresh atom
    let clock = TestPushClock()
    let store2 = withDependencies {
        $0.workspaceAtom = WorkspaceAtom()
    } operation: {
        WorkspaceStore(
            persistor: persistor,
            persistDebounceDuration: .milliseconds(100),
            clock: clock
        )
    }
    store2.restore()

    // Restore should NOT schedule a save
    // Do NOT waitForPendingSleepCount — it hangs when correct (no pending sleep)
    #expect(store2.isDirty == false)
    #expect(clock.pendingSleepCount == 0)
}
```

- [ ] **Step 3: Test observation tracks ALL persisted properties**

```swift
@Test
func test_observation_tracksAllHydratedProperties() async {
    let persistor = WorkspacePersistor(workspacesDir: tempDir)
    let clock = TestPushClock()

    let store = withDependencies {
        $0.workspaceAtom = WorkspaceAtom()
    } operation: {
        WorkspaceStore(
            persistor: persistor,
            persistDebounceDuration: .milliseconds(100),
            clock: clock
        )
    }
    store.restore()

    // Mutate a property easy to forget in tracking
    store.atom.setSidebarWidth(999)

    await clock.waitForPendingSleepCount(atLeast: 1)
    clock.advance(by: .milliseconds(150))

    switch persistor.load() {
    case .loaded(let state):
        #expect(state.sidebarWidth == 999)
    case .missing, .corrupt:
        Issue.record("sidebarWidth mutation not tracked — observation tracking closure incomplete")
    }
}
```

- [ ] **Step 4: Test dependency isolation (no singleton leakage)**

```swift
@Suite(.dependencies {
    $0.managementModeAtom = ManagementModeAtom()
})
struct ManagementModeIsolationTests {
    @ObservationIgnored @Dependency(\.managementModeAtom) var atom

    @Test func testA_toggleDoesNotLeakToTestB() {
        atom.activate()
        #expect(atom.isActive == true)
    }

    @Test func testB_startsInactive() {
        // If isolation works, this test's atom is fresh — NOT affected by testA
        #expect(atom.isActive == false)
    }
}
```

- [ ] **Step 5: Test hydrate populates atom state**

```swift
@Test
func test_hydrate_setsAtomProperties() {
    let atom = WorkspaceAtom()
    let testRepos = [Repo(name: "test", path: URL(fileURLWithPath: "/tmp/test"))]

    atom.hydrate(
        workspaceId: UUID(),
        workspaceName: "Test",
        repos: testRepos,
        panes: [:],
        tabs: [],
        activeTabId: nil,
        sidebarWidth: 300,
        windowFrame: nil,
        watchedPaths: [],
        unavailableRepoIds: [],
        createdAt: Date(),
        updatedAt: Date()
    )

    #expect(atom.repos.count == 1)
    #expect(atom.repos.first?.name == "test")
    #expect(atom.workspaceName == "Test")
    #expect(atom.sidebarWidth == 300)
}
```

- [ ] **Step 4: Run tests, commit**

---

## Task 10: Update architecture docs and CLAUDE.md

- [ ] **Step 1: Update CLAUDE.md** — replace store table with atom table, add atom/store/derived pattern section

- [ ] **Step 2: Update `docs/architecture/directory_structure.md`** — add `Core/Atoms/`

- [ ] **Step 3: Update `docs/architecture/component_architecture.md`** — update component table

- [ ] **Step 4: Commit**

---

## Task 11: Final verification

- [ ] **Step 1: Run all tests**

Run: `SWIFT_BUILD_DIR=".build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8)" swift test --build-path "$SWIFT_BUILD_DIR" > /tmp/test-output.txt 2>&1 && echo "PASS" || echo "FAIL"`

- [ ] **Step 2: Run lint**

Run: `mise run lint > /tmp/lint-output.txt 2>&1 && echo "PASS" || echo "FAIL"`

- [ ] **Step 3: Verify `Core/Atoms/` contents**

```bash
ls Sources/AgentStudio/Core/Atoms/
```

Expected:
- `ManagementModeAtom.swift`
- `UIStateAtom.swift`
- `RepoCacheAtom.swift`
- `WorkspaceAtom.swift`
- `SessionRuntimeAtom.swift`
- `PaneDisplayDerived.swift`
- `DynamicViewDerived.swift`

- [ ] **Step 4: Verify `Core/Stores/` — persistence only**

```bash
ls Sources/AgentStudio/Core/Stores/
```

Expected:
- `WorkspaceStore.swift` (persistence wrapper)
- `RepoCacheStore.swift` (persistence wrapper)
- `UIStateStore.swift` (persistence wrapper)
- `WorkspacePersistor.swift` (shared I/O)

- [ ] **Step 5: Commit if formatting fixes needed**
