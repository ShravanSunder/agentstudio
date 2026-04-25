import Foundation

struct AgentStudioTraceRuntime: Sendable {
    private let configuration: AgentStudioTraceConfiguration
    private let writer: AgentStudioJSONLTraceWriter?
    private let resource: [String: String]
    private let scopeVersion: String
    private let timeUnixNano: @Sendable () -> UInt64

    let outputFileURL: URL?

    var isEnabled: Bool {
        configuration.isEnabled
    }

    init(
        configuration: AgentStudioTraceConfiguration,
        processIdentifier: Int32 = ProcessInfo.processInfo.processIdentifier,
        serviceName: String = "AgentStudio",
        serviceVersion: String? = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
        scopeVersion: String = "0.1.0",
        writerRetainedLineLimit: Int = 2048,
        timeUnixNano: @escaping @Sendable () -> UInt64 = Self.currentTimeUnixNano
    ) {
        self.configuration = configuration
        self.resource = Self.resourceAttributes(
            serviceName: serviceName,
            serviceVersion: serviceVersion,
            processIdentifier: processIdentifier
        )
        self.scopeVersion = scopeVersion
        self.timeUnixNano = timeUnixNano

        if configuration.isEnabled {
            let outputFileURL = configuration.outputFileURL(processIdentifier: processIdentifier)
            self.outputFileURL = outputFileURL
            self.writer = AgentStudioJSONLTraceWriter(
                fileURL: outputFileURL,
                retainedLineLimit: writerRetainedLineLimit
            )
        } else {
            self.outputFileURL = nil
            self.writer = nil
        }
    }

    static func fromEnvironment(
        _ environment: [String: String] = ProcessInfo.processInfo.environment,
        processIdentifier: Int32 = ProcessInfo.processInfo.processIdentifier
    ) -> Self {
        Self(
            configuration: AgentStudioTraceConfiguration.from(environment: environment),
            processIdentifier: processIdentifier
        )
    }

    func isEnabled(_ tag: AgentStudioTraceTag) -> Bool {
        configuration.isEnabled(tag)
    }

    func record(
        tag: AgentStudioTraceTag,
        body: String,
        severityText: String = "INFO",
        traceID: String? = nil,
        spanID: String? = nil,
        parentSpanID: String? = nil,
        attributes: @autoclosure @Sendable () -> [String: AgentStudioTraceValue] = [:]
    ) async throws {
        guard configuration.isEnabled(tag), let writer else { return }

        var mergedAttributes = attributes()
        mergedAttributes["agentstudio.trace.tag"] = .string(tag.rawValue)

        let record = AgentStudioTraceRecord(
            timeUnixNano: timeUnixNano(),
            severityText: severityText,
            body: body,
            traceID: traceID,
            spanID: spanID,
            parentSpanID: parentSpanID,
            resource: resource,
            scope: .init(name: "agentstudio.\(tag.rawValue)", version: scopeVersion),
            attributes: mergedAttributes
        )
        try await writer.append(record)
    }

    func flush() async throws {
        try await writer?.flush()
    }

    private static func resourceAttributes(
        serviceName: String,
        serviceVersion: String?,
        processIdentifier: Int32
    ) -> [String: String] {
        var attributes = [
            "process.pid": "\(processIdentifier)",
            "service.name": serviceName,
        ]
        if let serviceVersion, !serviceVersion.isEmpty {
            attributes["service.version"] = serviceVersion
        }
        return attributes
    }

    private static func currentTimeUnixNano() -> UInt64 {
        let nanosecondsPerSecond: UInt64 = 1_000_000_000
        let now = Date().timeIntervalSince1970
        return UInt64(now * Double(nanosecondsPerSecond))
    }
}
