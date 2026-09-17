import AgentStudioAppIPC
import AgentStudioIPCTransport
import AgentStudioInfrastructure
import AgentStudioProgrammaticControl
import AgentStudioSessions
import CryptoKit
import Foundation
import Testing

@testable import AgentStudio
@testable import AgentStudioCore
@testable import AgentStudioTestSupport

/// One real socket, one real Sessions database. These cases exist to prove the
/// whole path: transport, authorization, canonical pane targeting, the App
/// adapter's mapping and the durable Sessions reduction underneath it.
@MainActor
@Suite("App IPC sessions vertical", .serialized)
struct AgentStudioIPCSessionsVerticalTests {
    init() { installTestCoreAtomsIfNeeded() }

    @Test("a qualified provider session start binds the pane and an unknown provider does not")
    func qualifiedSessionStartBindsThePane() async throws {
        let harness = try await SessionsVerticalHarness.make()
        defer { harness.tearDown() }

        let admitted = try await harness.sessionEvent(
            paneId: harness.boundPaneId,
            provider: SessionsVerticalHarness.qualifiedProvider,
            name: "sessionStart",
            conversationId: "conversation-bind"
        )
        #expect(admitted.disposition == .admitted)

        let unknown = try await harness.sessionEvent(
            paneId: harness.sparePaneId,
            provider: IPCSessionProviderIdentity(identifier: "never-shipped", version: "9.9.9", mode: "interactive"),
            name: "sessionStart",
            conversationId: "conversation-unknown"
        )
        #expect(unknown.disposition == .unknownCapability)

        #expect(try await harness.sessionQuery(paneId: harness.boundPaneId).sourceHealth == .live)
        #expect(try await harness.sessionQuery(paneId: harness.sparePaneId).sourceHealth == .unbound)
    }

    @Test("a needs-you report reaches the query as agent-reported state with a request identity")
    func needsYouReportReachesTheQuery() async throws {
        let harness = try await SessionsVerticalHarness.make()
        defer { harness.tearDown() }
        _ = try await harness.bindBoundPane()

        let report = try await harness.sessionReport(
            paneId: harness.boundPaneId,
            kind: "needsYou",
            explanation: "waiting on approval"
        )
        #expect(report.state == .needsYou)
        #expect(report.origin == .agentReported)
        let requestId = try #require(report.requestId)

        let queried = try await harness.sessionQuery(paneId: harness.boundPaneId)
        #expect(queried.state == .needsYou)
        #expect(queried.origin == .agentReported)
        #expect(queried.needsYou?.requestId == requestId)
        #expect(queried.needsYou?.explanation == "waiting on approval")
    }

    @Test("a done report reaches the query as agent-reported done")
    func doneReportReachesTheQuery() async throws {
        let harness = try await SessionsVerticalHarness.make()
        defer { harness.tearDown() }
        _ = try await harness.bindBoundPane()

        let report = try await harness.sessionReport(paneId: harness.boundPaneId, kind: "done", explanation: nil)
        #expect(report.state == .done)

        let queried = try await harness.sessionQuery(paneId: harness.boundPaneId)
        #expect(queried.state == .done)
        #expect(queried.origin == .agentReported)
        #expect(queried.needsYou == nil)
    }

    @Test("a message with Unicode and an embedded newline round-trips exactly")
    func messageTextRoundTripsExactly() async throws {
        let harness = try await SessionsVerticalHarness.make()
        defer { harness.tearDown() }
        _ = try await harness.bindBoundPane()
        let text = "migration \u{1F680} done\nsecond line \u{00E9}\u{4E2D}"

        let sent = try await harness.sessionMessage(paneId: harness.boundPaneId, text: text)
        #expect(sent.attributed)

        let queried = try await harness.sessionQuery(paneId: harness.boundPaneId)
        #expect(queried.messages.map(\.text) == [text])
        #expect(queried.messages.first?.seen == false)
        #expect(queried.messages.first?.occurrenceId == sent.occurrenceId)
    }

    @Test("the same message correlation sent twice stores one occurrence and returns the same result")
    func repeatedMessageCorrelationStoresOneOccurrence() async throws {
        let harness = try await SessionsVerticalHarness.make()
        defer { harness.tearDown() }
        _ = try await harness.bindBoundPane()
        let correlationId = UUIDv7.generate()

        let first = try await harness.sessionMessage(
            paneId: harness.boundPaneId, text: "only once", correlationId: correlationId
        )
        let second = try await harness.sessionMessage(
            paneId: harness.boundPaneId, text: "only once", correlationId: correlationId
        )

        #expect(first == second)
        #expect(try await harness.sessionQuery(paneId: harness.boundPaneId).messages.count == 1)
    }

    @Test("an unbound pane keeps a message durable and unattributed but refuses a deliberate report")
    func unboundPaneKeepsMessagesAndRefusesReports() async throws {
        let harness = try await SessionsVerticalHarness.make()
        defer { harness.tearDown() }

        let sent = try await harness.sessionMessage(paneId: harness.sparePaneId, text: "no binding yet")
        #expect(!sent.attributed)
        #expect(try await harness.sessionQuery(paneId: harness.sparePaneId).messages.map(\.text) == ["no binding yet"])

        let failure = try await harness.rawSessionReport(
            paneId: harness.sparePaneId, kind: "needsYou", explanation: "nobody home"
        )
        let errorData = try #require(failure.error?.data)
        guard case .object(let fields) = errorData, case .string(let reason)? = fields["reason"] else {
            Issue.record("an unbound deliberate report did not report a typed reason")
            return
        }
        #expect(reason == "bindingRequired")
    }
}
