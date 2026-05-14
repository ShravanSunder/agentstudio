# Drawer Interaction And Drag Repair Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restore drawer drag target registration/visibility, outside-click dismissal, and strict “drawer open owns interaction” behavior without breaking normal main-tab pane drag/drop.

**Architecture:** Treat drawer-open as an explicit interaction ownership state, not as scattered booleans. The drawer keeps the debug branch’s proven shape: tab-level AppKit drawer capture, panel-only coordinate bridge, drawer-specific dispatch, and drawer-local visual rendering. Main panes are inert while a drawer is expanded; normal main-pane behavior returns when no drawer is expanded.

**Tech Stack:** Swift 6.2, SwiftUI, AppKit `NSViewRepresentable`, Swift Testing, existing `mise run build/test/lint` tasks.

---

## Evidence Baseline

Use these files as the source of truth before editing:

- `/Users/shravansunder/Documents/dev/project-dev/agent-studio.drawer-target-debugging/docs/oracle/drawer-drag-experiment-tracker.md`
- `/Users/shravansunder/Documents/dev/project-dev/agent-studio.drawer-target-debugging/docs/oracle/drawer-drag-experiment-runbook.md`

Debug branch findings to preserve:

- Nested `DrawerSplitContainerDropCaptureOverlay` inside `DrawerPanel` is unreachable by AppKit drag destination traversal.
- Drawer drag must be captured by a shallow tab-level `DrawerSplitContainerDropCaptureOverlay`.
- Drawer drops must use drawer-specific dispatch, not the main split dispatcher.
- `DrawerPanelFrameInTabKey` must be panel-only, emitted from `DrawerPanel`, not from the outer overlay that includes connector height.
- While a drawer is expanded, main pane interaction/focus behind the drawer must be suppressed.

The AppKit drag-destination invariant:

```text
Once a registered NSView whose frame covers the drag location and whose registeredDraggedTypes
intersect the pasteboard types receives draggingEntered:, it owns the entire drag session.
Returning [] does not make AppKit fall through to another registered destination.
```

The first checkpoint must therefore remove the main split capture NSView while a drawer is expanded. Disabling commit logic is not enough: if the full-tab main capture is still registered for `.agentStudioPaneDrop`, it can win the session at drag start and silence the drawer capture for the rest of the drag.

Outside-click dismissal is a separate AppKit event-routing problem. The local monitor must consume the dismissing mouse event by returning `nil`; otherwise the same click collapses the drawer and then propagates into the underlying main pane.

---

## File Structure

Create:

- `Sources/AgentStudio/Core/Views/Panes/PaneDragCaptureOwnership.swift`
  - Discriminated union for `.none`, `.main`, and `.drawer(parentPaneId:geometry:)`.
  - Single source of truth for whether the tab mounts main capture, drawer capture, or no capture.

- `Tests/AgentStudioTests/Core/Views/Panes/PaneDragCaptureOwnershipTests.swift`
  - Unit tests for the capture-owner state machine.

Modify:

- `Sources/AgentStudio/Core/Views/Panes/FlatTabStripContainer.swift`
  - Use `PaneDragCaptureOwner` instead of separately computing `mainSplitDragCaptureEnabled` and drawer capture eligibility.
  - Switch over the ownership enum so main and drawer capture cannot both mount.

- `Sources/AgentStudio/Core/Views/Panes/PaneInteractionOcclusionPolicy.swift`
  - Add a typed tap/focus decision enum so main-pane focus under expanded drawer is unrepresentable at the call site.

- `Sources/AgentStudio/Core/Views/Panes/PaneLeafContainer.swift`
  - Use the tap/focus decision before calling `onPaneFocusTrigger`.
  - Main pane taps under expanded drawer become no-ops; drawer child taps still focus drawer children.

- `Sources/AgentStudio/Core/Views/Drawer/DrawerPanelOverlay.swift`
  - Route outside-click dismissal through a typed `DrawerDismissMouseRouting` decision.
  - Return `nil` from the local monitor when the click dismisses so main panes cannot receive the same mouse event.
  - Keep `DrawerPanelFrameInTabKey` panel-only in `DrawerPanel`.

- `Tests/AgentStudioTests/Core/Views/Panes/PaneInteractionOcclusionPolicyTests.swift`
  - Add tests for typed tap/focus decisions.

