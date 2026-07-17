import Foundation

enum WorkspaceCrossTabPaneWitness: Equatable, Sendable {
    case missing
    case present(PaneGraphState)
}

enum WorkspaceCrossTabPaneOwnershipWitness: Equatable, Sendable {
    case absent
    case owned(tabID: UUID)
    case multiple([UUID])
}

enum WorkspaceCrossTabTabWitness: Equatable, Sendable {
    case missing
    case present(TabGraphState)
}

struct WorkspaceCrossTabPaneCursorWitness: Equatable, Sendable {
    let arrangementID: UUID
    let cursor: WorkspaceActivePaneCursorWitness
}

struct WorkspaceCrossTabPaneMovePlanningContext: Equatable, Sendable {
    let pane: WorkspaceCrossTabPaneWitness
    let ownership: WorkspaceCrossTabPaneOwnershipWitness
    let sourceTab: WorkspaceCrossTabTabWitness
    let destinationTab: WorkspaceCrossTabTabWitness
    let sourceActiveArrangement: WorkspaceActiveArrangementSelection
    let destinationActiveArrangement: WorkspaceActiveArrangementSelection
    let sourcePaneCursors: [WorkspaceCrossTabPaneCursorWitness]
    let destinationPaneCursors: [WorkspaceCrossTabPaneCursorWitness]
    let activeTab: WorkspaceTabCursorSelection
    let sourceZoom: WorkspaceZoomSelection
    let destinationZoom: WorkspaceZoomSelection
}

enum WorkspaceCrossTabActiveArrangementMutation: Equatable, Sendable {
    case witness(tabID: UUID, expected: WorkspaceActiveArrangementSelection)
    case replace(tabID: UUID, previousArrangementID: UUID, replacementArrangementID: UUID)
}

enum WorkspaceCrossTabActivePaneMutation: Equatable, Sendable {
    case witness(arrangementID: UUID, expected: WorkspaceActivePaneCursorWitness)
    case replace(
        arrangementID: UUID,
        previous: WorkspaceActivePaneCursorWitness,
        replacement: WorkspacePaneSelection
    )
}

enum WorkspaceCrossTabActiveTabMutation: Equatable, Sendable {
    case witness(WorkspaceTabCursorSelection)
    case replace(previous: WorkspaceTabCursorSelection, replacementTabID: UUID)
}

enum WorkspaceCrossTabZoomMutation: Equatable, Sendable {
    case witness(tabID: UUID, expected: WorkspaceZoomSelection)
    case clear(tabID: UUID, previousPaneID: UUID)
}

struct WorkspaceCrossTabPaneMoveTransition: Equatable, Sendable {
    let pane: WorkspaceCrossTabPaneWitness
    let previousSourceTab: TabGraphState
    let replacementSourceTab: TabGraphState
    let previousDestinationTab: TabGraphState
    let replacementDestinationTab: TabGraphState
    let sourceActiveArrangement: WorkspaceCrossTabActiveArrangementMutation
    let destinationActiveArrangement: WorkspaceCrossTabActiveArrangementMutation
    let sourceActivePanes: [WorkspaceCrossTabActivePaneMutation]
    let destinationActivePanes: [WorkspaceCrossTabActivePaneMutation]
    let activeTab: WorkspaceCrossTabActiveTabMutation
    let sourceZoom: WorkspaceCrossTabZoomMutation
    let destinationZoom: WorkspaceCrossTabZoomMutation

