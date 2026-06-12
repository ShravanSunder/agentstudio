import AppKit
import Foundation
import os

enum WorkspaceNavigationFocusScope: Equatable {
    case mainRow
    case drawer(parentPaneId: UUID)
}

@MainActor
final class WorkspaceFocusController {
    private static let logger = Logger(subsystem: "com.agentstudio", category: "WorkspaceFocusController")

    private let store: WorkspaceStore
    private let executor: ActionExecutor
    private let viewRegistry: ViewRegistry
    private let windowProvider: @MainActor () -> NSWindow?

    private var lastFocusedTabId: UUID?
    private var lastFocusedPaneId: UUID?
    private var suppressedSelectionDrivenRefocus: (tabId: UUID?, paneId: UUID?)?
    private var lastManagementLayerActive = false
    private var managementNavigationScope: WorkspaceNavigationFocusScope = .mainRow
    private lazy var paneFocusExecutor = makePaneFocusExecutor()

    init(
        store: WorkspaceStore,
        executor: ActionExecutor,
        viewRegistry: ViewRegistry,
        windowProvider: @escaping @MainActor () -> NSWindow?
    ) {
        self.store = store
        self.executor = executor
        self.viewRegistry = viewRegistry
        self.windowProvider = windowProvider
    }

    var navigationScopeDescriptionForTesting: String {
        switch managementNavigationScope {
        case .mainRow:
            return "mainRow"
        case .drawer(let parentPaneId):
            return "drawer:\(parentPaneId.uuidString)"
        }
    }

    func setNavigationScope(_ scope: WorkspaceNavigationFocusScope) {
        managementNavigationScope = scope
    }

    func setNavigationScopeToDrawerForTesting(parentPaneId: UUID) {
        managementNavigationScope = .drawer(parentPaneId: parentPaneId)
    }

    func handleAppKitStateChange() {
        let isManagementLayerActive = atom(\.managementLayer).isActive
        let didExitManagementLayer = lastManagementLayerActive && !isManagementLayerActive
        if lastManagementLayerActive != isManagementLayerActive {
            let transition: PaneModeFocusTrigger.Transition =
                isManagementLayerActive ? .enteredManagementLayer : .exitedManagementLayer
            handlePaneFocusTrigger(
                .mode(
                    PaneModeFocusTrigger(
                        transition: transition,
                        source: .command
                    )
                )
            )
        }

        if !lastManagementLayerActive && isManagementLayerActive {
            managementNavigationScope = initialWorkspaceNavigationFocusScope()
        }
        lastManagementLayerActive = isManagementLayerActive
        managementNavigationScope = normalizedWorkspaceNavigationFocusScope()

        let currentTabId = store.tabLayoutAtom.activeTabId
        let currentPaneId = preferredVisibleFocusPaneId()
        let selectionChanged = currentTabId != lastFocusedTabId || currentPaneId != lastFocusedPaneId
        let activePaneViewMissing = currentPaneId.map { viewRegistry.view(for: $0) == nil } ?? false

        if selectionChanged || activePaneViewMissing {
            executor.restoreVisibleViewsForActiveTabIfNeeded()
        }

        if selectionChanged {
            lastFocusedTabId = currentTabId
            lastFocusedPaneId = currentPaneId
            if shouldSkipSelectionDrivenRefocus(currentTabId: currentTabId, currentPaneId: currentPaneId) {
                suppressedSelectionDrivenRefocus = nil
            } else {
                scheduleSelectionDrivenRefocus()
            }
        }

        if didExitManagementLayer {
            requestPaneRefocus(.managementLayerExited)
        }
    }

    func handlePaneFocusTrigger(_ trigger: PaneFocusTrigger) {
        guard let context = makePaneFocusContext(for: trigger) else {
            Self.logger.warning(
                "Pane focus trigger dropped because context assembly failed trigger=\(String(describing: trigger), privacy: .public)"
            )
            return
        }
        let decision = PaneFocusOrchestrator.decide(trigger: trigger, context: context)
        if !paneFocusExecutor.apply(decision) {
            Self.logger.warning(
                "Pane focus apply returned false for trigger \(String(describing: trigger), privacy: .public)")
        }
    }

