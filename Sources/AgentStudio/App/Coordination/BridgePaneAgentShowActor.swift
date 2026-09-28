import AgentStudioCore
import Foundation
import os

private let bridgePaneAgentShowLogger = Logger(subsystem: "com.agentstudio", category: "BridgeAgentShow")

/// Panes owns the inbox kind and its delivery. This App seam receives only the
/// pane and canonical file after the inventory open has been applied.
protocol BridgeBackgroundOpenNotificationPosting: Sendable {
    func postBackgroundOpenNotification(
        receiver: BridgeReceiver, location: BridgeDocumentLocation
    ) async throws
}

struct BridgeUnavailableBackgroundOpenNotificationPoster: BridgeBackgroundOpenNotificationPosting {
    func postBackgroundOpenNotification(
        receiver _: BridgeReceiver, location _: BridgeDocumentLocation
    ) async throws {
        throw BridgeLinkPortFailure.unavailable
    }
}

/// The IPC layer gates take-over before it calls this port. Both methods open
/// an inventory entry; take-over then follows ordinary human activation.
actor BridgePaneAgentShowActor: PaneAgentShowPort {
    private enum OpenOutcome {
        case opened(BridgeReceiver, BridgeOpenedDocument)
        case notFound
        case paneUnavailable
    }

    private let workspaceID: UUID
    private let handler: BridgeNavigationCommandHandler
    private let preparationPort: any BridgeAgentShowPreparationPort
    private let notificationPort: any BridgeBackgroundOpenNotificationPosting

    init(
        workspaceID: UUID, handler: BridgeNavigationCommandHandler,
        preparationPort: any BridgeAgentShowPreparationPort,
        notificationPort: any BridgeBackgroundOpenNotificationPosting
    ) {
        self.workspaceID = workspaceID
        self.handler = handler
        self.preparationPort = preparationPort
        self.notificationPort = notificationPort
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
        case .opened(let resolved, let document):
            let arrival = await handler.activateFile(
                document.location, in: resolved, line: document.openedLine)
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

        let preparation: BridgeAgentShowPreparation
        do {
            preparation = try await preparationPort.prepareAgentShow(
                workspaceID: workspaceID, receiver: resolved,
                target: target, topologySnapshot: topology)
        } catch {
            throw .unavailable
        }
        switch preparation {
        case .notFound: return .notFound
        case .paneUnavailable: return .paneUnavailable
        case .prepared(let document):
            guard await handler.applyPreparedBackgroundOpen(document, in: resolved) else {
                return .paneUnavailable
            }
            guard await handler.persistedOutcome() == .applied else {
                throw .outcomeUnknown
            }
            await postBackgroundOpenNotification(receiver: resolved, location: document.location)
            return .opened(resolved, document)
        }
    }

    private func postBackgroundOpenNotification(
        receiver: BridgeReceiver, location: BridgeDocumentLocation
    ) async {
        do {
            try await notificationPort.postBackgroundOpenNotification(
                receiver: receiver, location: location)
        } catch {
            bridgePaneAgentShowLogger.error("Bridge background Open notification failed")
        }
    }
}