    fileprivate init(
        pane: WorkspaceCrossTabPaneWitness,
        previousSourceTab: TabGraphState,
        replacementSourceTab: TabGraphState,
        previousDestinationTab: TabGraphState,
        replacementDestinationTab: TabGraphState,
        sourceActiveArrangement: WorkspaceCrossTabActiveArrangementMutation,
        destinationActiveArrangement: WorkspaceCrossTabActiveArrangementMutation,
        sourceActivePanes: [WorkspaceCrossTabActivePaneMutation],
        destinationActivePanes: [WorkspaceCrossTabActivePaneMutation],
        activeTab: WorkspaceCrossTabActiveTabMutation,
        sourceZoom: WorkspaceCrossTabZoomMutation,
        destinationZoom: WorkspaceCrossTabZoomMutation
    ) {
        self.pane = pane
        self.previousSourceTab = previousSourceTab
        self.replacementSourceTab = replacementSourceTab
        self.previousDestinationTab = previousDestinationTab
        self.replacementDestinationTab = replacementDestinationTab
        self.sourceActiveArrangement = sourceActiveArrangement
        self.destinationActiveArrangement = destinationActiveArrangement
        self.sourceActivePanes = sourceActivePanes
        self.destinationActivePanes = destinationActivePanes
        self.activeTab = activeTab
        self.sourceZoom = sourceZoom
        self.destinationZoom = destinationZoom
    }
}

enum WorkspaceCrossTabPaneMoveTransitionDecision: Equatable, Sendable {
    case changed(WorkspaceCrossTabPaneMoveTransition)
    case rejected(WorkspaceCrossTabPaneMoveRejection)
}

enum WorkspaceCrossTabPaneMoveRejection: Error, Equatable, Sendable {
    case sameTab(UUID)
    case paneMissing(UUID)
    case paneIdentityMismatch(expected: UUID, actual: UUID)
    case paneUnowned(UUID)
    case paneOwnedByWrongTab(paneID: UUID, expectedTabID: UUID, actualTabID: UUID)
    case paneMultiplyOwned(UUID, [UUID])
    case paneNotActive(UUID)
    case paneIsDrawerChild(UUID)
    case paneDrawerParentMismatch(paneID: UUID, actualParentPaneID: UUID)
    case paneDrawerPopulated(UUID)
    case sourceTabMissing(UUID)
    case destinationTabMissing(UUID)
    case tabIdentityMismatch(expected: UUID, actual: UUID)
    case duplicatePaneIdentity(tabID: UUID, paneID: UUID)
    case duplicateArrangementIdentity(tabID: UUID, arrangementID: UUID)
    case duplicateArrangementPane(tabID: UUID, arrangementID: UUID, paneID: UUID)
    case malformedDefault(tabID: UUID, arrangementIDs: [UUID])
    case sourceDoesNotOwnPane(tabID: UUID, paneID: UUID)
    case sourceArrangementMissingPane(tabID: UUID, arrangementID: UUID, paneID: UUID)
    case destinationAlreadyContainsPane(UUID)
    case wouldEmptySourceTab(UUID)
    case activeArrangementMissing(UUID)
    case activeArrangementNotInTab(tabID: UUID, arrangementID: UUID)
    case cursorArrangementOutOfOrder(expected: UUID, actual: UUID)
    case cursorMissing(UUID)
    case cursorExtra(UUID)
    case cursorInvalid(arrangementID: UUID, cursor: WorkspaceActivePaneCursorWitness)
    case destinationArrangementEmpty(UUID)
    case destinationTargetMissing(tabID: UUID, paneID: UUID)
    case sourceRemovalFailed(tabID: UUID, arrangementID: UUID, paneID: UUID)
    case destinationInsertionFailed(tabID: UUID, arrangementID: UUID, targetPaneID: UUID)
}

