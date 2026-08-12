import AppKit
import Foundation
import Testing

@testable import AgentStudio
@testable import AgentStudioCore
@testable import AgentStudioInboxNotification
@testable import AgentStudioInfrastructure
@testable import AgentStudioTestSupport

@MainActor
@Suite("Tab context menu AppKit integration", .serialized)
struct TabContextMenuAppKitIntegrationTests {
    init() {
        installTestCoreAtomsIfNeeded()
    }

    @Test("secondary click on a tab pill begins tracking the Rename context menu")
    func secondaryClickOnTabPillBeginsTrackingRenameContextMenu() async throws {
        try await assertRenameContextMenuTracks(
            clickType: .rightMouseDown,
            modifierFlags: [],
            target: .active
        )
    }

    @Test("secondary click on an inactive tab pill begins tracking the Rename context menu")
    func secondaryClickOnInactiveTabPillBeginsTrackingRenameContextMenu() async throws {
        try await assertRenameContextMenuTracks(
            clickType: .rightMouseDown,
            modifierFlags: [],
            target: .inactive
        )
    }

    @Test("control-click on a tab pill begins tracking the Rename context menu")
    func controlClickOnTabPillBeginsTrackingRenameContextMenu() async throws {
        try await assertRenameContextMenuTracks(
            clickType: .leftMouseDown,
            modifierFlags: [.control],
            target: .active
        )
    }

    private enum TargetTab {
        case active
        case inactive
    }

