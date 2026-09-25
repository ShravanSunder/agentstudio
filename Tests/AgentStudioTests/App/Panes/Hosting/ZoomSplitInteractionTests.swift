import AppKit
import SwiftUI
import Testing

@testable import AgentStudio
@testable import AgentStudioCore
@testable import AgentStudioEditorChooser
@testable import AgentStudioInfrastructure
@testable import AgentStudioSharedComponents

@MainActor
@Suite("Zoom split bounds interactions", .serialized)
struct ZoomSplitInteractionTests {
    init() {
        installTestAtomRegistryIfNeeded()
    }

    @Test("divider drag stops at the maximum terminal share")
    func dividerDragStopsAtMaximumTerminalShare() throws {
        let harness = makeMountedZoomSplit(initialRatio: 0.4)
        defer { close(harness.window) }

        try sendDrag(fromX: 160, toX: 380, in: harness.window)

        #expect(lastZoomRatio(in: harness.actions.actions) == 0.6)
    }

    @Test("divider drag stops at the minimum terminal share")
    func dividerDragStopsAtMinimumTerminalShare() throws {
        let harness = makeMountedZoomSplit(initialRatio: 0.4)
        defer { close(harness.window) }

        try sendDrag(fromX: 160, toX: 0, in: harness.window)

        #expect(lastZoomRatio(in: harness.actions.actions) == 0.3)
    }

    @Test("double-clicking the divider resets terminal share to forty percent")
    func doubleClickResetsTerminalShareToDefault() throws {
        let harness = makeMountedZoomSplit(initialRatio: 0.55)
        defer { close(harness.window) }

        try sendDoubleClick(atX: 220, in: harness.window)

        #expect(lastZoomRatio(in: harness.actions.actions) == 0.4)
    }

    private func makeMountedZoomSplit(initialRatio: Double) -> MountedZoomSplit {
        let actions = ZoomSplitActionRecorder()
        let sourcePaneId = UUIDv7.generate()
        let companionPaneId = UUIDv7.generate()
        let actionDispatcher = PaneTabActionDispatcher(
            dispatch: { actions.actions.append($0) },
            shouldHandleSplitDragPayload: { _ in false },
            shouldAcceptDrop: { _, _, _, _ in false },
            handleDrop: { _, _, _, _ in }
        )
        let rootView = ZoomPresentationContainer(
            tabId: UUIDv7.generate(),
            sourcePaneId: sourcePaneId,
            sourceOrdinal: 1,
            sourceContent: AnyView(Color.clear),
            companionContent: AnyView(Color.clear),
            parentToolbarPresentation: .zoom(ZoomToolbarModel(viewerAction: nil, zoomAction: nil)),
            splitRatio: initialRatio,
            store: WorkspaceStore(),
            octiconLoader: makeTestOcticonLoader(),
            editorChooser: makeTestAtomRegistry().editorChooser,
            actionDispatcher: actionDispatcher,
            arrangementInlineRenameState: ArrangementInlineRenameState(),
            onPaneFocusTrigger: { _ in },
            viewRegistry: ViewRegistry(),
            surfaceId: "zoom-split-interaction-test",
            renderedPaneIds: [sourcePaneId, companionPaneId]
        )
        let hostingView = NSHostingView(rootView: rootView.frame(width: 400, height: 240))
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 400, height: 240),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = hostingView
        window.makeKeyAndOrderFront(nil)
        hostingView.layoutSubtreeIfNeeded()
        return MountedZoomSplit(window: window, actions: actions)
    }

    private func sendDrag(fromX startX: CGFloat, toX endX: CGFloat, in window: NSWindow) throws {
        let y: CGFloat = 120
        window.sendEvent(try mouseEvent(.leftMouseDown, at: CGPoint(x: startX, y: y), window: window, number: 1))
        window.sendEvent(try mouseEvent(.leftMouseDragged, at: CGPoint(x: endX, y: y), window: window, number: 2))
        window.sendEvent(try mouseEvent(.leftMouseUp, at: CGPoint(x: endX, y: y), window: window, number: 3))
    }

    private func sendDoubleClick(atX x: CGFloat, in window: NSWindow) throws {
        let point = CGPoint(x: x, y: 120)
        window.sendEvent(try mouseEvent(.leftMouseDown, at: point, window: window, number: 1, clickCount: 1))
        window.sendEvent(try mouseEvent(.leftMouseUp, at: point, window: window, number: 2, clickCount: 1))
        window.sendEvent(try mouseEvent(.leftMouseDown, at: point, window: window, number: 3, clickCount: 2))
        window.sendEvent(try mouseEvent(.leftMouseUp, at: point, window: window, number: 4, clickCount: 2))
    }

    private func mouseEvent(
        _ type: NSEvent.EventType,
        at point: CGPoint,
        window: NSWindow,
        number: Int,
        clickCount: Int = 1
    ) throws -> NSEvent {
        try #require(
            NSEvent.mouseEvent(
                with: type,
                location: point,
                modifierFlags: [],
                timestamp: Double(number) / 10,
                windowNumber: window.windowNumber,
                context: nil,
                eventNumber: number,
                clickCount: clickCount,
                pressure: type == .leftMouseUp ? 0 : 1
            )
        )
    }

    private func lastZoomRatio(in actions: [WorkspaceActionCommand]) -> Double? {
        for action in actions.reversed() {
            if case .setZoomSplitRatio(_, let ratio) = action {
                return ratio
            }
        }
        return nil
    }

    private func close(_ window: NSWindow) {
        window.orderOut(nil)
        window.close()
    }
}

@MainActor
private struct MountedZoomSplit {
    let window: NSWindow
    let actions: ZoomSplitActionRecorder
}

@MainActor
private final class ZoomSplitActionRecorder {
    var actions: [WorkspaceActionCommand] = []
}
