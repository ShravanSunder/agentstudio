import AppKit
import Foundation
import SwiftUI
import Testing

@testable import AgentStudio

@Suite(.serialized)
@MainActor
struct SplitContainerDropCaptureOverlayTests {
    @Test
    func handleDragUpdate_ignoresDrawerSourcedPayloadBeforeTargetResolution() throws {
        let paneId = UUID()
        let sourcePaneId = UUID()
        let pasteboard = NSPasteboard(name: NSPasteboard.Name(UUID().uuidString))
        pasteboard.clearContents()
        pasteboard.setData(
            try JSONEncoder().encode(PaneDragPayload(paneId: sourcePaneId, tabId: UUID(), drawerParentPaneId: UUID())),
            forType: .agentStudioPaneDrop
        )

        let targetState = Binding<PaneDropTarget?>(
            get: { nil },
            set: { _ in }
        )
        let actionDispatcher = TestPaneActionDispatcher(
            shouldHandleSplitDragPayloadResult: false,
            shouldAcceptDropResult: true
        )
        let coordinator = SplitContainerDropCaptureOverlay.Coordinator(
            targetBinding: targetState,
            sourcePaneIdBinding: .constant(nil),
            actionDispatcher: actionDispatcher
        )
        coordinator.updateLayout(
            paneFrames: [paneId: CGRect(x: 0, y: 0, width: 200, height: 100)],
            containerBounds: CGRect(x: 0, y: 0, width: 200, height: 100),
            minimizedPaneIds: [],
            isManagementLayerActive: true
        )

        let target = coordinator.handleDragUpdate(
            from: pasteboard,
            location: CGPoint(x: 150, y: 50)
        )

        #expect(target == nil)
        #expect(actionDispatcher.shouldAcceptDropCallCount == 0)
    }

    @Test
    func handleDragUpdate_validatesDropWithResolvedSizingMode() throws {
        let paneId = UUID()
        let sourcePaneId = UUID()
        let sourceTabId = UUID()
        let pasteboard = NSPasteboard(name: NSPasteboard.Name(UUID().uuidString))
        pasteboard.clearContents()
        pasteboard.setData(
            try JSONEncoder().encode(PaneDragPayload(paneId: sourcePaneId, tabId: sourceTabId)),
            forType: .agentStudioPaneDrop
        )

        let targetState = Binding<PaneDropTarget?>(
            get: { nil },
            set: { _ in }
        )
        let actionDispatcher = TestPaneActionDispatcher()
        let coordinator = SplitContainerDropCaptureOverlay.Coordinator(
            targetBinding: targetState,
            sourcePaneIdBinding: .constant(nil),
            actionDispatcher: actionDispatcher
        )
        coordinator.updateLayout(
            paneFrames: [paneId: CGRect(x: 0, y: 0, width: 200, height: 100)],
            containerBounds: CGRect(x: 0, y: 0, width: 200, height: 100),
            minimizedPaneIds: [],
            isManagementLayerActive: true
        )

        // x=100 lands in the center zone of the 200-wide pane → split
        // → halveTarget sizing. (Was x=150 under the old whole-pane-
        // split model; that lands in the right 1/4 zone now → between
        // slot → proportional sizing.)
        _ = coordinator.handleDragUpdate(
            from: pasteboard,
            location: CGPoint(x: 100, y: 50)
        )

        #expect(actionDispatcher.shouldAcceptDropSizingModes == [.halveTarget])
    }
}

@MainActor
private final class TestPaneActionDispatcher: PaneActionDispatching {
    let shouldHandleSplitDragPayloadResult: Bool
    let shouldAcceptDropResult: Bool
    private(set) var shouldAcceptDropCallCount = 0
    private(set) var shouldAcceptDropSizingModes: [DropSizingMode] = []

    init(
        shouldHandleSplitDragPayloadResult: Bool = true,
        shouldAcceptDropResult: Bool = true
    ) {
        self.shouldHandleSplitDragPayloadResult = shouldHandleSplitDragPayloadResult
        self.shouldAcceptDropResult = shouldAcceptDropResult
    }

    func dispatch(_ action: WorkspaceActionCommand) {}

    func shouldHandleSplitDragPayload(_ payload: SplitDropPayload) -> Bool {
        shouldHandleSplitDragPayloadResult
    }

    func shouldAcceptDrop(
        _ payload: SplitDropPayload,
        destinationPaneId: UUID,
        zone: DropZoneSide,
        sizingMode: DropSizingMode
    ) -> Bool {
        shouldAcceptDropCallCount += 1
        shouldAcceptDropSizingModes.append(sizingMode)
        return shouldAcceptDropResult
    }

    func handleDrop(
        _ payload: SplitDropPayload,
        destinationPaneId: UUID,
        zone: DropZoneSide,
        sizingMode: DropSizingMode
    ) {}
}