    private func assertRenameContextMenuTracks(
        clickType: NSEvent.EventType,
        modifierFlags: NSEvent.ModifierFlags,
        target: TargetTab
    ) async throws {
        let fixture = try makeFixture()
        do {
            fixture.window.makeKeyAndOrderFront(nil)
            fixture.window.contentView?.layoutSubtreeIfNeeded()

            await eventually("seeded tab projection should mount") {
                fixture.window.contentView?.layoutSubtreeIfNeeded()
                return fixture.adapter.tabs.count == 2
            }

            fixture.hostingView.updateTabFrames([
                fixture.activeTabId: CGRect(
                    x: 10,
                    y: 4,
                    width: 100,
                    height: AppStyles.Shell.TabBar.tabPillHeight
                ),
                fixture.inactiveTabId: CGRect(
                    x: 120,
                    y: 4,
                    width: 100,
                    height: AppStyles.Shell.TabBar.tabPillHeight
                ),
            ])
            let targetTabId =
                switch target {
                case .active: fixture.activeTabId
                case .inactive: fixture.inactiveTabId
                }
            let pillFrame = try #require(fixture.hostingView.tabFrameInView(for: targetTabId))
            let pointInWindow = fixture.hostingView.convert(
                NSPoint(x: pillFrame.midX, y: pillFrame.midY),
                to: nil
            )
            let trackedMenu = try await dispatchContextClickAndCaptureTrackedMenu(
                type: clickType,
                modifierFlags: modifierFlags,
                pointInWindow: pointInWindow,
                window: fixture.window,
                hostingView: fixture.hostingView
            )

            #expect(trackedMenu != nil)
            #expect(
                Self.allMenuTitles(in: trackedMenu ?? NSMenu()).contains(
                    AppCommand.renameTab.definition.label
                )
            )
        } catch {
            fixture.tearDown()
            throw error
        }
        fixture.tearDown()
    }

    private struct Fixture {
        let window: NSWindow
        let hostingView: DraggableTabBarHostingView
        let adapter: TabBarAdapter
        let activeTabId: UUID
        let inactiveTabId: UUID
        let toolbarDelegate: ToolbarDelegate

        @MainActor
        func tearDown() {
            window.toolbar?.delegate = nil
            window.toolbar = nil
            hostingView.removeFromSuperview()
            window.contentView = nil
            window.orderOut(nil)
            window.close()
        }
    }

    private final class ToolbarDelegate: NSObject, NSToolbarDelegate {
        private static let tabBarItemIdentifier = NSToolbarItem.Identifier("test.workspaceTabs")
        private let chromeView: MainToolbarChromeView

        init(chromeView: MainToolbarChromeView) {
            self.chromeView = chromeView
        }

        func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
            [Self.tabBarItemIdentifier]
        }

        func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
            toolbarDefaultItemIdentifiers(toolbar)
        }

        func toolbar(
            _ toolbar: NSToolbar,
            itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
            willBeInsertedIntoToolbar flag: Bool
        ) -> NSToolbarItem? {
            guard itemIdentifier == Self.tabBarItemIdentifier else { return nil }
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.label = "Workspace Tabs"
            item.isBordered = false
            item.view = chromeView
            return item
        }
    }

    private final class MenuTrackingState {
        var trackedMenu: NSMenu?
    }

    private func makeFixture() throws -> Fixture {
        let atoms = makeTestAtomRegistry()
        let store = WorkspaceStore(
            identityAtom: atoms.core.workspaceIdentity,
            windowMemoryAtom: atoms.core.workspaceWindowMemory,
            repositoryTopologyAtom: atoms.core.workspaceRepositoryTopology,
            paneAtom: atoms.core.workspacePane,
            tabLayoutAtom: atoms.core.workspaceTabLayout,
            mutationCoordinator: atoms.core.workspaceMutationCoordinator
        )
        let adapter = TabBarAdapter(
            store: store,
            repoCache: atoms.core.repoCache,
            inboxAtom: InboxNotificationAtom()
        )
        let inactivePane = store.createPane()
        let inactiveTab = Tab(paneId: inactivePane.id, name: "Inactive Tab")
        store.appendTab(inactiveTab)
        let activePane = store.createPane()
        let activeTab = Tab(paneId: activePane.id, name: "Active Tab")
        store.appendTab(activeTab)

        let tabBar = CustomTabBar(
            adapter: adapter,
            onSelect: { _ in },
            canDispatchCommand: { _, _ in true },
            onCommand: { _, _ in },
            onShowArrangements: { _ in }
        )
        let hostingView = DraggableTabBarHostingView(rootView: tabBar)
        let chromeView = MainToolbarChromeView(tabBarHostingView: hostingView)
        let toolbarDelegate = ToolbarDelegate(chromeView: chromeView)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 300),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.contentView = NSView(frame: window.contentLayoutRect)
        let toolbar = NSToolbar(identifier: "TabContextMenuAppKitIntegrationTests")
        toolbar.delegate = toolbarDelegate
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        window.toolbar = toolbar
        window.toolbarStyle = .unifiedCompact

        return Fixture(
            window: window,
            hostingView: hostingView,
            adapter: adapter,
            activeTabId: activeTab.id,
            inactiveTabId: inactiveTab.id,
            toolbarDelegate: toolbarDelegate
        )
    }

    private func dispatchContextClickAndCaptureTrackedMenu(
        type: NSEvent.EventType,
        modifierFlags: NSEvent.ModifierFlags,
        pointInWindow: NSPoint,
        window: NSWindow,
        hostingView: DraggableTabBarHostingView
    ) async throws -> NSMenu? {
        let menuTrackingState = MenuTrackingState()
        let observationTask = Task { @MainActor in
            for await notification in NotificationCenter.default.notifications(
                named: NSMenu.didBeginTrackingNotification
            ) {
                menuTrackingState.trackedMenu = notification.object as? NSMenu
                return
            }
        }
        await Task.yield()

        let mouseUpType: NSEvent.EventType = type == .rightMouseDown ? .rightMouseUp : .leftMouseUp
        let mouseUpEventNumber = 2
        let mouseUp = try makeMouseEvent(
            type: mouseUpType,
            modifierFlags: modifierFlags,
            pointInWindow: pointInWindow,
            window: window,
            eventNumber: mouseUpEventNumber
        )
        NSApp.postEvent(mouseUp, atStart: false)

        do {
            let mouseDown = try makeMouseEvent(
                type: type,
                modifierFlags: modifierFlags,
                pointInWindow: pointInWindow,
                window: window,
                eventNumber: 1
            )
            let forwardedEvent = hostingView.routeContextMenuEvent(mouseDown)
            #expect(forwardedEvent == nil)

            await eventually("a context menu should begin tracking") {
                menuTrackingState.trackedMenu != nil
            }
        } catch {
            await cleanUpMenuTracking(
                menu: menuTrackingState.trackedMenu,
                observationTask: observationTask,
                mouseUpType: mouseUpType,
                mouseUpEventNumber: mouseUpEventNumber,
                windowNumber: window.windowNumber
            )
            throw error
        }

        await cleanUpMenuTracking(
            menu: menuTrackingState.trackedMenu,
            observationTask: observationTask,
            mouseUpType: mouseUpType,
            mouseUpEventNumber: mouseUpEventNumber,
            windowNumber: window.windowNumber
        )
        return menuTrackingState.trackedMenu
    }

    private func cleanUpMenuTracking(
        menu: NSMenu?,
        observationTask: Task<Void, Never>,
        mouseUpType: NSEvent.EventType,
        mouseUpEventNumber: Int,
        windowNumber: Int
    ) async {
        menu?.cancelTracking()
        observationTask.cancel()
        await observationTask.value
        removePostedMouseUpIfStillQueued(
            type: mouseUpType,
            eventNumber: mouseUpEventNumber,
            windowNumber: windowNumber
        )
    }

    private func removePostedMouseUpIfStillQueued(
        type: NSEvent.EventType,
        eventNumber: Int,
        windowNumber: Int
    ) {
        guard
            let queuedEvent = NSApp.nextEvent(
                matching: NSEvent.EventTypeMask(rawValue: 1 << type.rawValue),
                until: .distantPast,
                inMode: .default,
                dequeue: true
            )
        else { return }

        guard
            queuedEvent.eventNumber == eventNumber,
            queuedEvent.windowNumber == windowNumber
        else {
            NSApp.postEvent(queuedEvent, atStart: true)
            return
        }
    }

    private func makeMouseEvent(
        type: NSEvent.EventType,
        modifierFlags: NSEvent.ModifierFlags,
        pointInWindow: NSPoint,
        window: NSWindow,
        eventNumber: Int
    ) throws -> NSEvent {
        try #require(
            NSEvent.mouseEvent(
                with: type,
                location: pointInWindow,
                modifierFlags: modifierFlags,
                timestamp: 1,
                windowNumber: window.windowNumber,
                context: nil,
                eventNumber: eventNumber,
                clickCount: 1,
                pressure: 1
            )
        )
    }

    private static func allMenuTitles(in menu: NSMenu) -> [String] {
        menu.items.flatMap { item in
            [item.title] + (item.submenu.map(allMenuTitles) ?? [])
        }
    }
}
