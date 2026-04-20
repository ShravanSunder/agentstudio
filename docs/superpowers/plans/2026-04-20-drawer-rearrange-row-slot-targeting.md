# Drawer Rearrange Row-Slot Targeting Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make drawer rearrange behave predictably by replacing pane-edge drag guessing with explicit row-slot and row-creation targets, while keeping drawer drag isolated from main-pane drag and making the full flow unit-testable.

**Architecture:** Rebuild drawer rearrange around a pure `DrawerRearrangeTarget` model. The UI resolves pointer location into an explicit target (`rowSlot` or `createSecondRow`), the validator only checks whether that already-resolved target is legal for the current `DrawerGridLayout`, and the layout model computes the projected result while preserving existing split ratios. Drawer latching must keep the same contract as the main split drag system.

**Tech Stack:** Swift 6.2, AppKit, SwiftUI, `Testing`, `@Observable`

---

## Precondition

This plan assumes drawer interaction occlusion is already correct:

- when the drawer is expanded, background main-pane hover and management chrome do not render or receive pointer interaction
- the drawer scrim is a real hit-testing surface and blocks background event leakage

This drag rewrite does not attempt to solve background event leakage. It assumes that interaction layer is already fixed before Tasks 1–4 begin.

## Why This Exists

The current drawer drag algorithm is built around pane-edge inference:

- `DrawerPaneDragCoordinator` resolves `DrawerPaneDropTarget(paneId, zone)` where `zone` is `left/right/top/bottom`
- `DrawerPanel.shouldAcceptDrawerDrop(...)` converts that edge guess into `.moveDrawerPane(parentPaneId:, drawerPaneId:, targetDrawerPaneId:, direction:)`
- `DrawerCommandValidator.validateMove(...)` and `DrawerGridLayout.inserting(...)` decide whether that edge guess happens to produce a legal layout

That means the preview layer only shows a target if validation happens to accept the inferred edge. In practice, this makes drawer drag feel broken:

- one row with multiple panes does not expose explicit “insert between these panes” semantics
- one row to two rows is hidden behind top/bottom edge guesses on panes
- two rows do not clearly communicate “this will insert into row 1 vs row 2”
- many pointer positions show no target at all because the validator is being asked to invent semantics from a weak UI signal

The correct model is explicit:

- one row:
  - horizontal insertion slots in the row
  - top row-creation band
  - bottom row-creation band
- two rows:
  - top-row insertion slots
  - bottom-row insertion slots
  - no third-row targets

Grounding:

- `Sources/AgentStudio/Core/Views/Drawer/DrawerPanel.swift`
- `Sources/AgentStudio/Core/Views/Drawer/DrawerPaneDragCoordinator.swift`
- `Sources/AgentStudio/Core/Views/Drawer/DrawerDropZone.swift`
- `Sources/AgentStudio/Core/Views/Drawer/DrawerSplitContainerDropCaptureOverlay.swift`
- `Sources/AgentStudio/Core/Actions/DrawerCommandValidator.swift`
- `Sources/AgentStudio/Core/Models/DrawerGridLayout.swift`
- `Tests/AgentStudioTests/Core/Actions/DrawerCommandIntegrationTests.swift`
- `Tests/AgentStudioTests/Core/Stores/WorkspaceStoreDrawerTests.swift`

## Design Decisions

1. `moveDrawerPane` changes from `(targetDrawerPaneId, direction)` to `DrawerRearrangeTarget`.
2. Drawer rearrange is drawer-scoped only. `PaneDropPlanner` must not synthesize drawer rearrange from main-pane split drops.
3. `DrawerCommandValidator` stays as the post-resolution legality check. It validates already-resolved targets; it does not infer semantics.
4. One-row to two-row semantics are explicit:
   - `createSecondRow(position: .top)` makes the dragged pane the only pane in the new top row
   - `createSecondRow(position: .bottom)` makes the dragged pane the only pane in the new bottom row
5. Ratio preservation is required. Rearranging panes is a reorder, not a retile. Do not replace existing row layouts with `Layout.autoTiled(...)` except when constructing a brand-new row from scratch.
6. Drawer latching must match the main split drag contract:
   - resolve a fresh target
   - if fresh target is valid, use it
   - else if current latched target is still valid, keep it
   - else clear
7. The interaction-occlusion fix is a prerequisite, not part of the drag semantics rewrite.
8. `PaneDropPlanner` must not synthesize drawer rearrange from main-pane split drops. Drawer rearrange targets are produced only inside the drawer drag system.
9. Use `DrawerGridLayout` directly in the resolver. Do not introduce a parallel `DrawerRowLayout` type that duplicates the same structure.

## Geometry Spec

This section is decision-complete. Do not improvise the resolver.

### Coordinate space

- All drawer drag targeting uses SwiftUI `.named(DrawerPanel.drawerDropCoordinateSpace)`
- `drawerPaneFrames` already live in that space via `DrawerPaneFramePreferenceKey`
- origin is top-left, matching current SwiftUI geometry usage in drawer views

### New target types

```swift
enum DrawerRowPlacement: Equatable, Codable, Hashable {
    case top
    case bottom
}

enum DrawerRearrangeTarget: Equatable, Codable, Hashable {
    case rowSlot(row: DrawerRowPlacement, insertionIndex: Int)
    case createSecondRow(position: DrawerRowPlacement)
}
```

### One-row target geometry

Given one row with panes sorted by `minX`:

- creation bands:
  - `topBand = CGRect(x: container.minX, y: container.minY, width: container.width, height: 28)`
  - `bottomBand = CGRect(x: container.minX, y: container.maxY - 28, width: container.width, height: 28)`
- if `location` is inside `topBand`, target is `.createSecondRow(position: .top)`
- if `location` is inside `bottomBand`, target is `.createSecondRow(position: .bottom)`

If neither creation band matches, resolve a `rowSlot(row: .top, insertionIndex: i)`:

- let `sortedPanes` be row panes sorted by `minX`
- slot `0`: `location.x <= sortedPanes[0].midX`
- slot `i` for `1..<count`: `sortedPanes[i - 1].midX < location.x && location.x <= sortedPanes[i].midX`
- slot `count`: `location.x > sortedPanes[count - 1].midX`
- exact midpoint ties choose the smaller insertion index
- if `paneFrames` is empty, return `nil`

