import Foundation

struct BridgeProductViewOutstandingPart: Sendable {
    let viewDomain: BridgeProductViewDomainKey
    let handle: String
    let sequence: Int
    let admittedAt: Duration
    let admissionOrder: Int
}

/// Shares one transport credit budget across domains while retaining receipt
/// attribution by view, domain and incarnation. The handle fences old acks.
struct BridgeProductViewCreditWindow {
    private struct OutstandingPart {
        let sequence: Int
        let byteCount: Int
        let admittedAt: Duration
        let admissionOrder: Int
    }

    private struct ViewState {
        let handle: String
        var receivedThroughSequence = 0
        var lastAdmittedSequence = 0
        var outstandingParts: [OutstandingPart] = []
        var outstandingBytes = 0
    }

    private let maximumParts: Int
    private let maximumBytes: Int
    private var stateByViewDomain: [BridgeProductViewDomainKey: ViewState] = [:]
    private var outstandingPartCount = 0
    private var outstandingByteCount = 0
    private var nextAdmissionOrder = 0

    init(maximumParts: Int, maximumBytes: Int) {
        precondition(maximumParts > 0 && maximumBytes > 0)
        self.maximumParts = maximumParts
        self.maximumBytes = maximumBytes
    }

    mutating func open(_ viewDomain: BridgeProductViewDomainKey, handle: String) {
        precondition(!handle.isEmpty)
        close(viewDomain)
        stateByViewDomain[viewDomain] = ViewState(handle: handle)
    }

    mutating func close(_ viewDomain: BridgeProductViewDomainKey) {
        guard let state = stateByViewDomain.removeValue(forKey: viewDomain) else { return }
        outstandingPartCount -= state.outstandingParts.count
        outstandingByteCount -= state.outstandingBytes
    }

    func outstandingPartCount(for viewDomain: BridgeProductViewDomainKey) -> Int {
        stateByViewDomain[viewDomain]?.outstandingParts.count ?? 0
    }

    func oldestUnacknowledgedPart() -> BridgeProductViewOutstandingPart? {
        stateByViewDomain.compactMap { viewDomain, state in
            state.outstandingParts.first.map { part in
                BridgeProductViewOutstandingPart(
                    viewDomain: viewDomain,
                    handle: state.handle,
                    sequence: part.sequence,
                    admittedAt: part.admittedAt,
                    admissionOrder: part.admissionOrder
                )
            }
        }.min {
            $0.admittedAt == $1.admittedAt
                ? $0.admissionOrder < $1.admissionOrder
                : $0.admittedAt < $1.admittedAt
        }
    }

    /// A late receipt for already returned or abandoned credits is a no-op.
    /// It may be answered without releasing any capacity a second time.
    func wasAlreadySatisfied(
        for viewDomain: BridgeProductViewDomainKey,
        handle: String,
        through sequence: Int
    ) -> Bool {
        guard let state = stateByViewDomain[viewDomain], state.handle == handle else { return false }
        return sequence > 0 && sequence <= state.receivedThroughSequence
    }

    var maximumPartByteCount: Int { maximumBytes }

    /// Abandoning one staging bank returns only its in-transit credits. Reserved
    /// delivery sequences that never reached admission are skipped so the next
    /// sealed batch can keep its monotonic sequence. A late receipt cannot
    /// release successor capacity.
    mutating func abandonOutstanding(
        for viewDomain: BridgeProductViewDomainKey,
        throughReservedSequence: Int? = nil
    ) {
        guard var state = stateByViewDomain[viewDomain] else { return }
        outstandingPartCount -= state.outstandingParts.count
        outstandingByteCount -= state.outstandingBytes
        state.outstandingParts.removeAll()
        state.outstandingBytes = 0
        let abandonedThroughSequence = max(state.lastAdmittedSequence, throughReservedSequence ?? 0)
        state.lastAdmittedSequence = abandonedThroughSequence
        state.receivedThroughSequence = abandonedThroughSequence
        stateByViewDomain[viewDomain] = state
    }

    mutating func admitPart(
        for viewDomain: BridgeProductViewDomainKey,
        handle: String,
        sequence: Int,
        byteCount: Int,
        admittedAt: Duration = .zero
    ) -> Bool {
        guard var state = stateByViewDomain[viewDomain],
            state.handle == handle,
            sequence == state.lastAdmittedSequence + 1,
            byteCount > 0,
            byteCount <= maximumBytes - outstandingByteCount,
            outstandingPartCount < maximumParts
        else {
            return false
        }
        nextAdmissionOrder += 1
        state.outstandingParts.append(
            .init(
                sequence: sequence,
                byteCount: byteCount,
                admittedAt: admittedAt,
                admissionOrder: nextAdmissionOrder
            )
        )
        state.outstandingBytes += byteCount
        state.lastAdmittedSequence = sequence
        outstandingPartCount += 1
        outstandingByteCount += byteCount
        stateByViewDomain[viewDomain] = state
        return true
    }

    /// A cumulative receipt is valid only through a part this view admitted.
    /// Duplicate and speculative receipts do not change the credit balance.
    mutating func acknowledge(
        for viewDomain: BridgeProductViewDomainKey,
        handle: String,
        through receivedSequence: Int
    ) -> Bool {
        guard var state = stateByViewDomain[viewDomain],
            state.handle == handle,
            receivedSequence > state.receivedThroughSequence,
            receivedSequence <= state.lastAdmittedSequence
        else {
            return false
        }
        let receivedParts = state.outstandingParts.prefix {
            $0.sequence <= receivedSequence
        }
        let returnedPartCount = receivedParts.count
        let returnedByteCount = receivedParts.reduce(0) { $0 + $1.byteCount }
        state.outstandingBytes -= returnedByteCount
        state.outstandingParts.removeFirst(returnedPartCount)
        state.receivedThroughSequence = receivedSequence
        outstandingPartCount -= returnedPartCount
        outstandingByteCount -= returnedByteCount
        stateByViewDomain[viewDomain] = state
        return true
    }
}
