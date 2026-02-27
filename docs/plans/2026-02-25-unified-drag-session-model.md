# Unified Drag Session Model Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Implement a single validator-driven drag session model so split/drawer/tab drag targets, commit behavior, and teardown are consistent and deterministic across pane types.

**Architecture:** Introduce a shared drag intent pipeline: `payload + pointer + immutable snapshot -> candidate action -> validator -> target visibility`. Preview and commit both use the same candidate action model, and teardown is centralized to guarantee target cleanup on drop/release/focus/mode transitions. Cmd+E overlay visibility is moved to container-level pointer resolution instead of per-pane hover transitions.

**Tech Stack:** Swift 6, AppKit, SwiftUI, Swift Testing (`import Testing`), `mise` task runner.

---

### Task 1: Lock the behavior contract with failing tests (no implementation changes yet)

**Files:**
- Create: `Tests/AgentStudioTests/Core/Views/Splits/DragSessionContractTests.swift`
- Create: `Tests/AgentStudioTests/Core/Views/TabBar/TabBarPaneDropContractTests.swift`
- Modify: `Tests/AgentStudioTests/Core/Views/Splits/PaneDropTargetResolutionTests.swift`
- Modify: `Tests/AgentStudioTests/App/ManagementModeTests.swift`

**Step 1: Write the failing tests for the unified contract**

```swift
@Suite("Drag Session Contract")
struct DragSessionContractTests {
    @Test("preview target is visible only when candidate action validates")
    func previewIsValidatorGated() { /* assert invalid candidates render no target */ }

    @Test("drop teardown always clears target on release/focus-loss/mode-off")
    func teardownAlwaysClearsVisualTarget() { /* assert terminal target == nil */ }
}
```

```swift
@Suite("Tab Bar Pane Drop Contract")
struct TabBarPaneDropContractTests {
    @Test("insertion-gap drop creates new tab at insertion index")
    func insertionGapCreatesNewTabAtIndex() { /* no existing-tab merge fallback */ }

    @Test("tab-interior drop for pane drag is rejected for extract flow")
    func tabInteriorIsNotInsertionGap() { /* no ambiguous semantics */ }
}
```

**Step 2: Run tests to verify failures**

Run:
```bash
SWIFT_BUILD_DIR=".build-agent-unified-drag" swift test --build-path "$SWIFT_BUILD_DIR" --filter "DragSessionContractTests"
SWIFT_BUILD_DIR=".build-agent-unified-drag" swift test --build-path "$SWIFT_BUILD_DIR" --filter "TabBarPaneDropContractTests"
```

Expected: FAIL with missing types / behavior mismatch.

**Step 3: Commit test scaffolding**

```bash
git add Tests/AgentStudioTests/Core/Views/Splits/DragSessionContractTests.swift Tests/AgentStudioTests/Core/Views/TabBar/TabBarPaneDropContractTests.swift Tests/AgentStudioTests/Core/Views/Splits/PaneDropTargetResolutionTests.swift Tests/AgentStudioTests/App/ManagementModeTests.swift
git commit -m "test: define unified drag session behavioral contract"
```

---

### Task 2: Introduce shared drag session state model

**Files:**
- Create: `Sources/AgentStudio/Core/Views/Splits/DragSessionState.swift`
- Create: `Sources/AgentStudio/Core/Views/Splits/DragCandidateAction.swift`
- Modify: `Sources/AgentStudio/Core/Views/Splits/SplitContainerDropCaptureOverlay.swift`
- Test: `Tests/AgentStudioTests/Core/Views/Splits/DragSessionContractTests.swift`

**Step 1: Write failing state-machine tests**

```swift
@Test("armed state requires a validated candidate action")
func armedRequiresCandidate() {
    #expect(DragSessionState.armed(candidate: nil).isValid == false)
}
```

**Step 2: Run test to verify it fails**

Run:
```bash
SWIFT_BUILD_DIR=".build-agent-unified-drag" swift test --build-path "$SWIFT_BUILD_DIR" --filter "armedRequiresCandidate"
```

Expected: FAIL (type/state not implemented).

**Step 3: Write minimal state model implementation**

```swift
enum DragSessionState: Equatable {
    case idle
    case previewing(source: SplitDropPayload)
    case armed(source: SplitDropPayload, candidate: DragCandidateAction)
    case committing(candidate: DragCandidateAction)
    case teardown
}

struct DragCandidateAction: Equatable {
    let paneAction: PaneAction
    let target: PaneDropTarget
}
```

**Step 4: Integrate state holder into drop capture coordinator**

```swift
@MainActor
final class Coordinator {
    private(set) var dragSession: DragSessionState = .idle
}
```

**Step 5: Run tests to verify pass**

