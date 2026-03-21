import CoreGraphics
import Foundation

enum TerminalPaneGeometryResolver {
    static func resolveFrames(
        for layout: Layout,
        in availableRect: CGRect,
        dividerThickness: CGFloat,
        minimizedPaneIds: Set<UUID> = []
    ) -> [UUID: CGRect] {
        guard let root = layout.root else { return [:] }
        let splitRenderInfo = SplitRenderInfo.compute(layout: layout, minimizedPaneIds: minimizedPaneIds)
        var result: [UUID: CGRect] = [:]
        resolve(
            node: root,
            in: availableRect,
            dividerThickness: dividerThickness,
            splitRenderInfo: splitRenderInfo,
            into: &result
        )
        return result
    }

    private static func resolve(
        node: Layout.Node,
        in rect: CGRect,
        dividerThickness: CGFloat,
        splitRenderInfo: SplitRenderInfo,
        into result: inout [UUID: CGRect]
    ) {
        switch node {
        case .leaf(let paneId):
            result[paneId] = normalizedPaneFrame(from: rect)

        case .split(let split):
            let ratio = splitRenderInfo.splitInfo[split.id]?.adjustedRatio ?? split.ratio
            switch split.direction {
            case .horizontal:
                let totalWidth = max(rect.width - dividerThickness, 0)
                let leftWidth = totalWidth * ratio
                let rightWidth = totalWidth - leftWidth

                let leftRect = CGRect(
                    x: rect.minX,
                    y: rect.minY,
                    width: leftWidth,
                    height: rect.height
                )
                let rightRect = CGRect(
                    x: rect.minX + leftWidth + dividerThickness,
                    y: rect.minY,
                    width: rightWidth,
                    height: rect.height
                )

                resolve(
                    node: split.left,
                    in: leftRect,
                    dividerThickness: dividerThickness,
                    splitRenderInfo: splitRenderInfo,
                    into: &result
                )
                resolve(
                    node: split.right,
                    in: rightRect,
                    dividerThickness: dividerThickness,
                    splitRenderInfo: splitRenderInfo,
                    into: &result
                )

            case .vertical:
                let totalHeight = max(rect.height - dividerThickness, 0)
                let topHeight = totalHeight * ratio
                let bottomHeight = totalHeight - topHeight

                let topRect = CGRect(
                    x: rect.minX,
                    y: rect.minY,
                    width: rect.width,
                    height: topHeight
                )
                let bottomRect = CGRect(
                    x: rect.minX,
                    y: rect.minY + topHeight + dividerThickness,
                    width: rect.width,
                    height: bottomHeight
                )

                resolve(
                    node: split.left,
                    in: topRect,
                    dividerThickness: dividerThickness,
                    splitRenderInfo: splitRenderInfo,
                    into: &result
                )
                resolve(
                    node: split.right,
                    in: bottomRect,
                    dividerThickness: dividerThickness,
                    splitRenderInfo: splitRenderInfo,
                    into: &result
                )
            }
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
