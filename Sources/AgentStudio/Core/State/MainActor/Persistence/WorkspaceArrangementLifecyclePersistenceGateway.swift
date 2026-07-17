import Foundation

enum WorkspaceArrangementLifecyclePersistenceFailure: Equatable, Sendable {
    case application(WorkspaceArrangementLifecycleApplyRejection)
    case arrangementCursorCapture(WorkspaceArrangementCursorPersistenceCaptureError)
    case compositionDomainNotInstalled(phase: WorkspacePersistenceAdapterLifecyclePhase)
    case planning(WorkspaceArrangementLifecycleRejection)
    case revisionOwner(WorkspacePersistenceRevisionOwnerError)
    case tabGraphCapture(WorkspaceTabGraphPersistencePreparationError)
}

enum WorkspaceArrangementLifecyclePersistenceResult: Equatable, Sendable {
    case changed(revision: WorkspacePersistenceRevision)
    case unchanged(revision: WorkspacePersistenceRevision)
    case rejected(WorkspaceArrangementLifecyclePersistenceFailure)
}

@MainActor
final class WorkspaceArrangementLifecyclePersistenceGateway {
    private let revisionOwner: WorkspacePersistenceRevisionOwner
    private let adapters: WorkspacePersistenceAdapterBundle
    private let workspaceTabGraphAtom: WorkspaceTabGraphAtom
    private let workspaceArrangementCursorAtom: WorkspaceArrangementCursorAtom
    private let transitionApplier: WorkspaceArrangementLifecycleTransitionApplier

    init(
        revisionOwner: WorkspacePersistenceRevisionOwner,
        adapters: WorkspacePersistenceAdapterBundle,
        workspaceTabGraphAtom: WorkspaceTabGraphAtom,
        workspaceArrangementCursorAtom: WorkspaceArrangementCursorAtom
    ) {
        self.revisionOwner = revisionOwner
        self.adapters = adapters
        self.workspaceTabGraphAtom = workspaceTabGraphAtom
        self.workspaceArrangementCursorAtom = workspaceArrangementCursorAtom
        transitionApplier = .init(
            workspaceTabGraphAtom: workspaceTabGraphAtom,
            workspaceArrangementCursorAtom: workspaceArrangementCursorAtom
        )
    }

    func createArrangement(
        _ request: WorkspaceCreateArrangementRequest
    ) -> WorkspaceArrangementLifecyclePersistenceResult {
        guardInstalled {
            commit(
                WorkspaceArrangementLifecycleTransitionPlanner.planCreate(
                    request,
                    context: createContext(request: request)
                )
            )
        }
    }

    func removeArrangement(
        _ request: WorkspaceRemoveArrangementRequest
    ) -> WorkspaceArrangementLifecyclePersistenceResult {
        guardInstalled {
            commit(
                WorkspaceArrangementLifecycleTransitionPlanner.planRemove(
                    request,
                    context: removeContext(request: request)
                )
            )
        }
    }

    private func createContext(
        request: WorkspaceCreateArrangementRequest
    ) -> WorkspaceCreateArrangementPlanningContext {
        guard let tab = workspaceTabGraphAtom.tabState(request.tabID) else { return .missingTab }
        guard let activeArrangementID = workspaceArrangementCursorAtom.activeArrangementId(forTab: request.tabID)
        else { return .missingActiveArrangement(tab: tab) }
        guard let activeArrangement = tab.arrangements.first(where: { $0.id == activeArrangementID }) else {
            return .selectedActiveArrangement(
                .init(
                    tab: tab,
                    arrangementID: activeArrangementID,
                    activePaneCursor: activePaneWitness(arrangementID: activeArrangementID),
                    activeDrawerCursors: [],
                    proposedOwner: proposedOwner(arrangementID: request.arrangementID.rawValue),
                    proposedCursors: .init(
                        paneCursor: activePaneWitness(arrangementID: request.arrangementID.rawValue),
                        drawerCursors: []
                    )
                )
            )
        }
        let sourceDrawers = drawerWitnesses(
            arrangementID: activeArrangementID,
            drawerIDs: Array(activeArrangement.drawerViews.keys)
        )
        let proposedDrawers = drawerWitnesses(
            arrangementID: request.arrangementID.rawValue,
            drawerIDs: Array(activeArrangement.drawerViews.keys)
        )
        return .selectedActiveArrangement(
            .init(
                tab: tab,
                arrangementID: activeArrangementID,
                activePaneCursor: activePaneWitness(arrangementID: activeArrangementID),
                activeDrawerCursors: sourceDrawers,
                proposedOwner: proposedOwner(arrangementID: request.arrangementID.rawValue),
                proposedCursors: .init(
                    paneCursor: activePaneWitness(arrangementID: request.arrangementID.rawValue),
                    drawerCursors: proposedDrawers
                )
            )
        )
    }

