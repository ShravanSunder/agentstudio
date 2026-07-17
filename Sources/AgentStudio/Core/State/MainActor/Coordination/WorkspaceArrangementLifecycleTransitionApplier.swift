import Foundation

enum WorkspaceArrangementLifecycleApplyRejection: Equatable, Sendable {
    case arrangementIdentityAlreadyOwned(arrangementID: UUID, tabID: UUID)
    case proposedDrawerCursorAlreadyExists(ArrangementDrawerCursorKey)
    case proposedPaneCursorAlreadyExists(UUID)
    case staleActiveArrangement(
        tabID: UUID,
        expected: WorkspaceActiveArrangementSelection,
        actual: WorkspaceActiveArrangementSelection
    )
    case staleDrawerCursor(
        key: ArrangementDrawerCursorKey,
        expected: WorkspaceActiveDrawerChildCursorWitness,
        actual: WorkspaceActiveDrawerChildCursorWitness
    )
    case stalePaneCursor(
        arrangementID: UUID,
        expected: WorkspaceActivePaneCursorWitness,
        actual: WorkspaceActivePaneCursorWitness
    )
    case staleTabGraph(tabID: UUID, expected: TabGraphState, actual: WorkspaceTabGraphStateWitness)
}

enum WorkspaceArrangementLifecycleApplyResult: Equatable, Sendable {
    case applied
    case rejected(WorkspaceArrangementLifecycleApplyRejection)
}

enum WorkspaceArrangementLifecyclePreflightResult: Equatable, Sendable {
    case ready(WorkspacePreparedArrangementLifecycleApplication)
    case rejected(WorkspaceArrangementLifecycleApplyRejection)
}

struct WorkspacePreparedArrangementLifecycleApplication: Equatable, Sendable {
    fileprivate let transition: WorkspaceArrangementLifecycleTransition
}

@MainActor
final class WorkspaceArrangementLifecycleTransitionApplier {
    private let workspaceTabGraphAtom: WorkspaceTabGraphAtom
    private let workspaceArrangementCursorAtom: WorkspaceArrangementCursorAtom

    init(
        workspaceTabGraphAtom: WorkspaceTabGraphAtom,
        workspaceArrangementCursorAtom: WorkspaceArrangementCursorAtom
    ) {
        self.workspaceTabGraphAtom = workspaceTabGraphAtom
        self.workspaceArrangementCursorAtom = workspaceArrangementCursorAtom
    }

    func preflight(
        _ transition: WorkspaceArrangementLifecycleTransition
    ) -> WorkspaceArrangementLifecyclePreflightResult {
        if let rejection = validateTabAndActiveArrangement(transition) {
            return .rejected(rejection)
        }
        let rejection: WorkspaceArrangementLifecycleApplyRejection?
        switch transition {
        case .create(let creation): rejection = validateCreate(creation)
        case .remove(let removal): rejection = validateRemove(removal)
        }
        return rejection.map(WorkspaceArrangementLifecyclePreflightResult.rejected)
            ?? .ready(.init(transition: transition))
    }

    func apply(
        _ transition: WorkspaceArrangementLifecycleTransition
    ) -> WorkspaceArrangementLifecycleApplyResult {
        switch preflight(transition) {
        case .rejected(let rejection): return .rejected(rejection)
        case .ready(let preparation):
            apply(preparation)
            return .applied
        }
    }

    func apply(_ preparation: WorkspacePreparedArrangementLifecycleApplication) {
        guard case .ready = preflight(preparation.transition) else {
            preconditionFailure("prepared arrangement lifecycle application became stale")
        }
        switch preparation.transition {
        case .create(let creation): applyCreate(creation)
        case .remove(let removal): applyRemove(removal)
        }
    }

    private func validateTabAndActiveArrangement(
        _ transition: WorkspaceArrangementLifecycleTransition
    ) -> WorkspaceArrangementLifecycleApplyRejection? {
        let previousTab = transition.previousTab
        let actualTab = workspaceTabGraphAtom.tabState(previousTab.tabId)
        guard actualTab == previousTab else {
            return .staleTabGraph(
                tabID: previousTab.tabId,
                expected: previousTab,
                actual: actualTab.map(WorkspaceTabGraphStateWitness.present) ?? .missing
            )
        }
        let expected = transition.expectedActiveArrangement
        let actual = activeArrangementWitness(tabID: previousTab.tabId)
        guard actual == expected else {
            return .staleActiveArrangement(tabID: previousTab.tabId, expected: expected, actual: actual)
        }
        return nil
    }

    private func validateCreate(
        _ creation: WorkspaceCreateArrangementTransition
    ) -> WorkspaceArrangementLifecycleApplyRejection? {
        let newArrangementID = creation.paneCursorInsertion.arrangementID
        if let owner = workspaceTabGraphAtom.tabID(containingArrangement: newArrangementID) {
            return .arrangementIdentityAlreadyOwned(arrangementID: newArrangementID, tabID: owner)
        }
        guard case .missing = activePaneWitness(arrangementID: newArrangementID) else {
            return .proposedPaneCursorAlreadyExists(newArrangementID)
        }
        if let rejection = validatePaneCursor(
            arrangementID: creation.expectedActiveArrangement.arrangementID,
            expected: creation.expectedSourcePaneCursor
        ) {
            return rejection
        }
        if let rejection = validateDrawerCursors(
            creation.expectedSourceDrawerCursors,
            arrangementID: creation.expectedActiveArrangement.arrangementID
        ) {
            return rejection
        }
        for insertion in creation.drawerCursorInsertions
        where workspaceArrangementCursorAtom.hasDrawerCursor(insertion.key) {
            return .proposedDrawerCursorAlreadyExists(insertion.key)
        }
        return nil
    }

