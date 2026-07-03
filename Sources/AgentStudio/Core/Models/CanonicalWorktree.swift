import Foundation

/// Canonical worktree identity persisted in workspace state.
/// Stores stable linkage to a canonical repo and user-visible naming.
struct CanonicalWorktree: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let repoId: UUID
    var name: String
    var path: URL
    var isMainWorktree: Bool
    var tags: [String]

    /// Deterministic identity derived from filesystem path via SHA-256.
    var stableKey: String { StableKey.fromPath(path) }

    init(
        id: UUID = UUID(),
        repoId: UUID,
        name: String,
        path: URL,
        isMainWorktree: Bool = false,
        tags: [String] = []
    ) {
        self.id = id
        self.repoId = repoId
        self.name = name
        self.path = path
        self.isMainWorktree = isMainWorktree
        self.tags = tags
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.repoId = try container.decode(UUID.self, forKey: .repoId)
        self.name = try container.decode(String.self, forKey: .name)
        self.path = try container.decode(URL.self, forKey: .path)
        self.isMainWorktree = try container.decode(Bool.self, forKey: .isMainWorktree)
        self.tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
    }
}
