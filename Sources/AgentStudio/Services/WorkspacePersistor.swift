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
            do {
                let data = try Data(contentsOf: fileURL)

                let loaded = try JSONDecoder().decode(PersistableState.self, from: data)
                return loaded
            } catch {
                persistorLogger.error("Failed to load workspace file \(fileURL.lastPathComponent): \(error)")
            }
        }

        return nil
    }

    /// Load state from a specific file URL (for testing).
    func load(from url: URL) -> PersistableState? {
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(PersistableState.self, from: data)
        } catch {
            persistorLogger.error("Failed to load workspace from \(url.lastPathComponent): \(error)")
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

}
