import Foundation

struct AgentStudioStartupDiagnosticAction: Equatable, Sendable {
    static let environmentKey = "AGENTSTUDIO_STARTUP_DIAGNOSTIC_ACTION"

    enum Kind: String, Sendable {
        case newTab = "new-tab"
    }

    let kind: Kind

    var commandName: String {
        switch kind {
        case .newTab:
            "newTab"
        }
    }

    static func fromEnvironment(
        _ environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Self? {
        guard let rawValue = environment[environmentKey] else { return nil }
        let normalizedValue = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let kind = Kind(rawValue: normalizedValue) else { return nil }
        return Self(kind: kind)
    }
}
