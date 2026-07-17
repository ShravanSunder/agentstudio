import Foundation

enum WorkspacePaneResidencyLifecycleApplyRejection: Equatable, Sendable {
    case stalePane(paneID: UUID, expected: PaneGraphState, actual: WorkspacePaneResidencyPaneWitness)
    case staleTabGraph(tabID: UUID, expected: WorkspaceIndexedTabGraphState, actual: WorkspaceTargetTabWitness)
    case stalePaneFamilyOwnership(
        paneID: UUID,
        expected: WorkspacePaneResidencyTabOwnershipWitness,
        actual: WorkspacePaneResidencyTabOwnershipWitness
    )
    case staleTabShellRemoval(
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
    case staleActiveDrawerChild(
        key: ArrangementDrawerCursorKey,
        expected: WorkspacePaneResidencyDrawerCursorWitness,
        actual: WorkspacePaneResidencyDrawerCursorWitness
    )
    case staleZoom(tabID: UUID, expected: WorkspaceZoomSelection, actual: WorkspaceZoomSelection)
    case staleRetainedDrawerPayload(
        expected: WorkspaceRetainedDrawerPayloadWitness,
        actual: WorkspaceRetainedDrawerPayloadWitness
    )
}

enum WorkspacePaneResidencyLifecycleApplyResult: Equatable, Sendable {
    case applied(WorkspacePaneResidencyRuntimeEffect)
    case rejected(WorkspacePaneResidencyLifecycleApplyRejection)
}

enum WorkspacePaneResidencyLifecyclePreflightResult: Equatable, Sendable {
    case ready(WorkspacePreparedPaneResidencyLifecycleApplication)
    case rejected(WorkspacePaneResidencyLifecycleApplyRejection)
}

struct WorkspacePreparedPaneResidencyLifecycleApplication: Equatable, Sendable {
    fileprivate let transition: WorkspacePaneResidencyLifecycleTransition
}

@MainActor
final class WorkspacePaneResidencyLifecycleTransitionApplier {
    private let workspacePaneGraphAtom: WorkspacePaneGraphAtom
    private let workspaceTabShellAtom: WorkspaceTabShellAtom
    private let workspaceTabCursorAtom: WorkspaceTabCursorAtom
    private let workspaceTabGraphAtom: WorkspaceTabGraphAtom
    private let workspaceArrangementCursorAtom: WorkspaceArrangementCursorAtom
    private let workspacePanePresentationAtom: WorkspacePanePresentationAtom

    init(
        workspacePaneGraphAtom: WorkspacePaneGraphAtom,
        workspaceTabShellAtom: WorkspaceTabShellAtom,
        workspaceTabCursorAtom: WorkspaceTabCursorAtom,
        workspaceTabGraphAtom: WorkspaceTabGraphAtom,
        workspaceArrangementCursorAtom: WorkspaceArrangementCursorAtom,
        workspacePanePresentationAtom: WorkspacePanePresentationAtom
    ) {
        self.workspacePaneGraphAtom = workspacePaneGraphAtom
        self.workspaceTabShellAtom = workspaceTabShellAtom
        self.workspaceTabCursorAtom = workspaceTabCursorAtom
        self.workspaceTabGraphAtom = workspaceTabGraphAtom
        self.workspaceArrangementCursorAtom = workspaceArrangementCursorAtom
        self.workspacePanePresentationAtom = workspacePanePresentationAtom
    }

    func apply(
        _ transition: WorkspacePaneResidencyLifecycleTransition,
        retainedDrawerPayload: WorkspaceRetainedDrawerPayloadWitness
    ) -> WorkspacePaneResidencyLifecycleApplyResult {
        switch preflight(transition, retainedDrawerPayload: retainedDrawerPayload) {
        case .ready(let prepared):
            return apply(prepared, retainedDrawerPayload: retainedDrawerPayload)
        case .rejected(let rejection):
            return .rejected(rejection)
        }
    }

