import Foundation
import Observation
import os.log

private let workspaceTabLayoutLogger = Logger(subsystem: "com.agentstudio", category: "WorkspaceTabLayoutAtom")

@MainActor
@Observable
final class WorkspaceTabLayoutAtom {
    private(set) var tabs: [Tab] = []
    private(set) var activeTabId: UUID?

    func hydrate(persistedTabs: [Tab], activeTabId: UUID?, validPaneIds: Set<UUID>) {
        tabs = persistedTabs
        self.activeTabId = activeTabId
        pruneInvalidPanes(validPaneIds: validPaneIds)
        validateTabInvariants()
        if self.activeTabId == nil, let firstTab = tabs.first {
            self.activeTabId = firstTab.id
        }
    }

    var activeTab: Tab? {
        tabs.first { $0.id == activeTabId }
    }

    var activePaneIds: Set<UUID> {
        Set(activeTab?.paneIds ?? [])
    }

    var allPaneIds: Set<UUID> {
        Set(tabs.flatMap(\.paneIds))
    }

    func tab(_ id: UUID) -> Tab? {
        tabs.first { $0.id == id }
    }

    func tabContaining(paneId: UUID) -> Tab? {
        tabs.first { $0.panes.contains(paneId) }
    }

    func appendTab(_ tab: Tab) {
        tabs.append(tab)
        activeTabId = tab.id
    }

    func removeTab(_ tabId: UUID) {
        tabs.removeAll { $0.id == tabId }
        if activeTabId == tabId {
            activeTabId = tabs.last?.id
        }
    }

    func insertTab(_ tab: Tab, at index: Int) {
        let clampedIndex = min(index, tabs.count)
        tabs.insert(tab, at: clampedIndex)
    }

    func moveTab(fromId: UUID, toIndex: Int) {
        guard let fromIndex = tabs.firstIndex(where: { $0.id == fromId }) else {
            workspaceTabLayoutLogger.warning("moveTab: tab \(fromId) not found")
            return
        }
        let tab = tabs.remove(at: fromIndex)
        let adjustedIndex = toIndex > fromIndex ? toIndex - 1 : toIndex
        let clampedIndex = max(0, min(adjustedIndex, tabs.count))
        tabs.insert(tab, at: clampedIndex)
    }

    func moveTabByDelta(tabId: UUID, delta: Int) {
        guard let fromIndex = tabs.firstIndex(where: { $0.id == tabId }) else {
            workspaceTabLayoutLogger.warning("moveTabByDelta: tab \(tabId) not found")
            return
        }
        let count = tabs.count
        guard count > 1 else { return }

        let finalIndex: Int
        if delta < 0 {
            let magnitude = delta == Int.min ? Int.max : -delta
            finalIndex = fromIndex - min(fromIndex, magnitude)
        } else {
            let remaining = count - 1 - fromIndex
            finalIndex = fromIndex + min(remaining, delta)
        }
        guard finalIndex != fromIndex else { return }

        let tab = tabs.remove(at: fromIndex)
        tabs.insert(tab, at: finalIndex)
    }

    func setActiveTab(_ tabId: UUID?) {
        activeTabId = tabId
    }

    @discardableResult
    func insertPane(
        _ paneId: UUID,
        inTab tabId: UUID,
        at targetPaneId: UUID,
        direction: Layout.SplitDirection,
        position: Layout.Position
    ) -> Bool {
        guard let tabIndex = findTabIndex(tabId) else {
            workspaceTabLayoutLogger.warning("insertPane: tab \(tabId) not found")
            return false
        }
        let arrIndex = tabs[tabIndex].activeArrangementIndex

        guard tabs[tabIndex].arrangements[arrIndex].layout.contains(targetPaneId) else {
            workspaceTabLayoutLogger.warning("insertPane: targetPaneId \(targetPaneId) not in active arrangement")
            return false
        }

        tabs[tabIndex].zoomedPaneId = nil
        tabs[tabIndex].arrangements[arrIndex].layout = tabs[tabIndex].arrangements[arrIndex].layout
            .inserting(paneId: paneId, at: targetPaneId, direction: direction, position: position)
        tabs[tabIndex].arrangements[arrIndex].visiblePaneIds.insert(paneId)

        if !tabs[tabIndex].arrangements[arrIndex].isDefault {
            let defIdx = tabs[tabIndex].defaultArrangementIndex
            if tabs[tabIndex].arrangements[defIdx].layout.contains(targetPaneId) {
                tabs[tabIndex].arrangements[defIdx].layout = tabs[tabIndex].arrangements[defIdx].layout
                    .inserting(paneId: paneId, at: targetPaneId, direction: direction, position: position)
                tabs[tabIndex].arrangements[defIdx].visiblePaneIds.insert(paneId)
            }
        }

        if !tabs[tabIndex].panes.contains(paneId) {
            tabs[tabIndex].panes.append(paneId)
        }
        return true
    }

