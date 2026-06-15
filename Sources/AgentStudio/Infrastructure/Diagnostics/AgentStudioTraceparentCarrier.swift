import Tracing

struct AgentStudioTraceparentCarrier: Sendable {
    var fields: [String: String]

    init(fields: [String: String] = [:]) {
        self.fields = fields.reduce(into: [:]) { partialResult, element in
            partialResult[element.key.lowercased()] = element.value
        }
    }

    var traceparent: String? {
        fields["traceparent"]
    }
}

struct AgentStudioTraceparentInjector: Injector {
    func inject(_ value: String, forKey key: String, into carrier: inout AgentStudioTraceparentCarrier) {
        carrier.fields[key.lowercased()] = value
    }
}

struct AgentStudioTraceparentExtractor: Extractor {
    func extract(key: String, from carrier: AgentStudioTraceparentCarrier) -> String? {
        carrier.fields[key.lowercased()]
    }
}
