import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite("Pane hosting editor chooser identity")
struct PaneHostingEditorChooserIdentityTests {
    @Test("main and drawer pane leaves receive the exact App root editor chooser")
    func mainAndDrawerPaneLeavesReceiveExactAppRootEditorChooser() throws {
        try withTestAtomRegistry { atoms in
            // Arrange
            let store = WorkspaceStore(
                identityAtom: atoms.workspaceIdentity,
                windowMemoryAtom: atoms.workspaceWindowMemory,
                repositoryTopologyAtom: atoms.workspaceRepositoryTopology,
                paneAtom: atoms.workspacePane,
                tabLayoutAtom: atoms.workspaceTabLayout,
                mutationCoordinator: atoms.workspaceMutationCoordinator
            )
            let mainPane = store.createPane()
            let tab = Tab(paneId: mainPane.id)
            store.appendTab(tab)
            let drawerPane = try #require(store.addDrawerPane(to: mainPane.id))
            let dispatcher = PaneTabActionDispatcher(
                dispatch: { _ in },
                shouldHandleSplitDragPayload: { _ in false },
                shouldAcceptDrop: { _, _, _, _ in false },
                handleDrop: { _, _, _, _ in }
            )

            // Act
            let mainPaneLeaf = makePaneLeaf(
                paneId: mainPane.id,
                tabId: tab.id,
                store: store,
                editorChooser: atoms.editorChooser,
                dispatcher: dispatcher
            )
            let drawerPaneLeaf = makePaneLeaf(
                paneId: drawerPane.id,
                tabId: tab.id,
                store: store,
                editorChooser: atoms.editorChooser,
                dispatcher: dispatcher
            )

            // Assert
            #expect(mainPaneLeaf.editorChooser === atoms.editorChooser)
            #expect(drawerPaneLeaf.editorChooser === atoms.editorChooser)
        }
    }

    private func makePaneLeaf(
        paneId: UUID,
        tabId: UUID,
        store: WorkspaceStore,
        editorChooser: EditorChooserState,
        dispatcher: PaneTabActionDispatcher
    ) -> PaneLeafContainer {
        PaneLeafContainer(
            paneHost: PaneHostView(paneId: paneId),
            tabId: tabId,
            isActive: true,
            isSplit: false,
            isSplitResizing: false,
            store: store,
            repoCache: RepoCacheAtom(),
            editorChooser: editorChooser,
            closeTransitionCoordinator: PaneCloseTransitionCoordinator(),
            actionDispatcher: dispatcher,
            onPaneFocusTrigger: { _ in },
            onOpenPaneGitHub: { _ in }
        )
    }
}
