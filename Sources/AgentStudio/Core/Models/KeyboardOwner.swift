import Foundation

/// Derived value naming who currently owns keyboard interpretation.
/// Never stored, never manually set.
enum KeyboardOwner: Equatable, Sendable {
    case otherWindow
    case managementLayer
    case sidebar(SidebarSurface)
    case mainWindowChain
}