### Two-row target geometry

- no creation bands exist
- compute the row bands from current frames:
  - `topRowMinY = min(frame.minY for top-row panes)`
  - `topRowMaxY = max(frame.maxY for top-row panes)`
- `bottomRowMinY = min(frame.minY for bottom-row panes)`
- `bottomRowMaxY = max(frame.maxY for bottom-row panes)`
- if `location.y` is inside top-row band, resolve top-row slot using the same midpoint rules
- if `location.y` is inside bottom-row band, resolve bottom-row slot using the same midpoint rules
- if neither band contains `location.y`, return `nil` and let latching decide whether to keep the last valid target
- do not snap to the “nearest” row; that would reintroduce inference through geometry

### Resolver priority and latching

The drawer resolver must keep the same shape and contract as the main split drag system:

```swift
static func resolveLatchedTarget(
    location: CGPoint,
    paneFrames: [UUID: CGRect],
    layout: DrawerGridLayout,
    containerBounds: CGRect,
    currentTarget: DrawerRearrangeTarget?,
    shouldAcceptDrop: (DrawerRearrangeTarget) -> Bool
) -> DrawerRearrangeTarget?
```

Resolution order:

1. resolve a fresh explicit target
2. if the fresh target is accepted, use it
3. else if the current latched target is still accepted, keep it
4. else clear

Latch storage and clear conditions must stay parallel to main split drag:

- latch lives in `targetBinding.wrappedValue` inside `DrawerSplitContainerDropCaptureOverlay.Coordinator`
- clear on `draggingExited`
- clear on `draggingEnded`
- clear after `performDragOperation`
- clear via `DropTargetLatchState.shouldClearTarget(appIsActive:, pressedMouseButtons:)`

### Empty drawer

- if there are no panes, return `nil`
- empty drawers are created via `addDrawerPane`, not rearrange

## Task 0: Prerequisite — Lock The Occlusion Layer

**Files:**
- Modify: `Sources/AgentStudio/Core/Views/Splits/PaneLeafContainer.swift`
- Modify: `Sources/AgentStudio/Core/Views/Drawer/DrawerPanelOverlay.swift`
- Create: `Sources/AgentStudio/Core/Views/Splits/PaneInteractionOcclusionPolicy.swift`
- Test: `Tests/AgentStudioTests/Core/Views/Splits/PaneInteractionOcclusionPolicyTests.swift`

If the current branch already contains this prerequisite slice, verify it and mark the task complete without re-implementing it.

- [ ] **Step 1: Write the failing occlusion policy tests**

```swift
import Foundation
import Testing

@testable import AgentStudio

@Suite(.serialized)
struct PaneInteractionOcclusionPolicyTests {
    @Test
    func expandedDrawer_suppressesMainPaneInteraction() {
        #expect(
            PaneInteractionOcclusionPolicy.suppressMainPaneManagementInteraction(
                isDrawerChild: false,
                tabContainsExpandedDrawer: true
            )
        )
    }

    @Test
    func expandedDrawer_doesNotSuppressDrawerChildInteraction() {
        #expect(
            !PaneInteractionOcclusionPolicy.suppressMainPaneManagementInteraction(
                isDrawerChild: true,
                tabContainsExpandedDrawer: true
            )
        )
    }
}
```

- [ ] **Step 2: Run the occlusion tests to verify they fail**

Run: `swift test --build-path .build-agent-drawer-rearrange --filter PaneInteractionOcclusionPolicyTests`
Expected: FAIL because `PaneInteractionOcclusionPolicy` does not exist yet.

- [ ] **Step 3: Write the minimal occlusion policy and wire it**

```swift
// Sources/AgentStudio/Core/Views/Splits/PaneInteractionOcclusionPolicy.swift
import Foundation

enum PaneInteractionOcclusionPolicy {
    static func suppressMainPaneManagementInteraction(
        isDrawerChild: Bool,
        tabContainsExpandedDrawer: Bool
    ) -> Bool {
        tabContainsExpandedDrawer && !isDrawerChild
    }
}
```

```swift
// Sources/AgentStudio/Core/Views/Splits/PaneLeafContainer.swift
private var tabContainsExpandedDrawer: Bool {
    guard let tab = store.tabLayoutAtom.tab(tabId) else { return false }
    return tab.paneIds.contains { paneId in
        store.paneAtom.pane(paneId)?.drawer?.isExpanded == true
    }
}

private var suppressMainPaneManagementInteraction: Bool {
    PaneInteractionOcclusionPolicy.suppressMainPaneManagementInteraction(
        isDrawerChild: isDrawerChild,
        tabContainsExpandedDrawer: tabContainsExpandedDrawer
    )
}

private var isManagementHovered: Bool {
    guard !suppressMainPaneManagementInteraction else { return false }
    return isHovered || isPointerInsidePaneView
}
```

Apply `!suppressMainPaneManagementInteraction` gates to:
- hover border
- drag handle
- management controls
- split/browser/detach chrome
- `onHover { isHovered = ... }`

```swift
// Sources/AgentStudio/Core/Views/Drawer/DrawerPanelOverlay.swift
Color.black.opacity(0.001)
    .contentShape(
        .interaction,
        OutsideDismissShape(exclusionRect: exclusionRect),
        eoFill: true
    )
```

Add a short comment explaining why `Color.clear` is insufficient for reliable hit testing.

- [ ] **Step 4: Run the occlusion tests to verify they pass**

Run: `swift test --build-path .build-agent-drawer-rearrange --filter PaneInteractionOcclusionPolicyTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/AgentStudio/Core/Views/Splits/PaneInteractionOcclusionPolicy.swift Sources/AgentStudio/Core/Views/Splits/PaneLeafContainer.swift Sources/AgentStudio/Core/Views/Drawer/DrawerPanelOverlay.swift Tests/AgentStudioTests/Core/Views/Splits/PaneInteractionOcclusionPolicyTests.swift
git commit -m "fix: suppress main-pane interaction under expanded drawer" -m "Co-authored-by: Codex <noreply@openai.com>"
```

