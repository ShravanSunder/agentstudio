import Foundation

enum TabArrangementMutationRules {
    static func createArrangement(
        name: String,
        paneIds: Set<UUID>,
        from state: TabArrangementState
    ) -> PaneArrangement? {
        guard !paneIds.isEmpty else { return nil }
        let tabPaneSet = Set(state.allPaneIds)
        guard paneIds.isSubset(of: tabPaneSet) else { return nil }

        let defaultArrangement = defaultArrangement(in: state)
        let activeArrangement = activeArrangement(in: state)
        let paneIdsToRemove = Set(defaultArrangement.layout.paneIds).subtracting(paneIds)
        var filteredLayout = defaultArrangement.layout
        for removeId in paneIdsToRemove {
            if let newLayout = filteredLayout.removing(paneId: removeId, sizingMode: .halveTarget) {
                filteredLayout = newLayout
            }
        }

        return PaneArrangement(
            name: name,
            isDefault: false,
            layout: filteredLayout,
            visiblePaneIds: paneIds,
            minimizedPaneIds: activeArrangement.minimizedPaneIds.intersection(paneIds)
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
            if let activePaneId = updated.activePaneId, !defaultArrangement.layout.contains(activePaneId) {
                updated.activePaneId = TabArrangementSelectionRules.firstUnminimizedPaneId(in: defaultArrangement)
            } else if let activePaneId = updated.activePaneId,
                defaultArrangement.minimizedPaneIds.contains(activePaneId)
            {
                updated.activePaneId = TabArrangementSelectionRules.firstUnminimizedPaneId(in: defaultArrangement)
            }
        }
        updated.arrangements.remove(at: arrangementIndex)
        return updated
    }

    static func removingUserPane(_ paneId: UUID, from arrangements: [PaneArrangement]) -> [PaneArrangement] {
        arrangements.map { arrangement in
            var updated = arrangement
            guard updated.layout.contains(paneId) else {
                updated.visiblePaneIds.remove(paneId)
                updated.minimizedPaneIds.remove(paneId)
                return updated
            }
            if let newLayout = updated.layout.removing(paneId: paneId, sizingMode: .proportional) {
                updated.layout = newLayout
            } else {
                updated.layout = Layout()
            }
            updated.visiblePaneIds.remove(paneId)
            updated.minimizedPaneIds.remove(paneId)
            return updated
        }
    }

    static func switchingArrangement(to arrangementId: UUID, in state: TabArrangementState) -> TabArrangementState {
        guard state.arrangements.contains(where: { $0.id == arrangementId }) else { return state }
        guard state.activeArrangementId != arrangementId else { return state }

        var updated = state
        updated.zoomedPaneId = nil
        updated.activeArrangementId = arrangementId
        updated.activePaneId = TabArrangementSelectionRules.fallbackActivePaneId(
            currentActivePaneId: updated.activePaneId,
            in: activeArrangement(in: updated)
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
        if updated.activePaneId == paneId {
            let nonMinimized = visiblePaneIds.filter {
                !updated.arrangements[arrangementIndex].minimizedPaneIds.contains($0)
            }
            updated.activePaneId = nonMinimized.first
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
        updated.activePaneId = paneId
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
                activePaneId: tab.activePaneId,
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
        if updated.activePaneId == paneId {
            updated.activePaneId = TabArrangementSelectionRules.firstUnminimizedPaneId(
                in: activeArrangement(in: updated)
            )
        }

        let newTab = Tab(paneId: paneId)
        let extractedState = TabArrangementState(
            tabId: newTab.id,
            allPaneIds: newTab.allPaneIds,
            arrangements: newTab.arrangements,
            activeArrangementId: newTab.activeArrangementId,
            activePaneId: newTab.activePaneId,
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
            updated.arrangements[targetArrangementIndex].visiblePaneIds.insert(paneId)
            if targetArrangementIndex != defaultArrangementIndex {
                if let updatedDefaultLayout = updated.arrangements[defaultArrangementIndex].layout.inserting(
                    paneId: paneId,
                    at: currentTarget,
                    direction: direction,
                    position: position,
                    sizingMode: .halveTarget
                ) {
                    updated.arrangements[defaultArrangementIndex].layout = updatedDefaultLayout
                    updated.arrangements[defaultArrangementIndex].visiblePaneIds.insert(paneId)
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
