import AgentStudioInfrastructure
import Foundation
import Testing

@testable import AgentStudioCore

@Suite("Darwin FSEvent ingress capacity")
struct DarwinFSEventIngressCapacityTests {
    @Test("production ingress retains one filesystem and activity batch for a real-size fleet")
    func productionIngressRetainsRealSizeFleetBurst() async {
        let ingressBuffer = DarwinFSEventIngressBuffer(
            capacity: AppPolicies.FilesystemIngress.bufferedFineBatchCapacity
        )
        let worktreeIds = (0..<148).map { _ in UUIDv7.generate() }

        for (eventIndex, worktreeId) in worktreeIds.enumerated() {
            ingressBuffer.yield(
                FSEventBatch(worktreeId: worktreeId, paths: ["Sources/Changed.swift"])
            )
            ingressBuffer.yieldActivityObservations(
                FSEventActivityObservationBatch(
                    participant: FSEventParticipant(
                        scopeKey: "worktree:\(worktreeId.uuidString)",
                        generation: 1,
                        volumeIdentifier: "1"
                    ),
                    processedThroughEventID: UInt64(eventIndex + 1),
                    participantWorktreeIds: [worktreeId],
                    qualifyingWorktreeIds: [worktreeId],
                    coverageLostWorktreeIds: []
                )
            )
        }
        ingressBuffer.finish()

        var retainedItemCount = 0
        for await _ in ingressBuffer.events() {
            retainedItemCount += 1
        }

        #expect(retainedItemCount == worktreeIds.count * 2)
        #expect(ingressBuffer.consumeOverflowRecoveries().isEmpty)
        #expect(ingressBuffer.consumeActivityOverflowRecoveries().isEmpty)
    }
}
