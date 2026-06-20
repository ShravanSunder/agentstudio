import AppKit
import Foundation
import GhosttyKit
import Testing

@testable import AgentStudio

@MainActor
@Suite("MainWindowController inbox toolbar button", .serialized)
struct MainWindowControllerInboxToolbarButtonTests {
    init() {
        installTestAtomRegistryIfNeeded()
    }

    @Test("bell button is installed next to the sidebar controls")
    func bellButtonIsInstalled() async {
        await withMainWindowControllerHarness { harness in
            let worktreeButton =
                findDescendant(
                    in: harness.window,
                    identifier: "worktreeToolbarButton"
                ) as? NSButton
            let bellButton =
                findDescendant(
                    in: harness.window,
                    identifier: "inboxToolbarBell"
                ) as? NSButton

            #expect(worktreeButton != nil)
            #expect(bellButton != nil)
            #expect(bellButton?.image?.accessibilityDescription == "Toggle Inbox")
        }
    }

    @Test("main window does not install a product NSToolbar")
    func mainWindowDoesNotInstallProductToolbar() async {
        await withMainWindowControllerHarness { harness in
            #expect(harness.window.toolbar == nil)
        }
    }

    @Test("titlebar sidebar controls omit search and leave traffic-light padding")
    func sidebarControlsOmitSearchAndPadFromTrafficLights() async {
        await withMainWindowControllerHarness { harness in
            let accessory =
                findDescendant(
                    in: harness.window,
                    identifier: "sidebarToolbarAccessory"
                ) as? NSStackView
            let buttons = accessory?.arrangedSubviews.compactMap { $0 as? SidebarToolbarButton } ?? []

            #expect(accessory != nil)
            #expect(accessory?.edgeInsets.left == 22)
            #expect(buttons.map { $0.identifier?.rawValue } == ["worktreeToolbarButton", "inboxToolbarBell"])
            #expect(buttons.allSatisfy { $0.currentSymbolName != "magnifyingglass" })
        }
    }

