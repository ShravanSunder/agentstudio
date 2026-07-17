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

@MainActor
final class WorkspaceDrawerCursorTransitionApplier {
    private let workspaceDrawerCursorAtom: WorkspaceDrawerCursorAtom

    init(workspaceDrawerCursorAtom: WorkspaceDrawerCursorAtom) {
        self.workspaceDrawerCursorAtom = workspaceDrawerCursorAtom
    }

    func apply(
        _ transition: WorkspaceDrawerToggleTransition
    ) -> WorkspaceDrawerCursorApplyResult {
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

        workspaceDrawerCursorAtom.replaceExpandedDrawer(
            transition.replacementCursor.expandedDrawerID
        )
        return .applied
    }
}
