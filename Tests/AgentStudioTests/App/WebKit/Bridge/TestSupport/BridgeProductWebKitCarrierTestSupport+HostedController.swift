import AppKit
import WebKit

@testable import AgentStudioBridge

@MainActor
extension BridgeProductWebKitCarrierTestSupport {
    static func withHostedController<Value>(
        _ controller: BridgePaneController,
        frame: NSRect = NSRect(x: 0, y: 0, width: 960, height: 720),
        operation: @MainActor (BridgePaneController) async throws -> Value
    ) async throws -> BridgeProductWebKitCarrierRunResult<Value> {
        try await withHostedController(
            controller,
            frame: frame
        ) { hostedController, _ in
            try await operation(hostedController)
        }
    }

    static func hostSnapshot(window: NSWindow) -> BridgeProductWebKitCarrierHostSnapshot {
        guard let mountView = window.contentView as? BridgePaneMountView else {
            return BridgeProductWebKitCarrierHostSnapshot(
                applicationIsActive: NSApp.isActive,
                hostingViewHasWindow: false,
                hostingViewHeight: 0,
                hostingViewWidth: 0,
                mountViewHasWindow: false,
                mountViewHeight: 0,
                mountViewWidth: 0,
                windowIsKey: window.isKeyWindow,
                windowIsVisible: window.isVisible,
                windowOcclusionIsVisible: window.occlusionState.contains(.visible)
            )
        }
        return hostSnapshot(window: window, mountView: mountView)
    }

    static func waitForActiveFileViewerHost(_ page: WebPage) async throws {
        _ = try await WebPageEventWaits.waitForDocumentValue(
            page,
            reader: """
                const fileModeHost = document.querySelector('[data-testid="bridge-viewer-mode-host-file"]');
                if (fileModeHost?.getAttribute('data-bridge-viewer-mode-active') !== 'true') {
                  return null;
                }
                return true;
                """,
            arguments: [:]
        )
    }
}