    @Test("titlebar sidebar controls apply typed AppKit tooltips")
    func sidebarControlsApplyTypedAppKitTooltips() async {
        await withMainWindowControllerHarness { harness in
            let worktreeButton =
                findDescendant(
                    in: harness.window,
                    identifier: "worktreeToolbarButton"
                ) as? NSButton
            let bellButton =
                findDescendant(
                    in: harness.window,
                    identifier: "inboxToolbarBell"
                ) as? NSButton

            #expect(
                worktreeButton?.toolTip
                    == AppCommand.showWorktreeSidebar.definition.controlTooltipRenderValue().text
            )
            #expect(
                bellButton?.toolTip
                    == AppCommand.showInboxNotifications.definition.controlTooltipRenderValue().text
            )
            #expect(worktreeButton?.accessibilityLabel() == "Toggle Worktrees")
            #expect(bellButton?.accessibilityLabel() == "Toggle Inbox")
        }
    }

    @Test("right titlebar actions are icon only and accessible")
    func rightTitlebarActionsAreIconOnlyAndAccessible() async throws {
        try await withMainWindowControllerHarness { harness in
            let actionAccessory = try #require(
                findDescendant(
                    in: harness.window,
                    identifier: "titlebarActionAccessory"
                ) as? NSStackView
            )
            let managementButton = try #require(
                findDescendant(
                    in: harness.window,
                    identifier: "managementLayerTitlebarButton"
                ) as? NSButton
            )
            let watchFolderButton = try #require(
                findDescendant(
                    in: harness.window,
                    identifier: "watchFolderTitlebarButton"
                ) as? NSButton
            )

            #expect(
                actionAccessory.arrangedSubviews.compactMap { $0.identifier?.rawValue } == [
                    "managementLayerTitlebarButton",
                    "watchFolderTitlebarButton",
                ])
            #expect(managementButton.title.isEmpty)
            #expect(watchFolderButton.title.isEmpty)
            #expect(
                managementButton.toolTip
                    == AppCommand.toggleManagementLayer.definition.controlTooltipRenderValue().text
            )
            #expect(
                watchFolderButton.toolTip
                    == AppCommand.watchFolder.definition.controlTooltipRenderValue().text
            )
            #expect(managementButton.accessibilityLabel() == "Manage Workspace")
            #expect(watchFolderButton.accessibilityLabel() == "Watch Folder")
            #expect(managementButton.image?.accessibilityDescription == "Manage Workspace")
            #expect(watchFolderButton.image?.accessibilityDescription == "Watch Folder")
        }
    }

    @Test("clicking Watch Folder titlebar action dispatches command")
    func clickingWatchFolderTitlebarActionDispatchesCommand() async throws {
        let appRouter = TitlebarActionAppRouterProbe(appCommands: [.watchFolder])
        try await withIsolatedCommandDispatcher(
            configure: {
                AppCommandDispatcher.shared.handler = nil
                AppCommandDispatcher.shared.appCommandRouter = appRouter
            },
            body: {
                try await withMainWindowControllerHarness { harness in
                    let watchFolderButton = try #require(
                        findDescendant(
                            in: harness.window,
                            identifier: "watchFolderTitlebarButton"
                        ) as? NSButton
                    )

                    watchFolderButton.performClick(nil)

                    #expect(appRouter.handledCommands == [.watchFolder])
                }
            }
        )
    }

    @Test("clicking management titlebar action dispatches command")
    func clickingManagementTitlebarActionDispatchesCommand() async throws {
        let handler = TitlebarActionCommandHandlerProbe()
        try await withIsolatedCommandDispatcher(
            configure: {
                AppCommandDispatcher.shared.handler = nil
                AppCommandDispatcher.shared.appCommandRouter = nil
            },
            body: {
                try await withMainWindowControllerHarness { harness in
                    AppCommandDispatcher.shared.handler = handler
                    let managementButton = try #require(
                        findDescendant(
                            in: harness.window,
                            identifier: "managementLayerTitlebarButton"
                        ) as? NSButton
                    )

                    managementButton.performClick(nil)

                    #expect(handler.executedCommands == [.toggleManagementLayer])
                }
            }
        )
    }

    @Test("management titlebar icon tracks non-click management state changes")
    func managementTitlebarIconTracksExternalManagementStateChanges() async throws {
        try await withMainWindowControllerHarness { harness in
            let managementButton = try #require(
                findDescendant(
                    in: harness.window,
                    identifier: "managementLayerTitlebarButton"
                ) as? TitlebarActionButton
            )

            #expect(managementButton.currentSymbolName == "rectangle.split.2x2")

            harness.atoms.managementLayer.activate()

            await eventually("management titlebar icon should become active") {
                managementButton.currentSymbolName == "rectangle.split.2x2.fill"
            }

            harness.atoms.managementLayer.deactivate()

            await eventually("management titlebar icon should become inactive") {
                managementButton.currentSymbolName == "rectangle.split.2x2"
            }
        }
    }

    @Test("management titlebar observation releases after window teardown")
    func managementTitlebarObservationReleasesAfterWindowTeardown() async {
        weak var weakController: MainWindowController?
        var atomsAfterClose: AtomRegistry?

        await withMainWindowControllerHarness { harness in
            weakController = harness.controller
            atomsAfterClose = harness.atoms
        }

        atomsAfterClose?.managementLayer.activate()
        await Task.yield()

        #expect(weakController == nil)
    }

    @Test("titlebar action strip fits at minimum window width")
    func titlebarActionStripFitsAtMinimumWindowWidth() async throws {
        try await withMainWindowControllerHarness { harness in
            harness.window.setFrame(
                NSRect(x: 0, y: 0, width: 720, height: 600),
                display: true
            )
            harness.window.contentView?.layoutSubtreeIfNeeded()

            let sidebarAccessory = try #require(
                findDescendant(
                    in: harness.window,
                    identifier: "sidebarToolbarAccessory"
                ) as? NSStackView
            )
            let actionAccessory = try #require(
                findDescendant(
                    in: harness.window,
                    identifier: "titlebarActionAccessory"
                ) as? NSStackView
            )
            let actionButtons = actionAccessory.arrangedSubviews.compactMap { $0 as? NSButton }

            actionAccessory.layoutSubtreeIfNeeded()
            sidebarAccessory.layoutSubtreeIfNeeded()

            let sidebarFrame = sidebarAccessory.convert(sidebarAccessory.bounds, to: nil)
            let actionFrame = actionAccessory.convert(actionAccessory.bounds, to: nil)

            #expect(sidebarFrame.maxX < actionFrame.minX)
            #expect(actionFrame.maxX <= harness.window.frame.width)
            #expect(actionButtons.count == 2)
            #expect(
                actionButtons.allSatisfy { button in
                    actionAccessory.bounds.contains(button.convert(button.bounds, to: actionAccessory))
                })
        }
    }

    @Test("sidebar toolbar icons track active surface")
    func sidebarToolbarIconsTrackActiveSurface() async {
        await withMainWindowControllerHarness { harness in
            let worktreeButton =
                findDescendant(
                    in: harness.window,
                    identifier: "worktreeToolbarButton"
                ) as? NSButton
            let bellButton =
                findDescendant(
                    in: harness.window,
                    identifier: "inboxToolbarBell"
                ) as? NSButton

            let worktreeToolbarButton = worktreeButton as? SidebarToolbarButton
            let inboxToolbarButton = bellButton as? SidebarToolbarButton

            #expect(worktreeToolbarButton?.currentSymbolName == "square.stack.3d.down.right.fill")
            #expect(inboxToolbarButton?.currentSymbolName == "bell")

            harness.atoms.workspaceSidebarState.setSidebarSurface(.inbox)

            await eventually("inbox toolbar icon should become active") {
                worktreeToolbarButton?.currentSymbolName == "square.stack.3d.down.right"
                    && inboxToolbarButton?.currentSymbolName == "bell.fill"
            }
        }
    }

    @Test("clicking bell opens inbox surface")
    func clickingBellOpensInboxSurface() async {
        await withMainWindowControllerHarness { harness in
            let bellButton =
                findDescendant(
                    in: harness.window,
                    identifier: "inboxToolbarBell"
                ) as? NSButton

            bellButton?.performClick(nil)

            await eventually("inbox bell should switch sidebar surface") {
                harness.atoms.workspaceSidebarState.sidebarSurface == .inbox
            }
        }
    }

    @Test("bell unread badge tracks global roll-up alert count")
    func bellUnreadBadgeTracksRollUpAlertCount() async {
        let inboxAtom = InboxNotificationAtom()
        await withMainWindowControllerHarness(inboxAtom: inboxAtom) { harness in
            let badge = findDescendant(
                in: harness.window,
                identifier: "inboxToolbarUnreadBadge"
            )
            let oldDot = findDescendant(
                in: harness.window,
                identifier: "inboxToolbarBellDot"
            )

            #expect(badge != nil)
            #expect(oldDot == nil)
            #expect(badge?.isHidden == true)

            inboxAtom.append(makeRollUpAlertNotification())

            await eventually("inbox bell badge should become visible") {
                badge?.isHidden == false
            }
        }
    }

    @Test("bell unread badge text caps at ninety nine plus")
    func bellUnreadBadgeTextCapsAtNinetyNinePlus() {
        #expect(InboxToolbarUnreadBadgeText.text(for: 1) == "1")
        #expect(InboxToolbarUnreadBadgeText.text(for: 99) == "99")
        #expect(InboxToolbarUnreadBadgeText.text(for: 100) == "99+")
    }

    @Test("window frame changes update workspace-local memory without legacy defaults")
    func windowFrameChangesUpdateWorkspaceLocalMemoryWithoutLegacyDefaults() async {
        let legacyWindowFrameKey = "windowFrame"
        UserDefaults.standard.removeObject(forKey: legacyWindowFrameKey)
        defer { UserDefaults.standard.removeObject(forKey: legacyWindowFrameKey) }

        await withMainWindowControllerHarness { harness in
            let frame = NSRect(x: 40, y: 60, width: 900, height: 650)
            harness.window.setFrame(frame, display: false)
            harness.atoms.workspaceWindowMemory.setWindowFrame(nil)
            UserDefaults.standard.removeObject(forKey: legacyWindowFrameKey)

            harness.controller.windowDidMove(
                Notification(name: NSWindow.didMoveNotification, object: harness.window)
            )

            #expect(harness.atoms.workspaceWindowMemory.windowFrame == frame)
            #expect(UserDefaults.standard.object(forKey: legacyWindowFrameKey) == nil)
        }
    }

    @Test("bell badge sits in the bell icon top trailing corner")
    func bellBadgeSitsInBellIconTopTrailingCorner() async throws {
        let inboxAtom = InboxNotificationAtom()
        try await withMainWindowControllerHarness(inboxAtom: inboxAtom) { harness in
            let bellButton = try #require(
                findDescendant(
                    in: harness.window,
                    identifier: "inboxToolbarBell"
                ) as? NSButton
            )
            let badge = try #require(
                findDescendant(
                    in: harness.window,
                    identifier: "inboxToolbarUnreadBadge"
                )
            )
            let badgeAnchor = try #require(
                findDescendant(
                    in: harness.window,
                    identifier: "inboxToolbarBadgeAnchor"
                )
            )

            inboxAtom.append(makeRollUpAlertNotification())

            await eventually("inbox bell badge should become visible") {
                badge.isHidden == false
            }

            let badgeFrame = badge.convert(badge.bounds, to: badgeAnchor)
            let anchorFrame = badgeAnchor.convert(badgeAnchor.bounds, to: bellButton)

            #expect(anchorFrame.width == AppStyles.Shell.Sidebar.badgeHitboxSize)
            #expect(anchorFrame.height == AppStyles.Shell.Sidebar.badgeHitboxSize)
            #expect(badgeFrame.midX > badgeAnchor.bounds.midX)
            #expect(badgeFrame.midY > badgeAnchor.bounds.midY)
            #expect(badgeFrame.minX >= badgeAnchor.bounds.midX - 2)
            #expect(badgeFrame.maxY <= badgeAnchor.bounds.maxY + AppStyles.Shell.Sidebar.badgeOffset + 8)
        }
    }

    private func makeRollUpAlertNotification() -> InboxNotification {
        InboxNotification(
            id: UUID(),
            timestamp: Date(timeIntervalSince1970: 100),
            kind: .approvalRequested,
            title: "Approval requested",
            body: nil,
            source: .global,
            isRead: false,
            isDismissedFromPaneInbox: false
        )
    }
}

