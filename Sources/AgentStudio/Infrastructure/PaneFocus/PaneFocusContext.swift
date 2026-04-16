import Foundation

enum PaneManagementFocusScope: Sendable, Equatable {
    case mainRow
    case drawer(parentPaneId: UUID)
}

struct PaneFocusContext: Sendable, Equatable {
    enum PaneKind: Sendable, Equatable {
        case terminal
        case webview
        case bridge
        case codeViewer
        case unknown
    }

    enum ManagementModeState: Sendable, Equatable {
        case inactive
        case active(scope: PaneManagementFocusScope)
    }

    enum WindowState: Sendable, Equatable {
        case background
        case focused
        case key
    }

    enum MountedContentState: Sendable, Equatable {
        case unmounted
        case nonTerminal(acceptsFirstResponder: Bool)
        case terminal(surfaceId: UUID?)
    }

    struct ActiveDrawerContext: Sendable, Equatable {
        let parentPaneId: UUID
        let paneId: UUID?
    }

    let activeTabId: UUID?
    let activePaneId: UUID?
    let activeDrawer: ActiveDrawerContext?
    let targetPaneId: UUID?
    let targetTabId: UUID?
    let targetPaneKind: PaneKind
    let targetPaneIsAlreadyActive: Bool
    let targetMountedContent: MountedContentState
    let managementMode: ManagementModeState
    let windowState: WindowState

    init(
        activeTabId: UUID?,
        activePaneId: UUID?,
        activeDrawer: ActiveDrawerContext?,
        targetPaneId: UUID?,
        targetTabId: UUID?,
        targetPaneKind: PaneKind,
        targetPaneIsAlreadyActive: Bool,
        targetMountedContent: MountedContentState,
        managementMode: ManagementModeState,
        windowState: WindowState
    ) {
        assert(targetPaneId == nil || targetTabId != nil || activeTabId == nil || targetPaneIsAlreadyActive)
        self.activeTabId = activeTabId
        self.activePaneId = activePaneId
        self.activeDrawer = activeDrawer
        self.targetPaneId = targetPaneId
        self.targetTabId = targetTabId
        self.targetPaneKind = targetPaneKind
        self.targetPaneIsAlreadyActive = targetPaneIsAlreadyActive
        self.targetMountedContent = targetMountedContent
        self.managementMode = managementMode
        self.windowState = windowState
    }
}

extension PaneFocusContext.PaneKind {
    init(content: PaneContent?) {
        switch content {
        case .terminal:
            self = .terminal
        case .webview:
            self = .webview
        case .bridgePanel:
            self = .bridge
        case .codeViewer:
            self = .codeViewer
        case .unsupported, .none:
            self = .unknown
        }
    }
}
