# Workspace Focus Context Atom Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace ad hoc workspace focus computation with an app-wide `WorkspaceFocusContextAtom` that exposes `currentFocus` and is consumed by command bar and menu visibility code.

**Architecture:** Add a focused projection atom under `Core/State/MainActor/Atoms` that derives current workspace focus from the canonical workspace atoms. Keep `AppCommand` metadata unchanged for now, but migrate visibility/context consumers to the shared atom-backed read path so command bar and menus read one app-wide focus context surface.

**Tech Stack:** Swift 6.2, Swift Testing, AppKit, SwiftUI, Observation

---

### Task 1: Add failing tests for the new focus-context atom

**Files:**
- Modify: `Tests/AgentStudioTests/Features/CommandBar/CommandBarAppModeTests.swift`

- [ ] **Step 1: Write failing tests for `WorkspaceFocusContextAtom` naming and behavior**

Add tests that assert:
- `WorkspaceFocusContextAtom().currentFocus` starts with no active pane context
- recomputing from an empty `WorkspaceStore` leaves `currentFocus` empty
- recomputing from a store with an active terminal tab produces `hasActiveTab`, `hasActivePane`, and `.terminal`
- drawer / arrangement / multi-pane requirements are reflected in `currentFocus`

- [ ] **Step 2: Run the focused test suite and verify it fails**

Run: `SWIFT_BUILD_DIR=.build-agent-focus swift test --build-path "$SWIFT_BUILD_DIR" --filter "WorkspaceFocusContext" > /tmp/workspace-focus-context-tests.txt 2>&1; echo $?`

Expected: non-zero exit with missing type/member errors referencing `WorkspaceFocusContextAtom` or `currentFocus`

### Task 2: Implement `WorkspaceFocusContextAtom`

**Files:**
- Create: `Sources/AgentStudio/Core/State/MainActor/Atoms/WorkspaceFocusContextAtom.swift`
- Modify: `Sources/AgentStudio/Infrastructure/AtomLib/AtomStore.swift`
- Modify: `Sources/AgentStudio/App/Boot/AppDelegate.swift`

- [ ] **Step 1: Add the new atom type**

Create a focused atom with:
- `private(set) var currentFocus: WorkspaceFocus`
- a recompute API that projects from `WorkspaceStore`
- a default empty focus value for initial app state

- [ ] **Step 2: Wire the atom into `AtomStore`**

Expose `workspaceFocusContext` alongside the other app-wide atoms and derived helpers.

- [ ] **Step 3: Seed and refresh the atom during app boot**

Update app boot wiring so the atom reflects the restored workspace state before command bar / menu consumers use it.

- [ ] **Step 4: Run the focused test suite and verify it passes**

Run: `SWIFT_BUILD_DIR=.build-agent-focus swift test --build-path "$SWIFT_BUILD_DIR" --filter "WorkspaceFocusContext" > /tmp/workspace-focus-context-tests.txt 2>&1; echo $?`

Expected: `0`

### Task 3: Migrate focus consumers to the shared atom path

**Files:**
- Modify: `Sources/AgentStudio/Features/CommandBar/CommandBarDataSource.swift`
- Modify: `Sources/AgentStudio/Features/CommandBar/Views/CommandBarView.swift`
- Modify: `Sources/AgentStudio/App/Boot/AppDelegate.swift`
- Modify: `Tests/AgentStudioTests/Features/CommandBar/CommandBarDataSourceTests.swift`

- [ ] **Step 1: Update command bar consumers**

Switch command bar item building and status-strip context reads from direct `WorkspaceStore` focus computation to `atom(\.workspaceFocusContext).currentFocus`.

- [ ] **Step 2: Update menu validation**

Switch menu visibility checks to the same atom-backed `currentFocus` path so menus and command bar share one focus context source.

- [ ] **Step 3: Add or update tests proving consumers still filter correctly**

Extend command-bar data-source tests to verify command visibility still responds to the focus snapshot after the consumer migration.

- [ ] **Step 4: Run focused command-bar tests and verify they pass**

Run: `SWIFT_BUILD_DIR=.build-agent-focus swift test --build-path "$SWIFT_BUILD_DIR" --filter "CommandBarDataSourceTests|WorkspaceFocus" > /tmp/command-bar-focus-tests.txt 2>&1; echo $?`

Expected: `0`

### Task 4: Full verification

**Files:**
- Modify: `Sources/AgentStudio/Core/State/MainActor/Atoms/WorkspaceFocusContextAtom.swift`
- Modify: `Sources/AgentStudio/Infrastructure/AtomLib/AtomStore.swift`
- Modify: `Sources/AgentStudio/Features/CommandBar/CommandBarDataSource.swift`
- Modify: `Sources/AgentStudio/Features/CommandBar/Views/CommandBarView.swift`
- Modify: `Sources/AgentStudio/App/Boot/AppDelegate.swift`
- Modify: `Tests/AgentStudioTests/Features/CommandBar/CommandBarAppModeTests.swift`
- Modify: `Tests/AgentStudioTests/Features/CommandBar/CommandBarDataSourceTests.swift`

- [ ] **Step 1: Run the full test suite**

Run: `mise run test`

Expected: exit code `0`

- [ ] **Step 2: Run lint**

Run: `mise run lint`

Expected: exit code `0`

- [ ] **Step 3: Review for stale names and dead code**

Confirm old direct focus-computation call sites were removed or reduced to the atom implementation seam only.
