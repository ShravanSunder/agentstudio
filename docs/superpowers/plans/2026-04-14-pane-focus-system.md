# Pane Focus System Implementation Plan

> Completed implementation note (2026-04-15): the shipped code diverged in a few intentional ways from the original plan. Pure trigger/context/decision/decider/orchestrator types live under `Sources/AgentStudio/Infrastructure/PaneFocus/`; the AppKit-facing `PaneFocusExecutor` lives under `Sources/AgentStudio/App/Panes/`; `PaneTabViewController` and `PaneCoordinator` assemble `PaneFocusContext` instead of the orchestrator; and the final `PaneFocusContext` uses `targetMountedContent` plus `windowState` rather than the earlier `targetPaneAcceptsFirstResponder` / `targetPaneHasMountedContent` / `targetTerminalSurfaceId` sketch.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the current ad hoc pane focus behavior with a pane-scoped focus system built from exhaustive trigger/decision enums, typed family deciders, and a single `@MainActor` executor.

**Architecture:** Pane-affecting focus triggers become `PaneFocusTrigger` values, `PaneTabViewController` and `PaneCoordinator` assemble `PaneFocusContext` snapshots at the UI/runtime boundary, typed family deciders return exhaustive `PaneFocusDecision` values, and `PaneFocusExecutor` applies all selection/responder/runtime effects. This is a full clean-cut change: pane-affecting focus stops flowing through `PaneActionCommand.focusPane(...)` and direct `refocusActivePane()` / `makeFirstResponder(...)` helpers.

**Tech Stack:** Swift 6.2, AppKit, SwiftUI, Observation, Swift Testing, actor-bound atoms/derived selectors

---

## File Structure

```text
Create:
- Sources/AgentStudio/App/Panes/Focus/PaneFocusTrigger.swift
- Sources/AgentStudio/App/Panes/Focus/PaneFocusContext.swift
- Sources/AgentStudio/App/Panes/Focus/PaneFocusDecision.swift
- Sources/AgentStudio/App/Panes/Focus/PaneFocusOrchestrator.swift
- Sources/AgentStudio/App/Panes/Focus/PaneFocusExecutor.swift
- Sources/AgentStudio/App/Panes/Focus/PaneContentClickFocusDecider.swift
- Sources/AgentStudio/App/Panes/Focus/PaneTabClickFocusDecider.swift
- Sources/AgentStudio/App/Panes/Focus/PaneDrawerFocusDecider.swift
- Sources/AgentStudio/App/Panes/Focus/PaneKeyboardFocusDecider.swift
- Sources/AgentStudio/App/Panes/Focus/PaneModeFocusDecider.swift
- Sources/AgentStudio/App/Panes/Focus/PaneRefocusRequestFocusDecider.swift
- Sources/AgentStudio/App/Panes/Focus/PaneCommandFocusDecider.swift
- Tests/AgentStudioTests/App/Panes/Focus/PaneContentClickFocusDeciderTests.swift
- Tests/AgentStudioTests/App/Panes/Focus/PaneTabClickFocusDeciderTests.swift
- Tests/AgentStudioTests/App/Panes/Focus/PaneModeFocusDeciderTests.swift
- Tests/AgentStudioTests/App/Panes/Focus/PaneFocusOrchestratorTests.swift
- Tests/AgentStudioTests/App/Panes/Focus/PaneFocusExecutorTests.swift

Modify:
- Sources/AgentStudio/Core/Views/Splits/PaneLeafContainer.swift
- Sources/AgentStudio/App/Panes/PaneTabViewController.swift
- Sources/AgentStudio/App/Panes/Hosting/PaneHostView.swift
- Sources/AgentStudio/App/Lifecycle/ManagementModeMonitor.swift
- Sources/AgentStudio/App/Windows/MainSplitViewController.swift
- Sources/AgentStudio/App/Windows/MainWindowController.swift
- Sources/AgentStudio/App/Boot/AppDelegate+LifecycleRouting.swift
- Sources/AgentStudio/Features/Sidebar/RepoSidebarContentView.swift
- Sources/AgentStudio/Core/Views/Drawer/DrawerPanel.swift
- Sources/AgentStudio/Core/Views/Drawer/DrawerPanelOverlay.swift
- Sources/AgentStudio/Core/Views/Drawer/DrawerOverlay.swift
- Sources/AgentStudio/App/Panes/TabBar/CustomTabBar.swift
- Sources/AgentStudio/App/Panes/TabBar/DraggableTabBarHostingView.swift
- Sources/AgentStudio/App/Panes/TabBar/ArrangementPanel.swift
- Sources/AgentStudio/App/Commands/AppCommand.swift
- Sources/AgentStudio/Core/Actions/PaneActionCommand.swift
- Sources/AgentStudio/Core/Actions/ActionResolver.swift
- Sources/AgentStudio/Core/Actions/ActionValidator.swift
- Sources/AgentStudio/App/Coordination/PaneCoordinator+ActionExecution.swift
- Sources/AgentStudio/App/Coordination/PaneCoordinator+ViewHelpers.swift

Test:
- Tests/AgentStudioTests/App/ManagementModeTests.swift
- Tests/AgentStudioTests/App/PaneTabViewControllerCommandTests.swift
- Tests/AgentStudioTests/Features/Webview/WebviewPaneControllerTests.swift
```