    func removePaneFromLayout(_ paneId: UUID, inTab tabId: UUID) {
        guard let tabIndex = findTabIndex(tabId) else {
            workspaceTabLayoutLogger.warning("removePaneFromLayout: tab \(tabId) not found")
            return
        }

        if tabs[tabIndex].zoomedPaneId == paneId {
            tabs[tabIndex].zoomedPaneId = nil
        }
        tabs[tabIndex].minimizedPaneIds.remove(paneId)

        for arrangementIndex in tabs[tabIndex].arrangements.indices {
            if let newLayout = tabs[tabIndex].arrangements[arrangementIndex].layout.removing(paneId: paneId) {
                tabs[tabIndex].arrangements[arrangementIndex].layout = newLayout
            } else {
                tabs[tabIndex].arrangements[arrangementIndex].layout = Layout()
            }
            tabs[tabIndex].arrangements[arrangementIndex].visiblePaneIds.remove(paneId)
        }

        if tabs[tabIndex].activePaneId == paneId {
            let remainingVisiblePaneIds = tabs[tabIndex].activeArrangement.layout.paneIds.filter {
                !tabs[tabIndex].minimizedPaneIds.contains($0)
            }
            tabs[tabIndex].activePaneId = remainingVisiblePaneIds.first
        }

        if tabs[tabIndex].activeArrangement.layout.isEmpty && !tabs[tabIndex].defaultArrangement.layout.isEmpty {
            tabs[tabIndex].activeArrangementId = tabs[tabIndex].defaultArrangement.id
            let fallbackVisiblePaneIds = tabs[tabIndex].activeArrangement.layout.paneIds.filter {
                !tabs[tabIndex].minimizedPaneIds.contains($0)
            }
            tabs[tabIndex].activePaneId = fallbackVisiblePaneIds.first
        }

        tabs[tabIndex].panes.removeAll { $0 == paneId }
        if tabs[tabIndex].panes.isEmpty {
            removeTab(tabId)
        }
    }

    func removePaneReferences(_ paneId: UUID) {
        for tabIndex in tabs.indices {
            tabs[tabIndex].panes.removeAll { $0 == paneId }
            for arrIndex in tabs[tabIndex].arrangements.indices {
                tabs[tabIndex].arrangements[arrIndex].visiblePaneIds.remove(paneId)
                if let newLayout = tabs[tabIndex].arrangements[arrIndex].layout.removing(paneId: paneId) {
                    tabs[tabIndex].arrangements[arrIndex].layout = newLayout
                } else {
                    tabs[tabIndex].arrangements[arrIndex].layout = Layout()
                }
            }
            if tabs[tabIndex].activePaneId == paneId {
                tabs[tabIndex].activePaneId = tabs[tabIndex].activeArrangement.layout.paneIds.first
            }
            if tabs[tabIndex].zoomedPaneId == paneId {
                tabs[tabIndex].zoomedPaneId = nil
            }
            tabs[tabIndex].minimizedPaneIds.remove(paneId)
        }
        tabs.removeAll { $0.defaultArrangement.layout.isEmpty }
        if let activeTabId, !tabs.contains(where: { $0.id == activeTabId }) {
            self.activeTabId = tabs.last?.id
        }
    }

    func resizePane(tabId: UUID, splitId: UUID, ratio: Double) {
        guard let tabIndex = findTabIndex(tabId) else {
            workspaceTabLayoutLogger.warning("resizePane: tab \(tabId) not found")
            return
        }
        let arrIndex = tabs[tabIndex].activeArrangementIndex
        tabs[tabIndex].arrangements[arrIndex].layout = tabs[tabIndex].arrangements[arrIndex].layout
            .resizing(splitId: splitId, ratio: ratio)
    }

