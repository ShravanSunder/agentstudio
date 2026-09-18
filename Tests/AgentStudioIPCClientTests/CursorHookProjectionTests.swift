import Foundation
import Testing

@testable import AgentStudioIPCClientCore
@testable import AgentStudioProgrammaticControl

/// Loads the recorded and schema-derived Cursor hook documents next to this
/// suite. See `Fixtures/cursor-2026.09.15/README.md` for their provenance.
enum CursorHookFixture {
    static func payload(_ event: String, file: String = #filePath) throws -> CursorHookPayload {
        try JSONDecoder().decode(CursorHookPayload.self, from: try data(event, file: file))
    }

    static func data(_ event: String, file: String = #filePath) throws -> Data {
        try Data(contentsOf: directory(file: file).appending(path: "\(event).json"))
    }

    static func directory(file: String = #filePath) -> URL {
        URL(fileURLWithPath: file)
            .deletingLastPathComponent()
            .appending(path: "Fixtures/cursor-2026.09.15")
    }
}

/// One fixed identifier, so a projection difference is never a fresh UUID.
private let cursorFixtureIdentifier = UUID(uuidString: "00000000-0000-4000-8000-000000000002")!

/// The values the fixtures carry, named once so a test reads as a claim about
/// behaviour rather than a string comparison.
private enum CursorFixtureIdentity {
    static let conversation = "11111111-2222-4333-8444-555555555555"
    static let turn = "e3827ee0-ea14-49ba-b19f-2bde9cee5b1a"
    static let version = "2026.09.15-d2fe57e"
}

@Suite("Cursor hook projection")
struct CursorHookProjectionTests {
    private static let stableIdentifier = cursorFixtureIdentifier

    private func project(
        _ event: String,
        freshOccurrenceIdentifier: () -> UUID = { cursorFixtureIdentifier }
    ) throws -> CursorHookProjectionOutcome {
        CursorHookProjection.project(
            announcedEvent: event,
            payload: try CursorHookFixture.payload(event),
            providerVersion: CursorFixtureIdentity.version,
            correlationIdentifier: Self.stableIdentifier,
            freshOccurrenceIdentifier: freshOccurrenceIdentifier
        )
    }

    private func projectedParams(_ event: String) throws -> IPCSessionEventParams {
        guard case .projected(let params) = try project(event) else {
            Issue.record("\(event) did not project")
            throw CursorHookInvocationError.reportRejected
        }
        return params
    }

    @Test("Each installed hook event projects its lifecycle capability")
    func projectsEveryInstalledEvent() throws {
        // Arrange
        let expected: [String: IPCSessionEventName] = [
            "sessionStart": .sessionStart,
            "beforeSubmitPrompt": .turnStart,
            "preToolUse": .toolActivity,
            "subagentStart": .subagentActivity,
            "subagentStop": .subagentActivity,
            "stop": .turnDone,
            "sessionEnd": .sessionEnd,
        ]

        // Act
        let projected = try expected.keys.map { try ($0, projectedParams($0)) }

        // Assert
        #expect(Set(expected.keys) == Set(CursorHookEvent.allCases.map(\.rawValue)))
        for (event, params) in projected {
            #expect(params.event.name == expected[event])
            #expect(params.handle == "self")
            #expect(params.provider.identifier == "cursor-cli")
            #expect(params.provider.version == CursorFixtureIdentity.version)
            #expect(params.provider.mode == CursorProviderIdentity.operatingMode)
            #expect(params.event.conversationId == CursorFixtureIdentity.conversation)
            #expect(CursorProviderIdentity.projectedEventNames.contains(params.event.name))
        }
    }

    @Test("Cursor reports no permission event, so nothing projects onto one")
    func noEventProjectsAPermission() throws {
        // Arrange / Act
        let projected = try CursorHookEvent.allCases.map { try projectedParams($0.rawValue) }

        // Assert
        #expect(projected.allSatisfy { $0.event.name != .permission })
        #expect(projected.allSatisfy { $0.event.requestId == nil })
        #expect(!CursorProviderIdentity.projectedEventNames.contains(.permission))
    }

