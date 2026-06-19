import Foundation

/// Workspace state requirements that determine whether a command should be visible.
enum FocusRequirement: Hashable, CaseIterable, Sendable {
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
}

/// App-wide workspace pane focus snapshot shared by command visibility and other UI readers.
struct WorkspacePaneFocus: Equatable, Sendable {
    enum ContentType: Equatable, Sendable {
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

    enum DrawerFocusState: Equatable, Sendable {
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

    let activeTabId: UUID?
    let activePaneId: UUID?
    let activeRepoId: UUID?
    let activeWorktreeId: UUID?
    let paneContentType: ContentType
    let drawerFocusState: DrawerFocusState
    let satisfiedRequirements: Set<FocusRequirement>

    init(
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

    static let empty = Self(paneContentType: .noActivePane, satisfiedRequirements: [])

    var label: String? {
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

    var icon: String? {
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
    func isVisible(in focus: WorkspacePaneFocus) -> Bool {
        visibleWhen.isSubset(of: focus.satisfiedRequirements)
    }
}
