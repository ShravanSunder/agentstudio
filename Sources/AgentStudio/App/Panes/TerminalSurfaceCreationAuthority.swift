import AgentStudioCore
import AgentStudioTerminal

/// Proof that exactly one owner may create this pane's terminal surface now.
///
/// Every terminal-surface creation primitive requires a non-optional
/// `authority:` argument with no default value, so a call site cannot skip
/// the custody question by omission — it must obtain some value of this
/// type. Enum cases remain constructible anywhere in the module (Swift has
/// no case-level access control), so this type does not itself prevent a
/// caller from minting one; `PreparedContentMountStartupBoundaryTests`'s
/// `terminalSurfaceCreationAuthorityHasExactlyThreeProducers` test enforces
/// it instead, scanning the source for the only three legal producers and
/// failing if a fourth appears:
/// - `PreparedTerminalMountAdmissionPort`, after a successful
///   `pending -> mounting` claim.
/// - `ViewRegistry`, when the pane's custody is `completed` or absent.
/// - `WorkspaceSurfaceCoordinator`'s pre-boot fallback, when no accepted
///   composition generation exists yet: no cohort has been installed, so no
///   cohort could possibly be waiting to claim the pane, matching
///   `ViewRegistry`'s own "no entry, or a stale generation" release rule.
@MainActor
enum TerminalSurfaceCreationAuthority: Equatable {
    /// Minted only by `PreparedTerminalMountAdmissionPort` after a successful
    /// `pending -> mounting` claim.
    case prepared(ClaimedTerminalAdmission)
    /// Returned only by `ViewRegistry` when the pane's custody is `completed`
    /// or absent, or by `WorkspaceSurfaceCoordinator`'s pre-boot fallback
    /// when no accepted composition generation exists yet.
    case released(PaneId)
}
