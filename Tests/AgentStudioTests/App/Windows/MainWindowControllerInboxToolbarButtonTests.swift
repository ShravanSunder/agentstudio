import AppKit
import Foundation
import GhosttyKit
import Testing

@testable import AgentStudio
@testable import AgentStudioCore
@testable import AgentStudioInboxNotification
@testable import AgentStudioInfrastructure
@testable import AgentStudioTerminal
@testable import AgentStudioTestSupport

@MainActor
@Suite("Top chrome sidebar controls", .serialized)
struct MainWindowControllerInboxToolbarButtonTests {
    init() {
        installTestCoreAtomsIfNeeded()
    }

    @Test("main window installs the native toolbar boundary for top chrome")
    func mainWindowInstallsNativeToolbarBoundary() throws {
        let source = try sourceFile("Sources/AgentStudio/App/Windows/MainWindowController.swift")

        #expect(source.contains("toolbarStyle = .unifiedCompact"))
        #expect(!source.contains("setupTitlebarAccessory"))
    }

    @Test("main window installs native fixed controls before the workspace tabs item")
    func mainWindowInstallsNativeFixedControlsBeforeWorkspaceTabsItem() async throws {
        try await withMainWindowControllerHarness { harness in
            let window = harness.window
            let toolbar = try #require(window.toolbar)
            #expect(toolbar.identifier == NSToolbar.Identifier("MainToolbar"))
            #expect(window.toolbarStyle == .unifiedCompact)

            let expectedItemIdentifiers = [
                "worktreeSidebar",
                "inboxSidebar",
                "watchFolder",
                "managementLayer",
                "arrangement",
                "workspaceTabs",
            ]
            #expect(toolbar.items.map(\.itemIdentifier.rawValue) == expectedItemIdentifiers)

            let expectedFixedControlViews = [
                "worktreeSidebar": "worktreeToolbarControl",
                "inboxSidebar": "inboxToolbarControl",
                "watchFolder": "watchFolderToolbarControl",
                "managementLayer": "managementLayerToolbarControl",
                "arrangement": "arrangementToolbarControl",
            ]
            for (itemIdentifier, viewIdentifier) in expectedFixedControlViews {
                let item = try #require(
                    toolbar.items.first(where: {
                        $0.itemIdentifier.rawValue == itemIdentifier
                    })
                )
                #expect(item.view?.identifier?.rawValue == viewIdentifier)
                #expect(!(item.view is MainToolbarChromeView))
            }

            let workspaceTabsItem = try #require(
                toolbar.items.first(where: {
                    $0.itemIdentifier.rawValue == "workspaceTabs"
                })
            )
            let workspaceTabsView = try #require(workspaceTabsItem.view)
            #expect(workspaceTabsView.identifier == NSUserInterfaceItemIdentifier("workspaceTabsToolbarControl"))
            #expect(workspaceTabsView is MainToolbarChromeView)
            #expect(window.standardWindowButton(.closeButton)?.isHidden == false)
            #expect(window.standardWindowButton(.miniaturizeButton)?.isHidden == false)
            #expect(window.standardWindowButton(.zoomButton)?.isHidden == false)
            #expect(window.collectionBehavior.contains(.fullScreenNone))
            #expect(window.collectionBehavior.contains(.fullScreenDisallowsTiling))

