import Foundation

/// Canonical worktree identity persisted in workspace state.
/// Stores stable linkage to a canonical repo and user-visible naming.
struct CanonicalWorktree: Codable, Identifiable, Hashable {
    let id: UUID
    let repoId: UUID
    var name: String
    var path: URL
    var isMainWorktree: Bool

    /// Deterministic identity derived from filesystem path via SHA-256.
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
}
