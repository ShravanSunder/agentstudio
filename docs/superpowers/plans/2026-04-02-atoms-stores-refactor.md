# Atoms & Stores Refactor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Align the codebase to the Jotai-inspired state management model: atoms own state, stores handle persistence, derived computations are pure functions. Establish `Core/Atoms/` as the home for all reactive state.

**Architecture:** Split each fused "store+state" class into an atom (pure `@Observable` state + mutations) and a store (persistence wrapper that saves/restores the atom). Move derived computations (`PaneDisplayProjector`, `DynamicViewProjector`) into `Core/Atoms/` with `*Derived` naming. Extract the atom portion of `ManagementModeMonitor` and `SurfaceManager` from their behavior-heavy containers. Update architecture docs and CLAUDE.md to document the atom/store/derived pattern.

**Tech Stack:** Swift 6.2, `@Observable`, `@MainActor`

---

## Mental Model

```
PRIMITIVE ATOMS (Core/Atoms/)
  @Observable, private(set), own state, mutation methods.
  No persistence. No event interception. No resource management.

  WorkspaceAtom        ← tabs, panes, repos, worktrees, layouts, mutations
  RepoCacheAtom        ← branch names, git status, PR counts
  UIStateAtom          ← expanded groups, colors, sidebar filter
  ManagementModeAtom   ← isActive: Bool
  SurfaceStateAtom     ← surface registry, counts
  SessionRuntimeAtom   ← runtime statuses per pane

DERIVED (Core/Atoms/)
  Read-only. Pure functions from atoms. No owned state.

  PaneDisplayDerived   ← reads WorkspaceAtom + RepoCacheAtom → display labels
  DynamicViewDerived   ← reads WorkspaceAtom → tab groupings
  WorkspaceFocusDerived ← reads WorkspaceAtom → Set<FocusRequirement>  (future plan)

STORES (Core/Stores/)
  Persistence wrappers. Take an atom, save it, restore it.
  Not @Observable — the atom is what views observe.

  WorkspaceStore       ← saves/restores WorkspaceAtom → workspace.state.json
  RepoCacheStore       ← saves/restores RepoCacheAtom → workspace.cache.json
  UIStateStore         ← saves/restores UIStateAtom → workspace.ui.json

BEHAVIOR (stays in App/, Features/)
  AppKit event interception, resource lifecycle, C API bridges.
  Reads/writes atoms but doesn't own state.

  ManagementModeMonitor ← keyboard interception, first responder mgmt
                          reads/writes ManagementModeAtom
  SurfaceManager        ← Ghostty C API lifecycle, health delegates
                          reads/writes SurfaceStateAtom
  SessionRuntime        ← backend coordination, health checks
                          reads/writes SessionRuntimeAtom
```

---

## Scope & Order

This plan is ordered to minimize breakage. Each task produces a compiling, passing codebase.

**Phase 1:** Create `Core/Atoms/` folder, establish the pattern with the simplest atoms first (Tasks 1-3).
**Phase 2:** Rename derived computations — smaller diffs before the big split (Task 4).
**Phase 3:** Split the big `WorkspaceStore` (1981 lines) — the hardest task (Task 5).
**Phase 4:** Extract remaining atoms from behavior classes (Tasks 6-7).
**Phase 5:** Update architecture docs and CLAUDE.md (Task 8).

---

## File Structure

### New files

| File | What it is |
|------|-----------|
| `Core/Atoms/ManagementModeAtom.swift` | `isActive: Bool`, `toggle()`, `deactivate()` |
| `Core/Atoms/UIStateAtom.swift` | Renamed + moved from `Core/Stores/WorkspaceUIStore.swift` |
| `Core/Atoms/RepoCacheAtom.swift` | Renamed + moved from `Core/Stores/WorkspaceRepoCache.swift` |
| `Core/Atoms/WorkspaceAtom.swift` | State + mutations extracted from `Core/Stores/WorkspaceStore.swift` |
| `Core/Atoms/SurfaceStateAtom.swift` | Surface registry + counts extracted from `Features/Terminal/Ghostty/SurfaceManager.swift` |
| `Core/Atoms/SessionRuntimeAtom.swift` | Runtime statuses extracted from `Core/Stores/SessionRuntime.swift` |
| `Core/Atoms/PaneDisplayDerived.swift` | Renamed + moved from `Core/Views/PaneDisplayProjector.swift` |
| `Core/Atoms/DynamicViewDerived.swift` | Renamed + moved from `Core/Stores/DynamicViewProjector.swift` |

