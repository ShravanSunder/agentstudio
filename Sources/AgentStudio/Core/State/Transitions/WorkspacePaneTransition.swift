import Foundation

struct WorkspacePaneTitleUpdateRequest: Equatable, Sendable {
    let paneID: UUID
    let title: String
}

enum WorkspacePaneTitleTransitionRejection: Equatable, Sendable {
    case paneMissing(UUID)
    case paneIdentityMismatch(requestedPaneID: UUID, currentPaneID: UUID)
}

struct WorkspacePaneStateTransitionReplacement: Equatable, Sendable {
    let paneID: UUID
    let expectedCurrentState: PaneGraphState
    let replacementState: PaneGraphState
}

struct WorkspacePaneGraphTransition: Equatable, Sendable {
    let replacements: [WorkspacePaneStateTransitionReplacement]

    fileprivate init(replacements: [WorkspacePaneStateTransitionReplacement]) {
        precondition(!replacements.isEmpty, "pane graph transition requires at least one replacement")
        self.replacements = replacements
    }
}

enum WorkspacePaneTitleTransitionDecision: Equatable, Sendable {
    case changed(WorkspacePaneGraphTransition)
    case unchanged
    case rejected(WorkspacePaneTitleTransitionRejection)
}

enum WorkspacePaneTitleTransitionPlanner {
    static func plan(
        _ request: WorkspacePaneTitleUpdateRequest,
        currentPaneState: PaneGraphState?
    ) -> WorkspacePaneTitleTransitionDecision {
        guard let currentPaneState else {
            return .rejected(.paneMissing(request.paneID))
        }
        guard currentPaneState.id == request.paneID else {
            return .rejected(
                .paneIdentityMismatch(
                    requestedPaneID: request.paneID,
                    currentPaneID: currentPaneState.id
                )
            )
        }
        guard currentPaneState.metadata.title != request.title else {
            return .unchanged
        }

        var replacementState = currentPaneState
        replacementState.metadata.title = request.title
        return .changed(
            WorkspacePaneGraphTransition(
                replacements: [
                    WorkspacePaneStateTransitionReplacement(
                        paneID: request.paneID,
                        expectedCurrentState: currentPaneState,
                        replacementState: replacementState
                    )
                ]
            )
        )
    }
}
