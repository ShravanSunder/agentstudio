import Foundation
import os.log

private let persistorLogger = Logger(subsystem: "com.agentstudio", category: "WorkspacePersistor")

/// Pure persistence I/O for workspace state.
/// Collaborator of the main-actor persistence wrappers — not a public peer.
struct WorkspacePersistor {
    struct CanonicalQuarantineResult: Sendable, Equatable {
        let workspaceId: UUID?
        let quarantinedFilenames: [String]
        let failed: Bool

        var recoveryFilename: String? {
            guard !quarantinedFilenames.isEmpty else { return nil }
            return quarantinedFilenames.joined(separator: ", ")
        }

        var recovery: PersistenceRecoveryEvent.Recovery {
            failed ? .quarantineFailed : .quarantinedAndReset
        }
    }

    struct LegacyArchiveResult: Sendable, Equatable {
        let archiveDirectoryName: String
        let archivedFilenames: [String]
        let failedFilenames: [String]

        var succeeded: Bool {
            !archivedFilenames.isEmpty && failedFilenames.isEmpty
        }
    }

    /// Distinguishes "no file found" from "file exists but is corrupt" on load.
    enum LoadResult<T> {
        case loaded(T)
        case missing
        case corrupt(Error)
    }

    static let currentSchemaVersion = 1
    private static let canonicalSuffix = ".workspace.state.json"
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