    func equalizePanes(tabId: UUID) {
        guard let tabIndex = findTabIndex(tabId) else {
            workspaceTabLayoutLogger.warning("equalizePanes: tab \(tabId) not found")
            return
        }
        let arrIndex = tabs[tabIndex].activeArrangementIndex
        tabs[tabIndex].arrangements[arrIndex].layout = tabs[tabIndex].arrangements[arrIndex].layout.equalized()
    }

    func setActivePane(_ paneId: UUID?, inTab tabId: UUID) {
        guard let tabIndex = findTabIndex(tabId) else {
            workspaceTabLayoutLogger.warning("setActivePane: tab \(tabId) not found")
            return
        }
        if let paneId {
            guard tabs[tabIndex].panes.contains(paneId) else {
                workspaceTabLayoutLogger.warning("setActivePane: paneId \(paneId) not found in tab \(tabId)")
                return
            }
        }
        tabs[tabIndex].activePaneId = paneId
    }

    @discardableResult
    func createArrangement(name: String, paneIds: Set<UUID>, inTab tabId: UUID) -> UUID? {
        guard let tabIndex = findTabIndex(tabId) else {
            workspaceTabLayoutLogger.warning("createArrangement: tab \(tabId) not found")
            return nil
        }
        guard !paneIds.isEmpty else {
            workspaceTabLayoutLogger.warning("createArrangement: empty paneIds")
            return nil
        }
        let tabPaneSet = Set(tabs[tabIndex].panes)
        guard paneIds.isSubset(of: tabPaneSet) else {
            workspaceTabLayoutLogger.warning("createArrangement: paneIds not all in tab \(tabId)")
            return nil
        }

        let defLayout = tabs[tabIndex].defaultArrangement.layout
        let paneIdsToRemove = Set(defLayout.paneIds).subtracting(paneIds)
        var filteredLayout = defLayout
        for removeId in paneIdsToRemove {
            if let newLayout = filteredLayout.removing(paneId: removeId) {
                filteredLayout = newLayout
            }
        }

        let arrangement = PaneArrangement(
            name: name,
            isDefault: false,
            layout: filteredLayout,
            visiblePaneIds: paneIds
        )
        tabs[tabIndex].arrangements.append(arrangement)
        return arrangement.id
    }

    func removeArrangement(_ arrangementId: UUID, inTab tabId: UUID) {
        guard let tabIndex = findTabIndex(tabId) else {
            workspaceTabLayoutLogger.warning("removeArrangement: tab \(tabId) not found")
            return
        }
        guard let arrIndex = tabs[tabIndex].arrangements.firstIndex(where: { $0.id == arrangementId }) else {
            workspaceTabLayoutLogger.warning(
                "removeArrangement: arrangement \(arrangementId) not found in tab \(tabId)"
            )
            return
        }
        guard !tabs[tabIndex].arrangements[arrIndex].isDefault else {
            workspaceTabLayoutLogger.warning("removeArrangement: cannot remove default arrangement")
            return
        }

        if tabs[tabIndex].activeArrangementId == arrangementId {
            tabs[tabIndex].activeArrangementId = tabs[tabIndex].defaultArrangement.id
            if let activePaneId = tabs[tabIndex].activePaneId,
                !tabs[tabIndex].defaultArrangement.layout.contains(activePaneId)
            {
                tabs[tabIndex].activePaneId = tabs[tabIndex].defaultArrangement.layout.paneIds.first
            }
        }
        tabs[tabIndex].arrangements.remove(at: arrIndex)
    }

    func switchArrangement(to arrangementId: UUID, inTab tabId: UUID) {
        guard let tabIndex = findTabIndex(tabId) else {
            workspaceTabLayoutLogger.warning("switchArrangement: tab \(tabId) not found")
            return
        }
        guard tabs[tabIndex].arrangements.contains(where: { $0.id == arrangementId }) else {
            workspaceTabLayoutLogger.warning(
                "switchArrangement: arrangement \(arrangementId) not found in tab \(tabId)"
            )
            return
        }
        guard tabs[tabIndex].activeArrangementId != arrangementId else { return }

        tabs[tabIndex].zoomedPaneId = nil
        tabs[tabIndex].minimizedPaneIds = []
        tabs[tabIndex].activeArrangementId = arrangementId
        if let activePaneId = tabs[tabIndex].activePaneId,
            !tabs[tabIndex].activeArrangement.layout.contains(activePaneId)
        {
            tabs[tabIndex].activePaneId = tabs[tabIndex].activeArrangement.layout.paneIds.first
        }
    }

