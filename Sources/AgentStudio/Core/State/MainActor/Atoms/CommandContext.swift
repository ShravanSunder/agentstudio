import Foundation

/// Workspace facts that may be required for contextual command presentation.
package enum CommandRequirement: Hashable, CaseIterable, Sendable {
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

/// Immutable command-policy projection of the current workspace.
package struct CommandContext: Equatable, Sendable {
    private static let contentRequirements: Set<CommandRequirement> = [
        .paneIsTerminal,
        .paneIsWebview,
        .paneIsBridge,
        .paneIsCodeViewer,
    ]

    package let activeTabId: UUID?
    package let focusedPaneId: UUID?
    package let focusedRepoId: UUID?
    package let focusedWorktreeId: UUID?
    package let focusedContentType: WorkspaceFocusedPane.ContentType?
    package let satisfiedRequirements: Set<CommandRequirement>

    package init(
        activeTabId: UUID? = nil,
        focusedPaneId: UUID? = nil,
        focusedRepoId: UUID? = nil,
        focusedWorktreeId: UUID? = nil,
        focusedContentType: WorkspaceFocusedPane.ContentType? = nil,
        satisfiedRequirements: Set<CommandRequirement>
    ) {
        var normalizedRequirements = satisfiedRequirements.subtracting(Self.contentRequirements)
        if let focusedContentType {
            switch focusedContentType {
            case .terminal:
                normalizedRequirements.insert(.paneIsTerminal)
            case .webview:
                normalizedRequirements.insert(.paneIsWebview)
            case .bridge:
                normalizedRequirements.insert(.paneIsBridge)
            case .codeViewer:
                normalizedRequirements.insert(.paneIsCodeViewer)
            case .unsupported:
                break
            }
        }

        self.activeTabId = activeTabId
        self.focusedPaneId = focusedPaneId
        self.focusedRepoId = focusedRepoId
        self.focusedWorktreeId = focusedWorktreeId
        self.focusedContentType = focusedContentType
        self.satisfiedRequirements = normalizedRequirements
    }

    package static let empty = Self(satisfiedRequirements: [])
}
