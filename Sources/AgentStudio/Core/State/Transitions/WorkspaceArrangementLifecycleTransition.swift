import Foundation

enum WorkspaceNewArrangementIDRejection: Equatable, Sendable {
    case nonUUIDv7(UUID)
}

enum WorkspaceNewArrangementIDPreparation: Equatable, Sendable {
    case validated(WorkspaceNewArrangementID)
    case rejected(WorkspaceNewArrangementIDRejection)
}

struct WorkspaceNewArrangementID: Equatable, Sendable {
    let rawValue: UUID

    private init(validatedUUIDv7: UUID) {
        rawValue = validatedUUIDv7
    }

    static func prepare(_ candidate: UUID) -> WorkspaceNewArrangementIDPreparation {
        guard UUIDv7.isV7(candidate) else { return .rejected(.nonUUIDv7(candidate)) }
        return .validated(Self(validatedUUIDv7: candidate))
    }

    static func generate() -> Self {
        let generated = UUIDv7.generate()
        precondition(UUIDv7.isV7(generated), "UUIDv7 generator must return a version-7 identity")
        return Self(validatedUUIDv7: generated)
    }
}

struct WorkspaceCreateArrangementRequest: Equatable, Sendable {
    let tabID: UUID
    let arrangementID: WorkspaceNewArrangementID
    let name: String
}

struct WorkspaceRemoveArrangementRequest: Equatable, Sendable {
    let tabID: UUID
    let arrangementID: UUID
}

enum WorkspaceArrangementIdentityOwnerWitness: Equatable, Sendable {
    case unowned
    case ownedByTab(UUID)
}

enum WorkspaceDefaultArrangementWitness: Equatable, Sendable {
    case missing
    case selected(UUID)
    case multiple([UUID])
}

struct WorkspaceArrangementDrawerCursorWitness: Equatable, Sendable {
    let drawerID: UUID
    let cursor: WorkspaceActiveDrawerChildCursorWitness
}

struct WorkspaceArrangementProposedCursorWitness: Equatable, Sendable {
    let paneCursor: WorkspaceActivePaneCursorWitness
    let drawerCursors: [WorkspaceArrangementDrawerCursorWitness]
}

struct WorkspaceCreateArrangementSelectedContext: Equatable, Sendable {
    let tab: TabGraphState
    let arrangementID: UUID
    let activePaneCursor: WorkspaceActivePaneCursorWitness
    let activeDrawerCursors: [WorkspaceArrangementDrawerCursorWitness]
    let proposedOwner: WorkspaceArrangementIdentityOwnerWitness
    let proposedCursors: WorkspaceArrangementProposedCursorWitness
}

struct WorkspaceRemoveArrangementSelectedContext: Equatable, Sendable {
    let tab: TabGraphState
    let arrangementID: UUID
    let targetPaneCursor: WorkspaceActivePaneCursorWitness
    let targetDrawerCursors: [WorkspaceArrangementDrawerCursorWitness]
    let defaultArrangement: WorkspaceDefaultArrangementWitness
}

enum WorkspaceCreateArrangementPlanningContext: Equatable, Sendable {
    case missingTab
    case missingActiveArrangement(tab: TabGraphState)
    case selectedActiveArrangement(WorkspaceCreateArrangementSelectedContext)
}

enum WorkspaceRemoveArrangementPlanningContext: Equatable, Sendable {
    case missingTab
    case missingActiveArrangement(tab: TabGraphState)
    case selectedActiveArrangement(WorkspaceRemoveArrangementSelectedContext)
}

enum WorkspaceArrangementLifecycleRejection: Error, Equatable, Sendable {
    case defaultArrangementCannotBeRemoved(tabID: UUID, arrangementID: UUID)
    case duplicateArrangementIdentity(arrangementID: UUID, ownerTabID: UUID)
    case duplicateDrawerCursor(ArrangementDrawerCursorKey)
    case duplicateDrawerWitness(ArrangementDrawerCursorKey)
    case duplicatePaneCursor(UUID)
    case drawerWitnessSetMismatch(arrangementID: UUID, expected: Set<UUID>, actual: Set<UUID>)
    case emptyArrangementName
    case incompleteActiveArrangement(tabID: UUID, arrangementID: UUID)
    case inconsistentActiveDrawerCursor(ArrangementDrawerCursorKey)
    case inconsistentActivePaneCursor(UUID)
    case inconsistentDefaultArrangement(tabID: UUID, witness: WorkspaceDefaultArrangementWitness)
    case missingActiveArrangement(UUID)
    case missingArrangement(tabID: UUID, arrangementID: UUID)
    case missingDrawerCursor(ArrangementDrawerCursorKey)
    case missingPaneCursor(UUID)
    case missingTab(UUID)
    case tabIdentityMismatch(requested: UUID, actual: UUID)
}