### Task 1: Codify Drawer Rearrange Semantics In Pure Model Tests

**Files:**
- Create: `Sources/AgentStudio/Core/Models/DrawerRearrangeTarget.swift`
- Create: `Sources/AgentStudio/Core/Models/DrawerGridLayout+Rearrange.swift`
- Test: `Tests/AgentStudioTests/Core/Models/DrawerGridLayoutRearrangeTests.swift`

- [ ] **Step 1: Write the failing model tests**

```swift
import Foundation
import Testing

@testable import AgentStudio

@Suite(.serialized)
struct DrawerGridLayoutRearrangeTests {
    @Test
    func oneRow_slotInsertion_beforeMiddleAfter_areDistinct() throws {
        let a = UUID()
        let b = UUID()
        let c = UUID()
        let layout = DrawerGridLayout(topRow: Layout.autoTiled([a, b, c]))

        let before = try #require(
            layout.projectedMove(
                paneId: c,
                target: .rowSlot(row: .top, insertionIndex: 0)
            )
        )
        #expect(before.topRow.paneIds == [c, a, b])

        let middle = try #require(
            layout.projectedMove(
                paneId: a,
                target: .rowSlot(row: .top, insertionIndex: 1)
            )
        )
        #expect(middle.topRow.paneIds == [b, a, c])

        let after = try #require(
            layout.projectedMove(
                paneId: a,
                target: .rowSlot(row: .top, insertionIndex: 3)
            )
        )
        #expect(after.topRow.paneIds == [b, c, a])
    }

    @Test
    func oneRow_createSecondRow_topAndBottomBands_createTwoRows() throws {
        let a = UUID()
        let b = UUID()
        let c = UUID()
        let layout = DrawerGridLayout(topRow: Layout.autoTiled([a, b, c]))

        let topRow = try #require(
            layout.projectedMove(
                paneId: c,
                target: .createSecondRow(position: .top)
            )
        )
        #expect(topRow.topRow.paneIds == [c])
        #expect(topRow.bottomRow?.paneIds == [a, b])

        let bottomRow = try #require(
            layout.projectedMove(
                paneId: a,
                target: .createSecondRow(position: .bottom)
            )
        )
        #expect(bottomRow.topRow.paneIds == [b, c])
        #expect(bottomRow.bottomRow?.paneIds == [a])
    }

    @Test
    func twoRows_rowSlots_moveBetweenRows_withoutCreatingThirdRow() throws {
        let a = UUID()
        let b = UUID()
        let c = UUID()
        let d = UUID()
        let layout = DrawerGridLayout(
            topRow: Layout.autoTiled([a, b]),
            bottomRow: Layout.autoTiled([c, d]),
            rowSplitRatio: 0.5
        )

        let movedToBottom = try #require(
            layout.projectedMove(
                paneId: b,
                target: .rowSlot(row: .bottom, insertionIndex: 1)
            )
        )
        #expect(movedToBottom.topRow.paneIds == [a])
        #expect(movedToBottom.bottomRow?.paneIds == [c, b, d])
    }

    @Test
    func twoRows_createSecondRowTarget_isRejected() {
        let a = UUID()
        let b = UUID()
        let c = UUID()
        let layout = DrawerGridLayout(
            topRow: Layout.autoTiled([a, b]),
            bottomRow: Layout.autoTiled([c]),
            rowSplitRatio: 0.5
        )

        #expect(
            layout.projectedMove(
                paneId: a,
                target: .createSecondRow(position: .bottom)
            ) == nil
        )
    }
}
```

- [ ] **Step 2: Run the model tests to verify they fail**

Run: `swift test --build-path .build-agent-drawer-rearrange --filter DrawerGridLayoutRearrangeTests`
Expected: FAIL because `DrawerRearrangeTarget`, `DrawerRowPlacement`, and `projectedMove(...)` do not exist.

- [ ] **Step 3: Write the minimal model types and projection helpers**

```swift
// Sources/AgentStudio/Core/Models/DrawerRearrangeTarget.swift
import Foundation

enum DrawerRowPlacement: Equatable, Codable, Hashable {
    case top
    case bottom
}

enum DrawerRearrangeTarget: Equatable, Codable, Hashable {
    case rowSlot(row: DrawerRowPlacement, insertionIndex: Int)
    case createSecondRow(position: DrawerRowPlacement)
}
```

```swift
// Sources/AgentStudio/Core/Models/DrawerGridLayout+Rearrange.swift
import Foundation

extension DrawerGridLayout {
    func projectedMove(
        paneId: UUID,
        target: DrawerRearrangeTarget
    ) -> DrawerGridLayout? {
        guard let layoutWithoutSource = removing(paneId: paneId) else { return nil }

        switch target {
        case .rowSlot(let row, let insertionIndex):
            return layoutWithoutSource.insertingAtSlot(
                paneId: paneId,
                row: row,
                insertionIndex: insertionIndex
            )
        case .createSecondRow(let position):
            guard layoutWithoutSource.bottomRow == nil else { return nil }
            return layoutWithoutSource.creatingSecondRow(
                paneId: paneId,
                position: position
            )
        }
    }

    private func insertingAtSlot(
        paneId: UUID,
        row: DrawerRowPlacement,
        insertionIndex: Int
    ) -> DrawerGridLayout? {
        switch row {
        case .top:
            guard (0...topRow.paneIds.count).contains(insertionIndex) else { return nil }
            let updated = topRow.insertingPreservingRatios(paneId: paneId, insertionIndex: insertionIndex)
            return DrawerGridLayout(topRow: updated, bottomRow: bottomRow, rowSplitRatio: rowSplitRatio)
        case .bottom:
            guard let bottomRow else { return nil }
            guard (0...bottomRow.paneIds.count).contains(insertionIndex) else { return nil }
            let updated = bottomRow.insertingPreservingRatios(paneId: paneId, insertionIndex: insertionIndex)
            return DrawerGridLayout(topRow: topRow, bottomRow: updated, rowSplitRatio: rowSplitRatio)
        }
    }

    private func creatingSecondRow(
        paneId: UUID,
        position: DrawerRowPlacement
    ) -> DrawerGridLayout {
        switch position {
        case .top:
            return DrawerGridLayout(
                topRow: Layout(paneId: paneId),
                bottomRow: topRow,
                rowSplitRatio: rowSplitRatio
            )
        case .bottom:
            return DrawerGridLayout(
                topRow: topRow,
                bottomRow: Layout(paneId: paneId),
                rowSplitRatio: rowSplitRatio
            )
        }
    }
}

private extension Layout {
    func insertingPreservingRatios(
        paneId: UUID,
        insertionIndex: Int
    ) -> Layout {
        if paneIds.isEmpty {
            return Layout(paneId: paneId)
        }
        if insertionIndex == 0 {
            return inserting(
                paneId: paneId,
                at: paneIds[0],
                direction: .horizontal,
                position: .before
            )
        }
        if insertionIndex >= paneIds.count {
            return inserting(
                paneId: paneId,
                at: paneIds[paneIds.count - 1],
                direction: .horizontal,
                position: .after
            )
        }
        return inserting(
            paneId: paneId,
            at: paneIds[insertionIndex - 1],
            direction: .horizontal,
            position: .after
        )
    }
}
```

