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

            harness.atoms.uiState.setSidebarSurface(.inbox)

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
                harness.atoms.uiState.sidebarSurface == .inbox
            }
        }
    }

    @Test("bell unread badge tracks global unread count")
    func bellUnreadBadgeTracksUnreadCount() async {
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

            inboxAtom.append(makeUnreadNotification())

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

            inboxAtom.append(makeUnreadNotification())

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

    private func makeUnreadNotification() -> InboxNotification {
        InboxNotification(
            id: UUID(),
            timestamp: Date(timeIntervalSince1970: 100),
            kind: .agentRpc,
            title: "Agent finished",
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
    let coordinator: PaneCoordinator
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
        metadataAtom: atoms.workspaceMetadata,
        repositoryTopologyAtom: atoms.workspaceRepositoryTopology,
        paneAtom: atoms.workspacePane,
        tabLayoutAtom: atoms.workspaceTabLayout,
        mutationCoordinator: atoms.workspaceMutationCoordinator,
        persistor: persistor
    )
    store.restore()

    let viewRegistry = ViewRegistry()
    let runtime = SessionRuntime(atom: atoms.sessionRuntime, store: store)
    let coordinator = PaneCoordinator(
        store: store,
        viewRegistry: viewRegistry,
        runtime: runtime,
        surfaceManager: InboxToolbarTestSurfaceManager(),
        runtimeRegistry: RuntimeRegistry(),
        windowLifecycleStore: atoms.windowLifecycle
    )
    let actionExecutor = ActionExecutor(coordinator: coordinator, store: store)
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
            actionExecutor: actionExecutor,
            applicationLifecycleMonitor: applicationLifecycleMonitor,
            appLifecycleStore: appLifecycleStore,
            tabBarAdapter: tabBarAdapter,
            viewRegistry: viewRegistry,
            inboxAtom: inboxAtom,
            inboxPrefsAtom: inboxPrefsAtom,
            inboxSidebarStateAtom: InboxSidebarStateAtom(),
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

private final class InboxToolbarTestSurfaceManager: PaneCoordinatorSurfaceManaging {
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
