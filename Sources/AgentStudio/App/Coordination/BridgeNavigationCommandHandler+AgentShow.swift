import AgentStudioCore
import Foundation

@MainActor
extension BridgeNavigationCommandHandler {
    /// The prepared file is validated off-main. This uses the same atom-first
    /// inventory write and Q9 save path as human background opening.
    func applyPreparedBackgroundOpen(
        _ document: BridgeOpenedDocument, in receiver: BridgeReceiver
    ) -> Bool {
        guard let existing = ensureRecord(for: receiver, seedingKnownWorktreeId: nil) else {
            return false
        }
        navigationAtom.setRecord(
            BridgeNavigationRules.openingInBackground(document, in: existing),
            for: receiver)
        presentationPorts?.refreshFilesSource(receiver)
        return true
    }
}