- [ ] **Step 4: Run the model tests to verify they pass**

Run: `swift test --build-path .build-agent-drawer-rearrange --filter DrawerGridLayoutRearrangeTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/AgentStudio/Core/Models/DrawerRearrangeTarget.swift Sources/AgentStudio/Core/Models/DrawerGridLayout+Rearrange.swift Tests/AgentStudioTests/Core/Models/DrawerGridLayoutRearrangeTests.swift
git commit -m "test: codify drawer rearrange model semantics" -m "Co-authored-by: Codex <noreply@openai.com>"
```

### Task 2: Convert The Validator And Action Surface To Explicit Targets

**Files:**
- Modify: `Sources/AgentStudio/Core/Actions/PaneActionCommand.swift`
- Modify: `Sources/AgentStudio/Core/Actions/DrawerCommandValidator.swift`
- Modify: `Sources/AgentStudio/Core/Actions/ActionValidator.swift`
- Create: `Tests/AgentStudioTests/Core/Actions/DrawerCommandValidatorTests.swift`
- Modify: `Tests/AgentStudioTests/Core/Actions/PaneDropPlannerTests.swift`

- [ ] **Step 1: Write the failing validator tests**

```swift
import Foundation
import Testing

@testable import AgentStudio

@Suite(.serialized)
struct DrawerCommandValidatorTests {
    private func makeState(
        parentPaneId: UUID,
        drawerPaneIds: [UUID],
        layout: DrawerGridLayout
    ) -> ActionStateSnapshot {
        ActionStateSnapshot(
            tabs: [
                TabSnapshot(
                    id: UUID(),
                    visiblePaneIds: [parentPaneId],
                    ownedPaneIds: [parentPaneId] + drawerPaneIds,
                    activePaneId: parentPaneId
                )
            ],
            activeTabId: nil,
            isManagementLayerActive: true,
            drawerParentByPaneId: Dictionary(uniqueKeysWithValues: drawerPaneIds.map { ($0, parentPaneId) }),
            drawerLayoutByParentPaneId: [parentPaneId: layout]
        )
    }

    @Test
    func validateMove_acceptsExplicitTopRowSlot() {
        let parent = UUID()
        let a = UUID()
        let b = UUID()
        let c = UUID()
        let state = makeState(
            parentPaneId: parent,
            drawerPaneIds: [a, b, c],
            layout: DrawerGridLayout(topRow: Layout.autoTiled([a, b, c]))
        )

        let result = DrawerCommandValidator.validateMove(
            parentPaneId: parent,
            drawerPaneId: c,
            target: .rowSlot(row: .top, insertionIndex: 0),
            state: state
        )

        #expect(result.isSuccess)
    }

    @Test
    func validateMove_acceptsCreateSecondRowFromOneRow() {
        let parent = UUID()
        let a = UUID()
        let b = UUID()
        let state = makeState(
            parentPaneId: parent,
            drawerPaneIds: [a, b],
            layout: DrawerGridLayout(topRow: Layout.autoTiled([a, b]))
        )

        let result = DrawerCommandValidator.validateMove(
            parentPaneId: parent,
            drawerPaneId: b,
            target: .createSecondRow(position: .bottom),
            state: state
        )

        #expect(result.isSuccess)
    }

    @Test
    func validateMove_rejectsThirdRowCreation() {
        let parent = UUID()
        let a = UUID()
        let b = UUID()
        let c = UUID()
        let state = makeState(
            parentPaneId: parent,
            drawerPaneIds: [a, b, c],
            layout: DrawerGridLayout(
                topRow: Layout.autoTiled([a, b]),
                bottomRow: Layout.autoTiled([c]),
                rowSplitRatio: 0.5
            )
        )

        let result = DrawerCommandValidator.validateMove(
            parentPaneId: parent,
            drawerPaneId: a,
            target: .createSecondRow(position: .bottom),
            state: state
        )

        #expect(result.isFailure)
    }
}
```

- [ ] **Step 2: Run the validator tests to verify they fail**

Run: `swift test --build-path .build-agent-drawer-rearrange --filter DrawerCommandValidatorTests`
Expected: FAIL because `moveDrawerPane` and `validateMove(...)` still use `(targetDrawerPaneId, direction)`.

- [ ] **Step 3: Convert the action and validator APIs**

```swift
// Sources/AgentStudio/Core/Actions/PaneActionCommand.swift
case moveDrawerPane(
    parentPaneId: UUID,
    drawerPaneId: UUID,
    target: DrawerRearrangeTarget
)
```

