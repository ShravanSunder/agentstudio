import Foundation

extension BridgePaneProductSchemeProvider {
    struct BufferedContentBody: Sendable {
        let data: Data
        let endOfSource: Bool
        let sha256: String
    }

    struct FileContentStreamDigest: Sendable {
        let byteCount: Int
        let sha256: String
    }

    func beginActivityInvalidatedProducerRetirement(
        lease: BridgeProductProducerLease,
        session: BridgeProductSession
    ) async -> BridgeProductProducerRetirementBarrier {
        await session.beginProducerRetirement(
            lease,
            acknowledgeLifecycle: acknowledgeLifecycle,
            stopRequest: nil,
            abandonOutstandingDelivery: true
        )
    }

    func waitForProducerCancellation() async {
        let stream = AsyncStream<Void> { _ in }
        for await _ in stream {}
    }
}
