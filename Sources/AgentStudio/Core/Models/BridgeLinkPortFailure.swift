/// Shared failures outside the pane-link and agent-show result unions.
///
/// `unavailable` means the mutation was not dispatched and had no effect.
/// `outcomeUnknown` means a commit was dispatched but its durable result could
/// not be established. Link mutations are idempotent, so callers may retry.
package enum BridgeLinkPortFailure: Error, Equatable, Sendable {
    case unavailable
    case outcomeUnknown
}
