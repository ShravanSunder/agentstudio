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
}

@MainActor
private final class TestPaneActionDispatcher: PaneActionDispatching {
    let shouldHandleSplitDragPayloadResult: Bool
    let shouldAcceptDropResult: Bool
    private(set) var shouldAcceptDropCallCount = 0

    init(
        shouldHandleSplitDragPayloadResult: Bool = true,
        shouldAcceptDropResult: Bool = true
    ) {
        self.shouldHandleSplitDragPayloadResult = shouldHandleSplitDragPayloadResult
        self.shouldAcceptDropResult = shouldAcceptDropResult
    }

    func dispatch(_ action: PaneActionCommand) {}

    func shouldHandleSplitDragPayload(_ payload: SplitDropPayload) -> Bool {
        shouldHandleSplitDragPayloadResult
    }

    func shouldAcceptDrop(
        _ payload: SplitDropPayload,
        destinationPaneId: UUID,
        zone: DropZoneSide
    ) -> Bool {
        shouldAcceptDropCallCount += 1
        return shouldAcceptDropResult
    }

    func handleDrop(
        _ payload: SplitDropPayload,
        destinationPaneId: UUID,
        zone: DropZoneSide,
        sizingMode: DropSizingMode
    ) {}
}
