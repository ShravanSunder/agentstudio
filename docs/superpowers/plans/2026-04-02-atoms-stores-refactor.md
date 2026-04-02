# Atoms & Stores Refactor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Align the codebase to the Jotai-inspired state management model: atoms own state, stores observe atoms and handle persistence, derived computations are pure functions. Establish `Core/Atoms/` as the home for all reactive state.

**Architecture:** Split each fused "store+state" class into an atom (pure `@Observable` state + mutations) and a store (persistence wrapper that observes the atom via `@Observable` and saves/restores). Atoms have zero knowledge of persistence — stores compose atoms by holding references and observing changes. Transient state (zoom, minimize) lives in a separate atom that no store persists. Move derived computations (`PaneDisplayProjector`, `DynamicViewProjector`) into `Core/Atoms/` with `*Derived` naming.

**Tech Stack:** Swift 6.2, `@Observable`, `@MainActor`, `withObservationTracking`

---

## Mental Model

```
PRIMITIVE ATOMS (Core/Atoms/)
  @Observable, private(set), own state, mutation methods.
  No persistence. No callbacks. No event interception. No resource management.
  Atoms have ZERO knowledge of whether they are persisted.

  WorkspaceAtom          ← tabs, panes, repos, worktrees, layouts, mutations
  WorkspaceTransientAtom ← zoomedPaneId, minimizedPaneIds (not persisted)
  RepoCacheAtom          ← branch names, git status, PR counts
  UIStateAtom            ← expanded groups, colors, sidebar filter
  ManagementModeAtom     ← isActive: Bool
  SurfaceStateAtom       ← surface registry, counts
  SessionRuntimeAtom     ← runtime statuses per pane

DERIVED (Core/Atoms/)
  Read-only. Pure functions from atoms. No owned state.

  PaneDisplayDerived     ← reads WorkspaceAtom + RepoCacheAtom → display labels
  DynamicViewDerived     ← reads WorkspaceAtom → tab groupings

STORES (Core/Stores/)
  Persistence wrappers. Compose atoms by holding references.
  Observe atoms via @Observable — when atom state changes, schedule debounced save.
  No callbacks, no onMutate hooks. The store watches, the atom doesn't know.

  WorkspaceStore         ← observes WorkspaceAtom, saves → workspace.state.json
  RepoCacheStore         ← observes RepoCacheAtom, saves → workspace.cache.json
  UIStateStore           ← observes UIStateAtom, saves → workspace.ui.json

BEHAVIOR (stays in App/, Features/)
  AppKit event interception, resource lifecycle, C API bridges.
  Reads/writes atoms but doesn't own state.

  ManagementModeMonitor  ← keyboard interception, first responder mgmt
                           reads/writes ManagementModeAtom
  SurfaceManager         ← Ghostty C API lifecycle, health delegates
                           reads/writes SurfaceStateAtom
  SessionRuntime         ← backend coordination, health checks
                           reads/writes SessionRuntimeAtom

NOT TOUCHED (stays as-is)
  ZmxBackend             ← zmx session backend, not an atom or store
  WorkspacePersistor     ← shared file I/O mechanics, used by stores
  AppLifecycleStore      ← already in-memory only, already in App/
  WindowLifecycleStore   ← already in-memory only, already in App/
```

### How stores observe atoms (no callbacks)

```swift
@MainActor
final class WorkspaceStore {
    let atom: WorkspaceAtom        // the atom this store persists
    private let persistor: WorkspacePersistor

    func startObserving() {
        // withObservationTracking re-registers after each change
        func observe() {
            withObservationTracking {
                // Touch all persisted properties so we're notified when any change
                _ = atom.repos
                _ = atom.tabs
                _ = atom.panes
                _ = atom.activeTabId
                // ... all persisted properties
            } onChange: { [weak self] in
                Task { @MainActor [weak self] in
                    self?.scheduleDebouncedSave()
                    observe()  // re-register
                }
            }
        }
        observe()
    }
}
```

The atom mutates freely. The store watches. No coupling.

### Composability

```
WorkspaceAtom ──── observed by ──── WorkspaceStore ──── saves to .state.json
RepoCacheAtom ──── observed by ──── RepoCacheStore ──── saves to .cache.json
UIStateAtom ────── observed by ──── UIStateStore ────── saves to .ui.json

WorkspaceTransientAtom ──── no store ──── in-memory only
ManagementModeAtom ──────── no store ──── in-memory only
SurfaceStateAtom ────────── no store ──── in-memory only
SessionRuntimeAtom ──────── no store ──── in-memory only
```

A store picks which atoms to persist by holding references. Atoms it doesn't reference are in-memory only. No configuration, no callbacks, no flags.

---

## Scope & Exclusions

