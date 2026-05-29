import Foundation
import Observation

@MainActor
@Observable
final class WorkspaceIdentityAtom {
    private(set) var workspaceId = UUID()
    private(set) var workspaceName = "Default Workspace"
    private(set) var createdAt = Date()

    func hydrate(
        workspaceId: UUID,
        workspaceName: String,
        createdAt: Date
    ) {
        self.workspaceId = workspaceId
        self.workspaceName = workspaceName
        self.createdAt = createdAt
    }

    func setWorkspaceName(_ workspaceName: String) {
        guard self.workspaceName != workspaceName else { return }
        self.workspaceName = workspaceName
    }
}
