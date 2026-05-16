import Foundation

@MainActor
final class WorkspaceTabLayoutAtom {
    let shellAtom: WorkspaceTabShellAtom
    let arrangementAtom: WorkspaceTabArrangementAtom

    private var derived: WorkspaceTabDerived {
        WorkspaceTabDerived(shellAtom: shellAtom, arrangementAtom: arrangementAtom)
    }

    init(
        shellAtom: WorkspaceTabShellAtom = WorkspaceTabShellAtom(),
        arrangementAtom: WorkspaceTabArrangementAtom = WorkspaceTabArrangementAtom()
    ) {
        self.shellAtom = shellAtom
        self.arrangementAtom = arrangementAtom
    }

    func hydrate(persistedTabs: [Tab], activeTabId: UUID?, validPaneIds: Set<UUID>) {
        shellAtom.hydrate(persistedTabs: persistedTabs, activeTabId: activeTabId)
        arrangementAtom.hydrate(persistedTabs: persistedTabs, validPaneIds: validPaneIds)
        removeTabsWithoutArrangementState()
    }

    var tabs: [Tab] {
        derived.tabs
    }

    var activeTabId: UUID? {
        shellAtom.activeTabId
    }

    var activeTab: Tab? {
        derived.activeTab
    }

    var activePaneIds: Set<UUID> {
        derived.activePaneIds
    }

    var allPaneIds: Set<UUID> {
        derived.allPaneIds
    }

    func tab(_ id: UUID) -> Tab? {
        derived.tab(id)
    }

    func tabContaining(paneId: UUID) -> Tab? {
        derived.tabContaining(paneId: paneId)
    }

    func appendTab(_ tab: Tab) {
        shellAtom.appendTabShell(TabShell(id: tab.id, name: tab.name))
        arrangementAtom.appendState(Self.arrangementState(from: tab))
    }

    func removeTab(_ tabId: UUID) {
        shellAtom.removeTabShell(tabId)
        arrangementAtom.removeState(tabId)
    }

    func insertTab(_ tab: Tab, at index: Int) {
        shellAtom.insertTabShell(TabShell(id: tab.id, name: tab.name), at: index)
        arrangementAtom.insertState(Self.arrangementState(from: tab), at: index)
    }

    func moveTab(fromId: UUID, toIndex: Int) {
        shellAtom.moveTab(fromId: fromId, toIndex: toIndex)
    }

    func moveTabByDelta(tabId: UUID, delta: Int) {
        shellAtom.moveTabByDelta(tabId: tabId, delta: delta)
    }

    func setActiveTab(_ tabId: UUID?) {
        shellAtom.setActiveTab(tabId)
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
        arrangementAtom.insertPane(
            paneId,
            inTab: tabId,
            at: targetPaneId,
            direction: direction,
            position: position,
            sizingMode: sizingMode
        )
    }

    func removePaneFromLayout(_ paneId: UUID, inTab tabId: UUID, removingDrawerId drawerId: UUID? = nil) {
        arrangementAtom.removePaneFromLayout(paneId, inTab: tabId, removingDrawerId: drawerId)
        removeEmptyTabs()
    }

    func removePaneReferences(_ paneId: UUID, removingDrawerIds drawerIds: Set<UUID> = []) {
        arrangementAtom.removePaneReferences(paneId, removingDrawerIds: drawerIds)
        removeEmptyTabs()
    }

    func resizePane(tabId: UUID, splitId: UUID, ratio: Double) {
        arrangementAtom.resizePane(tabId: tabId, splitId: splitId, ratio: ratio)
    }

    func equalizePanes(tabId: UUID) {
        arrangementAtom.equalizePanes(tabId: tabId)
    }

    func setActivePane(_ paneId: UUID?, inTab tabId: UUID) {
        arrangementAtom.setActivePane(paneId, inTab: tabId)
    }

    @discardableResult
    func createArrangement(name: String, inTab tabId: UUID) -> UUID? {
        arrangementAtom.createArrangement(name: name, inTab: tabId)
    }

    func removeArrangement(_ arrangementId: UUID, inTab tabId: UUID) {
        arrangementAtom.removeArrangement(arrangementId, inTab: tabId)
    }

    func switchArrangement(to arrangementId: UUID, inTab tabId: UUID) {
        arrangementAtom.switchArrangement(to: arrangementId, inTab: tabId)
    }

    func renameArrangement(_ arrangementId: UUID, name: String, inTab tabId: UUID) {
        arrangementAtom.renameArrangement(arrangementId, name: name, inTab: tabId)
    }

    func renameTab(_ tabId: UUID, name: String) {
        shellAtom.renameTab(tabId, name: name)
    }

    func toggleZoom(paneId: UUID, inTab tabId: UUID) {
        arrangementAtom.toggleZoom(paneId: paneId, inTab: tabId)
    }

    @discardableResult
    func minimizePane(_ paneId: UUID, inTab tabId: UUID) -> Bool {
        arrangementAtom.minimizePane(paneId, inTab: tabId)
    }

    func expandPane(_ paneId: UUID, inTab tabId: UUID) {
        arrangementAtom.expandPane(paneId, inTab: tabId)
    }

    func resizePaneByDelta(tabId: UUID, paneId: UUID, direction: SplitResizeDirection, amount: UInt16) {
        arrangementAtom.resizePaneByDelta(tabId: tabId, paneId: paneId, direction: direction, amount: amount)
    }

    func breakUpTab(_ tabId: UUID) -> [Tab] {
        guard let tabIndex = shellAtom.tabShells.firstIndex(where: { $0.id == tabId }) else { return [] }
        let newStates = arrangementAtom.breakUpTab(tabId)
        guard !newStates.isEmpty else { return [] }

        shellAtom.removeTabShell(tabId)
        for (offset, state) in newStates.enumerated() {
            shellAtom.insertTabShell(TabShell(id: state.tabId, name: "Tab"), at: tabIndex + offset)
        }
        shellAtom.setActiveTab(newStates.first?.tabId)
        return newStates.compactMap { derived.tab($0.tabId) }
    }

    func extractPane(_ paneId: UUID, fromTab tabId: UUID) -> Tab? {
        guard let sourceIndex = shellAtom.tabShells.firstIndex(where: { $0.id == tabId }) else { return nil }
        guard let newState = arrangementAtom.extractPane(paneId, fromTab: tabId) else { return nil }
        shellAtom.insertTabShell(TabShell(id: newState.tabId, name: "Tab"), at: sourceIndex + 1)
        shellAtom.setActiveTab(newState.tabId)
        return derived.tab(newState.tabId)
    }

    func mergeTab(
        sourceId: UUID,
        intoTarget targetId: UUID,
        at targetPaneId: UUID,
        direction: Layout.SplitDirection,
        position: Layout.Position
    ) {
        guard sourceId != targetId else { return }
        arrangementAtom.mergeTab(
            sourceId: sourceId,
            intoTarget: targetId,
            at: targetPaneId,
            direction: direction,
            position: position
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
            let defaultLayoutIsEmpty =
                state.arrangements.first(where: \.isDefault)?.layout.isEmpty
                ?? state.arrangements.first?.layout.isEmpty
                ?? true
            if state.allPaneIds.isEmpty || defaultLayoutIsEmpty {
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
            activeArrangementId: tab.activeArrangementId,
            zoomedPaneId: tab.zoomedPaneId
        )
    }
}
