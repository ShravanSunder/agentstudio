import Testing

@testable import AgentStudio

@MainActor
@Suite("PaneTabViewController global shortcut routing")
struct PaneTabViewControllerGlobalShortcutRoutingTests {
    @Test("filterSidebar is only handled when the repos sidebar owns focus")
    func filterSidebarRequiresFocusedReposSidebar() {
        let uiState = UIStateAtom()
        let managementLayer = ManagementLayerAtom()

        #expect(
            !PaneTabViewController.shouldDispatchGlobalShortcut(
                .filterSidebar,
                uiState: uiState,
                managementLayer: managementLayer
            )
        )

        uiState.setSidebarHasFocus(true)
        uiState.setSidebarSurface(.inbox)
        #expect(
            !PaneTabViewController.shouldDispatchGlobalShortcut(
                .filterSidebar,
                uiState: uiState,
                managementLayer: managementLayer
            )
        )

        uiState.setSidebarSurface(.repos)
        #expect(
            PaneTabViewController.shouldDispatchGlobalShortcut(
                .filterSidebar,
                uiState: uiState,
                managementLayer: managementLayer
            )
        )

        managementLayer.activate()
        #expect(
            !PaneTabViewController.shouldDispatchGlobalShortcut(
                .filterSidebar,
                uiState: uiState,
                managementLayer: managementLayer
            )
        )
    }

    @Test("surface switch shortcuts remain globally routable")
    func surfaceSwitchShortcutsRemainGlobal() {
        let uiState = UIStateAtom()
        let managementLayer = ManagementLayerAtom()

        #expect(
            PaneTabViewController.shouldDispatchGlobalShortcut(
                .showInboxNotifications,
                uiState: uiState,
                managementLayer: managementLayer
            )
        )
        #expect(
            PaneTabViewController.shouldDispatchGlobalShortcut(
                .showWorktreeSidebar,
                uiState: uiState,
                managementLayer: managementLayer
            )
        )
    }
}
