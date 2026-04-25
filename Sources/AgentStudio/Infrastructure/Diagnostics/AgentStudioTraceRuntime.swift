import Foundation
import OTel
import Tracing

#if canImport(Darwin)
    import Darwin
#elseif canImport(Glibc)
    import Glibc
#endif

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
        sessionID: String = UUID().uuidString,
        scopeVersion: String = "0.1.0",
        writerRetainedLineLimit: Int = 2048,
        timeUnixNano: @escaping @Sendable () -> UInt64 = Self.currentTimeUnixNano
    ) {
        self.configuration = configuration
        self.resource = Self.resourceAttributes(
            serviceName: serviceName,
            serviceVersion: serviceVersion,
            processIdentifier: processIdentifier,
            sessionID: sessionID
        )
        self.scopeVersion = scopeVersion
        self.timeUnixNano = timeUnixNano

        if !configuration.unknownTagSelectors.isEmpty {
            Self.writeStartupDiagnostic(
                "AgentStudio tracing ignored unknown tag selectors: "
                    + configuration.unknownTagSelectors.joined(separator: ",")
            )
        }

        if configuration.isEnabled {
            let outputFileURL = configuration.outputFileURL(processIdentifier: processIdentifier)
            self.outputFileURL = outputFileURL
            self.writer = AgentStudioJSONLTraceWriter(
                fileURL: outputFileURL,
                retainedLineLimit: writerRetainedLineLimit
            )
            Self.writeStartupDiagnostic("AgentStudio tracing enabled: \(outputFileURL.path)")
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
        severity: AgentStudioTraceSeverity = .info,
        context: ServiceContext? = ServiceContext.current,
        traceID: String? = nil,
        spanID: String? = nil,
        parentSpanID: String? = nil,
        attributes: @autoclosure @Sendable () -> [String: AgentStudioTraceValue] = [:]
    ) async {
        guard configuration.isEnabled(tag), let writer else { return }

        await withSpan(body, context: context ?? .current ?? .topLevel) { span in
            var mergedAttributes = attributes()
            let spanContext = span.context
            mergedAttributes["agentstudio.trace.tag"] = .string(tag.rawValue)
            if let correlationID = context?.agentStudioCorrelationID ?? spanContext.agentStudioCorrelationID {
                mergedAttributes["agentstudio.correlation_id"] = .string(correlationID)
            }

            let record = AgentStudioTraceRecord(
                timeUnixNano: timeUnixNano(),
                severityText: severity,
                body: body,
                traceID: traceID ?? spanContext.otelTraceID,
                spanID: spanID,
                parentSpanID: parentSpanID,
                resource: resource,
                scope: .init(name: "agentstudio.\(tag.rawValue)", version: scopeVersion),
                attributes: mergedAttributes
            )
            do {
                try await writer.append(record)
                if configuration.flushMode == .immediate {
                    try await writer.flush()
                }
            } catch {
                debugLog("[trace] failed to record \(body): \(error)")
            }
        }
    }

    func flush() async throws {
        try await writer?.flush()
    }

    private static func resourceAttributes(
        serviceName: String,
        serviceVersion: String?,
        processIdentifier: Int32,
        sessionID: String
    ) -> [String: String] {
        var attributes = [
            "agentstudio.build.config": buildConfiguration,
            "agentstudio.session.id": sessionID,
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
        #if canImport(Darwin) || canImport(Glibc)
            var currentTime = timespec()
            clock_gettime(CLOCK_REALTIME, &currentTime)
            return UInt64(currentTime.tv_sec) * nanosecondsPerSecond + UInt64(currentTime.tv_nsec)
        #else
            let seconds = UInt64(Date().timeIntervalSince1970)
            let nanoseconds = UInt64(
                Date().timeIntervalSince1970.truncatingRemainder(dividingBy: 1) * Double(nanosecondsPerSecond))
            return seconds * nanosecondsPerSecond + nanoseconds
        #endif
    }

    private static var buildConfiguration: String {
        #if DEBUG
            "DEBUG"
        #else
            "RELEASE"
        #endif
    }

    private static func writeStartupDiagnostic(_ message: String) {
        try? FileHandle.standardError.write(contentsOf: Data("\(message)\n".utf8))
    }
}
