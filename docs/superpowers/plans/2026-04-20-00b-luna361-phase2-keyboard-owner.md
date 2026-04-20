# LUNA-361 Phase 2 — KeyboardOwner + CommandBar Default-Scope Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship the `KeyboardOwner` derived abstraction (enum in Core/Models + stateless factory in Core/State/MainActor/Atoms) and its first consumer: CommandBar default-scope logic. After this phase, opening ⌘P from a focused inbox-placeholder surface defaults CommandBar to the `.inbox` scope — proving the seam even before Phase 3 adds real inbox actions.

**Architecture:** `KeyboardOwner` is a derived value type (enum), computed by `KeyboardOwnerDerived` (stateless factory, follows the `WorkspaceFocusDerived` pattern). Inputs: `WindowLifecycleAtom.isWorkspaceWindowKey` (new accessor), `ManagementLayerAtom.isActive` (existing), `UIStateAtom.sidebarCollapsed` / `sidebarSurface` / `sidebarHasFocus` (added in Phase 1). CommandBar reads the derived owner at open time to pick default scope. Per the spec §5.2 matrix, only the `.sidebar(.inbox) → .inbox` row changes visible behavior in this phase; all other rows preserve existing defaults.

**Tech Stack:** Swift 6.2 · `@MainActor` structs · Swift Testing · mirrors `WorkspaceFocusDerived` at `Core/State/MainActor/Atoms/WorkspaceFocusDerived.swift` · existing CommandBar infrastructure under `Features/CommandBar/`

**Depends on:** Phase 1 (LUNA-361 Phase 1 plan). Specifically: `SidebarSurface` enum, `UIStateAtom` composition fields, RepoExplorer naming, Inbox placeholder surface.

**Blocks:** Phase 3 consumes `KeyboardOwner.sidebar(.inbox)` and the registered `.inbox` CommandBar scope.

---

## Spec references

- [`docs/superpowers/specs/2026-04-17-notification-inbox-design.md`](../specs/2026-04-17-notification-inbox-design.md) — §4.4 KeyboardOwnerDerived, §5.2 CommandBar default-scope matrix, §13 tests
- [`docs/superpowers/specs/2026-04-18-interaction-model-wip.md`](../specs/2026-04-18-interaction-model-wip.md) — §4 KeyboardOwner, §5 shortcut resolution pipeline
- [`Sources/AgentStudio/Core/State/MainActor/Atoms/WorkspaceFocusDerived.swift`](../../../Sources/AgentStudio/Core/State/MainActor/Atoms/WorkspaceFocusDerived.swift) — the pattern to mirror

---

## File Structure

```
Core/Models/
├── KeyboardOwner.swift                    [NEW] enum

Core/State/MainActor/Atoms/
├── WindowLifecycleAtom.swift              [MOD] +isWorkspaceWindowKey
└── KeyboardOwnerDerived.swift             [NEW] stateless factory

Features/CommandBar/
├── CommandBarState.swift                  [MOD] +CommandBarScope.inbox
│                                                 case, default-scope
│                                                 logic reads
│                                                 KeyboardOwnerDerived
└── CommandBarDataSource.swift             [MOD] register .inbox scope
                                                  (no actions yet —
                                                   Phase 3 populates)

Tests
├── Tests/AgentStudioTests/Core/State/MainActor/Atoms/
│   ├── WindowLifecycleAtomIsWorkspaceWindowKeyTests.swift    [NEW]
│   └── KeyboardOwnerDerivedTests.swift                       [NEW]
├── Tests/AgentStudioTests/Features/CommandBar/
│   └── CommandBarInboxScopeDefaultingTests.swift             [NEW]
```

---

## Task order rationale

1. `KeyboardOwner` enum in Core/Models — foundational type, no dependencies.
2. `WindowLifecycleAtom.isWorkspaceWindowKey` accessor — the third input `KeyboardOwnerDerived` needs.
3. `KeyboardOwnerDerived` — the derived factory. Tests exercise every precedence branch.
4. `CommandBarScope.inbox` — add the enum case.
5. CommandBar default-scope logic reads `KeyboardOwnerDerived.current(...)` at open time.
6. Register `.inbox` scope in `CommandBarDataSource` (no actions; placeholder registration).

TDD for each task. Commit after each.

---

## Task 1: Add `KeyboardOwner` enum in Core/Models

**Files:**
- Create: `Sources/AgentStudio/Core/Models/KeyboardOwner.swift`
- Test: `Tests/AgentStudioTests/Core/Models/KeyboardOwnerTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/AgentStudioTests/Core/Models/KeyboardOwnerTests.swift`:

```swift
import Testing
@testable import AgentStudio

@Suite("KeyboardOwner")
struct KeyboardOwnerTests {

    @Test("equality across cases")
    func equality() {
        #expect(KeyboardOwner.otherWindow == KeyboardOwner.otherWindow)
        #expect(KeyboardOwner.managementLayer == KeyboardOwner.managementLayer)
        #expect(KeyboardOwner.sidebar(.inbox) == KeyboardOwner.sidebar(.inbox))
        #expect(KeyboardOwner.sidebar(.repos) == KeyboardOwner.sidebar(.repos))
        #expect(KeyboardOwner.none == KeyboardOwner.none)

        #expect(KeyboardOwner.sidebar(.inbox) != KeyboardOwner.sidebar(.repos))
        #expect(KeyboardOwner.otherWindow != KeyboardOwner.managementLayer)
        #expect(KeyboardOwner.none != KeyboardOwner.sidebar(.inbox))
    }

    @Test("pattern matches .sidebar with associated surface")
    func patternMatchSidebar() {
        let owner = KeyboardOwner.sidebar(.inbox)
        switch owner {
        case .sidebar(let surface):
            #expect(surface == .inbox)
        default:
            Issue.record("expected .sidebar case")
        }
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mise run test -- --filter KeyboardOwnerTests`
Expected: FAIL — `KeyboardOwner` does not exist.

- [ ] **Step 3: Create `KeyboardOwner.swift`**

Create `Sources/AgentStudio/Core/Models/KeyboardOwner.swift`:

```swift
import Foundation

/// Who currently owns keyboard interpretation in the app.
///
/// Derived value. Never stored, never manually set. Computed by
/// `KeyboardOwnerDerived` from `WindowLifecycleAtom`,
/// `ManagementLayerAtom`, and `UIStateAtom`.
///
/// Consumed by CommandBar default-scope logic (Phase 2) and —
/// once the system evolves — repos-navigation keymap, debug
/// observability, and any future unified keyboard dispatcher.
///
/// See:
/// - docs/superpowers/specs/2026-04-18-interaction-model-wip.md §4
/// - docs/superpowers/specs/2026-04-17-notification-inbox-design.md §4.4
enum KeyboardOwner: Equatable, Sendable {

    /// Some non-workspace window is key (CommandBar panel, sheet,
    /// alert). AppKit routes keys there; the workspace is passive.
    case otherWindow

    /// Management Layer is active. Its monitor interprets keys.
    case managementLayer

    /// Sidebar is visible, has responder focus, and is showing a
    /// surface. The surface's local shortcuts are live.
    case sidebar(SidebarSurface)

    /// Main window is key and nothing above applies. Responder
    /// chain handles keys normally (pane content, etc.).
    case none
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `mise run test -- --filter KeyboardOwnerTests`
Expected: PASS (2 tests)

- [ ] **Step 5: Lint**

Run: `mise run lint`
Expected: clean

- [ ] **Step 6: Commit**

```bash
git add Sources/AgentStudio/Core/Models/KeyboardOwner.swift \
        Tests/AgentStudioTests/Core/Models/KeyboardOwnerTests.swift
git commit -m "feat(core): add KeyboardOwner enum

Derived value naming who owns keyboard interpretation:
.otherWindow, .managementLayer, .sidebar(SidebarSurface), .none.
Computed by KeyboardOwnerDerived (next task). Consumed by
CommandBar default-scope logic in this phase. LUNA-361 Phase 2."
```

---

## Task 2: Add `isWorkspaceWindowKey` accessor to `WindowLifecycleAtom`

**Files:**
- Modify: `Sources/AgentStudio/Core/State/MainActor/Atoms/WindowLifecycleAtom.swift`
- Test: `Tests/AgentStudioTests/Core/State/MainActor/Atoms/WindowLifecycleAtomIsWorkspaceWindowKeyTests.swift`

- [ ] **Step 1: Read the existing `WindowLifecycleAtom.swift`**

Run: `cat Sources/AgentStudio/Core/State/MainActor/Atoms/WindowLifecycleAtom.swift`

Confirm `keyWindowId: UUID?` and `registeredWindowIds: Set<UUID>` are present (both exist today per the code-fact research in the spec). The new accessor is a pure function over these.

- [ ] **Step 2: Write the failing tests**

Create `Tests/AgentStudioTests/Core/State/MainActor/Atoms/WindowLifecycleAtomIsWorkspaceWindowKeyTests.swift`:

```swift
import Foundation
import Testing
@testable import AgentStudio

@MainActor
@Suite("WindowLifecycleAtom.isWorkspaceWindowKey")
struct WindowLifecycleAtomIsWorkspaceWindowKeyTests {

    @Test("nil keyWindowId is false")
    func nilKeyWindowIdIsFalse() {
        let atom = WindowLifecycleAtom()
        #expect(atom.isWorkspaceWindowKey == false)
    }

