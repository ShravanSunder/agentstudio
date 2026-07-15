import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite(.serialized)
struct WorkspaceTabCursorAtomTests {
    @Test
    func hydrate_selectsProvidedTabWhenAvailable() {
        let firstTabId = UUID()
        let secondTabId = UUID()
        let atom = WorkspaceTabCursorAtom()

        atom.hydrate(activeTabId: secondTabId, availableTabIds: [firstTabId, secondTabId])

        #expect(atom.activeTabId == secondTabId)
    }

    @Test
    func hydrate_fallsBackToFirstTabWhenProvidedTabIsStale() {
        let firstTabId = UUID()
        let atom = WorkspaceTabCursorAtom()

        atom.hydrate(activeTabId: UUID(), availableTabIds: [firstTabId])

        #expect(atom.activeTabId == firstTabId)
    }

    @Test
    func removingActiveTabSelectsLastRemainingTab() {
        let firstTabId = UUID()
        let secondTabId = UUID()
        let atom = WorkspaceTabCursorAtom()
        atom.selectTab(secondTabId, availableTabIds: [firstTabId, secondTabId])

        atom.removeTab(secondTabId, remainingTabIds: [firstTabId])

        #expect(atom.activeTabId == firstTabId)
    }

    @Test
    func removingInactiveTabKeepsActiveTab() {
        let firstTabId = UUID()
        let secondTabId = UUID()
        let atom = WorkspaceTabCursorAtom()
        atom.selectTab(firstTabId, availableTabIds: [firstTabId, secondTabId])

        atom.removeTab(secondTabId, remainingTabIds: [firstTabId])

        #expect(atom.activeTabId == firstTabId)
    }

    @Test
    func selectTabRejectsMissingTab() {
        let activeTabId = UUID()
        let missingTabId = UUID()
        let atom = WorkspaceTabCursorAtom()
        atom.selectTab(activeTabId, availableTabIds: [activeTabId])

        atom.selectTab(missingTabId, availableTabIds: [activeTabId])

        #expect(atom.activeTabId == activeTabId)
    }

    @Test("prepared active tab uses membership presence and absence")
    func preparedActiveTabUsesMembershipPresenceAndAbsence() throws {
        let atom = WorkspaceTabCursorAtom()
        let revisionOwner = WorkspacePersistenceRevisionOwner()
        let activeTabID = UUID()
        guard case .constructed = atom.makePersistenceSnapshotParticipant() else {
            Issue.record("active-tab snapshot participant construction failed")
            return
        }

        let insertionTransaction = try revisionOwner.performSynchronousTransaction { preparation in
            try atom.prepareSelectTab(
                activeTabID,
                availableTabIds: [activeTabID],
                for: preparation,
                revisionOwner: revisionOwner
            )
        }
        #expect(insertionTransaction == revisionOwner.committedRevision)
        #expect(atom.persistenceSnapshotValue(for: .activeTab) == .value(activeTabID))

        let removalTransaction = try revisionOwner.performSynchronousTransaction { preparation in
            try atom.prepareSelectTab(
                nil,
                availableTabIds: [activeTabID],
                for: preparation,
                revisionOwner: revisionOwner
            )
        }
        #expect(removalTransaction == revisionOwner.committedRevision)
        #expect(atom.activeTabId == nil)
        #expect(atom.persistenceSnapshotValue(for: .activeTab) == .absent)
    }

    @Test("failed active tab preparation changes neither owner nor revision")
    func failedActiveTabPreparationChangesNeitherOwnerNorRevision() {
        let atom = WorkspaceTabCursorAtom()
        let revisionOwner = WorkspacePersistenceRevisionOwner()
        let tabID = UUID()
        guard case .constructed = atom.makePersistenceSnapshotParticipant() else {
            Issue.record("active-tab snapshot participant construction failed")
            return
        }

        #expect(throws: WorkspaceTabCursorSnapshotPreparationError.self) {
            try revisionOwner.performSynchronousTransaction { preparation in
                _ = try atom.prepareSelectTab(
                    tabID,
                    availableTabIds: [tabID],
                    for: preparation,
                    revisionOwner: revisionOwner
                )
                return try atom.prepareSelectTab(
                    nil,
                    availableTabIds: [tabID],
                    for: preparation,
                    revisionOwner: revisionOwner
                )
            }
        }

        #expect(revisionOwner.committedRevision == .zero)
        #expect(atom.activeTabId == nil)
        #expect(atom.persistenceSnapshotValue(for: .activeTab) == .absent)
    }
}
