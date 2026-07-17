import Foundation

enum WorkspaceArrangementSelectionApplyRejection: Equatable, Sendable {
    case staleTabGraph(
        tabID: UUID,
        expected: TabGraphState,
        actual: WorkspaceTabGraphStateWitness
    )
    case staleActiveArrangement(
        tabID: UUID,
        expected: WorkspaceActiveArrangementSelection,
        actual: WorkspaceActiveArrangementSelection
    )
    case staleActivePane(
        arrangementID: UUID,
        expected: WorkspaceActivePaneCursorWitness,
        actual: WorkspaceActivePaneCursorWitness
    )
    case staleActiveDrawerChild(
        key: ArrangementDrawerCursorKey,
        expected: WorkspaceActiveDrawerChildCursorWitness,
        actual: WorkspaceActiveDrawerChildCursorWitness
    )
}

enum WorkspaceArrangementSelectionApplyResult: Equatable, Sendable {
    case applied
    case rejected(WorkspaceArrangementSelectionApplyRejection)
}

enum WorkspaceArrangementSelectionPreflightResult: Equatable, Sendable {
    case ready(WorkspacePreparedArrangementSelectionApplication)
    case rejected(WorkspaceArrangementSelectionApplyRejection)
}

struct WorkspacePreparedArrangementSelectionApplication: Equatable, Sendable {
    fileprivate let transition: WorkspaceArrangementSelectionTransition
}

@MainActor
final class WorkspaceArrangementSelectionTransitionApplier {
    private let workspaceTabGraphAtom: WorkspaceTabGraphAtom
    private let workspaceArrangementCursorAtom: WorkspaceArrangementCursorAtom

    init(
        workspaceTabGraphAtom: WorkspaceTabGraphAtom,
        workspaceArrangementCursorAtom: WorkspaceArrangementCursorAtom
    ) {
        self.workspaceTabGraphAtom = workspaceTabGraphAtom
        self.workspaceArrangementCursorAtom = workspaceArrangementCursorAtom
    }

    func apply(
        _ transition: WorkspaceArrangementSelectionTransition
    ) -> WorkspaceArrangementSelectionApplyResult {
        switch preflight(transition) {
        case .ready(let preparation):
            apply(preparation)
            return .applied
        case .rejected(let rejection):
            return .rejected(rejection)
        }
    }

    func preflight(
        _ transition: WorkspaceArrangementSelectionTransition
    ) -> WorkspaceArrangementSelectionPreflightResult {
        if let rejection = preflightTabGraph(transition) {
            return .rejected(rejection)
        }
        if let rejection = preflightActiveArrangement(transition) {
            return .rejected(rejection)
        }
        if let rejection = preflightSelectionCursor(transition) {
            return .rejected(rejection)
        }
        return .ready(.init(transition: transition))
    }

    func apply(_ preparation: WorkspacePreparedArrangementSelectionApplication) {
        switch preflight(preparation.transition) {
        case .ready:
            break
        case .rejected(let rejection):
            preconditionFailure("prepared arrangement selection is stale: \(rejection)")
        }
        switch preparation.transition {
        case .activePane(let transition):
            apply(transition.mutation)
        case .activeDrawerChild(let transition):
            apply(transition.mutation)
        }
    }

    private func preflightTabGraph(
        _ transition: WorkspaceArrangementSelectionTransition
    ) -> WorkspaceArrangementSelectionApplyRejection? {
        let tabID = transition.tabID
        let expected = transition.expectedTabGraph
        let actual = workspaceTabGraphAtom.tabState(tabID)
        guard actual == expected else {
            return .staleTabGraph(
                tabID: tabID,
                expected: expected,
                actual: actual.map(WorkspaceTabGraphStateWitness.present) ?? .missing
            )
        }
        return nil
    }

    private func preflightActiveArrangement(
        _ transition: WorkspaceArrangementSelectionTransition
    ) -> WorkspaceArrangementSelectionApplyRejection? {
        let tabID = transition.tabID
        let expected = transition.expectedActiveArrangement
        let actual = activeArrangementSelection(tabID: tabID)
        guard actual == expected else {
            return .staleActiveArrangement(tabID: tabID, expected: expected, actual: actual)
        }
        return nil
    }

