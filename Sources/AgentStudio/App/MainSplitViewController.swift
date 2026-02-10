import AppKit
import os.log
import SwiftUI

private let sidebarLogger = Logger(subsystem: "com.agentstudio", category: "Sidebar")

/// Main split view controller with sidebar and terminal content area
class MainSplitViewController: NSSplitViewController {
    private var sidebarHostingController: NSHostingController<AnyView>?
    private var terminalTabViewController: TerminalTabViewController?

    // MARK: - Dependencies (injected)

    private let store: WorkspaceStore
    private let executor: ActionExecutor
    private let tabBarAdapter: TabBarAdapter
    private let viewRegistry: ViewRegistry

    init(store: WorkspaceStore, executor: ActionExecutor,
         tabBarAdapter: TabBarAdapter, viewRegistry: ViewRegistry) {
        self.store = store
        self.executor = executor
        self.tabBarAdapter = tabBarAdapter
        self.viewRegistry = viewRegistry
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not supported")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        // Configure split view
        splitView.isVertical = true
        splitView.dividerStyle = .thin

        // Create sidebar (SwiftUI via NSHostingController)
        let sidebarView = SidebarViewWrapper(store: store)
        let sidebarHosting = NSHostingController(rootView: AnyView(sidebarView))
        self.sidebarHostingController = sidebarHosting

        let sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebarHosting)
        sidebarItem.minimumThickness = 200
        sidebarItem.maximumThickness = 400
        sidebarItem.canCollapse = true
        sidebarItem.collapseBehavior = .preferResizingSplitViewWithFixedSiblings
        addSplitViewItem(sidebarItem)

        // Create terminal area (pure AppKit)
        let terminalVC = TerminalTabViewController(
            store: store,
            executor: executor,
            tabBarAdapter: tabBarAdapter,
            viewRegistry: viewRegistry
        )
        self.terminalTabViewController = terminalVC

        let terminalItem = NSSplitViewItem(viewController: terminalVC)
        terminalItem.minimumThickness = 400
        addSplitViewItem(terminalItem)

        // Set up notification observers
        setupNotificationObservers()
    }

    // MARK: - Notification Observers

    private func setupNotificationObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleOpenWorktree(_:)),
            name: .openWorktreeRequested,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleCloseTab(_:)),
            name: .closeTabRequested,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSelectTab(_:)),
            name: .selectTabAtIndex,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleToggleSidebar(_:)),
            name: .toggleSidebarRequested,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleOpenNewTerminal(_:)),
            name: .openNewTerminalRequested,
            object: nil
        )
    }

    @objc private func handleToggleSidebar(_ notification: Notification) {
        toggleSidebar(nil)
    }

    @objc private func handleOpenWorktree(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let worktree = userInfo["worktree"] as? Worktree,
              let repo = userInfo["repo"] as? Repo else {
            sidebarLogger.error("Invalid openWorktreeRequested notification payload")
            return
        }

        terminalTabViewController?.openTerminal(for: worktree, in: repo)
    }

    @objc private func handleOpenNewTerminal(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let worktree = userInfo["worktree"] as? Worktree,
              let repo = userInfo["repo"] as? Repo else {
            sidebarLogger.error("Invalid openNewTerminalRequested notification payload")
            return
        }

        terminalTabViewController?.openNewTerminal(for: worktree, in: repo)
    }

    @objc private func handleCloseTab(_ notification: Notification) {
        terminalTabViewController?.closeActiveTab()
    }

    @objc private func handleSelectTab(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let index = userInfo["index"] as? Int else {
            return
        }

        terminalTabViewController?.selectTab(at: index)
    }

    // MARK: - Subtle Divider

    override func splitView(_ splitView: NSSplitView, effectiveRect proposedEffectiveRect: NSRect, forDrawnRect drawnRect: NSRect, ofDividerAt dividerIndex: Int) -> NSRect {
        // Make the divider very thin/subtle
        var rect = proposedEffectiveRect
        rect.size.width = 1
        return rect
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}

// MARK: - Sidebar View Wrapper

/// SwiftUI wrapper that bridges to the AppKit world.
/// Uses WorkspaceStore instead of SessionManager.
struct SidebarViewWrapper: View {
    @ObservedObject var store: WorkspaceStore

    var body: some View {
        SidebarContentView(store: store)
    }
}

/// The actual sidebar content
struct SidebarContentView: View {
    @ObservedObject var store: WorkspaceStore
    @State private var expandedRepos: Set<UUID> = []
    @State private var filterText: String = ""
    @State private var debouncedQuery: String = ""
    @FocusState private var isFilterFocused: Bool

    /// Repos filtered by the debounced search text, with worktree-level filtering.
    private var filteredRepos: [Repo] {
        let query = debouncedQuery
        guard !query.isEmpty else { return store.repos }

        return store.repos.compactMap { repo in
            if repo.name.localizedCaseInsensitiveContains(query) {
                return repo // repo name matches → show all worktrees
            }
            let matchingWorktrees = repo.worktrees.filter {
                $0.name.localizedCaseInsensitiveContains(query)
            }
            guard !matchingWorktrees.isEmpty else { return nil }
            var filtered = repo
            filtered.worktrees = matchingWorktrees
            return filtered
        }
    }