enum WorkspaceCrossTabPaneMoveTransitionPlanner {
    static func plan(
        _ request: CrossTabPaneMoveRequest,
        context: WorkspaceCrossTabPaneMovePlanningContext
    ) -> WorkspaceCrossTabPaneMoveTransitionDecision {
        let validated: WorkspaceValidatedCrossTabPaneMove
        switch validateMove(request, context: context) {
        case .success(let value): validated = value
        case .failure(let rejection): return .rejected(rejection)
        }
        let sourceProjection: WorkspaceCrossTabSourceProjection
        switch projectSource(validated, request: request, cursors: context.sourcePaneCursors) {
        case .success(let value): sourceProjection = value
        case .failure(let rejection): return .rejected(rejection)
        }
        let destinationProjection: WorkspaceCrossTabDestinationProjection
        switch projectDestination(validated, request: request, cursors: context.destinationPaneCursors) {
        case .success(let value): destinationProjection = value
        case .failure(let rejection): return .rejected(rejection)
        }
        return .changed(
            .init(
                pane: context.pane,
                previousSourceTab: validated.source,
                replacementSourceTab: sourceProjection.tab,
                previousDestinationTab: validated.destination,
                replacementDestinationTab: destinationProjection.tab,
                sourceActiveArrangement: sourceProjection.activeArrangement,
                destinationActiveArrangement: .witness(
                    tabID: validated.destination.tabId,
                    expected: context.destinationActiveArrangement
                ),
                sourceActivePanes: sourceProjection.activePanes,
                destinationActivePanes: destinationProjection.activePanes,
                activeTab: activeTabMutation(context.activeTab, destinationTabID: validated.destination.tabId),
                sourceZoom: sourceZoomMutation(
                    context.sourceZoom,
                    tabID: validated.source.tabId,
                    paneID: request.paneId
                ),
                destinationZoom: destinationZoomMutation(
                    context.destinationZoom,
                    tabID: validated.destination.tabId
                )
            )
        )
    }
}

private struct WorkspaceValidatedCrossTabPaneMove {
    let source: TabGraphState
    let destination: TabGraphState
    let sourceActiveArrangementID: UUID
    let destinationActiveArrangementID: UUID
}

private struct WorkspaceCrossTabSourceProjection {
    let tab: TabGraphState
    let activeArrangement: WorkspaceCrossTabActiveArrangementMutation
    let activePanes: [WorkspaceCrossTabActivePaneMutation]
}

private struct WorkspaceCrossTabDestinationProjection {
    let tab: TabGraphState
    let activePanes: [WorkspaceCrossTabActivePaneMutation]
}

extension WorkspaceCrossTabPaneMoveTransitionPlanner {
    private static func validateMove(
        _ request: CrossTabPaneMoveRequest,
        context: WorkspaceCrossTabPaneMovePlanningContext
    ) -> Result<WorkspaceValidatedCrossTabPaneMove, WorkspaceCrossTabPaneMoveRejection> {
        guard request.sourceTabId != request.destTabId else { return .failure(.sameTab(request.sourceTabId)) }
        let pane: PaneGraphState
        switch resolvePane(request, witness: context.pane) {
        case .success(let value): pane = value
        case .failure(let rejection): return .failure(rejection)
        }
        if let rejection = validatePane(pane, request: request) { return .failure(rejection) }
        if let rejection = validateOwnership(request, witness: context.ownership) { return .failure(rejection) }
        let source: TabGraphState
        switch resolveTab(request.sourceTabId, witness: context.sourceTab, isSource: true) {
        case .success(let value): source = value
        case .failure(let rejection): return .failure(rejection)
        }
        let destination: TabGraphState
        switch resolveTab(request.destTabId, witness: context.destinationTab, isSource: false) {
        case .success(let value): destination = value
        case .failure(let rejection): return .failure(rejection)
        }
        if let rejection = validateSource(source, paneID: request.paneId) { return .failure(rejection) }
        if let rejection = validateDestination(destination, paneID: request.paneId) { return .failure(rejection) }
        let sourceActiveID: UUID
        switch resolveActiveArrangement(context.sourceActiveArrangement, tab: source) {
        case .success(let value): sourceActiveID = value
        case .failure(let rejection): return .failure(rejection)
        }
        let destinationActiveID: UUID
        switch resolveActiveArrangement(context.destinationActiveArrangement, tab: destination) {
        case .success(let value): destinationActiveID = value
        case .failure(let rejection): return .failure(rejection)
        }
        guard
            let destinationActive = destination.arrangements.first(where: { $0.id == destinationActiveID }),
            destinationActive.layout.contains(request.targetPaneId)
        else {
            return .failure(.destinationTargetMissing(tabID: destination.tabId, paneID: request.targetPaneId))
        }
        if let rejection = validateCursors(context.sourcePaneCursors, tab: source) { return .failure(rejection) }
        if let rejection = validateCursors(context.destinationPaneCursors, tab: destination) {
            return .failure(rejection)
        }
        return .success(
            .init(
                source: source,
                destination: destination,
                sourceActiveArrangementID: sourceActiveID,
                destinationActiveArrangementID: destinationActiveID
            )
        )
    }

