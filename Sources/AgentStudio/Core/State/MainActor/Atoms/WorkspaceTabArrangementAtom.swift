import Foundation
import Observation
import os.log

private let workspaceTabArrangementLogger = Logger(
    subsystem: "com.agentstudio", category: "WorkspaceTabArrangementAtom")

@MainActor
@Observable
final class WorkspaceTabArrangementAtom {
    private(set) var arrangementStates: [TabArrangementState] = []

    func hydrate(persistedTabs: [Tab], validPaneIds: Set<UUID>) {
        let hydratedStates = persistedTabs.map { tab in
            TabArrangementState(
                tabId: tab.id,
                allPaneIds: tab.allPaneIds,
                arrangements: tab.arrangements,
                activeArrangementId: tab.activeArrangementId,
                zoomedPaneId: tab.zoomedPaneId
            )
        }
        arrangementStates = TabArrangementValidation.validating(
            TabArrangementValidation.pruningInvalidPaneIds(validPaneIds: validPaneIds, from: hydratedStates)
        )
    }

    var allPaneIds: Set<UUID> {
        Set(arrangementStates.flatMap(\.allPaneIds))
    }

    func arrangementState(_ tabId: UUID) -> TabArrangementState? {
        arrangementStates.first { $0.tabId == tabId }
    }

    func tabContaining(paneId: UUID) -> TabArrangementState? {
        arrangementStates.first { $0.allPaneIds.contains(paneId) }
    }

    func appendState(_ state: TabArrangementState) {
        arrangementStates.append(state)
    }

    func removeState(_ tabId: UUID) {
        arrangementStates.removeAll { $0.tabId == tabId }
    }

    func insertState(_ state: TabArrangementState, at index: Int) {
        let clampedIndex = min(index, arrangementStates.count)
        arrangementStates.insert(state, at: clampedIndex)
    }

    @discardableResult
    func insertPane(
        _ paneId: UUID,
        inTab tabId: UUID,
        at targetPaneId: UUID,
        direction: Layout.SplitDirection,
        position: Layout.Position,
        sizingMode: DropSizingMode
    ) -> Bool {
        guard let tabIndex = findTabIndex(tabId) else {
            workspaceTabArrangementLogger.warning("insertPane: tab \(tabId) not found")
            return false
        }
        let arrIndex = activeArrangementIndex(for: tabIndex)

        guard arrangementStates[tabIndex].arrangements[arrIndex].layout.contains(targetPaneId) else {
            workspaceTabArrangementLogger.warning("insertPane: targetPaneId \(targetPaneId) not in active arrangement")
            return false
        }

        guard
            let updatedActiveLayout = arrangementStates[tabIndex].arrangements[arrIndex].layout.inserting(
                paneId: paneId, at: targetPaneId, direction: direction, position: position, sizingMode: sizingMode)
        else {
            workspaceTabArrangementLogger.warning("insertPane: targetPaneId \(targetPaneId) rejected during insertion")
            return false
        }

        arrangementStates[tabIndex].zoomedPaneId = nil
        arrangementStates[tabIndex].arrangements[arrIndex].layout = updatedActiveLayout
        arrangementStates[tabIndex].arrangements[arrIndex].activePaneId = paneId

        if !arrangementStates[tabIndex].arrangements[arrIndex].isDefault {
            let defIdx = defaultArrangementIndex(for: tabIndex)
            if arrangementStates[tabIndex].arrangements[defIdx].layout.contains(targetPaneId) {
                if let updatedDefaultLayout = arrangementStates[tabIndex].arrangements[defIdx].layout.inserting(
                    paneId: paneId, at: targetPaneId, direction: direction, position: position, sizingMode: sizingMode)
                {
                    arrangementStates[tabIndex].arrangements[defIdx].layout = updatedDefaultLayout
                }
            }
        }

        if !arrangementStates[tabIndex].allPaneIds.contains(paneId) {
            arrangementStates[tabIndex].allPaneIds.append(paneId)
        }
        return true
    }

