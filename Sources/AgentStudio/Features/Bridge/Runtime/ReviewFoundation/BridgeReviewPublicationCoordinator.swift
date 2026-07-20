import Foundation

/// Raw Sendable Review publication input that can cross to off-main preparation.
struct BridgeReviewPublicationCandidate: Equatable, Sendable {
    let package: BridgeReviewPackage
    let delta: BridgeReviewDelta?
    let contentHandles: [BridgeContentHandle]
    let artifactPin: BridgeReviewPublicationArtifactPin?

    init(
        package: BridgeReviewPackage,
        delta: BridgeReviewDelta?,
        contentHandles: [BridgeContentHandle],
        artifactPin: BridgeReviewPublicationArtifactPin? = nil
    ) {
        self.package = package
        self.delta = delta
        self.contentHandles = contentHandles
        self.artifactPin = artifactPin
    }
}

/// An immutable Review publication validated and indexed off-main before it
/// reaches the MainActor publication boundary.
struct BridgeReviewPreparedPublication: Equatable, Sendable {
    let package: BridgeReviewPackage
    let delta: BridgeReviewDelta?
    let contentHandles: [BridgeContentHandle]
    let artifactPin: BridgeReviewPublicationArtifactPin?

    private let contentHandleById: [String: BridgeContentHandle]

    @concurrent
    nonisolated static func prepare(
        _ candidate: BridgeReviewPublicationCandidate
    ) async -> Self? {
        Self(candidate)
    }