    private static func validatePane(
        _ pane: PaneGraphState,
        request: CrossTabPaneMoveRequest
    ) -> WorkspaceCrossTabPaneMoveRejection? {
        guard pane.residency.isActive else { return .paneNotActive(request.paneId) }
        switch pane.kind {
        case .drawerChild: return .paneIsDrawerChild(request.paneId)
        case .layout(let drawer) where drawer.parentPaneId != request.paneId:
            return .paneDrawerParentMismatch(paneID: request.paneId, actualParentPaneID: drawer.parentPaneId)
        case .layout(let drawer) where !drawer.paneIds.isEmpty:
            return .paneDrawerPopulated(request.paneId)
        case .layout: return nil
        }
    }

    private static func validateSource(
        _ source: TabGraphState,
        paneID: UUID
    ) -> WorkspaceCrossTabPaneMoveRejection? {
        if let rejection = validateTab(source) { return rejection }
        guard source.allPaneIds.contains(paneID) else {
            return .sourceDoesNotOwnPane(tabID: source.tabId, paneID: paneID)
        }
        let remainingPaneIDs = source.allPaneIds.filter { $0 != paneID }
        guard !remainingPaneIDs.isEmpty else { return .wouldEmptySourceTab(source.tabId) }
        for arrangement in source.arrangements where !arrangement.layout.contains(paneID) {
            return .sourceArrangementMissingPane(
                tabID: source.tabId,
                arrangementID: arrangement.id,
                paneID: paneID
            )
        }
        return nil
    }

    private static func validateDestination(
        _ destination: TabGraphState,
        paneID: UUID
    ) -> WorkspaceCrossTabPaneMoveRejection? {
        if let rejection = validateTab(destination) { return rejection }
        guard !destination.allPaneIds.contains(paneID) else { return .destinationAlreadyContainsPane(paneID) }
        for arrangement in destination.arrangements {
            guard !arrangement.layout.isEmpty else { return .destinationArrangementEmpty(arrangement.id) }
            guard !arrangement.layout.contains(paneID) else { return .destinationAlreadyContainsPane(paneID) }
        }
        return nil
    }

    private static func projectSource(
        _ validated: WorkspaceValidatedCrossTabPaneMove,
        request: CrossTabPaneMoveRequest,
        cursors: [WorkspaceCrossTabPaneCursorWitness]
    ) -> Result<WorkspaceCrossTabSourceProjection, WorkspaceCrossTabPaneMoveRejection> {
        var replacement = validated.source
        replacement.allPaneIds.removeAll { $0 == request.paneId }
        guard !replacement.allPaneIds.isEmpty else { return .failure(.wouldEmptySourceTab(replacement.tabId)) }
        var mutations: [WorkspaceCrossTabActivePaneMutation] = []
        for index in replacement.arrangements.indices {
            let previous = validated.source.arrangements[index]
            let layout: Layout
            if previous.layout.panes.count == 1 {
                layout = Layout()
            } else if let removed = previous.layout.removing(paneId: request.paneId, sizingMode: .proportional) {
                layout = removed
            } else {
                return .failure(
                    .sourceRemovalFailed(
                        tabID: validated.source.tabId,
                        arrangementID: previous.id,
                        paneID: request.paneId
                    )
                )
            }
            replacement.arrangements[index].layout = layout
            replacement.arrangements[index].minimizedPaneIds.remove(request.paneId)
            mutations.append(
                sourceCursorMutation(
                    cursors[index].cursor,
                    paneID: request.paneId,
                    replacement: replacement.arrangements[index]
                )
            )
        }
        return .success(
            .init(
                tab: replacement,
                activeArrangement: sourceArrangementMutation(
                    tab: validated.source,
                    replacement: replacement,
                    activeArrangementID: validated.sourceActiveArrangementID
                ),
                activePanes: mutations
            )
        )
    }

