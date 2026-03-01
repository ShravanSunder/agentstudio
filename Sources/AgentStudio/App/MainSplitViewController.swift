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
    private let cacheStore: WorkspaceCacheStore
    private let uiStore: WorkspaceUIStore
    private let actionExecutor: ActionExecutor
    private let tabBarAdapter: TabBarAdapter
    private let viewRegistry: ViewRegistry

    init(
        store: WorkspaceStore,
        cacheStore: WorkspaceCacheStore,
        uiStore: WorkspaceUIStore,
        actionExecutor: ActionExecutor,
        tabBarAdapter: TabBarAdapter, viewRegistry: ViewRegistry
    ) {
        self.store = store
        self.cacheStore = cacheStore
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
            cacheStore: cacheStore,
            uiStore: uiStore
        )
        let sidebarHosting = NSHostingController(rootView: AnyView(sidebarView))
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
    let cacheStore: WorkspaceCacheStore
    let uiStore: WorkspaceUIStore

    var body: some View {
        RepoSidebarContentView(
            store: store,
            cacheStore: cacheStore,
            uiStore: uiStore
        )
    }
}

/// The actual sidebar content
struct SidebarContentView: View {
    let store: WorkspaceStore
    @State private var expandedRepos: Set<UUID> = Self.loadExpandedRepos()
    @State private var filterText: String = ""
    @State private var debouncedQuery: String = ""
    @State private var isFilterVisible: Bool = false
    @FocusState private var isFilterFocused: Bool

    private static let filterDebounceMilliseconds = 25
    private static let expandedReposKey = "expandedRepos"

    private static func loadExpandedRepos() -> Set<UUID> {
        guard let strings = UserDefaults.standard.stringArray(forKey: expandedReposKey) else { return [] }
        return Set(strings.compactMap { UUID(uuidString: $0) })
    }

    private func saveExpandedRepos() {
        let strings = expandedRepos.map(\.uuidString)
        UserDefaults.standard.set(strings, forKey: Self.expandedReposKey)
    }

    private var filteredRepos: [Repo] {
        SidebarFilter.filter(repos: store.repos, query: debouncedQuery)
    }

    /// Whether a filter is actively narrowing results.
    private var isFiltering: Bool {
        !debouncedQuery.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search / filter bar (toggle-able)
            if isFilterVisible {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: AppStyle.textXs))
                        .foregroundStyle(.tertiary)

                    TextField("Filter...", text: $filterText)
                        .textFieldStyle(.plain)
                        .font(.system(size: AppStyle.textSm))
                        .foregroundStyle(.primary)
                        .focused($isFilterFocused)
                        .onExitCommand {
                            hideFilter()
                        }
                        .onKeyPress(.downArrow) {
                            // Transfer focus from filter to the list for keyboard navigation
                            isFilterFocused = false
                            return .handled
                        }

