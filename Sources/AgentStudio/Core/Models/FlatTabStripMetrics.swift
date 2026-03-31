import CoreGraphics
import Foundation

struct FlatTabStripMetrics {
    struct PaneSegment: Hashable {
        let paneId: UUID
        let frame: CGRect
        let isMinimized: Bool
    }

    struct DividerSegment: Hashable {
        let dividerId: UUID
        let leftPaneId: UUID
        let rightPaneId: UUID
        let frame: CGRect
        let leftPaneWidth: CGFloat
        let rightPaneWidth: CGFloat
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
            minimizedPaneIds: minimizedPaneIds
        )
        let collapsedWidthTotal = CGFloat(layout.panes.count - visiblePanes.count) * collapsedPaneWidth
        let visibleWidthBudget = max(
            bounds.width - collapsedWidthTotal - (CGFloat(visibleDividerCount) * dividerThickness),
            0
        )

        var paneSegments: [PaneSegment] = []
        var dividerSegments: [DividerSegment] = []
        var currentX = bounds.minX

        for index in layout.panes.indices {
            let pane = layout.panes[index]
            let isMinimized = minimizedPaneIds.contains(pane.paneId)
            let paneWidth: CGFloat
            if isMinimized {
                paneWidth = collapsedPaneWidth
            } else if visibleRatioTotal > 0 {
                paneWidth = visibleWidthBudget * CGFloat(pane.ratio / visibleRatioTotal)
            } else {
                paneWidth = 0
            }

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
            guard
                !minimizedPaneIds.contains(pane.paneId),
                !minimizedPaneIds.contains(nextPane.paneId)
            else {
                continue
            }

            let dividerFrame = CGRect(
                x: currentX,
                y: bounds.minY,
                width: dividerThickness,
                height: bounds.height
            )
            dividerSegments.append(
                DividerSegment(
                    dividerId: layout.dividerIds[index],
                    leftPaneId: pane.paneId,
                    rightPaneId: nextPane.paneId,
                    frame: dividerFrame,
                    leftPaneWidth: paneFrame.width,
                    rightPaneWidth: max(
                        visibleRatioTotal > 0
                            ? visibleWidthBudget * CGFloat(nextPane.ratio / visibleRatioTotal)
                            : 0,
                        0
                    )
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
        minimizedPaneIds: Set<UUID>
    ) -> Int {
        layout.dividerIds.indices.reduce(into: 0) { count, index in
            let leftPaneId = layout.panes[index].paneId
            let rightPaneId = layout.panes[index + 1].paneId
            if !minimizedPaneIds.contains(leftPaneId), !minimizedPaneIds.contains(rightPaneId) {
                count += 1
            }
        }
    }
}