### In scope
- Split `WorkspaceStore` → `WorkspaceAtom` + `WorkspaceTransientAtom` + `WorkspaceStore`
- Rename `WorkspaceRepoCache` → `RepoCacheAtom`, `WorkspaceUIStore` → `UIStateAtom`
- Extract atoms from `ManagementModeMonitor`, `SurfaceManager`, `SessionRuntime`
- Rename `PaneDisplayProjector` → `PaneDisplayDerived`, `DynamicViewProjector` → `DynamicViewDerived`
- Update CLAUDE.md and architecture docs

### NOT in scope — do not touch
- `ZmxBackend` — zmx session backend, not an atom or store
- `WorkspacePersistor` — shared I/O mechanics, used by stores unchanged
- `AppLifecycleStore` — already in-memory only, already in `App/Lifecycle/`
- `WindowLifecycleStore` — already in-memory only, already in `App/Lifecycle/`
- Event bus projectors (`GitWorkingDirectoryProjector`, `FilesystemActor`, `ForgeActor`) — these are real event subscribers, not derived atoms

---

## Scope & Order

**Phase 1:** Create `Core/Atoms/`, establish pattern with simplest atoms (Tasks 1-3).
**Phase 2:** Rename derived computations — smaller diffs before big split (Task 4).
**Phase 3:** Split `WorkspaceStore` — the big task (Task 5).
**Phase 4:** Extract remaining atoms from behavior classes (Tasks 6-7).
**Phase 5:** Tests for store observation + persistence (Task 8).
**Phase 6:** Update architecture docs (Task 9).
**Phase 7:** Final verification (Task 10).

---

## File Structure

### New files

| File | What it is |
|------|-----------|
| `Core/Atoms/ManagementModeAtom.swift` | `isActive: Bool`, `toggle()`, `deactivate()` |
| `Core/Atoms/UIStateAtom.swift` | Renamed from `WorkspaceUIStore` |
| `Core/Atoms/RepoCacheAtom.swift` | Renamed from `WorkspaceRepoCache` |
| `Core/Atoms/WorkspaceAtom.swift` | Persisted state + mutations from `WorkspaceStore` |
| `Core/Atoms/WorkspaceTransientAtom.swift` | Transient state: zoom, minimize |
| `Core/Atoms/SurfaceStateAtom.swift` | Surface registry + counts from `SurfaceManager` |
| `Core/Atoms/SessionRuntimeAtom.swift` | Runtime statuses from `SessionRuntime` |
| `Core/Atoms/PaneDisplayDerived.swift` | Renamed from `PaneDisplayProjector` |
| `Core/Atoms/DynamicViewDerived.swift` | Renamed from `DynamicViewProjector` |

### Modified files

| File | Change |
|------|--------|
| `Core/Stores/WorkspaceStore.swift` | Becomes persistence wrapper — observes `WorkspaceAtom`, saves/restores |
| `App/ManagementModeMonitor.swift` | Behavior only — state moves to `ManagementModeAtom` |
| `Features/Terminal/Ghostty/SurfaceManager.swift` | Behavior only — state moves to `SurfaceStateAtom` |
| `Core/Stores/SessionRuntime.swift` | Behavior only — statuses move to `SessionRuntimeAtom` |
| `CLAUDE.md` | Update architecture section |
| `docs/architecture/component_architecture.md` | Update component table |
| `docs/architecture/directory_structure.md` | Add `Core/Atoms/` section |
| ~72 source files | Update type references |
| ~41 test files | Update type references |

### Moved files

| File | From | To | Why |
|------|------|----|-----|
| `SessionRuntime.swift` | `Core/Stores/` | `Core/PaneRuntime/` | Behavior, not a store — belongs with runtime contracts |
| `ZmxBackend.swift` | `Core/Stores/` | `Core/PaneRuntime/` | Backend, not a store — belongs with runtime contracts |

### Unchanged files (explicit)

| File | Why unchanged |
|------|--------------|
| `Core/Stores/WorkspacePersistor.swift` | Shared I/O — stores use it, not refactored |

---

## Task 1: Create `Core/Atoms/` folder and extract `ManagementModeAtom`

Start with the simplest atom — `ManagementModeMonitor` has exactly one `Bool` of state. This establishes the pattern.

**Files:**
- Create: `Sources/AgentStudio/Core/Atoms/ManagementModeAtom.swift`
- Modify: `Sources/AgentStudio/App/ManagementModeMonitor.swift`

- [ ] **Step 1: Create the atom**

```swift
import Observation

/// Atom: management mode state.
/// Pure state — no keyboard interception, no first responder management.
/// Those behaviors live in ManagementModeMonitor which reads/writes this atom.
@Observable
@MainActor
final class ManagementModeAtom {
    static let shared = ManagementModeAtom()

    private(set) var isActive: Bool = false

    private init() {}

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

- [ ] **Step 2: Update `ManagementModeMonitor` to use the atom**

In `Sources/AgentStudio/App/ManagementModeMonitor.swift`, remove `isActive` state and delegate to the atom:

```swift
@MainActor
@Observable
final class ManagementModeMonitor {
    static let shared = ManagementModeMonitor()