Run:
```bash
SWIFT_BUILD_DIR=".build-agent-unified-drag" swift test --build-path "$SWIFT_BUILD_DIR" --filter "DragSessionContractTests"
```

Expected: PASS for new state tests.

**Step 6: Commit**

```bash
git add Sources/AgentStudio/Core/Views/Splits/DragSessionState.swift Sources/AgentStudio/Core/Views/Splits/DragCandidateAction.swift Sources/AgentStudio/Core/Views/Splits/SplitContainerDropCaptureOverlay.swift Tests/AgentStudioTests/Core/Views/Splits/DragSessionContractTests.swift
git commit -m "feat: add shared drag session state machine primitives"
```

---

### Task 3: Unify preview target visibility with candidate action + validator

**Files:**
- Create: `Sources/AgentStudio/Core/Views/Splits/DragCandidateResolver.swift`
- Modify: `Sources/AgentStudio/Core/Views/Splits/SplitContainerDropCaptureOverlay.swift`
- Modify: `Sources/AgentStudio/App/Panes/PaneTabViewController.swift`
- Test: `Tests/AgentStudioTests/Core/Views/Splits/DragSessionContractTests.swift`

**Step 1: Write failing test for validator-gated preview**

```swift
@Test("invalid candidate never produces visible target")
func invalidCandidateDoesNotRenderTarget() {
    #expect(resolvedCandidate == nil)
}
```

**Step 2: Run test to verify failure**

Run:
```bash
SWIFT_BUILD_DIR=".build-agent-unified-drag" swift test --build-path "$SWIFT_BUILD_DIR" --filter "invalidCandidateDoesNotRenderTarget"
```

Expected: FAIL.

**Step 3: Implement candidate resolver**

```swift
struct DragCandidateResolver {
    static func resolve(
        payload: SplitDropPayload,
        location: CGPoint,
        paneFrames: [UUID: CGRect],
        containerBounds: CGRect,
        snapshot: ActionStateSnapshot,
        destinationTabId: UUID
    ) -> DragCandidateAction? {
        guard let target = PaneDragCoordinator.resolveTarget(
            location: location,
            paneFrames: paneFrames,
            containerBounds: containerBounds
        ) else { return nil }
        guard let action = ActionResolver.resolveDrop(
            payload: payload,
            destinationPaneId: target.paneId,
            destinationTabId: destinationTabId,
            zone: target.zone,
            state: snapshot
        ) else { return nil }
        guard case .success = ActionValidator.validate(action, state: snapshot) else { return nil }
        return DragCandidateAction(paneAction: action, target: target)
    }
}
```

**Step 4: Wire preview path to resolver output only**

```swift
if let candidate = resolverCandidate {
    setTarget(candidate.target)
    dragSession = .armed(source: payload, candidate: candidate)
} else {
    setTarget(nil)
    dragSession = .previewing(source: payload)
}
```

**Step 5: Run tests**

Run:
```bash
SWIFT_BUILD_DIR=".build-agent-unified-drag" swift test --build-path "$SWIFT_BUILD_DIR" --filter "DragSessionContractTests"
```

Expected: PASS.

**Step 6: Commit**

```bash
git add Sources/AgentStudio/Core/Views/Splits/DragCandidateResolver.swift Sources/AgentStudio/Core/Views/Splits/SplitContainerDropCaptureOverlay.swift Sources/AgentStudio/App/Panes/PaneTabViewController.swift Tests/AgentStudioTests/Core/Views/Splits/DragSessionContractTests.swift
git commit -m "feat: validator-gate drag preview targets via unified candidate resolver"
```

---

### Task 4: Enforce drawer target geometry policy (pane-union bounds only)

**Files:**
- Modify: `Sources/AgentStudio/Core/Views/Drawer/DrawerPanel.swift`
- Modify: `Sources/AgentStudio/Core/Views/Splits/PaneDragCoordinator.swift`
- Test: `Tests/AgentStudioTests/Core/Views/Splits/PaneDropTargetResolutionTests.swift`

**Step 1: Write failing drawer-boundary tests**

```swift
@Test("drawer edge corridor excludes non-pane panel chrome")
func drawerCorridorUsesPaneUnionBounds() { /* assert no target in handle/padding zone */ }
```

**Step 2: Run tests to confirm failure**

Run:
```bash
SWIFT_BUILD_DIR=".build-agent-unified-drag" swift test --build-path "$SWIFT_BUILD_DIR" --filter "drawerCorridorUsesPaneUnionBounds"
```

Expected: FAIL.

**Step 3: Implement pane-union bounds calculation in drawer panel**

```swift
let paneUnionBounds = drawerPaneFrames.values.reduce(into: CGRect.null) { partial, frame in
    partial = partial.union(frame)
}
let effectiveBounds = paneUnionBounds.isNull ? containerBounds : paneUnionBounds
```