        let canonicalFiles =
            contents
            .filter { $0.lastPathComponent.hasSuffix(Self.canonicalSuffix) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        guard let fileURL = canonicalFiles.first else {
            return .missing
        }
        if canonicalFiles.count > 1 {
            persistorLogger.warning(
                "Found \(canonicalFiles.count, privacy: .public) canonical workspace files; loading deterministic first file \(fileURL.lastPathComponent, privacy: .public)"
            )
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
    func quarantineCorruptCanonicalWorkspaceFiles() -> CanonicalQuarantineResult? {
        let contents: [URL]
        do {
            contents = try FileManager.default.contentsOfDirectory(
                at: workspacesDir,
                includingPropertiesForKeys: nil,
                options: .skipsHiddenFiles
            )
        } catch {
            persistorLogger.error(
                "Failed to list workspace directory before quarantining corrupt canonical workspace: \(error)"
            )
            return CanonicalQuarantineResult(
                workspaceId: nil,
                quarantinedFilenames: [],
                failed: true
            )
        }

        guard let canonicalURL = contents.first(where: { $0.lastPathComponent.hasSuffix(Self.canonicalSuffix) })
        else {
            return nil
        }

        let workspaceId = workspaceIdFromCanonicalFile(canonicalURL)
        let timestamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        var quarantinedFilenames: [String] = []

        let candidates = canonicalRecoveryCandidates(
            canonicalURL: canonicalURL,
            workspaceId: workspaceId
        )

        for candidate in candidates where FileManager.default.fileExists(atPath: candidate.sourceURL.path) {
            let quarantinedURL = workspacesDir.appending(path: candidate.quarantinedName(timestamp))
            do {
                try FileManager.default.moveItem(at: candidate.sourceURL, to: quarantinedURL)
                quarantinedFilenames.append(quarantinedURL.lastPathComponent)
            } catch {
                persistorLogger.error(
                    "Failed to quarantine corrupt workspace file \(candidate.sourceURL.lastPathComponent, privacy: .public): \(error)"
                )
            }
        }

        return CanonicalQuarantineResult(
            workspaceId: workspaceId,
            quarantinedFilenames: quarantinedFilenames,
            failed: quarantinedFilenames.isEmpty
        )
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

    @discardableResult
    func archiveLegacyWorkspaceFiles(for workspaceId: UUID) -> LegacyArchiveResult? {
        let candidates = legacyWorkspaceFileURLs(for: workspaceId)
            .filter { FileManager.default.fileExists(atPath: $0.path) }
        guard !candidates.isEmpty else { return nil }

        let archiveDirectoryName = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let archiveDirectory =
            workspacesDir
            .appending(path: "legacy-imported")
            .appending(path: archiveDirectoryName)
        do {
            try FileManager.default.createDirectory(
                at: archiveDirectory,
                withIntermediateDirectories: true
            )
        } catch {
            persistorLogger.error(
                "Failed to create legacy workspace archive directory \(archiveDirectory.path): \(error)"
            )
            return LegacyArchiveResult(
                archiveDirectoryName: archiveDirectoryName,
                archivedFilenames: [],
                failedFilenames: candidates.map(\.lastPathComponent)
            )
        }

        var archivedPairs: [(sourceURL: URL, destinationURL: URL)] = []
        for (index, sourceURL) in candidates.enumerated() {
            let destinationURL = archiveDirectory.appending(path: sourceURL.lastPathComponent)
            do {
                try FileManager.default.moveItem(at: sourceURL, to: destinationURL)
                archivedPairs.append((sourceURL: sourceURL, destinationURL: destinationURL))
            } catch {
                persistorLogger.error(
                    "Failed to archive legacy workspace file \(sourceURL.lastPathComponent): \(error)"
                )
                var rollbackFailures: [String] = []
                for pair in archivedPairs.reversed() {
                    do {
                        try FileManager.default.moveItem(at: pair.destinationURL, to: pair.sourceURL)
                    } catch {
                        rollbackFailures.append(pair.destinationURL.lastPathComponent)
                        persistorLogger.error(
                            "Failed to roll back archived legacy workspace file \(pair.destinationURL.lastPathComponent): \(error)"
                        )
                    }
                }
                try? FileManager.default.removeItem(at: archiveDirectory)
                let unarchivedFailures = candidates[index...].map(\.lastPathComponent)
                return LegacyArchiveResult(
                    archiveDirectoryName: archiveDirectoryName,
                    archivedFilenames: rollbackFailures,
                    failedFilenames: unarchivedFailures + rollbackFailures
                )
            }
        }

        return LegacyArchiveResult(
            archiveDirectoryName: archiveDirectoryName,
            archivedFilenames: archivedPairs.map { $0.sourceURL.lastPathComponent },
            failedFilenames: []
        )
    }

    func canonicalWorkspaceStatePath(for workspaceId: UUID) -> String {
        canonicalFileURL(for: workspaceId).path
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

    private struct RecoveryCandidate {
        let sourceURL: URL
        let quarantinedName: (String) -> String
    }

    private func canonicalRecoveryCandidates(
        canonicalURL: URL,
        workspaceId: UUID?
    ) -> [RecoveryCandidate] {
        var candidates = [
            RecoveryCandidate(sourceURL: canonicalURL) { timestamp in
                "\(canonicalURL.deletingPathExtension().lastPathComponent).corrupt-\(timestamp).json"
            }
        ]
        guard let workspaceId else { return candidates }
        candidates.append(
            contentsOf: [
                RecoveryCandidate(sourceURL: cacheFileURL(for: workspaceId)) { timestamp in
                    "\(workspaceId.uuidString).workspace.cache.corrupt-\(timestamp).json"
                },
                RecoveryCandidate(sourceURL: uiFileURL(for: workspaceId)) { timestamp in
                    "\(workspaceId.uuidString).workspace.ui.corrupt-\(timestamp).json"
                },
                RecoveryCandidate(sourceURL: sidebarCacheFileURL(for: workspaceId)) { timestamp in
                    "\(workspaceId.uuidString).workspace.sidebar-cache.corrupt-\(timestamp).json"
                },
                RecoveryCandidate(sourceURL: inboxFileURL(for: workspaceId)) { timestamp in
                    "\(workspaceId.uuidString).notification-inbox.corrupt-\(timestamp).json"
                },
            ]
        )
        return candidates
    }

    private func legacyWorkspaceFileURLs(for workspaceId: UUID) -> [URL] {
        [
            canonicalFileURL(for: workspaceId),
            cacheFileURL(for: workspaceId),
            uiFileURL(for: workspaceId),
            sidebarCacheFileURL(for: workspaceId),
            inboxFileURL(for: workspaceId),
        ]
    }

    private func workspaceIdFromCanonicalFile(_ url: URL) -> UUID? {
        let fileName = url.lastPathComponent
        guard fileName.hasSuffix(Self.canonicalSuffix) else { return nil }
        let rawId = String(fileName.dropLast(Self.canonicalSuffix.count))
        return UUID(uuidString: rawId)
    }

    // MARK: - Delete

    /// Delete all workspace files for the given workspace ID.
    func delete(id: UUID) {
        let urls = [
            canonicalFileURL(for: id),
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

    private func canonicalFileURL(for id: UUID) -> URL {
        workspacesDir.appending(path: "\(id.uuidString)\(Self.canonicalSuffix)")
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
