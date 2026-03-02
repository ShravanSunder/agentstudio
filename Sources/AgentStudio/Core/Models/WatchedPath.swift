import Foundation

/// A user-added folder path persisted in workspace.state.json.
/// FilesystemActor watches this path with FSEvents and rescans for new repos.
struct WatchedPath: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    var path: URL
    var addedAt: Date

    var stableKey: String { StableKey.fromPath(path) }

    init(id: UUID = UUID(), path: URL, addedAt: Date = Date()) {
        self.id = id
        self.path = path
        self.addedAt = addedAt
    }
}
