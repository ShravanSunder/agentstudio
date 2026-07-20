import Foundation

@MainActor
struct RuntimeTargetResolver {
    let workspaceStore: WorkspaceStore

    func resolve(_ target: RuntimeCommandTarget) -> PaneId? {
        let workspacePane = workspaceStore.paneAtom
        let workspaceTab = WorkspaceTabLayoutDerived(
            shellAtom: workspaceStore.tabShellAtom,
            arrangementAtom: workspaceStore.tabArrangementAtom
        )
        switch target {
        case .pane(let paneId):
            return workspacePane.pane(paneId.uuid) == nil ? nil : paneId
        case .activePane:
            guard let uuid = workspaceTab.activeTab?.activePaneId else { return nil }
            return PaneId(existingUUID: uuid)
        case .activePaneInTab(let tabId):
            guard let uuid = workspaceTab.tab(tabId)?.activePaneId else { return nil }
            return PaneId(existingUUID: uuid)
        }
    }
}
