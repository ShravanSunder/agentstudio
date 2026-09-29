import Foundation

package enum BridgeAgentShowPreparation: Sendable {
    case prepared(location: BridgeDocumentLocation, entry: BridgeOpenedDocumentEntry)
    case notFound
    case paneUnavailable
}

/// Resolves the agent's target and checks its file before the UI inventory is
/// changed. The repository actor owns admission; this port never writes rows.
package protocol BridgeAgentShowPreparationPort: Sendable {
    func prepareAgentShow(
        workspaceID: UUID, receiver: BridgeReceiver, target: BridgeAgentShowTarget,
        topologySnapshot: BridgeReceiverTopologySnapshot,
        currentEntries: [BridgeDocumentLocation: BridgeOpenedDocumentEntry]
    ) async throws -> BridgeAgentShowPreparation
}

extension WorkspaceSQLiteDatastoreActor: BridgeAgentShowPreparationPort {}
