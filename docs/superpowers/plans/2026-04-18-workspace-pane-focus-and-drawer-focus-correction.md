# Workspace Pane Focus And Drawer Focus Correction Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rename `WorkspaceFocus` to `WorkspacePaneFocus` and make drawer focus a first-class part of the workspace pane-focus model so open-empty drawers, selected drawer panes, command visibility, and `⌥IJKL` routing all agree.

**Architecture:** Introduce one canonical workspace navigation scope atom that represents `mainPane`, `emptyDrawer`, and `drawerPane` focus ownership. `WorkspacePaneFocusDerived` will project the app-wide `WorkspacePaneFocus` snapshot from tab/pane atoms plus that scope atom, and `PaneTabViewController` plus the pane-focus executor will mutate the shared scope instead of carrying controller-local focus assumptions. This is a hard cutover: no `WorkspaceFocus` compatibility type, no duplicate keyboard drawer scope, and no shared main-pane routing inside the drawer boundary.

**Tech Stack:** Swift 6.2, AppKit, SwiftUI, Observation, Swift Testing, existing `PaneFocusOrchestrator` / `PaneFocusExecutor`, atom-bound app state

---

## Execution Gate

Do **not** start implementation from this plan until all drawer/focus correction scope is represented here.

Implementation may start only when all three are true:

1. every required item from `2026-04-17-drawer-navigation-and-detach.md` is mapped to:
   - already implemented and preserved
   - a task in this plan
   - or an explicit defer with reason
2. the remaining re-review issues that are relevant to the focus/drawer boundary are either:
   - folded into a task here
   - or explicitly marked out of scope
3. the engineer doing the work agrees to execute this plan as the single source of truth rather than mixing chat-only requirements and partial implementation memory

If any drawer/focus requirement is still being discussed but does not yet have a plan row or task reference, stop planning and add it before implementation starts.

## Carry-Forward Matrix From The 2026-04-17 Drawer Plan

This plan supersedes nothing silently. Every relevant requirement from [2026-04-17-drawer-navigation-and-detach.md](/Users/shravansunder/Documents/dev/project-dev/agent-studio.drawer-improvements/docs/superpowers/plans/2026-04-17-drawer-navigation-and-detach.md) must map to one of:

1. preserved as already-correct code
2. explicitly corrected by a task in this plan
3. explicitly deferred with a reason

```text
┌────────────────────────────────────┬──────────────────────┬─────────────────────────────┐
│ Original requirement               │ Status here          │ Proof / task                │
├────────────────────────────────────┼──────────────────────┼─────────────────────────────┤
│ Drawer-only boundary               │ corrected            │ Tasks 2, 3, 4              │
├────────────────────────────────────┼──────────────────────┼─────────────────────────────┤
│ `⌥IJKL` scope rules                │ corrected            │ Task 2                      │
├────────────────────────────────────┼──────────────────────┼─────────────────────────────┤
│ Empty drawer create rules          │ corrected            │ Task 2                      │
├────────────────────────────────────┼──────────────────────┼─────────────────────────────┤
│ Empty drawer keeps parent focus    │ intentionally        │ Replaced by new focus model │
│                                    │ changed              │ in Task 2                   │
├────────────────────────────────────┼──────────────────────┼─────────────────────────────┤
│ Detach to parent-right             │ preserved + verify   │ Task 3                      │
├────────────────────────────────────┼──────────────────────┼─────────────────────────────┤
│ Detach button                      │ preserved + verify   │ Task 4                      │
├────────────────────────────────────┼──────────────────────┼─────────────────────────────┤
│ Reject third row at validator      │ corrected            │ Task 3                      │
├────────────────────────────────────┼──────────────────────┼─────────────────────────────┤
│ Main-pane semantics unchanged      │ preserve + verify    │ Tasks 2, 5                  │
├────────────────────────────────────┼──────────────────────┼─────────────────────────────┤
│ Top/bottom rearrange reachable     │ preserve + verify    │ Tasks 4, 5                  │
├────────────────────────────────────┼──────────────────────┼─────────────────────────────┤
│ `navigateDrawerPane` stays         │ preserve             │ Task 1                      │
│ command-bar-targeted               │                      │                             │
└────────────────────────────────────┴──────────────────────┴─────────────────────────────┘
```

## Re-Review Items Folded Into This Plan

Relevant findings from the follow-up review are intentionally covered here:

```text
┌────────────────────────────────────────────┬──────────────────────────────────────┐
│ Review item                                │ Covered by                           │
├────────────────────────────────────────────┼──────────────────────────────────────┤
│ Detach arrangement suitability validation  │ Task 3                              │
├────────────────────────────────────────────┼──────────────────────────────────────┤
│ `managementLayerNavigationScope` misleading│ Task 4                              │
│ name                                        │                                      │
├────────────────────────────────────────────┼──────────────────────────────────────┤
│ Validator gate should be directly tested    │ Task 3                              │
├────────────────────────────────────────────┼──────────────────────────────────────┤
│ Drawer drag top/bottom needs visual proof   │ Task 5                              │
└────────────────────────────────────────────┴──────────────────────────────────────┘
```

Explicitly deferred from the review because they are polish, not blockers for the focus cutover:

```text
┌──────────────────────────────────────┬──────────────────────────────────────┐
│ Deferred item                        │ Reason                               │
├──────────────────────────────────────┼──────────────────────────────────────┤
│ Row-split resize UI                  │ UX enhancement beyond focus/model    │
│                                      │ correction                           │
├──────────────────────────────────────┼──────────────────────────────────────┤
│ Row-gap drop affordance polish       │ Nice-to-have; top/bottom targeting   │
│                                      │ is already reachable                 │
├──────────────────────────────────────┼──────────────────────────────────────┤
│ Add-pane row placement policy docs   │ Documentation/policy clarification   │
│                                      │ only                                 │
└──────────────────────────────────────┴──────────────────────────────────────┘
```

## File Structure

