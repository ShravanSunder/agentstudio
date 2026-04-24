import Foundation
import os.log

private let persistorLogger = Logger(subsystem: "com.agentstudio", category: "WorkspacePersistor")

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
        let encoder = makeEncoder()
        let data = try encoder.encode(state)
        try data.write(to: url, options: .atomic)
    }

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
