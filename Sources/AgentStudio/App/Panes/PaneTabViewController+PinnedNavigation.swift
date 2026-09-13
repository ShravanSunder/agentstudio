import AgentStudioCore
import AgentStudioInfrastructure
import AgentStudioRepoExplorer
import Foundation

extension PaneTabViewController {
    func pinnedNavigationCommandAvailability(_ command: AppCommand) -> Bool? {
        switch command {
        case .focusPreviousPinnedPane, .focusNextPinnedPane:
            pinnedPanePreferences != nil && !atom(\.managementLayer).isActive
                && store.tabLayoutAtom.activeTabId != nil
        default:
            nil
        }
    }

    func canApplyPinnedNavigationTarget(_ paneID: UUID) -> Bool {
        guard let paneState = store.paneAtom.graphAtom.paneState(paneID),
            paneState.isPinned, paneState.sessionResidency.isActive,
            store.tabLayoutAtom.tabID(containingPane: paneID) != nil
        else { return false }
        return true
    }

    @discardableResult
    func submitPinnedPaneNavigation(previous: Bool) -> Task<Bool, Never> {
        dispatchGesture { [weak self] execute in
            guard let self, let pinnedPanePreferences,
                !atom(\.managementLayer).isActive
            else { return false }
            // Capture origin only after the preceding gesture has finished.
            let originPaneID: UUID?
            switch normalizedWorkspaceNavigationScopeState() {
            case .mainPane(let paneID): originPaneID = paneID
            case .emptyDrawer(let parentPaneID): originPaneID = parentPaneID
            case .drawerPane(_, let paneID): originPaneID = paneID
            }
            let clock = ContinuousClock()
            let captureStarted = clock.now
            let request = RepoExplorerPinnedPaneProjectionRequest(
                coreAtoms: CoreAtomScope.store,
                sidebarPreferences: pinnedPanePreferences,
                referenceDate: Date()
            )
            performanceTraceRecorder?.recordDuration(
                .sidebarProjection,
                duration: captureStarted.duration(to: clock.now),
                attributes: [
                    "agentstudio.performance.sidebar.surface": .string("repo"),
                    "agentstudio.performance.sidebar.query_state": .string("empty"),
                    "agentstudio.performance.sidebar.group_mode": .string("not_applicable"),
                    "agentstudio.performance.sidebar.phase": .string("pinned_capture_mainactor"),
                    "agentstudio.performance.sidebar.trigger": .string("pinned_navigation"),
                ]
            )
            let targetPaneID: UUID
            do {
                guard
                    let candidate = try await RepoExplorerPinnedPaneProjector.targetPaneID(
                        from: request, originPaneID: originPaneID, previous: previous,
                        performanceTraceRecorder: performanceTraceRecorder
                    )
                else { return false }
                targetPaneID = candidate
            } catch {
                return false
            }
            // Current scalar owners validate the exact destination after projection.
            guard !Task.isCancelled, !atom(\.managementLayer).isActive,
                canApplyPinnedNavigationTarget(targetPaneID)
            else { return false }
            return await prepareAndApplyTargetFocus(paneId: targetPaneID, execute: execute)
        }
    }
}
