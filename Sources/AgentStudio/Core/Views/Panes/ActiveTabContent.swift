import SwiftUI

/// Legacy active-tab SwiftUI root preserved for diagnostics and transitional tests.
///
/// The production `PaneTabViewController` no longer hosts this view directly; it now
/// creates one persistent `SingleTabContent` host per tab at the AppKit layer.
/// This type remains as a compatibility shim for tests and debug-only investigation.
@available(*, deprecated, message: "PaneTabViewController now uses per-tab SingleTabContent hosts")
struct ActiveTabContent: View {
    let store: WorkspaceStore
    let repoCache: RepoCacheAtom
    let viewRegistry: ViewRegistry
    let appLifecycleStore: AppLifecycleAtom
    let closeTransitionCoordinator: PaneCloseTransitionCoordinator
    let actionDispatcher: PaneActionDispatching
    let onPaneFocusTrigger: PaneFocusTriggerHandler
    let paneInboxPresentation: PaneInboxPresentation? = nil
    let onOpenPaneGitHub: (UUID) -> Void
    let notificationCountForWorktree: (UUID) -> Int = { _ in 0 }
    let workspaceWindowId: UUID? = nil

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
        let activeTabId = store.tabLayoutAtom.activeTabId
        let tab = activeTabId.flatMap { store.tabLayoutAtom.tab($0) }
        let registeredPaneCount = tab?.activePaneIds.filter { viewRegistry.view(for: $0) != nil }.count ?? 0
        let tabPaneCount = tab?.activePaneIds.count ?? 0
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
                minimizedPaneIds: tab.activeMinimizedPaneIds,
                visiblePaneIds: atom(\.arrangementView).activeVisiblePaneIds(forTab: activeTabId),
                showsMinimizedPanes: atom(\.arrangementView).effectiveShowsMinimizedPanes(forTab: activeTabId),
                closeTransitionCoordinator: closeTransitionCoordinator,
                actionDispatcher: actionDispatcher,
                onPaneFocusTrigger: onPaneFocusTrigger,
                store: store,
                repoCache: repoCache,
                viewRegistry: viewRegistry,
                appLifecycleStore: appLifecycleStore,
                paneInboxPresentation: paneInboxPresentation,
                onOpenPaneGitHub: onOpenPaneGitHub,
                notificationCountForWorktree: notificationCountForWorktree,
                workspaceWindowId: workspaceWindowId
            )
            .background(AppStyles.Shell.PaneChrome.background)
        }
        // Empty/no-tab state handled by AppKit (PaneTabViewController toggles NSView visibility)
    }
}