    @Test("keyWindowId present but not registered is false")
    func keyWindowNotRegisteredIsFalse() {
        let atom = WindowLifecycleAtom()
        let foreignId = UUID()
        atom.recordWindowBecameKey(foreignId)
        // Not in registeredWindowIds → must return false
        #expect(atom.isWorkspaceWindowKey == false)
    }

    @Test("keyWindowId present and registered is true")
    func keyWindowRegisteredIsTrue() {
        let atom = WindowLifecycleAtom()
        let id = UUID()
        atom.recordWindowRegistered(id)
        atom.recordWindowBecameKey(id)
        #expect(atom.isWorkspaceWindowKey == true)
    }

    @Test("resigning key makes isWorkspaceWindowKey false")
    func resignKeyReturnsFalse() {
        let atom = WindowLifecycleAtom()
        let id = UUID()
        atom.recordWindowRegistered(id)
        atom.recordWindowBecameKey(id)
        #expect(atom.isWorkspaceWindowKey == true)

        atom.recordWindowResignedKey(id)
        #expect(atom.isWorkspaceWindowKey == false)
    }
}
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `mise run test -- --filter WindowLifecycleAtomIsWorkspaceWindowKey`
Expected: FAIL — `isWorkspaceWindowKey` not defined.

- [ ] **Step 4: Add the computed property**

Modify `Sources/AgentStudio/Core/State/MainActor/Atoms/WindowLifecycleAtom.swift`. Add after `isReadyForLaunchRestore` or wherever other computed properties live:

```swift
    /// True when a workspace window (registered via
    /// `recordWindowRegistered(_:)`) is currently key. False when
    /// no window is key, when the key window is a non-workspace
    /// panel (CommandBar, sheet, alert), or when the key window
    /// hasn't been registered.
    ///
    /// Consumed by `KeyboardOwnerDerived`.
    var isWorkspaceWindowKey: Bool {
        keyWindowId.map { registeredWindowIds.contains($0) } ?? false
    }
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `mise run test -- --filter WindowLifecycleAtomIsWorkspaceWindowKey`
Expected: PASS (4 tests)

- [ ] **Step 6: Lint**

Run: `mise run lint`
Expected: clean

- [ ] **Step 7: Commit**

```bash
git add Sources/AgentStudio/Core/State/MainActor/Atoms/WindowLifecycleAtom.swift \
        Tests/AgentStudioTests/Core/State/MainActor/Atoms/WindowLifecycleAtomIsWorkspaceWindowKeyTests.swift
git commit -m "feat(core): add WindowLifecycleAtom.isWorkspaceWindowKey

Computed accessor: true iff keyWindowId is non-nil AND
registered via recordWindowRegistered. False when some
non-workspace window (CommandBar panel, sheet, alert) is key,
or no window is key, or the key window is not one we
registered. Input to KeyboardOwnerDerived. LUNA-361 Phase 2."
```

---

## Task 3: Create `KeyboardOwnerDerived` stateless factory

**Files:**
- Create: `Sources/AgentStudio/Core/State/MainActor/Atoms/KeyboardOwnerDerived.swift`
- Test: `Tests/AgentStudioTests/Core/State/MainActor/Atoms/KeyboardOwnerDerivedTests.swift`

- [ ] **Step 1: Write the failing tests (full §5.2 matrix)**

Create `Tests/AgentStudioTests/Core/State/MainActor/Atoms/KeyboardOwnerDerivedTests.swift`:

```swift
import Foundation
import Testing
@testable import AgentStudio

@MainActor
@Suite("KeyboardOwnerDerived precedence")
struct KeyboardOwnerDerivedTests {

    // Fixture: all three atoms, defaults.
    private func makeAtoms() -> (
        window: WindowLifecycleAtom,
        management: ManagementLayerAtom,
        uiState: UIStateAtom
    ) {
        let window = WindowLifecycleAtom()
        let management = ManagementLayerAtom()
        let uiState = UIStateAtom()
        return (window, management, uiState)
    }

    private func makeWindowKey(_ atom: WindowLifecycleAtom) {
        let id = UUID()
        atom.recordWindowRegistered(id)
        atom.recordWindowBecameKey(id)
    }

    private let derived = KeyboardOwnerDerived()

    @Test("workspace window not key returns .otherWindow")
    func notKeyReturnsOtherWindow() {
        let (window, management, uiState) = makeAtoms()
        // window is not key; isWorkspaceWindowKey == false
        let owner = derived.current(
            windowLifecycle: window,
            managementLayer: management,
            uiState: uiState
        )
        #expect(owner == .otherWindow)
    }

