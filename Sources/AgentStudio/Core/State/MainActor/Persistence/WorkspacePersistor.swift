import Foundation
import os.log

private let persistorLogger = Logger(subsystem: "com.agentstudio", category: "WorkspacePersistor")

/// Pure persistence I/O for workspace-scoped JSON preferences and caches.
/// Collaborator of the main-actor persistence wrappers — not a public peer.
struct WorkspacePersistor {
    /// Distinguishes "no file found" from "file exists but is corrupt" on load.
    enum LoadResult<T> {
        case loaded(T)
        case missing
        case corrupt(Error)
    }

    static let currentSchemaVersion = 1
    private static let cacheSuffix = ".workspace.cache.json"
    private static let uiSuffix = ".workspace.ui.json"
    private static let sidebarCacheSuffix = ".workspace.sidebar-cache.json"
    private static let inboxSuffix = ".notification-inbox.json"

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

    func saveCache(_ state: PersistableCacheState) throws {
        let url = cacheFileURL(for: state.workspaceId)
        let encoder = makeEncoder()
        let data = try encoder.encode(state)
        try data.write(to: url, options: .atomic)
    }

    func saveUI(_ state: PersistableUIState) throws {
        let url = uiFileURL(for: state.workspaceId)
        let encoder = makeEncoder()
        let data = try encoder.encode(state)
        try data.write(to: url, options: .atomic)
    }

    func saveSidebarCache(_ state: PersistableSidebarCache) throws {
        let url = sidebarCacheFileURL(for: state.workspaceId)
        let encoder = makeEncoder()
        let data = try encoder.encode(state)
        try data.write(to: url, options: .atomic)
    }

    private func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    // MARK: - Load

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
    func quarantineCorruptRepoCacheFile(for workspaceId: UUID) -> URL? {
        quarantineCorruptFile(
            sourceURL: cacheFileURL(for: workspaceId),
            fileName: { timestamp in
                "\(workspaceId.uuidString).workspace.cache.corrupt-\(timestamp).json"
            },
            label: "repo cache"
        )
    }

    @discardableResult
    func quarantineCorruptUIFile(for workspaceId: UUID) -> URL? {
        quarantineCorruptFile(
            sourceURL: uiFileURL(for: workspaceId),
            fileName: { timestamp in
                "\(workspaceId.uuidString).workspace.ui.corrupt-\(timestamp).json"
            },
            label: "UI"
        )
    }

    @discardableResult
    func quarantineCorruptSidebarCacheFile(for workspaceId: UUID) -> URL? {
        quarantineCorruptFile(
            sourceURL: sidebarCacheFileURL(for: workspaceId),
            fileName: { timestamp in
                "\(workspaceId.uuidString).workspace.sidebar-cache.corrupt-\(timestamp).json"
            },
            label: "sidebar cache"
        )
    }

    func hasLegacyCacheFile(for workspaceId: UUID) -> Bool {
        FileManager.default.fileExists(atPath: cacheFileURL(for: workspaceId).path)
    }

    func hasLegacyUIFile(for workspaceId: UUID) -> Bool {
        FileManager.default.fileExists(atPath: uiFileURL(for: workspaceId).path)
    }

    func hasLegacySidebarCacheFile(for workspaceId: UUID) -> Bool {
        FileManager.default.fileExists(atPath: sidebarCacheFileURL(for: workspaceId).path)
    }

    @discardableResult
    private func quarantineCorruptFile(
        sourceURL: URL,
        fileName: (String) -> String,
        label: String
    ) -> URL? {
        guard FileManager.default.fileExists(atPath: sourceURL.path) else {
            return nil
        }

        let timestamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let quarantinedURL = workspacesDir.appending(path: fileName(timestamp))

        do {
            try FileManager.default.moveItem(at: sourceURL, to: quarantinedURL)
            return quarantinedURL
        } catch {
            persistorLogger.error(
                "Failed to quarantine corrupt \(label, privacy: .public) file \(sourceURL.lastPathComponent): \(error)"
            )
            return nil
        }
    }

    // MARK: - Delete

    /// Delete all workspace files for the given workspace ID.
    func delete(id: UUID) {
        let urls = [
            cacheFileURL(for: id),
            uiFileURL(for: id),
            sidebarCacheFileURL(for: id),
            notificationInboxFileURL(for: id),
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
            guard FileManager.default.fileExists(atPath: url.path) else {
                return .missing
            }
            persistorLogger.error(
                "Failed to read workspace file \(url.lastPathComponent): \(error)"
            )
            return .corrupt(error)
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

    private func cacheFileURL(for id: UUID) -> URL {
        workspacesDir.appending(path: "\(id.uuidString)\(Self.cacheSuffix)")
    }

    private func uiFileURL(for id: UUID) -> URL {
        workspacesDir.appending(path: "\(id.uuidString)\(Self.uiSuffix)")
    }

    private func sidebarCacheFileURL(for id: UUID) -> URL {
        workspacesDir.appending(path: "\(id.uuidString)\(Self.sidebarCacheSuffix)")
    }

    func notificationInboxFileURL(for id: UUID) -> URL {
        inboxFileURL(for: id)
    }

    private func inboxFileURL(for id: UUID) -> URL {
        workspacesDir.appending(path: "\(id.uuidString)\(Self.inboxSuffix)")
    }
}
