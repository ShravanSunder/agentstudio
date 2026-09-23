import AgentStudioInfrastructure
import Foundation
import Testing

@testable import AgentStudioCore

@MainActor
@Suite("WorkspaceStoreArrangementTests.VisibilityPersistence", .serialized)
struct WorkspaceStoreArrangementTestsSQLite {
    @Test("active and Default insertion membership survives file-backed SQLite round-trip")
    func activeAndDefaultMembershipSurvivesRoundTrip() async throws {
        let databaseDirectory = FileManager.default.temporaryDirectory.appending(
            path: "agentstudio-arrangement-visibility-\(UUIDv7.generate().uuidString)"
        )
        try FileManager.default.createDirectory(
            at: databaseDirectory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: databaseDirectory) }
        let coreDatabaseURL = databaseDirectory.appending(path: "core.sqlite")
        let localDatabaseURL = databaseDirectory.appending(path: "local.sqlite")
        let originalDatastore = WorkspaceSQLiteDatastoreFactory(
            coreDatabaseURL: coreDatabaseURL,
            localDatabaseURL: localDatabaseURL
        ).makeDatastore()
        _ = await originalDatastore.prepareDatabasesForBoot()
        let originalStore = WorkspaceStore(
            sqliteDatastore: originalDatastore,
            startsObserving: false
        )
        originalStore.identityAtom.replaceIdentity(
            workspaceId: UUIDv7.generate(),
            workspaceName: "Arrangement visibility persistence",
            createdAt: Date(timeIntervalSince1970: 1_789_120_000)
        )

        let parentPane = originalStore.createPane(title: "Parent")
        let tab = Tab(paneId: parentPane.id)
        originalStore.appendTab(tab)
        let firstDrawerPane = try #require(originalStore.addDrawerPane(to: parentPane.id))
        let untouchedArrangementID = try #require(
            originalStore.createArrangement(name: "Untouched", inTab: tab.id)
        )
        let activeArrangementID = try #require(
            originalStore.createArrangement(name: "Active", inTab: tab.id)
        )
        let untouchedBeforeInsertion = try #require(
            originalStore.tab(tab.id)?.arrangements.first { $0.id == untouchedArrangementID }
        )
        let insertedMainPane = try await originalStore.createTerminalPane(
            metadata: PaneMetadata(title: "Inserted main"),
            placement: .split(
                .init(
                    tabID: tab.id,
                    anchorID: parentPane.id,
                    direction: .horizontal,
                    position: .after,
                    sizingMode: .halveTarget
                )
            ),
            nameForPane: { _ in "Arrangement visibility persistence" },
            willPublish: { _ in }
        )
        let insertedDrawerPane = try await originalStore.createTerminalPane(
            metadata: PaneMetadata(title: "Inserted drawer"),
            placement: .drawer(
                .init(
                    tabID: tab.id,
                    parentID: parentPane.id,
                    anchorID: firstDrawerPane.id,
                    direction: .right,
                    sizingMode: .halveTarget
                )
            ),
            nameForPane: { _ in "Arrangement visibility persistence" },
            willPublish: { _ in }
        )
        let expectedTab = try #require(originalStore.tab(tab.id))
        let drawerID = try #require(originalStore.pane(parentPane.id)?.drawer?.drawerId)

        #expect((await originalStore.flushAsync()).succeeded)

        let restoredDatastore = WorkspaceSQLiteDatastoreFactory(
            coreDatabaseURL: coreDatabaseURL,
            localDatabaseURL: localDatabaseURL
        ).makeDatastore()
        _ = await restoredDatastore.prepareDatabasesForBoot()
        let restoredStore = WorkspaceStore(
            sqliteDatastore: restoredDatastore,
            startsObserving: false
        )
        guard case .loaded = await restoredStore.loadCanonicalComposition() else {
            Issue.record("Expected file-backed arrangement visibility reload")
            return
        }
        let restoredTab = try #require(restoredStore.tab(tab.id))

        #expect(restoredTab == expectedTab)
        #expect(restoredTab.arrangements.first { $0.id == untouchedArrangementID } == untouchedBeforeInsertion)
        #expect(restoredTab.defaultArrangement.layout.contains(insertedMainPane.id))
        #expect(restoredTab.defaultArrangement.drawerViews[drawerID]?.layout.contains(insertedDrawerPane.id) == true)
        #expect(
            restoredTab.arrangements.first { $0.id == activeArrangementID }?
                .layout.contains(insertedMainPane.id) == true
        )
        #expect(
            restoredTab.arrangements.first { $0.id == activeArrangementID }?
                .drawerViews[drawerID]?.layout.contains(insertedDrawerPane.id) == true
        )
    }
}
