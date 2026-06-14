import Foundation

/// Derived repo metadata computed from local/remote git facts.
/// Rebuildable cache data; not canonical workspace identity.
struct RawRepoOrigin: Codable, Hashable, Sendable {
    let origin: String?
    let upstream: String?
}

struct RepoIdentity: Codable, Hashable, Sendable {
    let groupKey: String
    let remoteSlug: String?
    let organizationName: String?
    let displayName: String
}

enum RepoEnrichment: Codable, Hashable, Sendable {
    case awaitingOrigin(repoId: UUID)
    case resolvedLocal(repoId: UUID, identity: RepoIdentity, updatedAt: Date)
    case resolvedRemote(repoId: UUID, raw: RawRepoOrigin, identity: RepoIdentity, updatedAt: Date)

    var repoId: UUID {
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

    var remoteSlug: String? {
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
