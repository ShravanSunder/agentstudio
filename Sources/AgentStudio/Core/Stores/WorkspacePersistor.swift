import Foundation
import os.log

private let persistorLogger = Logger(subsystem: "com.agentstudio", category: "WorkspacePersistor")

/// Pure persistence I/O for workspace state.
/// Collaborator of WorkspaceStore — not a public peer.
struct WorkspacePersistor {

    /// On-disk representation of workspace state.
    struct PersistableState: Codable {
        var id: UUID
        var name: String
        var repos: [Repo]
        var panes: [Pane]
        var tabs: [Tab]
        var activeTabId: UUID?
        var sidebarWidth: CGFloat
        var windowFrame: CGRect?
        var createdAt: Date
        var updatedAt: Date

        init(
            id: UUID = UUID(),
            name: String = "Default Workspace",
            repos: [Repo] = [],
            panes: [Pane] = [],
            tabs: [Tab] = [],
            activeTabId: UUID? = nil,
            sidebarWidth: CGFloat = 250,
            windowFrame: CGRect? = nil,
            createdAt: Date = Date(),
            updatedAt: Date = Date()
        ) {
            self.id = id
            self.name = name
            self.repos = repos
            self.panes = panes
            self.tabs = tabs
            self.activeTabId = activeTabId
            self.sidebarWidth = sidebarWidth
            self.windowFrame = windowFrame
            self.createdAt = createdAt
            self.updatedAt = updatedAt
        }
    }

    /// Rebuildable cache snapshot persisted separately from canonical state.
    struct PersistableCacheState: Codable {
        var workspaceId: UUID
        var repoEnrichmentByRepoId: [UUID: RepoEnrichment]
        var worktreeEnrichmentByWorktreeId: [UUID: WorktreeEnrichment]
        var pullRequestCountByWorktreeId: [UUID: Int]
        var notificationCountByWorktreeId: [UUID: Int]
        var sourceRevision: UInt64
        var lastRebuiltAt: Date?

        init(
            workspaceId: UUID,
            repoEnrichmentByRepoId: [UUID: RepoEnrichment] = [:],
            worktreeEnrichmentByWorktreeId: [UUID: WorktreeEnrichment] = [:],
            pullRequestCountByWorktreeId: [UUID: Int] = [:],
            notificationCountByWorktreeId: [UUID: Int] = [:],
            sourceRevision: UInt64 = 0,
            lastRebuiltAt: Date? = nil
        ) {
            self.workspaceId = workspaceId
            self.repoEnrichmentByRepoId = repoEnrichmentByRepoId
            self.worktreeEnrichmentByWorktreeId = worktreeEnrichmentByWorktreeId
            self.pullRequestCountByWorktreeId = pullRequestCountByWorktreeId
            self.notificationCountByWorktreeId = notificationCountByWorktreeId
            self.sourceRevision = sourceRevision
            self.lastRebuiltAt = lastRebuiltAt
        }
    }

    /// UI preference snapshot persisted separately from canonical and cache state.
    struct PersistableUIState: Codable {
        var workspaceId: UUID
        var expandedGroups: Set<String>
        var checkoutColors: [String: String]
        var filterText: String
        var isFilterVisible: Bool

        init(
            workspaceId: UUID,
            expandedGroups: Set<String> = [],
            checkoutColors: [String: String] = [:],
            filterText: String = "",
            isFilterVisible: Bool = false
        ) {
            self.workspaceId = workspaceId
            self.expandedGroups = expandedGroups
            self.checkoutColors = checkoutColors
            self.filterText = filterText
            self.isFilterVisible = isFilterVisible
        }
    }

    let workspacesDir: URL

    init(workspacesDir: URL? = nil) {
        if let dir = workspacesDir {
            self.workspacesDir = dir
        } else {
            let appSupport = FileManager.default.homeDirectoryForCurrentUser
                .appending(path: ".agentstudio")
            self.workspacesDir = appSupport.appending(path: "workspaces")
        }
    }

