import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite("WorkspaceIdentityAtom")
struct WorkspaceIdentityAtomTests {
    @Test("identity starts with a default workspace identity")
    func identityStartsWithDefaultWorkspaceIdentity() {
        let atom = WorkspaceIdentityAtom()

        #expect(atom.workspaceName == "Default Workspace")
        #expect(atom.createdAt <= Date())
    }

    @Test("hydrate updates only workspace identity fields")
    func hydrateUpdatesOnlyWorkspaceIdentityFields() {
        let atom = WorkspaceIdentityAtom()
        let workspaceId = UUID()
        let createdAt = Date(timeIntervalSince1970: 1_714_000_000)

        atom.hydrate(
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
        let atom = WorkspaceIdentityAtom()

        atom.setWorkspaceName("Renamed")

        #expect(atom.workspaceName == "Renamed")
    }

    @Test("prepared identity replacement uses one exact transaction")
    func preparedIdentityReplacementUsesOneExactTransaction() throws {
        let atom = WorkspaceIdentityAtom()
        let revisionOwner = WorkspacePersistenceRevisionOwner()
        let replacementID = UUID()
        let replacementDate = Date(timeIntervalSince1970: 1_720_000_000)
        guard case .constructed = atom.makePersistenceSnapshotParticipant() else {
            Issue.record("identity snapshot participant construction failed")
            return
        }

        let committedTransaction = try revisionOwner.performSynchronousTransaction { preparation in
            try atom.prepareHydrate(
                workspaceId: replacementID,
                workspaceName: "Prepared",
                createdAt: replacementDate,
                for: preparation,
                revisionOwner: revisionOwner
            )
        }

        #expect(committedTransaction == revisionOwner.committedRevision)
        #expect(atom.workspaceId == replacementID)
        #expect(atom.workspaceName == "Prepared")
        #expect(atom.createdAt == replacementDate)
        #expect(
            atom.persistenceSnapshotValue(for: .identity)
                == .value(
                    .init(
                        workspaceID: replacementID,
                        workspaceName: "Prepared",
                        createdAt: replacementDate
                    )
                )
        )
    }

    @Test("failed identity preparation changes neither owner nor revision")
    func failedIdentityPreparationChangesNeitherOwnerNorRevision() {
        let atom = WorkspaceIdentityAtom()
        let revisionOwner = WorkspacePersistenceRevisionOwner()
        let originalID = atom.workspaceId
        let originalName = atom.workspaceName
        let originalDate = atom.createdAt
        guard case .constructed = atom.makePersistenceSnapshotParticipant() else {
            Issue.record("identity snapshot participant construction failed")
            return
        }

        #expect(throws: WorkspaceIdentitySnapshotPreparationError.self) {
            try revisionOwner.performSynchronousTransaction { preparation in
                _ = try atom.prepareSetWorkspaceName(
                    "First",
                    for: preparation,
                    revisionOwner: revisionOwner
                )
                return try atom.prepareSetWorkspaceName(
                    "Rejected",
                    for: preparation,
                    revisionOwner: revisionOwner
                )
            }
        }

        #expect(revisionOwner.committedRevision == .zero)
        #expect(atom.workspaceId == originalID)
        #expect(atom.workspaceName == originalName)
        #expect(atom.createdAt == originalDate)
    }
}
