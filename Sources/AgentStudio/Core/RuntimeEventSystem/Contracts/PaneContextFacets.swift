import Foundation

/// Canonical source context carried by pane metadata and runtime envelopes.
///
/// This is the single shared context shape for pane/worktree/repo identity facets.
/// All fields are optional because not every pane participates in every grouping
/// dimension.
package struct PaneContextFacets: Codable, Hashable, Sendable {
    package var repoId: UUID?
    package var repoName: String?
    package var worktreeId: UUID?
    package var worktreeName: String?
    package var cwd: URL?
    package var parentFolder: String?
    package var organizationName: String?
    package var origin: String?
    package var upstream: String?

    package init(
        repoId: UUID? = nil,
        repoName: String? = nil,
        worktreeId: UUID? = nil,
        worktreeName: String? = nil,
        cwd: URL? = nil,
        parentFolder: String? = nil,
        organizationName: String? = nil,
        origin: String? = nil,
        upstream: String? = nil
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
    }

    package static let empty = Self()

    /// Returns a copy where nil/empty fields are filled from defaults.
    package func fillingNilFields(from defaults: Self) -> Self {
        Self(
            repoId: repoId ?? defaults.repoId,
            repoName: repoName ?? defaults.repoName,
            worktreeId: worktreeId ?? defaults.worktreeId,
            worktreeName: worktreeName ?? defaults.worktreeName,
            cwd: cwd ?? defaults.cwd,
            parentFolder: parentFolder ?? defaults.parentFolder,
            organizationName: organizationName ?? defaults.organizationName,
            origin: origin ?? defaults.origin,
            upstream: upstream ?? defaults.upstream
        )
    }

    /// Returns facets with explicit worktree scope overlaid for envelope migration.
    package func withWorktreeScope(repoId: UUID, worktreeId: UUID?) -> Self {
        var updated = self
        updated.repoId = repoId
        updated.worktreeId = worktreeId
        return updated
    }

    static func from(worktreeEnvelope: WorktreeEnvelope) -> Self {
        Self(repoId: worktreeEnvelope.repoId, worktreeId: worktreeEnvelope.worktreeId)
    }
}
