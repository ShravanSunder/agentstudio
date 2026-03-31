import SwiftUI

/// Legacy active-tab SwiftUI root preserved for diagnostics and transitional tests.
///
/// The production `PaneTabViewController` no longer hosts this view directly; it now
/// creates one persistent `SingleTabContent` host per tab at the AppKit layer.
/// This type remains as a compatibility shim for tests and debug-only investigation.
@available(*, deprecated, message: "PaneTabViewController now uses per-tab SingleTabContent hosts")
struct ActiveTabContent: View {
    let store: WorkspaceStore
    let repoCache: WorkspaceRepoCache
    let viewRegistry: ViewRegistry
    let appLifecycleStore: AppLifecycleStore
    let closeTransitionCoordinator: PaneCloseTransitionCoordinator
    let actionDispatcher: PaneActionDispatching

    private static func traceBody(
        activeTabId: UUID?,
        tabPaneCount: Int,
        registeredPaneCount: Int,
        hasTree: Bool
    ) -> Int {
        if let activeTabId {
            RestoreTrace.log(
                "ActiveTabContent.body activeTab=\(activeTabId) tabPaneCount=\(tabPaneCount) registeredPaneCount=\(registeredPaneCount) hasTree=\(hasTree)"
            )
        } else {
            RestoreTrace.log("ActiveTabContent.body empty activeTab=nil")
        }
        return 0
    }

    var body: some View {
        let activeTabId = store.activeTabId
        let tab = activeTabId.flatMap { store.tab($0) }
        let registeredPaneCount = tab?.paneIds.filter { viewRegistry.view(for: $0) != nil }.count ?? 0
        let tabPaneCount = tab?.paneIds.count ?? 0
        // swiftlint:disable:next redundant_discardable_let
        let _ = Self.traceBody(
            activeTabId: activeTabId,
            tabPaneCount: tabPaneCount,
            registeredPaneCount: registeredPaneCount,
            hasTree: tab != nil && registeredPaneCount > 0
        )

        if let activeTabId, let tab {
            FlatTabStripContainer(
                layout: tab.layout,
                tabId: activeTabId,
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
        // Empty/no-tab state handled by AppKit (PaneTabViewController toggles NSView visibility)
    }
}
