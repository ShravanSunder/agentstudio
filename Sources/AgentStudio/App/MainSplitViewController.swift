import AppKit
import SwiftUI
import os.log

private let sidebarLogger = Logger(subsystem: "com.agentstudio", category: "Sidebar")

/// Main split view controller with sidebar and terminal content area
class MainSplitViewController: NSSplitViewController {
    private var sidebarHostingController: NSHostingController<AnyView>?
    private var paneTabViewController: PaneTabViewController?
    private var notificationTasks: [Task<Void, Never>] = []
    private var willTerminateObserver: NSObjectProtocol?

    // MARK: - Dependencies (injected)

    private let store: WorkspaceStore
    private let repoCache: WorkspaceRepoCache
    private let uiStore: WorkspaceUIStore
    private let actionExecutor: ActionExecutor
    private let tabBarAdapter: TabBarAdapter
    private let viewRegistry: ViewRegistry

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
            executor: actionExecutor,
            tabBarAdapter: tabBarAdapter,
            viewRegistry: viewRegistry
        )
        self.paneTabViewController = paneTabVC

        let paneTabItem = NSSplitViewItem(viewController: paneTabVC)
        paneTabItem.minimumThickness = 400
        addSplitViewItem(paneTabItem)

        // Restore sidebar collapsed state
        if UserDefaults.standard.bool(forKey: Self.sidebarCollapsedKey) {
            sidebarItem.isCollapsed = true
        }

        setupNotificationObservers()
    }

    private func saveSidebarState() {
        let isCollapsed = splitViewItems.first?.isCollapsed ?? false
        UserDefaults.standard.set(isCollapsed, forKey: Self.sidebarCollapsedKey)
    }

    // MARK: - Notification Observers

    private func setupNotificationObservers() {
        notificationTasks.append(
            Task { [weak self] in
                guard let self else { return }
                let stream = await AppEventBus.shared.subscribe()
                for await event in stream {
                    guard !Task.isCancelled else { break }
                    switch event {
                    case .openWorktreeRequested(let worktreeId):
                        self.handleOpenWorktree(worktreeId: worktreeId)
                    case .closeTabRequested:
                        self.handleCloseTab()
                    case .selectTabAtIndex(let index):
                        self.handleSelectTab(index: index)
                    case .toggleSidebarRequested:
                        self.handleToggleSidebar()
                    case .addRepoRequested, .addFolderRequested:
                        self.expandSidebar()
                    case .addRepoAtPathRequested:
                        self.expandSidebar()
                    case .openNewTerminalRequested(let worktreeId):
                        self.handleOpenNewTerminal(worktreeId: worktreeId)
                    case .openWorktreeInPaneRequested(let worktreeId):
                        self.handleOpenWorktreeInPane(worktreeId: worktreeId)
                    case .filterSidebarRequested:
                        self.handleFilterSidebar()
                    default:
                        continue
                    }
                }
            })

        // willTerminateNotification is posted synchronously during app termination.
        // An async stream Task may not resume before the process exits, so use a
        // closure-based observer with queue: nil for synchronous inline execution.
        willTerminateObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            // Safety: NSApplication.willTerminateNotification is delivered on the main thread.
            // Assert that invariant before using MainActor.assumeIsolated.
            dispatchPrecondition(condition: .onQueue(.main))
            MainActor.assumeIsolated {
                self?.saveSidebarState()
            }
        }
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

    private func handleOpenWorktree(worktreeId: UUID) {
        guard let worktree = store.worktree(worktreeId),
            let repo = store.repo(containing: worktreeId)
        else {
            sidebarLogger.error("Invalid openWorktreeRequested payload for worktree \(worktreeId.uuidString)")
            return
        }
        paneTabViewController?.openTerminal(for: worktree, in: repo)
    }

    private func handleOpenNewTerminal(worktreeId: UUID) {
        guard let worktree = store.worktree(worktreeId),
            let repo = store.repo(containing: worktreeId)
        else {
            sidebarLogger.error("Invalid openNewTerminalRequested payload for worktree \(worktreeId.uuidString)")
            return
        }
        paneTabViewController?.openNewTerminal(for: worktree, in: repo)
    }

    private func handleOpenWorktreeInPane(worktreeId: UUID) {
        guard let worktree = store.worktree(worktreeId),
            let repo = store.repo(containing: worktreeId)
        else {
            sidebarLogger.error("Invalid openWorktreeInPaneRequested payload for worktree \(worktreeId.uuidString)")
            return
        }
        paneTabViewController?.openWorktreeInPane(for: worktree, in: repo)
    }

    private func handleCloseTab() {
        paneTabViewController?.closeActiveTab()
    }

    private func handleSelectTab(index: Int) {
        paneTabViewController?.selectTab(at: index)
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

    isolated deinit {
        for task in notificationTasks {
            task.cancel()
        }
        notificationTasks.removeAll()
        // Safe even if willTerminate fires after dealloc — the closure captures [weak self],
        // so the callback becomes a no-op once this instance is released.
        if let observer = willTerminateObserver {
            NotificationCenter.default.removeObserver(observer)
        }
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
