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
    case unresolved(repoId: UUID)
    case resolved(repoId: UUID, raw: RawRepoOrigin, identity: RepoIdentity, updatedAt: Date)

    var repoId: UUID {
        switch self {
        case .unresolved(let repoId):
            repoId
        case .resolved(let repoId, _, _, _):
            repoId
        }
    }

    var raw: RawRepoOrigin? {
        switch self {
        case .unresolved:
            nil
        case .resolved(_, let raw, _, _):
            raw
        }
    }

    var identity: RepoIdentity? {
        switch self {
        case .unresolved:
            nil
        case .resolved(_, _, let identity, _):
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
}
