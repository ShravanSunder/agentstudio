import Foundation

/// Canonical repo identity persisted in workspace state.
/// Contains only stable/user-intent fields; no derived git enrichment.
struct CanonicalRepo: Codable, Identifiable, Hashable {
    let id: UUID
    var name: String
    var repoPath: URL
    var createdAt: Date

    /// Deterministic identity derived from filesystem path via SHA-256.
    var stableKey: String { StableKey.fromPath(repoPath) }

    init(
        id: UUID = UUID(),
        name: String,
        repoPath: URL,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.repoPath = repoPath
        self.createdAt = createdAt
    }
}