    private func removeContext(
        request: WorkspaceRemoveArrangementRequest
    ) -> WorkspaceRemoveArrangementPlanningContext {
        guard let tab = workspaceTabGraphAtom.tabState(request.tabID) else { return .missingTab }
        guard let activeArrangementID = workspaceArrangementCursorAtom.activeArrangementId(forTab: request.tabID)
        else { return .missingActiveArrangement(tab: tab) }
        let drawerIDs =
            tab.arrangements.first(where: { $0.id == request.arrangementID })
            .map { Array($0.drawerViews.keys) } ?? []
        return .selectedActiveArrangement(
            .init(
                tab: tab,
                arrangementID: activeArrangementID,
                targetPaneCursor: activePaneWitness(arrangementID: request.arrangementID),
                targetDrawerCursors: drawerWitnesses(
                    arrangementID: request.arrangementID,
                    drawerIDs: drawerIDs
                ),
                defaultArrangement: defaultArrangementWitness(tab: tab)
            )
        )
    }

    private func proposedOwner(arrangementID: UUID) -> WorkspaceArrangementIdentityOwnerWitness {
        workspaceTabGraphAtom.tabID(containingArrangement: arrangementID)
            .map(WorkspaceArrangementIdentityOwnerWitness.ownedByTab) ?? .unowned
    }

    private func defaultArrangementWitness(tab: TabGraphState) -> WorkspaceDefaultArrangementWitness {
        let defaultIDs = tab.arrangements.filter(\.isDefault).map(\.id)
        switch defaultIDs.count {
        case 0: return .missing
        case 1: return .selected(defaultIDs[0])
        default: return .multiple(defaultIDs)
        }
    }

    private func activePaneWitness(arrangementID: UUID) -> WorkspaceActivePaneCursorWitness {
        guard workspaceArrangementCursorAtom.hasPaneCursor(arrangementID: arrangementID) else { return .missing }
        return .present(
            workspaceArrangementCursorAtom.activePaneId(forArrangement: arrangementID)
                .map(WorkspacePaneSelection.selected) ?? .noSelection
        )
    }

    private func drawerWitnesses(
        arrangementID: UUID,
        drawerIDs: [UUID]
    ) -> [WorkspaceArrangementDrawerCursorWitness] {
        drawerIDs.sorted { $0.uuidString < $1.uuidString }.map { drawerID in
            let key = ArrangementDrawerCursorKey(arrangementId: arrangementID, drawerId: drawerID)
            let cursor: WorkspaceActiveDrawerChildCursorWitness
            if workspaceArrangementCursorAtom.hasDrawerCursor(key) {
                cursor = .present(
                    workspaceArrangementCursorAtom.activeChildId(
                        forArrangement: arrangementID,
                        drawerId: drawerID
                    ).map(WorkspaceDrawerChildSelection.selected) ?? .noSelection
                )
            } else {
                cursor = .missing
            }
            return .init(drawerID: drawerID, cursor: cursor)
        }
    }

    private func guardInstalled(
        _ operation: () -> WorkspaceArrangementLifecyclePersistenceResult
    ) -> WorkspaceArrangementLifecyclePersistenceResult {
        guard case .installed = adapters.compositionLifecyclePhase else {
            return .rejected(.compositionDomainNotInstalled(phase: adapters.compositionLifecyclePhase))
        }
        return operation()
    }