    func preflight(
        _ transition: WorkspacePaneResidencyLifecycleTransition,
        retainedDrawerPayload: WorkspaceRetainedDrawerPayloadWitness
    ) -> WorkspacePaneResidencyLifecyclePreflightResult {
        let components = components(of: transition)
        for paneReplacement in components.panes {
            let actual =
                workspacePaneGraphAtom.paneState(paneReplacement.paneID)
                .map(WorkspacePaneResidencyPaneWitness.present) ?? .missing
            guard actual == .present(paneReplacement.previous) else {
                return .rejected(
                    .stalePane(
                        paneID: paneReplacement.paneID,
                        expected: paneReplacement.previous,
                        actual: actual
                    )
                )
            }
        }
        for ownership in components.familyOwnership {
            let actual = paneOwnershipWitness(ownership.paneID)
            guard paneOwnershipLocationMatches(actual, ownership.expected) else {
                return .rejected(
                    .stalePaneFamilyOwnership(
                        paneID: ownership.paneID,
                        expected: ownership.expected,
                        actual: actual
                    )
                )
            }
        }
        if let rejection = preflightTabGraph(components.tabGraph) { return .rejected(rejection) }
        if let rejection = preflightTabShell(components.tabShell) { return .rejected(rejection) }
        if let rejection = preflightTabCursor(components.tabCursor) { return .rejected(rejection) }
        for activeArrangement in components.activeArrangements {
            if let rejection = preflightActiveArrangement(activeArrangement) { return .rejected(rejection) }
        }
        for activePane in components.activePanes {
            if let rejection = preflightActivePane(activePane) { return .rejected(rejection) }
        }
        for activeDrawer in components.activeDrawers {
            if let rejection = preflightActiveDrawer(activeDrawer) { return .rejected(rejection) }
        }
        if let rejection = preflightZoom(components.zoom) { return .rejected(rejection) }
        guard retainedDrawerPayload == components.runtimePayload.expected else {
            return .rejected(
                .staleRetainedDrawerPayload(
                    expected: components.runtimePayload.expected,
                    actual: retainedDrawerPayload
                )
            )
        }
        return .ready(.init(transition: transition))
    }

    func apply(
        _ prepared: WorkspacePreparedPaneResidencyLifecycleApplication,
        retainedDrawerPayload: WorkspaceRetainedDrawerPayloadWitness
    ) -> WorkspacePaneResidencyLifecycleApplyResult {
        switch preflight(
            prepared.transition,
            retainedDrawerPayload: retainedDrawerPayload
        ) {
        case .ready: break
        case .rejected(let rejection):
            return .rejected(rejection)
        }
        let components = components(of: prepared.transition)
        for paneReplacement in components.panes {
            workspacePaneGraphAtom.replaceResidency(
                paneReplacement.replacement.residency,
                forPane: paneReplacement.paneID
            )
        }
        applyTabGraph(components.tabGraph)
        applyTabShell(components.tabShell)
        applyTabCursor(components.tabCursor)
        for mutation in components.activeArrangements { applyActiveArrangement(mutation) }
        for mutation in components.activePanes { applyActivePane(mutation) }
        for mutation in components.activeDrawers { applyActiveDrawer(mutation) }
        applyZoom(components.zoom)
        return .applied(components.runtimePayload.effect)
    }

    private func preflightTabGraph(
        _ mutation: WorkspacePaneResidencyTabGraphMutation
    ) -> WorkspacePaneResidencyLifecycleApplyRejection? {
        let expected: WorkspaceIndexedTabGraphState
        switch mutation {
        case .replace(let previous, _), .remove(let previous): expected = previous
        }
        let actualState = workspaceTabGraphAtom.tabState(expected.state.tabId)
        let actual: WorkspaceTargetTabWitness =
            actualState.map {
                .present(.init(index: workspaceTabGraphAtom.tabIndex(for: expected.state.tabId)!, state: $0))
            } ?? .missing
        guard actual == .present(expected) else {
            return .staleTabGraph(tabID: expected.state.tabId, expected: expected, actual: actual)
        }
        return nil
    }

    private func preflightTabShell(
        _ mutation: WorkspacePaneResidencyTabShellMutation
    ) -> WorkspacePaneResidencyLifecycleApplyRejection? {
        guard case .remove(let removed, let shiftedSuffix) = mutation else { return nil }
        let shells = workspaceTabShellAtom.tabShells
        let actualRemoved =
            shells.indices.contains(removed.index)
            ? WorkspaceIndexedTabShell(index: removed.index, shell: shells[removed.index]) : nil
        let actualSuffix = shells.enumerated().dropFirst(removed.index + 1).map {
            WorkspaceIndexedTabShell(index: $0.offset, shell: $0.element)
        }
        guard actualRemoved == removed, actualSuffix == shiftedSuffix else {
            return .staleTabShellRemoval(
                expectedRemoved: removed,
                actualRemoved: actualRemoved,
                expectedShiftedSuffix: shiftedSuffix,
                actualShiftedSuffix: actualSuffix
            )
        }
        return nil
    }

    private func preflightTabCursor(
        _ mutation: WorkspacePaneResidencyTabCursorMutation
    ) -> WorkspacePaneResidencyLifecycleApplyRejection? {
        let expected: WorkspaceTabCursorSelection
        switch mutation {
        case .notRead: return nil
        case .witness(let selection): expected = selection
        case .replace(let replacement): expected = replacement.previous
        }
        let actual = workspaceTabCursorAtom.activeTabId.map(WorkspaceTabCursorSelection.selected) ?? .noSelection
        return actual == expected ? nil : .staleTabCursor(expected: expected, actual: actual)
    }

