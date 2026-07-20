import Foundation

struct TerminalActivationCohort: Equatable, Sendable {
    let generation: WorkspaceContentMountGeneration
    let input: TerminalActivationInput
}

struct TerminalActivationAdmission: Equatable, Sendable {
    let generation: WorkspaceContentMountGeneration
    let descriptor: TerminalActivationDescriptor
    let attempt: Int
}

enum TerminalActivationFailure: Equatable, Sendable {
    case attachmentRejected(code: String)
    case surfaceCreationFailed(code: String)
    case surfaceAttachmentFailed(code: String)
}

enum TerminalActivationRetryDirective: Equatable, Sendable {
    case retry
    case doNotRetry
}

enum TerminalActivationAttemptResult: Equatable, Sendable {
    case ready(surfaceID: UUID)
    case failed(
        failure: TerminalActivationFailure,
        retry: TerminalActivationRetryDirective
    )
}

enum TerminalActivationRetry: Equatable, Sendable {
    case notRequested(attemptCount: Int)
    case exhausted(attemptCount: Int)
}

enum TerminalActivationMemberState: Equatable, Sendable {
    case queued(priority: TerminalActivationVisibilityPriority)
    case attaching
    case ready(surfaceID: UUID)
    case failedTerminal(
        failure: TerminalActivationFailure,
        retry: TerminalActivationRetry
    )
    case cancelledReplaced(replacement: WorkspaceContentMountGeneration)

    var isTerminal: Bool {
        switch self {
        case .queued, .attaching:
            return false
        case .ready, .failedTerminal, .cancelledReplaced:
            return true
        }
    }
}

enum TerminalActivationTerminalOutcome: Equatable, Sendable {
    case ready(surfaceID: UUID)
    case failedTerminal(
        failure: TerminalActivationFailure,
        retry: TerminalActivationRetry
    )
    case cancelledReplaced(replacement: WorkspaceContentMountGeneration)
}

struct TerminalActivationSettlement: Equatable, Sendable {
    let generation: WorkspaceContentMountGeneration
    let outcomesByPaneID: [PaneId: TerminalActivationTerminalOutcome]
}

struct TerminalActivationSchedulerDiagnostics: Equatable, Sendable {
    let currentSimultaneousAdmissions: Int
    let maximumSimultaneousAdmissions: Int
    let workerCount: Int
}

enum TerminalActivationPromotionResult: Equatable, Sendable {
    case promoted(
        from: TerminalActivationVisibilityPriority,
        to: TerminalActivationVisibilityPriority
    )
    case unchanged(priority: TerminalActivationVisibilityPriority)
    case paneNotFound
    case memberNotQueued(state: TerminalActivationMemberState)
}

@MainActor
protocol TerminalActivationAdmissionPort: AnyObject, Sendable {
    func activate(_ admission: TerminalActivationAdmission) async -> TerminalActivationAttemptResult
}
