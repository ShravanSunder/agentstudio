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

/// The IPC layer gates take-over before it calls this port. One call opens one
/// inventory entry, then optionally follows the ordinary human activation.
actor BridgePaneAgentShowActor: PaneRevealPort {
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

    func show(
        receiver: PaneId, target: BridgeRevealFileTarget, mode: BridgeAgentShowMode
    ) async throws(BridgeLinkPortFailure) -> BridgeAgentShowResult {
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
            _ = await handler.persistedOutcome()
            await postBackgroundOpenNotification(receiver: resolved, location: document.location)
            if mode == .takeOver {
                let arrival = await handler.activateFile(
                    document.location, in: resolved, line: document.openedLine)
                switch arrival {
                case .applied, .appliedUnsaved: return .shown
                case .failed(.receiverUnavailable):
                    return .paneUnavailable
                default: break
                }
            }
            return .opened
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