```text
Create:
- Sources/AgentStudio/Core/State/MainActor/Atoms/WorkspaceNavigationScopeAtom.swift
- Sources/AgentStudio/Core/State/MainActor/Atoms/WorkspacePaneFocus.swift
- Sources/AgentStudio/Core/State/MainActor/Atoms/WorkspacePaneFocusDerived.swift
- Tests/AgentStudioTests/Core/State/MainActor/Atoms/WorkspaceNavigationScopeAtomTests.swift
- Tests/AgentStudioTests/Core/State/MainActor/Atoms/WorkspacePaneFocusDerivedTests.swift

Delete:
- Sources/AgentStudio/Core/State/MainActor/Atoms/WorkspaceFocus.swift
- Sources/AgentStudio/Core/State/MainActor/Atoms/WorkspaceFocusDerived.swift

Modify:
- Sources/AgentStudio/Infrastructure/AtomLib/AtomRegistry.swift
- Sources/AgentStudio/App/Commands/AppCommand+Definitions.swift
- Sources/AgentStudio/App/Panes/PaneTabViewController.swift
- Sources/AgentStudio/App/Panes/PaneFocusExecutor.swift
- Sources/AgentStudio/App/Coordination/PaneCoordinator+ActionExecution.swift
- Sources/AgentStudio/Infrastructure/PaneFocus/PaneFocusContext.swift
- Sources/AgentStudio/Core/Views/Drawer/DrawerPanel.swift
- Sources/AgentStudio/Core/Actions/ActionValidator.swift
- Sources/AgentStudio/Core/Actions/DrawerCommandValidator.swift
- Sources/AgentStudio/Features/CommandBar/Views/CommandBarStatusStrip.swift
- Sources/AgentStudio/Features/CommandBar/Views/CommandBarView.swift
- Sources/AgentStudio/Features/CommandBar/CommandBarDataSource.swift
- Tests/AgentStudioTests/App/PaneTabViewControllerCommandTests.swift
- Tests/AgentStudioTests/App/PaneTabViewControllerDropRoutingTests.swift
- Tests/AgentStudioTests/Core/Actions/ActionValidatorTests.swift
- Tests/AgentStudioTests/Core/Actions/ActionValidatorOwnershipTests.swift
- Tests/AgentStudioTests/Core/Actions/PaneDropPlannerTests.swift
- Tests/AgentStudioTests/Core/Views/WorkspaceFocusDerivedTests.swift
- Tests/AgentStudioTests/Features/CommandBar/CommandBarAppModeTests.swift
```

```text
┌──────────────────────────────────────────────────────────────┐
│ Canonical focus ownership                                   │
│                                                              │
│  WorkspaceNavigationScopeAtom                                │
│    • mainPane(paneId)                                        │
│    • emptyDrawer(parentPaneId)                               │
│    • drawerPane(parentPaneId, drawerPaneId)                  │
│                                                              │
│             ▼ used by                                        │
│                                                              │
│  WorkspacePaneFocusDerived                                   │
│    • app-wide summary for command bar / command visibility   │
│                                                              │
│             ▼ read by                                         │
│                                                              │
│  CommandBarView / CommandBarStatusStrip / CommandSpecs       │
│  PaneTabViewController keyboard routing                      │
└──────────────────────────────────────────────────────────────┘
```

## Canonical Type Shape

All later tasks assume these exact types:

```swift
import Foundation

enum WorkspaceNavigationScope: Equatable, Sendable {
    case mainPane(paneId: UUID?)
    case emptyDrawer(parentPaneId: UUID)
    case drawerPane(parentPaneId: UUID, paneId: UUID)
}

@MainActor
@Observable
final class WorkspaceNavigationScopeAtom {
    private(set) var scope: WorkspaceNavigationScope = .mainPane(paneId: nil)

    func focusMainPane(_ paneId: UUID?) {
        scope = .mainPane(paneId: paneId)
    }

    func focusEmptyDrawer(parentPaneId: UUID) {
        scope = .emptyDrawer(parentPaneId: parentPaneId)
    }

    func focusDrawerPane(parentPaneId: UUID, paneId: UUID) {
        scope = .drawerPane(parentPaneId: parentPaneId, paneId: paneId)
    }
}
```

```swift
import Foundation

enum FocusRequirement: Hashable, CaseIterable, Sendable {
    case hasActiveTab
    case hasActivePane
    case hasMultiplePanes
    case hasDrawer
    case hasDrawerPanes
    case hasEmptyDrawerFocus
    case hasFocusedDrawerPane
    case hasMultipleTabs
    case hasArrangements
    case paneIsTerminal
    case paneIsWebview
    case paneIsBridge
    case paneIsCodeViewer
}

struct WorkspacePaneFocus: Equatable, Sendable {
    enum ContentType: Equatable, Sendable {
        case terminal
        case webview
        case bridge
        case codeViewer
        case unsupported
        case noActivePane
    }

    enum DrawerFocusState: Equatable, Sendable {
        case none
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

### Task 1: Rename `WorkspaceFocus` To `WorkspacePaneFocus` And Add Drawer Focus State

**Files:**
- Create: `Sources/AgentStudio/Core/State/MainActor/Atoms/WorkspacePaneFocus.swift`
- Create: `Sources/AgentStudio/Core/State/MainActor/Atoms/WorkspacePaneFocusDerived.swift`
- Delete: `Sources/AgentStudio/Core/State/MainActor/Atoms/WorkspaceFocus.swift`
- Delete: `Sources/AgentStudio/Core/State/MainActor/Atoms/WorkspaceFocusDerived.swift`
- Modify: `Sources/AgentStudio/Infrastructure/AtomLib/AtomRegistry.swift`
- Modify: `Sources/AgentStudio/App/Commands/AppCommand+Definitions.swift`
- Modify: `Sources/AgentStudio/Features/CommandBar/Views/CommandBarStatusStrip.swift`
- Modify: `Sources/AgentStudio/Features/CommandBar/Views/CommandBarView.swift`
- Modify: `Sources/AgentStudio/Features/CommandBar/CommandBarDataSource.swift`
- Modify: `Tests/AgentStudioTests/Core/Views/WorkspaceFocusDerivedTests.swift`
- Modify: `Tests/AgentStudioTests/Features/CommandBar/CommandBarAppModeTests.swift`

- [ ] **Step 1: Write the failing projection tests**

```swift
import Foundation
import Testing

@testable import AgentStudio