    func removePaneFromLayout(_ paneId: UUID, inTab tabId: UUID) {
        guard let tabIndex = findTabIndex(tabId) else {
            workspaceTabArrangementLogger.warning("removePaneFromLayout: tab \(tabId) not found")
            return
        }

        if arrangementStates[tabIndex].zoomedPaneId == paneId {
            arrangementStates[tabIndex].zoomedPaneId = nil
        }

        arrangementStates[tabIndex].arrangements = TabArrangementMutationRules.removingUserPane(
            paneId,
            from: arrangementStates[tabIndex].arrangements
        )

        if activeArrangement(for: tabIndex).layout.isEmpty && !defaultArrangement(for: tabIndex).layout.isEmpty {
            arrangementStates[tabIndex].activeArrangementId = defaultArrangement(for: tabIndex).id
        }

        arrangementStates[tabIndex].allPaneIds.removeAll { $0 == paneId }
    }

    func removePaneReferences(_ paneId: UUID) {
        for tabIndex in arrangementStates.indices {
            arrangementStates[tabIndex].allPaneIds.removeAll { $0 == paneId }
            arrangementStates[tabIndex].arrangements = TabArrangementRepairRules.removingPane(
                paneId,
                from: arrangementStates[tabIndex].arrangements
            )
            if arrangementStates[tabIndex].zoomedPaneId == paneId {
                arrangementStates[tabIndex].zoomedPaneId = nil
            }
        }
    }

    func resizePane(tabId: UUID, splitId: UUID, ratio: Double) {
        guard let tabIndex = findTabIndex(tabId) else {
            workspaceTabArrangementLogger.warning("resizePane: tab \(tabId) not found")
            return
        }
        let arrIndex = activeArrangementIndex(for: tabIndex)
        arrangementStates[tabIndex].arrangements[arrIndex].layout = arrangementStates[tabIndex].arrangements[arrIndex]
            .layout
            .resizing(splitId: splitId, ratio: ratio)
    }

    func equalizePanes(tabId: UUID) {
        guard let tabIndex = findTabIndex(tabId) else {
            workspaceTabArrangementLogger.warning("equalizePanes: tab \(tabId) not found")
            return
        }
        let arrIndex = activeArrangementIndex(for: tabIndex)
        arrangementStates[tabIndex].arrangements[arrIndex].layout = arrangementStates[tabIndex].arrangements[arrIndex]
            .layout.equalized()
    }

    func setActivePane(_ paneId: UUID?, inTab tabId: UUID) {
        guard let tabIndex = findTabIndex(tabId) else {
            workspaceTabArrangementLogger.warning("setActivePane: tab \(tabId) not found")
            return
        }
        if let paneId {
            guard arrangementStates[tabIndex].allPaneIds.contains(paneId) else {
                workspaceTabArrangementLogger.warning("setActivePane: paneId \(paneId) not found in tab \(tabId)")
                return
            }
        }
        let arrIndex = activeArrangementIndex(for: tabIndex)
        arrangementStates[tabIndex].arrangements[arrIndex].activePaneId = paneId
    }

    @discardableResult
    func createArrangement(name: String, paneIds: Set<UUID>, inTab tabId: UUID) -> UUID? {
        guard let tabIndex = findTabIndex(tabId) else {
            workspaceTabArrangementLogger.warning("createArrangement: tab \(tabId) not found")
            return nil
        }
        guard !paneIds.isEmpty else {
            workspaceTabArrangementLogger.warning("createArrangement: empty paneIds")
            return nil
        }
        let tabPaneSet = Set(arrangementStates[tabIndex].allPaneIds)
        guard paneIds.isSubset(of: tabPaneSet) else {
            workspaceTabArrangementLogger.warning("createArrangement: paneIds not all in tab \(tabId)")
            return nil
        }

        guard
            let arrangement = TabArrangementMutationRules.createArrangement(
                name: name,
                paneIds: paneIds,
                from: arrangementStates[tabIndex]
            )
        else {
            workspaceTabArrangementLogger.warning("createArrangement: failed to build arrangement for tab \(tabId)")
            return nil
        }
        arrangementStates[tabIndex].arrangements.append(arrangement)
        return arrangement.id
    }

    func removeArrangement(_ arrangementId: UUID, inTab tabId: UUID) {
        guard let tabIndex = findTabIndex(tabId) else {
            workspaceTabArrangementLogger.warning("removeArrangement: tab \(tabId) not found")
            return
        }
        guard let arrIndex = arrangementStates[tabIndex].arrangements.firstIndex(where: { $0.id == arrangementId })
        else {
            workspaceTabArrangementLogger.warning(
                "removeArrangement: arrangement \(arrangementId) not found in tab \(tabId)"
            )
            return
        }
        guard !arrangementStates[tabIndex].arrangements[arrIndex].isDefault else {
            workspaceTabArrangementLogger.warning("removeArrangement: cannot remove default arrangement")
            return
        }

        arrangementStates[tabIndex] = TabArrangementMutationRules.removingArrangement(
            arrangementId,
            from: arrangementStates[tabIndex]
        )
    }

