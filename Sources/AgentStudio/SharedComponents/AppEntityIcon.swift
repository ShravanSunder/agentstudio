import AppKit
import SwiftUI

enum AppEntityIcon: Equatable {
    enum Symbol: Equatable {
        case system(SystemSymbol)
        case octicon(OcticonSymbol)
    }

    enum SystemSymbol: String, Equatable {
        case building2 = "building.2"
        case rectangleSplit2x1 = "rectangle.split.2x1"
        case squareStackFill = "square.stack.fill"
        case tray
    }

    enum OcticonSymbol: String, Equatable {
        case gitWorktree = "octicon-git-worktree"
        case repo = "octicon-repo"
        case starFill = "octicon-star-fill"
    }

    case repo
    case coloredRepo(colorHex: String)
    case checkout(colorHex: String, isMain: Bool)
    case pane
    case paneGroup
    case tab
    case tabGroup
    case workspace
    case otherSources

    var symbol: Symbol {
        switch self {
        case .repo, .coloredRepo:
            return .octicon(.repo)
        case .checkout(_, let isMain):
            return .octicon(isMain ? .starFill : .gitWorktree)
        case .pane, .paneGroup:
            return .system(.rectangleSplit2x1)
        case .tab, .tabGroup:
            return .system(.squareStackFill)
        case .workspace:
            return .system(.building2)
        case .otherSources:
            return .system(.tray)
        }
    }

    var symbolName: String {
        switch symbol {
        case .system(let systemSymbol):
            return systemSymbol.rawValue
        case .octicon(let octiconSymbol):
            return octiconSymbol.rawValue
        }
    }

    @ViewBuilder
    func swiftUIImage(size: CGFloat) -> some View {
        switch self {
        case .pane, .paneGroup, .tab, .tabGroup, .workspace, .otherSources:
            Image(systemName: symbolName)
                .font(.system(size: size, weight: .medium))
                .foregroundStyle(foregroundStyle)
        case .repo, .coloredRepo, .checkout:
            OcticonImage(name: symbolName, size: size)
                .foregroundStyle(foregroundStyle)
                .rotationEffect(.degrees(rotationDegrees))
        }
    }

    var foregroundStyle: Color {
        switch self {
        case .coloredRepo(let colorHex), .checkout(let colorHex, _):
            return Color(nsColor: NSColor(hex: colorHex) ?? .controlAccentColor)
        case .repo, .pane, .paneGroup, .tab, .tabGroup, .workspace, .otherSources:
            return .secondary
        }
    }

    var rotationDegrees: Double {
        switch self {
        case .checkout(_, let isMain):
            return isMain ? 0 : 180
        case .repo, .coloredRepo, .pane, .paneGroup, .tab, .tabGroup, .workspace, .otherSources:
            return 0
        }
    }
}
