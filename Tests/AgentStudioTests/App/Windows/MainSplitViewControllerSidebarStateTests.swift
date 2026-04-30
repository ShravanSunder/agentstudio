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

    @Test("viewDidLoad restores sidebar width from workspace metadata")
    func viewDidLoadRestoresSidebarWidthFromWorkspaceMetadata() async {
        await withMainSplitViewControllerHarness(
            withRepos: true,
            configureWorkspaceMetadata: { $0.setSidebarWidth(320) },
            body: { harness in
                layOutMainSplitViewController(harness)
                await eventually("sidebar should restore persisted workspace width") {
                    let sidebarWidth = harness.controller.splitViewItems.first?.viewController.view.frame.width ?? 0
                    return abs(sidebarWidth - 320) <= 5
                }
            }
        )
    }

    @Test("resize persistence writes sidebar width into workspace metadata")
    func resizePersistsSidebarWidthIntoWorkspaceMetadata() async {
        await withMainSplitViewControllerHarness(
            withRepos: true,
            body: { harness in
                layOutMainSplitViewController(harness)
                harness.controller.splitView.setPosition(330, ofDividerAt: 0)
                harness.controller.splitView.layoutSubtreeIfNeeded()
                harness.controller.splitViewDidResizeSubviews(Notification(name: .init("test")))

                let sidebarWidth = harness.controller.splitViewItems.first?.viewController.view.frame.width ?? 0
                #expect(sidebarWidth > 300)
                #expect(abs(harness.store.metadataAtom.sidebarWidth - sidebarWidth) <= 1)
            }
        )
    }

    @Test("showWorktreeSidebar expands a restored collapsed inbox surface back to repos")
    func showWorktreeSidebarExpandsCollapsedInboxSurface() async {
        await withMainSplitViewControllerHarness(
            withRepos: true,
            configureUIState: {
                $0.setSidebarCollapsed(true)
                $0.setSidebarSurface(.inbox)
            },
            body: { harness in
                #expect(harness.controller.isSidebarCollapsed == true)
                #expect(harness.atoms.uiState.sidebarSurface == .inbox)

                harness.controller.showWorktreeSidebar()

                await eventually("showWorktreeSidebar should expand collapsed inbox state") {
                    harness.controller.isSidebarCollapsed == false
                        && harness.atoms.uiState.sidebarCollapsed == false
                        && harness.atoms.uiState.sidebarSurface == .repos
                }
            }
        )
    }

    @Test("collapseSidebar before viewDidLoad records collapsed shell state for restore")
    func collapseSidebarBeforeViewLoadPersistsIntent() async {
        await withUnloadedMainSplitViewControllerHarness(
            withRepos: true,
            body: { harness in
                #expect(harness.controller.isViewLoaded == false)
                #expect(harness.atoms.uiState.sidebarCollapsed == false)

                harness.controller.collapseSidebar()

                #expect(harness.atoms.uiState.sidebarCollapsed == true)
                #expect(harness.atoms.uiState.sidebarHasFocus == false)
            }
        )
    }

    private func layOutMainSplitViewController(_ harness: MainSplitViewControllerHarness) {
        harness.window.setContentSize(NSSize(width: 1000, height: 700))
        harness.controller.view.frame = NSRect(x: 0, y: 0, width: 1000, height: 700)
        harness.controller.splitView.frame = harness.controller.view.bounds
        harness.controller.view.layoutSubtreeIfNeeded()
        harness.controller.viewDidLayout()
    }
}
