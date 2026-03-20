import Foundation

/// A git worktree within a repo — structure-only.
/// All enrichment data (branch, status) comes from WorkspaceRepoCache via the event bus.
struct Worktree: Codable, Identifiable, Hashable {
    let id: UUID
    let repoId: UUID
    var name: String
    var path: URL
    var isMainWorktree: Bool

    /// Deterministic identity derived from filesystem path via SHA-256.
    /// Used for zmx session ID segment. Survives reinstall/data loss, breaks on directory move.
    var stableKey: String { StableKey.fromPath(path) }

    init(
        id: UUID = UUID(),
        repoId: UUID,
        name: String,
        path: URL,
        isMainWorktree: Bool = false
    ) {
        self.id = id
        self.repoId = repoId
        self.name = name
        self.path = path
        self.isMainWorktree = isMainWorktree
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.repoId = try container.decode(UUID.self, forKey: .repoId)
        self.name = try container.decode(String.self, forKey: .name)
        self.path = try container.decode(URL.self, forKey: .path)
        self.isMainWorktree = try container.decode(Bool.self, forKey: .isMainWorktree)
    }
}
