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

    @Test("showInboxNotifications expands sidebar and focuses inbox when command bar is not key")
    func showInboxNotificationsExpandsAndFocuses() async {
        await withMainSplitViewControllerHarness(
            withRepos: true,
            configureUIState: { $0.setSidebarCollapsed(true) },
            body: { harness in
                harness.controller.showInboxNotifications(commandBarIsKey: false)
                await eventually(
                    "inbox should become first responder"
                ) {
                    harness.atoms.workspaceSidebarState.sidebarSurface == .inbox
                        && harness.atoms.workspaceSidebarState.sidebarHasFocus
                        && (harness.window.firstResponder as? NSView)?.identifier
                            == InboxNotificationSidebarView.focusTargetIdentifier
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

                #expect(harness.atoms.workspaceSidebarState.sidebarSurface == .inbox)
                #expect(harness.atoms.workspaceSidebarState.sidebarHasFocus == false)
                #expect(
                    (harness.window.firstResponder as? NSView)?.identifier
                        != InboxNotificationSidebarView.focusTargetIdentifier
                )
            }
        )
    }

    @Test("showInboxNotifications retries until a delayed inbox mounts")
    func showInboxNotificationsRetriesUntilDelayedInboxMounts() async {
        await withMainSplitViewControllerHarness(
            withRepos: true,
            configureUIState: { $0.setSidebarCollapsed(true) },
            sidebarRootViewBuilder: { uiState, onEscape in
                AnyView(DelayedInboxTestSidebarView(uiState: uiState, onEscape: onEscape))
            },
            body: { harness in
                harness.controller.showInboxNotifications(commandBarIsKey: false)

                await eventually("delayed inbox should eventually gain focus") {
                    harness.atoms.workspaceSidebarState.sidebarSurface == .inbox
                        && harness.atoms.workspaceSidebarState.sidebarHasFocus
                        && (harness.window.firstResponder as? NSView)?.identifier
                            == InboxNotificationSidebarView.focusTargetIdentifier
                        && harness.controller.isSidebarCollapsed == false
                }
            }
        )
    }

    @Test("showWorktreeSidebar returns to repos surface and lets inbox focus clear naturally")
    func showWorktreeSidebarSwitchesSurfaceAndClearsInboxFocus() async {
        await withMainSplitViewControllerHarness(
            withRepos: true,
            body: { harness in
                harness.controller.showInboxNotifications(commandBarIsKey: false)
                await eventually("inbox should gain focus") {
                    harness.atoms.workspaceSidebarState.sidebarHasFocus
                }

                harness.controller.showWorktreeSidebar()
                await eventually("inbox focus should clear after surface swap") {
                    harness.atoms.workspaceSidebarState.sidebarSurface == .repos
                        && harness.atoms.workspaceSidebarState.sidebarHasFocus == false
                }
            }
        )
    }

    @Test("repos focus target publishes sidebar keyboard ownership")
    func focusSidebarReposSurfacePublishesKeyboardOwnership() async {
        await withMainSplitViewControllerHarness(
            withRepos: true,
            sidebarRootViewBuilder: { uiState, onEscape in
                AnyView(ReposFocusTargetTestSidebarView(uiState: uiState, onEscape: onEscape))
            },
            body: { harness in
                harness.atoms.workspaceSidebarState.setSidebarSurface(.repos)
                harness.atoms.workspaceSidebarState.setSidebarHasFocus(false)

                await eventually("repos focus bridge should become first responder") {
                    harness.controller.focusSidebar()
                        && harness.atoms.workspaceSidebarState.sidebarHasFocus
                        && (harness.window.firstResponder as? NSView)?.identifier
                            == RepoExplorerView.focusTargetIdentifier
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
                    harness.atoms.workspaceSidebarState.sidebarSurface == .inbox
                        && harness.atoms.workspaceSidebarState.sidebarHasFocus
                        && harness.controller.isSidebarCollapsed == false
                }

                harness.controller.showInboxNotifications(commandBarIsKey: false)
                await eventually("visible inbox should collapse on second toggle") {
                    harness.controller.isSidebarCollapsed
                        && harness.atoms.workspaceSidebarState.sidebarCollapsed
                        && harness.atoms.workspaceSidebarState.sidebarHasFocus == false
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
                #expect(harness.atoms.workspaceSidebarState.sidebarSurface == .repos)

                harness.controller.showWorktreeSidebar()
                await eventually("visible repos should collapse on toggle") {
                    harness.controller.isSidebarCollapsed
                        && harness.atoms.workspaceSidebarState.sidebarCollapsed
                        && harness.atoms.workspaceSidebarState.sidebarHasFocus == false
                }
            }
        )
    }

    @Test("showSidebarFilter leaves inbox untouched until inbox search exists")
    func showSidebarFilterIsNoOpFromInbox() async {
        await withMainSplitViewControllerHarness(
            withRepos: true,
            body: { harness in
                harness.controller.showInboxNotifications(commandBarIsKey: false)
                await eventually("inbox should be visible") {
                    harness.atoms.workspaceSidebarState.sidebarSurface == .inbox
                        && harness.controller.isSidebarCollapsed == false
                }

                harness.controller.showSidebarFilter()

                #expect(harness.atoms.workspaceSidebarState.sidebarSurface == .inbox)
                #expect(harness.atoms.workspaceSidebarState.isFilterVisible == false)
                #expect(harness.controller.isSidebarCollapsed == false)
            }
        )
    }

    @Test("showInboxNotifications expands a restored collapsed inbox surface")
    func showInboxNotificationsExpandsCollapsedInboxSurface() async {
        await withMainSplitViewControllerHarness(
            withRepos: true,
            configureUIState: {
                $0.setSidebarCollapsed(true)
                $0.setSidebarSurface(.inbox)
            },
            body: { harness in
                #expect(harness.controller.isSidebarCollapsed == true)
                #expect(harness.atoms.workspaceSidebarState.sidebarSurface == .inbox)

                harness.controller.showInboxNotifications(commandBarIsKey: false)

                await eventually("collapsed inbox state should expand instead of collapsing") {
                    harness.controller.isSidebarCollapsed == false
                        && harness.atoms.workspaceSidebarState.sidebarCollapsed == false
                        && harness.atoms.workspaceSidebarState.sidebarSurface == .inbox
                        && harness.atoms.workspaceSidebarState.sidebarHasFocus
                }
            }
        )
    }

    @Test("production pane inbox popover clear uses window scoped wiring")
    func productionPaneInboxPopoverClearUsesWindowScopedWiring() async throws {
        try await withIsolatedCommandDispatcher(
            configure: {},
            body: {
                let inboxAtom = InboxNotificationAtom()
                try await withMainSplitViewControllerHarness(
                    withRepos: true,
                    inboxAtom: inboxAtom,
                    body: { harness in
                        let pane = harness.store.createPane()
                        let tab = Tab(paneId: pane.id)
                        harness.store.appendTab(tab)
                        harness.store.setActiveTab(tab.id)
                        let notification = makePaneInboxNotification(paneId: pane.id, title: "Clearable")
                        inboxAtom.append(notification)
                        let commandHandler = MainSplitViewControllerCommandHandlerProbe()
                        AppCommandDispatcher.shared.handler = commandHandler
                        AppCommandDispatcher.shared.appCommandRouter = nil

                        let hostingView = makePaneInboxPopoverHostingView(
                            presentation: harness.controller.makePaneInboxPresentation(),
                            parentPaneId: pane.id,
                            paneIds: [pane.id]
                        )
                        let popoverWindow = makePopoverWindow(hostingView: hostingView)
                        defer { popoverWindow.orderOut(nil) }

                        let clearButton = try #require(
                            findAccessibleElement(in: hostingView, identifier: "paneInboxClearButton")
                        )

                        pressAccessibleElement(clearButton)

                        #expect(commandHandler.executedTargets.isEmpty)
                        #expect(inboxAtom.notifications.first?.isRead == true)
                        #expect(inboxAtom.notifications.first?.isDismissedFromPaneInbox == true)
                    }
                )
            }
        )
    }

    @Test("production pane inbox popover row activation uses window scoped focus")
    func productionPaneInboxPopoverRowActivationUsesWindowScopedFocus() async throws {
        try await withIsolatedCommandDispatcher(
            configure: {},
            body: {
                let inboxAtom = InboxNotificationAtom()
                try await withMainSplitViewControllerHarness(
                    withRepos: true,
                    inboxAtom: inboxAtom,
                    body: { harness in
                        let targetPane = harness.store.createPane(
                            title: "Target"
                        )
                        let targetTab = Tab(paneId: targetPane.id)
                        harness.store.appendTab(targetTab)
                        let activePane = harness.store.createPane(
                            title: "Active"
                        )
                        let activeTab = Tab(paneId: activePane.id)
                        harness.store.appendTab(activeTab)
                        harness.store.setActiveTab(activeTab.id)
                        let notification = makePaneInboxNotification(paneId: targetPane.id, title: "Focusable")
                        inboxAtom.append(notification)
                        let commandHandler = MainSplitViewControllerCommandHandlerProbe()
                        AppCommandDispatcher.shared.handler = commandHandler
                        AppCommandDispatcher.shared.appCommandRouter = nil

                        let hostingView = makePaneInboxPopoverHostingView(
                            presentation: harness.controller.makePaneInboxPresentation(),
                            parentPaneId: targetPane.id,
                            paneIds: [targetPane.id]
                        )
                        let popoverWindow = makePopoverWindow(hostingView: hostingView)
                        defer { popoverWindow.orderOut(nil) }

                        let row = try #require(
                            findAccessibleElement(
                                in: hostingView,
                                identifier: "paneInboxNotificationRow.\(notification.id.uuidString)"
                            )
                        )

                        pressAccessibleElement(row)

                        #expect(commandHandler.executedTargets.isEmpty)
                        #expect(harness.store.activeTabId == targetTab.id)
                        #expect(inboxAtom.notifications.first?.isRead == true)
                        #expect(inboxAtom.notifications.first?.isDismissedFromPaneInbox == true)
                    }
                )
            }
        )
    }

}

