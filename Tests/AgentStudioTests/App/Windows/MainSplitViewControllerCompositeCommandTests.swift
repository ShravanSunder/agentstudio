import AppKit
import Testing

@testable import AgentStudio
@testable import AgentStudioCore
@testable import AgentStudioRepoExplorer
@testable import AgentStudioTestSupport

@MainActor
@Suite(.serialized)
struct MainSplitViewControllerCompositeCommandTests {
    init() {
        installTestCoreAtomsIfNeeded()
    }

    @Test("focus sidebar enters a hidden sidebar and Escape restores its origin")
    func focusSidebarEntersHiddenSidebarAndEscapeRestoresOrigin() async throws {
        try await withMainSplitViewControllerHarness(
            withRepos: true,
            configureUIState: { $0.setSidebarCollapsed(true) },
            body: { harness in
                let externalResponder = MainSplitViewControllerTestInboxFocusableView()
                let paneView = try #require(
                    harness.controller.splitViewItems.last?.viewController.view
                )
                paneView.addSubview(externalResponder)
                #expect(harness.window.makeFirstResponder(externalResponder))

                harness.controller.focusSidebarFromCommand()

                await eventually("focus command should expand and focus the sidebar host") {
                    !harness.controller.isSidebarCollapsed
                        && (harness.window.firstResponder as? NSView)?.identifier
                            == RepoExplorerView.focusTargetIdentifier
                }

                // Saved UI restoration may clear the runtime fact after focus.
                harness.atoms.core.workspaceSidebarState.setSidebarHasFocus(false)
                harness.controller.focusSidebarFromCommand()
                await eventually("repeated sidebar entry should repair runtime focus publication") {
                    harness.atoms.core.workspaceSidebarState.sidebarHasFocus
                }
                let escapeEvent = try #require(
                    NSEvent.keyEvent(
                        with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                        windowNumber: harness.window.windowNumber, context: nil,
                        characters: "\u{1B}", charactersIgnoringModifiers: "\u{1B}",
                        isARepeat: false, keyCode: 53
                    )
                )
                harness.window.sendEvent(escapeEvent)

                #expect(!harness.controller.isSidebarCollapsed)
                #expect(harness.window.firstResponder === externalResponder)
            }
        )
    }

    @Test("hiding a focused sidebar restores the external responder")
    func hidingFocusedSidebarRestoresExternalResponder() async throws {
        try await withMainSplitViewControllerHarness(
            withRepos: true,
            body: { harness in
                let externalResponder = MainSplitViewControllerTestInboxFocusableView()
                let paneView = try #require(
                    harness.controller.splitViewItems.last?.viewController.view
                )
                paneView.addSubview(externalResponder)
                #expect(harness.window.makeFirstResponder(externalResponder))

                harness.controller.focusSidebarFromCommand()
                await eventually("focus command should focus the sidebar host") {
                    (harness.window.firstResponder as? NSView)?.identifier
                        == RepoExplorerView.focusTargetIdentifier
                }

                harness.controller.toggleSidebarFromCommand()

                #expect(harness.controller.isSidebarCollapsed)
                #expect(harness.window.firstResponder === externalResponder)
            }
        )
    }

    @Test("sidebar filter focuses Panes without switching screens")
    func sidebarFilterPreservesPanesScreen() async {
        await withMainSplitViewControllerHarness(
            withRepos: true,
            configureUIState: {
                $0.setSidebarSurface(.panes)
                $0.setFilterVisible(false)
            },
            body: { harness in
                harness.controller.showSidebarFilter()
                #expect(harness.atoms.core.workspaceSidebarState.sidebarSurface == .panes)
                #expect(harness.atoms.core.workspaceSidebarState.isFilterVisible)
            }
        )
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
