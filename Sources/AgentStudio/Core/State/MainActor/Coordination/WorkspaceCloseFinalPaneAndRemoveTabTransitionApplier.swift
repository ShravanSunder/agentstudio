import Foundation

enum WorkspaceCloseFinalPaneAndRemoveTabApplyRejection: Equatable, Sendable {
    case stalePane(paneID: UUID, expected: WorkspaceClosePaneWitness, actual: WorkspaceClosePaneWitness)
    case staleOwnership(
        paneID: UUID,
        expected: WorkspaceClosePaneOwnershipWitness,
        actual: WorkspaceClosePaneOwnershipWitness
    )
    case staleTab(expected: WorkspaceIndexedTabGraphState, actual: WorkspaceIndexedTabGraphState?)
    case staleShellRemoval(
        expectedRemoved: WorkspaceIndexedTabShell,
        actualRemoved: WorkspaceIndexedTabShell?,
        expectedShiftedSuffix: [WorkspaceIndexedTabShell],
        actualShiftedSuffix: [WorkspaceIndexedTabShell]
    )
    case staleTabCursor(expected: WorkspaceTabCursorSelection, actual: WorkspaceTabCursorSelection)
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
    case staleArrangementDrawerCursor(
        key: ArrangementDrawerCursorKey,
        expected: WorkspacePaneResidencyDrawerCursorWitness,
        actual: WorkspacePaneResidencyDrawerCursorWitness
    )
    case staleDrawerCursor(expected: WorkspaceDrawerCursorSelection, actual: WorkspaceDrawerCursorSelection)
    case staleZoom(tabID: UUID, expected: WorkspaceZoomSelection, actual: WorkspaceZoomSelection)
}

enum WorkspaceCloseFinalPaneAndRemoveTabApplyResult: Equatable, Sendable {
    case applied
    case rejected(WorkspaceCloseFinalPaneAndRemoveTabApplyRejection)
}

enum WorkspaceCloseFinalPaneAndRemoveTabPreflightResult: Equatable, Sendable {
    case ready(WorkspacePreparedFinalPaneTabRemoval)
    case rejected(WorkspaceCloseFinalPaneAndRemoveTabApplyRejection)
}

struct WorkspacePreparedFinalPaneTabRemoval: Equatable, Sendable {
    fileprivate let transition: WorkspaceCloseFinalPaneAndRemoveTabTransition
}

@MainActor
final class WorkspaceFinalPaneTabRemovalApplier {
    private let workspacePaneGraphAtom: WorkspacePaneGraphAtom
    private let workspaceTabShellAtom: WorkspaceTabShellAtom
    private let workspaceTabCursorAtom: WorkspaceTabCursorAtom
    private let workspaceTabGraphAtom: WorkspaceTabGraphAtom
    private let workspaceArrangementCursorAtom: WorkspaceArrangementCursorAtom
    private let workspaceDrawerCursorAtom: WorkspaceDrawerCursorAtom
    private let workspacePanePresentationAtom: WorkspacePanePresentationAtom

    init(
        workspacePaneGraphAtom: WorkspacePaneGraphAtom,
        workspaceTabShellAtom: WorkspaceTabShellAtom,
        workspaceTabCursorAtom: WorkspaceTabCursorAtom,
        workspaceTabGraphAtom: WorkspaceTabGraphAtom,
        workspaceArrangementCursorAtom: WorkspaceArrangementCursorAtom,
        workspaceDrawerCursorAtom: WorkspaceDrawerCursorAtom,
        workspacePanePresentationAtom: WorkspacePanePresentationAtom
    ) {
        self.workspacePaneGraphAtom = workspacePaneGraphAtom
        self.workspaceTabShellAtom = workspaceTabShellAtom
        self.workspaceTabCursorAtom = workspaceTabCursorAtom
        self.workspaceTabGraphAtom = workspaceTabGraphAtom
        self.workspaceArrangementCursorAtom = workspaceArrangementCursorAtom
        self.workspaceDrawerCursorAtom = workspaceDrawerCursorAtom
        self.workspacePanePresentationAtom = workspacePanePresentationAtom
    }

    func apply(
        _ transition: WorkspaceCloseFinalPaneAndRemoveTabTransition
    ) -> WorkspaceCloseFinalPaneAndRemoveTabApplyResult {
        switch preflight(transition) {
        case .ready(let prepared):
            apply(prepared)
            return .applied
        case .rejected(let rejection):
            return .rejected(rejection)
        }
    }

