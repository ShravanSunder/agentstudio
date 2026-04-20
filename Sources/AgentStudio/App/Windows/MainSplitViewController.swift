import AppKit
import SwiftUI

/// Main split view controller with sidebar and terminal content area
class MainSplitViewController: NSSplitViewController {
    typealias SidebarRootViewBuilder =
        @MainActor (WorkspaceStore, UIStateAtom, @escaping () -> Void) -> AnyView

    private var sidebarHostingController: NSHostingController<AnyView>?
    private var paneTabViewController: PaneTabViewController?

    // MARK: - Dependencies (injected)

    private let store: WorkspaceStore
    private var repoCache: RepoCacheAtom { atom(\.repoCache) }
    private var uiState: UIStateAtom { atom(\.uiState) }
    private let actionExecutor: ActionExecutor
    private let applicationLifecycleMonitor: ApplicationLifecycleMonitor
    private let appLifecycleStore: AppLifecycleAtom
    private let tabBarAdapter: TabBarAdapter
    private let viewRegistry: ViewRegistry
    private let sidebarRootViewBuilder: SidebarRootViewBuilder

    func syncVisibleTerminalGeometry(reason: StaticString) {
        paneTabViewController?.syncVisibleTerminalGeometry(reason: reason)
    }

    init(
        store: WorkspaceStore,
        actionExecutor: ActionExecutor,
        applicationLifecycleMonitor: ApplicationLifecycleMonitor,
        appLifecycleStore: AppLifecycleAtom,
        tabBarAdapter: TabBarAdapter,
        viewRegistry: ViewRegistry,
        sidebarRootViewBuilder: @escaping SidebarRootViewBuilder = { store, uiState, onRefocusActivePane in
            AnyView(
                SidebarSurfaceHost(
                    store: store,
                    uiState: uiState,
                    onRefocusActivePane: onRefocusActivePane
                )
            )
        }
    ) {
        self.store = store
        self.actionExecutor = actionExecutor
        self.applicationLifecycleMonitor = applicationLifecycleMonitor
        self.appLifecycleStore = appLifecycleStore
        self.tabBarAdapter = tabBarAdapter
        self.viewRegistry = viewRegistry
        self.sidebarRootViewBuilder = sidebarRootViewBuilder
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not supported")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        let paneTabVC = PaneTabViewController(
            store: store,
            repoCache: repoCache,
            applicationLifecycleMonitor: applicationLifecycleMonitor,
            appLifecycleStore: appLifecycleStore,
            executor: actionExecutor,
            tabBarAdapter: tabBarAdapter,
            viewRegistry: viewRegistry
        )
        self.paneTabViewController = paneTabVC

        // Configure split view
        splitView.isVertical = true
        splitView.dividerStyle = .thin
        splitView.autosaveName = "MainSplitView"  // Persists divider position

        // Create sidebar (SwiftUI via NSHostingController)
        let sidebarView = sidebarRootViewBuilder(
            store,
            uiState,
            { [weak paneTabVC] in
                paneTabVC?.refocusActivePane()
            }
        )
        let sidebarHosting = NSHostingController(rootView: sidebarView)
        sidebarHosting.sizingOptions = []
        self.sidebarHostingController = sidebarHosting

        let sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebarHosting)
        sidebarItem.minimumThickness = 200
        sidebarItem.maximumThickness = 400
        sidebarItem.canCollapse = true
        sidebarItem.collapseBehavior = NSSplitViewItem.CollapseBehavior.preferResizingSiblingsWithFixedSplitView
        addSplitViewItem(sidebarItem)

        let paneTabItem = NSSplitViewItem(viewController: paneTabVC)
        paneTabItem.minimumThickness = 400
        addSplitViewItem(paneTabItem)

        // Restore sidebar collapsed state — force collapse if no repos
        if store.repositoryTopologyAtom.repos.isEmpty {
            sidebarItem.isCollapsed = true
        } else if uiState.sidebarCollapsed {
            sidebarItem.isCollapsed = true
        }
    }

    private func saveSidebarState() {
        let isCollapsed = splitViewItems.first?.isCollapsed ?? false
        uiState.setSidebarCollapsed(isCollapsed)
    }

    func savePersistentUIState() {
        saveSidebarState()
    }

    private func handleToggleSidebar() {
        toggleSidebar(nil)
        // Yield to the next MainActor turn so the sidebar item's collapsed state is updated.
        Task { @MainActor [weak self] in
            self?.saveSidebarState()
        }
    }

    private func handleFilterSidebar() {
        guard isSidebarCollapsed else { return }
        expandSidebar()
    }

    // MARK: - Sidebar State

    var isSidebarCollapsed: Bool {
        splitViewItems.first?.isCollapsed ?? false
    }

    func expandSidebar() {
        guard let sidebarItem = splitViewItems.first, sidebarItem.isCollapsed else { return }
        sidebarItem.animator().isCollapsed = false
        Task { @MainActor [weak self] in
            self?.saveSidebarState()
        }
    }

    func ensureSidebarVisible() {
        expandSidebar()
    }

    func focusSidebar() {
        guard isViewLoaded else { return }
        guard let window = view.window else { return }

        switch uiState.sidebarSurface {
        case .repos:
            _ = window.makeFirstResponder(sidebarHostingController?.view)
        case .inbox:
            guard
                let focusTarget = sidebarHostingController?.view.descendantView(
                    matching: InboxNotificationPlaceholderView.focusTargetIdentifier
                )
            else {
                return
            }
            _ = window.makeFirstResponder(focusTarget)
        }
    }

    func toggleSidebarFromCommand() {
        handleToggleSidebar()
    }

    func showSidebarFilter() {
        if uiState.isFilterVisible {
            uiState.setFilterVisible(false)
            refocusActivePane()
            return
        }

        expandSidebar()
        uiState.setFilterVisible(true)
    }

    func showInboxNotifications(commandBarIsKey: Bool) {
        ensureSidebarVisible()
        uiState.setSidebarSurface(.inbox)
        if !commandBarIsKey {
            Task { @MainActor [weak self] in
                await Task.yield()
                self?.focusSidebar()
            }
        }
    }

    func showWorktreeSidebar() {
        ensureSidebarVisible()
        uiState.setSidebarSurface(.repos)
    }

    func refocusActivePane() {
        paneTabViewController?.refocusActivePane()
    }

    func shutdown() {
        paneTabViewController?.shutdown()
    }

    // MARK: - Subtle Divider

    override func splitView(
        _ splitView: NSSplitView, effectiveRect proposedEffectiveRect: NSRect, forDrawnRect drawnRect: NSRect,
        ofDividerAt dividerIndex: Int
    ) -> NSRect {
        // Make the divider very thin/subtle
        var rect = proposedEffectiveRect
        rect.size.width = 1
        return rect
    }
    override func splitViewDidResizeSubviews(_ notification: Notification) {
        super.splitViewDidResizeSubviews(notification)
        RestoreTrace.log(
            "MainSplitViewController.splitViewDidResizeSubviews splitBounds=\(NSStringFromRect(splitView.bounds)) sidebarCollapsed=\(isSidebarCollapsed)"
        )
        saveSidebarState()
        paneTabViewController?.syncVisibleTerminalGeometry(reason: "splitViewDidResizeSubviews")
    }
}

extension NSView {
    fileprivate func descendantView(matching identifier: NSUserInterfaceItemIdentifier) -> NSView? {
        if self.identifier == identifier {
            return self
        }

        for subview in subviews {
            if let match = subview.descendantView(matching: identifier) {
                return match
            }
        }

        return nil
    }
}