struct WorkspaceArrangementPaneCursorInsertion: Equatable, Sendable {
    let arrangementID: UUID
    let state: ArrangementPaneCursorState
}

struct WorkspaceArrangementDrawerCursorInsertion: Equatable, Sendable {
    let key: ArrangementDrawerCursorKey
    let state: ArrangementDrawerCursorState
}

struct WorkspaceCreateArrangementTransition: Equatable, Sendable {
    let previousTab: TabGraphState
    let replacementTab: TabGraphState
    let expectedActiveArrangement: WorkspaceActiveArrangementSelection
    let expectedSourcePaneCursor: WorkspaceActivePaneCursorWitness
    let expectedSourceDrawerCursors: [WorkspaceArrangementDrawerCursorWitness]
    let paneCursorInsertion: WorkspaceArrangementPaneCursorInsertion
    let drawerCursorInsertions: [WorkspaceArrangementDrawerCursorInsertion]
}

struct WorkspaceRemoveArrangementTransition: Equatable, Sendable {
    let previousTab: TabGraphState
    let replacementTab: TabGraphState
    let expectedActiveArrangement: WorkspaceActiveArrangementSelection
    let replacementActiveArrangementID: UUID?
    let removedArrangementID: UUID
    let expectedPaneCursor: WorkspaceActivePaneCursorWitness
    let expectedDrawerCursors: [WorkspaceArrangementDrawerCursorWitness]
}

enum WorkspaceArrangementLifecycleTransition: Equatable, Sendable {
    case create(WorkspaceCreateArrangementTransition)
    case remove(WorkspaceRemoveArrangementTransition)
}

enum WorkspaceArrangementLifecycleDecision: Equatable, Sendable {
    case changed(WorkspaceArrangementLifecycleTransition)
    case unchanged
    case rejected(WorkspaceArrangementLifecycleRejection)
}

enum WorkspaceArrangementLifecycleTransitionPlanner {
    static func planCreate(
        _ request: WorkspaceCreateArrangementRequest,
        context: WorkspaceCreateArrangementPlanningContext
    ) -> WorkspaceArrangementLifecycleDecision {
        let source: WorkspaceArrangementLifecycleSource
        switch resolveCreateSource(request: request, context: context) {
        case .resolved(let value): source = value
        case .rejected(let rejection): return .rejected(rejection)
        }
        let normalizedName = Tab.normalizedName(request.name)
        guard !normalizedName.isEmpty else { return .rejected(.emptyArrangementName) }
        guard case .unowned = source.proposedOwner else {
            guard case .ownedByTab(let ownerTabID) = source.proposedOwner else {
                preconditionFailure("arrangement owner witness must be exhaustive")
            }
            return .rejected(
                .duplicateArrangementIdentity(
                    arrangementID: request.arrangementID.rawValue,
                    ownerTabID: ownerTabID
                )
            )
        }
        guard case .missing = source.proposedCursors.paneCursor else {
            return .rejected(.duplicatePaneCursor(request.arrangementID.rawValue))
        }
        if let rejection = validateProposedDrawerWitnesses(
            source.proposedCursors.drawerCursors,
            sourceArrangement: source.arrangement,
            newArrangementID: request.arrangementID.rawValue
        ) {
            return .rejected(rejection)
        }
        for proposedDrawer in source.proposedCursors.drawerCursors {
            guard case .missing = proposedDrawer.cursor else {
                return .rejected(
                    .duplicateDrawerCursor(
                        .init(
                            arrangementId: request.arrangementID.rawValue,
                            drawerId: proposedDrawer.drawerID
                        )
                    )
                )
            }
        }
        guard validatesCompleteView(tab: source.tab, arrangement: source.arrangement) else {
            return .rejected(
                .incompleteActiveArrangement(
                    tabID: request.tabID,
                    arrangementID: source.arrangement.id
                )
            )
        }
        guard validDefaultArrangementID(in: source.tab, witness: defaultArrangementWitness(source.tab)) != nil else {
            return .rejected(
                .inconsistentDefaultArrangement(
                    tabID: request.tabID,
                    witness: defaultArrangementWitness(source.tab)
                )
            )
        }
        guard case .present = source.activePaneCursor else {
            return .rejected(.missingPaneCursor(source.arrangement.id))
        }
        guard
            let activePaneState = paneCursorState(
                source.activePaneCursor,
                arrangement: source.arrangement
            )
        else {
            return .rejected(.inconsistentActivePaneCursor(source.arrangement.id))
        }
        let drawerInsertions: [WorkspaceArrangementDrawerCursorInsertion]
        switch drawerCursorInsertions(
            source.activeDrawerCursors,
            arrangement: source.arrangement,
            newArrangementID: request.arrangementID.rawValue
        ) {
        case .success(let values): drawerInsertions = values
        case .failure(let rejection): return .rejected(rejection)
        }

        let replacement = appendingArrangement(
            to: source.tab,
            copying: source.arrangement,
            arrangementID: request.arrangementID.rawValue,
            name: normalizedName
        )
        return .changed(
            .create(
                .init(
                    previousTab: source.tab,
                    replacementTab: replacement,
                    expectedActiveArrangement: .selected(source.arrangement.id),
                    expectedSourcePaneCursor: source.activePaneCursor,
                    expectedSourceDrawerCursors: source.activeDrawerCursors,
                    paneCursorInsertion: .init(
                        arrangementID: request.arrangementID.rawValue,
                        state: activePaneState
                    ),
                    drawerCursorInsertions: drawerInsertions
                )
            )
        )
    }

