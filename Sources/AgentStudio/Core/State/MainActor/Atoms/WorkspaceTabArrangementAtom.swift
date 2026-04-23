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
                activePaneId: tab.activePaneId,
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

        arrangementStates[tabIndex].zoomedPaneId = nil
        arrangementStates[tabIndex].arrangements[arrIndex].layout = arrangementStates[tabIndex].arrangements[arrIndex]
            .layout
            .inserting(
                paneId: paneId, at: targetPaneId, direction: direction, position: position, sizingMode: sizingMode)
        arrangementStates[tabIndex].arrangements[arrIndex].visiblePaneIds.insert(paneId)

        if !arrangementStates[tabIndex].arrangements[arrIndex].isDefault {
            let defIdx = defaultArrangementIndex(for: tabIndex)
            if arrangementStates[tabIndex].arrangements[defIdx].layout.contains(targetPaneId) {
                arrangementStates[tabIndex].arrangements[defIdx].layout = arrangementStates[tabIndex].arrangements[
                    defIdx
                ]
                .layout
                .inserting(
                    paneId: paneId, at: targetPaneId, direction: direction, position: position, sizingMode: sizingMode)
                arrangementStates[tabIndex].arrangements[defIdx].visiblePaneIds.insert(paneId)
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

        if arrangementStates[tabIndex].activePaneId == paneId {
            arrangementStates[tabIndex].activePaneId = TabArrangementSelectionRules.firstUnminimizedPaneId(
                in: activeArrangement(for: tabIndex)
            )
        }

        if activeArrangement(for: tabIndex).layout.isEmpty && !defaultArrangement(for: tabIndex).layout.isEmpty {
            arrangementStates[tabIndex].activeArrangementId = defaultArrangement(for: tabIndex).id
            arrangementStates[tabIndex].activePaneId = TabArrangementSelectionRules.firstUnminimizedPaneId(
                in: activeArrangement(for: tabIndex)
            )
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
            if arrangementStates[tabIndex].activePaneId == paneId {
                arrangementStates[tabIndex].activePaneId = TabArrangementSelectionRules.firstUnminimizedPaneId(
                    in: activeArrangement(for: tabIndex)
                )
            }
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
        arrangementStates[tabIndex].activePaneId = paneId
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
