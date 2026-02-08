import Foundation
import os.log

private let executorLogger = Logger(subsystem: "com.agentstudio", category: "ActionExecutor")

/// Executes validated PaneActions by coordinating WorkspaceStore,
/// ViewRegistry, and surface lifecycle.
///
/// This is the action dispatch hub — replaces the giant switch statement
/// in TerminalTabViewController.
@MainActor
final class ActionExecutor {
    private let store: WorkspaceStore
    private let viewRegistry: ViewRegistry

    /// Called when the executor needs to create a new terminal view.
    /// Injected by the view controller layer.
    var onCreateView: ((TerminalSession) -> AgentStudioTerminalView)?

    /// Called when a view should be torn down.
    var onTeardownView: ((UUID) -> Void)?

    /// Called when a tab is closed (for undo stack management).
    var onTabClosed: ((WorkspaceStore.CloseSnapshot) -> Void)?

    init(store: WorkspaceStore, viewRegistry: ViewRegistry) {
        self.store = store
        self.viewRegistry = viewRegistry
    }

    /// Execute a resolved PaneAction.
    func execute(_ action: PaneAction) {
        executorLogger.debug("Executing: \(String(describing: action))")

        switch action {
        case .selectTab(let tabId):
            store.setActiveTab(tabId)

        case .closeTab(let tabId):
            executeCloseTab(tabId)

        case .breakUpTab(let tabId):
            executeBreakUpTab(tabId)

        case .closePane(let tabId, let paneId):
            executeClosePane(tabId: tabId, sessionId: paneId)

        case .extractPaneToTab(let tabId, let paneId):
            _ = store.extractSession(paneId, fromTab: tabId)

        case .focusPane(let tabId, let paneId):
            store.setActiveSession(paneId, inTab: tabId)

        case .insertPane(let source, let targetTabId, let targetPaneId, let direction):
            executeInsertPane(
                source: source,
                targetTabId: targetTabId,
                targetPaneId: targetPaneId,
                direction: direction
            )

        case .resizePane(let tabId, let splitId, let ratio):
            store.resizePane(tabId: tabId, splitId: splitId, ratio: ratio)

        case .equalizePanes(let tabId):
            store.equalizePanes(tabId: tabId)

        case .mergeTab(let sourceTabId, let targetTabId, let targetPaneId, let direction):
            executeMergeTab(
                sourceTabId: sourceTabId,
                targetTabId: targetTabId,
                targetPaneId: targetPaneId,
                direction: direction
            )
        }
    }

    // MARK: - Private Execution

    private func executeCloseTab(_ tabId: UUID) {
        // Snapshot for undo before closing
        if let snapshot = store.snapshotForClose(tabId: tabId) {
            onTabClosed?(snapshot)
        }

        // Teardown views for all sessions in this tab
        if let tab = store.tab(tabId) {
            for sessionId in tab.sessionIds {
                onTeardownView?(sessionId)
                viewRegistry.unregister(sessionId)
            }
        }

        store.removeTab(tabId)
    }

    private func executeBreakUpTab(_ tabId: UUID) {
        let newTabs = store.breakUpTab(tabId)
        if newTabs.isEmpty {
            executorLogger.debug("breakUpTab: tab has single session, no-op")
        }
    }

    private func executeClosePane(tabId: UUID, sessionId: UUID) {
        onTeardownView?(sessionId)
        viewRegistry.unregister(sessionId)
        store.removeSessionFromLayout(sessionId, inTab: tabId)
    }

    private func executeInsertPane(
        source: PaneSource,
        targetTabId: UUID,
        targetPaneId: UUID,
        direction: SplitNewDirection
    ) {
        let layoutDirection = bridgeDirection(direction)
        let position: Layout.Position = (direction == .left || direction == .up) ? .before : .after

        switch source {
        case .existingPane(let paneId, let sourceTabId):
            // Always remove from source layout first to prevent duplicate IDs.
            // This handles both same-tab reposition and cross-tab moves.
            store.removeSessionFromLayout(paneId, inTab: sourceTabId)
            store.insertSession(
                paneId, inTab: targetTabId, at: targetPaneId,
                direction: layoutDirection, position: position
            )

        case .newTerminal:
            // Create a new session and insert it
            let session = store.createSession(
                source: .floating(workingDirectory: nil, title: nil)
            )
            if let view = onCreateView?(session) {
                viewRegistry.register(view, for: session.id)
            }
            store.insertSession(
                session.id, inTab: targetTabId, at: targetPaneId,
                direction: layoutDirection, position: position
            )
        }
    }

    private func executeMergeTab(
        sourceTabId: UUID,
        targetTabId: UUID,
        targetPaneId: UUID,
        direction: SplitNewDirection
    ) {
        let layoutDirection = bridgeDirection(direction)
        let position: Layout.Position = (direction == .left || direction == .up) ? .before : .after

        store.mergeTab(
            sourceId: sourceTabId,
            intoTarget: targetTabId,
            at: targetPaneId,
            direction: layoutDirection,
            position: position
        )
    }

    /// Bridge SplitNewDirection → Layout.SplitDirection.
    private func bridgeDirection(_ direction: SplitNewDirection) -> Layout.SplitDirection {
        switch direction {
        case .left, .right: return .horizontal
        case .up, .down: return .vertical
        }
    }
}
