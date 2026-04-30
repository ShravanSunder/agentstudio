# Drawer and Main Drop Target Correction Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restore the agreed drag/drop behavior: drawer rearrange targets work in the real app, main and drawer share the same target semantics, pane-slot drops render as between-pane insertion markers, pane-split drops render as pane regions, and drawer/main movement boundaries are impossible to violate silently.

**Architecture:** Checkpoint 0 is the drawer-target-debugging fix: tab-level AppKit capture, panel-only drawer frame, drawer-local pane frames, and target state bridged back into `DrawerPanel`. Do not start shared visual refactoring until drawer targeting is proven through headless seam tests plus a real smoke check. After the drawer gate is proven, finish the shared target-to-visual layer so main and drawer consume the same discriminated `DropTarget` semantics with only small adapters for legal rows, payload ownership, and command dispatch.

**Tech Stack:** Swift 6.2, SwiftUI, AppKit `NSViewRepresentable`, Swift Testing, mise build/test/lint, Peekaboo visual smoke for native macOS UI.

---

## Current Failure Model

### What is wrong

The branch has a shared `DropTargetResolver`, but the result is not shared all the way to the user-visible surface.

Current main path:

```swift
DropTargetResolver
    -> PaneDragCoordinator
    -> PaneDropTarget(paneId, zone, sizingTarget)
    -> PaneDropTargetOverlay(targetRects: [PaneDropTarget: CGRect])
```

Problem: `PaneDropTargetOverlay` renders everything as a pane-edge marker. A `.paneSlot(row: .main, index: 1)` gets adapted into `PaneDropTarget(paneId: leftPane, zone: .right, sizingTarget: .paneSlot(...))`, then rendered as a right-edge marker on the left pane. That loses the agreed semantic distinction between:

```swift
DropTarget.paneSplit(paneId: side:)
DropTarget.paneSlot(row: index:)
```

Current drawer path:

```swift
DropTargetResolver
    -> DrawerPaneDragCoordinator
    -> DrawerRearrangeTarget
    -> DrawerDropTargetVisual
    -> DrawerDropTargetOverlay
```

Problem: drawer has a better visual distinction (`region` vs `insertionMarker`), but it is drawer-specific. The drawer capture path is also structurally more fragile:

```text
FlatTabStripContainer
  ├─ DrawerPanelOverlay
  │    └─ DrawerPanel
  │         └─ DrawerDropTargetOverlay      drawer-local visual coords
  │
  └─ DrawerSplitContainerDropCaptureOverlay tab-level AppKit capture coords
```

The debugging branch proved the capture must be mounted at tab level, while the target overlay remains inside `DrawerPanel`. The bridge between those spaces is `DrawerPanelFrameInTabKey`; it must mean panel-only frame, not panel+connector.

The exact fix from `drawer-target-debugging` is:

```text
DrawerPanel
  publishes DrawerPanelFrameInTabKey
  value: panel-only frame in tabContainer

FlatTabStripContainer
  reads DrawerPanelFrameInTabKey
  mounts DrawerSplitContainerDropCaptureOverlay at tab level
  passes drawer-local pane frames + panel-sized container bounds

DrawerSplitContainerDropCaptureOverlay
  receives AppKit drag events reliably because it is shallow
  resolves targets in drawer-local coordinates
  writes drawerDropTarget binding

DrawerPanel
  receives drawerDropTarget
  renders DrawerDropTargetOverlay in drawer-local coordinates
```

What must never return:

```text
DrawerPanelOverlay outer VStack
  publishes DrawerPanelFrameInTabKey
  value: panel + connector

DrawerPanel
  publishes drawer pane frames
  value: panel-local

Resolver receives mixed coordinate spaces and lies.
```

### Non-negotiable invariants

```swift
// Drawer panes never leave their drawer.
// Main panes never enter a drawer.
// Moving a pane between main tabs remains allowed.
// Detach is separate from drawer rearrange and must not be mixed into drag/drop.
// Drawer adds only one capability over main: two rows plus second-row creation.
```

---

## File Structure

### Create

- `Sources/AgentStudio/Core/Views/DragAndDrop/DropTargetVisual.swift`
  - Shared discriminated visual model: `.region`, `.insertionMarker`, `.rowBand`.

- `Sources/AgentStudio/Core/Views/DragAndDrop/DropTargetVisualResolver.swift`
  - Shared conversion from `DropTargetResolver.targetRects(...)` plus row order into visible geometry.

- `Sources/AgentStudio/Core/Views/Drawer/DrawerCaptureGeometry.swift`
  - Pure drawer bridge type proving tab-level capture frame, drawer-local bounds, and drawer-local pane frames agree before capture is considered ready.

- `Tests/AgentStudioTests/Core/Views/DragAndDrop/DropTargetVisualResolverTests.swift`
  - Shared visual semantics tests for pane split, row slot, second-row band.

- `Tests/AgentStudioTests/Core/Views/Drawer/DrawerCaptureGeometryTests.swift`
  - Headless gate for panel-only bounds and capture readiness.

- `Tests/AgentStudioTests/Core/Views/Drawer/DrawerCompositionGateTests.swift`
  - End-to-end headless seam: tab-level drawer capture geometry, resolver target, and drawer overlay visual agree on the same location.

- `Tests/AgentStudioTests/Core/Views/Panes/PaneDropTargetVisualTests.swift`
  - Main-pane adapter tests proving slot visuals are centered insertion markers and split visuals are regions.

### Modify

- `Sources/AgentStudio/Core/Views/Drawer/DrawerPanelOverlay.swift`
  - Keep global dismiss frame for panel+connector.
  - Do not publish `DrawerPanelFrameInTabKey` from outer overlay.
  - Keep outside dismiss monitor safe with empty/stale frames.

- `Sources/AgentStudio/Core/Views/Drawer/DrawerPanel.swift`
  - Publish panel-only `DrawerPanelFrameInTabKey`.
  - Render drawer targets through shared `DropTargetVisual`.

- `Sources/AgentStudio/Core/Views/Drawer/DrawerDropTargetOverlay.swift`
  - Remove drawer-specific visual enum and use shared `DropTargetVisual`.

- `Sources/AgentStudio/Core/Views/Drawer/DrawerPaneDragCoordinator.swift`
  - Use shared `DropTargetVisualResolver`.
  - Keep drawer-only target adapter and row constraints.

