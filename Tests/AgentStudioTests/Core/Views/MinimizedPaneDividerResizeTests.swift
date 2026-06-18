import CoreGraphics
import Foundation
import Testing

@testable import AgentStudio

@Suite
struct MinimizedPaneDividerResizeTests {
    private let bounds = CGRect(x: 0, y: 0, width: 1000, height: 500)
    private let dividerThickness: CGFloat = 8
    private let collapsedPaneWidth: CGFloat = 40
    private let minimumPaneSize: CGFloat = 50

    @Test
    func draggingLeftHandleAroundMinimizedMiddlePaneMovesByPointerDelta() throws {
        let paneIds = PaneIds(count: 3)
        let layout = Layout.autoTiled(paneIds.values)
        let initialMetrics = metrics(for: layout, minimizedPaneIds: [paneIds[1]])
        let divider = try #require(initialMetrics.dividerSegments.first)
        let updatedLayout = drag(divider: divider, in: layout, translation: 40)
        let updatedMetrics = metrics(for: updatedLayout, minimizedPaneIds: [paneIds[1]])

        let actualDelta = try dividerMovement(
            paneId: paneIds[0],
            from: initialMetrics,
            to: updatedMetrics
        )

        #expect(abs(actualDelta - 40) < 1)
        #expect(ratio(for: paneIds[1], in: updatedLayout).isApproximately(ratio(for: paneIds[1], in: layout)))
        #expect(width(for: paneIds[1], in: updatedMetrics) == collapsedPaneWidth)
    }

    @Test
    func draggingRightHandleAroundMinimizedMiddlePaneMovesByPointerDelta() throws {
        let paneIds = PaneIds(count: 3)
        let layout = Layout.autoTiled(paneIds.values)
        let initialMetrics = metrics(for: layout, minimizedPaneIds: [paneIds[1]])
        let divider = try #require(initialMetrics.dividerSegments.last)
        let updatedLayout = drag(divider: divider, in: layout, translation: -40)
        let updatedMetrics = metrics(for: updatedLayout, minimizedPaneIds: [paneIds[1]])

        let actualDelta = try dividerMovement(
            paneId: paneIds[0],
            from: initialMetrics,
            to: updatedMetrics
        )

        #expect(abs(actualDelta - -40) < 1)
        #expect(ratio(for: paneIds[1], in: updatedLayout).isApproximately(ratio(for: paneIds[1], in: layout)))
        #expect(width(for: paneIds[1], in: updatedMetrics) == collapsedPaneWidth)
    }

    @Test
    func draggingAroundConsecutiveMinimizedPanesPreservesHiddenRatios() throws {
        let paneIds = PaneIds(count: 4)
        let layout = Layout.autoTiled(paneIds.values)
        let minimizedPaneIds: Set<UUID> = [paneIds[1], paneIds[2]]
        let initialMetrics = metrics(for: layout, minimizedPaneIds: minimizedPaneIds)
        let divider = try #require(initialMetrics.dividerSegments.first)
        let updatedLayout = drag(divider: divider, in: layout, translation: 40)
        let updatedMetrics = metrics(for: updatedLayout, minimizedPaneIds: minimizedPaneIds)

        let actualDelta = try dividerMovement(
            paneId: paneIds[0],
            from: initialMetrics,
            to: updatedMetrics
        )

        #expect(abs(actualDelta - 40) < 1)
        #expect(ratio(for: paneIds[1], in: updatedLayout).isApproximately(ratio(for: paneIds[1], in: layout)))
        #expect(ratio(for: paneIds[2], in: updatedLayout).isApproximately(ratio(for: paneIds[2], in: layout)))
        #expect(width(for: paneIds[1], in: updatedMetrics) == collapsedPaneWidth)
        #expect(width(for: paneIds[2], in: updatedMetrics) == collapsedPaneWidth)
    }

    @Test
    func draggingAroundMinimizedPaneDoesNotMoveUnrelatedVisiblePane() throws {
        let paneIds = PaneIds(count: 4)
        let layout = Layout.autoTiled(paneIds.values)
        let initialMetrics = metrics(for: layout, minimizedPaneIds: [paneIds[1]])
        let divider = try #require(initialMetrics.dividerSegments.first)
        let updatedLayout = drag(divider: divider, in: layout, translation: 40)
        let updatedMetrics = metrics(for: updatedLayout, minimizedPaneIds: [paneIds[1]])

        #expect(width(for: paneIds[3], in: updatedMetrics) == width(for: paneIds[3], in: initialMetrics))
        #expect(ratio(for: paneIds[3], in: updatedLayout).isApproximately(ratio(for: paneIds[3], in: layout)))
    }

