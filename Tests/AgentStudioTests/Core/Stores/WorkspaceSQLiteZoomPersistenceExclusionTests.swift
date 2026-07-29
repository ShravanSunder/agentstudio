import AgentStudioInfrastructure
import Foundation
import Testing

@testable import AgentStudioCore

@MainActor
@Suite("WorkspaceSQLiteZoomPersistenceExclusionTests", .serialized)
struct WorkspaceSQLiteZoomPersistenceExclusionTests {
    @Test("file-backed SQLite restores durable composition without Zoom runtime state")
    func fileBackedSQLiteExcludesZoomPresentationsAndCompanions() async throws {
        let fixture = try await makeZoomPersistenceFixture()
        defer { try? FileManager.default.removeItem(at: fixture.databaseDirectory) }

        #expect(fixture.originalStore.panePresentationAtom.zoomPresentationsByTabId.count == 2)
        #expect(fixture.originalStore.panePresentationAtom.zoomCompanionsBySourcePaneId.count == 2)
        #expect((await fixture.originalStore.flushAsync()).succeeded)

        let restoredDatastore = WorkspaceSQLiteDatastoreFactory(
            coreDatabaseURL: fixture.coreDatabaseURL,
            localDatabaseURL: fixture.localDatabaseURL
        ).makeDatastore()
        _ = await restoredDatastore.prepareDatabasesForBoot()
        let restoredStore = WorkspaceStore(
            sqliteDatastore: restoredDatastore,
            startsObserving: false
        )
        let loadResult = await restoredStore.loadCanonicalComposition()
        guard case .loaded = loadResult else {
            Issue.record("Expected independent file-backed reload, got \(loadResult)")
            return
        }

        #expect(restoredStore.identityAtom.workspaceId == fixture.workspaceId)
        #expect(Set(restoredStore.panes.keys) == fixture.durablePaneIds)
        #expect(restoredStore.panes.count == 4)
        #expect(restoredStore.tabs == fixture.expectedTabs)
        #expect(restoredStore.tabs.count == 2)
        #expect(restoredStore.tabs.allSatisfy { $0.arrangements.count == 2 })
        #expect(restoredStore.activeTabId == fixture.expectedTabs[1].id)

        #expect(restoredStore.panePresentationAtom.zoomPresentationsByTabId.isEmpty)
        #expect(restoredStore.panePresentationAtom.zoomCompanionsBySourcePaneId.isEmpty)
        #expect(Set(restoredStore.panes.keys).isDisjoint(with: fixture.companionPaneIds))
        #expect(
            Set(restoredStore.tabs.flatMap(\.allPaneIds))
                .isDisjoint(with: fixture.companionPaneIds)
        )
        #expect(
            Set(restoredStore.tabs.flatMap(\.arrangements).flatMap(\.layout.paneIds))
                .isDisjoint(with: fixture.companionPaneIds)
        )
    }
}

private struct ZoomPersistenceFixture {
    let databaseDirectory: URL
    let coreDatabaseURL: URL
    let localDatabaseURL: URL
    let originalStore: WorkspaceStore
    let workspaceId: UUID
    let expectedTabs: [Tab]
    let durablePaneIds: Set<UUID>
    let companionPaneIds: Set<UUID>
}

private struct DurableZoomComposition {
    let tabs: [Tab]
    let paneIds: Set<UUID>
    let sourcePaneIds: [UUID]
}

@MainActor
private func makeZoomPersistenceFixture() async throws -> ZoomPersistenceFixture {
    let databaseDirectory = FileManager.default.temporaryDirectory.appending(
        path: "agentstudio-zoom-persistence-\(UUIDv7.generate().uuidString)"
    )
    try FileManager.default.createDirectory(
        at: databaseDirectory,
        withIntermediateDirectories: true
    )
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
    let workspaceId = UUIDv7.generate()
    originalStore.identityAtom.replaceIdentity(
        workspaceId: workspaceId,
        workspaceName: "Zoom persistence exclusion",
        createdAt: Date(timeIntervalSince1970: 1_700_500_000)
    )

    let durableComposition = installDurableZoomComposition(in: originalStore)
    let companionPaneIds = installZoomPresentations(
        in: originalStore,
        durableComposition: durableComposition
    )
    return ZoomPersistenceFixture(
        databaseDirectory: databaseDirectory,
        coreDatabaseURL: coreDatabaseURL,
        localDatabaseURL: localDatabaseURL,
        originalStore: originalStore,
        workspaceId: workspaceId,
        expectedTabs: durableComposition.tabs,
        durablePaneIds: durableComposition.paneIds,
        companionPaneIds: companionPaneIds
    )
}

