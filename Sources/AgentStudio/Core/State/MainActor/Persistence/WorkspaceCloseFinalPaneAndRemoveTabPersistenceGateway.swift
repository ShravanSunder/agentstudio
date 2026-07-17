import Foundation

enum WorkspaceFinalPaneTabRemovalFailure: Error, Equatable, Sendable {
    case application(WorkspaceCloseFinalPaneAndRemoveTabApplyRejection)
    case arrangementCursorCapture(WorkspaceArrangementCursorPersistenceCaptureError)
    case compositionDomainNotInstalled(phase: WorkspacePersistenceAdapterLifecyclePhase)
    case paneGraphCapture(WorkspacePaneGraphPersistenceCaptureError)
    case planning(WorkspaceCloseFinalPaneAndRemoveTabRejection)
    case revisionOwner(WorkspacePersistenceRevisionOwnerError)
    case tabCursorCapture(WorkspaceTabCursorPersistenceCaptureError)
    case tabGraphCapture(WorkspaceTabGraphPersistencePreparationError)
    case tabShellCapture(WorkspaceTabShellPersistencePreparationError)
}

enum WorkspaceFinalPaneTabRemovalResult: Equatable, Sendable {
    case closed(revision: WorkspacePersistenceRevision)
    case rejected(WorkspaceFinalPaneTabRemovalFailure)
}

@MainActor
final class WorkspaceFinalPaneTabRemovalGateway {
    private let revisionOwner: WorkspacePersistenceRevisionOwner
    private let adapters: WorkspacePersistenceAdapterBundle
    private let workspacePaneGraphAtom: WorkspacePaneGraphAtom
    private let workspaceTabShellAtom: WorkspaceTabShellAtom
    private let workspaceTabCursorAtom: WorkspaceTabCursorAtom
    private let workspaceTabGraphAtom: WorkspaceTabGraphAtom
    private let workspaceArrangementCursorAtom: WorkspaceArrangementCursorAtom
    private let workspaceDrawerCursorAtom: WorkspaceDrawerCursorAtom
    private let workspacePanePresentationAtom: WorkspacePanePresentationAtom
    private let transitionApplier: WorkspaceFinalPaneTabRemovalApplier

    init(
        revisionOwner: WorkspacePersistenceRevisionOwner,
        adapters: WorkspacePersistenceAdapterBundle,
        workspacePaneGraphAtom: WorkspacePaneGraphAtom,
        workspaceTabShellAtom: WorkspaceTabShellAtom,
        workspaceTabCursorAtom: WorkspaceTabCursorAtom,
        workspaceTabGraphAtom: WorkspaceTabGraphAtom,
        workspaceArrangementCursorAtom: WorkspaceArrangementCursorAtom,
        workspaceDrawerCursorAtom: WorkspaceDrawerCursorAtom,
        workspacePanePresentationAtom: WorkspacePanePresentationAtom
    ) {
        self.revisionOwner = revisionOwner
        self.adapters = adapters
        self.workspacePaneGraphAtom = workspacePaneGraphAtom
        self.workspaceTabShellAtom = workspaceTabShellAtom
        self.workspaceTabCursorAtom = workspaceTabCursorAtom
        self.workspaceTabGraphAtom = workspaceTabGraphAtom
        self.workspaceArrangementCursorAtom = workspaceArrangementCursorAtom
        self.workspaceDrawerCursorAtom = workspaceDrawerCursorAtom
        self.workspacePanePresentationAtom = workspacePanePresentationAtom
        transitionApplier = .init(
            workspacePaneGraphAtom: workspacePaneGraphAtom,
            workspaceTabShellAtom: workspaceTabShellAtom,
            workspaceTabCursorAtom: workspaceTabCursorAtom,
            workspaceTabGraphAtom: workspaceTabGraphAtom,
            workspaceArrangementCursorAtom: workspaceArrangementCursorAtom,
            workspaceDrawerCursorAtom: workspaceDrawerCursorAtom,
            workspacePanePresentationAtom: workspacePanePresentationAtom
        )
    }

    func close(
        _ request: WorkspaceCloseFinalPaneAndRemoveTabRequest
    ) -> WorkspaceFinalPaneTabRemovalResult {
        guard case .installed = adapters.compositionLifecyclePhase else {
            return .rejected(.compositionDomainNotInstalled(phase: adapters.compositionLifecyclePhase))
        }
        switch WorkspaceFinalPaneTabRemovalPlanner.plan(
            request,
            context: planningContext(request)
        ) {
        case .changed(let transition): return commit(transition)
        case .rejected(let rejection): return .rejected(.planning(rejection))
        }
    }

    private func planningContext(
        _ request: WorkspaceCloseFinalPaneAndRemoveTabRequest
    ) -> WorkspaceCloseFinalPaneAndRemoveTabPlanningContext {
        let pane = workspacePaneGraphAtom.paneState(request.paneID)
        let tab = workspaceTabGraphAtom.tabState(request.tabID)
        return .init(
            pane: pane.map(WorkspaceClosePaneWitness.present) ?? .missing,
            ownership: workspaceTabGraphAtom.tabID(containingPane: request.paneID)
                .map(WorkspaceClosePaneOwnershipWitness.owned) ?? .absent,
            tab: tab.map(WorkspaceClosePaneTabWitness.present) ?? .missing,
            tabIndex: workspaceTabGraphAtom.tabIndex(for: request.tabID),
            tabShells: workspaceTabShellAtom.tabShells,
            activeTab: workspaceTabCursorAtom.activeTabId.map(WorkspaceTabCursorSelection.selected) ?? .noSelection,
            activeArrangement: workspaceArrangementCursorAtom.activeArrangementId(forTab: request.tabID)
                .map(WorkspaceActiveArrangementSelection.selected) ?? .missing,
            paneCursors: tab.map(activePaneCursorWitnesses) ?? [],
            arrangementDrawerCursorKeys: drawerCursorKeys(tab: tab),
            drawerCursor: .init(expandedDrawerID: workspaceDrawerCursorAtom.expandedDrawerId),
            zoom: workspacePanePresentationAtom.zoomedPaneId(forTab: request.tabID)
                .map(WorkspaceZoomSelection.zoomed) ?? .notZoomed
        )
    }