    func requestPaneRefocus(_ reason: PaneRefocusRequestTrigger.Reason = .explicit) {
        handlePaneFocusTrigger(.refocusRequest(PaneRefocusRequestTrigger(reason: reason)))
    }

    func initialWorkspaceNavigationFocusScope() -> WorkspaceNavigationFocusScope {
        if let parentPaneId = activeMainPaneId(),
            store.paneAtom.pane(parentPaneId)?.drawer?.isExpanded == true
        {
            return .drawer(parentPaneId: parentPaneId)
        }

        return .mainRow
    }

    func normalizedWorkspaceNavigationFocusScope() -> WorkspaceNavigationFocusScope {
        guard case .drawer(let parentPaneId) = managementNavigationScope else {
            return managementNavigationScope
        }
        guard
            let activeTabId = store.tabLayoutAtom.activeTabId,
            let activePaneId = store.tabLayoutAtom.tab(activeTabId)?.activePaneId,
            activePaneId == parentPaneId,
            let drawer = store.paneAtom.pane(parentPaneId)?.drawer,
            drawer.isExpanded
        else {
            return .mainRow
        }
        return managementNavigationScope
    }

    func normalizedWorkspaceNavigationScopeState() -> WorkspaceFocusOwner {
        WorkspaceFocusOwnerNormalizer.normalize(
            requested: atom(\.workspaceFocusOwner).owner,
            context: currentWorkspaceFocusOwnerContext()
        )
    }

    func activeMainPaneId() -> UUID? {
        store.tabLayoutAtom.activeTabId
            .flatMap { store.tabLayoutAtom.tab($0) }?
            .activePaneId
    }

    func visibleDrawerPaneIds(for parentPaneId: UUID) -> [UUID] {
        arrangementView.drawerVisiblePaneIds(forParent: parentPaneId)
    }

    func visibleActiveDrawerPaneId(for parentPaneId: UUID) -> UUID? {
        guard let drawer = store.paneAtom.pane(parentPaneId)?.drawer else { return nil }
        guard drawer.isExpanded else { return nil }
        guard let drawerView = arrangementView.drawerView(forParent: parentPaneId),
            let drawerPaneId = drawerView.activeChildId
        else { return nil }
        guard !drawerView.minimizedPaneIds.contains(drawerPaneId) else { return nil }
        return drawerPaneId
    }

    func clearFirstResponderToWindowContentForDrawer(parentPaneId: UUID) -> Bool {
        let window = viewRegistry.view(for: parentPaneId)?.window ?? windowProvider() ?? NSApp.keyWindow
        guard let window, let contentView = window.contentView else { return false }
        return window.makeFirstResponder(contentView)
    }

    func applyWorkspaceFocusOwner(_ owner: WorkspaceFocusOwner) {
        switch owner {
        case .mainPane(let paneId):
            atom(\.workspaceFocusOwner).focusMainPane(paneId)
            managementNavigationScope = .mainRow
        case .drawerPane(let parentPaneId, let drawerPaneId):
            atom(\.workspaceFocusOwner).focusDrawerPane(parentPaneId: parentPaneId, paneId: drawerPaneId)
            managementNavigationScope = .drawer(parentPaneId: parentPaneId)
        case .emptyDrawer(let parentPaneId):
            atom(\.workspaceFocusOwner).focusEmptyDrawer(parentPaneId: parentPaneId)
            managementNavigationScope = .drawer(parentPaneId: parentPaneId)
            _ = clearFirstResponderToWindowContentForDrawer(parentPaneId: parentPaneId)
        }
    }

    func syncFocusOwnerAfterDrawerMutation(parentPaneId: UUID) {
        guard let drawer = store.paneAtom.pane(parentPaneId)?.drawer else { return }

        if drawer.isExpanded {
            managementNavigationScope = .drawer(parentPaneId: parentPaneId)
            let drawerView = arrangementView.drawerView(forParent: parentPaneId)
            if let drawerPaneId = drawerView?.activeChildId,
                drawerView?.minimizedPaneIds.contains(drawerPaneId) == false
            {
                atom(\.workspaceFocusOwner).focusDrawerPane(parentPaneId: parentPaneId, paneId: drawerPaneId)
            } else {
                atom(\.workspaceFocusOwner).focusEmptyDrawer(parentPaneId: parentPaneId)
                _ = clearFirstResponderToWindowContentForDrawer(parentPaneId: parentPaneId)
            }
        } else {
            managementNavigationScope = .mainRow
            atom(\.workspaceFocusOwner).focusMainPane(parentPaneId)
        }
    }