The final implementation split pure pane-focus types into `Infrastructure/PaneFocus/` and kept the AppKit-facing executor in `App/Panes/`.

---

### Task 1: Lock the exhaustive trigger/decision model with failing tests

**Files:**
- Create: `Tests/AgentStudioTests/App/Panes/Focus/PaneContentClickFocusDeciderTests.swift`
- Create: `Tests/AgentStudioTests/App/Panes/Focus/PaneModeFocusDeciderTests.swift`
- Create: `Tests/AgentStudioTests/App/Panes/Focus/PaneFocusOrchestratorTests.swift`

- [ ] **Step 1: Write failing content-click decider tests**

```swift
import Testing

@testable import AgentStudio

@Suite(.serialized)
@MainActor
struct PaneContentClickFocusDeciderTests {
    @Test("active webview content click is a host no-op")
    func activeWebviewContentClick_isNoOp() {
        let trigger = PaneFocusTrigger.contentClick(
            PaneContentClickFocusTrigger(
                targetPaneId: UUID(),
                location: .content,
                clickPhase: .completed
            )
        )
        let context = PaneFocusContext(
            activeTabId: UUID(),
            activePaneId: trigger.targetPaneIdForTesting,
            activeDrawerParentPaneId: nil,
            activeDrawerPaneId: nil,
            targetPaneId: trigger.targetPaneIdForTesting,
            targetTabId: UUID(),
            targetPaneKind: .webview,
            targetPaneIsAlreadyActive: true,
            targetPaneAcceptsFirstResponder: true,
            targetPaneHasMountedContent: true,
            targetTerminalSurfaceId: nil,
            managementMode: .inactive,
            triggerSource: .contentClick
        )

        let decision = PaneContentClickFocusDecider.decide(
            trigger: try! #require(trigger.contentClickTriggerForTesting),
            context: context
        )

        #expect(decision.selection == .keep)
        #expect(decision.responder == .none)
        #expect(decision.runtime == .none)
        #expect(decision.content == .preserve)
    }
}
```

- [ ] **Step 2: Write failing mode decider tests**

```swift
import Testing

@testable import AgentStudio

@Suite(.serialized)
@MainActor
struct PaneModeFocusDeciderTests {
    @Test("management mode entry for active webview clears pane-host ownership and blocks content")
    func managementModeEntry_webviewBlocksContent() {
        let trigger = PaneModeFocusTrigger(
            transition: .enteredManagementMode,
            source: .keyboardShortcut
        )
        let context = PaneFocusContext(
            activeTabId: UUID(),
            activePaneId: UUID(),
            activeDrawerParentPaneId: nil,
            activeDrawerPaneId: nil,
            targetPaneId: UUID(),
            targetTabId: UUID(),
            targetPaneKind: .webview,
            targetPaneIsAlreadyActive: true,
            targetPaneAcceptsFirstResponder: true,
            targetPaneHasMountedContent: true,
            targetTerminalSurfaceId: nil,
            managementMode: .active(scope: .mainRow),
            triggerSource: .modeTransition
        )

        let decision = PaneModeFocusDecider.decide(trigger: trigger, context: context)

        #expect(decision.content == .block)
    }
}
```

- [ ] **Step 3: Write failing orchestrator dispatch tests**

```swift
import Testing

@testable import AgentStudio

@Suite(.serialized)
@MainActor
struct PaneFocusOrchestratorTests {
    @Test("orchestrator dispatches content click through content decider family")
    func orchestratorDispatchesContentClick() {
        let paneId = UUID()
        let trigger = PaneFocusTrigger.contentClick(
            PaneContentClickFocusTrigger(
                targetPaneId: paneId,
                location: .content,
                clickPhase: .completed
            )
        )

        let decision = PaneFocusOrchestrator.decide(
            trigger: trigger,
            context: .fixture(
                activePaneId: paneId,
                targetPaneId: paneId,
                targetPaneKind: .webview
            )
        )

        guard case .contentClick = decision else {
            Issue.record("Expected contentClick decision, got \(decision)")
            return
        }
    }
}
```

- [ ] **Step 4: Run focused tests to verify they fail**

Run:

```bash
SWIFT_BUILD_DIR=.build-agent-pane-focus-red \
swift test --build-path "$SWIFT_BUILD_DIR" \
  --filter "PaneContentClickFocusDeciderTests|PaneModeFocusDeciderTests|PaneFocusOrchestratorTests"
```

Expected: FAIL with missing `PaneFocusTrigger`, `PaneFocusContext`, `PaneFocusDecision`, or family decider types.

- [ ] **Step 5: Commit**