    private func preflightSelectionCursor(
        _ transition: WorkspaceArrangementSelectionTransition
    ) -> WorkspaceArrangementSelectionApplyRejection? {
        switch transition {
        case .activePane(let transition):
            let arrangementID = transition.mutation.arrangementID
            let actual = activePaneWitness(arrangementID: arrangementID)
            guard actual == transition.expectedCursor else {
                return .staleActivePane(
                    arrangementID: arrangementID,
                    expected: transition.expectedCursor,
                    actual: actual
                )
            }
        case .activeDrawerChild(let transition):
            let key = transition.mutation.key
            let actual = activeDrawerChildWitness(key: key)
            guard actual == transition.expectedCursor else {
                return .staleActiveDrawerChild(
                    key: key,
                    expected: transition.expectedCursor,
                    actual: actual
                )
            }
        }
        return nil
    }

    private func apply(_ mutation: WorkspaceActivePaneSelectionMutation) {
        switch mutation {
        case .insert(let arrangementID, _, let replacement),
            .replace(let arrangementID, _, let replacement):
            workspaceArrangementCursorAtom.setPaneCursor(
                .init(activePaneId: replacement),
                forArrangement: arrangementID
            )
        case .remove(let arrangementID, _):
            workspaceArrangementCursorAtom.setPaneCursor(
                .init(activePaneId: nil),
                forArrangement: arrangementID
            )
        }
    }

    private func apply(_ mutation: WorkspaceActiveDrawerChildSelectionMutation) {
        let key = mutation.key
        let replacement: UUID
        switch mutation {
        case .insert(_, _, let paneID), .replace(_, _, let paneID):
            replacement = paneID
        }
        workspaceArrangementCursorAtom.setDrawerCursor(
            .init(activeChildId: replacement),
            for: key
        )
    }

    private func activeArrangementSelection(tabID: UUID) -> WorkspaceActiveArrangementSelection {
        workspaceArrangementCursorAtom.activeArrangementId(forTab: tabID)
            .map(WorkspaceActiveArrangementSelection.selected) ?? .missing
    }

    private func activePaneWitness(arrangementID: UUID) -> WorkspaceActivePaneCursorWitness {
        guard workspaceArrangementCursorAtom.hasPaneCursor(arrangementID: arrangementID) else {
            return .missing
        }
        return .present(
            workspaceArrangementCursorAtom.activePaneId(forArrangement: arrangementID)
                .map(WorkspacePaneSelection.selected) ?? .noSelection
        )
    }

    private func activeDrawerChildWitness(
        key: ArrangementDrawerCursorKey
    ) -> WorkspaceActiveDrawerChildCursorWitness {
        guard workspaceArrangementCursorAtom.hasDrawerCursor(key) else {
            return .missing
        }
        return .present(
            workspaceArrangementCursorAtom.activeChildId(
                forArrangement: key.arrangementId,
                drawerId: key.drawerId
            ).map(WorkspaceDrawerChildSelection.selected) ?? .noSelection
        )
    }
}

extension WorkspaceArrangementSelectionTransition {
    fileprivate var tabID: UUID {
        switch self {
        case .activePane(let transition): transition.tabID
        case .activeDrawerChild(let transition): transition.tabID
        }
    }

    fileprivate var expectedTabGraph: TabGraphState {
        switch self {
        case .activePane(let transition): transition.expectedTabGraph
        case .activeDrawerChild(let transition): transition.expectedTabGraph
        }
    }

    fileprivate var expectedActiveArrangement: WorkspaceActiveArrangementSelection {
        switch self {
        case .activePane(let transition): transition.expectedActiveArrangement
        case .activeDrawerChild(let transition): transition.expectedActiveArrangement
        }
    }
}

extension WorkspaceActivePaneSelectionMutation {
    fileprivate var arrangementID: UUID {
        switch self {
        case .insert(let arrangementID, _, _),
            .replace(let arrangementID, _, _),
            .remove(let arrangementID, _):
            arrangementID
        }
    }
}

extension WorkspaceActiveDrawerChildSelectionMutation {
    fileprivate var key: ArrangementDrawerCursorKey {
        switch self {
        case .insert(let key, _, _), .replace(let key, _, _): key
        }
    }
}
