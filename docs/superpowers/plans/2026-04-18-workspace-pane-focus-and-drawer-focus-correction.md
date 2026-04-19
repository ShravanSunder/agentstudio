# Workspace Pane Focus And Drawer Focus Correction Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make drawer focus ownership canonical so an open drawer always owns focus, an open drawer with an active pane focuses that pane, and closing the drawer reliably returns focus to the main pane.

**Architecture:** Promote the existing three-state navigation scope into the one canonical mutable focus-owner state with three legal states: `mainPane`, `emptyDrawer`, and `drawerPane`. Add a focus normalizer/validator layer that turns requested focus transitions plus visible drawer state into one valid canonical state, then derive `WorkspacePaneFocus` from that normalized state and drive responder application, keyboard routing, and command visibility from the same source of truth.

**Tech Stack:** Swift 6.2, AppKit, SwiftUI, Observation, Swift Testing, existing `PaneFocusOrchestrator` / `PaneFocusExecutor`, atom-bound app state

---

## Why The Previous Plan Was Incomplete

```text
┌──────────────────────────────────────┬──────────────────────────────────────┐
│ Missing piece                        │ Consequence                          │
├──────────────────────────────────────┼──────────────────────────────────────┤
│ Drawer open as focus transition      │ drawer could open while main pane    │
│                                      │ still owned responder focus          │
├──────────────────────────────────────┼──────────────────────────────────────┤
│ Empty drawer as real focus target    │ `d` depended on synthetic scope      │
│                                      │ instead of real focus ownership      │
├──────────────────────────────────────┼──────────────────────────────────────┤
│ Single canonical focus-owner state   │ responder, routing, and visibility   │
│                                      │ could drift apart                    │
├──────────────────────────────────────┼──────────────────────────────────────┤
│ Focus normalizer / validator layer   │ stale drawer focus could survive     │
│                                      │ close/remove/detach transitions      │
└──────────────────────────────────────┴──────────────────────────────────────┘
```

## Required Invariant

```text
┌──────────────────────────────────────────────────────────────┐
│ If drawer is open, main pane is not focused.                │
│                                                              │
│ drawer open + empty      -> emptyDrawer focus               │
│ drawer open + active     -> drawerPane focus                │
│ drawer closed            -> mainPane focus                  │
└──────────────────────────────────────────────────────────────┘
```

## Canonical State Machine

```text
S0 MainPaneFocused
   owner = main pane
   drawer closed

   open drawer
   ├─ empty drawer       -> S1
   └─ active drawer pane -> S2


S1 EmptyDrawerFocused
   owner = drawer domain
   drawer open, empty

   create/select first pane -> S2
   close drawer             -> S0


S2 DrawerPaneFocused
   owner = active drawer pane
   drawer open, active pane exists

   change drawer pane       -> S2
   remove/detach active     -> S1 or S2
   close drawer             -> S0
```

## Full Matrix

```text
┌──────────────────────────────┬──────────────────────┬──────────────────────┬──────────────────────────────┐
│ Visible state                │ Canonical state      │ Focus owner          │ Keyboard semantics           │
├──────────────────────────────┼──────────────────────┼──────────────────────┼──────────────────────────────┤
│ Drawer closed                │ mainPane             │ main pane            │ main-pane navigation         │
├──────────────────────────────┼──────────────────────┼──────────────────────┼──────────────────────────────┤
│ Drawer open, empty           │ emptyDrawer          │ drawer domain        │ `d` works, no main fallback  │
├──────────────────────────────┼──────────────────────┼──────────────────────┼──────────────────────────────┤
│ Drawer open, active pane     │ drawerPane           │ active drawer pane   │ `⌥IJKL` move in drawer       │
├──────────────────────────────┼──────────────────────┼──────────────────────┼──────────────────────────────┤
│ Drawer closes from S1        │ mainPane             │ main pane            │ main-pane routing resumes    │
├──────────────────────────────┼──────────────────────┼──────────────────────┼──────────────────────────────┤
│ Drawer closes from S2        │ mainPane             │ main pane            │ main-pane routing resumes    │
└──────────────────────────────┴──────────────────────┴──────────────────────┴──────────────────────────────┘
```

