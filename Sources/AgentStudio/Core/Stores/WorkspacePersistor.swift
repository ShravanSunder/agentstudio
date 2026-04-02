import Foundation
import os.log

private let persistorLogger = Logger(subsystem: "com.agentstudio", category: "WorkspacePersistor")

/// Pure persistence I/O for workspace state.
/// Collaborator of WorkspaceStore — not a public peer.
struct WorkspacePersistor {

    /// Distinguishes "no file found" from "file exists but is corrupt" on load.
    enum LoadResult<T> {
        case loaded(T)
        case missing
        case corrupt(Error)
    }

    static let currentSchemaVersion = 1
    private static let canonicalSuffix = ".workspace.state.json"

    // MARK: - Persistable Structs

    /// On-disk representation of workspace state.
    struct PersistableState: Codable {
        var schemaVersion: Int
        var id: UUID
        var name: String
        var repos: [CanonicalRepo]
        var worktrees: [CanonicalWorktree]
        var unavailableRepoIds: Set<UUID>
        var panes: [Pane]
        var tabs: [Tab]
        var activeTabId: UUID?
        var sidebarWidth: CGFloat
        var windowFrame: CGRect?
        var watchedPaths: [WatchedPath]
        var createdAt: Date
        var updatedAt: Date

        enum CodingKeys: String, CodingKey {
            case schemaVersion, id, name, repos, worktrees, unavailableRepoIds
            case panes, tabs, activeTabId, sidebarWidth, windowFrame
            case watchedPaths, createdAt, updatedAt
        }

        init(
            id: UUID = UUID(),
            name: String = "Default Workspace",
            repos: [CanonicalRepo] = [],
            worktrees: [CanonicalWorktree] = [],
            unavailableRepoIds: Set<UUID> = [],
            panes: [Pane] = [],
            tabs: [Tab] = [],
            activeTabId: UUID? = nil,
            sidebarWidth: CGFloat = 250,
            windowFrame: CGRect? = nil,
            watchedPaths: [WatchedPath] = [],
            createdAt: Date = Date(),
            updatedAt: Date = Date()
        ) {
            self.schemaVersion = WorkspacePersistor.currentSchemaVersion
            self.id = id
            self.name = name
            self.repos = repos
            self.worktrees = worktrees
            self.unavailableRepoIds = unavailableRepoIds
            self.panes = panes
            self.tabs = tabs
            self.activeTabId = activeTabId
            self.sidebarWidth = sidebarWidth
            self.windowFrame = windowFrame
            self.watchedPaths = watchedPaths
            self.createdAt = createdAt
            self.updatedAt = updatedAt
        }

    }

    /// Rebuildable cache snapshot persisted separately from canonical state.
    struct PersistableCacheState: Codable {
        var schemaVersion: Int
        var workspaceId: UUID
        var repoEnrichmentByRepoId: [UUID: RepoEnrichment]
        var worktreeEnrichmentByWorktreeId: [UUID: WorktreeEnrichment]
        var pullRequestCountByWorktreeId: [UUID: Int]
        var notificationCountByWorktreeId: [UUID: Int]
        var recentTargets: [RecentWorkspaceTarget]
        var sourceRevision: UInt64
        var lastRebuiltAt: Date?

        init(
            workspaceId: UUID,
            repoEnrichmentByRepoId: [UUID: RepoEnrichment] = [:],
            worktreeEnrichmentByWorktreeId: [UUID: WorktreeEnrichment] = [:],
            pullRequestCountByWorktreeId: [UUID: Int] = [:],
            notificationCountByWorktreeId: [UUID: Int] = [:],
            recentTargets: [RecentWorkspaceTarget] = [],
            sourceRevision: UInt64 = 0,
            lastRebuiltAt: Date? = nil
        ) {
            self.schemaVersion = WorkspacePersistor.currentSchemaVersion
            self.workspaceId = workspaceId
            self.repoEnrichmentByRepoId = repoEnrichmentByRepoId
            self.worktreeEnrichmentByWorktreeId = worktreeEnrichmentByWorktreeId
            self.pullRequestCountByWorktreeId = pullRequestCountByWorktreeId
            self.notificationCountByWorktreeId = notificationCountByWorktreeId
            self.recentTargets = recentTargets
            self.sourceRevision = sourceRevision
            self.lastRebuiltAt = lastRebuiltAt
        }

