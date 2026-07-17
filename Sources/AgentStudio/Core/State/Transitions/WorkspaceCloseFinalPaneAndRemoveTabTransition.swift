import Foundation

struct WorkspaceCloseFinalPaneAndRemoveTabRequest: Equatable, Sendable {
    let paneID: UUID
    let tabID: UUID
}

struct WorkspaceFinalPaneDrawerCursorAbsenceWitness: Equatable, Sendable {
    let arrangementIDs: [UUID]
}

struct WorkspaceCloseFinalPaneAndRemoveTabPlanningContext: Equatable, Sendable {
    let pane: WorkspaceClosePaneWitness
    let ownership: WorkspaceClosePaneOwnershipWitness
    let tab: WorkspaceClosePaneTabWitness
    let tabIndex: Int?
    let tabShells: [TabShell]
    let activeTab: WorkspaceTabCursorSelection
    let activeArrangement: WorkspaceActiveArrangementSelection
    let paneCursors: [WorkspaceClosePaneCursorWitness]
    let arrangementDrawerCursorKeys: [ArrangementDrawerCursorKey]
    let drawerCursor: WorkspaceDrawerCursorSelection
    let zoom: WorkspaceZoomSelection
}

enum WorkspaceFinalPaneTabCursorMutation: Equatable, Sendable {
    case witness(WorkspaceTabCursorSelection)
    case replace(WorkspaceTabCursorReplacement)
}

enum WorkspaceFinalPaneZoomMutation: Equatable, Sendable {
    case witness(tabID: UUID, expected: WorkspaceZoomSelection)
    case clear(tabID: UUID, previousPaneID: UUID)
}

struct WorkspaceCloseFinalPaneAndRemoveTabTransition: Equatable, Sendable {
    let previousPane: PaneGraphState
    let removedTab: WorkspaceIndexedTabGraphState
    let removedShell: WorkspaceIndexedTabShell
    let shiftedShellSuffix: [WorkspaceIndexedTabShell]
    let tabCursor: WorkspaceFinalPaneTabCursorMutation
    let removedActiveArrangementID: UUID
    let removedActivePanes: [WorkspaceClosePaneCursorWitness]
    let absentDrawerCursors: WorkspaceFinalPaneDrawerCursorAbsenceWitness
    let drawerCursor: WorkspaceDrawerCursorSelection
    let zoom: WorkspaceFinalPaneZoomMutation

    fileprivate init(
        previousPane: PaneGraphState,
        removedTab: WorkspaceIndexedTabGraphState,
        removedShell: WorkspaceIndexedTabShell,
        shiftedShellSuffix: [WorkspaceIndexedTabShell],
        tabCursor: WorkspaceFinalPaneTabCursorMutation,
        removedActiveArrangementID: UUID,
        removedActivePanes: [WorkspaceClosePaneCursorWitness],
        absentDrawerCursors: WorkspaceFinalPaneDrawerCursorAbsenceWitness,
        drawerCursor: WorkspaceDrawerCursorSelection,
        zoom: WorkspaceFinalPaneZoomMutation
    ) {
        self.previousPane = previousPane
        self.removedTab = removedTab
        self.removedShell = removedShell
        self.shiftedShellSuffix = shiftedShellSuffix
        self.tabCursor = tabCursor
        self.removedActiveArrangementID = removedActiveArrangementID
        self.removedActivePanes = removedActivePanes
        self.absentDrawerCursors = absentDrawerCursors
        self.drawerCursor = drawerCursor
        self.zoom = zoom
    }
}

enum WorkspaceCloseFinalPaneAndRemoveTabDecision: Equatable, Sendable {
    case changed(WorkspaceCloseFinalPaneAndRemoveTabTransition)
    case rejected(WorkspaceCloseFinalPaneAndRemoveTabRejection)
}

