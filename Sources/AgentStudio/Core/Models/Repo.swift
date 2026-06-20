import Foundation

/// A git repository that may contain multiple worktrees
struct Repo: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    var name: String
    var repoPath: URL
    var worktrees: [Worktree]
    var createdAt: Date
    var isFavorite: Bool
    var note: String?

    /// Deterministic identity derived from filesystem path via SHA-256.
    /// Used for zmx session ID segment. Survives reinstall/data loss, breaks on directory move.
    var stableKey: String { StableKey.fromPath(repoPath) }

    init(
        id: UUID = UUID(),
        name: String,
        repoPath: URL,
        worktrees: [Worktree] = [],
        createdAt: Date = Date(),
        isFavorite: Bool = false,
        note: String? = nil
    ) {
        self.id = id
        self.name = name
        self.repoPath = repoPath
        self.worktrees = worktrees
        self.createdAt = createdAt
        self.isFavorite = isFavorite
        self.note = note
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.name = try container.decode(String.self, forKey: .name)
        self.repoPath = try container.decode(URL.self, forKey: .repoPath)
        self.worktrees = try container.decode([Worktree].self, forKey: .worktrees)
        self.createdAt = try container.decode(Date.self, forKey: .createdAt)
        self.isFavorite = try container.decodeIfPresent(Bool.self, forKey: .isFavorite) ?? false
        self.note = try container.decodeIfPresent(String.self, forKey: .note)
    }
}