@Suite(.serialized)
@MainActor
struct WorkspacePaneFocusDerivedTests {
    @Test("expanded empty drawer projects empty drawer focus")
    func expandedEmptyDrawer_projectsEmptyDrawerFocus() {
        let workspaceTabLayout = WorkspaceTabLayoutAtom()
        let workspacePane = WorkspacePaneAtom()
        let navigationScope = WorkspaceNavigationScopeAtom()

        let pane = workspacePane.createPane(source: .floating(launchDirectory: nil, title: "Parent"))
        let tab = Tab(paneId: pane.id)
        workspaceTabLayout.appendTab(tab)
        workspaceTabLayout.setActiveTab(tab.id)
        workspaceTabLayout.setActivePane(pane.id, inTab: tab.id)
        workspacePane.toggleDrawer(for: pane.id)
        navigationScope.focusEmptyDrawer(parentPaneId: pane.id)

        let focus = WorkspacePaneFocusDerived().currentFocus(
            workspaceTabLayout: workspaceTabLayout,
            workspacePane: workspacePane,
            workspaceNavigationScope: navigationScope
        )

        #expect(focus.activePaneId == pane.id)
        #expect(focus.drawerFocusState == .emptyDrawer(parentPaneId: pane.id))
        #expect(focus.satisfiedRequirements.contains(.hasDrawer))
        #expect(focus.satisfiedRequirements.contains(.hasEmptyDrawerFocus))
        #expect(!focus.satisfiedRequirements.contains(.hasDrawerPanes))
    }

    @Test("selected drawer pane projects focused drawer pane")
    func selectedDrawerPane_projectsDrawerPaneFocus() throws {
        let workspaceTabLayout = WorkspaceTabLayoutAtom()
        let workspacePane = WorkspacePaneAtom()
        let navigationScope = WorkspaceNavigationScopeAtom()

        let parent = workspacePane.createPane(source: .floating(launchDirectory: nil, title: "Parent"))
        let tab = Tab(paneId: parent.id)
        workspaceTabLayout.appendTab(tab)
        workspaceTabLayout.setActiveTab(tab.id)
        workspaceTabLayout.setActivePane(parent.id, inTab: tab.id)
        let drawerPane = try #require(
            workspacePane.addDrawerPane(to: parent.id, parentFallbackCWD: nil)
        )
        workspacePane.setActiveDrawerPane(drawerPane.id, in: parent.id)
        navigationScope.focusDrawerPane(parentPaneId: parent.id, paneId: drawerPane.id)

        let focus = WorkspacePaneFocusDerived().currentFocus(
            workspaceTabLayout: workspaceTabLayout,
            workspacePane: workspacePane,
            workspaceNavigationScope: navigationScope
        )

