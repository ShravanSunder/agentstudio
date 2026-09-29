import AgentStudioCore
import Foundation

/// The IPC layer gates take-over before it calls this port. Both methods open
/// an inventory entry; take-over then follows ordinary human activation.
actor BridgePaneAgentShowActor: PaneAgentShowPort {
    private enum OpenOutcome {
        case opened(BridgeReceiver, BridgeDocumentLocation, BridgeOpenedDocumentEntry)
        case notFound
        case paneUnavailable
    }

    private let workspaceID: UUID
    private let handler: BridgeNavigationCommandHandler
    private let preparationPort: any BridgeAgentShowPreparationPort

    init(
        workspaceID: UUID, handler: BridgeNavigationCommandHandler,
        preparationPort: any BridgeAgentShowPreparationPort
    ) {
        self.workspaceID = workspaceID
        self.handler = handler
        self.preparationPort = preparationPort
    }

    func openInBackground(
        receiver: PaneId, target: BridgeAgentShowTarget
    ) async throws(BridgeLinkPortFailure) -> BridgeAgentBackgroundOpenResult {
        switch try await open(receiver: receiver, target: target) {
        case .opened: .opened
        case .notFound: .notFound
        case .paneUnavailable: .paneUnavailable
        }
    }

    func takeOver(
        receiver: PaneId, target: BridgeAgentShowTarget
    ) async throws(BridgeLinkPortFailure) -> BridgeAgentTakeOverResult {
        switch try await open(receiver: receiver, target: target) {
        case .notFound: return .notFound
        case .paneUnavailable: return .paneUnavailable
        case .opened(let resolved, let location, let entry):
            let arrival = await handler.activateFile(
                location, in: resolved, line: entry.openedLine)
            switch arrival {
            case .applied, .appliedUnsaved: return .shown
            case .failed(.receiverUnavailable): return .paneUnavailable
            default: return .opened
            }
        }
    }

    private func open(
        receiver: PaneId, target: BridgeAgentShowTarget
    ) async throws(BridgeLinkPortFailure) -> OpenOutcome {
        let topology = await handler.captureLinkTopology(sourcePaneID: receiver.uuid)
        guard
            let resolved = BridgeReceiverResolution.receiver(
                forCommandPaneId: receiver.uuid,
                companionEntriesBySourceID: topology.companionEntriesBySourceID,
                paneStatesByID: topology.paneStatesByID
            )
        else { return .paneUnavailable }
        let currentEntries = await handler.record(for: resolved)?.openedDocuments ?? [:]

        let preparation: BridgeAgentShowPreparation
        do {
            preparation = try await preparationPort.prepareAgentShow(
                workspaceID: workspaceID, receiver: resolved,
                target: target, topologySnapshot: topology,
                currentEntries: currentEntries)
        } catch {
            throw .unavailable
        }
        switch preparation {
        case .notFound: return .notFound
        case .paneUnavailable: return .paneUnavailable
        case .prepared(let location, let entry):
            guard await handler.applyPreparedBackgroundOpen(entry, at: location, in: resolved) else {
                return .paneUnavailable
            }
            guard await handler.persistedOutcome() == .applied else {
                throw .outcomeUnknown
            }
            return .opened(resolved, location, entry)
        }
    }
}
