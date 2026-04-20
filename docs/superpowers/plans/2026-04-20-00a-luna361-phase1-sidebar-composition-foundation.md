# LUNA-361 Phase 1 — Sidebar Composition Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move sidebar composition state (collapsed / surface / has-focus) onto `UIStateAtom` in Core, introduce a `SidebarSurfaceHost` switcher view in App, migrate sidebar collapsed persistence off `UserDefaults`, rename `Features/Sidebar/` to `Features/RepoExplorer/`, and wire `⌘I`/`⌘S` composite commands — establishing the shell so Phase 2 (KeyboardOwner) and Phase 3 (Notification Inbox feature) can build on it.

**Architecture:** App-wide UI shell state is composition state, which lives on the existing `UIStateAtom` in Core (see `docs/architecture/directory_structure.md` — Feature Slice Self-Containment, and `docs/superpowers/specs/2026-04-17-notification-inbox-design.md` §4.3). Each sidebar surface (RepoExplorer, future Inbox) is a self-contained feature that declares its own internal focus enum and publishes `focusedField != nil` into `UIStateAtom.setSidebarHasFocus(...)`. A new `SidebarSurfaceHost` SwiftUI view in `App/Windows/` switches between feature surfaces based on `uiState.sidebarSurface`. Greenfield migration for `sidebarCollapsed` — `UIStateStore` loads before windows open; no `UserDefaults` fallback.

**Tech Stack:** Swift 6.2 · AppKit + SwiftUI hybrid · Swift Testing framework (`@Suite`, `@Test`, `#expect`) · `@Observable @MainActor` atoms · `UIStateStore` JSON persistence · `mise run test` / `mise run lint`

**Depends on:** None. This phase stands alone.
**Blocks:** Phase 2 (KeyboardOwner), Phase 3 (Notification Inbox).

---

## Spec references

- [`docs/superpowers/specs/2026-04-17-notification-inbox-design.md`](../specs/2026-04-17-notification-inbox-design.md) — §4.3 atoms/persistence, §5.1 composite commands, §8.1 folder structure, §13 testing
- [`docs/superpowers/specs/2026-04-18-interaction-model-wip.md`](../specs/2026-04-18-interaction-model-wip.md) — §4.3 sidebarHasFocus contract
- [`docs/architecture/directory_structure.md`](../../architecture/directory_structure.md) — Feature Slice Self-Containment
- [`docs/architecture/workspace_data_architecture.md`](../../architecture/workspace_data_architecture.md) — Tier C (UIStateAtom)

---

## File Structure

```
Core/Models/
├── SidebarSurface.swift                          [NEW] enum .repos | .inbox

Core/State/MainActor/Atoms/
├── UIStateAtom.swift                             [MOD] +sidebarCollapsed,
│                                                       +sidebarSurface,
│                                                       +sidebarHasFocus,
│                                                       +3 setters

Core/State/MainActor/Persistence/
├── UIStateStore.swift                            [MOD] persist sidebar-
│                                                       Collapsed +
│                                                       sidebarSurface

Features/Sidebar/  →  Features/RepoExplorer/      [RENAME]
├── RepoSidebarContentView.swift → RepoExplorerView.swift
│                                                 [MOD] +RepoExplorer-
│                                                       Focus enum,
│                                                       +@FocusState,
│                                                       publishes sidebar-
│                                                       HasFocus
├── SidebarFilter.swift → RepoExplorerFilter.swift
├── SidebarGroupHeader.swift → RepoExplorerGroupHeader.swift
└── SidebarWorktreeRow.swift → RepoExplorerWorktreeRow.swift

Features/NotificationInbox/Views/
└── InboxPlaceholderView.swift                    [NEW, temporary]
                                                  Empty "Inbox coming
                                                  soon" view. Removed
                                                  in Phase 3.

App/Windows/
├── SidebarSurfaceHost.swift                      [NEW] SwiftUI switcher
│                                                       (imports both
│                                                        features)
└── MainSplitViewController.swift                 [MOD] drop UserDefaults,
                                                         read from
                                                         UIStateAtom,
                                                         install
                                                         SidebarSurface-
                                                         Host

App/Boot/
└── AppDelegate.swift                             [MOD] await UIState-
                                                         Store.load()
                                                         before opening
                                                         windows

App/Commands/
├── AppCommand.swift                              [MOD] +.showNotification-
│                                                       Inbox,
│                                                       +.showWorktree-
│                                                       Sidebar
└── AppShortcut.swift                             [MOD] bind ⌘I, ⌘S

Tests
├── Tests/AgentStudioTests/Core/State/MainActor/Atoms/
│   └── UIStateAtomCompositionTests.swift         [NEW]
├── Tests/AgentStudioTests/Core/State/MainActor/Persistence/
│   └── UIStateStoreCompositionTests.swift        [NEW]
├── Tests/AgentStudioTests/Features/RepoExplorer/
│   └── RepoExplorerFocusTests.swift              [NEW]
├── Tests/AgentStudioTests/App/Windows/
│   └── SidebarSurfaceHostTests.swift             [NEW]
└── Tests/AgentStudioTests/App/Windows/
    └── MainSplitViewControllerSidebarStateTests.swift  [NEW]
```

---

## Task order rationale

1. Create `SidebarSurface` enum (new type, no dependencies).
2. Extend `UIStateAtom` with composition fields (with tests).
3. Extend `UIStateStore` to persist the new fields (with tests).
4. Rename `Features/Sidebar/` → `Features/RepoExplorer/` (pure file + type renames).
5. `RepoExplorerView` declares `RepoExplorerFocus` and publishes `sidebarHasFocus`.
6. Create `InboxPlaceholderView` (empty temporary view for Phase 1 ⌘I target).
7. Create `SidebarSurfaceHost` switcher view.
8. Migrate `MainSplitViewController` off `UserDefaults`, install `SidebarSurfaceHost`.
9. `AppDelegate`: await `UIStateStore.load()` before opening windows.
10. Add `⌘I` / `⌘S` command cases + shortcut bindings + dispatch handler.

Tests first within each task (TDD). Commit after each task.

Run `mise run test` and `mise run lint` after every task to keep the tree green.

---

## Task 1: Add `SidebarSurface` enum in Core/Models

**Files:**
- Create: `Sources/AgentStudio/Core/Models/SidebarSurface.swift`
- Test: `Tests/AgentStudioTests/Core/Models/SidebarSurfaceTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/AgentStudioTests/Core/Models/SidebarSurfaceTests.swift`:

```swift
import Testing
@testable import AgentStudio

@Suite("SidebarSurface")
struct SidebarSurfaceTests {
    @Test("encodes to raw string")
    func encodesToRawString() throws {
        #expect(SidebarSurface.repos.rawValue == "repos")
        #expect(SidebarSurface.inbox.rawValue == "inbox")
    }

    @Test("round-trips through JSON")
    func roundTripsJSON() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        for surface in [SidebarSurface.repos, .inbox] {
            let data = try encoder.encode(surface)
            let decoded = try decoder.decode(SidebarSurface.self, from: data)
            #expect(decoded == surface)
        }
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mise run test -- --filter SidebarSurfaceTests`
Expected: FAIL with "cannot find type 'SidebarSurface' in scope"

- [ ] **Step 3: Create `SidebarSurface.swift`**

Create `Sources/AgentStudio/Core/Models/SidebarSurface.swift`:

```swift
import Foundation

/// Which content the sidebar is currently rendering.
///
/// Composition tag consumed by `UIStateAtom.sidebarSurface`,
/// `SidebarSurfaceHost` (App/Windows), and `KeyboardOwner`
/// (Phase 2). Cases enumerate every sidebar surface the app
/// supports; new surfaces extend this enum monotonically.
///
/// See docs/superpowers/specs/2026-04-18-interaction-model-wip.md §8.
enum SidebarSurface: String, Codable, Sendable, Equatable, CaseIterable {
    case repos
    case inbox
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `mise run test -- --filter SidebarSurfaceTests`
Expected: PASS (2 tests)

- [ ] **Step 5: Lint**

Run: `mise run lint`
Expected: clean

- [ ] **Step 6: Commit**

```bash
git add Sources/AgentStudio/Core/Models/SidebarSurface.swift \
        Tests/AgentStudioTests/Core/Models/SidebarSurfaceTests.swift
git commit -m "feat(core): add SidebarSurface enum

Composition tag for which surface the sidebar is currently
rendering (.repos | .inbox). Referenced by UIStateAtom in
Phase 1 and KeyboardOwner in Phase 2. LUNA-361 Phase 1."
```

---

## Task 2: Add composition fields to `UIStateAtom`

**Files:**
- Modify: `Sources/AgentStudio/Core/State/MainActor/Atoms/UIStateAtom.swift`
- Test: `Tests/AgentStudioTests/Core/State/MainActor/Atoms/UIStateAtomCompositionTests.swift`

- [ ] **Step 1: Read the existing `UIStateAtom.swift`**

Read the current file to confirm its shape before editing. Expected properties: `expandedGroups`, `checkoutColors`, `filterVisible`, `filterText` (or similar). Confirm the `@Observable @MainActor` class signature and the existing setter pattern.

Run: `cat Sources/AgentStudio/Core/State/MainActor/Atoms/UIStateAtom.swift`

- [ ] **Step 2: Write the failing tests**

Create `Tests/AgentStudioTests/Core/State/MainActor/Atoms/UIStateAtomCompositionTests.swift`:

```swift
import Testing
@testable import AgentStudio

@MainActor
@Suite("UIStateAtom composition state")
struct UIStateAtomCompositionTests {

    @Test("sidebarCollapsed defaults to false")
    func sidebarCollapsedDefault() {
        let atom = UIStateAtom()
        #expect(atom.sidebarCollapsed == false)
    }

    @Test("setSidebarCollapsed updates value")
    func setSidebarCollapsed() {
        let atom = UIStateAtom()
        atom.setSidebarCollapsed(true)
        #expect(atom.sidebarCollapsed == true)
        atom.setSidebarCollapsed(false)
        #expect(atom.sidebarCollapsed == false)
    }

    @Test("sidebarSurface defaults to .repos")
    func sidebarSurfaceDefault() {
        let atom = UIStateAtom()
        #expect(atom.sidebarSurface == .repos)
    }

    @Test("setSidebarSurface updates value")
    func setSidebarSurface() {
        let atom = UIStateAtom()
        atom.setSidebarSurface(.inbox)
        #expect(atom.sidebarSurface == .inbox)
        atom.setSidebarSurface(.repos)
        #expect(atom.sidebarSurface == .repos)
    }

    @Test("sidebarHasFocus defaults to false")
    func sidebarHasFocusDefault() {
        let atom = UIStateAtom()
        #expect(atom.sidebarHasFocus == false)
    }

    @Test("setSidebarHasFocus updates value")
    func setSidebarHasFocus() {
        let atom = UIStateAtom()
        atom.setSidebarHasFocus(true)
        #expect(atom.sidebarHasFocus == true)
        atom.setSidebarHasFocus(false)
        #expect(atom.sidebarHasFocus == false)
    }
}
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `mise run test -- --filter UIStateAtomCompositionTests`
Expected: FAIL — `sidebarCollapsed`, `sidebarSurface`, and `sidebarHasFocus` do not exist on `UIStateAtom`.

- [ ] **Step 4: Add the composition fields and setters**

Modify `Sources/AgentStudio/Core/State/MainActor/Atoms/UIStateAtom.swift`. Add the following inside the `UIStateAtom` class, after the existing `filterText` (or last existing) property:

```swift
    // MARK: - Sidebar composition state (LUNA-361 Phase 1)
    //
    // App-wide UI shell state. Describes how features compose into
    // the sidebar, not feature-specific data. Read by
    // SidebarSurfaceHost (App/Windows), MainSplitViewController,
    // KeyboardOwnerDerived (Phase 2), and CommandBar default-scope
    // logic (Phase 2).
    //
    // See docs/architecture/directory_structure.md — composition
    // state vs feature state — and docs/superpowers/specs/
    // 2026-04-17-notification-inbox-design.md §4.3.

    /// True when the sidebar split item is collapsed (hidden).
    /// Persisted via UIStateStore. Migrated from the legacy
    /// UserDefaults "sidebarCollapsed" key; no fallback.
    private(set) var sidebarCollapsed: Bool = false

    /// Which surface the sidebar is currently rendering.
    /// Persisted via UIStateStore. Default `.repos`.
    private(set) var sidebarSurface: SidebarSurface = .repos

    /// True when any declared `@FocusState` target inside the
    /// currently-visible sidebar surface is non-nil.
    /// Runtime-only — not persisted. Resets to `false` on launch.
    /// Published by each sidebar surface view via
    /// `@FocusState.onChange`.
    private(set) var sidebarHasFocus: Bool = false

    func setSidebarCollapsed(_ value: Bool) {
        sidebarCollapsed = value
    }

    func setSidebarSurface(_ surface: SidebarSurface) {
        sidebarSurface = surface
    }

    func setSidebarHasFocus(_ value: Bool) {
        sidebarHasFocus = value
    }
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `mise run test -- --filter UIStateAtomCompositionTests`
Expected: PASS (6 tests)

- [ ] **Step 6: Lint**

Run: `mise run lint`
Expected: clean

- [ ] **Step 7: Commit**

```bash
git add Sources/AgentStudio/Core/State/MainActor/Atoms/UIStateAtom.swift \
        Tests/AgentStudioTests/Core/State/MainActor/Atoms/UIStateAtomCompositionTests.swift
git commit -m "feat(core): add sidebar composition state to UIStateAtom

Adds sidebarCollapsed, sidebarSurface, sidebarHasFocus and the
three corresponding setters. Composition state — app-wide UI
shell state, not feature-specific. sidebarHasFocus is runtime-
only; the other two persist via UIStateStore in the next task.
LUNA-361 Phase 1."
```

---

## Task 3: Persist `sidebarCollapsed` and `sidebarSurface` in `UIStateStore`

**Files:**
- Modify: `Sources/AgentStudio/Core/State/MainActor/Persistence/UIStateStore.swift`
- Test: `Tests/AgentStudioTests/Core/State/MainActor/Persistence/UIStateStoreCompositionTests.swift`

- [ ] **Step 1: Read the existing `UIStateStore.swift`**

Run: `cat Sources/AgentStudio/Core/State/MainActor/Persistence/UIStateStore.swift`

Note the existing codable payload struct shape (likely `WorkspaceUIState` or similar), the save path, and the load path. The new composition fields need to round-trip through that payload.

- [ ] **Step 2: Write the failing tests**

Create `Tests/AgentStudioTests/Core/State/MainActor/Persistence/UIStateStoreCompositionTests.swift`:

```swift
import Foundation
import Testing
@testable import AgentStudio

