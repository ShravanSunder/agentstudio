import Foundation

enum WorkspacePaneResidencyPersistenceFailure: Equatable, Sendable {
    case application(WorkspacePaneResidencyLifecycleApplyRejection)
    case arrangementCursorCapture(WorkspaceArrangementCursorPersistenceCaptureError)
    case compositionDomainNotInstalled(phase: WorkspacePersistenceAdapterLifecyclePhase)
    case paneGraphCapture(WorkspacePaneGraphPersistenceCaptureError)
    case planning(WorkspacePaneResidencyLifecycleRejection)
    case revisionOwner(WorkspacePersistenceRevisionOwnerError)
    case tabCursorCapture(WorkspaceTabCursorPersistenceCaptureError)
    case tabGraphCapture(WorkspaceTabGraphPersistencePreparationError)
    case tabShellCapture(WorkspaceTabShellPersistencePreparationError)
}

enum WorkspacePaneResidencyPersistenceResult: Equatable, Sendable {
    case changed(
        revision: WorkspacePersistenceRevision,
        effect: WorkspacePaneResidencyRuntimeEffect
    )
    case unchanged(revision: WorkspacePersistenceRevision)
    case rejected(WorkspacePaneResidencyPersistenceFailure)
}

private struct WorkspaceCommittedPaneResidencyMutation {
    let revision: WorkspacePersistenceRevision
    let effect: WorkspacePaneResidencyRuntimeEffect
}

/// Owns fixed-revision persistence for discrete pane-residency lifecycle mutations.
@MainActor
final class WorkspacePaneResidencyPersistenceGateway {
    private let revisionOwner: WorkspacePersistenceRevisionOwner
    private let adapters: WorkspacePersistenceAdapterBundle
    private let workspacePaneGraphAtom: WorkspacePaneGraphAtom
    private let workspaceTabShellAtom: WorkspaceTabShellAtom
    private let workspaceTabCursorAtom: WorkspaceTabCursorAtom
    private let workspaceTabGraphAtom: WorkspaceTabGraphAtom
    private let workspaceArrangementCursorAtom: WorkspaceArrangementCursorAtom
    private let workspacePanePresentationAtom: WorkspacePanePresentationAtom
    private let transitionApplier: WorkspacePaneResidencyLifecycleTransitionApplier

    init(
        revisionOwner: WorkspacePersistenceRevisionOwner,
        adapters: WorkspacePersistenceAdapterBundle,
        workspacePaneGraphAtom: WorkspacePaneGraphAtom,
        workspaceTabShellAtom: WorkspaceTabShellAtom,
        workspaceTabCursorAtom: WorkspaceTabCursorAtom,
        workspaceTabGraphAtom: WorkspaceTabGraphAtom,
        workspaceArrangementCursorAtom: WorkspaceArrangementCursorAtom,
        workspacePanePresentationAtom: WorkspacePanePresentationAtom
    ) {
        self.revisionOwner = revisionOwner
        self.adapters = adapters
        self.workspacePaneGraphAtom = workspacePaneGraphAtom
        self.workspaceTabShellAtom = workspaceTabShellAtom
        self.workspaceTabCursorAtom = workspaceTabCursorAtom
        self.workspaceTabGraphAtom = workspaceTabGraphAtom
        self.workspaceArrangementCursorAtom = workspaceArrangementCursorAtom
        self.workspacePanePresentationAtom = workspacePanePresentationAtom
        transitionApplier = WorkspacePaneResidencyLifecycleTransitionApplier(
            workspacePaneGraphAtom: workspacePaneGraphAtom,
            workspaceTabShellAtom: workspaceTabShellAtom,
            workspaceTabCursorAtom: workspaceTabCursorAtom,
            workspaceTabGraphAtom: workspaceTabGraphAtom,
            workspaceArrangementCursorAtom: workspaceArrangementCursorAtom,
            workspacePanePresentationAtom: workspacePanePresentationAtom
        )
    }

    func backgroundPane(
        _ request: WorkspaceBackgroundPaneRequest,
        retainedDrawerPayload: WorkspaceRetainedDrawerPayloadWitness
    ) -> WorkspacePaneResidencyPersistenceResult {
        guardInstalled { () -> WorkspacePaneResidencyPersistenceResult in
            let context = backgroundPlanningContext(
                paneID: request.paneID,
                retainedDrawerPayload: retainedDrawerPayload
            )
            switch WorkspaceBackgroundPaneTransitionPlanner.plan(request, context: context) {
            case .changed(let transition):
                return commit(transition, retainedDrawerPayload: retainedDrawerPayload)
            case .unchanged:
                return .unchanged(revision: revisionOwner.committedRevision)
            case .rejected(let rejection):
                return .rejected(.planning(rejection))
            }
        }
    }

