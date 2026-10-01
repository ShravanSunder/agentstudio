import AgentStudioProgrammaticControl
import AgentStudioSessions
import Foundation

extension SessionsProviderProfile {
    /// The Claude Code release whose hook events this repository has verified
    /// end to end. Capabilities are listed only where a projected hook event
    /// exists in the recorded 2.1.286 payloads. Silent interrupts stay unqualified.
    package static let claudeCodeCommandLine = Self(
        providerIdentifier: ClaudeCodeProviderIdentity.identifier,
        exactVersion: ClaudeCodeProviderIdentity.supportedExactVersion,
        operatingMode: ClaudeCodeProviderIdentity.operatingMode,
        qualifiedCapabilities: [
            .sessionStart,
            .sessionEnd,
            .turnStart,
            .turnDone,
            .turnFailed,
            .permission,
            .toolActivity,
            .subagentActivity,
            .question,
            .elicitation,
            .elicitationResult,
            .toolCompleted,
            .toolFailed,
        ]
    )
}
