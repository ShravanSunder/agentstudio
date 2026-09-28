import Foundation

/// Bridge performs native file effects after the IPC layer has routed and,
/// for take-over, approved the request. Neither method can return declined.
/// Implementations validate and perform I/O off MainActor.
package protocol PaneAgentShowPort: Sendable {
    /// Opens in the inventory without page or focus work. Notification delivery
    /// is best-effort and cannot change an opened answer.
    /// Throws `.unavailable` if not dispatched; `.outcomeUnknown` if the
    /// inventory applied but its save was not confirmed.
    func openInBackground(
        receiver: PaneId, target: BridgeAgentShowTarget
    ) async throws(BridgeLinkPortFailure) -> BridgeAgentBackgroundOpenResult

    /// Called only after IPC approval; opens in background, then follows the
    /// ordinary human activation path. A draft refusal still returns opened.
    /// Throws `.unavailable` if not dispatched; `.outcomeUnknown` if the
    /// inventory applied but its save was not confirmed.
    func takeOver(
        receiver: PaneId, target: BridgeAgentShowTarget
    ) async throws(BridgeLinkPortFailure) -> BridgeAgentTakeOverResult
}
