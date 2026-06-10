import Foundation

struct BridgeChangeIndexSnapshot: Equatable, Sendable {
    let activeReviewGeneration: BridgeReviewGeneration
    let endpointsById: [String: BridgeSourceEndpoint]
    let checkpointsById: [String: BridgeReviewCheckpoint]
    let packageRevisionsById: [String: Int]
}

actor BridgeChangeIndex {
    private var activeReviewGeneration: BridgeReviewGeneration
    private var endpointsById: [String: BridgeSourceEndpoint] = [:]
    private var checkpointsById: [String: BridgeReviewCheckpoint] = [:]
    private var packageRevisionsById: [String: Int] = [:]

    init(activeReviewGeneration: BridgeReviewGeneration = 0) {
        self.activeReviewGeneration = activeReviewGeneration
    }

    func nextReviewGeneration() -> BridgeReviewGeneration {
        activeReviewGeneration = activeReviewGeneration.next()
        return activeReviewGeneration
    }

    func recordEndpoint(_ endpoint: BridgeSourceEndpoint) {
        endpointsById[endpoint.endpointId] = endpoint
    }

    func recordCheckpoint(_ checkpoint: BridgeReviewCheckpoint) {
        checkpointsById[checkpoint.checkpointId] = checkpoint
        activeReviewGeneration = max(activeReviewGeneration, checkpoint.reviewGeneration)
    }

    func recordPackage(_ package: BridgeReviewPackage, revision: Int = 0) {
        endpointsById[package.baseEndpoint.endpointId] = package.baseEndpoint
        endpointsById[package.headEndpoint.endpointId] = package.headEndpoint
        packageRevisionsById[package.packageId] = max(
            packageRevisionsById[package.packageId] ?? 0,
            revision
        )
        activeReviewGeneration = max(activeReviewGeneration, package.reviewGeneration)
    }

    func recordDelta(_ delta: BridgeReviewDelta) {
        packageRevisionsById[delta.packageId] = max(
            packageRevisionsById[delta.packageId] ?? 0,
            delta.revision
        )
        activeReviewGeneration = max(activeReviewGeneration, delta.reviewGeneration)
    }

    func checkpointIds(kind: BridgeReviewCheckpoint.Kind? = nil) -> [String] {
        checkpointsById.values
            .filter { checkpoint in
                kind.map { $0 == checkpoint.checkpointKind } ?? true
            }
            .sorted { lhs, rhs in
                if lhs.createdAtUnixMilliseconds == rhs.createdAtUnixMilliseconds {
                    lhs.checkpointId < rhs.checkpointId
                } else {
                    lhs.createdAtUnixMilliseconds < rhs.createdAtUnixMilliseconds
                }
            }
            .map(\.checkpointId)
    }

    func snapshot() -> BridgeChangeIndexSnapshot {
        BridgeChangeIndexSnapshot(
            activeReviewGeneration: activeReviewGeneration,
            endpointsById: endpointsById,
            checkpointsById: checkpointsById,
            packageRevisionsById: packageRevisionsById
        )
    }
}