    func drawerParentByPaneId() -> [UUID: UUID] {
        Dictionary(
            uniqueKeysWithValues: store.paneAtom.panes.values.compactMap { pane in
                guard let parentPaneId = pane.parentPaneId else { return nil }
                return (pane.id, parentPaneId)
            }
        )
    }

    func drawerLayoutByParentPaneId() -> [UUID: DrawerGridLayout] {
        Dictionary(
            uniqueKeysWithValues: store.paneAtom.panes.values.compactMap { pane in
                guard pane.drawer != nil, let drawerView = arrangementView.drawerView(forParent: pane.id) else {
                    return nil
                }
                return (pane.id, drawerView.layout)
            }
        )
    }

    private var arrangementView: WorkspaceArrangementViewDerived {
        WorkspaceArrangementViewDerived(
            tabLayoutAtom: store.tabLayoutAtom,
            paneAtom: store.paneAtom,
            managementLayerAtom: atom(\.managementLayer)
        )
    }

    private func preferredVisibleFocusPaneId() -> UUID? {
        switch normalizedWorkspaceNavigationScopeState() {
        case .drawerPane(_, let drawerPaneId):
            return drawerPaneId
        case .emptyDrawer:
            return nil
        case .mainPane(let paneId):
            return paneId
        }
    }

    private func scheduleSelectionDrivenRefocus() {
        Task { @MainActor [weak self] in
            self?.requestPaneRefocus(.explicit)
        }
    }

    private func makePaneFocusExecutor() -> PaneFocusExecutor {
        PaneFocusExecutor(
            hostViewProvider: { [weak self] paneId in
                self?.viewRegistry.view(for: paneId)
            },
            hostViewsProvider: { [weak self] in
                guard let self else { return [] }
                return self.viewRegistry.registeredPaneIds.compactMap { self.viewRegistry.view(for: $0) }
            },
            selectTab: { [weak self] tabId in
                guard let self else { return }
                self.selectTabAndRestoreVisibleViews(tabId)
                self.restoreFocusOwnerForSelectedTab()
            },
            selectPane: { [weak self] tabId, paneId in
                guard let self else { return }
                self.recordSelectionDrivenRefocusSuppression(tabId: tabId, paneId: paneId)
                if self.store.tabLayoutAtom.activeTabId != tabId {
                    self.selectTabAndRestoreVisibleViews(tabId)
                }
                self.revealArrangementContainingPane(tabId: tabId, paneId: paneId)
                if let tab = self.store.tabLayoutAtom.tab(tabId),
                    tab.activeMinimizedPaneIds.contains(paneId)
                {
                    self.executor.execute(.expandPane(tabId: tabId, paneId: paneId))
                }
                self.store.tabLayoutAtom.setActivePane(paneId, inTab: tabId)
                atom(\.workspaceFocusOwner).focusMainPane(paneId)
                self.managementNavigationScope = .mainRow
            },
            selectDrawerPane: { [weak self] parentPaneId, drawerPaneId in
                guard let self else { return }
                self.recordSelectionDrivenRefocusSuppression(
                    tabId: self.store.tabLayoutAtom.activeTabId,
                    paneId: drawerPaneId
                )
                if let tabId = self.store.tabLayoutAtom.tabContaining(paneId: parentPaneId)?.id,
                    let drawerId = self.store.paneAtom.pane(parentPaneId)?.drawer?.drawerId
                {
                    self.store.tabArrangementAtom.setActiveDrawerPane(drawerPaneId, drawerId: drawerId, inTab: tabId)
                }
                atom(\.workspaceFocusOwner).focusDrawerPane(
                    parentPaneId: parentPaneId,
                    paneId: drawerPaneId
                )
                self.managementNavigationScope = .drawer(parentPaneId: parentPaneId)
            },
            selectEmptyDrawer: { [weak self] parentPaneId in
                guard let self else { return }
                atom(\.workspaceFocusOwner).focusEmptyDrawer(parentPaneId: parentPaneId)
                self.managementNavigationScope = .drawer(parentPaneId: parentPaneId)
                _ = self.clearFirstResponderToWindowContentForDrawer(parentPaneId: parentPaneId)
            },
            syncRuntimeFocus: { surfaceId in
                SurfaceManager.shared.syncFocus(activeSurfaceId: surfaceId)
            }
        )
    }