    @Test
    func draggingEdgeMinimizedBoundaryDoesNotResize() throws {
        let paneIds = PaneIds(count: 3)
        let layout = Layout.autoTiled(paneIds.values)
        let initialMetrics = metrics(for: layout, minimizedPaneIds: [paneIds[0]])
        let divider = try #require(initialMetrics.dividerSegments.first)
        let updatedLayout = drag(divider: divider, in: layout, translation: 40)
        let updatedMetrics = metrics(for: updatedLayout, minimizedPaneIds: [paneIds[0]])

        #expect(updatedLayout.ratios == layout.ratios)
        #expect(updatedMetrics.paneSegments.map(\.frame.width) == initialMetrics.paneSegments.map(\.frame.width))
    }

    @Test
    func draggingRightEdgeMinimizedBoundaryDoesNotResize() throws {
        let paneIds = PaneIds(count: 3)
        let layout = Layout.autoTiled(paneIds.values)
        let initialMetrics = metrics(for: layout, minimizedPaneIds: [paneIds[2]])
        let divider = try #require(initialMetrics.dividerSegments.last)
        let updatedLayout = drag(divider: divider, in: layout, translation: -40)
        let updatedMetrics = metrics(for: updatedLayout, minimizedPaneIds: [paneIds[2]])

        #expect(updatedLayout.ratios == layout.ratios)
        #expect(updatedMetrics.paneSegments.map(\.frame.width) == initialMetrics.paneSegments.map(\.frame.width))
    }

    @Test
    func overdragAroundMinimizedPaneClampsWithoutChangingHiddenRatio() throws {
        let paneIds = PaneIds(count: 3)
        let layout = Layout.autoTiled(paneIds.values)
        let initialMetrics = metrics(for: layout, minimizedPaneIds: [paneIds[1]])
        let divider = try #require(initialMetrics.dividerSegments.first)
        let updatedLayout = drag(divider: divider, in: layout, translation: 1000)

        #expect(ratio(for: paneIds[1], in: updatedLayout).isApproximately(ratio(for: paneIds[1], in: layout)))
        #expect(ratio(for: paneIds[0], in: updatedLayout) <= 0.9)
    }

    @Test
    func oppositeOverdragAroundMinimizedPaneClampsWithoutChangingHiddenRatio() throws {
        let paneIds = PaneIds(count: 3)
        let layout = Layout.autoTiled(paneIds.values)
        let initialMetrics = metrics(for: layout, minimizedPaneIds: [paneIds[1]])
        let divider = try #require(initialMetrics.dividerSegments.last)
        let updatedLayout = drag(divider: divider, in: layout, translation: -1000)

        #expect(ratio(for: paneIds[1], in: updatedLayout).isApproximately(ratio(for: paneIds[1], in: layout)))
        #expect((updatedLayout.ratioForPanePair(leftPaneId: paneIds[0], rightPaneId: paneIds[2]) ?? 0) >= 0.1)
    }

