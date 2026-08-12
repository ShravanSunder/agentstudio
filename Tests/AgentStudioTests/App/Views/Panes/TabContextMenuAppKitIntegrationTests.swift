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

    @Test("tab context-menu routing preserves toolbar interactions")
    func tabContextMenuRoutingPreservesToolbarInteractions() async throws {
        let fixture = try await makeMountedFixture()
        defer { fixture.tearDown() }

        try await assertRenameContextMenuPresentation(
            fixture: fixture,
            clickType: .rightMouseDown,
            modifierFlags: [],
            target: .active
        )
        fixture.menuPresentationSpy.reset()
        fixture.commandInvocationSpy.reset()

        try await assertRenameContextMenuPresentation(
            fixture: fixture,
            clickType: .rightMouseDown,
            modifierFlags: [],
            target: .inactive
        )
        fixture.menuPresentationSpy.reset()
        fixture.commandInvocationSpy.reset()

        try await assertRenameContextMenuPresentation(
            fixture: fixture,
            clickType: .leftMouseDown,
            modifierFlags: [.control],
            target: .active
        )
        fixture.menuPresentationSpy.reset()
        fixture.commandInvocationSpy.reset()

        try assertSecondaryClickOutsideTabPillsIsForwarded(fixture: fixture)
        fixture.menuPresentationSpy.reset()

        try assertOrdinaryPrimaryClickOnTabIsForwarded(fixture: fixture)
        fixture.menuPresentationSpy.reset()

        try assertSecondaryClickFromDifferentWindowIsForwarded(fixture: fixture)
    }

    private func assertSecondaryClickOutsideTabPillsIsForwarded(fixture: Fixture) throws {
        let event = try fixture.makeMouseEventOutsideTabPills(type: .rightMouseDown)

        let forwardedEvent = fixture.hostingView.routeContextMenuEvent(event)

        #expect(forwardedEvent === event)
        #expect(fixture.menuPresentationSpy.presentations.isEmpty)
    }

    private func assertOrdinaryPrimaryClickOnTabIsForwarded(fixture: Fixture) throws {
        let event = try fixture.makeMouseEvent(
            type: .leftMouseDown,
            target: .active
        )

        let forwardedEvent = fixture.hostingView.routeContextMenuEvent(event)

        #expect(forwardedEvent === event)
        #expect(fixture.menuPresentationSpy.presentations.isEmpty)
    }

    private func assertSecondaryClickFromDifferentWindowIsForwarded(fixture: Fixture) throws {
        let otherWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        defer { otherWindow.close() }
        let event = try Self.makeMouseEvent(
            type: .rightMouseDown,
            modifierFlags: [],
            pointInWindow: NSPoint(x: 50, y: 50),
            window: otherWindow
        )

        let forwardedEvent = fixture.hostingView.routeContextMenuEvent(event)

        #expect(forwardedEvent === event)
        #expect(fixture.menuPresentationSpy.presentations.isEmpty)
    }

    private enum TargetTab {
        case active
        case inactive
    }

    private func assertRenameContextMenuPresentation(
        fixture: Fixture,
        clickType: NSEvent.EventType,
        modifierFlags: NSEvent.ModifierFlags,
        target: TargetTab
    ) async throws {
        let event = try fixture.makeMouseEvent(
            type: clickType,
            modifierFlags: modifierFlags,
            target: target
        )

        let forwardedEvent = fixture.hostingView.routeContextMenuEvent(event)

        #expect(forwardedEvent == nil)
        #expect(fixture.menuPresentationSpy.presentations.count == 1)
        let presentation = try #require(fixture.menuPresentationSpy.presentations.first)
        #expect(presentation.event === event)
        #expect(
            Self.allMenuTitles(in: presentation.menu).contains(
                AppCommand.renameTab.definition.label
            )
        )

        guard target == .inactive else {
            #expect(fixture.commandInvocationSpy.invocations.isEmpty)
            return
        }

        let renameMenuItem = try #require(
            Self.menuItem(
                titled: AppCommand.renameTab.definition.label,
                in: presentation.menu
            )
        )
        let renameAction = try #require(renameMenuItem.action)

        let actionWasSent = NSApp.sendAction(
            renameAction,
            to: renameMenuItem.target,
            from: renameMenuItem
        )

        #expect(actionWasSent)
        await eventually("inactive tab rename menu item should dispatch its targeted command") {
            fixture.commandInvocationSpy.invocations.count == 1
        }
        let invocation = try #require(fixture.commandInvocationSpy.invocations.first)
        #expect(invocation.command == .renameTab)
        #expect(invocation.targetTabId == fixture.inactiveTabId)
    }

    @MainActor
    private struct Fixture {
        let window: NSWindow
        let hostingView: DraggableTabBarHostingView
        let adapter: TabBarAdapter
        let activeTabId: UUID
        let inactiveTabId: UUID
        let toolbarDelegate: ToolbarDelegate
        let menuPresentationSpy: MenuPresentationSpy
        let commandInvocationSpy: CommandInvocationSpy

        func makeMouseEvent(
            type: NSEvent.EventType,
            modifierFlags: NSEvent.ModifierFlags = [],
            target: TargetTab
        ) throws -> NSEvent {
            let targetTabId =
                switch target {
                case .active: activeTabId
                case .inactive: inactiveTabId
                }
            let pillFrame = try #require(hostingView.tabFrameInView(for: targetTabId))
            return try makeMouseEvent(
                type: type,
                modifierFlags: modifierFlags,
                pointInHostingView: NSPoint(x: pillFrame.midX, y: pillFrame.midY)
            )
        }

        func makeMouseEvent(
            type: NSEvent.EventType,
            modifierFlags: NSEvent.ModifierFlags = [],
            pointInHostingView: NSPoint
        ) throws -> NSEvent {
            try TabContextMenuAppKitIntegrationTests.makeMouseEvent(
                type: type,
                modifierFlags: modifierFlags,
                pointInWindow: hostingView.convert(pointInHostingView, to: nil),
                window: window
            )
        }

        func makeMouseEventOutsideTabPills(type: NSEvent.EventType) throws -> NSEvent {
            let tabFrames = try [
                #require(hostingView.tabFrameInView(for: activeTabId)),
                #require(hostingView.tabFrameInView(for: inactiveTabId)),
            ]
            let hostingBounds = hostingView.bounds.insetBy(dx: 1, dy: 1)
            let candidatePoints = [
                NSPoint(x: hostingBounds.minX, y: hostingBounds.minY),
                NSPoint(x: hostingBounds.midX, y: hostingBounds.minY),
                NSPoint(x: hostingBounds.maxX, y: hostingBounds.minY),
                NSPoint(x: hostingBounds.minX, y: hostingBounds.maxY),
                NSPoint(x: hostingBounds.midX, y: hostingBounds.maxY),
                NSPoint(x: hostingBounds.maxX, y: hostingBounds.maxY),
            ]
            let pointOutsideTabPills = try #require(
                candidatePoints.first { point in
                    !tabFrames.contains { $0.contains(point) }
                }
            )
            return try makeMouseEvent(type: type, pointInHostingView: pointOutsideTabPills)
        }

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

    private final class MenuPresentationSpy {
        struct Presentation {
            let menu: NSMenu
            let event: NSEvent
        }

        private(set) var presentations: [Presentation] = []

        func present(menu: NSMenu, event: NSEvent, view: NSView) {
            presentations.append(Presentation(menu: menu, event: event))
        }

        func reset() {
            presentations.removeAll(keepingCapacity: true)
        }
    }

    private final class CommandInvocationSpy {
        struct Invocation {
            let command: AppCommand
            let targetTabId: UUID
        }

        private(set) var invocations: [Invocation] = []

        func record(command: AppCommand, targetTabId: UUID) {
            invocations.append(Invocation(command: command, targetTabId: targetTabId))
        }

        func reset() {
            invocations.removeAll(keepingCapacity: true)
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

    private func makeMountedFixture() async throws -> Fixture {
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

        let commandInvocationSpy = CommandInvocationSpy()
        let tabBar = CustomTabBar(
            adapter: adapter,
            onSelect: { _ in },
            canDispatchCommand: { _, _ in true },
            onCommand: commandInvocationSpy.record,
            onShowArrangements: { _ in }
        )
        let hostingView = DraggableTabBarHostingView(rootView: tabBar)
        hostingView.configure(adapter: adapter, onReorder: { _, _ in })
        let menuPresentationSpy = MenuPresentationSpy()
        hostingView.presentResolvedContextMenu = menuPresentationSpy.present
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

        window.makeKeyAndOrderFront(nil)
        window.contentView?.layoutSubtreeIfNeeded()
        await eventually("seeded tab pills should mount and report their frames") {
            window.contentView?.layoutSubtreeIfNeeded()
            window.displayIfNeeded()
            return adapter.tabs.count == 2
                && adapter.tabFrames[activeTab.id] != nil
                && adapter.tabFrames[inactiveTab.id] != nil
        }

        return Fixture(
            window: window,
            hostingView: hostingView,
            adapter: adapter,
            activeTabId: activeTab.id,
            inactiveTabId: inactiveTab.id,
            toolbarDelegate: toolbarDelegate,
            menuPresentationSpy: menuPresentationSpy,
            commandInvocationSpy: commandInvocationSpy
        )
    }

    private static func makeMouseEvent(
        type: NSEvent.EventType,
        modifierFlags: NSEvent.ModifierFlags,
        pointInWindow: NSPoint,
        window: NSWindow
    ) throws -> NSEvent {
        try #require(
            NSEvent.mouseEvent(
                with: type,
                location: pointInWindow,
                modifierFlags: modifierFlags,
                timestamp: 1,
                windowNumber: window.windowNumber,
                context: nil,
                eventNumber: 1,
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

    private static func menuItem(titled title: String, in menu: NSMenu) -> NSMenuItem? {
        for item in menu.items {
            if item.title == title {
                return item
            }
            if let submenu = item.submenu,
                let matchingItem = menuItem(titled: title, in: submenu)
            {
                return matchingItem
            }
        }
        return nil
    }
}