    func renameArrangement(_ arrangementId: UUID, name: String, inTab tabId: UUID) {
        guard let tabIndex = findTabIndex(tabId) else {
            workspaceTabLayoutLogger.warning("renameArrangement: tab \(tabId) not found")
            return
        }
        guard let arrIndex = tabs[tabIndex].arrangements.firstIndex(where: { $0.id == arrangementId }) else {
            workspaceTabLayoutLogger.warning(
                "renameArrangement: arrangement \(arrangementId) not found in tab \(tabId)"
            )
            return
        }
        tabs[tabIndex].arrangements[arrIndex].name = name
    }

    func toggleZoom(paneId: UUID, inTab tabId: UUID) {
        guard let tabIndex = findTabIndex(tabId) else {
            workspaceTabLayoutLogger.warning("toggleZoom: tab \(tabId) not found")
            return
        }
        if tabs[tabIndex].zoomedPaneId == paneId {
            tabs[tabIndex].zoomedPaneId = nil
        } else if tabs[tabIndex].layout.contains(paneId) {
            tabs[tabIndex].zoomedPaneId = paneId
        }
    }

    @discardableResult
    func minimizePane(_ paneId: UUID, inTab tabId: UUID) -> Bool {
        guard let tabIndex = findTabIndex(tabId) else {
            workspaceTabLayoutLogger.warning("minimizePane: tab \(tabId) not found")
            return false
        }
        let visiblePaneIds = tabs[tabIndex].paneIds
        guard visiblePaneIds.contains(paneId) else {
            workspaceTabLayoutLogger.warning("minimizePane: pane \(paneId) not in active arrangement")
            return false
        }

        tabs[tabIndex].minimizedPaneIds.insert(paneId)
        if tabs[tabIndex].activePaneId == paneId {
            let nonMinimized = visiblePaneIds.filter { !tabs[tabIndex].minimizedPaneIds.contains($0) }
            tabs[tabIndex].activePaneId = nonMinimized.first
        }
        if tabs[tabIndex].zoomedPaneId == paneId {
            tabs[tabIndex].zoomedPaneId = nil
        }
        return true
    }

    func expandPane(_ paneId: UUID, inTab tabId: UUID) {
        guard let tabIndex = findTabIndex(tabId) else {
            workspaceTabLayoutLogger.warning("expandPane: tab \(tabId) not found")
            return
        }
        guard tabs[tabIndex].minimizedPaneIds.contains(paneId) else { return }
        tabs[tabIndex].minimizedPaneIds.remove(paneId)
        tabs[tabIndex].activePaneId = paneId
    }

    func resizePaneByDelta(tabId: UUID, paneId: UUID, direction: SplitResizeDirection, amount: UInt16) {
        guard let tabIndex = findTabIndex(tabId) else {
            workspaceTabLayoutLogger.warning("resizePaneByDelta: tab \(tabId) not found")
            return
        }
        let tab = tabs[tabIndex]
        guard tab.zoomedPaneId == nil else { return }
        guard let (splitId, increase) = tab.layout.resizeTarget(for: paneId, direction: direction) else { return }
        guard let currentRatio = tab.layout.ratioForSplit(splitId) else {
            workspaceTabLayoutLogger.warning("resizePaneByDelta: ratioForSplit returned nil for split \(splitId)")
            return
        }

        let delta = Self.resizeRatioStep * (Double(amount) / Self.resizeBaseAmount)
        let newRatio = min(0.9, max(0.1, increase ? currentRatio + delta : currentRatio - delta))
        let arrIndex = tabs[tabIndex].activeArrangementIndex
        tabs[tabIndex].arrangements[arrIndex].layout = tabs[tabIndex].arrangements[arrIndex].layout
            .resizing(splitId: splitId, ratio: newRatio)
    }