```swift
// Sources/AgentStudio/Core/Actions/DrawerCommandValidator.swift
static func validateMove(
    parentPaneId: UUID,
    drawerPaneId: UUID,
    target: DrawerRearrangeTarget,
    state: ActionStateSnapshot
) -> Result<Void, ActionValidationError> {
    if let membershipError = validateMembership(
        parentPaneId: parentPaneId,
        drawerPaneId: drawerPaneId,
        state: state
    ) {
        return .failure(membershipError)
    }

    guard let currentLayout = state.drawerLayout(for: parentPaneId) else {
        return .failure(.invalidDrawerLayout(parentPaneId: parentPaneId))
    }

    guard currentLayout.projectedMove(paneId: drawerPaneId, target: target) != nil else {
        return .failure(.invalidDrawerLayout(parentPaneId: parentPaneId))
    }

    return .success(())
}
```

```swift
// Sources/AgentStudio/Core/Actions/ActionValidator.swift
case .moveDrawerPane(let parentPaneId, let drawerPaneId, let target):
    return DrawerCommandValidator.validateMove(
        parentPaneId: parentPaneId,
        drawerPaneId: drawerPaneId,
        target: target,
        state: state
    ).map { ValidatedAction(action) }
```

Update existing planner tests and drawer integration tests to use the new action shape.

- [ ] **Step 4: Remove planner-side drawer move synthesis**

Drawer rearrange must be drawer-scoped only. In `PaneDropPlanner.splitDecision(...)`, remove the `targetDrawerParentPaneId` branch that synthesizes `.moveDrawerPane(...)` from main split drop inputs. Main-pane drops landing on drawer panes must become `.ineligible`.

```swift
// Sources/AgentStudio/Core/Actions/PaneDropPlanner.swift
private static func splitDecision(
    payload: SplitDropPayload,
    targetPaneId: UUID,
    targetTabId: UUID,
    direction: SplitNewDirection,
    targetDrawerParentPaneId: UUID?,
    state: ActionStateSnapshot
) -> PaneDropPreviewDecision {
    if targetDrawerParentPaneId != nil {
        return .ineligible
    }

    if case .existingPane(let sourcePaneId, _) = payload.kind,
        state.drawerParentPaneId(of: sourcePaneId) != nil
    {
        return .ineligible
    }

    guard
        let action = WorkspaceCommandResolver.resolveDrop(
            payload: payload,
            destinationPaneId: targetPaneId,
            destinationTabId: targetTabId,
            zone: dropZone(for: direction),
            state: state
        )
    else {
        return .ineligible
    }

    return eligiblePaneAction(action, state: state)
}
```

- [ ] **Step 5: Run the validator and planner tests to verify they pass**

Run: `swift test --build-path .build-agent-drawer-rearrange --filter 'DrawerCommandValidatorTests|PaneDropPlannerTests'`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources/AgentStudio/Core/Actions/PaneActionCommand.swift Sources/AgentStudio/Core/Actions/DrawerCommandValidator.swift Sources/AgentStudio/Core/Actions/ActionValidator.swift Sources/AgentStudio/Core/Actions/PaneDropPlanner.swift Tests/AgentStudioTests/Core/Actions/DrawerCommandValidatorTests.swift Tests/AgentStudioTests/Core/Actions/PaneDropPlannerTests.swift
git commit -m "refactor: make drawer move validation target-based" -m "Co-authored-by: Codex <noreply@openai.com>"
```

### Task 3: Rewrite Drawer Drag Resolution Around Explicit Targets

**Files:**
- Modify: `Sources/AgentStudio/Core/Views/Drawer/DrawerPaneDragCoordinator.swift`
- Modify: `Sources/AgentStudio/Core/Views/Drawer/DrawerSplitContainerDropCaptureOverlay.swift`
- Modify: `Sources/AgentStudio/Core/Views/Drawer/DrawerDropTargetOverlay.swift`
- Create: `Tests/AgentStudioTests/Core/Views/Drawer/DrawerPaneDragCoordinatorTests.swift`
- Delete: `Tests/AgentStudioTests/Core/Views/Drawer/DrawerDropZoneTests.swift`

- [ ] **Step 1: Write the failing drag-resolution tests**

```swift
import CoreGraphics
import Foundation
import Testing

@testable import AgentStudio

@Suite(.serialized)
struct DrawerPaneDragCoordinatorTests {
    @Test
    func oneRow_resolvesHorizontalSlots() {
        let a = UUID()
        let b = UUID()
        let c = UUID()
        let frames: [UUID: CGRect] = [
            a: CGRect(x: 0, y: 40, width: 100, height: 80),
            b: CGRect(x: 110, y: 40, width: 100, height: 80),
            c: CGRect(x: 220, y: 40, width: 100, height: 80),
        ]

        let target = DrawerPaneDragCoordinator.resolveTarget(
            location: CGPoint(x: 160, y: 80),
            paneFrames: frames,
            layout: DrawerGridLayout(topRow: Layout.autoTiled([a, b, c])),
            containerBounds: CGRect(x: 0, y: 0, width: 320, height: 140)
        )

        #expect(target == .rowSlot(row: .top, insertionIndex: 2))
    }

    @Test
    func oneRow_resolvesTopBandToCreateSecondRow() {
        let a = UUID()
        let frames: [UUID: CGRect] = [a: CGRect(x: 20, y: 40, width: 100, height: 80)]

        let target = DrawerPaneDragCoordinator.resolveTarget(
            location: CGPoint(x: 70, y: 15),
            paneFrames: frames,
            layout: DrawerGridLayout(topRow: Layout.autoTiled([a])),
            containerBounds: CGRect(x: 0, y: 0, width: 200, height: 140)
        )

        #expect(target == .createSecondRow(position: .top))
    }

    @Test
    func oneRow_exactMidpoint_prefersSmallerInsertionIndex() {
        let a = UUID()
        let b = UUID()
        let frames: [UUID: CGRect] = [
            a: CGRect(x: 0, y: 40, width: 100, height: 80),
            b: CGRect(x: 110, y: 40, width: 100, height: 80),
        ]

        let midpointX = (frames[a]!.midX + frames[b]!.midX) / 2
        let target = DrawerPaneDragCoordinator.resolveTarget(
            location: CGPoint(x: midpointX, y: 80),
            paneFrames: frames,
            layout: DrawerGridLayout(topRow: Layout.autoTiled([a, b])),
            containerBounds: CGRect(x: 0, y: 0, width: 220, height: 140)
        )

        #expect(target == .rowSlot(row: .top, insertionIndex: 1))
    }