    static func planRemove(
        _ request: WorkspaceRemoveArrangementRequest,
        context: WorkspaceRemoveArrangementPlanningContext
    ) -> WorkspaceArrangementLifecycleDecision {
        let source: WorkspaceArrangementRemovalSource
        switch resolveRemovalSource(request: request, context: context) {
        case .resolved(let value): source = value
        case .rejected(let rejection): return .rejected(rejection)
        }
        guard !source.target.isDefault else {
            return .rejected(
                .defaultArrangementCannotBeRemoved(
                    tabID: request.tabID,
                    arrangementID: request.arrangementID
                )
            )
        }
        guard
            let defaultArrangementID = validDefaultArrangementID(
                in: source.tab,
                witness: source.defaultArrangement
            )
        else {
            return .rejected(
                .inconsistentDefaultArrangement(
                    tabID: request.tabID,
                    witness: source.defaultArrangement
                )
            )
        }
        switch source.targetPaneCursor {
        case .missing:
            return .rejected(.missingPaneCursor(request.arrangementID))
        case .present:
            guard paneCursorState(source.targetPaneCursor, arrangement: source.target) != nil else {
                return .rejected(.inconsistentActivePaneCursor(request.arrangementID))
            }
        }
        if let rejection = validateDrawerCursors(source.targetDrawerCursors, arrangement: source.target) {
            return .rejected(rejection)
        }
        var replacement = source.tab
        replacement.arrangements.removeAll { $0.id == request.arrangementID }
        let replacementActiveArrangementID =
            source.activeArrangementID == request.arrangementID ? defaultArrangementID : nil
        return .changed(
            .remove(
                .init(
                    previousTab: source.tab,
                    replacementTab: replacement,
                    expectedActiveArrangement: .selected(source.activeArrangementID),
                    replacementActiveArrangementID: replacementActiveArrangementID,
                    removedArrangementID: request.arrangementID,
                    expectedPaneCursor: source.targetPaneCursor,
                    expectedDrawerCursors: source.targetDrawerCursors
                )
            )
        )
    }
}

private struct WorkspaceArrangementLifecycleSource {
    let tab: TabGraphState
    let arrangement: PaneArrangementGraphState
    let activePaneCursor: WorkspaceActivePaneCursorWitness
    let activeDrawerCursors: [WorkspaceArrangementDrawerCursorWitness]
    let proposedOwner: WorkspaceArrangementIdentityOwnerWitness
    let proposedCursors: WorkspaceArrangementProposedCursorWitness
}

private enum WorkspaceArrangementLifecycleSourceResolution {
    case resolved(WorkspaceArrangementLifecycleSource)
    case rejected(WorkspaceArrangementLifecycleRejection)
}

private struct WorkspaceArrangementRemovalSource {
    let tab: TabGraphState
    let activeArrangementID: UUID
    let target: PaneArrangementGraphState
    let targetPaneCursor: WorkspaceActivePaneCursorWitness
    let targetDrawerCursors: [WorkspaceArrangementDrawerCursorWitness]
    let defaultArrangement: WorkspaceDefaultArrangementWitness
}