    private let atom = ManagementModeAtom.shared

    /// Whether management mode is currently active — delegates to atom.
    var isActive: Bool { atom.isActive }

    private var keyboardMonitor: Any?

    private init() {
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

    // ... keyboard monitoring and first responder code unchanged ...
}
```

All 18 files referencing `ManagementModeMonitor.shared.isActive` continue to work — the public API is identical.

- [ ] **Step 3: Build and run ManagementMode tests**

Run: `SWIFT_BUILD_DIR=".build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8)" swift test --build-path "$SWIFT_BUILD_DIR" --filter "ManagementMode" > /tmp/test-output.txt 2>&1 && echo "PASS" || echo "FAIL"`

Expected: PASS

- [ ] **Step 4: Commit**

```bash
git add Sources/AgentStudio/Core/Atoms/ManagementModeAtom.swift Sources/AgentStudio/App/ManagementModeMonitor.swift
git commit -m "refactor: extract ManagementModeAtom from ManagementModeMonitor"
```

---

## Task 2: Rename `WorkspaceUIStore` → `UIStateAtom`

47 lines. Already mostly a pure atom — just rename and move.

**Files:**
- Rename: `Sources/AgentStudio/Core/Stores/WorkspaceUIStore.swift` → `Sources/AgentStudio/Core/Atoms/UIStateAtom.swift`
- Modify: all files referencing `WorkspaceUIStore` (~5 source files)

- [ ] **Step 1: Rename file and class**

```bash
git mv Sources/AgentStudio/Core/Stores/WorkspaceUIStore.swift Sources/AgentStudio/Core/Atoms/UIStateAtom.swift
```

Rename class in the file: `class WorkspaceUIStore` → `class UIStateAtom`.

Add doc comment:
```swift
/// Atom: UI preferences state (expanded groups, colors, sidebar filter).
/// In-memory only — no persistence store wraps this atom yet.
/// Future: UIStateStore will observe and persist to workspace.ui.json.
```

- [ ] **Step 2: Update all references**

```bash
rg -l "WorkspaceUIStore" Sources/ Tests/
```

Find and replace `WorkspaceUIStore` → `UIStateAtom` in each file.

- [ ] **Step 3: Build and test**

Run: `SWIFT_BUILD_DIR=".build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8)" swift build --build-path "$SWIFT_BUILD_DIR" > /tmp/build-output.txt 2>&1 && echo "PASS" || echo "FAIL"`

Expected: PASS

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "refactor: rename WorkspaceUIStore → UIStateAtom, move to Core/Atoms/"
```

---

## Task 3: Rename `WorkspaceRepoCache` → `RepoCacheAtom`

60 lines. Same pattern as Task 2.

**Files:**
- Rename: `Sources/AgentStudio/Core/Stores/WorkspaceRepoCache.swift` → `Sources/AgentStudio/Core/Atoms/RepoCacheAtom.swift`
- Modify: ~20 source files + test files

- [ ] **Step 1: Rename file and class**

```bash
git mv Sources/AgentStudio/Core/Stores/WorkspaceRepoCache.swift Sources/AgentStudio/Core/Atoms/RepoCacheAtom.swift
```

Rename class: `class WorkspaceRepoCache` → `class RepoCacheAtom`.

Add doc comment:
```swift
/// Atom: repo enrichment cache (branches, git status, PR counts).
/// In-memory only — no persistence store wraps this atom yet.
/// Future: RepoCacheStore will observe and persist to workspace.cache.json.
```

- [ ] **Step 2: Update all references**

```bash
rg -l "WorkspaceRepoCache" Sources/ Tests/
```

~20 files. Find and replace `WorkspaceRepoCache` → `RepoCacheAtom`.

**Important call site:** `CommandBarDataSource.items()` has default parameter `repoCache: WorkspaceRepoCache = WorkspaceRepoCache()`. Update to `repoCache: RepoCacheAtom = RepoCacheAtom()`.

- [ ] **Step 3: Build and test**

Run: `SWIFT_BUILD_DIR=".build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8)" swift build --build-path "$SWIFT_BUILD_DIR" > /tmp/build-output.txt 2>&1 && echo "PASS" || echo "FAIL"`

Expected: PASS

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "refactor: rename WorkspaceRepoCache → RepoCacheAtom, move to Core/Atoms/"
```

---

## Task 4: Rename derived computations → `*Derived` in `Core/Atoms/`

Smaller diffs before the big WorkspaceStore split.

**Files:**
- Rename: `Core/Views/PaneDisplayProjector.swift` → `Core/Atoms/PaneDisplayDerived.swift`
- Rename: `Core/Stores/DynamicViewProjector.swift` → `Core/Atoms/DynamicViewDerived.swift`
- Modify: ~14 files referencing these types

- [ ] **Step 1: Rename `PaneDisplayProjector` → `PaneDisplayDerived`**

```bash
git mv Sources/AgentStudio/Core/Views/PaneDisplayProjector.swift Sources/AgentStudio/Core/Atoms/PaneDisplayDerived.swift
```

Rename `enum PaneDisplayProjector` → `enum PaneDisplayDerived` in the file.

Update doc comment: "Derived: projects pane display labels from WorkspaceAtom + RepoCacheAtom. Not an event-bus projector."

Find and replace in all files (~11 source files, ~3 test files):
```bash
rg -l "PaneDisplayProjector" Sources/ Tests/
```

- [ ] **Step 2: Rename `DynamicViewProjector` → `DynamicViewDerived`**

```bash
git mv Sources/AgentStudio/Core/Stores/DynamicViewProjector.swift Sources/AgentStudio/Core/Atoms/DynamicViewDerived.swift
```

Rename `enum DynamicViewProjector` → `enum DynamicViewDerived`.

```bash
rg -l "DynamicViewProjector" Sources/ Tests/
```

~3 files (mostly tests — unused in production code).

- [ ] **Step 3: Build and test**

Run: `SWIFT_BUILD_DIR=".build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8)" swift build --build-path "$SWIFT_BUILD_DIR" > /tmp/build-output.txt 2>&1 && echo "PASS" || echo "FAIL"`

Expected: PASS

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "refactor: rename PaneDisplayProjector → PaneDisplayDerived, DynamicViewProjector → DynamicViewDerived, move to Core/Atoms/"
```

---

## Task 5: Split `WorkspaceStore` → `WorkspaceAtom` + `WorkspaceTransientAtom` + `WorkspaceStore`

The biggest task. `WorkspaceStore` is 1981 lines. Split into:
- `WorkspaceAtom` (~1500 lines): persisted state + mutations + queries + undo
- `WorkspaceTransientAtom` (~60 lines): zoom and minimize state
- `WorkspaceStore` (~400 lines): persistence wrapper that observes `WorkspaceAtom`

### What goes where

**WorkspaceAtom** (all persisted state + mutations):
- Properties: `repos`, `watchedPaths`, `panes`, `tabs`, `activeTabId`, `workspaceId`, `workspaceName`, `sidebarWidth`, `windowFrame`, `createdAt`, `updatedAt`, `unavailableRepoIds`
- All query methods: `pane(_:)`, `tab(_:)`, `repo(_:)`, `worktree(_:)`, etc.
- All mutation methods that currently call `markDirty()`: `createPane`, `removePane`, `appendTab`, `removeTab`, `insertPane`, `removePaneFromLayout`, etc. (~49 methods)
- Undo methods: `snapshotForClose`, `restoreFromSnapshot`, etc.
- Private helpers: `findTabIndex`, `canonicalRepos`, `pruneInvalidPanes`, `validateTabInvariants`
- Remove ALL `markDirty()` calls — the atom doesn't know about persistence
- Remove `persistor`, `isDirty`, `debouncedSaveTask`, `clock` properties
- Remove `restore()`, `markDirty()`, `flush()`, `persistNow()`, `prePersistHook`
- `init()` becomes parameterless — no persistor

**WorkspaceTransientAtom** (transient state, NOT persisted):
- `zoomedPaneId` per tab — currently `Tab.zoomedPaneId`
- `minimizedPaneIds` per tab — currently `Tab.minimizedPaneIds`
- Methods: `toggleZoom`, `minimizePane`, `expandPane` (the three methods that say "Do NOT markDirty()")

Note: zoom and minimize are currently stored ON the `Tab` struct. Extracting them to a separate atom means either:
- (a) Moving them off `Tab` into a dictionary keyed by tabId
- (b) Keeping them on `Tab` but accepting that `WorkspaceAtom` holds some transient fields

**Decision: option (b) for now.** Keep `zoomedPaneId` and `minimizedPaneIds` on `Tab`. The `WorkspaceStore` simply doesn't persist those fields (they're already excluded from `PersistableState` encoding). Extracting them to a separate atom is a future refinement. This avoids touching the `Tab` model and all its consumers.

