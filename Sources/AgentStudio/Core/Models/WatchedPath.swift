import AgentStudioInfrastructure
import Foundation

/// A user-added folder path persisted through the workspace SQLite topology store.
/// FilesystemActor watches this path with FSEvents and rescans for new repos.
package struct WatchedPath: Codable, Identifiable, Hashable, Sendable {
    package let id: UUID
    package private(set) var path: URL
    var addedAt: Date

    var stableKey: String { StableKey.fromPath(path) }

    init(id: UUID = UUIDv7.generate(), path: URL, addedAt: Date = Date()) {
        self.id = id
        self.path = path
        self.addedAt = addedAt
    }
}
