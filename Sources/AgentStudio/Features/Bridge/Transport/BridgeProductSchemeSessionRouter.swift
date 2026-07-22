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
    private var drainWaiters: [CheckedContinuation<Void, Never>] = []
    private var latestCapabilityAuthenticator: BridgeProductCapabilityAuthenticator?
    private let productAdmissionGate: BridgeProductAdmissionGate
    private var transportClaimMintCount = 0

    init(
        activeInstallation: BridgeProductSessionInstallation? = nil,
        productAdmissionGate: BridgeProductAdmissionGate
    ) {
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
    }

    func claimActiveAdapter(
        presentedCapability: String
    ) -> BridgeProductSchemeTransportAdmission {
        guard latestCapabilityAuthenticator?.matches(presentedCapability) == true else {
            return .unauthorized
        }
        guard let productAdmission = productAdmissionGate.acquire(),
            let activeInstallation
        else {
            return .conflict
        }
        let claimId = UUID()
        activeSchemeTaskIds.insert(claimId)
        activeTransportClaimIds.insert(claimId)
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
        guard snapshot.hasZeroResidue else { return }
        let waiters = drainWaiters
        drainWaiters.removeAll()
        for waiter in waiters { waiter.resume() }
    }
}