**WorkspaceStore** (persistence only):
- Properties: `atom: WorkspaceAtom`, `persistor: WorkspacePersistor`, `isDirty`, `debouncedSaveTask`, `clock`
- `restore()` — loads from disk, writes into `atom`'s properties, then starts observing
- `startObserving()` — uses `withObservationTracking` to watch atom changes, schedules saves
- `scheduleDebouncedSave()` — debounced persist logic (existing `markDirty` body)
- `flush()` — immediate save
- `persistNow()` — reads from `atom`, writes via `persistor`
- `prePersistHook` — stays here

**Files:**
- Create: `Sources/AgentStudio/Core/Atoms/WorkspaceAtom.swift`
- Modify: `Sources/AgentStudio/Core/Stores/WorkspaceStore.swift`
- Modify: ~31 source files, ~41 test files

- [ ] **Step 1: Create `WorkspaceAtom.swift`**

1. Copy `Sources/AgentStudio/Core/Stores/WorkspaceStore.swift` to `Sources/AgentStudio/Core/Atoms/WorkspaceAtom.swift`
2. Rename class: `WorkspaceStore` → `WorkspaceAtom`
3. Delete the MARK: - Persistence section entirely (lines ~1436-1600):
   - Delete properties: `persistor`, `persistDebounceDuration`, `clock`, `debouncedSaveTask`, `isDirty`, `prePersistHook`
   - Delete methods: `restore()`, `markDirty()`, `flush()`, `persistNow()`, `tabPersistenceSummary()`, `layoutRatioSummary()`