### Modified files

| File | Change |
|------|--------|
| `Core/Stores/WorkspaceStore.swift` | Becomes persistence wrapper around `WorkspaceAtom` |
| `Core/Stores/WorkspacePersistor.swift` | Unchanged (already just I/O) |
| `App/ManagementModeMonitor.swift` | Behavior only — state moves to `ManagementModeAtom` |
| `Features/Terminal/Ghostty/SurfaceManager.swift` | Behavior only — registry/counts move to `SurfaceStateAtom` |
| `Core/Stores/SessionRuntime.swift` | Behavior only — statuses move to `SessionRuntimeAtom` |
| `CLAUDE.md` | Update architecture section |
| `docs/architecture/component_architecture.md` | Update store table |
| `docs/architecture/directory_structure.md` | Add `Core/Atoms/` section |
| ~72 source files | Update type references |
| ~41 test files | Update type references |

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

In `Sources/AgentStudio/App/ManagementModeMonitor.swift`, remove the state and delegate to the atom:

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

Note: `ManagementModeMonitor.shared.isActive` is referenced in ~18 files. Since we're keeping the `isActive` property as a pass-through, **no call sites need to change**. The monitor's public API is identical.

- [ ] **Step 3: Build to verify**

Run: `SWIFT_BUILD_DIR=".build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8)" swift build --build-path "$SWIFT_BUILD_DIR" > /tmp/build-output.txt 2>&1 && echo "PASS" || echo "FAIL"`

Expected: PASS — all call sites use `ManagementModeMonitor.shared.isActive` which still works.

- [ ] **Step 4: Run tests**

Run: `SWIFT_BUILD_DIR=".build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8)" swift test --build-path "$SWIFT_BUILD_DIR" --filter "ManagementMode" > /tmp/test-output.txt 2>&1 && echo "PASS" || echo "FAIL"`

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/AgentStudio/Core/Atoms/ManagementModeAtom.swift Sources/AgentStudio/App/ManagementModeMonitor.swift
git commit -m "refactor: extract ManagementModeAtom from ManagementModeMonitor"
```

---

## Task 2: Move and rename `WorkspaceUIStore` → `UIStateAtom`

`WorkspaceUIStore` is 47 lines — small and self-contained. It's already mostly an atom (just state), but it currently lives in `Core/Stores/`.

**Files:**
- Rename: `Sources/AgentStudio/Core/Stores/WorkspaceUIStore.swift` → `Sources/AgentStudio/Core/Atoms/UIStateAtom.swift`
- Modify: all files referencing `WorkspaceUIStore`

- [ ] **Step 1: Read the current file to understand its shape**

Read `Sources/AgentStudio/Core/Stores/WorkspaceUIStore.swift` in full. Identify:
- What state it owns
- Whether it has persistence logic inline (it shouldn't — persistence is in `WorkspacePersistor`)
- All `WorkspaceUIStore` references in Sources/ and Tests/

- [ ] **Step 2: Rename the file and class**

```bash
git mv Sources/AgentStudio/Core/Stores/WorkspaceUIStore.swift Sources/AgentStudio/Core/Atoms/UIStateAtom.swift
```

In the file, rename `class WorkspaceUIStore` → `class UIStateAtom`. Add a doc comment:

```swift
/// Atom: UI preferences state (expanded groups, colors, sidebar filter).
/// Persisted by UIStateStore (in Core/Stores/).
@Observable
@MainActor
final class UIStateAtom {
    // ... existing state and mutations, class name changed ...
}
```

- [ ] **Step 3: Update all references**

Find and replace `WorkspaceUIStore` → `UIStateAtom` across all source and test files:

```bash
rg -l "WorkspaceUIStore" Sources/ Tests/
```

Update each file. The reference count is ~5 files in Sources/.

- [ ] **Step 4: Build and test**

Run: `SWIFT_BUILD_DIR=".build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8)" swift build --build-path "$SWIFT_BUILD_DIR" > /tmp/build-output.txt 2>&1 && echo "PASS" || echo "FAIL"`

Expected: PASS

Run: `mise run test > /tmp/test-output.txt 2>&1 && echo "PASS" || echo "FAIL"`

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "refactor: rename WorkspaceUIStore → UIStateAtom, move to Core/Atoms/"
```

---