- `Sources/AgentStudio/Core/Views/Panes/FlatTabStripContainer.swift`
  - Build drawer capture only from `DrawerCaptureGeometry.ready`.
  - Pass shared visual model to main and drawer overlays.
  - Clear drawer target on drawer close, app inactive, management inactive, and capture geometry invalidation.

- `Sources/AgentStudio/Core/Views/Panes/PaneDragCoordinator.swift`
  - Add `targetVisuals(...)`.
  - Keep dispatch adapter explicit.

- `Sources/AgentStudio/Core/Views/Panes/PaneDropTargetOverlay.swift`
  - Render from `DropTargetVisual`, keyed by `PaneDropTarget.sizingTarget`.

- `Sources/AgentStudio/Core/Views/Drawer/DrawerSplitContainerDropCaptureOverlay.swift`
  - Ensure hover and drop use the same capture geometry contract.
  - Keep latched-target commit behavior.

- `Sources/AgentStudio/Core/Views/Drawer/DrawerDropDispatch.swift`
  - Keep boundary invariant tests green: drawer payloads only, same parent only.

- `Tests/AgentStudioTests/Architecture/DrawerTabLevelCaptureArchitectureTests.swift`
  - Replace source-string confidence with narrower invariant checks only where behavior cannot be mounted headlessly.

---

## Checkpoint 0: Port And Prove The Debugging-Branch Drawer Fix

This checkpoint is the first exit gate. The rest of the plan is blocked until this is true:

```text
drawer pane drag in the running app produces drawer targets
between two drawer panes produces a centered insertion marker
over a drawer pane half produces a split region
outside click still dismisses the drawer
```

Required proof:

```text
headless pure tests
  DrawerCaptureGeometryTests

headless composition seam tests
  DrawerCompositionGateTests
  DrawerSplitContainerDropCaptureOverlayTests

architecture invariant tests
  DrawerPanelFrameInTabKey is published by DrawerPanel
  DrawerPanelOverlay does not publish DrawerPanelFrameInTabKey
  DrawerSplitContainerDropCaptureOverlay is mounted from FlatTabStripContainer
  DrawerPanel does not mount DrawerSplitContainerDropCaptureOverlay

native smoke
  launch debug app by PID
  open drawer
  enable management mode
  drag drawer pane between panes and see insertion marker
  drag drawer pane over pane half and see split region
  click outside and drawer closes
```

Do not touch shared visual unification, main-pane drift, or cosmetic cleanup before this checkpoint passes.

---

## Gate 1: Drawer Overlay / Capture Bridge

This gate is first. Do not touch main-pane visual semantics until this gate is red-then-green.

### Task 1: Add Pure Drawer Capture Geometry

**Files:**
- Create: `Sources/AgentStudio/Core/Views/Drawer/DrawerCaptureGeometry.swift`
- Test: `Tests/AgentStudioTests/Core/Views/Drawer/DrawerCaptureGeometryTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `Tests/AgentStudioTests/Core/Views/Drawer/DrawerCaptureGeometryTests.swift`:

```swift
import CoreGraphics
import Foundation
import Testing

@testable import AgentStudio

@Suite(.serialized)
struct DrawerCaptureGeometryTests {
    @Test
    func readiness_waitsForPanelFrameAndPaneFrames() {
        let paneId = UUID()

        #expect(
            DrawerCaptureGeometry.make(
                panelFrameInTab: .zero,
                paneFramesInDrawer: [paneId: CGRect(x: 0, y: 0, width: 100, height: 80)]
            ) == nil
        )

        #expect(
            DrawerCaptureGeometry.make(
                panelFrameInTab: CGRect(x: 20, y: 30, width: 400, height: 160),
                paneFramesInDrawer: [:]
            ) == nil
        )
    }

    @Test
    func readyGeometryUsesPanelOnlyBounds() throws {
        let leftPaneId = UUID()
        let rightPaneId = UUID()
        let geometry = try #require(
            DrawerCaptureGeometry.make(
                panelFrameInTab: CGRect(x: 100, y: 200, width: 500, height: 180),
                paneFramesInDrawer: [
                    leftPaneId: CGRect(x: 16, y: 40, width: 220, height: 100),
                    rightPaneId: CGRect(x: 264, y: 40, width: 220, height: 100),
                ]
            )
        )

        #expect(geometry.containerBounds == CGRect(x: 0, y: 0, width: 500, height: 180))
        #expect(geometry.locationInDrawer(fromTabLocation: CGPoint(x: 350, y: 280)) == CGPoint(x: 250, y: 80))
    }

    @Test
    func readyGeometryRejectsPaneFramesOutsidePanelBounds() {
        let paneId = UUID()

        #expect(
            DrawerCaptureGeometry.make(
                panelFrameInTab: CGRect(x: 100, y: 200, width: 500, height: 180),
                paneFramesInDrawer: [
                    paneId: CGRect(x: 16, y: 40, width: 220, height: 200),
                ]
            ) == nil
        )
    }
}
```

- [ ] **Step 2: Run the failing test**

Run:

```bash
mise run test --filter DrawerCaptureGeometryTests
```

Expected: FAIL because `DrawerCaptureGeometry` does not exist.

- [ ] **Step 3: Add the pure geometry type**

Create `Sources/AgentStudio/Core/Views/Drawer/DrawerCaptureGeometry.swift`:

```swift
import CoreGraphics
import Foundation

struct DrawerCaptureGeometry: Equatable {
    let panelFrameInTab: CGRect
    let paneFramesInDrawer: [UUID: CGRect]

    var containerBounds: CGRect {
        CGRect(origin: .zero, size: panelFrameInTab.size)
    }

    static func make(
        panelFrameInTab: CGRect,
        paneFramesInDrawer: [UUID: CGRect]
    ) -> Self? {
        guard !panelFrameInTab.isEmpty else { return nil }
        guard !paneFramesInDrawer.isEmpty else { return nil }

        let bounds = CGRect(origin: .zero, size: panelFrameInTab.size)
        let allPaneFramesFit = paneFramesInDrawer.values.allSatisfy { frame in
            bounds.contains(frame.origin)
                && bounds.contains(CGPoint(x: frame.maxX, y: frame.maxY))
        }
        guard allPaneFramesFit else { return nil }

        return Self(
            panelFrameInTab: panelFrameInTab,
            paneFramesInDrawer: paneFramesInDrawer
        )
    }