    @Test
    func twoRows_resolvesBottomRowSlots() {
        let a = UUID()
        let b = UUID()
        let c = UUID()
        let frames: [UUID: CGRect] = [
            a: CGRect(x: 0, y: 0, width: 100, height: 60),
            b: CGRect(x: 110, y: 0, width: 100, height: 60),
            c: CGRect(x: 0, y: 80, width: 100, height: 60),
        ]

        let target = DrawerPaneDragCoordinator.resolveTarget(
            location: CGPoint(x: 105, y: 110),
            paneFrames: frames,
            layout: DrawerGridLayout(
                topRow: Layout.autoTiled([a, b]),
                bottomRow: Layout.autoTiled([c]),
                rowSplitRatio: 0.5
            ),
            containerBounds: CGRect(x: 0, y: 0, width: 220, height: 140)
        )

        #expect(target == .rowSlot(row: .bottom, insertionIndex: 1))
    }

    @Test
    func resolveLatchedTarget_matchesMainPaneContract() {
        let a = UUID()
        let frames: [UUID: CGRect] = [a: CGRect(x: 0, y: 40, width: 100, height: 80)]
        let currentTarget = DrawerRearrangeTarget.rowSlot(row: .top, insertionIndex: 0)

        let target = DrawerPaneDragCoordinator.resolveLatchedTarget(
            location: CGPoint(x: 500, y: 500),
            paneFrames: frames,
            layout: DrawerGridLayout(topRow: Layout.autoTiled([a])),
            containerBounds: CGRect(x: 0, y: 0, width: 200, height: 140),
            currentTarget: currentTarget,
            shouldAcceptDrop: { _ in true }
        )

        #expect(target == currentTarget)
    }

    @Test
    func twoRows_pointerOutsideBothRowBands_returnsNil() {
        let a = UUID()
        let b = UUID()
        let c = UUID()
        let frames: [UUID: CGRect] = [
            a: CGRect(x: 0, y: 0, width: 100, height: 60),
            b: CGRect(x: 110, y: 0, width: 100, height: 60),
            c: CGRect(x: 0, y: 90, width: 100, height: 60),
        ]

        let target = DrawerPaneDragCoordinator.resolveTarget(
            location: CGPoint(x: 50, y: 75),
            paneFrames: frames,
            layout: DrawerGridLayout(
                topRow: Layout.autoTiled([a, b]),
                bottomRow: Layout.autoTiled([c]),
                rowSplitRatio: 0.5
            ),
            containerBounds: CGRect(x: 0, y: 0, width: 220, height: 160)
        )

        #expect(target == nil)
    }

    @Test
    func emptyPaneFrames_returnNil() {
        let target = DrawerPaneDragCoordinator.resolveTarget(
            location: CGPoint(x: 50, y: 50),
            paneFrames: [:],
            layout: DrawerGridLayout(),
            containerBounds: CGRect(x: 0, y: 0, width: 220, height: 140)
        )

        #expect(target == nil)
    }
}
```

- [ ] **Step 2: Run the drag-resolution tests to verify they fail**

Run: `swift test --build-path .build-agent-drawer-rearrange --filter DrawerPaneDragCoordinatorTests`
Expected: FAIL because the coordinator still returns `DrawerPaneDropTarget(paneId, zone)`.

- [ ] **Step 3: Rewrite the drawer drag coordinator**

```swift
// Sources/AgentStudio/Core/Views/Drawer/DrawerPaneDragCoordinator.swift
import CoreGraphics
import Foundation

struct DrawerPaneDragCoordinator {
    static let creationBandHeight: CGFloat = 28

    static func resolveTarget(
        location: CGPoint,
        paneFrames: [UUID: CGRect],
        layout: DrawerGridLayout,
        containerBounds: CGRect
    ) -> DrawerRearrangeTarget? {
        guard !paneFrames.isEmpty else { return nil }

        if layout.bottomRow == nil {
            let topBand = CGRect(
                x: containerBounds.minX,
                y: containerBounds.minY,
                width: containerBounds.width,
                height: creationBandHeight
            )
            if topBand.contains(location) {
                return .createSecondRow(position: .top)
            }

            let bottomBand = CGRect(
                x: containerBounds.minX,
                y: containerBounds.maxY - creationBandHeight,
                width: containerBounds.width,
                height: creationBandHeight
            )
            if bottomBand.contains(location) {
                return .createSecondRow(position: .bottom)
            }

            return resolveRowSlot(
                location: location,
                paneIds: layout.topRow.paneIds,
                row: .top,
                paneFrames: paneFrames
            )
        }

        if let target = resolveRowSlot(
            location: location,
            paneIds: layout.topRow.paneIds,
            row: .top,
            paneFrames: paneFrames
        ) {
            return target
        }

        return resolveRowSlot(
            location: location,
            paneIds: layout.bottomRow?.paneIds ?? [],
            row: .bottom,
            paneFrames: paneFrames
        )
    }

    static func resolveLatchedTarget(
        location: CGPoint,
        paneFrames: [UUID: CGRect],
        layout: DrawerGridLayout,
        containerBounds: CGRect,
        currentTarget: DrawerRearrangeTarget?,
        shouldAcceptDrop: (DrawerRearrangeTarget) -> Bool
    ) -> DrawerRearrangeTarget? {
        if let resolvedTarget = resolveTarget(
            location: location,
            paneFrames: paneFrames,
            layout: layout,
            containerBounds: containerBounds
        ),
            shouldAcceptDrop(resolvedTarget)
        {
            return resolvedTarget
        }

        if let currentTarget, shouldAcceptDrop(currentTarget) {
            return currentTarget
        }

        return nil
    }