@MainActor
@Suite("UIStateStore composition roundtrip")
struct UIStateStoreCompositionTests {

    private func makeTempURL() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(
            at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("workspace.ui.json")
    }

    @Test("sidebarCollapsed roundtrips")
    func sidebarCollapsedRoundtrips() async throws {
        let url = makeTempURL()
        let atom1 = UIStateAtom()
        atom1.setSidebarCollapsed(true)
        let store1 = UIStateStore(atom: atom1, fileURL: url)
        try await store1.save()

        let atom2 = UIStateAtom()
        let store2 = UIStateStore(atom: atom2, fileURL: url)
        try store2.load()
        #expect(atom2.sidebarCollapsed == true)
    }

    @Test("sidebarSurface roundtrips")
    func sidebarSurfaceRoundtrips() async throws {
        let url = makeTempURL()
        let atom1 = UIStateAtom()
        atom1.setSidebarSurface(.inbox)
        let store1 = UIStateStore(atom: atom1, fileURL: url)
        try await store1.save()

        let atom2 = UIStateAtom()
        let store2 = UIStateStore(atom: atom2, fileURL: url)
        try store2.load()
        #expect(atom2.sidebarSurface == .inbox)
    }

    @Test("sidebarHasFocus does NOT persist")
    func sidebarHasFocusIsRuntimeOnly() async throws {
        let url = makeTempURL()
        let atom1 = UIStateAtom()
        atom1.setSidebarHasFocus(true)
        let store1 = UIStateStore(atom: atom1, fileURL: url)
        try await store1.save()

        let atom2 = UIStateAtom()
        let store2 = UIStateStore(atom: atom2, fileURL: url)
        try store2.load()
        #expect(atom2.sidebarHasFocus == false,
                "sidebarHasFocus must reset to false on load")
    }

    @Test("load on missing file uses defaults")
    func loadWithMissingFileUsesDefaults() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("does-not-exist-\(UUID()).json")
        let atom = UIStateAtom()
        let store = UIStateStore(atom: atom, fileURL: url)
        try store.load()  // Must not throw on missing file
        #expect(atom.sidebarCollapsed == false)
        #expect(atom.sidebarSurface == .repos)
    }
}
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `mise run test -- --filter UIStateStoreCompositionTests`
Expected: FAIL — the persisted payload does not include the new fields yet; `sidebarCollapsed`/`sidebarSurface` on reload will be the defaults.

- [ ] **Step 4: Extend the codable payload and save/load logic**

Modify `Sources/AgentStudio/Core/State/MainActor/Persistence/UIStateStore.swift`:

1. Find the codable struct that represents persisted UI state (likely `WorkspaceUIState` or `UIStateSnapshot`). Add the two new fields:

```swift
// In WorkspaceUIState (or whatever the codable payload is named):
    var sidebarCollapsed: Bool = false
    var sidebarSurface: SidebarSurface = .repos
```

2. Update the snapshot builder (the code that packs the atom into the codable struct) to include the new fields. Example, inside `save()` or its helper:

```swift
let payload = WorkspaceUIState(
    expandedGroups: atom.expandedGroups,
    checkoutColors: atom.checkoutColors,
    filterVisible: atom.filterVisible,
    filterText: atom.filterText,
    sidebarCollapsed: atom.sidebarCollapsed,       // NEW
    sidebarSurface: atom.sidebarSurface            // NEW
    // sidebarHasFocus intentionally omitted — runtime-only
)
```

3. Update the apply-on-load code to push the loaded fields back into the atom. Example, inside `load()` or its helper:

```swift
atom.setSidebarCollapsed(payload.sidebarCollapsed)
atom.setSidebarSurface(payload.sidebarSurface)
// sidebarHasFocus not applied — stays at its default (false)
```

4. Ensure the decoder handles missing fields gracefully (for files written before this change). Use default values on the struct (shown above) OR an explicit `decodeIfPresent` pattern in a custom `init(from:)` if the existing pattern uses one. The greenfield policy allows missing fields to fall back to defaults — no migration shim required, just defensive decoding.

- [ ] **Step 5: Run tests to verify they pass**

Run: `mise run test -- --filter UIStateStoreCompositionTests`
Expected: PASS (4 tests)

- [ ] **Step 6: Run the broader UIStateStore test suite to confirm no regressions**

Run: `mise run test -- --filter UIStateStore`
Expected: all existing tests still pass.

- [ ] **Step 7: Lint**

Run: `mise run lint`
Expected: clean

- [ ] **Step 8: Commit**

```bash
git add Sources/AgentStudio/Core/State/MainActor/Persistence/UIStateStore.swift \
        Tests/AgentStudioTests/Core/State/MainActor/Persistence/UIStateStoreCompositionTests.swift
git commit -m "feat(core): persist sidebarCollapsed and sidebarSurface

Extends the UIStateStore codable payload with the two new
persistent composition fields. sidebarHasFocus is intentionally
NOT persisted — it is runtime-only and always resets to false
on load. Missing-field decoding falls back to defaults (green-
field policy, no migration shim). LUNA-361 Phase 1."
```

---

## Task 4: Rename `Features/Sidebar/` → `Features/RepoExplorer/`

This is a pure file-move + symbol rename. Does not change behavior. Tests that existed before the rename must still pass after it.

**Files (renames — use `git mv`):**
- `Sources/AgentStudio/Features/Sidebar/RepoSidebarContentView.swift` → `Sources/AgentStudio/Features/RepoExplorer/RepoExplorerView.swift`
- `Sources/AgentStudio/Features/Sidebar/SidebarFilter.swift` → `Sources/AgentStudio/Features/RepoExplorer/RepoExplorerFilter.swift`
- `Sources/AgentStudio/Features/Sidebar/SidebarGroupHeader.swift` → `Sources/AgentStudio/Features/RepoExplorer/RepoExplorerGroupHeader.swift`
- `Sources/AgentStudio/Features/Sidebar/SidebarWorktreeRow.swift` → `Sources/AgentStudio/Features/RepoExplorer/RepoExplorerWorktreeRow.swift`
- Any other files under `Features/Sidebar/` — move them all under `Features/RepoExplorer/` with analogous names.

- [ ] **Step 1: Inspect what's in `Features/Sidebar/` today**

Run: `ls -1 Sources/AgentStudio/Features/Sidebar/`

Make a list of every file. Every file moves; every file's contained `struct`/`class`/`enum` renames if its name contains "Sidebar" or references "RepoSidebar".

- [ ] **Step 2: Create the new directory**

Run: `mkdir -p Sources/AgentStudio/Features/RepoExplorer/`

- [ ] **Step 3: git mv each file with its new name**

Run, for each file identified in Step 1:

```bash
git mv Sources/AgentStudio/Features/Sidebar/RepoSidebarContentView.swift \
       Sources/AgentStudio/Features/RepoExplorer/RepoExplorerView.swift
git mv Sources/AgentStudio/Features/Sidebar/SidebarFilter.swift \
       Sources/AgentStudio/Features/RepoExplorer/RepoExplorerFilter.swift
git mv Sources/AgentStudio/Features/Sidebar/SidebarGroupHeader.swift \
       Sources/AgentStudio/Features/RepoExplorer/RepoExplorerGroupHeader.swift
git mv Sources/AgentStudio/Features/Sidebar/SidebarWorktreeRow.swift \
       Sources/AgentStudio/Features/RepoExplorer/RepoExplorerWorktreeRow.swift
```

