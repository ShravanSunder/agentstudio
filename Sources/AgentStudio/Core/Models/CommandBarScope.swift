import Foundation

/// Scope of the command bar, determined by prefix character or default owner.
enum CommandBarScope: Equatable, Sendable {
    case everything
    case commands
    case panes
    case repos
    case inbox
}
