import Foundation

enum TabArrangementMutationRules {
    static func createArrangement(
        name: String,
        from state: TabArrangementState
    ) -> PaneArrangement? {
        let activeArrangement = activeArrangement(in: state)
        guard
            let arrangementLayout = layoutForNewArrangement(
                basedOn: activeArrangement.layout,
                allPaneIds: state.allPaneIds
            )
        else { return nil }
        let arrangementPaneIds = Set(arrangementLayout.paneIds)
        let arrangementMinimizedPaneIds = activeArrangement.minimizedPaneIds.intersection(arrangementPaneIds)

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
            let drawerIds = drawerId.map { Set([$0]) } ?? []
            return TabArrangementRepairRules.removingPane(
                paneId,
                removingDrawerIds: drawerIds,
                layoutSizingMode: .proportional,
                from: [arrangement]
            )[0]
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
        let layoutPaneIds = arrangement.layout.paneIds
        guard layoutPaneIds.contains(paneId) else { return nil }

        var updated = state
        let arrangementIndex = activeArrangementIndex(in: updated)
        updated.arrangements[arrangementIndex].minimizedPaneIds.insert(paneId)
        if updated.arrangements[arrangementIndex].activePaneId == paneId {
            let nonMinimized = layoutPaneIds.filter {
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
        let sourcePaneIds = defaultArrangement(in: source).layout.paneIds
        for arrangementIndex in updated.arrangements.indices {
            var currentTarget = targetPaneId
            for paneId in sourcePaneIds {
                let updatedLayout: Layout?
                if updated.arrangements[arrangementIndex].layout.contains(currentTarget) {
                    updatedLayout = updated.arrangements[arrangementIndex].layout.inserting(
                        paneId: paneId,
                        at: currentTarget,
                        direction: direction,
                        position: position,
                        sizingMode: .halveTarget
                    )
                } else {
                    updatedLayout = appendingPane(
                        paneId,
                        to: updated.arrangements[arrangementIndex].layout
                    )
                }
                guard let updatedLayout else { return nil }
                updated.arrangements[arrangementIndex].layout = updatedLayout
                updated.arrangements[arrangementIndex].minimizedPaneIds.remove(paneId)
                if position == .after {
                    currentTarget = paneId
                }
            }
        }

        for paneId in sourcePaneIds where !updated.allPaneIds.contains(paneId) {
            updated.allPaneIds.append(paneId)
        }
        return updated
    }

    private static func defaultArrangement(in state: TabArrangementState) -> PaneArrangement {
        state.arrangements[defaultArrangementIndex(in: state)]
    }

    private static func activeArrangement(in state: TabArrangementState) -> PaneArrangement {
        state.arrangements[activeArrangementIndex(in: state)]
    }

    private static func layoutForNewArrangement(
        basedOn activeLayout: Layout,
        allPaneIds: [UUID]
    ) -> Layout? {
        guard !allPaneIds.isEmpty else { return nil }

        var layout = activeLayout
        let tabPaneIds = Set(allPaneIds)
        for paneId in layout.paneIds where !tabPaneIds.contains(paneId) {
            layout = layout.removing(paneId: paneId, sizingMode: .halveTarget) ?? Layout()
        }

        for paneId in allPaneIds where !layout.contains(paneId) {
            guard let updatedLayout = appendingPane(paneId, to: layout) else {
                return Layout.autoTiled(allPaneIds)
            }
            layout = updatedLayout
        }

        return layout.isEmpty ? Layout.autoTiled(allPaneIds) : layout
    }

    private static func appendingPane(_ paneId: UUID, to layout: Layout) -> Layout? {
        guard let anchorPaneId = layout.paneIds.last else { return Layout(paneId: paneId) }
        return layout.inserting(
            paneId: paneId,
            at: anchorPaneId,
            direction: .horizontal,
            position: .after,
            sizingMode: .halveTarget
        )
    }

    private static func defaultArrangementIndex(in state: TabArrangementState) -> Int {
        state.arrangements.firstIndex(where: \.isDefault) ?? 0
    }

    private static func activeArrangementIndex(in state: TabArrangementState) -> Int {
        state.arrangements.firstIndex { $0.id == state.activeArrangementId } ?? defaultArrangementIndex(in: state)
    }
}