Use `git mv` (not plain `mv`) so git tracks the rename and preserves blame history.

- [ ] **Step 4: Remove the now-empty `Features/Sidebar/` directory**

Run:
```bash
rmdir Sources/AgentStudio/Features/Sidebar/
```

If the directory is not empty, repeat Step 3 for the remaining files.

- [ ] **Step 5: Rename the symbols inside each moved file**

For each moved file, rename the top-level `struct` / `class` / `enum` to match the new file name. Example in `RepoExplorerView.swift` (was `RepoSidebarContentView.swift`):

```swift
// BEFORE
struct RepoSidebarContentView: View { ... }

// AFTER
struct RepoExplorerView: View { ... }
```

Apply the same pattern to:
- `SidebarFilter` → `RepoExplorerFilter`
- `SidebarGroupHeader` → `RepoExplorerGroupHeader`
- `SidebarWorktreeRow` → `RepoExplorerWorktreeRow`

Also rename any internal helper types whose names contain "Sidebar" or "RepoSidebar" to use the "RepoExplorer" prefix — preserve meaning, just unify naming.

- [ ] **Step 6: Update every reference across the codebase**

Run a grep to find every reference, then rename each:

```bash
grep -rn "RepoSidebarContentView\|SidebarFilter\|SidebarGroupHeader\|SidebarWorktreeRow" Sources/ Tests/
```

For each match, replace the old name with the new name. Do this with `sed` for speed, or manually file-by-file if you prefer to review each call site. Example:

```bash
# Dry-run preview
grep -rl "RepoSidebarContentView" Sources/ Tests/ | xargs grep -n "RepoSidebarContentView"

# Apply (macOS sed — note the -i '' flag):
grep -rl "RepoSidebarContentView" Sources/ Tests/ | \
    xargs sed -i '' 's/RepoSidebarContentView/RepoExplorerView/g'
```

Repeat for `SidebarFilter`, `SidebarGroupHeader`, `SidebarWorktreeRow`.

- [ ] **Step 7: Build to confirm no reference is missed**

Run: `mise run build`
Expected: clean build. If any "cannot find type" error appears, the symbol rename missed a call site — search and update.

- [ ] **Step 8: Run the full test suite**

Run: `mise run test`
Expected: all tests pass. Existing sidebar behavior is unchanged by the rename.

- [ ] **Step 9: Lint**

Run: `mise run lint`
Expected: clean

- [ ] **Step 10: Commit**

```bash
git add -A Sources/AgentStudio/Features/ Tests/
git commit -m "refactor: rename Features/Sidebar/ to Features/RepoExplorer/

Pure file-move + symbol rename. No behavior change. Aligns
naming with the feature's actual role (repo/worktree explorer);
the sidebar itself is composition in App/Windows/, not a
feature. Types renamed:

- RepoSidebarContentView → RepoExplorerView
- SidebarFilter         → RepoExplorerFilter
- SidebarGroupHeader    → RepoExplorerGroupHeader
- SidebarWorktreeRow    → RepoExplorerWorktreeRow

LUNA-361 Phase 1."
```

---

## Task 5: `RepoExplorerView` declares `RepoExplorerFocus` and publishes `sidebarHasFocus`

**Files:**
- Modify: `Sources/AgentStudio/Features/RepoExplorer/RepoExplorerView.swift`
- Test: `Tests/AgentStudioTests/Features/RepoExplorer/RepoExplorerFocusTests.swift`

- [ ] **Step 1: Read the current `RepoExplorerView.swift`**

Run: `cat Sources/AgentStudio/Features/RepoExplorer/RepoExplorerView.swift`

Note the existing `@FocusState` for the filter field (previously at `RepoSidebarContentView.swift:28`). Identify every focusable control so the new `RepoExplorerFocus` enum enumerates all of them.

- [ ] **Step 2: Write the failing tests**

Create `Tests/AgentStudioTests/Features/RepoExplorer/RepoExplorerFocusTests.swift`:

```swift
import Testing
@testable import AgentStudio

@MainActor
@Suite("RepoExplorer focus publishing")
struct RepoExplorerFocusTests {

    @Test("RepoExplorerFocus enum includes filter and list cases")
    func enumCases() {
        // Fail-fast canaries so later additions can't accidentally
        // remove well-known focus targets the rest of the system
        // depends on.
        let _ : RepoExplorerFocus = .filter
        let _ : RepoExplorerFocus = .list
    }

    @Test("publishing non-nil focus flips uiState.sidebarHasFocus true")
    func nonNilFocusPublishesTrue() {
        let uiState = UIStateAtom()
        #expect(uiState.sidebarHasFocus == false)

        // Simulate what @FocusState.onChange would do when the
        // filter field gains focus:
        RepoExplorerFocusPublisher.publish(
            focusedField: RepoExplorerFocus.filter,
            into: uiState
        )
        #expect(uiState.sidebarHasFocus == true)
    }

    @Test("publishing nil focus flips uiState.sidebarHasFocus false")
    func nilFocusPublishesFalse() {
        let uiState = UIStateAtom()
        uiState.setSidebarHasFocus(true)

        RepoExplorerFocusPublisher.publish(
            focusedField: nil,
            into: uiState
        )
        #expect(uiState.sidebarHasFocus == false)
    }
}
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `mise run test -- --filter RepoExplorerFocusTests`
Expected: FAIL — `RepoExplorerFocus` and `RepoExplorerFocusPublisher` do not exist yet.

- [ ] **Step 4: Add `RepoExplorerFocus` enum and publisher**

Inside `Sources/AgentStudio/Features/RepoExplorer/RepoExplorerView.swift`, ABOVE the `RepoExplorerView` struct, add:

```swift
/// Focus targets within the RepoExplorer sidebar surface.
/// Feature-internal. Cases enumerate the focusable controls inside
/// the view; `sidebarHasFocus` in UIStateAtom is derived from
/// whether `focusedField` is non-nil.
///
/// See docs/superpowers/specs/2026-04-17-notification-inbox-design.md §4.3
/// for the sidebarHasFocus contract.
enum RepoExplorerFocus: Hashable {
    case filter
    case list
    case row(UUID)   // worktree row id
}

/// Thin testable seam: publishes focus transitions into UIStateAtom.
/// Extracted from the view so unit tests can drive it without
/// instantiating SwiftUI.
enum RepoExplorerFocusPublisher {
    @MainActor
    static func publish(
        focusedField: RepoExplorerFocus?,
        into uiState: UIStateAtom
    ) {
        uiState.setSidebarHasFocus(focusedField != nil)
    }
}
```

- [ ] **Step 5: Wire `@FocusState` in `RepoExplorerView`**

Still in `RepoExplorerView.swift`, update the view struct. Replace the existing `@FocusState private var isFilterFocused: Bool` binding with the new enum-based binding:

```swift
struct RepoExplorerView: View {
    // ... existing environment / atom reads ...

    @FocusState private var focusedField: RepoExplorerFocus?

    var body: some View {
        // ... existing body ...
    }
}
```

Then, wherever the filter field was previously bound to `isFilterFocused`:

```swift
// BEFORE
.focused($isFilterFocused)

