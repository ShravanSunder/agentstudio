import Foundation

enum WorktreeAnnotationRecoveryState: Equatable, Sendable {
    case available
    case recoveredDegraded(WorktreeAnnotationRecoveryProvenance)
    case unavailable
}

enum WorktreeAnnotationCommandFailureCode: String, Codable, Equatable, Sendable {
    case conflict
    case editTokenConflict = "edit_token_conflict"
    case invalidSource = "invalid_source"
    case messageLocked = "message_locked"
    case notFound = "not_found"
    case openThreadCountConflict = "open_thread_count_conflict"
    case outputUnavailable = "output_unavailable"
    case recoveryAcknowledgementRequired = "recovery_acknowledgement_required"
    case sessionReadOnly = "session_read_only"
    case sessionSelectionRequired = "session_selection_required"
    case unavailable
    case unexpected
    case unresolvedWorkConfirmationRequired = "unresolved_work_confirmation_required"
}

enum WorktreeAnnotationCommandOutcomeStatus: Equatable, Sendable {
    case committed
    case admissionRequired(WorktreeAnnotationAdmissionChoice)
    case history([WorktreeAnnotationOutputHistorySummary])
    case output(WorktreeAnnotationOutputCommandOutcome)
    case failed(WorktreeAnnotationCommandFailureCode)
}

struct WorktreeAnnotationPlacementContextKey: Hashable, Sendable {
    let contextID: String
    let surface: BridgeProductSurface
    let sessionID: WorktreeAnnotationSessionID
}

struct WorktreeAnnotationCommandOutcome: Equatable, Sendable {
    let requestID: String
    let surface: BridgeProductSurface
    let sessionID: WorktreeAnnotationSessionID?
    let status: WorktreeAnnotationCommandOutcomeStatus
    let receipt: WorktreeAnnotationMessageCommandReceipt?

    init(
        requestID: String,
        surface: BridgeProductSurface,
        sessionID: WorktreeAnnotationSessionID?,
        status: WorktreeAnnotationCommandOutcomeStatus,
        receipt: WorktreeAnnotationMessageCommandReceipt? = nil
    ) {
        self.requestID = requestID
        self.surface = surface
        self.sessionID = sessionID
        self.status = status
        self.receipt = receipt
    }
}

struct WorktreeAnnotationMessageCommandReceipt: Equatable, Sendable {
    let messageID: WorktreeAnnotationMessageID
    let threadID: WorktreeAnnotationThreadID
    let sessionRevision: Int
    let messageRevision: Int
    let draftRevision: Int?
    let savedRevision: Int?
}
