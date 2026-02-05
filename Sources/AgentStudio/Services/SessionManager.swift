import Foundation
import Combine

/// Manages application state persistence and restoration
@MainActor
final class SessionManager: ObservableObject {
    static let shared = SessionManager()

    // MARK: - Published State

    @Published var projects: [Project] = []
    @Published var openTabs: [OpenTab] = []
    @Published var activeTabId: UUID?

    // MARK: - Private

    private let stateURL: URL
    private let projectsURL: URL
    private let worktrunkService = WorktrunkService.shared

    // MARK: - Initialization

    private init() {
        let appSupport = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: ".agentstudio")

        // Create directory if needed
        try? FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)

        stateURL = appSupport.appending(path: "state.json")
        projectsURL = appSupport.appending(path: "projects.json")

        load()
    }

    // MARK: - Persistence

    /// Load state from disk
    func load() {
        // Load projects
        if let data = try? Data(contentsOf: projectsURL),
           let loadedProjects = try? JSONDecoder().decode([Project].self, from: data) {
            self.projects = loadedProjects

            // Refresh worktrees for each project
            for i in projects.indices {
                let discovered = worktrunkService.discoverWorktrees(for: projects[i].repoPath)
                projects[i].worktrees = mergeWorktrees(existing: projects[i].worktrees, discovered: discovered)
            }
        }

        // Load UI state
        if let data = try? Data(contentsOf: stateURL),
           let state = try? JSONDecoder().decode(AppState.self, from: data) {
            self.openTabs = state.openTabs
            self.activeTabId = state.activeTabId
        }
    }

    /// Save state to disk
    func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        // Save projects
        if let data = try? encoder.encode(projects) {
            try? data.write(to: projectsURL, options: .atomic)
        }

        // Save UI state
        let state = AppState(
            projects: projects,
            openTabs: openTabs,
            activeTabId: activeTabId,
            sidebarWidth: 250,
            windowFrame: nil
        )
        if let data = try? encoder.encode(state) {
            try? data.write(to: stateURL, options: .atomic)
        }
    }

    // MARK: - Project Management

    /// Add a new project from a repository path
    @discardableResult
    func addProject(at path: URL) -> Project {
        // Check if already exists
        if let existing = projects.first(where: { $0.repoPath == path }) {
            return existing
        }

        let worktrees = worktrunkService.discoverWorktrees(for: path)

        let project = Project(
            name: path.lastPathComponent,
            repoPath: path,
            worktrees: worktrees
        )

        projects.append(project)
        save()

        return project
    }

    /// Remove a project
    func removeProject(_ project: Project) {
        // Close any open tabs for this project
        let tabsToClose = openTabs.filter { $0.projectId == project.id }
        for tab in tabsToClose {
            closeTab(tab)
        }

        projects.removeAll { $0.id == project.id }
        save()
    }

    /// Refresh worktrees for a project
    func refreshWorktrees(for project: Project) {
        guard let index = projects.firstIndex(where: { $0.id == project.id }) else { return }

        let discovered = worktrunkService.discoverWorktrees(for: project.repoPath)
        projects[index].worktrees = mergeWorktrees(existing: projects[index].worktrees, discovered: discovered)
        projects[index].updatedAt = Date()

        save()
    }

    /// Merge existing worktree state with newly discovered worktrees
    private func mergeWorktrees(existing: [Worktree], discovered: [Worktree]) -> [Worktree] {
        return discovered.map { newWorktree in
            // Preserve existing state (isOpen, agent, etc.) if this worktree existed before
            if let existingWorktree = existing.first(where: { $0.path == newWorktree.path }) {
                var merged = newWorktree
                merged.isOpen = existingWorktree.isOpen
                merged.agent = existingWorktree.agent
                merged.status = existingWorktree.status
                merged.lastOpened = existingWorktree.lastOpened
                return merged
            }
            return newWorktree
        }
    }

    // MARK: - Tab Management

    /// Open a tab for a worktree
    @discardableResult
    func openTab(for worktree: Worktree, in project: Project) -> OpenTab {
        // Check if already open
        if let existing = openTabs.first(where: { $0.worktreeId == worktree.id }) {
            activeTabId = existing.id
            return existing
        }

        let tab = OpenTab(
            worktreeId: worktree.id,
            projectId: project.id,
            order: openTabs.count
        )

        openTabs.append(tab)
        activeTabId = tab.id

        // Update worktree status
        updateWorktreeStatus(worktree.id, isOpen: true)

        save()
        return tab
    }

    /// Close a tab
    func closeTab(_ tab: OpenTab) {
        openTabs.removeAll { $0.id == tab.id }
        updateWorktreeStatus(tab.worktreeId, isOpen: false)

        // Select adjacent tab if closing active
        if activeTabId == tab.id {
            activeTabId = openTabs.last?.id
        }

        // Reorder remaining tabs
        for i in openTabs.indices {
            openTabs[i].order = i
        }

        save()
    }

    /// Reorder tabs based on new worktree order
    func reorderTabs(_ worktreeIds: [UUID]) {
        for (index, worktreeId) in worktreeIds.enumerated() {
            if let tabIndex = openTabs.firstIndex(where: { $0.worktreeId == worktreeId }) {
                openTabs[tabIndex].order = index
            }
        }
        save()
    }

    /// Switch to a specific tab
    func switchToTab(_ tab: OpenTab) {
        activeTabId = tab.id
    }

    /// Switch to tab at index (for keyboard shortcuts)
    func switchToTab(at index: Int) {
        guard index >= 0, index < openTabs.count else { return }
        let sortedTabs = openTabs.sorted { $0.order < $1.order }
        activeTabId = sortedTabs[index].id
    }

    /// Update a tab's split tree data (for auto-save)
    func updateTabSplitTree(_ tabId: UUID, splitTreeData: Data?, activePaneId: UUID?) {
        guard let index = openTabs.firstIndex(where: { $0.id == tabId }) else { return }
        openTabs[index].splitTreeData = splitTreeData
        openTabs[index].activePaneId = activePaneId
        save()
    }

    /// Update worktree open status
    private func updateWorktreeStatus(_ worktreeId: UUID, isOpen: Bool) {
        for i in projects.indices {
            for j in projects[i].worktrees.indices {
                if projects[i].worktrees[j].id == worktreeId {
                    projects[i].worktrees[j].isOpen = isOpen
                    if isOpen {
                        projects[i].worktrees[j].lastOpened = Date()
                    }
                }
            }
        }
    }

    // MARK: - Lookup Helpers

    /// Find worktree for a tab
    func worktree(for tab: OpenTab) -> Worktree? {
        projects
            .first { $0.id == tab.projectId }?
            .worktrees
            .first { $0.id == tab.worktreeId }
    }

    /// Find project for a tab
    func project(for tab: OpenTab) -> Project? {
        projects.first { $0.id == tab.projectId }
    }

    /// Find project containing a worktree
    func project(containing worktree: Worktree) -> Project? {
        projects.first { project in
            project.worktrees.contains { $0.id == worktree.id }
        }
    }
}
