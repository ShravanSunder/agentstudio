import AgentStudioCore
import Foundation

@MainActor
extension BridgeNavigationCommandHandler {
    /// The prepared file is validated off-main. The inventory write follows
    /// the same atom-first and Q9 save shape as human close and selection.
    func applyPreparedBackgroundOpen(
        _ document: BridgeOpenedDocument, in receiver: BridgeReceiver
    ) -> Bool {
        let knownCWD = presentationPorts?.knownCWDWorktreeId(receiver)
        guard let existing = ensureRecord(for: receiver, seedingKnownWorktreeId: knownCWD) else {
            return false
        }
        navigationAtom.setRecord(
            BridgeNavigationRules.openingInBackground(document, in: existing),
            for: receiver)
        presentationPorts?.refreshFilesSource(receiver)
        return true
    }
}
