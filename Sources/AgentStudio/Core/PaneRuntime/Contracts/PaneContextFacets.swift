import Foundation

/// Canonical source context carried by pane metadata and runtime envelopes.
///
/// This is the single shared context shape for pane/worktree/repo identity facets.
/// All fields are optional except `tags`, because not every pane participates in
/// every grouping dimension.
struct PaneContextFacets: Codable, Hashable, Sendable {
    var repoId: UUID?
    var repoName: String?
    var worktreeId: UUID?
    var worktreeName: String?
    var cwd: URL?
    var parentFolder: String?
    var organizationName: String?
    var origin: String?
    var upstream: String?
    var tags: [String]

    init(
        repoId: UUID? = nil,
        repoName: String? = nil,
        worktreeId: UUID? = nil,
        worktreeName: String? = nil,
        cwd: URL? = nil,
        parentFolder: String? = nil,
        organizationName: String? = nil,
        origin: String? = nil,
        upstream: String? = nil,
        tags: [String] = []
    ) {
        self.repoId = repoId
        self.repoName = repoName
        self.worktreeId = worktreeId
        self.worktreeName = worktreeName
        self.cwd = cwd
        self.parentFolder = parentFolder
        self.organizationName = organizationName
        self.origin = origin
        self.upstream = upstream
        self.tags = tags
    }

    static let empty = Self()

    /// Returns a copy where nil/empty fields are filled from defaults.
    func fillingNilFields(from defaults: Self) -> Self {
        Self(
            repoId: repoId ?? defaults.repoId,
            repoName: repoName ?? defaults.repoName,
            worktreeId: worktreeId ?? defaults.worktreeId,
            worktreeName: worktreeName ?? defaults.worktreeName,
            cwd: cwd ?? defaults.cwd,
            parentFolder: parentFolder ?? defaults.parentFolder,
            organizationName: organizationName ?? defaults.organizationName,
            origin: origin ?? defaults.origin,
            upstream: upstream ?? defaults.upstream,
            tags: tags.isEmpty ? defaults.tags : tags
        )
    }
}
