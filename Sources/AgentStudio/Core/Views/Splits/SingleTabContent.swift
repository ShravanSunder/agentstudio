import SwiftUI

struct SingleTabContent: View {
    let tabId: UUID
    let store: WorkspaceStore
    let repoCache: WorkspaceRepoCache
    let viewRegistry: ViewRegistry
    let appLifecycleStore: AppLifecycleStore
    let closeTransitionCoordinator: PaneCloseTransitionCoordinator
    let actionDispatcher: PaneActionDispatching

    private static func traceMissingTab(tabId: UUID) -> Int {
        RestoreTrace.log("SingleTabContent.body missingTab tabId=\(tabId)")
        return 0
    }

    private static func traceBody(tabId: UUID, hasTab: Bool, registeredPaneCount: Int) -> Int {
        RestoreTrace.log(
            "SingleTabContent.body tabId=\(tabId) hasTab=\(hasTab) registeredPaneCount=\(registeredPaneCount)"
        )
        return 0
    }

    var body: some View {
        let tab = store.tab(tabId)
        let registeredPaneCount =
            tab?.paneIds.filter { paneId in
                _ = viewRegistry.registrationEpoch(for: paneId)
                return viewRegistry.slot(for: paneId).host != nil
            }.count ?? 0
        // swiftlint:disable:next redundant_discardable_let
        let _ = Self.traceBody(tabId: tabId, hasTab: tab != nil, registeredPaneCount: registeredPaneCount)
        // swiftlint:disable:next redundant_discardable_let
        let _ = tab == nil ? Self.traceMissingTab(tabId: tabId) : 0
        if let tab {
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
        }
    }
}
