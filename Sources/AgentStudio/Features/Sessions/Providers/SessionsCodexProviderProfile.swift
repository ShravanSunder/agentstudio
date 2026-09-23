import Foundation

/// The provider profiles Agent Studio qualifies out of the box.
///
/// A profile is an exact claim: this provider, at this version, in this mode,
/// reports these capabilities well enough for Sessions to treat its events as
/// provider-reported truth. A nearby version is not a match, because a provider
/// that changed its hook payload changed what the evidence means.
extension SessionsProviderProfile {
    /// Codex CLI, driven by the hooks the Agent Studio package installs.
    ///
    /// The version is exact because Codex 0.154.0 reports no version of its own
    /// in a hook payload (`codex-rs/hooks/src/schema.rs`), so the projection
    /// sends this one. Raising it means re-verifying the hook payload shape.
    ///
    /// The capabilities are exactly the ones the installed hooks can report.
    /// `question` and `elicitation` are absent: Codex has no hook event for
    /// either, so claiming them would qualify evidence that never arrives.
    package static let codexCommandLine = SessionsProviderProfile(
        providerIdentifier: "codex",
        exactVersion: "0.154.0",
        operatingMode: "cli",
        qualifiedCapabilities: [
            .sessionStart,
            .sessionEnd,
            .turnStart,
            .turnDone,
            .turnAbort,
            .permission,
            .toolActivity,
            .subagentActivity,
        ]
    )

    /// Every provider profile shipped with the app.
    package static let shippedProfiles: [SessionsProviderProfile] = [.codexCommandLine]
}
