import AppKit
import SwiftUI
import Testing

@testable import AgentStudio

@MainActor
@Suite
struct SplitContainerDropCaptureOverlayTraceTests {
    @Test
    func handleDragUpdateWritesAcceptedTargetTrace() async throws {
        let paneId = UUID()
        let sourceTabId = UUID()
        let traceDirectory = temporaryTraceDirectoryURL()
        var currentTarget: PaneDropTarget?
        let dispatcher = RecordingPaneActionDispatcher()
        let runtime = AgentStudioTraceRuntime(
            configuration: AgentStudioTraceConfiguration.from(environment: [
                "AGENTSTUDIO_TRACE_DIR": traceDirectory.path,
                "AGENTSTUDIO_TRACE_NAME": "split-drag",
                "AGENTSTUDIO_TRACE_TAGS": "drag",
            ]),
            processIdentifier: 4242,
            timeUnixNano: { 123 }
        )
        let coordinator = SplitContainerDropCaptureOverlay.Coordinator(
            targetBinding: Binding(
                get: { currentTarget },
                set: { currentTarget = $0 }
            ),
            actionDispatcher: dispatcher,
            traceRuntime: runtime
        )
        coordinator.updateLayout(
            paneFrames: [paneId: CGRect(x: 0, y: 0, width: 200, height: 100)],
            containerBounds: CGRect(x: 0, y: 0, width: 200, height: 100),
            isManagementLayerActive: true
        )
        let pasteboard = try panePasteboard(paneId: paneId, sourceTabId: sourceTabId)

        let target = coordinator.handleDragUpdate(from: pasteboard, location: CGPoint(x: 25, y: 50))

        #expect(target == PaneDropTarget(paneId: paneId, zone: .left))
        let outputFileURL = try #require(runtime.outputFileURL)
        await assertEventuallyAsync("drag trace should flush to JSONL") {
            guard let contents = try? String(contentsOf: outputFileURL, encoding: .utf8) else {
                return false
            }
            return contents.contains("\"body\":\"drag.update\"")
                && contents.contains("\"drag.accepted\":true")
                && contents.contains("\"drag.payload.kind\":\"existing_pane\"")
                && contents.contains("\"drag.session_id\":")
                && contents.contains("\"drag.target.pane_id\":\"\(paneId.uuidString)\"")
                && contents.contains("\"drag.target.zone\":\"left\"")
                && contents.contains("\"agentstudio.correlation_id\":")
        }
    }

    private func temporaryTraceDirectoryURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("agentstudio-split-drag-trace-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    private func panePasteboard(paneId: UUID, sourceTabId: UUID) throws -> NSPasteboard {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("agentstudio.split-drag.\(UUID().uuidString)"))
        pasteboard.clearContents()
        let payload = PaneDragPayload(paneId: paneId, tabId: sourceTabId)
        try pasteboard.setData(JSONEncoder().encode(payload), forType: .agentStudioPaneDrop)
        return pasteboard
    }

    @MainActor
    private final class RecordingPaneActionDispatcher: PaneActionDispatching {
        func dispatch(_ action: PaneActionCommand) {}

        func shouldAcceptDrop(
            _ payload: SplitDropPayload,
            destinationPaneId: UUID,
            zone: DropZone
        ) -> Bool {
            true
        }

        func handleDrop(
            _ payload: SplitDropPayload,
            destinationPaneId: UUID,
            zone: DropZone
        ) {}
    }
}
