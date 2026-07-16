import Foundation
import Observation

@MainActor
@Observable
final class WorkspaceIdentityAtom {
    var workspaceId: UUID { storedWorkspaceId }
    var workspaceName: String { storedWorkspaceName }
    var createdAt: Date { storedCreatedAt }

    private var storedWorkspaceId: UUID
    private var storedWorkspaceName: String
    private var storedCreatedAt: Date

    init(
        workspaceId: UUID = UUIDv7.generate(),
        workspaceName: String = "Default Workspace",
        createdAt: Date = Date()
    ) {
        storedWorkspaceId = workspaceId
        storedWorkspaceName = workspaceName
        storedCreatedAt = createdAt
    }

    func replaceIdentity(
        workspaceId: UUID,
        workspaceName: String,
        createdAt: Date
    ) {
        storedWorkspaceId = workspaceId
        storedWorkspaceName = workspaceName
        storedCreatedAt = createdAt
    }

    func setWorkspaceName(_ workspaceName: String) {
        guard storedWorkspaceName != workspaceName else { return }
        storedWorkspaceName = workspaceName
    }
}
