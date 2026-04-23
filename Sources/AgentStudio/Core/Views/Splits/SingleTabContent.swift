import SwiftUI

struct SingleTabContent: View {
    let tabId: UUID
    let store: WorkspaceStore
    let repoCache: RepoCacheAtom
    let viewRegistry: ViewRegistry
    let appLifecycleStore: AppLifecycleAtom
    let closeTransitionCoordinator: PaneCloseTransitionCoordinator
    let actionDispatcher: PaneActionDispatching
    let onPaneFocusTrigger: PaneFocusTriggerHandler
    let drawerInboxPresentation: DrawerInboxPresentation?
    let onOpenPaneGitHub: (UUID) -> Void

    init(
        tabId: UUID,
        store: WorkspaceStore,
        repoCache: RepoCacheAtom,
        viewRegistry: ViewRegistry,
        appLifecycleStore: AppLifecycleAtom,
        closeTransitionCoordinator: PaneCloseTransitionCoordinator,
        actionDispatcher: PaneActionDispatching,
        onPaneFocusTrigger: @escaping PaneFocusTriggerHandler,
        drawerInboxPresentation: DrawerInboxPresentation? = nil,
        onOpenPaneGitHub: @escaping (UUID) -> Void
    ) {
        self.tabId = tabId
        self.store = store
        self.repoCache = repoCache
        self.viewRegistry = viewRegistry
        self.appLifecycleStore = appLifecycleStore
        self.closeTransitionCoordinator = closeTransitionCoordinator
        self.actionDispatcher = actionDispatcher
        self.onPaneFocusTrigger = onPaneFocusTrigger
        self.drawerInboxPresentation = drawerInboxPresentation
        self.onOpenPaneGitHub = onOpenPaneGitHub
    }

    private static func traceMissingTab(tabId: UUID) -> Int {
        RestoreTrace.log("SingleTabContent.body missingTab tabId=\(tabId)")
        return 0
    }

    var body: some View {
        let workspaceTab = WorkspaceTabDerived(
            shellAtom: store.tabShellAtom,
            arrangementAtom: store.tabArrangementAtom
        )
        let tab = workspaceTab.tab(tabId)
        // swiftlint:disable:next redundant_discardable_let
        let _ = tab == nil ? Self.traceMissingTab(tabId: tabId) : 0
        if let tab {
            FlatTabStripContainer(
                layout: tab.layout,
                tabId: tabId,
                activePaneId: tab.activePaneId,
                zoomedPaneId: tab.zoomedPaneId,
                minimizedPaneIds: tab.activeMinimizedPaneIds,
                closeTransitionCoordinator: closeTransitionCoordinator,
                actionDispatcher: actionDispatcher,
                onPaneFocusTrigger: onPaneFocusTrigger,
                store: store,
                repoCache: repoCache,
                viewRegistry: viewRegistry,
                appLifecycleStore: appLifecycleStore,
                drawerInboxPresentation: drawerInboxPresentation,
                onOpenPaneGitHub: onOpenPaneGitHub
            )
            .background(AppStyles.Shell.PaneChrome.background)
        }
    }
}
