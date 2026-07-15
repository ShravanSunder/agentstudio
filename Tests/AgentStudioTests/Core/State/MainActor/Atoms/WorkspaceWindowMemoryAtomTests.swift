import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite("WorkspaceWindowMemoryAtom")
struct WorkspaceWindowMemoryAtomTests {
    @Test("window memory starts with default local geometry")
    func windowMemoryStartsWithDefaultLocalGeometry() {
        let atom = WorkspaceWindowMemoryAtom()

        #expect(atom.sidebarWidth == 250)
        #expect(atom.windowFrame == nil)
    }

    @Test("hydrate updates only local window memory fields")
    func hydrateUpdatesOnlyLocalWindowMemoryFields() {
        let atom = WorkspaceWindowMemoryAtom()
        let frame = CGRect(x: 12, y: 34, width: 900, height: 700)

        atom.hydrate(sidebarWidth: 320, windowFrame: frame)

        #expect(atom.sidebarWidth == 320)
        #expect(atom.windowFrame == frame)
    }

    @Test("sidebar and window frame mutate independently from identity")
    func sidebarAndWindowFrameMutateIndependentlyFromIdentity() {
        let identity = WorkspaceIdentityAtom()
        let initialWorkspaceId = identity.workspaceId
        let memory = WorkspaceWindowMemoryAtom()
        let frame = CGRect(x: 4, y: 5, width: 600, height: 500)

        memory.setSidebarWidth(300)
        memory.setWindowFrame(frame)

        #expect(identity.workspaceId == initialWorkspaceId)
        #expect(identity.workspaceName == "Default Workspace")
        #expect(memory.sidebarWidth == 300)
        #expect(memory.windowFrame == frame)
    }

    @Test("prepared window replacement uses one exact transaction")
    func preparedWindowReplacementUsesOneExactTransaction() throws {
        let atom = WorkspaceWindowMemoryAtom()
        let revisionOwner = WorkspacePersistenceRevisionOwner()
        let frame = CGRect(x: 8, y: 13, width: 987, height: 654)
        guard case .constructed = atom.makePersistenceSnapshotParticipant() else {
            Issue.record("window-memory snapshot participant construction failed")
            return
        }

        let committedTransaction = try revisionOwner.performSynchronousTransaction { preparation in
            try atom.prepareHydrate(
                sidebarWidth: 333,
                windowFrame: frame,
                for: preparation,
                revisionOwner: revisionOwner
            )
        }

        #expect(committedTransaction == revisionOwner.committedRevision)
        #expect(atom.sidebarWidth == 333)
        #expect(atom.windowFrame == frame)
        #expect(
            atom.persistenceSnapshotValue(for: .windowMemory)
                == .value(.init(sidebarWidth: 333, windowFrame: frame))
        )
    }

    @Test("failed window preparation changes neither owner nor revision")
    func failedWindowPreparationChangesNeitherOwnerNorRevision() {
        let atom = WorkspaceWindowMemoryAtom()
        let revisionOwner = WorkspacePersistenceRevisionOwner()
        guard case .constructed = atom.makePersistenceSnapshotParticipant() else {
            Issue.record("window-memory snapshot participant construction failed")
            return
        }

        #expect(throws: WorkspaceWindowMemorySnapshotPreparationError.self) {
            try revisionOwner.performSynchronousTransaction { preparation in
                _ = try atom.prepareSetSidebarWidth(
                    300,
                    for: preparation,
                    revisionOwner: revisionOwner
                )
                return try atom.prepareSetWindowFrame(
                    CGRect(x: 1, y: 2, width: 3, height: 4),
                    for: preparation,
                    revisionOwner: revisionOwner
                )
            }
        }

        #expect(revisionOwner.committedRevision == .zero)
        #expect(atom.sidebarWidth == 250)
        #expect(atom.windowFrame == nil)
    }
}
