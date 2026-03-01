import Foundation

/// Derived repo metadata computed from local/remote git facts.
/// Rebuildable cache data; not canonical workspace identity.
struct RepoEnrichment: Codable, Hashable, Sendable {
    let repoId: UUID
    var organizationName: String?
    var origin: String?
    var upstream: String?
    var remoteSlug: String?
    var groupKey: String?
    var displayName: String?
    var updatedAt: Date

    init(
        repoId: UUID,
        organizationName: String? = nil,
        origin: String? = nil,
        upstream: String? = nil,
        remoteSlug: String? = nil,
        groupKey: String? = nil,
        displayName: String? = nil,
        updatedAt: Date = Date()
    ) {
        self.repoId = repoId
        self.organizationName = organizationName
        self.origin = origin
        self.upstream = upstream
        self.remoteSlug = remoteSlug
        self.groupKey = groupKey
        self.displayName = displayName
        self.updatedAt = updatedAt
    }
}
