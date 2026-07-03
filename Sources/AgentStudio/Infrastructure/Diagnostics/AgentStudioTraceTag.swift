import Foundation

struct AgentStudioTraceTagSelection: Equatable, Sendable {
    let tags: Set<AgentStudioTraceTag>
    let unknownSelectors: [String]
}

enum AgentStudioTraceTag: String, CaseIterable, Codable, Sendable {
    case actions
    case appFocus = "app.focus"
    case appStartup = "app.startup"
    case arrangement
    case atoms
    case bridgePerformanceSwift = "bridge.performance.swift"
    case bridgePerformanceWeb = "bridge.performance.web"
    case bridgePerformanceWebKit = "bridge.performance.webkit"
    case drag
    case eventbus
    case inbox
    case paneInbox
    case performance
    case persistenceOperation = "persistence.operation"
    case persistenceRecovery = "persistence.recovery"
    case persistenceSnapshot = "persistence.snapshot"
    case restore
    case runtime
    case surface
    case terminalActivity = "terminal.activity"
    case terminalSignal = "terminal.signal"
    case terminalStartup = "terminal.startup"
    case uiInteraction = "ui.interaction"
    case uiSurface = "ui.surface"

    static func parseList(_ rawValue: String?) -> Set<Self> {
        parseSelection(rawValue).tags
    }

    static func parseSelection(_ rawValue: String?) -> AgentStudioTraceTagSelection {
        guard let rawValue else {
            return AgentStudioTraceTagSelection(tags: [], unknownSelectors: [])
        }
        let normalizedValue = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedValue.isEmpty, normalizedValue != "off" else {
            return AgentStudioTraceTagSelection(tags: [], unknownSelectors: [])
        }

        let selectors =
            normalizedValue
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if selectors.contains("*") {
            // The wildcard excludes high-volume lanes: atoms emits ~150k+
            // events under a large-worktree boot storm, which has overflowed
            // the OTLP batch log queue and crashed debug sessions. Selecting
            // atoms requires naming it explicitly (e.g. "*,atoms").
            var tags = Set(Self.allCases).subtracting(Self.explicitOnlyTags)
            for selector in selectors where selector != "*" {
                tags.formUnion(Self.tags(matching: selector))
            }
            return AgentStudioTraceTagSelection(tags: tags, unknownSelectors: [])
        }

        var tags = Set<Self>()
        var unknownSelectors: [String] = []
        for selector in selectors {
            let matches = Self.tags(matching: selector)
            if matches.isEmpty {
                unknownSelectors.append(String(selector))
            } else {
                tags.formUnion(matches)
            }
        }
        return AgentStudioTraceTagSelection(tags: tags, unknownSelectors: unknownSelectors)
    }

    /// High-volume lanes that never ride the wildcard; opt in by name.
    static let explicitOnlyTags: Set<Self> = [.atoms]

    private static func tags(matching selector: String) -> [Self] {
        if selector.hasSuffix(".*") {
            let prefix = selector.dropLast(2)
            return Self.allCases.filter {
                let rawValue = $0.rawValue.lowercased()
                return rawValue == prefix || rawValue.hasPrefix("\(prefix).")
            }
        }
        return Self.allCases.filter { $0.rawValue.lowercased() == selector }
    }
}
