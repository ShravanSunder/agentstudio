enum WorkspaceDrawerCursorApplyRejection: Equatable, Sendable {
    case staleCurrentCursor(
        expected: WorkspaceDrawerCursorSelection,
        actual: WorkspaceDrawerCursorSelection
    )
}

enum WorkspaceDrawerCursorApplyResult: Equatable, Sendable {
    case applied
    case rejected(WorkspaceDrawerCursorApplyRejection)
}

enum WorkspaceDrawerCursorPreflightResult: Equatable, Sendable {
    case ready(WorkspacePreparedDrawerCursorApplication)
    case rejected(WorkspaceDrawerCursorApplyRejection)
}

struct WorkspacePreparedDrawerCursorApplication: Equatable, Sendable {
    fileprivate let transition: WorkspaceDrawerToggleTransition
}

@MainActor
final class WorkspaceDrawerCursorTransitionApplier {
    private let workspaceDrawerCursorAtom: WorkspaceDrawerCursorAtom

    init(workspaceDrawerCursorAtom: WorkspaceDrawerCursorAtom) {
        self.workspaceDrawerCursorAtom = workspaceDrawerCursorAtom
    }

    func apply(
        _ transition: WorkspaceDrawerToggleTransition
    ) -> WorkspaceDrawerCursorApplyResult {
        switch preflight(transition) {
        case .ready(let preparation):
            apply(preparation)
            return .applied
        case .rejected(let rejection):
            return .rejected(rejection)
        }
    }

    func preflight(
        _ transition: WorkspaceDrawerToggleTransition
    ) -> WorkspaceDrawerCursorPreflightResult {
        let actualCursor = WorkspaceDrawerCursorSelection(
            expandedDrawerID: workspaceDrawerCursorAtom.expandedDrawerId
        )
        guard actualCursor == transition.expectedCursor else {
            return .rejected(
                .staleCurrentCursor(
                    expected: transition.expectedCursor,
                    actual: actualCursor
                )
            )
        }

        return .ready(WorkspacePreparedDrawerCursorApplication(transition: transition))
    }

    func apply(_ preparation: WorkspacePreparedDrawerCursorApplication) {
        preconditionPreparedApplicationIsFresh(preparation)
        workspaceDrawerCursorAtom.replaceExpandedDrawer(
            preparation.transition.replacementCursor.expandedDrawerID
        )
    }

    private func preconditionPreparedApplicationIsFresh(
        _ preparation: WorkspacePreparedDrawerCursorApplication
    ) {
        switch preflight(preparation.transition) {
        case .ready:
            return
        case .rejected(let rejection):
            preconditionFailure("prepared drawer-cursor transition is stale: \(rejection)")
        }
    }
}
