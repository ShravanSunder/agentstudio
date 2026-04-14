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

    enum TriggerSource: Sendable, Equatable {
        case contentClick
        case tabClick
        case drawerClick
        case keyboard
        case modeTransition
        case refocusRequest
        case command
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

    let activeTabId: UUID?
    let activePaneId: UUID?
    let activeDrawerParentPaneId: UUID?
    let activeDrawerPaneId: UUID?
    let targetPaneId: UUID?
    let targetTabId: UUID?
    let targetPaneKind: PaneKind
    let targetPaneIsAlreadyActive: Bool
    let targetMountedContent: MountedContentState
    let managementMode: ManagementModeState
    let windowState: WindowState
    let triggerSource: TriggerSource
}
