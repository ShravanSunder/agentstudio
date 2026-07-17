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

enum WorkspacePaneNoteUpdate: Equatable, Sendable {
    case set(String)
    case clear
}

enum WorkspacePaneMetadataUpdate: Equatable, Sendable {
    case title(String)
    case note(WorkspacePaneNoteUpdate)
}

struct WorkspacePaneMetadataUpdateRequest: Equatable, Sendable {
    let paneID: UUID
    let update: WorkspacePaneMetadataUpdate
}

enum WorkspacePaneMetadataTransitionDecision: Equatable, Sendable {
    case changed(WorkspacePaneGraphTransition)
    case unchanged
    case rejected(WorkspacePaneTitleTransitionRejection)
}

enum WorkspacePaneMetadataTransitionPlanner {
    static func plan(
        _ request: WorkspacePaneMetadataUpdateRequest,
        currentPaneState: PaneGraphState?
    ) -> WorkspacePaneMetadataTransitionDecision {
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

        var replacementState = currentPaneState
        switch request.update {
        case .title(let title):
            replacementState.metadata.title = title
        case .note(.set(let note)):
            replacementState.metadata.updateNote(note)
        case .note(.clear):
            replacementState.metadata.updateNote(nil)
        }
        guard replacementState != currentPaneState else {
            return .unchanged
        }

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

enum WorkspacePaneResolvedContext: Equatable, Sendable {
    case unresolved
    case resolved(repoID: UUID, worktreeID: UUID)
}

struct WorkspacePaneContextUpdateRequest: Equatable, Sendable {
    let paneID: UUID
    let cwd: URL?
    let resolvedContext: WorkspacePaneResolvedContext
}

enum WorkspacePaneContextTransitionRejection: Equatable, Sendable {
    case paneMissing(UUID)
    case paneIdentityMismatch(requestedPaneID: UUID, currentPaneID: UUID)
}

enum WorkspacePaneContextTransitionDecision: Equatable, Sendable {
    case changed(WorkspacePaneGraphTransition)
    case unchanged
    case rejected(WorkspacePaneContextTransitionRejection)
}

enum WorkspacePaneContextTransitionPlanner {
    static func plan(
        _ request: WorkspacePaneContextUpdateRequest,
        currentPaneState: PaneGraphState?
    ) -> WorkspacePaneContextTransitionDecision {
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

        var replacementState = currentPaneState
        replacementState.metadata.facets.cwd = request.cwd
        switch request.resolvedContext {
        case .unresolved:
            replacementState.metadata.facets.repoId = nil
            replacementState.metadata.facets.worktreeId = nil
        case .resolved(let repoID, let worktreeID):
            replacementState.metadata.facets.repoId = repoID
            replacementState.metadata.facets.worktreeId = worktreeID
        }
        guard replacementState != currentPaneState else {
            return .unchanged
        }

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

struct WorkspacePaneWebviewStateUpdateRequest: Equatable, Sendable {
    let paneID: UUID
    let state: WebviewState
}

enum WorkspacePaneWebviewStateTransitionRejection: Equatable, Sendable {
    case paneMissing(UUID)
    case paneIdentityMismatch(requestedPaneID: UUID, currentPaneID: UUID)
    case paneContentIsNotWebview(UUID)
}

enum WorkspacePaneWebviewStateTransitionDecision: Equatable, Sendable {
    case changed(WorkspacePaneGraphTransition)
    case unchanged
    case rejected(WorkspacePaneWebviewStateTransitionRejection)
}

enum WorkspacePaneWebviewStateTransitionPlanner {
    static func plan(
        _ request: WorkspacePaneWebviewStateUpdateRequest,
        currentPaneState: PaneGraphState?
    ) -> WorkspacePaneWebviewStateTransitionDecision {
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
        guard case .webview(let currentWebviewState) = currentPaneState.content else {
            return .rejected(.paneContentIsNotWebview(request.paneID))
        }
        guard currentWebviewState != request.state else {
            return .unchanged
        }

        var replacementState = currentPaneState
        replacementState.content = .webview(request.state)
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
