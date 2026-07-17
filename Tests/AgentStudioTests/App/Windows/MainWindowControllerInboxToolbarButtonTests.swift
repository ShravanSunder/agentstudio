import AppKit
import Foundation
import GhosttyKit
import Testing

@testable import AgentStudio

@MainActor
@Suite("Top chrome sidebar controls", .serialized)
struct MainWindowControllerInboxToolbarButtonTests {
    init() {
        installTestAtomRegistryIfNeeded()
    }

    @Test("main window delegates top chrome instead of installing native toolbar controls")
    func mainWindowDelegatesTopChromeInsteadOfInstallingNativeToolbarControls() throws {
        let source = try sourceFile("Sources/AgentStudio/App/Windows/MainWindowController.swift")

        #expect(source.contains("MainSplitViewController owns the shell-spanning top strip."))
        #expect(!source.contains("\n        setupToolbar()"))
        #expect(!source.contains("\n        setupTitlebarAccessory()"))
    }

    @Test("top chrome installs worktree and inbox sidebar buttons")
    func topChromeInstallsWorktreeAndInboxSidebarButtons() throws {
        let source = try sourceFile("Sources/AgentStudio/App/Panes/TabBar/ShellTabBarControls.swift")

        #expect(source.contains("struct SidebarSurfaceTabBarControls: View"))
        #expect(source.contains("command: .showWorktreeSidebar"))
        #expect(source.contains("symbolName: \"square.stack.3d.down.right\""))
        #expect(source.contains("selectedSymbolName: \"square.stack.3d.down.right.fill\""))
        #expect(source.contains("command: .showInboxNotifications"))
        #expect(source.contains("symbolName: \"bell\""))
        #expect(source.contains("selectedSymbolName: \"bell.fill\""))
    }

    @Test("top chrome sidebar buttons use command specs and dispatch through shared commands")
    func topChromeSidebarButtonsUseCommandSpecsAndDispatchThroughSharedCommands() throws {
        let source = try sourceFile("Sources/AgentStudio/App/Panes/TabBar/ShellTabBarControls.swift")

        #expect(source.contains("AppCommandDispatcher.shared.definition(for: command)"))
        #expect(source.contains("AppCommandDispatcher.shared.dispatch(command)"))
        #expect(source.contains(".help(commandDefinition.controlToolTip)"))
    }

    @Test("top chrome sidebar icons track open active surface")
    func topChromeSidebarIconsTrackOpenActiveSurface() throws {
        let source = try sourceFile("Sources/AgentStudio/App/Panes/TabBar/ShellTabBarControls.swift")

        #expect(source.contains("!sidebarState.sidebarCollapsed"))
        #expect(source.contains("isSelected: isSidebarOpen && sidebarState.sidebarSurface == .repos"))
        #expect(source.contains("isSelected: isSidebarOpen && sidebarState.sidebarSurface == .inbox"))
    }

    @Test("top chrome inbox badge reads global roll-up count")
    func topChromeInboxBadgeReadsGlobalRollUpCount() throws {
        let source = try sourceFile("Sources/AgentStudio/App/Panes/TabBar/ShellTabBarControls.swift")

        #expect(source.contains("badgeCount: atom(\\.inboxNotification).globalRollUpAlertCount"))
        #expect(source.contains("badgeText: badgeCount > 0 ? InboxToolbarUnreadBadgeText.text(for: badgeCount) : nil"))
    }

    @Test("watch folder uses the shared top chrome button")
    func watchFolderUsesSharedTopChromeButton() throws {
        let source = try sourceFile("Sources/AgentStudio/App/Panes/TabBar/ShellTabBarControls.swift")

        #expect(source.contains("struct WatchFolderTabBarMenu: View"))
        #expect(source.contains("AppCommandDispatcher.shared.definition(for: .watchFolder)"))
        #expect(source.contains("AppCommandDispatcher.shared.dispatch(.watchFolder)"))
        #expect(source.contains("symbolName: \"folder.badge.plus\""))
        #expect(source.contains("ChromeToolbarButtonLabel("))
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
    let atoms = makeInstalledTestAtomRegistry()
    let store = WorkspaceStore(
        identityAtom: atoms.workspaceIdentity,
        windowMemoryAtom: atoms.workspaceWindowMemory,
        repositoryTopologyAtom: atoms.workspaceRepositoryTopology,
        paneAtom: atoms.workspacePane,
        tabLayoutAtom: atoms.workspaceTabLayout,
        mutationCoordinator: atoms.workspaceMutationCoordinator)
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