        private enum CodingKeys: String, CodingKey {
            case schemaVersion
            case workspaceId
            case repoEnrichmentByRepoId
            case worktreeEnrichmentByWorktreeId
            case pullRequestCountByWorktreeId
            case notificationCountByWorktreeId
            case recentTargets
            case sourceRevision
            case lastRebuiltAt
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
            self.workspaceId = try container.decode(UUID.self, forKey: .workspaceId)
            self.repoEnrichmentByRepoId = try container.decode(
                [UUID: RepoEnrichment].self,
                forKey: .repoEnrichmentByRepoId
            )
            self.worktreeEnrichmentByWorktreeId = try container.decode(
                [UUID: WorktreeEnrichment].self,
                forKey: .worktreeEnrichmentByWorktreeId
            )
            self.pullRequestCountByWorktreeId = try container.decode(
                [UUID: Int].self,
                forKey: .pullRequestCountByWorktreeId
            )
            self.notificationCountByWorktreeId = try container.decode(
                [UUID: Int].self,
                forKey: .notificationCountByWorktreeId
            )
            self.recentTargets =
                try container.decodeIfPresent(
                    [RecentWorkspaceTarget].self,
                    forKey: .recentTargets
                )
                ?? []
            self.sourceRevision = try container.decode(UInt64.self, forKey: .sourceRevision)
            self.lastRebuiltAt = try container.decodeIfPresent(
                Date.self,
                forKey: .lastRebuiltAt
            )
        }

    }

    /// UI preference snapshot persisted separately from canonical and cache state.
    struct PersistableUIState: Codable {
        var schemaVersion: Int
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
            self.schemaVersion = WorkspacePersistor.currentSchemaVersion
            self.workspaceId = workspaceId
            self.expandedGroups = expandedGroups
            self.checkoutColors = checkoutColors
            self.filterText = filterText
            self.isFilterVisible = isFilterVisible
        }

    }

    // MARK: - Properties

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
            persistorLogger.error(
                "Failed to create workspaces directory \(self.workspacesDir.path): \(error)"
            )
        }
    }

    // MARK: - Save

    /// Save state to disk. Immediate write with atomic option.
    /// Throws on encoding or write failure so callers can handle.
    func save(_ state: PersistableState) throws {
        let url = canonicalFileURL(for: state.id)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let data = try encoder.encode(state)
        try data.write(to: url, options: .atomic)
    }

    func saveCache(_ state: PersistableCacheState) throws {
        let url = cacheFileURL(for: state.workspaceId)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(state)
        try data.write(to: url, options: .atomic)
    }

    func saveUI(_ state: PersistableUIState) throws {
        let url = uiFileURL(for: state.workspaceId)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(state)
        try data.write(to: url, options: .atomic)
    }

    // MARK: - Load

    /// Load canonical workspace state from disk.
    /// Scans for files matching the `*.workspace.state.json` suffix convention.
    func load() -> LoadResult<PersistableState> {
        let contents: [URL]
        do {
            contents = try FileManager.default.contentsOfDirectory(
                at: workspacesDir,
                includingPropertiesForKeys: nil,
                options: .skipsHiddenFiles
            )
        } catch {
            // Directory doesn't exist yet — fresh install
            return .missing
        }

        let canonicalFiles = contents.filter {
            $0.lastPathComponent.hasSuffix(Self.canonicalSuffix)
        }

        guard let fileURL = canonicalFiles.first else {
            return .missing
        }

        return decodeFromFile(fileURL, as: PersistableState.self)
    }

    func loadCache(for workspaceId: UUID) -> LoadResult<PersistableCacheState> {
        decodeFromFile(cacheFileURL(for: workspaceId), as: PersistableCacheState.self)
    }

    func loadUI(for workspaceId: UUID) -> LoadResult<PersistableUIState> {
        decodeFromFile(uiFileURL(for: workspaceId), as: PersistableUIState.self)
    }

    // MARK: - Delete

    /// Delete all workspace files for the given workspace ID.
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
                persistorLogger.error(
                    "Failed to delete workspace file \(url.lastPathComponent): \(error)"
                )
            }
        }
    }

    // MARK: - Private

    private func decodeFromFile<T: Decodable>(
        _ url: URL,
        as type: T.Type
    ) -> LoadResult<T> {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            // File doesn't exist or can't be read — treat as missing.
            return .missing
        }

        do {
            let decoded = try JSONDecoder().decode(type, from: data)
            return .loaded(decoded)
        } catch {
            persistorLogger.error(
                "Failed to decode workspace file \(url.lastPathComponent): \(error)"
            )
            return .corrupt(error)
        }
    }

    private func canonicalFileURL(for id: UUID) -> URL {
        workspacesDir.appending(path: "\(id.uuidString)\(Self.canonicalSuffix)")
    }

    private func cacheFileURL(for id: UUID) -> URL {
        workspacesDir.appending(path: "\(id.uuidString).workspace.cache.json")
    }

    private func uiFileURL(for id: UUID) -> URL {
        workspacesDir.appending(path: "\(id.uuidString).workspace.ui.json")
    }
}
