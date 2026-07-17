import Foundation

struct WorkspaceClosePaneInRetainedTabRequest: Equatable, Sendable {
    let paneID: UUID
    let tabID: UUID
}

enum WorkspaceClosePaneWitness: Equatable, Sendable {
    case missing
    case present(PaneGraphState)
}

enum WorkspaceClosePaneOwnershipWitness: Equatable, Sendable {
    case absent
    case owned(tabID: UUID)
    case multiple([UUID])
}

enum WorkspaceClosePaneTabWitness: Equatable, Sendable {
    case missing
    case present(TabGraphState)
}

struct WorkspaceClosePaneCursorWitness: Equatable, Sendable {
    let arrangementID: UUID
    let cursor: WorkspaceActivePaneCursorWitness
}

struct WorkspaceClosePaneInRetainedTabPlanningContext: Equatable, Sendable {
    let pane: WorkspaceClosePaneWitness
    let ownership: WorkspaceClosePaneOwnershipWitness
    let tab: WorkspaceClosePaneTabWitness
    let activeArrangement: WorkspaceActiveArrangementSelection
    let paneCursors: [WorkspaceClosePaneCursorWitness]
    let drawerCursor: WorkspaceDrawerCursorSelection
    let zoom: WorkspaceZoomSelection
}

enum WorkspaceClosePaneActiveArrangementMutation: Equatable, Sendable {
    case witness(tabID: UUID, expected: WorkspaceActiveArrangementSelection)
    case replace(tabID: UUID, previousArrangementID: UUID, replacementArrangementID: UUID)
}

enum WorkspaceClosePaneActivePaneMutation: Equatable, Sendable {
    case witness(arrangementID: UUID, expected: WorkspaceActivePaneCursorWitness)
    case replace(
        arrangementID: UUID,
        previous: WorkspaceActivePaneCursorWitness,
        replacement: WorkspacePaneSelection
    )
}

enum WorkspaceClosePaneZoomMutation: Equatable, Sendable {
    case witness(tabID: UUID, expected: WorkspaceZoomSelection)
    case clear(tabID: UUID, previousPaneID: UUID)
}

struct WorkspaceClosePaneInRetainedTabTransition: Equatable, Sendable {
    let previousPane: PaneGraphState
    let previousTab: TabGraphState
    let replacementTab: TabGraphState
    let activeArrangement: WorkspaceClosePaneActiveArrangementMutation
    let activePanes: [WorkspaceClosePaneActivePaneMutation]
    let drawerCursor: WorkspaceDrawerCursorSelection
    let zoom: WorkspaceClosePaneZoomMutation

    fileprivate init(
        previousPane: PaneGraphState,
        previousTab: TabGraphState,
        replacementTab: TabGraphState,
        activeArrangement: WorkspaceClosePaneActiveArrangementMutation,
        activePanes: [WorkspaceClosePaneActivePaneMutation],
        drawerCursor: WorkspaceDrawerCursorSelection,
        zoom: WorkspaceClosePaneZoomMutation
    ) {
        self.previousPane = previousPane
        self.previousTab = previousTab
        self.replacementTab = replacementTab
        self.activeArrangement = activeArrangement
        self.activePanes = activePanes
        self.drawerCursor = drawerCursor
        self.zoom = zoom
    }
}

enum WorkspaceClosePaneInRetainedTabDecision: Equatable, Sendable {
    case changed(WorkspaceClosePaneInRetainedTabTransition)
    case rejected(WorkspaceClosePaneInRetainedTabRejection)
}