## Carry-Forward From The 2026-04-17 Plan

```text
┌────────────────────────────────────┬──────────────────────┬─────────────────────────────┐
│ Original requirement               │ Status here          │ Covered by                  │
├────────────────────────────────────┼──────────────────────┼─────────────────────────────┤
│ Drawer-only boundary               │ preserve + verify    │ Tasks 4, 6                 │
├────────────────────────────────────┼──────────────────────┼─────────────────────────────┤
│ `⌥IJKL` scope rules                │ correct fully        │ Tasks 3, 5                 │
├────────────────────────────────────┼──────────────────────┼─────────────────────────────┤
│ Empty drawer create rules          │ correct fully        │ Tasks 3, 5                 │
├────────────────────────────────────┼──────────────────────┼─────────────────────────────┤
│ Empty drawer keeps parent focus    │ intentionally        │ replaced by drawer-owned   │
│                                    │ changed              │ focus model                │
├────────────────────────────────────┼──────────────────────┼─────────────────────────────┤
│ Detach to parent-right             │ preserve + verify    │ Tasks 4, 6                 │
├────────────────────────────────────┼──────────────────────┼─────────────────────────────┤
│ Detach button                      │ preserve + verify    │ Tasks 4, 6                 │
├────────────────────────────────────┼──────────────────────┼─────────────────────────────┤
│ Reject third row at validator      │ preserve + verify    │ Tasks 4, 6                 │
├────────────────────────────────────┼──────────────────────┼─────────────────────────────┤
│ Drawer open means drawer has focus │ newly explicit       │ Tasks 2, 3, 5             │
└────────────────────────────────────┴──────────────────────┴─────────────────────────────┘
```

## File Structure

```text
Create:
- Sources/AgentStudio/Infrastructure/PaneFocus/WorkspaceFocusOwnerNormalizer.swift
- Tests/AgentStudioTests/Core/State/MainActor/Atoms/WorkspaceFocusOwnerAtomTests.swift
- Tests/AgentStudioTests/App/PaneTabViewControllerDrawerFocusStateMachineTests.swift

Rename:
- Sources/AgentStudio/Core/State/MainActor/Atoms/WorkspaceNavigationScopeAtom.swift -> Sources/AgentStudio/Core/State/MainActor/Atoms/WorkspaceFocusOwnerAtom.swift
- Sources/AgentStudio/Core/State/MainActor/Atoms/WorkspaceFocus.swift -> Sources/AgentStudio/Core/State/MainActor/Atoms/WorkspacePaneFocus.swift

Already present, modify in place:
- Sources/AgentStudio/Core/State/MainActor/Atoms/WorkspacePaneFocus.swift
- Sources/AgentStudio/Core/State/MainActor/Atoms/WorkspacePaneFocusDerived.swift
- Tests/AgentStudioTests/Core/State/MainActor/Atoms/WorkspacePaneFocusDerivedTests.swift

Delete:
- Sources/AgentStudio/Core/State/MainActor/Atoms/WorkspaceFocusDerived.swift

Modify:
- Sources/AgentStudio/Infrastructure/AtomLib/AtomRegistry.swift
- Sources/AgentStudio/App/Commands/AppCommand+Catalog.swift
- Sources/AgentStudio/App/Panes/PaneTabViewController.swift
- Sources/AgentStudio/App/Panes/PaneFocusExecutor.swift
- Sources/AgentStudio/Infrastructure/PaneFocus/PaneFocusContext.swift
- Sources/AgentStudio/Infrastructure/PaneFocus/PaneDrawerFocusDecider.swift
- Sources/AgentStudio/Infrastructure/PaneFocus/PaneModeFocusDecider.swift
- Sources/AgentStudio/Infrastructure/PaneFocus/PaneRefocusRequestFocusDecider.swift
- Sources/AgentStudio/Core/Actions/ActionValidator.swift
- Sources/AgentStudio/App/Coordination/PaneCoordinator+ActionExecution.swift
- Sources/AgentStudio/Features/CommandBar/CommandBarDataSource.swift
- Sources/AgentStudio/Features/CommandBar/Views/CommandBarView.swift
- Sources/AgentStudio/Features/CommandBar/Views/CommandBarStatusStrip.swift
- Tests/AgentStudioTests/App/PaneTabViewControllerCommandTests.swift
- Tests/AgentStudioTests/App/Panes/Focus/PaneFocusExecutorTests.swift
- Tests/AgentStudioTests/Core/Views/WorkspaceFocusDerivedTests.swift
- Tests/AgentStudioTests/Features/CommandBar/CommandBarAppModeTests.swift
```