// AFTER
.focused($focusedField, equals: .filter)
```

Add `.focused($focusedField, equals: .list)` to the list container (a `List` or `ScrollView` as appropriate).

At the end of `body`, add the publisher:

```swift
        }
        .onChange(of: focusedField) { _, new in
            RepoExplorerFocusPublisher.publish(
                focusedField: new, into: uiState)
        }
    }
```

Make sure `uiState` is accessible inside the view — add the appropriate `@Environment`, `@Atom`, or property injection per the existing pattern in the file.

- [ ] **Step 6: Update any existing `isFilterFocused` call sites**

Run: `grep -rn "isFilterFocused" Sources/ Tests/`

For any reference outside `RepoExplorerView.swift`, map it to the new enum-based binding. If a caller programmatically sets filter focus (e.g., the `.filterSidebar` command handler), change it to set `focusedField = .filter` on the view's binding, or call into a view-exposed helper.

- [ ] **Step 7: Run the tests**

Run: `mise run test -- --filter RepoExplorerFocusTests`
Expected: PASS (3 tests)

Run: `mise run test -- --filter RepoExplorer`
Expected: all RepoExplorer tests pass (filter tests plus the new focus tests).

- [ ] **Step 8: Lint**

Run: `mise run lint`
Expected: clean

- [ ] **Step 9: Commit**

```bash
git add Sources/AgentStudio/Features/RepoExplorer/RepoExplorerView.swift \
        Tests/AgentStudioTests/Features/RepoExplorer/RepoExplorerFocusTests.swift
git commit -m "feat(repo-explorer): publish sidebarHasFocus via RepoExplorerFocus

RepoExplorerView declares an internal RepoExplorerFocus enum
(.filter, .list, .row(id)) and publishes focusedField != nil
into UIStateAtom.sidebarHasFocus on .onChange. A thin
RepoExplorerFocusPublisher seam keeps the state-transition
logic testable without SwiftUI instantiation. This is the
per-surface focus pattern specified in the notification-inbox
design §4.3 and the interaction-model WIP §8. LUNA-361 Phase 1."
```

---

## Task 6: Create temporary `InboxPlaceholderView`

A minimal empty view so `⌘I` in Phase 1 has something to render. Replaced in Phase 3 with the real `InboxSidebarView`.

**Files:**
- Create: `Sources/AgentStudio/Features/NotificationInbox/Views/InboxPlaceholderView.swift`

- [ ] **Step 1: Create the feature slice directory**

Run: `mkdir -p Sources/AgentStudio/Features/NotificationInbox/Views/`

- [ ] **Step 2: Create the placeholder view**

Create `Sources/AgentStudio/Features/NotificationInbox/Views/InboxPlaceholderView.swift`:

```swift
import SwiftUI

/// Placeholder inbox view used in LUNA-361 Phase 1 only.
/// Replaced by `InboxSidebarView` in Phase 3.
///
/// Exists so `⌘I` has a renderable destination once
/// `SidebarSurfaceHost` is wired.
struct InboxPlaceholderView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "bell.slash")
                .imageScale(.large)
                .foregroundStyle(.secondary)
            Text("Inbox")
                .font(.headline)
            Text("No notifications yet")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}
```

- [ ] **Step 3: Build to confirm the file compiles**

Run: `mise run build`
Expected: clean build.

- [ ] **Step 4: Lint**

Run: `mise run lint`
Expected: clean

- [ ] **Step 5: Commit**

```bash
git add Sources/AgentStudio/Features/NotificationInbox/Views/InboxPlaceholderView.swift
git commit -m "feat(notification-inbox): add InboxPlaceholderView (Phase 1 only)

Minimal empty view so CMD+I has a renderable destination once
SidebarSurfaceHost is wired. Replaced by the real
InboxSidebarView in Phase 3. LUNA-361 Phase 1."
```

---

## Task 7: Create `SidebarSurfaceHost` switcher view

**Files:**
- Create: `Sources/AgentStudio/App/Windows/SidebarSurfaceHost.swift`
- Test: `Tests/AgentStudioTests/App/Windows/SidebarSurfaceHostTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/AgentStudioTests/App/Windows/SidebarSurfaceHostTests.swift`:

```swift
import SwiftUI
import Testing
@testable import AgentStudio

@MainActor
@Suite("SidebarSurfaceHost")
struct SidebarSurfaceHostTests {

    @Test("activeSurface returns .repos when uiState.sidebarSurface is .repos")
    func activeSurfaceRepos() {
        let uiState = UIStateAtom()
        uiState.setSidebarSurface(.repos)
        #expect(SidebarSurfaceHost.activeSurface(uiState: uiState) == .repos)
    }

    @Test("activeSurface returns .inbox when uiState.sidebarSurface is .inbox")
    func activeSurfaceInbox() {
        let uiState = UIStateAtom()
        uiState.setSidebarSurface(.inbox)
        #expect(SidebarSurfaceHost.activeSurface(uiState: uiState) == .inbox)
    }
}
```

`activeSurface` is a thin testable accessor exposing the current surface. The actual `body` rendering is harder to unit-test directly; we rely on compile + manual verification for that.

- [ ] **Step 2: Run test to verify it fails**

Run: `mise run test -- --filter SidebarSurfaceHostTests`
Expected: FAIL — `SidebarSurfaceHost` does not exist.

- [ ] **Step 3: Create `SidebarSurfaceHost.swift`**

Create `Sources/AgentStudio/App/Windows/SidebarSurfaceHost.swift`:

```swift
import SwiftUI

/// Root SwiftUI view hosting the sidebar. Switches between
/// sidebar surface implementations based on
/// `uiState.sidebarSurface`. Lives in App/Windows/ because it
/// imports both Features/RepoExplorer/ and
/// Features/NotificationInbox/ — only App may import across
/// feature boundaries.
///
/// Each surface view owns its own focus state and publishes
/// into `UIStateAtom.sidebarHasFocus`; this host intentionally
/// does NOT publish focus itself (per the per-surface contract
/// in docs/superpowers/specs/2026-04-17-notification-inbox-design.md §4.3).
struct SidebarSurfaceHost: View {
    let uiState: UIStateAtom
    // Add other dependencies (store, repo cache, etc.) as needed
    // to construct the child views. Follow existing patterns in
    // whatever currently hosts the sidebar content.

    var body: some View {
        switch uiState.sidebarSurface {
        case .repos:
            RepoExplorerView(/* pass required deps */)
        case .inbox:
            InboxPlaceholderView()
        }
    }

    /// Pure accessor exposed for tests. Mirrors the switch in `body`.
    static func activeSurface(uiState: UIStateAtom) -> SidebarSurface {
        uiState.sidebarSurface
    }
}
```

Adjust the `RepoExplorerView(/* pass required deps */)` initialization to match whatever parameters that view currently takes. Look at the current call site in `MainSplitViewController` (or wherever `RepoExplorerView` is instantiated today) and mirror it.

- [ ] **Step 4: Run test to verify it passes**

Run: `mise run test -- --filter SidebarSurfaceHostTests`
Expected: PASS (2 tests)

- [ ] **Step 5: Build to confirm the full view compiles**

Run: `mise run build`
Expected: clean build.

- [ ] **Step 6: Lint**

Run: `mise run lint`
Expected: clean

- [ ] **Step 7: Commit**

```bash
git add Sources/AgentStudio/App/Windows/SidebarSurfaceHost.swift \
        Tests/AgentStudioTests/App/Windows/SidebarSurfaceHostTests.swift
git commit -m "feat(app): add SidebarSurfaceHost switcher view

