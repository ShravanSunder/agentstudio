import AppKit
import SwiftUI

@MainActor
final class TabContentHostController {
    private let store: WorkspaceStore
    private let repoCache: RepoCacheAtom
    private let viewRegistry: ViewRegistry
    private let appLifecycleStore: AppLifecycleAtom
    private let closeTransitionCoordinator: PaneCloseTransitionCoordinator
    private let actionDispatcher: PaneActionDispatching
    private let executor: ActionExecutor
    private let paneInboxPresentation: PaneInboxPresentation?
    private let workspaceWindowId: UUID?
    private let terminalContainerProvider: @MainActor () -> NSView?
    private let rootViewProvider: @MainActor () -> NSView?
    private let tabBarHostingViewProvider: @MainActor () -> NSView?
    private let handlePaneFocusTrigger: @MainActor (PaneFocusTrigger) -> Void
    private let openPaneGitHub: @MainActor (UUID) -> Void

    private var tabContentHosts: [UUID: PersistentTabHostView] = [:]
    private var pendingVisibleViewRestoreTask: Task<Void, Never>?

    init(
        store: WorkspaceStore,
        repoCache: RepoCacheAtom,
        viewRegistry: ViewRegistry,
        appLifecycleStore: AppLifecycleAtom,
        closeTransitionCoordinator: PaneCloseTransitionCoordinator,
        actionDispatcher: PaneActionDispatching,
        executor: ActionExecutor,
        paneInboxPresentation: PaneInboxPresentation?,
        workspaceWindowId: UUID?,
        terminalContainerProvider: @escaping @MainActor () -> NSView?,
        rootViewProvider: @escaping @MainActor () -> NSView?,
        tabBarHostingViewProvider: @escaping @MainActor () -> NSView?,
        handlePaneFocusTrigger: @escaping @MainActor (PaneFocusTrigger) -> Void,
        openPaneGitHub: @escaping @MainActor (UUID) -> Void
    ) {
        self.store = store
        self.repoCache = repoCache
        self.viewRegistry = viewRegistry
        self.appLifecycleStore = appLifecycleStore
        self.closeTransitionCoordinator = closeTransitionCoordinator
        self.actionDispatcher = actionDispatcher
        self.executor = executor
        self.paneInboxPresentation = paneInboxPresentation
        self.workspaceWindowId = workspaceWindowId
        self.terminalContainerProvider = terminalContainerProvider
        self.rootViewProvider = rootViewProvider
        self.tabBarHostingViewProvider = tabBarHostingViewProvider
        self.handlePaneFocusTrigger = handlePaneFocusTrigger
        self.openPaneGitHub = openPaneGitHub
    }

    deinit {
        pendingVisibleViewRestoreTask?.cancel()
    }

    func shutdown() {
        pendingVisibleViewRestoreTask?.cancel()
        pendingVisibleViewRestoreTask = nil
    }

    func syncTabContentHosts() {
        guard let terminalContainer = terminalContainerProvider() else { return }

        for paneId in store.paneAtom.panes.keys {
            viewRegistry.ensureSlot(for: paneId)
        }

        let liveTabIds = Set(store.tabLayoutAtom.tabs.map(\.id))
        guard liveTabIds != Set(tabContentHosts.keys) else { return }

        for tab in store.tabLayoutAtom.tabs where tabContentHosts[tab.id] == nil {
            let host = buildTabContentHost(for: tab.id)
            terminalContainer.addSubview(host)
            NSLayoutConstraint.activate([
                host.topAnchor.constraint(equalTo: terminalContainer.topAnchor),
                host.leadingAnchor.constraint(equalTo: terminalContainer.leadingAnchor),
                host.trailingAnchor.constraint(equalTo: terminalContainer.trailingAnchor),
                host.bottomAnchor.constraint(equalTo: terminalContainer.bottomAnchor),
            ])
            tabContentHosts[tab.id] = host
        }

        for (tabId, host) in tabContentHosts where !liveTabIds.contains(tabId) {
            host.removeFromSuperview()
            tabContentHosts.removeValue(forKey: tabId)
        }
    }

    func updateVisibleTabHost() {
        let activeTabId = store.tabLayoutAtom.activeTabId
        for (tabId, host) in tabContentHosts {
            host.isHidden = tabId != activeTabId
        }
    }

