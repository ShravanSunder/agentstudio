import AppKit

@testable import AgentStudioBridge

@MainActor
extension BridgeProductWebKitCarrierTestSupport {
    static func withHostedController<Value>(
        _ controller: BridgePaneController,
        frame: NSRect = NSRect(x: 0, y: 0, width: 960, height: 720),
        requireVisibleHost: Bool = false,
        operation: @MainActor (BridgePaneController) async throws -> Value
    ) async throws -> BridgeProductWebKitCarrierRunResult<Value> {
        try await withHostedController(
            controller,
            frame: frame,
            requireVisibleHost: requireVisibleHost
        ) { hostedController, _ in
            try await operation(hostedController)
        }
    }
}
