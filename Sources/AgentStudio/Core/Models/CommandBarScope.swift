import Foundation

/// Scope of the command bar, determined by prefix character or default owner.
package enum CommandBarScope: Equatable, Sendable {
    case everything
    case quickOpen
    case commands
    case panes
    case repos
    case inbox
}