```bash
git add Tests/AgentStudioTests/App/Panes/Focus/PaneContentClickFocusDeciderTests.swift \
        Tests/AgentStudioTests/App/Panes/Focus/PaneModeFocusDeciderTests.swift \
        Tests/AgentStudioTests/App/Panes/Focus/PaneFocusOrchestratorTests.swift
git commit -m "test: lock pane focus trigger and decision model"
```

---

### Task 2: Add the Pane Focus type system and orchestrator

**Files:**
- Create: `Sources/AgentStudio/App/Panes/Focus/PaneFocusTrigger.swift`
- Create: `Sources/AgentStudio/App/Panes/Focus/PaneFocusContext.swift`
- Create: `Sources/AgentStudio/App/Panes/Focus/PaneFocusDecision.swift`
- Create: `Sources/AgentStudio/App/Panes/Focus/PaneFocusOrchestrator.swift`

- [ ] **Step 1: Add the exhaustive trigger enum and child trigger payloads**

```swift
import Foundation

enum PaneFocusTrigger: Sendable, Equatable {
    case contentClick(PaneContentClickFocusTrigger)
    case tabClick(PaneTabClickFocusTrigger)
    case drawer(PaneDrawerFocusTrigger)
    case keyboard(PaneKeyboardFocusTrigger)
    case mode(PaneModeFocusTrigger)
    case refocusRequest(PaneRefocusRequestTrigger)
    case command(PaneCommandFocusTrigger)
}

struct PaneContentClickFocusTrigger: Sendable, Equatable {
    enum Location: Sendable, Equatable {
        case content
        case chrome
    }

    enum ClickPhase: Sendable, Equatable {
        case completed
    }

    let targetPaneId: UUID
    let location: Location
    let clickPhase: ClickPhase
}
```

- [ ] **Step 2: Add the full context snapshot type**

```swift
import Foundation

struct PaneFocusContext: Sendable, Equatable {
    enum PaneKind: Sendable, Equatable {
        case terminal
        case webview
        case bridge
        case codeViewer
        case unknown
    }

    enum ManagementModeState: Sendable, Equatable {
        case inactive
        case active(scope: PaneManagementFocusScope)
    }

    enum TriggerSource: Sendable, Equatable {
        case contentClick
        case tabClick
        case drawerClick
        case keyboard
        case modeTransition
        case refocusRequest
        case command
    }

    let activeTabId: UUID?
    let activePaneId: UUID?
    let activeDrawerParentPaneId: UUID?
    let activeDrawerPaneId: UUID?
    let targetPaneId: UUID?
    let targetTabId: UUID?
    let targetPaneKind: PaneKind
    let targetPaneIsAlreadyActive: Bool
    let targetPaneAcceptsFirstResponder: Bool
    let targetPaneHasMountedContent: Bool
    let targetTerminalSurfaceId: UUID?
    let managementMode: ManagementModeState
    let triggerSource: TriggerSource
}
```

- [ ] **Step 3: Add the exhaustive decision enum and typed child decision payloads**

```swift
import Foundation

enum PaneFocusDecision: Sendable, Equatable {
    case noOp(PaneFocusNoOpDecision)
    case contentClick(PaneContentClickFocusDecision)
    case tabClick(PaneTabClickFocusDecision)
    case drawer(PaneDrawerFocusDecision)
    case keyboard(PaneKeyboardFocusDecision)
    case mode(PaneModeFocusDecision)
    case refocusRequest(PaneRefocusRequestDecision)
    case command(PaneCommandFocusDecision)
}

struct PaneFocusNoOpDecision: Sendable, Equatable {
    let reason: PaneFocusReason
}

enum PaneFocusReason: Sendable, Equatable {
    case activeContentClickPreservesOwnership
    case inactivePaneRequiresSelection
    case managementModeEntered
    case explicitRefocus
    case commandTriggeredFocus
    case drawerSelectionChanged
}
```

- [ ] **Step 4: Add the exhaustive orchestrator shell**

```swift
import Foundation

enum PaneFocusOrchestrator {
    static func decide(
        trigger: PaneFocusTrigger,
        context: PaneFocusContext
    ) -> PaneFocusDecision {
        switch trigger {
        case .contentClick(let trigger):
            return .contentClick(
                PaneContentClickFocusDecider.decide(trigger: trigger, context: context)
            )
        case .tabClick(let trigger):
            return .tabClick(
                PaneTabClickFocusDecider.decide(trigger: trigger, context: context)
            )
        case .drawer(let trigger):
            return .drawer(
                PaneDrawerFocusDecider.decide(trigger: trigger, context: context)
            )
        case .keyboard(let trigger):
            return .keyboard(
                PaneKeyboardFocusDecider.decide(trigger: trigger, context: context)
            )
        case .mode(let trigger):
            return .mode(
                PaneModeFocusDecider.decide(trigger: trigger, context: context)
            )
        case .refocusRequest(let trigger):
            return .refocusRequest(
                PaneRefocusRequestFocusDecider.decide(trigger: trigger, context: context)
            )
        case .command(let trigger):
            return .command(
                PaneCommandFocusDecider.decide(trigger: trigger, context: context)
            )
        }
    }
}
```

