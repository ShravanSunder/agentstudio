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
        let url = fileURL(for: state.id)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let data = try encoder.encode(state)
        try data.write(to: url, options: .atomic)
    }

    /// Load state from disk. Returns nil if no workspace file exists or schema is incompatible.
    /// Tries the current schema first, then falls back to the legacy (pre-pane-model) schema.
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
            if let state = decodeWithMigration(from: fileURL) {
                return state
            }
        }

        return nil
    }

    /// Load state from a specific file URL (for testing).
    func load(from url: URL) -> PersistableState? {
        decodeWithMigration(from: url)
    }

    /// Try current schema first, then fall back to legacy migration.
    private func decodeWithMigration(from url: URL) -> PersistableState? {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            persistorLogger.error("Failed to read workspace file \(url.lastPathComponent): \(error)")
            return nil
        }

        // Try current schema
        do {
            return try JSONDecoder().decode(PersistableState.self, from: data)
        } catch {
            persistorLogger.info("Current schema decode failed for \(url.lastPathComponent), trying legacy migration")
        }

        // Try legacy schema (pre-pane-model: sessions/views format)
        do {
            let legacy = try JSONDecoder().decode(LegacyPersistableState.self, from: data)
            let migrated = Self.migrate(from: legacy)
            persistorLogger.info("Migrated legacy workspace '\(legacy.name)' (\(legacy.sessions.count) session(s) → \(migrated.panes.count) pane(s))")
            return migrated
        } catch {
            persistorLogger.error("Failed to load workspace file \(url.lastPathComponent) (both current and legacy schemas): \(error)")
            return nil
        }
    }

    /// Check if any workspace files exist on disk (distinguishes first-launch from load-failure).
    func hasWorkspaceFiles() -> Bool {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: workspacesDir,
            includingPropertiesForKeys: nil,
            options: .skipsHiddenFiles
        ) else { return false }
        return contents.contains { $0.pathExtension == "json" }
    }

    /// Delete workspace file.
    func delete(id: UUID) {
        let url = fileURL(for: id)
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            persistorLogger.error("Failed to delete workspace file \(url.lastPathComponent): \(error)")
        }
    }

    // MARK: - Private

    private func fileURL(for id: UUID) -> URL {
        workspacesDir.appending(path: "\(id.uuidString).json")
    }

    // MARK: - Legacy Schema Migration

    /// Convert legacy (pre-pane-model) workspace state to the current schema.
    static func migrate(from legacy: LegacyPersistableState) -> PersistableState {
        // Convert sessions → panes
        let panes: [Pane] = legacy.sessions.map { session in
            Pane(
                id: session.id,
                content: .terminal(TerminalState(
                    provider: session.provider,
                    lifetime: session.lifetime
                )),
                metadata: PaneMetadata(
                    source: session.source,
                    title: session.title,
                    cwd: session.lastKnownCWD,
                    agentType: session.agent
                ),
                residency: session.residency
            )
        }

        // Find the main view (or first available)
        let mainView = legacy.views.first { $0.kind == .main } ?? legacy.views.first

        // Convert old tabs → new tabs
        let tabs: [Tab] = (mainView?.tabs ?? []).map { legacyTab in
            // Layout.Node decoder already handles sessionId → paneId migration
            let layout = legacyTab.layout
            let paneIds = layout.paneIds
            let arrangement = PaneArrangement(
                name: "Default",
                isDefault: true,
                layout: layout,
                visiblePaneIds: Set(paneIds)
            )
            return Tab(
                id: legacyTab.id,
                name: "Tab",
                panes: paneIds,
                arrangements: [arrangement],
                activeArrangementId: arrangement.id,
                activePaneId: legacyTab.activeSessionId ?? paneIds.first
            )
        }

        let activeTabId = mainView?.activeTabId ?? tabs.first?.id

        return PersistableState(
            id: legacy.id,
            name: legacy.name,
            repos: legacy.repos,
            panes: panes,
            tabs: tabs,
            activeTabId: activeTabId,
            sidebarWidth: legacy.sidebarWidth,
            windowFrame: legacy.windowFrame,
            createdAt: legacy.createdAt,
            updatedAt: legacy.updatedAt
        )
    }
}

// MARK: - Legacy Schema Types

/// Pre-pane-model workspace format. Used only for migration from old on-disk data.
struct LegacyPersistableState: Codable {
    var id: UUID
    var name: String
    var repos: [Repo]
    var sessions: [LegacySession]
    var views: [LegacyView]
    var activeViewId: UUID?
    var sidebarWidth: CGFloat
    var windowFrame: CGRect?
    var createdAt: Date
    var updatedAt: Date
}

struct LegacySession: Codable {
    let id: UUID
    var source: TerminalSource
    var title: String
    var agent: AgentType?
    var provider: SessionProvider
    var lifetime: SessionLifetime
    var residency: SessionResidency
    var lastKnownCWD: URL?
}

struct LegacyView: Codable {
    let id: UUID
    var name: String
    var kind: LegacyViewKind
    var tabs: [LegacyTab]
    var activeTabId: UUID?
}

enum LegacyViewKind: Codable, Equatable {
    case main
    case saved
    case worktree(worktreeId: UUID)
    case dynamic(rule: LegacyDynamicViewRule)
}

enum LegacyDynamicViewRule: Codable, Hashable {
    case byRepo(repoId: UUID)
    case byAgent(AgentType)
    case custom(name: String)
}

struct LegacyTab: Codable {
    let id: UUID
    var layout: Layout
    var activeSessionId: UUID?
}
