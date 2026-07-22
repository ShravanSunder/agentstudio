import Foundation

struct BridgeChangeIndexSnapshot: Equatable, Sendable {
    let activeReviewGeneration: BridgeReviewGeneration
    let endpointsById: [String: BridgeSourceEndpoint]
    let checkpointsById: [String: BridgeReviewCheckpoint]
    let packageRevisionsById: [String: Int]
    let packagesById: [String: BridgeReviewPackage]
}

struct BridgeChangeIndexPreparedLoad: Equatable, Sendable {
    let package: BridgeReviewPackage
    let delta: BridgeReviewDelta?
}

enum BridgeChangeIndexError: Error, Equatable {
    case admissionClosed
}

actor BridgeChangeIndex {
    private var activeReviewGeneration: BridgeReviewGeneration
    private var endpointsById: [String: BridgeSourceEndpoint] = [:]
    private var checkpointsById: [String: BridgeReviewCheckpoint] = [:]
    private var packageRevisionsById: [String: Int] = [:]
    private var packagesById: [String: BridgeReviewPackage] = [:]

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

    func recordPackage(_ package: BridgeReviewPackage, revision: Int? = nil) {
        let resolvedRevision = max(
            packageRevisionsById[package.packageId] ?? 0,
            revision ?? package.revision
        )
        endpointsById[package.baseEndpoint.endpointId] = package.baseEndpoint
        endpointsById[package.headEndpoint.endpointId] = package.headEndpoint
        packagesById[package.packageId] = package.withRevision(resolvedRevision)
        packageRevisionsById[package.packageId] = resolvedRevision
        activeReviewGeneration = max(activeReviewGeneration, package.reviewGeneration)
    }

    func prepareExplicitLoad(
        _ package: BridgeReviewPackage,
        fallbackRevision: Int? = nil,
        productAdmission: BridgeProductAdmissionContext
    ) throws -> BridgeChangeIndexPreparedLoad {
        guard
            let admittedResult = try productAdmission.withValidAdmission({
                try prepareAdmittedExplicitLoad(
                    package,
                    fallbackRevision: fallbackRevision
                )
            })
        else {
            throw BridgeChangeIndexError.admissionClosed
        }
        return admittedResult
    }

    func recordCommittedLoad(
        _ preparedLoad: BridgeChangeIndexPreparedLoad,
        productAdmission: BridgeProductAdmissionContext
    ) -> Bool {
        productAdmission.withValidAdmission {
            recordPackage(
                preparedLoad.package,
                revision: preparedLoad.delta?.revision ?? preparedLoad.package.revision
            )
            if let delta = preparedLoad.delta {
                recordDelta(delta)
            }
            return true
        } == true
    }

    private func prepareAdmittedExplicitLoad(
        _ package: BridgeReviewPackage,
        fallbackRevision: Int?
    ) throws -> BridgeChangeIndexPreparedLoad {
        guard package.reviewGeneration >= activeReviewGeneration else {
            return BridgeChangeIndexPreparedLoad(
                package: package.withRevision(fallbackRevision ?? package.revision),
                delta: nil
            )
        }

        guard let currentPackage = packagesById[package.packageId] else {
            return BridgeChangeIndexPreparedLoad(
                package: package.withRevision(fallbackRevision ?? package.revision),
                delta: nil
            )
        }
        guard package.reviewGeneration == currentPackage.reviewGeneration else {
            return BridgeChangeIndexPreparedLoad(
                package: package.withRevision(fallbackRevision ?? package.revision),
                delta: nil
            )
        }

        let currentRevision = packageRevisionsById[package.packageId] ?? currentPackage.revision
        guard
            let delta = try BridgeReviewDeltaBuilder.build(
                BridgeReviewDeltaBuildRequest(
                    currentPackage: currentPackage,
                    nextPackage: package,
                    currentRevision: currentRevision
                )
            )
        else {
            return BridgeChangeIndexPreparedLoad(
                package: package.withRevision(fallbackRevision ?? currentRevision),
                delta: nil
            )
        }

        return BridgeChangeIndexPreparedLoad(
            package: package.withRevision(delta.revision),
            delta: delta
        )
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
            packageRevisionsById: packageRevisionsById,
            packagesById: packagesById
        )
    }
}

extension BridgeReviewPackage {
    func withRevision(_ revision: Int) -> BridgeReviewPackage {
        BridgeReviewPackage(
            packageId: packageId,
            schemaVersion: schemaVersion,
            reviewGeneration: reviewGeneration,
            revision: revision,
            query: query,
            baseEndpoint: baseEndpoint,
            headEndpoint: headEndpoint,
            orderedItemIds: orderedItemIds,
            itemsById: itemsById,
            groups: groups,
            summary: summary,
            filterState: filterState,
            generatedAtUnixMilliseconds: generatedAtUnixMilliseconds,
            changesetCluster: changesetCluster
        )
    }

    func withChangesetCluster(_ changesetCluster: BridgeReviewChangesetClusterMetadata?) -> BridgeReviewPackage {
        BridgeReviewPackage(
            packageId: packageId,
            schemaVersion: schemaVersion,
            reviewGeneration: reviewGeneration,
            revision: revision,
            query: query,
            baseEndpoint: baseEndpoint,
            headEndpoint: headEndpoint,
            orderedItemIds: orderedItemIds,
            itemsById: itemsById,
            groups: groups,
            summary: summary,
            filterState: filterState,
            generatedAtUnixMilliseconds: generatedAtUnixMilliseconds,
            changesetCluster: changesetCluster
        )
    }
}
