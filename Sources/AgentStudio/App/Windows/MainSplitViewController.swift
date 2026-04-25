import AppKit
import SwiftUI

struct SidebarRootViewDependencies {
    let store: WorkspaceStore
    let uiState: UIStateAtom
    let sidebarCache: SidebarCacheAtom
    let inboxFilterDraft: InboxFilterDraftAtom
    let inboxAtom: InboxNotificationAtom
    let prefsAtom: InboxNotificationPrefsAtom
    let onRefocusActivePane: () -> Void
    let onDismissInbox: @MainActor @Sendable () -> Void
}

/// Main split view controller with sidebar and terminal content area
class MainSplitViewController: NSSplitViewController {
    typealias SidebarRootViewBuilder = @MainActor (SidebarRootViewDependencies) -> AnyView
    private static let inboxFocusRetryTurns = 20

    @MainActor
    private static func defaultSidebarRootViewBuilder(
        dependencies: SidebarRootViewDependencies
    ) -> AnyView {
        AnyView(
            SidebarSurfaceHost(
                store: dependencies.store,
                uiState: dependencies.uiState,
                sidebarCache: dependencies.sidebarCache,
                inboxFilterDraft: dependencies.inboxFilterDraft,
                inboxAtom: dependencies.inboxAtom,
                prefsAtom: dependencies.prefsAtom,
                onRefocusActivePane: dependencies.onRefocusActivePane,
                onDismissInbox: dependencies.onDismissInbox
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
    private let inboxAtom: InboxNotificationAtom
    private let inboxPrefsAtom: InboxNotificationPrefsAtom
    private let drawerInboxPresenter: InboxNotificationDrawerPresenter
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
        inboxAtom: InboxNotificationAtom,
        inboxPrefsAtom: InboxNotificationPrefsAtom,
        drawerInboxPresenter: InboxNotificationDrawerPresenter,
        sidebarRootViewBuilder: @escaping SidebarRootViewBuilder = MainSplitViewController.defaultSidebarRootViewBuilder
    ) {
        self.store = store
        self.actionExecutor = actionExecutor
        self.applicationLifecycleMonitor = applicationLifecycleMonitor
        self.appLifecycleStore = appLifecycleStore
        self.tabBarAdapter = tabBarAdapter
        self.viewRegistry = viewRegistry
        self.inboxAtom = inboxAtom
        self.inboxPrefsAtom = inboxPrefsAtom
        self.drawerInboxPresenter = drawerInboxPresenter
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
            viewRegistry: viewRegistry,
            drawerInboxPresentation: makeDrawerInboxPresentation()
        )
        self.paneTabViewController = paneTabVC

        // Configure split view
        splitView.isVertical = true
        splitView.dividerStyle = .thin
        splitView.autosaveName = "MainSplitView"  // Persists divider position

        // Create sidebar (SwiftUI via NSHostingController)
        let sidebarView = sidebarRootViewBuilder(
            SidebarRootViewDependencies(
                store: store,
                uiState: uiState,
                sidebarCache: atom(\.sidebarCache),
                inboxFilterDraft: atom(\.inboxFilterDraft),
                inboxAtom: inboxAtom,
                prefsAtom: inboxPrefsAtom,
                onRefocusActivePane: { [weak paneTabVC] in
                    paneTabVC?.refocusActivePane()
                },
                onDismissInbox: { [weak self] in
                    self?.collapseSidebar()
                    self?.refocusActivePane()
                }
            )
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

        // Pre-load collapse/expand requests only update atoms. Once AppKit has
        // splitViewItems, realize the persisted presentation exactly once here.
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

    private func makeDrawerInboxPresentation() -> DrawerInboxPresentation {
        DrawerInboxPresentation(
            unreadCount: { [inboxAtom] drawerPaneIds in
                inboxAtom.unreadCount(forDrawerPaneIds: drawerPaneIds)
            },
            open: { [drawerInboxPresenter] parentPaneId, drawerPaneIds in
                drawerInboxPresenter.open(parentPaneId: parentPaneId, drawerPaneIds: drawerPaneIds)
            },
            pendingRequest: { [drawerInboxPresenter] in
                drawerInboxPresenter.request
            },
            clearRequest: { [drawerInboxPresenter] request in
                drawerInboxPresenter.clearRequest(request)
            },
            popoverContent: { [inboxAtom] drawerPaneIds, onClose in
                AnyView(
                    InboxNotificationDrawerPopover(
                        drawerPaneIds: drawerPaneIds,
                        inboxAtom: inboxAtom,
                        dispatcher: CommandDispatcher.shared,
                        onClose: onClose
                    )
                )
            }
        )
    }

    func savePersistentUIState() {
        saveSidebarState()
    }

    private func scheduleSaveSidebarState() {
        Task { @MainActor [weak self] in
            self?.saveSidebarState()
        }
    }

    private func handleToggleSidebar() {
        toggleSidebar(nil)
        // Contract: AppKit flips the split item collapsed flag asynchronously while
        // processing toggleSidebar(_:). Save on the next turn so UIState observes
        // the post-toggle truth instead of the stale pre-toggle value.
        scheduleSaveSidebarState()
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
        scheduleSaveSidebarState()
    }

    func ensureSidebarVisible() {
        expandSidebar()
    }

    func collapseSidebar() {
        guard isViewLoaded else {
            // Contract: restore and composite commands may ask for collapse before
            // splitViewItems exist. Clear the pending expansion bit here so the
            // last pre-load intent wins once viewDidLoad realizes shell state.
            shouldExpandSidebarOnLoad = false
            uiState.setSidebarCollapsed(true)
            uiState.setSidebarHasFocus(false)
            return
        }
        guard let sidebarItem = splitViewItems.first, !sidebarItem.isCollapsed else { return }
        sidebarItem.animator().isCollapsed = true
        uiState.setSidebarHasFocus(false)
        scheduleSaveSidebarState()
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
                    matching: InboxNotificationSidebarView.focusTargetIdentifier
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
        // Why: until inbox has its own search affordance, ⌘F should preserve the
        // current surface instead of silently flipping the user back to repos.
        guard uiState.sidebarSurface == .repos else { return }
        if uiState.isFilterVisible {
            uiState.setFilterVisible(false)
            refocusActivePane()
            return
        }

        expandSidebar()
        uiState.setFilterVisible(true)
    }

    func showInboxNotifications(commandBarIsKey: Bool) {
        // Contract: a visible inbox means the user is already on the requested
        // surface, so the second invocation is a close toggle rather than a no-op.
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
        // Contract: keep ⌘S symmetric with ⌘I. A second press on the visible
        // requested surface closes the sidebar instead of reasserting state.
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
