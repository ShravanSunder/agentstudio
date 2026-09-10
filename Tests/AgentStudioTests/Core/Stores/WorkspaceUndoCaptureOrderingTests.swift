import AgentStudioInfrastructure
import AgentStudioTestSupport
import Foundation
import Testing

@testable import AgentStudioCore

@MainActor
@Suite("Workspace undo capture ordering", .serialized)
struct WorkspaceUndoCaptureOrderingTests {
    init() {
        installTestCoreAtomsIfNeeded()
    }

    @Test("close publishes only after its composition and undo are durable", arguments: [false, true])
    func closePublicationRequiresCommit(rejectWrite: Bool) async throws {
        let workspaceID = UUIDv7.generate()
        let fixture = try makeWorkspaceSQLiteBridgeFixture(workspaceId: workspaceID)
        let datastore = try await preparedWorkspaceSQLiteDatastore(from: fixture.backend)
        let topology = RepositoryTopologyAtom()
        let panes = WorkspacePaneAtom(repositoryTopologyAtom: topology)
        let tabs = WorkspaceTabLayoutAtom()
        let pane = makePane(id: UUIDv7.generate())
        let tab = Tab(paneId: pane.id)
        panes.addPane(pane)
        tabs.appendTab(tab)
        let coordinator = WorkspaceSQLiteSaveCoordinator(
            identityAtom: WorkspaceIdentityAtom(workspaceId: workspaceID),
            windowMemoryAtom: WorkspaceWindowMemoryAtom(), workspacePaneAtom: panes,
            workspaceTabLayoutAtom: tabs, sqliteDatastore: datastore
        )
        _ = try await coordinator.save(persistedAt: Date(timeIntervalSince1970: 100))
        if rejectWrite {
            try await fixture.coreRepository.databaseWriter.write { database in
                try database.execute(
                    sql: """
                        CREATE TRIGGER reject_close BEFORE INSERT ON workspace_undo_close
                        BEGIN SELECT RAISE(ABORT, 'injected journal failure'); END
                        """)
            }
        }
        let closeID = UUIDv7.generate()
        var published = false
        do {
            _ = try await coordinator.commitCloseForUndo(
                tabID: tab.id, paneID: nil, closeID: closeID,
                time: .init(
                    utc: Date(timeIntervalSince1970: 100), bootID: "boot-fixture",
                    uptimeNanoseconds: 100_000_000_000),
                publish: { proposal, receipt in
                    published = true
                    #expect(!rejectWrite)
                    #expect(proposal.removedPaneIDs == [pane.id])
                    #expect(receipt.availableCloseIDs == [closeID])
                    #expect(
                        (try? fixture.coreRepository.fetchPaneGraph(workspaceId: workspaceID).panes.isEmpty) == true)
                    #expect(
                        (try? fixture.coreRepository.fetchAvailableUndoCloses(workspaceID: workspaceID).map(\.closeID))
                            == [closeID])
                    _ = panes.deletePaneAndOwnedDrawerChildren(pane.id)
                    tabs.removeTab(tab.id)
                }
            )
            #expect(!rejectWrite)
        } catch {
            #expect(rejectWrite)
        }
        #expect(published == !rejectWrite)
        #expect((panes.pane(pane.id) != nil) == rejectWrite)
        #expect(try fixture.coreRepository.fetchPaneGraph(workspaceId: workspaceID).panes.isEmpty == !rejectWrite)
        let history = try await datastore.fetchAvailableUndoCloses(workspaceID: workspaceID)
        #expect(history.count == (rejectWrite ? 0 : 1))
    }

    @Test("tab order changes advance capture revision and equal replacements do not")
    func tabOrderChangesAdvanceRevision() {
        let atom = WorkspaceTabShellAtom()
        let first = TabShell(id: UUIDv7.generate(), name: "First")
        let second = TabShell(id: UUIDv7.generate(), name: "Second")
        atom.replaceTabShells([first, second])
        let initial = atom.tabShellAcceptedCommitRevision

        atom.moveTab(fromId: first.id, insertionIndex: 2)
        #expect(atom.orderedTabIds == [second.id, first.id])
        #expect(atom.tabShellAcceptedCommitRevision == initial + 1)
        atom.moveTabByDelta(tabId: first.id, delta: -1)
        #expect(atom.orderedTabIds == [first.id, second.id])
        #expect(atom.tabShellAcceptedCommitRevision == initial + 2)
        atom.replaceTabShells([second, first])
        #expect(atom.tabShellAcceptedCommitRevision == initial + 3)
        atom.replaceTabShells([second, first])
        #expect(atom.tabShellAcceptedCommitRevision == initial + 3)
    }

    @Test("an older capture cannot restore panes removed by a newer persisted capture")
    func staleCaptureCannotResurrectPane() async throws {
        let workspaceID = UUIDv7.generate()
        let fixture = try makeWorkspaceSQLiteBridgeFixture(workspaceId: workspaceID)
        let datastore = try await preparedWorkspaceSQLiteDatastore(from: fixture.backend)
        let pane = makePane(id: UUIDv7.generate())
        let older = WorkspaceSQLiteSaveBundle(
            workspace: .init(id: workspaceID, panes: [pane], tabs: [Tab(paneId: pane.id)]),
            captureRevision: .init(panes: 1, tabShells: 1, tabGraphs: 1)
        )
        let newer = WorkspaceSQLiteSaveBundle(
            workspace: .init(id: workspaceID),
            captureRevision: .init(panes: 2, tabShells: 2, tabGraphs: 2)
        )
        try await datastore.saveWorkspaceSnapshotBundle(older)
        try await datastore.saveWorkspaceSnapshotBundle(newer)

        await #expect(throws: WorkspaceSQLiteDatastoreError.staleWorkspaceCapture) {
            try await datastore.saveWorkspaceSnapshotBundle(older)
        }
        #expect(try fixture.coreRepository.fetchPaneGraph(workspaceId: workspaceID).panes.isEmpty)
    }

    @Test("journal publication fences captures made before the committed UI delta")
    func publicationFencesIntermediateCapture() async throws {
        let workspaceID = UUIDv7.generate()
        let fixture = try makeWorkspaceSQLiteBridgeFixture(workspaceId: workspaceID)
        let datastore = try await preparedWorkspaceSQLiteDatastore(from: fixture.backend)
        let pane = makePane(id: UUIDv7.generate())
        let tab = Tab(paneId: pane.id)
        let payload = WorkspaceUndoCloseSnapshot.tab(tab: tab, panes: [pane], tabIndex: 0)
        let captured = WorkspaceCompositionRevision(panes: 1, tabShells: 1, tabGraphs: 1)
        try await datastore.saveWorkspaceSnapshotBundle(
            .init(workspace: .init(id: workspaceID, panes: [pane], tabs: [tab]), captureRevision: captured)
        )
        try await datastore.commitWorkspaceSnapshotWithUndo(
            .init(workspace: .init(id: workspaceID), captureRevision: captured),
            change: .record(
                .init(
                    closeID: UUIDv7.generate(), workspaceID: workspaceID, kind: .tab,
                    closedAt: Date(timeIntervalSince1970: 100), expiresAt: Date(timeIntervalSince1970: 400),
                    deadlineBootID: "boot-fixture", deadlineUptimeNanoseconds: 400_000_000_000,
                    snapshotVersion: 1, snapshotPayload: try JSONEncoder().encode(payload), members: payload.members
                )
            ),
            publish: { _ in
                #expect(Thread.isMainThread)
                return WorkspaceCompositionRevision(panes: 3, tabShells: 2, tabGraphs: 2)
            }
        )
        await #expect(throws: WorkspaceSQLiteDatastoreError.staleWorkspaceCapture) {
            try await datastore.saveWorkspaceSnapshotBundle(
                .init(
                    workspace: .init(id: workspaceID, panes: [pane], tabs: [tab]),
                    captureRevision: .init(panes: 2, tabShells: 1, tabGraphs: 1)
                )
            )
        }
        await #expect(throws: WorkspaceSQLiteDatastoreError.missingWorkspaceCaptureRevision) {
            try await datastore.saveWorkspaceSnapshotBundle(.init(workspace: .init(id: workspaceID)))
        }
        let expired = try await datastore.expireUndoCloses(
            workspaceID: workspaceID,
            time: .init(
                utc: Date(timeIntervalSince1970: 400), bootID: "boot-fixture", uptimeNanoseconds: 400_000_000_000)
        )
        #expect(expired.count == 1)
    }
}
