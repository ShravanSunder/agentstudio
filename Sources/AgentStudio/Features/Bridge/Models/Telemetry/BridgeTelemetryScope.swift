enum BridgeTelemetryScope: String, CaseIterable, Codable, Equatable, Hashable, Sendable {
    case swift
    case web
    case webKit = "webkit"

    var traceTag: AgentStudioTraceTag {
        switch self {
        case .swift:
            .bridgePerformanceSwift
        case .web:
            .bridgePerformanceWeb
        case .webKit:
            .bridgePerformanceWebKit
        }
    }
}
