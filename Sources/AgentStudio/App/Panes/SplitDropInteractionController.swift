import Foundation

struct SplitDropCommitDestination: Equatable {
    let paneId: UUID
    let drawerParentPaneId: UUID?
}

@MainActor
final class SplitDropInteractionController {
    private let store: WorkspaceStore
    private let visiblePaneIdsProvider: @MainActor (Tab) -> [UUID]
    private let drawerParentByPaneIdProvider: @MainActor () -> [UUID: UUID]
    private let drawerLayoutByParentPaneIdProvider: @MainActor () -> [UUID: DrawerGridLayout]
    private let dispatchAction: @MainActor (PaneActionCommand) -> Void

    init(
        store: WorkspaceStore,
        visiblePaneIdsProvider: @escaping @MainActor (Tab) -> [UUID],
        drawerParentByPaneIdProvider: @escaping @MainActor () -> [UUID: UUID],
        drawerLayoutByParentPaneIdProvider: @escaping @MainActor () -> [UUID: DrawerGridLayout],
        dispatchAction: @escaping @MainActor (PaneActionCommand) -> Void
    ) {
        self.store = store
        self.visiblePaneIdsProvider = visiblePaneIdsProvider
        self.drawerParentByPaneIdProvider = drawerParentByPaneIdProvider
        self.drawerLayoutByParentPaneIdProvider = drawerLayoutByParentPaneIdProvider
        self.dispatchAction = dispatchAction
    }

    func shouldHandleSplitDragPayload(_ payload: SplitDropPayload) -> Bool {
        switch payload.kind {
        case .existingPane(let sourcePaneId, _):
            guard let sourcePane = store.paneAtom.pane(sourcePaneId) else { return false }
            return sourcePane.parentPaneId == nil
        case .newTerminal:
            return true
        case .existingTab:
            return false
        }
    }

    func shouldAcceptDrop(
        payload: SplitDropPayload,
        destPaneId: UUID,
        zone: DropZoneSide,
        sizingMode: DropSizingMode
    ) -> Bool {
        guard shouldHandleSplitDragPayload(payload) else {
            return false
        }
        let snapshot = dragDropSnapshot()
        return Self.splitDropCommitPlan(
            payload: payload,
            destination: SplitDropCommitDestination(
                paneId: destPaneId,
                drawerParentPaneId: store.paneAtom.pane(destPaneId)?.parentPaneId
            ),
            zone: zone,
            sizingMode: sizingMode,
            activeTabId: store.tabLayoutAtom.activeTabId,
            state: snapshot
        ) != nil
    }

    func handleDrop(
        payload: SplitDropPayload,
        destPaneId: UUID,
        zone: DropZoneSide,
        sizingMode: DropSizingMode
    ) {
        guard shouldHandleSplitDragPayload(payload) else {
            return
        }
        let snapshot = dragDropSnapshot()
        guard
            let plan = Self.splitDropCommitPlan(
                payload: payload,
                destination: SplitDropCommitDestination(
                    paneId: destPaneId,
                    drawerParentPaneId: store.paneAtom.pane(destPaneId)?.parentPaneId
                ),
                zone: zone,
                sizingMode: sizingMode,
                activeTabId: store.tabLayoutAtom.activeTabId,
                state: snapshot
            )
        else {
            return
        }
        executeDropCommitPlan(plan)
    }

    private func dragDropSnapshot() -> ActionStateSnapshot {
        WorkspaceCommandResolver.snapshot(
            from: store.tabLayoutAtom.tabs,
            activeTabId: store.tabLayoutAtom.activeTabId,
            isManagementLayerActive: atom(\.managementLayer).isActive,
            knownWorktreeIds: Set(store.repositoryTopologyAtom.repos.flatMap(\.worktrees).map(\.id)),
            drawerParentByPaneId: drawerParentByPaneIdProvider(),
            drawerLayoutByParentPaneId: drawerLayoutByParentPaneIdProvider(),
            visiblePaneIds: visiblePaneIdsProvider
        )
    }

    private func executeDropCommitPlan(_ plan: DropCommitPlan) {
        switch plan {
        case .paneAction(let action):
            dispatchAction(action)
        case .moveTab(let tabId, let toIndex):
            dispatchAction(.reorderTab(tabId: tabId, newIndex: toIndex))
        case .extractPaneToTabThenMove(let paneId, let sourceTabId, let toIndex):
            let tabCountBefore = store.tabLayoutAtom.tabs.count
            dispatchAction(.extractPaneToTab(tabId: sourceTabId, paneId: paneId))
            guard
                store.tabLayoutAtom.tabs.count == tabCountBefore + 1,
                let extractedTabId = store.tabLayoutAtom.activeTabId
            else {
                return
            }
            dispatchAction(.reorderTab(tabId: extractedTabId, newIndex: toIndex))
        }
    }

    nonisolated static func splitDropCommitPlan(
        payload: SplitDropPayload,
        destination: SplitDropCommitDestination,
        zone: DropZoneSide,
        sizingMode: DropSizingMode,
        activeTabId: UUID?,
        state: ActionStateSnapshot
    ) -> DropCommitPlan? {
        guard let activeTabId else {
            return nil
        }
        let paneDropDestination = PaneDropDestination.split(
            targetPaneId: destination.paneId,
            targetTabId: activeTabId,
            direction: splitDirection(for: zone),
            sizingMode: sizingMode,
            targetDrawerParentPaneId: destination.drawerParentPaneId
        )
        let decision = PaneDropPlanner.previewDecision(
            payload: payload,
            destination: paneDropDestination,
            state: state
        )
        if case .eligible(let plan) = decision {
            return plan
        }
        return nil
    }

    nonisolated static func splitDirection(for zone: DropZoneSide) -> SplitNewDirection {
        switch zone {
        case .left:
            return .left
        case .right:
            return .right
        }
    }
}
