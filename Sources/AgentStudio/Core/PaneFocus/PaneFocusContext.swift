import Foundation

package enum PaneManagementFocusScope: Sendable, Equatable {
    case mainRow
    case drawer(parentPaneId: UUID)
}

package struct PaneFocusContext: Sendable, Equatable {
    package enum PaneKind: Sendable, Equatable {
        case terminal
        case webview
        case bridge
        case codeViewer
        case unknown
    }

    package enum ManagementLayerState: Sendable, Equatable {
        case inactive
        case active(scope: PaneManagementFocusScope)
    }

    package enum WindowState: Sendable, Equatable {
        case background
        case focused
        case key
    }

    package enum MountedContentState: Sendable, Equatable {
        case unmounted
        case nonTerminal(acceptsFirstResponder: Bool)
        case terminal(surfaceId: UUID?)
    }

    package struct ActiveDrawerContext: Sendable, Equatable {
        let parentPaneId: UUID
        let paneId: UUID?
        let isEmpty: Bool

        package init(parentPaneId: UUID, paneId: UUID?, isEmpty: Bool = false) {
            self.parentPaneId = parentPaneId
            self.paneId = paneId
            self.isEmpty = isEmpty
        }
    }

    let activeTabId: UUID?
    let activePaneId: UUID?
    let activeDrawer: ActiveDrawerContext?
    package let targetPaneId: UUID?
    package let targetTabId: UUID?
    let targetPaneKind: PaneKind
    let targetPaneIsAlreadyActive: Bool
    let targetMountedContent: MountedContentState
    let managementLayer: ManagementLayerState
    let windowState: WindowState

    package init(
        activeTabId: UUID?,
        activePaneId: UUID?,
        activeDrawer: ActiveDrawerContext?,
        targetPaneId: UUID?,
        targetTabId: UUID?,
        targetPaneKind: PaneKind,
        targetPaneIsAlreadyActive: Bool,
        targetMountedContent: MountedContentState,
        managementLayer: ManagementLayerState,
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
        self.managementLayer = managementLayer
        self.windowState = windowState
    }
}