    func switchArrangement(to arrangementId: UUID, inTab tabId: UUID) {
        guard let tabIndex = findTabIndex(tabId) else {
            workspaceTabArrangementLogger.warning("switchArrangement: tab \(tabId) not found")
            return
        }
        guard arrangementStates[tabIndex].arrangements.contains(where: { $0.id == arrangementId }) else {
            workspaceTabArrangementLogger.warning(
                "switchArrangement: arrangement \(arrangementId) not found in tab \(tabId)"
            )
            return
        }
        guard arrangementStates[tabIndex].activeArrangementId != arrangementId else { return }
        arrangementStates[tabIndex] = TabArrangementMutationRules.switchingArrangement(
            to: arrangementId,
            in: arrangementStates[tabIndex]
        )
    }

    func renameArrangement(_ arrangementId: UUID, name: String, inTab tabId: UUID) {
        guard let tabIndex = findTabIndex(tabId) else {
            workspaceTabArrangementLogger.warning("renameArrangement: tab \(tabId) not found")
            return
        }
        guard let arrIndex = arrangementStates[tabIndex].arrangements.firstIndex(where: { $0.id == arrangementId })
        else {
            workspaceTabArrangementLogger.warning(
                "renameArrangement: arrangement \(arrangementId) not found in tab \(tabId)"
            )
            return
        }
        arrangementStates[tabIndex].arrangements[arrIndex].name = name
    }

    func toggleZoom(paneId: UUID, inTab tabId: UUID) {
        guard let tabIndex = findTabIndex(tabId) else {
            workspaceTabArrangementLogger.warning("toggleZoom: tab \(tabId) not found")
            return
        }
        if arrangementStates[tabIndex].zoomedPaneId == paneId {
            arrangementStates[tabIndex].zoomedPaneId = nil
        } else if activeArrangement(for: tabIndex).layout.contains(paneId) {
            arrangementStates[tabIndex].zoomedPaneId = paneId
        }
    }

    @discardableResult
    func minimizePane(_ paneId: UUID, inTab tabId: UUID) -> Bool {
        guard let tabIndex = findTabIndex(tabId) else {
            workspaceTabArrangementLogger.warning("minimizePane: tab \(tabId) not found")
            return false
        }
        let visiblePaneIds = activeArrangement(for: tabIndex).layout.paneIds
        guard visiblePaneIds.contains(paneId) else {
            workspaceTabArrangementLogger.warning("minimizePane: pane \(paneId) not in active arrangement")
            return false
        }

        guard let updated = TabArrangementMutationRules.minimizingPane(paneId, in: arrangementStates[tabIndex]) else {
            workspaceTabArrangementLogger.warning("minimizePane: pane \(paneId) not in active arrangement")
            return false
        }
        arrangementStates[tabIndex] = updated
        return true
    }

    func expandPane(_ paneId: UUID, inTab tabId: UUID) {
        guard let tabIndex = findTabIndex(tabId) else {
            workspaceTabArrangementLogger.warning("expandPane: tab \(tabId) not found")
            return
        }
        arrangementStates[tabIndex] = TabArrangementMutationRules.expandingPane(paneId, in: arrangementStates[tabIndex])
    }