- [ ] **Step 5: Run the focused tests and verify the model compiles**

Run:

```bash
SWIFT_BUILD_DIR=.build-agent-pane-focus-types \
swift test --build-path "$SWIFT_BUILD_DIR" \
  --filter "PaneContentClickFocusDeciderTests|PaneModeFocusDeciderTests|PaneFocusOrchestratorTests"
```

Expected: FAILs move from missing top-level types to missing family deciders / decision members.

- [ ] **Step 6: Commit**

```bash
git add Sources/AgentStudio/App/Panes/Focus/PaneFocusTrigger.swift \
        Sources/AgentStudio/App/Panes/Focus/PaneFocusContext.swift \
        Sources/AgentStudio/App/Panes/Focus/PaneFocusDecision.swift \
        Sources/AgentStudio/App/Panes/Focus/PaneFocusOrchestrator.swift
git commit -m "feat: add pane focus trigger and decision types"
```

---

### Task 3: Implement content, tab, and drawer click deciders

**Files:**
- Create: `Sources/AgentStudio/App/Panes/Focus/PaneContentClickFocusDecider.swift`
- Create: `Sources/AgentStudio/App/Panes/Focus/PaneTabClickFocusDecider.swift`
- Create: `Sources/AgentStudio/App/Panes/Focus/PaneDrawerFocusDecider.swift`
- Create: `Tests/AgentStudioTests/App/Panes/Focus/PaneTabClickFocusDeciderTests.swift`

- [ ] **Step 1: Add failing tab-click and drawer-click tests**

```swift
import Testing

@testable import AgentStudio

@Suite(.serialized)
@MainActor
struct PaneTabClickFocusDeciderTests {
    @Test("tab click selects tab without implicit responder move")
    func tabClick_selectsTab_withoutImplicitResponderMove() {
        let tabId = UUID()
        let decision = PaneTabClickFocusDecider.decide(
            trigger: PaneTabClickFocusTrigger(targetTabId: tabId),
            context: .fixture(activeTabId: nil, targetTabId: tabId, targetPaneKind: .terminal)
        )

        #expect(decision.selection == .selectTab(tabId))
        #expect(decision.responder == .none)
    }
}
```

- [ ] **Step 2: Implement the content-click decider**

```swift
import Foundation

enum PaneContentClickFocusDecider {
    static func decide(
        trigger: PaneContentClickFocusTrigger,
        context: PaneFocusContext
    ) -> PaneContentClickFocusDecision {
        if context.targetPaneIsAlreadyActive {
            return PaneContentClickFocusDecision(
                selection: .keep,
                responder: .none,
                runtime: .none,
                content: .preserve,
                reason: .activeContentClickPreservesOwnership
            )
        }

        switch context.targetPaneKind {
        case .terminal:
            return PaneContentClickFocusDecision(
                selection: .selectPane(tabId: context.targetTabId!, paneId: trigger.targetPaneId),
                responder: .focusPaneHost(paneId: trigger.targetPaneId),
                runtime: .syncTerminalSurface(paneId: trigger.targetPaneId),
                content: .preserve,
                reason: .inactivePaneRequiresSelection
            )
        case .webview, .bridge, .codeViewer, .unknown:
            return PaneContentClickFocusDecision(
                selection: .selectPane(tabId: context.targetTabId!, paneId: trigger.targetPaneId),
                responder: .none,
                runtime: .none,
                content: .preserve,
                reason: .inactivePaneRequiresSelection
            )
        }
    }
}
```

- [ ] **Step 3: Implement tab-click and drawer-click deciders**

```swift
import Foundation

enum PaneTabClickFocusDecider {
    static func decide(
        trigger: PaneTabClickFocusTrigger,
        context: PaneFocusContext
    ) -> PaneTabClickFocusDecision {
        PaneTabClickFocusDecision(
            selection: .selectTab(trigger.targetTabId),
            responder: .none,
            runtime: .none,
            reason: .commandTriggeredFocus
        )
    }
}

enum PaneDrawerFocusDecider {
    static func decide(
        trigger: PaneDrawerFocusTrigger,
        context: PaneFocusContext
    ) -> PaneDrawerFocusDecision {
        switch trigger {
        case .selectPane(let parentPaneId, let drawerPaneId):
            return PaneDrawerFocusDecision(
                selection: .selectDrawerPane(parentPaneId: parentPaneId, drawerPaneId: drawerPaneId),
                responder: .focusPaneHost(paneId: drawerPaneId),
                runtime: .none,
                reason: .drawerSelectionChanged
            )
        case .toggle(let parentPaneId):
            return PaneDrawerFocusDecision(
                selection: .keep,
                responder: .focusPaneHost(paneId: parentPaneId),
                runtime: .none,
                reason: .drawerSelectionChanged
            )
        }
    }
}
```

- [ ] **Step 4: Run focused click-family tests**

Run:

