import Foundation

struct BridgeProductSchemeSessionRouterSnapshot: Equatable, Sendable {
    let activeSchemeTaskCount: Int
    let activeTransportClaimCount: Int
    let transportClaimMintCount: Int

    var hasZeroResidue: Bool {
        activeSchemeTaskCount == 0 && activeTransportClaimCount == 0
    }
}

struct BridgeProductSchemeTransportClaim: Sendable {
    let adapter: BridgeProductSchemeAdapter
    let productAdmission: BridgeProductAdmissionContext

    fileprivate let id: UUID
    fileprivate let router: BridgeProductSchemeSessionRouter

    func finish() async {
        await router.finish(self)
    }
}

enum BridgeProductSchemeTransportAdmission: Sendable {
    case admitted(BridgeProductSchemeTransportClaim)
    case conflict
    case unauthorized
}

actor BridgeProductSchemeSessionRouter {
    private(set) var activeInstallation: BridgeProductSessionInstallation?
    private var activeSchemeTaskIds: Set<UUID> = []
    private var activeTransportClaimIds: Set<UUID> = []
    private var activeStreamClaimIds: Set<UUID> = []
    private var drainWaiters: [CheckedContinuation<Void, Never>] = []
    private var latestCapabilityAuthenticator: BridgeProductCapabilityAuthenticator?
    private let productAdmissionGate: BridgeProductAdmissionGate
    private var streamDrainWaitersById: [UInt64: CheckedContinuation<Void, Never>] = [:]
    private var nextStreamDrainWaiterId: UInt64 = 0
    private var cancelledStreamDrainWaiterIds: Set<UInt64> = []
    private var transportClaimMintCount = 0

    /// Reachable without an actor hop because `onTermination` is synchronous.
    nonisolated let schemeTaskCensus: BridgeProductSchemeTaskCensus

    init(
        activeInstallation: BridgeProductSessionInstallation? = nil,
        productAdmissionGate: BridgeProductAdmissionGate,
        schemeTaskCensus: BridgeProductSchemeTaskCensus = BridgeProductSchemeTaskCensus()
    ) {
        self.schemeTaskCensus = schemeTaskCensus
        precondition(
            activeInstallation == nil
                || activeInstallation?.productAdmissionGate === productAdmissionGate
        )
        self.activeInstallation = activeInstallation
        self.latestCapabilityAuthenticator = activeInstallation?.session.capabilityAuthenticator
        self.productAdmissionGate = productAdmissionGate
    }

    func activate(
        _ installation: BridgeProductSessionInstallation,
        productAdmission: BridgeProductAdmissionContext
    ) -> Bool {
        guard productAdmission.wasMinted(by: productAdmissionGate) else { return false }
        return productAdmission.withValidAdmission {
            precondition(activeSchemeTaskIds.isEmpty && activeTransportClaimIds.isEmpty)
            precondition(installation.productAdmissionGate === productAdmissionGate)
            activeInstallation = installation
            latestCapabilityAuthenticator = installation.session.capabilityAuthenticator
            return true
        } ?? false
    }

    func clear() {
        activeInstallation = nil
        resumeAllStreamDrainWaiters()
    }

    /// - Parameters:
    ///   - schemeTaskId: minted by the scheme handler before the reply task so
    ///     the census and the claim are the same identity.
    ///   - route: only a metadata stream joins the stream-scoped drain; a live
    ///     content stream must never hold a bootstrap open.
    func claimActiveAdapter(
        presentedCapability: String,
        schemeTaskId: UUID,
        route: BridgeProductSchemeRoute?
    ) -> BridgeProductSchemeTransportAdmission {
        guard latestCapabilityAuthenticator?.matches(presentedCapability) == true else {
            return .unauthorized
        }
        guard let productAdmission = productAdmissionGate.acquire(),
            let activeInstallation
        else {
            return .conflict
        }
        let claimId = schemeTaskId
        activeSchemeTaskIds.insert(claimId)
        activeTransportClaimIds.insert(claimId)
        if route == .metadataStream {
            activeStreamClaimIds.insert(claimId)
        }
        transportClaimMintCount += 1
        return .admitted(
            BridgeProductSchemeTransportClaim(
                adapter: activeInstallation.productAdapter,
                productAdmission: productAdmission,
                id: claimId,
                router: self
            )
        )
    }

    func waitForDrain() async {
        guard !snapshot.hasZeroResidue else { return }
        await withCheckedContinuation { continuation in
            drainWaiters.append(continuation)
        }
    }

    /// Resolves when no metadata-stream claim remains.
    ///
    /// Deliberately narrower than `waitForDrain()`: a command or content claim
    /// can legitimately outlive a stream, and waiting on one would hang a caller
    /// that only needs the stream's transport to be gone.
    func waitForStreamClaimDrain() async {
        guard !activeStreamClaimIds.isEmpty else { return }
        let waiterId = mintStreamDrainWaiterId()
        // Cancellation-safe and lost-wakeup-free. The handler can run BEFORE the
        // continuation is stored, so storing re-checks whether this id was already
        // cancelled and resumes immediately; every resume path removes the id
        // first, so exactly one resume happens on every interleaving.
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                storeStreamDrainWaiter(continuation, id: waiterId)
            }
        } onCancel: {
            Task { await self.resumeStreamDrainWaiter(id: waiterId) }
        }
    }

    private func mintStreamDrainWaiterId() -> UInt64 {
        nextStreamDrainWaiterId += 1
        return nextStreamDrainWaiterId
    }

    private func storeStreamDrainWaiter(
        _ continuation: CheckedContinuation<Void, Never>,
        id waiterId: UInt64
    ) {
        if cancelledStreamDrainWaiterIds.remove(waiterId) != nil {
            // The cancellation handler already ran for this id.
            continuation.resume()
            return
        }
        streamDrainWaitersById[waiterId] = continuation
    }

    private func resumeStreamDrainWaiter(id waiterId: UInt64) {
        guard let continuation = streamDrainWaitersById.removeValue(forKey: waiterId) else {
            // The handler beat the store; the store will resume immediately.
            cancelledStreamDrainWaiterIds.insert(waiterId)
            return
        }
        continuation.resume()
    }

    /// Resumes every parked stream-drain waiter. Called on every teardown path so
    /// a waiter can never outlive the router that would have woken it.
    private func resumeAllStreamDrainWaiters() {
        let parkedWaiters = streamDrainWaitersById
        streamDrainWaitersById.removeAll()
        for (_, continuation) in parkedWaiters { continuation.resume() }
    }

    var snapshot: BridgeProductSchemeSessionRouterSnapshot {
        .init(
            activeSchemeTaskCount: activeSchemeTaskIds.count,
            activeTransportClaimCount: activeTransportClaimIds.count,
            transportClaimMintCount: transportClaimMintCount
        )
    }

    fileprivate func finish(_ claim: BridgeProductSchemeTransportClaim) {
        activeSchemeTaskIds.remove(claim.id)
        activeTransportClaimIds.remove(claim.id)
        if activeStreamClaimIds.remove(claim.id) != nil, activeStreamClaimIds.isEmpty {
            resumeAllStreamDrainWaiters()
        }
        guard snapshot.hasZeroResidue else { return }
        let waiters = drainWaiters
        drainWaiters.removeAll()
        for waiter in waiters { waiter.resume() }
    }
}
