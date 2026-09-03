import Foundation

enum WorktreeAnnotationSessionLifecycle: String, Codable, CaseIterable, Sendable {
    case living
    case completed
}

enum WorktreeAnnotationSourceRelationship: String, Codable, CaseIterable, Sendable {
    case applicable
    case uncertain
    case detached
}

enum WorktreeAnnotationPlacement: String, Codable, CaseIterable, Sendable {
    case exact
    case relocated
    case outdated
    case unavailable
}

enum WorktreeAnnotationThreadScope: String, Codable, CaseIterable, Sendable {
    case located
    case wholeFile = "whole_file"
    case session
}

enum WorktreeAnnotationThreadResolution: String, Codable, CaseIterable, Sendable {
    case open
    case resolved
}

enum WorktreeAnnotationMessageStatus: String, Codable, CaseIterable, Sendable {
    case editable
    case locked
}

enum WorktreeAnnotationAuthorKind: String, Codable, CaseIterable, Sendable {
    case human
    case agent
}

enum WorktreeAnnotationAttentionState: String, Codable, CaseIterable, Sendable {
    case notApplicable = "not_applicable"
    case new
    case viewed
}

enum WorktreeAnnotationMessageStateValidationError: Error, Equatable, Sendable {
    case humanViewedRevision
    case agentDraft
    case agentHandled
    case agentCurrentRevisionMissing
    case agentCurrentRevisionIsNotPositive(currentSavedRevision: Int)
    case agentViewedRevisionIsNotPositive(viewedSavedRevision: Int)
    case agentViewedRevisionIsNewerThanCurrent(
        viewedSavedRevision: Int,
        currentSavedRevision: Int
    )
}

struct WorktreeAnnotationMessageNewPendingProjection: Equatable, Sendable {
    let attentionState: WorktreeAnnotationAttentionState
    let isPending: Bool
    let isAllEligible: Bool

    var isNew: Bool { attentionState == .new }
}

enum WorktreeAnnotationSourceRole: String, Codable, CaseIterable, Sendable {
    case file
    case reviewBase = "review_base"
    case reviewHead = "review_head"
}

enum WorktreeAnnotationDiffSide: String, Codable, CaseIterable, Sendable {
    case additions
    case deletions
}

enum WorktreeAnnotationOutputKind: String, Codable, CaseIterable, Sendable {
    case clipboardMarkdown = "clipboard_markdown"
    case jsonFile = "json_file"
}

enum WorktreeAnnotationOutputAttemptState: String, Codable, CaseIterable, Sendable {
    case prepared
    case cancelled
    case succeeded
    case unknown
    case finalizationFailed = "finalization_failed"
}

enum WorktreeAnnotationOutputEventKind: String, Codable, CaseIterable, Sendable {
    case copied
    case exported
}

enum WorktreeAnnotationAdmissionChoiceReason: String, Codable, Equatable, Sendable {
    case applicableSessionChoice = "applicable_session_choice"
    case uncertainContinuityChoice = "uncertain_continuity_choice"
}

struct WorktreeAnnotationAdmissionChoice: Equatable, Sendable {
    let reason: WorktreeAnnotationAdmissionChoiceReason
    let candidateSessionIDs: [WorktreeAnnotationSessionID]
}

struct WorktreeAnnotationSourceFingerprint: Codable, Equatable, Sendable {
    let repositoryID: String
    let worktreeID: String
    let fileSourceIdentity: String?
    let reviewComparisonOrigin: WorktreeAnnotationReviewComparisonOrigin?
}

enum WorktreeAnnotationSubjectEvidenceError: Error, Equatable, Sendable {
    case emptyEvidence
    case emptyBranchName
    case invalidReviewedHeadOID
}

struct WorktreeAnnotationReviewedSubjectEvidence: Codable, Equatable, Sendable {
    let branchName: String?
    let reviewedHeadOID: String?

    private struct CodingKey: Swift.CodingKey, Hashable {
        let stringValue: String
        let intValue: Int? = nil

