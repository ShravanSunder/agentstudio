import Foundation
import os.log

private let persistorPayloadLogger = Logger(
    subsystem: "com.agentstudio",
    category: "WorkspacePersistor.Payloads"
)

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
        persistorPayloadLogger.warning(
            "\(payloadName, privacy: .public) schemaVersion=\(schemaVersion) invalid field \(key.stringValue, privacy: .public); using default"
        )
        return defaultValue()
    }

    if schemaVersion >= 1 {
        persistorPayloadLogger.warning(
            "\(payloadName, privacy: .public) schemaVersion=\(schemaVersion) missing field \(key.stringValue, privacy: .public); using default"
        )
    }
    return defaultValue()
}

/// Decodes the on-disk schema as a file-level invariant.
///
/// Recoverable slices may default, but an unsupported schema means the file
/// may have different semantics from this binary and must be quarantined by
/// the owning store instead of silently interpreted as v1.
private func decodeSupportedSchemaVersion<Key: CodingKey>(
    from container: KeyedDecodingContainer<Key>,
    forKey key: Key,
    payloadName: String
) throws -> Int {
    let decodedVersion = try container.decode(Int.self, forKey: key)
    guard decodedVersion == WorkspacePersistor.currentSchemaVersion else {
        persistorPayloadLogger.warning(
            "\(payloadName, privacy: .public) schemaVersion=\(decodedVersion) is unsupported; treating file as corrupt"
        )
        throw DecodingError.dataCorruptedError(
            forKey: key,
            in: container,
            debugDescription: "\(payloadName) schemaVersion \(decodedVersion) is unsupported"
        )
    }
    return decodedVersion
}

/// Decodes identity fields as file-level invariants, not recoverable slices.
private func decodeRequiredIdentity<Key: CodingKey, Value: Decodable>(
    _ type: Value.Type,
    from container: KeyedDecodingContainer<Key>,
    forKey key: Key,
    payloadName: String
) throws -> Value {
    do {
        return try container.decode(type, forKey: key)
    } catch {
        persistorPayloadLogger.warning(
            "\(payloadName, privacy: .public) invalid identity field \(key.stringValue, privacy: .public); treating file as corrupt"
        )
        throw error
    }
}

/// Decodes canonical state slices whose absence changes workspace semantics.
private func decodeRequiredCanonicalField<Key: CodingKey, Value: Decodable>(
    _ type: Value.Type,
    from container: KeyedDecodingContainer<Key>,
    forKey key: Key,
    payloadName: String
) throws -> Value {
    do {
        return try container.decode(type, forKey: key)
    } catch {
        persistorPayloadLogger.warning(
            "\(payloadName, privacy: .public) invalid canonical field \(key.stringValue, privacy: .public); treating file as corrupt"
        )
        throw error
    }
}