    func addDrawerPaneView(
        drawerId: UUID,
        parentPaneId: UUID,
        drawerPaneId: UUID,
        inTab tabId: UUID,
        targetDrawerPaneId: UUID? = nil,
        direction: SplitNewDirection = .right,
        sizingMode: DropSizingMode = .halveTarget
    ) {
        guard let tabIndex = findTabIndex(tabId) else {
            workspaceTabArrangementLogger.warning("addDrawerPaneView: tab \(tabId) not found")
            return
        }

        for arrangementIndex in arrangementStates[tabIndex].arrangements.indices {
            guard arrangementStates[tabIndex].arrangements[arrangementIndex].layout.contains(parentPaneId) else {
                continue
            }
            var drawerView =
                arrangementStates[tabIndex].arrangements[arrangementIndex].drawerViews[drawerId]
                ?? DrawerView(layout: DrawerGridLayout(topRow: Layout(paneId: drawerPaneId)))

            if drawerView.layout.contains(drawerPaneId) {
                drawerView.activeChildId = drawerPaneId
            } else if drawerView.layout.isEmpty {
                drawerView.layout = DrawerGridLayout(topRow: Layout(paneId: drawerPaneId))
                drawerView.activeChildId = drawerPaneId
            } else {
                let targetPaneId = targetDrawerPaneId ?? drawerView.layout.paneIds.last
                if let targetPaneId,
                    let updatedLayout = drawerView.layout.inserting(
                        paneId: drawerPaneId,
                        at: targetPaneId,
                        direction: direction,
                        sizingMode: sizingMode
                    )
                {
                    drawerView.layout = updatedLayout
                    if arrangementIndex == activeArrangementIndex(for: tabIndex) {
                        drawerView.activeChildId = drawerPaneId
                    }
                }
            }

            arrangementStates[tabIndex].arrangements[arrangementIndex].drawerViews[drawerId] = drawerView
        }
    }

    func removeDrawerPaneView(drawerId: UUID, drawerPaneId: UUID, inTab tabId: UUID) {
        guard let tabIndex = findTabIndex(tabId) else {
            workspaceTabArrangementLogger.warning("removeDrawerPaneView: tab \(tabId) not found")
            return
        }

        for arrangementIndex in arrangementStates[tabIndex].arrangements.indices {
            guard var drawerView = arrangementStates[tabIndex].arrangements[arrangementIndex].drawerViews[drawerId]
            else { continue }
            drawerView.minimizedPaneIds.remove(drawerPaneId)
            if drawerView.layout.contains(drawerPaneId) {
                drawerView.layout =
                    drawerView.layout.removing(paneId: drawerPaneId, sizingMode: .proportional)
                    ?? DrawerGridLayout()
            }
            if drawerView.layout.isEmpty {
                arrangementStates[tabIndex].arrangements[arrangementIndex].drawerViews.removeValue(forKey: drawerId)
                continue
            }
            if drawerView.activeChildId == drawerPaneId {
                drawerView.activeChildId = drawerView.layout.paneIds.first
            }
            arrangementStates[tabIndex].arrangements[arrangementIndex].drawerViews[drawerId] = drawerView
        }
    }

    func setActiveDrawerPane(_ drawerPaneId: UUID, drawerId: UUID, inTab tabId: UUID) {
        guard let tabIndex = findTabIndex(tabId) else {
            workspaceTabArrangementLogger.warning("setActiveDrawerPane: tab \(tabId) not found")
            return
        }
        let arrangementIndex = activeArrangementIndex(for: tabIndex)
        guard var drawerView = arrangementStates[tabIndex].arrangements[arrangementIndex].drawerViews[drawerId],
            drawerView.layout.contains(drawerPaneId)
        else {
            workspaceTabArrangementLogger.warning("setActiveDrawerPane: drawer pane \(drawerPaneId) not found")
            return
        }
        drawerView.activeChildId = drawerPaneId
        arrangementStates[tabIndex].arrangements[arrangementIndex].drawerViews[drawerId] = drawerView
    }

    func resizeDrawerPane(drawerId: UUID, tabId: UUID, splitId: UUID, ratio: Double) {
        guard let tabIndex = findTabIndex(tabId) else {
            workspaceTabArrangementLogger.warning("resizeDrawerPane: tab \(tabId) not found")
            return
        }
        let arrangementIndex = activeArrangementIndex(for: tabIndex)
        guard var drawerView = arrangementStates[tabIndex].arrangements[arrangementIndex].drawerViews[drawerId]
        else { return }
        drawerView.layout = drawerView.layout.resizing(splitId: splitId, ratio: ratio)
        arrangementStates[tabIndex].arrangements[arrangementIndex].drawerViews[drawerId] = drawerView
    }

    func equalizeDrawerPanes(drawerId: UUID, tabId: UUID) {
        guard let tabIndex = findTabIndex(tabId) else {
            workspaceTabArrangementLogger.warning("equalizeDrawerPanes: tab \(tabId) not found")
            return
        }
        let arrangementIndex = activeArrangementIndex(for: tabIndex)
        guard var drawerView = arrangementStates[tabIndex].arrangements[arrangementIndex].drawerViews[drawerId]
        else { return }
        drawerView.layout = drawerView.layout.equalized()
        arrangementStates[tabIndex].arrangements[arrangementIndex].drawerViews[drawerId] = drawerView
    }