            let contentView = try #require(window.contentView)
            let rootView = try #require(window.contentViewController?.view)
            let splitView = try #require(findDescendant(in: rootView, ofType: ShellSplitView.self))
            splitView.layoutSubtreeIfNeeded()
            let splitRect = splitView.convert(splitView.bounds, to: contentView)
            let nonObscuredRect = contentView.convert(window.contentLayoutRect, from: nil)
            #expect(splitRect.minY >= nonObscuredRect.minY - 1)
            #expect(splitRect.maxY <= nonObscuredRect.maxY + 1)
            #expect(abs(splitRect.maxY - nonObscuredRect.maxY) < 1)
        }
    }

    @Test("workspace tabs keep overflow and new-tab controls but exclude fixed toolbar controls")
    func workspaceTabsKeepTabUtilitiesButExcludeFixedToolbarControls() throws {
        let tabBarSource = try sourceFile("Sources/AgentStudio/App/Panes/TabBar/CustomTabBar.swift")
        let layoutSource = try sourceFile("Sources/AgentStudio/App/Panes/TabBar/TabBarChromeLayoutPlan.swift")

        #expect(!tabBarSource.contains("leadingChromeControl"))
        #expect(!tabBarSource.contains("ToolbarButton.verticalOffset"))
        #expect(layoutSource.contains("var workspaceTabControls: [TabBarChromeControl]"))
        #expect(layoutSource.contains(".tabStrip"))
        #expect(layoutSource.contains(".overflowLeft"))
        #expect(layoutSource.contains(".overflowRight"))
        #expect(layoutSource.contains(".overflowMenu"))
        #expect(layoutSource.contains(".newTab"))
        #expect(!layoutSource.contains(".sidebarSurfaces"))
        #expect(!layoutSource.contains(".watchFolder"))
        #expect(!layoutSource.contains(".managementLayer"))
        #expect(!layoutSource.contains(".arrangement"))
    }

    @Test("top chrome sidebar buttons use command specs and dispatch through shared commands")
    func topChromeSidebarButtonsUseCommandSpecsAndDispatchThroughSharedCommands() throws {
        let source = try sourceFile("Sources/AgentStudio/App/Panes/TabBar/ShellTabBarControls.swift")

        #expect(source.contains("AppCommandDispatcher.shared.definition(for: command)"))
        #expect(source.contains("presentation.perform()"))
        #expect(source.contains(".disabled(!presentation.isEnabled)"))
        #expect(source.contains(".help(presentation.controlToolTip)"))
    }

    @Test("watch folder uses the shared top chrome button")
    func watchFolderUsesSharedTopChromeButton() throws {
        let source = try sourceFile("Sources/AgentStudio/App/Panes/TabBar/ShellTabBarControls.swift")

        #expect(source.contains("struct WatchFolderTabBarMenu: View"))
        #expect(source.contains("command: .watchFolder"))
        #expect(source.contains("presentation.perform()"))
        #expect(source.contains(".disabled(!presentation.isEnabled)"))
        #expect(source.contains("symbolName: \"folder.badge.plus\""))
        #expect(source.contains("ChromeToolbarButtonLabel("))
    }

    @Test("worktree sidebar presentation is filtered by app toolbar surface and command context")
    func worktreeSidebarPresentationIsFilteredByAppToolbarSurfaceAndCommandContext() {
        expectAppToolbarPresentationFiltering(for: .showWorktreeSidebar)
    }

    @Test("inbox presentation is filtered by app toolbar surface and command context")
    func inboxPresentationIsFilteredByAppToolbarSurfaceAndCommandContext() {
        expectAppToolbarPresentationFiltering(for: .showInboxNotifications)
    }

    @Test("watch folder presentation is filtered by app toolbar surface and command context")
    func watchFolderPresentationIsFilteredByAppToolbarSurfaceAndCommandContext() {
        expectAppToolbarPresentationFiltering(for: .watchFolder)
    }

    @Test("window frame changes update workspace-local memory without legacy defaults")
    func windowFrameChangesUpdateWorkspaceLocalMemoryWithoutLegacyDefaults() async {
        let legacyWindowFrameKey = "windowFrame"
        UserDefaults.standard.removeObject(forKey: legacyWindowFrameKey)
        defer { UserDefaults.standard.removeObject(forKey: legacyWindowFrameKey) }

        await withMainWindowControllerHarness { harness in
            let frame = NSRect(x: 40, y: 60, width: 900, height: 650)
            harness.window.setFrame(frame, display: false)
            harness.atoms.core.workspaceWindowMemory.setWindowFrame(nil)
            UserDefaults.standard.removeObject(forKey: legacyWindowFrameKey)

            harness.controller.windowDidMove(
                Notification(name: NSWindow.didMoveNotification, object: harness.window)
            )

            #expect(harness.atoms.core.workspaceWindowMemory.windowFrame == frame)
            #expect(UserDefaults.standard.object(forKey: legacyWindowFrameKey) == nil)
        }
    }

    @Test("badge overlay is anchored to the top trailing corner of shared chrome buttons")
    func badgeOverlayIsAnchoredToTopTrailingCornerOfSharedChromeButtons() throws {
        let source = try sourceFile("Sources/AgentStudio/SharedComponents/ChromeToolbarButtonLabel.swift")

        #expect(source.contains(".overlay(alignment: .topTrailing)"))
        #expect(source.contains("UnreadCountBadge(text: badgeText)"))
        #expect(source.contains("AppStyles.Shell.Chrome.ToolbarButton.badgeOffsetX"))
        #expect(source.contains("AppStyles.Shell.Chrome.ToolbarButton.badgeOffsetY"))
    }

    private func sourceFile(_ relativePath: String) throws -> String {
        let projectRoot = URL(fileURLWithPath: TestPathResolver.projectRoot(from: #filePath))
        return try String(contentsOf: projectRoot.appending(path: relativePath), encoding: .utf8)
    }

    private func expectAppToolbarPresentationFiltering(for command: AppCommand) {
        let definition = command.definition
        let emptyContext = CommandContext.empty
        let appToolbarPresentation = ShellTabBarCommandPresentation(
            definition: definition,
            surface: .toolbar(.app),
            commandContext: emptyContext
        )

        #expect(appToolbarPresentation?.command == command)
        #expect(appToolbarPresentation?.controlToolTip == definition.controlToolTip)

        let commandBarOnlyDefinition = AppCommandSpec(
            command: command,
            label: definition.label,
            icon: definition.icon,
            helpText: definition.helpText,
            surfacePolicy: .exposed([.commandBar]),
            targeting: .contextual
        )
        #expect(
            ShellTabBarCommandPresentation(
                definition: commandBarOnlyDefinition,
                surface: .toolbar(.app),
                commandContext: emptyContext
            ) == nil
        )

        let activeTabDefinition = AppCommandSpec(
            command: command,
            label: definition.label,
            icon: definition.icon,
            helpText: definition.helpText,
            surfacePolicy: .exposed([.toolbar(.app)]),
            targeting: .contextual,
            visibleWhen: [.hasActiveTab]
        )
        #expect(
            ShellTabBarCommandPresentation(
                definition: activeTabDefinition,
                surface: .toolbar(.app),
                commandContext: emptyContext
            ) == nil
        )
        #expect(
            ShellTabBarCommandPresentation(
                definition: activeTabDefinition,
                surface: .toolbar(.app),
                commandContext: CommandContext(satisfiedRequirements: [.hasActiveTab])
            )?.command == command
        )
    }

    @Test("app toolbar actions expose capability and recheck before dispatch")
    func appToolbarActionsRecheckCapabilityBeforeDispatch() throws {
        let dispatcher = RecordingAppToolbarCommandDispatcher()
        dispatcher.enabledCommands = [.newTab]
        let presentation = try #require(
            ShellTabBarCommandPresentation(
                definition: AppCommand.newTab.definition,
                surface: .toolbar(.app),
                commandContext: .empty,
                dispatcher: dispatcher
            )
        )

        #expect(presentation.isEnabled)
        #expect(dispatcher.capabilityQueries == [.newTab])

        dispatcher.enabledCommands = []
        presentation.perform()

        #expect(dispatcher.capabilityQueries == [.newTab, .newTab])
        #expect(dispatcher.dispatchedCommands.isEmpty)

        dispatcher.enabledCommands = [.newTab]
        presentation.perform()

        #expect(dispatcher.capabilityQueries == [.newTab, .newTab, .newTab])
        #expect(dispatcher.dispatchedCommands == [.newTab])
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
private final class RecordingAppToolbarCommandDispatcher: AppCommandDispatching {
    var enabledCommands: Set<AppCommand> = []
    private(set) var capabilityQueries: [AppCommand] = []
    private(set) var dispatchedCommands: [AppCommand] = []

