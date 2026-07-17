import Foundation

enum WorkspaceTabLeafTransitionApplicationRejection: Equatable, Sendable {
    case staleShells(expected: [TabShell], actual: [TabShell])
    case staleCursor(
        expected: WorkspaceTabCursorSelection,
        actual: WorkspaceTabCursorSelection
    )
}

enum WorkspaceTabLeafTransitionApplicationResult: Equatable, Sendable {
    case applied
    case rejected(WorkspaceTabLeafTransitionApplicationRejection)
}

enum WorkspaceTabLeafTransitionPreflightResult: Equatable, Sendable {
    case ready(WorkspacePreparedTabLeafTransitionApplication)
    case rejected(WorkspaceTabLeafTransitionApplicationRejection)
}

struct WorkspacePreparedTabLeafTransitionApplication: Equatable, Sendable {
    fileprivate let transition: WorkspaceReorderAndSelectTabTransition
}

@MainActor
final class WorkspaceTabLeafTransitionApplier {
    private let workspaceTabShellAtom: WorkspaceTabShellAtom
    private let workspaceTabCursorAtom: WorkspaceTabCursorAtom

    init(
        workspaceTabShellAtom: WorkspaceTabShellAtom,
        workspaceTabCursorAtom: WorkspaceTabCursorAtom
    ) {
        self.workspaceTabShellAtom = workspaceTabShellAtom
        self.workspaceTabCursorAtom = workspaceTabCursorAtom
    }

    func apply(
        _ transition: WorkspaceTabShellCollectionTransition
    ) -> WorkspaceTabLeafTransitionApplicationResult {
        apply(.shellOnly(transition))
    }

    func apply(
        _ transition: WorkspaceTabCursorReplacement
    ) -> WorkspaceTabLeafTransitionApplicationResult {
        apply(.cursorOnly(transition))
    }

    func apply(
        _ transition: WorkspaceReorderAndSelectTabTransition
    ) -> WorkspaceTabLeafTransitionApplicationResult {
        switch preflight(transition) {
        case .ready(let preparation):
            apply(preparation)
            return .applied
        case .rejected(let rejection):
            return .rejected(rejection)
        }
    }

    func preflight(
        _ transition: WorkspaceTabShellCollectionTransition
    ) -> WorkspaceTabLeafTransitionPreflightResult {
        preflight(.shellOnly(transition))
    }

    func preflight(
        _ transition: WorkspaceTabCursorReplacement
    ) -> WorkspaceTabLeafTransitionPreflightResult {
        preflight(.cursorOnly(transition))
    }

    func preflight(
        _ transition: WorkspaceReorderAndSelectTabTransition
    ) -> WorkspaceTabLeafTransitionPreflightResult {
        switch transition {
        case .shellOnly(let shells):
            return preflightShells(shells, transition: transition)
        case .cursorOnly(let cursor):
            return preflightCursor(cursor, transition: transition)
        case .shellAndCursor(let shells, let cursor):
            switch preflightShells(shells, transition: transition) {
            case .ready:
                return preflightCursor(cursor, transition: transition)
            case .rejected(let rejection):
                return .rejected(rejection)
            }
        }
    }

    func apply(_ preparation: WorkspacePreparedTabLeafTransitionApplication) {
        preconditionPreparedApplicationIsFresh(preparation)
        switch preparation.transition {
        case .shellOnly(let shells):
            workspaceTabShellAtom.replaceTabShells(shells.replacementTabShells)
        case .cursorOnly(let cursor):
            workspaceTabCursorAtom.replaceActiveTab(cursor.replacement.optionalTabID)
        case .shellAndCursor(let shells, let cursor):
            workspaceTabShellAtom.replaceTabShells(shells.replacementTabShells)
            workspaceTabCursorAtom.replaceActiveTab(cursor.replacement.optionalTabID)
        }
    }

    private func preconditionPreparedApplicationIsFresh(
        _ preparation: WorkspacePreparedTabLeafTransitionApplication
    ) {
        switch preflight(preparation.transition) {
        case .ready:
            return
        case .rejected(let rejection):
            preconditionFailure("prepared tab-leaf transition is stale: \(rejection)")
        }
    }

    private func preflightShells(
        _ shells: WorkspaceTabShellCollectionTransition,
        transition: WorkspaceReorderAndSelectTabTransition
    ) -> WorkspaceTabLeafTransitionPreflightResult {
        let expectedShells = shells.expectedPreviousTabShells
        guard workspaceTabShellAtom.tabShells == expectedShells else {
            return .rejected(
                .staleShells(
                    expected: expectedShells,
                    actual: workspaceTabShellAtom.tabShells
                )
            )
        }
        return .ready(WorkspacePreparedTabLeafTransitionApplication(transition: transition))
    }

    private func preflightCursor(
        _ cursor: WorkspaceTabCursorReplacement,
        transition: WorkspaceReorderAndSelectTabTransition
    ) -> WorkspaceTabLeafTransitionPreflightResult {
        let actualSelection =
            workspaceTabCursorAtom.activeTabId.map(WorkspaceTabCursorSelection.selected)
            ?? .noSelection
        guard actualSelection == cursor.previous else {
            return .rejected(
                .staleCursor(
                    expected: cursor.previous,
                    actual: actualSelection
                )
            )
        }
        return .ready(WorkspacePreparedTabLeafTransitionApplication(transition: transition))
    }
}

extension WorkspaceTabShellCollectionTransition {
    fileprivate var expectedPreviousTabShells: [TabShell] {
        var expectedShells = replacementTabShells
        for affectedShell in affectedShells {
            precondition(
                expectedShells.indices.contains(affectedShell.previous.index),
                "tab-leaf transition previous index must remain in collection bounds"
            )
            expectedShells[affectedShell.previous.index] = affectedShell.previous.shell
        }
        return expectedShells
    }
}

extension WorkspaceTabCursorSelection {
    fileprivate var optionalTabID: UUID? {
        switch self {
        case .noSelection:
            nil
        case .selected(let tabID):
            tabID
        }
    }
}