enum WorkspaceCloseFinalPaneAndRemoveTabRejection: Error, Equatable, Sendable {
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
    case tabIndexMissing(UUID)
    case tabIdentityMismatch(expected: UUID, actual: UUID)
    case tabOwnsUnexpectedPanes(tabID: UUID, paneIDs: [UUID])
    case missingArrangement(UUID)
    case duplicateArrangementIdentity(tabID: UUID, arrangementID: UUID)
    case malformedDefault(tabID: UUID, arrangementIDs: [UUID])
    case arrangementDoesNotContainOnlyFinalPane(tabID: UUID, arrangementID: UUID, paneIDs: [UUID])
    case invalidMinimizedPane(tabID: UUID, arrangementID: UUID, paneID: UUID)
    case drawerViewPresent(arrangementID: UUID, drawerID: UUID)
    case activeArrangementMissing(UUID)
    case activeArrangementNotInTab(tabID: UUID, arrangementID: UUID)
    case cursorArrangementOutOfOrder(expected: UUID, actual: UUID)
    case cursorMissing(UUID)
    case cursorExtra(UUID)
    case cursorInvalid(arrangementID: UUID, cursor: WorkspaceActivePaneCursorWitness)
    case arrangementDrawerCursorPresent(ArrangementDrawerCursorKey)
    case duplicateTabShell(UUID)
    case tabShellMissing(UUID)
    case tabOwnerIndexMismatch(tabID: UUID, graphIndex: Int, shellIndex: Int)
    case invalidActiveTabSelection(UUID)
}

enum WorkspaceFinalPaneTabRemovalPlanner {
    static func plan(
        _ request: WorkspaceCloseFinalPaneAndRemoveTabRequest,
        context: WorkspaceCloseFinalPaneAndRemoveTabPlanningContext
    ) -> WorkspaceCloseFinalPaneAndRemoveTabDecision {
        let pane: PaneGraphState
        switch resolvePane(request, context.pane) {
        case .success(let value): pane = value
        case .failure(let rejection): return .rejected(rejection)
        }
        if let rejection = validatePane(pane, request: request, drawerCursor: context.drawerCursor) {
            return .rejected(rejection)
        }
        if let rejection = validateOwnership(request, context.ownership) { return .rejected(rejection) }
        let tab: TabGraphState
        switch resolveTab(request, context.tab) {
        case .success(let value): tab = value
        case .failure(let rejection): return .rejected(rejection)
        }
        guard let tabIndex = context.tabIndex else { return .rejected(.tabIndexMissing(request.tabID)) }
        if let rejection = validateTab(tab, request: request) { return .rejected(rejection) }
        let activeArrangementID: UUID
        switch resolveActiveArrangement(context.activeArrangement, tab: tab) {
        case .success(let value): activeArrangementID = value
        case .failure(let rejection): return .rejected(rejection)
        }
        if let rejection = validatePaneCursors(context.paneCursors, tab: tab) { return .rejected(rejection) }
        if let rejection = validateDrawerCursors(context.arrangementDrawerCursorKeys, tab: tab) {
            return .rejected(rejection)
        }
        let shellRemoval: WorkspaceFinalPaneShellRemoval
        switch resolveShellRemoval(tabID: request.tabID, graphIndex: tabIndex, shells: context.tabShells) {
        case .success(let value): shellRemoval = value
        case .failure(let rejection): return .rejected(rejection)
        }
        let remainingShells = context.tabShells.enumerated().compactMap { index, shell in
            index == shellRemoval.removed.index ? nil : shell
        }
        guard
            let replacementActiveTab = activeTabAfterRemoving(
                request.tabID,
                activeTab: context.activeTab,
                remainingShells: remainingShells
            )
        else {
            return .rejected(.invalidActiveTabSelection(request.tabID))
        }
        let tabCursor: WorkspaceFinalPaneTabCursorMutation =
            replacementActiveTab == context.activeTab
            ? .witness(context.activeTab)
            : .replace(.init(previous: context.activeTab, replacement: replacementActiveTab))
        return .changed(
            .init(
                previousPane: pane,
                removedTab: .init(index: tabIndex, state: tab),
                removedShell: shellRemoval.removed,
                shiftedShellSuffix: shellRemoval.shiftedSuffix,
                tabCursor: tabCursor,
                removedActiveArrangementID: activeArrangementID,
                removedActivePanes: context.paneCursors,
                absentDrawerCursors: .init(arrangementIDs: tab.arrangements.map(\.id)),
                drawerCursor: context.drawerCursor,
                zoom: context.zoom == .zoomed(request.paneID)
                    ? .clear(tabID: request.tabID, previousPaneID: request.paneID)
                    : .witness(tabID: request.tabID, expected: context.zoom)
            )
        )
    }
}

