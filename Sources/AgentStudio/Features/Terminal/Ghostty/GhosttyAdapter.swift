import Foundation

/// Adapter boundary translating low-level Ghostty action tags into typed
/// domain events consumed by TerminalRuntime.
@MainActor
final class GhosttyAdapter {
    static let shared = GhosttyAdapter()

    private init() {}

    func translate(actionTag: UInt32) -> GhosttyEvent {
        switch actionTag {
        case 0:
            return .bellRang
        default:
            return .unhandled(tag: actionTag)
        }
    }

    func route(actionTag: UInt32, to runtime: TerminalRuntime) {
        let event = translate(actionTag: actionTag)
        runtime.handleGhosttyEvent(event)
    }
}