    func locationInDrawer(fromTabLocation location: CGPoint) -> CGPoint {
        CGPoint(
            x: location.x - panelFrameInTab.minX,
            y: location.y - panelFrameInTab.minY
        )
    }
}
```

- [ ] **Step 4: Run the test**

Run:

```bash
mise run test --filter DrawerCaptureGeometryTests
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/AgentStudio/Core/Views/Drawer/DrawerCaptureGeometry.swift \
  Tests/AgentStudioTests/Core/Views/Drawer/DrawerCaptureGeometryTests.swift
git commit -m "test: pin drawer capture geometry bridge

Co-authored-by: Codex <noreply@openai.com>"
```

### Task 2: Use Capture Geometry As The Drawer Overlay Gate

**Files:**
- Modify: `Sources/AgentStudio/Core/Views/Panes/FlatTabStripContainer.swift`
- Test: `Tests/AgentStudioTests/Core/Views/Drawer/DrawerCompositionGateTests.swift`

- [ ] **Step 1: Write the failing composition test**

Create `Tests/AgentStudioTests/Core/Views/Drawer/DrawerCompositionGateTests.swift`:

```swift
import CoreGraphics
import Foundation
import Testing

@testable import AgentStudio

@Suite(.serialized)
struct DrawerCompositionGateTests {
    @Test
    func tabLevelCaptureGeometryResolvesSameTargetThatDrawerOverlayCanRender() throws {
        let sourcePaneId = UUID()
        let leftPaneId = UUID()
        let rightPaneId = UUID()
        let panelFrameInTab = CGRect(x: 100, y: 200, width: 500, height: 180)
        let paneFramesInDrawer: [UUID: CGRect] = [
            leftPaneId: CGRect(x: 16, y: 40, width: 220, height: 100),
            rightPaneId: CGRect(x: 264, y: 40, width: 220, height: 100),
        ]
        let captureGeometry = try #require(
            DrawerCaptureGeometry.make(
                panelFrameInTab: panelFrameInTab,
                paneFramesInDrawer: paneFramesInDrawer
            )
        )
        let drawerLayout = DrawerGridLayout(topRow: Layout.autoTiled([sourcePaneId, leftPaneId, rightPaneId]))
        let hoverLocationInTab = CGPoint(x: 350, y: 280)
        let hoverLocationInDrawer = captureGeometry.locationInDrawer(fromTabLocation: hoverLocationInTab)

        let target = DrawerPaneDragCoordinator.resolveTarget(
            location: hoverLocationInDrawer,
            geometry: DrawerPaneDragGeometry(
                paneFrames: paneFramesInDrawer,
                layout: drawerLayout,
                containerBounds: captureGeometry.containerBounds,
                minimizedPaneIds: [],
                excludedPaneIds: [sourcePaneId]
            )
        )
        let visuals = DrawerPaneDragCoordinator.targetVisuals(
            geometry: DrawerPaneDragGeometry(
                paneFrames: paneFramesInDrawer,
                layout: drawerLayout,
                containerBounds: captureGeometry.containerBounds,
                minimizedPaneIds: [],
                excludedPaneIds: [sourcePaneId]
            )
        )