        #expect(focus.drawerFocusState == .drawerPane(parentPaneId: parent.id, paneId: drawerPane.id))
        #expect(focus.satisfiedRequirements.contains(.hasDrawerPanes))
        #expect(focus.satisfiedRequirements.contains(.hasFocusedDrawerPane))
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run:

```bash
swift test --build-path .build-agent-workspace-pane-focus \
  --filter 'WorkspacePaneFocusDerivedTests|WorkspaceFocusTests|WorkspaceFocusDerivedProjectionTests'
```

Expected:

```text
FAIL because WorkspacePaneFocus / WorkspacePaneFocusDerived / WorkspaceNavigationScopeAtom do not exist yet
```

- [ ] **Step 3: Write the renamed focus types and command-bar call-site updates**

```swift
// Sources/AgentStudio/Core/State/MainActor/Atoms/WorkspacePaneFocus.swift
import Foundation

enum FocusRequirement: Hashable, CaseIterable, Sendable {
    case hasActiveTab
    case hasActivePane
    case hasMultiplePanes
    case hasDrawer
    case hasDrawerPanes
    case hasEmptyDrawerFocus
    case hasFocusedDrawerPane
    case hasMultipleTabs
    case hasArrangements
    case paneIsTerminal
    case paneIsWebview
    case paneIsBridge
    case paneIsCodeViewer
}

struct WorkspacePaneFocus: Equatable, Sendable {
    enum ContentType: Equatable, Sendable {
        case terminal
        case webview
        case bridge
        case codeViewer
        case unsupported
        case noActivePane
    }

    enum DrawerFocusState: Equatable, Sendable {
        case none
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

    static let empty = Self(
        activeTabId: nil,
        activePaneId: nil,
        activeRepoId: nil,
        activeWorktreeId: nil,
        paneContentType: .noActivePane,
        drawerFocusState: .none,
        satisfiedRequirements: []
    )
}

extension CommandSpec {
    func isVisible(in focus: WorkspacePaneFocus) -> Bool {
        visibleWhen.isSubset(of: focus.satisfiedRequirements)
    }
}
```

```swift
// Sources/AgentStudio/Core/State/MainActor/Atoms/WorkspacePaneFocusDerived.swift
import Foundation

@MainActor
struct WorkspacePaneFocusDerived {
    func currentFocus(
        workspaceTabLayout: WorkspaceTabLayoutAtom,
        workspacePane: WorkspacePaneAtom,
        workspaceNavigationScope: WorkspaceNavigationScopeAtom
    ) -> WorkspacePaneFocus {
        var satisfiedRequirements: Set<FocusRequirement> = []

        guard
            let activeTabId = workspaceTabLayout.activeTabId,
            let tab = workspaceTabLayout.tab(activeTabId)
        else {
            return .empty
        }

        satisfiedRequirements.insert(.hasActiveTab)
        if workspaceTabLayout.tabs.count > 1 { satisfiedRequirements.insert(.hasMultipleTabs) }
        if tab.activePaneIds.count > 1 { satisfiedRequirements.insert(.hasMultiplePanes) }
        if tab.arrangements.count > 1 { satisfiedRequirements.insert(.hasArrangements) }

        guard let activePaneId = tab.activePaneId, let pane = workspacePane.pane(activePaneId) else {
            return WorkspacePaneFocus(
                activeTabId: activeTabId,
                activePaneId: nil,
                activeRepoId: nil,
                activeWorktreeId: nil,
                paneContentType: .noActivePane,
                drawerFocusState: .none,
                satisfiedRequirements: satisfiedRequirements
            )
        }

        satisfiedRequirements.insert(.hasActivePane)
        if pane.drawer != nil { satisfiedRequirements.insert(.hasDrawer) }
        if !(pane.drawer?.paneIds.isEmpty ?? true) { satisfiedRequirements.insert(.hasDrawerPanes) }

        let drawerFocusState: WorkspacePaneFocus.DrawerFocusState = switch workspaceNavigationScope.scope {
        case .mainPane:
            .none
        case .emptyDrawer(let parentPaneId):
            satisfiedRequirements.insert(.hasEmptyDrawerFocus)
            .emptyDrawer(parentPaneId: parentPaneId)
        case .drawerPane(let parentPaneId, let paneId):
            satisfiedRequirements.insert(.hasFocusedDrawerPane)
            .drawerPane(parentPaneId: parentPaneId, paneId: paneId)
        }

        let paneContentType: WorkspacePaneFocus.ContentType = switch pane.content {
        case .terminal: .terminal
        case .webview: .webview
        case .bridgePanel: .bridge
        case .codeViewer: .codeViewer
        case .unsupported: .unsupported
        }

        return WorkspacePaneFocus(
            activeTabId: activeTabId,
            activePaneId: activePaneId,
            activeRepoId: pane.repoId,
            activeWorktreeId: pane.worktreeId,
            paneContentType: paneContentType,
            drawerFocusState: drawerFocusState,
            satisfiedRequirements: satisfiedRequirements
        )
    }
}
```

```swift
// Sources/AgentStudio/Infrastructure/AtomLib/AtomRegistry.swift
@MainActor
final class AtomRegistry {
    let workspaceNavigationScope: WorkspaceNavigationScopeAtom

    init(
        workspaceNavigationScope: WorkspaceNavigationScopeAtom = .init()
    ) {
        self.workspaceNavigationScope = workspaceNavigationScope
    }

    var workspacePaneFocus: WorkspacePaneFocusDerived {
        WorkspacePaneFocusDerived()
    }
}
```

```swift
// Sources/AgentStudio/App/Commands/AppCommand+Definitions.swift
case .navigateDrawerPane:
    return CommandSpec(
        command: self,
        label: "Switch Drawer Pane",
        icon: "arrow.down.to.line",
        helpText: "Switch to a pane inside the active drawer",
        appliesTo: [.pane],
        visibleWhen: [.hasActivePane, .hasDrawerPanes],
        commandBarGroupName: "Pane",
        commandBarGroupPriority: CommandBarGroupPriority.pane
    )
```

```swift
// Sources/AgentStudio/Features/CommandBar/Views/CommandBarStatusStrip.swift
struct CommandBarStatusStrip: View {
    let mode: CommandBarAppMode
    let context: WorkspacePaneFocus
}
```

```swift
// Sources/AgentStudio/Features/CommandBar/Views/CommandBarView.swift
private var currentContext: WorkspacePaneFocus {
    atom(\.workspacePaneFocus).currentFocus(
        workspaceTabLayout: store.tabLayoutAtom,
        workspacePane: store.paneAtom,
        workspaceNavigationScope: atom(\.workspaceNavigationScope)
    )
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run:

```bash
swift test --build-path .build-agent-workspace-pane-focus \
  --filter 'WorkspacePaneFocusDerivedTests|WorkspaceFocusTests|WorkspaceFocusDerivedProjectionTests'
```

Expected:

```text
PASS
```

- [ ] **Step 5: Commit**

```bash
git add Sources/AgentStudio/Core/State/MainActor/Atoms/WorkspacePaneFocus.swift \
        Sources/AgentStudio/Core/State/MainActor/Atoms/WorkspacePaneFocusDerived.swift \
        Sources/AgentStudio/Core/State/MainActor/Atoms/WorkspaceNavigationScopeAtom.swift \
        Sources/AgentStudio/Infrastructure/AtomLib/AtomRegistry.swift \
        Sources/AgentStudio/Features/CommandBar/Views/CommandBarStatusStrip.swift \
        Sources/AgentStudio/Features/CommandBar/Views/CommandBarView.swift \
        Sources/AgentStudio/Features/CommandBar/CommandBarDataSource.swift \
        Tests/AgentStudioTests/Core/State/MainActor/Atoms/WorkspaceNavigationScopeAtomTests.swift \
        Tests/AgentStudioTests/Core/State/MainActor/Atoms/WorkspacePaneFocusDerivedTests.swift \
        Tests/AgentStudioTests/Core/Views/WorkspaceFocusDerivedTests.swift \
        Tests/AgentStudioTests/Features/CommandBar/CommandBarAppModeTests.swift
git commit -m $'feat: rename workspace pane focus model\n\nCo-authored-by: Codex <noreply@openai.com>'
```

### Task 2: Make Empty Drawer And Drawer Pane Focus First-Class In The Focus Pipeline

**Files:**
- Create: `Tests/AgentStudioTests/Core/State/MainActor/Atoms/WorkspaceNavigationScopeAtomTests.swift`
- Modify: `Sources/AgentStudio/Infrastructure/PaneFocus/PaneFocusContext.swift`
- Modify: `Sources/AgentStudio/App/Panes/PaneFocusExecutor.swift`
- Modify: `Sources/AgentStudio/App/Panes/PaneTabViewController.swift`
- Modify: `Tests/AgentStudioTests/App/PaneTabViewControllerCommandTests.swift`

- [ ] **Step 1: Write the failing focus-behavior tests**

```swift
import AppKit
import Foundation
import Testing

@testable import AgentStudio

@Suite(.serialized)
@MainActor
struct WorkspaceNavigationScopeAtomTests {
    @Test("empty drawer focus is first-class")
    func emptyDrawerFocus_isFirstClass() {
        let atom = WorkspaceNavigationScopeAtom()
        let parentPaneId = UUID()

        atom.focusEmptyDrawer(parentPaneId: parentPaneId)

        #expect(atom.scope == .emptyDrawer(parentPaneId: parentPaneId))
    }
}
```

```swift
@Test("enterDrawer on expanded empty drawer switches to empty drawer focus instead of keeping main-row focus")
func executeEnterDrawer_emptyDrawer_projectsEmptyDrawerFocus() throws {
    let harness = makeHarness()
    defer { try? FileManager.default.removeItem(at: harness.tempDir) }

    let parent = harness.store.createPane(source: .floating(launchDirectory: nil, title: "Parent"))
    let tab = Tab(paneId: parent.id)
    harness.store.appendTab(tab)
    harness.store.setActiveTab(tab.id)
    harness.store.setActivePane(parent.id, inTab: tab.id)
    harness.store.toggleDrawer(for: parent.id)

    harness.controller.execute(.enterDrawer)

    #expect(atom(\.workspaceNavigationScope).scope == .emptyDrawer(parentPaneId: parent.id))
}

@Test("d creates first drawer pane while empty drawer has focus")
func rawD_openEmptyDrawerWithEmptyDrawerFocus_createsFirstDrawerPane() throws {
    let harness = makeHarness()
    defer { try? FileManager.default.removeItem(at: harness.tempDir) }

    let parent = harness.store.createPane(source: .floating(launchDirectory: nil, title: "Parent"))
    let tab = Tab(paneId: parent.id)
    harness.store.appendTab(tab)
    harness.store.setActiveTab(tab.id)
    harness.store.setActivePane(parent.id, inTab: tab.id)
    harness.store.toggleDrawer(for: parent.id)
    atom(\.workspaceNavigationScope).focusEmptyDrawer(parentPaneId: parent.id)

    let event = try #require(
        NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "d",
            charactersIgnoringModifiers: "d",
            isARepeat: false,
            keyCode: 2
        )
    )

    #expect(harness.controller.handleAppOwnedKeyEvent(event, requiresNeutralDrawerFocus: false))
    #expect(harness.store.pane(parent.id)?.drawer?.paneIds.count == 1)
}

