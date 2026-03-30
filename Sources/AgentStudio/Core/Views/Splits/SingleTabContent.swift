import SwiftUI

struct SingleTabContent: View {
    let tabId: UUID
    let store: WorkspaceStore
    let repoCache: WorkspaceRepoCache
    let viewRegistry: ViewRegistry
    let appLifecycleStore: AppLifecycleStore
    let closeTransitionCoordinator: PaneCloseTransitionCoordinator
    let actionDispatcher: PaneActionDispatching

    var body: some View {
        if let tab = store.tab(tabId) {
            FlatTabStripContainer(
                layout: tab.layout,
                tabId: tabId,
                activePaneId: tab.activePaneId,
                zoomedPaneId: tab.zoomedPaneId,
                minimizedPaneIds: tab.minimizedPaneIds,
                closeTransitionCoordinator: closeTransitionCoordinator,
                actionDispatcher: actionDispatcher,
                store: store,
                repoCache: repoCache,
                viewRegistry: viewRegistry,
                appLifecycleStore: appLifecycleStore
            )
            .background(AppStyle.chromeBackground)
        } else {
            _ = RestoreTrace.log("SingleTabContent.body missingTab tabId=\(tabId)")
        }
    }
}