    private init?(_ candidate: BridgeReviewPublicationCandidate) {
        let package = candidate.package
        let delta = candidate.delta
        let contentHandles = candidate.contentHandles
        let orderedItemIdSet = Set(package.orderedItemIds)
        guard orderedItemIdSet.count == package.orderedItemIds.count,
            orderedItemIdSet == Set(package.itemsById.keys),
            package.itemsById.allSatisfy({ itemId, item in
                itemId == item.itemId
            })
        else {
            return nil
        }

        let suppliedHandleById = Dictionary(
            contentHandles.map { ($0.handleId, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        guard suppliedHandleById.count == contentHandles.count,
            contentHandles.allSatisfy({ handle in
                handle.sizeBytes >= 0
                    && handle.reviewGeneration == package.reviewGeneration
                    && package.itemsById[handle.itemId] != nil
            })
        else {
            return nil
        }

        let expectedHandles = package.itemsById.values.flatMap(\.contentRoles.allHandles)
        let expectedHandleById = Dictionary(
            expectedHandles.map { ($0.handleId, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        guard expectedHandleById.count == expectedHandles.count,
            expectedHandleById == suppliedHandleById
        else {
            return nil
        }

        if let delta {
            guard delta.packageId == package.packageId,
                delta.reviewGeneration == package.reviewGeneration,
                delta.revision == package.revision
            else {
                return nil
            }
        }

        self.package = package
        self.delta = delta
        self.contentHandles = contentHandles
        artifactPin = candidate.artifactPin
        contentHandleById = suppliedHandleById
    }

    fileprivate func contentHandle(
        handleId: String,
        reviewGeneration: BridgeReviewGeneration
    ) -> BridgeContentHandle? {
        guard let handle = contentHandleById[handleId],
            handle.reviewGeneration == reviewGeneration
        else {
            return nil
        }
        return handle
    }
}

struct BridgeReviewPublicationToken: Hashable, Sendable {
    let publicationId: UUID
}

struct BridgeReviewCommittedPublication: Equatable, Sendable {
    let publicationId: UUID
    let package: BridgeReviewPackage
    let delta: BridgeReviewDelta?
    let contentHandles: [BridgeContentHandle]
}

struct BridgeReviewContentAuthorityLease: Equatable, Sendable {
    fileprivate let leaseId: UUID
    let publicationId: UUID
    let packageId: String
    let sourceIdentity: String
    let handle: BridgeContentHandle
}

enum BridgeReviewPublicationDeliveryDisposition: Equatable, Sendable {
    case deferred
    case failed
    case transportAcknowledged
}

enum BridgeReviewPublicationOutcome: Equatable, Sendable {
    case rejectedBeforeCommit
    case superseded
    case closed
    case committed(delivery: BridgeReviewPublicationDeliveryDisposition)
}

enum BridgeReviewPublicationCommitResult: Equatable, Sendable {
    case committed(BridgeReviewCommittedPublication)
    case superseded
    case closed
}

struct BridgeReviewPublicationDiagnostic: Equatable, Sendable {
    let publicationId: UUID
    let packageId: String
    let reviewGeneration: BridgeReviewGeneration
    let revision: Int
}

struct BridgeReviewPublicationStateSnapshot: Equatable, Sendable {
    let active: BridgeReviewPublicationDiagnostic?
    let pending: BridgeReviewPublicationDiagnostic?
    let retiring: [BridgeReviewPublicationDiagnostic]
    let activeContentLeaseCount: Int
    let isClosed: Bool
}

struct BridgeReviewPublicationCloseDrain: Sendable {
    let artifactPins: [BridgeReviewPublicationArtifactPin]
    let priorReleaseTask: Task<Void, Never>?

    func releaseAndWait() async {
        await withTaskGroup(of: Void.self) { taskGroup in
            if let priorReleaseTask {
                taskGroup.addTask {
                    await priorReleaseTask.value
                }
            }
            for artifactPin in artifactPins {
                taskGroup.addTask {
                    await artifactPin.releaseAndWait()
                }
            }
        }
    }

    static let empty = Self(artifactPins: [], priorReleaseTask: nil)
}

/// Owns one pane's native Review package and descriptor publication authority.
///
/// Expensive candidate preparation and delivery stay off-main. This coordinator
/// only performs synchronous state transitions so activating native B and
/// presenting pane B occur in one MainActor turn.
@MainActor
final class BridgeReviewPublicationCoordinator {
    private struct Publication {
        let publicationId: UUID
        let preparedPublication: BridgeReviewPreparedPublication
        let productAdmission: BridgeProductAdmissionContext
    }

    private struct PendingPublication {
        let publication: Publication
        let predecessorPublicationId: UUID?
    }

    private struct RetiringPublication {
        let publication: Publication
        var activeContentLeaseIds: Set<UUID>
        var acceptsNewContentLeases: Bool
    }

    private var activePublication: Publication?
    private var contentLeaseById: [UUID: BridgeReviewContentAuthorityLease] = [:]
    private var pendingPublication: PendingPublication?
    private var retiringPublicationById: [UUID: RetiringPublication] = [:]
    private var isClosed = false
    private var artifactPinReleaseTail: Task<Void, Never>?
    private var artifactPinReleaseTailGeneration: UInt64 = 0

    var diagnosticSnapshot: BridgeReviewPublicationStateSnapshot {
        BridgeReviewPublicationStateSnapshot(
            active: activePublication.map(Self.diagnostic),
            pending: pendingPublication.map { Self.diagnostic($0.publication) },
            retiring: retiringPublicationById.values
                .map { Self.diagnostic($0.publication) }
                .sorted { left, right in
                    if left.packageId == right.packageId {
                        left.publicationId.uuidString < right.publicationId.uuidString
                    } else {
                        left.packageId < right.packageId
                    }
                },
            activeContentLeaseCount: contentLeaseById.count,
            isClosed: isClosed
        )
    }

    func stage(
        _ preparedPublication: BridgeReviewPreparedPublication,
        productAdmission: BridgeProductAdmissionContext
    ) -> BridgeReviewPublicationToken? {
        guard !isClosed else {
            releaseArtifactPin(preparedPublication.artifactPin)
            return nil
        }
        var stagedToken: BridgeReviewPublicationToken?
        _ = productAdmission.withValidAdmission {
            guard !isClosed,
                Self.canFollow(
                    preparedPublication.package,
                    floor: activePublication?.preparedPublication.package
                ),
                Self.canFollow(
                    preparedPublication.package,
                    floor: pendingPublication?.publication.preparedPublication.package
                )
            else { return }
            let token = BridgeReviewPublicationToken(publicationId: UUIDv7.generate())
            releasePublication(pendingPublication?.publication)
            pendingPublication = PendingPublication(
                publication: Publication(
                    publicationId: token.publicationId,
                    preparedPublication: preparedPublication,
                    productAdmission: productAdmission
                ),
                predecessorPublicationId: activePublication?.publicationId
            )
            stagedToken = token
        }
        if stagedToken == nil {
            releaseArtifactPin(preparedPublication.artifactPin)
        }
        return stagedToken
    }

    func rejectReservation(
        _ token: BridgeReviewPublicationToken,
        productAdmission: BridgeProductAdmissionContext
    ) -> BridgeReviewPublicationOutcome {
        guard !isClosed else { return .closed }
        guard pendingMatches(token, productAdmission: productAdmission) else {
            return .superseded
        }
        return productAdmission.withValidAdmission {
            guard pendingMatches(token, productAdmission: productAdmission) else {
                return BridgeReviewPublicationOutcome.superseded
            }
            releasePublication(pendingPublication?.publication)
            pendingPublication = nil
            return .rejectedBeforeCommit
        } ?? .closed
    }

    /// Commits native B and presents pane B without suspension.
    ///
    /// `presentCommitted` executes while the admission gate linearizes the
    /// state transition with pane teardown. It may synchronously inspect the
    /// committed state, but must not call a mutating coordinator method.
    func commit(
        _ token: BridgeReviewPublicationToken,
        productAdmission: BridgeProductAdmissionContext,
        presentCommitted: (BridgeReviewCommittedPublication) -> Void
    ) -> BridgeReviewPublicationCommitResult {
        guard !isClosed else { return .closed }
        guard pendingMatches(token, productAdmission: productAdmission) else {
            return .superseded
        }
        return productAdmission.withValidAdmission {
            guard !isClosed,
                let pendingPublication,
                pendingPublication.publication.publicationId == token.publicationId,
                pendingPublication.publication.productAdmission.matches(productAdmission),
                pendingPublication.predecessorPublicationId == activePublication?.publicationId,
                Self.canFollow(
                    pendingPublication.publication.preparedPublication.package,
                    floor: activePublication?.preparedPublication.package
                )
            else {
                return isClosed
                    ? BridgeReviewPublicationCommitResult.closed
                    : .superseded
            }

            let previousActive = activePublication
            activePublication = pendingPublication.publication
            self.pendingPublication = nil
            beginRetiringAuthority(previousActive)

            let committedPublication = Self.committed(pendingPublication.publication)
            presentCommitted(committedPublication)
            guard !isClosed else { return .closed }
            return .committed(committedPublication)
        } ?? .closed
    }

    func isCurrentPublication(
        publicationId: UUID,
        productAdmission: BridgeProductAdmissionContext
    ) -> Bool {
        guard !isClosed,
            activeMatches(
                publicationId: publicationId,
                productAdmission: productAdmission
            )
        else {
            return false
        }
        return productAdmission.withValidAdmission {
            activeMatches(
                publicationId: publicationId,
                productAdmission: productAdmission
            )
        } ?? false
    }

    func recordTransportDeliveryDisposition(
        _ disposition: BridgeReviewPublicationDeliveryDisposition,
        publicationId: UUID,
        productAdmission: BridgeProductAdmissionContext
    ) -> BridgeReviewPublicationOutcome {
        guard !isClosed else { return .closed }
        guard
            activeMatches(
                publicationId: publicationId,
                productAdmission: productAdmission
            )
        else {
            return .superseded
        }
        return productAdmission.withValidAdmission {
            guard
                activeMatches(
                    publicationId: publicationId,
                    productAdmission: productAdmission
                )
            else {
                return BridgeReviewPublicationOutcome.superseded
            }
            return .committed(delivery: disposition)
        } ?? .closed
    }

    func activeContentHandle(
        handleId: String,
        requestedGeneration: BridgeReviewGeneration,
        productAdmission: BridgeProductAdmissionContext
    ) -> BridgeContentHandle? {
        guard !isClosed else { return nil }
        var activeHandle: BridgeContentHandle?
        _ = productAdmission.withValidAdmission {
            guard let activePublication,
                activePublication.productAdmission.matches(productAdmission),
                activePublication.preparedPublication.package.reviewGeneration
                    == requestedGeneration
            else {
                return
            }
            activeHandle = activePublication.preparedPublication.contentHandle(
                handleId: handleId,
                reviewGeneration: requestedGeneration
            )
        }
        return activeHandle
    }

    func acquireContentLease(
        handleId: String,
        packageId: String,
        requestedGeneration: BridgeReviewGeneration,
        sourceIdentity: String,
        productAdmission: BridgeProductAdmissionContext
    ) -> BridgeReviewContentAuthorityLease? {
        guard !isClosed else { return nil }
        var acquiredLease: BridgeReviewContentAuthorityLease?
        _ = productAdmission.withValidAdmission {
            guard
                let authorityPublication = contentAuthorityPublication(
                    packageId: packageId,
                    requestedGeneration: requestedGeneration,
                    sourceIdentity: sourceIdentity,
                    productAdmission: productAdmission
                ),
                let handle = authorityPublication.preparedPublication.contentHandle(
                    handleId: handleId,
                    reviewGeneration: requestedGeneration
                )
            else {
                return
            }
            let lease = BridgeReviewContentAuthorityLease(
                leaseId: UUIDv7.generate(),
                publicationId: authorityPublication.publicationId,
                packageId: packageId,
                sourceIdentity: sourceIdentity,
                handle: handle
            )
            contentLeaseById[lease.leaseId] = lease
            if var retiringPublication = retiringPublicationById[authorityPublication.publicationId] {
                retiringPublication.activeContentLeaseIds.insert(lease.leaseId)
                retiringPublicationById[authorityPublication.publicationId] = retiringPublication
            }
            acquiredLease = lease
        }
        return acquiredLease
    }

    @discardableResult
    func settleContentLease(_ lease: BridgeReviewContentAuthorityLease) -> Bool {
        guard contentLeaseById[lease.leaseId] == lease else { return false }
        contentLeaseById.removeValue(forKey: lease.leaseId)
        settleFrozenRetiringLease(lease)
        return true
    }

    func committedPublicationForReplay(
        productAdmission: BridgeProductAdmissionContext
    ) -> BridgeReviewCommittedPublication? {
        guard !isClosed else { return nil }
        var replayPublication: BridgeReviewCommittedPublication?
        _ = productAdmission.withValidAdmission {
            guard let activePublication,
                activePublication.productAdmission.matches(productAdmission)
            else {
                return
            }
            replayPublication = Self.committed(activePublication)
        }
        return replayPublication
    }

    @discardableResult
    func recordWorkerApplication(
        publicationId: UUID,
        productAdmission: BridgeProductAdmissionContext
    ) -> Bool {
        guard !isClosed,
            activeMatches(
                publicationId: publicationId,
                productAdmission: productAdmission
            )
        else {
            return false
        }
        return productAdmission.withValidAdmission {
            guard
                activeMatches(
                    publicationId: publicationId,
                    productAdmission: productAdmission
                )
            else {
                return false
            }
            closeRetiringContentAdmission()
            return true
        } ?? false
    }

    func close() -> BridgeReviewPublicationCloseDrain {
        guard !isClosed else { return .empty }
        isClosed = true
        let artifactPins = ownedArtifactPins()
        let priorReleaseTask = takeArtifactPinReleaseTask()
        activePublication = nil
        contentLeaseById.removeAll(keepingCapacity: false)
        pendingPublication = nil
        retiringPublicationById.removeAll(keepingCapacity: false)
        return BridgeReviewPublicationCloseDrain(
            artifactPins: artifactPins,
            priorReleaseTask: priorReleaseTask
        )
    }

    func takeArtifactPinReleaseTask() -> Task<Void, Never>? {
        let releaseTask = artifactPinReleaseTail
        artifactPinReleaseTail = nil
        artifactPinReleaseTailGeneration &+= 1
        return releaseTask
    }

    private func pendingMatches(
        _ token: BridgeReviewPublicationToken,
        productAdmission: BridgeProductAdmissionContext
    ) -> Bool {
        guard let pendingPublication else { return false }
        return pendingPublication.publication.publicationId == token.publicationId
            && pendingPublication.publication.productAdmission.matches(productAdmission)
    }

    private func activeMatches(
        publicationId: UUID,
        productAdmission: BridgeProductAdmissionContext
    ) -> Bool {
        guard let activePublication else { return false }
        return activePublication.publicationId == publicationId
            && activePublication.productAdmission.matches(productAdmission)
    }

    private func beginRetiringAuthority(
        _ publication: Publication?
    ) {
        guard let publication else { return }
        let activeContentLeaseIds = Set(
            contentLeaseById.values.lazy
                .filter { $0.publicationId == publication.publicationId }
                .map(\.leaseId)
        )
        retiringPublicationById[publication.publicationId] = RetiringPublication(
            publication: publication,
            activeContentLeaseIds: activeContentLeaseIds,
            acceptsNewContentLeases: true
        )
    }

    private func settleFrozenRetiringLease(_ lease: BridgeReviewContentAuthorityLease) {
        guard var retiringPublication = retiringPublicationById[lease.publicationId],
            retiringPublication.activeContentLeaseIds.remove(lease.leaseId) != nil
        else {
            return
        }
        if retiringPublication.activeContentLeaseIds.isEmpty,
            !retiringPublication.acceptsNewContentLeases
        {
            releasePublication(retiringPublication.publication)
            retiringPublicationById.removeValue(forKey: lease.publicationId)
        } else {
            retiringPublicationById[lease.publicationId] = retiringPublication
        }
    }

    private func contentAuthorityPublication(
        packageId: String,
        requestedGeneration: BridgeReviewGeneration,
        sourceIdentity: String,
        productAdmission: BridgeProductAdmissionContext
    ) -> Publication? {
        if let activePublication,
            publicationMatchesContentRequest(
                activePublication,
                packageId: packageId,
                requestedGeneration: requestedGeneration,
                sourceIdentity: sourceIdentity,
                productAdmission: productAdmission
            )
        {
            return activePublication
        }
        return retiringPublicationById.values.first { retiringPublication in
            retiringPublication.acceptsNewContentLeases
                && publicationMatchesContentRequest(
                    retiringPublication.publication,
                    packageId: packageId,
                    requestedGeneration: requestedGeneration,
                    sourceIdentity: sourceIdentity,
                    productAdmission: productAdmission
                )
        }?.publication
    }

    private func publicationMatchesContentRequest(
        _ publication: Publication,
        packageId: String,
        requestedGeneration: BridgeReviewGeneration,
        sourceIdentity: String,
        productAdmission: BridgeProductAdmissionContext
    ) -> Bool {
        publication.productAdmission.matches(productAdmission)
            && publication.preparedPublication.package.packageId == packageId
            && publication.preparedPublication.package.reviewGeneration == requestedGeneration
            && publication.preparedPublication.package.query.queryId == sourceIdentity
    }

    private func closeRetiringContentAdmission() {
        for publicationId in Array(retiringPublicationById.keys) {
            guard var retiringPublication = retiringPublicationById[publicationId] else { continue }
            retiringPublication.acceptsNewContentLeases = false
            if retiringPublication.activeContentLeaseIds.isEmpty {
                releasePublication(retiringPublication.publication)
                retiringPublicationById.removeValue(forKey: publicationId)
            } else {
                retiringPublicationById[publicationId] = retiringPublication
            }
        }
    }

    private func releasePublication(_ publication: Publication?) {
        releaseArtifactPin(publication?.preparedPublication.artifactPin)
    }

    private func releaseArtifactPin(_ artifactPin: BridgeReviewPublicationArtifactPin?) {
        guard let artifactPin else { return }
        enqueueArtifactPinRelease(artifactPin)
    }

    private func enqueueArtifactPinRelease(_ artifactPin: BridgeReviewPublicationArtifactPin) {
        let priorReleaseTask = artifactPinReleaseTail
        let artifactPinReleaseTask = Task {
            await artifactPin.releaseAndWait()
        }
        artifactPinReleaseTailGeneration &+= 1
        let releaseGeneration = artifactPinReleaseTailGeneration
        artifactPinReleaseTail = Task { @MainActor [weak self] in
            await priorReleaseTask?.value
            await artifactPinReleaseTask.value
            guard self?.artifactPinReleaseTailGeneration == releaseGeneration else { return }
            self?.artifactPinReleaseTail = nil
        }
    }

    private func ownedArtifactPins() -> [BridgeReviewPublicationArtifactPin] {
        let publications =
            [activePublication, pendingPublication?.publication]
            + retiringPublicationById.values.map(\.publication)
        var seenPinIdentities: Set<ObjectIdentifier> = []
        return publications.compactMap { publication in
            guard let artifactPin = publication?.preparedPublication.artifactPin,
                seenPinIdentities.insert(ObjectIdentifier(artifactPin)).inserted
            else {
                return nil
            }
            return artifactPin
        }
    }

    private static func committed(_ publication: Publication) -> BridgeReviewCommittedPublication {
        BridgeReviewCommittedPublication(
            publicationId: publication.publicationId,
            package: publication.preparedPublication.package,
            delta: publication.preparedPublication.delta,
            contentHandles: publication.preparedPublication.contentHandles
        )
    }

    private static func diagnostic(_ publication: Publication) -> BridgeReviewPublicationDiagnostic {
        BridgeReviewPublicationDiagnostic(
            publicationId: publication.publicationId,
            packageId: publication.preparedPublication.package.packageId,
            reviewGeneration: publication.preparedPublication.package.reviewGeneration,
            revision: publication.preparedPublication.package.revision
        )
    }

    private static func canFollow(
        _ candidate: BridgeReviewPackage,
        floor: BridgeReviewPackage?
    ) -> Bool {
        guard let floor else { return true }
        if candidate.reviewGeneration != floor.reviewGeneration {
            return candidate.reviewGeneration > floor.reviewGeneration
        }
        guard candidate.packageId == floor.packageId,
            candidate.query.queryId == floor.query.queryId
        else {
            return false
        }
        return candidate.revision > floor.revision
    }
}
