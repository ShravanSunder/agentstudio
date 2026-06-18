import CoreGraphics
import Foundation

struct FlatTabStripMetrics {
    struct PaneSegment: Hashable {
        let paneId: UUID
        let frame: CGRect
        let isMinimized: Bool
    }

    struct DividerSegment: Hashable {
        enum ResizeIntent: Hashable {
            case structural(splitId: UUID)
            case visiblePanePair(leftPaneId: UUID, rightPaneId: UUID)
            case noResize
        }

        let dividerId: UUID
        let leftPaneId: UUID
        let rightPaneId: UUID
        let frame: CGRect
        let visualLeftPaneWidth: CGFloat
        let visualRightPaneWidth: CGFloat
        let resizeIntent: ResizeIntent
        let resizeLeftPaneWidth: CGFloat
        let resizeRightPaneWidth: CGFloat
    }

    let paneSegments: [PaneSegment]
    let dividerSegments: [DividerSegment]
    let allMinimized: Bool

    static func compute(
        layout: Layout,
        in bounds: CGRect,
        dividerThickness: CGFloat,
        minimizedPaneIds: Set<UUID>,
        collapsedPaneWidth: CGFloat
    ) -> Self {
        guard !layout.panes.isEmpty, !bounds.isEmpty else {
            return Self(paneSegments: [], dividerSegments: [], allMinimized: false)
        }

        let allMinimized = layout.panes.allSatisfy { minimizedPaneIds.contains($0.paneId) }
        let visiblePanes = layout.panes.filter { !minimizedPaneIds.contains($0.paneId) }
        let visibleRatioTotal = visiblePanes.reduce(0.0) { $0 + $1.ratio }
        let visibleDividerCount = adjacentVisibleDividerCount(
            layout: layout,
            minimizedPaneIds: minimizedPaneIds,
            collapsedPaneWidth: collapsedPaneWidth
        )
        let collapsedWidthTotal = CGFloat(layout.panes.count - visiblePanes.count) * collapsedPaneWidth
        let visibleWidthBudget = max(
            bounds.width - collapsedWidthTotal - (CGFloat(visibleDividerCount) * dividerThickness),
            0
        )

        var paneSegments: [PaneSegment] = []
        var dividerSegments: [DividerSegment] = []
        var currentX = bounds.minX
        var paneWidthsById: [UUID: CGFloat] = [:]

        for pane in layout.panes {
            let isMinimized = minimizedPaneIds.contains(pane.paneId)
            if isMinimized {
                paneWidthsById[pane.paneId] = collapsedPaneWidth
            } else if visibleRatioTotal > 0 {
                paneWidthsById[pane.paneId] = visibleWidthBudget * CGFloat(pane.ratio / visibleRatioTotal)
            } else {
                paneWidthsById[pane.paneId] = 0
            }
        }

        for index in layout.panes.indices {
            let pane = layout.panes[index]
            let isMinimized = minimizedPaneIds.contains(pane.paneId)
            let paneWidth = paneWidthsById[pane.paneId] ?? 0

            let paneFrame = CGRect(
                x: currentX,
                y: bounds.minY,
                width: paneWidth,
                height: bounds.height
            )
            paneSegments.append(
                PaneSegment(
                    paneId: pane.paneId,
                    frame: paneFrame,
                    isMinimized: isMinimized
                )
            )
            currentX += paneWidth

            guard index < layout.dividerIds.count else { continue }
            let nextPane = layout.panes[index + 1]
            let leftIsMinimized = minimizedPaneIds.contains(pane.paneId)
            let rightIsMinimized = minimizedPaneIds.contains(nextPane.paneId)
            if collapsedPaneWidth == 0 {
                guard !leftIsMinimized, !rightIsMinimized else { continue }
            }
            guard
                !(leftIsMinimized && rightIsMinimized)
            else {
                continue
            }

            let dividerFrame = CGRect(
                x: currentX,
                y: bounds.minY,
                width: dividerThickness,
                height: bounds.height
            )
            let visualRightPaneWidth = paneWidthsById[nextPane.paneId] ?? 0
            let resizeIntent = resizeIntent(
                layout: layout,
                dividerIndex: index,
                minimizedPaneIds: minimizedPaneIds
            )
            let resizeWidths = resizeWidths(
                intent: resizeIntent,
                paneWidthsById: paneWidthsById,
                visualLeftPaneWidth: paneFrame.width,
                visualRightPaneWidth: visualRightPaneWidth
            )
            dividerSegments.append(
                DividerSegment(
                    dividerId: layout.dividerIds[index],
                    leftPaneId: pane.paneId,
                    rightPaneId: nextPane.paneId,
                    frame: dividerFrame,
                    visualLeftPaneWidth: paneFrame.width,
                    visualRightPaneWidth: visualRightPaneWidth,
                    resizeIntent: resizeIntent,
                    resizeLeftPaneWidth: resizeWidths.left,
                    resizeRightPaneWidth: resizeWidths.right
                )
            )
            currentX += dividerThickness
        }

        return Self(
            paneSegments: paneSegments,
            dividerSegments: dividerSegments,
            allMinimized: allMinimized
        )
    }

    private static func adjacentVisibleDividerCount(
        layout: Layout,
        minimizedPaneIds: Set<UUID>,
        collapsedPaneWidth: CGFloat
    ) -> Int {
        layout.dividerIds.indices.reduce(into: 0) { count, index in
            let leftPaneId = layout.panes[index].paneId
            let rightPaneId = layout.panes[index + 1].paneId
            if collapsedPaneWidth == 0 {
                if !minimizedPaneIds.contains(leftPaneId), !minimizedPaneIds.contains(rightPaneId) {
                    count += 1
                }
                return
            }
            if !(minimizedPaneIds.contains(leftPaneId) && minimizedPaneIds.contains(rightPaneId)) {
                count += 1
            }
        }
    }

    private static func resizeIntent(
        layout: Layout,
        dividerIndex: Int,
        minimizedPaneIds: Set<UUID>
    ) -> DividerSegment.ResizeIntent {
        guard
            let pair = PaneResizeVisibilityResolver.pairAroundDivider(
                layout: layout,
                dividerIndex: dividerIndex,
                minimizedPaneIds: minimizedPaneIds
            )
        else { return .noResize }

        let leftPaneId = layout.panes[dividerIndex].paneId
        let rightPaneId = layout.panes[dividerIndex + 1].paneId
        if pair.leftPaneId == leftPaneId, pair.rightPaneId == rightPaneId {
            return .structural(splitId: layout.dividerIds[dividerIndex])
        }
        return .visiblePanePair(leftPaneId: pair.leftPaneId, rightPaneId: pair.rightPaneId)
    }

    private static func resizeWidths(
        intent: DividerSegment.ResizeIntent,
        paneWidthsById: [UUID: CGFloat],
        visualLeftPaneWidth: CGFloat,
        visualRightPaneWidth: CGFloat
    ) -> (left: CGFloat, right: CGFloat) {
        switch intent {
        case .structural:
            return (max(visualLeftPaneWidth, 0), max(visualRightPaneWidth, 0))
        case .visiblePanePair(let leftPaneId, let rightPaneId):
            return (max(paneWidthsById[leftPaneId] ?? 0, 0), max(paneWidthsById[rightPaneId] ?? 0, 0))
        case .noResize:
            return (0, 0)
        }
    }
}