@MainActor
private struct MainWindowControllerHarness {
    let atoms: AtomRegistry
    let store: WorkspaceStore
    let coordinator: WorkspaceSurfaceCoordinator
    let controller: MainWindowController
    let window: NSWindow
    let tempDir: URL
}

@MainActor
private func withMainWindowControllerHarness<T>(
    inboxAtom: InboxNotificationAtom = InboxNotificationAtom(),
    inboxPrefsAtom: InboxNotificationPrefsAtom = InboxNotificationPrefsAtom(),
    paneInboxPresenter: PaneInboxNotificationPresenter = PaneInboxNotificationPresenter(),
    body: @MainActor (MainWindowControllerHarness) async throws -> T
) async rethrows -> T {
    let tempDir = FileManager.default.temporaryDirectory
        .appending(path: "main-window-controller-tests-\(UUID().uuidString)")
    let persistor = WorkspacePersistor(workspacesDir: tempDir)
    let atoms = AtomRegistry()
    let store = WorkspaceStore(
        identityAtom: atoms.workspaceIdentity,
        windowMemoryAtom: atoms.workspaceWindowMemory,
        repositoryTopologyAtom: atoms.workspaceRepositoryTopology,
        paneAtom: atoms.workspacePane,
        tabLayoutAtom: atoms.workspaceTabLayout,
        mutationCoordinator: atoms.workspaceMutationCoordinator,
        persistor: persistor
    )
    store.restore()

    let viewRegistry = ViewRegistry()
    let runtime = SessionRuntime(atom: atoms.sessionRuntime, store: store)
    let coordinator = WorkspaceSurfaceCoordinator(
        store: store,
        viewRegistry: viewRegistry,
        runtime: runtime,
        surfaceManager: InboxToolbarTestSurfaceManager(),
        runtimeRegistry: RuntimeRegistry(),
        windowLifecycleStore: atoms.windowLifecycle
    )
    let workspaceActionExecutor = WorkspaceActionExecutor(coordinator: coordinator, store: store)
    let appLifecycleStore = AppLifecycleAtom()
    let applicationLifecycleMonitor = ApplicationLifecycleMonitor(
        appLifecycleStore: appLifecycleStore,
        windowLifecycleStore: atoms.windowLifecycle
    )
    let tabBarAdapter = TabBarAdapter(store: store, repoCache: atoms.repoCache)

    var controller: MainWindowController?
    let result = try await AtomScope.$override.withValue(atoms) {
        let windowController = MainWindowController(
            store: store,
            workspaceActionExecutor: workspaceActionExecutor,
            runtimeCommandDispatcher: coordinator,
            applicationLifecycleMonitor: applicationLifecycleMonitor,
            appLifecycleStore: appLifecycleStore,
            tabBarAdapter: tabBarAdapter,
            viewRegistry: viewRegistry,
            inboxAtom: inboxAtom,
            inboxPrefsAtom: inboxPrefsAtom,
            inboxSidebarState: InboxSidebarState(),
            paneInboxPresenter: paneInboxPresenter
        )
        controller = windowController
        windowController.showWindow(nil)

        let harness = MainWindowControllerHarness(
            atoms: atoms,
            store: store,
            coordinator: coordinator,
            controller: windowController,
            window: windowController.window!,
            tempDir: tempDir
        )

        return try await body(harness)
    }

    (controller?.window?.contentViewController as? MainSplitViewController)?.shutdown()
    controller?.close()
    await coordinator.shutdown()
    try? FileManager.default.removeItem(at: tempDir)
    return result
}

