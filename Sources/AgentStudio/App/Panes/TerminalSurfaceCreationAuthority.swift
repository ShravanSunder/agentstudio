import AgentStudioCore

/// Proof that exactly one owner may create this pane's terminal surface now.
/// Only `PreparedTerminalMountAdmissionPort` and `ViewRegistry` can produce a
/// value, so no creation site can assert authority it was not granted.
///
/// There is no public initializer and no default value: a creation path that
/// skips the custody question does not compile.
@MainActor
enum TerminalSurfaceCreationAuthority: Equatable {
    // S2 adds .prepared(ClaimedTerminalAdmission)
    case released(PaneId)
}