extension WorkspacePersistor {
    /// Legacy JSON workspace payload.
    ///
    /// This remains the pre-SQLite import/export contract only. The rich
    /// `Pane` and `Tab` values are decoded here so `WorkspacePersistenceTransformer`
    /// can field-route them into split graph/cursor/presentation owners; they are
    /// not future SQLite row projections.
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
            let schemaVersion = try decodeSupportedSchemaVersion(
                from: container,
                forKey: .schemaVersion,
                payloadName: "PersistableState"
            )
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
            self.id = try decodeRequiredIdentity(
                UUID.self,
                from: container,
                forKey: .id,
                payloadName: "PersistableState"
            )
            self.name = decodeField(String.self, forKey: .name, default: "Default Workspace")
            self.repos = decodeField([CanonicalRepo].self, forKey: .repos, default: [])
            self.worktrees = decodeField([CanonicalWorktree].self, forKey: .worktrees, default: [])
            self.unavailableRepoIds = decodeField(Set<UUID>.self, forKey: .unavailableRepoIds, default: [])
            self.panes = try decodeRequiredCanonicalField(
                [Pane].self,
                from: container,
                forKey: .panes,
                payloadName: "PersistableState"
            )
            self.tabs = try decodeRequiredCanonicalField(
                [Tab].self,
                from: container,
                forKey: .tabs,
                payloadName: "PersistableState"
            )
            self.activeTabId = decodeField(UUID?.self, forKey: .activeTabId, default: nil)
            self.sidebarWidth = decodeField(CGFloat.self, forKey: .sidebarWidth, default: 250)
            self.windowFrame = decodeField(CGRect?.self, forKey: .windowFrame, default: nil)
            self.watchedPaths = decodeField([WatchedPath].self, forKey: .watchedPaths, default: [])
            self.createdAt = decodeField(Date.self, forKey: .createdAt, default: Date())
            self.updatedAt = decodeField(Date.self, forKey: .updatedAt, default: Date())
        }
    }

    /// Cache companion snapshot persisted separately from canonical state.
    /// Enrichment fields are rebuildable; recent targets are local UX memory.
    struct PersistableCacheState: Codable {
        var schemaVersion: Int
        var workspaceId: UUID
        var repoEnrichmentByRepoId: [UUID: RepoEnrichment]
        var worktreeEnrichmentByWorktreeId: [UUID: WorktreeEnrichment]
        var pullRequestCountByWorktreeId: [UUID: Int]
        var recentTargets: [RecentWorkspaceTarget]
        var sourceRevision: UInt64
        var lastRebuiltAt: Date?

        init(
            workspaceId: UUID,
            repoEnrichmentByRepoId: [UUID: RepoEnrichment] = [:],
            worktreeEnrichmentByWorktreeId: [UUID: WorktreeEnrichment] = [:],
            pullRequestCountByWorktreeId: [UUID: Int] = [:],
            recentTargets: [RecentWorkspaceTarget] = [],
            sourceRevision: UInt64 = 0,
            lastRebuiltAt: Date? = nil
        ) {
            self.schemaVersion = WorkspacePersistor.currentSchemaVersion
            self.workspaceId = workspaceId
            self.repoEnrichmentByRepoId = repoEnrichmentByRepoId
            self.worktreeEnrichmentByWorktreeId = worktreeEnrichmentByWorktreeId
            self.pullRequestCountByWorktreeId = pullRequestCountByWorktreeId
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
            case recentTargets
            case sourceRevision
            case lastRebuiltAt
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let schemaVersion = try decodeSupportedSchemaVersion(
                from: container,
                forKey: .schemaVersion,
                payloadName: "PersistableCacheState"
            )

            self.schemaVersion = schemaVersion
            self.workspaceId = try decodeRequiredIdentity(
                UUID.self,
                from: container,
                forKey: .workspaceId,
                payloadName: "PersistableCacheState"
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
        var sidebarCollapsed: Bool
        var sidebarSurface: SidebarSurface
        var editorChooserState: PersistedEditorChooserState

        init(
            workspaceId: UUID,
            filterText: String = "",
            isFilterVisible: Bool = false,
            sidebarCollapsed: Bool = false,
            sidebarSurface: SidebarSurface = .repos,
            editorChooserState: PersistedEditorChooserState = .init()
        ) {
            self.schemaVersion = WorkspacePersistor.currentSchemaVersion
            self.workspaceId = workspaceId
            self.filterText = filterText
            self.isFilterVisible = isFilterVisible
            self.sidebarCollapsed = sidebarCollapsed
            self.sidebarSurface = sidebarSurface
            self.editorChooserState = editorChooserState
        }

        private enum CodingKeys: String, CodingKey {
            case schemaVersion
            case workspaceId
            case filterText
            case isFilterVisible
            case sidebarCollapsed
            case sidebarSurface
            case editorChooserState
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let schemaVersion = try decodeSupportedSchemaVersion(
                from: container,
                forKey: .schemaVersion,
                payloadName: "PersistableUIState"
            )

            self.schemaVersion = schemaVersion
            self.workspaceId = try decodeRequiredIdentity(
                UUID.self,
                from: container,
                forKey: .workspaceId,
                payloadName: "PersistableUIState"
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
        var expandedGroups: Set<SidebarGroupKey>
        var checkoutColors: [SidebarCheckoutColorKey: String]

        init(
            workspaceId: UUID,
            expandedGroups: Set<SidebarGroupKey> = [],
            checkoutColors: [SidebarCheckoutColorKey: String] = [:]
        ) {
            self.schemaVersion = WorkspacePersistor.currentSchemaVersion
            self.workspaceId = workspaceId
            self.expandedGroups = expandedGroups
            self.checkoutColors = checkoutColors
        }

        private enum CodingKeys: String, CodingKey {
            case schemaVersion
            case workspaceId
            case expandedGroups
            case checkoutColors
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let schemaVersion = try decodeSupportedSchemaVersion(
                from: container,
                forKey: .schemaVersion,
                payloadName: "PersistableSidebarCache"
            )

            self.schemaVersion = schemaVersion
            self.workspaceId = try decodeRequiredIdentity(
                UUID.self,
                from: container,
                forKey: .workspaceId,
                payloadName: "PersistableSidebarCache"
            )
            self.expandedGroups = decodeRecoverableField(
                Set<SidebarGroupKey>.self,
                from: container,
                forKey: .expandedGroups,
                schemaVersion: schemaVersion,
                payloadName: "PersistableSidebarCache",
                default: []
            )
            let rawCheckoutColors = decodeRecoverableField(
                [String: String].self,
                from: container,
                forKey: .checkoutColors,
                schemaVersion: schemaVersion,
                payloadName: "PersistableSidebarCache",
                default: [:]
            )
            self.checkoutColors = Dictionary(
                uniqueKeysWithValues: rawCheckoutColors.map { key, value in
                    (SidebarCheckoutColorKey(key), value)
                }
            )
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(schemaVersion, forKey: .schemaVersion)
            try container.encode(workspaceId, forKey: .workspaceId)
            try container.encode(expandedGroups, forKey: .expandedGroups)
            try container.encode(
                Dictionary(uniqueKeysWithValues: checkoutColors.map { key, value in (key.rawValue, value) }),
                forKey: .checkoutColors
            )
        }
    }
}
