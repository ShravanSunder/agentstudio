import AppKit
import SwiftUI

/// Main split view controller with sidebar and terminal content area
class MainSplitViewController: NSSplitViewController {
    typealias SidebarRootViewBuilder =
        @MainActor (WorkspaceStore, UIStateAtom, @escaping () -> Void, @escaping @MainActor @Sendable () -> Void) ->
        AnyView
    private static let inboxFocusRetryTurns = 20

    @MainActor
    private static func defaultSidebarRootViewBuilder(
        store: WorkspaceStore,
        uiState: UIStateAtom,
        onRefocusActivePane: @escaping () -> Void,
        onDismissInbox: @escaping @MainActor @Sendable () -> Void
    ) -> AnyView {
        AnyView(
            SidebarSurfaceHost(
                store: store,
                uiState: uiState,
                onRefocusActivePane: onRefocusActivePane,
                onDismissInbox: onDismissInbox
            )
        )
    }

    private var sidebarHostingController: NSHostingController<AnyView>?
    private var paneTabViewController: PaneTabViewController?
    private var sidebarFocusTask: Task<Void, Never>?
    private var shouldExpandSidebarOnLoad = false
    private var shouldFocusSidebarWhenVisible = false

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
        sidebarRootViewBuilder: @escaping SidebarRootViewBuilder = Self.defaultSidebarRootViewBuilder
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
            },
            { [weak self] in
                self?.collapseSidebar()
                self?.refocusActivePane()
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
        if shouldExpandSidebarOnLoad {
            sidebarItem.isCollapsed = false
            shouldExpandSidebarOnLoad = false
        } else if store.repositoryTopologyAtom.repos.isEmpty {
            sidebarItem.isCollapsed = true
        } else if uiState.sidebarCollapsed {
            sidebarItem.isCollapsed = true
        }
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        guard shouldFocusSidebarWhenVisible else { return }
        shouldFocusSidebarWhenVisible = false
        scheduleSidebarFocus()
    }

    private func saveSidebarState() {
        let isCollapsed = splitViewItems.first?.isCollapsed ?? false
        guard uiState.sidebarCollapsed != isCollapsed else { return }
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
        guard isViewLoaded else {
            shouldExpandSidebarOnLoad = true
            uiState.setSidebarCollapsed(false)
            return
        }
        guard let sidebarItem = splitViewItems.first, sidebarItem.isCollapsed else { return }
        sidebarItem.animator().isCollapsed = false
        Task { @MainActor [weak self] in
            self?.saveSidebarState()
        }
    }

    func ensureSidebarVisible() {
        expandSidebar()
    }

    func collapseSidebar() {
        guard isViewLoaded else {
            shouldExpandSidebarOnLoad = false
            uiState.setSidebarCollapsed(true)
            uiState.setSidebarHasFocus(false)
            return
        }
        guard let sidebarItem = splitViewItems.first, !sidebarItem.isCollapsed else { return }
        sidebarItem.animator().isCollapsed = true
        uiState.setSidebarHasFocus(false)
        Task { @MainActor [weak self] in
            self?.saveSidebarState()
        }
    }

    @discardableResult
    func focusSidebar() -> Bool {
        guard isViewLoaded else { return false }
        guard let window = view.window else { return false }
        window.makeKey()

        switch uiState.sidebarSurface {
        case .repos:
            return window.makeFirstResponder(sidebarHostingController?.view)
        case .inbox:
            guard
                let focusTarget = sidebarHostingController?.view.descendantView(
                    matching: InboxNotificationPlaceholderView.focusTargetIdentifier
                )
            else {
                return false
            }
            return window.makeFirstResponder(focusTarget)
        }
    }

    private func scheduleSidebarFocus() {
        sidebarFocusTask?.cancel()
        sidebarFocusTask = Task { @MainActor [weak self] in
            guard let self else { return }
            for _ in 0..<Self.inboxFocusRetryTurns {
                guard !Task.isCancelled else { return }
                if self.focusSidebar() {
                    return
                }
                await Task.yield()
            }
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

        if uiState.sidebarSurface == .inbox {
            uiState.setSidebarSurface(.repos)
        }
        expandSidebar()
        uiState.setFilterVisible(true)
    }

    func showInboxNotifications(commandBarIsKey: Bool) {
        if !isSidebarCollapsed && uiState.sidebarSurface == .inbox {
            collapseSidebar()
            return
        }
        ensureSidebarVisible()
        uiState.setSidebarSurface(.inbox)
        if commandBarIsKey {
            sidebarFocusTask?.cancel()
            shouldFocusSidebarWhenVisible = false
            uiState.setSidebarHasFocus(false)
            return
        }
        guard isViewLoaded, view.window != nil else {
            shouldFocusSidebarWhenVisible = true
            return
        }
        scheduleSidebarFocus()
    }

    func showWorktreeSidebar() {
        if !isSidebarCollapsed && uiState.sidebarSurface == .repos {
            collapseSidebar()
            return
        }
        sidebarFocusTask?.cancel()
        shouldFocusSidebarWhenVisible = false
        ensureSidebarVisible()
        uiState.setSidebarSurface(.repos)
    }

    func refocusActivePane() {
        paneTabViewController?.refocusActivePane()
    }

    func shutdown() {
        sidebarFocusTask?.cancel()
        shouldFocusSidebarWhenVisible = false
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
