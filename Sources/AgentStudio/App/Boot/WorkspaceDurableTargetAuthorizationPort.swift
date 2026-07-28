import Foundation

@MainActor
final class WorkspaceDurableTargetAuthorizationPort: WorkspaceDurableTargetAuthorizing {
    private let workspaceStore: WorkspaceStore

    init(workspaceStore: WorkspaceStore) {
        self.workspaceStore = workspaceStore
    }

    func containsRepository(id: UUID) -> Bool {
        workspaceStore.programmaticControlSnapshot().repositories.contains { $0.id == id }
    }

    func containsTab(id: UUID) -> Bool {
        workspaceStore.programmaticControlSnapshot().tabs.contains { $0.id == id }
    }

    func containsPane(id: UUID) -> Bool {
        workspaceStore.programmaticControlSnapshot().panes.contains { pane in
            pane.id == id && pane.tabId != nil
        }
    }
}