## Canonical Types

```swift
enum WorkspaceFocusOwner: Equatable, Sendable {
    case mainPane(paneId: UUID?)
    case emptyDrawer(parentPaneId: UUID)
    case drawerPane(parentPaneId: UUID, paneId: UUID)
}

@MainActor
@Observable
final class WorkspaceFocusOwnerAtom {
    private(set) var owner: WorkspaceFocusOwner = .mainPane(paneId: nil)

    func focusMainPane(_ paneId: UUID?) { owner = .mainPane(paneId: paneId) }
    func focusEmptyDrawer(parentPaneId: UUID) { owner = .emptyDrawer(parentPaneId: parentPaneId) }
    func focusDrawerPane(parentPaneId: UUID, paneId: UUID) {
        owner = .drawerPane(parentPaneId: parentPaneId, paneId: paneId)
    }
}
```

```text
Normalizer contract
  input:
    • requested WorkspaceFocusOwner
    • activeTabId
    • active main-pane id
    • parent drawer visible/expanded state
    • drawer pane membership
    • active drawer pane id
    • minimized drawer pane ids

  output:
    • one legal WorkspaceFocusOwner

  execution:
    • on every write transition into the atom
    • re-used at read time by WorkspacePaneFocusDerived as a defensive projection
```

```swift
struct WorkspacePaneFocus: Equatable, Sendable {
    enum DrawerFocusState: Equatable, Sendable {
        case inactive
        case emptyDrawer(parentPaneId: UUID)
        case drawerPane(parentPaneId: UUID, paneId: UUID)
    }

    let activeTabId: UUID?
    let activePaneId: UUID?
    let activeRepoId: UUID?
    let activeWorktreeId: UUID?
    let paneContentType: ContentType
    let drawerFocusState: DrawerFocusState
    let satisfiedRequirements: Set<FocusRequirement>
}
```

## Naming Decision

```text
Decision:
  Rename `WorkspaceNavigationScopeAtom`
  -> `WorkspaceFocusOwnerAtom`

Reason:
  Its responsibility is not generic “navigation scope”.
  Its responsibility is the single canonical mutable owner of workspace focus.

One-sentence responsibility:
  `WorkspaceFocusOwnerAtom` owns who currently has workspace focus:
  main pane, empty drawer, or active drawer pane.
```

## Task 1: Introduce The Canonical Focus-Owner State

**Files:**
- Rename: `Sources/AgentStudio/Core/State/MainActor/Atoms/WorkspaceNavigationScopeAtom.swift` -> `Sources/AgentStudio/Core/State/MainActor/Atoms/WorkspaceFocusOwnerAtom.swift`
- Create: `Sources/AgentStudio/Infrastructure/PaneFocus/WorkspaceFocusOwnerNormalizer.swift`
- Modify: `Sources/AgentStudio/Infrastructure/AtomLib/AtomRegistry.swift`
- Test: `Tests/AgentStudioTests/Core/State/MainActor/Atoms/WorkspaceFocusOwnerAtomTests.swift`

