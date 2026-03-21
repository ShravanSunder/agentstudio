import CoreGraphics
import Foundation

enum TerminalPaneGeometryResolver {
    static func resolveFrames(
        for layout: Layout,
        in availableRect: CGRect,
        dividerThickness: CGFloat
    ) throws -> [UUID: CGRect] {
        guard let root = layout.root else { return [:] }
        var result: [UUID: CGRect] = [:]
        resolve(node: root, in: availableRect, dividerThickness: dividerThickness, into: &result)
        return result
    }

    private static func resolve(
        node: Layout.Node,
        in rect: CGRect,
        dividerThickness: CGFloat,
        into result: inout [UUID: CGRect]
    ) {
        switch node {
        case .leaf(let paneId):
            result[paneId] = rect

        case .split(let split):
            switch split.direction {
            case .horizontal:
                let totalWidth = max(rect.width - dividerThickness, 0)
                let leftWidth = totalWidth * split.ratio
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

                resolve(node: split.left, in: leftRect, dividerThickness: dividerThickness, into: &result)
                resolve(node: split.right, in: rightRect, dividerThickness: dividerThickness, into: &result)

            case .vertical:
                let totalHeight = max(rect.height - dividerThickness, 0)
                let topHeight = totalHeight * split.ratio
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

                resolve(node: split.left, in: topRect, dividerThickness: dividerThickness, into: &result)
                resolve(node: split.right, in: bottomRect, dividerThickness: dividerThickness, into: &result)
            }
        }
    }
}
