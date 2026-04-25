import Foundation

struct AgentStudioDragDebugOptions: Equatable, Sendable {
    let showsDestinations: Bool

    static func fromEnvironment(_ environment: [String: String] = ProcessInfo.processInfo.environment) -> Self {
        Self(showsDestinations: parseBoolean(environment["AGENTSTUDIO_DEBUG_DRAG_DESTINATIONS"]))
    }

    private static func parseBoolean(_ rawValue: String?) -> Bool {
        guard let rawValue else { return false }
        switch rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "1", "true", "yes", "on":
            return true
        default:
            return false
        }
    }
}