4. Delete every `markDirty()` call from mutation methods — there are 49 of them. The three methods with `// Do NOT markDirty()` already don't call it, so they need no change.
5. Simplify `init()`:
   ```swift
   init() {}
   ```
6. Add doc comment:
   ```swift
   /// Atom: canonical workspace state — tabs, panes, repos, worktrees, layouts.
   /// Pure @Observable state + mutations. No persistence knowledge.
   /// Persisted by WorkspaceStore which observes this atom.
   ```

- [ ] **Step 2: Rewrite `WorkspaceStore.swift` as persistence wrapper**

Replace the entire contents of `Sources/AgentStudio/Core/Stores/WorkspaceStore.swift`:

```swift
import Foundation
import os.log

private let storeLogger = Logger(subsystem: "com.agentstudio", category: "WorkspaceStore")

/// Persistence wrapper for WorkspaceAtom.
/// Observes the atom via @Observable — when persisted state changes,
/// schedules a debounced save. The atom has zero knowledge of persistence.
@MainActor
final class WorkspaceStore {
    let atom: WorkspaceAtom
    private let persistor: WorkspacePersistor
    private let persistDebounceDuration: Duration
    private let clock: any Clock<Duration>
    private var debouncedSaveTask: Task<Void, Never>?
    private(set) var isDirty: Bool = false

    /// Hook called before each persist — used to sync runtime state
    var prePersistHook: (() -> Void)?

    init(
        atom: WorkspaceAtom = WorkspaceAtom(),
        persistor: WorkspacePersistor = WorkspacePersistor(),
        persistDebounceDuration: Duration = .milliseconds(500),
        clock: any Clock<Duration> = ContinuousClock()
    ) {
        self.atom = atom
        self.persistor = persistor
        self.persistDebounceDuration = persistDebounceDuration
        self.clock = clock
    }

    // MARK: - Restore

    func restore() {
        persistor.ensureDirectory()
        switch persistor.load() {
        case .loaded(let state):
            atom.workspaceId = state.id
            atom.workspaceName = state.name
            // ... restore all atom properties from PersistableState ...
            // Copy the existing restore() logic from current WorkspaceStore,
            // replacing every `self.property` with `atom.property`
            storeLogger.info("Restored workspace '\(state.name)'")
        case .corrupt(let error):
            storeLogger.error("Workspace decode failed — starting fresh: \(error)")
        case .missing:
            storeLogger.info("No workspace files — first launch")
        }

        // Prune invalid panes, validate tab invariants
        // ... copy existing post-restore validation logic ...

        // Start observing atom changes AFTER restore completes
        startObserving()
    }

    // MARK: - Observation

    private func startObserving() {
        func observe() {
            withObservationTracking {
                // Touch all persisted properties to register for change notifications
                _ = atom.repos
                _ = atom.tabs
                _ = atom.panes
                _ = atom.activeTabId
                _ = atom.watchedPaths
                _ = atom.workspaceName
                _ = atom.sidebarWidth
                _ = atom.windowFrame
                _ = atom.unavailableRepoIds
            } onChange: { [weak self] in
                Task { @MainActor [weak self] in
                    self?.scheduleDebouncedSave()
                    observe()  // re-register for next change
                }
            }
        }
        observe()
    }

    // MARK: - Persistence

    private func scheduleDebouncedSave() {
        if !isDirty {
            isDirty = true
            ProcessInfo.processInfo.disableSuddenTermination()
        }
        debouncedSaveTask?.cancel()
        debouncedSaveTask = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await self.clock.sleep(for: self.persistDebounceDuration)
            guard !Task.isCancelled else { return }
            self.persistNow()
        }
    }

    @discardableResult
    func flush() -> Bool {
        debouncedSaveTask?.cancel()
        debouncedSaveTask = nil
        return persistNow()
    }

    @discardableResult
    private func persistNow() -> Bool {
        prePersistHook?()
        persistor.ensureDirectory()
        atom.updatedAt = Date()
        // Build PersistableState from atom properties
        // ... copy existing persistNow() logic, reading from atom instead of self ...
        // Call persistor.save(state)
        if isDirty {
            isDirty = false
            ProcessInfo.processInfo.enableSuddenTermination()
        }
        return true
    }
}
```