    @Test("Turn start and turn done report the same turn, so a turn can record a result")
    func turnBoundariesShareOneTurnIdentifier() throws {
        // Arrange / Act
        let turnStart = try projectedParams("beforeSubmitPrompt")
        let turnDone = try projectedParams("stop")

        // Assert
        #expect(turnStart.event.turnId == CursorFixtureIdentity.turn)
        #expect(turnDone.event.turnId == CursorFixtureIdentity.turn)
        #expect(turnDone.event.turnId != turnDone.event.conversationId)
    }

    @Test("A generation that merely echoes the conversation is not reported as a turn")
    func echoedGenerationIsNotATurn() throws {
        // Arrange: Cursor fills `generation_id` with the conversation's own
        // identifier on every event that does not belong to a turn.
        let echoing = ["sessionStart", "sessionEnd", "preToolUse"]

        // Act
        let projected = try echoing.map { try projectedParams($0) }

        // Assert
        #expect(projected.allSatisfy { $0.event.turnId == nil })
        for event in echoing {
            let payload = try CursorHookFixture.payload(event)
            #expect(payload.generationId == payload.conversationId)
        }
    }

    @Test("Tool and subagent activity carry their own subject identity")
    func subjectIdentitiesStaySeparate() throws {
        // Arrange / Act
        let tool = try projectedParams("preToolUse")
        let subagent = try projectedParams("subagentStop")

        // Assert
        #expect(tool.event.toolId == (try CursorHookFixture.payload("preToolUse").toolUseId))
        #expect(tool.event.subagentId == nil)
        #expect(subagent.event.subagentId == "subagent-8f1c2d34")
        #expect(subagent.event.toolId == nil)
    }

    @Test("A tool invocation identifier makes the occurrence identity deterministic")
    func occurrenceIsDeterministicWithToolUseIdentifier() throws {
        // Arrange
        var freshCallCount = 0
        let fresh: () -> UUID = {
            freshCallCount += 1
            return UUID()
        }

        // Act
        guard case .projected(let first) = try project("preToolUse", freshOccurrenceIdentifier: fresh),
            case .projected(let second) = try project("preToolUse", freshOccurrenceIdentifier: fresh)
        else {
            Issue.record("preToolUse did not project")
            return
        }

        // Assert
        #expect(first.event.occurrenceId == second.event.occurrenceId)
        #expect(freshCallCount == 0)
        // RFC 4122 version 5: version nibble 5, variant bits 10.
        #expect(first.event.occurrenceId.uuidString.split(separator: "-")[2].first == "5")
    }

    @Test("Two tools sharing one Cursor tool-use identifier stay separate occurrences")
    func toolNameSeparatesOneSharedToolUseIdentifier() throws {
        // Arrange: Cursor issues one `tool_use_id` per assistant-message chunk,
        // so two different tools in one message arrive carrying the same value.
        let shared = try CursorHookFixture.payload("preToolUse")
        let otherTool = CursorHookPayload(
            conversationId: shared.conversationId,
            hookEventName: shared.hookEventName,
            generationId: shared.generationId,
            toolName: "Read",
            toolUseId: shared.toolUseId,
            subagentId: nil
        )

        // Act
        let write = try projectedParams("preToolUse")
        let read = CursorHookProjection.project(
            announcedEvent: "preToolUse",
            payload: otherTool,
            providerVersion: CursorFixtureIdentity.version,
            correlationIdentifier: Self.stableIdentifier,
            freshOccurrenceIdentifier: { Self.stableIdentifier }
        )

        // Assert
        guard case .projected(let readParams) = read else {
            Issue.record("preToolUse did not project")
            return
        }
        #expect(shared.toolName == "Write")
        #expect(write.event.occurrenceId != readParams.event.occurrenceId)
    }