        init(stringValue: String) {
            self.stringValue = stringValue
        }

        init?(intValue: Int) {
            nil
        }

        static let branchName = Self(stringValue: "branchName")
        static let reviewedHeadOID = Self(stringValue: "reviewedHeadOID")
    }

    init(branchName: String?, reviewedHeadOID: String?) throws {
        if let branchName, branchName.isEmpty {
            throw WorktreeAnnotationSubjectEvidenceError.emptyBranchName
        }
        if let reviewedHeadOID, !Self.isFullCommitOID(reviewedHeadOID) {
            throw WorktreeAnnotationSubjectEvidenceError.invalidReviewedHeadOID
        }
        guard branchName != nil || reviewedHeadOID != nil else {
            throw WorktreeAnnotationSubjectEvidenceError.emptyEvidence
        }
        self.branchName = branchName
        self.reviewedHeadOID = reviewedHeadOID
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKey.self)
        let allowedKeys: Set<CodingKey> = [.branchName, .reviewedHeadOID]
        guard Set(container.allKeys).isSubset(of: allowedKeys) else {
            throw DecodingError.dataCorrupted(
                .init(
                    codingPath: decoder.codingPath,
                    debugDescription: "Reviewed subject evidence contains unexpected fields"
                )
            )
        }
        do {
            try self.init(
                branchName: container.decodeIfPresent(String.self, forKey: .branchName),
                reviewedHeadOID: container.decodeIfPresent(String.self, forKey: .reviewedHeadOID)
            )
        } catch {
            throw DecodingError.dataCorrupted(
                .init(
                    codingPath: decoder.codingPath,
                    debugDescription: "Reviewed subject evidence is invalid",
                    underlyingError: error
                )
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        _ = try Self(branchName: branchName, reviewedHeadOID: reviewedHeadOID)
        var container = encoder.container(keyedBy: CodingKey.self)
        try container.encodeIfPresent(branchName, forKey: .branchName)
        try container.encodeIfPresent(reviewedHeadOID, forKey: .reviewedHeadOID)
    }

    private static func isFullCommitOID(_ value: String) -> Bool {
        guard value.count == 40 || value.count == 64 else { return false }
        return value.allSatisfy(\.isHexDigit)
    }
}

struct WorktreeAnnotationReviewComparisonOrigin: Codable, Equatable, Sendable {
    let symbolicTarget: String
    let resolvedTargetOID: String
    let reviewedHeadOID: String
    let baseRole: String
    let baseOID: String
}

struct WorktreeAnnotationLocatedOrigin: Codable, Equatable, Sendable {
    let repositoryRelativePath: String
    let startLine: Int
    let endLine: Int
    let sourceRole: WorktreeAnnotationSourceRole
    let diffSide: WorktreeAnnotationDiffSide?
    let sourceIdentity: String
    let selectedExcerpt: String
    let contextBefore: String?
    let contextAfter: String?
}

enum WorktreeAnnotationThreadOrigin: Codable, Equatable, Sendable {
    case located(WorktreeAnnotationLocatedOrigin)
    case wholeFile(repositoryRelativePath: String, sourceRole: WorktreeAnnotationSourceRole)
    case session

    var scope: WorktreeAnnotationThreadScope {
        switch self {
        case .located:
            .located
        case .wholeFile:
            .wholeFile
        case .session:
            .session
        }
    }
}

struct WorktreeAnnotationSession: Equatable, Sendable {
    let id: WorktreeAnnotationSessionID
    let repositoryID: String
    let worktreeID: String
    let lifecycle: WorktreeAnnotationSessionLifecycle
    let sourceRelationship: WorktreeAnnotationSourceRelationship
    let acceptedSourceFingerprint: WorktreeAnnotationSourceFingerprint
    let acceptedReviewedSubject: WorktreeAnnotationReviewedSubjectEvidence?
    let semanticRevision: Int
    let createdAt: Date
    let updatedAt: Date
    let completedAt: Date?

