import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite("WorkspaceIdentityAtom")
struct WorkspaceIdentityAtomTests {
    @Test("identity starts with a default workspace identity")
    func identityStartsWithDefaultWorkspaceIdentity() {
        let atom = WorkspaceIdentityAtom(workspaceId: UUIDv7.generate())

        #expect(atom.workspaceName == "Default Workspace")
        #expect(atom.createdAt <= Date())
    }

    @Test("identity replacement updates only workspace identity fields")
    func identityReplacementUpdatesOnlyWorkspaceIdentityFields() {
        let atom = WorkspaceIdentityAtom(workspaceId: UUIDv7.generate())
        let workspaceId = UUID()
        let createdAt = Date(timeIntervalSince1970: 1_714_000_000)

        atom.replaceIdentity(
            workspaceId: workspaceId,
            workspaceName: "SQLite Cutover",
            createdAt: createdAt
        )

        #expect(atom.workspaceId == workspaceId)
        #expect(atom.workspaceName == "SQLite Cutover")
        #expect(atom.createdAt == createdAt)
    }

    @Test("workspace name mutation stays on identity atom")
    func workspaceNameMutationStaysOnIdentityAtom() {
        let atom = WorkspaceIdentityAtom(workspaceId: UUIDv7.generate())

        atom.setWorkspaceName("Renamed")

        #expect(atom.workspaceName == "Renamed")
    }

}
