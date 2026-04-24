import AppKit
import CoreGraphics
import SwiftUI
import Testing

@testable import AgentStudio

@MainActor
@Suite(.serialized)
struct DrawerSplitContainerDropCaptureOverlayTests {
    @Test
    func performDrop_commitsLatchedTargetWhenReleaseIsInGap() throws {
        let sourcePaneId = UUID()
        let targetPaneId = UUID()
        var latchedTarget: DrawerRearrangeTarget? = .paneSplit(paneId: targetPaneId, side: .left)
        var handledDrops: [HandledDrawerDrop] = []

        let coordinator = DrawerSplitContainerDropCaptureOverlay.Coordinator(
            targetBinding: Binding(
                get: { latchedTarget },
                set: { latchedTarget = $0 }
            ),
            shouldAcceptDrop: { _, _, _ in true },
            handleDrop: { payload, target, sizingMode in
                handledDrops.append(HandledDrawerDrop(payload: payload, target: target, sizingMode: sizingMode))
            }
        )
        coordinator.updateLayout(
            paneFrames: [targetPaneId: CGRect(x: 0, y: 0, width: 100, height: 80)],
            layout: DrawerGridLayout(topRow: Layout.autoTiled([sourcePaneId, targetPaneId])),
            minimizedPaneIds: [],
            containerBounds: CGRect(x: 0, y: 0, width: 240, height: 120),
            isManagementLayerActive: true
        )
        let payload = SplitDropPayload(kind: .existingPane(paneId: sourcePaneId, sourceTabId: UUID()))
        let pasteboard = try pasteboard(containing: payload)

        let didDrop = coordinator.performDrop(
            from: pasteboard,
            location: CGPoint(x: 220, y: 110)
        )

        #expect(didDrop)
        #expect(
            handledDrops == [
                HandledDrawerDrop(
                    payload: payload, target: .paneSplit(paneId: targetPaneId, side: .left), sizingMode: .halveTarget)
            ]
        )
    }

    @Test
    func performDrop_usesSameSizingModeForValidationAndDispatch() throws {
        let sourcePaneId = UUID()
        let targetPaneId = UUID()
        var latchedTarget: DrawerRearrangeTarget? = .paneSplit(paneId: targetPaneId, side: .right)
        var validatedSizingModes: [DropSizingMode] = []
        var handledSizingModes: [DropSizingMode] = []

        let coordinator = DrawerSplitContainerDropCaptureOverlay.Coordinator(
            targetBinding: Binding(
                get: { latchedTarget },
                set: { latchedTarget = $0 }
            ),
            shouldAcceptDrop: { _, _, sizingMode in
                validatedSizingModes.append(sizingMode)
                return true
            },
            handleDrop: { _, _, sizingMode in
                handledSizingModes.append(sizingMode)
            }
        )
        coordinator.updateLayout(
            paneFrames: [targetPaneId: CGRect(x: 0, y: 0, width: 100, height: 80)],
            layout: DrawerGridLayout(topRow: Layout.autoTiled([sourcePaneId, targetPaneId])),
            minimizedPaneIds: [],
            containerBounds: CGRect(x: 0, y: 0, width: 240, height: 120),
            isManagementLayerActive: true
        )
        let pasteboard = try pasteboard(
            containing: SplitDropPayload(kind: .existingPane(paneId: sourcePaneId, sourceTabId: UUID()))
        )

        _ = coordinator.performDrop(from: pasteboard, location: CGPoint(x: 220, y: 110))

        #expect(validatedSizingModes == [.halveTarget])
        #expect(handledSizingModes == validatedSizingModes)
    }

    private func pasteboard(containing payload: SplitDropPayload) throws -> NSPasteboard {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name(UUID().uuidString))
        pasteboard.clearContents()
        guard case .existingPane(let paneId, let sourceTabId) = payload.kind else {
            Issue.record("Expected existing-pane payload")
            return pasteboard
        }
        pasteboard.setData(
            try JSONEncoder().encode(PaneDragPayload(paneId: paneId, tabId: sourceTabId)),
            forType: .agentStudioPaneDrop
        )
        return pasteboard
    }
}

private struct HandledDrawerDrop: Equatable {
    let payload: SplitDropPayload
    let target: DrawerRearrangeTarget
    let sizingMode: DropSizingMode
}
