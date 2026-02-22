import Foundation

@MainActor
struct PaneTargetResolver {
    let workspaceStore: WorkspaceStore

    func resolve(_ target: PaneCommandTarget) -> PaneId? {
        switch target {
        case .pane(let paneId):
            return workspaceStore.pane(paneId.uuid) == nil ? nil : paneId
        case .activePane:
            guard let uuid = workspaceStore.activeTab?.activePaneId else { return nil }
            return PaneId(uuid: uuid)
        case .activePaneInTab(let tabId):
            guard let uuid = workspaceStore.tab(tabId)?.activePaneId else { return nil }
            return PaneId(uuid: uuid)
        }
    }
}