## Task 3: Move and rename `WorkspaceRepoCache` → `RepoCacheAtom`

`WorkspaceRepoCache` is 60 lines. Same pattern as Task 2.

**Files:**
- Rename: `Sources/AgentStudio/Core/Stores/WorkspaceRepoCache.swift` → `Sources/AgentStudio/Core/Atoms/RepoCacheAtom.swift`
- Modify: ~20 files referencing `WorkspaceRepoCache`

- [ ] **Step 1: Rename the file and class**

```bash
git mv Sources/AgentStudio/Core/Stores/WorkspaceRepoCache.swift Sources/AgentStudio/Core/Atoms/RepoCacheAtom.swift
```

Rename `class WorkspaceRepoCache` → `class RepoCacheAtom` in the file. Add doc comment:

```swift
/// Atom: repo enrichment cache (branches, git status, PR counts).
/// Persisted by RepoCacheStore (in Core/Stores/).
@Observable
@MainActor
final class RepoCacheAtom {
    // ... existing state and mutations ...
}
```

- [ ] **Step 2: Update all references**

```bash
rg -l "WorkspaceRepoCache" Sources/ Tests/
```

~20 source files + test files. Find and replace `WorkspaceRepoCache` → `RepoCacheAtom`.

**Important:** `CommandBarDataSource.items()` has a default parameter `repoCache: WorkspaceRepoCache = WorkspaceRepoCache()`. Update to `repoCache: RepoCacheAtom = RepoCacheAtom()`.

- [ ] **Step 3: Build and test**

Run: `SWIFT_BUILD_DIR=".build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8)" swift build --build-path "$SWIFT_BUILD_DIR" > /tmp/build-output.txt 2>&1 && echo "PASS" || echo "FAIL"`

Run: `mise run test > /tmp/test-output.txt 2>&1 && echo "PASS" || echo "FAIL"`

Expected: PASS

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "refactor: rename WorkspaceRepoCache → RepoCacheAtom, move to Core/Atoms/"
```

---

## Task 4: Rename derived computations → `*Derived` in `Core/Atoms/`

Move `PaneDisplayProjector` and `DynamicViewProjector` to `Core/Atoms/` with `*Derived` naming before the big WorkspaceStore split. Smaller diffs first reduce cognitive load.

**Files:**
- Rename: `Core/Views/PaneDisplayProjector.swift` → `Core/Atoms/PaneDisplayDerived.swift`
- Rename: `Core/Stores/DynamicViewProjector.swift` → `Core/Atoms/DynamicViewDerived.swift`

- [ ] **Step 1: Rename `PaneDisplayProjector` → `PaneDisplayDerived`**

```bash
git mv Sources/AgentStudio/Core/Views/PaneDisplayProjector.swift Sources/AgentStudio/Core/Atoms/PaneDisplayDerived.swift
```

In the file:
- Rename `enum PaneDisplayProjector` → `enum PaneDisplayDerived`
- Update doc comment: "Derived atom: projects pane display labels from WorkspaceAtom + RepoCacheAtom."

Find and replace across all files:
```bash
rg -l "PaneDisplayProjector" Sources/ Tests/
```

~11 files reference it. Replace `PaneDisplayProjector` → `PaneDisplayDerived`.

- [ ] **Step 2: Rename `DynamicViewProjector` → `DynamicViewDerived`**

```bash
git mv Sources/AgentStudio/Core/Stores/DynamicViewProjector.swift Sources/AgentStudio/Core/Atoms/DynamicViewDerived.swift
```

Rename `enum DynamicViewProjector` → `enum DynamicViewDerived`. Update references:
```bash
rg -l "DynamicViewProjector" Sources/ Tests/
```

~3 files (mostly tests since it's unused in production).

- [ ] **Step 3: Build and test**

Run: `SWIFT_BUILD_DIR=".build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8)" swift build --build-path "$SWIFT_BUILD_DIR" > /tmp/build-output.txt 2>&1 && echo "PASS" || echo "FAIL"`

Run: `mise run test > /tmp/test-output.txt 2>&1 && echo "PASS" || echo "FAIL"`

Expected: PASS

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "refactor: rename PaneDisplayProjector → PaneDisplayDerived, DynamicViewProjector → DynamicViewDerived, move to Core/Atoms/"
```

---

## Task 5: Split `WorkspaceStore` → `WorkspaceAtom` + `WorkspaceStore`

