import Foundation
import Observation

enum WorkspaceIdentityInstallationState {
    case awaitingCanonicalComposition
    case installed(workspaceId: UUID, workspaceName: String, createdAt: Date)
}

@MainActor
@Observable
final class WorkspaceIdentityAtom {
    var workspaceId: UUID { installedIdentity.workspaceId }
    var workspaceName: String { installedIdentity.workspaceName }
    var createdAt: Date { installedIdentity.createdAt }

    private var installationState: WorkspaceIdentityInstallationState

    init(installationState: WorkspaceIdentityInstallationState) {
        self.installationState = installationState
    }

    init(
        workspaceId: UUID,
        workspaceName: String = "Default Workspace",
        createdAt: Date = Date()
    ) {
        installationState = .installed(
            workspaceId: workspaceId,
            workspaceName: workspaceName,
            createdAt: createdAt
        )
    }

    func replaceIdentity(
        workspaceId: UUID,
        workspaceName: String,
        createdAt: Date
    ) {
        installationState = .installed(
            workspaceId: workspaceId,
            workspaceName: workspaceName,
            createdAt: createdAt
        )
    }

    func setWorkspaceName(_ workspaceName: String) {
        let identity = installedIdentity
        guard identity.workspaceName != workspaceName else { return }
        installationState = .installed(
            workspaceId: identity.workspaceId,
            workspaceName: workspaceName,
            createdAt: identity.createdAt
        )
    }

    private var installedIdentity: (workspaceId: UUID, workspaceName: String, createdAt: Date) {
        guard case .installed(let workspaceId, let workspaceName, let createdAt) = installationState else {
            preconditionFailure("workspace identity accessed before canonical composition installation")
        }
        return (workspaceId, workspaceName, createdAt)
    }
}
