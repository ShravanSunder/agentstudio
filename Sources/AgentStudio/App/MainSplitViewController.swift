import AppKit
import SwiftUI

/// Main split view controller with sidebar and terminal content area
class MainSplitViewController: NSSplitViewController {
    private var sidebarHostingController: NSHostingController<AnyView>?
    private var paneTabViewController: PaneTabViewController?

    // MARK: - Dependencies (injected)

    private let store: WorkspaceStore
    private let repoCache: WorkspaceRepoCache
    private let uiStore: WorkspaceUIStore
    private let actionExecutor: ActionExecutor
    private let tabBarAdapter: TabBarAdapter
    private let viewRegistry: ViewRegistry
    var onRestoreHostReady: ((CGRect) -> Void)? {
        didSet {
            paneTabViewController?.onRestoreHostReady = onRestoreHostReady
        }
    }

    var terminalContainerBounds: CGRect? {
        paneTabViewController?.terminalContainerBounds
    }

    var isReadyForRestore: Bool {
        paneTabViewController?.isReadyForRestore ?? false
    }

    func armLaunchRestoreReadiness() {
        paneTabViewController?.armLaunchRestoreReadiness()
    }

    func syncVisibleTerminalGeometry(reason: StaticString) {
        paneTabViewController?.syncVisibleTerminalGeometry(reason: reason)
    }

    init(
        store: WorkspaceStore,
        repoCache: WorkspaceRepoCache,
        uiStore: WorkspaceUIStore,
        actionExecutor: ActionExecutor,
        tabBarAdapter: TabBarAdapter, viewRegistry: ViewRegistry
    ) {
        self.store = store
        self.repoCache = repoCache
        self.uiStore = uiStore
        self.actionExecutor = actionExecutor
        self.tabBarAdapter = tabBarAdapter
        self.viewRegistry = viewRegistry
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not supported")
    }

    private static let sidebarCollapsedKey = "sidebarCollapsed"

    override func viewDidLoad() {
        super.viewDidLoad()

        // Configure split view
        splitView.isVertical = true
        splitView.dividerStyle = .thin
        splitView.autosaveName = "MainSplitView"  // Persists divider position

        // Create sidebar (SwiftUI via NSHostingController)
        let sidebarView = SidebarViewWrapper(
            store: store,
            repoCache: repoCache,
            uiStore: uiStore
        )
        let sidebarHosting = NSHostingController(rootView: AnyView(sidebarView))
        sidebarHosting.sizingOptions = []
        self.sidebarHostingController = sidebarHosting

        let sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebarHosting)
        sidebarItem.minimumThickness = 200
        sidebarItem.maximumThickness = 400
        sidebarItem.canCollapse = true
        sidebarItem.collapseBehavior = .preferResizingSiblingsWithFixedSplitView
        addSplitViewItem(sidebarItem)

        // Create pane tab area (pure AppKit)
        let paneTabVC = PaneTabViewController(
            store: store,
            repoCache: repoCache,
            executor: actionExecutor,
            tabBarAdapter: tabBarAdapter,
            viewRegistry: viewRegistry
        )
        self.paneTabViewController = paneTabVC
        paneTabVC.onRestoreHostReady = onRestoreHostReady

        let paneTabItem = NSSplitViewItem(viewController: paneTabVC)
        paneTabItem.minimumThickness = 400
        addSplitViewItem(paneTabItem)

        // Restore sidebar collapsed state
        if UserDefaults.standard.bool(forKey: Self.sidebarCollapsedKey) {
            sidebarItem.isCollapsed = true
        }
    }

    private func saveSidebarState() {
        let isCollapsed = splitViewItems.first?.isCollapsed ?? false
        UserDefaults.standard.set(isCollapsed, forKey: Self.sidebarCollapsedKey)
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

    func toggleSidebarFromCommand() {
        handleToggleSidebar()
    }

    func showSidebarFilter() {
        if uiStore.isFilterVisible {
            uiStore.setFilterVisible(false)
            refocusActivePane()
            return
        }

        expandSidebar()
        uiStore.setFilterVisible(true)
    }

    func refocusActivePane() {
        paneTabViewController?.refocusActivePane()
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
        paneTabViewController?.syncVisibleTerminalGeometry(reason: "splitViewDidResizeSubviews")
    }
}

// MARK: - Sidebar View Wrapper

/// SwiftUI wrapper that bridges to the AppKit world.
/// Uses WorkspaceStore instead of SessionManager.
struct SidebarViewWrapper: View {
    let store: WorkspaceStore
    let repoCache: WorkspaceRepoCache
    let uiStore: WorkspaceUIStore

    var body: some View {
        RepoSidebarContentView(
            store: store,
            repoCache: repoCache,
            uiStore: uiStore
        )
    }
}
