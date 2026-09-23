import Foundation

/// Content families a drawer child could be created with.
package enum DrawerChildContentKind: Equatable, Hashable, Sendable, CaseIterable {
    case terminal
    case browser
    case bridge
    case codeViewer
    case unsupported

    package init(_ content: PaneContent) {
        switch content {
        case .terminal: self = .terminal
        case .webview: self = .browser
        case .bridgePanel: self = .bridge
        case .codeViewer: self = .codeViewer
        case .unsupported: self = .unsupported
        }
    }
}

/// Drawer children are supporting terminals or browsers only. Bridge and
/// code-viewer content never enters a drawer, whatever path asks for it.
///
/// Applied where drawer children are admitted, not in the pane graph atom:
/// existing content is neither migrated nor deleted by this rule.
package enum DrawerChildContentPolicy {
    package static func admits(_ kind: DrawerChildContentKind) -> Bool {
        switch kind {
        case .terminal, .browser:
            return true
        case .bridge, .codeViewer, .unsupported:
            return false
        }
    }

    package static func admits(_ content: PaneContent) -> Bool {
        admits(DrawerChildContentKind(content))
    }
}
