import Foundation

struct BridgeProductSchemeSessionRouterSnapshot: Equatable, Sendable {
    let activeSchemeTaskCount: Int
    let activeTransportClaimCount: Int

    var hasZeroResidue: Bool {
        activeSchemeTaskCount == 0 && activeTransportClaimCount == 0
    }
}

struct BridgeProductSchemeTransportClaim: Sendable {
    let adapter: BridgeProductSchemeAdapter

    fileprivate let id: UUID
    fileprivate let router: BridgeProductSchemeSessionRouter

    func finish() async {
        await router.finish(self)
    }
}

actor BridgeProductSchemeSessionRouter {
    private(set) var activeInstallation: BridgeProductSessionInstallation?
    private var activeSchemeTaskIds: Set<UUID> = []
    private var activeTransportClaimIds: Set<UUID> = []
    private var drainWaiters: [CheckedContinuation<Void, Never>] = []

    init(activeInstallation: BridgeProductSessionInstallation? = nil) {
        self.activeInstallation = activeInstallation
    }

    func activate(_ installation: BridgeProductSessionInstallation) {
        precondition(activeSchemeTaskIds.isEmpty && activeTransportClaimIds.isEmpty)
        activeInstallation = installation
    }

    func clear() {
        activeInstallation = nil
    }

    func claimActiveAdapter() -> BridgeProductSchemeTransportClaim? {
        guard let activeInstallation else { return nil }
        let claimId = UUID()
        activeSchemeTaskIds.insert(claimId)
        activeTransportClaimIds.insert(claimId)
        return BridgeProductSchemeTransportClaim(
            adapter: activeInstallation.productAdapter,
            id: claimId,
            router: self
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
            activeTransportClaimCount: activeTransportClaimIds.count
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