@Test("option-j from empty drawer focus is a no-op instead of main-row movement")
func optionJ_emptyDrawerFocus_doesNotMoveMainRow() throws {
    let harness = makeHarness()
    defer { try? FileManager.default.removeItem(at: harness.tempDir) }

    let left = harness.store.createPane(source: .floating(launchDirectory: nil, title: "Left"))
    let parent = harness.store.createPane(source: .floating(launchDirectory: nil, title: "Parent"))
    let tab = Tab(paneId: left.id)
    harness.store.appendTab(tab)
    harness.store.insertPane(parent.id, inTab: tab.id, at: left.id, direction: .horizontal, position: .after)
    harness.store.setActiveTab(tab.id)
    harness.store.setActivePane(parent.id, inTab: tab.id)
    harness.store.toggleDrawer(for: parent.id)
    atom(\.workspaceNavigationScope).focusEmptyDrawer(parentPaneId: parent.id)

    let event = try #require(
        NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [.option],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "j",
            charactersIgnoringModifiers: "j",
            isARepeat: false,
            keyCode: 38
        )
    )

    #expect(harness.controller.handleAppOwnedKeyEvent(event, requiresNeutralDrawerFocus: false))
    #expect(harness.store.tab(tab.id)?.activePaneId == parent.id)
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run:

```bash
swift test --build-path .build-agent-workspace-pane-focus \
  --filter 'WorkspaceNavigationScopeAtomTests|PaneTabViewControllerCommandTests'
```

Expected:

```text
FAIL because workspace navigation scope is not the canonical drawer focus source yet
```

- [ ] **Step 3: Implement the canonical navigation scope cutover**

```swift
// Sources/AgentStudio/Infrastructure/PaneFocus/PaneFocusContext.swift
import Foundation

enum PaneManagementFocusScope: Sendable, Equatable {
    case mainRow
    case emptyDrawer(parentPaneId: UUID)
    case drawer(parentPaneId: UUID)
}

struct PaneFocusContext: Sendable, Equatable {
    struct ActiveDrawerContext: Sendable, Equatable {
        let parentPaneId: UUID
        let paneId: UUID?
        let isEmpty: Bool
    }
}
```

```swift
// Sources/AgentStudio/App/Panes/PaneFocusExecutor.swift
@MainActor
final class PaneFocusExecutor {
    typealias DrawerEmptySelectionHandler = @MainActor (UUID) -> Void

    private let selectEmptyDrawer: DrawerEmptySelectionHandler

    init(
        hostViewProvider: @escaping HostViewProvider,
        hostViewsProvider: @escaping HostViewsProvider,
        selectTab: @escaping TabSelectionHandler,
        selectPane: @escaping PaneSelectionHandler,
        selectDrawerPane: @escaping DrawerSelectionHandler,
        selectEmptyDrawer: @escaping DrawerEmptySelectionHandler,
        syncRuntimeFocus: @escaping RuntimeFocusHandler
    ) {
        self.selectEmptyDrawer = selectEmptyDrawer
        self.syncRuntimeFocus = syncRuntimeFocus
    }
}
```

```swift
// Sources/AgentStudio/App/Panes/PaneTabViewController.swift
private func makePaneFocusExecutor() -> PaneFocusExecutor {
    PaneFocusExecutor(
        hostViewProvider: { [weak self] paneId in
            self?.viewRegistry.view(for: paneId)
        },
        hostViewsProvider: { [weak self] in
            guard let self else { return [] }
            return self.viewRegistry.registeredPaneIds.compactMap { self.viewRegistry.view(for: $0) }
        },
        selectTab: { [weak self] tabId in
            guard let self else { return }
            self.store.tabLayoutAtom.setActiveTab(tabId)
            atom(\.workspaceNavigationScope).focusMainPane(
                self.store.tabLayoutAtom.tab(tabId)?.activePaneId
            )
        },
        selectPane: { [weak self] tabId, paneId in
            guard let self else { return }
            self.store.tabLayoutAtom.setActiveTab(tabId)
            self.store.tabLayoutAtom.setActivePane(paneId, inTab: tabId)
            atom(\.workspaceNavigationScope).focusMainPane(paneId)
        },
        selectDrawerPane: { [weak self] parentPaneId, drawerPaneId in
            guard let self else { return }
            self.store.paneAtom.setActiveDrawerPane(drawerPaneId, in: parentPaneId)
            atom(\.workspaceNavigationScope).focusDrawerPane(
                parentPaneId: parentPaneId,
                paneId: drawerPaneId
            )
        },
        selectEmptyDrawer: { parentPaneId in
            atom(\.workspaceNavigationScope).focusEmptyDrawer(parentPaneId: parentPaneId)
        },
        syncRuntimeFocus: { surfaceId in
            SurfaceManager.shared.syncFocus(activeSurfaceId: surfaceId)
        }
    )
}
```

