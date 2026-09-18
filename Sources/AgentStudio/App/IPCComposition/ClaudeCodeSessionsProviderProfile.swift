import AgentStudioProgrammaticControl
import AgentStudioSessions
import Foundation

extension SessionsProviderProfile {
    /// The Claude Code release whose hook events this repository has verified
    /// end to end. Capabilities are listed only where a projected hook event
    /// exists: turn abort, question and elicitation stay unqualified because
    /// Claude Code 2.1.274 reports no event this package projects onto them.
    package static let claudeCodeCommandLine = Self(
        providerIdentifier: ClaudeCodeProviderIdentity.identifier,
        exactVersion: ClaudeCodeProviderIdentity.supportedExactVersion,
        operatingMode: ClaudeCodeProviderIdentity.operatingMode,
        qualifiedCapabilities: [
            .sessionStart,
            .sessionEnd,
            .turnStart,
            .turnDone,
            .permission,
            .toolActivity,
            .subagentActivity,
        ]
    )
}