- `Tests/AgentStudioTests/Core/Views/Drawer/DrawerPanelOverlayStateTests.swift`
  - Add tests for outside-dismiss event routing.

- `Tests/AgentStudioTests/Core/Views/Drawer/DrawerCompositionGateTests.swift`
  - Add end-to-end headless composition tests for drawer target visibility and AppKit ownership.

Keep:

- `Sources/AgentStudio/Core/Views/Drawer/DrawerCaptureGeometry.swift`
  - Panel-only capture geometry stays.

- `Sources/AgentStudio/Core/Views/Drawer/DrawerDropDispatch.swift`
  - Drawer-specific dispatch stays.

- `Sources/AgentStudio/Core/Views/Drawer/DrawerPanel.swift`
  - `DrawerPanelFrameInTabKey` remains emitted from `DrawerPanel` body.

---

### Task 1: Capture Ownership Discriminated Union

**Files:**
- Create: `Sources/AgentStudio/Core/Views/Panes/PaneDragCaptureOwnership.swift`
- Create: `Tests/AgentStudioTests/Core/Views/Panes/PaneDragCaptureOwnershipTests.swift`
- Modify: `Sources/AgentStudio/Core/Views/Panes/FlatTabStripContainer.swift`

- [ ] **Step 1: Write failing capture-owner tests**

Create `Tests/AgentStudioTests/Core/Views/Panes/PaneDragCaptureOwnershipTests.swift`:

```swift
import CoreGraphics
import Foundation
import Testing

@testable import AgentStudio

@Suite(.serialized)
struct PaneDragCaptureOwnershipTests {
    @Test
    func inactiveManagement_ownsNoCapture() {
        let owner = PaneDragCaptureOwner.resolve(
            managementLayerActive: false,
            expandedDrawerParentPaneId: nil,
            drawerPanelFrameInTab: CGRect(x: 10, y: 20, width: 300, height: 200),
            drawerPaneFramesInDrawer: [:]
        )

        #expect(owner == .none)
    }

    @Test
    func activeManagementWithoutDrawer_ownsMainCapture() {
        let owner = PaneDragCaptureOwner.resolve(
            managementLayerActive: true,
            expandedDrawerParentPaneId: nil,
            drawerPanelFrameInTab: .zero,
            drawerPaneFramesInDrawer: [:]
        )

        #expect(owner == .main)
    }

    @Test
    func activeManagementWithReadyDrawer_ownsDrawerCaptureOnly() throws {
        let parentPaneId = UUID()
        let drawerPaneId = UUID()
        let owner = PaneDragCaptureOwner.resolve(
            managementLayerActive: true,
            expandedDrawerParentPaneId: parentPaneId,
            drawerPanelFrameInTab: CGRect(x: 100, y: 200, width: 500, height: 180),
            drawerPaneFramesInDrawer: [
                drawerPaneId: CGRect(x: 20, y: 30, width: 120, height: 80)
            ]
        )

        guard case .drawer(let resolvedParentPaneId, let geometry) = owner else {
            Issue.record("Expected drawer owner")
            return
        }
        #expect(resolvedParentPaneId == parentPaneId)
        #expect(geometry.containerBounds == CGRect(x: 0, y: 0, width: 500, height: 180))
    }

    @Test
    func activeManagementWithDrawerButMissingPanelFrame_ownsNoCaptureNotMainCapture() {
        let owner = PaneDragCaptureOwner.resolve(
            managementLayerActive: true,
            expandedDrawerParentPaneId: UUID(),
            drawerPanelFrameInTab: .zero,
            drawerPaneFramesInDrawer: [:]
        )

        #expect(owner == .none)
    }

    @Test
    func activeManagementWithDrawerAndOutOfBoundsPaneFrame_ownsNoCaptureNotMainCapture() {
        let owner = PaneDragCaptureOwner.resolve(
            managementLayerActive: true,
            expandedDrawerParentPaneId: UUID(),
            drawerPanelFrameInTab: CGRect(x: 100, y: 200, width: 500, height: 180),
            drawerPaneFramesInDrawer: [
                UUID(): CGRect(x: 20, y: 30, width: 800, height: 80)
            ]
        )

        #expect(owner == .none)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
mise run test --filter PaneDragCaptureOwnershipTests
```

Expected: FAIL because `PaneDragCaptureOwner` does not exist.