    func reactivatePane(
        _ request: WorkspaceReactivatePaneRequest,
        retainedDrawerPayload: WorkspaceRetainedDrawerPayloadWitness
    ) -> WorkspacePaneResidencyPersistenceResult {
        guardInstalled { () -> WorkspacePaneResidencyPersistenceResult in
            let context = reactivatePlanningContext(
                request: request,
                retainedDrawerPayload: retainedDrawerPayload
            )
            switch WorkspaceReactivatePaneTransitionPlanner.plan(request, context: context) {
            case .changed(let transition):
                return commit(transition, retainedDrawerPayload: retainedDrawerPayload)
            case .unchanged:
                return .unchanged(revision: revisionOwner.committedRevision)
            case .rejected(let rejection):
                return .rejected(.planning(rejection))
            }
        }
    }

    private func guardInstalled(
        _ mutation: () -> WorkspacePaneResidencyPersistenceResult
    ) -> WorkspacePaneResidencyPersistenceResult {
        guard case .installed = adapters.compositionLifecyclePhase else {
            return .rejected(
                .compositionDomainNotInstalled(phase: adapters.compositionLifecyclePhase)
            )
        }
        return mutation()
    }

    private func commit(
        _ transition: WorkspacePaneResidencyLifecycleTransition,
        retainedDrawerPayload: WorkspaceRetainedDrawerPayloadWitness
    ) -> WorkspacePaneResidencyPersistenceResult {
        let preparedApplication: WorkspacePreparedPaneResidencyLifecycleApplication
        switch transitionApplier.preflight(
            transition,
            retainedDrawerPayload: retainedDrawerPayload
        ) {
        case .ready(let preparation):
            preparedApplication = preparation
        case .rejected(let rejection):
            return .rejected(.application(rejection))
        }

        do {
            let committed = try revisionOwner.performSynchronousTransaction { preparation in
                try capturePreimages(transition, for: preparation)
                return preparation.commit { [transitionApplier] in
                    let effect: WorkspacePaneResidencyRuntimeEffect
                    switch transitionApplier.apply(
                        preparedApplication,
                        retainedDrawerPayload: retainedDrawerPayload
                    ) {
                    case .applied(let appliedEffect):
                        effect = appliedEffect
                    case .rejected:
                        preconditionFailure(
                            "synchronous pane-residency application changed after preflight"
                        )
                    }
                    return WorkspaceCommittedPaneResidencyMutation(
                        revision: preparation.transaction.proposedRevision,
                        effect: effect
                    )
                }
            }
            return .changed(revision: committed.revision, effect: committed.effect)
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
            preconditionFailure("pane-residency persistence gateway emitted an unmodeled error")
        }
    }

    private func backgroundPlanningContext(
        paneID: UUID,
        retainedDrawerPayload: WorkspaceRetainedDrawerPayloadWitness
    ) -> WorkspaceBackgroundPanePlanningContext {
        let pane = paneWitness(paneID)
        let familyPaneIDs = paneFamilyIDs(pane)
        let ownership = ownershipWitnesses(familyPaneIDs)
        let sourceTab = ownedTab(for: paneID)
        let drawerID = drawerID(pane)
        return WorkspaceBackgroundPanePlanningContext(
            pane: pane,
            declaredDrawerChildrenByID: childStates(familyPaneIDs.dropFirst()),
            ownershipByPaneID: ownership,
            tabCursors: cursorSnapshot(tab: sourceTab, drawerID: drawerID),
            tabRemoval: tabRemovalContext(sourceTab: sourceTab, familyPaneIDs: familyPaneIDs),
            retainedDrawerPayload: retainedDrawerPayload
        )
    }

    private func reactivatePlanningContext(
        request: WorkspaceReactivatePaneRequest,
        retainedDrawerPayload: WorkspaceRetainedDrawerPayloadWitness
    ) -> WorkspaceReactivatePanePlanningContext {
        let pane = paneWitness(request.paneID)
        let familyPaneIDs = paneFamilyIDs(pane)
        let targetTab = indexedTab(request.targetTabID)
        return WorkspaceReactivatePanePlanningContext(
            pane: pane,
            declaredDrawerChildrenByID: childStates(familyPaneIDs.dropFirst()),
            ownershipByPaneID: ownershipWitnesses(familyPaneIDs),
            targetTab: targetTab.map(WorkspaceTargetTabWitness.present) ?? .missing,
            targetTabCursors: cursorSnapshot(
                tab: targetTab,
                drawerID: drawerID(pane)
            ),
            retainedDrawerPayload: retainedDrawerPayload
        )
    }