    private static func projectDestination(
        _ validated: WorkspaceValidatedCrossTabPaneMove,
        request: CrossTabPaneMoveRequest,
        cursors: [WorkspaceCrossTabPaneCursorWitness]
    ) -> Result<WorkspaceCrossTabDestinationProjection, WorkspaceCrossTabPaneMoveRejection> {
        var replacement = validated.destination
        replacement.allPaneIds.append(request.paneId)
        var mutations: [WorkspaceCrossTabActivePaneMutation] = []
        for index in replacement.arrangements.indices {
            let previous = validated.destination.arrangements[index]
            let isActive = previous.id == validated.destinationActiveArrangementID
            let targetID = isActive ? request.targetPaneId : previous.layout.paneIds.last!
            guard
                let inserted = previous.layout.inserting(
                    paneId: request.paneId,
                    at: targetID,
                    direction: isActive ? request.direction : .horizontal,
                    position: isActive ? request.position : .after,
                    sizingMode: isActive ? .halveTarget : .proportional
                )
            else {
                return .failure(
                    .destinationInsertionFailed(
                        tabID: validated.destination.tabId,
                        arrangementID: previous.id,
                        targetPaneID: targetID
                    )
                )
            }
            replacement.arrangements[index].layout = inserted
            replacement.arrangements[index].minimizedPaneIds.remove(request.paneId)
            let cursor = cursors[index].cursor
            mutations.append(
                isActive
                    ? .replace(
                        arrangementID: previous.id,
                        previous: cursor,
                        replacement: .selected(request.paneId)
                    )
                    : .witness(arrangementID: previous.id, expected: cursor)
            )
        }
        return .success(.init(tab: replacement, activePanes: mutations))
    }

    private static func resolvePane(
        _ request: CrossTabPaneMoveRequest,
        witness: WorkspaceCrossTabPaneWitness
    ) -> Result<PaneGraphState, WorkspaceCrossTabPaneMoveRejection> {
        switch witness {
        case .missing: return .failure(.paneMissing(request.paneId))
        case .present(let pane) where pane.id != request.paneId:
            return .failure(.paneIdentityMismatch(expected: request.paneId, actual: pane.id))
        case .present(let pane): return .success(pane)
        }
    }

    private static func validateOwnership(
        _ request: CrossTabPaneMoveRequest,
        witness: WorkspaceCrossTabPaneOwnershipWitness
    ) -> WorkspaceCrossTabPaneMoveRejection? {
        switch witness {
        case .absent: return .paneUnowned(request.paneId)
        case .owned(let tabID) where tabID != request.sourceTabId:
            return .paneOwnedByWrongTab(
                paneID: request.paneId,
                expectedTabID: request.sourceTabId,
                actualTabID: tabID
            )
        case .owned: return nil
        case .multiple(let tabIDs): return .paneMultiplyOwned(request.paneId, tabIDs)
        }
    }

    private static func resolveTab(
        _ requestedID: UUID,
        witness: WorkspaceCrossTabTabWitness,
        isSource: Bool
    ) -> Result<TabGraphState, WorkspaceCrossTabPaneMoveRejection> {
        switch witness {
        case .missing:
            return .failure(isSource ? .sourceTabMissing(requestedID) : .destinationTabMissing(requestedID))
        case .present(let tab) where tab.tabId != requestedID:
            return .failure(.tabIdentityMismatch(expected: requestedID, actual: tab.tabId))
        case .present(let tab): return .success(tab)
        }
    }

