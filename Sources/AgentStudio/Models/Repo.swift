import Foundation

/// A git repository that may contain multiple worktrees
struct Repo: Codable, Identifiable, Hashable {
    let id: UUID
    var name: String
    var repoPath: URL
    var worktrees: [Worktree]
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        repoPath: URL,
        worktrees: [Worktree] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.repoPath = repoPath
        self.worktrees = worktrees
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