    func breakUpTab(_ tabId: UUID) -> [Tab] {
        guard let tabIndex = findTabIndex(tabId) else { return [] }
        let tabPaneIds = tabs[tabIndex].paneIds
        guard tabPaneIds.count > 1 else { return [] }

        tabs[tabIndex].zoomedPaneId = nil
        tabs.remove(at: tabIndex)

        let newTabs = tabPaneIds.map { Tab(paneId: $0) }
        let insertIndex = min(tabIndex, tabs.count)
        tabs.insert(contentsOf: newTabs, at: insertIndex)
        activeTabId = newTabs.first?.id
        return newTabs
    }

    func extractPane(_ paneId: UUID, fromTab tabId: UUID) -> Tab? {
        guard let tabIndex = findTabIndex(tabId) else { return nil }
        guard tabs[tabIndex].paneIds.count > 1 else { return nil }
        guard tabs[tabIndex].panes.contains(paneId) else {
            workspaceTabLayoutLogger.warning("extractPane: paneId \(paneId) not in tab \(tabId)")
            return nil
        }

        if tabs[tabIndex].zoomedPaneId == paneId {
            tabs[tabIndex].zoomedPaneId = nil
        }

        for arrIndex in tabs[tabIndex].arrangements.indices {
            if let newLayout = tabs[tabIndex].arrangements[arrIndex].layout.removing(paneId: paneId) {
                tabs[tabIndex].arrangements[arrIndex].layout = newLayout
                tabs[tabIndex].arrangements[arrIndex].visiblePaneIds.remove(paneId)
            }
        }
        tabs[tabIndex].panes.removeAll { $0 == paneId }
        if tabs[tabIndex].activePaneId == paneId {
            tabs[tabIndex].activePaneId = tabs[tabIndex].activeArrangement.layout.paneIds.first
        }

        let newTab = Tab(paneId: paneId)
        let insertIndex = tabIndex + 1
        tabs.insert(newTab, at: min(insertIndex, tabs.count))
        activeTabId = newTab.id
        return newTab
    }

    func mergeTab(
        sourceId: UUID,
        intoTarget targetId: UUID,
        at targetPaneId: UUID,
        direction: Layout.SplitDirection,
        position: Layout.Position
    ) {
        guard let sourceTabIndex = tabs.firstIndex(where: { $0.id == sourceId }),
            let targetTabIndex = tabs.firstIndex(where: { $0.id == targetId })
        else { return }

        let targetArrIndex = tabs[targetTabIndex].activeArrangementIndex
        guard tabs[targetTabIndex].arrangements[targetArrIndex].layout.contains(targetPaneId) else {
            workspaceTabLayoutLogger.warning("mergeTab: targetPaneId \(targetPaneId) not in target arrangement")
            return
        }

        tabs[targetTabIndex].zoomedPaneId = nil
        let sourcePaneIds = tabs[sourceTabIndex].paneIds
        var currentTarget = targetPaneId
        for paneId in sourcePaneIds {
            tabs[targetTabIndex].arrangements[targetArrIndex].layout = tabs[targetTabIndex].arrangements[targetArrIndex]
                .layout
                .inserting(paneId: paneId, at: currentTarget, direction: direction, position: position)
            tabs[targetTabIndex].arrangements[targetArrIndex].visiblePaneIds.insert(paneId)
            if !tabs[targetTabIndex].panes.contains(paneId) {
                tabs[targetTabIndex].panes.append(paneId)
            }
            currentTarget = paneId
        }

        tabs.remove(at: sourceTabIndex)
        activeTabId = targetId
    }

    private static let resizeRatioStep: Double = 0.05
    private static let resizeBaseAmount: Double = 10.0

    private func findTabIndex(_ tabId: UUID) -> Int? {
        tabs.firstIndex { $0.id == tabId }
    }