**Note on `restore()` and `persistNow()`:** These methods contain significant logic (pruning, validation, serialization). The implementing agent must:
1. Read the current `restore()` method (lines 1438-1507 of current WorkspaceStore)
2. Copy it into the new `WorkspaceStore.restore()`, replacing every `self.repos` with `atom.repos`, `self.tabs` with `atom.tabs`, etc.
3. Same for `persistNow()` (lines 1541-1600) — read from `atom.*` instead of `self.*`

The `pruneInvalidPanes` and `validateTabInvariants` helper methods stay on `WorkspaceAtom` (they mutate state). `restore()` calls them: `atom.pruneInvalidPanes(...)`, `atom.validateTabInvariants()`. These need to become `internal` (not `private`) on the atom.

- [ ] **Step 3: Update all call sites**

Every file that uses `WorkspaceStore` for state access needs `.atom`:
- `store.tabs` → `store.atom.tabs`
- `store.pane(id)` → `store.atom.pane(id)`
- `store.setActiveTab(id)` → `store.atom.setActiveTab(id)`
- `store.restore()` → stays as `store.restore()` (persistence method)
- `store.flush()` → stays as `store.flush()` (persistence method)

Find all call sites:
```bash
rg -l "WorkspaceStore" Sources/ Tests/
```

**~31 source files + ~41 test files.** This is mechanical: add `.atom` to every state/mutation access.

**Test strategy:** Most tests only test state mutations — they should eventually use `WorkspaceAtom` directly. For this task, use the `.atom` accessor as the mechanical first pass. Tests that test persistence (flush/restore/markDirty) stay using `WorkspaceStore`.

- [ ] **Step 4: Build incrementally**

Run: `SWIFT_BUILD_DIR=".build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8)" swift build --build-path "$SWIFT_BUILD_DIR" > /tmp/build-output.txt 2>&1 && echo "PASS" || echo "FAIL"`

Fix compilation errors iteratively. The pattern is mechanical but there are 72+ files.

- [ ] **Step 5: Run full test suite**

Run: `SWIFT_BUILD_DIR=".build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8)" swift test --build-path "$SWIFT_BUILD_DIR" > /tmp/test-output.txt 2>&1 && echo "PASS" || echo "FAIL"`

Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "refactor: split WorkspaceStore into WorkspaceAtom (state) + WorkspaceStore (persistence)"
```

---

## Task 6: Extract `SurfaceStateAtom` from `SurfaceManager`

`SurfaceManager` is 942 lines. Before writing code, read the file to identify exactly which properties are observable state vs behavior infrastructure.

**Files:**
- Create: `Sources/AgentStudio/Core/Atoms/SurfaceStateAtom.swift`
- Modify: `Sources/AgentStudio/Features/Terminal/Ghostty/SurfaceManager.swift`

- [ ] **Step 1: Read `SurfaceManager.swift` and identify atom state**

Read `Sources/AgentStudio/Features/Terminal/Ghostty/SurfaceManager.swift` in full. Find every `private(set) var` property — these are the atom candidates. Expected to find:
- `activeSurfaceCount: Int`
- `hiddenSurfaceCount: Int`
- Possibly a surface registry dictionary

Also identify: which properties do views observe? Those are definitely atom state.

- [ ] **Step 2: Create the atom with the identified properties**

Create `Sources/AgentStudio/Core/Atoms/SurfaceStateAtom.swift` with the exact properties found in Step 1. Add mutation methods for each.

Pattern:
```swift
@Observable
@MainActor
final class SurfaceStateAtom {
    static let shared = SurfaceStateAtom()

    // ... exact properties from Step 1 ...

    private init() {}

    // ... mutation methods ...
}
```

- [ ] **Step 3: Update `SurfaceManager` to delegate state to atom**

For each property moved: replace `private(set) var X` with a computed property `var X { atom.X }` that delegates to the atom. Update mutation sites to call atom methods.

- [ ] **Step 4: Build and test**

Run: `SWIFT_BUILD_DIR=".build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8)" swift build --build-path "$SWIFT_BUILD_DIR" > /tmp/build-output.txt 2>&1 && echo "PASS" || echo "FAIL"`

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/AgentStudio/Core/Atoms/SurfaceStateAtom.swift Sources/AgentStudio/Features/Terminal/Ghostty/SurfaceManager.swift
git commit -m "refactor: extract SurfaceStateAtom from SurfaceManager"
```