```bash
SWIFT_BUILD_DIR=.build-agent-pane-focus-clicks \
swift test --build-path "$SWIFT_BUILD_DIR" \
  --filter "PaneContentClickFocusDeciderTests|PaneTabClickFocusDeciderTests|PaneFocusOrchestratorTests"
```

Expected: PASS for click-family decision tests.

- [ ] **Step 5: Commit**

```bash
git add Sources/AgentStudio/App/Panes/Focus/PaneContentClickFocusDecider.swift \
        Sources/AgentStudio/App/Panes/Focus/PaneTabClickFocusDecider.swift \
        Sources/AgentStudio/App/Panes/Focus/PaneDrawerFocusDecider.swift \
        Tests/AgentStudioTests/App/Panes/Focus/PaneTabClickFocusDeciderTests.swift
git commit -m "feat: add pane click focus deciders"
```

---

### Task 4: Implement keyboard, mode, command, and refocus deciders

**Files:**
- Create: `Sources/AgentStudio/App/Panes/Focus/PaneKeyboardFocusDecider.swift`
- Create: `Sources/AgentStudio/App/Panes/Focus/PaneModeFocusDecider.swift`
- Create: `Sources/AgentStudio/App/Panes/Focus/PaneRefocusRequestFocusDecider.swift`
- Create: `Sources/AgentStudio/App/Panes/Focus/PaneCommandFocusDecider.swift`

- [ ] **Step 1: Add the keyboard and mode decision families**

```swift
import Foundation

enum PaneKeyboardFocusDecider {
    static func decide(
        trigger: PaneKeyboardFocusTrigger,
        context: PaneFocusContext
    ) -> PaneKeyboardFocusDecision {
        switch trigger {
        case .moveToPane(let tabId, let paneId, let paneKind):
            return PaneKeyboardFocusDecision(
                selection: .selectPane(tabId: tabId, paneId: paneId),
                responder: paneKind == .terminal ? .focusPaneHost(paneId: paneId) : .none,
                runtime: paneKind == .terminal ? .syncTerminalSurface(paneId: paneId) : .none,
                keyboard: .passThrough,
                reason: .commandTriggeredFocus
            )
        }
    }
}

enum PaneModeFocusDecider {
    static func decide(
        trigger: PaneModeFocusTrigger,
        context: PaneFocusContext
    ) -> PaneModeFocusDecision {
        switch trigger.transition {
        case .enteredManagementMode:
            switch context.targetPaneKind {
            case .terminal:
                return PaneModeFocusDecision(
                    responder: .clearToWindowContent,
                    keyboard: .consume,
                    content: .block,
                    reason: .managementModeEntered
                )
            case .webview, .bridge, .codeViewer, .unknown:
                return PaneModeFocusDecision(
                    responder: .none,
                    keyboard: .consume,
                    content: .block,
                    reason: .managementModeEntered
                )
            }
        case .exitedManagementMode:
            return PaneModeFocusDecision(
                responder: .none,
                keyboard: .passThrough,
                content: .release,
                reason: .explicitRefocus
            )
        }
    }
}
```

- [ ] **Step 2: Add refocus-request and command deciders**

```swift
import Foundation

enum PaneRefocusRequestFocusDecider {
    static func decide(
        trigger: PaneRefocusRequestTrigger,
        context: PaneFocusContext
    ) -> PaneRefocusRequestDecision {
        guard let activePaneId = context.activePaneId else {
            return PaneRefocusRequestDecision(
                responder: .none,
                runtime: .none,
                reason: .explicitRefocus
            )
        }

        switch context.targetPaneKind {
        case .terminal:
            return PaneRefocusRequestDecision(
                responder: .focusPaneHost(paneId: activePaneId),
                runtime: .syncTerminalSurface(paneId: activePaneId),
                reason: .explicitRefocus
            )
        case .webview, .bridge, .codeViewer, .unknown:
            return PaneRefocusRequestDecision(
                responder: .focusMountedContent(paneId: activePaneId),
                runtime: .none,
                reason: .explicitRefocus
            )
        }
    }
}

enum PaneCommandFocusDecider {
    static func decide(
        trigger: PaneCommandFocusTrigger,
        context: PaneFocusContext
    ) -> PaneCommandFocusDecision {
        switch trigger {
        case .focusPane(let tabId, let paneId):
            return PaneCommandFocusDecision(
                selection: .selectPane(tabId: tabId, paneId: paneId),
                responder: .none,
                runtime: .none,
                reason: .commandTriggeredFocus
            )
        case .selectTab(let tabId):
            return PaneCommandFocusDecision(
                selection: .selectTab(tabId),
                responder: .none,
                runtime: .none,
                reason: .commandTriggeredFocus
            )
        case .paneCreated(let paneId, let paneKind):
            return PaneCommandFocusDecision(
                selection: .keep,
                responder: paneKind == .terminal ? .focusPaneHost(paneId: paneId) : .none,
                runtime: paneKind == .terminal ? .syncTerminalSurface(paneId: paneId) : .none,
                reason: .commandTriggeredFocus
            )
        }
    }
}
```

