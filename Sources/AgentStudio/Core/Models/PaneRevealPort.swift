import Foundation

/// One agent request produces one answer. Background opens the file without
/// page or focus work. Take-over is called only after the IPC layer's human
/// approval; it opens in the background, then runs the human activation path.
/// The port never asks for approval and never returns `declined`.
/// Implementations validate and perform I/O off MainActor.
package protocol PaneRevealPort: Sendable {
    func show(
        receiver: PaneId, target: BridgeRevealFileTarget, mode: BridgeAgentShowMode
    ) async throws(BridgeLinkPortFailure) -> BridgeAgentShowResult
}
