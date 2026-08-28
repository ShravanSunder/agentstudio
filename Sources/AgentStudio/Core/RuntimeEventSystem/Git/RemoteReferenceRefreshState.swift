import AgentStudioGit
import Foundation

struct RemoteReferenceRegistration: Sendable {
    let repoId: UUID
    var repositoryPath: URL
    var remoteName: String
    var expectedOrigin: String?
    var topologyGeneration: UInt64
    var worktreeIds: Set<UUID>
}

package enum RemoteReferenceAuthorityUpdate: Sendable {
    case invalidated(repoId: UUID, topologyGeneration: UInt64, authorityRevision: UInt64)
    case localAccepted(RemoteReferenceAcceptance)
    case promoted(RemoteReferenceAcceptance, representedWorktreeIds: Set<UUID>)

    package var repoId: UUID {
        switch self {
        case .invalidated(let repoId, _, _): repoId
        case .localAccepted(let acceptance), .promoted(let acceptance, _): acceptance.repoId
        }
    }

    package var authorityRevision: UInt64 {
        switch self {
        case .invalidated(_, _, let authorityRevision): authorityRevision
        case .localAccepted(let acceptance), .promoted(let acceptance, _): acceptance.authorityRevision
        }
    }
}

struct RemoteReferenceAttempt: Sendable {
    let repoId: UUID
    let repositoryPath: URL
    let remoteName: String
    let expectedOrigin: String
    let topologyGeneration: UInt64
    let stagingId: UUID
}

struct RemoteReferenceExplicitUpdateAttempt {
    let repoId: UUID
    let topologyGeneration: UInt64
    let expectedOrigin: String
    let settlement: RepositoryFactSourceUpdateSettlement
}

enum RemoteReferenceStagingOutcome: Sendable {
    case failed(RemoteReferenceAttempt)
    case obsolete(RemoteReferenceAttempt)
    case staged(RemoteReferenceAttempt, GitStagedFetchResult)

    var attempt: RemoteReferenceAttempt {
        switch self {
        case .failed(let attempt), .obsolete(let attempt), .staged(let attempt, _): attempt
        }
    }
}

enum RemoteReferencePromotionOutcome: Sendable {
    case failed(RemoteReferenceAttempt, GitStagedFetchResult)
    case promoted(RemoteReferenceAttempt, GitStagedFetchResult)

    var attempt: RemoteReferenceAttempt {
        switch self {
        case .failed(let attempt, _), .promoted(let attempt, _): attempt
        }
    }

    var stagedFetch: GitStagedFetchResult {
        switch self {
        case .failed(_, let stagedFetch), .promoted(_, let stagedFetch): stagedFetch
        }
    }
}

enum RemoteReferenceActiveOperation {
    case staging(RemoteReferenceAttempt, Task<RemoteReferenceStagingOutcome, Never>)
    case promoting(
        RemoteReferenceAttempt,
        GitStagedFetchResult,
        Task<RemoteReferencePromotionOutcome, Never>
    )

    var attempt: RemoteReferenceAttempt {
        switch self {
        case .staging(let attempt, _), .promoting(let attempt, _, _): attempt
        }
    }
}
