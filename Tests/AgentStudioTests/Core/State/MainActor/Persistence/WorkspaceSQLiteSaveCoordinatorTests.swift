import Foundation
import GRDB
import Testing

@testable import AgentStudio

@MainActor
@Suite("Workspace SQLite save coordinator", .serialized)
struct WorkspaceSQLiteSaveCoordinatorTests {
    @Test("shallow capture prepares the exact current composition off-main")
    func shallowCapturePreparesExactCurrentCompositionOffMain() async throws {
        // Arrange
        let fixture = try makeFixture()
        let persistedAt = Date(timeIntervalSince1970: 1_784_000_004)
        let expectedTabs = fixture.tabLayoutAtom.tabs

        // Act
        let capture = fixture.coordinator.captureCurrentSaveState(persistedAt: persistedAt)
        let prepared = await WorkspaceSQLiteSavePreparation.prepareOffMain(capture)

        // Assert
        #expect(
            prepared.workspace.id
                == fixture.coordinator.captureCurrentSaveState(persistedAt: persistedAt).workspaceID
        )
        #expect(prepared.workspace.panes.count == 1)
        #expect(prepared.workspace.tabs == expectedTabs)
    }

    @Test("valid save writes the exact current composition bundle")
    func validSaveWritesExactCurrentCompositionBundle() async throws {
        // Arrange
        let fixture = try makeFixture()
        let persistedAt = Date(timeIntervalSince1970: 1_784_000_000)
        let expected = await fixture.coordinator.captureCurrentSaveBundle(persistedAt: persistedAt)

        // Act
        let saved = try await fixture.coordinator.save(persistedAt: persistedAt)
        let loadedWorkspace = await fixture.datastore.loadWorkspaceSnapshot()

        // Assert
        #expect(saved == expected)
        guard case .loaded(let workspace) = loadedWorkspace else {
            Issue.record("Expected saved workspace to load")
            return
        }
        #expect(workspace == expected.workspace)
        #expect(await fixture.probe.events.contains(.saveWorkspaceSnapshot))
    }

    @Test("topology changes cannot change captured composition")
    func topologyChangesCannotChangeCapturedComposition() async throws {
        // Arrange
        let fixture = try makeFixture()
        let persistedAt = Date(timeIntervalSince1970: 1_784_000_003)
        let beforeTopologyChange = await fixture.coordinator.captureCurrentSaveBundle(
            persistedAt: persistedAt
        )

        // Act
        let preparation = RepositoryTopologyReplacement.prepare(
            repositories: [],
            watchedPaths: [
                WatchedPath(
                    id: UUIDv7.generate(),
                    path: URL(filePath: "/tmp/topology-only-change")
                )
            ],
            unavailableRepositoryIDs: []
        )
        guard case .prepared(let replacement) = preparation else {
            Issue.record("Expected valid topology-only replacement")
            return
        }
        fixture.repositoryTopologyAtom.replaceTopology(replacement)
        let afterTopologyChange = await fixture.coordinator.captureCurrentSaveBundle(
            persistedAt: persistedAt
        )

        // Assert
        #expect(afterTopologyChange == beforeTopologyChange)
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
        let before = await fixture.coordinator.captureCurrentSaveBundle(persistedAt: persistedAt)

        // Act
        _ = try await fixture.coordinator.save(persistedAt: persistedAt)

        // Assert
        let after = await fixture.coordinator.captureCurrentSaveBundle(persistedAt: persistedAt)
        #expect(after == before)
    }

    @Test("save bundle omits panes explicitly held for pending undo")
    func saveBundleOmitsExplicitPendingUndoPanes() async throws {
        // Arrange
        let fixture = try makeFixture()
        let pendingUndoPane = makeUnownedPane(
            title: "Pending undo",
            residency: .pendingUndo(expiresAt: Date(timeIntervalSince1970: 1_784_000_300))
        )
        fixture.workspacePaneAtom.addPane(pendingUndoPane)

        // Act
        let bundle = await fixture.coordinator.captureCurrentSaveBundle(
            persistedAt: Date(timeIntervalSince1970: 1_784_000_003)
        )

        // Assert
        #expect(!bundle.workspace.panes.contains(where: { $0.id == pendingUndoPane.id }))
    }

    @Test("pending undo projection preserves strict rejection for an active unowned pane")
    func pendingUndoProjectionPreservesStrictRejectionForActiveUnownedPane() async throws {
        // Arrange
        let fixture = try makeFixture()
        let activeUnownedPane = makeUnownedPane(title: "Active unowned", residency: .active)
        fixture.workspacePaneAtom.addPane(activeUnownedPane)

        // Act
        do {
            _ = try await fixture.coordinator.save(
                persistedAt: Date(timeIntervalSince1970: 1_784_000_004)
            )
            Issue.record("Expected active unowned pane rejection")
        } catch {
            #expect(error == .compositionRejected(.paneNotOwnedByTab(activeUnownedPane.id)))
        }

        // Assert
        #expect(!(await fixture.probe.events.contains(.saveWorkspaceSnapshot)))
    }
}

@MainActor
private struct WorkspaceSQLiteSaveCoordinatorFixture {
    let repositoryTopologyAtom: RepositoryTopologyAtom
    let workspacePaneAtom: WorkspacePaneAtom
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
        metadata: PaneMetadata(createdAt: createdAt, title: "Exact pane"),
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
        repositoryTopologyAtom: repositoryTopologyAtom,
        workspacePaneAtom: workspacePaneAtom,
        tabLayoutAtom: tabLayoutAtom,
        datastore: datastore,
        coordinator: WorkspaceSQLiteSaveCoordinator(
            identityAtom: identityAtom,
            windowMemoryAtom: windowMemoryAtom,
            workspacePaneAtom: workspacePaneAtom,
            workspaceTabLayoutAtom: tabLayoutAtom,
            sqliteDatastore: datastore
        ),
        probe: probe
    )
}

private func makeUnownedPane(title: String, residency: SessionResidency) -> Pane {
    Pane(
        content: .terminal(
            TerminalState(
                provider: .zmx,
                lifetime: .persistent,
                zmxSessionID: .generateUUIDv7()
            )
        ),
        metadata: PaneMetadata(title: title),
        residency: residency
    )
}

private actor WorkspaceSQLiteSaveCoordinatorProbe {
    private(set) var events: [WorkspaceSQLiteDatastore.ProbeEvent] = []

    func record(_ event: WorkspaceSQLiteDatastore.ProbeEvent) {
        events.append(event)
    }
}
