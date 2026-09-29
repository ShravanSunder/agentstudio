import Foundation

/// The Files input of one Bridge controller: the receiver's known member
/// worktrees in collection order plus its opened documents, published under
/// one collection token that stays stable for the receiver. App derives it from
/// the receiver's navigation record; membership changes update the mounted
/// collection in place.
package struct BridgeFilesSourceBinding: Hashable, Sendable {
    package let collectionToken: String
    package var members: [Worktree]
    package var openedDocuments: [BridgeDocumentLocation]

    package init(collectionToken: String, members: [Worktree], openedDocuments: [BridgeDocumentLocation]) {
        self.collectionToken = collectionToken
        self.members = members
        self.openedDocuments = openedDocuments
    }

    /// The collection token of a receiver: stable across companion
    /// replacement, restart and membership changes.
    package static func collectionToken(forReceiverPaneId paneId: UUID) -> String {
        "receiver-\(paneId.uuidString.lowercased())"
    }
}
