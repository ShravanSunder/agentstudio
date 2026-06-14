import Foundation
import os.log

@MainActor
final class ManagementLayerCommandController {
    private static let logger = Logger(subsystem: "com.agentstudio", category: "ManagementLayerCommandController")

    private let store: WorkspaceStore
    private let repoCache: RepoCacheAtom
    private let executor: ActionExecutor
    private let workspaceFocusController: WorkspaceFocusController
    private let arrangementViewProvider: @MainActor () -> WorkspaceArrangementViewDerived
    private let dispatchAction: @MainActor (PaneActionCommand) -> Void
    private let executeCommand: @MainActor (AppCommand) -> Void
    private let canExecuteCommand: @MainActor (AppCommand) -> Bool
    private let handlePaneFocusTrigger: @MainActor (PaneFocusTrigger) -> Void
    private let openGitHubWebview: @MainActor (UUID) -> Void
    private let focusTargetedDrawerPane: @MainActor (UUID, UUID) -> Void

    init(
        store: WorkspaceStore,
        repoCache: RepoCacheAtom,
        executor: ActionExecutor,
        workspaceFocusController: WorkspaceFocusController,
        arrangementViewProvider: @escaping @MainActor () -> WorkspaceArrangementViewDerived,
        dispatchAction: @escaping @MainActor (PaneActionCommand) -> Void,
        executeCommand: @escaping @MainActor (AppCommand) -> Void,
        canExecuteCommand: @escaping @MainActor (AppCommand) -> Bool,
        handlePaneFocusTrigger: @escaping @MainActor (PaneFocusTrigger) -> Void,
        openGitHubWebview: @escaping @MainActor (UUID) -> Void,
        focusTargetedDrawerPane: @escaping @MainActor (UUID, UUID) -> Void
    ) {
        self.store = store
        self.repoCache = repoCache
        self.executor = executor
        self.workspaceFocusController = workspaceFocusController
        self.arrangementViewProvider = arrangementViewProvider
        self.dispatchAction = dispatchAction
        self.executeCommand = executeCommand
        self.canExecuteCommand = canExecuteCommand
        self.handlePaneFocusTrigger = handlePaneFocusTrigger
        self.openGitHubWebview = openGitHubWebview
        self.focusTargetedDrawerPane = focusTargetedDrawerPane
    }

    func handleManagementCommand(_ command: AppCommand) -> Bool {
        switch command {
        case .toggleManagementLayer:
            let wasManagementLayerActive = atom(\.managementLayer).isActive
            atom(\.managementLayer).toggle()
            if !wasManagementLayerActive {
                workspaceFocusController.setNavigationScope(
                    workspaceFocusController.initialWorkspaceNavigationFocusScope()
                )
            }
            return true

        case .managementLayerFocusLeft:
            handleManagementMoveLeft()
            return true

        case .managementLayerFocusRight:
            handleManagementMoveRight()
            return true

        case .managementLayerEnterDrawer:
            handleManagementMoveDown()
            return true

        case .managementLayerExitDrawer:
            handleManagementMoveUp()
            return true

        case .managementLayerOpenDrawer:
            handleManagementOpenDrawer()
            return true

        case .managementLayerCreateTerminal:
            handleManagementCreateTerminal()
            return true

        case .managementLayerCreateBrowser:
            handleManagementCreateBrowser()
            return true

        case .managementLayerExit:
            atom(\.managementLayer).deactivate()
            return true

        default:
            return false
        }
    }

    func enterDrawerFromActivePane() {
        guard
            let activeTabId = store.tabLayoutAtom.activeTabId,
            let parentPaneId = store.tabLayoutAtom.tab(activeTabId)?.activePaneId
        else { return }

        if store.paneAtom.pane(parentPaneId)?.drawer?.isExpanded == false {
            dispatchAction(.toggleDrawer(paneId: parentPaneId))
        }

        if let drawerPaneId = arrangementViewProvider().drawerView(forParent: parentPaneId)?.activeChildId {
            workspaceFocusController.setNavigationScope(.drawer(parentPaneId: parentPaneId))
            handlePaneFocusTrigger(.drawer(.selectPane(parentPaneId: parentPaneId, drawerPaneId: drawerPaneId)))
        } else {
            workspaceFocusController.setNavigationScope(.drawer(parentPaneId: parentPaneId))
            atom(\.workspaceFocusOwner).focusEmptyDrawer(parentPaneId: parentPaneId)
            _ = workspaceFocusController.clearFirstResponderToWindowContentForDrawer(parentPaneId: parentPaneId)
        }
    }

