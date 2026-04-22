import Foundation

/// Workspace state requirements that determine whether a command should be visible.
enum CommandRequirement: Hashable, CaseIterable, Sendable {
    case hasActiveTab
    case hasActivePane
    case hasMultiplePanes
    case hasDrawer
    case hasDrawerPanes
    case hasMultipleTabs
    case hasArrangements
    case paneIsTerminal
    case paneIsWebview
    case paneIsBridge
    case paneIsCodeViewer
}

/// App-wide workspace focus snapshot shared by command visibility and other UI readers.
struct CommandContext: Equatable, Sendable {
    enum ContentType: Equatable, Sendable {
        case terminal
        case webview
        case bridge
        case codeViewer
        case unsupported
        case noActivePane

        fileprivate var visibilityRequirement: CommandRequirement? {
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

    private static let contentRequirements: Set<CommandRequirement> = [
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
    let satisfiedRequirements: Set<CommandRequirement>

    init(
        activeTabId: UUID? = nil,
        activePaneId: UUID? = nil,
        activeRepoId: UUID? = nil,
        activeWorktreeId: UUID? = nil,
        paneContentType: ContentType,
        satisfiedRequirements: Set<CommandRequirement>
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

extension CommandSpec {
    func isVisible(in focus: CommandContext) -> Bool {
        visibleWhen.isSubset(of: focus.satisfiedRequirements)
    }
}