**Step 4: Feed effective bounds into drop resolver**

```swift
SplitContainerDropCaptureOverlay(
    paneFrames: drawerPaneFrames,
    containerBounds: effectiveBounds,
    ...
)
```

**Step 5: Run tests**

Run:
```bash
SWIFT_BUILD_DIR=".build-agent-unified-drag" swift test --build-path "$SWIFT_BUILD_DIR" --filter "PaneDropTargetResolutionTests"
```

Expected: PASS.

**Step 6: Commit**

```bash
git add Sources/AgentStudio/Core/Views/Drawer/DrawerPanel.swift Sources/AgentStudio/Core/Views/Splits/PaneDragCoordinator.swift Tests/AgentStudioTests/Core/Views/Splits/PaneDropTargetResolutionTests.swift
git commit -m "fix: constrain drawer drag target corridors to pane-union bounds"
```

---

### Task 5: Rework tab-bar pane drag semantics to insertion-gap-only new-tab creation

**Files:**
- Modify: `Sources/AgentStudio/Core/Views/DraggableTabBarHostingView.swift`
- Modify: `Sources/AgentStudio/App/Panes/PaneTabViewController.swift`
- Modify: `Sources/AgentStudio/Core/Views/CustomTabBar.swift`
- Test: `Tests/AgentStudioTests/Core/Views/TabBar/TabBarPaneDropContractTests.swift`

**Step 1: Write failing tab-region classifier tests**

```swift
@Test("pane drop in insertion gap extracts to new tab at index")
func insertionGapExtractsAtIndex() {}

@Test("pane drop over tab interior does not become insertion extract")
func tabInteriorDoesNotExtract() {}
```

**Step 2: Run failing tests**

Run:
```bash
SWIFT_BUILD_DIR=".build-agent-unified-drag" swift test --build-path "$SWIFT_BUILD_DIR" --filter "TabBarPaneDropContractTests"
```

Expected: FAIL.

**Step 3: Implement explicit tab-drop region classification**

```swift
enum TabBarDropRegion {
    case insertionGap(index: Int)
    case tabInterior(tabId: UUID)
    case outside
}
```

```swift
switch classifyPaneDropRegion(dropPoint) {
case .insertionGap(let index):
    postExtractPaneRequested(targetTabIndex: index)
case .tabInterior:
    return false
case .outside:
    return false
}
```

**Step 4: Keep extraction commit path validator-routed**

```swift
dispatchAction(.extractPaneToTab(tabId: tabId, paneId: paneId))
store.moveTab(fromId: extractedTabId, toIndex: targetTabIndex)
```

**Step 5: Run tests**

Run:
```bash
SWIFT_BUILD_DIR=".build-agent-unified-drag" swift test --build-path "$SWIFT_BUILD_DIR" --filter "TabBarPaneDropContractTests"
```

Expected: PASS.

**Step 6: Commit**

```bash
git add Sources/AgentStudio/Core/Views/DraggableTabBarHostingView.swift Sources/AgentStudio/App/Panes/PaneTabViewController.swift Sources/AgentStudio/Core/Views/CustomTabBar.swift Tests/AgentStudioTests/Core/Views/TabBar/TabBarPaneDropContractTests.swift
git commit -m "fix: enforce insertion-gap-only pane-to-new-tab semantics on tab bar"
```

---

### Task 6: Centralize drag teardown and target cleanup finalizer

**Files:**
- Modify: `Sources/AgentStudio/Core/Views/Splits/SplitContainerDropCaptureOverlay.swift`
- Modify: `Sources/AgentStudio/Core/Views/Drawer/DrawerPanel.swift`
- Modify: `Sources/AgentStudio/Core/Views/Splits/TerminalSplitContainer.swift`
- Modify: `Sources/AgentStudio/Core/Views/DraggableTabBarHostingView.swift`
- Test: `Tests/AgentStudioTests/Core/Views/Splits/DragSessionContractTests.swift`

**Step 1: Write failing teardown matrix tests**

```swift
@Test("teardown clears on perform success/fail")
func teardownOnPerformOutcomes() {}

@Test("teardown clears on mouse release + app resign + mode exit")
func teardownOnLifecycleEvents() {}
```

**Step 2: Run failing tests**

Run:
```bash
SWIFT_BUILD_DIR=".build-agent-unified-drag" swift test --build-path "$SWIFT_BUILD_DIR" --filter "teardownOn"
```

Expected: FAIL.

**Step 3: Implement shared teardown helper**

```swift
func finalizeDragSession() {
    setTarget(nil)
    dragSession = .idle
}
```

**Step 4: Call finalizer in every terminal path**

```swift
override func draggingExited(...) { finalizeDragSession() }
override func draggingEnded(...) { finalizeDragSession() }
override func performDragOperation(...) -> Bool {
    defer { finalizeDragSession() }
    ...
}
```

