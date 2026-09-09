import Foundation

/// Canonical repo identity persisted in workspace state.
/// Contains only stable/user-intent fields; no derived git enrichment.
struct CanonicalRepo: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    var name: String
    var repoPath: URL
    let stableKey: String
    var createdAt: Date
    var isFavorite: Bool
    var note: String?
    var tags: [String]

    init(
        id: UUID = UUID(),
        name: String,
        repoPath: URL,
        stableKey: String? = nil,
        createdAt: Date = Date(),
        isFavorite: Bool = false,
        note: String? = nil,
        tags: [String] = []
    ) {
        self.id = id
        self.name = name
        self.repoPath = repoPath
        self.stableKey = stableKey ?? StableKey.fromPath(repoPath)
        self.createdAt = createdAt
        self.isFavorite = isFavorite
        self.note = note
        self.tags = tags
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.name = try container.decode(String.self, forKey: .name)
        self.repoPath = try container.decode(URL.self, forKey: .repoPath)
        self.stableKey =
            try container.decodeIfPresent(String.self, forKey: .stableKey)
            ?? StableKey.fromPath(repoPath)
        self.createdAt = try container.decode(Date.self, forKey: .createdAt)
        self.isFavorite = try container.decodeIfPresent(Bool.self, forKey: .isFavorite) ?? false
        self.note = try container.decodeIfPresent(String.self, forKey: .note)
        self.tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
    }
}
