enum BridgeTelemetryPriority: String, CaseIterable, Codable, Equatable, Hashable, Sendable {
    case hot
    case warm
    case cold
    case bestEffort = "best_effort"
}
