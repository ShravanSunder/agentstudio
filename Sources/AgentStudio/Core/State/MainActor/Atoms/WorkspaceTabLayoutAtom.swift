import Foundation

@MainActor
package final class WorkspaceTabLayoutAtom {
    package let shellAtom: WorkspaceTabShellAtom
    package let arrangementAtom: WorkspaceTabArrangementAtom

    private var derived: WorkspaceTabLayoutDerived {
        WorkspaceTabLayoutDerived(shellAtom: shellAtom, arrangementAtom: arrangementAtom)
    }

    package init(
        shellAtom: WorkspaceTabShellAtom = WorkspaceTabShellAtom(),
        arrangementAtom: WorkspaceTabArrangementAtom = WorkspaceTabArrangementAtom()
    ) {
        self.shellAtom = shellAtom
        self.arrangementAtom = arrangementAtom
    }

    func replaceTabs(
        _ tabs: [Tab],
        activeTabId: UUID?,
        validPaneIds: Set<UUID>,
        drawerParentPaneIdByDrawerId: [UUID: UUID]? = nil
    ) {
        let shells = tabs.map { TabShell(id: $0.id, name: $0.name, colorHex: $0.colorHex) }
        shellAtom.replaceTabShells(shells)
        shellAtom.cursorAtom.replaceActiveTab(
            activeTabId.flatMap { selectedID in shells.contains(where: { $0.id == selectedID }) ? selectedID : nil }
                ?? shells.first?.id
        )
        arrangementAtom.replaceTabs(
            tabs,
            validPaneIds: validPaneIds,
            drawerParentPaneIdByDrawerId: drawerParentPaneIdByDrawerId
        )
        removeTabsWithoutArrangementState()
    }

    package var tabs: [Tab] {
        derived.tabs
    }

    package var activeTabId: UUID? {
        shellAtom.activeTabId
    }

    package var activeTab: Tab? {
        derived.activeTab
    }

    var activePaneIds: Set<UUID> {
        derived.activePaneIds
    }

    package var allPaneIds: Set<UUID> {
        derived.allPaneIds
    }

    package func tab(_ id: UUID) -> Tab? {
        derived.tab(id)
    }

    package func tabContaining(paneId: UUID) -> Tab? {
        derived.tabContaining(paneId: paneId)
    }

    package func tabID(containingPane paneID: UUID) -> UUID? {
        arrangementAtom.graphAtom.tabID(containingPane: paneID)
    }

    package func activePaneID(forTab tabID: UUID) -> UUID? {
        guard let arrangementID = arrangementAtom.cursorAtom.activeArrangementId(forTab: tabID) else {
            return nil
        }
        return arrangementAtom.cursorAtom.activePaneId(forArrangement: arrangementID)
    }

    package func containsTab(_ tabID: UUID) -> Bool {
        arrangementAtom.graphAtom.containsTab(tabID)
    }

    package func activeArrangementIsSplit(forTab tabID: UUID) -> Bool {
        guard
            let arrangementID = arrangementAtom.cursorAtom.activeArrangementId(forTab: tabID),
            let tabState = arrangementAtom.graphAtom.tabState(tabID),
            let arrangement = tabState.arrangements.first(where: { $0.id == arrangementID })
        else {
            return false
        }
        return arrangement.layout.isSplit
    }

    package func appendTab(_ tab: Tab) {
        shellAtom.appendTabShell(TabShell(id: tab.id, name: tab.name, colorHex: tab.colorHex))
        arrangementAtom.appendState(Self.arrangementState(from: tab))
    }

    package func removeTab(_ tabId: UUID) {
        shellAtom.removeTabShell(tabId)
        arrangementAtom.removeState(tabId)
    }

    package func insertTab(_ tab: Tab, at index: Int) {
        shellAtom.insertTabShell(TabShell(id: tab.id, name: tab.name, colorHex: tab.colorHex), at: index)
        arrangementAtom.insertState(Self.arrangementState(from: tab), at: index)
    }

    package func restoreTab(_ tab: Tab, at index: Int) {
        if shellAtom.tabShell(tab.id) == nil {
            shellAtom.insertTabShell(TabShell(id: tab.id, name: tab.name, colorHex: tab.colorHex), at: index)
        } else {
            shellAtom.renameTab(tab.id, name: tab.name)
            try? shellAtom.setTabColorHex(tab.colorHex, tabId: tab.id)
        }
        arrangementAtom.removeState(tab.id)
        arrangementAtom.insertState(Self.arrangementState(from: tab), at: index)
    }

    package func moveTab(fromId: UUID, toIndex: Int) {
        shellAtom.moveTab(fromId: fromId, toIndex: toIndex)
    }

    package func reorderTab(_ tabId: UUID, to newIndex: Int) {
        guard shellAtom.tabShell(tabId) != nil else { return }
        guard newIndex >= 0 && newIndex < shellAtom.tabShells.count else { return }
        shellAtom.moveTab(fromId: tabId, toIndex: newIndex)
    }

    package func moveTabByDelta(tabId: UUID, delta: Int) {
        shellAtom.moveTabByDelta(tabId: tabId, delta: delta)
    }

    package func setActiveTab(_ tabId: UUID?) {
        shellAtom.setActiveTab(tabId)
    }

    @discardableResult
    package func insertPane(
        _ paneId: UUID,
        inTab tabId: UUID,
        at targetPaneId: UUID,
        direction: Layout.SplitDirection,
        position: Layout.Position,
        sizingMode: DropSizingMode
    ) -> Bool {
        arrangementAtom.insertPane(
            paneId,
            inTab: tabId,
            at: targetPaneId,
            direction: direction,
            position: position,
            sizingMode: sizingMode
        )
    }

    package func removePaneFromLayout(_ paneId: UUID, inTab tabId: UUID, removingDrawerId drawerId: UUID? = nil) {
        arrangementAtom.removePaneFromLayout(paneId, inTab: tabId, removingDrawerId: drawerId)
        removeEmptyTabs()
    }

    func removePaneReferences(_ paneId: UUID, removingDrawerIds drawerIds: Set<UUID> = []) {
        arrangementAtom.removePaneReferences(Set([paneId]), removingDrawerIds: drawerIds)
        removeEmptyTabs()
    }

    package func resizePane(tabId: UUID, splitId: UUID, ratio: Double) {
        arrangementAtom.resizePane(tabId: tabId, splitId: splitId, ratio: ratio)
    }

    package func resizeVisiblePanePair(tabId: UUID, leftPaneId: UUID, rightPaneId: UUID, ratio: Double) {
        arrangementAtom.resizeVisiblePanePair(
            tabId: tabId,
            leftPaneId: leftPaneId,
            rightPaneId: rightPaneId,
            ratio: ratio
        )
    }

    package func equalizePanes(tabId: UUID) {
        arrangementAtom.equalizePanes(tabId: tabId)
    }

    package func setActivePane(_ paneId: UUID?, inTab tabId: UUID) {
        arrangementAtom.setActivePane(paneId, inTab: tabId)
    }

    @discardableResult
    package func createArrangement(name: String, inTab tabId: UUID) -> UUID? {
        arrangementAtom.createArrangement(name: name, inTab: tabId)
    }

    package func removeArrangement(_ arrangementId: UUID, inTab tabId: UUID) {
        arrangementAtom.removeArrangement(arrangementId, inTab: tabId)
    }

    package func switchArrangement(to arrangementId: UUID, inTab tabId: UUID) {
        arrangementAtom.switchArrangement(to: arrangementId, inTab: tabId)
    }

    package func renameArrangement(_ arrangementId: UUID, name: String, inTab tabId: UUID) {
        arrangementAtom.renameArrangement(arrangementId, name: name, inTab: tabId)
    }

    package func renameTab(_ tabId: UUID, name: String) {
        shellAtom.renameTab(tabId, name: name)
    }

    func setTabColorHex(_ colorHex: String?, tabId: UUID) throws {
        try shellAtom.setTabColorHex(colorHex, tabId: tabId)
    }

    @discardableResult
    package func minimizePane(_ paneId: UUID, inTab tabId: UUID) -> Bool {
        arrangementAtom.minimizePane(paneId, inTab: tabId)
    }

    package func expandPane(_ paneId: UUID, inTab tabId: UUID) {
        arrangementAtom.expandPane(paneId, inTab: tabId)
    }

    package func resizePaneByDelta(tabId: UUID, paneId: UUID, direction: SplitResizeDirection, amount: UInt16) {
        arrangementAtom.resizePaneByDelta(tabId: tabId, paneId: paneId, direction: direction, amount: amount)
    }

    package func breakUpTab(
        _ tabId: UUID,
        drawerPayloadsByParentPaneId: [UUID: PaneDrawerMovePayload] = [:]
    ) -> [Tab] {
        guard let tabIndex = shellAtom.tabShells.firstIndex(where: { $0.id == tabId }) else { return [] }
        let newStates = arrangementAtom.breakUpTab(
            tabId,
            drawerPayloadsByParentPaneId: drawerPayloadsByParentPaneId
        )
        guard !newStates.isEmpty else { return [] }

        shellAtom.removeTabShell(tabId)
        for (offset, state) in newStates.enumerated() {
            shellAtom.insertTabShell(TabShell(id: state.tabId, name: "Tab"), at: tabIndex + offset)
        }
        shellAtom.setActiveTab(newStates.first?.tabId)
        return newStates.compactMap { derived.tab($0.tabId) }
    }

    package func extractPane(
        _ paneId: UUID,
        fromTab tabId: UUID,
        drawerPayload: PaneDrawerMovePayload? = nil
    ) -> Tab? {
        guard let sourceIndex = shellAtom.tabShells.firstIndex(where: { $0.id == tabId }) else { return nil }
        guard
            let newState = arrangementAtom.extractPane(
                paneId,
                fromTab: tabId,
                drawerPayload: drawerPayload
            )
        else { return nil }
        shellAtom.insertTabShell(TabShell(id: newState.tabId, name: "Tab"), at: sourceIndex + 1)
        shellAtom.setActiveTab(newState.tabId)
        return derived.tab(newState.tabId)
    }

    @discardableResult
    package func movePaneAcrossTabs(_ mutation: CrossTabPaneMoveMutation) -> CrossTabPaneMoveResult? {
        guard let result = arrangementAtom.movePaneAcrossTabs(mutation) else { return nil }

        if result.sourceTabClosed {
            shellAtom.removeTabShell(mutation.request.sourceTabId)
            arrangementAtom.removeState(mutation.request.sourceTabId)
        }
        shellAtom.setActiveTab(mutation.request.destTabId)
        return result
    }

    package func mergeTab(
        sourceId: UUID,
        intoTarget targetId: UUID,
        at targetPaneId: UUID,
        direction: Layout.SplitDirection,
        position: Layout.Position,
        drawerPayloadsByParentPaneId: [UUID: PaneDrawerMovePayload] = [:]
    ) {
        guard sourceId != targetId else { return }
        arrangementAtom.mergeTab(
            sourceId: sourceId,
            intoTarget: targetId,
            at: targetPaneId,
            direction: direction,
            position: position,
            drawerPayloadsByParentPaneId: drawerPayloadsByParentPaneId
        )
        shellAtom.removeTabShell(sourceId)
        shellAtom.setActiveTab(targetId)
    }

    private func removeTabsWithoutArrangementState() {
        let validTabIds = Set(arrangementAtom.arrangementStates.map(\.tabId))
        for shell in shellAtom.tabShells where !validTabIds.contains(shell.id) {
            shellAtom.removeTabShell(shell.id)
        }
    }

    private func removeEmptyTabs() {
        for state in arrangementAtom.arrangementStates {
            if !TabArrangementRepairRules.hasLivePaneReferences(in: state.arrangements) {
                removeTab(state.tabId)
            }
        }
        removeTabsWithoutArrangementState()
    }

    private static func arrangementState(from tab: Tab) -> TabArrangementState {
        TabArrangementState(
            tabId: tab.id,
            allPaneIds: tab.allPaneIds,
            arrangements: tab.arrangements,
            activeArrangementId: tab.activeArrangementId
        )
    }
}