    func preflight(
        _ transition: WorkspaceCloseFinalPaneAndRemoveTabTransition
    ) -> WorkspaceCloseFinalPaneAndRemoveTabPreflightResult {
        let paneID = transition.previousPane.id
        let expectedPane = WorkspaceClosePaneWitness.present(transition.previousPane)
        let actualPane = paneWitness(paneID)
        guard actualPane == expectedPane else {
            return .rejected(.stalePane(paneID: paneID, expected: expectedPane, actual: actualPane))
        }
        let expectedOwnership = WorkspaceClosePaneOwnershipWitness.owned(tabID: transition.removedTab.state.tabId)
        let actualOwnership = ownershipWitness(paneID)
        guard actualOwnership == expectedOwnership else {
            return .rejected(
                .staleOwnership(paneID: paneID, expected: expectedOwnership, actual: actualOwnership)
            )
        }
        let actualTab = indexedTab(transition.removedTab.state.tabId)
        guard actualTab == transition.removedTab else {
            return .rejected(.staleTab(expected: transition.removedTab, actual: actualTab))
        }
        if let rejection = preflightShell(transition) { return .rejected(rejection) }
        if let rejection = preflightTabCursor(transition.tabCursor) { return .rejected(rejection) }
        let tabID = transition.removedTab.state.tabId
        let actualArrangement = activeArrangementWitness(tabID)
        let expectedArrangement = WorkspaceActiveArrangementSelection.selected(
            transition.removedActiveArrangementID
        )
        guard actualArrangement == expectedArrangement else {
            return .rejected(
                .staleActiveArrangement(
                    tabID: tabID,
                    expected: expectedArrangement,
                    actual: actualArrangement
                )
            )
        }
        for witness in transition.removedActivePanes {
            let actual = activePaneWitness(witness.arrangementID)
            guard actual == witness.cursor else {
                return .rejected(
                    .staleActivePane(
                        arrangementID: witness.arrangementID,
                        expected: witness.cursor,
                        actual: actual
                    )
                )
            }
        }
        let removedArrangementIDs = Set(transition.absentDrawerCursors.arrangementIDs)
        if let key = workspaceArrangementCursorAtom.drawerCursorsByKey.keys.first(where: {
            removedArrangementIDs.contains($0.arrangementId)
        }) {
            let actual = arrangementDrawerWitness(key)
            return .rejected(
                .staleArrangementDrawerCursor(
                    key: key,
                    expected: .missing,
                    actual: actual
                )
            )
        }
        let actualDrawerCursor = WorkspaceDrawerCursorSelection(
            expandedDrawerID: workspaceDrawerCursorAtom.expandedDrawerId
        )
        guard actualDrawerCursor == transition.drawerCursor else {
            return .rejected(.staleDrawerCursor(expected: transition.drawerCursor, actual: actualDrawerCursor))
        }
        if let rejection = preflightZoom(transition.zoom) { return .rejected(rejection) }
        return .ready(.init(transition: transition))
    }

    func apply(_ prepared: WorkspacePreparedFinalPaneTabRemoval) {
        guard case .ready = preflight(prepared.transition) else {
            preconditionFailure("prepared final-pane tab removal became stale")
        }
        let transition = prepared.transition
        workspaceTabGraphAtom.removeTabState(transition.removedTab.state.tabId)
        workspaceTabShellAtom.removeTabShellPreservingCursor(transition.removedShell.shell.id)
        applyTabCursor(transition.tabCursor)
        workspaceArrangementCursorAtom.removeActiveArrangementId(forTab: transition.removedTab.state.tabId)
        for witness in transition.removedActivePanes {
            workspaceArrangementCursorAtom.removePaneCursor(forArrangement: witness.arrangementID)
        }
        if case .clear(let tabID, _) = transition.zoom {
            workspacePanePresentationAtom.setZoomedPaneId(nil, forTab: tabID)
        }
        let removedPane = workspacePaneGraphAtom.removeCanonicalPaneState(for: transition.previousPane.id)
        precondition(
            removedPane == transition.previousPane, "preflighted final-pane removal must remove its exact pane")
    }

