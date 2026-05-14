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

        // FLIPPED COORDINATE SYSTEM — please read.
        //
        // SwiftUI uses a flipped coord system: origin is at the
        // TOP-LEFT, the y-axis grows DOWNWARD on screen. So:
        //
        //     y = availableRect.minY  ←─ TOP    of the panel
        //     y = availableRect.maxY  ←─ BOTTOM of the panel
        //
        // (AppKit's NSView default is the opposite — origin at the
        //  bottom-left, y grows up — but anything Hosting-Controlled
        //  by SwiftUI runs flipped, and that includes the drawer.)
        //
        // The drawer's "top row" is what the user sees at the top
        // of the panel. In flipped coords that means it must be
        // anchored at the SMALLER y (`minY`). The "bottom row" sits
        // below it at the LARGER y.
        //
        // Earlier this resolver swapped the assignments — the rect
        // labelled `bottomRect` was placed at `availableRect.minY`
        // (visually the top) and `topRect` was anchored below it.
        // Net effect: top-row panes painted at the bottom of the
        // panel, bottom-row at the top. Restored telemetry, drag-
        // target reads, and the user's mental model all silently
        // disagreed.
        let topRect = CGRect(
            x: availableRect.minX,
            y: availableRect.minY,
            width: availableRect.width,
            height: topHeight
        )
        let bottomRect = CGRect(
            x: availableRect.minX,
            y: topRect.maxY + dividerThickness,
            width: availableRect.width,
            height: bottomHeight
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