**Step 5: Run tests**

Run:
```bash
SWIFT_BUILD_DIR=".build-agent-unified-drag" swift test --build-path "$SWIFT_BUILD_DIR" --filter "DragSessionContractTests"
```

Expected: PASS.

**Step 6: Commit**

```bash
git add Sources/AgentStudio/Core/Views/Splits/SplitContainerDropCaptureOverlay.swift Sources/AgentStudio/Core/Views/Drawer/DrawerPanel.swift Sources/AgentStudio/Core/Views/Splits/TerminalSplitContainer.swift Sources/AgentStudio/Core/Views/DraggableTabBarHostingView.swift Tests/AgentStudioTests/Core/Views/Splits/DragSessionContractTests.swift
git commit -m "fix: centralize drag teardown and guaranteed target cleanup"
```

---

### Task 7: Make Cmd+E controls appear immediately via container-level pointer resolver

**Files:**
- Modify: `Sources/AgentStudio/Core/Views/Splits/PaneLeafContainer.swift`
- Modify: `Sources/AgentStudio/Core/Views/Splits/TerminalSplitContainer.swift`
- Modify: `Sources/AgentStudio/App/ManagementModeMonitor.swift`
- Test: `Tests/AgentStudioTests/App/ManagementModeTests.swift`

**Step 1: Write failing immediate-activation test**

```swift
@Test("management controls visible immediately on activation without pointer motion")
func controlsAppearImmediatelyOnCmdE() { /* assert hovered pane resolves at activation */ }
```

**Step 2: Run failing test**

Run:
```bash
SWIFT_BUILD_DIR=".build-agent-unified-drag" swift test --build-path "$SWIFT_BUILD_DIR" --filter "controlsAppearImmediatelyOnCmdE"
```

Expected: FAIL.

**Step 3: Replace per-pane global-frame fallback with container hover resolver**

```swift
// Container computes hoveredPaneId from pointer + paneFrames in one coordinate system.
@State private var hoveredPaneId: UUID?
```

```swift
onChange(of: managementMode.isActive) { _, active in
    if active { hoveredPaneId = resolveHoveredPane(at: currentPointerInContainer) }
}
```

**Step 4: Render controls by `hoveredPaneId == paneView.id`**

```swift
let isManagementHovered = hoveredPaneId == paneView.id
```

**Step 5: Run tests**

Run:
```bash
SWIFT_BUILD_DIR=".build-agent-unified-drag" swift test --build-path "$SWIFT_BUILD_DIR" --filter "ManagementModeTests"
```

Expected: PASS.

**Step 6: Commit**

```bash
git add Sources/AgentStudio/Core/Views/Splits/PaneLeafContainer.swift Sources/AgentStudio/Core/Views/Splits/TerminalSplitContainer.swift Sources/AgentStudio/App/ManagementModeMonitor.swift Tests/AgentStudioTests/App/ManagementModeTests.swift
git commit -m "fix: resolve management hover at container level for immediate Cmd+E controls"
```

---

### Task 8: Full validation matrix and documentation

**Files:**
- Modify: `docs/architecture/appkit_swiftui_architecture.md`
- Modify: `docs/architecture/pane_runtime_architecture.md`
- Modify: `Tests/AgentStudioTests/Core/Views/Splits/DragSessionContractTests.swift`

**Step 1: Add final matrix tests**

```swift
@Test("matrix: terminal/webview/minimized/drawer panes share same drag contract")
func paneTypeAgnosticDragContract() {}
```

**Step 2: Run focused matrix tests**

Run:
```bash
SWIFT_BUILD_DIR=".build-agent-unified-drag" swift test --build-path "$SWIFT_BUILD_DIR" --filter "DragSessionContractTests"
```

Expected: PASS.

**Step 3: Run required project checks**

Run:
```bash
mise run format
mise run lint
mise run test
```

Expected:
- format: success
- lint: 0 violations + boundary checks pass
- test: full pass

**Step 4: Update architecture docs with final event-flow diagrams**

```markdown
### Unified Drag Session
payload + pointer + snapshot -> candidate action -> validator -> target visibility + commit
```

**Step 5: Commit**

```bash
git add docs/architecture/appkit_swiftui_architecture.md docs/architecture/pane_runtime_architecture.md Tests/AgentStudioTests/Core/Views/Splits/DragSessionContractTests.swift
git commit -m "docs: record unified drag session model and verification matrix"
```

---

### Execution Notes

- Use `@superpowers:test-driven-development` for each task.
- Use `@superpowers:systematic-debugging` if any drag-path mismatch appears during implementation.
- Keep each task small and independently commit as above.
- Do not touch sidebar files in this plan.