    private func validateRemove(
        _ removal: WorkspaceRemoveArrangementTransition
    ) -> WorkspaceArrangementLifecycleApplyRejection? {
        if let rejection = validatePaneCursor(
            arrangementID: removal.removedArrangementID,
            expected: removal.expectedPaneCursor
        ) {
            return rejection
        }
        return validateDrawerCursors(
            removal.expectedDrawerCursors,
            arrangementID: removal.removedArrangementID
        )
    }

    private func validatePaneCursor(
        arrangementID: UUID,
        expected: WorkspaceActivePaneCursorWitness
    ) -> WorkspaceArrangementLifecycleApplyRejection? {
        let actual = activePaneWitness(arrangementID: arrangementID)
        guard actual == expected else {
            return .stalePaneCursor(arrangementID: arrangementID, expected: expected, actual: actual)
        }
        return nil
    }

    private func validateDrawerCursors(
        _ cursors: [WorkspaceArrangementDrawerCursorWitness],
        arrangementID: UUID
    ) -> WorkspaceArrangementLifecycleApplyRejection? {
        for cursor in cursors {
            let key = ArrangementDrawerCursorKey(arrangementId: arrangementID, drawerId: cursor.drawerID)
            let actual = activeDrawerCursorWitness(key: key)
            guard actual == cursor.cursor else {
                return .staleDrawerCursor(key: key, expected: cursor.cursor, actual: actual)
            }
        }
        return nil
    }

    private func applyCreate(_ creation: WorkspaceCreateArrangementTransition) {
        workspaceTabGraphAtom.replaceTabStateAndArrangementOwnership(creation.replacementTab)
        workspaceArrangementCursorAtom.insertPaneCursor(
            creation.paneCursorInsertion.state,
            forArrangement: creation.paneCursorInsertion.arrangementID
        )
        for insertion in creation.drawerCursorInsertions {
            workspaceArrangementCursorAtom.insertDrawerCursor(insertion.state, for: insertion.key)
        }
    }

    private func applyRemove(_ removal: WorkspaceRemoveArrangementTransition) {
        workspaceTabGraphAtom.replaceTabStateAndArrangementOwnership(removal.replacementTab)
        workspaceArrangementCursorAtom.removePaneCursor(forArrangement: removal.removedArrangementID)
        for cursor in removal.expectedDrawerCursors {
            workspaceArrangementCursorAtom.removeDrawerCursor(
                for: .init(arrangementId: removal.removedArrangementID, drawerId: cursor.drawerID)
            )
        }
        if let replacementActiveArrangementID = removal.replacementActiveArrangementID {
            workspaceArrangementCursorAtom.setActiveArrangementId(
                replacementActiveArrangementID,
                forTab: removal.previousTab.tabId
            )
        }
    }

    private func activeArrangementWitness(tabID: UUID) -> WorkspaceActiveArrangementSelection {
        workspaceArrangementCursorAtom.activeArrangementId(forTab: tabID)
            .map(WorkspaceActiveArrangementSelection.selected) ?? .missing
    }

    private func activePaneWitness(arrangementID: UUID) -> WorkspaceActivePaneCursorWitness {
        guard workspaceArrangementCursorAtom.hasPaneCursor(arrangementID: arrangementID) else { return .missing }
        return .present(
            workspaceArrangementCursorAtom.activePaneId(forArrangement: arrangementID)
                .map(WorkspacePaneSelection.selected) ?? .noSelection
        )
    }

    private func activeDrawerCursorWitness(
        key: ArrangementDrawerCursorKey
    ) -> WorkspaceActiveDrawerChildCursorWitness {
        guard workspaceArrangementCursorAtom.hasDrawerCursor(key) else { return .missing }
        return .present(
            workspaceArrangementCursorAtom.activeChildId(
                forArrangement: key.arrangementId,
                drawerId: key.drawerId
            ).map(WorkspaceDrawerChildSelection.selected) ?? .noSelection
        )
    }
}

extension WorkspaceArrangementLifecycleTransition {
    fileprivate var previousTab: TabGraphState {
        switch self {
        case .create(let creation): creation.previousTab
        case .remove(let removal): removal.previousTab
        }
    }

    fileprivate var expectedActiveArrangement: WorkspaceActiveArrangementSelection {
        switch self {
        case .create(let creation): creation.expectedActiveArrangement
        case .remove(let removal): removal.expectedActiveArrangement
        }
    }
}

extension WorkspaceActiveArrangementSelection {
    fileprivate var arrangementID: UUID {
        guard case .selected(let arrangementID) = self else {
            preconditionFailure("arrangement lifecycle transition requires a selected active arrangement")
        }
        return arrangementID
    }
}