- [ ] **Step 3: Run focused non-click tests**

Run:

```bash
SWIFT_BUILD_DIR=.build-agent-pane-focus-nonclick \
swift test --build-path "$SWIFT_BUILD_DIR" \
  --filter "PaneModeFocusDeciderTests|ManagementModeTests|PaneFocusOrchestratorTests"
```

Expected: PASS for mode-family tests and compile coverage across all decider families.

- [ ] **Step 4: Commit**

```bash
git add Sources/AgentStudio/App/Panes/Focus/PaneKeyboardFocusDecider.swift \
        Sources/AgentStudio/App/Panes/Focus/PaneModeFocusDecider.swift \
        Sources/AgentStudio/App/Panes/Focus/PaneRefocusRequestFocusDecider.swift \
        Sources/AgentStudio/App/Panes/Focus/PaneCommandFocusDecider.swift
git commit -m "feat: add pane keyboard and mode focus deciders"
```

---

### Task 5: Implement the executor and replace direct responder mutation paths

**Files:**
- Create: `Sources/AgentStudio/App/Panes/Focus/PaneFocusExecutor.swift`
- Create: `Tests/AgentStudioTests/App/Panes/Focus/PaneFocusExecutorTests.swift`
- Modify: `Sources/AgentStudio/App/Panes/Hosting/PaneHostView.swift`
- Modify: `Sources/AgentStudio/App/Panes/PaneTabViewController.swift`
- Modify: `Sources/AgentStudio/App/Coordination/PaneCoordinator+ViewHelpers.swift`
- Modify: `Sources/AgentStudio/App/Lifecycle/ManagementModeMonitor.swift`

- [ ] **Step 1: Write failing executor tests**

```swift
import Testing

@testable import AgentStudio

@Suite(.serialized)
@MainActor
struct PaneFocusExecutorTests {
    @Test("executor applies host responder focus without direct helper bypass")
    func executorAppliesResponderFocus() {
        let window = NSWindow()
        let paneView = PaneHostView(paneId: UUID())
        window.contentView = NSView()
        window.contentView?.addSubview(paneView)

        let executor = PaneFocusExecutor()
        executor.registerHostView(paneView)

        executor.apply(
            .contentClick(
                PaneContentClickFocusDecision(
                    selection: .keep,
                    responder: .focusPaneHost(paneId: paneView.paneId),
                    runtime: .none,
                    content: .preserve,
                    reason: .explicitRefocus
                )
            )
        )

        #expect(window.firstResponder === paneView)
    }
}
```

- [ ] **Step 2: Implement the executor skeleton**

```swift
import AppKit
import Foundation

@MainActor
final class PaneFocusExecutor {
    private var hostViewsByPaneId: [UUID: PaneHostView] = [:]

    func registerHostView(_ view: PaneHostView) {
        hostViewsByPaneId[view.paneId] = view
    }

    func unregisterHostView(_ paneId: UUID) {
        hostViewsByPaneId.removeValue(forKey: paneId)
    }

    func apply(_ decision: PaneFocusDecision) {
        switch decision {
        case .noOp:
            return
        case .contentClick(let decision):
            apply(decision)
        case .tabClick(let decision):
            apply(decision)
        case .drawer(let decision):
            apply(decision)
        case .keyboard(let decision):
            apply(decision)
        case .mode(let decision):
            apply(decision)
        case .refocusRequest(let decision):
            apply(decision)
        case .command(let decision):
            apply(decision)
        }
    }
}
```

- [ ] **Step 3: Replace direct helper-side focus mutations**

Replace direct `makeFirstResponder(...)` and `refocusActivePane()` effect paths with executor calls.

```swift
// before
paneView.window?.makeFirstResponder(paneView)

// after
paneFocusExecutor.apply(decision)
```

```swift
// before
func refocusActivePane() {
    guard let paneId = preferredVisibleFocusPaneId() else { return }
    ...
    paneView.window?.makeFirstResponder(paneView)
}

// after
func requestPaneRefocus(_ source: PaneRefocusRequestTrigger.Source) {
    guard let context = paneFocusOrchestrator.makeContext(
        source: .refocusRequest,
        targetPaneId: preferredVisibleFocusPaneId()
    ) else { return }
    let trigger = PaneFocusTrigger.refocusRequest(
        PaneRefocusRequestTrigger(source: source)
    )
    let decision = PaneFocusOrchestrator.decide(trigger: trigger, context: context)
    paneFocusExecutor.apply(decision)
}
```

- [ ] **Step 4: Run focused executor tests**

Run:

```bash
SWIFT_BUILD_DIR=.build-agent-pane-focus-executor \
swift test --build-path "$SWIFT_BUILD_DIR" \
  --filter "PaneFocusExecutorTests|WebviewPaneControllerTests|ManagementModeTests"
```

Expected: PASS, including the existing webview interaction regression coverage.

- [ ] **Step 5: Commit**