struct DelayedInboxTestSidebarView: View {
    let uiState: WorkspaceSidebarState
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
                    MainSplitViewControllerTestInboxView(
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

struct ReposFocusTargetTestSidebarView: View {
    let uiState: WorkspaceSidebarState
    let onEscape: @MainActor @Sendable () -> Void

    var body: some View {
        Group {
            switch uiState.sidebarSurface {
            case .repos:
                RepoExplorerFocusBridge(uiState: uiState)
                    .frame(width: 12, height: 12)
            case .inbox:
                MainSplitViewControllerTestInboxView(
                    uiState: uiState,
                    onEscape: onEscape
                )
            }
        }
        .frame(minWidth: 200, maxWidth: .infinity, maxHeight: .infinity)
    }
}

@MainActor
private final class MainSplitViewControllerCommandHandlerProbe: WorkspaceCommandHandling {
    var executedCommands: [AppCommand] = []
    var executedTargets: [(command: AppCommand, target: UUID, targetType: SearchItemType)] = []

    func execute(_ command: AppCommand) {
        executedCommands.append(command)
    }

    func execute(_ command: AppCommand, target: UUID, targetType: SearchItemType) {
        executedTargets.append((command, target, targetType))
    }

    func canExecute(_: AppCommand) -> Bool {
        true
    }

    func canExecute(_: AppCommand, target _: UUID, targetType _: SearchItemType) -> Bool {
        true
    }

    func executeExtractPaneToTab(tabId _: UUID, paneId _: UUID, targetTabIndex _: Int?) {}

    func executeMovePaneToTab(sourcePaneId _: UUID, sourceTabId _: UUID?, targetTabId _: UUID) {}
}

@MainActor
private func makePaneInboxPopoverHostingView(
    presentation: PaneInboxPresentation,
    parentPaneId: UUID,
    paneIds: [UUID]
) -> NSHostingView<AnyView> {
    NSHostingView(
        rootView: AnyView(
            presentation.popoverContent(
                parentPaneId,
                paneIds,
                {
                    presentation.clear(parentPaneId, paneIds)
                },
                ignorePaneInboxPopoverClose
            )
            .frame(width: 360, height: 240)
        )
    )
}

@MainActor
private func ignorePaneInboxPopoverClose() {}

@MainActor
private func makePopoverWindow(hostingView: NSView) -> NSWindow {
    let window = NSWindow(
        contentRect: CGRect(x: 0, y: 0, width: 360, height: 240),
        styleMask: [.titled, .closable],
        backing: .buffered,
        defer: false
    )
    window.contentView = hostingView
    window.makeKeyAndOrderFront(nil)
    hostingView.layoutSubtreeIfNeeded()
    return window
}

@MainActor
private func makePaneInboxNotification(paneId: UUID, title: String) -> InboxNotification {
    InboxNotification(
        id: UUID(),
        timestamp: Date(timeIntervalSince1970: 100),
        kind: .agentRpc,
        title: title,
        body: nil,
        source: .pane(.init(paneId: paneId)),
        isRead: false,
        isDismissedFromPaneInbox: false
    )
}

@MainActor
private func findAccessibleElement(in root: AnyObject, identifier: String) -> AnyObject? {
    var visited: Set<ObjectIdentifier> = []
    return findAccessibleElement(in: root, identifier: identifier, visited: &visited)
}

@MainActor
private func findAccessibleElement(
    in element: AnyObject,
    identifier: String,
    visited: inout Set<ObjectIdentifier>
) -> AnyObject? {
    let objectIdentifier = ObjectIdentifier(element)
    guard visited.insert(objectIdentifier).inserted else { return nil }

    if accessibilityIdentifier(of: element) == identifier {
        return element
    }

    for child in accessibilityChildren(of: element) {
        if let match = findAccessibleElement(in: child, identifier: identifier, visited: &visited) {
            return match
        }
    }

    for subview in (element as? NSView)?.subviews ?? [] {
        if let match = findAccessibleElement(in: subview, identifier: identifier, visited: &visited) {
            return match
        }
    }

    return nil
}

@MainActor
private func accessibilityIdentifier(of element: AnyObject) -> String? {
    if let view = element as? NSView, let identifier = view.identifier?.rawValue {
        return identifier
    }
    return element.accessibilityIdentifier?()
}

@MainActor
private func accessibilityChildren(of element: AnyObject) -> [AnyObject] {
    guard let children = element.accessibilityChildren?() else { return [] }
    return children.compactMap { $0 as? NSObject }
}

@MainActor
private func pressAccessibleElement(_ element: AnyObject) {
    guard element.accessibilityPerformPress?() != true else { return }
    (element as? NSButton)?.performClick(nil)
}
