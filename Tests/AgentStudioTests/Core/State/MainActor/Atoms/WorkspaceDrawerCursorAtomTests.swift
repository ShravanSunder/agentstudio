import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite("WorkspaceDrawerCursorAtom fixed-revision participation")
struct WorkspaceDrawerCursorAtomTests {
    @Test("prepared expanded drawer replaces membership and removes it on collapse")
    func preparedExpandedDrawerReplacesMembershipAndRemovesItOnCollapse() throws {
        let atom = WorkspaceDrawerCursorAtom()
        let revisionOwner = WorkspacePersistenceRevisionOwner()
        let firstDrawerID = UUID()
        let secondDrawerID = UUID()
        guard case .constructed = atom.makePersistenceSnapshotParticipant() else {
            Issue.record("expanded-drawer snapshot participant construction failed")
            return
        }

        let insertionTransaction = try revisionOwner.performSynchronousTransaction { preparation in
            try atom.prepareExpandDrawer(
                drawerId: firstDrawerID,
                for: preparation,
                revisionOwner: revisionOwner
            )
        }
        #expect(insertionTransaction == revisionOwner.committedRevision)
        #expect(atom.persistenceSnapshotValue(for: firstDrawerID) == .value(firstDrawerID))

        let replacementTransaction = try revisionOwner.performSynchronousTransaction { preparation in
            try atom.prepareExpandDrawer(
                drawerId: secondDrawerID,
                for: preparation,
                revisionOwner: revisionOwner
            )
        }
        #expect(replacementTransaction == revisionOwner.committedRevision)
        #expect(atom.persistenceSnapshotValue(for: firstDrawerID) == .absent)
        #expect(atom.persistenceSnapshotValue(for: secondDrawerID) == .value(secondDrawerID))

        let removalTransaction = try revisionOwner.performSynchronousTransaction { preparation in
            try atom.prepareCollapseAllDrawers(
                for: preparation,
                revisionOwner: revisionOwner
            )
        }
        #expect(removalTransaction == revisionOwner.committedRevision)
        #expect(atom.expandedDrawerId == nil)
        #expect(atom.persistenceSnapshotValue(for: secondDrawerID) == .absent)
    }

    @Test("failed expanded drawer preparation changes neither owner nor revision")
    func failedExpandedDrawerPreparationChangesNeitherOwnerNorRevision() {
        let atom = WorkspaceDrawerCursorAtom()
        let revisionOwner = WorkspacePersistenceRevisionOwner()
        let drawerID = UUID()
        guard case .constructed = atom.makePersistenceSnapshotParticipant() else {
            Issue.record("expanded-drawer snapshot participant construction failed")
            return
        }

        #expect(throws: WorkspaceDrawerCursorSnapshotPreparationError.self) {
            try revisionOwner.performSynchronousTransaction { preparation in
                _ = try atom.prepareExpandDrawer(
                    drawerId: drawerID,
                    for: preparation,
                    revisionOwner: revisionOwner
                )
                return try atom.prepareCollapseAllDrawers(
                    for: preparation,
                    revisionOwner: revisionOwner
                )
            }
        }

        #expect(revisionOwner.committedRevision == .zero)
        #expect(atom.expandedDrawerId == nil)
        #expect(atom.persistenceSnapshotValue(for: drawerID) == .absent)
    }
}