    private func selectTabAndRestoreVisibleViews(_ tabId: UUID) {
        store.tabLayoutAtom.setActiveTab(tabId)
        executor.restoreVisibleViewsForActiveTabIfNeeded(forceWhenBoundsExist: true)
    }

    private func restoreFocusOwnerForSelectedTab() {
        guard let parentPaneId = activeMainPaneId() else {
            applyWorkspaceFocusOwner(.mainPane(paneId: nil))
            return
        }

        let requestedFocusOwner: WorkspaceFocusOwner =
            if store.paneAtom.pane(parentPaneId)?.drawer?.isExpanded == true {
                .emptyDrawer(parentPaneId: parentPaneId)
            } else {
                .mainPane(paneId: parentPaneId)
            }

        applyWorkspaceFocusOwner(
            WorkspaceFocusOwnerNormalizer.normalize(
                requested: requestedFocusOwner,
                context: currentWorkspaceFocusOwnerContext()
            )
        )
    }

    private func recordSelectionDrivenRefocusSuppression(tabId: UUID?, paneId: UUID?) {
        suppressedSelectionDrivenRefocus = (tabId, paneId)
    }

    private func shouldSkipSelectionDrivenRefocus(currentTabId: UUID?, currentPaneId: UUID?) -> Bool {
        suppressedSelectionDrivenRefocus?.tabId == currentTabId
            && suppressedSelectionDrivenRefocus?.paneId == currentPaneId
    }

    private func makePaneFocusContext(for trigger: PaneFocusTrigger) -> PaneFocusContext? {
        let activeTabId = store.tabLayoutAtom.activeTabId
        let activePaneId = preferredVisibleFocusPaneId()
        let targetTabId = paneFocusTargetTabId(for: trigger, activeTabId: activeTabId)
        let targetPaneId = paneFocusTargetPaneId(
            for: trigger,
            targetTabId: targetTabId,
            activePaneId: activePaneId
        )
        guard targetPaneId == nil || targetTabId != nil else {
            return nil
        }
        let targetPaneKind = PaneFocusContext.PaneKind(
            content: targetPaneId.flatMap { store.paneAtom.pane($0)?.content }
        )
        let targetMountedContent =
            targetPaneId
            .flatMap { viewRegistry.view(for: $0)?.mountedContentStateForPaneFocus }
            ?? .unmounted
        let activeDrawerParentPaneId = activeMainPaneId()

        return PaneFocusContext(
            activeTabId: activeTabId,
            activePaneId: activePaneId,
            activeDrawer: activeDrawerParentPaneId.map {
                .init(
                    parentPaneId: $0,
                    paneId: visibleActiveDrawerPaneId(for: $0),
                    isEmpty: store.paneAtom.pane($0)?.drawer?.paneIds.isEmpty == true
                )
            },
            targetPaneId: targetPaneId,
            targetTabId: targetTabId,
            targetPaneKind: targetPaneKind,
            targetPaneIsAlreadyActive: paneFocusTargetIsAlreadyActive(
                trigger: trigger,
                targetPaneId: targetPaneId,
                activePaneId: activePaneId,
                activeTabId: activeTabId
            ),
            targetMountedContent: targetMountedContent,
            managementLayer: atom(\.managementLayer).isActive
                ? .active(scope: paneFocusManagementScope)
                : .inactive,
            windowState: paneFocusWindowState(for: targetPaneId)
        )
    }

    private var paneFocusManagementScope: PaneManagementFocusScope {
        switch managementNavigationScope {
        case .mainRow:
            return .mainRow
        case .drawer(let parentPaneId):
            return .drawer(parentPaneId: parentPaneId)
        }
    }

