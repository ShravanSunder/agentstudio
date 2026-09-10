import Testing

@testable import AgentStudio
@testable import AgentStudioCore
@testable import AgentStudioTestSupport

@MainActor
@Suite(.serialized)
struct MainSplitViewControllerCompositeCommandTests {
    init() {
        installTestCoreAtomsIfNeeded()
    }

    @Test("retired Inbox commands have no interactive presentation")
    func retiredInboxCommandsHaveNoInteractivePresentation() {
        #expect(AppCommand.showInboxNotifications.definition.surfacePolicy == .notPresented)
        #expect(AppCommand.clearReadInboxNotifications.definition.surfacePolicy == .notPresented)
        #expect(AppCommand.showPaneInboxNotifications.definition.surfacePolicy == .notPresented)
        #expect(AppCommand.clearPaneInboxNotifications.definition.surfacePolicy == .notPresented)
    }

    @Test("legacy Inbox sidebar state normalizes before controller composition")
    func legacyInboxSidebarStateNormalizesBeforeControllerComposition() async {
        await withMainSplitViewControllerHarness(
            withRepos: true,
            configureUIState: {
                $0.setSidebarCollapsed(true)
                $0.setSidebarSurface(.inbox)
            },
            body: { harness in
                #expect(harness.atoms.core.workspaceSidebarState.sidebarSurface == .repos)

                harness.controller.showWorktreeSidebar()

                await eventually("Repo Explorer should expand from legacy restored state") {
                    harness.controller.isSidebarCollapsed == false
                        && harness.atoms.core.workspaceSidebarState.sidebarCollapsed == false
                        && harness.atoms.core.workspaceSidebarState.sidebarSurface == .repos
                }
            }
        )
    }

    @Test("showWorktreeSidebar toggles the sole visible sidebar")
    func showWorktreeSidebarTogglesSoleVisibleSidebar() async {
        await withMainSplitViewControllerHarness(
            withRepos: true,
            body: { harness in
                #expect(harness.controller.isSidebarCollapsed == false)
                #expect(harness.atoms.core.workspaceSidebarState.sidebarSurface == .repos)

                harness.controller.showWorktreeSidebar()

                await eventually("visible Repo Explorer should collapse on toggle") {
                    harness.controller.isSidebarCollapsed
                        && harness.atoms.core.workspaceSidebarState.sidebarCollapsed
                        && harness.atoms.core.workspaceSidebarState.sidebarHasFocus == false
                }
            }
        )
    }
}
