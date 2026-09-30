import AgentStudioIPCClientCore
import AgentStudioInfrastructure
import AgentStudioProgrammaticControl
import AgentStudioSessions
import Foundation
import Testing

@testable import AgentStudio
@testable import AgentStudioCore

@MainActor
@Suite("App IPC lifecycle end fact", .serialized, SessionsVerticalHarnessTrait(providerProfiles: .shipped))
struct AgentStudioIPCLifecycleEndFactTests {
    @Test(
        "a projected provider end reaches its binding with reason classification and exact text",
        arguments: [
            ("claude-code", "prompt_input_exit", ProviderEndReason.personExit),
            ("claude-code", "clear", .providerOther),
            ("codex", "exit", .personExit),
            ("codex", "other", .providerOther),
            ("codex", "private future reason", .unrecognized),
        ]
    )
    func projectedEndReachesBinding(
        providerIdentifier: String, rawReason: String, expected: ProviderEndReason
    ) async throws {
        let harness = try await #require(SessionsVerticalHarnessContext.current).freshPanePair()
        let paneId = harness.boundPaneId
        let sessionId = UUIDv7.generate().uuidString
        let start = try lifecycleParams(
            providerIdentifier: providerIdentifier, eventName: "SessionStart", sessionId: sessionId,
            rawReason: nil, paneId: paneId
        )
        #expect(try await harness.sessionEvent(params: start).disposition == .admitted)

        let end = try lifecycleParams(
            providerIdentifier: providerIdentifier, eventName: "SessionEnd", sessionId: sessionId,
            rawReason: rawReason, paneId: paneId
        )
        #expect(try await harness.sessionEvent(params: end).disposition == .admitted)

        let snapshot = try await harness.paneSnapshot(paneId: paneId)
        let binding = try #require(snapshot.currentBinding)
        #expect(binding.providerEndReason == expected)
        #expect(binding.providerEndReasonText == rawReason)
        #expect(binding.providerEndedAt != nil)
        #expect(binding.providerConversationId == sessionId)
        #expect(binding.status == .ended)
    }

    @Test("an end from an older CLI without a reason remains a reported end")
    func missingReasonReachesBinding() async throws {
        let harness = try await #require(SessionsVerticalHarnessContext.current).freshPanePair()
        let paneId = harness.boundPaneId
        let sessionId = UUIDv7.generate().uuidString
        let start = try lifecycleParams(
            providerIdentifier: "codex", eventName: "SessionStart", sessionId: sessionId,
            rawReason: nil, paneId: paneId
        )
        _ = try await harness.sessionEvent(params: start)

        let end = try lifecycleParams(
            providerIdentifier: "codex", eventName: "SessionEnd", sessionId: sessionId,
            rawReason: nil, paneId: paneId
        )
        #expect(try await harness.sessionEvent(params: end).disposition == .admitted)

        let snapshot = try await harness.paneSnapshot(paneId: paneId)
        let binding = try #require(snapshot.currentBinding)
        #expect(binding.providerEndReason == .notGiven)
        #expect(binding.providerEndReasonText == nil)
        #expect(binding.providerEndedAt != nil)
    }

    @Test("a projected provider end after the launch sweep still records the end")
    func projectedEndAfterSweepReachesBinding() async throws {
        let harness = try await #require(SessionsVerticalHarnessContext.current).freshPanePair()
        let paneId = harness.boundPaneId
        let sessionId = UUIDv7.generate().uuidString
        let start = try lifecycleParams(
            providerIdentifier: "codex", eventName: "SessionStart", sessionId: sessionId,
            rawReason: nil, paneId: paneId
        )
        _ = try await harness.sessionEvent(params: start)
        let ingestion = try #require(harness.appDelegate.appIPCSessionsIngestion)
        _ = try await ingestion.prepareForLaunch(at: Date(timeIntervalSince1970: 2))

        let end = try lifecycleParams(
            providerIdentifier: "codex", eventName: "SessionEnd", sessionId: sessionId,
            rawReason: "exit", paneId: paneId
        )
        #expect(try await harness.sessionEvent(params: end).disposition == .admitted)

        let snapshot = try await harness.paneSnapshot(paneId: paneId)
        let binding = try #require(snapshot.currentBinding)
        #expect(binding.providerEndReason == .personExit)
        #expect(binding.providerEndReasonText == "exit")
        #expect(binding.providerEndedAt != nil)
    }

