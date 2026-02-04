import Foundation
import Combine
import os

private let logger = Logger(subsystem: "com.agentstudio", category: "SessionManager")

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
    private let checkpointURL: URL
    private let worktrunkService = WorktrunkService.shared
    private let zellijService = ZellijService.shared

    // MARK: - Initialization

    private init() {
        let appSupport = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: ".agentstudio")

        // Create directory if needed
        try? FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)

        stateURL = appSupport.appending(path: "state.json")
        projectsURL = appSupport.appending(path: "projects.json")
        checkpointURL = appSupport.appending(path: "session-checkpoint.json")

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

    // MARK: - Zellij Integration

    /// Get or create Zellij session for a project
    func getOrCreateSession(for project: Project) async throws -> ZellijSession {
        if let existing = zellijService.session(for: project) {
            return existing
        }
        return try await zellijService.createSession(for: project)
    }

    /// Get or create Zellij tab for a worktree in a session
    func getOrCreateTab(in session: ZellijSession, for worktree: Worktree) async throws -> ZellijTab {
        if let existing = session.tabs.first(where: { $0.worktreeId == worktree.id }) {
            return existing
        }
        return try await zellijService.createTab(in: session, for: worktree)
    }

    /// Get the Zellij attach command for a tab (for Ghostty surface)
    func attachCommand(for tab: OpenTab) async throws -> String? {
        guard let project = project(for: tab),
              let worktree = worktree(for: tab) else {
            return nil
        }

        let session = try await getOrCreateSession(for: project)
        _ = try await getOrCreateTab(in: session, for: worktree)

        return zellijService.attachCommand(for: session)
    }

    // MARK: - Checkpoint (Reboot Recovery)

    /// Save checkpoint for reboot recovery
    func saveCheckpoint() {
        let checkpoint = SessionCheckpoint(sessions: zellijService.sessions)

        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(checkpoint)
            try data.write(to: checkpointURL, options: .atomic)
            logger.info("Saved session checkpoint with \(checkpoint.sessions.count) sessions")
        } catch {
            logger.error("Failed to save checkpoint: \(error)")
        }
    }

    /// Restore sessions from checkpoint after reboot
    func restoreFromCheckpoint() async {
        guard FileManager.default.fileExists(atPath: checkpointURL.path) else {
            logger.info("No checkpoint file found, skipping restore")
            return
        }

        do {
            let data = try Data(contentsOf: checkpointURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let checkpoint = try decoder.decode(SessionCheckpoint.self, from: data)

            logger.info("Restoring \(checkpoint.sessions.count) sessions from checkpoint")

            for sessionData in checkpoint.sessions {
                // Skip if session already running (Zellij may have resurrected it)
                if await zellijService.sessionExists(sessionData.id) {
                    logger.info("Session \(sessionData.id) already running, skipping")
                    continue
                }

                // Find project
                guard let project = projects.first(where: { $0.id == sessionData.projectId }) else {
                    logger.warning("Project \(sessionData.projectId) not found, skipping session")
                    continue
                }

                // Recreate session
                let session = try await zellijService.createSession(for: project)

                // Recreate tabs
                for tabData in sessionData.tabs {
                    guard let worktree = project.worktrees.first(where: { $0.id == tabData.worktreeId }) else {
                        logger.warning("Worktree \(tabData.worktreeId) not found, skipping tab")
                        continue
                    }

                    var tab = try await zellijService.createTab(in: session, for: worktree)
                    tab.restoreCommand = tabData.restoreCommand

                    // Re-run command if specified
                    if let cmd = tabData.restoreCommand, !cmd.isEmpty {
                        try await zellijService.sendText(cmd + "\n", to: session)
                        logger.info("Re-executed command '\(cmd)' in tab \(tab.name)")
                    }
                }
            }

            logger.info("Checkpoint restore complete")
        } catch {
            logger.error("Failed to restore checkpoint: \(error)")
        }
    }

    /// Initialize Zellij on app launch
    func initializeZellij() async {
        // Ensure config files exist
        do {
            try zellijService.ensureConfigFiles()
        } catch {
            logger.error("Failed to setup Zellij configs: \(error)")
        }

        // Check for running sessions or restore from checkpoint
        let runningSessions = await zellijService.discoverSessions()
        if runningSessions.isEmpty {
            logger.info("No running sessions found, restoring from checkpoint")
            await restoreFromCheckpoint()
        } else {
            logger.info("Found \(runningSessions.count) running sessions")
        }
    }
}
