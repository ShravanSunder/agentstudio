import CoreServices
import Foundation

extension DarwinSharedExactItemObserverRegistry {
    func captureActivityBarrier() -> FSEventActivityBarrier? {
        let retainedParticipants = lifecycleCondition.withLock {
            () -> [(DarwinSharedExactItemParentKey, UInt64, any DarwinSharedExactItemStreamLifetime)]? in
            guard !hasShutdown else { return nil }
            return observerByParent.keys.sorted(by: Self.sortParentKeys).compactMap { parentKey in
                guard let observer = observerByParent[parentKey] else { return nil }
                return (parentKey, observer.generation, observer.streamLifetime)
            }
        }
        guard let retainedParticipants else { return nil }
        for (_, _, streamLifetime) in retainedParticipants {
            guard streamLifetime.flush() else { return nil }
        }

        return lifecycleCondition.withLock {
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
                deliveredEventIDByParticipant[participant] = UInt64(observer.latestEventId ?? 0)
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
            return FSEventActivityBarrier(
                bindings: bindings,
                deliveredEventIDByParticipant: deliveredEventIDByParticipant
            )
        }
    }
}
