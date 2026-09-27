import Foundation

/// One agent request produces one answer. Background opens the file without
/// page or focus work; take-over uses IPC human approval, then human activation.
/// Implementations validate and perform I/O off MainActor.
package protocol PaneRevealPort: Sendable {
    func show(
        receiver: PaneId, target: BridgeRevealFileTarget, mode: BridgeAgentShowMode
    ) async throws(BridgeLinkPortFailure) -> BridgeAgentShowResult
}
