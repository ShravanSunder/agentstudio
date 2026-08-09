import AppKit
import Foundation
import Testing

@testable import AgentStudio
@testable import AgentStudioCore
@testable import AgentStudioInfrastructure
@testable import AgentStudioTestSupport

@MainActor
@Suite
struct DraggableTabBarWindowDragTests {
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

    @Test("main window disables native titlebar and background movement")
    func mainWindowDisablesNativeWindowMovement() throws {
        let source = try sourceContents("Sources/AgentStudio/App/Windows/MainWindowController.swift")

        #expect(source.contains("window.isMovable = false"))
        #expect(source.contains("window.isMovableByWindowBackground = false"))
    }

    @Test("shell chrome owns an explicit app drag region")
    func shellChromeOwnsExplicitDragRegion() throws {
        let source = try sourceContents("Sources/AgentStudio/App/Windows/ShellChromeDragRegionView.swift")

        #expect(source.contains("final class ShellChromeDragRegionView: NSView"))
        #expect(source.contains("override func mouseDown(with event: NSEvent)"))
        #expect(source.contains("window?.performDrag(with: event)"))
    }

    @Test("drag region tracks the tab bar gap above bottom-aligned tab pills")
    func dragRegionTracksTabBarGapAboveBottomAlignedTabPills() {
        #expect(
            AppStyles.Shell.Chrome.windowDragRegionHeight
                == AppStyles.Shell.TabBar.height - AppStyles.Shell.TabBar.tabPillHeight
        )
    }

    @MainActor
    @Test("explicit drag region forwards mouse down to app-owned window drag")
    func explicitDragRegionForwardsMouseDownToAppOwnedWindowDrag() throws {
        let dragRegion = ShellChromeDragRegionView(
            frame: NSRect(
                x: 0,
                y: 0,
                width: 320,
                height: AppStyles.Shell.Chrome.windowDragRegionHeight
            )
        )
        let event = try #require(
            NSEvent.mouseEvent(
                with: .leftMouseDown,
                location: NSPoint(x: 12, y: 3),
                modifierFlags: [],
                timestamp: 1,
                windowNumber: 0,
                context: nil,
                eventNumber: 10,
                clickCount: 1,
                pressure: 1
            )
        )

        var capturedEvent: NSEvent?
        dragRegion.performWindowDrag = { capturedEvent = $0 }

        dragRegion.mouseDown(with: event)

        #expect(capturedEvent === event)
    }

    @MainActor
    @Test("explicit drag region zooms the window on double click")
    func explicitDragRegionZoomsWindowOnDoubleClick() throws {
        let dragRegion = ShellChromeDragRegionView(
            frame: NSRect(
                x: 0,
                y: 0,
                width: 320,
                height: AppStyles.Shell.Chrome.windowDragRegionHeight
            )
        )
        let event = try #require(
            NSEvent.mouseEvent(
                with: .leftMouseDown,
                location: NSPoint(x: 12, y: 3),
                modifierFlags: [],
                timestamp: 1,
                windowNumber: 0,
                context: nil,
                eventNumber: 10,
                clickCount: 2,
                pressure: 1
            )
        )

        var didDrag = false
        var didZoom = false
        dragRegion.performWindowDrag = { _ in didDrag = true }
        dragRegion.performWindowZoom = { didZoom = true }

        dragRegion.mouseDown(with: event)

        #expect(didZoom)
        #expect(!didDrag)
    }

    @MainActor
    @Test("explicit drag region falls back to window zoom on double click")
    func explicitDragRegionFallsBackToWindowZoomOnDoubleClick() throws {
        let window = ZoomRecordingWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 120),
            styleMask: [.titled, .resizable],
            backing: .buffered,
            defer: false
        )
        let contentView = NSView(frame: window.contentView?.bounds ?? NSRect(x: 0, y: 0, width: 320, height: 120))
        window.contentView = contentView

        let dragRegion = ShellChromeDragRegionView(
            frame: NSRect(
                x: 0,
                y: 0,
                width: 320,
                height: AppStyles.Shell.Chrome.windowDragRegionHeight
            )
        )
        contentView.addSubview(dragRegion)

        let event = try #require(
            NSEvent.mouseEvent(
                with: .leftMouseDown,
                location: NSPoint(x: 12, y: 3),
                modifierFlags: [],
                timestamp: 1,
                windowNumber: window.windowNumber,
                context: nil,
                eventNumber: 11,
                clickCount: 2,
                pressure: 1
            )
        )

        var didDrag = false
        dragRegion.performWindowDrag = { _ in didDrag = true }

        dragRegion.mouseDown(with: event)

        #expect(window.didPerformZoom)
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

    private func sourceContents(_ relativePath: String) throws -> String {
        let projectRoot = URL(fileURLWithPath: TestPathResolver.projectRoot(from: #filePath))
        return try String(contentsOf: projectRoot.appending(path: relativePath), encoding: .utf8)
    }

}

private final class ZoomRecordingWindow: NSWindow {
    var didPerformZoom = false

    override func performZoom(_ sender: Any?) {
        didPerformZoom = true
    }
}
