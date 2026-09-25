import AgentStudioCore
import Foundation

enum PaneFocusAppControlError: Error, Equatable, Sendable {
    case targetNotFound
    case validationRejected
}

@MainActor
protocol PaneFocusAppControlling: Sendable {
    func focusPane(_ paneId: UUID) async throws
}

/// The part of the pane tab controller the IPC focus owner needs: whether it
/// still takes commands, whether a pane has a native host, and the submitted
/// focus operation whose task yields the committed outcome.
@MainActor
protocol TargetedPaneFocusSubmitting: AnyObject {
    var acceptsIPCCommands: Bool { get }
    func hasNativePaneHost(_ paneId: UUID) -> Bool
    func submitTargetedPaneFocus(_ paneId: UUID) -> Task<Bool, Never>
}

extension PaneTabViewController: TargetedPaneFocusSubmitting {}

@MainActor
final class PaneTabViewControllerPaneFocusAppControl: PaneFocusAppControlling, @unchecked Sendable {
    private let targetedPaneFocusSubmitter: any TargetedPaneFocusSubmitting
    private let workspaceStore: WorkspaceStore

    init(targetedPaneFocusSubmitter: any TargetedPaneFocusSubmitting, workspaceStore: WorkspaceStore) {
        self.targetedPaneFocusSubmitter = targetedPaneFocusSubmitter
        self.workspaceStore = workspaceStore
    }

    func focusPane(_ paneId: UUID) async throws {
        guard targetedPaneFocusSubmitter.acceptsIPCCommands else {
            throw PaneFocusAppControlError.validationRejected
        }
        let snapshot = workspaceStore.programmaticControlSnapshot()
        guard let pane = snapshot.panes.first(where: { $0.id == paneId }) else {
            throw PaneFocusAppControlError.targetNotFound
        }
        guard pane.tabId != nil else {
            throw PaneFocusAppControlError.validationRejected
        }
        guard targetedPaneFocusSubmitter.hasNativePaneHost(paneId) else {
            throw PaneFocusAppControlError.validationRejected
        }

        guard await targetedPaneFocusSubmitter.submitTargetedPaneFocus(paneId).value else {
            throw PaneFocusAppControlError.validationRejected
        }
    }
}
