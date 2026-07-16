import Foundation

struct BridgeChangeIndexSnapshot: Equatable, Sendable {
    let activeReviewGeneration: BridgeReviewGeneration
    let endpointsById: [String: BridgeSourceEndpoint]
    let checkpointsById: [String: BridgeReviewCheckpoint]
    let packageRevisionsById: [String: Int]
    let packagesById: [String: BridgeReviewPackage]
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

    func ingestExplicitLoad(
        _ package: BridgeReviewPackage,
        productAdmission: BridgeProductAdmissionContext
    ) throws -> BridgeReviewDelta? {
        guard
            let admittedResult = try productAdmission.withValidAdmission({
                try ingestAdmittedExplicitLoad(package)
            })
        else {
            throw BridgeChangeIndexError.admissionClosed
        }
        return admittedResult
    }

    private func ingestAdmittedExplicitLoad(_ package: BridgeReviewPackage) throws -> BridgeReviewDelta? {
        guard package.reviewGeneration >= activeReviewGeneration else {
            return nil
        }

        guard let currentPackage = packagesById[package.packageId] else {
            recordPackage(package)
            return nil
        }
        guard package.reviewGeneration == currentPackage.reviewGeneration else {
            if package.reviewGeneration > currentPackage.reviewGeneration {
                recordPackage(package, revision: package.revision)
            }
            return nil
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
            recordPackage(package, revision: currentRevision)
            return nil
        }

        packagesById[package.packageId] = package.withRevision(delta.revision)
        recordDelta(delta)
        return delta
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
