import AgentStudioCore
import AgentStudioTerminal

/// Proof that exactly one owner may create this pane's terminal surface now.
///
/// Every terminal-surface creation primitive requires a non-optional
/// `authority:` argument with no default value, so a call site cannot skip
/// the custody question by omission — it must obtain some value of this
/// type. Enum cases remain constructible anywhere in the module (Swift has
/// no case-level access control), so this type does not itself prevent a
/// caller from minting one; `PreparedContentMountStartupBoundaryTests`
/// scans the source for the only two legal producers,
/// `PreparedTerminalMountAdmissionPort` and `ViewRegistry`, and fails if a
/// third one appears.
@MainActor
enum TerminalSurfaceCreationAuthority: Equatable {
    /// Minted only by `PreparedTerminalMountAdmissionPort` after a successful
    /// `pending -> mounting` claim.
    case prepared(ClaimedTerminalAdmission)
    /// Returned only by `ViewRegistry` when the pane's custody is `completed`
    /// or absent.
    case released(PaneId)
}
