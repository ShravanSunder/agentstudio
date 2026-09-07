import AgentStudioInfrastructure
import AgentStudioTestSupport
import Foundation
import Testing

@testable import AgentStudioCore

@MainActor
@Suite("Workspace durable close store publication", .serialized)
struct WorkspaceUndoStorePublicationTests {
    @Test("undo skips an unavailable placement without consuming it or blocking an older tab")
    func unavailableNewestEntryDoesNotBlockUndo() async throws {
        let workspaceID = UUIDv7.generate()
        let fixture = try makeWorkspaceSQLiteBridgeFixture(workspaceId: workspaceID)
        let datastore = try await preparedWorkspaceSQLiteDatastore(from: fixture.backend)
        let store = WorkspaceStore(
            identityAtom: WorkspaceIdentityAtom(workspaceId: workspaceID),
            sqliteDatastore: datastore, startsObserving: false
        )
        let olderPane = store.createPane()
        let olderTab = Tab(paneId: olderPane.id)
        store.appendTab(olderTab)
        let newerPane = store.createPane()
        let sibling = store.createPane()
        let newerTab = makeTab(paneIds: [newerPane.id, sibling.id], activePaneId: newerPane.id)
        store.appendTab(newerTab)
        let time = WorkspaceUndoJournalTime(
            utc: Date(timeIntervalSince1970: 100), bootID: "boot-fixture", uptimeNanoseconds: 100_000_000_000
        )
        let olderID = UUIDv7.generate()
        let newerID = UUIDv7.generate()
        try await store.closeForUndo(
            tabID: olderTab.id, paneID: nil, closeID: olderID, time: time,
            willPublish: { _, _ in }, didPublish: { _, _ in })
        try await store.closeForUndo(
            tabID: newerTab.id, paneID: newerPane.id, closeID: newerID, time: time,
            willPublish: { _, _ in }, didPublish: { _, _ in })
        store.mutationCoordinator.removePane(sibling.id)
        #expect(await store.flushAsync() == .persisted)

        let receipt = try await store.undoClose(
            time: time,
            willPublish: { proposal, _ in
                #expect(proposal.close.closeID == olderID)
                #expect(store.paneAtom.pane(olderPane.id) == nil)
                #expect(
                    (try? fixture.coreRepository.fetchPaneGraph(workspaceId: workspaceID).panes.map(\.id)) == [
                        olderPane.id
                    ])
            },
            didPublish: { _, _ in
                #expect(
                    store.paneAtom.pane(olderPane.id)?.terminalState?.zmxSessionID
                        == olderPane.terminalState?.zmxSessionID)
            }
        )

        #expect(receipt?.availableCloseIDs == [newerID])
        #expect(store.tabLayoutAtom.tabs.map(\.id) == [olderTab.id])
        #expect(store.paneAtom.pane(newerPane.id) == nil)
        let remaining = try await datastore.fetchAvailableUndoCloses(workspaceID: workspaceID)
        #expect(remaining.map(\.closeID) == [newerID])
    }

    @Test("committed drawer close publishes its exact layout without overwriting newer metadata")
    func drawerClosePreservesNewerMetadata() async throws {
        let workspaceID = UUIDv7.generate()
        let fixture = try makeWorkspaceSQLiteBridgeFixture(workspaceId: workspaceID)
        let datastore = try await preparedWorkspaceSQLiteDatastore(from: fixture.backend)
        let store = WorkspaceStore(
            identityAtom: WorkspaceIdentityAtom(workspaceId: workspaceID),
            sqliteDatastore: datastore, startsObserving: false
        )
        let parent = store.createPane()
        let tab = Tab(paneId: parent.id)
        store.appendTab(tab)
        let child = try #require(store.addDrawerPane(to: parent.id))
        #expect(await store.flushAsync() == .persisted)

        let closeID = UUIDv7.generate()
        let receipt = try await store.closeForUndo(
            tabID: tab.id, paneID: child.id, closeID: closeID,
            time: .init(
                utc: Date(timeIntervalSince1970: 100), bootID: "boot-fixture",
                uptimeNanoseconds: 100_000_000_000),
            willPublish: { proposal, _ in
                #expect(store.paneAtom.pane(child.id) != nil)
                #expect(proposal.removedPaneIDs == [child.id])
                store.paneAtom.updatePaneTitle(parent.id, title: "Updated during commit")
            },
            didPublish: { _, _ in
                #expect(store.paneAtom.pane(child.id) == nil)
            }
        )

        #expect(receipt.availableCloseIDs == [closeID])
        #expect(store.paneAtom.pane(parent.id)?.title == "Updated during commit")
        #expect(store.paneAtom.pane(parent.id)?.drawer?.paneIds.isEmpty == true)
        #expect(store.tabLayoutAtom.tab(tab.id)?.allPaneIds == [parent.id])
        #expect(store.tabLayoutAtom.tab(tab.id)?.arrangements.first?.drawerViews.isEmpty == true)
        #expect(await store.flushAsync() == .persisted)
        let persisted = try fixture.coreRepository.fetchPaneGraph(workspaceId: workspaceID)
        #expect(persisted.panes.map(\.id) == [parent.id])
        let undo = try await datastore.fetchAvailableUndoCloses(workspaceID: workspaceID)
        #expect(undo.first?.snapshot.panes.map(\.id) == [child.id])
    }
}