enum WorkspaceClosePaneInRetainedTabRejection: Error, Equatable, Sendable {
    case paneMissing(UUID)
    case paneIdentityMismatch(expected: UUID, actual: UUID)
    case paneUnowned(UUID)
    case paneOwnedByWrongTab(paneID: UUID, expectedTabID: UUID, actualTabID: UUID)
    case paneMultiplyOwned(UUID, [UUID])
    case paneNotActive(UUID)
    case paneIsDrawerChild(UUID)
    case paneDrawerParentMismatch(paneID: UUID, actualParentPaneID: UUID)
    case paneDrawerPopulated(UUID)
    case paneDrawerExpanded(drawerID: UUID)
    case tabMissing(UUID)
    case tabIdentityMismatch(expected: UUID, actual: UUID)
    case duplicatePaneIdentity(tabID: UUID, paneID: UUID)
    case duplicateArrangementIdentity(tabID: UUID, arrangementID: UUID)
    case duplicateArrangementPane(tabID: UUID, arrangementID: UUID, paneID: UUID)
    case malformedDefault(tabID: UUID, arrangementIDs: [UUID])
    case tabDoesNotOwnPane(tabID: UUID, paneID: UUID)
    case arrangementMissingPane(tabID: UUID, arrangementID: UUID, paneID: UUID)
    case wouldRemoveLastPane(UUID)
    case activeArrangementMissing(UUID)
    case activeArrangementNotInTab(tabID: UUID, arrangementID: UUID)
    case cursorArrangementOutOfOrder(expected: UUID, actual: UUID)
    case cursorMissing(UUID)
    case cursorExtra(UUID)
    case cursorInvalid(arrangementID: UUID, cursor: WorkspaceActivePaneCursorWitness)
    case layoutRemovalFailed(tabID: UUID, arrangementID: UUID, paneID: UUID)
}

enum WorkspaceClosePaneInRetainedTabTransitionPlanner {
    static func plan(
        _ request: WorkspaceClosePaneInRetainedTabRequest,
        context: WorkspaceClosePaneInRetainedTabPlanningContext
    ) -> WorkspaceClosePaneInRetainedTabDecision {
        let pane: PaneGraphState
        switch resolvePane(request, witness: context.pane) {
        case .success(let value): pane = value
        case .failure(let rejection): return .rejected(rejection)
        }
        if let rejection = validatePane(pane, request: request) { return .rejected(rejection) }
        if let rejection = validateDrawerCursor(pane, witness: context.drawerCursor) {
            return .rejected(rejection)
        }
        if let rejection = validateOwnership(request, witness: context.ownership) { return .rejected(rejection) }
        let tab: TabGraphState
        switch resolveTab(request, witness: context.tab) {
        case .success(let value): tab = value
        case .failure(let rejection): return .rejected(rejection)
        }
        if let rejection = validateTab(tab, request: request) { return .rejected(rejection) }
        let activeArrangementID: UUID
        switch resolveActiveArrangement(context.activeArrangement, tab: tab) {
        case .success(let value): activeArrangementID = value
        case .failure(let rejection): return .rejected(rejection)
        }
        if let rejection = validateCursors(context.paneCursors, tab: tab) { return .rejected(rejection) }

        var replacement = tab
        replacement.allPaneIds.removeAll { $0 == request.paneID }
        var activePanes: [WorkspaceClosePaneActivePaneMutation] = []
        for index in replacement.arrangements.indices {
            let previous = tab.arrangements[index]
            let layout: Layout
            if previous.layout.panes.count == 1 {
                layout = Layout()
            } else if let removed = previous.layout.removing(
                paneId: request.paneID,
                sizingMode: .proportional
            ) {
                layout = removed
            } else {
                return .rejected(
                    .layoutRemovalFailed(
                        tabID: tab.tabId,
                        arrangementID: previous.id,
                        paneID: request.paneID
                    )
                )
            }
            replacement.arrangements[index].layout = layout
            replacement.arrangements[index].minimizedPaneIds.remove(request.paneID)
            activePanes.append(
                activePaneMutation(
                    context.paneCursors[index].cursor,
                    paneID: request.paneID,
                    replacement: replacement.arrangements[index]
                )
            )
        }

        return .changed(
            .init(
                previousPane: pane,
                previousTab: tab,
                replacementTab: replacement,
                activeArrangement: activeArrangementMutation(
                    previous: tab,
                    replacement: replacement,
                    activeArrangementID: activeArrangementID
                ),
                activePanes: activePanes,
                drawerCursor: context.drawerCursor,
                zoom: zoomMutation(context.zoom, tabID: tab.tabId, paneID: request.paneID)
            )
        )
    }
}

