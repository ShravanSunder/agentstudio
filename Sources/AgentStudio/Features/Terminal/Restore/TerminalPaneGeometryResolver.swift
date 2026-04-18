import CoreGraphics
import Foundation

enum TerminalPaneGeometryResolver {
    static func resolveFrames(
        for layout: Layout,
        in availableRect: CGRect,
        dividerThickness: CGFloat,
        minimizedPaneIds: Set<UUID> = [],
        collapsedPaneWidth: CGFloat
    ) -> [UUID: CGRect] {
        let metrics = FlatTabStripMetrics.compute(
            layout: layout,
            in: availableRect,
            dividerThickness: dividerThickness,
            minimizedPaneIds: minimizedPaneIds,
            collapsedPaneWidth: collapsedPaneWidth
        )
        return metrics.paneSegments.reduce(into: [UUID: CGRect]()) { result, segment in
            result[segment.paneId] = normalizedPaneFrame(from: segment.frame)
        }
    }

    static func resolveFrames(
        for layout: DrawerGridLayout,
        in availableRect: CGRect,
        dividerThickness: CGFloat,
        minimizedPaneIds: Set<UUID> = [],
        collapsedPaneWidth: CGFloat
    ) -> [UUID: CGRect] {
        guard let bottomRow = layout.bottomRow else {
            return resolveFrames(
                for: layout.topRow,
                in: availableRect,
                dividerThickness: dividerThickness,
                minimizedPaneIds: minimizedPaneIds,
                collapsedPaneWidth: collapsedPaneWidth
            )
        }

        let clampedRatio = min(0.9, max(0.1, layout.rowSplitRatio))
        let contentHeight = max(availableRect.height - dividerThickness, 0)
        let topHeight = contentHeight * clampedRatio
        let bottomHeight = max(contentHeight - topHeight, 0)

        let bottomRect = CGRect(
            x: availableRect.minX,
            y: availableRect.minY,
            width: availableRect.width,
            height: bottomHeight
        )
        let topRect = CGRect(
            x: availableRect.minX,
            y: bottomRect.maxY + dividerThickness,
            width: availableRect.width,
            height: topHeight
        )

        let topPaneIds = Set(layout.topRow.paneIds)
        let bottomPaneIds = Set(bottomRow.paneIds)

        var frames = resolveFrames(
            for: layout.topRow,
            in: topRect,
            dividerThickness: dividerThickness,
            minimizedPaneIds: minimizedPaneIds.intersection(topPaneIds),
            collapsedPaneWidth: collapsedPaneWidth
        )
        let bottomFrames = resolveFrames(
            for: bottomRow,
            in: bottomRect,
            dividerThickness: dividerThickness,
            minimizedPaneIds: minimizedPaneIds.intersection(bottomPaneIds),
            collapsedPaneWidth: collapsedPaneWidth
        )
        frames.merge(bottomFrames) { _, latest in latest }
        return frames
    }

    private static func normalizedPaneFrame(from rawRect: CGRect) -> CGRect {
        let paneGap = AppStyles.General.Layout.paneGap
        return CGRect(
            x: rawRect.minX + paneGap,
            y: rawRect.minY + paneGap,
            width: max(rawRect.width - (paneGap * 2), 1),
            height: max(rawRect.height - (paneGap * 2), 1)
        )
    }
}
