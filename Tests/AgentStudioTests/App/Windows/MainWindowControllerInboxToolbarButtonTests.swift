import AppKit
import Foundation
import GhosttyKit
import Testing

@testable import AgentStudio
@testable import AgentStudioCore
@testable import AgentStudioInboxNotification
@testable import AgentStudioTerminal
@testable import AgentStudioTestSupport

@MainActor
@Suite("Top chrome sidebar controls", .serialized)
struct MainWindowControllerInboxToolbarButtonTests {
    init() {
        installTestCoreAtomsIfNeeded()
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

    @Test("top chrome inbox badge reads the injected global roll-up count")
    func topChromeInboxBadgeReadsInjectedGlobalRollUpCount() throws {
        let source = try sourceFile("Sources/AgentStudio/App/Panes/TabBar/ShellTabBarControls.swift")

        #expect(source.contains("let inboxAtom: InboxNotificationAtom"))
        #expect(source.contains("badgeCount: inboxAtom.globalRollUpAlertCount"))
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