    private func preflightActiveArrangement(
        _ mutation: WorkspacePaneResidencyActiveArrangementMutation
    ) -> WorkspacePaneResidencyLifecycleApplyRejection? {
        let tabID: UUID
        let expected: WorkspaceActiveArrangementSelection
        switch mutation {
        case .witness(let id, let selection):
            tabID = id
            expected = selection
        case .remove(let id, let previous):
            tabID = id
            expected = .selected(previous)
        }
        let actual =
            workspaceArrangementCursorAtom.activeArrangementId(forTab: tabID)
            .map(WorkspaceActiveArrangementSelection.selected) ?? .missing
        return actual == expected ? nil : .staleActiveArrangement(tabID: tabID, expected: expected, actual: actual)
    }

    private func preflightActivePane(
        _ mutation: WorkspacePaneResidencyActivePaneMutation
    ) -> WorkspacePaneResidencyLifecycleApplyRejection? {
        let arrangementID: UUID
        let expected: WorkspaceActivePaneCursorWitness
        switch mutation {
        case .witness(let id, let witness), .replace(let id, let witness, _), .remove(let id, let witness):
            arrangementID = id
            expected = witness
        }
        let actual = activePaneWitness(arrangementID)
        return actual == expected
            ? nil : .staleActivePane(arrangementID: arrangementID, expected: expected, actual: actual)
    }

    private func preflightActiveDrawer(
        _ mutation: WorkspacePaneResidencyActiveDrawerMutation
    ) -> WorkspacePaneResidencyLifecycleApplyRejection? {
        let key: ArrangementDrawerCursorKey
        let expected: WorkspacePaneResidencyDrawerCursorWitness
        switch mutation {
        case .witness(let value, let witness), .insert(let value, let witness, _):
            key = value
            expected = witness
        case .replace(let value, let previous, _), .remove(let value, let previous):
            key = value
            expected = previous
        }
        let actual = activeDrawerWitness(key)
        return actual == expected ? nil : .staleActiveDrawerChild(key: key, expected: expected, actual: actual)
    }

    private func preflightZoom(
        _ mutation: WorkspacePaneResidencyZoomMutation
    ) -> WorkspacePaneResidencyLifecycleApplyRejection? {
        let tabID: UUID
        let expected: WorkspaceZoomSelection
        switch mutation {
        case .witness(let id, let selection):
            tabID = id
            expected = selection
        case .clear(let id, let previous):
            tabID = id
            expected = .zoomed(previous)
        }
        let actual =
            workspacePanePresentationAtom.zoomedPaneId(forTab: tabID)
            .map(WorkspaceZoomSelection.zoomed) ?? .notZoomed
        return actual == expected ? nil : .staleZoom(tabID: tabID, expected: expected, actual: actual)
    }

    private func applyTabGraph(_ mutation: WorkspacePaneResidencyTabGraphMutation) {
        switch mutation {
        case .replace(_, let replacement): workspaceTabGraphAtom.replaceTabStateAndOwnership(replacement.state)
        case .remove(let previous): workspaceTabGraphAtom.removeTabState(previous.state.tabId)
        }
    }

    private func applyTabShell(_ mutation: WorkspacePaneResidencyTabShellMutation) {
        guard case .remove(let removed, _) = mutation else { return }
        workspaceTabShellAtom.removeTabShellPreservingCursor(removed.shell.id)
    }

    private func applyTabCursor(_ mutation: WorkspacePaneResidencyTabCursorMutation) {
        guard case .replace(let replacement) = mutation else { return }
        switch replacement.replacement {
        case .noSelection: workspaceTabCursorAtom.replaceActiveTab(nil)
        case .selected(let tabID): workspaceTabCursorAtom.replaceActiveTab(tabID)
        }
    }

    private func applyActiveArrangement(_ mutation: WorkspacePaneResidencyActiveArrangementMutation) {
        guard case .remove(let tabID, _) = mutation else { return }
        workspaceArrangementCursorAtom.removeActiveArrangementId(forTab: tabID)
    }

    private func applyActivePane(_ mutation: WorkspacePaneResidencyActivePaneMutation) {
        switch mutation {
        case .witness: break
        case .replace(let arrangementID, _, let replacement):
            let selectedPaneID: UUID?
            switch replacement {
            case .noSelection: selectedPaneID = nil
            case .selected(let paneID): selectedPaneID = paneID
            }
            workspaceArrangementCursorAtom.setPaneCursor(
                .init(activePaneId: selectedPaneID),
                forArrangement: arrangementID
            )
        case .remove(let arrangementID, _):
            workspaceArrangementCursorAtom.removePaneCursor(forArrangement: arrangementID)
        }
    }

