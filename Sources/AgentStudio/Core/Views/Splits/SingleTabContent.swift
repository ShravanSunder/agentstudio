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
    let onOpenPaneGitHub: (UUID) -> Void

    private static func traceMissingTab(tabId: UUID) -> Int {
        RestoreTrace.log("SingleTabContent.body missingTab tabId=\(tabId)")
        return 0
    }

    var body: some View {
        let tab = store.tabLayoutAtom.tab(tabId)
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
                onOpenPaneGitHub: onOpenPaneGitHub
            )
            .background(AppStyle.chromeBackground)
        }
    }
}
