import Foundation

enum AgentStudioTraceTag: String, CaseIterable, Codable, Sendable {
    case actions
    case atoms
    case drag
    case eventbus
    case restore
    case runtime
    case surface

    static func parseList(_ rawValue: String?) -> Set<Self> {
        guard let rawValue else { return [] }
        let normalizedValue = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedValue.isEmpty, normalizedValue != "off" else { return [] }

        let selectors =
            normalizedValue
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if selectors.contains("*") {
            return Set(Self.allCases)
        }

        return Set(selectors.flatMap(Self.tags(matching:)))
    }

    private static func tags(matching selector: String) -> [Self] {
        if selector.hasSuffix(".*") {
            let prefix = selector.dropLast(2)
            return Self.allCases.filter { $0.rawValue == prefix || $0.rawValue.hasPrefix("\(prefix).") }
        }
        return Self.allCases.filter { $0.rawValue == selector }
    }
}
