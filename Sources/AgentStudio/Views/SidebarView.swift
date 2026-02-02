import SwiftUI

struct SidebarView: View {
    @EnvironmentObject private var sessionManager: SessionManager
    @State private var selectedProjectId: UUID?
    @State private var expandedProjects: Set<UUID> = []

    var body: some View {
        List(selection: $selectedProjectId) {
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
                            WorktreeRow(
                                worktree: worktree,
                                onOpen: {
                                    sessionManager.openTab(for: worktree, in: project)
                                }
                            )
                        }
                    } label: {
                        ProjectRow(project: project)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .frame(minWidth: 200)
        .toolbar {
            ToolbarItem {
                Button(action: addProject) {
                    Label("Add Project", systemImage: "folder.badge.plus")
                }
            }

            ToolbarItem {
                Button(action: refreshWorktrees) {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .addProjectRequested)) { _ in
            addProject()
        }
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

// MARK: - Project Row

struct ProjectRow: View {
    let project: Project

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "folder.fill")
                .foregroundStyle(.secondary)

            Text(project.name)
                .lineLimit(1)

            Spacer()

            Text("\(project.worktrees.count)")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }
}

// MARK: - Worktree Row

struct WorktreeRow: View {
    let worktree: Worktree
    let onOpen: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(worktree.isOpen ? Color.accentColor : Color.secondary.opacity(0.3))
                .frame(width: 8, height: 8)

            Text(worktree.name)
                .lineLimit(1)

            Spacer()

            if let agent = worktree.agent {
                AgentBadge(agent: agent)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            onOpen()
        }
        .contextMenu {
            Button("Open in Terminal") {
                onOpen()
            }

            Button("Open in Cursor") {
                openInCursor()
            }

            Divider()

            Button("Reveal in Finder") {
                NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: worktree.path.path)
            }
        }
    }

    private func openInCursor() {
        let cursorURL = URL(fileURLWithPath: "/Applications/Cursor.app")
        let config = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.open([worktree.path], withApplicationAt: cursorURL, configuration: config)
    }
}

// MARK: - Agent Badge

struct AgentBadge: View {
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