    private static func validateTab(_ tab: TabGraphState) -> WorkspaceCrossTabPaneMoveRejection? {
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
    ) -> Result<UUID, WorkspaceCrossTabPaneMoveRejection> {
        switch witness {
        case .missing: return .failure(.activeArrangementMissing(tab.tabId))
        case .selected(let arrangementID):
            guard tab.arrangements.contains(where: { $0.id == arrangementID }) else {
                return .failure(.activeArrangementNotInTab(tabID: tab.tabId, arrangementID: arrangementID))
            }
            return .success(arrangementID)
        }
    }

    private static func validateCursors(
        _ witnesses: [WorkspaceCrossTabPaneCursorWitness],
        tab: TabGraphState
    ) -> WorkspaceCrossTabPaneMoveRejection? {
        for index in tab.arrangements.indices {
            guard witnesses.indices.contains(index) else { return .cursorMissing(tab.arrangements[index].id) }
            let arrangement = tab.arrangements[index]
            let witness = witnesses[index]
            guard witness.arrangementID == arrangement.id else {
                return .cursorArrangementOutOfOrder(expected: arrangement.id, actual: witness.arrangementID)
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
        case .missing: return false
        case .present(.noSelection):
            return arrangement.layout.paneIds.allSatisfy(arrangement.minimizedPaneIds.contains)
        case .present(.selected(let paneID)):
            return arrangement.layout.contains(paneID) && !arrangement.minimizedPaneIds.contains(paneID)
        }
    }

    private static func sourceCursorMutation(
        _ cursor: WorkspaceActivePaneCursorWitness,
        paneID: UUID,
        replacement: PaneArrangementGraphState
    ) -> WorkspaceCrossTabActivePaneMutation {
        guard cursor == .present(.selected(paneID)) else {
            return .witness(arrangementID: replacement.id, expected: cursor)
        }
        let fallback = replacement.layout.paneIds.first { !replacement.minimizedPaneIds.contains($0) }
        return .replace(
            arrangementID: replacement.id,
            previous: cursor,
            replacement: fallback.map(WorkspacePaneSelection.selected) ?? .noSelection
        )
    }

    private static func sourceArrangementMutation(
        tab: TabGraphState,
        replacement: TabGraphState,
        activeArrangementID: UUID
    ) -> WorkspaceCrossTabActiveArrangementMutation {
        let activeReplacement = replacement.arrangements.first { $0.id == activeArrangementID }!
        guard activeReplacement.layout.isEmpty else {
            return .witness(tabID: tab.tabId, expected: .selected(activeArrangementID))
        }
        let defaultArrangement = replacement.arrangements.first { $0.isDefault }!
        guard defaultArrangement.id != activeArrangementID, !defaultArrangement.layout.isEmpty else {
            return .witness(tabID: tab.tabId, expected: .selected(activeArrangementID))
        }
        return .replace(
            tabID: tab.tabId,
            previousArrangementID: activeArrangementID,
            replacementArrangementID: defaultArrangement.id
        )
    }

    private static func activeTabMutation(
        _ witness: WorkspaceTabCursorSelection,
        destinationTabID: UUID
    ) -> WorkspaceCrossTabActiveTabMutation {
        witness == .selected(destinationTabID)
            ? .witness(witness)
            : .replace(previous: witness, replacementTabID: destinationTabID)
    }

    private static func sourceZoomMutation(
        _ witness: WorkspaceZoomSelection,
        tabID: UUID,
        paneID: UUID
    ) -> WorkspaceCrossTabZoomMutation {
        witness == .zoomed(paneID)
            ? .clear(tabID: tabID, previousPaneID: paneID)
            : .witness(tabID: tabID, expected: witness)
    }

    private static func destinationZoomMutation(
        _ witness: WorkspaceZoomSelection,
        tabID: UUID
    ) -> WorkspaceCrossTabZoomMutation {
        switch witness {
        case .notZoomed: return .witness(tabID: tabID, expected: witness)
        case .zoomed(let paneID): return .clear(tabID: tabID, previousPaneID: paneID)
        }
    }

    private static func duplicate(in values: [UUID]) -> UUID? {
        var seen: Set<UUID> = []
        return values.first { !seen.insert($0).inserted }
    }
}