This is the biggest task. `WorkspaceStore` is 1981 lines with state, mutations, queries, persistence, undo, and UI state all in one class.

**Target:**
- `WorkspaceAtom` (~1600 lines): all state, mutations, queries, undo, helpers
- `WorkspaceStore` (~300 lines): persistence wrapper — `restore()`, `markDirty()`, `flush()`, `persistNow()`

**Files:**
- Create: `Sources/AgentStudio/Core/Atoms/WorkspaceAtom.swift`
- Modify: `Sources/AgentStudio/Core/Stores/WorkspaceStore.swift` (becomes persistence wrapper)
- Modify: ~31 source files, ~41 test files that reference `WorkspaceStore`

- [ ] **Step 1: Create `WorkspaceAtom.swift`**

Copy the current `WorkspaceStore.swift` to `Sources/AgentStudio/Core/Atoms/WorkspaceAtom.swift`. Then:

1. Rename the class: `class WorkspaceStore` → `class WorkspaceAtom`
2. Remove the persistence section entirely (lines 1436-1600):
   - Remove `persistor` property
   - Remove `persistDebounceDuration`, `clock`, `debouncedSaveTask` properties
   - Remove `isDirty` property
   - Remove `restore()`, `markDirty()`, `flush()`, `persistNow()`, `prePersistHook`
   - Remove `tabPersistenceSummary()`, `layoutRatioSummary()`
3. Remove the persistor from `init()`:
   ```swift
   init() {}
   ```
4. Remove all `markDirty()` calls from mutation methods — the store wrapper will handle this
5. Add a `didMutate` callback that the store can hook into:
   ```swift
   /// Called after any mutation. The persistence store hooks this to schedule saves.
   var onMutate: (() -> Void)?
   ```
6. Replace every `markDirty()` call with `onMutate?()` — there are approximately 40-50 call sites

Add doc comment:
```swift
/// Atom: canonical workspace state — tabs, panes, repos, worktrees, layouts.
/// Pure state + mutations. No persistence.
/// Persisted by WorkspaceStore (in Core/Stores/).
```

- [ ] **Step 2: Rewrite `WorkspaceStore` as persistence wrapper**

Replace the contents of `Sources/AgentStudio/Core/Stores/WorkspaceStore.swift`:

```swift
import Foundation
import os.log

private let storeLogger = Logger(subsystem: "com.agentstudio", category: "WorkspaceStore")

/// Persistence wrapper for WorkspaceAtom.
/// Saves and restores the atom's state to/from workspace.state.json.
/// Not @Observable — observe WorkspaceAtom directly.
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
        // NOTE: onMutate is NOT wired here — it must be wired AFTER restore()
        // completes, otherwise restore() mutations trigger markDirty() and
        // schedule saves of data we just loaded.
    }

    // MARK: - Restore

    func restore() {
        // ... move the existing restore() code here,
        // but write to atom properties instead of self properties:
        // atom.repos = ..., atom.tabs = ..., atom.panes = ..., etc.

        // Wire atom mutations to persistence AFTER restore is complete.
        // This prevents restore mutations from triggering markDirty().
        atom.onMutate = { [weak self] in
            self?.markDirty()
        }
    }

    // MARK: - Persistence

    func markDirty() {
        // ... existing markDirty code (debounce + sudden termination) ...
    }

    @discardableResult
    func flush() -> Bool {
        // ... existing flush code ...
    }

    @discardableResult
    private func persistNow() -> Bool {
        // ... existing persistNow code,
        // but read from atom properties instead of self ...
    }
}
```

- [ ] **Step 3: Update all call sites**

This is the largest mechanical step. Every file that uses `WorkspaceStore` needs to decide: am I reading/writing state (use `WorkspaceAtom`) or am I doing persistence (use `WorkspaceStore`)?

**Pattern for most call sites:**

Most code reads state or calls mutations. These should reference `WorkspaceAtom`:
```swift
// BEFORE
let store: WorkspaceStore
store.tabs
store.pane(id)
store.setActiveTab(id)

// AFTER — option A: reference the atom directly
let workspace: WorkspaceAtom
workspace.tabs
workspace.pane(id)
workspace.setActiveTab(id)

// AFTER — option B: access atom through store
let store: WorkspaceStore
store.atom.tabs
store.atom.pane(id)
store.atom.setActiveTab(id)
```

**Recommendation: Option A for new code, Option B as mechanical first pass.** Change `WorkspaceStore` references to access `.atom` for state operations. This minimizes the diff — we're not renaming variables, just adding `.atom`. A follow-up can rename parameters from `store` to `workspace` where appropriate.

