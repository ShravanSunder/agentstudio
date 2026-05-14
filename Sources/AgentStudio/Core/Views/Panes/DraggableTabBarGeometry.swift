import CoreGraphics
import Foundation

enum DraggableTabBarGeometry {
    static func tabId(at point: CGPoint, tabFrames: [UUID: CGRect]) -> UUID? {
        let containingTabs =
            tabFrames
            .filter { _, frame in frame.contains(point) }
            .sorted { lhs, rhs in
                if lhs.value.minX != rhs.value.minX {
                    return lhs.value.minX < rhs.value.minX
                }
                if lhs.value.minY != rhs.value.minY {
                    return lhs.value.minY < rhs.value.minY
                }
                return lhs.key.uuidString < rhs.key.uuidString
            }

        return containingTabs.first?.key
    }
}