    @Test("Without a natural key each occurrence is freshly generated")
    func occurrenceIsFreshWithoutNaturalKey() throws {
        // Arrange
        var issued: [UUID] = []
        let fresh: () -> UUID = {
            let identifier = UUID()
            issued.append(identifier)
            return identifier
        }

        // Act
        guard case .projected(let first) = try project("stop", freshOccurrenceIdentifier: fresh),
            case .projected(let second) = try project("stop", freshOccurrenceIdentifier: fresh)
        else {
            Issue.record("stop did not project")
            return
        }

        // Assert
        #expect(first.event.occurrenceId != second.event.occurrenceId)
        #expect(issued == [first.event.occurrenceId, second.event.occurrenceId])
    }

    @Test("Unprojected Cursor events produce no call")
    func unprojectedEventsAreRefused() throws {
        // Arrange / Act
        let postToolUse = try project("postToolUse")
        let afterAgentResponse = try project("afterAgentResponse")

        // Assert
        #expect(postToolUse == .refused(.unprojectedEvent("postToolUse")))
        #expect(afterAgentResponse == .refused(.unprojectedEvent("afterAgentResponse")))
    }

    @Test("A hook document disagreeing with its announced event is refused")
    func announcedEventMismatchIsRefused() throws {
        // Arrange
        let payload = try CursorHookFixture.payload("stop")

        // Act
        let outcome = CursorHookProjection.project(
            announcedEvent: "sessionEnd",
            payload: payload,
            providerVersion: CursorFixtureIdentity.version,
            correlationIdentifier: Self.stableIdentifier,
            freshOccurrenceIdentifier: { Self.stableIdentifier }
        )

        // Assert
        #expect(outcome == .refused(.announcedEventMismatch(announced: "sessionEnd", reported: "stop")))
    }
}

@Suite("Cursor hook invocation")
struct CursorHookInvocationTests {
    private func inputs(
        arguments: [String],
        environment: [String: String],
        standardInput: @escaping () throws -> Data = { Data() },
        diagnostics: @escaping (String) -> Void = { _ in }
    ) -> CursorHookInvocationInputs {
        CursorHookInvocationInputs(
            arguments: arguments,
            environment: environment,
            standardInput: standardInput,
            identifierGenerator: { UUID() },
            diagnosticSink: diagnostics
        )
    }

    @Test("Arguments for another command are not claimed")
    func unrelatedArgumentsAreNotClaimed() {
        // Arrange / Act
        let outcome = CursorHookInvocation.handle(
            inputs(arguments: ["session.query"], environment: [:])
        )

        // Assert
        #expect(outcome == nil)
    }

    @Test("Another provider's hook is left to its own router")
    func claudeHookIsNotClaimed() {
        // Arrange / Act
        let outcome = CursorHookInvocation.handle(
            inputs(arguments: ["hook", "claude", "SessionStart"], environment: [:])
        )

        // Assert
        #expect(outcome == nil)
    }

    @Test("Outside an Agent Studio pane the hook exits silently without reading stdin")
    func environmentGuardExitsSilently() throws {
        // Arrange
        var standardInputReads = 0
        var diagnostics: [String] = []
        let guarded = inputs(
            arguments: ["hook", "cursor", "sessionStart"],
            environment: ["AGENTSTUDIO_PANE_TOKEN": "token"],
            standardInput: {
                standardInputReads += 1
                return try CursorHookFixture.data("sessionStart")
            },
            diagnostics: { diagnostics.append($0) }
        )

        // Act
        let outcome = CursorHookInvocation.handle(guarded)

        // Assert
        #expect(outcome == 0)
        #expect(standardInputReads == 0)
        #expect(diagnostics.isEmpty)
    }

