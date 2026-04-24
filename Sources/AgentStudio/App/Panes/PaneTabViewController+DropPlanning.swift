import Foundation

@MainActor
extension PaneTabViewController {
    nonisolated static func splitDirection(for zone: DropZoneSide) -> SplitNewDirection {
        switch zone {
        case .left:
            return .left
        case .right:
            return .right
        }
    }
}
