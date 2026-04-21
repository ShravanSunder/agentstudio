import AppKit
import SwiftUI
import Testing

@testable import AgentStudio

@MainActor
@Suite(.serialized)
struct MainSplitViewControllerCompositeCommandTests {
    init() {
        installTestAtomRegistryIfNeeded()
    }

    @Test("showInboxNotifications expands sidebar and focuses placeholder when command bar is not key")
    func showInboxNotificationsExpandsAndFocuses() async {
        await withMainSplitViewControllerHarness(
            withRepos: true,
            configureUIState: { $0.setSidebarCollapsed(true) },
            body: { harness in
                harness.controller.showInboxNotifications(commandBarIsKey: false)
                await eventually(
                    "inbox placeholder should become first responder"
                ) {
                    harness.atoms.uiState.sidebarSurface == .inbox
                        && harness.atoms.uiState.sidebarHasFocus
                        && (harness.window.firstResponder as? NSView)?.identifier
                            == InboxNotificationPlaceholderView.focusTargetIdentifier
                        && harness.controller.isSidebarCollapsed == false
                }
            }
        )
    }

    @Test("showInboxNotifications with command bar key does not steal focus")
    func showInboxNotificationsDoesNotStealFocusWhenCommandBarIsKey() async {
        await withMainSplitViewControllerHarness(
            withRepos: true,
            configureUIState: { $0.setSidebarHasFocus(true) },
            body: { harness in
                harness.controller.showInboxNotifications(commandBarIsKey: true)
                await Task.yield()

                #expect(harness.atoms.uiState.sidebarSurface == .inbox)
                #expect(harness.atoms.uiState.sidebarHasFocus == false)
                #expect(
                    (harness.window.firstResponder as? NSView)?.identifier
                        != InboxNotificationPlaceholderView.focusTargetIdentifier
                )
            }
        )
    }

    @Test("showInboxNotifications retries until a delayed inbox placeholder mounts")
    func showInboxNotificationsRetriesUntilDelayedPlaceholderMounts() async {
        await withMainSplitViewControllerHarness(
            withRepos: true,
            configureUIState: { $0.setSidebarCollapsed(true) },
            sidebarRootViewBuilder: { uiState, onEscape in
                AnyView(DelayedInboxPlaceholderSidebarView(uiState: uiState, onEscape: onEscape))
            },
            body: { harness in
                harness.controller.showInboxNotifications(commandBarIsKey: false)

                await eventually("delayed inbox placeholder should eventually gain focus") {
                    harness.atoms.uiState.sidebarSurface == .inbox
                        && harness.atoms.uiState.sidebarHasFocus
                        && (harness.window.firstResponder as? NSView)?.identifier
                            == InboxNotificationPlaceholderView.focusTargetIdentifier
                        && harness.controller.isSidebarCollapsed == false
                }
            }
        )
    }

    @Test("showWorktreeSidebar returns to repos surface and lets placeholder focus clear naturally")
    func showWorktreeSidebarSwitchesSurfaceAndClearsPlaceholderFocus() async {
        await withMainSplitViewControllerHarness(
            withRepos: true,
            body: { harness in
                harness.controller.showInboxNotifications(commandBarIsKey: false)
                await eventually("placeholder should gain focus") {
                    harness.atoms.uiState.sidebarHasFocus
                }

                harness.controller.showWorktreeSidebar()
                await eventually("placeholder focus should clear after surface swap") {
                    harness.atoms.uiState.sidebarSurface == .repos
                        && harness.atoms.uiState.sidebarHasFocus == false
                }
            }
        )
    }

    @Test("showInboxNotifications toggles a visible inbox sidebar closed")
    func showInboxNotificationsTogglesVisibleInboxClosed() async {
        await withMainSplitViewControllerHarness(
            withRepos: true,
            body: { harness in
                harness.controller.showInboxNotifications(commandBarIsKey: false)
                await eventually("inbox should be visible and focused") {
                    harness.atoms.uiState.sidebarSurface == .inbox
                        && harness.atoms.uiState.sidebarHasFocus
                        && harness.controller.isSidebarCollapsed == false
                }

                harness.controller.showInboxNotifications(commandBarIsKey: false)
                await eventually("visible inbox should collapse on second toggle") {
                    harness.controller.isSidebarCollapsed
                        && harness.atoms.uiState.sidebarCollapsed
                        && harness.atoms.uiState.sidebarHasFocus == false
                }
            }
        )
    }

    @Test("showWorktreeSidebar toggles a visible repos sidebar closed")
    func showWorktreeSidebarTogglesVisibleReposClosed() async {
        await withMainSplitViewControllerHarness(
            withRepos: true,
            body: { harness in
                #expect(harness.controller.isSidebarCollapsed == false)
                #expect(harness.atoms.uiState.sidebarSurface == .repos)

                harness.controller.showWorktreeSidebar()
                await eventually("visible repos should collapse on toggle") {
                    harness.controller.isSidebarCollapsed
                        && harness.atoms.uiState.sidebarCollapsed
                        && harness.atoms.uiState.sidebarHasFocus == false
                }
            }
        )
    }

    @Test("showSidebarFilter switches inbox surface back to repos and reveals filter")
    func showSidebarFilterSwitchesInboxBackToRepos() async {
        await withMainSplitViewControllerHarness(
            withRepos: true,
            body: { harness in
                harness.controller.showInboxNotifications(commandBarIsKey: false)
                await eventually("inbox should be visible") {
                    harness.atoms.uiState.sidebarSurface == .inbox
                        && harness.controller.isSidebarCollapsed == false
                }

                harness.controller.showSidebarFilter()

                #expect(harness.atoms.uiState.sidebarSurface == .inbox)
                #expect(harness.atoms.uiState.isFilterVisible == false)
                #expect(harness.controller.isSidebarCollapsed == false)
            }
        )
    }

}

struct DelayedInboxPlaceholderSidebarView: View {
    let uiState: UIStateAtom
    let onEscape: @MainActor @Sendable () -> Void

    @State private var isInboxMounted = false

    var body: some View {
        Group {
            switch uiState.sidebarSurface {
            case .repos:
                Color.clear
                    .onAppear {
                        isInboxMounted = false
                    }
            case .inbox:
                if isInboxMounted {
                    InboxNotificationPlaceholderView(
                        uiState: uiState,
                        onEscape: onEscape
                    )
                } else {
                    Color.clear
                        .task {
                            for _ in 0..<2 {
                                await Task.yield()
                            }
                            isInboxMounted = true
                        }
                }
            }
        }
        .frame(minWidth: 200, maxWidth: .infinity, maxHeight: .infinity)
    }
}
