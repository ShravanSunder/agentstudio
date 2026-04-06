import Foundation
import Observation
import os.log

private let workspaceFocusLogger = Logger(subsystem: "com.agentstudio", category: "WorkspaceFocusContext")

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

/// App-wide workspace focus snapshot shared by command visibility and other UI readers.
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

    let activeTabId: UUID?
    let activePaneId: UUID?
    let activeRepoId: UUID?
    let activeWorktreeId: UUID?
    let paneContentType: ContentType
    let satisfiedRequirements: Set<FocusRequirement>

    init(
        activeTabId: UUID? = nil,
        activePaneId: UUID? = nil,
        activeRepoId: UUID? = nil,
        activeWorktreeId: UUID? = nil,
        paneContentType: ContentType,
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

@MainActor
@Observable
final class WorkspaceFocusContextAtom {
    private var observedStore: WorkspaceStore?
    private var didLogMissingObservedStore = false

    func startObserving(store: WorkspaceStore) {
        observedStore = store
        didLogMissingObservedStore = false
    }

    var currentFocus: WorkspaceFocus {
        guard let observedStore else {
            if !didLogMissingObservedStore {
                workspaceFocusLogger.error("WorkspaceFocusContextAtom accessed without an observed WorkspaceStore")
                didLogMissingObservedStore = true
            }
            return .empty
        }

        return WorkspaceFocusProjector.project(store: observedStore)
    }
}

@MainActor
enum WorkspaceFocusProjector {
    static func project(store: WorkspaceStore) -> WorkspaceFocus {
        var satisfiedRequirements: Set<FocusRequirement> = []

        guard
            let activeTabId = store.activeTabId,
            let tab = store.tab(activeTabId)
        else {
            return .empty
        }

        satisfiedRequirements.insert(.hasActiveTab)

        if store.tabs.count > 1 {
            satisfiedRequirements.insert(.hasMultipleTabs)
        }

        if tab.activePaneIds.count > 1 {
            satisfiedRequirements.insert(.hasMultiplePanes)
        }

        if tab.arrangements.count > 1 {
            satisfiedRequirements.insert(.hasArrangements)
        }

        guard let activePaneId = tab.activePaneId else {
            return WorkspaceFocus(
                activeTabId: activeTabId,
                paneContentType: .noActivePane,
                satisfiedRequirements: satisfiedRequirements
            )
        }

        guard let pane = store.pane(activePaneId) else {
            return WorkspaceFocus(
                activeTabId: activeTabId,
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
            activeTabId: activeTabId,
            activePaneId: activePaneId,
            activeRepoId: pane.repoId,
            activeWorktreeId: pane.worktreeId,
            paneContentType: paneContentType,
            satisfiedRequirements: satisfiedRequirements
        )
    }
}

extension CommandSpec {
    func isVisible(in focus: WorkspaceFocus) -> Bool {
        visibleWhen.isSubset(of: focus.satisfiedRequirements)
    }
}
