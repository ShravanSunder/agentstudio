import CoreServices
import Foundation

struct DarwinSharedExactItemActivityBarrierSnapshot {
    let barrier: FSEventActivityBarrier
    let topologyRevision: UInt64
}

extension DarwinSharedExactItemObserverRegistry {
    func captureActivityBarrier() -> FSEventActivityBarrier? {
        captureActivityBarrierSnapshot()?.barrier
    }

    func captureActivityBarrierSnapshot() -> DarwinSharedExactItemActivityBarrierSnapshot? {
        let retainedParticipants = lifecycleCondition.withLock {
            () -> (UInt64, [(DarwinSharedExactItemParentKey, UInt64, any DarwinSharedExactItemStreamLifetime)])? in
            guard !hasShutdown else { return nil }
            let participants:
                [(
                    DarwinSharedExactItemParentKey,
                    UInt64,
                    any DarwinSharedExactItemStreamLifetime
                )] = observerByParent.keys.sorted(by: Self.sortParentKeys).compactMap { parentKey in
                    guard let observer = observerByParent[parentKey] else { return nil }
                    return (parentKey, observer.generation, observer.streamLifetime)
                }
            return (activityTopologyRevision, participants)
        }
        guard let (capturedTopologyRevision, retainedParticipants) = retainedParticipants else {
            return nil
        }
        for (_, _, streamLifetime) in retainedParticipants {
            guard streamLifetime.flush() else { return nil }
        }

        return lifecycleCondition.withLock { () -> DarwinSharedExactItemActivityBarrierSnapshot? in
            guard !hasShutdown else { return nil }
            var bindings: [FSEventParticipantBinding] = []
            var deliveredEventIDByParticipant: [FSEventParticipant: UInt64] = [:]
            for (parentKey, generation, _) in retainedParticipants {
                guard
                    let observer = observerByParent[parentKey],
                    observer.generation == generation
                else { return nil }
                let participant = FSEventParticipant(
                    scopeKey: "shared:\(parentKey.volumeSystemNumber):\(parentKey.parentPath)",
                    generation: generation,
                    volumeIdentifier: String(parentKey.volumeSystemNumber)
                )
                deliveredEventIDByParticipant[participant] = UInt64(
                    observer.latestActivitySettledEventId ?? 0
                )
                for worktreeId in observer.exactPathsByWorktreeId.keys.sorted(by: Self.sortWorktreeIds) {
                    guard bindingValidationByWorktreeId[worktreeId]?.isCurrent() == true else {
                        continue
                    }
                    bindings.append(
                        FSEventParticipantBinding(
                            worktreeId: worktreeId,
                            participant: participant
                        )
                    )
                }
            }
            return DarwinSharedExactItemActivityBarrierSnapshot(
                barrier: FSEventActivityBarrier(
                    bindings: bindings,
                    deliveredEventIDByParticipant: deliveredEventIDByParticipant
                ),
                topologyRevision: capturedTopologyRevision
            )
        }
    }

    func activityBarrierIsCurrent(
        _ snapshot: DarwinSharedExactItemActivityBarrierSnapshot
    ) -> Bool {
        lifecycleCondition.withLock {
            !hasShutdown && activityTopologyRevision == snapshot.topologyRevision
        }
    }
}
