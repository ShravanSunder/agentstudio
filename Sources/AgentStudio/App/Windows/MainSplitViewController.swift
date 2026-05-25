import AppKit
import SwiftUI

struct SidebarRootViewDependencies {
    let store: WorkspaceStore
    let uiState: UIStateAtom
    let sidebarCache: SidebarCacheAtom
    let inboxSidebarState: InboxSidebarStateAtom
    let inboxAtom: InboxNotificationAtom
    let prefsAtom: InboxNotificationPrefsAtom
    let repoCache: RepoCacheAtom
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
                inboxSidebarState: dependencies.inboxSidebarState,
                inboxAtom: dependencies.inboxAtom,
                prefsAtom: dependencies.prefsAtom,
                repoCache: dependencies.repoCache,
                onRefocusActivePane: dependencies.onRefocusActivePane,
                onDismissInbox: dependencies.onDismissInbox
            )
        )
    }

    private var sidebarHostingController: NSHostingController<AnyView>?
    private var paneTabViewController: PaneTabViewController?
    private var sidebarFocusTask: Task<Void, Never>?
    private var sidebarWidthRestoreTask: Task<Void, Never>?
    private var shouldExpandSidebarOnLoad = false
    private var shouldFocusSidebarWhenVisible = false
    private var didApplySidebarWidthAfterLayout = false

    // MARK: - Dependencies (injected)

    private let store: WorkspaceStore
    private let workspaceWindowId: UUID?
    private var repoCache: RepoCacheAtom { atom(\.repoCache) }
    private var uiState: UIStateAtom { atom(\.uiState) }
    private let actionExecutor: ActionExecutor
    private let applicationLifecycleMonitor: ApplicationLifecycleMonitor
    private let appLifecycleStore: AppLifecycleAtom
    private let windowLifecycleStore: WindowLifecycleAtom
    private let tabBarAdapter: TabBarAdapter
    private let viewRegistry: ViewRegistry
    private let inboxAtom: InboxNotificationAtom
    private let inboxPrefsAtom: InboxNotificationPrefsAtom
    private let inboxSidebarStateAtom: InboxSidebarStateAtom
    private let paneInboxPresenter: PaneInboxNotificationPresenter
    private let sidebarRootViewBuilder: SidebarRootViewBuilder
    private let closeTransitionCoordinator: PaneCloseTransitionCoordinator
    private let paneTabRegistersAsCommandHandler: Bool

    func syncVisibleTerminalGeometry(reason: StaticString) {
        paneTabViewController?.syncVisibleTerminalGeometry(reason: reason)
    }

    init(
        store: WorkspaceStore,
        workspaceWindowId: UUID? = nil,
        actionExecutor: ActionExecutor,
        applicationLifecycleMonitor: ApplicationLifecycleMonitor,
        appLifecycleStore: AppLifecycleAtom,
        windowLifecycleStore: WindowLifecycleAtom = atom(\.windowLifecycle),
        tabBarAdapter: TabBarAdapter,
        viewRegistry: ViewRegistry,
        inboxAtom: InboxNotificationAtom,
        inboxPrefsAtom: InboxNotificationPrefsAtom,
        inboxSidebarStateAtom: InboxSidebarStateAtom,
        paneInboxPresenter: PaneInboxNotificationPresenter,
        sidebarRootViewBuilder: @escaping SidebarRootViewBuilder = MainSplitViewController
            .defaultSidebarRootViewBuilder,
        closeTransitionCoordinator: PaneCloseTransitionCoordinator = PaneCloseTransitionCoordinator(),
        paneTabRegistersAsCommandHandler: Bool = true
    ) {
        self.store = store
        self.workspaceWindowId = workspaceWindowId
        self.actionExecutor = actionExecutor
        self.applicationLifecycleMonitor = applicationLifecycleMonitor
        self.appLifecycleStore = appLifecycleStore
        self.windowLifecycleStore = windowLifecycleStore
        self.tabBarAdapter = tabBarAdapter
        self.viewRegistry = viewRegistry
        self.inboxAtom = inboxAtom
        self.inboxPrefsAtom = inboxPrefsAtom
        self.inboxSidebarStateAtom = inboxSidebarStateAtom
        self.paneInboxPresenter = paneInboxPresenter
        self.sidebarRootViewBuilder = sidebarRootViewBuilder
        self.closeTransitionCoordinator = closeTransitionCoordinator
        self.paneTabRegistersAsCommandHandler = paneTabRegistersAsCommandHandler
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
            windowLifecycleStore: windowLifecycleStore,
            workspaceWindowId: workspaceWindowId,
            executor: actionExecutor,
            tabBarAdapter: tabBarAdapter,
            viewRegistry: viewRegistry,
            paneInboxPresentation: makePaneInboxPresentation(),
            closeTransitionCoordinator: closeTransitionCoordinator,
            registersAsCommandHandler: paneTabRegistersAsCommandHandler
        )
        self.paneTabViewController = paneTabVC

        // Configure split view
        splitView.isVertical = true
        splitView.dividerStyle = .thin

        // Create sidebar (SwiftUI via NSHostingController)
        let sidebarView = sidebarRootViewBuilder(
            SidebarRootViewDependencies(
                store: store,
                uiState: uiState,
                sidebarCache: atom(\.sidebarCache),
                inboxSidebarState: inboxSidebarStateAtom,
                inboxAtom: inboxAtom,
                prefsAtom: inboxPrefsAtom,
                repoCache: repoCache,
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
        sidebarItem.minimumThickness = 250
        sidebarItem.maximumThickness = 450
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

        scheduleSidebarWidthRestore()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        applySidebarWidthAfterLayoutIfNeeded()
        guard shouldFocusSidebarWhenVisible else { return }
        shouldFocusSidebarWhenVisible = false
        scheduleSidebarFocus()
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        applySidebarWidthAfterLayoutIfNeeded()
    }

    private func saveSidebarState() {
        let isCollapsed = splitViewItems.first?.isCollapsed ?? false
        if uiState.sidebarCollapsed != isCollapsed {
            uiState.setSidebarCollapsed(isCollapsed)
        }

        guard !isCollapsed, didApplySidebarWidthAfterLayout, let sidebarWidth = currentSidebarWidth() else { return }
        store.metadataAtom.setSidebarWidth(sidebarWidth)
    }

    private func applySidebarWidthAfterLayoutIfNeeded() {
        guard !didApplySidebarWidthAfterLayout else { return }
        guard splitViewItems.count >= 2 else { return }
        guard let sidebarItem = splitViewItems.first, !sidebarItem.isCollapsed else { return }
        guard splitView.bounds.width > 0 else { return }
        let sidebarWidth = clampedSidebarWidth(for: sidebarItem)
        let trailingMinimumThickness = splitViewItems.dropFirst().reduce(CGFloat(0)) { result, item in
            result + item.minimumThickness
        }
        guard splitView.bounds.width >= sidebarWidth + trailingMinimumThickness else { return }
        splitView.layoutSubtreeIfNeeded()
        splitView.setPosition(sidebarWidth, ofDividerAt: 0)
        splitView.adjustSubviews()
        splitView.layoutSubtreeIfNeeded()
        if let currentWidth = currentSidebarWidth(), abs(currentWidth - sidebarWidth) > 1 {
            splitView.setPosition(sidebarWidth + (sidebarWidth - currentWidth), ofDividerAt: 0)
            splitView.adjustSubviews()
            splitView.layoutSubtreeIfNeeded()
        }
        guard let currentWidth = currentSidebarWidth(), abs(currentWidth - sidebarWidth) <= 1 else { return }
        didApplySidebarWidthAfterLayout = true
    }

    private func scheduleSidebarWidthRestore() {
        sidebarWidthRestoreTask?.cancel()
        sidebarWidthRestoreTask = Task { @MainActor [weak self] in
            for _ in 0..<5 {
                guard let self, !Task.isCancelled, !self.didApplySidebarWidthAfterLayout else { return }
                await Task.yield()
                self.applySidebarWidthAfterLayoutIfNeeded()
            }
        }
    }

    private func clampedSidebarWidth(for sidebarItem: NSSplitViewItem) -> CGFloat {
        let sidebarWidth = min(
            max(store.metadataAtom.sidebarWidth, sidebarItem.minimumThickness),
            sidebarItem.maximumThickness
        )
        return sidebarWidth
    }

    private func currentSidebarWidth() -> CGFloat? {
        guard let sidebarView = splitViewItems.first?.viewController.view else { return nil }
        let width = sidebarView.frame.width
        guard width > 0 else { return nil }
        return width
    }

    func makePaneInboxPresentation() -> PaneInboxPresentation {
        let inbox = inboxAtom
        let presenter = paneInboxPresenter
        let paneInboxState = atom(\.paneInboxPresentationState)
        return PaneInboxPresentation(
            unreadCount: { paneIds in
                inbox.visiblePaneInboxUnreadCount(forPaneIds: paneIds)
            },
            clear: { _, paneIds in
                inbox.clearPaneInbox(paneIds: paneIds)
            },
            open: { parentPaneId, paneIds in
                presenter.open(parentPaneId: parentPaneId, paneIds: paneIds)
            },
            toggle: { parentPaneId, paneIds in
                presenter.toggle(parentPaneId: parentPaneId, paneIds: paneIds)
            },
            setPresented: { parentPaneId, paneIds, isPresented in
                presenter.setPresented(parentPaneId: parentPaneId, paneIds: paneIds, isPresented: isPresented)
            },
            pendingRequest: {
                presenter.request
            },
            clearRequest: { request in
                presenter.clearRequest(request)
            },
            popoverContent: { [weak self] parentPaneId, paneIds, onClear, onClose in
                AnyView(
                    PaneInboxNotificationPopover(
                        parentPaneId: parentPaneId,
                        workspaceWindowId: self?.workspaceWindowId,
                        paneIds: paneIds,
                        inboxAtom: inbox,
                        presentationAtom: paneInboxState,
                        onActivate: { notification in
                            presenter.recordRowActivation(notification: notification, paneIds: paneIds)
                        },
                        onFocusPane: { [weak self] paneId in
                            self?.paneTabViewController?.execute(.focusPane, target: paneId, targetType: .pane)
                        },
                        onClear: onClear,
                        onClose: onClose
                    )
                )
            },
            pruneFilterModes: { retainedParentPaneIds in
                paneInboxState.prune(retainingParentPaneIds: retainedParentPaneIds)
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
        didApplySidebarWidthAfterLayout = false
        sidebarItem.animator().isCollapsed = false
        Task { @MainActor [weak self] in
            await Task.yield()
            self?.applySidebarWidthAfterLayoutIfNeeded()
        }
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
            guard
                let focusTarget = sidebarHostingController?.view.descendantView(
                    matching: RepoExplorerView.focusTargetIdentifier
                )
            else {
                return false
            }
            return window.makeFirstResponder(focusTarget)
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
        // Contract: the sidebar filter command focuses the always-visible repo search
        // without silently flipping the user out of another sidebar surface.
        guard uiState.sidebarSurface == .repos else { return }
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
        sidebarWidthRestoreTask?.cancel()
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