- [ ] Write failing tests for the three legal focus-owner states and basic state transitions using the existing scope atom shape as the baseline.
- [ ] Run the focused tests and verify they fail for the missing `WorkspaceFocusOwnerNormalizer` and missing canonical-write normalization behavior.
- [ ] Rename the existing scope atom to `WorkspaceFocusOwnerAtom` and implement the normalizer as the single canonical transition gate.
- [ ] Re-run the focused tests and verify they pass.
- [ ] Commit this slice.

## Task 2: Finish The `WorkspacePaneFocus` Cutover And Derive It From Canonical Ownership

**Files:**
- Modify: `Sources/AgentStudio/Core/State/MainActor/Atoms/WorkspacePaneFocus.swift`
- Modify: `Sources/AgentStudio/Core/State/MainActor/Atoms/WorkspacePaneFocusDerived.swift`
- Modify: `Sources/AgentStudio/Features/CommandBar/CommandBarDataSource.swift`
- Modify: `Sources/AgentStudio/Features/CommandBar/Views/CommandBarView.swift`
- Modify: `Sources/AgentStudio/Features/CommandBar/Views/CommandBarStatusStrip.swift`
- Test: `Tests/AgentStudioTests/Core/Views/WorkspaceFocusDerivedTests.swift`
- Test: `Tests/AgentStudioTests/Features/CommandBar/CommandBarAppModeTests.swift`

- [ ] Write failing projection tests for `inactive`, `emptyDrawer`, and `drawerPane`, plus stale-scope fallback behavior.
- [ ] Run the focused tests and verify they fail against the partially-canonical current snapshot behavior.
- [ ] Tighten `WorkspacePaneFocus` and `WorkspacePaneFocusDerived` so they consume normalized canonical focus ownership and no longer trust stale raw scope.
- [ ] Re-run the focused tests and verify they pass.
- [ ] Commit this slice.

## Task 3: Make Drawer Open And Close Real Focus Transitions

**Files:**
- Modify: `Sources/AgentStudio/App/Panes/PaneTabViewController.swift`
- Modify: `Sources/AgentStudio/Infrastructure/PaneFocus/PaneDrawerFocusDecider.swift`
- Modify: `Sources/AgentStudio/Infrastructure/PaneFocus/PaneModeFocusDecider.swift`
- Modify: `Sources/AgentStudio/Infrastructure/PaneFocus/PaneRefocusRequestFocusDecider.swift`
- Modify: `Sources/AgentStudio/App/Panes/PaneFocusExecutor.swift`
- Test: `Tests/AgentStudioTests/App/PaneTabViewControllerDrawerFocusStateMachineTests.swift`
- Test: `Tests/AgentStudioTests/App/Panes/Focus/PaneFocusExecutorTests.swift`

- [ ] Write failing tests for:
  - open empty drawer -> `emptyDrawer`
  - open drawer with pane -> `drawerPane`
  - close drawer -> `mainPane`
  - create first drawer pane -> `drawerPane`
  - `window.firstResponder` changes to drawer-owned responder when empty drawer opens
  - `window.firstResponder` returns to main-pane responder when drawer closes
- [ ] Run the focused tests and verify they fail for the current mixed focus paths.
- [ ] Implement drawer-open and drawer-close as canonical focus transitions, and make responder application match the normalized focus owner.
- [ ] Explicit responder contract:
  - `emptyDrawer(parentPaneId)` -> clear first responder away from pane content to the window content / drawer neutral context owned by the drawer shell
  - `mainPane(paneId)` after drawer close -> focus the parent main-pane host or mounted content according to existing pane-focus rules
- [ ] Re-run the focused tests and verify they pass.
- [ ] Commit this slice.