    /// Whether a filter is actively narrowing results.
    private var isFiltering: Bool {
        !debouncedQuery.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search / filter bar
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)

                TextField("Filter...", text: $filterText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .focused($isFilterFocused)
                    .onExitCommand {
                        filterText = ""
                        isFilterFocused = false
                    }

                if !filterText.isEmpty {
                    Button {
                        filterText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Clear filter")
                    .transition(.opacity.animation(.easeOut(duration: 0.1)))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(nsColor: .controlBackgroundColor))

            // Main list content
            if isFiltering && filteredRepos.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 24))
                        .foregroundStyle(.secondary)
                        .opacity(0.5)

                    Text("No results")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(.opacity.animation(.easeOut(duration: 0.12)))
            } else {
                List {
                    Section("Repos") {
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
                                        }
                                    )
                                    .listRowInsets(EdgeInsets(top: 0, leading: 5, bottom: 0, trailing: 0))
                                }
                            } label: {
                                RepoRowView(repo: repo)
                            }
                        }
                    }
                }
                .listStyle(.sidebar)
            }

        }
        .frame(minWidth: 200)
        .background(Color(nsColor: .windowBackgroundColor))
        // Subtle shadow on right edge only
        .shadow(color: .black.opacity(0.2), radius: 4, x: 2, y: 0)
        .onReceive(NotificationCenter.default.publisher(for: .addRepoRequested)) { _ in
            addRepo()
        }
        .onReceive(NotificationCenter.default.publisher(for: .refreshWorktreesRequested)) { _ in
            refreshWorktrees()
        }
        .onReceive(NotificationCenter.default.publisher(for: .filterSidebarRequested)) { _ in
            isFilterFocused = true
        }
        .onChange(of: filterText) { _, newValue in
            let trimmed = newValue.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                // Clear immediately for responsiveness
                withAnimation(.easeOut(duration: 0.12)) {
                    debouncedQuery = ""
                }
            } else {
                // Debounce non-empty input
                debounceTask?.cancel()
                debounceTask = Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(25))
                    guard !Task.isCancelled else { return }
                    withAnimation(.easeOut(duration: 0.12)) {
                        debouncedQuery = trimmed
                    }
                }
            }
        }
    }

    @State private var debounceTask: Task<Void, Never>?

    private func toggleSidebar() {
        NotificationCenter.default.post(name: .toggleSidebarRequested, object: nil)
    }

    private func openWorktree(_ worktree: Worktree, in repo: Repo) {
        NotificationCenter.default.post(
            name: .openWorktreeRequested,
            object: nil,
            userInfo: ["worktree": worktree, "repo": repo]
        )
    }

    private func openNewTerminal(_ worktree: Worktree, in repo: Repo) {
        NotificationCenter.default.post(
            name: .openNewTerminalRequested,
            object: nil,
            userInfo: ["worktree": worktree, "repo": repo]
        )
    }

    private func addRepo() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Select a git repository"
        panel.prompt = "Add Repo"

        if panel.runModal() == .OK, let url = panel.url {
            let repo = store.addRepo(at: url)
            // Immediately discover worktrees so the sidebar isn't empty
            let worktrees = WorktrunkService.shared.discoverWorktrees(for: repo.repoPath)
            store.updateRepoWorktrees(repo.id, worktrees: worktrees)
        }
    }

    private func refreshWorktrees() {
        // Refresh worktrees using WorktrunkService
        for repo in store.repos {
            let worktrees = WorktrunkService.shared.discoverWorktrees(for: repo.repoPath)
            store.updateRepoWorktrees(repo.id, worktrees: worktrees)
        }
    }
}

// MARK: - Repo Row View

struct RepoRowView: View {
    let repo: Repo

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "folder.fill")
                .font(.system(size: 14))
                .foregroundStyle(.orange)

            Text(repo.name)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)

            Spacer()

            // Worktree count badge
            Text("\(repo.worktrees.count)")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.secondary.opacity(0.15))
                .clipShape(Capsule())
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Worktree Row View

struct WorktreeRowView: View {
    let worktree: Worktree
    let onOpen: () -> Void
    let onOpenNew: () -> Void
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 6) {
            // Branch icon
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            // Worktree name
            Text(worktree.name)
                .font(.system(size: 12))
                .lineLimit(1)
                .foregroundStyle(.primary)

            Spacer()

            // Status badge
            if worktree.status != .idle {
                StatusBadgeView(status: worktree.status)
            }

            // Agent badge
            if let agent = worktree.agent {
                AgentBadgeView(agent: agent)
            }
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isHovering ? Color.accentColor.opacity(0.1) : Color.clear)
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovering = hovering
        }
        .onTapGesture(count: 2) {
            onOpen()
        }
        .contextMenu {
            Button {
                onOpenNew()
            } label: {
                Label("Open New Terminal in Tab", systemImage: "terminal.fill")
            }

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
                NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: worktree.path.path)
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
        NSWorkspace.shared.open([worktree.path], withApplicationAt: cursorURL, configuration: config)
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
                .font(.system(size: 9, weight: .medium))
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
            .font(.system(size: 9, weight: .medium))
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(agent.color.opacity(0.2))
            .foregroundStyle(agent.color)
            .clipShape(Capsule())
    }
}
