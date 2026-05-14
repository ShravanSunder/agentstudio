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
            location: CGPoint(x: 105, y: 80),
            geometry: geometry(
                paneFrames: frames,
                layout: DrawerGridLayout(topRow: Layout.autoTiled([a, b, c])),
                bounds: CGRect(x: 0, y: 0, width: 320, height: 140)
            )
        )

        #expect(target == .rowSlot(row: .top, insertionIndex: 1))
    }

    @Test
    func oneRow_locationInsidePaneHalf_resolvesPaneSplit() {
        let a = UUID()
        let b = UUID()
        let frames: [UUID: CGRect] = [
            a: CGRect(x: 0, y: 40, width: 100, height: 80),
            b: CGRect(x: 110, y: 40, width: 100, height: 80),
        ]

        let leftTarget = DrawerPaneDragCoordinator.resolveTarget(
            location: CGPoint(x: 25, y: 80),
            geometry: geometry(
                paneFrames: frames,
                layout: DrawerGridLayout(topRow: Layout.autoTiled([a, b])),
                bounds: CGRect(x: 0, y: 0, width: 220, height: 140)
            )
        )
        // x=170 lands in paneB's center zone [135, 185), right of midX
        // (160) → split-right. (Was x=185 under the old whole-pane-
        // split model; 185 is now in paneB's right 1/4 zone, which
        // produces a between-slot target instead.)
        let rightTarget = DrawerPaneDragCoordinator.resolveTarget(
            location: CGPoint(x: 170, y: 80),
            geometry: geometry(
                paneFrames: frames,
                layout: DrawerGridLayout(topRow: Layout.autoTiled([a, b])),
                bounds: CGRect(x: 0, y: 0, width: 220, height: 140)
            )
        )

        #expect(leftTarget == .paneSplit(paneId: a, side: .left))
        #expect(rightTarget == .paneSplit(paneId: b, side: .right))
    }

    @Test
    func oneRow_minimizedPaneIsNotSplittableAndFallsBackToSlot() {
        let a = UUID()
        let b = UUID()
        let frames: [UUID: CGRect] = [
            a: CGRect(x: 0, y: 40, width: 100, height: 80),
            b: CGRect(x: 110, y: 40, width: 100, height: 80),
        ]

        let target = DrawerPaneDragCoordinator.resolveTarget(
            location: CGPoint(x: 25, y: 80),
            geometry: geometry(
                paneFrames: frames,
                layout: DrawerGridLayout(topRow: Layout.autoTiled([a, b])),
                bounds: CGRect(x: 0, y: 0, width: 220, height: 140),
                minimizedPaneIds: [a]
            )
        )

        #expect(target == .rowSlot(row: .top, insertionIndex: 0))
    }

    @Test
    func oneRow_cursorOverSourceWithFrame_rejectsSelfAndAdjacentSlots() {
        // Source (a) has a frame and is at geometric index 0 → R1 rejects
        // split(a) and R2 rejects slot 0 (= source's position). Cursor in
        // pane a's left half resolves to slot 0 (since a is excluded from
        // splittable), which is then source-rejected → nil.
        let a = UUID()
        let b = UUID()
        let frames: [UUID: CGRect] = [
            a: CGRect(x: 0, y: 40, width: 100, height: 80),
            b: CGRect(x: 110, y: 40, width: 100, height: 80),
        ]

        let target = DrawerPaneDragCoordinator.resolveTarget(
            location: CGPoint(x: 25, y: 80),
            geometry: geometry(
                paneFrames: frames,
                layout: DrawerGridLayout(topRow: Layout.autoTiled([a, b])),
                bounds: CGRect(x: 0, y: 0, width: 220, height: 140),
                excludedPaneIds: [a]
            )
        )

        #expect(target == nil)
    }

    @Test
    func oneRow_rowSlotVisualBetweenPanes_isCenteredInsertionMarker() throws {
        let a = UUID()
        let b = UUID()
        let frames: [UUID: CGRect] = [
            a: CGRect(x: 0, y: 40, width: 100, height: 80),
            b: CGRect(x: 120, y: 40, width: 100, height: 80),
        ]

        let visuals = DrawerPaneDragCoordinator.targetVisuals(
            geometry: geometry(
                paneFrames: frames,
                layout: DrawerGridLayout(topRow: Layout.autoTiled([a, b])),
                bounds: CGRect(x: 0, y: 0, width: 220, height: 140)
            )
        )

        let visual = try #require(visuals[.rowSlot(row: .top, insertionIndex: 1)])
        let markerRect = try #require(visual.insertionMarker)
        let expectedMarkerWidth = AppStyles.General.Layout.dropTargetMarkerWidth

        #expect(markerRect.width == expectedMarkerWidth)
        #expect(markerRect.midX == 110)
        #expect(markerRect.minY == 40)
        #expect(markerRect.height == 80)
    }

    @Test
    func oneRow_rowSlotVisualWithSourceFramePresent_matchesResolvedTarget() throws {
        let source = UUID()
        let middle = UUID()
        let right = UUID()
        let frames: [UUID: CGRect] = [
            source: CGRect(x: 0, y: 40, width: 100, height: 80),
            middle: CGRect(x: 120, y: 40, width: 100, height: 80),
            right: CGRect(x: 240, y: 40, width: 100, height: 80),
        ]
        let layout = DrawerGridLayout(topRow: Layout.autoTiled([source, middle, right]))
        let bounds = CGRect(x: 0, y: 0, width: 340, height: 140)
        let location = CGPoint(x: 230, y: 80)

        let target = DrawerPaneDragCoordinator.resolveTarget(
            location: location,
            geometry: geometry(
                paneFrames: frames,
                layout: layout,
                bounds: bounds,
                excludedPaneIds: [source]
            )
        )
        let visuals = DrawerPaneDragCoordinator.targetVisuals(
            geometry: geometry(
                paneFrames: frames,
                layout: layout,
                bounds: bounds
            )
        )

        #expect(target == .rowSlot(row: .top, insertionIndex: 2))
        let resolvedTarget = try #require(target)
        let visual = try #require(visuals[resolvedTarget])
        let markerRect = try #require(visual.insertionMarker)
        #expect(markerRect.midX == 230)
    }

    @Test
    func oneRow_paneSplitVisual_isRegionNotInsertionMarker() throws {
        let a = UUID()
        let frames: [UUID: CGRect] = [
            a: CGRect(x: 20, y: 40, width: 100, height: 80)
        ]

        let visuals = DrawerPaneDragCoordinator.targetVisuals(
            geometry: geometry(
                paneFrames: frames,
                layout: DrawerGridLayout(topRow: Layout.autoTiled([a])),
                bounds: CGRect(x: 0, y: 0, width: 180, height: 140)
            )
        )

        let visual = try #require(visuals[.paneSplit(paneId: a, side: .left)])

        #expect(visual.insertionMarker == nil)
        #expect(visual.region == CGRect(x: 20, y: 40, width: 50, height: 80))
    }

    @Test
    func oneRow_resolvesTopBandToCreateSecondRow() {
        let a = UUID()
        let frames: [UUID: CGRect] = [a: CGRect(x: 20, y: 40, width: 100, height: 80)]

        let target = DrawerPaneDragCoordinator.resolveTarget(
            location: CGPoint(x: 70, y: 15),
            geometry: geometry(
                paneFrames: frames,
                layout: DrawerGridLayout(topRow: Layout.autoTiled([a])),
                bounds: CGRect(x: 0, y: 0, width: 200, height: 140)
            )
        )

        #expect(target == .createSecondRow(position: .top))
    }

    @Test
    func oneRow_createSecondRowVisual_isFullWidthBand() throws {
        let a = UUID()
        let frames: [UUID: CGRect] = [a: CGRect(x: 20, y: 40, width: 100, height: 80)]
        let bounds = CGRect(x: 0, y: 0, width: 200, height: 140)

        let visuals = DrawerPaneDragCoordinator.targetVisuals(
            geometry: geometry(
                paneFrames: frames,
                layout: DrawerGridLayout(topRow: Layout.autoTiled([a])),
                bounds: bounds
            )
        )

        let visual = try #require(visuals[.createSecondRow(position: .bottom)])

        #expect(visual.insertionMarker == nil)
        #expect(visual.region == CGRect(x: 0, y: 112, width: 200, height: 28))
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
            geometry: geometry(
                paneFrames: frames,
                layout: DrawerGridLayout(topRow: Layout.autoTiled([a, b])),
                bounds: CGRect(x: 0, y: 0, width: 220, height: 140)
            )
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
            geometry: geometry(
                paneFrames: frames,
                layout: DrawerGridLayout(
                    topRow: Layout.autoTiled([a, b]),
                    bottomRow: Layout.autoTiled([c]),
                    rowSplitRatio: 0.5
                ),
                bounds: CGRect(x: 0, y: 0, width: 220, height: 140)
            )
        )

        #expect(target == .rowSlot(row: .bottom, insertionIndex: 1))
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
            geometry: geometry(
                paneFrames: frames,
                layout: DrawerGridLayout(
                    topRow: Layout.autoTiled([a, b]),
                    bottomRow: Layout.autoTiled([c]),
                    rowSplitRatio: 0.5
                ),
                bounds: CGRect(x: 0, y: 0, width: 220, height: 160)
            )
        )

        #expect(target == nil)
    }

    @Test
    func twoRows_topBandDoesNotResolveToCreateSecondRow() {
        let a = UUID()
        let b = UUID()
        let c = UUID()
        let frames: [UUID: CGRect] = [
            a: CGRect(x: 0, y: 20, width: 100, height: 40),
            b: CGRect(x: 110, y: 20, width: 100, height: 40),
            c: CGRect(x: 0, y: 80, width: 100, height: 40),
        ]

        let target = DrawerPaneDragCoordinator.resolveTarget(
            location: CGPoint(x: 60, y: 10),
            geometry: geometry(
                paneFrames: frames,
                layout: DrawerGridLayout(
                    topRow: Layout.autoTiled([a, b]),
                    bottomRow: Layout.autoTiled([c]),
                    rowSplitRatio: 0.5
                ),
                bounds: CGRect(x: 0, y: 0, width: 220, height: 140)
            )
        )

        #expect(target == nil)
    }

    @Test
    func emptyPaneFrames_returnNil() {
        let target = DrawerPaneDragCoordinator.resolveTarget(
            location: CGPoint(x: 50, y: 50),
            geometry: geometry(
                paneFrames: [:],
                layout: DrawerGridLayout(),
                bounds: CGRect(x: 0, y: 0, width: 220, height: 140)
            )
        )

        #expect(target == nil)
    }

    @Test
    func resolveLatchedTarget_matchesMainPaneContract() {
        let a = UUID()
        let frames: [UUID: CGRect] = [a: CGRect(x: 0, y: 40, width: 100, height: 80)]
        let currentTarget = DrawerRearrangeTarget.rowSlot(row: .top, insertionIndex: 0)

        let target = DrawerPaneDragCoordinator.resolveLatchedTarget(
            location: CGPoint(x: 500, y: 500),
            geometry: geometry(
                paneFrames: frames,
                layout: DrawerGridLayout(topRow: Layout.autoTiled([a])),
                bounds: CGRect(x: 0, y: 0, width: 200, height: 140)
            ),
            currentTarget: currentTarget,
            shouldAcceptDrop: { _ in true }
        )

        #expect(target == currentTarget)
    }

    private func geometry(
        paneFrames: [UUID: CGRect],
        layout: DrawerGridLayout,
        bounds: CGRect,
        minimizedPaneIds: Set<UUID> = [],
        excludedPaneIds: Set<UUID> = []
    ) -> DrawerPaneDragGeometry {
        DrawerPaneDragGeometry(
            paneFrames: paneFrames,
            layout: layout,
            containerBounds: bounds,
            minimizedPaneIds: minimizedPaneIds,
            excludedPaneIds: excludedPaneIds
        )
    }
}