Find all call sites in BOTH source and test files:
```bash
rg -l "WorkspaceStore" Sources/ Tests/
```

**~31 source files + ~41 test files** need updating. For each file, add `.atom` to state/mutation accesses. Persistence calls (`restore()`, `flush()`, `markDirty()`) stay on the store.

**Test files are the largest batch.** Most tests create a `WorkspaceStore` and call `store.tabs`, `store.pane(id)`, `store.setActiveTab(id)` directly. All of these become `store.atom.tabs`, `store.atom.pane(id)`, `store.atom.setActiveTab(id)`. This is mechanical but must be done for ALL 41 test files or the build fails.

- [ ] **Step 4: Build incrementally**

This step will have many compilation errors. Fix them file by file. The pattern is mechanical:
- `store.tabs` → `store.atom.tabs`
- `store.pane(id)` → `store.atom.pane(id)`
- `store.setActiveTab(id)` → `store.atom.setActiveTab(id)`
- `store.restore()` → stays as `store.restore()`
- `store.flush()` → stays as `store.flush()`

Run: `SWIFT_BUILD_DIR=".build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8)" swift build --build-path "$SWIFT_BUILD_DIR" > /tmp/build-output.txt 2>&1 && echo "PASS" || echo "FAIL"`

Fix errors iteratively until PASS.

- [ ] **Step 5: Run full test suite**

Run: `mise run test > /tmp/test-output.txt 2>&1 && echo "PASS" || echo "FAIL"`

Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "refactor: split WorkspaceStore into WorkspaceAtom (state) + WorkspaceStore (persistence)"
```

---

## Task 6: Extract `SurfaceStateAtom` from `SurfaceManager`

`SurfaceManager` is 942 lines. The atom portion is small — surface registry and counts. The bulk is Ghostty C API lifecycle.

**Files:**
- Create: `Sources/AgentStudio/Core/Atoms/SurfaceStateAtom.swift`
- Modify: `Sources/AgentStudio/Features/Terminal/Ghostty/SurfaceManager.swift`

- [ ] **Step 1: Read `SurfaceManager` to identify the atom state**

Read the full file. Identify:
- `private(set) var activeSurfaceCount: Int`
- `private(set) var hiddenSurfaceCount: Int`
- Any surface registry (`surfaces: [UUID: Surface]` or similar)
- Any other `@Observable` state that views read

Extract these into `SurfaceStateAtom`. Leave lifecycle, health delegates, and Ghostty C API in `SurfaceManager`.

- [ ] **Step 2: Create the atom**

```swift
import Observation

/// Atom: Ghostty surface state — registry and counts.
/// Behavior (lifecycle, health, C API) lives in SurfaceManager.
@Observable
@MainActor
final class SurfaceStateAtom {
    static let shared = SurfaceStateAtom()

    private(set) var activeSurfaceCount: Int = 0
    private(set) var hiddenSurfaceCount: Int = 0
    // ... any other surface registry state ...

    private init() {}

    // ... mutation methods for counts/registry ...
}
```

- [ ] **Step 3: Update `SurfaceManager` to delegate state to the atom**

Make `SurfaceManager` read/write `SurfaceStateAtom.shared` instead of owning the state directly.

- [ ] **Step 4: Build and test**

Run: `SWIFT_BUILD_DIR=".build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8)" swift build --build-path "$SWIFT_BUILD_DIR" > /tmp/build-output.txt 2>&1 && echo "PASS" || echo "FAIL"`

Run: `mise run test > /tmp/test-output.txt 2>&1 && echo "PASS" || echo "FAIL"`

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/AgentStudio/Core/Atoms/SurfaceStateAtom.swift Sources/AgentStudio/Features/Terminal/Ghostty/SurfaceManager.swift
git commit -m "refactor: extract SurfaceStateAtom from SurfaceManager"
```

---

## Task 7: Extract `SessionRuntimeAtom` from `SessionRuntime`

`SessionRuntime` is 238 lines. The atom is `statuses: [UUID: SessionRuntimeStatus]`. The behavior is backend coordination and health checks.

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

- [ ] **Step 3: Build and test**

Run: `SWIFT_BUILD_DIR=".build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8)" swift build --build-path "$SWIFT_BUILD_DIR" > /tmp/build-output.txt 2>&1 && echo "PASS" || echo "FAIL"`

