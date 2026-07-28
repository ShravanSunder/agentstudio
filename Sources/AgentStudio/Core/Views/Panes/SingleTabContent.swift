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
    let onFocusPane: (UUID) -> Void
    let paneInboxPresentation: PaneInboxPresentation?
    let onOpenPaneGitHub: (UUID) -> Void
    let onToggleZoom: (UUID?) -> Void
    let notificationCountForWorktree: (UUID) -> Int
    let workspaceWindowId: UUID?
    let paneSurfaceToolbarPresentation: (UUID) -> PaneSurfaceToolbarPresentation
    let zoomPaneSurfaceToolbarPresentation: (UUID, ZoomViewerPresentation) -> PaneSurfaceToolbarPresentation

    init(
        tabId: UUID,
        store: WorkspaceStore,
        repoCache: RepoCacheAtom,
        viewRegistry: ViewRegistry,
        appLifecycleStore: AppLifecycleAtom,
        closeTransitionCoordinator: PaneCloseTransitionCoordinator,
        actionDispatcher: PaneActionDispatching,
        onPaneFocusTrigger: @escaping PaneFocusTriggerHandler,
        onFocusPane: @escaping (UUID) -> Void,
        paneInboxPresentation: PaneInboxPresentation? = nil,
        onOpenPaneGitHub: @escaping (UUID) -> Void,
        onToggleZoom: @escaping (UUID?) -> Void = { _ in },
        notificationCountForWorktree: @escaping (UUID) -> Int = { _ in 0 },
        workspaceWindowId: UUID? = nil,
        paneSurfaceToolbarPresentation: @escaping (UUID) -> PaneSurfaceToolbarPresentation,
        zoomPaneSurfaceToolbarPresentation:
            @escaping (UUID, ZoomViewerPresentation) -> PaneSurfaceToolbarPresentation
    ) {
        self.tabId = tabId
        self.store = store
        self.repoCache = repoCache
        self.viewRegistry = viewRegistry
        self.appLifecycleStore = appLifecycleStore
        self.closeTransitionCoordinator = closeTransitionCoordinator
        self.actionDispatcher = actionDispatcher
        self.onPaneFocusTrigger = onPaneFocusTrigger
        self.onFocusPane = onFocusPane
        self.paneInboxPresentation = paneInboxPresentation
        self.onOpenPaneGitHub = onOpenPaneGitHub
        self.onToggleZoom = onToggleZoom
        self.notificationCountForWorktree = notificationCountForWorktree
        self.workspaceWindowId = workspaceWindowId
        self.paneSurfaceToolbarPresentation = paneSurfaceToolbarPresentation
        self.zoomPaneSurfaceToolbarPresentation = zoomPaneSurfaceToolbarPresentation
    }

    private static func traceMissingTab(tabId: UUID) -> Int {
        RestoreTrace.log("SingleTabContent.body missingTab tabId=\(tabId)")
        return 0
    }

    var body: some View {
        let workspaceTab = WorkspaceTabLayoutDerived(
            shellAtom: store.tabShellAtom,
            arrangementAtom: store.tabArrangementAtom
        )
        let tab = workspaceTab.tab(tabId)
        // swiftlint:disable:next redundant_discardable_let
        let _ = tab == nil ? Self.traceMissingTab(tabId: tabId) : 0
        if let tab {
            if let zoomPresentation = store.panePresentationAtom.zoomPresentation(forTab: tabId) {
                zoomContent(
                    presentation: zoomPresentation,
                    tab: tab
                )
                .background(AppStyles.Shell.PaneChrome.background)
                .transition(.identity)
            } else {
                FlatTabStripContainer(
                    layout: tab.layout,
                    tabId: tabId,
                    activePaneId: tab.activePaneId,
                    minimizedPaneIds: tab.activeMinimizedPaneIds,
                    visiblePaneIds: atom(\.arrangementView).activeVisiblePaneIds(forTab: tabId),
                    closeTransitionCoordinator: closeTransitionCoordinator,
                    actionDispatcher: actionDispatcher,
                    onPaneFocusTrigger: onPaneFocusTrigger,
                    onFocusPane: onFocusPane,
                    store: store,
                    repoCache: repoCache,
                    viewRegistry: viewRegistry,
                    appLifecycleStore: appLifecycleStore,
                    paneInboxPresentation: paneInboxPresentation,
                    onOpenPaneGitHub: onOpenPaneGitHub,
                    onToggleZoom: onToggleZoom,
                    notificationCountForWorktree: notificationCountForWorktree,
                    workspaceWindowId: workspaceWindowId,
                    paneSurfaceToolbarPresentation: paneSurfaceToolbarPresentation
                )
                .background(AppStyles.Shell.PaneChrome.background)
                .transition(.identity)
            }
        }
    }

    @ViewBuilder
    private func zoomContent(
        presentation: ZoomPresentation,
        tab: Tab
    ) -> some View {
        let parentToolbar = zoomPaneSurfaceToolbarPresentation(
            presentation.sourcePaneId,
            presentation.viewerPresentation
        )
        if let renderState = ZoomPresentationContainer.resolveRenderState(
            presentation: presentation,
            viewRegistry: viewRegistry,
            parentToolbar: parentToolbar
        ) {
            let ordinalMap = PaneOrdinalMap(orderedPaneIds: tab.layout.paneIds)
            let isSplit = renderState.children.count > 1
            let sourceContent = zoomChildContent(
                renderState.children[0],
                sourcePaneId: presentation.sourcePaneId,
                isSplit: isSplit,
                ordinalMap: ordinalMap
            )
            let companionContent = renderState.children.dropFirst().first.map {
                zoomChildContent(
                    $0,
                    sourcePaneId: presentation.sourcePaneId,
                    isSplit: isSplit,
                    ordinalMap: ordinalMap
                )
            }

            ZoomPresentationContainer(
                tabId: tabId,
                sourcePaneId: presentation.sourcePaneId,
                sourceOrdinal: ordinalMap.ordinal(forPaneId: presentation.sourcePaneId),
                sourceContent: sourceContent,
                companionContent: companionContent,
                isCompanionVisible: renderState.isCompanionVisible,
                parentToolbarPresentation: renderState.parentToolbar,
                splitRatio: presentation.transientSplitRatio ?? 0.5,
                store: store,
                repoCache: repoCache,
                appLifecycleStore: appLifecycleStore,
                closeTransitionCoordinator: closeTransitionCoordinator,
                paneInboxPresentation: paneInboxPresentation,
                workspaceWindowId: workspaceWindowId,
                actionDispatcher: actionDispatcher,
                onPaneFocusTrigger: onPaneFocusTrigger,
                onFocusPane: onFocusPane,
                onOpenPaneGitHub: onOpenPaneGitHub,
                notificationCountForWorktree: notificationCountForWorktree,
                viewRegistry: viewRegistry,
                surfaceId: "zoom:\(tabId)",
                renderedPaneIds: Set(renderState.children.map(\.paneId))
            )
            .id(presentation.sourcePaneId)
        } else {
            Color.clear
        }
    }

    private func zoomChildContent(
        _ child: ZoomPresentationChild,
        sourcePaneId: UUID,
        isSplit: Bool,
        ordinalMap: PaneOrdinalMap
    ) -> AnyView {
        guard let paneHost = child.paneSlot.host else {
            return AnyView(Color.clear)
        }

        return AnyView(
            PaneLeafContainer(
                paneHost: paneHost,
                tabId: tabId,
                isActive: child.paneId == sourcePaneId,
                isSplit: isSplit,
                isSplitResizing: false,
                store: store,
                repoCache: repoCache,
                closeTransitionCoordinator: closeTransitionCoordinator,
                actionDispatcher: actionDispatcher,
                onPaneFocusTrigger: onPaneFocusTrigger,
                onOpenPaneGitHub: onOpenPaneGitHub,
                notificationCountForWorktree: notificationCountForWorktree,
                dropTargetCoordinateSpace: "tabContainer",
                paneInboxPresentation: child.paneId == sourcePaneId ? paneInboxPresentation : nil,
                ordinal: ordinalMap.ordinal(forPaneId: child.paneId),
                workspaceWindowId: workspaceWindowId,
                toolbarPresentation: child.toolbarPresentation,
                managementChromePresentation: .zoomChild
            )
        )
    }
}