private struct WorkspaceFinalPaneShellRemoval {
    let removed: WorkspaceIndexedTabShell
    let shiftedSuffix: [WorkspaceIndexedTabShell]
}

extension WorkspaceFinalPaneTabRemovalPlanner {
    private static func resolvePane(
        _ request: WorkspaceCloseFinalPaneAndRemoveTabRequest,
        _ witness: WorkspaceClosePaneWitness
    ) -> Result<PaneGraphState, WorkspaceCloseFinalPaneAndRemoveTabRejection> {
        switch witness {
        case .missing: return .failure(.paneMissing(request.paneID))
        case .present(let pane) where pane.id != request.paneID:
            return .failure(.paneIdentityMismatch(expected: request.paneID, actual: pane.id))
        case .present(let pane): return .success(pane)
        }
    }

    private static func validatePane(
        _ pane: PaneGraphState,
        request: WorkspaceCloseFinalPaneAndRemoveTabRequest,
        drawerCursor: WorkspaceDrawerCursorSelection
    ) -> WorkspaceCloseFinalPaneAndRemoveTabRejection? {
        guard pane.residency.isActive else { return .paneNotActive(request.paneID) }
        switch pane.kind {
        case .drawerChild: return .paneIsDrawerChild(request.paneID)
        case .layout(let drawer) where drawer.parentPaneId != request.paneID:
            return .paneDrawerParentMismatch(paneID: request.paneID, actualParentPaneID: drawer.parentPaneId)
        case .layout(let drawer) where !drawer.paneIds.isEmpty:
            return .paneDrawerPopulated(request.paneID)
        case .layout(let drawer) where drawerCursor == .expanded(drawerID: drawer.drawerId):
            return .paneDrawerExpanded(drawerID: drawer.drawerId)
        case .layout: return nil
        }
    }

    private static func validateOwnership(
        _ request: WorkspaceCloseFinalPaneAndRemoveTabRequest,
        _ witness: WorkspaceClosePaneOwnershipWitness
    ) -> WorkspaceCloseFinalPaneAndRemoveTabRejection? {
        switch witness {
        case .absent: return .paneUnowned(request.paneID)
        case .owned(let tabID) where tabID != request.tabID:
            return .paneOwnedByWrongTab(paneID: request.paneID, expectedTabID: request.tabID, actualTabID: tabID)
        case .owned: return nil
        case .multiple(let tabIDs): return .paneMultiplyOwned(request.paneID, tabIDs)
        }
    }

    private static func resolveTab(
        _ request: WorkspaceCloseFinalPaneAndRemoveTabRequest,
        _ witness: WorkspaceClosePaneTabWitness
    ) -> Result<TabGraphState, WorkspaceCloseFinalPaneAndRemoveTabRejection> {
        switch witness {
        case .missing: return .failure(.tabMissing(request.tabID))
        case .present(let tab) where tab.tabId != request.tabID:
            return .failure(.tabIdentityMismatch(expected: request.tabID, actual: tab.tabId))
        case .present(let tab): return .success(tab)
        }
    }