---

## Task 7: Extract `SessionRuntimeAtom` from `SessionRuntime`

`SessionRuntime` is 238 lines. The atom is the `statuses` dictionary.

**Files:**
- Create: `Sources/AgentStudio/Core/Atoms/SessionRuntimeAtom.swift`
- Modify: `Sources/AgentStudio/Core/Stores/SessionRuntime.swift`

- [ ] **Step 1: Create the atom**

```swift
import Observation

/// Atom: runtime status per pane.
/// Behavior (backend coordination, health checks) lives in SessionRuntime.
@Observable
@MainActor
final class SessionRuntimeAtom {
    static let shared = SessionRuntimeAtom()

    private(set) var statuses: [UUID: SessionRuntimeStatus] = [:]

    private init() {}

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

- [ ] **Step 2: Update `SessionRuntime` to delegate**

Replace `private(set) var statuses` with reads/writes to `SessionRuntimeAtom.shared`.

- [ ] **Step 3: Move `SessionRuntime` and `ZmxBackend` out of `Core/Stores/`**

They're behavior/backends, not persistence stores. Move to `Core/PaneRuntime/` where runtime contracts already live:

```bash
git mv Sources/AgentStudio/Core/Stores/SessionRuntime.swift Sources/AgentStudio/Core/PaneRuntime/SessionRuntime.swift
git mv Sources/AgentStudio/Core/Stores/ZmxBackend.swift Sources/AgentStudio/Core/PaneRuntime/ZmxBackend.swift
```

Update any imports if needed (SPM single-module — no import changes required).

- [ ] **Step 4: Build and test**

Run: `SWIFT_BUILD_DIR=".build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8)" swift build --build-path "$SWIFT_BUILD_DIR" > /tmp/build-output.txt 2>&1 && echo "PASS" || echo "FAIL"`

Expected: PASS

- [ ] **Step 4: Commit**

```bash
git add Sources/AgentStudio/Core/Atoms/SessionRuntimeAtom.swift Sources/AgentStudio/Core/Stores/SessionRuntime.swift
git commit -m "refactor: extract SessionRuntimeAtom from SessionRuntime"
```

---

## Task 8: Add tests for store observation and persistence wiring

The store's observation-based persistence is new behavior that needs tests.

**Files:**
- Modify: `Tests/AgentStudioTests/Core/Stores/WorkspaceStoreTests.swift`

- [ ] **Step 1: Write test that atom mutations trigger store saves**

```swift
@Test
func test_atomMutation_triggersStoreObservation() async {
    let persistor = WorkspacePersistor(workspacesDir: tempDir)
    let atom = WorkspaceAtom()
    let store = WorkspaceStore(
        atom: atom,
        persistor: persistor,
        persistDebounceDuration: .milliseconds(10),
        clock: ContinuousClock()
    )
    store.restore()  // starts observation

    // Mutate the atom directly
    atom.appendTab(Tab(paneId: UUID()))

    // Wait for debounce
    try? await Task.sleep(for: .milliseconds(50))

    // Store should have flushed
    #expect(store.isDirty == false)
    // Verify file was written
    #expect(persistor.load() != .missing)
}
```

- [ ] **Step 2: Write test that transient mutations do NOT trigger saves**

```swift
@Test
func test_transientMutation_doesNotTriggerSave() async {
    let persistor = WorkspacePersistor(workspacesDir: tempDir)
    let atom = WorkspaceAtom()
    let store = WorkspaceStore(
        atom: atom,
        persistor: persistor,
        persistDebounceDuration: .milliseconds(10),
        clock: ContinuousClock()
    )
    store.restore()

    let pane = atom.createPane(source: .floating(launchDirectory: nil, title: nil))
    let tab = Tab(paneId: pane.id)
    atom.appendTab(tab)
    store.flush()  // save the initial state

    // Transient mutation: toggle zoom
    atom.toggleZoom(paneId: pane.id, inTab: tab.id)

    // Wait — should NOT trigger save since zoom is not observed
    try? await Task.sleep(for: .milliseconds(50))

    // isDirty should still be false (no persisted property changed)
    #expect(store.isDirty == false)
}
```

- [ ] **Step 3: Write test that restore does NOT trigger observation saves**

```swift
@Test
func test_restore_doesNotTriggerObservationSaves() async {
    let persistor = WorkspacePersistor(workspacesDir: tempDir)

    // Create initial state and save it
    let atom1 = WorkspaceAtom()
    let store1 = WorkspaceStore(atom: atom1, persistor: persistor)
    let pane = atom1.createPane(source: .floating(launchDirectory: nil, title: nil))
    atom1.appendTab(Tab(paneId: pane.id))
    store1.flush()

    // Create new store and restore — should NOT trigger a save
    let atom2 = WorkspaceAtom()
    let store2 = WorkspaceStore(
        atom: atom2,
        persistor: persistor,
        persistDebounceDuration: .milliseconds(10),
        clock: ContinuousClock()
    )
    store2.restore()

    // Wait for any accidental debounced save
    try? await Task.sleep(for: .milliseconds(50))

    // Observation starts AFTER restore — no dirty flag should be set
    #expect(store2.isDirty == false)
}
```

- [ ] **Step 4: Run tests**

Run: `SWIFT_BUILD_DIR=".build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8)" swift test --build-path "$SWIFT_BUILD_DIR" --filter "WorkspaceStore" > /tmp/test-output.txt 2>&1 && echo "PASS" || echo "FAIL"`

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Tests/AgentStudioTests/Core/Stores/WorkspaceStoreTests.swift
git commit -m "test: add store observation and persistence wiring tests"
```

