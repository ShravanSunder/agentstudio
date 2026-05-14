import Tracing

extension ServiceContext {
    var agentStudioCorrelationID: String? {
        get {
            self[AgentStudioCorrelationIDKey.self]
        }
        set {
            self[AgentStudioCorrelationIDKey.self] = newValue
        }
    }
}

private enum AgentStudioCorrelationIDKey: ServiceContextKey {
    typealias Value = String
    static let nameOverride: String? = "agentstudio-correlation-id"
}