    @Test("Claude clear ends the old binding and a fresh start binds the new exact session id")
    func clearRebindsExactSession() async throws {
        let harness = try await #require(SessionsVerticalHarnessContext.current).freshPanePair()
        let paneId = harness.boundPaneId
        let oldSessionId = UUIDv7.generate().uuidString
        let newSessionId = UUIDv7.generate().uuidString
        let oldStart = try lifecycleParams(
            providerIdentifier: "claude-code", eventName: "SessionStart", sessionId: oldSessionId,
            rawReason: nil, paneId: paneId
        )
        _ = try await harness.sessionEvent(params: oldStart)
        let clearEnd = try lifecycleParams(
            providerIdentifier: "claude-code", eventName: "SessionEnd", sessionId: oldSessionId,
            rawReason: "clear", paneId: paneId
        )
        _ = try await harness.sessionEvent(params: clearEnd)
        let endedSnapshot = try await harness.paneSnapshot(paneId: paneId)
        let oldBinding = try #require(endedSnapshot.currentBinding)
        #expect(oldBinding.providerEndReason == .providerOther)
        #expect(oldBinding.providerEndReasonText == "clear")

        let newStart = try lifecycleParams(
            providerIdentifier: "claude-code", eventName: "SessionStart", sessionId: newSessionId,
            rawReason: nil, paneId: paneId
        )
        #expect(try await harness.sessionEvent(params: newStart).disposition == .admitted)

        let reboundSnapshot = try await harness.paneSnapshot(paneId: paneId)
        let newBinding = try #require(reboundSnapshot.currentBinding)
        #expect(newBinding.providerConversationId == newSessionId)
        #expect(newBinding.sourceGenerationId != oldBinding.sourceGenerationId)
        #expect(newBinding.providerEndedAt == nil)
        #expect(newBinding.providerEndReason == nil)
        #expect(newBinding.status == .active)
    }

    private func lifecycleParams(
        providerIdentifier: String, eventName: String, sessionId: String, rawReason: String?, paneId: UUID
    ) throws -> IPCSessionEventParams {
        var document = ["session_id": sessionId, "hook_event_name": eventName]
        document["reason"] = rawReason
        let data = try JSONEncoder().encode(document)
        let correlationId = UUIDv7.generate()
        let reportIdentifier = UUIDv7.generate()
        let provider: IPCSessionProviderIdentity
        let event: IPCSessionEventIdentity
        if providerIdentifier == "codex" {
            let payload = try JSONDecoder().decode(CodexHookPayload.self, from: data)
            let projected = try #require(
                CodexHookProjection.project(
                    eventName: try #require(CodexHookEventName(rawValue: eventName)),
                    payload: payload, reportIdentifier: reportIdentifier
                ))
            provider = projected.provider
            event = projected.event
        } else {
            let payload = try JSONDecoder().decode(ClaudeCodeHookPayload.self, from: data)
            let outcome = ClaudeCodeHookProjection.project(
                announcedEvent: eventName, payload: payload,
                providerVersion: ClaudeCodeProviderIdentity.supportedExactVersion,
                correlationIdentifier: correlationId, freshOccurrenceIdentifier: { UUIDv7.generate() },
                reportIdentifier: reportIdentifier
            )
            guard case .projected(let params) = outcome else {
                throw ClaudeCodeHookInvocationError.reportRejected
            }
            provider = params.provider
            event = params.event
        }
        return IPCSessionEventParams(
            handle: paneId.uuidString, provider: provider, event: event, correlationId: correlationId
        )
    }
}
