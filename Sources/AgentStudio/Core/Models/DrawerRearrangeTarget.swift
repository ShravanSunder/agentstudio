import Foundation

enum DrawerRowPlacement: Equatable, Codable, Hashable {
    case top
    case bottom
}

enum DrawerRearrangeTarget: Equatable, Codable, Hashable {
    case paneSplit(paneId: UUID, side: DropZoneSide)
    case rowSlot(row: DrawerRowPlacement, insertionIndex: Int)
    case createSecondRow(position: DrawerRowPlacement)
}
