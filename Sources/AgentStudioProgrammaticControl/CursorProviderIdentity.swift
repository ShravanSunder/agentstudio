import Foundation

/// The wire identity Agent Studio recognises for the Cursor command-line
/// client. The hook projection in the bundled CLI and the Sessions provider
/// profile in the app both read these constants, so a rename can never leave
/// one side reporting an identity the other refuses.
///
/// `supportedExactVersion` is the Cursor CLI release this round's projection was
/// verified against. A hook installed against a different release reports that
/// release instead, which the Sessions registry treats as unqualified rather
/// than silently admitting unverified capabilities.
package enum CursorProviderIdentity {
    package static let identifier = "cursor-cli"

    /// `cursor-agent --version` self-updates past its launcher symlink, so this
    /// is the release every captured hook document reported in `cursor_version`,
    /// not the version directory the launcher points at.
    package static let supportedExactVersion = "2026.09.15-d2fe57e"

    /// Cursor's command-line client. Unlike Claude Code, the two CLI modes do
    /// not report the same events: an attended pane session reports turn
    /// boundaries and a `--print` run does not. The pane is the mode Agent
    /// Studio runs, so the operating mode names it rather than the union.
    package static let operatingMode = "cli"

    /// Lifecycle events this provider's hooks project. Everything else Cursor
    /// emits stays unprojected rather than mapping onto a nearby name.
    ///
    /// `permission` is deliberately absent. Cursor's permission-gating hooks ask
    /// the hook for a decision; none of them report that Cursor is waiting on
    /// the person. The CLI's own Claude-hook compatibility table maps
    /// `PermissionRequest` to `null`, so there is nothing to project onto.
    package static let projectedEventNames: Set<IPCSessionEventName> = [
        .sessionStart,
        .sessionEnd,
        .turnStart,
        .turnDone,
        .toolActivity,
        .subagentActivity,
    ]
}