    private func applyActiveDrawer(_ mutation: WorkspacePaneResidencyActiveDrawerMutation) {
        switch mutation {
        case .witness: break
        case .insert(let key, _, let replacement):
            workspaceArrangementCursorAtom.insertDrawerCursor(
                .init(activeChildId: selectedDrawerChildID(replacement)),
                for: key
            )
        case .replace(let key, _, let replacement):
            workspaceArrangementCursorAtom.setDrawerCursor(
                .init(activeChildId: selectedDrawerChildID(replacement)),
                for: key
            )
        case .remove(let key, _): workspaceArrangementCursorAtom.removeDrawerCursor(for: key)
        }
    }

    private func applyZoom(_ mutation: WorkspacePaneResidencyZoomMutation) {
        guard case .clear(let tabID, _) = mutation else { return }
        workspacePanePresentationAtom.setZoomedPaneId(nil, forTab: tabID)
    }

    private func activePaneWitness(_ arrangementID: UUID) -> WorkspaceActivePaneCursorWitness {
        guard let cursor = workspaceArrangementCursorAtom.paneCursorsByArrangementId[arrangementID] else {
            return .missing
        }
        return .present(cursor.activePaneId.map(WorkspacePaneSelection.selected) ?? .noSelection)
    }

    private func activeDrawerWitness(
        _ key: ArrangementDrawerCursorKey
    ) -> WorkspacePaneResidencyDrawerCursorWitness {
        guard let cursor = workspaceArrangementCursorAtom.drawerCursorsByKey[key] else { return .missing }
        return .present(
            cursor.activeChildId.map(WorkspacePaneResidencyDrawerSelection.selected) ?? .noSelection
        )
    }

    private func paneOwnershipWitness(
        _ paneID: UUID
    ) -> WorkspacePaneResidencyTabOwnershipWitness {
        guard let tabID = workspaceTabGraphAtom.tabID(containingPane: paneID),
            let state = workspaceTabGraphAtom.tabState(tabID),
            let index = workspaceTabGraphAtom.tabIndex(for: tabID)
        else { return .absent }
        return .owned(.init(index: index, state: state))
    }
}

private func paneOwnershipLocationMatches(
    _ lhs: WorkspacePaneResidencyTabOwnershipWitness,
    _ rhs: WorkspacePaneResidencyTabOwnershipWitness
) -> Bool {
    switch (lhs, rhs) {
    case (.absent, .absent): return true
    case (.multiple(let lhsIDs), .multiple(let rhsIDs)): return lhsIDs == rhsIDs
    case (.owned(let lhsOwner), .owned(let rhsOwner)):
        return lhsOwner.index == rhsOwner.index && lhsOwner.state.tabId == rhsOwner.state.tabId
    default: return false
    }
}

private struct WorkspacePaneResidencyLifecycleComponents {
    let panes: [WorkspacePaneResidencyPaneReplacement]
    let familyOwnership: [WorkspacePaneResidencyFamilyOwnershipWitness]
    let tabGraph: WorkspacePaneResidencyTabGraphMutation
    let tabShell: WorkspacePaneResidencyTabShellMutation
    let tabCursor: WorkspacePaneResidencyTabCursorMutation
    let activeArrangements: [WorkspacePaneResidencyActiveArrangementMutation]
    let activePanes: [WorkspacePaneResidencyActivePaneMutation]
    let activeDrawers: [WorkspacePaneResidencyActiveDrawerMutation]
    let zoom: WorkspacePaneResidencyZoomMutation
    let runtimePayload: WorkspacePaneResidencyRuntimePayloadTransition
}

private func components(
    of transition: WorkspacePaneResidencyLifecycleTransition
) -> WorkspacePaneResidencyLifecycleComponents {
    switch transition {
    case .background(let value):
        return .init(
            panes: value.paneReplacements,
            familyOwnership: value.familyOwnership,
            tabGraph: value.tabGraph,
            tabShell: value.tabShell,
            tabCursor: value.tabCursor,
            activeArrangements: value.activeArrangements,
            activePanes: value.activePanes,
            activeDrawers: value.activeDrawerChildren,
            zoom: value.zoom,
            runtimePayload: value.runtimePayload
        )
    case .reactivate(let value):
        return .init(
            panes: value.paneReplacements,
            familyOwnership: value.familyOwnership,
            tabGraph: value.tabGraph,
            tabShell: .notRead,
            tabCursor: .notRead,
            activeArrangements: value.activeArrangements,
            activePanes: value.activePanes,
            activeDrawers: value.activeDrawerChildren,
            zoom: value.zoom,
            runtimePayload: value.runtimePayload
        )
    }
}

private func selectedDrawerChildID(
    _ selection: WorkspacePaneResidencyDrawerSelection
) -> UUID? {
    guard case .selected(let childID) = selection else { return nil }
    return childID
}