    @Test("management layer active returns .managementLayer")
    func managementActiveReturnsManagementLayer() {
        let (window, management, uiState) = makeAtoms()
        makeWindowKey(window)
        management.activate()
        let owner = derived.current(
            windowLifecycle: window,
            managementLayer: management,
            uiState: uiState
        )
        #expect(owner == .managementLayer)
    }

    @Test("sidebar collapsed returns .none")
    func sidebarCollapsedReturnsNone() {
        let (window, management, uiState) = makeAtoms()
        makeWindowKey(window)
        uiState.setSidebarCollapsed(true)
        uiState.setSidebarHasFocus(true)  // has focus but collapsed
        let owner = derived.current(
            windowLifecycle: window,
            managementLayer: management,
            uiState: uiState
        )
        #expect(owner == .none)
    }

    @Test("sidebar visible but no focus returns .none")
    func sidebarVisibleNoFocusReturnsNone() {
        let (window, management, uiState) = makeAtoms()
        makeWindowKey(window)
        // sidebarCollapsed default is false; sidebarHasFocus default is false
        let owner = derived.current(
            windowLifecycle: window,
            managementLayer: management,
            uiState: uiState
        )
        #expect(owner == .none)
    }

    @Test("sidebar visible with focus and .repos returns .sidebar(.repos)")
    func sidebarWithFocusReposReturnsSidebarRepos() {
        let (window, management, uiState) = makeAtoms()
        makeWindowKey(window)
        uiState.setSidebarHasFocus(true)
        uiState.setSidebarSurface(.repos)
        let owner = derived.current(
            windowLifecycle: window,
            managementLayer: management,
            uiState: uiState
        )
        #expect(owner == .sidebar(.repos))
    }

    @Test("sidebar visible with focus and .inbox returns .sidebar(.inbox)")
    func sidebarWithFocusInboxReturnsSidebarInbox() {
        let (window, management, uiState) = makeAtoms()
        makeWindowKey(window)
        uiState.setSidebarHasFocus(true)
        uiState.setSidebarSurface(.inbox)
        let owner = derived.current(
            windowLifecycle: window,
            managementLayer: management,
            uiState: uiState
        )
        #expect(owner == .sidebar(.inbox))
    }

    @Test(".otherWindow wins over .managementLayer")
    func otherWindowWinsOverManagement() {
        let (window, management, uiState) = makeAtoms()
        // window NOT key
        management.activate()
        let owner = derived.current(
            windowLifecycle: window,
            managementLayer: management,
            uiState: uiState
        )
        #expect(owner == .otherWindow)
    }