    func dispatch(_ command: AppCommand) {
        dispatchedCommands.append(command)
    }

    func dispatch(_: AppCommand, target _: UUID, targetType _: SearchItemType) {}

    func canDispatch(_ command: AppCommand) -> Bool {
        capabilityQueries.append(command)
        return enabledCommands.contains(command)
    }

    func canDispatch(_: AppCommand, target _: UUID, targetType _: SearchItemType) -> Bool {
        false
    }

    func bridgePaneCommandTarget(worktreeId _: UUID) -> BridgePaneCommandTarget? {
        nil
    }

    func dispatchMovePaneToTab(
        sourcePaneId _: UUID,
        sourceTabId _: UUID?,
        targetTabId _: UUID
    ) {}
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
    let atoms = makeTestAtomRegistry()
    let store = WorkspaceStore(
        identityAtom: atoms.core.workspaceIdentity,
        windowMemoryAtom: atoms.core.workspaceWindowMemory,
        repositoryTopologyAtom: atoms.core.workspaceRepositoryTopology,
        paneAtom: atoms.core.workspacePane,
        tabLayoutAtom: atoms.core.workspaceTabLayout,
        mutationCoordinator: atoms.core.workspaceMutationCoordinator)
    let viewRegistry = ViewRegistry()
    let runtime = SessionRuntime(atom: atoms.core.sessionRuntime, store: store)
    let coordinator = WorkspaceSurfaceCoordinator(
        store: store,
        viewRegistry: viewRegistry,
        runtime: runtime,
        surfaceManager: InboxToolbarTestSurfaceManager(),
        runtimeRegistry: RuntimeRegistry(),
        windowLifecycleStore: atoms.core.windowLifecycle,
        bridgePaneAttendance: atoms.bridgePaneAttendance
    )
    let workspaceActionExecutor = WorkspaceActionExecutor(coordinator: coordinator, store: store)
    let appLifecycleStore = AppLifecycleAtom()
    let applicationLifecycleMonitor = ApplicationLifecycleMonitor(
        appLifecycleStore: appLifecycleStore,
        windowLifecycleStore: atoms.core.windowLifecycle
    )
    let tabBarAdapter = TabBarAdapter(store: store, repoCache: atoms.core.repoCache)