- [ ] **Step 3: Implement the ownership enum**

Create `Sources/AgentStudio/Core/Views/Panes/PaneDragCaptureOwnership.swift`:

```swift
import CoreGraphics
import Foundation

enum PaneDragCaptureOwner: Equatable {
    case none
    case main
    case drawer(parentPaneId: UUID, geometry: DrawerCaptureGeometry)

    static func resolve(
        managementLayerActive: Bool,
        expandedDrawerParentPaneId: UUID?,
        drawerPanelFrameInTab: CGRect,
        drawerPaneFramesInDrawer: [UUID: CGRect]
    ) -> Self {
        guard managementLayerActive else { return .none }
        guard let expandedDrawerParentPaneId else { return .main }
        guard
            let geometry = DrawerCaptureGeometry.make(
                panelFrameInTab: drawerPanelFrameInTab,
                paneFramesInDrawer: drawerPaneFramesInDrawer
            )
        else {
            return .none
        }
        return .drawer(parentPaneId: expandedDrawerParentPaneId, geometry: geometry)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run:

```bash
mise run test --filter PaneDragCaptureOwnershipTests
```

Expected: PASS.

- [ ] **Step 5: Wire ownership into `FlatTabStripContainer`**

In `Sources/AgentStudio/Core/Views/Panes/FlatTabStripContainer.swift`, replace the `mainSplitDragCaptureEnabled` local with:

```swift
let dragCaptureOwner = PaneDragCaptureOwner.resolve(
    managementLayerActive: managementLayer.isActive,
    expandedDrawerParentPaneId: expandedDrawerParentPaneId,
    drawerPanelFrameInTab: drawerPanelFrameInTab,
    drawerPaneFramesInDrawer: drawerPaneFramesInDrawer
)
```

Replace:

```swift
if managementLayer.isActive && mainSplitDragCaptureEnabled {
```

with:

```swift
if case .main = dragCaptureOwner {
```

Replace:

```swift
tabLevelDrawerCapture(expandedDrawerParentPaneId: expandedDrawerParentPaneId)
```

with:

```swift
tabLevelDrawerCapture(owner: dragCaptureOwner)
```

Replace the helper signature and opening guard:

```swift
@ViewBuilder
private func tabLevelDrawerCapture(owner: PaneDragCaptureOwner) -> some View {
    if case .drawer(let expandedDrawerPaneId, let captureGeometry) = owner,
        let expandedDrawer = store.paneAtom.pane(expandedDrawerPaneId)?.drawer
    {
        let drawerBounds = captureGeometry.containerBounds
        let drawerDispatchContext = DrawerDropDispatch.context(
            parentPaneId: expandedDrawerPaneId,
            store: store
        )
        DrawerSplitContainerDropCaptureOverlay(
            paneFrames: captureGeometry.paneFramesInDrawer,
            layout: expandedDrawer.layout,
            minimizedPaneIds: expandedDrawer.minimizedPaneIds,
            containerBounds: drawerBounds,
            target: $drawerDropTarget,
            isManagementLayerActive: true,
            shouldAcceptDrop: { payload, target, sizingMode in
                DrawerDropDispatch.shouldAcceptDrop(
                    payload: payload,
                    target: target,
                    sizingMode: sizingMode,
                    context: drawerDispatchContext
                )
            },
            handleDrop: { payload, target, sizingMode in
                DrawerDropDispatch.handleDrop(
                    payload: payload,
                    target: target,
                    sizingMode: sizingMode,
                    context: drawerDispatchContext,
                    actionDispatcher: actionDispatcher
                )
            }
        )
        .frame(width: drawerBounds.width, height: drawerBounds.height)
        .position(x: captureGeometry.panelFrameInTab.midX, y: captureGeometry.panelFrameInTab.midY)
    }
}
```

- [ ] **Step 6: Run ownership and drawer capture tests**

Run:

```bash
mise run test --filter 'PaneDragCaptureOwnershipTests|FlatTabStripContainerDragOwnershipTests|DrawerCompositionGateTests'
```

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add Sources/AgentStudio/Core/Views/Panes/PaneDragCaptureOwnership.swift \
  Sources/AgentStudio/Core/Views/Panes/FlatTabStripContainer.swift \
  Tests/AgentStudioTests/Core/Views/Panes/PaneDragCaptureOwnershipTests.swift
git commit -m "fix: make pane drag capture ownership explicit" \
  -m "Co-authored-by: Codex <noreply@openai.com>"
```

---

### Task 2: Suppress Main Pane Focus While Drawer Is Expanded

**Files:**
- Modify: `Sources/AgentStudio/Core/Views/Panes/PaneInteractionOcclusionPolicy.swift`
- Modify: `Sources/AgentStudio/Core/Views/Panes/PaneLeafContainer.swift`
- Modify: `Tests/AgentStudioTests/Core/Views/Panes/PaneInteractionOcclusionPolicyTests.swift`

- [ ] **Step 1: Write failing tap-decision tests**

Add to `Tests/AgentStudioTests/Core/Views/Panes/PaneInteractionOcclusionPolicyTests.swift`:

```swift
@Test
func mainPaneTap_ignoresFocusWhenDrawerIsExpanded() {
    let decision = PaneInteractionOcclusionPolicy.contentTapFocusDecision(
        isDrawerChild: false,
        tabContainsExpandedDrawer: true
    )

    #expect(decision == .ignore)
}

@Test
func drawerChildTap_stillFocusesDrawerChildWhenDrawerIsExpanded() {
    let decision = PaneInteractionOcclusionPolicy.contentTapFocusDecision(
        isDrawerChild: true,
        tabContainsExpandedDrawer: true
    )

    #expect(decision == .focusDrawerChild)
}

@Test
func mainPaneTap_focusesMainPaneWhenNoDrawerIsExpanded() {
    let decision = PaneInteractionOcclusionPolicy.contentTapFocusDecision(
        isDrawerChild: false,
        tabContainsExpandedDrawer: false
    )

    #expect(decision == .focusMainPane)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
mise run test --filter PaneInteractionOcclusionPolicyTests
```

Expected: FAIL because `contentTapFocusDecision` and `PaneContentTapFocusDecision` do not exist.

- [ ] **Step 3: Implement typed tap decision**

Replace `Sources/AgentStudio/Core/Views/Panes/PaneInteractionOcclusionPolicy.swift` with:

```swift
import Foundation

enum PaneContentTapFocusDecision: Equatable {
    case ignore
    case focusDrawerChild
    case focusMainPane
}

enum PaneInteractionOcclusionPolicy {
    static func suppressMainPaneManagementInteraction(
        isDrawerChild: Bool,
        tabContainsExpandedDrawer: Bool
    ) -> Bool {
        tabContainsExpandedDrawer && !isDrawerChild
    }

    static func contentTapFocusDecision(
        isDrawerChild: Bool,
        tabContainsExpandedDrawer: Bool
    ) -> PaneContentTapFocusDecision {
        if isDrawerChild {
            return .focusDrawerChild
        }
        if tabContainsExpandedDrawer {
            return .ignore
        }
        return .focusMainPane
    }
}
```

- [ ] **Step 4: Wire `PaneLeafContainer.onTapGesture` to the decision**

In `Sources/AgentStudio/Core/Views/Panes/PaneLeafContainer.swift`, replace the current `.onTapGesture` body with:

```swift
.onTapGesture {
    switch PaneInteractionOcclusionPolicy.contentTapFocusDecision(
        isDrawerChild: isDrawerChild,
        tabContainsExpandedDrawer: tabContainsExpandedDrawer
    ) {
    case .ignore:
        return
    case .focusDrawerChild:
        guard let drawerParentPaneId else { return }
        onPaneFocusTrigger(
            .drawer(
                .selectPane(parentPaneId: drawerParentPaneId, drawerPaneId: paneHost.id)
            )
        )
    case .focusMainPane:
        onPaneFocusTrigger(
            .contentClick(
                PaneContentClickFocusTrigger(
                    targetPaneId: paneHost.id,
                    location: .content,
                    clickPhase: .completed
                )
            )
        )
    }
}
```

- [ ] **Step 5: Run focus occlusion tests**

Run:

```bash
mise run test --filter PaneInteractionOcclusionPolicyTests
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources/AgentStudio/Core/Views/Panes/PaneInteractionOcclusionPolicy.swift \
  Sources/AgentStudio/Core/Views/Panes/PaneLeafContainer.swift \
  Tests/AgentStudioTests/Core/Views/Panes/PaneInteractionOcclusionPolicyTests.swift
git commit -m "fix: prevent main pane focus under expanded drawer" \
  -m "Co-authored-by: Codex <noreply@openai.com>"
```

---

### Task 3: Consume The Outside-Dismiss Mouse Event

**Files:**
- Modify: `Sources/AgentStudio/Core/Views/Drawer/DrawerPanelOverlay.swift`
- Modify: `Tests/AgentStudioTests/Core/Views/Drawer/DrawerPanelOverlayStateTests.swift`
- Modify: `Tests/AgentStudioTests/Architecture/DrawerTabLevelCaptureArchitectureTests.swift`

- [ ] **Step 1: Write failing outside-dismiss routing tests**

Add these tests to `Tests/AgentStudioTests/Core/Views/Drawer/DrawerPanelOverlayStateTests.swift`:

```swift
@Test
func dismissMonitor_consumesOutsideClickThatDismisses() {
    var dismissCount = 0
    let monitor = DrawerDismissMonitor(onDismiss: {
        dismissCount += 1
    })
    monitor.drawerRect = CGRect(x: 200, y: 120, width: 400, height: 240)
    monitor.iconBarRect = CGRect(x: 560, y: 300, width: 40, height: 80)

    let routing = monitor.handleMouseDown(globalPoint: CGPoint(x: 40, y: 40))

    #expect(routing == .consume)
    #expect(dismissCount == 1)
}

@Test
func dismissMonitor_propagatesClicksInsideDrawerAndIconBar() {
    var dismissCount = 0
    let monitor = DrawerDismissMonitor(onDismiss: {
        dismissCount += 1
    })
    monitor.drawerRect = CGRect(x: 200, y: 120, width: 400, height: 240)
    monitor.iconBarRect = CGRect(x: 560, y: 300, width: 40, height: 80)

    let drawerRouting = monitor.handleMouseDown(globalPoint: CGPoint(x: 240, y: 180))
    let iconBarRouting = monitor.handleMouseDown(globalPoint: CGPoint(x: 580, y: 320))

    #expect(drawerRouting == .propagate)
    #expect(iconBarRouting == .propagate)
    #expect(dismissCount == 0)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
mise run test --filter DrawerPanelOverlayStateTests
```

Expected: FAIL because `DrawerDismissMouseRouting` does not exist and `handleMouseDown(globalPoint:)` does not return the typed routing decision.

- [ ] **Step 3: Add typed mouse routing**

In `Sources/AgentStudio/Core/Views/Drawer/DrawerPanelOverlay.swift`, add near `DrawerDismissMonitor`:

```swift
enum DrawerDismissMouseRouting: Equatable {
    case consume
    case propagate
}
```

- [ ] **Step 4: Return typed routing from the monitor handler**

In `DrawerDismissMonitor`, replace the current boolean handler with:

```swift
@discardableResult
func handleMouseDown(globalPoint: CGPoint) -> DrawerDismissMouseRouting {
    guard shouldDismiss(globalPoint: globalPoint) else {
        return .propagate
    }
    onDismiss()
    return .consume
}
```

Update `install()` so the local monitor consumes the exact event that dismissed the drawer:

```swift
monitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
    guard let self else { return event }
    let globalPoint = NSEvent.mouseLocation
    switch self.handleMouseDown(globalPoint: globalPoint) {
    case .consume:
        return nil
    case .propagate:
        return event
    }
}
```

Do not restore the SwiftUI scrim in this task. The proven regression is AppKit event propagation from the local monitor; consuming the monitor event is the smaller and stricter fix.

- [ ] **Step 5: Update architecture test expectations**

In `Tests/AgentStudioTests/Architecture/DrawerTabLevelCaptureArchitectureTests.swift`, keep the no-scrim assertions and add the monitor consumption assertion:

```swift
#expect(!sources.drawerPanelOverlay.contains("OutsideDismissShape"))
#expect(!sources.drawerPanelOverlay.contains("Color.black.opacity(0.001)"))
#expect(sources.drawerPanelOverlay.contains("return nil"))
#expect(sources.drawerPanelOverlay.contains("case .consume:"))
```

- [ ] **Step 6: Run drawer dismiss tests**

Run:

```bash
mise run test --filter 'DrawerPanelOverlayStateTests|DrawerTabLevelCaptureArchitectureTests|PaneInteractionOcclusionPolicyTests'
```

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add Sources/AgentStudio/Core/Views/Drawer/DrawerPanelOverlay.swift \
  Tests/AgentStudioTests/Core/Views/Drawer/DrawerPanelOverlayStateTests.swift \
  Tests/AgentStudioTests/Architecture/DrawerTabLevelCaptureArchitectureTests.swift
git commit -m "fix: consume drawer outside dismiss clicks" \
  -m "Co-authored-by: Codex <noreply@openai.com>"
```

---

### Task 4: Prove Drawer Drag Target Appears Through The Tab-Level Capture

**Files:**
- Modify: `Tests/AgentStudioTests/Core/Views/Drawer/DrawerSplitContainerDropCaptureOverlayTests.swift`
- Modify: `Tests/AgentStudioTests/Core/Views/Drawer/DrawerCompositionGateTests.swift`

- [ ] **Step 1: Add a failing capture-to-visual smoke test**

Add to `Tests/AgentStudioTests/Core/Views/Drawer/DrawerCompositionGateTests.swift`:

```swift
@Test
func tabLevelCaptureUpdateProducesRenderableDrawerTargetForMiddleSlot() throws {
    let sourcePaneId = UUID()
    let leftPaneId = UUID()
    let rightPaneId = UUID()
    let panelFrameInTab = CGRect(x: 100, y: 200, width: 500, height: 180)
    let paneFramesInDrawer: [UUID: CGRect] = [
        leftPaneId: CGRect(x: 16, y: 40, width: 220, height: 100),
        rightPaneId: CGRect(x: 264, y: 40, width: 220, height: 100),
    ]
    let geometry = try #require(
        DrawerCaptureGeometry.make(
            panelFrameInTab: panelFrameInTab,
            paneFramesInDrawer: paneFramesInDrawer
        )
    )
    let drawerLayout = DrawerGridLayout(topRow: Layout.autoTiled([sourcePaneId, leftPaneId, rightPaneId]))
    var target: DrawerRearrangeTarget?
    let coordinator = DrawerSplitContainerDropCaptureOverlay.Coordinator(
        targetBinding: Binding(
            get: { target },
            set: { target = $0 }
        ),
        shouldAcceptDrop: { _, _, _ in true },
        handleDrop: { _, _, _ in }
    )
    coordinator.updateLayout(
        paneFrames: geometry.paneFramesInDrawer,
        layout: drawerLayout,
        minimizedPaneIds: [],
        containerBounds: geometry.containerBounds,
        isManagementLayerActive: true
    )
    let pasteboard = NSPasteboard(name: NSPasteboard.Name(UUID().uuidString))
    pasteboard.clearContents()
    pasteboard.setData(
        try JSONEncoder().encode(PaneDragPayload(paneId: sourcePaneId, tabId: UUID())),
        forType: .agentStudioPaneDrop
    )

    let resolvedTarget = coordinator.handleDragUpdate(
        from: pasteboard,
        location: geometry.locationInDrawer(fromTabLocation: CGPoint(x: 350, y: 280))
    )
    coordinator.setTarget(resolvedTarget)
    let visuals = DrawerPaneDragCoordinator.targetVisuals(
        geometry: DrawerPaneDragGeometry(
            paneFrames: paneFramesInDrawer,
            layout: drawerLayout,
            containerBounds: geometry.containerBounds,
            minimizedPaneIds: [],
            excludedPaneIds: [sourcePaneId]
        )
    )

    #expect(target == .rowSlot(row: .top, insertionIndex: 1))
    let visual = try #require(visuals[try #require(target)])
    #expect(visual.insertionMarkerRect != nil)
}
```

- [ ] **Step 2: Run test to verify it fails if drawer capture/visual bridge is broken**

Run:

```bash
mise run test --filter DrawerCompositionGateTests
```

Expected before implementation is complete: FAIL if target does not update or visual cannot be rendered. If it already passes after Tasks 1-3, keep it as the regression guard and continue.

- [ ] **Step 3: Add explicit source-exclusion assertion**

Add to `Tests/AgentStudioTests/Core/Views/Drawer/DrawerSplitContainerDropCaptureOverlayTests.swift`:

```swift
@Test
func handleDragUpdate_doesNotSplitDraggedDrawerPaneOntoItself() throws {
    let sourcePaneId = UUID()
    var target: DrawerRearrangeTarget?
    let coordinator = DrawerSplitContainerDropCaptureOverlay.Coordinator(
        targetBinding: Binding(
            get: { target },
            set: { target = $0 }
        ),
        shouldAcceptDrop: { _, _, _ in true },
        handleDrop: { _, _, _ in }
    )
    coordinator.updateLayout(
        paneFrames: [
            sourcePaneId: CGRect(x: 0, y: 40, width: 100, height: 80)
        ],
        layout: DrawerGridLayout(topRow: Layout.autoTiled([sourcePaneId])),
        minimizedPaneIds: [],
        containerBounds: CGRect(x: 0, y: 0, width: 140, height: 140),
        isManagementLayerActive: true
    )
    let pasteboard = NSPasteboard(name: NSPasteboard.Name(UUID().uuidString))
    pasteboard.clearContents()
    pasteboard.setData(
        try JSONEncoder().encode(PaneDragPayload(paneId: sourcePaneId, tabId: UUID())),
        forType: .agentStudioPaneDrop
    )

    let resolvedTarget = coordinator.handleDragUpdate(
        from: pasteboard,
        location: CGPoint(x: 20, y: 80)
    )

    #expect(resolvedTarget == nil)
}
```

- [ ] **Step 4: Run drawer target tests**

Run:

```bash
mise run test --filter 'DrawerCompositionGateTests|DrawerSplitContainerDropCaptureOverlayTests|DrawerPaneDragCoordinatorTests'
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Tests/AgentStudioTests/Core/Views/Drawer/DrawerCompositionGateTests.swift \
  Tests/AgentStudioTests/Core/Views/Drawer/DrawerSplitContainerDropCaptureOverlayTests.swift
git commit -m "test: pin drawer tab-level target smoke" \
  -m "Co-authored-by: Codex <noreply@openai.com>"
```

---

### Task 5: Verify Drawer/Main Movement Boundaries

**Files:**
- Modify: `Tests/AgentStudioTests/Core/Views/Drawer/DrawerDropDispatchTests.swift`
- Modify: `Tests/AgentStudioTests/Core/Views/Splits/SplitContainerDropCaptureOverlayTests.swift`

- [ ] **Step 1: Add failing boundary tests**

In `Tests/AgentStudioTests/Core/Views/Drawer/DrawerDropDispatchTests.swift`, add:

```swift
@Test
func shouldAcceptDrop_rejectsMainPanePayloadForDrawerTarget() {
    let parentPaneId = UUID()
    let mainPaneId = UUID()
    let targetDrawerPaneId = UUID()
    let context = DrawerDropDispatch.Context(
        parentPaneId: parentPaneId,
        sourcePane: Pane(id: mainPaneId, parentPaneId: nil),
        targetPaneIds: [targetDrawerPaneId],
        validator: RecordingDrawerValidator(result: .success)
    )

    let accepted = DrawerDropDispatch.shouldAcceptDrop(
        payload: SplitDropPayload(kind: .existingPane(paneId: mainPaneId, sourceTabId: UUID())),
        target: .paneSplit(paneId: targetDrawerPaneId, side: .left),
        sizingMode: .halveTarget,
        context: context
    )

    #expect(!accepted)
}
```

In `Tests/AgentStudioTests/Core/Views/Splits/SplitContainerDropCaptureOverlayTests.swift`, keep or add the existing drawer-child rejection test:

```swift
@Test
func drawerChildPayload_isRejectedByMainSplitCapture() throws {
    let sourcePaneId = UUID()
    let pasteboard = NSPasteboard(name: NSPasteboard.Name(UUID().uuidString))
    pasteboard.clearContents()
    pasteboard.setData(
        try JSONEncoder().encode(PaneDragPayload(paneId: sourcePaneId, tabId: UUID(), drawerParentPaneId: UUID())),
        forType: .agentStudioPaneDrop
    )
    let dispatcher = RecordingPaneActionDispatcher(
        shouldHandleSplitDragPayload: { _ in false }
    )
    var target: PaneDropTarget?
    let coordinator = SplitContainerDropCaptureOverlay.Coordinator(
        targetBinding: Binding(get: { target }, set: { target = $0 }),
        actionDispatcher: dispatcher
    )

    let resolvedTarget = coordinator.handleDragUpdate(
        from: pasteboard,
        location: CGPoint(x: 20, y: 20)
    )

    #expect(resolvedTarget == nil)
}
```

- [ ] **Step 2: Run boundary tests**

Run:

```bash
mise run test --filter 'DrawerDropDispatchTests|SplitContainerDropCaptureOverlayTests'
```

Expected: PASS after existing dispatch boundaries are confirmed. If the drawer main-pane payload test fails, update `DrawerDropDispatch.shouldAcceptDrop` so it requires `sourcePane.parentPaneId == context.parentPaneId`.

- [ ] **Step 3: Commit**

```bash
git add Tests/AgentStudioTests/Core/Views/Drawer/DrawerDropDispatchTests.swift \
  Tests/AgentStudioTests/Core/Views/Splits/SplitContainerDropCaptureOverlayTests.swift \
  Sources/AgentStudio/Core/Views/Drawer/DrawerDropDispatch.swift
git commit -m "test: enforce drawer and main drag boundaries" \
  -m "Co-authored-by: Codex <noreply@openai.com>"
```

---

### Task 6: Full Verification And Live Smoke

**Files:**
- No source files.
- Runtime verification only.

- [ ] **Step 1: Run focused drawer gates**

Run:

```bash
mise run test --filter 'PaneDragCaptureOwnershipTests|PaneInteractionOcclusionPolicyTests|DrawerPanelOverlayStateTests|DrawerCompositionGateTests|DrawerSplitContainerDropCaptureOverlayTests|DrawerDropDispatchTests|FlatTabStripContainerDragOwnershipTests|DrawerTabLevelCaptureArchitectureTests'
```

Expected: PASS with exit code 0.

- [ ] **Step 2: Run full test suite**

Run:

```bash
mise run test
```

Expected: PASS with exit code 0. Record the test count and suite count in the final report.

- [ ] **Step 3: Run build**

Run:

```bash
mise run build
```

Expected: PASS with exit code 0.

- [ ] **Step 4: Run lint**

Run:

```bash
mise run lint
```

Expected: PASS with exit code 0 and 0 violations.

- [ ] **Step 5: Launch debug build without killing the user’s running app**

Run:

```bash
BUILD_PATH=".build-agent-$PPID"
"$BUILD_PATH/debug/AgentStudio" &
echo $!
```

Expected: prints a PID. Do not use `pkill AgentStudio`.

- [ ] **Step 6: Live smoke checklist**

Use the launched PID and manually verify:

```text
1. Open management mode.
2. Open a drawer with at least two drawer panes.
3. Drag a drawer pane between two drawer panes.
   Expected: drawer target marker appears between panes.
4. Release on the highlighted drawer slot.
   Expected: drawer pane moves inside the drawer.
5. Click outside the drawer but inside the tab.
   Expected: drawer dismisses.
6. Repeat outside click while watching main pane focus and terminal/web content.
   Expected: main pane does not receive focus, cursor movement, text selection, link clicks, or any other content action from the dismissing click.
7. Close drawer, then drag a main pane.
   Expected: normal main-pane drag/drop still works.
```

- [ ] **Step 7: Commit verification-only note if source changed after last commit**

If Task 6 required no source changes, do not create an empty commit. If fixes were made during verification, commit them:

```bash
git status --short
git add <changed files>
git commit -m "fix: complete drawer interaction verification" \
  -m "Co-authored-by: Codex <noreply@openai.com>"
```

---

## Self-Review

Spec coverage:

- Drawer drag registers and shows targets: Tasks 1 and 4.
- Outside-click dismiss works and consumes the dismissing click: Task 3 and Task 6.
- Main pane does not focus/interact while drawer is open: Task 2 and Task 6.
- Normal main tab behavior still works when drawer is closed: Tasks 1, 5, and Task 6.
- Drawer panes never move outside drawer, main panes never move into drawer: Task 5.
- Test pyramid: Tasks 1-5 are headless unit/composition tests; Task 6 is one live smoke.
- No wall-clock tests: no `Task.sleep` or arbitrary delay is introduced.

Placeholder scan:

- No `TBD`, `TODO`, `implement later`, or “similar to” steps.
- Every test task includes concrete test code and exact commands.

Type consistency:

- `PaneDragCaptureOwner` is introduced before `FlatTabStripContainer` uses it.
- `PaneContentTapFocusDecision` is introduced before `PaneLeafContainer` uses it.
- `DrawerDismissMouseRouting` is introduced before `DrawerDismissMonitor` uses it.