    private static func validateTab(
        _ tab: TabGraphState,
        request: WorkspaceCloseFinalPaneAndRemoveTabRequest
    ) -> WorkspaceCloseFinalPaneAndRemoveTabRejection? {
        guard tab.allPaneIds == [request.paneID] else {
            return .tabOwnsUnexpectedPanes(tabID: tab.tabId, paneIDs: tab.allPaneIds)
        }
        guard !tab.arrangements.isEmpty else { return .missingArrangement(tab.tabId) }
        var arrangementIDs: Set<UUID> = []
        for arrangement in tab.arrangements {
            guard arrangementIDs.insert(arrangement.id).inserted else {
                return .duplicateArrangementIdentity(tabID: tab.tabId, arrangementID: arrangement.id)
            }
            guard arrangement.layout.paneIds == [request.paneID] else {
                return .arrangementDoesNotContainOnlyFinalPane(
                    tabID: tab.tabId,
                    arrangementID: arrangement.id,
                    paneIDs: arrangement.layout.paneIds
                )
            }
            for minimizedPaneID in arrangement.minimizedPaneIds where minimizedPaneID != request.paneID {
                return .invalidMinimizedPane(
                    tabID: tab.tabId,
                    arrangementID: arrangement.id,
                    paneID: minimizedPaneID
                )
            }
            if let drawerID = arrangement.drawerViews.keys.first {
                return .drawerViewPresent(arrangementID: arrangement.id, drawerID: drawerID)
            }
        }
        let defaultIDs = tab.arrangements.filter(\.isDefault).map(\.id)
        guard defaultIDs.count == 1 else {
            return .malformedDefault(tabID: tab.tabId, arrangementIDs: defaultIDs)
        }
        return nil
    }

    private static func resolveActiveArrangement(
        _ witness: WorkspaceActiveArrangementSelection,
        tab: TabGraphState
    ) -> Result<UUID, WorkspaceCloseFinalPaneAndRemoveTabRejection> {
        switch witness {
        case .missing: return .failure(.activeArrangementMissing(tab.tabId))
        case .selected(let arrangementID):
            guard tab.arrangements.contains(where: { $0.id == arrangementID }) else {
                return .failure(.activeArrangementNotInTab(tabID: tab.tabId, arrangementID: arrangementID))
            }
            return .success(arrangementID)
        }
    }

    private static func validatePaneCursors(
        _ witnesses: [WorkspaceClosePaneCursorWitness],
        tab: TabGraphState
    ) -> WorkspaceCloseFinalPaneAndRemoveTabRejection? {
        for index in tab.arrangements.indices {
            guard witnesses.indices.contains(index) else { return .cursorMissing(tab.arrangements[index].id) }
            let arrangement = tab.arrangements[index]
            let witness = witnesses[index]
            guard witness.arrangementID == arrangement.id else {
                return .cursorArrangementOutOfOrder(expected: arrangement.id, actual: witness.arrangementID)
            }
            let expected: WorkspaceActivePaneCursorWitness =
                arrangement.minimizedPaneIds.contains(tab.allPaneIds[0])
                ? .present(.noSelection)
                : .present(.selected(tab.allPaneIds[0]))
            guard witness.cursor == expected else {
                return .cursorInvalid(arrangementID: arrangement.id, cursor: witness.cursor)
            }
        }
        if witnesses.count > tab.arrangements.count {
            return .cursorExtra(witnesses[tab.arrangements.count].arrangementID)
        }
        return nil
    }

    private static func validateDrawerCursors(
        _ keys: [ArrangementDrawerCursorKey],
        tab: TabGraphState
    ) -> WorkspaceCloseFinalPaneAndRemoveTabRejection? {
        let removedArrangementIDs = Set(tab.arrangements.map(\.id))
        if let presentKey = keys.first(where: { removedArrangementIDs.contains($0.arrangementId) }) {
            return .arrangementDrawerCursorPresent(presentKey)
        }
        return nil
    }

    private static func resolveShellRemoval(
        tabID: UUID,
        graphIndex: Int,
        shells: [TabShell]
    ) -> Result<WorkspaceFinalPaneShellRemoval, WorkspaceCloseFinalPaneAndRemoveTabRejection> {
        var seen: Set<UUID> = []
        for shell in shells where !seen.insert(shell.id).inserted {
            return .failure(.duplicateTabShell(shell.id))
        }
        guard let shellIndex = shells.firstIndex(where: { $0.id == tabID }) else {
            return .failure(.tabShellMissing(tabID))
        }
        guard shellIndex == graphIndex else {
            return .failure(.tabOwnerIndexMismatch(tabID: tabID, graphIndex: graphIndex, shellIndex: shellIndex))
        }
        return .success(
            .init(
                removed: .init(index: shellIndex, shell: shells[shellIndex]),
                shiftedSuffix: shells.enumerated().dropFirst(shellIndex + 1).map {
                    .init(index: $0.offset, shell: $0.element)
                }
            )
        )
    }
}
