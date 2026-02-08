import AppKit
import SwiftUI

/// Main split view controller with sidebar and terminal content area
class MainSplitViewController: NSSplitViewController {
    private var sidebarHostingController: NSHostingController<AnyView>?
    private var terminalTabViewController: TerminalTabViewController?

    override func viewDidLoad() {
        super.viewDidLoad()

        // Configure split view
        splitView.isVertical = true
        splitView.dividerStyle = .thin

        // Create sidebar (SwiftUI via NSHostingController)
        let sidebarView = SidebarViewWrapper()
        let sidebarHosting = NSHostingController(rootView: AnyView(sidebarView))
        self.sidebarHostingController = sidebarHosting

        let sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebarHosting)
        sidebarItem.minimumThickness = 200
        sidebarItem.maximumThickness = 400
        sidebarItem.canCollapse = true
        sidebarItem.collapseBehavior = .preferResizingSplitViewWithFixedSiblings
        addSplitViewItem(sidebarItem)

        // Create terminal area (pure AppKit)
        let terminalVC = TerminalTabViewController()
        self.terminalTabViewController = terminalVC

        let terminalItem = NSSplitViewItem(viewController: terminalVC)
        terminalItem.minimumThickness = 400
        addSplitViewItem(terminalItem)

        // Set up notification observers
        setupNotificationObservers()

        // Restore previously open tabs
        restoreSessionTabs()
    }

    private func restoreSessionTabs() {
        // Get the sorted open tabs from session manager
        let sortedTabs = SessionManager.shared.openTabs.sorted { $0.order < $1.order }

        debugLog("[MainSplitVC] Restoring \(sortedTabs.count) tabs from session")

        for tab in sortedTabs {
            // Use restoreTab which handles split tree restoration
            debugLog("[MainSplitVC] Restoring tab: \(tab.id) (has splitTree: \(tab.splitTreeData != nil))")
            terminalTabViewController?.restoreTab(from: tab)
        }

        // Select the active tab if it exists
        if let activeTabId = SessionManager.shared.activeTabId,
           let activeTab = SessionManager.shared.openTabs.first(where: { $0.id == activeTabId }),
           let index = sortedTabs.firstIndex(where: { $0.id == activeTab.id }) {
            terminalTabViewController?.selectTab(at: index)
        }
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
    }

    @objc private func handleToggleSidebar(_ notification: Notification) {
        toggleSidebar(nil)
    }

    @objc private func handleOpenWorktree(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let worktree = userInfo["worktree"] as? Worktree,
              let project = userInfo["project"] as? Project else {
            return
        }

        terminalTabViewController?.openTerminal(for: worktree, in: project)
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

/// SwiftUI wrapper that bridges to the AppKit world
struct SidebarViewWrapper: View {
    @ObservedObject private var sessionManager = SessionManager.shared

    var body: some View {
        SidebarContentView(sessionManager: sessionManager)
    }
}

/// The actual sidebar content
struct SidebarContentView: View {
    @ObservedObject var sessionManager: SessionManager
    @State private var expandedProjects: Set<UUID> = []

    var body: some View {
        VStack(spacing: 0) {
            // Main list content (toggle button is now in titlebar)
            List {
                Section("Projects") {
                    ForEach(sessionManager.projects) { project in
                        DisclosureGroup(
                            isExpanded: Binding(
                                get: { expandedProjects.contains(project.id) },
                                set: { isExpanded in
                                    if isExpanded {
                                        expandedProjects.insert(project.id)
                                    } else {
                                        expandedProjects.remove(project.id)
                                    }
                                }
                            )
                        ) {
                            ForEach(project.worktrees) { worktree in
                                WorktreeRowView(
                                    worktree: worktree,
                                    onOpen: {
                                        openWorktree(worktree, in: project)
                                    }
                                )
                            }
                        } label: {
                            ProjectRowView(project: project)
                        }
                    }
                }
            }
            .listStyle(.sidebar)

        }
        .frame(minWidth: 200)
        .background(Color(nsColor: .windowBackgroundColor))
        // Subtle shadow on right edge only
        .shadow(color: .black.opacity(0.2), radius: 4, x: 2, y: 0)
        .onReceive(NotificationCenter.default.publisher(for: .addProjectRequested)) { _ in
            addProject()
        }
        .onReceive(NotificationCenter.default.publisher(for: .refreshWorktreesRequested)) { _ in
            refreshWorktrees()
        }
    }

    private func toggleSidebar() {
        NotificationCenter.default.post(name: .toggleSidebarRequested, object: nil)
    }

    private func openWorktree(_ worktree: Worktree, in project: Project) {
        sessionManager.openTab(for: worktree, in: project)
        NotificationCenter.default.post(
            name: .openWorktreeRequested,
            object: nil,
            userInfo: ["worktree": worktree, "project": project]
        )
    }

    private func addProject() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Select a git repository"
        panel.prompt = "Add Project"

        if panel.runModal() == .OK, let url = panel.url {
            _ = sessionManager.addProject(at: url)
        }
    }

    private func refreshWorktrees() {
        for project in sessionManager.projects {
            sessionManager.refreshWorktrees(for: project)
        }
    }
}

// MARK: - Project Row View

struct ProjectRowView: View {
    let project: Project

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "folder.fill")
                .font(.system(size: 14))
                .foregroundStyle(.orange)

            Text(project.name)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)

            Spacer()

            // Worktree count badge
            Text("\(project.worktrees.count)")
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
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 8) {
            // Status indicator with animation
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
                .animation(.easeInOut(duration: 0.2), value: worktree.isOpen)

            // Branch icon
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            // Worktree name
            Text(worktree.name)
                .font(.system(size: 12))
                .lineLimit(1)
                .foregroundStyle(worktree.isOpen ? .primary : .secondary)

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
                onOpen()
            } label: {
                Label("Open in Terminal", systemImage: "terminal")
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

    private var statusColor: Color {
        if worktree.isOpen {
            return .green
        }
        switch worktree.status {
        case .idle: return .secondary.opacity(0.4)
        case .running: return .green
        case .pendingReview: return .orange
        case .error: return .red
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
