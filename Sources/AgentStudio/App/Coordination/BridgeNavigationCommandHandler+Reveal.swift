import AgentStudioCore
import Foundation

@MainActor
extension BridgeNavigationCommandHandler {
    /// Admission linearizes after repository preflight. The ticket is the
    /// constant-time Q9 ordering step; validation remains off MainActor.
    func nextRevealAdmissionTicket() -> Int { writeSequencer.nextTicket().value }

    /// Trusted App composition supplies the bound agent identity. The request
    /// target never nominates its contributor.
    func admitAgentReveal(
        _ target: BridgeRevealFileTarget, in receiver: BridgeReceiver,
        requestedBy: BridgeLinkContributor
    ) async throws -> BridgeRevealAdmissionResult {
        guard let paneRevealActor else { throw BridgeLinkPortFailure.unavailable }
        return try await paneRevealActor.admitAgentReveal(
            receiver: PaneId(existingUUID: receiver.paneId), target: target,
            requestedBy: requestedBy
        )
    }

    func awaitAgentRevealSettlement(
        _ operationID: UUID, in receiver: BridgeReceiver
    ) async throws -> BridgeAgentRevealSettlement {
        guard let paneRevealActor else { throw BridgeLinkPortFailure.unavailable }
        return try await paneRevealActor.awaitAgentRevealSettlement(
            receiver: PaneId(existingUUID: receiver.paneId), operationId: operationID
        )
    }

    func retainedOpenViewItems(in receiver: BridgeReceiver) async -> [BridgeRetainedOpenViewItem] {
        guard let paneRevealActor else { return [] }
        return await paneRevealActor.retainedOpenViewItems(
            receiver: PaneId(existingUUID: receiver.paneId)
        )
    }
}
