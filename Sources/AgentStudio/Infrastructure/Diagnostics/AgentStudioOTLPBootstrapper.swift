import Foundation
import Logging
import OTel
import ServiceLifecycle

protocol AgentStudioOTLPBootstrapping: Sendable {
    func emit(_ record: AgentStudioOTLPProjectedLogRecord, context: AgentStudioOTLPTraceSinkContext) async
    func flush() async
    func shutdown() async
}

actor AgentStudioOTLPBootstrapper: AgentStudioOTLPBootstrapping {
    static let shared = AgentStudioOTLPBootstrapper()

    private var state: AgentStudioOTLPServiceState?
    private var didReportBootstrapFailure = false

    func emit(_ record: AgentStudioOTLPProjectedLogRecord, context: AgentStudioOTLPTraceSinkContext) async {
        guard let state = bootstrapIfNeeded(record: record, context: context) else {
            return
        }

        state.logger.log(
            level: Logger.Level(record.severityText),
            "\(record.body)",
            metadata: Self.metadata(from: record.attributes)
        )
    }

    func flush() async {
        // Swift OTel owns batching behind the bootstrapped service. Routine AgentStudio
        // trace flushes must not stop that service; final drain happens in shutdown().
    }

    func shutdown() async {
        guard let state else { return }
        await state.serviceGroup.triggerGracefulShutdown()
        await state.runTask.value
        self.state = nil
    }

    private func bootstrapIfNeeded(
        record: AgentStudioOTLPProjectedLogRecord,
        context: AgentStudioOTLPTraceSinkContext
    ) -> AgentStudioOTLPServiceState? {
        if let state {
            return state
        }

        do {
            let configuration = Self.otelConfiguration(record: record, context: context)
            let loggingBackend = try OTel.makeLoggingBackend(configuration: configuration)
            let serviceGroup = ServiceGroup(
                services: [loggingBackend.service],
                logger: Logger(label: "agentstudio.otlp.service", factory: StreamLogHandler.standardError(label:))
            )
            let runTask = Task {
                do {
                    try await serviceGroup.run()
                } catch {
                    Self.writeStartupDiagnostic("AgentStudio OTLP service stopped with error: \(error)")
                }
            }
            let state = AgentStudioOTLPServiceState(
                serviceGroup: serviceGroup,
                runTask: runTask,
                logger: Logger(label: "agentstudio.otlp", factory: loggingBackend.factory)
            )
            self.state = state
            Self.writeStartupDiagnostic("AgentStudio OTLP export enabled: \(Self.logsEndpoint(from: context.endpoint))")
            return state
        } catch {
            if !didReportBootstrapFailure {
                didReportBootstrapFailure = true
                Self.writeStartupDiagnostic("AgentStudio OTLP bootstrap failed: \(error)")
            }
            return nil
        }
    }

    private static func otelConfiguration(
        record: AgentStudioOTLPProjectedLogRecord,
        context: AgentStudioOTLPTraceSinkContext
    ) -> OTel.Configuration {
        var configuration = OTel.Configuration.default
        configuration.metrics.enabled = false
        configuration.traces.enabled = false
        configuration.logs.enabled = true
        configuration.logs.level = .trace
        configuration.logs.exporter = .otlp
        configuration.logs.otlpExporter.endpoint = Self.logsEndpoint(from: context.endpoint)
        configuration.logs.otlpExporter.protocol = .httpProtobuf
        configuration.logs.batchLogRecordProcessor.scheduleDelay = .milliseconds(200)
        configuration.logs.batchLogRecordProcessor.exportTimeout = .seconds(2)
        configuration.serviceName = record.resource["service.name"] ?? "agentstudio"
        configuration.resourceAttributes = record.resource.filter { key, _ in
            key != "service.name"
        }
        return configuration
    }

    private static func logsEndpoint(from endpoint: URL) -> String {
        guard var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else {
            return endpoint.absoluteString
        }

        let path = components.path
        guard !path.hasSuffix("/v1/logs") else {
            return endpoint.absoluteString
        }

        if path.isEmpty || path == "/" {
            components.path = "/v1/logs"
        } else if path.hasSuffix("/") {
            components.path = "\(path)v1/logs"
        } else {
            components.path = "\(path)/v1/logs"
        }
        return components.url?.absoluteString ?? endpoint.absoluteString
    }

    private static func metadata(
        from attributes: [String: AgentStudioTraceValue]
    ) -> Logger.Metadata {
        var metadata: Logger.Metadata = [:]
        for (key, value) in attributes {
            metadata[key] = Logger.MetadataValue(value)
        }
        return metadata
    }

    private static func writeStartupDiagnostic(_ message: String) {
        try? FileHandle.standardError.write(contentsOf: Data("\(message)\n".utf8))
    }
}

private struct AgentStudioOTLPServiceState: Sendable {
    let serviceGroup: ServiceGroup
    let runTask: Task<Void, Never>
    let logger: Logger
}

extension Logger.Level {
    fileprivate init(_ severity: AgentStudioTraceSeverity) {
        switch severity {
        case .trace:
            self = .trace
        case .debug:
            self = .debug
        case .info:
            self = .info
        case .warn:
            self = .warning
        case .error:
            self = .error
        }
    }
}

extension Logger.MetadataValue {
    fileprivate init(_ value: AgentStudioTraceValue) {
        switch value {
        case .bool(let boolValue):
            self = .stringConvertible(boolValue)
        case .double(let doubleValue):
            self = .stringConvertible(doubleValue)
        case .int(let intValue):
            self = .stringConvertible(intValue)
        case .string(let stringValue):
            self = .string(stringValue)
        case .stringArray(let values):
            self = .array(values.map(Logger.Metadata.Value.string))
        }
    }
}