```swift
// Sources/AgentStudio/App/Panes/PaneTabViewController.swift
private func scopeAwarePaneCommand(for trigger: ShortcutTrigger) -> AppCommand? {
    let scope = atom(\.workspaceNavigationScope).scope

    switch trigger {
    case .init(key: .character(.i), modifiers: [.option]):
        return if case .drawerPane = scope { .focusDrawerPaneUp } else { nil }
    case .init(key: .character(.j), modifiers: [.option]):
        switch scope {
        case .mainPane:
            return .focusPaneLeft
        case .emptyDrawer:
            return nil
        case .drawerPane:
            return .focusDrawerPaneLeft
        }
    case .init(key: .character(.k), modifiers: [.option]):
        switch scope {
        case .mainPane:
            return .enterDrawer
        case .emptyDrawer:
            return nil
        case .drawerPane:
            return .focusDrawerPaneDown
        }
    case .init(key: .character(.l), modifiers: [.option]):
        switch scope {
        case .mainPane:
            return .focusPaneRight
        case .emptyDrawer:
            return nil
        case .drawerPane:
            return .focusDrawerPaneRight
        }
    default:
        return nil
    }
}
```

```swift
// Sources/AgentStudio/App/Panes/PaneTabViewController.swift
private func shouldCreateFirstDrawerPane(from event: NSEvent) -> Bool {
    guard
        atom(\.managementLayer).isActive == false,
        event.charactersIgnoringModifiers?.lowercased() == "d",
        event.modifierFlags.isDisjoint(with: .deviceIndependentFlagsMask),
        case .emptyDrawer(let parentPaneId) = atom(\.workspaceNavigationScope).scope,
        store.paneAtom.pane(parentPaneId)?.drawer?.paneIds.isEmpty == true
    else {
        return false
    }
    return true
}
```

```swift
// Sources/AgentStudio/App/Panes/PaneTabViewController.swift
private func enterDrawerFromActivePane() {
    guard
        let activeTabId = store.tabLayoutAtom.activeTabId,
        let parentPaneId = store.tabLayoutAtom.tab(activeTabId)?.activePaneId
    else { return }

    if store.paneAtom.pane(parentPaneId)?.drawer?.isExpanded == false {
        dispatchAction(.toggleDrawer(paneId: parentPaneId))
    }

    if let drawerPaneId = store.paneAtom.pane(parentPaneId)?.drawer?.activePaneId {
        handlePaneFocusTrigger(.drawer(.selectPane(parentPaneId: parentPaneId, drawerPaneId: drawerPaneId)))
    } else {
        atom(\.workspaceNavigationScope).focusEmptyDrawer(parentPaneId: parentPaneId)
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run:

```bash
swift test --build-path .build-agent-workspace-pane-focus \
  --filter 'WorkspaceNavigationScopeAtomTests|PaneTabViewControllerCommandTests'
```

Expected:

```text
PASS
```

- [ ] **Step 5: Commit**

```bash
git add Sources/AgentStudio/Infrastructure/PaneFocus/PaneFocusContext.swift \
        Sources/AgentStudio/App/Panes/PaneFocusExecutor.swift \
        Sources/AgentStudio/App/Panes/PaneTabViewController.swift \
        Tests/AgentStudioTests/Core/State/MainActor/Atoms/WorkspaceNavigationScopeAtomTests.swift \
        Tests/AgentStudioTests/App/PaneTabViewControllerCommandTests.swift
