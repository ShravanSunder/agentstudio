import AppKit
import Foundation
import Testing

@testable import AgentStudio
@testable import AgentStudioCore
@testable import AgentStudioInboxNotification
@testable import AgentStudioInfrastructure
@testable import AgentStudioTestSupport

@MainActor
@Suite
struct DraggableTabBarWindowDragTests {
    private static let doubleClickActionDefaultsKey = "AppleActionOnDoubleClick"

    init() {
        installTestCoreAtomsIfNeeded()
    }

    @Test("tab host does not rely on AppKit mouseDown window-drag inference")
    func tabHostDoesNotRelyOnMouseDownWindowDragInference() throws {
        let source = try sourceContents("Sources/AgentStudio/App/Panes/TabBar/DraggableTabBarHostingView.swift")

        #expect(
            !source.contains("mouseDownCanMoveWindow"),
            "Tab host must not patch child hit views with mouseDownCanMoveWindow. Disable native window movement at the NSWindow boundary instead."
        )
    }

    @Test("main window allows native movement so performDrag can move it")
    func mainWindowAllowsNativeMovementButNotBackgroundDrag() throws {
        let source = try sourceContents("Sources/AgentStudio/App/Windows/MainWindowController.swift")

        #expect(source.contains("window.isMovable = true"))
        #expect(source.contains("window.isMovableByWindowBackground = false"))
    }

    @Test("toolbar chrome no longer hosts a separate drag region overlay")
    func toolbarChromeNoLongerHostsSeparateDragRegionOverlay() throws {
        let source = try sourceContents("Sources/AgentStudio/App/Windows/MainToolbarChromeView.swift")

        #expect(!source.contains("ShellChromeDragRegionView"))
        #expect(!source.contains("windowDragRegionHeight"))
    }

    @Test("tab host owns mouse down window-drag handling directly")
    func tabHostOwnsMouseDownWindowDragHandlingDirectly() throws {
        let source = try sourceContents("Sources/AgentStudio/App/Panes/TabBar/DraggableTabBarHostingView.swift")

        #expect(source.contains("override func mouseDown(with event: NSEvent)"))
        #expect(source.contains("tabAtPoint(location)"))
        #expect(source.contains("AppleActionOnDoubleClick"))
    }

    @Test("a click inside a tab pill frame does not start a window drag")
    func clickInsidePillFrameDoesNotStartWindowDrag() throws {
        let fixture = makeHostingViewFixture()
        var didDrag = false
        fixture.hostingView.performWindowDrag = { _ in didDrag = true }

        let event = try makeMouseDownEvent(
            atNSViewPoint: fixture.pointInsidePill, clickCount: 1, windowNumber: fixture.window.windowNumber
        )
        fixture.hostingView.mouseDown(with: event)

        #expect(!didDrag)
    }

    @Test("a click in the empty strip starts a window drag")
    func clickInEmptyStripStartsWindowDrag() throws {
        let fixture = makeHostingViewFixture()
        var draggedEvent: NSEvent?
        fixture.hostingView.performWindowDrag = { draggedEvent = $0 }

        let event = try makeMouseDownEvent(
            atNSViewPoint: fixture.pointOutsidePill, clickCount: 1, windowNumber: fixture.window.windowNumber
        )
        fixture.hostingView.mouseDown(with: event)

        #expect(draggedEvent === event)
    }

    @Test("a double click in the empty strip zooms when the system pref is Maximize")
    func doubleClickInEmptyStripZoomsWhenSystemPrefIsMaximize() throws {
        UserDefaults.standard.set("Maximize", forKey: Self.doubleClickActionDefaultsKey)
        defer { UserDefaults.standard.removeObject(forKey: Self.doubleClickActionDefaultsKey) }

        let fixture = makeHostingViewFixture()
        var didZoom = false
        var didDrag = false
        fixture.hostingView.performWindowZoom = { didZoom = true }
        fixture.hostingView.performWindowDrag = { _ in didDrag = true }

        let event = try makeMouseDownEvent(
            atNSViewPoint: fixture.pointOutsidePill, clickCount: 2, windowNumber: fixture.window.windowNumber
        )
        fixture.hostingView.mouseDown(with: event)

        #expect(didZoom)
        #expect(!didDrag)
    }

    @Test("a double click in the empty strip minimizes when the system pref is Minimize")
    func doubleClickInEmptyStripMinimizesWhenSystemPrefIsMinimize() throws {
        UserDefaults.standard.set("Minimize", forKey: Self.doubleClickActionDefaultsKey)
        defer { UserDefaults.standard.removeObject(forKey: Self.doubleClickActionDefaultsKey) }

        let fixture = makeHostingViewFixture()
        var didMiniaturize = false
        fixture.hostingView.performWindowMiniaturize = { didMiniaturize = true }

        let event = try makeMouseDownEvent(
            atNSViewPoint: fixture.pointOutsidePill, clickCount: 2, windowNumber: fixture.window.windowNumber
        )
        fixture.hostingView.mouseDown(with: event)

        #expect(didMiniaturize)
    }

    @Test("a double click in the empty strip does nothing when the system pref is some other value")
    func doubleClickInEmptyStripDoesNothingWhenSystemPrefIsSomeOtherValue() throws {
        // Setting an explicit non-matching value (rather than removeObject) keeps this
        // deterministic: UserDefaults.standard falls through to NSGlobalDomain, and this
        // machine's real "double-click title bar" system preference could otherwise leak
        // in as "Maximize" once the app-level override is merely removed.
        UserDefaults.standard.set("None", forKey: Self.doubleClickActionDefaultsKey)
        defer { UserDefaults.standard.removeObject(forKey: Self.doubleClickActionDefaultsKey) }

        let fixture = makeHostingViewFixture()
        var didZoom = false
        var didMiniaturize = false
        var didDrag = false
        fixture.hostingView.performWindowZoom = { didZoom = true }
        fixture.hostingView.performWindowMiniaturize = { didMiniaturize = true }
        fixture.hostingView.performWindowDrag = { _ in didDrag = true }

        let event = try makeMouseDownEvent(
            atNSViewPoint: fixture.pointOutsidePill, clickCount: 2, windowNumber: fixture.window.windowNumber
        )
        fixture.hostingView.mouseDown(with: event)

        #expect(!didZoom)
        #expect(!didMiniaturize)
        #expect(!didDrag)
    }

    @MainActor
    @Test("main split no longer owns a content chrome row")
    func mainSplitNoLongerOwnsContentChromeRow() throws {
        let source = try sourceContents("Sources/AgentStudio/App/Windows/MainSplitViewController.swift")

        #expect(!source.contains("shellChromeContainerView"))
        #expect(!source.contains("installShellChrome"))
        #expect(source.contains("makeToolbarChromeView"))
    }

    // MARK: - Fixture

    private struct HostingViewFixture {
        let hostingView: DraggableTabBarHostingView
        let window: NSWindow
        let pointInsidePill: NSPoint
        let pointOutsidePill: NSPoint
    }

    /// Builds a `DraggableTabBarHostingView` hosted as the content view of a real,
    /// never-ordered-front borderless window, with one tab-pill frame seeded directly
    /// via `updateTabFrames` (bypassing SwiftUI layout entirely). `mouseDown` converts
    /// `event.locationInWindow` through `convert(_:from:)`, which needs a real window
    /// to resolve correctly; a borderless window sized to the view's bounds keeps
    /// window-base coordinates identical to the view's own local coordinates.
    /// `tabAtPoint` then flips NSView-space points (bottom-left origin) into the
    /// SwiftUI-space frame stored in `tabFrames` (top-left origin), so the two probe
    /// points below are chosen to land inside and outside the seeded pill frame after
    /// that flip.
    private func makeHostingViewFixture() -> HostingViewFixture {
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
        let tabBar = CustomTabBar(
            adapter: adapter,
            onSelect: { _ in },
            canDispatchCommand: { _, _ in true },
            onCommand: { _, _ in },
            onShowArrangements: { _ in }
        )
        let hostingView = DraggableTabBarHostingView(rootView: tabBar)
        let boundsHeight: CGFloat = AppStyles.Shell.TabBar.height
        let bounds = NSRect(x: 0, y: 0, width: 400, height: boundsHeight)
        hostingView.frame = bounds

        let window = NSWindow(
            contentRect: bounds,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView

        let pillFrame = CGRect(x: 20, y: 4, width: 100, height: AppStyles.Shell.TabBar.tabPillHeight)
        hostingView.updateTabFrames([UUID(): pillFrame])

        return HostingViewFixture(
            hostingView: hostingView,
            window: window,
            pointInsidePill: NSPoint(x: 50, y: boundsHeight - 20),
            pointOutsidePill: NSPoint(x: 300, y: boundsHeight - 20)
        )
    }

    private func makeMouseDownEvent(
        atNSViewPoint point: NSPoint,
        clickCount: Int,
        windowNumber: Int
    ) throws -> NSEvent {
        try #require(
            NSEvent.mouseEvent(
                with: .leftMouseDown,
                location: point,
                modifierFlags: [],
                timestamp: 1,
                windowNumber: windowNumber,
                context: nil,
                eventNumber: 10,
                clickCount: clickCount,
                pressure: 1
            )
        )
    }

    private func sourceContents(_ relativePath: String) throws -> String {
        let projectRoot = URL(fileURLWithPath: TestPathResolver.projectRoot(from: #filePath))
        return try String(contentsOf: projectRoot.appending(path: relativePath), encoding: .utf8)
    }
}
