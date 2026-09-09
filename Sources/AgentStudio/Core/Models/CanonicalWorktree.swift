import Foundation

/// Canonical worktree identity persisted in workspace state.
/// Stores stable linkage to a canonical repo and user-visible naming.
struct CanonicalWorktree: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let repoId: UUID
    var name: String
    var path: URL
    let stableKey: String
    var isMainWorktree: Bool
    var note: String?

    init(
        id: UUID = UUID(),
        repoId: UUID,
        name: String,
        path: URL,
        stableKey: String? = nil,
        isMainWorktree: Bool = false,
        note: String? = nil
    ) {
        self.id = id
        self.repoId = repoId
        self.name = name
        self.path = path
        self.stableKey = stableKey ?? StableKey.fromPath(path)
        self.isMainWorktree = isMainWorktree
        self.note = note
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.repoId = try container.decode(UUID.self, forKey: .repoId)
        self.name = try container.decode(String.self, forKey: .name)
        self.path = try container.decode(URL.self, forKey: .path)
        self.stableKey =
            try container.decodeIfPresent(String.self, forKey: .stableKey)
            ?? StableKey.fromPath(path)
        self.isMainWorktree = try container.decode(Bool.self, forKey: .isMainWorktree)
        self.note = try container.decodeIfPresent(String.self, forKey: .note)
    }
}
