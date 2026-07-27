import Foundation

package enum DrawerRowPlacement: Equatable, Codable, Hashable, Sendable {
    case top
    case bottom
}

package enum DrawerRearrangeTarget: Equatable, Codable, Hashable, Sendable {
    case paneSplit(paneId: UUID, side: DropZoneSide)
    case rowSlot(row: DrawerRowPlacement, insertionIndex: Int)
    case createSecondRow(position: DrawerRowPlacement)
}
