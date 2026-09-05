import AgentStudioCore
import AgentStudioTerminal

/// Proof that exactly one owner may create this pane's terminal surface now.
/// Only `PreparedTerminalMountAdmissionPort` and `ViewRegistry` can produce a
/// value, so no creation site can assert authority it was not granted.
///
/// There is no public initializer and no default value: a creation path that
/// skips the custody question does not compile.
@MainActor
enum TerminalSurfaceCreationAuthority: Equatable {
    /// Minted only by `PreparedTerminalMountAdmissionPort` after a successful
    /// `pending -> mounting` claim.
    case prepared(ClaimedTerminalAdmission)
    /// Returned only by `ViewRegistry` when the pane's custody is `completed`
    /// or absent.
    case released(PaneId)
}