Switches between RepoExplorerView and InboxPlaceholderView
based on uiState.sidebarSurface. Lives in App/Windows/ because
it imports both features — only App may import across feature
boundaries. Does NOT publish focus itself; per the
interaction-model contract, each surface view publishes its
own focus state into UIStateAtom.sidebarHasFocus. LUNA-361
Phase 1."
```

---

## Task 8: Migrate `MainSplitViewController` off `UserDefaults`

**Files:**
- Modify: `Sources/AgentStudio/App/Windows/MainSplitViewController.swift`
- Test: `Tests/AgentStudioTests/App/Windows/MainSplitViewControllerSidebarStateTests.swift`

This is the sidebarCollapsed ownership migration. Per spec §4.3 and the non-goals, **no migration from UserDefaults** — the legacy key is simply abandoned. `MainSplitViewController` reads `uiState.sidebarCollapsed` at `viewDidLoad` and writes back via `uiState.setSidebarCollapsed(...)` on toggle.

- [ ] **Step 1: Read the existing `MainSplitViewController.swift`**

Run: `cat Sources/AgentStudio/App/Windows/MainSplitViewController.swift | head -160`

Note specifically:
- Line 45: `sidebarCollapsedKey = "sidebarCollapsed"` constant
- Line ~91: `UserDefaults.standard.bool(forKey: Self.sidebarCollapsedKey)` read in `viewDidLoad`
- Line ~96: `saveSidebarState()` function writing to UserDefaults
- Line ~98: the actual `UserDefaults.standard.set(...)` call
- Line ~120: `isSidebarCollapsed` computed var reading `splitViewItems.first?.isCollapsed`

Also identify how the controller is constructed — specifically, does it already receive a `uiState: UIStateAtom` dependency, or do you need to inject it? Likely it receives a `store` that has a `uiStateAtom`. Follow the existing pattern.

- [ ] **Step 2: Write the failing tests**

Create `Tests/AgentStudioTests/App/Windows/MainSplitViewControllerSidebarStateTests.swift`:

```swift
import AppKit
import Testing
@testable import AgentStudio

@MainActor
@Suite("MainSplitViewController sidebar state")
struct MainSplitViewControllerSidebarStateTests {

    // NOTE: These tests instantiate the controller and drive its
    // loadView/viewDidLoad. Adjust the constructor call to match
    // the real MainSplitViewController init signature.

    @Test("viewDidLoad with uiState.sidebarCollapsed=true collapses the sidebar")
    func respectsAtomOnLoad() {
        // Arrange
        let uiState = UIStateAtom()
        uiState.setSidebarCollapsed(true)
        let controller = MainSplitViewController.makeForTest(uiState: uiState)

        // Act
        _ = controller.view  // triggers loadView + viewDidLoad

        // Assert
        #expect(controller.isSidebarCollapsed == true)
    }

    @Test("viewDidLoad with uiState.sidebarCollapsed=false leaves sidebar expanded")
    func expandsWhenAtomFalse() {
        let uiState = UIStateAtom()
        // Must also have non-empty repos OR the existing "force collapse
        // if no repos" safeguard kicks in. Set minimal non-empty state
        // per the fixture pattern in the existing suite.
        let controller = MainSplitViewController.makeForTest(
            uiState: uiState,
            withRepos: true
        )

        _ = controller.view

        #expect(controller.isSidebarCollapsed == false)
    }

    @Test("toggling sidebar writes into uiState.sidebarCollapsed")
    func toggleWritesToAtom() {
        let uiState = UIStateAtom()
        let controller = MainSplitViewController.makeForTest(
            uiState: uiState, withRepos: true)
        _ = controller.view
        #expect(uiState.sidebarCollapsed == false)

        controller.toggleSidebarForTest()
        #expect(uiState.sidebarCollapsed == true)

        controller.toggleSidebarForTest()
        #expect(uiState.sidebarCollapsed == false)
    }
}
```

If `MainSplitViewController` does not already expose a test seam (`makeForTest`, `toggleSidebarForTest`), add a minimal internal one in the next step. Keep production init unchanged.

- [ ] **Step 3: Run tests to verify they fail**

Run: `mise run test -- --filter MainSplitViewControllerSidebarStateTests`
Expected: FAIL — either `makeForTest` is missing, or the controller still reads `UserDefaults`.

- [ ] **Step 4: Replace the UserDefaults read with a `UIStateAtom` read**

In `MainSplitViewController.swift`:

1. Delete the `sidebarCollapsedKey` constant at line 45.

```swift
// DELETE
private static let sidebarCollapsedKey = "sidebarCollapsed"
```

2. Replace the `UserDefaults.standard.bool(forKey: Self.sidebarCollapsedKey)` read in `viewDidLoad`. Look for the block near line 89-93 that looks like:

```swift
// BEFORE
if store.repositoryTopologyAtom.repos.isEmpty {
    sidebarItem.isCollapsed = true
} else if UserDefaults.standard.bool(forKey: Self.sidebarCollapsedKey) {
    sidebarItem.isCollapsed = true
}
```

Replace with:

```swift
// AFTER
if store.repositoryTopologyAtom.repos.isEmpty {
    sidebarItem.isCollapsed = true
} else if store.uiStateAtom.sidebarCollapsed {
    sidebarItem.isCollapsed = true
}
```

Adjust the atom accessor to match the existing convention in the file (e.g., `store.uiState`, `atom(\.uiState)`, or however the controller currently reaches UIStateAtom). Look at nearby code in the same controller for the idiom.

3. Replace `saveSidebarState()`. Look for a function near line 96 like:

```swift
// BEFORE
private func saveSidebarState() {
    let isCollapsed = splitViewItems.first?.isCollapsed ?? false
    UserDefaults.standard.set(isCollapsed, forKey: Self.sidebarCollapsedKey)
}
```

Replace with:

```swift
// AFTER
private func saveSidebarState() {
    let isCollapsed = splitViewItems.first?.isCollapsed ?? false
    store.uiStateAtom.setSidebarCollapsed(isCollapsed)
}
```

4. Confirm `savePersistentUIState()` (or equivalent) still calls `saveSidebarState()` — no change required if it already does.

5. Install `SidebarSurfaceHost` as the sidebar content. Find where the sidebar split item's view is built today — it probably instantiates `RepoExplorerView` (post-rename) via an `NSHostingController`. Replace that with `SidebarSurfaceHost`:

```swift
// BEFORE (approximate — adjust to the real code)
let sidebarHostingController = NSHostingController(
    rootView: RepoExplorerView(...)
)

// AFTER
let sidebarHostingController = NSHostingController(
    rootView: SidebarSurfaceHost(uiState: store.uiStateAtom /* plus
        other deps needed to instantiate RepoExplorerView inside */)
)
```

- [ ] **Step 5: Expose test seams**

At the bottom of `MainSplitViewController.swift`, add an internal test helper block (wrapped in `#if DEBUG` if the project convention requires it, or unwrapped if internal test helpers are allowed in production files). Per `AGENTS.md` "do not add new `#if DEBUG` test hooks in production files" — so use internal access instead, or expose a lightweight factory in a test-support file.

Given the AGENTS.md guidance against `#if DEBUG` test hooks, use a **separate extension file** under `Tests/` or an internal constructor already expected to exist. If neither option is clean, propose a protocol seam in the spec and implement that. For this plan, assume an internal factory exists or add one:

```swift
// In a new file: Tests/AgentStudioTests/App/Windows/MainSplitViewController+TestSupport.swift
import AppKit
@testable import AgentStudio

extension MainSplitViewController {
    static func makeForTest(
        uiState: UIStateAtom,
        withRepos: Bool = false
    ) -> MainSplitViewController {
        // Build minimal fixture dependencies matching the real
        // init signature. If the real signature requires more
        // than can be reasonably faked, escalate: propose a
        // test-seam refactor before continuing.
        let store = /* minimal WorkspaceStore fixture */
        if withRepos { /* add a canonical repo fixture */ }
        return MainSplitViewController(store: store /*, ... */)
    }

    func toggleSidebarForTest() {
        handleToggleSidebar()  // or whatever the existing toggle is named
        saveSidebarState()     // mirror the real toggle path
    }

    var isSidebarCollapsed: Bool {
        splitViewItems.first?.isCollapsed ?? false
    }
}
```

If the project does not already have a `+TestSupport.swift` convention, follow the pattern used elsewhere — check `Tests/AgentStudioTests/` for existing `*+TestSupport.swift` or `*+Fixtures.swift` files and mimic.

- [ ] **Step 6: Run tests to verify they pass**

Run: `mise run test -- --filter MainSplitViewControllerSidebarStateTests`
Expected: PASS (3 tests)

- [ ] **Step 7: Confirm the UserDefaults key is truly dead**

Run:
```bash
grep -rn "sidebarCollapsed" Sources/ --include='*.swift'
```

The only matches should be in `UIStateAtom.swift`, `UIStateStore.swift`, `SidebarSurfaceHost.swift`, `MainSplitViewController.swift` (reading from atom), and tests. **No `UserDefaults` references. No `"sidebarCollapsed"` string literal.** If any legacy reference remains, remove it.

- [ ] **Step 8: Run the full test suite to confirm no regression**

Run: `mise run test`
Expected: all tests pass.

- [ ] **Step 9: Lint**

Run: `mise run lint`
Expected: clean

- [ ] **Step 10: Commit**

```bash
git add Sources/AgentStudio/App/Windows/MainSplitViewController.swift \
        Tests/AgentStudioTests/App/Windows/MainSplitViewControllerSidebarStateTests.swift \
        Tests/AgentStudioTests/App/Windows/MainSplitViewController+TestSupport.swift
git commit -m "feat(app): migrate sidebarCollapsed to UIStateAtom; install SidebarSurfaceHost

Drops the UserDefaults 'sidebarCollapsed' key read/write
entirely. Greenfield migration per the design-doc non-goals:
no dual-write, no backward-compat shim. Reads from
store.uiStateAtom.sidebarCollapsed at viewDidLoad; writes via
uiStateAtom.setSidebarCollapsed on toggle.

Installs SidebarSurfaceHost as the sidebar content so CMD+I
(wired in Task 10) has a renderable surface switcher.

LUNA-361 Phase 1."
```

---

## Task 9: `AppDelegate` awaits `UIStateStore.load()` before opening windows

This ordering fix ensures `uiState.sidebarCollapsed` and `uiState.sidebarSurface` are populated from disk before `MainSplitViewController.viewDidLoad()` reads them. Without this, the first read returns the defaults and we'd need a reactive observer to "fix up" the view after the fact.

**Files:**
- Modify: `Sources/AgentStudio/App/Boot/AppDelegate.swift`

- [ ] **Step 1: Locate the boot sequence in `AppDelegate.swift`**

Run: `grep -n "UIStateStore\|applicationDidFinishLaunching\|MainWindow\|openWindow" Sources/AgentStudio/App/Boot/AppDelegate.swift`

Identify:
- Where `UIStateStore` is instantiated
- Where `UIStateStore.load()` is currently called (if at all)
- Where the main window is opened (`NSApp.activate`, `NSWindowController(...).showWindow`, or similar)

- [ ] **Step 2: Ensure `UIStateStore.load()` is called before window open**

Modify the boot sequence so the order is:

```swift
// In applicationDidFinishLaunching (or equivalent):
// 1. Instantiate atoms and stores
let uiStateAtom = UIStateAtom()
let uiStateStore = UIStateStore(atom: uiStateAtom, fileURL: /* ... */)
// ... other stores ...

// 2. Load persisted state BEFORE opening any window
do {
    try uiStateStore.load()
    try workspaceStore.load()
    try repoCacheStore.load()
} catch {
    // Greenfield policy: missing/corrupt files → defaults, no crash.
    // Log and continue.
    Logger.boot.error("Store load failed; using defaults: \(error)")
}

// 3. NOW open the main window
mainWindowController = MainWindowController(...)
mainWindowController.showWindow(nil)
```

Follow the existing pattern; do not invent new sequencing primitives. If `load()` is already called before `showWindow`, no change is needed here — just confirm by reading the file.

- [ ] **Step 3: Run the full test suite**

Run: `mise run test`
Expected: all tests pass. If any test instantiates `AppDelegate` or the boot sequence, confirm it still works.

- [ ] **Step 4: Run the app and verify visually**