private enum WorkspaceArrangementRemovalSourceResolution {
    case resolved(WorkspaceArrangementRemovalSource)
    case rejected(WorkspaceArrangementLifecycleRejection)
}

extension WorkspaceArrangementLifecycleTransitionPlanner {
    private static func appendingArrangement(
        to tab: TabGraphState,
        copying source: PaneArrangementGraphState,
        arrangementID: UUID,
        name: String
    ) -> TabGraphState {
        var replacement = tab
        replacement.arrangements.append(
            PaneArrangementGraphState(
                id: arrangementID,
                name: name,
                isDefault: false,
                layout: source.layout,
                minimizedPaneIds: source.minimizedPaneIds,
                showsMinimizedPanes: source.showsMinimizedPanes,
                drawerViews: source.drawerViews
            )
        )
        return replacement
    }

    private static func resolveCreateSource(
        request: WorkspaceCreateArrangementRequest,
        context: WorkspaceCreateArrangementPlanningContext
    ) -> WorkspaceArrangementLifecycleSourceResolution {
        switch context {
        case .missingTab:
            return .rejected(.missingTab(request.tabID))
        case .missingActiveArrangement:
            return .rejected(.missingActiveArrangement(request.tabID))
        case .selectedActiveArrangement(let selected):
            let tab = selected.tab
            let arrangementID = selected.arrangementID
            guard tab.tabId == request.tabID else {
                return .rejected(.tabIdentityMismatch(requested: request.tabID, actual: tab.tabId))
            }
            guard let arrangement = tab.arrangements.first(where: { $0.id == arrangementID }) else {
                return .rejected(.missingArrangement(tabID: request.tabID, arrangementID: arrangementID))
            }
            return .resolved(
                .init(
                    tab: tab,
                    arrangement: arrangement,
                    activePaneCursor: selected.activePaneCursor,
                    activeDrawerCursors: selected.activeDrawerCursors,
                    proposedOwner: selected.proposedOwner,
                    proposedCursors: selected.proposedCursors
                )
            )
        }
    }

    private static func resolveRemovalSource(
        request: WorkspaceRemoveArrangementRequest,
        context: WorkspaceRemoveArrangementPlanningContext
    ) -> WorkspaceArrangementRemovalSourceResolution {
        switch context {
        case .missingTab:
            return .rejected(.missingTab(request.tabID))
        case .missingActiveArrangement:
            return .rejected(.missingActiveArrangement(request.tabID))
        case .selectedActiveArrangement(let selected):
            let tab = selected.tab
            let activeArrangementID = selected.arrangementID
            guard tab.tabId == request.tabID else {
                return .rejected(.tabIdentityMismatch(requested: request.tabID, actual: tab.tabId))
            }
            guard let target = tab.arrangements.first(where: { $0.id == request.arrangementID }) else {
                return .rejected(
                    .missingArrangement(tabID: request.tabID, arrangementID: request.arrangementID)
                )
            }
            guard tab.arrangements.contains(where: { $0.id == activeArrangementID }) else {
                return .rejected(
                    .missingArrangement(tabID: request.tabID, arrangementID: activeArrangementID)
                )
            }
            return .resolved(
                .init(
                    tab: tab,
                    activeArrangementID: activeArrangementID,
                    target: target,
                    targetPaneCursor: selected.targetPaneCursor,
                    targetDrawerCursors: selected.targetDrawerCursors,
                    defaultArrangement: selected.defaultArrangement
                )
            )
        }
    }

    private static func validatesCompleteView(
        tab: TabGraphState,
        arrangement: PaneArrangementGraphState
    ) -> Bool {
        let arrangementPaneIDs =
            arrangement.layout.paneIds
            + arrangement.drawerViews.values.flatMap(\.layout.paneIds)
        return Set(arrangementPaneIDs) == Set(tab.allPaneIds)
            && arrangementPaneIDs.count == tab.allPaneIds.count
            && Set(tab.allPaneIds).count == tab.allPaneIds.count
    }

    private static func paneCursorState(
        _ witness: WorkspaceActivePaneCursorWitness,
        arrangement: PaneArrangementGraphState
    ) -> ArrangementPaneCursorState? {
        guard case .present(let selection) = witness else { return nil }
        switch selection {
        case .noSelection:
            guard arrangement.layout.paneIds.allSatisfy(arrangement.minimizedPaneIds.contains) else { return nil }
            return .init(activePaneId: nil)
        case .selected(let paneID):
            guard arrangement.layout.contains(paneID), !arrangement.minimizedPaneIds.contains(paneID) else {
                return nil
            }
            return .init(activePaneId: paneID)
        }
    }

