@MainActor
final class WorkspacePaneTransitionApplier {
    private let workspacePaneGraphAtom: WorkspacePaneGraphAtom

    init(workspacePaneGraphAtom: WorkspacePaneGraphAtom) {
        self.workspacePaneGraphAtom = workspacePaneGraphAtom
    }

    func apply(_ transition: WorkspacePaneGraphTransition) {
        for replacement in transition.replacements {
            precondition(
                workspacePaneGraphAtom.paneState(replacement.paneID)
                    == replacement.expectedCurrentState,
                "pane transition expected canonical state changed before apply"
            )
        }
        for replacement in transition.replacements {
            workspacePaneGraphAtom.setCanonicalPaneState(replacement.replacementState)
        }
    }
}