    private func preflightShell(
        _ transition: WorkspaceCloseFinalPaneAndRemoveTabTransition
    ) -> WorkspaceCloseFinalPaneAndRemoveTabApplyRejection? {
        let shells = workspaceTabShellAtom.tabShells
        let index = transition.removedShell.index
        let actualRemoved =
            shells.indices.contains(index)
            ? WorkspaceIndexedTabShell(index: index, shell: shells[index]) : nil
        let actualSuffix = shells.enumerated().dropFirst(index + 1).map {
            WorkspaceIndexedTabShell(index: $0.offset, shell: $0.element)
        }
        guard
            actualRemoved == transition.removedShell,
            actualSuffix == transition.shiftedShellSuffix
        else {
            return .staleShellRemoval(
                expectedRemoved: transition.removedShell,
                actualRemoved: actualRemoved,
                expectedShiftedSuffix: transition.shiftedShellSuffix,
                actualShiftedSuffix: actualSuffix
            )
        }
        return nil
    }

    private func preflightTabCursor(
        _ mutation: WorkspaceFinalPaneTabCursorMutation
    ) -> WorkspaceCloseFinalPaneAndRemoveTabApplyRejection? {
        let expected: WorkspaceTabCursorSelection
        switch mutation {
        case .witness(let selection): expected = selection
        case .replace(let replacement): expected = replacement.previous
        }
        let actual = workspaceTabCursorAtom.activeTabId.map(WorkspaceTabCursorSelection.selected) ?? .noSelection
        return actual == expected ? nil : .staleTabCursor(expected: expected, actual: actual)
    }

    private func preflightZoom(
        _ mutation: WorkspaceFinalPaneZoomMutation
    ) -> WorkspaceCloseFinalPaneAndRemoveTabApplyRejection? {
        let tabID: UUID
        let expected: WorkspaceZoomSelection
        switch mutation {
        case .witness(let id, let witness):
            tabID = id
            expected = witness
        case .clear(let id, let paneID):
            tabID = id
            expected = .zoomed(paneID)
        }
        let actual =
            workspacePanePresentationAtom.zoomedPaneId(forTab: tabID)
            .map(WorkspaceZoomSelection.zoomed) ?? .notZoomed
        return actual == expected ? nil : .staleZoom(tabID: tabID, expected: expected, actual: actual)
    }

    private func applyTabCursor(_ mutation: WorkspaceFinalPaneTabCursorMutation) {
        guard case .replace(let replacement) = mutation else { return }
        switch replacement.replacement {
        case .noSelection: workspaceTabCursorAtom.replaceActiveTab(nil)
        case .selected(let tabID): workspaceTabCursorAtom.replaceActiveTab(tabID)
        }
    }

    private func paneWitness(_ paneID: UUID) -> WorkspaceClosePaneWitness {
        workspacePaneGraphAtom.paneState(paneID).map(WorkspaceClosePaneWitness.present) ?? .missing
    }

    private func ownershipWitness(_ paneID: UUID) -> WorkspaceClosePaneOwnershipWitness {
        workspaceTabGraphAtom.tabID(containingPane: paneID).map(WorkspaceClosePaneOwnershipWitness.owned) ?? .absent
    }

    private func indexedTab(_ tabID: UUID) -> WorkspaceIndexedTabGraphState? {
        guard
            let state = workspaceTabGraphAtom.tabState(tabID),
            let index = workspaceTabGraphAtom.tabIndex(for: tabID)
        else { return nil }
        return .init(index: index, state: state)
    }

    private func activeArrangementWitness(_ tabID: UUID) -> WorkspaceActiveArrangementSelection {
        workspaceArrangementCursorAtom.activeArrangementId(forTab: tabID)
            .map(WorkspaceActiveArrangementSelection.selected) ?? .missing
    }

    private func activePaneWitness(_ arrangementID: UUID) -> WorkspaceActivePaneCursorWitness {
        guard workspaceArrangementCursorAtom.hasPaneCursor(arrangementID: arrangementID) else { return .missing }
        return .present(
            workspaceArrangementCursorAtom.activePaneId(forArrangement: arrangementID)
                .map(WorkspacePaneSelection.selected) ?? .noSelection
        )
    }

    private func arrangementDrawerWitness(
        _ key: ArrangementDrawerCursorKey
    ) -> WorkspacePaneResidencyDrawerCursorWitness {
        guard workspaceArrangementCursorAtom.hasDrawerCursor(key) else { return .missing }
        return .present(
            workspaceArrangementCursorAtom.activeChildId(
                forArrangement: key.arrangementId,
                drawerId: key.drawerId
            ).map(WorkspacePaneResidencyDrawerSelection.selected) ?? .noSelection
        )
    }
}