extension WorkspaceClosePaneInRetainedTabTransitionPlanner {
    private static func resolvePane(
        _ request: WorkspaceClosePaneInRetainedTabRequest,
        witness: WorkspaceClosePaneWitness
    ) -> Result<PaneGraphState, WorkspaceClosePaneInRetainedTabRejection> {
        switch witness {
        case .missing:
            return .failure(.paneMissing(request.paneID))
        case .present(let pane) where pane.id != request.paneID:
            return .failure(.paneIdentityMismatch(expected: request.paneID, actual: pane.id))
        case .present(let pane):
            return .success(pane)
        }
    }

    private static func validatePane(
        _ pane: PaneGraphState,
        request: WorkspaceClosePaneInRetainedTabRequest
    ) -> WorkspaceClosePaneInRetainedTabRejection? {
        guard pane.residency.isActive else { return .paneNotActive(request.paneID) }
        switch pane.kind {
        case .drawerChild:
            return .paneIsDrawerChild(request.paneID)
        case .layout(let drawer) where drawer.parentPaneId != request.paneID:
            return .paneDrawerParentMismatch(
                paneID: request.paneID,
                actualParentPaneID: drawer.parentPaneId
            )
        case .layout(let drawer) where !drawer.paneIds.isEmpty:
            return .paneDrawerPopulated(request.paneID)
        case .layout:
            return nil
        }
    }

    private static func validateOwnership(
        _ request: WorkspaceClosePaneInRetainedTabRequest,
        witness: WorkspaceClosePaneOwnershipWitness
    ) -> WorkspaceClosePaneInRetainedTabRejection? {
        switch witness {
        case .absent:
            return .paneUnowned(request.paneID)
        case .owned(let tabID) where tabID != request.tabID:
            return .paneOwnedByWrongTab(
                paneID: request.paneID,
                expectedTabID: request.tabID,
                actualTabID: tabID
            )
        case .owned:
            return nil
        case .multiple(let tabIDs):
            return .paneMultiplyOwned(request.paneID, tabIDs)
        }
    }

    private static func validateDrawerCursor(
        _ pane: PaneGraphState,
        witness: WorkspaceDrawerCursorSelection
    ) -> WorkspaceClosePaneInRetainedTabRejection? {
        guard let drawerID = pane.drawer?.drawerId else { return nil }
        guard witness != .expanded(drawerID: drawerID) else {
            return .paneDrawerExpanded(drawerID: drawerID)
        }
        return nil
    }

    private static func resolveTab(
        _ request: WorkspaceClosePaneInRetainedTabRequest,
        witness: WorkspaceClosePaneTabWitness
    ) -> Result<TabGraphState, WorkspaceClosePaneInRetainedTabRejection> {
        switch witness {
        case .missing:
            return .failure(.tabMissing(request.tabID))
        case .present(let tab) where tab.tabId != request.tabID:
            return .failure(.tabIdentityMismatch(expected: request.tabID, actual: tab.tabId))
        case .present(let tab):
            return .success(tab)
        }
    }

    private static func validateTab(
        _ tab: TabGraphState,
        request: WorkspaceClosePaneInRetainedTabRequest
    ) -> WorkspaceClosePaneInRetainedTabRejection? {
        if let duplicate = duplicate(in: tab.allPaneIds) {
            return .duplicatePaneIdentity(tabID: tab.tabId, paneID: duplicate)
        }
        var arrangementIDs: Set<UUID> = []
        for arrangement in tab.arrangements {
            guard arrangementIDs.insert(arrangement.id).inserted else {
                return .duplicateArrangementIdentity(tabID: tab.tabId, arrangementID: arrangement.id)
            }
            if let duplicate = duplicate(in: arrangement.layout.paneIds) {
                return .duplicateArrangementPane(
                    tabID: tab.tabId,
                    arrangementID: arrangement.id,
                    paneID: duplicate
                )
            }
            guard arrangement.layout.contains(request.paneID) else {
                return .arrangementMissingPane(
                    tabID: tab.tabId,
                    arrangementID: arrangement.id,
                    paneID: request.paneID
                )
            }
        }
        let defaultIDs = tab.arrangements.filter(\.isDefault).map(\.id)
        guard defaultIDs.count == 1 else {
            return .malformedDefault(tabID: tab.tabId, arrangementIDs: defaultIDs)
        }
        guard tab.allPaneIds.contains(request.paneID) else {
            return .tabDoesNotOwnPane(tabID: tab.tabId, paneID: request.paneID)
        }
        guard tab.allPaneIds.count > 1 else { return .wouldRemoveLastPane(tab.tabId) }
        return nil
    }

