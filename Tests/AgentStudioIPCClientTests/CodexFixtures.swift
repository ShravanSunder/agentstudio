import Foundation
import Testing

@testable import AgentStudioIPCClientCore

/// Loads the schema-derived Codex hook payloads. The fixtures decode through
/// the real `CodexHookPayload`, so a field the projection reads but the payload
/// never carries fails here rather than in production.
enum CodexFixtures {
    static let sessionId = "01994d2f-8f1a-7c3b-9d44-2a6f5b8c1e07"
    static let turnId = "01994d30-1b22-7a55-8e91-4c7d0f2a6b13"

    enum FixtureError: Error {
        case missingFixture(String)
    }

    static func fileName(for eventName: CodexHookEventName) -> String {
        switch eventName {
        case .sessionStart: "session-start"
        case .sessionEnd: "session-end"
        case .userPromptSubmit: "user-prompt-submit"
        case .permissionRequest: "permission-request"
        case .preToolUse: "pre-tool-use"
        case .postToolUse: "post-tool-use"
        case .subagentStart: "subagent-start"
        case .subagentStop: "subagent-stop"
        case .stop: "stop"
        case .interrupt: "interrupt"
        case .preCompact: "pre-compact"
        case .postCompact: "post-compact"
        }
    }

    static func data(for eventName: CodexHookEventName) throws -> Data {
        let name = fileName(for: eventName)
        guard
            let url = Bundle.module.url(
                forResource: name, withExtension: "json", subdirectory: "Fixtures/codex-0.154")
        else {
            throw FixtureError.missingFixture(name)
        }
        return try Data(contentsOf: url)
    }

    static func payload(for eventName: CodexHookEventName) throws -> CodexHookPayload {
        try JSONDecoder().decode(CodexHookPayload.self, from: try data(for: eventName))
    }
}