    private static func resolveRowSlot(
        location: CGPoint,
        paneIds: [UUID],
        row: DrawerRowPlacement,
        paneFrames: [UUID: CGRect]
    ) -> DrawerRearrangeTarget? {
        let sortedFrames = paneIds.compactMap { paneId -> CGRect? in
            paneFrames[paneId]
        }.sorted { $0.minX < $1.minX }
        guard !sortedFrames.isEmpty else { return nil }

        let rowMinY = sortedFrames.map(\\.minY).min() ?? 0
        let rowMaxY = sortedFrames.map(\\.maxY).max() ?? 0
        guard location.y >= rowMinY, location.y <= rowMaxY else { return nil }

        if location.x <= sortedFrames[0].midX {
            return .rowSlot(row: row, insertionIndex: 0)
        }

        for index in 1..<sortedFrames.count {
            let previousMidX = sortedFrames[index - 1].midX
            let currentMidX = sortedFrames[index].midX
            if location.x > previousMidX, location.x <= currentMidX {
                return .rowSlot(row: row, insertionIndex: index)
            }
        }

        return .rowSlot(row: row, insertionIndex: sortedFrames.count)
    }
}
```

- [ ] **Step 4: Rewrite the drawer overlay types**

```swift
// Sources/AgentStudio/Core/Views/Drawer/DrawerDropTargetOverlay.swift
import SwiftUI

