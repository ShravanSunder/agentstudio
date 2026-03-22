import SwiftUI

/// SwiftUI root for the main terminal content area.
///
/// Hosted by PaneTabViewController's `splitHostingView` (NSHostingView).
/// Reads the active tab from WorkspaceStore via @Observable property tracking
/// and renders `TerminalSplitContainer` for that tab. Re-renders automatically
/// when any accessed store property changes — no manual invalidation needed.
///
/// See docs/architecture/appkit_swiftui_architecture.md for the hosting pattern.
struct ActiveTabContent: View {
    let store: WorkspaceStore
    let repoCache: WorkspaceRepoCache
    let viewRegistry: ViewRegistry
    let appLifecycleStore: AppLifecycleStore
    let action: (PaneActionCommand) -> Void
    let shouldAcceptDrop: (SplitDropPayload, UUID, DropZone) -> Bool
    let onDrop: (SplitDropPayload, UUID, DropZone) -> Void

    private static func traceBody(
        activeTabId: UUID?,
        viewRevision: Int,
        tabPaneCount: Int,
        registeredPaneCount: Int,
        hasTree: Bool
    ) -> Int {
        if let activeTabId {
            RestoreTrace.log(
                "ActiveTabContent.body activeTab=\(activeTabId) viewRevision=\(viewRevision) tabPaneCount=\(tabPaneCount) registeredPaneCount=\(registeredPaneCount) hasTree=\(hasTree)"
            )
        } else {
            RestoreTrace.log(
                "ActiveTabContent.body empty activeTab=nil viewRevision=\(viewRevision)"
            )
        }
        return 0
    }

    var body: some View {
        // Read viewRevision so @Observable tracks it — triggers re-render after repair
        let currentViewRevision = store.viewRevision
        let activeTabId = store.activeTabId
        let tab = activeTabId.flatMap { store.tab($0) }
        let tree = tab.flatMap { viewRegistry.renderTree(for: $0.layout) }
        let registeredPaneCount = tab?.paneIds.filter { viewRegistry.view(for: $0) != nil }.count ?? 0
        let tabPaneCount = tab?.paneIds.count ?? 0
        // swiftlint:disable:next redundant_discardable_let
        let _ = Self.traceBody(
            activeTabId: activeTabId,
            viewRevision: currentViewRevision,
            tabPaneCount: tabPaneCount,
            registeredPaneCount: registeredPaneCount,
            hasTree: tree != nil
        )

        if let activeTabId, let tab, let tree {
            let renderInfo = SplitRenderInfo.compute(
                layout: tab.layout,
                minimizedPaneIds: tab.minimizedPaneIds
            )
            TerminalSplitContainer(
                tree: tree,
                tabId: activeTabId,
                activePaneId: tab.activePaneId,
                zoomedPaneId: tab.zoomedPaneId,
                minimizedPaneIds: tab.minimizedPaneIds,
                splitRenderInfo: renderInfo,
                action: action,
                onPersist: nil,
                shouldAcceptDrop: shouldAcceptDrop,
                onDrop: onDrop,
                store: store,
                repoCache: repoCache,
                viewRegistry: viewRegistry,
                appLifecycleStore: appLifecycleStore
            )
        }
        // Empty/no-tab state handled by AppKit (PaneTabViewController toggles NSView visibility)
    }
}
