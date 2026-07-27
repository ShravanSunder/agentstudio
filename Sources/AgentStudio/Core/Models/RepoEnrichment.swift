import Foundation

/// Derived repo metadata computed from local/remote git facts.
/// Rebuildable cache data; not canonical workspace identity.
package struct RawRepoOrigin: Codable, Hashable, Sendable {
    package let origin: String?
    package let upstream: String?

    package init(origin: String?, upstream: String?) {
        self.origin = origin
        self.upstream = upstream
    }
}

package struct RepoIdentity: Codable, Hashable, Sendable {
    package let groupKey: String
    package let remoteSlug: String?
    package let organizationName: String?
    package let displayName: String

    package init(
        groupKey: String,
        remoteSlug: String?,
        organizationName: String?,
        displayName: String
    ) {
        self.groupKey = groupKey
        self.remoteSlug = remoteSlug
        self.organizationName = organizationName
        self.displayName = displayName
    }
}

package enum RepoEnrichment: Codable, Hashable, Sendable {
    case awaitingOrigin(repoId: UUID)
    case resolvedLocal(repoId: UUID, identity: RepoIdentity, updatedAt: Date)
    case resolvedRemote(repoId: UUID, raw: RawRepoOrigin, identity: RepoIdentity, updatedAt: Date)

    package var repoId: UUID {
        switch self {
        case .awaitingOrigin(let repoId):
            repoId
        case .resolvedLocal(let repoId, _, _):
            repoId
        case .resolvedRemote(let repoId, _, _, _):
            repoId
        }
    }

    var raw: RawRepoOrigin? {
        switch self {
        case .awaitingOrigin, .resolvedLocal:
            nil
        case .resolvedRemote(_, let raw, _, _):
            raw
        }
    }

    var identity: RepoIdentity? {
        switch self {
        case .awaitingOrigin:
            nil
        case .resolvedLocal(_, let identity, _):
            identity
        case .resolvedRemote(_, _, let identity, _):
            identity
        }
    }

    var origin: String? {
        raw?.origin
    }

    var upstream: String? {
        raw?.upstream
    }

    var groupKey: String? {
        identity?.groupKey
    }

    package var remoteSlug: String? {
        identity?.remoteSlug
    }

    var organizationName: String? {
        identity?.organizationName
    }

    var displayName: String? {
        identity?.displayName
    }

    func hasSameCacheContent(as other: Self) -> Bool {
        switch (self, other) {
        case (.awaitingOrigin(let lhsRepoId), .awaitingOrigin(let rhsRepoId)):
            lhsRepoId == rhsRepoId
        case (
            .resolvedLocal(let lhsRepoId, let lhsIdentity, _),
            .resolvedLocal(let rhsRepoId, let rhsIdentity, _)
        ):
            lhsRepoId == rhsRepoId && lhsIdentity == rhsIdentity
        case (
            .resolvedRemote(let lhsRepoId, let lhsRaw, let lhsIdentity, _),
            .resolvedRemote(let rhsRepoId, let rhsRaw, let rhsIdentity, _)
        ):
            lhsRepoId == rhsRepoId && lhsRaw == rhsRaw && lhsIdentity == rhsIdentity
        case (.awaitingOrigin, .resolvedLocal),
            (.awaitingOrigin, .resolvedRemote),
            (.resolvedLocal, .awaitingOrigin),
            (.resolvedLocal, .resolvedRemote),
            (.resolvedRemote, .awaitingOrigin),
            (.resolvedRemote, .resolvedLocal):
            false
        }
    }
}