    @Test("A pane without a credential exits silently")
    func missingPaneTokenExitsSilently() {
        // Arrange
        var diagnostics: [String] = []
        let guarded = inputs(
            arguments: ["hook", "cursor", "sessionStart"],
            environment: ["AGENTSTUDIO_CLI": "/tmp/agentstudio"],
            diagnostics: { diagnostics.append($0) }
        )

        // Act
        let outcome = CursorHookInvocation.handle(guarded)

        // Assert
        #expect(outcome == 0)
        #expect(diagnostics.isEmpty)
    }

    @Test("An unreachable app reports one line on stderr and still exits zero")
    func unreachableAppStillExitsZero() throws {
        // Arrange
        var diagnostics: [String] = []
        let unreachable = inputs(
            arguments: ["hook", "cursor", "sessionStart", "--provider-version", "2026.09.15-d2fe57e"],
            environment: [
                "AGENTSTUDIO_CLI": "/tmp/agentstudio",
                "AGENTSTUDIO_PANE_TOKEN": "token",
                "AGENTSTUDIO_IPC_SOCKET": FileManager.default.temporaryDirectory
                    .appending(path: "agentstudio-absent-\(UUID().uuidString).sock").path,
            ],
            standardInput: { try CursorHookFixture.data("sessionStart") },
            diagnostics: { diagnostics.append($0) }
        )

        // Act
        let outcome = CursorHookInvocation.handle(unreachable)

        // Assert
        #expect(outcome == 0)
        #expect(diagnostics == ["agentstudio hook cursor: sessionStart not reported"])
    }

    @Test("A malformed hook document reports one line and never echoes its content")
    func malformedDocumentIsNotEchoed() {
        // Arrange
        var diagnostics: [String] = []
        let malformed = inputs(
            arguments: ["hook", "cursor", "stop"],
            environment: [
                "AGENTSTUDIO_CLI": "/tmp/agentstudio",
                "AGENTSTUDIO_PANE_TOKEN": "token",
                "AGENTSTUDIO_IPC_SOCKET": "/tmp/agentstudio-absent.sock",
            ],
            standardInput: { Data(#"{"secret":"do not echo"}"#.utf8) },
            diagnostics: { diagnostics.append($0) }
        )

        // Act
        let outcome = CursorHookInvocation.handle(malformed)

        // Assert
        #expect(outcome == 0)
        #expect(diagnostics == ["agentstudio hook cursor: stop not reported"])
        #expect(diagnostics.allSatisfy { !$0.contains("do not echo") })
    }

    @Test("An unprojected event submits nothing and still exits zero")
    func unprojectedEventSubmitsNothing() throws {
        // Arrange: reaching the socket would fail, so a silent exit with no
        // diagnostic is the only outcome that proves nothing was submitted.
        var diagnostics: [String] = []
        let unprojected = inputs(
            arguments: ["hook", "cursor", "postToolUse"],
            environment: [
                "AGENTSTUDIO_CLI": "/tmp/agentstudio",
                "AGENTSTUDIO_PANE_TOKEN": "token",
                "AGENTSTUDIO_IPC_SOCKET": "/tmp/agentstudio-absent.sock",
            ],
            standardInput: { try CursorHookFixture.data("postToolUse") },
            diagnostics: { diagnostics.append($0) }
        )

        // Act
        let outcome = CursorHookInvocation.handle(unprojected)

        // Assert
        #expect(outcome == 0)
        #expect(diagnostics.isEmpty)
    }
}

@Suite("Cursor installed version")
struct CursorInstalledVersionTests {
    @Test("A calendar build with a hex suffix parses")
    func calendarBuildParses() {
        // Arrange / Act / Assert
        #expect(CursorInstalledVersion.parsedVersion("2026.09.15-d2fe57e\n") == "2026.09.15-d2fe57e")
    }

    @Test("Output that is not a bare version is refused rather than guessed at")
    func prosePrefixIsRefused() {
        // Arrange / Act / Assert
        #expect(CursorInstalledVersion.parsedVersion("cursor-agent version 1.2\n") == nil)
        #expect(CursorInstalledVersion.parsedVersion("") == nil)
    }
}
