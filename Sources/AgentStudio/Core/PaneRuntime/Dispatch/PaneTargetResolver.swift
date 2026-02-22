import Foundation

@MainActor
struct PaneTargetResolver {
    let workspaceStore: WorkspaceStore

    func resolve(_ target: PaneCommandTarget) -> PaneId? {
        switch target {
        case .pane(let paneId):
            return workspaceStore.pane(paneId) == nil ? nil : paneId
        case .activePane:
            return workspaceStore.activeTab?.activePaneId
        case .activePaneInTab(let tabId):
            return workspaceStore.tab(tabId)?.activePaneId
        }
    }
}