    private func commit(
        _ decision: WorkspaceArrangementLifecycleDecision
    ) -> WorkspaceArrangementLifecyclePersistenceResult {
        switch decision {
        case .unchanged: return .unchanged(revision: revisionOwner.committedRevision)
        case .rejected(let rejection): return .rejected(.planning(rejection))
        case .changed(let transition): return commit(transition)
        }
    }

    private func commit(
        _ transition: WorkspaceArrangementLifecycleTransition
    ) -> WorkspaceArrangementLifecyclePersistenceResult {
        let preparedApplication: WorkspacePreparedArrangementLifecycleApplication
        switch transitionApplier.preflight(transition) {
        case .ready(let preparation): preparedApplication = preparation
        case .rejected(let rejection): return .rejected(.application(rejection))
        }
        do {
            let revision = try revisionOwner.performSynchronousTransaction { preparation in
                try adapters.workspaceTabGraph.capturePersistencePreimages(
                    .init(operations: [.valueChange(transition.tabID)]),
                    for: preparation
                )
                let cursorCapture = transition.cursorPersistenceCapture
                if !cursorCapture.isEmpty {
                    try adapters.workspaceArrangementCursor.capturePersistencePreimages(
                        cursorCapture,
                        for: preparation
                    )
                }
                return preparation.commit { [transitionApplier] in
                    transitionApplier.apply(preparedApplication)
                    return preparation.transaction.proposedRevision
                }
            }
            return .changed(revision: revision)
        } catch let error as WorkspaceTabGraphPersistencePreparationError {
            return .rejected(.tabGraphCapture(error))
        } catch let error as WorkspaceArrangementCursorPersistenceCaptureError {
            return .rejected(.arrangementCursorCapture(error))
        } catch let error as WorkspacePersistenceRevisionOwnerError {
            return .rejected(.revisionOwner(error))
        } catch {
            preconditionFailure("arrangement lifecycle persistence gateway emitted an unmodeled error")
        }
    }
}

extension WorkspaceArrangementLifecycleTransition {
    fileprivate var tabID: UUID {
        switch self {
        case .create(let creation): creation.previousTab.tabId
        case .remove(let removal): removal.previousTab.tabId
        }
    }

    fileprivate var cursorPersistenceCapture: WorkspaceArrangementCursorPersistenceCapture {
        switch self {
        case .create(let creation):
            return .init(
                activeArrangements: [],
                activePanes: creation.paneCursorInsertion.state.activePaneId == nil
                    ? [] : [.insertion(arrangementID: creation.paneCursorInsertion.arrangementID)],
                activeDrawerChildren: creation.drawerCursorInsertions.compactMap { insertion in
                    insertion.state.activeChildId == nil ? nil : .insertion(insertion.key)
                }
            )
        case .remove(let removal):
            return .init(
                activeArrangements: removal.replacementActiveArrangementID == nil
                    ? [] : [.valueChange(tabID: removal.previousTab.tabId)],
                activePanes: removal.expectedPaneCursor.hasSelectedValue
                    ? [.removal(arrangementID: removal.removedArrangementID)] : [],
                activeDrawerChildren: removal.expectedDrawerCursors.compactMap { witness in
                    guard witness.cursor.hasSelectedValue else { return nil }
                    return .removal(
                        .init(
                            arrangementId: removal.removedArrangementID,
                            drawerId: witness.drawerID
                        )
                    )
                }
            )
        }
    }
}

extension WorkspaceArrangementCursorPersistenceCapture {
    fileprivate var isEmpty: Bool {
        activeArrangements.isEmpty && activePanes.isEmpty && activeDrawerChildren.isEmpty
    }
}

extension WorkspaceActivePaneCursorWitness {
    fileprivate var hasSelectedValue: Bool {
        guard case .present(.selected) = self else { return false }
        return true
    }
}

extension WorkspaceActiveDrawerChildCursorWitness {
    fileprivate var hasSelectedValue: Bool {
        guard case .present(.selected) = self else { return false }
        return true
    }
}