    private func activePaneCursorWitnesses(_ tab: TabGraphState) -> [WorkspaceClosePaneCursorWitness] {
        tab.arrangements.map { arrangement in
            let cursor: WorkspaceActivePaneCursorWitness
            if workspaceArrangementCursorAtom.hasPaneCursor(arrangementID: arrangement.id) {
                cursor = .present(
                    workspaceArrangementCursorAtom.activePaneId(forArrangement: arrangement.id)
                        .map(WorkspacePaneSelection.selected) ?? .noSelection
                )
            } else {
                cursor = .missing
            }
            return .init(arrangementID: arrangement.id, cursor: cursor)
        }
    }

    private func drawerCursorKeys(tab: TabGraphState?) -> [ArrangementDrawerCursorKey] {
        guard let tab else { return [] }
        let removedArrangementIDs = Set(tab.arrangements.map(\.id))
        return workspaceArrangementCursorAtom.drawerCursorsByKey.keys.filter {
            removedArrangementIDs.contains($0.arrangementId)
        }
    }

    private func commit(
        _ transition: WorkspaceCloseFinalPaneAndRemoveTabTransition
    ) -> WorkspaceFinalPaneTabRemovalResult {
        let prepared: WorkspacePreparedFinalPaneTabRemoval
        switch transitionApplier.preflight(transition) {
        case .ready(let value): prepared = value
        case .rejected(let rejection): return .rejected(.application(rejection))
        }
        do {
            let revision = try revisionOwner.performSynchronousTransaction { preparation in
                try adapters.workspacePaneGraph.capturePersistencePreimages(
                    .init(operations: [.removal(transition.previousPane.id)]),
                    for: preparation
                )
                try adapters.workspaceTabGraph.capturePersistencePreimages(
                    .init(operations: [.removal(transition.removedTab.state.tabId)]),
                    for: preparation
                )
                let shellCaptures: [WorkspaceTabShellPersistenceCaptureOperation] =
                    [.removal(transition.removedShell.shell.id)]
                    + transition.shiftedShellSuffix.map { .valueChange($0.shell.id) }
                try adapters.workspaceTabShell.capturePersistencePreimages(
                    .init(operations: shellCaptures),
                    for: preparation
                )
                try captureTabCursorPreimage(transition.tabCursor, for: preparation)
                let selectedPaneCaptures = transition.removedActivePanes.compactMap { witness in
                    switch witness.cursor {
                    case .present(.selected):
                        WorkspaceActivePanePersistenceCapture.removal(arrangementID: witness.arrangementID)
                    case .missing, .present(.noSelection):
                        nil
                    }
                }
                try adapters.workspaceArrangementCursor.capturePersistencePreimages(
                    .init(
                        activeArrangements: [.removal(tabID: transition.removedTab.state.tabId)],
                        activePanes: selectedPaneCaptures,
                        activeDrawerChildren: []
                    ),
                    for: preparation
                )
                return preparation.commit { [transitionApplier] in
                    transitionApplier.apply(prepared)
                    return preparation.transaction.proposedRevision
                }
            }
            return .closed(revision: revision)
        } catch let error as WorkspacePaneGraphPersistenceCaptureError {
            return .rejected(.paneGraphCapture(error))
        } catch let error as WorkspaceTabGraphPersistencePreparationError {
            return .rejected(.tabGraphCapture(error))
        } catch let error as WorkspaceTabShellPersistencePreparationError {
            return .rejected(.tabShellCapture(error))
        } catch let error as WorkspaceTabCursorPersistenceCaptureError {
            return .rejected(.tabCursorCapture(error))
        } catch let error as WorkspaceArrangementCursorPersistenceCaptureError {
            return .rejected(.arrangementCursorCapture(error))
        } catch let error as WorkspacePersistenceRevisionOwnerError {
            return .rejected(.revisionOwner(error))
        } catch {
            preconditionFailure("final-pane tab removal gateway emitted an unmodeled error")
        }
    }

    private func captureTabCursorPreimage(
        _ mutation: WorkspaceFinalPaneTabCursorMutation,
        for preparation: WorkspacePersistenceTransactionPreparation
    ) throws {
        guard case .replace(let replacement) = mutation else { return }
        let capture: WorkspaceTabCursorPersistenceCapture
        switch (replacement.previous, replacement.replacement) {
        case (.selected, .selected): capture = .valueChange
        case (.selected, .noSelection): capture = .removal
        case (.noSelection, .selected): capture = .insertion
        case (.noSelection, .noSelection):
            preconditionFailure("changed final-pane removal cannot preserve an empty tab cursor")
        }
        try adapters.workspaceTabCursor.capturePersistencePreimage(capture, for: preparation)
    }
}