@MainActor
private func findDescendant(in window: NSWindow, identifier: String) -> NSView? {
    for accessory in window.titlebarAccessoryViewControllers {
        if let match = findDescendant(in: accessory.view, identifier: identifier) {
            return match
        }
    }
    return window.contentView.flatMap { findDescendant(in: $0, identifier: identifier) }
}

@MainActor
private func findDescendant(in view: NSView, identifier: String) -> NSView? {
    if view.identifier?.rawValue == identifier {
        return view
    }
    for subview in view.subviews {
        if let match = findDescendant(in: subview, identifier: identifier) {
            return match
        }
    }
    return nil
}

private final class InboxToolbarTestSurfaceManager: WorkspaceSurfaceManaging {
    private let cwdStream: AsyncStream<SurfaceManager.SurfaceCWDChangeEvent>

    init() {
        self.cwdStream = AsyncStream<SurfaceManager.SurfaceCWDChangeEvent> { continuation in
            continuation.finish()
        }
    }

    var surfaceCWDChanges: AsyncStream<SurfaceManager.SurfaceCWDChangeEvent> { cwdStream }

    func syncFocus(activeSurfaceId: UUID?) {}

    func createSurface(
        config: Ghostty.SurfaceConfiguration,
        metadata: SurfaceMetadata
    ) -> Result<ManagedSurface, SurfaceError> {
        .failure(.ghosttyNotInitialized)
    }

