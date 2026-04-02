import Foundation

/// Cache-backed recent launcher target for workspace tabless states.
/// Derived activity metadata only — never canonical workspace structure.
struct RecentWorkspaceTarget: Codable, Hashable, Sendable, Identifiable {
    enum Kind: String, Codable, Sendable {
        case worktree
        case cwdOnly
    }

    let id: String
    let path: URL
    let displayTitle: String
    let subtitle: String
    let repoId: UUID?
    let worktreeId: UUID?
    let kind: Kind
    let lastOpenedAt: Date

    static func forWorktree(
        path: URL,
        worktree: Worktree,
        repo: Repo,
        displayTitle: String? = nil,
        subtitle: String? = nil,
        lastOpenedAt: Date = Date()
    ) -> Self {
        let normalizedPath = path.standardizedFileURL
        return Self(
            id: "worktree:\(worktree.id.uuidString)",
            path: normalizedPath,
            displayTitle: displayTitle ?? worktree.name,
            subtitle: subtitle ?? repo.name,
            repoId: repo.id,
            worktreeId: worktree.id,
            kind: .worktree,
            lastOpenedAt: lastOpenedAt
        )
    }

    static func forCwd(
        _ path: URL,
        title: String? = nil,
        subtitle: String? = nil,
        lastOpenedAt: Date = Date()
    ) -> Self {
        let normalizedPath = path.standardizedFileURL
        let trimmedTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackTitle =
            normalizedPath.lastPathComponent.isEmpty ? normalizedPath.path : normalizedPath.lastPathComponent

        return Self(
            id: "cwd:\(normalizedPath.path)",
            path: normalizedPath,
            displayTitle: (trimmedTitle?.isEmpty == false) ? trimmedTitle! : fallbackTitle,
            subtitle: subtitle ?? normalizedPath.path,
            kind: .cwdOnly,
            lastOpenedAt: lastOpenedAt
        )
    }

    /// Raw initializer kept for Codable/test construction.
    /// Production code should prefer `forWorktree` / `forCwd` so the dedup id
    /// and referent-shape invariants stay centralized.
    private init(
        id: String,
        path: URL,
        displayTitle: String,
        subtitle: String = "",
        repoId: UUID? = nil,
        worktreeId: UUID? = nil,
        kind: Kind,
        lastOpenedAt: Date = Date()
    ) {
        self.id = id
        self.path = path
        self.displayTitle = displayTitle
        self.subtitle = subtitle
        self.repoId = repoId
        self.worktreeId = worktreeId
        self.kind = kind
        self.lastOpenedAt = lastOpenedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case path
        case displayTitle
        case subtitle
        case repoId
        case worktreeId
        case kind
        case lastOpenedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let id = try container.decode(String.self, forKey: .id)
        let path = try container.decode(URL.self, forKey: .path).standardizedFileURL
        let displayTitle = try container.decode(String.self, forKey: .displayTitle)
        let subtitle = try container.decodeIfPresent(String.self, forKey: .subtitle) ?? path.path
        let repoId = try container.decodeIfPresent(UUID.self, forKey: .repoId)
        let worktreeId = try container.decodeIfPresent(UUID.self, forKey: .worktreeId)
        let kind = try container.decode(Kind.self, forKey: .kind)
        let lastOpenedAt = try container.decode(Date.self, forKey: .lastOpenedAt)

        switch kind {
        case .worktree:
            guard repoId != nil, worktreeId != nil else {
                throw DecodingError.dataCorruptedError(
                    forKey: .kind,
                    in: container,
                    debugDescription: "worktree targets require repoId and worktreeId"
                )
            }
        case .cwdOnly:
            guard repoId == nil, worktreeId == nil else {
                throw DecodingError.dataCorruptedError(
                    forKey: .kind,
                    in: container,
                    debugDescription: "cwdOnly targets may not include repoId or worktreeId"
                )
            }
        }

        self.init(
            id: id,
            path: path,
            displayTitle: displayTitle,
            subtitle: subtitle,
            repoId: repoId,
            worktreeId: worktreeId,
            kind: kind,
            lastOpenedAt: lastOpenedAt
        )
    }
}
