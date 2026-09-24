import AgentStudioBridge
import AgentStudioCore
import Foundation

@MainActor
extension WorkspaceSurfaceCoordinator {
    /// How the navigation handler reaches mounted Bridges and persistence.
    func bridgeReceiverPresentationPorts() -> BridgeReceiverPresentationPorts {
        BridgeReceiverPresentationPorts(
            mountedPresentation: { [weak self] receiver in
                self?.mountedBridgeController(for: receiver)
            },
            replaceReviewSource: { [weak self] receiver, surface in
                self?.replaceBridgeReviewSource(for: receiver, showing: surface) ?? false
            },
            knownCWDWorktreeId: { [weak self] receiver in
                self?.knownCWDWorktreeId(for: receiver)
            },
            refreshFilesSource: { [weak self] receiver in
                guard let self,
                    let controller = self.mountedBridgeController(for: receiver),
                    let files = self.bridgeNavigationCommandHandler.filesBinding(for: receiver)
                else { return }
                controller.enqueueFilesSourceUpdate(files)
            },
            persistNavigation: { [weak self] in
                await self?.store.flushAsync().succeeded ?? false
            }
        )
    }

    /// Run one navigation command against the receiver `paneId` addresses.
    /// A terminal receiver's first record is seeded from its current known
    /// worktree, exactly as presenting its companion would seed it.
    func performBridgeNavigation(
        _ request: BridgeNavigationRequest,
        forPaneId paneId: UUID
    ) async -> BridgeNavigationCommandOutcome {
        guard let receiver = bridgeReceiver(forCommandPaneId: paneId) else {
            return .failed(.receiverUnavailable)
        }
        if receiver.kind == .terminalAssociated {
            let knownCWD = knownCWDWorktreeId(for: receiver)
            bridgeNavigationCommandHandler.ensureRecord(for: receiver, seedingKnownWorktreeId: knownCWD)
            bridgeNavigationCommandHandler.applyKnownCWDAssociation(knownCWD, forTerminalPane: receiver.paneId)
        }
        return await bridgeNavigationCommandHandler.perform(request, in: receiver)
    }

    /// The controller that renders `receiver`: its Zoom companion for a
    /// terminal receiver, the pane's own controller for a standalone Bridge.
    func mountedBridgeController(for receiver: BridgeReceiver) -> BridgePaneController? {
        let paneId: UUID
        switch receiver.kind {
        case .terminalAssociated:
            guard let companion = store.panePresentationAtom.zoomCompanion(forSourcePane: receiver.paneId)
            else { return nil }
            paneId = companion.companionPaneId
        case .standaloneBridge:
            paneId = receiver.paneId
        }
        return viewRegistry.allBridgeViews[paneId]?.controller
    }

    /// Route every displayed File selection of a controller to its receiver's
    /// navigation record.
    func bindDisplayedFilesSelection(of controller: BridgePaneController, to receiver: BridgeReceiver) {
        controller.onFilesSelectionDisplayed = { [weak self] selection in
            self?.bridgeNavigationCommandHandler.recordDisplayedFilesSelection(selection, for: receiver)
        }
    }

    /// Replace the receiver's controller after its Review member changed. The
    /// replacement is built from the navigation record and asked for Review;
    /// the caller has already flushed the old page's editors.
    private func replaceBridgeReviewSource(
        for receiver: BridgeReceiver,
        showing surface: BridgeProductSurface
    ) -> Bool {
        switch receiver.kind {
        case .terminalAssociated:
            guard let companion = store.panePresentationAtom.zoomCompanion(forSourcePane: receiver.paneId)
            else { return false }
            let presentation = reconcileZoomCompanion(
                sourcePaneId: receiver.paneId,
                owningTabId: companion.owningTabId,
                viewerSurfaceRequest: { [weak self] _, companionPaneId in
                    self?.requestBridgePaneSurface(surface, paneId: companionPaneId) ?? false
                }
            )
            return presentation.companionPaneId != nil
        case .standaloneBridge:
            guard viewRegistry.allBridgeViews[receiver.paneId] != nil else { return false }
            executeRepair(.recreateSurface(paneId: receiver.paneId))
            return requestBridgePaneSurface(surface, paneId: receiver.paneId)
        }
    }

    /// The owner terminal's current known worktree association.
    func knownCWDWorktreeId(for receiver: BridgeReceiver) -> UUID? {
        guard receiver.kind == .terminalAssociated,
            let terminal = store.paneAtom.pane(receiver.paneId)
        else { return nil }
        return store.repositoryTopologyAtom.validatedAssociation(
            repoId: terminal.repoId,
            worktreeId: terminal.worktreeId
        )?.worktree.id
    }

    /// The receiver a command addressed to `paneId` acts on. A terminal is its
    /// own receiver and a standalone Bridge pane is itself; a Zoom companion
    /// renders its terminal's receiver; a drawer child maps to its owner's
    /// receiver, never to a receiver of its own.
    func bridgeReceiver(forCommandPaneId paneId: UUID) -> BridgeReceiver? {
        BridgeReceiverResolution.receiver(
            forCommandPaneId: paneId,
            zoomSourcePaneIdByCompanionPaneId: Dictionary(
                store.panePresentationAtom.zoomCompanionsBySourcePaneId.map { ($0.value.companionPaneId, $0.key) },
                uniquingKeysWith: { first, _ in first }
            ),
            pane: { [store] in store.paneAtom.pane($0) }
        )
    }
}