                    if !filterText.isEmpty {
                        Button {
                            filterText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: AppStyle.textSm))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Clear filter")
                        .transition(.opacity.animation(.easeOut(duration: 0.1)))
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.primary.opacity(0.06))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.primary.opacity(0.1), lineWidth: 1)
                )
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            // Main list content
            if isFiltering && filteredRepos.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: AppStyle.text2xl))
                        .foregroundStyle(.secondary)
                        .opacity(0.5)

                    Text("No results")
                        .font(.system(size: AppStyle.textSm, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(.opacity.animation(.easeOut(duration: 0.12)))
            } else {
                List {
                    ForEach(filteredRepos) { repo in
                        DisclosureGroup(
                            isExpanded: Binding(
                                get: {
                                    isFiltering || expandedRepos.contains(repo.id)
                                },
                                set: { isExpanded in
                                    if isExpanded {
                                        expandedRepos.insert(repo.id)
                                    } else {
                                        expandedRepos.remove(repo.id)
                                    }
                                    saveExpandedRepos()
                                }
                            )
                        ) {
                            ForEach(repo.worktrees) { worktree in
                                WorktreeRowView(
                                    worktree: worktree,
                                    onOpen: {
                                        openWorktree(worktree, in: repo)
                                    },
                                    onOpenNew: {
                                        openNewTerminal(worktree, in: repo)
                                    },
                                    onOpenInPane: {
                                        openWorktreeInPane(worktree, in: repo)
                                    }
                                )
                                .listRowInsets(EdgeInsets(top: 0, leading: 2, bottom: 0, trailing: 0))
                            }
                        } label: {
                            RepoRowView(
                                repo: repo,
                                onRefresh: {
                                    requestWorktreeRefresh()
                                },
                                onRemove: {
                                    postAppEvent(.removeRepoRequested(repoId: repo.id))
                                }
                            )
                        }
                        .listRowInsets(EdgeInsets(top: 0, leading: 2, bottom: 0, trailing: 0))
                    }
                }
                .listStyle(.sidebar)
                .transition(.opacity.animation(.easeOut(duration: 0.12)))
            }

        }
        .frame(minWidth: 200)
        .background(Color(nsColor: .windowBackgroundColor))
        // Subtle shadow on right edge only
        .shadow(color: .black.opacity(0.2), radius: 4, x: 2, y: 0)
        .task {
            let stream = await AppEventBus.shared.subscribe()
            for await event in stream {
                switch event {
                case .addRepoRequested:
                    addRepo()
                case .refreshWorktreesRequested:
                    continue
                case .filterSidebarRequested:
                    withAnimation(.easeOut(duration: 0.15)) {
                        if isFilterVisible {
                            hideFilter()
                        } else {
                            isFilterVisible = true
                        }
                    }
                    // Focus after animation starts
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(50))
                        isFilterFocused = true
                    }
                default:
                    continue
                }
            }
        }
        .onDisappear {
            debounceTask?.cancel()
        }
        .onChange(of: filterText) { _, newValue in
            let trimmed = newValue.trimmingCharacters(in: .whitespaces)
            debounceTask?.cancel()
            if trimmed.isEmpty {
                // Clear immediately for responsiveness
                withAnimation(.easeOut(duration: 0.12)) {
                    debouncedQuery = ""
                }
            } else {
                // Debounce non-empty input
                debounceTask = Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(Self.filterDebounceMilliseconds))
                    guard !Task.isCancelled else { return }
                    withAnimation(.easeOut(duration: 0.12)) {
                        debouncedQuery = trimmed
                    }
                }
            }
        }
    }

    @State private var debounceTask: Task<Void, Never>?

    private func hideFilter() {
        filterText = ""
        debouncedQuery = ""
        isFilterFocused = false
        withAnimation(.easeOut(duration: 0.15)) {
            isFilterVisible = false
        }
        // Return focus to the active terminal
        postAppEvent(.refocusTerminalRequested)
    }

    private func toggleSidebar() {
        postAppEvent(.toggleSidebarRequested)
    }

    private func openWorktree(_ worktree: Worktree, in _: Repo) {
        postAppEvent(.openWorktreeRequested(worktreeId: worktree.id))
    }

    private func openNewTerminal(_ worktree: Worktree, in _: Repo) {
        postAppEvent(.openNewTerminalRequested(worktreeId: worktree.id))
    }

    private func openWorktreeInPane(_ worktree: Worktree, in _: Repo) {
        postAppEvent(.openWorktreeInPaneRequested(worktreeId: worktree.id))
    }

    private func addRepo() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Select a folder containing git repositories"
        panel.prompt = "Add Repos"

        if panel.runModal() == .OK, let url = panel.url {
            let scanner = RepoScanner()
            let repoPaths = scanner.scanForGitRepos(in: url, maxDepth: 3)

            if repoPaths.isEmpty {
                // Fallback: treat the selected folder itself as a repo
                _ = store.addRepo(at: url)
                requestWorktreeRefresh()
            } else {
                for repoPath in repoPaths {
                    // Skip if repo already exists (by path)
                    guard !store.repos.contains(where: { $0.repoPath == repoPath }) else {
                        continue
                    }
                    _ = store.addRepo(at: repoPath)
                }
                requestWorktreeRefresh()
            }
        }
    }

    private func requestWorktreeRefresh() {
        postAppEvent(.refreshWorktreesRequested)
    }
}

// MARK: - Repo Row View

struct RepoRowView: View {
    let repo: Repo
    let onRefresh: () -> Void
    let onRemove: () -> Void
    @State private var isHovered: Bool = false

