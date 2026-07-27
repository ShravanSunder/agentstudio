import AgentStudioCore
import AgentStudioInfrastructure
import Foundation

package struct TerminalActivationCohort: Equatable, Sendable {
    package let generation: WorkspaceContentMountGeneration
    package let input: TerminalActivationInput

    package init(
        generation: WorkspaceContentMountGeneration,
        input: TerminalActivationInput
    ) {
        self.generation = generation
        self.input = input
    }
}

package struct TerminalActivationAdmission: Equatable, Sendable {
    package let generation: WorkspaceContentMountGeneration
    package let descriptor: TerminalActivationDescriptor
    package let attempt: Int
}

package enum TerminalActivationFailure: Equatable, Sendable {
    case attachmentRejected(code: String)
    case surfaceCreationFailed(code: String)
    case surfaceAttachmentFailed(code: String)
}

package enum TerminalActivationRetryDirective: Equatable, Sendable {
    case retry
    case doNotRetry
}

package enum TerminalActivationAttemptResult: Equatable, Sendable {
    case ready(surfaceID: UUID)
    case failed(
        failure: TerminalActivationFailure,
        retry: TerminalActivationRetryDirective
    )
}

package enum TerminalActivationRetry: Equatable, Sendable {
    case notRequested(attemptCount: Int)
    case exhausted(attemptCount: Int)
}

package enum TerminalActivationMemberState: Equatable, Sendable {
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

package enum TerminalActivationTerminalOutcome: Equatable, Sendable {
    case ready(surfaceID: UUID)
    case failedTerminal(
        failure: TerminalActivationFailure,
        retry: TerminalActivationRetry
    )
    case cancelledReplaced(replacement: WorkspaceContentMountGeneration)
}

package struct TerminalActivationSettlement: Equatable, Sendable {
    package let generation: WorkspaceContentMountGeneration
    package let outcomesByPaneID: [PaneId: TerminalActivationTerminalOutcome]
}

struct TerminalActivationSchedulerDiagnostics: Equatable, Sendable {
    let currentSimultaneousAdmissions: Int
    let maximumSimultaneousAdmissions: Int
    let workerCount: Int
}

package enum TerminalActivationPromotionResult: Equatable, Sendable {
    case promoted(
        from: TerminalActivationVisibilityPriority,
        to: TerminalActivationVisibilityPriority
    )
    case unchanged(priority: TerminalActivationVisibilityPriority)
    case paneNotFound
    case memberNotQueued(state: TerminalActivationMemberState)
}

@MainActor
package protocol TerminalActivationAdmissionPort: AnyObject, Sendable {
    func activate(_ admission: TerminalActivationAdmission) async -> TerminalActivationAttemptResult
}