    /// Ensure the storage directory exists.
    func ensureDirectory() {
        do {
            try FileManager.default.createDirectory(
                at: workspacesDir,
                withIntermediateDirectories: true
            )
        } catch {
            persistorLogger.error("Failed to create workspaces directory \(self.workspacesDir.path): \(error)")
        }
    }

    /// Save state to disk. Immediate write with atomic option.
    /// Throws on encoding or write failure so callers can handle.
    func save(_ state: PersistableState) throws {
        let url = canonicalFileURL(for: state.id)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let data = try encoder.encode(state)
        try data.write(to: url, options: .atomic)
    }

    /// Load state from disk. Returns nil if no workspace file exists or schema is incompatible.
    func load() -> PersistableState? {
        let contents: [URL]
        do {
            contents = try FileManager.default.contentsOfDirectory(
                at: workspacesDir,
                includingPropertiesForKeys: nil,
                options: .skipsHiddenFiles
            )
        } catch {
            // Directory doesn't exist yet — fresh install
            return nil
        }

        let workspaceFiles = contents.filter { $0.pathExtension == "json" }

        // Single workspace — load the first one found
        for fileURL in workspaceFiles {
            if let state = decodePersistedState(from: fileURL) {
                return state
            }
        }

        return nil
    }

    func saveCanonical(_ state: PersistableState) throws {
        try save(state)
    }

    func loadCanonical() -> PersistableState? {
        load()
    }

    func saveCache(_ state: PersistableCacheState) throws {
        let url = cacheFileURL(for: state.workspaceId)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(state)
        try data.write(to: url, options: .atomic)
    }

    func loadCache(for workspaceId: UUID) -> PersistableCacheState? {
        decodePersistedState(from: cacheFileURL(for: workspaceId), as: PersistableCacheState.self)
    }

    func saveUI(_ state: PersistableUIState) throws {
        let url = uiFileURL(for: state.workspaceId)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(state)
        try data.write(to: url, options: .atomic)
    }

    func loadUI(for workspaceId: UUID) -> PersistableUIState? {
        decodePersistedState(from: uiFileURL(for: workspaceId), as: PersistableUIState.self)
    }

    /// Load state from a specific file URL (for testing).
    func load(from url: URL) -> PersistableState? {
        decodePersistedState(from: url)
    }

    /// Decode canonical persisted workspace state.
    private func decodePersistedState(from url: URL) -> PersistableState? {
        decodePersistedState(from: url, as: PersistableState.self)
    }

    private func decodePersistedState<T: Decodable>(from url: URL, as type: T.Type) -> T? {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            persistorLogger.error("Failed to read workspace file \(url.lastPathComponent): \(error)")
            return nil
        }

        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            persistorLogger.error("Failed to load workspace file \(url.lastPathComponent): \(error)")
            return nil
        }
    }

    /// Check if any workspace files exist on disk (distinguishes first-launch from load-failure).
    func hasWorkspaceFiles() -> Bool {
        guard
            let contents = try? FileManager.default.contentsOfDirectory(
                at: workspacesDir,
                includingPropertiesForKeys: nil,
                options: .skipsHiddenFiles
            )
        else { return false }
        return contents.contains { $0.pathExtension == "json" }
    }

    /// Delete workspace file.
    func delete(id: UUID) {
        let urls = [
            canonicalFileURL(for: id),
            cacheFileURL(for: id),
            uiFileURL(for: id),
        ]
        for url in urls {
            do {
                try FileManager.default.removeItem(at: url)
            } catch {
                persistorLogger.error("Failed to delete workspace file \(url.lastPathComponent): \(error)")
            }
        }
    }

    // MARK: - Private

    private func canonicalFileURL(for id: UUID) -> URL {
        workspacesDir.appending(path: "\(id.uuidString).workspace.state.json")
    }

    private func cacheFileURL(for id: UUID) -> URL {
        workspacesDir.appending(path: "\(id.uuidString).workspace.cache.json")
    }

    private func uiFileURL(for id: UUID) -> URL {
        workspacesDir.appending(path: "\(id.uuidString).workspace.ui.json")
    }

}
