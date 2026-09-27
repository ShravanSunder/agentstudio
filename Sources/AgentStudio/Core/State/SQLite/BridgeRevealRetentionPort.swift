import Foundation

/// Read-only admission happens before an operation ID is returned. The later
/// durable effect revalidates the same facts and may settle differently.
package enum BridgeRevealAdmissionPreflight: Equatable, Sendable {
    case eligible(location: BridgeDocumentLocation)
    case unsupportedTarget
    case staleOwner
    case staleReceiver
}

package enum BridgeRevealRetentionResult: Hashable, Sendable {
    case retained(BridgeRetainedOpenViewItem)
    case cleared
    case alreadyAbsent
    case unsupportedTarget
    case staleOwner
    case staleReceiver
    case superseded
}

package typealias BridgeRevealRetentionReceipt = BridgeLinkCommitReceipt<BridgeRevealRetentionResult>

/// Native Open view storage. Only dedicated retain/clear commits mutate the
/// retained metadata; ordinary UI saves may change inventory state only.
package protocol BridgeRevealRetentionPort: Sendable {
    func previewAgentReveal(
        workspaceID: UUID, receiver: BridgeReceiver,
        target: BridgeRevealFileTarget,
        topologySnapshot: BridgeReceiverTopologySnapshot
    ) async throws -> BridgeRevealAdmissionPreflight

    func retainAgentReveal(
        context: BridgeLinkMutationContext, target: BridgeRevealFileTarget,
        requestedBy: BridgeLinkContributor, retainedAt: Date
    ) async throws -> BridgeRevealRetentionReceipt

    func clearRetainedOpenViewItem(
        context: BridgeLinkMutationContext, location: BridgeDocumentLocation
    ) async throws -> BridgeRevealRetentionReceipt

    func retainedOpenViewItems(
        workspaceID: UUID, receiver: BridgeReceiver
    ) async throws -> [BridgeRetainedOpenViewItem]
}

extension WorkspaceSQLiteDatastoreActor: BridgeRevealRetentionPort {}
