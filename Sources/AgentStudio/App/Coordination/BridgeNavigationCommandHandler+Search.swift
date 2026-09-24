import AgentStudioBridge
import AgentStudioCore
import Foundation

/// The outcome of searching a receiver's Files collection. Search is a read:
/// it never changes the receiver's navigation, membership, selection or
/// focus, and it never mounts a hidden Bridge to answer.
package enum BridgeFilesSearchRequestOutcome: Equatable, Sendable {
    case answered(BridgeFilesSearchOutcome)
    /// The receiver has no navigation record.
    case receiverUnavailable
    /// No mounted Bridge renders the receiver.
    case notMounted
    /// The narrowed member is not a member of this receiver.
    case notMember
}

@MainActor
extension BridgeNavigationCommandHandler {
    /// Search the receiver's mounted Files collection across its members and
    /// opened documents, or within the requested narrowing.
    func searchFiles(
        _ criteria: BridgeFilesSearchCriteria,
        in receiver: BridgeReceiver
    ) async -> BridgeFilesSearchRequestOutcome {
        guard let record = navigationAtom.record(for: receiver) else { return .receiverUnavailable }
        if case .member(let worktreeId) = criteria.scope, !record.containsMember(worktreeId) {
            return .notMember
        }
        guard let presentation = presentationPorts?.mountedPresentation(receiver) else {
            return .notMounted
        }
        return .answered(await presentation.searchFilesCollection(criteria))
    }
}
