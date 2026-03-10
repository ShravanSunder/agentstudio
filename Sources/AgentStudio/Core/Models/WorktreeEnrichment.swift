import Foundation

/// Derived worktree metadata computed from git status/projectors.
/// Rebuildable cache data; not canonical workspace identity.
struct WorktreeEnrichment: Codable, Hashable, Sendable {
    let worktreeId: UUID
    let repoId: UUID
    var branch: String
    var isMainWorktree: Bool
    var snapshot: GitWorkingTreeSnapshot?
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case worktreeId
        case repoId
        case branch
        case isMainWorktree
        case updatedAt
    }

    init(
        worktreeId: UUID,
        repoId: UUID,
        branch: String,
        isMainWorktree: Bool = false,
        snapshot: GitWorkingTreeSnapshot? = nil,
        updatedAt: Date = Date()
    ) {
        self.worktreeId = worktreeId
        self.repoId = repoId
        self.branch = branch
        self.isMainWorktree = isMainWorktree
        self.snapshot = snapshot
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.worktreeId = try container.decode(UUID.self, forKey: .worktreeId)
        self.repoId = try container.decode(UUID.self, forKey: .repoId)
        self.branch = try container.decode(String.self, forKey: .branch)
        self.isMainWorktree = try container.decodeIfPresent(Bool.self, forKey: .isMainWorktree) ?? false
        self.updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
        self.snapshot = nil
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(worktreeId, forKey: .worktreeId)
        try container.encode(repoId, forKey: .repoId)
        try container.encode(branch, forKey: .branch)
        try container.encode(isMainWorktree, forKey: .isMainWorktree)
        try container.encode(updatedAt, forKey: .updatedAt)
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.worktreeId == rhs.worktreeId
            && lhs.repoId == rhs.repoId
            && lhs.branch == rhs.branch
            && lhs.isMainWorktree == rhs.isMainWorktree
            && lhs.updatedAt == rhs.updatedAt
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(worktreeId)
        hasher.combine(repoId)
        hasher.combine(branch)
        hasher.combine(isMainWorktree)
        hasher.combine(updatedAt)
    }
}