    func moveDrawerFocus(_ command: AppCommand) {
        guard let target = drawerFocusNeighbor(for: command) else { return }
        handlePaneFocusTrigger(
            .drawer(.selectPane(parentPaneId: target.parentPaneId, drawerPaneId: target.drawerPaneId)))
    }

    func focusDrawerPaneOrdinal(command: AppCommand) -> Bool {
        guard let target = resolveDrawerPaneOrdinalTarget(for: command) else { return false }
        if target.drawerView.minimizedPaneIds.contains(target.drawerPaneId) {
            dispatchAction(.expandDrawerPane(parentPaneId: target.parentPaneId, drawerPaneId: target.drawerPaneId))
        }
        focusTargetedDrawerPane(target.parentPaneId, target.drawerPaneId)
        return true
    }

    func canExecuteManagementCommand(_ command: AppCommand) -> Bool {
        let navigationScope = workspaceFocusController.normalizedWorkspaceNavigationFocusScope()

        switch command {
        case .managementLayerFocusLeft:
            switch navigationScope {
            case .mainRow:
                return canExecuteCommand(.focusPaneLeft)
            case .drawer(let parentPaneId):
                return workspaceFocusController.visibleDrawerPaneIds(for: parentPaneId).count > 1
            }
        case .managementLayerFocusRight:
            switch navigationScope {
            case .mainRow:
                return canExecuteCommand(.focusPaneRight)
            case .drawer(let parentPaneId):
                return workspaceFocusController.visibleDrawerPaneIds(for: parentPaneId).count > 1
            }
        case .managementLayerEnterDrawer, .managementLayerOpenDrawer:
            return workspaceFocusController.activeMainPaneId() != nil
        case .managementLayerExitDrawer, .managementLayerExit:
            if case .drawer = navigationScope {
                return true
            }
            return command == .managementLayerExit
        case .managementLayerCreateTerminal:
            switch managementLayerCreationScope() {
            case .mainRow:
                return canExecuteCommand(.newTerminalInTab)
            case .drawer(let parentPaneId):
                return store.paneAtom.pane(parentPaneId)?.drawer != nil
            }
        case .managementLayerCreateBrowser:
            return managementLayerCreationScope() != .mainRow || workspaceFocusController.activeMainPaneId() != nil
        default:
            return false
        }
    }

    func canExecuteDrawerFocusCommand(_ command: AppCommand) -> Bool {
        drawerFocusNeighbor(for: command) != nil
    }

    func canExecuteDrawerOrdinalCommand(_ command: AppCommand) -> Bool {
        resolveDrawerPaneOrdinalTarget(for: command) != nil
    }

    private func managementLayerCreationScope() -> WorkspaceNavigationFocusScope {
        let navigationScope = workspaceFocusController.normalizedWorkspaceNavigationFocusScope()

        if case .drawer = navigationScope {
            return navigationScope
        }

        return workspaceFocusController.initialWorkspaceNavigationFocusScope()
    }

    private func focusSiblingDrawerPane(in parentPaneId: UUID, delta: Int) {
        let visiblePaneIds = workspaceFocusController.visibleDrawerPaneIds(for: parentPaneId)
        guard !visiblePaneIds.isEmpty else { return }

        let currentPaneId =
            workspaceFocusController.visibleActiveDrawerPaneId(for: parentPaneId) ?? visiblePaneIds.first!
        guard let currentIndex = visiblePaneIds.firstIndex(of: currentPaneId) else { return }

        let nextIndex = (currentIndex + delta + visiblePaneIds.count) % visiblePaneIds.count
        let nextPaneId = visiblePaneIds[nextIndex]
        workspaceFocusController.setNavigationScope(.drawer(parentPaneId: parentPaneId))
        handlePaneFocusTrigger(.drawer(.selectPane(parentPaneId: parentPaneId, drawerPaneId: nextPaneId)))
    }

    private func handleManagementMoveLeft() {
        switch workspaceFocusController.normalizedWorkspaceNavigationFocusScope() {
        case .mainRow:
            executeCommand(.focusPaneLeft)
        case .drawer(let parentPaneId):
            focusSiblingDrawerPane(in: parentPaneId, delta: -1)
        }
    }

    private func handleManagementMoveRight() {
        switch workspaceFocusController.normalizedWorkspaceNavigationFocusScope() {
        case .mainRow:
            executeCommand(.focusPaneRight)
        case .drawer(let parentPaneId):
            focusSiblingDrawerPane(in: parentPaneId, delta: 1)
        }
    }

    private func handleManagementMoveDown() {
        guard case .drawer(let parentPaneId) = workspaceFocusController.normalizedWorkspaceNavigationFocusScope()
        else {
            return
        }
        workspaceFocusController.setNavigationScope(.drawer(parentPaneId: parentPaneId))
        if let drawerPaneId = workspaceFocusController.visibleActiveDrawerPaneId(for: parentPaneId) {
            handlePaneFocusTrigger(.drawer(.selectPane(parentPaneId: parentPaneId, drawerPaneId: drawerPaneId)))
        }
    }