git commit -m $'feat: make drawer focus a first-class workspace scope\n\nCo-authored-by: Codex <noreply@openai.com>'
```

### Task 3: Move Command Visibility And Drawer Validation Onto The New Focus Model

**Files:**
- Modify: `Sources/AgentStudio/Features/CommandBar/CommandBarDataSource.swift`
- Modify: `Sources/AgentStudio/Core/Actions/ActionValidator.swift`
- Modify: `Sources/AgentStudio/Core/Actions/DrawerCommandValidator.swift`
- Modify: `Sources/AgentStudio/App/Coordination/PaneCoordinator+ActionExecution.swift`
- Modify: `Tests/AgentStudioTests/Core/Actions/ActionValidatorTests.swift`
- Modify: `Tests/AgentStudioTests/Core/Actions/ActionValidatorOwnershipTests.swift`
- Modify: `Tests/AgentStudioTests/Features/CommandBar/CommandBarAppModeTests.swift`

- [ ] **Step 1: Write the failing command-visibility and validator tests**

```swift
@Test("detach drawer pane command is visible only when a drawer pane really has focus")
func detachCommand_visibleOnlyForFocusedDrawerPane() {
    let emptyDrawerFocus = WorkspacePaneFocus(
        activeTabId: UUID(),
        activePaneId: UUID(),
        activeRepoId: nil,
        activeWorktreeId: nil,
        paneContentType: .terminal,
        drawerFocusState: .emptyDrawer(parentPaneId: UUID()),
        satisfiedRequirements: [.hasActiveTab, .hasActivePane, .hasDrawer, .hasEmptyDrawerFocus]
    )
    let drawerPaneFocus = WorkspacePaneFocus(
        activeTabId: UUID(),
        activePaneId: UUID(),
        activeRepoId: nil,
        activeWorktreeId: nil,
        paneContentType: .terminal,
        drawerFocusState: .drawerPane(parentPaneId: UUID(), paneId: UUID()),
        satisfiedRequirements: [.hasActiveTab, .hasActivePane, .hasDrawer, .hasDrawerPanes, .hasFocusedDrawerPane]
    )

    #expect(!CommandDispatcher.shared.definition(for: .detachDrawerPane).isVisible(in: emptyDrawerFocus))
    #expect(CommandDispatcher.shared.definition(for: .detachDrawerPane).isVisible(in: drawerPaneFocus))
}
```

```swift
@Test("detachDrawerPane hidden parent fails before coordinator execution")
func detachDrawerPane_hiddenParentFailsValidation() {
    let parentPaneId = UUIDv7.generate()
    let drawerPaneId = UUIDv7.generate()
    let snapshot = ActionStateSnapshot(
        tabs: [
            TabSnapshot(
                id: UUID(),
                visiblePaneIds: [],
                ownedPaneIds: [parentPaneId, drawerPaneId],
                activePaneId: nil
            )
        ],
        activeTabId: nil,
        isManagementLayerActive: false,
        drawerParentByPaneId: [drawerPaneId: parentPaneId],
        drawerLayoutByParentPaneId: [
            parentPaneId: DrawerGridLayout(topRow: Layout.autoTiled([drawerPaneId]))
        ]
    )

    let result = WorkspaceCommandValidator.validate(
        .detachDrawerPane(parentPaneId: parentPaneId, drawerPaneId: drawerPaneId),
        state: snapshot
    )

    if case .failure(.paneNotFound) = result { return }
    Issue.record("Expected paneNotFound when parent is not showing in active arrangement")
}
```

```swift
@Test("insertDrawerPane invalid third row fails in validator before store execution")
func insertDrawerPane_invalidThirdRowFailsAtValidatorBoundary() {
    let parentPaneId = UUIDv7.generate()
    let topPaneId = UUIDv7.generate()
    let bottomPaneId = UUIDv7.generate()
    let snapshot = ActionStateSnapshot(
        tabs: [
            TabSnapshot(
                id: UUID(),
                visiblePaneIds: [parentPaneId],
                ownedPaneIds: [parentPaneId, topPaneId, bottomPaneId],
                activePaneId: parentPaneId
            )
        ],
        activeTabId: nil,
        isManagementLayerActive: false,
        drawerParentByPaneId: [
            topPaneId: parentPaneId,
            bottomPaneId: parentPaneId
        ],
        drawerLayoutByParentPaneId: [
            parentPaneId: DrawerGridLayout(
                topRow: Layout.autoTiled([topPaneId]),
                bottomRow: Layout.autoTiled([bottomPaneId])
            )
        ]
    )

    let result = WorkspaceCommandValidator.validate(
        .insertDrawerPane(
            parentPaneId: parentPaneId,
            targetDrawerPaneId: bottomPaneId,
            direction: .down
        ),
        state: snapshot
    )

    if case .failure(.invalidDrawerLayout) = result { return }
    Issue.record("Expected invalidDrawerLayout")
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run:

```bash
swift test --build-path .build-agent-workspace-pane-focus \
  --filter 'ActionValidatorTests|ActionValidatorOwnershipTests|WorkspaceFocusTests'
```

Expected:

```text
FAIL because visibility and validator logic still only understand the old coarse focus summary
```

- [ ] **Step 3: Implement the minimal visibility and validation cutover**

```swift
// Sources/AgentStudio/App/Commands/AppCommand+Definitions.swift
case .focusDrawerPaneUp, .focusDrawerPaneLeft, .focusDrawerPaneDown, .focusDrawerPaneRight:
    return CommandSpec(
        command: self,
        label: "Move Drawer Focus",
        icon: "arrow.up.left.and.arrow.down.right",
        helpText: "Move selection within the active drawer",
        appliesTo: [.pane],
        visibleWhen: [.hasActivePane, .hasFocusedDrawerPane],
        commandBarGroupName: "Pane",
        commandBarGroupPriority: CommandBarGroupPriority.pane,
        isHiddenInCommandBar: true
    )
case .detachDrawerPane:
    return CommandSpec(
        command: self,
        label: "Detach Drawer Pane",
        icon: "arrow.up.right.square",
        helpText: "Promote the selected drawer pane into the main layout",
        appliesTo: [.pane],
        visibleWhen: [.hasActivePane, .hasFocusedDrawerPane],
        commandBarGroupName: "Pane",
        commandBarGroupPriority: CommandBarGroupPriority.pane,
        isHiddenInCommandBar: true
    )
```

```swift
// Sources/AgentStudio/Core/Actions/DrawerCommandValidator.swift
static func validateInsertion(
    parentPaneId: UUID,
    targetDrawerPaneId: UUID,
    direction: SplitNewDirection,
    state: ActionStateSnapshot
) -> Result<Void, ActionValidationError> {
    guard let currentLayout = state.drawerLayout(for: parentPaneId) else {
        return .failure(.invalidDrawerLayout(parentPaneId: parentPaneId))
    }

    let projectedPaneId = UUID()
    guard let projectedLayout = currentLayout.inserting(
        paneId: projectedPaneId,
        at: targetDrawerPaneId,
        direction: direction
    ) else {
        return .failure(.invalidDrawerLayout(parentPaneId: parentPaneId))
    }

    return validateResultingLayout(
        projectedLayout,
        parentPaneId: parentPaneId,
        state: state,
        requestedDirection: direction,
        wouldCreateThirdRow: false
    )
}
```

```swift
// Sources/AgentStudio/Core/Actions/ActionValidator.swift
case .insertDrawerPane(let parentPaneId, let targetDrawerPaneId, let direction):
    return DrawerCommandValidator.validateInsertion(
        parentPaneId: parentPaneId,
        targetDrawerPaneId: targetDrawerPaneId,
        direction: direction,
        state: state
    ).map { ValidatedAction(action) }

case .detachDrawerPane(let parentPaneId, let drawerPaneId):
    if let error = DrawerCommandValidator.validateMembership(
        parentPaneId: parentPaneId,
        drawerPaneId: drawerPaneId,
        state: state
    ) {
        return .failure(error)
    }
    guard state.tabShowing(paneId: parentPaneId) != nil else {
        return .failure(.paneNotFound(paneId: parentPaneId, tabId: state.activeTabId ?? UUID()))
    }
    return .success(ValidatedAction(action))
```

- [ ] **Step 4: Run the tests to verify they pass**

Run:

```bash
swift test --build-path .build-agent-workspace-pane-focus \
  --filter 'ActionValidatorTests|ActionValidatorOwnershipTests|WorkspaceFocusTests'
```

Expected:

```text
PASS
```

- [ ] **Step 5: Commit**

```bash
git add Sources/AgentStudio/Features/CommandBar/CommandBarDataSource.swift \
        Sources/AgentStudio/Core/Actions/ActionValidator.swift \
        Sources/AgentStudio/Core/Actions/DrawerCommandValidator.swift \
        Sources/AgentStudio/App/Coordination/PaneCoordinator+ActionExecution.swift \
        Tests/AgentStudioTests/Core/Actions/ActionValidatorTests.swift \
        Tests/AgentStudioTests/Core/Actions/ActionValidatorOwnershipTests.swift \
        Tests/AgentStudioTests/Features/CommandBar/CommandBarAppModeTests.swift
git commit -m $'feat: align drawer visibility and validation with pane focus\n\nCo-authored-by: Codex <noreply@openai.com>'
```

### Task 4: Rename Controller Scope For Clarity And Preserve Drawer-Only Boundary Naming

**Files:**
- Modify: `Sources/AgentStudio/App/Panes/PaneTabViewController.swift`
- Modify: `Tests/AgentStudioTests/App/PaneTabViewControllerCommandTests.swift`

- [ ] **Step 1: Write the failing naming/behavior regression tests**

```swift
@Test("empty drawer focus is a no-op for option-j and does not leak to main-row movement")
func optionJ_emptyDrawerFocus_doesNotMoveMainRow() throws {
    let harness = makeHarness()
    defer { try? FileManager.default.removeItem(at: harness.tempDir) }

    let left = harness.store.createPane(source: .floating(launchDirectory: nil, title: "Left"))
    let parent = harness.store.createPane(source: .floating(launchDirectory: nil, title: "Parent"))
    let tab = Tab(paneId: left.id)
    harness.store.appendTab(tab)
    harness.store.insertPane(parent.id, inTab: tab.id, at: left.id, direction: .horizontal, position: .after)
    harness.store.setActiveTab(tab.id)
    harness.store.setActivePane(parent.id, inTab: tab.id)
    harness.store.toggleDrawer(for: parent.id)
    atom(\.workspaceNavigationScope).focusEmptyDrawer(parentPaneId: parent.id)

    let event = try #require(
        NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [.option],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "j",
            charactersIgnoringModifiers: "j",
            isARepeat: false,
            keyCode: 38
        )
    )

    #expect(harness.controller.handleAppOwnedKeyEvent(event, requiresNeutralDrawerFocus: false))
    #expect(harness.store.tab(tab.id)?.activePaneId == parent.id)
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run:

```bash
swift test --build-path .build-agent-workspace-pane-focus \
  --filter 'PaneTabViewControllerCommandTests'
```

Expected:

```text
FAIL until the controller scope name and behavior are aligned with the canonical workspace navigation scope
```

- [ ] **Step 3: Implement the minimal scope rename and behavior alignment**

```swift
// Sources/AgentStudio/App/Panes/PaneTabViewController.swift
// Rename the controller-local scope variable from
// `managementLayerNavigationScope` to `workspaceNavigationFocusScope`
// everywhere it is used as the canonical drawer/main keyboard scope.
```

- [ ] **Step 4: Run the tests to verify they pass**

Run:

```bash
swift test --build-path .build-agent-workspace-pane-focus \
  --filter 'PaneTabViewControllerCommandTests'
```

Expected:

```text
PASS
```

- [ ] **Step 5: Commit**

```bash
git add Sources/AgentStudio/App/Panes/PaneTabViewController.swift \
        Tests/AgentStudioTests/App/PaneTabViewControllerCommandTests.swift
git commit -m $'refactor: clarify workspace pane focus scope naming\n\nCo-authored-by: Codex <noreply@openai.com>'
```

### Task 5: Run The Full Workspace Pane Focus And Drawer Boundary Verification

**Files:**
- Modify: `Tests/AgentStudioTests/App/PaneTabViewControllerDropRoutingTests.swift`
- Modify: `Tests/AgentStudioTests/Core/Actions/PaneDropPlannerTests.swift`
- Modify: `Tests/AgentStudioTests/Core/Actions/DrawerCommandIntegrationTests.swift`

- [ ] **Step 1: Add the final boundary tests**

```swift
@Test("dragging within one drawer still yields a drawer move plan after the focus-model rename")
func splitDropCommitPlan_returnsMoveDrawerPlan_forSameDrawerParent() {
    let parentPaneId = UUIDv7.generate()
    let sourcePaneId = UUIDv7.generate()
    let destinationPaneId = UUIDv7.generate()
    let tabId = UUIDv7.generate()

    let state = ActionStateSnapshot(
        tabs: [
            TabSnapshot(
                id: tabId,
                visiblePaneIds: [parentPaneId, sourcePaneId, destinationPaneId],
                ownedPaneIds: [parentPaneId, sourcePaneId, destinationPaneId],
                activePaneId: parentPaneId
            )
        ],
        activeTabId: tabId,
        isManagementLayerActive: true,
        drawerParentByPaneId: [
            sourcePaneId: parentPaneId,
            destinationPaneId: parentPaneId
        ],
        drawerLayoutByParentPaneId: [
            parentPaneId: DrawerGridLayout(topRow: Layout.autoTiled([sourcePaneId, destinationPaneId]))
        ]
    )
    let payload = SplitDropPayload(kind: .existingPane(paneId: sourcePaneId, sourceTabId: tabId))

    let result = PaneDropPlanner.previewDecision(
        payload: payload,
        destination: .split(
            targetPaneId: destinationPaneId,
            targetTabId: tabId,
            direction: .left,
            targetDrawerParentPaneId: parentPaneId
        ),
        state: state
    )

    #expect(
        result == .eligible(
            .paneAction(
                .moveDrawerPane(
                    parentPaneId: parentPaneId,
                    drawerPaneId: sourcePaneId,
                    targetDrawerPaneId: destinationPaneId,
                    direction: .left
                )
            )
        )
    )
}
```

- [ ] **Step 2: Run the focused correction suites**

Run:

```bash
swift test --build-path .build-agent-workspace-pane-focus \
  --filter 'WorkspaceNavigationScopeAtomTests|WorkspacePaneFocusDerivedTests|PaneTabViewControllerCommandTests|PaneTabViewControllerDropRoutingTests|PaneDropPlannerTests|DrawerCommandIntegrationTests'
