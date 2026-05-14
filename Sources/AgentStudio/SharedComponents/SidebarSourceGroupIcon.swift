import AppKit
import SwiftUI

enum SidebarSourceGroupIcon: Equatable {
    enum SymbolKind: Equatable {
        case system
        case octicon
    }

    case repo
    case coloredRepo(colorHex: String)
    case checkout(colorHex: String, isMain: Bool)
    case pane
    case tab
    case workspace
    case otherSources

    var symbolName: String {
        switch self {
        case .repo, .coloredRepo:
            return "octicon-repo"
        case .checkout(_, let isMain):
            return isMain ? "octicon-star-fill" : "octicon-git-worktree"
        case .pane:
            return "rectangle.inset.filled"
        case .tab:
            return "macwindow"
        case .workspace:
            return "building.2"
        case .otherSources:
            return "tray"
        }
    }

    var symbolKind: SymbolKind {
        switch self {
        case .repo, .coloredRepo, .checkout:
            return .octicon
        case .pane, .tab, .workspace, .otherSources:
            return .system
        }
    }

    var foregroundStyle: Color {
        switch self {
        case .coloredRepo(let colorHex), .checkout(let colorHex, _):
            return Color(nsColor: NSColor(hex: colorHex) ?? .controlAccentColor)
        case .repo, .pane, .tab, .workspace, .otherSources:
            return .secondary
        }
    }

    var rotationDegrees: Double {
        switch self {
        case .checkout(_, let isMain):
            return isMain ? 0 : 180
        case .repo, .coloredRepo, .pane, .tab, .workspace, .otherSources:
            return 0
        }
    }
}
