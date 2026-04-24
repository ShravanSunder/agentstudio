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
        let rightTarget = DrawerPaneDragCoordinator.resolveTarget(
            location: CGPoint(x: 185, y: 80),
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
        minimizedPaneIds: Set<UUID> = []
    ) -> DrawerPaneDragGeometry {
        DrawerPaneDragGeometry(
            paneFrames: paneFrames,
            layout: layout,
            containerBounds: bounds,
            minimizedPaneIds: minimizedPaneIds
        )
    }
}
