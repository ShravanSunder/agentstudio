import Foundation

enum TabArrangementMutationRules {
    static func createArrangement(
        name: String,
        from state: TabArrangementState
    ) -> PaneArrangement? {
        let activeArrangement = activeArrangement(in: state)
        let orderedPaneIds =
            activeArrangement.layout.paneIds
            + state.allPaneIds.filter { !activeArrangement.layout.contains($0) }
        guard !orderedPaneIds.isEmpty else { return nil }
        let arrangementLayout = Layout.autoTiled(orderedPaneIds)
        let arrangementMinimizedPaneIds = activeArrangement.minimizedPaneIds.intersection(Set(orderedPaneIds))

        return PaneArrangement(
            name: name,
            isDefault: false,
            layout: arrangementLayout,
            minimizedPaneIds: arrangementMinimizedPaneIds,
            showsMinimizedPanes: activeArrangement.showsMinimizedPanes,
            activePaneId: TabArrangementSelectionRules.fallbackActivePaneId(
                currentActivePaneId: activeArrangement.activePaneId,
                in: PaneArrangement(
                    name: name,
                    isDefault: false,
                    layout: arrangementLayout,
                    minimizedPaneIds: arrangementMinimizedPaneIds,
                    showsMinimizedPanes: activeArrangement.showsMinimizedPanes
                )
            ),
            drawerViews: activeArrangement.drawerViews
        )
    }

    static func removingArrangement(_ arrangementId: UUID, from state: TabArrangementState) -> TabArrangementState {
        guard let arrangementIndex = state.arrangements.firstIndex(where: { $0.id == arrangementId }) else {
            return state
        }
        guard !state.arrangements[arrangementIndex].isDefault else {
            return state
        }

        var updated = state
        if updated.activeArrangementId == arrangementId {
            let defaultArrangement = defaultArrangement(in: updated)
            updated.activeArrangementId = defaultArrangement.id
        }
        updated.arrangements.remove(at: arrangementIndex)
        return updated
    }

    static func removingUserPane(
        _ paneId: UUID,
        removingDrawerId drawerId: UUID? = nil,
        from arrangements: [PaneArrangement]
    ) -> [PaneArrangement] {
        arrangements.map { arrangement in
            var updated = arrangement
            if let drawerId {
                updated.drawerViews.removeValue(forKey: drawerId)
            }
            guard updated.layout.contains(paneId) else {
                updated.minimizedPaneIds.remove(paneId)
                return updated
            }
            if let newLayout = updated.layout.removing(paneId: paneId, sizingMode: .proportional) {
                updated.layout = newLayout
            } else {
                updated.layout = Layout()
            }
            updated.minimizedPaneIds.remove(paneId)
            if updated.activePaneId == paneId {
                updated.activePaneId = TabArrangementSelectionRules.firstUnminimizedPaneId(in: updated)
            }
            return updated
        }
    }

    static func switchingArrangement(to arrangementId: UUID, in state: TabArrangementState) -> TabArrangementState {
        guard state.arrangements.contains(where: { $0.id == arrangementId }) else { return state }
        guard state.activeArrangementId != arrangementId else { return state }

        var updated = state
        updated.zoomedPaneId = nil
        updated.activeArrangementId = arrangementId
        let arrangementIndex = activeArrangementIndex(in: updated)
        updated.arrangements[arrangementIndex].activePaneId = TabArrangementSelectionRules.fallbackActivePaneId(
            currentActivePaneId: updated.arrangements[arrangementIndex].activePaneId,
            in: updated.arrangements[arrangementIndex]
        )
        return updated
    }

    static func minimizingPane(_ paneId: UUID, in state: TabArrangementState) -> TabArrangementState? {
        let arrangement = activeArrangement(in: state)
        let visiblePaneIds = arrangement.layout.paneIds
        guard visiblePaneIds.contains(paneId) else { return nil }

        var updated = state
        let arrangementIndex = activeArrangementIndex(in: updated)
        updated.arrangements[arrangementIndex].minimizedPaneIds.insert(paneId)
        if updated.arrangements[arrangementIndex].activePaneId == paneId {
            let nonMinimized = visiblePaneIds.filter {
                !updated.arrangements[arrangementIndex].minimizedPaneIds.contains($0)
            }
            updated.arrangements[arrangementIndex].activePaneId = nonMinimized.first
        }
        if updated.zoomedPaneId == paneId {
            updated.zoomedPaneId = nil
        }
        return updated
    }

