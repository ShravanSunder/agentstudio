import Foundation
import Combine
import os.log

private let sessionLogger = Logger(subsystem: "com.agentstudio", category: "SessionManager")

/// Manages application state persistence and restoration
@MainActor
final class SessionManager: ObservableObject {
    static let shared = SessionManager()

    // MARK: - Published State

    @Published var repos: [Repo] = []
    @Published var openTabs: [OpenTab] = []
    @Published var activeTabId: UUID?

    // MARK: - Workspace

    private(set) var workspace: Workspace

    // MARK: - Private

    private let workspacesDir: URL
    private let worktrunkService = WorktrunkService.shared

    // MARK: - Initialization

    private init() {
        let appSupport = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: ".agentstudio")

        workspacesDir = appSupport.appending(path: "workspaces")

        // Create directories if needed
        do {
            try FileManager.default.createDirectory(at: workspacesDir, withIntermediateDirectories: true)
        } catch {
            sessionLogger.error("Failed to create workspaces directory \(self.workspacesDir.path): \(error)")
        }

        // Initialize with empty workspace, then load
        workspace = Workspace()
        load()
    }

    // MARK: - Persistence

    /// URL for the current workspace file
    private var workspaceURL: URL {
        workspacesDir.appending(path: "\(workspace.id.uuidString).json")
    }

    /// Load state from disk
    func load() {
        if let loaded = loadWorkspace() {
            workspace = loaded
        }

        // Populate published properties from workspace
        repos = workspace.repos
        openTabs = workspace.openTabs
        activeTabId = workspace.activeTabId

        // Refresh worktrees for each repo
        for i in repos.indices {
            let discovered = worktrunkService.discoverWorktrees(for: repos[i].repoPath)
            repos[i].worktrees = mergeWorktrees(existing: repos[i].worktrees, discovered: discovered)
        }

        // Sync back to workspace
        workspace.repos = repos
    }

    /// Load workspace from the workspaces directory
    private func loadWorkspace() -> Workspace? {
        let contents: [URL]
        do {
            contents = try FileManager.default.contentsOfDirectory(
                at: workspacesDir,
                includingPropertiesForKeys: nil,
                options: .skipsHiddenFiles
            )
        } catch {
            sessionLogger.error("Failed to list workspaces directory: \(error)")
            return nil
        }

        let workspaceFiles = contents.filter { $0.pathExtension == "json" }

        // Phase 1: single workspace — load the first one found
        for fileURL in workspaceFiles {
            do {
                let data = try Data(contentsOf: fileURL)
                let loaded = try JSONDecoder().decode(Workspace.self, from: data)
                return loaded
            } catch {
                sessionLogger.error("Failed to load workspace file \(fileURL.lastPathComponent): \(error)")
            }
        }
        return nil
    }

    /// Save state to disk
    func save() {
        workspace.repos = repos
        workspace.openTabs = openTabs
        workspace.activeTabId = activeTabId
        workspace.updatedAt = Date()

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        do {
            let data = try encoder.encode(workspace)
            try data.write(to: workspaceURL, options: .atomic)
        } catch {
            sessionLogger.error("Failed to save workspace to \(self.workspaceURL.lastPathComponent): \(error)")
        }
    }

    // MARK: - Repo Management

    /// Add a new repo from a repository path
    @discardableResult
    func addRepo(at path: URL) -> Repo {
        if let existing = repos.first(where: { $0.repoPath == path }) {
            return existing
        }

        let worktrees = worktrunkService.discoverWorktrees(for: path)

        let repo = Repo(
            name: path.lastPathComponent,
            repoPath: path,
            worktrees: worktrees
        )

        repos.append(repo)
        save()

        return repo
    }

    /// Remove a repo
    func removeRepo(_ repo: Repo) {
        let tabsToClose = openTabs.filter { $0.repoId == repo.id }
        for tab in tabsToClose {
            closeTab(tab)
        }

        repos.removeAll { $0.id == repo.id }
        save()
    }

    /// Refresh worktrees for a repo
    func refreshWorktrees(for repo: Repo) {
        guard let index = repos.firstIndex(where: { $0.id == repo.id }) else { return }

        let discovered = worktrunkService.discoverWorktrees(for: repo.repoPath)
        repos[index].worktrees = mergeWorktrees(existing: repos[index].worktrees, discovered: discovered)
        repos[index].updatedAt = Date()

        save()
    }

    /// Merge existing worktree state with newly discovered worktrees
    func mergeWorktrees(existing: [Worktree], discovered: [Worktree]) -> [Worktree] {
        return discovered.map { newWorktree in
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
    func openTab(for worktree: Worktree, in repo: Repo) -> OpenTab {
        if let existing = openTabs.first(where: { $0.worktreeId == worktree.id }) {
            activeTabId = existing.id
            return existing
        }

        let tab = OpenTab(
            worktreeId: worktree.id,
            repoId: repo.id,
            order: openTabs.count
        )

        openTabs.append(tab)
        activeTabId = tab.id

        updateWorktreeStatus(worktree.id, isOpen: true)

        save()
        return tab
    }

    /// Close a tab
    func closeTab(_ tab: OpenTab) {
        openTabs.removeAll { $0.id == tab.id }
        updateWorktreeStatus(tab.worktreeId, isOpen: false)

        if activeTabId == tab.id {
            activeTabId = openTabs.last?.id
        }

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
        for i in repos.indices {
            for j in repos[i].worktrees.indices {
                if repos[i].worktrees[j].id == worktreeId {
                    repos[i].worktrees[j].isOpen = isOpen
                    if isOpen {
                        repos[i].worktrees[j].lastOpened = Date()
                    }
                }
            }
        }
    }

    // MARK: - Lookup Helpers

    /// Find worktree for a tab
    func worktree(for tab: OpenTab) -> Worktree? {
        repos
            .first { $0.id == tab.repoId }?
            .worktrees
            .first { $0.id == tab.worktreeId }
    }

    /// Find repo for a tab
    func repo(for tab: OpenTab) -> Repo? {
        repos.first { $0.id == tab.repoId }
    }

    /// Find repo containing a worktree
    func repo(containing worktree: Worktree) -> Repo? {
        repos.first { repo in
            repo.worktrees.contains { $0.id == worktree.id }
        }
    }

    // MARK: - Static Lookup Helpers (for testability)

    nonisolated static func findWorktree(for tab: OpenTab, in repos: [Repo]) -> Worktree? {
        repos
            .first { $0.id == tab.repoId }?
            .worktrees
            .first { $0.id == tab.worktreeId }
    }

    nonisolated static func findRepo(for tab: OpenTab, in repos: [Repo]) -> Repo? {
        repos.first { $0.id == tab.repoId }
    }

    nonisolated static func findRepo(containing worktree: Worktree, in repos: [Repo]) -> Repo? {
        repos.first { repo in
            repo.worktrees.contains { $0.id == worktree.id }
        }
    }

    nonisolated static func mergeWorktrees(existing: [Worktree], discovered: [Worktree]) -> [Worktree] {
        discovered.map { newWorktree in
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
}
