import Foundation

enum ActiveKeyboardSurface: Equatable, Sendable {
    case commandBar(scope: CommandBarScope)
    case transient(TransientKeyboardSurfaceKind)
    case stable(KeyboardOwner)
}
