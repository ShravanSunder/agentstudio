import AppKit
import Testing

@testable import AgentStudio

@MainActor
@Suite(.serialized)
struct MainSplitViewControllerSidebarStateTests {
    init() {
        installTestAtomRegistryIfNeeded()
    }

    @Test("viewDidLoad with sidebarCollapsed true collapses the sidebar")
    func respectsSidebarCollapsedAtomOnLoad() async {
        await withMainSplitViewControllerHarness(
            withRepos: true,
            configureUIState: { $0.setSidebarCollapsed(true) },
            body: { harness in
                #expect(harness.controller.isSidebarCollapsed == true)
            }
        )
    }

    @Test("viewDidLoad with no repos force-collapses the sidebar")
    func noReposForceCollapseSidebar() async {
        await withMainSplitViewControllerHarness(
            withRepos: false,
            body: { harness in
                #expect(harness.controller.isSidebarCollapsed == true)
            }
        )
    }

    @Test("toggleSidebarFromCommand writes collapsed state back into UIStateAtom")
    func toggleSidebarWritesBackIntoAtom() async {
        await withMainSplitViewControllerHarness(
            withRepos: true,
            body: { harness in
                #expect(harness.atoms.uiState.sidebarCollapsed == false)

                harness.controller.toggleSidebarFromCommand()
                await Task.yield()
                #expect(harness.atoms.uiState.sidebarCollapsed == true)

                harness.controller.toggleSidebarFromCommand()
                await Task.yield()
                #expect(harness.atoms.uiState.sidebarCollapsed == false)
            }
        )
    }

    @Test("resize persistence writes current collapsed state into UIStateAtom")
    func resizePersistsSidebarCollapsedState() async {
        await withMainSplitViewControllerHarness(
            withRepos: true,
            body: { harness in
                harness.controller.toggleSidebarFromCommand()
                await Task.yield()
                #expect(harness.controller.isSidebarCollapsed == true)
                #expect(harness.atoms.uiState.sidebarCollapsed == true)

                harness.atoms.uiState.setSidebarCollapsed(false)
                #expect(harness.atoms.uiState.sidebarCollapsed == false)

                harness.controller.splitViewDidResizeSubviews(Notification(name: .init("test")))
                #expect(harness.atoms.uiState.sidebarCollapsed == true)
            }
        )
    }
}