    @discardableResult
    func attach(_ surfaceId: UUID, to paneId: UUID) -> Ghostty.SurfaceView? {
        nil
    }

    func detach(_ surfaceId: UUID, reason: SurfaceDetachReason) {}

    func undoClose() -> ManagedSurface? { nil }

    func requeueUndo(_ surfaceId: UUID) {}

    func destroy(_ surfaceId: UUID) {}
}

@MainActor
private final class TitlebarActionCommandHandlerProbe: WorkspaceCommandHandling {
    var executedCommands: [AppCommand] = []

    func execute(_ command: AppCommand) {
        executedCommands.append(command)
    }

    func execute(_ command: AppCommand, target _: UUID, targetType _: SearchItemType) {
        executedCommands.append(command)
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
private final class TitlebarActionAppRouterProbe: ShellCommandHandling {
    let appCommands: Set<AppCommand>
    var handledCommands: [AppCommand] = []

    init(appCommands: Set<AppCommand>) {
        self.appCommands = appCommands
    }

    func canExecute(_ command: AppCommand) -> Bool {
        appCommands.contains(command)
    }

    func canExecute(_ command: AppCommand, target _: UUID, targetType _: SearchItemType) -> Bool {
        canExecute(command)
    }

    func execute(_ command: AppCommand) -> Bool {
        guard appCommands.contains(command) else { return false }
        handledCommands.append(command)
        return true
    }

    func execute(_ command: AppCommand, target _: UUID, targetType _: SearchItemType) -> Bool {
        execute(command)
    }

    func showRepoCommandBar() {}

    func refreshWorktrees() {}

    func refocusActivePane() {}
}