    private func handleManagementOpenDrawer() {
        guard let parentPaneId = workspaceFocusController.activeMainPaneId() else {
            Self.logger.warning("management open drawer ignored because active main pane is unavailable")
            return
        }
        let drawerIsExpanded = store.paneAtom.pane(parentPaneId)?.drawer?.isExpanded == true
        if !drawerIsExpanded {
            dispatchAction(.toggleDrawer(paneId: parentPaneId))
            handlePaneFocusTrigger(.drawer(.toggle(parentPaneId: parentPaneId)))
        }

        workspaceFocusController.setNavigationScope(.drawer(parentPaneId: parentPaneId))

        if let drawerPaneId = workspaceFocusController.visibleActiveDrawerPaneId(for: parentPaneId) {
            handlePaneFocusTrigger(.drawer(.selectPane(parentPaneId: parentPaneId, drawerPaneId: drawerPaneId)))
        }
    }

    private func handleManagementMoveUp() {
        guard case .drawer(let parentPaneId) = workspaceFocusController.normalizedWorkspaceNavigationFocusScope()
        else { return }
        if store.paneAtom.pane(parentPaneId)?.drawer?.isExpanded == true {
            dispatchAction(.toggleDrawer(paneId: parentPaneId))
            handlePaneFocusTrigger(.drawer(.toggle(parentPaneId: parentPaneId)))
        }
        workspaceFocusController.setNavigationScope(.mainRow)
    }

    private func drawerFocusNeighbor(for command: AppCommand) -> (parentPaneId: UUID, drawerPaneId: UUID)? {
        guard
            case .drawerPane(let parentPaneId, let drawerPaneId) =
                workspaceFocusController.normalizedWorkspaceNavigationScopeState()
        else {
            return nil
        }

        let direction: FocusDirection
        switch command {
        case .focusDrawerPaneUp:
            direction = .up
        case .focusDrawerPaneLeft:
            direction = .left
        case .focusDrawerPaneDown:
            direction = .down
        case .focusDrawerPaneRight:
            direction = .right
        default:
            return nil
        }

        guard
            let drawerView = arrangementViewProvider().drawerView(forParent: parentPaneId),
            let targetPaneId = drawerView.layout.neighbor(of: drawerPaneId, direction: direction)
        else { return nil }

        return (parentPaneId, targetPaneId)
    }

    private func resolveDrawerPaneOrdinalTarget(for command: AppCommand) -> (
        parentPaneId: UUID,
        drawerView: DrawerView,
        drawerPaneId: UUID
    )? {
        guard
            let ordinal = drawerPaneOrdinal(for: command),
            let parentPaneId = workspaceFocusController.activeMainPaneId(),
            let drawerView = arrangementViewProvider().drawerView(forParent: parentPaneId),
            let drawerPaneId = PaneOrdinalMap(orderedPaneIds: drawerView.layout.paneIds).paneId(forOrdinal: ordinal)
        else {
            return nil
        }
        return (parentPaneId, drawerView, drawerPaneId)
    }

    private func drawerPaneOrdinal(for command: AppCommand) -> Int? {
        AppCommand.focusDrawerPaneCommands.firstIndex(of: command).map { $0 + 1 }
    }

    private func handleManagementCreateTerminal() {
        switch managementLayerCreationScope() {
        case .mainRow:
            workspaceFocusController.setNavigationScope(.mainRow)
            executeCommand(.newTerminalInTab)
        case .drawer(let parentPaneId):
            workspaceFocusController.setNavigationScope(.drawer(parentPaneId: parentPaneId))
            dispatchAction(.addDrawerPane(parentPaneId: parentPaneId))
        }
    }

    private func handleManagementCreateBrowser() {
        switch managementLayerCreationScope() {
        case .mainRow:
            workspaceFocusController.setNavigationScope(.mainRow)
            guard let paneId = workspaceFocusController.activeMainPaneId() else {
                Self.logger.warning("management create browser ignored because active main pane is unavailable")
                return
            }
            openGitHubWebview(paneId)
        case .drawer(let parentPaneId):
            workspaceFocusController.setNavigationScope(.drawer(parentPaneId: parentPaneId))
            let url = GitHubWebviewLaunchResolver.url(
                for: parentPaneId,
                store: store,
                repoCache: repoCache
            )
            _ = executor.openContextualWebviewInDrawer(
                parentPaneId: parentPaneId,
                url: url
            )
        }
    }
}