    var body: some View {
        HStack(spacing: AppStyle.spacingStandard) {
            Image(systemName: "folder.fill")
                .font(.system(size: AppStyle.textLg))
                .foregroundStyle(.orange)

            Text(repo.name)
                .font(.system(size: AppStyle.textLg, weight: .medium))
                .lineLimit(1)

            Spacer()

            if isHovered {
                HStack(spacing: 2) {
                    Menu {
                        Button("Refresh Worktrees") { onRefresh() }
                        Divider()
                        Button {
                            NSWorkspace.shared.selectFile(
                                nil, inFileViewerRootedAtPath: repo.repoPath.path)
                        } label: {
                            Label("Reveal in Finder", systemImage: "folder")
                        }
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(repo.repoPath.path, forType: .string)
                        } label: {
                            Label("Copy Path", systemImage: "doc.on.clipboard")
                        }
                        Divider()
                        Button("Remove Repo", role: .destructive) { onRemove() }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: AppStyle.textSm))
                            .foregroundStyle(.secondary)
                            .frame(width: 20, height: 20)
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                }
                .transition(.opacity)
            } else {
                // Worktree count badge
                Text("\(repo.worktrees.count)")
                    .font(.system(size: AppStyle.textSm, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.15))
                    .clipShape(Capsule())
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
    }
}

// MARK: - Worktree Row View

struct WorktreeRowView: View {
    let worktree: Worktree
    let onOpen: () -> Void
    let onOpenNew: () -> Void
    let onOpenInPane: () -> Void
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: AppStyle.spacingStandard) {
            // Main worktree gets star, others get branch icon
            if worktree.isMainWorktree {
                Image(systemName: "star.fill")
                    .font(.system(size: AppStyle.textXs))
                    .foregroundStyle(.yellow)
            } else {
                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: AppStyle.textXs))
                    .foregroundStyle(.secondary)
            }

            Text(worktree.name)
                .font(.system(size: AppStyle.textBase))
                .lineLimit(1)
                .foregroundStyle(.primary)

            Spacer()

            if worktree.status != .idle {
                StatusBadgeView(status: worktree.status)
            }

            if let agent = worktree.agent {
                AgentBadgeView(agent: agent)
            }
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 4)
        .background(
            RoundedRectangle(cornerRadius: AppStyle.barCornerRadius)
                .fill(isHovering ? Color.accentColor.opacity(0.1) : Color.clear)
        )
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .onTapGesture(count: 2) {
            onOpen()
        }
        .contextMenu {
            Button {
                onOpenNew()
            } label: {
                Label("Open in New Tab", systemImage: "plus.rectangle")
            }

            Button {
                onOpenInPane()
            } label: {
                Label("Open in Pane (Split)", systemImage: "rectangle.split.2x1")
            }

            Divider()

            Button {
                onOpen()
            } label: {
                Label("Go to Terminal", systemImage: "terminal")
            }

            Button {
                openInCursor()
            } label: {
                Label("Open in Cursor", systemImage: "cursorarrow.rays")
            }

            Divider()

            Button {
                NSWorkspace.shared.selectFile(
                    nil, inFileViewerRootedAtPath: worktree.path.path)
            } label: {
                Label("Reveal in Finder", systemImage: "folder")
            }

            Button {
                copyPath()
            } label: {
                Label("Copy Path", systemImage: "doc.on.clipboard")
            }
        }
    }

    private func openInCursor() {
        let cursorURL = URL(fileURLWithPath: "/Applications/Cursor.app")
        let config = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.open(
            [worktree.path], withApplicationAt: cursorURL, configuration: config)
    }

    private func copyPath() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(worktree.path.path, forType: .string)
    }
}

// MARK: - Status Badge View

struct StatusBadgeView: View {
    let status: WorktreeStatus

    var body: some View {
        HStack(spacing: 3) {
            if status == .running {
                ProgressView()
                    .controlSize(.mini)
            }
            Text(status.displayName)
                .font(.system(size: AppStyle.textXs, weight: .medium))
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(status.color.opacity(0.2))
        .foregroundStyle(status.color)
        .clipShape(Capsule())
    }
}

// MARK: - Agent Badge View

struct AgentBadgeView: View {
    let agent: AgentType

    var body: some View {
        Text(agent.shortName)
            .font(.system(size: AppStyle.textXs, weight: .medium))
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(agent.color.opacity(0.2))
            .foregroundStyle(agent.color)
            .clipShape(Capsule())
    }
}