Run: `mise run test > /tmp/test-output.txt 2>&1 && echo "PASS" || echo "FAIL"`

Expected: PASS

- [ ] **Step 4: Commit**

```bash
git add Sources/AgentStudio/Core/Atoms/SessionRuntimeAtom.swift Sources/AgentStudio/Core/Stores/SessionRuntime.swift
git commit -m "refactor: extract SessionRuntimeAtom from SessionRuntime"
```

---

## Task 8: Update architecture docs and CLAUDE.md

Document the atom/store/derived pattern so future work follows it.

**Files:**
- Modify: `CLAUDE.md`
- Modify: `docs/architecture/directory_structure.md`
- Modify: `docs/architecture/component_architecture.md`

- [ ] **Step 1: Update CLAUDE.md architecture section**

In the "Architecture at a Glance" section, update the store table:

```markdown
| Atom | Owns | Persisted by |
|------|------|-------------|
| `WorkspaceAtom` | repos, worktrees, tabs, panes, layouts | `WorkspaceStore` → `workspace.state.json` |
| `RepoCacheAtom` | repo enrichment, branches, git status, PR counts | `RepoCacheStore` → `workspace.cache.json` |
| `UIStateAtom` | expanded groups, colors, filter | `UIStateStore` → `workspace.ui.json` |
| `ManagementModeAtom` | management mode toggle | in-memory |
| `SurfaceStateAtom` | Ghostty surface registry, counts | in-memory |
| `SessionRuntimeAtom` | runtime status per pane | in-memory |
```

Add a section explaining the pattern:

```markdown
### Atom / Store / Derived Pattern

The codebase follows a Jotai-inspired state model:

- **Atoms** (`Core/Atoms/`, `*Atom` suffix): `@Observable` state containers with `private(set)` properties and mutation methods. Atoms own state but have no persistence, no event handling, no resource management.
- **Derived** (`Core/Atoms/`, `*Derived` suffix): Read-only computations from atoms. Pure functions, no owned state. Recompute on access via SwiftUI observation.
- **Stores** (`Core/Stores/`, `*Store` suffix): Persistence wrappers that save/restore atoms to disk. Not `@Observable` — observe the atom, not the store.
- **Behavior** (`App/`, `Features/`): AppKit event interception, C API bridges, resource managers. Read/write atoms but don't own state.

The rule: **atoms own state. Everything else reads/writes atoms.**
```

- [ ] **Step 2: Update `docs/architecture/directory_structure.md`**

Add `Core/Atoms/` to the directory listing with the component placement rationale.

- [ ] **Step 3: Update `docs/architecture/component_architecture.md`**

Update the component table to reflect the new atom/store split.

- [ ] **Step 4: Commit**

```bash
git add CLAUDE.md docs/architecture/directory_structure.md docs/architecture/component_architecture.md
git commit -m "docs: document atom/store/derived pattern in architecture docs"
```

---

## Task 9: Run full test suite, lint, and verify

- [ ] **Step 1: Run all tests**

Run: `mise run test > /tmp/test-output.txt 2>&1 && echo "PASS" || echo "FAIL"`

Expected: PASS

- [ ] **Step 2: Run lint**

Run: `mise run lint > /tmp/lint-output.txt 2>&1 && echo "PASS" || echo "FAIL"`

Expected: PASS

- [ ] **Step 3: Verify `Core/Atoms/` contains all expected files**

```bash
ls Sources/AgentStudio/Core/Atoms/
```

Expected files:
- `ManagementModeAtom.swift`
- `UIStateAtom.swift`
- `RepoCacheAtom.swift`
- `WorkspaceAtom.swift`
- `SurfaceStateAtom.swift`
- `SessionRuntimeAtom.swift`
- `PaneDisplayDerived.swift`
- `DynamicViewDerived.swift`

- [ ] **Step 4: Verify `Core/Stores/` contains only persistence**

```bash
ls Sources/AgentStudio/Core/Stores/
```

Expected files:
- `WorkspaceStore.swift` (persistence wrapper)
- `WorkspacePersistor.swift` (shared I/O)
- `SessionRuntime.swift` (behavior — reads/writes SessionRuntimeAtom)
- `ZmxBackend.swift` (backend — not an atom or store)

- [ ] **Step 5: Final commit if any formatting fixes needed**

```bash
git add -A
git commit -m "chore: formatting fixes from lint"
```
