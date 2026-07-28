import Foundation

/// Workspace state requirements that determine whether a command should be visible.
package enum FocusRequirement: Hashable, CaseIterable, Sendable {
    case hasActiveTab
    case hasActivePane
    case hasMultiplePanes
    case hasDrawer
    case hasDrawerPanes
    case hasEmptyDrawerFocus
    case hasFocusedDrawerPane
    case hasMultipleTabs
    case hasArrangements
    case paneIsTerminal
    case paneIsWebview
    case paneIsBridge
    case paneIsCodeViewer
    case supportsTerminalZoom
    case hasActiveTerminalZoom
}

/// App-wide workspace pane focus snapshot shared by command visibility and other UI readers.
package struct WorkspacePaneFocus: Equatable, Sendable {
    package enum ContentType: Equatable, Sendable {
        case terminal
        case webview
        case bridge
        case codeViewer
        case unsupported
        case noActivePane

        fileprivate var visibilityRequirement: FocusRequirement? {
            switch self {
            case .terminal:
                return .paneIsTerminal
            case .webview:
                return .paneIsWebview
            case .bridge:
                return .paneIsBridge
            case .codeViewer:
                return .paneIsCodeViewer
            case .unsupported, .noActivePane:
                return nil
            }
        }
    }

    package enum DrawerFocusState: Equatable, Sendable {
        case inactive
        case emptyDrawer(parentPaneId: UUID)
        case drawerPane(parentPaneId: UUID, paneId: UUID)
    }

    private static let contentRequirements: Set<FocusRequirement> = [
        .paneIsTerminal,
        .paneIsWebview,
        .paneIsBridge,
        .paneIsCodeViewer,
    ]

    package let activeTabId: UUID?
    package let activePaneId: UUID?
    package let activeRepoId: UUID?
    package let activeWorktreeId: UUID?
    package let paneContentType: ContentType
    package let drawerFocusState: DrawerFocusState
    package let satisfiedRequirements: Set<FocusRequirement>

    package init(
        activeTabId: UUID? = nil,
        activePaneId: UUID? = nil,
        activeRepoId: UUID? = nil,
        activeWorktreeId: UUID? = nil,
        paneContentType: ContentType,
        drawerFocusState: DrawerFocusState = .inactive,
        satisfiedRequirements: Set<FocusRequirement>
    ) {
        var normalizedRequirements = satisfiedRequirements.subtracting(Self.contentRequirements)
        if let contentRequirement = paneContentType.visibilityRequirement {
            normalizedRequirements.insert(contentRequirement)
        }

        self.activeTabId = activeTabId
        self.activePaneId = activePaneId
        self.activeRepoId = activeRepoId
        self.activeWorktreeId = activeWorktreeId
        self.paneContentType = paneContentType
        self.drawerFocusState = drawerFocusState
        self.satisfiedRequirements = normalizedRequirements
    }

    package static let empty = Self(paneContentType: .noActivePane, satisfiedRequirements: [])

    package var label: String? {
        switch paneContentType {
        case .terminal:
            return "Terminal"
        case .webview:
            return "Webview"
        case .bridge:
            return "Bridge"
        case .codeViewer:
            return "Code Viewer"
        case .unsupported:
            return "Unsupported"
        case .noActivePane:
            return nil
        }
    }

    package var icon: String? {
        switch paneContentType {
        case .terminal:
            return "terminal"
        case .webview:
            return "globe"
        case .bridge:
            return "rectangle.split.2x1"
        case .codeViewer:
            return "doc.text"
        case .unsupported:
            return "questionmark.square"
        case .noActivePane:
            return nil
        }
    }
}

extension AppCommandSpec {
    package func isVisible(in focus: WorkspacePaneFocus) -> Bool {
        visibleWhen.isSubset(of: focus.satisfiedRequirements)
    }
}
