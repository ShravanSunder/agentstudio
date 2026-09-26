import Foundation

/// Shares one transport credit budget across domains while retaining receipt
/// attribution by view, domain and incarnation. The handle fences old acks.
struct BridgeProductViewCreditWindow {
    private struct OutstandingPart {
        let sequence: Int
        let byteCount: Int
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

    var maximumPartByteCount: Int { maximumBytes }

    /// Abandoning one staging bank returns only its in-transit credits. A late
    /// cumulative acknowledgement for those parts must not credit them again.
    mutating func abandonOutstanding(for viewDomain: BridgeProductViewDomainKey) {
        guard var state = stateByViewDomain[viewDomain] else { return }
        outstandingPartCount -= state.outstandingParts.count
        outstandingByteCount -= state.outstandingBytes
        state.outstandingParts.removeAll()
        state.outstandingBytes = 0
        state.receivedThroughSequence = state.lastAdmittedSequence
        stateByViewDomain[viewDomain] = state
    }

    mutating func admitPart(
        for viewDomain: BridgeProductViewDomainKey,
        handle: String,
        sequence: Int,
        byteCount: Int
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
        state.outstandingParts.append(.init(sequence: sequence, byteCount: byteCount))
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