```bash
git add Sources/AgentStudio/App/Panes/Focus/PaneFocusExecutor.swift \
        Tests/AgentStudioTests/App/Panes/Focus/PaneFocusExecutorTests.swift \
        Sources/AgentStudio/App/Panes/PaneTabViewController.swift \
        Sources/AgentStudio/App/Panes/Hosting/PaneHostView.swift \
        Sources/AgentStudio/App/Coordination/PaneCoordinator+ViewHelpers.swift \
        Sources/AgentStudio/App/Lifecycle/ManagementModeMonitor.swift
git commit -m "feat: route pane focus effects through executor"
```

---

### Task 6: Replace pane, tab, drawer, command, and refocus triggers at call sites

**Files:**
- Modify: `Sources/AgentStudio/Core/Views/Splits/PaneLeafContainer.swift`
- Modify: `Sources/AgentStudio/App/Panes/TabBar/CustomTabBar.swift`
- Modify: `Sources/AgentStudio/App/Panes/TabBar/DraggableTabBarHostingView.swift`
- Modify: `Sources/AgentStudio/Core/Views/Drawer/DrawerPanel.swift`
- Modify: `Sources/AgentStudio/Core/Views/Drawer/DrawerPanelOverlay.swift`
- Modify: `Sources/AgentStudio/Core/Views/Drawer/DrawerOverlay.swift`
- Modify: `Sources/AgentStudio/Features/Sidebar/RepoSidebarContentView.swift`
- Modify: `Sources/AgentStudio/App/Panes/TabBar/ArrangementPanel.swift`

- [ ] **Step 1: Replace pane content/container tap dispatch**

```swift
// before
.onTapGesture {
    actionDispatcher.dispatch(.focusPane(tabId: tabId, paneId: paneHost.id))
}

// after
.onTapGesture {
    paneFocusRouter.handle(
        .contentClick(
            PaneContentClickFocusTrigger(
                targetPaneId: paneHost.id,
                location: .content,
                clickPhase: .completed
            )
        )
    )
}
```

- [ ] **Step 2: Replace tab and drawer click paths**

```swift
// tab click
onSelect: { tabId in
    paneFocusRouter.handle(
        .tabClick(PaneTabClickFocusTrigger(targetTabId: tabId))
    )
}

// drawer selection
case .focusPane(_, let paneId):
    paneFocusRouter.handle(
        .drawer(.selectPane(parentPaneId: parentPaneId, drawerPaneId: paneId))
    )
```

- [ ] **Step 3: Replace explicit refocus callers**

```swift
// before
CommandDispatcher.shared.appCommandRouter?.refocusActivePane()

// after
CommandDispatcher.shared.appCommandRouter?.requestPaneRefocus(.sidebarFilterClosed)
```

- [ ] **Step 4: Run focused integration tests**

Run:

```bash
SWIFT_BUILD_DIR=.build-agent-pane-focus-callers \
swift test --build-path "$SWIFT_BUILD_DIR" \
  --filter "PaneTabViewControllerCommandTests|WebviewPaneControllerTests|ManagementModeTests"
```

Expected: PASS with click flows entering the new system instead of directly mutating focus.

- [ ] **Step 5: Commit**

```bash
git add Sources/AgentStudio/Core/Views/Splits/PaneLeafContainer.swift \
        Sources/AgentStudio/App/Panes/TabBar/CustomTabBar.swift \
        Sources/AgentStudio/App/Panes/TabBar/DraggableTabBarHostingView.swift \
        Sources/AgentStudio/Core/Views/Drawer/DrawerPanel.swift \
        Sources/AgentStudio/Core/Views/Drawer/DrawerPanelOverlay.swift \
        Sources/AgentStudio/Core/Views/Drawer/DrawerOverlay.swift \
        Sources/AgentStudio/Features/Sidebar/RepoSidebarContentView.swift \
        Sources/AgentStudio/App/Panes/TabBar/ArrangementPanel.swift
git commit -m "feat: route pane-affecting click triggers through pane focus system"
```

---

### Task 7: Remove old pane-focus command paths and direct helpers

**Files:**
- Modify: `Sources/AgentStudio/App/Commands/AppCommand.swift`
- Modify: `Sources/AgentStudio/Core/Actions/PaneActionCommand.swift`
- Modify: `Sources/AgentStudio/Core/Actions/ActionResolver.swift`
- Modify: `Sources/AgentStudio/Core/Actions/ActionValidator.swift`
- Modify: `Sources/AgentStudio/App/Coordination/PaneCoordinator+ActionExecution.swift`

- [ ] **Step 1: Remove pane focus from PaneActionCommand**

```swift
// delete
case focusPane(tabId: UUID, paneId: UUID)
```

- [ ] **Step 2: Remove old command resolution for pane focus**

```swift
// delete old .focusPane resolution branches
// replace command-origin focus with PaneFocusTrigger.command(...)
```

- [ ] **Step 3: Replace old coordinator execution paths**

```swift
// before
case .focusPane(let tabId, let paneId):
    store.tabLayoutAtom.setActivePane(paneId, inTab: tabId)
    focusVisiblePaneHost(paneId)

// after
// no PaneActionCommand.focusPane case remains
```

