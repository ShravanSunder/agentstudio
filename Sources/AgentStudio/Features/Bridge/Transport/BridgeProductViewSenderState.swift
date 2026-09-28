import Foundation

enum BridgeProductViewSenderError: Error {
    case staleProducer
    case batchAlreadyActive
    case partExceedsCreditWindow
}

private struct BridgeProductLogicalViewDomain: Hashable {
    let viewId: String
    let domain: BridgeProductViewDomain
}

/// N3's bounded state before scheme-pump integration. One stream-wide credit
/// budget is scheduled round-robin across domain batches; each domain retains
/// its own dirty keys, cursor and resnapshot disposition.
struct BridgeProductViewSenderState {
    private struct Emission {
        let batch: BridgeProductSealedViewBatch
        var nextOrdinal = 0
    }

    private var dirtyKeys: BridgeProductViewDirtyKeyAccumulator
    private var credits: BridgeProductViewCreditWindow
    private var activeByLogicalDomain: [BridgeProductLogicalViewDomain: BridgeProductViewDomainKey] = [:]
    private var emissionByViewDomain: [BridgeProductViewDomainKey: Emission] = [:]
    private var schedulingOrder: [BridgeProductViewDomainKey] = []

    init(maximumDirtyKeys: Int, creditParts: Int, creditBytes: Int) {
        dirtyKeys = .init(maximumDirtyKeysPerViewDomain: maximumDirtyKeys)
        credits = .init(maximumParts: creditParts, maximumBytes: creditBytes)
    }

    mutating func open(_ viewDomain: BridgeProductViewDomainKey, handle: String, scanGeneration: Int) {
        let logical = BridgeProductLogicalViewDomain(viewId: viewDomain.viewId, domain: viewDomain.domain)
        if let prior = activeByLogicalDomain[logical] {
            close(prior)
        }
        activeByLogicalDomain[logical] = viewDomain
        dirtyKeys.open(viewDomain, scanGeneration: scanGeneration)
        credits.open(viewDomain, handle: handle)
    }

    mutating func close(_ viewDomain: BridgeProductViewDomainKey) {
        let logical = BridgeProductLogicalViewDomain(viewId: viewDomain.viewId, domain: viewDomain.domain)
        if activeByLogicalDomain[logical] == viewDomain {
            activeByLogicalDomain.removeValue(forKey: logical)
        }
        dirtyKeys.removeViewDomain(viewDomain)
        credits.close(viewDomain)
        emissionByViewDomain.removeValue(forKey: viewDomain)
        schedulingOrder.removeAll { $0 == viewDomain }
    }

    mutating func advanceScanGeneration(for viewDomain: BridgeProductViewDomainKey, to generation: Int) -> Bool {
        guard dirtyKeys.advanceScanGeneration(for: viewDomain, to: generation) else { return false }
        resnapshot(viewDomain)
        return true
    }

    @discardableResult
    mutating func recordChange(
        for viewDomain: BridgeProductViewDomainKey,
        scanGeneration: Int,
        recordKey: String,
        revision: Int
    ) -> Bool {
        dirtyKeys.recordChange(
            for: viewDomain,
            scanGeneration: scanGeneration,
            recordKey: recordKey,
            revision: revision
        )
    }

    func pending(for viewDomain: BridgeProductViewDomainKey) -> BridgeProductViewPendingChange {
        dirtyKeys.pending(for: viewDomain)
    }

    mutating func takePending(for viewDomain: BridgeProductViewDomainKey) -> BridgeProductViewPendingChange {
        dirtyKeys.takePending(for: viewDomain)
    }

    mutating func restorePending(_ pending: BridgeProductViewPendingChange, for viewDomain: BridgeProductViewDomainKey)
    {
        dirtyKeys.restore(pending, for: viewDomain)
    }

    mutating func seal(_ batch: BridgeProductSealedViewBatch) throws {
        guard dirtyKeys.accepts(batch.viewDomain, scanGeneration: batch.producerScanGeneration) else {
            throw BridgeProductViewSenderError.staleProducer
        }
        guard emissionByViewDomain[batch.viewDomain] == nil else {
            throw BridgeProductViewSenderError.batchAlreadyActive
        }
        emissionByViewDomain[batch.viewDomain] = .init(batch: batch)
        schedulingOrder.append(batch.viewDomain)
    }

    func hasActiveEmission(for viewDomain: BridgeProductViewDomainKey) -> Bool {
        emissionByViewDomain[viewDomain] != nil
    }

    /// Returns one frame without materializing another batch-sized array.
    /// An out-of-credit domain yields its turn to a sibling.
    mutating func nextFrame(
        stream: BridgeProductMetadataStreamCorrelation,
        streamSequence: Int,
        admittedAt: Duration = .zero
    ) throws -> BridgeProductMetadataFrame? {
        let candidateCount = schedulingOrder.count
        for _ in 0..<candidateCount {
            let viewDomain = schedulingOrder[0]
            guard var emission = emissionByViewDomain[viewDomain] else {
                schedulingOrder.removeFirst()
                continue
            }
            let frame = try emission.batch.frame(
                atOrdinal: emission.nextOrdinal,
                stream: stream,
                streamSequence: streamSequence
            )
            if case .batch(.part(let partFrame)) = frame {
                let byteCount = try BridgeProductMetadataFrameCodec.encode(frame).count
                guard byteCount <= credits.maximumPartByteCount else {
                    throw BridgeProductViewSenderError.partExceedsCreditWindow
                }
                guard
                    credits.admitPart(
                        for: viewDomain,
                        handle: emission.batch.handle,
                        sequence: partFrame.deliverySequence,
                        byteCount: byteCount,
                        admittedAt: admittedAt
                    )
                else {
                    schedulingOrder.removeFirst()
                    schedulingOrder.append(viewDomain)
                    continue
                }
            }
            schedulingOrder.removeFirst()
            emission.nextOrdinal += 1
            if emission.nextOrdinal == emission.batch.frameCount {
                emissionByViewDomain.removeValue(forKey: viewDomain)
            } else {
                emissionByViewDomain[viewDomain] = emission
                schedulingOrder.append(viewDomain)
            }
            return frame
        }
        return nil
    }

    mutating func acknowledge(
        for viewDomain: BridgeProductViewDomainKey,
        handle: String,
        through deliverySequence: Int
    ) -> Bool {
        credits.acknowledge(for: viewDomain, handle: handle, through: deliverySequence)
    }

    func acknowledgementWasAlreadySatisfied(
        for viewDomain: BridgeProductViewDomainKey,
        handle: String,
        through deliverySequence: Int
    ) -> Bool {
        credits.wasAlreadySatisfied(for: viewDomain, handle: handle, through: deliverySequence)
    }

    mutating func resnapshot(_ viewDomain: BridgeProductViewDomainKey) {
        guard dirtyKeys.hasActiveIncarnation(viewDomain) else { return }
        dirtyKeys.requireSnapshot(for: viewDomain)
        let reservedThroughSequence = emissionByViewDomain[viewDomain].map { emission in
            emission.batch.firstDeliverySequence + emission.batch.parts.count - 1
        }
        credits.abandonOutstanding(for: viewDomain, throughReservedSequence: reservedThroughSequence)
        emissionByViewDomain.removeValue(forKey: viewDomain)
        schedulingOrder.removeAll { $0 == viewDomain }
    }

    func outstandingPartCount(for viewDomain: BridgeProductViewDomainKey) -> Int {
        credits.outstandingPartCount(for: viewDomain)
    }

    func oldestUnacknowledgedPart() -> BridgeProductViewOutstandingPart? {
        credits.oldestUnacknowledgedPart()
    }
}
