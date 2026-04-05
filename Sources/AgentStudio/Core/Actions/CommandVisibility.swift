import Foundation
import os.log

private let commandVisibilityLogger = Logger(subsystem: "com.agentstudio", category: "CommandVisibility")

/// Workspace state requirements that determine whether a command should be visible.
enum FocusRequirement: Hashable, CaseIterable, Sendable {
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

/// User-facing pane context for status-strip and visibility decisions.
struct WorkspaceFocus: Equatable, Sendable {
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

    private static let contentRequirements: Set<FocusRequirement> = [
        .paneIsTerminal,
        .paneIsWebview,
        .paneIsBridge,
        .paneIsCodeViewer,
    ]

    let paneContentType: ContentType
    let satisfiedRequirements: Set<FocusRequirement>

    init(paneContentType: ContentType, satisfiedRequirements: Set<FocusRequirement>) {
        var normalizedRequirements = satisfiedRequirements.subtracting(Self.contentRequirements)
        if let contentRequirement = paneContentType.visibilityRequirement {
            normalizedRequirements.insert(contentRequirement)
        }

        self.paneContentType = paneContentType
        self.satisfiedRequirements = normalizedRequirements
    }

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

extension CommandDefinition {
    func isVisible(in focus: WorkspaceFocus) -> Bool {
        visibleWhen.isSubset(of: focus.satisfiedRequirements)
    }
}

@MainActor
enum WorkspaceFocusComputer {
    static func compute(store: WorkspaceStore) -> WorkspaceFocus {
        var satisfiedRequirements: Set<FocusRequirement> = []

        guard
            let activeTabId = store.activeTabId,
            let tab = store.tab(activeTabId)
        else {
            return WorkspaceFocus(
                paneContentType: .noActivePane,
                satisfiedRequirements: satisfiedRequirements
            )
        }

        satisfiedRequirements.insert(.hasActiveTab)

        if store.tabs.count > 1 {
            satisfiedRequirements.insert(.hasMultipleTabs)
        }

        if tab.activePaneIds.count > 1 {
            satisfiedRequirements.insert(.hasMultiplePanes)
        }

        // The default arrangement is always present, so > 1 means the tab has at least one saved custom arrangement.
        if tab.arrangements.count > 1 {
            satisfiedRequirements.insert(.hasArrangements)
        }

        guard let activePaneId = tab.activePaneId else {
            return WorkspaceFocus(
                paneContentType: .noActivePane,
                satisfiedRequirements: satisfiedRequirements
            )
        }

        guard let pane = store.pane(activePaneId) else {
            commandVisibilityLogger.warning(
                "Workspace focus dropped invalid activePaneId=\(activePaneId.uuidString, privacy: .public) for tab=\(tab.id.uuidString, privacy: .public)"
            )
            return WorkspaceFocus(
                paneContentType: .noActivePane,
                satisfiedRequirements: satisfiedRequirements
            )
        }

        satisfiedRequirements.insert(.hasActivePane)

        if let drawer = pane.drawer {
            satisfiedRequirements.insert(.hasDrawer)
            if !drawer.paneIds.isEmpty {
                satisfiedRequirements.insert(.hasDrawerPanes)
            }
        }

        let paneContentType: WorkspaceFocus.ContentType
        switch pane.content {
        case .terminal:
            paneContentType = .terminal
        case .webview:
            paneContentType = .webview
        case .bridgePanel:
            paneContentType = .bridge
        case .codeViewer:
            paneContentType = .codeViewer
        case .unsupported:
            paneContentType = .unsupported
        }

        return WorkspaceFocus(
            paneContentType: paneContentType,
            satisfiedRequirements: satisfiedRequirements
        )
    }
}
