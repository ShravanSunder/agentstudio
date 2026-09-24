import AgentStudioCore
import AgentStudioProgrammaticControl
import Foundation

/// Receiver navigation and membership commands. Every entry resolves the
/// receiving Bridge from an explicit pane (the IPC target or the focused pane)
/// and hands one typed request to the navigation handler; no host decides the
/// effect itself.
extension PaneTabViewController {
    static let bridgeNavigationCommands: Set<AppCommand> = [
        .activateBridgeFile, .activateBridgeReview, .closeBridgeFile,
        .addBridgeWorktree, .selectBridgeWorktree, .removeBridgeWorktree, .searchBridgeFiles,
    ]

    /// The request a worktree-addressed navigation command makes.
    static func bridgeNavigationRequest(
        for command: AppCommand,
        worktreeId: UUID
    ) -> BridgeNavigationRequest? {
        switch command {
        case .activateBridgeReview: .activateReview(worktreeId: worktreeId)
        case .addBridgeWorktree: .addWorktree(worktreeId: worktreeId)
        case .selectBridgeWorktree: .selectReviewWorktree(worktreeId: worktreeId)
        case .removeBridgeWorktree: .removeWorktree(worktreeId: worktreeId)
        default: nil
        }
    }

    /// The request a document-addressed navigation command makes.
    static func bridgeNavigationRequest(
        for command: AppCommand,
        absolutePath: String
    ) -> BridgeNavigationRequest? {
        switch command {
        case .activateBridgeFile: .activateFile(absolutePath: absolutePath)
        case .closeBridgeFile: .closeFile(absolutePath: absolutePath)
        default: nil
        }
    }

    // MARK: - IPC

    func executeBridgeNavigationIPC(
        _ request: BridgeNavigationRequest,
        targetPaneSelector: IPCPaneSelector,
        ownPaneAssertion: WorkspaceOwnPaneAssertion?
    ) async -> AppCommandExecutionOutcome {
        guard let paneId = AppCommandTypedIPCPane.canonicalId(targetPaneSelector) else {
            return .unavailable(.noApplicableTarget)
        }
        return await performBridgeNavigation(request, paneId: paneId, ownPaneAssertion: ownPaneAssertion)
    }

    /// A pane agent's own pane is re-checked in the same main-actor step that
    /// hands the request to the navigation owner.
    private func performBridgeNavigation(
        _ request: BridgeNavigationRequest,
        paneId: UUID,
        ownPaneAssertion: WorkspaceOwnPaneAssertion?
    ) async -> AppCommandExecutionOutcome {
        if let ownPaneAssertion, !store.ownPaneAssertionHolds(ownPaneAssertion, for: paneId) {
            return .outsideOwnPane
        }
        return await executor.performBridgeNavigation(request, forPaneId: paneId).commandExecutionOutcome
    }

    /// Pane-addressed Bridge commands over IPC.
    func executeBridgePaneCommand(
        _ command: AppCommand,
        paneId: UUID,
        ownPaneAssertion: WorkspaceOwnPaneAssertion?
    ) async -> AppCommandExecutionOutcome {
        switch command {
        case .reloadBridgeWebView:
            guard let mountView = resolvedBridgeCommandMountView(paneId: paneId),
                mountView.controller.reloadWebView()
            else { return .stateUnavailable }
            // The webview reload is initiated here and completes in WebKit, so
            // the receipt is acceptance rather than application.
            return .accepted(operationId: nil)
        case .searchBridgeFiles:
            // B2: the Files search affordance; agents read results through `bridge.files.search`.
            return await performBridgeNavigation(.showFiles, paneId: paneId, ownPaneAssertion: ownPaneAssertion)
        default:
            return .unsupportedCommand
        }
    }

    // MARK: - Interactive

    /// Contextual invocation acts on the focused pane's receiver. File
    /// activation without a document returns to Files; closing without a
    /// document closes the one Files displays. Searching shows Files; the
    /// search affordance itself arrives in B2.
    func executeContextualBridgeNavigationCommand(_ command: AppCommand) -> Bool {
        guard Self.bridgeNavigationCommands.contains(command), let paneId = focusedBridgeCommandPaneId() else {
            return false
        }
        switch command {
        case .activateBridgeFile, .searchBridgeFiles:
            submitBridgeNavigation(.showFiles, paneId: paneId)
            return true
        case .closeBridgeFile:
            guard
                let receiver = executor.bridgeReceiver(forCommandPaneId: paneId),
                let displayed = executor.bridgeNavigationRecord(for: receiver)?.selectedFilesDocument
            else { return false }
            submitBridgeNavigation(.closeFile(absolutePath: displayed.canonicalPath), paneId: paneId)
            return true
        default:
            return false
        }
    }

    /// Targeted invocation names the member worktree; the receiver is the
    /// focused pane's.
    func executeTargetedBridgeNavigationCommand(_ command: AppCommand, worktreeId: UUID) -> Bool {
        guard let request = Self.bridgeNavigationRequest(for: command, worktreeId: worktreeId),
            let paneId = focusedBridgeCommandPaneId()
        else { return false }
        submitBridgeNavigation(request, paneId: paneId)
        return true
    }

    private func submitBridgeNavigation(_ request: BridgeNavigationRequest, paneId: UUID) {
        Task { [executor] in
            _ = await executor.performBridgeNavigation(request, forPaneId: paneId)
        }
    }
}
