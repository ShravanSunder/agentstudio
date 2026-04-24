import Foundation
import os.log

private let persistorLogger = Logger(subsystem: "com.agentstudio", category: "WorkspacePersistor")

private func decodeRecoverableField<Key: CodingKey, Value: Decodable>(
    _ type: Value.Type,
    from container: KeyedDecodingContainer<Key>,
    forKey key: Key,
    schemaVersion: Int,
    payloadName: String,
    default defaultValue: @autoclosure () -> Value
) -> Value {
    do {
        if let value = try container.decodeIfPresent(type, forKey: key) {
            return value
        }
    } catch {
        persistorLogger.warning(
            "\(payloadName, privacy: .public) schemaVersion=\(schemaVersion) invalid field \(key.stringValue, privacy: .public); using default"
        )
        return defaultValue()
    }

    if schemaVersion >= 1 {
        persistorLogger.warning(
            "\(payloadName, privacy: .public) schemaVersion=\(schemaVersion) missing field \(key.stringValue, privacy: .public); using default"
        )
    }
    return defaultValue()
}

/// Pure persistence I/O for workspace state.
/// Collaborator of the main-actor persistence wrappers — not a public peer.
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

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let schemaVersion =
                (try? container.decode(Int.self, forKey: .schemaVersion))
                ?? WorkspacePersistor.currentSchemaVersion
            func decodeField<Value: Decodable>(
                _ type: Value.Type,
                forKey key: CodingKeys,
                default defaultValue: @autoclosure () -> Value
            ) -> Value {
                decodeRecoverableField(
                    type,
                    from: container,
                    forKey: key,
                    schemaVersion: schemaVersion,
                    payloadName: "PersistableState",
                    default: defaultValue()
                )
            }

            self.schemaVersion = schemaVersion
            self.id = decodeField(UUID.self, forKey: .id, default: UUID())
            self.name = decodeField(String.self, forKey: .name, default: "Default Workspace")
            self.repos = decodeField([CanonicalRepo].self, forKey: .repos, default: [])
            self.worktrees = decodeField([CanonicalWorktree].self, forKey: .worktrees, default: [])
            self.unavailableRepoIds = decodeField(Set<UUID>.self, forKey: .unavailableRepoIds, default: [])
            self.panes = decodeField([Pane].self, forKey: .panes, default: [])
            self.tabs = decodeField([Tab].self, forKey: .tabs, default: [])
            self.activeTabId = decodeField(UUID?.self, forKey: .activeTabId, default: nil)
            self.sidebarWidth = decodeField(CGFloat.self, forKey: .sidebarWidth, default: 250)
            self.windowFrame = decodeField(CGRect?.self, forKey: .windowFrame, default: nil)
            self.watchedPaths = decodeField([WatchedPath].self, forKey: .watchedPaths, default: [])
            self.createdAt = decodeField(Date.self, forKey: .createdAt, default: Date())
            self.updatedAt = decodeField(Date.self, forKey: .updatedAt, default: Date())
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
            let schemaVersion =
                (try? container.decode(Int.self, forKey: .schemaVersion))
                ?? WorkspacePersistor.currentSchemaVersion

            self.schemaVersion = schemaVersion
            self.workspaceId = decodeRecoverableField(
                UUID.self,
                from: container,
                forKey: .workspaceId,
                schemaVersion: schemaVersion,
                payloadName: "PersistableCacheState",
                default: UUID()
            )
            self.repoEnrichmentByRepoId = decodeRecoverableField(
                [UUID: RepoEnrichment].self,
                from: container,
                forKey: .repoEnrichmentByRepoId,
                schemaVersion: schemaVersion,
                payloadName: "PersistableCacheState",
                default: [:]
            )
            self.worktreeEnrichmentByWorktreeId = decodeRecoverableField(
                [UUID: WorktreeEnrichment].self,
                from: container,
                forKey: .worktreeEnrichmentByWorktreeId,
                schemaVersion: schemaVersion,
                payloadName: "PersistableCacheState",
                default: [:]
            )
            self.pullRequestCountByWorktreeId = decodeRecoverableField(
                [UUID: Int].self,
                from: container,
                forKey: .pullRequestCountByWorktreeId,
                schemaVersion: schemaVersion,
                payloadName: "PersistableCacheState",
                default: [:]
            )
            self.notificationCountByWorktreeId = decodeRecoverableField(
                [UUID: Int].self,
                from: container,
                forKey: .notificationCountByWorktreeId,
                schemaVersion: schemaVersion,
                payloadName: "PersistableCacheState",
                default: [:]
            )
            self.recentTargets = decodeRecoverableField(
                [RecentWorkspaceTarget].self,
                from: container,
                forKey: .recentTargets,
                schemaVersion: schemaVersion,
                payloadName: "PersistableCacheState",
                default: []
            )
            self.sourceRevision = decodeRecoverableField(
                UInt64.self,
                from: container,
                forKey: .sourceRevision,
                schemaVersion: schemaVersion,
                payloadName: "PersistableCacheState",
                default: 0
            )
            self.lastRebuiltAt = decodeRecoverableField(
                Date?.self,
                from: container,
                forKey: .lastRebuiltAt,
                schemaVersion: schemaVersion,
                payloadName: "PersistableCacheState",
                default: nil
            )
        }

    }

    /// UI preference snapshot persisted separately from canonical and cache state.
    struct PersistableUIState: Codable {
        struct PersistedEditorChooserState: Codable {
            var bookmarkedEditorId: EditorTargetId?
        }

        var schemaVersion: Int
        var workspaceId: UUID
        var filterText: String
        var isFilterVisible: Bool
        var showMinimizedBars: Bool
        var sidebarCollapsed: Bool
        var sidebarSurface: SidebarSurface
        var editorChooserState: PersistedEditorChooserState

        init(
            workspaceId: UUID,
            filterText: String = "",
            isFilterVisible: Bool = false,
            showMinimizedBars: Bool = true,
            sidebarCollapsed: Bool = false,
            sidebarSurface: SidebarSurface = .repos,
            editorChooserState: PersistedEditorChooserState = .init()
        ) {
            self.schemaVersion = WorkspacePersistor.currentSchemaVersion
            self.workspaceId = workspaceId
            self.filterText = filterText
            self.isFilterVisible = isFilterVisible
            self.showMinimizedBars = showMinimizedBars
            self.sidebarCollapsed = sidebarCollapsed
            self.sidebarSurface = sidebarSurface
            self.editorChooserState = editorChooserState
        }

        private enum CodingKeys: String, CodingKey {
            case schemaVersion
            case workspaceId
            case filterText
            case isFilterVisible
            case showMinimizedBars
            case sidebarCollapsed
            case sidebarSurface
            case editorChooserState
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let schemaVersion =
                (try? container.decode(Int.self, forKey: .schemaVersion))
                ?? WorkspacePersistor.currentSchemaVersion

            self.schemaVersion = schemaVersion
            self.workspaceId = decodeRecoverableField(
                UUID.self,
                from: container,
                forKey: .workspaceId,
                schemaVersion: schemaVersion,
                payloadName: "PersistableUIState",
                default: UUID()
            )
            self.filterText = decodeRecoverableField(
                String.self,
                from: container,
                forKey: .filterText,
                schemaVersion: schemaVersion,
                payloadName: "PersistableUIState",
                default: ""
            )
            self.isFilterVisible = decodeRecoverableField(
                Bool.self,
                from: container,
                forKey: .isFilterVisible,
                schemaVersion: schemaVersion,
                payloadName: "PersistableUIState",
                default: false
            )
            self.showMinimizedBars = decodeRecoverableField(
                Bool.self,
                from: container,
                forKey: .showMinimizedBars,
                schemaVersion: schemaVersion,
                payloadName: "PersistableUIState",
                default: true
            )
            self.sidebarCollapsed = decodeRecoverableField(
                Bool.self,
                from: container,
                forKey: .sidebarCollapsed,
                schemaVersion: schemaVersion,
                payloadName: "PersistableUIState",
                default: false
            )
            self.sidebarSurface = decodeRecoverableField(
                SidebarSurface.self,
                from: container,
                forKey: .sidebarSurface,
                schemaVersion: schemaVersion,
                payloadName: "PersistableUIState",
                default: .repos
            )
            self.editorChooserState = decodeRecoverableField(
                PersistedEditorChooserState.self,
                from: container,
                forKey: .editorChooserState,
                schemaVersion: schemaVersion,
                payloadName: "PersistableUIState",
                default: .init()
            )
        }

    }

    /// Durable sidebar memory persisted separately from shell composition state.
    struct PersistableSidebarCache: Codable {
        var schemaVersion: Int
        var workspaceId: UUID
        var expandedGroups: Set<String>
        var checkoutColors: [String: String]
        var collapsedInboxGroups: Set<String>

        init(
            workspaceId: UUID,
            expandedGroups: Set<String> = [],
            checkoutColors: [String: String] = [:],
            collapsedInboxGroups: Set<String> = []
        ) {
            self.schemaVersion = WorkspacePersistor.currentSchemaVersion
            self.workspaceId = workspaceId
            self.expandedGroups = expandedGroups
            self.checkoutColors = checkoutColors
            self.collapsedInboxGroups = collapsedInboxGroups
        }

        private enum CodingKeys: String, CodingKey {
            case schemaVersion
            case workspaceId
            case expandedGroups
            case checkoutColors
            case collapsedInboxGroups
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let schemaVersion =
                (try? container.decode(Int.self, forKey: .schemaVersion))
                ?? WorkspacePersistor.currentSchemaVersion

            self.schemaVersion = schemaVersion
            self.workspaceId = decodeRecoverableField(
                UUID.self,
                from: container,
                forKey: .workspaceId,
                schemaVersion: schemaVersion,
                payloadName: "PersistableSidebarCache",
                default: UUID()
            )
            self.expandedGroups = decodeRecoverableField(
                Set<String>.self,
                from: container,
                forKey: .expandedGroups,
                schemaVersion: schemaVersion,
                payloadName: "PersistableSidebarCache",
                default: []
            )
            self.checkoutColors = decodeRecoverableField(
                [String: String].self,
                from: container,
                forKey: .checkoutColors,
                schemaVersion: schemaVersion,
                payloadName: "PersistableSidebarCache",
                default: [:]
            )
            self.collapsedInboxGroups = decodeRecoverableField(
                Set<String>.self,
                from: container,
                forKey: .collapsedInboxGroups,
                schemaVersion: schemaVersion,
                payloadName: "PersistableSidebarCache",
                default: []
            )
        }
    }

    // MARK: - Properties

    let workspacesDir: URL

    init(workspacesDir: URL? = nil) {
        if let dir = workspacesDir {
            self.workspacesDir = dir
        } else {
            self.workspacesDir = AppDataPaths.workspacesDirectory()
        }
    }

    /// Ensure the storage directory exists.
    @discardableResult
    func ensureDirectory() -> Bool {
        do {
            try FileManager.default.createDirectory(
                at: workspacesDir,
                withIntermediateDirectories: true
            )
            return true
        } catch {
            persistorLogger.error(
                "Failed to create workspaces directory \(self.workspacesDir.path): \(error)"
            )
            return false
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

    func saveSidebarCache(_ state: PersistableSidebarCache) throws {
        let url = sidebarCacheFileURL(for: state.workspaceId)
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

    func loadSidebarCache(for workspaceId: UUID) -> LoadResult<PersistableSidebarCache> {
        decodeFromFile(sidebarCacheFileURL(for: workspaceId), as: PersistableSidebarCache.self)
    }

    @discardableResult
    func quarantineCorruptUIFile(for workspaceId: UUID) -> URL? {
        let sourceURL = uiFileURL(for: workspaceId)
        guard FileManager.default.fileExists(atPath: sourceURL.path) else {
            return nil
        }

        let timestamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let quarantinedURL = workspacesDir.appending(
            path: "\(workspaceId.uuidString).workspace.ui.corrupt-\(timestamp).json"
        )

        do {
            try FileManager.default.moveItem(at: sourceURL, to: quarantinedURL)
            return quarantinedURL
        } catch {
            persistorLogger.error(
                "Failed to quarantine corrupt UI file \(sourceURL.lastPathComponent): \(error)"
            )
            return nil
        }
    }

    @discardableResult
    func quarantineCorruptSidebarCacheFile(for workspaceId: UUID) -> URL? {
        let sourceURL = sidebarCacheFileURL(for: workspaceId)
        guard FileManager.default.fileExists(atPath: sourceURL.path) else {
            return nil
        }

        let timestamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let quarantinedURL = workspacesDir.appending(
            path: "\(workspaceId.uuidString).workspace.sidebar-cache.corrupt-\(timestamp).json"
        )

        do {
            try FileManager.default.moveItem(at: sourceURL, to: quarantinedURL)
            return quarantinedURL
        } catch {
            persistorLogger.error(
                "Failed to quarantine corrupt sidebar cache file \(sourceURL.lastPathComponent): \(error)"
            )
            return nil
        }
    }

    // MARK: - Delete

    /// Delete all workspace files for the given workspace ID.
    func delete(id: UUID) {
        let urls = [
            canonicalFileURL(for: id),
            cacheFileURL(for: id),
            uiFileURL(for: id),
            sidebarCacheFileURL(for: id),
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

    private func sidebarCacheFileURL(for id: UUID) -> URL {
        workspacesDir.appending(path: "\(id.uuidString).workspace.sidebar-cache.json")
    }
}
