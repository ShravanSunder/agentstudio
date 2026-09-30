import AgentStudioPrimitives
import AgentStudioProgrammaticControl
import Foundation
import Testing

@testable import AgentStudioIPCClientCore

@Suite("Lifecycle hook report identity")
struct LifecycleHookReportIdentityTests {
    @Test(
        "Codex ends preserve present, missing and unknown reasons",
        arguments: ["exit", "other", "future-reason", nil]
    )
    func codexEndReasonIsLenient(rawReason: String?) throws {
        let payload = try codexPayload(event: .sessionEnd, rawReason: rawReason)
        let reportIdentifier = UUIDv7.generate()

        let projected = try #require(
            CodexHookProjection.project(
                eventName: .sessionEnd, payload: payload, reportIdentifier: reportIdentifier
            )
        )

        #expect(payload.reason == rawReason)
        #expect(projected.event.endReason == rawReason)
        #expect(projected.event.occurrenceId == reportIdentifier)
    }

    @Test(
        "Claude ends preserve present, missing and unknown reasons",
        arguments: ["prompt_input_exit", "clear", "logout", "other", "future-reason", nil]
    )
    func claudeEndReasonIsLenient(rawReason: String?) throws {
        let payload = try claudePayload(event: .sessionEnd, rawReason: rawReason)
        let reportIdentifier = UUIDv7.generate()

        let params = try projectedClaude(payload: payload, reportIdentifier: reportIdentifier)

        #expect(payload.reason == rawReason)
        #expect(params.event.endReason == rawReason)
        #expect(params.event.occurrenceId == reportIdentifier)
    }

    @Test(
        "each Codex lifecycle hook run uses its report id", arguments: [CodexHookEventName.sessionStart, .sessionEnd])
    func codexLifecycleOccurrenceIsReportIdentity(eventName: CodexHookEventName) throws {
        let payload = try codexPayload(event: eventName, rawReason: "other")
        let firstReport = UUIDv7.generate()
        let secondReport = UUIDv7.generate()

        let first = try #require(
            CodexHookProjection.project(
                eventName: eventName, payload: payload, reportIdentifier: firstReport
            ))
        let replay = try #require(
            CodexHookProjection.project(
                eventName: eventName, payload: payload, reportIdentifier: firstReport
            ))
        let nextRun = try #require(
            CodexHookProjection.project(
                eventName: eventName, payload: payload, reportIdentifier: secondReport
            ))

        #expect(first.event.occurrenceId == firstReport)
        #expect(replay == first)
        #expect(nextRun.event.occurrenceId == secondReport)
        #expect(first.event.endReason == (eventName == .sessionEnd ? "other" : nil))
    }

    @Test(
        "each Claude lifecycle run uses its report id even with a tool id",
        arguments: [ClaudeCodeHookEvent.sessionStart, .sessionEnd]
    )
    func claudeLifecycleOccurrenceIsReportIdentity(eventName: ClaudeCodeHookEvent) throws {
        let payload = try claudePayload(event: eventName, rawReason: "other")
        let firstReport = UUIDv7.generate()
        let secondReport = UUIDv7.generate()

        let first = try projectedClaude(payload: payload, reportIdentifier: firstReport)
        let replay = try projectedClaude(payload: payload, reportIdentifier: firstReport)
        let nextRun = try projectedClaude(payload: payload, reportIdentifier: secondReport)

        #expect(first.event.occurrenceId == firstReport)
        #expect(replay.event == first.event)
        #expect(nextRun.event.occurrenceId == secondReport)
        #expect(first.event.endReason == (eventName == .sessionEnd ? "other" : nil))
    }

    @Test(
        "every Codex activity hook keeps its derived occurrence and carries no end reason",
        arguments: CodexHookEventName.installedEvents.filter { $0 != .sessionStart && $0 != .sessionEnd }
    )
    func codexActivityIdentityIsUnchanged(eventName: CodexHookEventName) throws {
        let payload = try codexPayload(event: eventName, rawReason: "private reason")

        let first = try #require(
            CodexHookProjection.project(
                eventName: eventName, payload: payload, reportIdentifier: UUIDv7.generate()
            ))
        let second = try #require(
            CodexHookProjection.project(
                eventName: eventName, payload: payload, reportIdentifier: UUIDv7.generate()
            ))

        #expect(first.event == second.event)
        #expect(
            first.event.occurrenceId == CodexHookProjection.derivedIdentifier(eventName: eventName, payload: payload)
        )
        #expect(first.event.endReason == nil)
    }

    @Test(
        "every Claude activity hook keeps its existing occurrence and carries no end reason",
        arguments: ClaudeCodeHookEvent.allCases.filter { $0 != .sessionStart && $0 != .sessionEnd }
    )
    func claudeActivityIdentityIsUnchanged(eventName: ClaudeCodeHookEvent) throws {
        let payload = try claudePayload(event: eventName, rawReason: "private reason")

        let first = try projectedClaude(payload: payload, reportIdentifier: UUIDv7.generate())
        let second = try projectedClaude(payload: payload, reportIdentifier: UUIDv7.generate())
        let existingIdentity = ClaudeCodeHookOccurrenceIdentity.occurrenceIdentifier(
            sessionId: payload.sessionId, hookEventName: payload.hookEventName,
            toolUseId: payload.toolUseId, freshIdentifier: { UUIDv7.generate() }
        )

        #expect(first.event == second.event)
        #expect(first.event.occurrenceId == existingIdentity)
        #expect(first.event.endReason == nil)
    }

    @Test("an older CLI envelope without endReason still decodes")
    func oldEnvelopeDecodesWithoutReason() throws {
        let identifier = UUIDv7.generate()
        let document: [String: String] = [
            "name": "sessionEnd", "conversationId": identifier.uuidString,
            "occurrenceId": UUIDv7.generate().uuidString,
        ]

        let event = try JSONDecoder().decode(
            IPCSessionEventIdentity.self, from: JSONEncoder().encode(document)
        )

        #expect(event.endReason == nil)
        #expect(event.name == .sessionEnd)
    }

    @Test("endReason survives the ordinary wire round trip")
    func endReasonRoundTrips() throws {
        let payload = try codexPayload(event: .sessionEnd, rawReason: "future-reason")
        let projected = try #require(
            CodexHookProjection.project(
                eventName: .sessionEnd, payload: payload, reportIdentifier: UUIDv7.generate()
            ))

        let decoded = try JSONDecoder().decode(
            IPCSessionEventIdentity.self, from: JSONEncoder().encode(projected.event)
        )

        #expect(decoded == projected.event)
        #expect(decoded.endReason == "future-reason")
    }

    private func codexPayload(event: CodexHookEventName, rawReason: String?) throws -> CodexHookPayload {
        var document = hookDocument(eventName: event.rawValue, rawReason: rawReason)
        document["turn_id"] = "turn-one"
        document["tool_name"] = "shell"
        document["tool_use_id"] = "tool-one"
        document["agent_id"] = "agent-one"
        return try JSONDecoder().decode(CodexHookPayload.self, from: JSONEncoder().encode(document))
    }

    private func claudePayload(event: ClaudeCodeHookEvent, rawReason: String?) throws -> ClaudeCodeHookPayload {
        var document = hookDocument(eventName: event.rawValue, rawReason: rawReason)
        document["prompt_id"] = "turn-one"
        document["tool_use_id"] = "tool-one"
        document["agent_id"] = "agent-one"
        return try JSONDecoder().decode(ClaudeCodeHookPayload.self, from: JSONEncoder().encode(document))
    }

    private func hookDocument(eventName: String, rawReason: String?) -> [String: String] {
        var document = [
            "session_id": "019a0f45-0000-7000-8000-000000000001",
            "hook_event_name": eventName, "unknown_field": "ignored",
        ]
        document["reason"] = rawReason
        return document
    }

    private func projectedClaude(
        payload: ClaudeCodeHookPayload, reportIdentifier: UUID
    ) throws -> IPCSessionEventParams {
        let outcome = ClaudeCodeHookProjection.project(
            announcedEvent: payload.hookEventName, payload: payload,
            providerVersion: ClaudeCodeProviderIdentity.supportedExactVersion,
            correlationIdentifier: UUIDv7.generate(), freshOccurrenceIdentifier: { UUIDv7.generate() },
            reportIdentifier: reportIdentifier
        )
        guard case .projected(let params) = outcome else {
            throw ClaudeCodeHookInvocationError.reportRejected
        }
        return params
    }
}