    private func paneWitness(_ paneID: UUID) -> WorkspacePaneResidencyPaneWitness {
        workspacePaneGraphAtom.paneState(paneID)
            .map(WorkspacePaneResidencyPaneWitness.present) ?? .missing
    }

    private func paneFamilyIDs(
        _ pane: WorkspacePaneResidencyPaneWitness
    ) -> [UUID] {
        guard case .present(let paneState) = pane else { return [] }
        guard case .layout(let drawer) = paneState.kind else { return [paneState.id] }
        return [paneState.id] + drawer.paneIds
    }

    private func drawerID(
        _ pane: WorkspacePaneResidencyPaneWitness
    ) -> UUID? {
        guard case .present(let paneState) = pane,
            case .layout(let drawer) = paneState.kind
        else { return nil }
        return drawer.drawerId
    }

    private func childStates<S: Sequence>(
        _ paneIDs: S
    ) -> [UUID: PaneGraphState] where S.Element == UUID {
        Dictionary(
            uniqueKeysWithValues: paneIDs.compactMap { paneID in
                workspacePaneGraphAtom.paneState(paneID).map { (paneID, $0) }
            }
        )
    }

    private func ownershipWitnesses(
        _ paneIDs: [UUID]
    ) -> [UUID: WorkspacePaneResidencyTabOwnershipWitness] {
        Dictionary(uniqueKeysWithValues: paneIDs.map { ($0, ownershipWitness($0)) })
    }

    private func ownershipWitness(
        _ paneID: UUID
    ) -> WorkspacePaneResidencyTabOwnershipWitness {
        guard let owner = ownedTab(for: paneID) else { return .absent }
        return .owned(owner)
    }

    private func ownedTab(
        for paneID: UUID
    ) -> WorkspaceIndexedTabGraphState? {
        guard let tabID = workspaceTabGraphAtom.tabID(containingPane: paneID) else { return nil }
        return indexedTab(tabID)
    }

    private func indexedTab(
        _ tabID: UUID
    ) -> WorkspaceIndexedTabGraphState? {
        guard let state = workspaceTabGraphAtom.tabState(tabID),
            let index = workspaceTabGraphAtom.tabIndex(for: tabID)
        else { return nil }
        return .init(index: index, state: state)
    }

    private func cursorSnapshot(
        tab: WorkspaceIndexedTabGraphState?,
        drawerID: UUID?
    ) -> WorkspacePaneResidencyTabCursorSnapshot {
        guard let tab else {
            return .init(
                activeArrangement: .missing,
                activePanesByArrangementID: [:],
                activeDrawerChildrenByKey: [:],
                zoom: .notZoomed
            )
        }
        let activePanes = Dictionary(
            uniqueKeysWithValues: tab.state.arrangements.map { arrangement in
                (arrangement.id, activePaneWitness(arrangement.id))
            }
        )
        let activeDrawers: [ArrangementDrawerCursorKey: WorkspacePaneResidencyDrawerCursorWitness]
        if let drawerID {
            activeDrawers = Dictionary(
                uniqueKeysWithValues: tab.state.arrangements.map { arrangement in
                    let key = ArrangementDrawerCursorKey(
                        arrangementId: arrangement.id,
                        drawerId: drawerID
                    )
                    return (key, activeDrawerWitness(key))
                }
            )
        } else {
            activeDrawers = [:]
        }
        return .init(
            activeArrangement: workspaceArrangementCursorAtom.activeArrangementId(forTab: tab.state.tabId)
                .map(WorkspaceActiveArrangementSelection.selected) ?? .missing,
            activePanesByArrangementID: activePanes,
            activeDrawerChildrenByKey: activeDrawers,
            zoom: workspacePanePresentationAtom.zoomedPaneId(forTab: tab.state.tabId)
                .map(WorkspaceZoomSelection.zoomed) ?? .notZoomed
        )
    }

    private func activePaneWitness(
        _ arrangementID: UUID
    ) -> WorkspaceActivePaneCursorWitness {
        guard let cursor = workspaceArrangementCursorAtom.paneCursorsByArrangementId[arrangementID]
        else { return .missing }
        return .present(cursor.activePaneId.map(WorkspacePaneSelection.selected) ?? .noSelection)
    }

