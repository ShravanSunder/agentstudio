import AgentStudioCore
import AgentStudioSharedComponents

/// The host retains the last ask; nil/notices and hidden/sidebar hosts never consume it.
enum PaneContextPopoverAutoOpenPolicy {
    static func shouldOpen(
        newestAskId: AgentMessageId?, lastPresentedAskId: AgentMessageId?,
        isVisible: Bool, location: PaneContextPopoverLocation
    ) -> Bool {
        isVisible && location == .pane && newestAskId != nil && newestAskId != lastPresentedAskId
    }
}
