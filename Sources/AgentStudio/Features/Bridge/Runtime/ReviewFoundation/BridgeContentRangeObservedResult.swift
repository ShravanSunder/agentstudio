import CryptoKit
import Foundation

struct BridgeContentRangeObservedResult: Equatable, Sendable {
    let handle: BridgeContentHandle
    let bytes: Data
    let wholeByteLength: Int
    let startByte: Int
    let sha256: String
    let isFinalRange: Bool
    let observation: BridgeContentLoadObservation
}

enum BridgeContentRangeError: Error, Equatable, Sendable {
    case invalidStartByte(Int)
    case invalidMaximumBytes(Int)
    case rangeOverflow(startByte: Int, maximumBytes: Int)
    case startByteBeyondContent(startByte: Int, wholeByteLength: Int)
}

extension BridgeContentStore {
    func loadRangeObserved(
        handleId: String,
        requestedGeneration: BridgeReviewGeneration,
        startByte: Int,
        maximumBytes: Int,
        productAdmission: BridgeProductAdmissionContext
    ) async throws -> BridgeContentRangeObservedResult {
        guard startByte >= 0 else {
            throw BridgeContentRangeError.invalidStartByte(startByte)
        }
        guard maximumBytes > 0 else {
            throw BridgeContentRangeError.invalidMaximumBytes(maximumBytes)
        }
        let (requestedEndByte, rangeOverflowed) = startByte.addingReportingOverflow(maximumBytes)
        guard !rangeOverflowed else {
            throw BridgeContentRangeError.rangeOverflow(startByte: startByte, maximumBytes: maximumBytes)
        }

        let observedLoad = try await loadObserved(
            handleId: handleId,
            requestedGeneration: requestedGeneration,
            productAdmission: productAdmission
        )
        try Task.checkCancellation()
        let wholeByteLength = observedLoad.result.data.count
        guard startByte <= wholeByteLength else {
            throw BridgeContentRangeError.startByteBeyondContent(
                startByte: startByte,
                wholeByteLength: wholeByteLength
            )
        }
        let endByte = min(requestedEndByte, wholeByteLength)
        let bytes = observedLoad.result.data.subdata(in: startByte..<endByte)
        let rangeSHA256 = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        guard
            let range = productAdmission.withValidAdmission({
                BridgeContentRangeObservedResult(
                    handle: observedLoad.result.handle,
                    bytes: bytes,
                    wholeByteLength: wholeByteLength,
                    startByte: startByte,
                    sha256: rangeSHA256,
                    isFinalRange: endByte == wholeByteLength,
                    observation: observedLoad.observation
                )
            })
        else { throw BridgeContentStoreError.productAdmissionRejected }
        try Task.checkCancellation()
        return range
    }
}
