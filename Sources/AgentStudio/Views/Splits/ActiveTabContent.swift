import SwiftUI

/// SwiftUI root for the main terminal content area.
///
/// Hosted by TerminalTabViewController's `splitHostingView` (NSHostingView).
/// Reads the active tab from WorkspaceStore via @Observable property tracking
/// and renders `TerminalSplitContainer` for that tab. Re-renders automatically
/// when any accessed store property changes — no manual invalidation needed.
///
/// See docs/architecture/appkit_swiftui_architecture.md for the hosting pattern.
struct ActiveTabContent: View {
    let store: WorkspaceStore
    let viewRegistry: ViewRegistry
    let action: (PaneAction) -> Void
    let shouldAcceptDrop: (UUID, DropZone) -> Bool
    let onDrop: (SplitDropPayload, UUID, DropZone) -> Void

    var body: some View {
        // Read viewRevision so @Observable tracks it — triggers re-render after repair
        // swiftlint:disable:next redundant_discardable_let
        let _ = store.viewRevision  // swift-format:ignore

        if let activeTabId = store.activeTabId,
            let tab = store.tab(activeTabId),
            let tree = viewRegistry.renderTree(for: tab.layout)
        {
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
                viewRegistry: viewRegistry
            )
        }
        // Empty/no-tab state handled by AppKit (TTVC toggles NSView visibility)
    }
}