@MainActor
private func installDurableZoomComposition(
    in store: WorkspaceStore
) -> DurableZoomComposition {
    let firstSourcePane = store.createPane(title: "First source")
    let firstSiblingPane = store.createPane(title: "First sibling")
    let secondSourcePane = store.createPane(title: "Second source")
    let secondSiblingPane = store.createPane(title: "Second sibling")

    let firstDefaultArrangement = PaneArrangement(
        id: UUIDv7.generate(),
        name: "Default",
        isDefault: true,
        layout: Layout.autoTiled([firstSourcePane.id, firstSiblingPane.id]),
        activePaneId: firstSourcePane.id
    )
    let firstUserArrangement = PaneArrangement(
        id: UUIDv7.generate(),
        name: "Layout 1",
        isDefault: false,
        layout: Layout.autoTiled([firstSiblingPane.id, firstSourcePane.id]),
        minimizedPaneIds: [firstSiblingPane.id],
        activePaneId: firstSourcePane.id
    )
    let firstTab = Tab(
        id: UUIDv7.generate(),
        name: "First tab",
        allPaneIds: [firstSourcePane.id, firstSiblingPane.id],
        arrangements: [firstDefaultArrangement, firstUserArrangement],
        activeArrangementId: firstUserArrangement.id,
        colorHex: "#336699"
    )

    let secondDefaultArrangement = PaneArrangement(
        id: UUIDv7.generate(),
        name: "Default",
        isDefault: true,
        layout: Layout.autoTiled([secondSourcePane.id, secondSiblingPane.id]),
        activePaneId: secondSiblingPane.id
    )
    let secondUserArrangement = PaneArrangement(
        id: UUIDv7.generate(),
        name: "Layout 2",
        isDefault: false,
        layout: Layout.autoTiled([secondSiblingPane.id, secondSourcePane.id]),
        minimizedPaneIds: [secondSourcePane.id],
        activePaneId: secondSiblingPane.id
    )
    let secondTab = Tab(
        id: UUIDv7.generate(),
        name: "Second tab",
        allPaneIds: [secondSourcePane.id, secondSiblingPane.id],
        arrangements: [secondDefaultArrangement, secondUserArrangement],
        activeArrangementId: secondDefaultArrangement.id,
        colorHex: "#993366"
    )

    store.appendTab(firstTab)
    store.appendTab(secondTab)
    store.setActiveTab(secondTab.id)
    return DurableZoomComposition(
        tabs: [firstTab, secondTab],
        paneIds: [
            firstSourcePane.id,
            firstSiblingPane.id,
            secondSourcePane.id,
            secondSiblingPane.id,
        ],
        sourcePaneIds: [firstSourcePane.id, secondSourcePane.id]
    )
}

@MainActor
private func installZoomPresentations(
    in store: WorkspaceStore,
    durableComposition: DurableZoomComposition
) -> Set<UUID> {
    let firstTab = durableComposition.tabs[0]
    let secondTab = durableComposition.tabs[1]
    let firstSourcePaneId = durableComposition.sourcePaneIds[0]
    let secondSourcePaneId = durableComposition.sourcePaneIds[1]
    let firstCompanionPaneId = UUIDv7.generate()
    let secondCompanionPaneId = UUIDv7.generate()

    store.panePresentationAtom.cacheZoomCompanion(
        ZoomCompanionMetadata(
            owningTabId: firstTab.id,
            resolvedWorktreeId: UUIDv7.generate(),
            companionPaneId: firstCompanionPaneId,
            lastZoomVisibility: .visible
        ),
        forSourcePane: firstSourcePaneId
    )
    store.panePresentationAtom.enterZoom(
        inTab: firstTab.id,
        sourcePaneId: firstSourcePaneId,
        viewerPresentation: .retainedVisible(companionPaneId: firstCompanionPaneId),
        transientSplitRatio: 0.4
    )

    store.panePresentationAtom.cacheZoomCompanion(
        ZoomCompanionMetadata(
            owningTabId: secondTab.id,
            resolvedWorktreeId: UUIDv7.generate(),
            companionPaneId: secondCompanionPaneId,
            lastZoomVisibility: .hidden
        ),
        forSourcePane: secondSourcePaneId
    )
    store.panePresentationAtom.enterZoom(
        inTab: secondTab.id,
        sourcePaneId: secondSourcePaneId,
        viewerPresentation: .retainedHidden(companionPaneId: secondCompanionPaneId),
        transientSplitRatio: 0.6
    )
    return [firstCompanionPaneId, secondCompanionPaneId]
}
