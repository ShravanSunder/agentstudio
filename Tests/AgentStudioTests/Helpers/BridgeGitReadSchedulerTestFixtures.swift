import Foundation

@testable import AgentStudio

func makeBridgeGitReadContext(rootURL: URL) -> BridgeGitReadContext {
    let topology = BridgeGitReadSchedulerTopology(
        slotsByOperationClass: [
            .reviewMetadata: [
                BridgeGitReadSlotID(token: "test-review-metadata")
            ],
            .selectedVisibleContent: [
                BridgeGitReadSlotID(token: "test-selected-visible-content")
            ],
        ],
        maximumQueuedOperationCountByClass: [
            .reviewMetadata: 8,
            .selectedVisibleContent: 8,
        ],
        maximumLogicalWaiterCountPerOperation: 4
    )
    return BridgeGitReadContext(
        scheduler: BridgeGitReadScheduler(
            topology: topology,
            deadlineScheduler: BridgeGitReadManualDeadlineScheduler()
        ),
        worktreeKey: BridgeGitReadWorktreeKey(token: StableKey.fromPath(rootURL))
    )
}

func loadTestBridgeFileIgnorePolicy(rootURL: URL) async -> BridgeWorktreeFileIgnorePolicy {
    await BridgeWorktreeFileIgnorePolicy.load(
        rootURL: rootURL,
        gitReadContext: makeBridgeGitReadContext(rootURL: rootURL)
    )
}
