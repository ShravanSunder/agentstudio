struct BridgeTelemetryScopeGate: Equatable, Sendable {
    let enabledScopes: Set<BridgeTelemetryScope>

    init(enabledScopes: Set<BridgeTelemetryScope>) {
        self.enabledScopes = enabledScopes
    }

    init(traceRuntime: AgentStudioTraceRuntime?) {
        guard let traceRuntime else {
            self.enabledScopes = []
            return
        }
        self.enabledScopes = Set(
            BridgeTelemetryScope.allCases.filter { scope in
                traceRuntime.isEnabled(scope.traceTag)
            }
        )
    }

    var isEnabled: Bool {
        !enabledScopes.isEmpty
    }

    var browserExposedScopes: Set<BridgeTelemetryScope> {
        enabledScopes.intersection([.web])
    }

    func isEnabled(_ scope: BridgeTelemetryScope) -> Bool {
        enabledScopes.contains(scope)
    }
}
