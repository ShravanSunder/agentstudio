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
    let originatingWorkspaceID: String?
    let lifecycle: WorktreeAnnotationSessionLifecycle
    let sourceRelationship: WorktreeAnnotationSourceRelationship
    let acceptedSourceFingerprint: WorktreeAnnotationSourceFingerprint
    let semanticRevision: Int
    let createdAt: Date
    let updatedAt: Date
    let completedAt: Date?
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
    let semanticRevision: Int
    let createdAt: Date
    let updatedAt: Date
    let savedBody: String?
    let savedRevision: Int?
    let draft: WorktreeAnnotationDraft?
    let status: WorktreeAnnotationMessageStatus
}

struct WorktreeAnnotationThreadDetail: Equatable, Sendable {
    let thread: WorktreeAnnotationThread
    let messages: [WorktreeAnnotationMessage]
}

struct WorktreeAnnotationSessionDetail: Equatable, Sendable {
    let session: WorktreeAnnotationSession
    let threads: [WorktreeAnnotationThreadDetail]
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