    @discardableResult
    func minimizeDrawerPane(_ drawerPaneId: UUID, drawerId: UUID, tabId: UUID) -> Bool {
        guard let tabIndex = findTabIndex(tabId) else {
            workspaceTabArrangementLogger.warning("minimizeDrawerPane: tab \(tabId) not found")
            return false
        }
        let arrangementIndex = activeArrangementIndex(for: tabIndex)
        guard var drawerView = arrangementStates[tabIndex].arrangements[arrangementIndex].drawerViews[drawerId],
            drawerView.layout.contains(drawerPaneId)
        else { return false }

        drawerView.minimizedPaneIds.insert(drawerPaneId)
        if drawerView.activeChildId == drawerPaneId {
            drawerView.activeChildId = drawerView.layout.paneIds.first { !drawerView.minimizedPaneIds.contains($0) }
        }
        arrangementStates[tabIndex].arrangements[arrangementIndex].drawerViews[drawerId] = drawerView
        return true
    }

    func expandDrawerPane(_ drawerPaneId: UUID, drawerId: UUID, tabId: UUID) {
        guard let tabIndex = findTabIndex(tabId) else {
            workspaceTabArrangementLogger.warning("expandDrawerPane: tab \(tabId) not found")
            return
        }
        let arrangementIndex = activeArrangementIndex(for: tabIndex)
        guard var drawerView = arrangementStates[tabIndex].arrangements[arrangementIndex].drawerViews[drawerId]
        else { return }
        drawerView.minimizedPaneIds.remove(drawerPaneId)
        drawerView.activeChildId = drawerPaneId
        arrangementStates[tabIndex].arrangements[arrangementIndex].drawerViews[drawerId] = drawerView
    }

    func moveDrawerPane(
        _ drawerPaneId: UUID,
        drawerId: UUID,
        tabId: UUID,
        target: DrawerRearrangeTarget,
        sizingMode: DropSizingMode
    ) {
        guard let tabIndex = findTabIndex(tabId) else {
            workspaceTabArrangementLogger.warning("moveDrawerPane: tab \(tabId) not found")
            return
        }
        let arrangementIndex = activeArrangementIndex(for: tabIndex)
        guard var drawerView = arrangementStates[tabIndex].arrangements[arrangementIndex].drawerViews[drawerId]
        else { return }

        switch drawerView.layout.projectedMove(paneId: drawerPaneId, target: target, sizingMode: sizingMode) {
        case .success(let movedLayout):
            drawerView.layout = movedLayout
            drawerView.activeChildId = drawerPaneId
            arrangementStates[tabIndex].arrangements[arrangementIndex].drawerViews[drawerId] = drawerView
        case .failure(let failure):
            workspaceTabArrangementLogger.warning(
                "moveDrawerPane: rejected moving pane \(drawerPaneId): \(failure.description)"
            )
        }
    }

    func resizePaneByDelta(tabId: UUID, paneId: UUID, direction: SplitResizeDirection, amount: UInt16) {
        guard let tabIndex = findTabIndex(tabId) else {
            workspaceTabArrangementLogger.warning("resizePaneByDelta: tab \(tabId) not found")
            return
        }
        guard arrangementStates[tabIndex].zoomedPaneId == nil else { return }
        guard
            let (splitId, increase) = activeArrangement(for: tabIndex).layout.resizeTarget(
                for: paneId, direction: direction)
        else { return }
        guard let currentRatio = activeArrangement(for: tabIndex).layout.ratioForSplit(splitId) else {
            workspaceTabArrangementLogger.warning("resizePaneByDelta: ratioForSplit returned nil for split \(splitId)")
            return
        }

        let delta = Self.resizeRatioStep * (Double(amount) / Self.resizeBaseAmount)
        let newRatio = min(0.9, max(0.1, increase ? currentRatio + delta : currentRatio - delta))
        let arrIndex = activeArrangementIndex(for: tabIndex)
        arrangementStates[tabIndex].arrangements[arrIndex].layout = arrangementStates[tabIndex].arrangements[arrIndex]
            .layout
            .resizing(splitId: splitId, ratio: newRatio)
    }