    func handleTerminalContainerBoundsChanged(reason: StaticString) {
        let terminalContainerBounds = terminalContainerProvider()?.bounds ?? .zero
        RestoreTrace.log(
            "PaneTabViewController terminalContainerBoundsChanged reason=\(reason) bounds=\(NSStringFromRect(terminalContainerBounds))"
        )
        RestoreTrace.log(geometryHierarchySnapshot(reason: reason))
        scheduleVisibleViewRestoreAfterLayout(reason: reason)
    }

    func syncVisibleTerminalGeometry(reason: StaticString) {
        guard let activeTabId = store.tabLayoutAtom.activeTabId else { return }
        let visibleTerminalViews =
            store.tabLayoutAtom.tab(activeTabId)?.paneIds.compactMap {
                viewRegistry.terminalView(for: $0)
            }.filter { terminalView in
                terminalView.window != nil && !terminalView.isHidden
            } ?? []
        guard !visibleTerminalViews.isEmpty else { return }
        RestoreTrace.log(
            "PaneTabViewController.syncVisibleTerminalGeometry reason=\(reason) count=\(visibleTerminalViews.count)"
        )
        for terminalView in visibleTerminalViews {
            terminalView.forceGeometrySync(reason: reason)
        }
    }

    func geometryHierarchySnapshot(reason: StaticString) -> String {
        let rootView = rootViewProvider()
        let terminalContainer = terminalContainerProvider()
        let tabBarHostingView = tabBarHostingViewProvider()
        let rootFrame = rootView.map { NSStringFromRect($0.frame) } ?? "nil"
        let rootBounds = rootView.map { NSStringFromRect($0.bounds) } ?? "nil"
        let terminalFrame = terminalContainer.map { NSStringFromRect($0.frame) } ?? "nil"
        let terminalBounds = terminalContainer.map { NSStringFromRect($0.bounds) } ?? "nil"
        let hostingFrame = activeTabHost().map { NSStringFromRect($0.frame) } ?? "nil"
        let hostingBounds = activeTabHost().map { NSStringFromRect($0.bounds) } ?? "nil"
        let tabBarFrame = tabBarHostingView.map { NSStringFromRect($0.frame) } ?? "nil"
        return
            "PaneTabViewController.geometry reason=\(reason) viewFrame=\(rootFrame) viewBounds=\(rootBounds) terminalFrame=\(terminalFrame) terminalBounds=\(terminalBounds) hostingFrame=\(hostingFrame) hostingBounds=\(hostingBounds) tabBarFrame=\(tabBarFrame)"
    }

    func activeTabHost() -> PersistentTabHostView? {
        guard let activeTabId = store.tabLayoutAtom.activeTabId else { return nil }
        return tabContentHosts[activeTabId]
    }

    func tabHostViewForTesting(tabId: UUID) -> NSView? {
        tabContentHosts[tabId]
    }

    private func buildTabContentHost(for tabId: UUID) -> PersistentTabHostView {
        let contentView = SingleTabContent(
            tabId: tabId,
            store: store,
            repoCache: repoCache,
            viewRegistry: viewRegistry,
            appLifecycleStore: appLifecycleStore,
            closeTransitionCoordinator: closeTransitionCoordinator,
            actionDispatcher: actionDispatcher,
            onPaneFocusTrigger: { [weak self] trigger in
                self?.handlePaneFocusTrigger(trigger)
            },
            paneInboxPresentation: paneInboxPresentation,
            onOpenPaneGitHub: { [weak self] paneId in
                self?.openPaneGitHub(paneId)
            },
            notificationCountForWorktree: { worktreeId in
                WorkspaceNotificationCountProjection.unreadCount(
                    worktreeId: worktreeId,
                    inboxAtom: atom(\.inboxNotification)
                )
            },
            workspaceWindowId: workspaceWindowId
        )

        return PersistentTabHostView(tabId: tabId, rootView: contentView)
    }

    private func scheduleVisibleViewRestoreAfterLayout(reason: StaticString) {
        pendingVisibleViewRestoreTask?.cancel()
        pendingVisibleViewRestoreTask = Task { @MainActor [weak self] in
            await Task.yield()
            guard !Task.isCancelled, let self else { return }
            self.executor.restoreVisibleViewsForActiveTabIfNeeded()
            self.syncVisibleTerminalGeometry(reason: reason)
            self.pendingVisibleViewRestoreTask = nil
        }
    }
}