```

Expected:

```text
PASS
```

- [ ] **Step 3: Run full repo verification**

Run:

```bash
AGENT_RUN_ID=workspace-pane-focus-cutover mise run test
AGENT_RUN_ID=workspace-pane-focus-cutover mise run lint
```

Expected:

```text
All repo tests PASS
swiftlint: OK
architecture boundary checks PASS
```

- [ ] **Step 4: Run visual verification for top/bottom drawer targeting**

Run:

```bash
pkill -9 -f "AgentStudio" || true
.build/debug/AgentStudio &
PID=$(pgrep -f ".build/debug/AgentStudio")
peekaboo see --app "PID:$PID" --json
```

Expected:

```text
Visually confirm:
- top-edge drawer drag highlights top target
- bottom-edge drawer drag highlights bottom target
- main-pane split drag remains left/right only
```

- [ ] **Step 5: Commit**

```bash
git add Tests/AgentStudioTests/App/PaneTabViewControllerDropRoutingTests.swift \
        Tests/AgentStudioTests/Core/Actions/PaneDropPlannerTests.swift \
        Tests/AgentStudioTests/Core/Actions/DrawerCommandIntegrationTests.swift
git commit -m $'test: lock workspace pane focus drawer boundary\n\nCo-authored-by: Codex <noreply@openai.com>'
```
