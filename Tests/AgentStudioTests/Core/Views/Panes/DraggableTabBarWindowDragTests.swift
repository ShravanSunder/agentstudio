import AppKit
import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite
struct DraggableTabBarWindowDragTests {
    init() {
        installTestAtomRegistryIfNeeded()
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
    @Test("main split chrome layers explicit drag region above tab host")
    func mainSplitChromeLayersExplicitDragRegionAboveTabHost() async throws {
        try await withMainSplitViewControllerHarness { harness in
            harness.controller.view.frame = NSRect(x: 0, y: 0, width: 1000, height: 700)
            harness.controller.view.layoutSubtreeIfNeeded()

            let descendants = descendants(of: harness.controller.view)
            let dragRegion = try #require(descendants.compactMap { $0 as? ShellChromeDragRegionView }.first)
            let tabHost = try #require(descendants.compactMap { $0 as? DraggableTabBarHostingView }.first)
            let chromeContainer = try #require(dragRegion.superview)
            let tabHostContainer = try #require(tabHost.superview)

            #expect(chromeContainer === tabHostContainer)
            let dragRegionIndex = try #require(chromeContainer.subviews.firstIndex { $0 === dragRegion })
            let tabHostIndex = try #require(chromeContainer.subviews.firstIndex { $0 === tabHost })
            #expect(dragRegionIndex > tabHostIndex)
            #expect(abs(dragRegion.frame.height - AppStyles.Shell.Chrome.windowDragRegionHeight) < 0.5)
        }
    }

    private func sourceContents(_ relativePath: String) throws -> String {
        let projectRoot = URL(fileURLWithPath: TestPathResolver.projectRoot(from: #filePath))
        return try String(contentsOf: projectRoot.appending(path: relativePath), encoding: .utf8)
    }

    @MainActor
    private func descendants(of view: NSView) -> [NSView] {
        view.subviews + view.subviews.flatMap { descendants(of: $0) }
    }
}