- [ ] **Step 4: Run focused regression tests**

Run:

```bash
SWIFT_BUILD_DIR=.build-agent-pane-focus-cutover \
swift test --build-path "$SWIFT_BUILD_DIR" \
  --filter "ActionResolverTests|ActionValidatorTests|PaneTabViewControllerCommandTests|WebviewPaneControllerTests"
```

Expected: PASS with old focus command paths removed.

- [ ] **Step 5: Commit**

```bash
git add Sources/AgentStudio/App/Commands/AppCommand.swift \
        Sources/AgentStudio/Core/Actions/PaneActionCommand.swift \
        Sources/AgentStudio/Core/Actions/ActionResolver.swift \
        Sources/AgentStudio/Core/Actions/ActionValidator.swift \
        Sources/AgentStudio/App/Coordination/PaneCoordinator+ActionExecution.swift
git commit -m "refactor: remove legacy pane focus command paths"
```

---

### Task 8: Full verification and documentation touch-up

**Files:**
- Modify: `docs/superpowers/specs/2026-04-14-pane-focus-system-design.md` (only if implementation clarified naming or boundaries)
- Verify: updated source and test files above

- [ ] **Step 1: Run lint**

Run:

```bash
mise run lint
```

Expected: PASS, exit code `0`

- [ ] **Step 2: Run full test wrapper**

Run:

```bash
AGENT_RUN_ID=pane-focus-system mise run test
```

Expected:
- main parallel suite passes
- serialized WebKit suites pass
- any E2E suites are skipped only if project wrapper explicitly disables them

- [ ] **Step 3: Verify the key bug scenario manually in tests or UI harness**

Minimum expected scenarios:

```text
- click active GitHub "Go to file" input -> caret remains, typing works
- click active Google search input -> caret remains, typing works
- click inactive terminal pane -> pane activates and terminal focus syncs
- enter management mode -> mode policy applies explicit responder/content behavior
```

- [ ] **Step 4: Final commit**

```bash
git add Sources/AgentStudio/App/Panes/Focus \
        Tests/AgentStudioTests/App/Panes/Focus \
        Sources/AgentStudio/Core/Views/Splits/PaneLeafContainer.swift \
        Sources/AgentStudio/App/Panes/PaneTabViewController.swift \
        Sources/AgentStudio/App/Panes/Hosting/PaneHostView.swift \
        Sources/AgentStudio/App/Lifecycle/ManagementModeMonitor.swift \
        Sources/AgentStudio/App/Windows/MainSplitViewController.swift \
        Sources/AgentStudio/App/Windows/MainWindowController.swift \
        Sources/AgentStudio/App/Boot/AppDelegate+LifecycleRouting.swift \
        Sources/AgentStudio/Features/Sidebar/RepoSidebarContentView.swift \
        Sources/AgentStudio/Core/Views/Drawer/DrawerPanel.swift \
        Sources/AgentStudio/Core/Views/Drawer/DrawerPanelOverlay.swift \
        Sources/AgentStudio/Core/Views/Drawer/DrawerOverlay.swift \
        Sources/AgentStudio/App/Panes/TabBar/CustomTabBar.swift \
        Sources/AgentStudio/App/Panes/TabBar/DraggableTabBarHostingView.swift \
        Sources/AgentStudio/App/Panes/TabBar/ArrangementPanel.swift \
        Sources/AgentStudio/App/Commands/AppCommand.swift \
        Sources/AgentStudio/Core/Actions/PaneActionCommand.swift \
        Sources/AgentStudio/Core/Actions/ActionResolver.swift \
        Sources/AgentStudio/Core/Actions/ActionValidator.swift \
        Sources/AgentStudio/App/Coordination/PaneCoordinator+ActionExecution.swift \
        Sources/AgentStudio/App/Coordination/PaneCoordinator+ViewHelpers.swift \
        docs/superpowers/specs/2026-04-14-pane-focus-system-design.md
git commit -m "feat: replace pane focus with policy-driven system"
```

---

## Self-Review

**Spec coverage**

```text
- pane-scoped naming: covered by new App/Panes/Focus file set
- exhaustive trigger/decision enums: Task 2
- single full PaneFocusContext: Task 2 + orchestrator context assembly
- typed family deciders: Tasks 3 and 4
- one MainActor executor: Task 5
- full clean cutover from PaneActionCommand.focusPane: Task 7
- missing scenarios (window activation, pane creation, repair): Tasks 4, 5, 8
```

**Placeholder scan**

```text
- no TBD/TODO markers
- each task names exact files
- each code-changing task contains concrete Swift code to add/replace
- each verification step names exact commands and expected outcomes
```

**Type consistency**

```text
- top-level enums: PaneFocusTrigger / PaneFocusDecision
- context snapshot: PaneFocusContext
- dispatcher: PaneFocusOrchestrator
- effect applier: PaneFocusExecutor
- family implementations use "Decider" suffix consistently
```
