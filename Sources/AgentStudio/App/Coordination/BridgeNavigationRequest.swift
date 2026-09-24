import AgentStudioBridge
import AgentStudioCore
import Foundation

/// One receiver navigation or membership command, already resolved to typed
/// identities. Keyboard, command bar, IPC and tests all reach the navigation
/// handler through this value.
enum BridgeNavigationRequest: Equatable, Sendable {
    /// Show an exact document of the receiving collection in Files.
    case activateFile(absolutePath: String)
    /// Return to Files with its retained document.
    case showFiles
    /// Remove an opened document from the receiver's inventory.
    case closeFile(absolutePath: String)
    // B2: an explicit comparison and file for the Review activation.
    /// Show one member's Review with its retained comparison.
    case activateReview(worktreeId: UUID)
    case addWorktree(worktreeId: UUID)
    /// Select the member Review reads; Files is never narrowed.
    case selectReviewWorktree(worktreeId: UUID)
    case removeWorktree(worktreeId: UUID)
}

@MainActor
extension BridgeNavigationCommandHandler {
    func perform(
        _ request: BridgeNavigationRequest,
        in receiver: BridgeReceiver
    ) async -> BridgeNavigationCommandOutcome {
        switch request {
        case .activateFile(let absolutePath):
            guard
                let location = await BridgeDocumentLocationCanonicalizer.canonicalLocation(
                    ofAbsolutePath: absolutePath
                )
            else { return .failed(.notListed) }
            return await activateFile(location, in: receiver)
        case .showFiles:
            return await showFiles(in: receiver)
        case .closeFile(let absolutePath):
            guard
                let location = await BridgeDocumentLocationCanonicalizer.canonicalLocation(
                    ofAbsolutePath: absolutePath
                )
            else { return .failed(.notInInventory) }
            return await closeFile(location, in: receiver)
        case .activateReview(let worktreeId):
            return await activateReview(of: worktreeId, in: receiver)
        case .addWorktree(let worktreeId):
            return await addWorktree(worktreeId, to: receiver)
        case .selectReviewWorktree(let worktreeId):
            return await selectReviewWorktree(worktreeId, in: receiver)
        case .removeWorktree(let worktreeId):
            return await removeWorktree(worktreeId, from: receiver)
        }
    }
}

extension BridgeNavigationCommandOutcome {
    /// The IPC projection of a navigation outcome: a visible effect is applied
    /// even when its remembered state is still unsaved; refusals and failures
    /// changed nothing.
    var commandExecutionOutcome: AppCommandExecutionOutcome {
        switch self {
        case .applied, .appliedUnsaved:
            .applied
        case .refusedUnsavedDraft, .refusedProtected, .superseded:
            .unavailable(.stateUnavailable)
        case .failed(let failure):
            switch failure {
            case .receiverUnavailable, .notMounted, .pageUnavailable:
                .unavailable(.noApplicableTarget)
            case .notInInventory, .notListed, .notMember, .worktreeUnavailable, .documentUnavailable:
                .unavailable(.stateUnavailable)
            }
        }
    }
}