    var controller: MainWindowController?
    let result = try await withAsyncTestCoreAtoms(using: atoms.core) { _ in
        let windowController = MainWindowController(
            store: store,
            octiconLoader: makeTestOcticonLoader(),
            workspaceActionExecutor: workspaceActionExecutor,
            runtimeCommandDispatcher: coordinator,
            applicationLifecycleMonitor: applicationLifecycleMonitor,
            appLifecycleStore: appLifecycleStore,
            tabBarAdapter: tabBarAdapter,
            viewRegistry: viewRegistry,
            bridgePaneAttendance: atoms.bridgePaneAttendance,
            editorChooser: atoms.editorChooser,
            inboxAtom: inboxAtom,
            inboxPrefsAtom: inboxPrefsAtom,
            inboxSidebarState: InboxSidebarState(),
            paneInboxPresentationState: atoms.paneInboxPresentationState,
            repoExplorerSidebarPrefs: atoms.repoExplorerSidebarPrefs,
            bridgeAttendanceSnapshot: {
                atoms.bridgePaneAttendance.ordinalSnapshot()
            },
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

@MainActor
private func findDescendant<T: NSView>(in view: NSView, ofType type: T.Type) -> T? {
    if let match = view as? T {
        return match
    }
    for subview in view.subviews {
        if let match = findDescendant(in: subview, ofType: type) {
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
