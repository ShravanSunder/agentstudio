import CoreGraphics
import Foundation

enum TerminalPaneGeometryResolver {
    private static let collapsedPaneWidth: CGFloat = 30

    static func resolveFrames(
        for layout: Layout,
        in availableRect: CGRect,
        dividerThickness: CGFloat,
        minimizedPaneIds: Set<UUID> = []
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

    private static func normalizedPaneFrame(from rawRect: CGRect) -> CGRect {
        let paneGap = AppStyle.paneGap
        return CGRect(
            x: rawRect.minX + paneGap,
            y: rawRect.minY + paneGap,
            width: max(rawRect.width - (paneGap * 2), 1),
            height: max(rawRect.height - (paneGap * 2), 1)
        )
    }
}