    static func expandingPane(_ paneId: UUID, in state: TabArrangementState) -> TabArrangementState {
        var updated = state
        let arrangementIndex = activeArrangementIndex(in: updated)
        guard updated.arrangements[arrangementIndex].minimizedPaneIds.contains(paneId) else { return state }
        updated.arrangements[arrangementIndex].minimizedPaneIds.remove(paneId)
        updated.arrangements[arrangementIndex].activePaneId = paneId
        return updated
    }

    static func breakingUpTab(_ state: TabArrangementState) -> [TabArrangementState] {
        let tabPaneIds = defaultArrangement(in: state).layout.paneIds
        guard tabPaneIds.count > 1 else { return [] }

        return tabPaneIds.map { paneId in
            let tab = Tab(paneId: paneId)
            return TabArrangementState(
                tabId: tab.id,
                allPaneIds: tab.allPaneIds,
                arrangements: tab.arrangements,
                activeArrangementId: tab.activeArrangementId,
                zoomedPaneId: tab.zoomedPaneId
            )
        }
    }

    static func extractingPane(
        _ paneId: UUID,
        from state: TabArrangementState
    ) -> (updatedState: TabArrangementState, extractedState: TabArrangementState)? {
        guard activeArrangement(in: state).layout.paneIds.count > 1 else { return nil }
        guard state.allPaneIds.contains(paneId) else { return nil }

        var updated = state
        if updated.zoomedPaneId == paneId {
            updated.zoomedPaneId = nil
        }

        updated.arrangements = removingUserPane(paneId, from: updated.arrangements)
        updated.allPaneIds.removeAll { $0 == paneId }

        let newTab = Tab(paneId: paneId)
        let extractedState = TabArrangementState(
            tabId: newTab.id,
            allPaneIds: newTab.allPaneIds,
            arrangements: newTab.arrangements,
            activeArrangementId: newTab.activeArrangementId,
            zoomedPaneId: newTab.zoomedPaneId
        )
        return (updated, extractedState)
    }

    static func merging(
        source: TabArrangementState,
        into target: TabArrangementState,
        at targetPaneId: UUID,
        direction: Layout.SplitDirection,
        position: Layout.Position
    ) -> TabArrangementState? {
        let targetArrangement = activeArrangement(in: target)
        guard targetArrangement.layout.contains(targetPaneId) else { return nil }

        var updated = target
        updated.zoomedPaneId = nil
        let targetArrangementIndex = activeArrangementIndex(in: updated)
        let defaultArrangementIndex = defaultArrangementIndex(in: updated)
        let sourcePaneIds = defaultArrangement(in: source).layout.paneIds
        var currentTarget = targetPaneId
        for paneId in sourcePaneIds {
            guard
                let updatedActiveLayout = updated.arrangements[targetArrangementIndex].layout.inserting(
                    paneId: paneId,
                    at: currentTarget,
                    direction: direction,
                    position: position,
                    sizingMode: .halveTarget
                )
            else { return nil }
            updated.arrangements[targetArrangementIndex].layout = updatedActiveLayout
            if targetArrangementIndex != defaultArrangementIndex {
                if let updatedDefaultLayout = updated.arrangements[defaultArrangementIndex].layout.inserting(
                    paneId: paneId,
                    at: currentTarget,
                    direction: direction,
                    position: position,
                    sizingMode: .halveTarget
                ) {
                    updated.arrangements[defaultArrangementIndex].layout = updatedDefaultLayout
                }
            }
            if !updated.allPaneIds.contains(paneId) {
                updated.allPaneIds.append(paneId)
            }
            if position == .after {
                currentTarget = paneId
            }
        }
        return updated
    }

    private static func defaultArrangement(in state: TabArrangementState) -> PaneArrangement {
        state.arrangements[defaultArrangementIndex(in: state)]
    }

    private static func activeArrangement(in state: TabArrangementState) -> PaneArrangement {
        state.arrangements[activeArrangementIndex(in: state)]
    }

    private static func defaultArrangementIndex(in state: TabArrangementState) -> Int {
        state.arrangements.firstIndex(where: \.isDefault) ?? 0
    }

    private static func activeArrangementIndex(in state: TabArrangementState) -> Int {
        state.arrangements.firstIndex { $0.id == state.activeArrangementId } ?? defaultArrangementIndex(in: state)
    }
}