    private static func resolveActiveArrangement(
        _ witness: WorkspaceActiveArrangementSelection,
        tab: TabGraphState
    ) -> Result<UUID, WorkspaceClosePaneInRetainedTabRejection> {
        switch witness {
        case .missing:
            return .failure(.activeArrangementMissing(tab.tabId))
        case .selected(let arrangementID):
            guard tab.arrangements.contains(where: { $0.id == arrangementID }) else {
                return .failure(
                    .activeArrangementNotInTab(tabID: tab.tabId, arrangementID: arrangementID)
                )
            }
            return .success(arrangementID)
        }
    }

    private static func validateCursors(
        _ witnesses: [WorkspaceClosePaneCursorWitness],
        tab: TabGraphState
    ) -> WorkspaceClosePaneInRetainedTabRejection? {
        for index in tab.arrangements.indices {
            guard witnesses.indices.contains(index) else {
                return .cursorMissing(tab.arrangements[index].id)
            }
            let arrangement = tab.arrangements[index]
            let witness = witnesses[index]
            guard witness.arrangementID == arrangement.id else {
                return .cursorArrangementOutOfOrder(
                    expected: arrangement.id,
                    actual: witness.arrangementID
                )
            }
            guard cursorIsValid(witness.cursor, arrangement: arrangement) else {
                return .cursorInvalid(arrangementID: arrangement.id, cursor: witness.cursor)
            }
        }
        if witnesses.count > tab.arrangements.count {
            return .cursorExtra(witnesses[tab.arrangements.count].arrangementID)
        }
        return nil
    }

    private static func cursorIsValid(
        _ cursor: WorkspaceActivePaneCursorWitness,
        arrangement: PaneArrangementGraphState
    ) -> Bool {
        switch cursor {
        case .missing:
            return false
        case .present(.noSelection):
            return arrangement.layout.paneIds.allSatisfy(arrangement.minimizedPaneIds.contains)
        case .present(.selected(let paneID)):
            return arrangement.layout.contains(paneID)
                && !arrangement.minimizedPaneIds.contains(paneID)
        }
    }

    private static func activePaneMutation(
        _ cursor: WorkspaceActivePaneCursorWitness,
        paneID: UUID,
        replacement: PaneArrangementGraphState
    ) -> WorkspaceClosePaneActivePaneMutation {
        guard cursor == .present(.selected(paneID)) else {
            return .witness(arrangementID: replacement.id, expected: cursor)
        }
        let fallback = replacement.layout.paneIds.first {
            !replacement.minimizedPaneIds.contains($0)
        }
        return .replace(
            arrangementID: replacement.id,
            previous: cursor,
            replacement: fallback.map(WorkspacePaneSelection.selected) ?? .noSelection
        )
    }

    private static func activeArrangementMutation(
        previous: TabGraphState,
        replacement: TabGraphState,
        activeArrangementID: UUID
    ) -> WorkspaceClosePaneActiveArrangementMutation {
        let activeReplacement = replacement.arrangements.first { $0.id == activeArrangementID }!
        guard activeReplacement.layout.isEmpty else {
            return .witness(tabID: previous.tabId, expected: .selected(activeArrangementID))
        }
        let defaultArrangement = replacement.arrangements.first { $0.isDefault }!
        guard defaultArrangement.id != activeArrangementID, !defaultArrangement.layout.isEmpty else {
            return .witness(tabID: previous.tabId, expected: .selected(activeArrangementID))
        }
        return .replace(
            tabID: previous.tabId,
            previousArrangementID: activeArrangementID,
            replacementArrangementID: defaultArrangement.id
        )
    }

    private static func zoomMutation(
        _ witness: WorkspaceZoomSelection,
        tabID: UUID,
        paneID: UUID
    ) -> WorkspaceClosePaneZoomMutation {
        witness == .zoomed(paneID)
            ? .clear(tabID: tabID, previousPaneID: paneID)
            : .witness(tabID: tabID, expected: witness)
    }

    private static func duplicate(in ids: [UUID]) -> UUID? {
        var seen: Set<UUID> = []
        return ids.first { !seen.insert($0).inserted }
    }
}
