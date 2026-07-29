import AgentStudioInfrastructure

enum BridgeTelemetryEventValidationResult: Equatable, Sendable {
    case accepted
    case dropped(BridgeTelemetryDropReason)
}

struct BridgeTelemetryEventValidator: Sendable {
    private let scopeGate: BridgeTelemetryScopeGate

    init(scopeGate: BridgeTelemetryScopeGate) {
        self.scopeGate = scopeGate
    }

    func validate(_ sample: BridgeTelemetrySample) -> BridgeTelemetryEventValidationResult {
        guard sample.scope == .web, scopeGate.isEnabled(sample.scope) else {
            return .dropped(.disabledScope)
        }
        if let dropReason = BridgeTelemetryWireSchema.dropReason(
            eventName: sample.name,
            durationMilliseconds: sample.durationMilliseconds,
            stringAttributes: sample.stringAttributes,
            numericAttributes: sample.numericAttributes,
            booleanAttributes: sample.booleanAttributes
        ) {
            return .dropped(dropReason)
        }
        return .accepted
    }
}
