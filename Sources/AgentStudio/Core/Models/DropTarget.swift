import Foundation

package enum RowID: Hashable, Sendable {
    case main
    case drawerTop
    case drawerBottom
}

package enum DropZoneSide: String, Codable, Hashable, Sendable, CaseIterable {
    case left
    case right
}

package enum NewRowPosition: Hashable, Sendable {
    case top
    case bottom
}

package enum DropTarget: Hashable, Sendable {
    case paneSplit(paneId: UUID, side: DropZoneSide)
    case paneSlot(row: RowID, index: Int)
    case paneNewRow(position: NewRowPosition)
}