struct DrawerDropTargetOverlay: View {
    let target: DrawerRearrangeTarget?
    let targetRects: [DrawerRearrangeTarget: CGRect]

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let target, let rect = targetRects[target] {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.accentColor.opacity(0.16))
                    .frame(width: rect.width, height: rect.height)
                    .offset(x: rect.minX, y: rect.minY)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
```

Remove `DrawerDropZone.swift` entirely once no code or tests reference it.

- [ ] **Step 5: Run the drawer drag-resolution tests to verify they pass**

Run: `swift test --build-path .build-agent-drawer-rearrange --filter DrawerPaneDragCoordinatorTests`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources/AgentStudio/Core/Views/Drawer/DrawerPaneDragCoordinator.swift Sources/AgentStudio/Core/Views/Drawer/DrawerSplitContainerDropCaptureOverlay.swift Sources/AgentStudio/Core/Views/Drawer/DrawerDropTargetOverlay.swift Tests/AgentStudioTests/Core/Views/Drawer/DrawerPaneDragCoordinatorTests.swift
git rm Tests/AgentStudioTests/Core/Views/Drawer/DrawerDropZoneTests.swift Sources/AgentStudio/Core/Views/Drawer/DrawerDropZone.swift
git commit -m "feat: resolve drawer drag targets by row slots" -m "Co-authored-by: Codex <noreply@openai.com>"
```

### Task 4: Wire DrawerPanel And Store Integration To The New Target Model

**Files:**
- Modify: `Sources/AgentStudio/Core/Views/Drawer/DrawerPanel.swift`
- Modify: `Sources/AgentStudio/Core/Views/Drawer/DrawerSplitContainerDropCaptureOverlay.swift`
- Modify: `Tests/AgentStudioTests/Core/Actions/DrawerCommandIntegrationTests.swift`
- Modify: `Tests/AgentStudioTests/Core/Stores/WorkspaceStoreDrawerTests.swift`

- [ ] **Step 1: Write the failing integration tests**

```swift
@Test
func test_moveDrawerPane_createBottomRow_fromSingleRow() throws {
    let (parentPaneId, _) = createParentPaneInTab()
    let first = try #require(store.addDrawerPane(to: parentPaneId))
    let second = try #require(store.addDrawerPane(to: parentPaneId))

    executor.execute(
        .moveDrawerPane(
            parentPaneId: parentPaneId,
            drawerPaneId: second.id,
            target: .createSecondRow(position: .bottom)
        )
    )

    let drawer = try #require(store.pane(parentPaneId)?.drawer)
    #expect(drawer.layout.topRow.paneIds == [first.id])
    #expect(drawer.layout.bottomRow?.paneIds == [second.id])
}

@Test
func test_moveDrawerPane_rowSlot_movesIntoBottomRowMiddleSlot() throws {
    let (parentPaneId, _) = createParentPaneInTab()
    let first = try #require(store.addDrawerPane(to: parentPaneId))
    let second = try #require(store.addDrawerPane(to: parentPaneId))
    let third = try #require(
        store.insertDrawerPane(
            in: parentPaneId,
            at: first.id,
            direction: .vertical,
            position: .after
        )
    )

    executor.execute(
        .moveDrawerPane(
            parentPaneId: parentPaneId,
            drawerPaneId: second.id,
            target: .rowSlot(row: .bottom, insertionIndex: 1)
        )
    )

    let drawer = try #require(store.pane(parentPaneId)?.drawer)
    #expect(drawer.bottomRow?.paneIds == [third.id, second.id])
}
```

- [ ] **Step 2: Run the integration tests to verify they fail**

Run: `swift test --build-path .build-agent-drawer-rearrange --filter 'DrawerCommandIntegrationTests|WorkspaceStoreDrawerTests'`
Expected: FAIL because executor/store still use the old move signature.

- [ ] **Step 3: Wire the new target model through the UI and store**

```swift
// Sources/AgentStudio/Core/Views/Drawer/DrawerPanel.swift
@State private var dropTarget: DrawerRearrangeTarget?
@State private var targetRects: [DrawerRearrangeTarget: CGRect] = [:]

private func shouldAcceptDrawerDrop(
    payload: SplitDropPayload,
    target: DrawerRearrangeTarget
) -> Bool {
    guard case .existingPane(let sourcePaneId, _) = payload.kind else { return false }

    let snapshot = WorkspaceCommandResolver.snapshot(
        from: store.tabLayoutAtom.tabs,
        activeTabId: store.tabLayoutAtom.activeTabId,
        isManagementLayerActive: atom(\\.managementLayer).isActive,
        knownWorktreeIds: Set(store.repositoryTopologyAtom.repos.flatMap(\\.worktrees).map(\\.id)),
        drawerParentByPaneId: drawerParentByPaneId(),
        drawerLayoutByParentPaneId: drawerLayoutByParentPaneId()
    )

    let action = PaneActionCommand.moveDrawerPane(
        parentPaneId: parentPaneId,
        drawerPaneId: sourcePaneId,
        target: target
    )

    if case .success = WorkspaceCommandValidator.validate(action, state: snapshot) {
        return true
    }
    return false
}
```

```swift
// Sources/AgentStudio/Core/Views/Drawer/DrawerSplitContainerDropCaptureOverlay.swift
struct DrawerSplitContainerDropCaptureOverlay: NSViewRepresentable {
    let paneFrames: [UUID: CGRect]
    let layout: DrawerGridLayout
    let containerBounds: CGRect
    @Binding var target: DrawerRearrangeTarget?
    let isManagementLayerActive: Bool
    let shouldAcceptDrop: (SplitDropPayload, DrawerRearrangeTarget) -> Bool
    let handleDrop: (SplitDropPayload, DrawerRearrangeTarget) -> Void
}
```

Update the coordinator to call:

```swift
DrawerPaneDragCoordinator.resolveLatchedTarget(
    location: location,
    paneFrames: paneFrames,
    layout: layout,
    containerBounds: containerBounds,
    currentTarget: targetBinding.wrappedValue,
    shouldAcceptDrop: { target in
        shouldAcceptDropClosure(payload, target)
    }
)
```

Update store-side move helpers to consume `DrawerRearrangeTarget` and delegate to `DrawerGridLayout.projectedMove(...)`.

- [ ] **Step 4: Run the integration suites to verify they pass**

Run: `swift test --build-path .build-agent-drawer-rearrange --filter 'DrawerCommandIntegrationTests|WorkspaceStoreDrawerTests|DrawerPaneDragCoordinatorTests'`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/AgentStudio/Core/Views/Drawer/DrawerPanel.swift Sources/AgentStudio/Core/Views/Drawer/DrawerSplitContainerDropCaptureOverlay.swift Tests/AgentStudioTests/Core/Actions/DrawerCommandIntegrationTests.swift Tests/AgentStudioTests/Core/Stores/WorkspaceStoreDrawerTests.swift
git commit -m "feat: wire drawer UI to explicit rearrange targets" -m "Co-authored-by: Codex <noreply@openai.com>"
```

### Task 5: Full Verification And Visual Repro

**Files:**
- No new files

- [ ] **Step 1: Run focused drawer suites**

Run:

```bash
swift test --build-path .build-agent-drawer-rearrange --filter 'DrawerGridLayoutRearrangeTests|DrawerCommandValidatorTests|DrawerPaneDragCoordinatorTests|DrawerCommandIntegrationTests|WorkspaceStoreDrawerTests|PaneDropPlannerTests'
```

Expected: PASS.

- [ ] **Step 2: Run lint**

Run:

```bash
mise run lint
```

Expected: exit 0, no violations.

- [ ] **Step 3: Run the full suite**

Run:

```bash
mise run test
```

Expected:
- main pass green
- serialized WebKit green
- E2E / Zmx E2E still skipped unless explicitly enabled

- [ ] **Step 4: Visually verify the drawer drag semantics**

Confirm all of these:

- one row with 3 panes:
  - visible slot targets appear before first, between panes, and after last
  - top band and bottom band appear
- dragging into top band creates a new top row containing only the dragged pane
- dragging into bottom band creates a new bottom row containing only the dragged pane
- two rows:
  - top-row slots and bottom-row slots are both visible
  - dragging into a slot in the other row moves the pane there
  - no third-row target is ever shown
- while dragging inside the drawer:
  - no main-pane hover target appears
  - no main split target latches

- [ ] **Step 5: Final commit**

```bash
git add Sources/AgentStudio/Core/Models/DrawerRearrangeTarget.swift Sources/AgentStudio/Core/Models/DrawerGridLayout+Rearrange.swift Sources/AgentStudio/Core/Actions/PaneActionCommand.swift Sources/AgentStudio/Core/Actions/DrawerCommandValidator.swift Sources/AgentStudio/Core/Actions/ActionValidator.swift Sources/AgentStudio/Core/Views/Drawer/DrawerPaneDragCoordinator.swift Sources/AgentStudio/Core/Views/Drawer/DrawerSplitContainerDropCaptureOverlay.swift Sources/AgentStudio/Core/Views/Drawer/DrawerDropTargetOverlay.swift Sources/AgentStudio/Core/Views/Drawer/DrawerPanel.swift Sources/AgentStudio/Core/Views/Splits/PaneInteractionOcclusionPolicy.swift Sources/AgentStudio/Core/Views/Splits/PaneLeafContainer.swift Sources/AgentStudio/Core/Views/Drawer/DrawerPanelOverlay.swift Tests/AgentStudioTests/Core/Models/DrawerGridLayoutRearrangeTests.swift Tests/AgentStudioTests/Core/Actions/DrawerCommandValidatorTests.swift Tests/AgentStudioTests/Core/Views/Drawer/DrawerPaneDragCoordinatorTests.swift Tests/AgentStudioTests/Core/Actions/DrawerCommandIntegrationTests.swift Tests/AgentStudioTests/Core/Stores/WorkspaceStoreDrawerTests.swift Tests/AgentStudioTests/Core/Actions/PaneDropPlannerTests.swift Tests/AgentStudioTests/Core/Views/Splits/PaneInteractionOcclusionPolicyTests.swift
git commit -m "fix: rewrite drawer rearrange around row-slot targets" -m "Co-authored-by: Codex <noreply@openai.com>"
```

## Self-Review

Spec coverage:

- Explicit one-row reorder semantics: covered in Task 1 and Task 3.
- Explicit one-row to two-row semantics: covered in Task 1 and Task 4.
- Two-row row-specific insertion semantics: covered in Task 1, Task 3, and Task 4.
- Third-row prohibition: covered in Task 1 and Task 2.
- Validator remains post-resolution only: covered in Task 2.
- Main/drawer isolation remains intact: covered in Task 0 and Task 5 visual verification.
- Latching stays symmetric with main pane: covered in Task 3.

Placeholder scan:

- No `TODO`, `TBD`, or “similar to above” placeholders remain.
- Every changed signature is defined before it is used in later tasks.

Type consistency:

- The plan consistently uses `DrawerRowPlacement`, `DrawerRearrangeTarget`, `.rowSlot`, and `.createSecondRow`.
- `moveDrawerPane` consistently changes to `target: DrawerRearrangeTarget`.
- Latching signatures are explicitly aligned with the main-pane contract.
