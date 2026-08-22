import AppKit
import Foundation

struct RepoExplorerMaterializationHostLifetimeID: Hashable, Sendable {
    let rawValue: UUID
}

struct RepoExplorerMaterializationCandidateID: Hashable, Sendable {
    let rawValue: UInt64
}

struct RepoExplorerMaterializationFingerprint: Equatable, Sendable {
    let rawValue: UInt64

    static func make(snapshot: RepoExplorerMaterializationSnapshot) -> Self {
        var hasher = Hasher()
        hasher.combine(snapshot.rows.count)
        for row in snapshot.rows {
            hasher.combine(row.id)
            hasher.combine(String(reflecting: row.contentRevision))
            hasher.combine(String(reflecting: row.layout))
            hasher.combine(row.representedRepoID)
            hasher.combine(row.representedWorktreeID)
        }
        return Self(rawValue: UInt64(bitPattern: Int64(hasher.finalize())))
    }
}

enum RepoExplorerRowlessPresentation: CaseIterable, Equatable, Sendable {
    case noRepositories
    case noPanes
    case noTabs
    case searchNoResults

    init?(emptyState: RepoExplorerEmptyState) {
        switch emptyState {
        case .content: return nil
        case .noRepositories: self = .noRepositories
        case .noPanes: self = .noPanes
        case .noTabs: self = .noTabs
        case .searchNoResults: self = .searchNoResults
        }
    }

    var emptyState: RepoExplorerEmptyState {
        switch self {
        case .noRepositories: .noRepositories
        case .noPanes: .noPanes
        case .noTabs: .noTabs
        case .searchNoResults: .searchNoResults
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .noRepositories: "No repositories"
        case .noPanes: "No panes"
        case .noTabs: "No tabs"
        case .searchNoResults: "No results"
        }
    }

    fileprivate var fingerprint: RepoExplorerMaterializationFingerprint {
        switch self {
        case .noRepositories: RepoExplorerMaterializationFingerprint(rawValue: 1)
        case .noPanes: RepoExplorerMaterializationFingerprint(rawValue: 2)
        case .noTabs: RepoExplorerMaterializationFingerprint(rawValue: 3)
        case .searchNoResults: RepoExplorerMaterializationFingerprint(rawValue: 4)
        }
    }
}

enum RepoExplorerMaterializationPresentation: Equatable, Sendable {
    case rowless(RepoExplorerRowlessPresentation)
    case content(
        snapshot: RepoExplorerMaterializationSnapshot,
        fingerprint: RepoExplorerMaterializationFingerprint
    )

    var rowCount: Int {
        switch self {
        case .rowless: 0
        case .content(let snapshot, _): snapshot.rows.count
        }
    }

    var fingerprint: RepoExplorerMaterializationFingerprint {
        switch self {
        case .rowless(let presentation): presentation.fingerprint
        case .content(_, let fingerprint): fingerprint
        }
    }

    var rowlessPresentation: RepoExplorerRowlessPresentation? {
        guard case .rowless(let presentation) = self else { return nil }
        return presentation
    }

    var contentSnapshot: RepoExplorerMaterializationSnapshot? {
        guard case .content(let snapshot, _) = self else { return nil }
        return snapshot
    }

    func hasSameVisibleIdentity(as other: Self) -> Bool {
        switch (self, other) {
        case (.rowless(let lhs), .rowless(let rhs)):
            lhs == rhs
        case (.content, .content):
            rowCount == other.rowCount && fingerprint == other.fingerprint
        case (.rowless, .content), (.content, .rowless):
            false
        }
    }
}

struct RepoExplorerMaterializationBaseline: Equatable, Sendable {
    let lifetimeID: RepoExplorerMaterializationHostLifetimeID
    let demandEpoch: UInt64
    let revision: UInt64
    let visibleGeneration: UInt64
    let presentation: RepoExplorerMaterializationPresentation

    var rowCount: Int { presentation.rowCount }
    var fingerprint: RepoExplorerMaterializationFingerprint { presentation.fingerprint }
}

struct RepoExplorerMaterializationCandidate: Equatable, Sendable {
    let id: RepoExplorerMaterializationCandidateID
    let lifetimeID: RepoExplorerMaterializationHostLifetimeID
    let demandEpoch: UInt64
    let visibleGeneration: UInt64
    let expectedRevision: UInt64
    let proposedRevision: UInt64
    let presentation: RepoExplorerMaterializationPresentation
}

enum RepoExplorerMaterializationFeedbackIdentity: Equatable, Sendable {
    case initial
    case candidate(RepoExplorerMaterializationCandidateID)
    case reentry
}

enum RepoExplorerMaterializationRejectionReason: Equatable, Sendable {
    case hostDetached
    case demandSuspended
    case candidateInProgress
    case lifetimeMismatch
    case demandEpochMismatch
    case revisionMismatch
    case generationNotNewer
    case invalidRevisionTransition
    case childRejected
    case childDispositionInvariant
}

enum RepoExplorerMaterializationFeedback: Equatable, Sendable {
    case accepted(
        identity: RepoExplorerMaterializationFeedbackIdentity,
        baseline: RepoExplorerMaterializationBaseline
    )
    case rejected(
        candidateID: RepoExplorerMaterializationCandidateID,
        reason: RepoExplorerMaterializationRejectionReason
    )
}

enum RepoExplorerMaterializationApplyDisposition: Equatable, Sendable {
    case equal(RepoExplorerMaterializationBaseline)
    case accepted(RepoExplorerMaterializationBaseline)
    case rejected(RepoExplorerMaterializationRejectionReason)
}

enum RepoExplorerMaterializationChildDisposition: Equatable, Sendable {
    case accepted
    case rejected
}

@MainActor
protocol RepoExplorerMaterializationContentChild: AnyObject {
    var view: NSView { get }

    func apply(
        snapshot: RepoExplorerMaterializationSnapshot,
        visibleGeneration: UInt64,
        completion: @escaping (RepoExplorerMaterializationChildDisposition) -> Void
    )

    func prepareForRemoval(
        visibleGeneration: UInt64,
        completion: @escaping (RepoExplorerMaterializationChildDisposition) -> Void
    )

    func detach()
}
