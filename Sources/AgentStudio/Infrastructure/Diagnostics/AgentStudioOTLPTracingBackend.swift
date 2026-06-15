import Foundation
import OTel
import ServiceLifecycle
import Tracing

protocol AgentStudioTraceSpanRecording: Sendable {
    func traceparent(from context: ServiceContext) -> String?

    func withSpan<T>(
        operationName: String,
        parentTraceparent: String?,
        startTimeUnixNano: UInt64,
        durationMilliseconds: Double?,
        attributes: [String: AgentStudioTraceValue],
        _ operation: () -> T
    ) -> T
}

struct AgentStudioOTLPTracingBackend: AgentStudioTraceSpanRecording {
    let service: any Service
    private let extractContext: @Sendable (String?) -> ServiceContext
    private let injectTraceparent: @Sendable (ServiceContext) -> String?
    private let startSpan:
        @Sendable (
            String,
            ServiceContext,
            SpanKind,
            DefaultTracerClock.Timestamp
        ) -> any Span

    init(configuration: OTel.Configuration) throws {
        let backend = try OTel.makeTracingBackend(configuration: configuration)
        self.init(tracer: backend.factory, service: backend.service)
    }

    private init<TTracer>(
        tracer: TTracer,
        service: any Service
    ) where TTracer: Tracer {
        self.service = service
        self.injectTraceparent = { context in
            var carrier = AgentStudioTraceparentCarrier()
            tracer.inject(context, into: &carrier, using: AgentStudioTraceparentInjector())
            return carrier.traceparent
        }
        self.extractContext = { traceparent in
            guard let traceparent else {
                return .topLevel
            }

            var context = ServiceContext.topLevel
            let carrier = AgentStudioTraceparentCarrier(fields: ["traceparent": traceparent])
            tracer.extract(carrier, into: &context, using: AgentStudioTraceparentExtractor())
            return context
        }
        self.startSpan = { operationName, context, kind, instant in
            tracer.startSpan(
                operationName,
                context: context,
                ofKind: kind,
                at: instant
            )
        }
    }

    func traceparent(from context: ServiceContext) -> String? {
        injectTraceparent(context)
    }

    func withSpan<T>(
        operationName: String,
        parentTraceparent: String?,
        startTimeUnixNano: UInt64,
        durationMilliseconds: Double?,
        attributes: [String: AgentStudioTraceValue],
        _ operation: () -> T
    ) -> T {
        let parentContext = extractContext(parentTraceparent)
        let startInstant = DefaultTracerClock.Timestamp(nanosecondsSinceEpoch: startTimeUnixNano)
        let span = startSpan(
            operationName,
            parentContext,
            .internal,
            startInstant
        )
        span.attributes = spanAttributes(from: attributes)
        let endInstant = DefaultTracerClock.Timestamp(
            nanosecondsSinceEpoch: endTimeUnixNano(
                startTimeUnixNano: startTimeUnixNano,
                durationMilliseconds: durationMilliseconds
            )
        )

        return ServiceContext.$current.withValue(span.context) {
            defer { span.end(at: endInstant) }
            return operation()
        }
    }

    private func spanAttributes(from attributes: [String: AgentStudioTraceValue]) -> SpanAttributes {
        var spanAttributes = SpanAttributes()
        spanAttributes.reserveCapacity(attributes.count)

        for (key, value) in attributes {
            switch value {
            case .bool(let boolValue):
                spanAttributes[key] = boolValue
            case .double(let doubleValue):
                guard doubleValue.isFinite else { continue }
                spanAttributes[key] = doubleValue
            case .int(let intValue):
                spanAttributes[key] = intValue
            case .string(let stringValue):
                spanAttributes[key] = stringValue
            case .stringArray:
                continue
            }
        }

        return spanAttributes
    }

    private func endTimeUnixNano(startTimeUnixNano: UInt64, durationMilliseconds: Double?) -> UInt64 {
        guard let durationMilliseconds, durationMilliseconds.isFinite, durationMilliseconds >= 0 else {
            return startTimeUnixNano &+ 1
        }

        let durationNanoseconds = UInt64((durationMilliseconds * 1_000_000).rounded())
        return startTimeUnixNano &+ max(1, durationNanoseconds)
    }
}