    func breakUpTab(_ tabId: UUID) -> [TabArrangementState] {
        guard let tabIndex = findTabIndex(tabId) else {
            workspaceTabArrangementLogger.warning("breakUpTab: tab \(tabId) not found")
            return []
        }
        let state = arrangementStates[tabIndex]
        let newStates = TabArrangementMutationRules.breakingUpTab(state)
        guard !newStates.isEmpty else {
            workspaceTabArrangementLogger.warning(
                "breakUpTab: tab \(tabId) has fewer than two panes in the active arrangement")
            return []
        }

        arrangementStates.remove(at: tabIndex)
        let insertIndex = min(tabIndex, arrangementStates.count)
        arrangementStates.insert(contentsOf: newStates, at: insertIndex)
        return newStates
    }

    func extractPane(_ paneId: UUID, fromTab tabId: UUID) -> TabArrangementState? {
        guard let tabIndex = findTabIndex(tabId) else {
            workspaceTabArrangementLogger.warning("extractPane: tab \(tabId) not found")
            return nil
        }
        guard arrangementStates[tabIndex].allPaneIds.contains(paneId) else {
            workspaceTabArrangementLogger.warning("extractPane: paneId \(paneId) not in tab \(tabId)")
            return nil
        }
        guard let result = TabArrangementMutationRules.extractingPane(paneId, from: arrangementStates[tabIndex]) else {
            workspaceTabArrangementLogger.warning(
                "extractPane: pane \(paneId) cannot be extracted because the active arrangement has fewer than two panes"
            )
            return nil
        }
        arrangementStates[tabIndex] = result.updatedState
        let insertIndex = tabIndex + 1
        arrangementStates.insert(result.extractedState, at: min(insertIndex, arrangementStates.count))
        return result.extractedState
    }

    func mergeTab(
        sourceId: UUID,
        intoTarget targetId: UUID,
        at targetPaneId: UUID,
        direction: Layout.SplitDirection,
        position: Layout.Position
    ) {
        guard sourceId != targetId else {
            workspaceTabArrangementLogger.warning("mergeTab: sourceId and targetId are the same tab \(sourceId)")
            return
        }
        guard let sourceTabIndex = arrangementStates.firstIndex(where: { $0.tabId == sourceId }),
            let targetTabIndex = arrangementStates.firstIndex(where: { $0.tabId == targetId })
        else {
            workspaceTabArrangementLogger.warning("mergeTab: source \(sourceId) or target \(targetId) tab not found")
            return
        }

        let targetArrIndex = activeArrangementIndex(for: targetTabIndex)
        guard arrangementStates[targetTabIndex].arrangements[targetArrIndex].layout.contains(targetPaneId) else {
            workspaceTabArrangementLogger.warning("mergeTab: targetPaneId \(targetPaneId) not in target arrangement")
            return
        }

        guard
            let mergedState = TabArrangementMutationRules.merging(
                source: arrangementStates[sourceTabIndex],
                into: arrangementStates[targetTabIndex],
                at: targetPaneId,
                direction: direction,
                position: position
            )
        else {
            workspaceTabArrangementLogger.warning(
                "mergeTab: merge helper rejected source \(sourceId) into target \(targetId) at pane \(targetPaneId)"
            )
            return
        }
        arrangementStates[targetTabIndex] = mergedState

        arrangementStates.remove(at: sourceTabIndex)
    }

    private static let resizeRatioStep: Double = 0.05
    private static let resizeBaseAmount: Double = 10.0

    private func findTabIndex(_ tabId: UUID) -> Int? {
        arrangementStates.firstIndex { $0.tabId == tabId }
    }

    private func defaultArrangementIndex(for tabIndex: Int) -> Int {
        arrangementStates[tabIndex].arrangements.firstIndex(where: \.isDefault) ?? 0
    }

    private func activeArrangementIndex(for tabIndex: Int) -> Int {
        arrangementStates[tabIndex].arrangements.firstIndex {
            $0.id == arrangementStates[tabIndex].activeArrangementId
        } ?? defaultArrangementIndex(for: tabIndex)
    }

    private func defaultArrangement(for tabIndex: Int) -> PaneArrangement {
        arrangementStates[tabIndex].arrangements[defaultArrangementIndex(for: tabIndex)]
    }

    private func activeArrangement(for tabIndex: Int) -> PaneArrangement {
        arrangementStates[tabIndex].arrangements[activeArrangementIndex(for: tabIndex)]
    }
}