    private func pruneInvalidPanes(validPaneIds: Set<UUID>) {
        for tabIndex in tabs.indices {
            tabs[tabIndex].panes.removeAll { !validPaneIds.contains($0) }
            for arrIndex in tabs[tabIndex].arrangements.indices {
                let invalidIds = tabs[tabIndex].arrangements[arrIndex].layout.paneIds.filter {
                    !validPaneIds.contains($0)
                }
                for paneId in invalidIds {
                    if let newLayout = tabs[tabIndex].arrangements[arrIndex].layout.removing(paneId: paneId) {
                        tabs[tabIndex].arrangements[arrIndex].layout = newLayout
                    } else {
                        tabs[tabIndex].arrangements[arrIndex].layout = Layout()
                    }
                    tabs[tabIndex].arrangements[arrIndex].visiblePaneIds.remove(paneId)
                }
            }
            if let activePaneId = tabs[tabIndex].activePaneId, !validPaneIds.contains(activePaneId) {
                tabs[tabIndex].activePaneId = tabs[tabIndex].activeArrangement.layout.paneIds.first
            }
        }

        tabs.removeAll { $0.defaultArrangement.layout.isEmpty }
        if let activeTabId, !tabs.contains(where: { $0.id == activeTabId }) {
            self.activeTabId = tabs.last?.id
        }
    }

    private func validateTabInvariants() {
        var seenPaneIds: Set<UUID> = []

        for tabIndex in tabs.indices {
            if tabs[tabIndex].arrangements.isEmpty {
                tabs[tabIndex].arrangements = [PaneArrangement(name: "Default", isDefault: true, layout: Layout())]
            }

            if !tabs[tabIndex].arrangements.contains(where: \.isDefault) {
                tabs[tabIndex].arrangements[0].isDefault = true
            }
            for arrangementIndex in tabs[tabIndex].arrangements.indices.dropFirst() {
                if tabs[tabIndex].arrangements[arrangementIndex].isDefault {
                    tabs[tabIndex].arrangements[arrangementIndex].isDefault = false
                }
            }

            let allArrangementPaneIds = Set(tabs[tabIndex].arrangements.flatMap { $0.layout.paneIds })
            tabs[tabIndex].panes = Array(allArrangementPaneIds)

            let duplicatePaneIds = allArrangementPaneIds.intersection(seenPaneIds)
            if !duplicatePaneIds.isEmpty {
                tabs[tabIndex].panes.removeAll { duplicatePaneIds.contains($0) }
                for arrangementIndex in tabs[tabIndex].arrangements.indices {
                    for paneId in duplicatePaneIds {
                        tabs[tabIndex].arrangements[arrangementIndex].visiblePaneIds.remove(paneId)
                        if let newLayout = tabs[tabIndex].arrangements[arrangementIndex].layout.removing(paneId: paneId)
                        {
                            tabs[tabIndex].arrangements[arrangementIndex].layout = newLayout
                        } else {
                            tabs[tabIndex].arrangements[arrangementIndex].layout = Layout()
                        }
                    }
                }
            }

            let validPaneIds = Set(tabs[tabIndex].panes)
            for arrangementIndex in tabs[tabIndex].arrangements.indices {
                let arrangementPaneIds = Set(tabs[tabIndex].arrangements[arrangementIndex].layout.paneIds)
                tabs[tabIndex].arrangements[arrangementIndex].visiblePaneIds.formIntersection(validPaneIds)
                tabs[tabIndex].arrangements[arrangementIndex].visiblePaneIds.formIntersection(arrangementPaneIds)
            }

            if !tabs[tabIndex].arrangements.contains(where: { $0.id == tabs[tabIndex].activeArrangementId }) {
                tabs[tabIndex].activeArrangementId = tabs[tabIndex].defaultArrangement.id
            }

            tabs[tabIndex].minimizedPaneIds.formIntersection(validPaneIds)
            if let zoomedPaneId = tabs[tabIndex].zoomedPaneId, !validPaneIds.contains(zoomedPaneId) {
                tabs[tabIndex].zoomedPaneId = nil
            }
            if let activePaneId = tabs[tabIndex].activePaneId, !validPaneIds.contains(activePaneId) {
                tabs[tabIndex].activePaneId = tabs[tabIndex].activeArrangement.layout.paneIds.first
            }

            seenPaneIds.formUnion(validPaneIds)
        }

        tabs.removeAll { $0.defaultArrangement.layout.isEmpty }
        if let activeTabId, !tabs.contains(where: { $0.id == activeTabId }) {
            self.activeTabId = tabs.last?.id
        }
    }
}