## Task 4: Move Command Visibility, Routing, And Validation Onto The New Focus Model

**Files:**
- Modify: `Sources/AgentStudio/App/Commands/AppCommand+Catalog.swift`
- Modify: `Sources/AgentStudio/Core/Actions/ActionValidator.swift`
- Modify: `Sources/AgentStudio/App/Coordination/PaneCoordinator+ActionExecution.swift`
- Modify: `Sources/AgentStudio/App/Panes/PaneTabViewController.swift`
- Test: `Tests/AgentStudioTests/App/PaneTabViewControllerCommandTests.swift`
- Test: `Tests/AgentStudioTests/Core/Actions/ActionValidatorTests.swift`
- Test: `Tests/AgentStudioTests/Core/Actions/ActionValidatorOwnershipTests.swift`

- [ ] Write failing tests for:
  - `d` only works in `emptyDrawer`
  - `⌥IJKL` drawer movement only works in `drawerPane`
  - stale drawer focus normalizes away on close/remove/detach
  - command visibility reflects `hasEmptyDrawerFocus` and `hasFocusedDrawerPane`
- [ ] Run the focused tests and verify they fail.
- [ ] Implement routing/visibility/validation against normalized focus ownership instead of raw controller-local state.
- [ ] Re-run the focused tests and verify they pass.
- [ ] Commit this slice.

## Task 5: Re-Verify Drawer Boundary, Detach, And Management-Layer Integration

**Files:**
- Modify if required by failing tests:
  - `Sources/AgentStudio/Core/Views/Drawer/DrawerPanel.swift`
  - `Sources/AgentStudio/App/Lifecycle/ManagementLayerMonitor.swift`
  - `Sources/AgentStudio/Core/Actions/DrawerCommandValidator.swift`
  - `Sources/AgentStudio/App/Coordination/PaneCoordinator+ActionExecution.swift`
- Test:
  - `Tests/AgentStudioTests/App/ManagementLayerTests.swift`
  - `Tests/AgentStudioTests/Core/Actions/DrawerCommandIntegrationTests.swift`
  - `Tests/AgentStudioTests/Core/Actions/PaneDropPlannerTests.swift`

- [ ] Re-run the drawer-only boundary suites after the focus-owner cutover.
- [ ] If drawer-only drag/drop, management-layer pass-through, detach-right-of-parent, or validator tests regress, fix them without widening the architecture again.
- [ ] Re-run those suites and verify they pass.
- [ ] Commit only if code changed.

## Task 6: Final Verification

**Files:**
- No code changes expected

- [ ] Run focused focus/drawer suites:

```bash
swift test --build-path .build-agent-workspace-pane-focus \
  --filter 'PaneTabViewControllerCommandTests|PaneTabViewControllerDrawerFocusStateMachineTests|PaneFocusExecutorTests|WorkspacePaneFocusDerivedTests|ActionValidatorTests|ActionValidatorOwnershipTests|ManagementLayerTests|DrawerCommandIntegrationTests'
```

- [ ] Run full repo tests:

```bash
AGENT_RUN_ID=workspace-pane-focus-cutover mise run test
```

- [ ] Run lint:

```bash
AGENT_RUN_ID=workspace-pane-focus-cutover mise run lint
```

- [ ] Run visual verification for the focus transitions:
  - open empty drawer -> drawer has focus
  - create first drawer pane -> drawer pane has focus
  - close drawer -> main pane has focus

- [ ] If all checks pass, stop and report the exact evidence.

## Definition Of Done For This Plan

```text
1. Opening a drawer is a focus transition.
2. Open empty drawer owns focus.
3. Open drawer with active pane focuses that pane.
4. Closing the drawer returns focus to main pane.
5. `d` works from the real empty-drawer path.
6. `⌥IJKL` only use drawer movement in drawer-pane focus.
7. Command visibility and validators read normalized canonical focus state.
8. Full repo test and lint are green.
```