    @Test(".managementLayer wins over .sidebar")
    func managementWinsOverSidebar() {
        let (window, management, uiState) = makeAtoms()
        makeWindowKey(window)
        management.activate()
        uiState.setSidebarHasFocus(true)
        uiState.setSidebarSurface(.inbox)
        let owner = derived.current(
            windowLifecycle: window,
            managementLayer: management,
            uiState: uiState
        )
        #expect(owner == .managementLayer)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `mise run test -- --filter KeyboardOwnerDerivedTests`
Expected: FAIL — `KeyboardOwnerDerived` does not exist.

- [ ] **Step 3: Create `KeyboardOwnerDerived.swift`**

Create `Sources/AgentStudio/Core/State/MainActor/Atoms/KeyboardOwnerDerived.swift`:

```swift
import Foundation

/// Stateless factory that computes the current `KeyboardOwner`
/// from the three canonical input atoms.
///
/// Mirrors the `WorkspaceFocusDerived` pattern: no storage, no
/// observation lifecycle, no mutation — pure function returning
/// a snapshot value. Consumers call `current(...)` synchronously
/// (typically during SwiftUI view body evaluation or right before
/// opening CommandBar). Reactivity is inherited from the input
/// `@Observable` atoms: any view reading the result re-evaluates
/// when any input changes.
///
/// See:
/// - docs/superpowers/specs/2026-04-18-interaction-model-wip.md §4
/// - docs/superpowers/specs/2026-04-17-notification-inbox-design.md §4.4
/// - Sources/AgentStudio/Core/State/MainActor/Atoms/WorkspaceFocusDerived.swift
///   (the pattern this mirrors)
@MainActor
struct KeyboardOwnerDerived {

    /// Computes the current owner. Precedence (highest to lowest):
    ///
    /// 1. Workspace window is not key → `.otherWindow`
    /// 2. ManagementLayer is active → `.managementLayer`
    /// 3. Sidebar visible AND focused → `.sidebar(sidebarSurface)`
    /// 4. Otherwise → `.none`
    func current(
        windowLifecycle: WindowLifecycleAtom,
        managementLayer: ManagementLayerAtom,
        uiState: UIStateAtom
    ) -> KeyboardOwner {
        guard windowLifecycle.isWorkspaceWindowKey else {
            return .otherWindow
        }
        if managementLayer.isActive {
            return .managementLayer
        }
        if !uiState.sidebarCollapsed && uiState.sidebarHasFocus {
            return .sidebar(uiState.sidebarSurface)
        }
        return .none
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `mise run test -- --filter KeyboardOwnerDerivedTests`
Expected: PASS (8 tests covering every precedence branch of the §5.2 matrix and the two dominance cases).

- [ ] **Step 5: Lint**

Run: `mise run lint`
Expected: clean

- [ ] **Step 6: Commit**

```bash
git add Sources/AgentStudio/Core/State/MainActor/Atoms/KeyboardOwnerDerived.swift \
        Tests/AgentStudioTests/Core/State/MainActor/Atoms/KeyboardOwnerDerivedTests.swift
git commit -m "feat(core): add KeyboardOwnerDerived stateless factory

Mirrors WorkspaceFocusDerived: @MainActor struct, reads atom
references, returns a plain KeyboardOwner value. Precedence:
.otherWindow > .managementLayer > .sidebar(surface) > .none.

Tests cover every precedence branch from the spec §5.2 matrix
plus the two dominance cases (otherWindow dominates management;
management dominates sidebar). LUNA-361 Phase 2."
```

---

## Task 4: Add `.inbox` case to `CommandBarScope`

**Files:**
- Modify: `Sources/AgentStudio/Features/CommandBar/CommandBarState.swift`
- Test: extend existing CommandBar state tests if any, OR create if none exists.

- [ ] **Step 1: Read the existing `CommandBarState.swift`**

Run: `cat Sources/AgentStudio/Features/CommandBar/CommandBarState.swift | head -60`

Locate the `CommandBarScope` enum (a search: `grep -n "enum CommandBarScope" Sources/AgentStudio/Features/CommandBar/`). Confirm the existing cases (likely `.everything` plus a few others). The new `.inbox` case joins them.

- [ ] **Step 2: Add a smoke test for the new case**

Check for an existing CommandBar scope test. If `Tests/AgentStudioTests/Features/CommandBar/CommandBarScopeTests.swift` (or similar) exists, add a new test there. Otherwise, create it:

Create or extend `Tests/AgentStudioTests/Features/CommandBar/CommandBarScopeTests.swift`:

```swift
import Testing
@testable import AgentStudio

@Suite("CommandBarScope")
struct CommandBarScopeTests {

    @Test(".inbox scope exists")
    func inboxScopeExists() {
        // Fail-fast canary so later refactors can't silently
        // remove the scope that CommandBar default-scope logic
        // and Phase 3 action-registration depend on.
        let _: CommandBarScope = .inbox
    }

    // Add any parity tests for scope-prefix / scope-label / scope-
    // icon that exist for other scopes — for .inbox, all of those
    // should be set to sensible values that match the codebase
    // convention.
}
```

- [ ] **Step 3: Run test to verify it fails**

Run: `mise run test -- --filter CommandBarScopeTests`
Expected: FAIL — `.inbox` is not a case.

- [ ] **Step 4: Add the `.inbox` case**

Modify `CommandBarState.swift`. Find the `CommandBarScope` enum and add:

```swift
enum CommandBarScope: /* existing conformances */ {
    // ... existing cases ...
    case inbox          // LUNA-361: Notification Inbox surface
}
```

Update any exhaustive switch statements on `CommandBarScope` elsewhere in the file (and across the codebase — run `grep -rn "case .everything" Sources/` to find them). For each, add a `case .inbox:` branch. In Phase 2, those branches can be minimal placeholders:

- Scope label: `"Inbox"` (or whatever the label style is for other scopes)
- Scope icon: a bell glyph — `Image(systemName: "bell")` or the existing octicon convention
- Scope prefix (if the codebase uses `/scope-name` prefixes): `"inbox"` or leave to match the pattern

**Do not** populate scope actions in this phase — Phase 3 does that. The scope is registered but empty, which means typing `/inbox` (or whatever triggers it) shows an "Inbox" scope pill and no results. That's intentional.

- [ ] **Step 5: Run tests to verify they pass**

Run: `mise run test -- --filter CommandBarScope`
Expected: PASS.

- [ ] **Step 6: Build to confirm every exhaustive switch is updated**

Run: `mise run build`
Expected: clean build. Any missing `case .inbox:` branch surfaces as a compile error.

- [ ] **Step 7: Lint**

Run: `mise run lint`
Expected: clean

- [ ] **Step 8: Commit**

```bash
git add Sources/AgentStudio/Features/CommandBar/CommandBarState.swift \
        Tests/AgentStudioTests/Features/CommandBar/CommandBarScopeTests.swift
git commit -m "feat(command-bar): add .inbox case to CommandBarScope

Registers the scope so default-scope logic (next task) and
Phase 3 action registration have a value to switch on. Scope
is registered but has no actions yet — typing /inbox shows
the scope pill with an empty result list. Phase 3 populates
actions. LUNA-361 Phase 2."
```

---

## Task 5: CommandBar default-scope on open reads `KeyboardOwnerDerived`

**Files:**
- Modify: `Sources/AgentStudio/Features/CommandBar/CommandBarState.swift` (or wherever the "opening fresh CommandBar" path lives)
- Test: `Tests/AgentStudioTests/Features/CommandBar/CommandBarInboxScopeDefaultingTests.swift`

- [ ] **Step 1: Locate the open / reset / default-scope entry point**

Find the function that runs when CommandBar becomes key (or is toggled open from closed). Likely candidates:

```bash
grep -rn "performOpen\|reset\|becomeFirstResponder\|becomeKeyWindow\|open(\|openCommandBar" Sources/AgentStudio/Features/CommandBar/
```

Look for where the initial `pinnedScope` (or the current-scope value) is set. That's where default-scope selection happens. In existing code, this likely defaults to `.everything` unconditionally. The new logic adds a branch for "if opening fresh AND `KeyboardOwner == .sidebar(.inbox)`, set default to `.inbox`."

- [ ] **Step 2: Write the failing tests**

Create `Tests/AgentStudioTests/Features/CommandBar/CommandBarInboxScopeDefaultingTests.swift`:

```swift
import Foundation
import Testing
@testable import AgentStudio

@MainActor
@Suite("CommandBar default scope reads KeyboardOwnerDerived")
struct CommandBarInboxScopeDefaultingTests {

    // Adjust these helpers to match the real CommandBarState API.
    // The intent: open CommandBar against a fixture set of atoms
    // and verify the resulting default scope.

    private func makeAtoms(
        isInboxOwner: Bool
    ) -> (
        window: WindowLifecycleAtom,
        management: ManagementLayerAtom,
        uiState: UIStateAtom
    ) {
        let window = WindowLifecycleAtom()
        let management = ManagementLayerAtom()
        let uiState = UIStateAtom()
        if isInboxOwner {
            let id = UUID()
            window.recordWindowRegistered(id)
            window.recordWindowBecameKey(id)
            uiState.setSidebarHasFocus(true)
            uiState.setSidebarSurface(.inbox)
        }
        return (window, management, uiState)
    }

    @Test("opening CommandBar with owner=.sidebar(.inbox) sets default scope to .inbox")
    func inboxOwnerSetsInboxScope() {
        let (window, management, uiState) = makeAtoms(isInboxOwner: true)
        let state = CommandBarState.forOpen(
            windowLifecycle: window,
            managementLayer: management,
            uiState: uiState
        )
        #expect(state.pinnedScope == .inbox)
    }

    @Test("opening CommandBar with owner=.none preserves existing default")
    func noneOwnerPreservesExistingDefault() {
        let (window, management, uiState) = makeAtoms(isInboxOwner: false)
        // Make it `.none`: window is key but no sidebar focus
        let id = UUID()
        window.recordWindowRegistered(id)
        window.recordWindowBecameKey(id)
        let state = CommandBarState.forOpen(
            windowLifecycle: window,
            managementLayer: management,
            uiState: uiState
        )
        #expect(state.pinnedScope == .everything)  // existing default
    }

    @Test("opening CommandBar with owner=.sidebar(.repos) preserves existing default")
    func reposOwnerPreservesExistingDefault() {
        let (window, management, uiState) = makeAtoms(isInboxOwner: false)
        let id = UUID()
        window.recordWindowRegistered(id)
        window.recordWindowBecameKey(id)
        uiState.setSidebarHasFocus(true)
        uiState.setSidebarSurface(.repos)
        let state = CommandBarState.forOpen(
            windowLifecycle: window,
            managementLayer: management,
            uiState: uiState
        )
        // Phase 2 only adds .inbox → .inbox. Other owners preserve
        // the existing default (which is .everything today).
        // If a future repos-nav ticket wants .repos here, that's
        // a separate change.
        #expect(state.pinnedScope == .everything)
    }

    @Test("opening CommandBar with management layer active preserves existing default")
    func managementOwnerPreservesExistingDefault() {
        let window = WindowLifecycleAtom()
        let management = ManagementLayerAtom()
        let uiState = UIStateAtom()
        let id = UUID()
        window.recordWindowRegistered(id)
        window.recordWindowBecameKey(id)
        management.activate()
        let state = CommandBarState.forOpen(
            windowLifecycle: window,
            managementLayer: management,
            uiState: uiState
        )
        // No change to existing management-layer CommandBar behavior.
        #expect(state.pinnedScope == .everything)
    }
}
```

If the existing `CommandBarState` API doesn't have a `forOpen(...)` factory, either:
- **Preferred**: add such a factory as a thin wrapper around whatever the real open path does. Production code calls the factory too, so tests exercise the same code path.
- **Alternative**: pass atoms into the existing open path and test via the live state object.

Match the existing idiom. Do NOT fork a test-only code path that diverges from production.

- [ ] **Step 3: Run tests to verify they fail**

Run: `mise run test -- --filter CommandBarInboxScopeDefaultingTests`
Expected: FAIL — either `forOpen(...)` doesn't exist, or it doesn't branch on `KeyboardOwner` yet.

- [ ] **Step 4: Wire the branch**

In `CommandBarState.swift`, add a factory (or modify the existing open path) that reads `KeyboardOwnerDerived.current(...)` and sets the default scope:

```swift
extension CommandBarState {

    /// Produce a `CommandBarState` configured for a fresh open.
    /// Default scope is selected from the current `KeyboardOwner`:
    ///
    ///   - `.sidebar(.inbox)` → `.inbox`
    ///   - everything else    → existing default (`.everything`)
    ///
    /// Other owners preserve existing behavior. Future consumers
    /// (repos nav) can extend this mapping.
    @MainActor
    static func forOpen(
        windowLifecycle: WindowLifecycleAtom,
        managementLayer: ManagementLayerAtom,
        uiState: UIStateAtom
    ) -> CommandBarState {
        let state = CommandBarState()  // or whatever the existing
                                       // "fresh default" init is
        let owner = KeyboardOwnerDerived().current(
            windowLifecycle: windowLifecycle,
            managementLayer: managementLayer,
            uiState: uiState
        )
        switch owner {
        case .sidebar(.inbox):
            state.pinInbox()  // or set pinnedScope = .inbox, matching API
        case .sidebar(.repos), .managementLayer, .otherWindow, .none:
            break  // preserve existing default
        }
        return state
    }
}
```

Replace `state.pinInbox()` with whatever method sets `pinnedScope` on the existing `CommandBarState` — follow the convention. If the enum case requires additional metadata (label, icon) that's not auto-derived, set it here.

Also update the CommandBar open path (wherever it currently runs when the panel becomes key) to call `forOpen(...)` instead of the current unconditional default. Inject the three atom dependencies via whatever DI mechanism the file uses (`atom(\.windowLifecycle)`, `store.uiStateAtom`, or direct injection).

- [ ] **Step 5: Run tests to verify they pass**

Run: `mise run test -- --filter CommandBarInboxScopeDefaultingTests`
Expected: PASS (4 tests).

- [ ] **Step 6: Run the broader CommandBar test suite for regressions**

Run: `mise run test -- --filter CommandBar`
Expected: all existing CommandBar tests still pass. The existing default (`.everything`) is preserved for every owner except `.sidebar(.inbox)`.

- [ ] **Step 7: Manual verification**

Build and launch:
```bash
mise run build
BUILD_PATH=".build-agent-$PPID"
"$BUILD_PATH/debug/AgentStudio" &
APP_PID=$!
sleep 2
```

Then manually:
1. Press ⌘I → sidebar shows `InboxPlaceholderView`.
2. Click into the sidebar (focus it).
3. Press ⌘P to open CommandBar → the scope pill shows "Inbox" (not "Everything").
4. Close CommandBar. Press ⌘S → sidebar shows `RepoExplorerView`.
5. Focus the repos sidebar. Press ⌘P → the scope pill shows the existing default (likely "Everything").

Kill the app: `kill "$APP_PID"`

- [ ] **Step 8: Lint**

Run: `mise run lint`
Expected: clean

- [ ] **Step 9: Commit**

```bash
git add Sources/AgentStudio/Features/CommandBar/CommandBarState.swift \
        Tests/AgentStudioTests/Features/CommandBar/CommandBarInboxScopeDefaultingTests.swift
git commit -m "feat(command-bar): default scope to .inbox when owner=.sidebar(.inbox)

CommandBarState.forOpen reads KeyboardOwnerDerived.current and
selects the default pinnedScope. Only the .sidebar(.inbox) →
.inbox mapping is active in Phase 2; all other owners preserve
the existing default (.everything) — so no regression on the
management, repos, or pane-focused paths. Future consumers
(repos nav) extend the mapping.

Manual verification: CMD+I → focus sidebar → CMD+P now shows
the 'Inbox' scope pill. LUNA-361 Phase 2."
```

---

## Task 6: Register `.inbox` scope in `CommandBarDataSource` (no actions yet)

**Files:**
- Modify: `Sources/AgentStudio/Features/CommandBar/CommandBarDataSource.swift`

Phase 3 populates the actions under `.inbox` (Mark all as read, Change grouping, etc.). Phase 2 just registers the empty scope so the scope pill renders and the data source doesn't throw when `.inbox` is the active scope.

- [ ] **Step 1: Read the existing `CommandBarDataSource.swift`**

Run: `cat Sources/AgentStudio/Features/CommandBar/CommandBarDataSource.swift | head -60`

Find where scopes are registered. Likely there's a `scopes` list, a switch on scope in `items(for:)`, or similar. The pattern to follow is whatever `.everything` does today.

- [ ] **Step 2: Add `.inbox` to the scope registry**

Wherever scopes are enumerated for UI purposes (e.g., a `CommandBarScopePill` list, a scope-to-label map, or a switch in the data source items query), add a branch for `.inbox`:

```swift
// In items(for scope: CommandBarScope, ...) or equivalent:
switch scope {
case .everything:
    return everythingItems()
case .inbox:
    return []  // Phase 3 populates
// ... other scopes ...
}
```

If there's a scope-pill builder (a `CommandBarScopePill` factory), add the `.inbox` case with a sensible label and icon.

- [ ] **Step 3: Build to confirm every exhaustive switch is covered**

Run: `mise run build`
Expected: clean build. Any missing `case .inbox:` from exhaustive switches surfaces as a compile error and must be added.

- [ ] **Step 4: Manual verification**

Build and launch. Then:
1. Press ⌘I, focus sidebar, press ⌘P → CommandBar opens with `.inbox` scope pill.
2. Type something (or nothing) → results list shows empty (no actions registered yet).
3. Switch scope to `.everything` (however the CommandBar allows that) → normal results appear.

This confirms the scope is correctly registered as an empty scope.

- [ ] **Step 5: Run the full test suite**

Run: `mise run test`
Expected: all tests pass.

- [ ] **Step 6: Lint**

Run: `mise run lint`
Expected: clean

- [ ] **Step 7: Commit**

```bash
git add Sources/AgentStudio/Features/CommandBar/CommandBarDataSource.swift
git commit -m "feat(command-bar): register empty .inbox scope

CommandBarDataSource now handles the .inbox scope case. Empty
result list in Phase 2 — Phase 3 populates the inbox-scoped
actions (Mark all as read, Change grouping, Toggle sort, etc.).
This closes the last exhaustive-switch gap so the scope compiles
cleanly everywhere. LUNA-361 Phase 2."
```

---

## Phase 2 verification

- [ ] **`mise run test`** — all Phase 2 new tests pass plus every existing test.

- [ ] **`mise run lint`** — clean.

- [ ] **Manual smoke:**
    - [ ] Launch app
    - [ ] Press ⌘I → `InboxPlaceholderView` renders
    - [ ] Click into sidebar (focus it)
    - [ ] Press ⌘P → scope pill shows "Inbox"
    - [ ] Close CommandBar
    - [ ] Press ⌘S → `RepoExplorerView` renders
    - [ ] Focus filter in repos sidebar
    - [ ] Press ⌘P → scope pill shows existing default
    - [ ] Turn on management layer (whatever the toggle is)
    - [ ] Press ⌘P → scope pill shows existing default (no regression)

- [ ] **Grep for unreferenced KeyboardOwner consumers:**

    ```bash
    grep -rn "KeyboardOwnerDerived\|KeyboardOwner\." Sources/ --include='*.swift'
    ```
    Expected consumers: `CommandBarState.forOpen`, the atom file itself, tests. No unexpected readers.

- [ ] **Phase 2 is done.** Phase 3 (the notification inbox feature) can now proceed.

---

## Scope boundaries (what is explicitly NOT in Phase 2)

- ✗ Notification atoms / store / router — Phase 3.
- ✗ Inbox view content beyond the placeholder from Phase 1 — Phase 3.
- ✗ Drawer bell icon, drawer popover — Phase 3.
- ✗ Bridge `inbox.post` RPC handler — Phase 3.
- ✗ Inbox-scoped CommandBar actions (Mark all as read, Change grouping, etc.) — Phase 3.
- ✗ ⌘⇧I drawer inbox popover — Phase 3.
- ✗ Inbox keymap (⌥F / ⌥G / ⌥S / arrows / Enter / Space / Esc) — Phase 3.
- ✗ Unified keyboard dispatcher — deferred architectural debt.
- ✗ Repos-navigation keymap — future ticket; `KeyboardOwner.sidebar(.repos)` default-scope mapping left at existing behavior intentionally.

If any of the above starts to bleed into Phase 2 while executing, stop and flag — the boundary needs revision.
