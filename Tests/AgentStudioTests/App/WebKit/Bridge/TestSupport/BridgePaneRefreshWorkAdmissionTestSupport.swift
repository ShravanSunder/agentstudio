@testable import AgentStudioBridge

struct BridgePaneRefreshWorkAdmissionTestContext: Sendable {
    let admission: BridgePaneRefreshWorkAdmission
    let source: BridgePaneRefreshWorkAdmissionSource

    @MainActor
    static func foregroundOnMainActor() -> Self {
        let coordinator = BridgePaneRefreshAdmissionCoordinator(initialActivity: .foreground)
        guard let admission = coordinator.acquireForegroundWork() else {
            preconditionFailure("Foreground Bridge pane activity must admit test work")
        }
        return Self(
            admission: admission,
            source: coordinator.workAdmissionSource
        )
    }

    static func foreground() async -> Self {
        await foregroundOnMainActor()
    }
}