    private static func drawerCursorInsertions(
        _ witnesses: [WorkspaceArrangementDrawerCursorWitness],
        arrangement: PaneArrangementGraphState,
        newArrangementID: UUID
    ) -> Result<[WorkspaceArrangementDrawerCursorInsertion], WorkspaceArrangementLifecycleRejection> {
        if let rejection = validateDrawerCursors(witnesses, arrangement: arrangement) {
            return .failure(rejection)
        }
        return .success(
            witnesses.sorted { $0.drawerID.uuidString < $1.drawerID.uuidString }.map { witness in
                let selection: WorkspaceDrawerChildSelection
                guard case .present(let value) = witness.cursor else {
                    preconditionFailure("validated drawer cursor must be present")
                }
                selection = value
                let activeChildID: UUID?
                switch selection {
                case .noSelection: activeChildID = nil
                case .selected(let paneID): activeChildID = paneID
                }
                return .init(
                    key: .init(arrangementId: newArrangementID, drawerId: witness.drawerID),
                    state: .init(activeChildId: activeChildID)
                )
            }
        )
    }

    private static func validateDrawerCursors(
        _ witnesses: [WorkspaceArrangementDrawerCursorWitness],
        arrangement: PaneArrangementGraphState
    ) -> WorkspaceArrangementLifecycleRejection? {
        let actualIDs = Set(witnesses.map(\.drawerID))
        let expectedIDs = Set(arrangement.drawerViews.keys)
        guard actualIDs.count == witnesses.count else {
            let duplicateID = witnesses.map(\.drawerID).first { id in
                witnesses.filter { $0.drawerID == id }.count > 1
            }!
            return .duplicateDrawerWitness(
                .init(arrangementId: arrangement.id, drawerId: duplicateID)
            )
        }
        guard actualIDs == expectedIDs else {
            return .drawerWitnessSetMismatch(
                arrangementID: arrangement.id,
                expected: expectedIDs,
                actual: actualIDs
            )
        }
        for witness in witnesses {
            let key = ArrangementDrawerCursorKey(arrangementId: arrangement.id, drawerId: witness.drawerID)
            guard let drawer = arrangement.drawerViews[witness.drawerID], case .present(let selection) = witness.cursor
            else { return .missingDrawerCursor(key) }
            switch selection {
            case .noSelection:
                guard drawer.layout.paneIds.allSatisfy(drawer.minimizedPaneIds.contains) else {
                    return .inconsistentActiveDrawerCursor(key)
                }
            case .selected(let paneID):
                guard drawer.layout.contains(paneID), !drawer.minimizedPaneIds.contains(paneID) else {
                    return .inconsistentActiveDrawerCursor(key)
                }
            }
        }
        return nil
    }

    private static func validDefaultArrangementID(
        in tab: TabGraphState,
        witness: WorkspaceDefaultArrangementWitness
    ) -> UUID? {
        let defaultIDs = tab.arrangements.filter(\.isDefault).map(\.id)
        guard defaultIDs.count == 1, case .selected(let witnessedID) = witness, defaultIDs[0] == witnessedID else {
            return nil
        }
        return witnessedID
    }

    private static func defaultArrangementWitness(
        _ tab: TabGraphState
    ) -> WorkspaceDefaultArrangementWitness {
        let defaultIDs = tab.arrangements.filter(\.isDefault).map(\.id)
        switch defaultIDs.count {
        case 0: return .missing
        case 1: return .selected(defaultIDs[0])
        default: return .multiple(defaultIDs)
        }
    }

    private static func validateProposedDrawerWitnesses(
        _ witnesses: [WorkspaceArrangementDrawerCursorWitness],
        sourceArrangement: PaneArrangementGraphState,
        newArrangementID: UUID
    ) -> WorkspaceArrangementLifecycleRejection? {
        let actualIDs = Set(witnesses.map(\.drawerID))
        let expectedIDs = Set(sourceArrangement.drawerViews.keys)
        guard actualIDs.count == witnesses.count else {
            let duplicateID = witnesses.map(\.drawerID).first { id in
                witnesses.filter { $0.drawerID == id }.count > 1
            }!
            return .duplicateDrawerWitness(
                .init(arrangementId: newArrangementID, drawerId: duplicateID)
            )
        }
        guard actualIDs == expectedIDs else {
            return .drawerWitnessSetMismatch(
                arrangementID: newArrangementID,
                expected: expectedIDs,
                actual: actualIDs
            )
        }
        return nil
    }
}