    init(
        id: WorktreeAnnotationSessionID,
        repositoryID: String,
        worktreeID: String,
        lifecycle: WorktreeAnnotationSessionLifecycle,
        sourceRelationship: WorktreeAnnotationSourceRelationship,
        acceptedSourceFingerprint: WorktreeAnnotationSourceFingerprint,
        acceptedReviewedSubject: WorktreeAnnotationReviewedSubjectEvidence? = nil,
        semanticRevision: Int,
        createdAt: Date,
        updatedAt: Date,
        completedAt: Date?
    ) {
        self.id = id
        self.repositoryID = repositoryID
        self.worktreeID = worktreeID
        self.lifecycle = lifecycle
        self.sourceRelationship = sourceRelationship
        self.acceptedSourceFingerprint = acceptedSourceFingerprint
        self.acceptedReviewedSubject = acceptedReviewedSubject
        self.semanticRevision = semanticRevision
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.completedAt = completedAt
    }
}

struct WorktreeAnnotationThread: Equatable, Sendable {
    let id: WorktreeAnnotationThreadID
    let sessionID: WorktreeAnnotationSessionID
    let origin: WorktreeAnnotationThreadOrigin
    let resolution: WorktreeAnnotationThreadResolution
    let createdOrdinal: Int
    let semanticRevision: Int
    let createdAt: Date
    let updatedAt: Date
    let resolvedAt: Date?
}

struct WorktreeAnnotationDraft: Equatable, Sendable {
    let messageID: WorktreeAnnotationMessageID
    let activeEditToken: String?
    let body: String
    let draftRevision: Int
    let updatedAt: Date
}

struct WorktreeAnnotationMessage: Equatable, Sendable {
    let id: WorktreeAnnotationMessageID
    let threadID: WorktreeAnnotationThreadID
    let ordinal: Int
    let authorKind: WorktreeAnnotationAuthorKind
    let semanticRevision: Int
    let createdAt: Date
    let updatedAt: Date
    let savedBody: String?
    let savedRevision: Int?
    let draft: WorktreeAnnotationDraft?
    let handled: Bool
    let viewedSavedRevision: Int?
    let status: WorktreeAnnotationMessageStatus

    init(
        id: WorktreeAnnotationMessageID,
        threadID: WorktreeAnnotationThreadID,
        ordinal: Int,
        semanticRevision: Int,
        createdAt: Date,
        updatedAt: Date,
        savedBody: String?,
        savedRevision: Int?,
        draft: WorktreeAnnotationDraft?,
        handled: Bool,
        status: WorktreeAnnotationMessageStatus,
        authorKind: WorktreeAnnotationAuthorKind = .human,
        viewedSavedRevision: Int? = nil
    ) {
        self.id = id
        self.threadID = threadID
        self.ordinal = ordinal
        self.authorKind = authorKind
        self.semanticRevision = semanticRevision
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.savedBody = savedBody
        self.savedRevision = savedRevision
        self.draft = draft
        self.handled = handled
        self.viewedSavedRevision = viewedSavedRevision
        self.status = status
    }

