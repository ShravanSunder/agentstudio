import Foundation

enum DrawerRowPlacement: Equatable, Codable, Hashable {
    case top
    case bottom
}

enum DrawerRearrangeTarget: Equatable, Codable, Hashable {
    case rowSlot(row: DrawerRowPlacement, insertionIndex: Int)
    case createSecondRow(position: DrawerRowPlacement)
}