        #expect(target == .rowSlot(row: .top, insertionIndex: 1))
        let resolvedTarget = try #require(target)
        let visual = try #require(visuals[resolvedTarget])
        let markerRect = try #require(visual.insertionMarkerRect)
        #expect(markerRect.midX == 250)
        #expect(markerRect.minY == 40)
        #expect(markerRect.height == 100)
    }
}
```

- [ ] **Step 2: Run the gate**

Run:

```bash
mise run test --filter DrawerCompositionGateTests
```

Expected before Task 1: FAIL because `DrawerCaptureGeometry` does not exist. Expected after Task 1: PASS. If it fails after Task 1, fix geometry or target visual math before moving on.

- [ ] **Step 3: Wire `FlatTabStripContainer` through `DrawerCaptureGeometry`**

In `Sources/AgentStudio/Core/Views/Panes/FlatTabStripContainer.swift`, replace the body of `tabLevelDrawerCapture(expandedDrawerParentPaneId:)` with:

```swift
@ViewBuilder
private func tabLevelDrawerCapture(expandedDrawerParentPaneId: UUID?) -> some View {
    if DrawerDragOwnershipPolicy.drawerCaptureEnabled(
        managementLayerActive: managementLayer.isActive,
        expandedDrawerParentPaneId: expandedDrawerParentPaneId,
        drawerPanelFrameInTab: drawerPanelFrameInTab
    ),
        let expandedDrawerPaneId = expandedDrawerParentPaneId,
        let expandedDrawer = store.paneAtom.pane(expandedDrawerPaneId)?.drawer,
        let captureGeometry = DrawerCaptureGeometry.make(
            panelFrameInTab: drawerPanelFrameInTab,
            paneFramesInDrawer: drawerPaneFramesInDrawer
        )
    {
        let drawerDispatchContext = DrawerDropDispatch.context(
            parentPaneId: expandedDrawerPaneId,
            store: store
        )
        DrawerSplitContainerDropCaptureOverlay(
            paneFrames: captureGeometry.paneFramesInDrawer,
            layout: expandedDrawer.layout,
            minimizedPaneIds: expandedDrawer.minimizedPaneIds,
            containerBounds: captureGeometry.containerBounds,
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
        .frame(width: captureGeometry.containerBounds.width, height: captureGeometry.containerBounds.height)
        .position(x: captureGeometry.panelFrameInTab.midX, y: captureGeometry.panelFrameInTab.midY)
    }
}
```

- [ ] **Step 4: Clear stale drawer target when capture geometry becomes invalid**

Still in `FlatTabStripContainer.swift`, add this to the existing `.onPreferenceChange(DrawerPanelFrameInTabKey.self)` block:

```swift
.onPreferenceChange(DrawerPanelFrameInTabKey.self) { frame in
    drawerPanelFrameInTab = frame
    if DrawerCaptureGeometry.make(
        panelFrameInTab: frame,
        paneFramesInDrawer: drawerPaneFramesInDrawer
    ) == nil {
        drawerDropTarget = nil
    }
}
```

Replace the current one-line preference handler:

```swift
.onPreferenceChange(DrawerPanelFrameInTabKey.self) { drawerPanelFrameInTab = $0 }
```

- [ ] **Step 5: Run the drawer gate tests**

Run:

```bash
mise run test --filter DrawerCaptureGeometryTests
mise run test --filter DrawerCompositionGateTests
mise run test --filter DrawerSplitContainerDropCaptureOverlayTests
```

Expected: all PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources/AgentStudio/Core/Views/Panes/FlatTabStripContainer.swift \
  Tests/AgentStudioTests/Core/Views/Drawer/DrawerCompositionGateTests.swift
git commit -m "fix: gate drawer capture on aligned panel geometry

Co-authored-by: Codex <noreply@openai.com>"
```

### Task 3: Preserve Outside-Click Dismiss While Keeping Capture Shallow

**Files:**
- Modify: `Sources/AgentStudio/Core/Views/Drawer/DrawerPanelOverlay.swift`
- Test: `Tests/AgentStudioTests/Core/Views/Drawer/DrawerPanelOverlayStateTests.swift`

- [ ] **Step 1: Add failing dismiss tests**

Append to `DrawerPanelOverlayStateTests.swift`:

```swift
@Test
func drawerDismissMonitorKeepsIconBarAndDrawerAsExclusionZones() {
    let monitor = DrawerDismissMonitor()
    monitor.drawerRect = CGRect(x: 100, y: 100, width: 500, height: 220)
    monitor.iconBarRect = CGRect(x: 240, y: 330, width: 160, height: 28)

    #expect(!monitor.shouldDismiss(globalPoint: CGPoint(x: 120, y: 120)))
    #expect(!monitor.shouldDismiss(globalPoint: CGPoint(x: 260, y: 340)))
    #expect(monitor.shouldDismiss(globalPoint: CGPoint(x: 40, y: 40)))
}

@Test
func drawerDismissMonitorUpdatesWhenFrameResets() {
    let monitor = DrawerDismissMonitor()
    monitor.drawerRect = CGRect(x: 100, y: 100, width: 500, height: 220)
    monitor.iconBarRect = .zero
    #expect(monitor.shouldDismiss(globalPoint: CGPoint(x: 40, y: 40)))

    monitor.drawerRect = .zero
    #expect(!monitor.shouldDismiss(globalPoint: CGPoint(x: 40, y: 40)))
}
```

- [ ] **Step 2: Run the tests**

Run:

```bash
mise run test --filter DrawerPanelOverlayStateTests
```

Expected: PASS if current monitor behavior is correct. If FAIL, fix only the monitor policy.

- [ ] **Step 3: Make the overlay comments and geometry explicit**

In `DrawerPanelOverlay.swift`, replace the stale doc comment above `DrawerPanelOverlay` with:

```swift
/// Tab-level overlay that renders the expanded drawer panel on top of all panes.
///
/// Drag/drop capture is intentionally not mounted inside this overlay. AppKit
/// drag destination traversal did not reliably reach a nested drawer capture
/// view in this composition, so `FlatTabStripContainer` owns the shallow
/// tab-level `DrawerSplitContainerDropCaptureOverlay`.
///
/// This overlay owns visual drawer chrome and outside-click dismissal only.
/// `DrawerPanelGlobalFrameKey` reports the panel+connector global frame for
/// dismiss exclusion. `DrawerPanelFrameInTabKey` must stay panel-only and is
/// published by `DrawerPanel`.
```

- [ ] **Step 4: Run the tests**

Run:

```bash
mise run test --filter DrawerPanelOverlayStateTests
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/AgentStudio/Core/Views/Drawer/DrawerPanelOverlay.swift \
  Tests/AgentStudioTests/Core/Views/Drawer/DrawerPanelOverlayStateTests.swift
git commit -m "test: protect drawer dismiss and capture geometry roles

Co-authored-by: Codex <noreply@openai.com>"
```

---

## Gate 2: Shared Target Visual Semantics

Do not proceed unless Gate 1 is green.

### Task 4: Add Shared `DropTargetVisual`

**Files:**
- Create: `Sources/AgentStudio/Core/Views/DragAndDrop/DropTargetVisual.swift`

- [ ] **Step 1: Add the shared visual type**

Create `DropTargetVisual.swift`:

```swift
import CoreGraphics
import Foundation

enum DropTargetVisual: Equatable {
    case region(CGRect)
    case insertionMarker(CGRect)
    case rowBand(CGRect)

    var rect: CGRect {
        switch self {
        case .region(let rect), .insertionMarker(let rect), .rowBand(let rect):
            return rect
        }
    }

    var insertionMarkerRect: CGRect? {
        switch self {
        case .insertionMarker(let rect):
            return rect
        case .region, .rowBand:
            return nil
        }
    }
}
```

- [ ] **Step 2: Build**

Run:

```bash
mise run build
```

Expected: PASS.

- [ ] **Step 3: Commit**

```bash
git add Sources/AgentStudio/Core/Views/DragAndDrop/DropTargetVisual.swift
git commit -m "feat: add shared drop target visual type

Co-authored-by: Codex <noreply@openai.com>"
```

### Task 5: Add Shared Visual Resolver

**Files:**
- Create: `Sources/AgentStudio/Core/Views/DragAndDrop/DropTargetVisualResolver.swift`
- Test: `Tests/AgentStudioTests/Core/Views/DragAndDrop/DropTargetVisualResolverTests.swift`

- [ ] **Step 1: Write failing tests**

Create `DropTargetVisualResolverTests.swift`:

```swift
import CoreGraphics
import Foundation
import Testing

@testable import AgentStudio

@Suite(.serialized)
struct DropTargetVisualResolverTests {
    @Test
    func paneSlotBetweenTwoPanes_isInsertionMarkerCenteredInGap() throws {
        let leftPaneId = UUID()
        let rightPaneId = UUID()
        let frames: [UUID: CGRect] = [
            leftPaneId: CGRect(x: 0, y: 40, width: 100, height: 80),
            rightPaneId: CGRect(x: 120, y: 40, width: 100, height: 80),
        ]

        let visuals = DropTargetVisualResolver.visuals(
            rows: [.main: [leftPaneId, rightPaneId]],
            paneFrames: frames,
            containerBounds: CGRect(x: 0, y: 0, width: 220, height: 140),
            config: .main,
            splittablePanes: Set(frames.keys)
        )

        let visual = try #require(visuals[.paneSlot(row: .main, index: 1)])
        let marker = try #require(visual.insertionMarkerRect)

        #expect(marker.midX == 110)
        #expect(marker.minY == 40)
        #expect(marker.height == 80)
    }

    @Test
    func paneSplit_isRegionForPaneHalf() throws {
        let paneId = UUID()
        let frames: [UUID: CGRect] = [
            paneId: CGRect(x: 20, y: 40, width: 100, height: 80)
        ]

        let visuals = DropTargetVisualResolver.visuals(
            rows: [.main: [paneId]],
            paneFrames: frames,
            containerBounds: CGRect(x: 0, y: 0, width: 160, height: 140),
            config: .main,
            splittablePanes: [paneId]
        )

        #expect(visuals[.paneSplit(paneId: paneId, side: .left)] == .region(CGRect(x: 20, y: 40, width: 50, height: 80)))
        #expect(visuals[.paneSplit(paneId: paneId, side: .right)] == .region(CGRect(x: 70, y: 40, width: 50, height: 80)))
    }

    @Test
    func newRowBand_isRowBandVisual() throws {
        let paneId = UUID()
        let frames: [UUID: CGRect] = [
            paneId: CGRect(x: 20, y: 40, width: 100, height: 80)
        ]

        let visuals = DropTargetVisualResolver.visuals(
            rows: [.drawerTop: [paneId]],
            paneFrames: frames,
            containerBounds: CGRect(x: 0, y: 0, width: 200, height: 140),
            config: .drawerSingleRow,
            splittablePanes: [paneId]
        )

        #expect(visuals[.paneNewRow(position: .top)] == .rowBand(CGRect(x: 0, y: 0, width: 200, height: 28)))
        #expect(visuals[.paneNewRow(position: .bottom)] == .rowBand(CGRect(x: 0, y: 112, width: 200, height: 28)))
    }
}
```

- [ ] **Step 2: Run the failing tests**

Run:

```bash
mise run test --filter DropTargetVisualResolverTests
```

Expected: FAIL because `DropTargetVisualResolver` does not exist.

- [ ] **Step 3: Implement resolver**

Create `DropTargetVisualResolver.swift`:

```swift
import CoreGraphics
import Foundation

enum DropTargetVisualResolver {
    static func visuals(
        rows: [RowID: [UUID]],
        paneFrames: [UUID: CGRect],
        containerBounds: CGRect,
        config: DropTargetConfig,
        splittablePanes: Set<UUID>
    ) -> [DropTarget: DropTargetVisual] {
        let rects = DropTargetResolver.targetRects(
            rows: rows,
            paneFrames: paneFrames,
            containerBounds: containerBounds,
            config: config,
            splittablePanes: splittablePanes
        )

        var visuals: [DropTarget: DropTargetVisual] = [:]

        for (target, rect) in rects {
            switch target {
            case .paneSplit:
                visuals[target] = .region(rect)
            case .paneNewRow:
                visuals[target] = .rowBand(rect)
            case .paneSlot:
                break
            }
        }

        for rowID in config.rows {
            guard let paneIds = rows[rowID] else { continue }
            mergeSlotMarkers(
                into: &visuals,
                rowID: rowID,
                paneIds: paneIds,
                paneFrames: paneFrames
            )
        }

        return visuals
    }

    private static func mergeSlotMarkers(
        into visuals: inout [DropTarget: DropTargetVisual],
        rowID: RowID,
        paneIds: [UUID],
        paneFrames: [UUID: CGRect]
    ) {
        let rowFrames = paneIds.compactMap { paneFrames[$0] }.sorted { lhs, rhs in
            if lhs.minX != rhs.minX { return lhs.minX < rhs.minX }
            return lhs.minY < rhs.minY
        }
        guard !rowFrames.isEmpty else { return }

        let markerWidth = AppStyles.General.Layout.dropTargetMarkerWidth
        let halfMarkerWidth = markerWidth / 2
        let rowMinY = rowFrames.map(\.minY).min() ?? 0
        let rowMaxY = rowFrames.map(\.maxY).max() ?? 0

        for insertionIndex in 0...rowFrames.count {
            let boundaryX: CGFloat
            if insertionIndex == 0 {
                boundaryX = rowFrames[0].minX
            } else if insertionIndex == rowFrames.count {
                boundaryX = rowFrames[rowFrames.count - 1].maxX
            } else {
                boundaryX = (rowFrames[insertionIndex - 1].maxX + rowFrames[insertionIndex].minX) / 2
            }

            visuals[.paneSlot(row: rowID, index: insertionIndex)] = .insertionMarker(
                CGRect(
                    x: boundaryX - halfMarkerWidth,
                    y: rowMinY,
                    width: markerWidth,
                    height: rowMaxY - rowMinY
                )
            )
        }
    }
}
```

- [ ] **Step 4: Run the tests**

Run:

```bash
mise run test --filter DropTargetVisualResolverTests
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/AgentStudio/Core/Views/DragAndDrop/DropTargetVisualResolver.swift \
  Tests/AgentStudioTests/Core/Views/DragAndDrop/DropTargetVisualResolverTests.swift
git commit -m "feat: resolve shared drop target visuals

Co-authored-by: Codex <noreply@openai.com>"
```

---

## Gate 3: Drawer Consumes Shared Visuals

### Task 6: Replace Drawer-Specific Visual Type

**Files:**
- Modify: `Sources/AgentStudio/Core/Views/Drawer/DrawerDropTargetOverlay.swift`
- Modify: `Sources/AgentStudio/Core/Views/Drawer/DrawerPaneDragCoordinator.swift`
- Test: `Tests/AgentStudioTests/Core/Views/Drawer/DrawerPaneDragCoordinatorTests.swift`

- [ ] **Step 1: Update drawer tests to require shared visual type**

In `DrawerPaneDragCoordinatorTests.swift`, keep existing assertions but require the type to be `DropTargetVisual` by adding this test:

```swift
@Test
func drawerTargetVisualsUseSharedVisualType() throws {
    let paneId = UUID()
    let visuals: [DrawerRearrangeTarget: DropTargetVisual] = DrawerPaneDragCoordinator.targetVisuals(
        geometry: geometry(
            paneFrames: [paneId: CGRect(x: 20, y: 40, width: 100, height: 80)],
            layout: DrawerGridLayout(topRow: Layout.autoTiled([paneId])),
            bounds: CGRect(x: 0, y: 0, width: 160, height: 140)
        )
    )

    #expect(visuals[.paneSplit(paneId: paneId, side: .left)] == .region(CGRect(x: 20, y: 40, width: 50, height: 80)))
}
```

- [ ] **Step 2: Run the failing drawer visual tests**

Run:

```bash
mise run test --filter DrawerPaneDragCoordinatorTests
```

Expected: FAIL because `DrawerPaneDragCoordinator.targetVisuals` still returns `DrawerDropTargetVisual`.

- [ ] **Step 3: Modify `DrawerDropTargetOverlay`**

Replace `DrawerDropTargetOverlay.swift` with:

```swift
import SwiftUI

struct DrawerDropTargetOverlay: View {
    let target: DrawerRearrangeTarget?
    let targetVisuals: [DrawerRearrangeTarget: DropTargetVisual]

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let target, let visual = targetVisuals[target] {
                DropTargetVisualView(visual: visual)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
```

- [ ] **Step 4: Add shared visual view**

Create this view at the bottom of `DropTargetVisual.swift`:

```swift
import SwiftUI

struct DropTargetVisualView: View {
    let visual: DropTargetVisual

    var body: some View {
        switch visual {
        case .region(let rect), .rowBand(let rect):
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.accentColor.opacity(0.16))
                .frame(width: rect.width, height: rect.height)
                .offset(x: rect.minX, y: rect.minY)
        case .insertionMarker(let rect):
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.accentColor.opacity(0.85))
                .frame(width: rect.width, height: rect.height)
                .offset(x: rect.minX, y: rect.minY)
        }
    }
}
```

- [ ] **Step 5: Modify `DrawerPaneDragCoordinator.targetVisuals`**

Replace the current `targetVisuals` and delete `mergeRowSlotMarkers` / `sortedRowFrames`:

```swift
static func targetVisuals(
    geometry: DrawerPaneDragGeometry
) -> [DrawerRearrangeTarget: DropTargetVisual] {
    let sharedVisuals = DropTargetVisualResolver.visuals(
        rows: rowsDictionary(from: geometry.layout),
        paneFrames: geometry.paneFrames,
        containerBounds: geometry.containerBounds,
        config: config(for: geometry.layout),
        splittablePanes: geometry.splittablePaneIds
    )

    return sharedVisuals.reduce(into: [:]) { translatedVisuals, entry in
        guard let target = drawerTarget(from: entry.key) else { return }
        translatedVisuals[target] = entry.value
    }
}
```

Keep `targetRects` as:

```swift
static func targetRects(
    geometry: DrawerPaneDragGeometry
) -> [DrawerRearrangeTarget: CGRect] {
    targetVisuals(geometry: geometry).mapValues(\.rect)
}
```

- [ ] **Step 6: Run tests**

Run:

```bash
mise run test --filter DrawerPaneDragCoordinatorTests
mise run test --filter DrawerCompositionGateTests
```

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add Sources/AgentStudio/Core/Views/Drawer/DrawerDropTargetOverlay.swift \
  Sources/AgentStudio/Core/Views/Drawer/DrawerPaneDragCoordinator.swift \
  Sources/AgentStudio/Core/Views/DragAndDrop/DropTargetVisual.swift \
  Tests/AgentStudioTests/Core/Views/Drawer/DrawerPaneDragCoordinatorTests.swift
git commit -m "refactor: share drawer drop target visuals

Co-authored-by: Codex <noreply@openai.com>"
```

---

## Gate 4: Main Pane Consumes Shared Visuals

### Task 7: Add Main Target Visual Adapter

**Files:**
- Modify: `Sources/AgentStudio/Core/Views/Panes/PaneDragCoordinator.swift`
- Test: `Tests/AgentStudioTests/Core/Views/Panes/PaneDropTargetVisualTests.swift`

- [ ] **Step 1: Write failing tests**

Create `PaneDropTargetVisualTests.swift`:

```swift
import CoreGraphics
import Foundation
import Testing

@testable import AgentStudio

@Suite(.serialized)
struct PaneDropTargetVisualTests {
    @Test
    func mainPaneSlotBetweenPanes_isCenteredInsertionMarker() throws {
        let leftPaneId = UUID()
        let rightPaneId = UUID()
        let frames: [UUID: CGRect] = [
            leftPaneId: CGRect(x: 0, y: 0, width: 300, height: 400),
            rightPaneId: CGRect(x: 320, y: 0, width: 300, height: 400),
        ]

        let visuals = PaneDragCoordinator.targetVisuals(
            paneFrames: frames,
            containerBounds: CGRect(x: 0, y: 0, width: 620, height: 400),
            minimizedPaneIds: []
        )

        let target = PaneDropTarget(
            paneId: leftPaneId,
            zone: .right,
            sizingTarget: .paneSlot(row: .main, index: 1)
        )
        let visual = try #require(visuals[target])
        let marker = try #require(visual.insertionMarkerRect)

        #expect(marker.midX == 310)
        #expect(marker.height == 400)
    }

    @Test
    func mainPaneSplit_isRegionNotInsertionMarker() throws {
        let paneId = UUID()
        let frames: [UUID: CGRect] = [
            paneId: CGRect(x: 20, y: 0, width: 300, height: 400)
        ]

        let visuals = PaneDragCoordinator.targetVisuals(
            paneFrames: frames,
            containerBounds: CGRect(x: 0, y: 0, width: 340, height: 400),
            minimizedPaneIds: []
        )

        let target = PaneDropTarget(
            paneId: paneId,
            zone: .left,
            sizingTarget: .paneSplit(paneId: paneId, side: .left)
        )

        #expect(visuals[target] == .region(CGRect(x: 20, y: 0, width: 150, height: 400)))
    }
}
```

- [ ] **Step 2: Run the failing tests**

Run:

```bash
mise run test --filter PaneDropTargetVisualTests
```

Expected: FAIL because `PaneDragCoordinator.targetVisuals` does not exist.

- [ ] **Step 3: Add `PaneDragCoordinator.targetVisuals`**

In `PaneDragCoordinator.swift`, add:

```swift
static func targetVisuals(
    paneFrames: [UUID: CGRect],
    containerBounds: CGRect,
    minimizedPaneIds: Set<UUID>
) -> [PaneDropTarget: DropTargetVisual] {
    let sortedPaneIds = sortedPaneIds(from: paneFrames)
    let splittablePaneIds = Set(paneFrames.keys).subtracting(minimizedPaneIds)
    let sharedVisuals = DropTargetVisualResolver.visuals(
        rows: [.main: sortedPaneIds],
        paneFrames: paneFrames,
        containerBounds: containerBounds,
        config: .main,
        splittablePanes: splittablePaneIds
    )

    return sharedVisuals.reduce(into: [:]) { translatedVisuals, entry in
        guard let paneTarget = paneTarget(from: entry.key, sortedPaneIds: sortedPaneIds) else { return }
        translatedVisuals[paneTarget] = entry.value
    }
}
```

- [ ] **Step 4: Run tests**

Run:

```bash
mise run test --filter PaneDropTargetVisualTests
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/AgentStudio/Core/Views/Panes/PaneDragCoordinator.swift \
  Tests/AgentStudioTests/Core/Views/Panes/PaneDropTargetVisualTests.swift
git commit -m "feat: adapt main pane drop visuals from shared targets

Co-authored-by: Codex <noreply@openai.com>"
```

### Task 8: Render Main Pane Targets From Shared Visuals

**Files:**
- Modify: `Sources/AgentStudio/Core/Views/Panes/PaneDropTargetOverlay.swift`
- Modify: `Sources/AgentStudio/Core/Views/Panes/FlatTabStripContainer.swift`
- Test: `Tests/AgentStudioTests/Core/Views/Panes/PaneDropTargetVisualTests.swift`

- [ ] **Step 1: Update `PaneDropTargetOverlay`**

Replace `PaneDropTargetOverlay.swift` with:

```swift
import SwiftUI

/// Renders a single split drop target overlay in tab-container coordinates.
struct PaneDropTargetOverlay: View {
    let target: PaneDropTarget?
    let targetVisuals: [PaneDropTarget: DropTargetVisual]

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let target,
                let visual = targetVisuals[target]
            {
                DropTargetVisualView(visual: visual)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
```

- [ ] **Step 2: Update main overlay call site**

In `FlatTabStripContainer.swift`, replace:

```swift
PaneDropTargetOverlay(
    target: dropTarget,
    targetRects: PaneDragCoordinator.targetRects(
        paneFrames: paneFrames,
        containerBounds: containerBounds,
        minimizedPaneIds: minimizedPaneIds
    )
)
```

with:

```swift
PaneDropTargetOverlay(
    target: dropTarget,
    targetVisuals: PaneDragCoordinator.targetVisuals(
        paneFrames: paneFrames,
        containerBounds: containerBounds,
        minimizedPaneIds: minimizedPaneIds
    )
)
```

- [ ] **Step 3: Build**

Run:

```bash
mise run build
```

Expected: PASS.

- [ ] **Step 4: Run focused visual tests**

Run:

```bash
mise run test --filter PaneDropTargetVisualTests
mise run test --filter DropTargetVisualResolverTests
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/AgentStudio/Core/Views/Panes/PaneDropTargetOverlay.swift \
  Sources/AgentStudio/Core/Views/Panes/FlatTabStripContainer.swift
git commit -m "fix: render main pane slot targets as insertion markers

Co-authored-by: Codex <noreply@openai.com>"
```

---

## Gate 5: Movement Boundary Invariants

### Task 9: Pin Drawer/Main Boundary Rules

**Files:**
- Modify: `Tests/AgentStudioTests/Core/Views/Drawer/DrawerDropDispatchTests.swift`
- Modify: `Tests/AgentStudioTests/Core/Views/Drawer/DrawerSplitContainerDropCaptureOverlayTests.swift`

- [ ] **Step 1: Add drawer/main rejection tests**

Append to `DrawerDropDispatchTests.swift`:

```swift
@Test
func shouldAcceptDrop_rejectsMainPanePayloadWithoutDrawerParent() {
    let parentPaneId = UUID()
    let mainPaneId = UUID()
    let targetPaneId = UUID()
    let store = WorkspaceStoreTestAccess.makeStore()
    store.paneAtom.upsertPane(Pane(id: parentPaneId, content: .empty, drawer: Drawer(layout: DrawerGridLayout(topRow: Layout.autoTiled([targetPaneId])))))
    store.paneAtom.upsertPane(Pane(id: mainPaneId, content: .empty))
    store.paneAtom.upsertPane(Pane(id: targetPaneId, parentPaneId: parentPaneId, content: .empty))

    let context = DrawerDropDispatch.context(parentPaneId: parentPaneId, store: store)
    let accepted = DrawerDropDispatch.shouldAcceptDrop(
        payload: SplitDropPayload(kind: .existingPane(paneId: mainPaneId, sourceTabId: UUID())),
        target: .rowSlot(row: .top, insertionIndex: 1),
        sizingMode: .proportional,
        context: context
    )

    #expect(!accepted)
}
```

If the local `Pane` initializer differs, use the existing helper style already in `DrawerDropDispatchTests.swift`. The assertion must be exact: a main pane has no drawer parent and must be rejected by drawer dispatch.

- [ ] **Step 2: Add capture-level no-dispatch test**

Append to `DrawerSplitContainerDropCaptureOverlayTests.swift`:

```swift
@Test
func performDrop_rejectsWhenDispatcherRejectsMainPanePayload() throws {
    let sourcePaneId = UUID()
    let targetPaneId = UUID()
    var latchedTarget: DrawerRearrangeTarget? = .rowSlot(row: .top, insertionIndex: 1)
    var handledDropCount = 0

    let coordinator = DrawerSplitContainerDropCaptureOverlay.Coordinator(
        targetBinding: Binding(
            get: { latchedTarget },
            set: { latchedTarget = $0 }
        ),
        shouldAcceptDrop: { _, _, _ in false },
        handleDrop: { _, _, _ in handledDropCount += 1 }
    )
    coordinator.updateLayout(
        paneFrames: [targetPaneId: CGRect(x: 0, y: 0, width: 100, height: 80)],
        layout: DrawerGridLayout(topRow: Layout.autoTiled([targetPaneId])),
        minimizedPaneIds: [],
        containerBounds: CGRect(x: 0, y: 0, width: 160, height: 100),
        isManagementLayerActive: true
    )
    let payload = SplitDropPayload(kind: .existingPane(paneId: sourcePaneId, sourceTabId: UUID()))
    let pasteboard = try pasteboard(containing: payload)

    let didDrop = coordinator.performDrop(from: pasteboard, location: CGPoint(x: 80, y: 40))

    #expect(!didDrop)
    #expect(handledDropCount == 0)
}
```

- [ ] **Step 3: Run boundary tests**

Run:

```bash
mise run test --filter DrawerDropDispatchTests
mise run test --filter DrawerSplitContainerDropCaptureOverlayTests
```

Expected: PASS. If FAIL, fix `DrawerDropDispatch.shouldAcceptDrop` only; do not loosen the invariant.

- [ ] **Step 4: Commit**

```bash
git add Tests/AgentStudioTests/Core/Views/Drawer/DrawerDropDispatchTests.swift \
  Tests/AgentStudioTests/Core/Views/Drawer/DrawerSplitContainerDropCaptureOverlayTests.swift
git commit -m "test: pin drawer and main pane movement boundaries

Co-authored-by: Codex <noreply@openai.com>"
```

---

## Gate 6: Visual Smoke Validation

### Task 10: Add A Native Smoke Checklist And Run It

**Files:**
- Create: `docs/wip/debugging/2026-04-24-drawer-drop-target-smoke.md`

- [ ] **Step 1: Create smoke runbook**

Create `docs/wip/debugging/2026-04-24-drawer-drop-target-smoke.md`:

```markdown
# 2026-04-24 Drawer Drop Target Smoke

## Required states

1. Drawer opens.
2. Clicking outside drawer dismisses it.
3. Management layer active.
4. Drawer pane drag between two drawer panes shows a vertical insertion marker centered between panes.
5. Drawer pane drag over left/right half of a drawer pane shows a region target on that half.
6. Main pane drag between two main panes shows a vertical insertion marker centered between panes.
7. Main pane drag over left/right half of a main pane shows a region target on that half.
8. Main pane cannot be dropped into drawer.
9. Drawer pane cannot be dropped outside drawer.

## Commands

```bash
mise run build
BUILD_PATH=".build-agent-$PPID"
"$BUILD_PATH/debug/AgentStudio" &
APP_PID=$!
peekaboo see --app "PID:$APP_PID" --json > /tmp/agent-studio-drawer-smoke-initial.json
```

Use screenshots plus app interaction to verify the states above. Do not count this smoke as a substitute for the headless tests.
```

- [ ] **Step 2: Run build**

Run:

```bash
mise run build
```

Expected: PASS.

- [ ] **Step 3: Launch debug app with PID**

Run:

```bash
BUILD_PATH=".build-agent-$PPID"
"$BUILD_PATH/debug/AgentStudio" &
APP_PID=$!
echo "$APP_PID"
```

Expected: app launches and prints PID.

- [ ] **Step 4: Capture screenshot**

Run:

```bash
peekaboo see --app "PID:$APP_PID" --json > /tmp/agent-studio-drawer-smoke-initial.json
```

Expected: screenshot JSON contains the AgentStudio window.

- [ ] **Step 5: Manually verify smoke checklist**

Expected: all nine states in the runbook are true. If any fail, do not continue to final validation; return to the relevant gate.

- [ ] **Step 6: Commit runbook**

```bash
git add docs/wip/debugging/2026-04-24-drawer-drop-target-smoke.md
git commit -m "docs: add drawer drop target smoke checklist

Co-authored-by: Codex <noreply@openai.com>"
```

---

## Final Validation

Run these from the repo root, sequentially, with no parallel Swift commands in the same build directory:

```bash
mise run build
mise run test
mise run lint
```

Expected:

```text
mise run build: exit 0
mise run test: exit 0, full suite pass count reported
mise run lint: exit 0, zero violations
```

Then run targeted gates again:

```bash
mise run test --filter DrawerCaptureGeometryTests
mise run test --filter DrawerCompositionGateTests
mise run test --filter DrawerSplitContainerDropCaptureOverlayTests
mise run test --filter DrawerPaneDragCoordinatorTests
mise run test --filter DropTargetVisualResolverTests
mise run test --filter PaneDropTargetVisualTests
mise run test --filter DrawerDropDispatchTests
```

Expected: every command exits 0.

Finally, run the smoke checklist in `docs/wip/debugging/2026-04-24-drawer-drop-target-smoke.md`.

---

## Self-Review

### Spec coverage

- Drawer overlay first gate: covered by Tasks 1-3.
- Drawer targets visible in real composition: covered by Tasks 1-2 and Task 10 smoke.
- Main and drawer share utilities: covered by Tasks 4-8.
- Pane-slot visual between panes: covered by Tasks 5, 7, 8.
- Pane-split visual inside pane half: covered by Tasks 5, 7, 8.
- Drawer panes cannot leave drawer: covered by Task 9.
- Main panes cannot enter drawer: covered by Task 9.
- Testing pyramid: pure tests in Tasks 1, 5, 7; seam tests in Tasks 2, 6, 9; one native smoke in Task 10.

### Placeholder scan

No task depends on an unspecified implementation. The only helper caveat is in Task 9 for existing test factory style; the required invariant and assertion are explicit.

### Type consistency

- `DropTargetVisual` is the single shared visual discriminated union.
- `DropTargetVisualResolver.visuals(...)` returns `[DropTarget: DropTargetVisual]`.
- `PaneDragCoordinator.targetVisuals(...)` returns `[PaneDropTarget: DropTargetVisual]`.
- `DrawerPaneDragCoordinator.targetVisuals(...)` returns `[DrawerRearrangeTarget: DropTargetVisual]`.
- `DrawerCaptureGeometry.make(...)` is optional and is the only capture-readiness gate.
