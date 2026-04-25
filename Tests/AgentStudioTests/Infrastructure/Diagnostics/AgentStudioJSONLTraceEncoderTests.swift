import Foundation
import Testing

@testable import AgentStudio

@Suite
struct AgentStudioJSONLTraceEncoderTests {
    @Test
    func encodeLineWritesOneJsonObjectPlusNewline() throws {
        let record = AgentStudioTraceRecord(
            timeUnixNano: 1_777_134_723_123_000_000,
            severityText: "INFO",
            body: "drag.update",
            traceID: "trace-1",
            spanID: "span-1",
            parentSpanID: "parent-1",
            resource: [
                "process.pid": "42",
                "service.name": "AgentStudio",
            ],
            scope: .init(name: "agentstudio.drag", version: "0.1.0"),
            attributes: [
                "agentstudio.trace.tag": .string("drag"),
                "drag.session_id": .string("drag-123"),
                "drag.update_count": .int(7),
                "drag.accepted": .bool(true),
                "drag.types": .stringArray(["public.file-url", "public.text"]),
            ]
        )

        let line = try AgentStudioJSONLTraceEncoder().encodeLine(record)

        #expect(line.hasSuffix("\n"))
        let data = try #require(line.dropLast().data(using: .utf8))
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect(object["time_unix_nano"] as? NSNumber == 1_777_134_723_123_000_000)
        #expect(object["severity_text"] as? String == "INFO")
        #expect(object["body"] as? String == "drag.update")
        #expect(object["trace_id"] as? String == "trace-1")
        #expect(object["span_id"] as? String == "span-1")
        #expect(object["parent_span_id"] as? String == "parent-1")

        let resource = try #require(object["resource"] as? [String: String])
        #expect(resource["service.name"] == "AgentStudio")
        #expect(resource["process.pid"] == "42")

        let scope = try #require(object["scope"] as? [String: String])
        #expect(scope["name"] == "agentstudio.drag")
        #expect(scope["version"] == "0.1.0")

        let attributes = try #require(object["attributes"] as? [String: Any])
        #expect(attributes["agentstudio.trace.tag"] as? String == "drag")
        #expect(attributes["drag.session_id"] as? String == "drag-123")
        #expect(attributes["drag.update_count"] as? NSNumber == 7)
        #expect(attributes["drag.accepted"] as? Bool == true)
        #expect(attributes["drag.types"] as? [String] == ["public.file-url", "public.text"])
    }

    @Test
    func encodeLineOmitsNilSpanIdentifiers() throws {
        let record = AgentStudioTraceRecord(
            timeUnixNano: 1,
            severityText: "INFO",
            body: "eventbus.post",
            traceID: nil,
            spanID: nil,
            parentSpanID: nil,
            resource: [:],
            scope: .init(name: "agentstudio.eventbus", version: "0.1.0"),
            attributes: [:]
        )

        let line = try AgentStudioJSONLTraceEncoder().encodeLine(record)
        let data = try #require(line.dropLast().data(using: .utf8))
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect(object["trace_id"] == nil)
        #expect(object["span_id"] == nil)
        #expect(object["parent_span_id"] == nil)
    }
}
