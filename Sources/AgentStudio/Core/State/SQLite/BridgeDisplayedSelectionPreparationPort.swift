import Foundation

/// Prepares a displayed Files receipt from copied receiver and topology facts.
/// The datastore actor is the sole product mint point for new sort keys.
package protocol BridgeDisplayedSelectionPreparationPort: Sendable {
    func prepareDisplayedFilesSelection(
        receiver: BridgeReceiver, location: BridgeDocumentLocation,
        memberWorktreeID: UUID?, memberRelativePath: String?,
        record: BridgeNavigationRecord, topology: BridgeReceiverTopologySnapshot
    ) async -> BridgeNavigationRecord?
}

extension WorkspaceSQLiteDatastoreActor: BridgeDisplayedSelectionPreparationPort {}