    @Test
    func dividerResizeIntentUsesSameVisiblePairBaselineOnBothSidesOfMinimizedRun() throws {
        let paneIds = PaneIds(count: 3)
        let layout = Layout.autoTiled(paneIds.values)
        let metrics = metrics(for: layout, minimizedPaneIds: [paneIds[1]])

        let dividerBeforeMinimized = try #require(metrics.dividerSegments.first)
        let dividerAfterMinimized = try #require(metrics.dividerSegments.last)

        #expect(
            dividerBeforeMinimized.resizeIntent == .visiblePanePair(leftPaneId: paneIds[0], rightPaneId: paneIds[2])
        )
        #expect(
            dividerAfterMinimized.resizeIntent == .visiblePanePair(leftPaneId: paneIds[0], rightPaneId: paneIds[2])
        )
        #expect(dividerBeforeMinimized.resizeLeftPaneWidth == dividerAfterMinimized.resizeLeftPaneWidth)
        #expect(dividerBeforeMinimized.resizeRightPaneWidth == dividerAfterMinimized.resizeRightPaneWidth)
        #expect(dividerBeforeMinimized.visualRightPaneWidth == collapsedPaneWidth)
        #expect(dividerAfterMinimized.visualLeftPaneWidth == collapsedPaneWidth)
    }

    @Test
    func edgeMinimizedDividerHasNoResizeIntent() throws {
        let paneIds = PaneIds(count: 3)
        let layout = Layout.autoTiled(paneIds.values)
        let metrics = metrics(for: layout, minimizedPaneIds: [paneIds[0]])
        let edgeDivider = try #require(metrics.dividerSegments.first)

        #expect(edgeDivider.resizeIntent == .noResize)
        #expect(edgeDivider.resizeLeftPaneWidth == 0)
        #expect(edgeDivider.resizeRightPaneWidth == 0)
    }

    @Test
    func rightEdgeMinimizedDividerHasNoResizeIntent() throws {
        let paneIds = PaneIds(count: 3)
        let layout = Layout.autoTiled(paneIds.values)
        let metrics = metrics(for: layout, minimizedPaneIds: [paneIds[2]])
        let edgeDivider = try #require(metrics.dividerSegments.last)

        #expect(edgeDivider.resizeIntent == .noResize)
        #expect(edgeDivider.resizeLeftPaneWidth == 0)
        #expect(edgeDivider.resizeRightPaneWidth == 0)
    }

    @Test
    func resizeCommandMapsVisiblePairIntentToVisiblePairCommand() {
        let tabId = UUID()
        let leftPaneId = UUID()
        let rightPaneId = UUID()

        let command = FlatPaneDivider.resizeCommand(
            for: .visiblePanePair(leftPaneId: leftPaneId, rightPaneId: rightPaneId),
            tabId: tabId,
            ratio: 0.4
        )

        #expect(
            command
                == .resizeVisiblePanePair(tabId: tabId, leftPaneId: leftPaneId, rightPaneId: rightPaneId, ratio: 0.4))
    }

    private func drag(
        divider: FlatTabStripMetrics.DividerSegment,
        in layout: Layout,
        translation: CGFloat
    ) -> Layout {
        let ratio = FlatPaneDivider.computeResizeRatio(
            initialLeftWidth: divider.resizeLeftPaneWidth,
            initialRightWidth: divider.resizeRightPaneWidth,
            translationWidth: translation,
            minSize: minimumPaneSize
        )
        switch divider.resizeIntent {
        case .structural(let splitId):
            return layout.resizing(splitId: splitId, ratio: ratio)
        case .visiblePanePair(let leftPaneId, let rightPaneId):
            return layout.resizingPanePair(leftPaneId: leftPaneId, rightPaneId: rightPaneId, ratio: ratio)
        case .noResize:
            return layout
        }
    }

    private func metrics(for layout: Layout, minimizedPaneIds: Set<UUID>) -> FlatTabStripMetrics {
        FlatTabStripMetrics.compute(
            layout: layout,
            in: bounds,
            dividerThickness: dividerThickness,
            minimizedPaneIds: minimizedPaneIds,
            collapsedPaneWidth: collapsedPaneWidth
        )
    }

    private func dividerMovement(
        paneId: UUID,
        from initialMetrics: FlatTabStripMetrics,
        to updatedMetrics: FlatTabStripMetrics
    ) throws -> CGFloat {
        let initialSegment = try #require(segment(for: paneId, in: initialMetrics))
        let updatedSegment = try #require(segment(for: paneId, in: updatedMetrics))
        return updatedSegment.frame.maxX - initialSegment.frame.maxX
    }

    private func segment(for paneId: UUID, in metrics: FlatTabStripMetrics) -> FlatTabStripMetrics.PaneSegment? {
        metrics.paneSegments.first { $0.paneId == paneId }
    }

    private func width(for paneId: UUID, in metrics: FlatTabStripMetrics) -> CGFloat {
        segment(for: paneId, in: metrics)?.frame.width ?? 0
    }

    private func ratio(for paneId: UUID, in layout: Layout) -> Double {
        layout.panes.first { $0.paneId == paneId }?.ratio ?? 0
    }

    private struct PaneIds {
        let values: [UUID]

        init(count: Int) {
            values = (0..<count).map { _ in UUID() }
        }

        subscript(index: Int) -> UUID {
            values[index]
        }
    }
}

extension Double {
    fileprivate func isApproximately(_ other: Double, tolerance: Double = 1e-9) -> Bool {
        abs(self - other) <= tolerance
    }
}