    func projectNewPendingState() throws -> WorktreeAnnotationMessageNewPendingProjection {
        let hasCurrentSavedRevision = savedBody != nil && savedRevision != nil
        let isOutputEligible = hasCurrentSavedRevision && draft == nil

        switch authorKind {
        case .human:
            guard viewedSavedRevision == nil else {
                throw WorktreeAnnotationMessageStateValidationError.humanViewedRevision
            }
            return .init(
                attentionState: .notApplicable,
                isPending: isOutputEligible && !handled,
                isAllEligible: isOutputEligible
            )

        case .agent:
            guard draft == nil else {
                throw WorktreeAnnotationMessageStateValidationError.agentDraft
            }
            guard !handled else {
                throw WorktreeAnnotationMessageStateValidationError.agentHandled
            }
            guard savedBody != nil, let savedRevision else {
                throw WorktreeAnnotationMessageStateValidationError.agentCurrentRevisionMissing
            }
            guard savedRevision > 0 else {
                throw WorktreeAnnotationMessageStateValidationError.agentCurrentRevisionIsNotPositive(
                    currentSavedRevision: savedRevision
                )
            }
            if let viewedSavedRevision, viewedSavedRevision < 1 {
                throw WorktreeAnnotationMessageStateValidationError.agentViewedRevisionIsNotPositive(
                    viewedSavedRevision: viewedSavedRevision
                )
            }
            if let viewedSavedRevision, viewedSavedRevision > savedRevision {
                throw WorktreeAnnotationMessageStateValidationError.agentViewedRevisionIsNewerThanCurrent(
                    viewedSavedRevision: viewedSavedRevision,
                    currentSavedRevision: savedRevision
                )
            }
            let attentionState: WorktreeAnnotationAttentionState =
                viewedSavedRevision == savedRevision ? .viewed : .new
            return .init(
                attentionState: attentionState,
                isPending: false,
                isAllEligible: true
            )
        }
    }
}

struct WorktreeAnnotationThreadDetail: Equatable, Sendable {
    let thread: WorktreeAnnotationThread
    let messages: [WorktreeAnnotationMessage]
}

struct WorktreeAnnotationSessionDetail: Equatable, Sendable {
    let session: WorktreeAnnotationSession
    let threads: [WorktreeAnnotationThreadDetail]
}

func worktreeAnnotationSourceFileLines(_ source: String) -> [String] {
    var lines = source.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    if source.hasSuffix("\n") { lines.removeLast() }
    return lines
}

func worktreeAnnotationSelectedExcerptLines(_ selectedExcerpt: String) -> [String] {
    selectedExcerpt.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
}

struct WorktreeAnnotationOutputAttempt: Equatable, Sendable {
    let id: WorktreeAnnotationOutputAttemptID
    let sessionID: WorktreeAnnotationSessionID
    let outputKind: WorktreeAnnotationOutputKind
    let state: WorktreeAnnotationOutputAttemptState
    let formatVersion: Int
    let contentType: String
    let exactBytes: Data
    let destinationPath: String?
    let repeatedFromAttemptID: WorktreeAnnotationOutputAttemptID?
    let effectError: String?
    let cleanupError: String?
    let createdAt: Date
    let updatedAt: Date
}

struct WorktreeAnnotationOutputEvent: Equatable, Sendable {
    let id: WorktreeAnnotationOutputEventID
    let attemptID: WorktreeAnnotationOutputAttemptID
    let eventKind: WorktreeAnnotationOutputEventKind
    let createdAt: Date
}

struct WorktreeAnnotationOutputHistorySummary: Equatable, Sendable {
    let attemptID: WorktreeAnnotationOutputAttemptID
    let sessionID: WorktreeAnnotationSessionID
    let outputKind: WorktreeAnnotationOutputKind
    let state: WorktreeAnnotationOutputAttemptState
    let messageCount: Int
    let repeatedFromAttemptID: WorktreeAnnotationOutputAttemptID?
    let canMarkNotHandled: Bool
    let createdAt: Date
    let updatedAt: Date
}

struct WorktreeAnnotationRecoveryProvenance: Equatable, Sendable {
    let id: WorktreeAnnotationRecoveryProvenanceID
    let recoveredAt: Date
    let quarantinedFilenames: [String]
    let reason: String
    let acknowledgedAt: Date?
}

enum WorktreeAnnotationRepositoryError: Error, Equatable, Sendable {
    case conflict(currentRevision: Int)
    case editTokenConflict
    case messageLocked
    case sessionReadOnly
    case sessionSelectionRequired(WorktreeAnnotationAdmissionChoice)
    case openThreadCountConflict(currentCount: Int)
    case unresolvedWorkConfirmationRequired
    case notFound
    case invalidState
    case duplicateSelection
    case emptySelection
}