---

## Task 9: Update architecture docs and CLAUDE.md

**Files:**
- Modify: `CLAUDE.md`
- Modify: `docs/architecture/directory_structure.md`
- Modify: `docs/architecture/component_architecture.md`

- [ ] **Step 1: Update CLAUDE.md**

In "Architecture at a Glance", replace the store table:

```markdown
| Atom | Owns | Persisted by |
|------|------|-------------|
| `WorkspaceAtom` | repos, worktrees, tabs, panes, layouts | `WorkspaceStore` → `workspace.state.json` |
| `RepoCacheAtom` | repo enrichment, branches, git status, PR counts | (future: `RepoCacheStore` → `workspace.cache.json`) |
| `UIStateAtom` | expanded groups, colors, filter | (future: `UIStateStore` → `workspace.ui.json`) |
| `ManagementModeAtom` | management mode toggle | in-memory |
| `SurfaceStateAtom` | Ghostty surface registry, counts | in-memory |
| `SessionRuntimeAtom` | runtime status per pane | in-memory |
```

Add the Atom / Store / Derived pattern section:

```markdown
### Atom / Store / Derived Pattern

The codebase follows a Jotai-inspired state model:

- **Atoms** (`Core/Atoms/`, `*Atom` suffix): `@Observable` state containers with `private(set)` properties and mutation methods. Atoms own state but have no persistence, no event handling, no resource management. Atoms have zero knowledge of whether they are persisted.
- **Derived** (`Core/Atoms/`, `*Derived` suffix): Read-only computations from atoms. Pure functions, no owned state. Recompute on access via SwiftUI observation.
- **Stores** (`Core/Stores/`, `*Store` suffix): Persistence wrappers that observe atoms via `@Observable` and save/restore to disk. Stores compose atoms by holding references — atoms they don't reference are in-memory only.
- **Behavior** (`App/`, `Features/`): AppKit event interception, C API bridges, resource managers. Read/write atoms but don't own state.

The rule: **atoms own state. Everything else reads/writes atoms.**
```

- [ ] **Step 2: Update directory_structure.md and component_architecture.md**

Add `Core/Atoms/` with component placement rationale. Update component table.

- [ ] **Step 3: Commit**

```bash
git add CLAUDE.md docs/architecture/directory_structure.md docs/architecture/component_architecture.md
git commit -m "docs: document atom/store/derived pattern in architecture"
```

---

## Task 10: Run full test suite, lint, and verify

- [ ] **Step 1: Run all tests**

Run: `SWIFT_BUILD_DIR=".build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8)" swift test --build-path "$SWIFT_BUILD_DIR" > /tmp/test-output.txt 2>&1 && echo "PASS" || echo "FAIL"`

Expected: PASS

- [ ] **Step 2: Run lint**

Run: `mise run lint > /tmp/lint-output.txt 2>&1 && echo "PASS" || echo "FAIL"`

Expected: PASS

- [ ] **Step 3: Verify `Core/Atoms/` contents**

```bash
ls Sources/AgentStudio/Core/Atoms/
```

Expected:
- `ManagementModeAtom.swift`
- `UIStateAtom.swift`
- `RepoCacheAtom.swift`
- `WorkspaceAtom.swift`
- `SurfaceStateAtom.swift`
- `SessionRuntimeAtom.swift`
- `PaneDisplayDerived.swift`
- `DynamicViewDerived.swift`

- [ ] **Step 4: Verify `Core/Stores/` — persistence only**

```bash
ls Sources/AgentStudio/Core/Stores/
```

Expected (only persistence):
- `WorkspaceStore.swift` (persistence wrapper)
- `WorkspacePersistor.swift` (shared I/O)

- [ ] **Step 5: Commit if formatting fixes needed**

```bash
git add -A
git commit -m "chore: formatting fixes from lint"
```