    private func activeDrawerWitness(
        _ key: ArrangementDrawerCursorKey
    ) -> WorkspacePaneResidencyDrawerCursorWitness {
        guard let cursor = workspaceArrangementCursorAtom.drawerCursorsByKey[key]
        else { return .missing }
        return .present(
            cursor.activeChildId.map(WorkspacePaneResidencyDrawerSelection.selected) ?? .noSelection
        )
    }

    private func tabRemovalContext(
        sourceTab: WorkspaceIndexedTabGraphState?,
        familyPaneIDs: [UUID]
    ) -> WorkspaceBackgroundTabRemovalContext {
        guard let sourceTab,
            Set(sourceTab.state.allPaneIds) == Set(familyPaneIDs)
        else { return .notRequired }
        let activeTab =
            workspaceTabCursorAtom.activeTabId
            .map(WorkspaceTabCursorSelection.selected) ?? .noSelection
        return .current(tabShells: workspaceTabShellAtom.tabShells, activeTab: activeTab)
    }

    private func capturePreimages(
        _ transition: WorkspacePaneResidencyLifecycleTransition,
        for preparation: WorkspacePersistenceTransactionPreparation
    ) throws {
        switch transition {
        case .background(let background):
            try capturePanePreimages(background.paneReplacements, for: preparation)
            try captureTabGraphPreimage(background.tabGraph, for: preparation)
            try captureTabShellPreimages(background.tabShell, for: preparation)
            try captureTabCursorPreimage(background.tabCursor, for: preparation)
            try captureArrangementCursorPreimages(
                activeArrangements: background.activeArrangements,
                activePanes: background.activePanes,
                activeDrawers: background.activeDrawerChildren,
                for: preparation
            )
        case .reactivate(let reactivate):
            try capturePanePreimages(reactivate.paneReplacements, for: preparation)
            try captureTabGraphPreimage(reactivate.tabGraph, for: preparation)
            try captureArrangementCursorPreimages(
                activeArrangements: reactivate.activeArrangements,
                activePanes: reactivate.activePanes,
                activeDrawers: reactivate.activeDrawerChildren,
                for: preparation
            )
        }
    }

    private func capturePanePreimages(
        _ replacements: [WorkspacePaneResidencyPaneReplacement],
        for preparation: WorkspacePersistenceTransactionPreparation
    ) throws {
        try adapters.workspacePaneGraph.capturePersistencePreimages(
            WorkspacePaneGraphPersistenceCapture(
                operations: replacements.map { .valueChange($0.paneID) }
            ),
            for: preparation
        )
    }

    private func captureTabGraphPreimage(
        _ mutation: WorkspacePaneResidencyTabGraphMutation,
        for preparation: WorkspacePersistenceTransactionPreparation
    ) throws {
        let operation: WorkspaceTabGraphPersistenceCaptureOperation
        switch mutation {
        case .replace(let previous, _):
            operation = .valueChange(previous.state.tabId)
        case .remove(let previous):
            operation = .removal(previous.state.tabId)
        }
        try adapters.workspaceTabGraph.capturePersistencePreimages(
            WorkspaceTabGraphPersistenceCapture(operations: [operation]),
            for: preparation
        )
    }

    private func captureTabShellPreimages(
        _ mutation: WorkspacePaneResidencyTabShellMutation,
        for preparation: WorkspacePersistenceTransactionPreparation
    ) throws {
        guard case .remove(let removed, let shiftedSuffix) = mutation else { return }
        let operations: [WorkspaceTabShellPersistenceCaptureOperation] =
            [.removal(removed.shell.id)] + shiftedSuffix.map { .valueChange($0.shell.id) }
        try adapters.workspaceTabShell.capturePersistencePreimages(
            WorkspaceTabShellPersistenceCapture(operations: operations),
            for: preparation
        )
    }

    private func captureTabCursorPreimage(
        _ mutation: WorkspacePaneResidencyTabCursorMutation,
        for preparation: WorkspacePersistenceTransactionPreparation
    ) throws {
        guard case .replace(let replacement) = mutation else { return }
        let capture: WorkspaceTabCursorPersistenceCapture
        switch (replacement.previous, replacement.replacement) {
        case (.noSelection, .selected): capture = .insertion
        case (.selected, .selected): capture = .valueChange
        case (.selected, .noSelection): capture = .removal
        case (.noSelection, .noSelection):
            preconditionFailure("changed pane residency cannot preserve an empty tab cursor")
        }
        try adapters.workspaceTabCursor.capturePersistencePreimage(capture, for: preparation)
    }

