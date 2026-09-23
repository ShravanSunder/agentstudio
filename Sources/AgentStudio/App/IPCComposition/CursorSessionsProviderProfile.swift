import AgentStudioProgrammaticControl
import AgentStudioSessions
import Foundation

extension SessionsProviderProfile {
    /// The Cursor CLI release whose hook events this repository has verified end
    /// to end. Capabilities are listed only where a projected hook event exists.
    ///
    /// `permission` is absent, unlike Claude Code: Cursor reports no event that
    /// asks the person for a decision. Its permission-gating hooks ask the hook
    /// process, and the CLI's own Claude-hook compatibility table maps
    /// `PermissionRequest` onto nothing. Turn abort, question and elicitation
    /// stay unqualified for the same reason.
    package static let cursorCommandLine = Self(
        providerIdentifier: CursorProviderIdentity.identifier,
        exactVersion: CursorProviderIdentity.supportedExactVersion,
        operatingMode: CursorProviderIdentity.operatingMode,
        qualifiedCapabilities: [
            .sessionStart,
            .sessionEnd,
            .turnStart,
            .turnDone,
            .toolActivity,
            .subagentActivity,
        ]
    )
}