Run (in a separate shell, so the blocking launch doesn't stall the plan):
```bash
mise run build
BUILD_PATH=".build-agent-$PPID"
"$BUILD_PATH/debug/AgentStudio" &
APP_PID=$!
# Wait a few seconds for the app to fully launch
sleep 3
# Check that the sidebar collapse state was read before the window opened
# (i.e., no "flash" of expanded sidebar when the persisted state is collapsed).
# Manual visual check — no automated assertion for this.
kill "$APP_PID"
```

- [ ] **Step 5: Lint**

Run: `mise run lint`
Expected: clean

- [ ] **Step 6: Commit**

```bash
git add Sources/AgentStudio/App/Boot/AppDelegate.swift
git commit -m "fix(boot): load UIStateStore before opening main window

Guarantees uiState.sidebarCollapsed and uiState.sidebarSurface
are populated from disk before MainSplitViewController.view-
DidLoad() reads them, avoiding a first-frame flash of the
default sidebar state. Greenfield policy: load failures fall
back to defaults (no crash). LUNA-361 Phase 1."
```

---

## Task 10: Wire `⌘I` and `⌘S` composite commands

**Files:**
- Modify: `Sources/AgentStudio/App/Commands/AppCommand.swift`
- Modify: `Sources/AgentStudio/App/Commands/AppShortcut.swift`
- Modify: `Sources/AgentStudio/App/Boot/AppDelegate.swift` (or wherever command dispatch lives)

- [ ] **Step 1: Locate the existing `AppCommand` enum**

Run: `grep -n "enum AppCommand\|case filterSidebar\|case " Sources/AgentStudio/App/Commands/AppCommand.swift | head -20`

- [ ] **Step 2: Add the two new cases**

Modify `Sources/AgentStudio/App/Commands/AppCommand.swift`. Add the new cases alongside existing ones (e.g., next to `.filterSidebar`):

```swift
enum AppCommand: Hashable {
    // ... existing cases ...
    case filterSidebar
    case showNotificationInbox     // NEW — ⌘I: composite, ensures sidebar
                                   //       visible, surface = .inbox,
                                   //       moves focus to inbox list
                                   //       unless CommandBar is key
    case showWorktreeSidebar       // NEW — ⌘S: composite, ensures sidebar
                                   //       visible, surface = .repos;
                                   //       does NOT force focus
    // ... other existing cases ...
}
```

- [ ] **Step 3: Add the shortcut bindings**

Modify `Sources/AgentStudio/App/Commands/AppShortcut.swift`. Find the existing binding table (there's likely a dictionary or switch mapping shortcut triggers to `AppCommand`). Add:

```swift
// In the binding table, alongside existing entries:
ShortcutTrigger(key: "i", modifiers: [.command]): .showNotificationInbox,
ShortcutTrigger(key: "s", modifiers: [.command]): .showWorktreeSidebar,
```

Adjust the syntax to match the existing convention in the file exactly.

- [ ] **Step 4: Implement the dispatch handler**

Find `AppDelegate.perform(_ command: AppCommand)` (or equivalent in whatever handles dispatch — possibly `CommandDispatcher` calls into `AppDelegate` via `.perform`). Add two new cases:

```swift
case .showNotificationInbox:
    showNotificationInbox()

case .showWorktreeSidebar:
    showWorktreeSidebar()
```

Then add the two helper methods:

```swift
@MainActor
private func showNotificationInbox() {
    // 1. Ensure sidebar visible
    mainSplitViewController.ensureSidebarVisible()

    // 2. Set surface to inbox
    store.uiStateAtom.setSidebarSurface(.inbox)

    // 3. Move focus to the inbox surface — UNLESS CommandBar is
    //    the key window (we must not steal its focus).
    if !isCommandBarKey {
        mainSplitViewController.focusSidebar()
    }
}

@MainActor
private func showWorktreeSidebar() {
    mainSplitViewController.ensureSidebarVisible()
    store.uiStateAtom.setSidebarSurface(.repos)
    // Does NOT force focus — respects user's current focus target.
}
```

Implement `ensureSidebarVisible()` and `focusSidebar()` on `MainSplitViewController` if they don't exist:

```swift
// In MainSplitViewController:
func ensureSidebarVisible() {
    guard let sidebarItem = splitViewItems.first,
          sidebarItem.isCollapsed else { return }
    sidebarItem.animator().isCollapsed = false
    store.uiStateAtom.setSidebarCollapsed(false)
}

func focusSidebar() {
    // Route focus to the active sidebar surface. The surface's
    // own @FocusState will publish into uiState.sidebarHasFocus.
    // Use whatever NSWindow.makeFirstResponder(...) / SwiftUI
    // focus-binding mechanism the codebase already uses for
    // e.g. .filterSidebar.
    // ...
}
```

For `isCommandBarKey`, look for an existing accessor (e.g., `commandBarPanel.isKeyWindow`) and use that. If none exists, temporarily gate on `NSApp.keyWindow !== mainWindow` or similar.

- [ ] **Step 5: Launch the app and verify visually**

Run:
```bash
mise run build
BUILD_PATH=".build-agent-$PPID"
"$BUILD_PATH/debug/AgentStudio" &
APP_PID=$!
```

Then manually verify:
1. Press ⌘I → sidebar shows `InboxPlaceholderView` ("Inbox / No notifications yet")
2. Press ⌘S → sidebar returns to `RepoExplorerView` (worktrees list)
3. Collapse the sidebar (⌃⌘S or toolbar button, whatever exists), then ⌘I → sidebar reappears showing inbox
4. Quit and relaunch → sidebar surface persisted; if you left it on inbox, it's still on inbox

Kill the app: `kill "$APP_PID"`

- [ ] **Step 6: Run the full test suite**

Run: `mise run test`
Expected: all tests pass.

- [ ] **Step 7: Lint**

Run: `mise run lint`
Expected: clean

- [ ] **Step 8: Commit**

```bash
git add Sources/AgentStudio/App/Commands/AppCommand.swift \
        Sources/AgentStudio/App/Commands/AppShortcut.swift \
        Sources/AgentStudio/App/Boot/AppDelegate.swift \
        Sources/AgentStudio/App/Windows/MainSplitViewController.swift
git commit -m "feat(app): wire CMD+I and CMD+S composite commands

CMD+I shows the inbox sidebar surface (placeholder in Phase 1).
CMD+S returns to the repo sidebar. Both are composite commands
that ensure the sidebar is visible, set sidebarSurface on the
atom, and move focus appropriately (CMD+I focuses the sidebar
unless CommandBar is key; CMD+S respects current focus).

Phase 1 wrap-up: the sidebar shell is now complete. Phase 2
adds KeyboardOwnerDerived so CommandBar default-scope reacts
to the current surface; Phase 3 replaces InboxPlaceholderView
with the real notification inbox.

LUNA-361 Phase 1."
```

---

## Phase 1 verification (run at end)

Before marking Phase 1 complete, run the full verification matrix:

- [ ] **`mise run test`** — every test passes, including all new tests from Tasks 1, 2, 3, 5, 7, 8.

- [ ] **`mise run lint`** — clean (zero errors, zero warnings, or matches pre-change baseline).

- [ ] **Manual smoke test** — launch the app:
    - [ ] ⌘I → sidebar shows `InboxPlaceholderView` ("Inbox / No notifications yet").
    - [ ] ⌘S → sidebar shows `RepoExplorerView` (worktrees list).
    - [ ] Toggle the sidebar collapsed; relaunch → state persists.
    - [ ] Toggle sidebar surface; relaunch → surface persists.
    - [ ] Focus the filter in repos sidebar → can see (via `po atom(\.uiState).sidebarHasFocus` in the debugger, or add a temporary log) that `sidebarHasFocus == true`; blur → false.

- [ ] **Grep for dead references:**

    ```bash
    grep -rn "sidebarCollapsed" Sources/ --include='*.swift' | \
        grep -v "UIStateAtom\|UIStateStore\|setSidebarCollapsed\|\.sidebarCollapsed"
    ```
    Expected: no hits (no stray UserDefaults-key string or stale references).

    ```bash
    grep -rn "isFilterFocused" Sources/ --include='*.swift'
    ```
    Expected: no hits (all call sites migrated to `RepoExplorerFocus.filter`).

- [ ] **Grep for the old feature name:**

    ```bash
    grep -rn "Features/Sidebar/\|RepoSidebarContentView\|SidebarFilter\|SidebarGroupHeader\|SidebarWorktreeRow" Sources/ Tests/
    ```
    Expected: no hits.

- [ ] **Phase 1 is done.** Phase 2 can now proceed (in the next plan doc).

---

## Scope boundaries (what is explicitly NOT in Phase 1)

- ✗ `KeyboardOwner` enum or `KeyboardOwnerDerived` — Phase 2.
- ✗ `Notification` model, `NotificationInboxAtom`, `NotificationInboxPrefsAtom`, `NotificationInboxStore`, `NotificationRouter`, `PaneFocusTracker` — Phase 3.
- ✗ Drawer bell icon, `DrawerOverlay.TrailingActions` extensions — Phase 3.
- ✗ Bridge `inbox.post` RPC handler — Phase 3.
- ✗ `CommandBar` `.inbox` scope registration or actions — Phase 2 registers, Phase 3 populates.
- ✗ `⌘⇧I` drawer inbox popover command — Phase 3.
- ✗ Inbox-specific keymap (`⌥F`, `⌥G`, `⌥S`, arrows, etc.) — Phase 3.
- ✗ Per-worktree `🔔 N` pill data binding — Phase 3.
- ✗ `SharedComponents/` at top level — separate design-system ticket.

If any of these appears relevant while executing a Phase 1 task, stop and flag it — it either doesn't belong or the boundary needs revision.