    private func captureArrangementCursorPreimages(
        activeArrangements: [WorkspacePaneResidencyActiveArrangementMutation],
        activePanes: [WorkspacePaneResidencyActivePaneMutation],
        activeDrawers: [WorkspacePaneResidencyActiveDrawerMutation],
        for preparation: WorkspacePersistenceTransactionPreparation
    ) throws {
        let capture = WorkspaceArrangementCursorPersistenceCapture(
            activeArrangements: activeArrangements.compactMap(\.persistenceCapture),
            activePanes: activePanes.compactMap(\.persistenceCapture),
            activeDrawerChildren: activeDrawers.compactMap(\.persistenceCapture)
        )
        guard
            !capture.activeArrangements.isEmpty || !capture.activePanes.isEmpty
                || !capture.activeDrawerChildren.isEmpty
        else { return }
        try adapters.workspaceArrangementCursor.capturePersistencePreimages(
            capture,
            for: preparation
        )
    }
}

extension WorkspacePaneResidencyActiveArrangementMutation {
    fileprivate var persistenceCapture: WorkspaceActiveArrangementPersistenceCapture? {
        switch self {
        case .witness: nil
        case .remove(let tabID, _): .removal(tabID: tabID)
        }
    }
}

extension WorkspacePaneResidencyActivePaneMutation {
    fileprivate var persistenceCapture: WorkspaceActivePanePersistenceCapture? {
        switch self {
        case .witness: nil
        case .replace(let arrangementID, let previous, let replacement):
            paneSelectionCapture(
                arrangementID: arrangementID,
                previous: previous,
                replacement: replacement
            )
        case .remove(let arrangementID, let previous):
            paneRemovalCapture(arrangementID: arrangementID, previous: previous)
        }
    }
}

extension WorkspacePaneResidencyActiveDrawerMutation {
    fileprivate var persistenceCapture: WorkspaceActiveDrawerChildPersistenceCapture? {
        switch self {
        case .witness: nil
        case .insert(let key, _, let replacement):
            drawerInsertionCapture(key: key, replacement: replacement)
        case .replace(let key, let previous, let replacement):
            drawerSelectionCapture(key: key, previous: previous, replacement: replacement)
        case .remove(let key, let previous):
            drawerRemovalCapture(key: key, previous: previous)
        }
    }
}

private func paneSelectionCapture(
    arrangementID: UUID,
    previous: WorkspaceActivePaneCursorWitness,
    replacement: WorkspacePaneSelection
) -> WorkspaceActivePanePersistenceCapture? {
    guard case .present(let previousSelection) = previous else {
        preconditionFailure("changed active-pane selection must have a present preimage")
    }
    switch (previousSelection, replacement) {
    case (.noSelection, .noSelection): return nil
    case (.noSelection, .selected): return .insertion(arrangementID: arrangementID)
    case (.selected, .noSelection): return .removal(arrangementID: arrangementID)
    case (.selected, .selected): return .valueChange(arrangementID: arrangementID)
    }
}

private func paneRemovalCapture(
    arrangementID: UUID,
    previous: WorkspaceActivePaneCursorWitness
) -> WorkspaceActivePanePersistenceCapture? {
    guard case .present(let selection) = previous else {
        preconditionFailure("removed active-pane cursor must have a present preimage")
    }
    guard case .selected = selection else { return nil }
    return .removal(arrangementID: arrangementID)
}

private func drawerInsertionCapture(
    key: ArrangementDrawerCursorKey,
    replacement: WorkspacePaneResidencyDrawerSelection
) -> WorkspaceActiveDrawerChildPersistenceCapture? {
    guard case .selected = replacement else { return nil }
    return .insertion(key)
}

private func drawerSelectionCapture(
    key: ArrangementDrawerCursorKey,
    previous: WorkspacePaneResidencyDrawerCursorWitness,
    replacement: WorkspacePaneResidencyDrawerSelection
) -> WorkspaceActiveDrawerChildPersistenceCapture? {
    guard case .present(let previousSelection) = previous else {
        preconditionFailure("changed drawer selection must have a present preimage")
    }
    switch (previousSelection, replacement) {
    case (.noSelection, .noSelection): return nil
    case (.noSelection, .selected): return .insertion(key)
    case (.selected, .noSelection): return .removal(key)
    case (.selected, .selected): return .valueChange(key)
    }
}

private func drawerRemovalCapture(
    key: ArrangementDrawerCursorKey,
    previous: WorkspacePaneResidencyDrawerCursorWitness
) -> WorkspaceActiveDrawerChildPersistenceCapture? {
    guard case .present(let selection) = previous else {
        preconditionFailure("removed drawer cursor must have a present preimage")
    }
    guard case .selected = selection else { return nil }
    return .removal(key)
}
