import Foundation
import GRDB
import Testing

@testable import AgentStudio

@MainActor
@Suite("Workspace SQLite save coordinator", .serialized)
struct WorkspaceSQLiteSaveCoordinatorTests {
    @Test("valid save writes the exact current bundle")
    func validSaveWritesExactCurrentBundle() async throws {
        // Arrange
        let fixture = try makeFixture()
        let persistedAt = Date(timeIntervalSince1970: 1_784_000_000)
        let expected = fixture.coordinator.captureCurrentSaveBundle(persistedAt: persistedAt)

        // Act
        let saved = try await fixture.coordinator.save(persistedAt: persistedAt)
        let loadedWorkspace = await fixture.datastore.loadWorkspaceSnapshot()
        let loadedTopology = await fixture.datastore.loadRepositoryTopologySnapshot(
            workspaceId: fixture.workspaceID
        )

        // Assert
        #expect(saved == expected)
        guard case .loaded(let workspace) = loadedWorkspace else {
            Issue.record("Expected saved workspace to load")
            return
        }
        guard case .loaded(let topology) = loadedTopology else {
            Issue.record("Expected saved repository topology to load")
            return
        }
        #expect(workspace == expected.workspace)
        #expect(topology == expected.repositoryTopology)
        #expect(await fixture.probe.events.contains(.saveWorkspaceSnapshot))
    }

    @Test("invalid current composition is rejected before datastore write")
    func invalidCurrentCompositionIsRejectedBeforeDatastoreWrite() async throws {
        // Arrange
        let fixture = try makeFixture()
        let missingTabID = UUIDv7.generate()
        fixture.tabLayoutAtom.shellAtom.cursorAtom.replaceActiveTab(missingTabID)

        // Act
        do {
            _ = try await fixture.coordinator.save(
                persistedAt: Date(timeIntervalSince1970: 1_784_000_001)
            )
            Issue.record("Expected invalid active tab rejection")
        } catch {
            #expect(error == .compositionRejected(.activeTabNotFound(missingTabID)))
        }

        // Assert
        #expect(!(await fixture.probe.events.contains(.saveWorkspaceSnapshot)))
    }

    @Test("successful save acknowledgement does not mutate canonical atoms or cursors")
    func successfulSaveAcknowledgementDoesNotMutateCanonicalAtomsOrCursors() async throws {
        // Arrange
        let fixture = try makeFixture()
        let persistedAt = Date(timeIntervalSince1970: 1_784_000_002)
        let before = fixture.coordinator.captureCurrentSaveBundle(persistedAt: persistedAt)

        // Act
        _ = try await fixture.coordinator.save(persistedAt: persistedAt)

        // Assert
        let after = fixture.coordinator.captureCurrentSaveBundle(persistedAt: persistedAt)
        #expect(after == before)
    }
}

@MainActor
private struct WorkspaceSQLiteSaveCoordinatorFixture {
    let workspaceID: UUID
    let tabLayoutAtom: WorkspaceTabLayoutAtom
    let datastore: WorkspaceSQLiteDatastore
    let coordinator: WorkspaceSQLiteSaveCoordinator
    let probe: WorkspaceSQLiteSaveCoordinatorProbe
}

@MainActor
private func makeFixture() throws -> WorkspaceSQLiteSaveCoordinatorFixture {
    let workspaceID = UUIDv7.generate()
    let paneID = PaneId.generateUUIDv7().uuid
    let drawerID = UUIDv7.generate()
    let arrangementID = UUIDv7.generate()
    let tabID = UUIDv7.generate()
    let createdAt = Date(timeIntervalSince1970: 1_783_000_000)
    let pane = Pane(
        id: paneID,
        content: .terminal(
            TerminalState(
                provider: .zmx,
                lifetime: .persistent,
                zmxSessionID: .generateUUIDv7()
            )
        ),
        metadata: PaneMetadata(title: "Exact pane"),
        kind: .layout(
            drawer: Drawer(
                drawerId: drawerID,
                parentPaneId: paneID
            )
        )
    )
    let arrangement = PaneArrangement(
        id: arrangementID,
        layout: Layout(paneId: paneID),
        activePaneId: paneID
    )
    let tab = Tab(
        id: tabID,
        name: "Exact tab",
        allPaneIds: [paneID],
        arrangements: [arrangement],
        activeArrangementId: arrangementID
    )
    let identityAtom = WorkspaceIdentityAtom(
        workspaceId: workspaceID,
        workspaceName: "Exact workspace",
        createdAt: createdAt
    )
    let windowMemoryAtom = WorkspaceWindowMemoryAtom(sidebarWidth: 312)
    let repositoryTopologyAtom = RepositoryTopologyAtom()
    let workspacePaneAtom = WorkspacePaneAtom(repositoryTopologyAtom: repositoryTopologyAtom)
    workspacePaneAtom.addPane(pane)
    let tabLayoutAtom = WorkspaceTabLayoutAtom()
    tabLayoutAtom.appendTab(tab)
    tabLayoutAtom.setActiveTab(tabID)

    let coreQueue = try SQLiteDatabaseFactory.makeInMemoryQueue(
        label: "AgentStudio.sqlite.save-coordinator.core"
    )
    let localQueue = try SQLiteDatabaseFactory.makeInMemoryQueue(
        label: "AgentStudio.sqlite.save-coordinator.local"
    )
    try WorkspaceCoreMigrations.migrate(coreQueue)
    try WorkspaceLocalMigrations.migrate(localQueue)
    let probe = WorkspaceSQLiteSaveCoordinatorProbe()
    let datastore = WorkspaceSQLiteDatastore(
        coreRepository: WorkspaceCoreRepository(databaseWriter: coreQueue),
        makeLocalRepository: {
            WorkspaceLocalRepository(workspaceId: $0, databaseWriter: localQueue)
        },
        probe: { event in await probe.record(event) }
    )
    return WorkspaceSQLiteSaveCoordinatorFixture(
        workspaceID: workspaceID,
        tabLayoutAtom: tabLayoutAtom,
        datastore: datastore,
        coordinator: WorkspaceSQLiteSaveCoordinator(
            identityAtom: identityAtom,
            windowMemoryAtom: windowMemoryAtom,
            repositoryTopologyAtom: repositoryTopologyAtom,
            workspacePaneAtom: workspacePaneAtom,
            workspaceTabLayoutAtom: tabLayoutAtom,
            sqliteDatastore: datastore
        ),
        probe: probe
    )
}

private actor WorkspaceSQLiteSaveCoordinatorProbe {
    private(set) var events: [WorkspaceSQLiteDatastore.ProbeEvent] = []

    func record(_ event: WorkspaceSQLiteDatastore.ProbeEvent) {
        events.append(event)
    }
}
