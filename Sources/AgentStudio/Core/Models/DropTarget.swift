import Foundation

enum RowID: Hashable, Sendable {
    case main
    case drawerTop
    case drawerBottom
}

enum DropZoneSide: String, Codable, Hashable, Sendable, CaseIterable {
    case left
    case right
}

enum NewRowPosition: Hashable, Sendable {
    case top
    case bottom
}

enum DropTarget: Hashable, Sendable {
    case paneSplit(paneId: UUID, side: DropZoneSide)
    case paneSlot(row: RowID, index: Int)
    case paneNewRow(position: NewRowPosition)
}
