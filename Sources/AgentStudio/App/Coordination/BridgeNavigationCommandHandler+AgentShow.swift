import AgentStudioCore
import Foundation

@MainActor
extension BridgeNavigationCommandHandler {
    /// The prepared file is validated off-main. The inventory write follows
    /// the same atom-first and Q9 save shape as human close and selection.
    func applyPreparedBackgroundOpen(
        _ entry: BridgeOpenedDocumentEntry, at location: BridgeDocumentLocation,
        in receiver: BridgeReceiver
    ) -> Bool {
        let knownCWD = presentationPorts?.knownCWDWorktreeId(receiver)
        guard ensureRecord(for: receiver, seedingKnownWorktreeId: knownCWD) != nil else {
            return false
        }
        navigationAtom.assignOpenedDocument(entry, at: location, for: receiver)
        presentationPorts?.refreshFilesSource(receiver)
        return true
    }
}
