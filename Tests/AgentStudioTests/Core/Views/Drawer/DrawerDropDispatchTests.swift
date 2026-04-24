import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite(.serialized)
final class DrawerDropDispatchTests {
    init() {
        installTestAtomRegistryIfNeeded()
    }

    @Test
    func shouldAcceptDrop_sameParentDrawerPane_returnsTrue() throws {
        let fixture = try makeDrawerFixture()

        let accepted = DrawerDropDispatch.shouldAcceptDrop(
            payload: .init(kind: .existingPane(paneId: fixture.firstDrawerPaneId, sourceTabId: fixture.tabId)),
            target: .rowSlot(row: .top, insertionIndex: 1),
            sizingMode: .proportional,
            parentPaneId: fixture.parentPaneId,
            store: fixture.store
        )

        #expect(accepted)
    }

    @Test
    func shouldAcceptDrop_mainPanePayload_returnsFalse() throws {
        let fixture = try makeDrawerFixture()

        let accepted = DrawerDropDispatch.shouldAcceptDrop(
            payload: .init(kind: .existingPane(paneId: fixture.parentPaneId, sourceTabId: fixture.tabId)),
            target: .rowSlot(row: .top, insertionIndex: 1),
            sizingMode: .proportional,
            parentPaneId: fixture.parentPaneId,
            store: fixture.store
        )

        #expect(!accepted)
    }

    @Test
    func shouldAcceptDrop_otherDrawerParentPayload_returnsFalse() throws {
        let fixture = try makeDrawerFixture()
        let otherDrawer = try addDrawerParent(to: fixture.store)

        let accepted = DrawerDropDispatch.shouldAcceptDrop(
            payload: .init(
                kind: .existingPane(paneId: otherDrawer.firstDrawerPaneId, sourceTabId: otherDrawer.tabId)),
            target: .rowSlot(row: .top, insertionIndex: 1),
            sizingMode: .proportional,
            parentPaneId: fixture.parentPaneId,
            store: fixture.store
        )

        #expect(!accepted)
    }

    @Test
    func handleDrop_sameParentDrawerPane_dispatchesMoveWithExplicitSizingMode() throws {
        let fixture = try makeDrawerFixture()
        let dispatcher = RecordingPaneActionDispatcher()

        DrawerDropDispatch.handleDrop(
            payload: .init(kind: .existingPane(paneId: fixture.firstDrawerPaneId, sourceTabId: fixture.tabId)),
            target: .paneSplit(paneId: fixture.secondDrawerPaneId, side: .left),
            sizingMode: .halveTarget,
            parentPaneId: fixture.parentPaneId,
            actionDispatcher: dispatcher,
            store: fixture.store
        )

        #expect(
            dispatcher.dispatchedActions == [
                .moveDrawerPane(
                    parentPaneId: fixture.parentPaneId,
                    drawerPaneId: fixture.firstDrawerPaneId,
                    target: .paneSplit(paneId: fixture.secondDrawerPaneId, side: .left),
                    sizingMode: .halveTarget
                )
            ]
        )
    }

    @Test
    func handleDrop_otherDrawerParentPayload_doesNotDispatch() throws {
        let fixture = try makeDrawerFixture()
        let otherDrawer = try addDrawerParent(to: fixture.store)
        let dispatcher = RecordingPaneActionDispatcher()

        DrawerDropDispatch.handleDrop(
            payload: .init(
                kind: .existingPane(paneId: otherDrawer.firstDrawerPaneId, sourceTabId: otherDrawer.tabId)),
            target: .rowSlot(row: .top, insertionIndex: 1),
            sizingMode: .proportional,
            parentPaneId: fixture.parentPaneId,
            actionDispatcher: dispatcher,
            store: fixture.store
        )

        #expect(dispatcher.dispatchedActions.isEmpty)
    }

    private func addDrawerParent(to store: WorkspaceStore) throws -> DrawerParentFixture {
        let parentPane = store.createPane(source: .floating(launchDirectory: nil, title: nil))
        let tab = Tab(paneId: parentPane.id)
        store.appendTab(tab)
        let firstDrawerPane = try #require(store.addDrawerPane(to: parentPane.id))

        return DrawerParentFixture(
            tabId: tab.id,
            parentPaneId: parentPane.id,
            firstDrawerPaneId: firstDrawerPane.id
        )
    }

    private func makeDrawerFixture() throws -> DrawerDispatchFixture {
        atom(\.managementLayer).activate()
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "drawer-drop-dispatch-\(UUID().uuidString)")
        let store = WorkspaceStore(persistor: WorkspacePersistor(workspacesDir: tempDir))
        store.restore()

        let parentPane = store.createPane(source: .floating(launchDirectory: nil, title: nil))
        let tab = Tab(paneId: parentPane.id)
        store.appendTab(tab)
        let firstDrawerPane = try #require(store.addDrawerPane(to: parentPane.id))
        let secondDrawerPane = try #require(store.addDrawerPane(to: parentPane.id))

        return DrawerDispatchFixture(
            store: store,
            tempDir: tempDir,
            tabId: tab.id,
            parentPaneId: parentPane.id,
            firstDrawerPaneId: firstDrawerPane.id,
            secondDrawerPaneId: secondDrawerPane.id
        )
    }
}

private struct DrawerParentFixture {
    let tabId: UUID
    let parentPaneId: UUID
    let firstDrawerPaneId: UUID
}

@MainActor
private final class DrawerDispatchFixture {
    let store: WorkspaceStore
    let tempDir: URL
    let tabId: UUID
    let parentPaneId: UUID
    let firstDrawerPaneId: UUID
    let secondDrawerPaneId: UUID

    init(
        store: WorkspaceStore,
        tempDir: URL,
        tabId: UUID,
        parentPaneId: UUID,
        firstDrawerPaneId: UUID,
        secondDrawerPaneId: UUID
    ) {
        self.store = store
        self.tempDir = tempDir
        self.tabId = tabId
        self.parentPaneId = parentPaneId
        self.firstDrawerPaneId = firstDrawerPaneId
        self.secondDrawerPaneId = secondDrawerPaneId
    }

    deinit {
        try? FileManager.default.removeItem(at: tempDir)
    }
}

@MainActor
private final class RecordingPaneActionDispatcher: PaneActionDispatching {
    private(set) var dispatchedActions: [PaneActionCommand] = []

    func dispatch(_ action: PaneActionCommand) {
        dispatchedActions.append(action)
    }

    func shouldAcceptDrop(
        _ payload: SplitDropPayload,
        destinationPaneId: UUID,
        zone: DropZoneSide,
        sizingMode: DropSizingMode
    ) -> Bool {
        false
    }

    func handleDrop(
        _ payload: SplitDropPayload,
        destinationPaneId: UUID,
        zone: DropZoneSide,
        sizingMode: DropSizingMode
    ) {}
}