    private func paneFocusTargetTabId(for trigger: PaneFocusTrigger, activeTabId: UUID?) -> UUID? {
        switch trigger {
        case .contentClick(let trigger):
            return store.tabLayoutAtom.tabs.first { $0.paneIds.contains(trigger.targetPaneId) }?.id
        case .tabClick(let trigger):
            return trigger.targetTabId
        case .drawer:
            return activeTabId
        case .keyboard(let trigger):
            switch trigger {
            case .moveToPane(let tabId, _, _):
                return tabId
            }
        case .mode, .refocusRequest:
            return activeTabId
        case .command(let trigger):
            switch trigger {
            case .focusPane(let tabId, _):
                return tabId
            case .selectTab(let tabId):
                return tabId
            case .paneCreated:
                return activeTabId
            }
        }
    }

    private func paneFocusTargetPaneId(
        for trigger: PaneFocusTrigger,
        targetTabId: UUID?,
        activePaneId: UUID?
    ) -> UUID? {
        switch trigger {
        case .contentClick(let trigger):
            return trigger.targetPaneId
        case .tabClick:
            return targetTabId.flatMap { store.tabLayoutAtom.tab($0) }?.activePaneId
        case .drawer(let trigger):
            switch trigger {
            case .selectPane(_, let drawerPaneId):
                return drawerPaneId
            case .toggle(let parentPaneId):
                return parentPaneId
            }
        case .keyboard(let trigger):
            switch trigger {
            case .moveToPane(_, let paneId, _):
                return paneId
            }
        case .mode:
            return activePaneId
        case .refocusRequest:
            return activePaneId
        case .command(let trigger):
            switch trigger {
            case .focusPane(_, let paneId), .paneCreated(let paneId, _):
                return paneId
            case .selectTab(let tabId):
                return store.tabLayoutAtom.tab(tabId)?.activePaneId
            }
        }
    }

    private func paneFocusTargetIsAlreadyActive(
        trigger: PaneFocusTrigger,
        targetPaneId: UUID?,
        activePaneId: UUID?,
        activeTabId: UUID?
    ) -> Bool {
        switch trigger {
        case .tabClick(let trigger):
            return activeTabId == trigger.targetTabId
        case .drawer(let trigger):
            switch trigger {
            case .selectPane(_, let drawerPaneId):
                return activeMainPaneId().flatMap { visibleActiveDrawerPaneId(for: $0) } == drawerPaneId
            case .toggle(let parentPaneId):
                return activePaneId == parentPaneId
            }
        default:
            return activePaneId == targetPaneId
        }
    }

    private func paneFocusWindowState(for paneId: UUID?) -> PaneFocusContext.WindowState {
        let window = paneId.flatMap { viewRegistry.view(for: $0)?.window } ?? windowProvider() ?? NSApp.keyWindow
        guard let window else { return .background }
        if window.isKeyWindow {
            return .key
        }
        if window.isMainWindow {
            return .focused
        }
        return .background
    }

    private func currentWorkspaceFocusOwnerContext() -> WorkspaceFocusOwnerNormalizer.Context {
        let activeMainPaneId = activeMainPaneId()
        let drawer = activeMainPaneId.flatMap { store.paneAtom.pane($0)?.drawer }
        let drawerView = activeMainPaneId.flatMap { arrangementView.drawerView(forParent: $0) }
        return .init(
            activeMainPaneId: activeMainPaneId,
            expandedDrawerParentPaneId: drawer?.isExpanded == true ? activeMainPaneId : nil,
            paneIds: drawer?.paneIds ?? [],
            activeDrawerPaneId: drawerView?.activeChildId,
            minimizedDrawerPaneIds: drawerView?.minimizedPaneIds ?? []
        )
    }

    private func revealArrangementContainingPane(tabId: UUID, paneId: UUID) {
        guard let tab = store.tabLayoutAtom.tab(tabId),
            !tab.activeArrangement.layout.contains(paneId),
            let containingArrangement = tab.arrangements.first(where: { $0.layout.contains(paneId) })
        else {
            return
        }

        store.tabLayoutAtom.switchArrangement(to: containingArrangement.id, inTab: tabId)
    }
}
