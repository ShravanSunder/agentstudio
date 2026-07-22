import CryptoKit
import Foundation

struct BridgeProductControlAdmissionToken: Equatable, Hashable, Sendable {
    let identifier: UInt64
    let requestSequence: Int
}

enum BridgeProductControlReplayRejection: Equatable, Sendable {
    case payloadTooLarge
    case requestInFlight(nextExpectedRequestSequence: Int)
    case sequenceExhausted(nextExpectedRequestSequence: Int)
    case sequenceConflict(nextExpectedRequestSequence: Int)
}

enum BridgeProductControlReplayAdmission: Equatable, Sendable {
    case execute(BridgeProductControlAdmissionToken)
    case replay(exactResponseBytes: Data)
    case rejected(BridgeProductControlReplayRejection)
}

enum BridgeProductControlReplayCacheError: Error, Equatable {
    case invalidAdmissionToken
    case invalidSequenceFloor
    case responsePayloadTooLarge
    case sequenceExhausted
}

struct BridgeProductControlReplaySnapshot: Equatable, Sendable {
    let inFlightRequestSequence: Int?
    let nextExpectedRequestSequence: Int
    let replayableRequestSequence: Int?
}

struct BridgeProductControlReplayCache: Sendable {
    private struct InFlightRequest: Sendable {
        let exactRequestBytes: Data
        let requestDigest: Data
        let token: BridgeProductControlAdmissionToken
    }

    private struct CompletedRequest: Sendable {
        let exactRequestBytes: Data
        let exactResponseBytes: Data
        let requestDigest: Data
        let requestSequence: Int
    }

    private let maximumRequestOrResponseBytes: Int
    private var nextAdmissionIdentifier: UInt64 = 1
    private var nextExpectedRequestSequence: Int
    private var inFlightRequest: InFlightRequest?
    private var completedRequest: CompletedRequest?

    init(
        maximumRequestOrResponseBytes: Int = BridgeProductWireContract.maximumRequestBodyBytes,
        nextExpectedRequestSequence: Int = 1
    ) {
        precondition(
            maximumRequestOrResponseBytes > 0
                && maximumRequestOrResponseBytes
                    <= BridgeProductWireContract.maximumRequestBodyBytes
        )
        precondition(nextExpectedRequestSequence > 0)
        self.maximumRequestOrResponseBytes = maximumRequestOrResponseBytes
        self.nextExpectedRequestSequence = nextExpectedRequestSequence
    }

    var snapshot: BridgeProductControlReplaySnapshot {
        .init(
            inFlightRequestSequence: inFlightRequest?.token.requestSequence,
            nextExpectedRequestSequence: nextExpectedRequestSequence,
            replayableRequestSequence: completedRequest?.requestSequence
        )
    }

    mutating func begin(
        requestSequence: Int,
        exactRequestBytes: Data
    ) -> BridgeProductControlReplayAdmission {
        guard exactRequestBytes.count <= maximumRequestOrResponseBytes else {
            return .rejected(.payloadTooLarge)
        }
        guard inFlightRequest == nil else {
            return .rejected(
                .requestInFlight(nextExpectedRequestSequence: nextExpectedRequestSequence)
            )
        }
        guard requestSequence < BridgeProductWireContract.maximumSafeInteger else {
            return .rejected(
                .sequenceExhausted(nextExpectedRequestSequence: nextExpectedRequestSequence)
            )
        }

        let requestDigest = Self.digest(exactRequestBytes)
        if requestSequence == nextExpectedRequestSequence {
            let token = BridgeProductControlAdmissionToken(
                identifier: nextAdmissionIdentifier,
                requestSequence: requestSequence
            )
            nextAdmissionIdentifier &+= 1
            inFlightRequest = .init(
                exactRequestBytes: exactRequestBytes,
                requestDigest: requestDigest,
                token: token
            )
            return .execute(token)
        }

        if let completedRequest,
            completedRequest.requestSequence == requestSequence,
            completedRequest.requestDigest == requestDigest,
            completedRequest.exactRequestBytes == exactRequestBytes
        {
            return .replay(exactResponseBytes: completedRequest.exactResponseBytes)
        }

        return .rejected(
            .sequenceConflict(nextExpectedRequestSequence: nextExpectedRequestSequence)
        )
    }

    mutating func complete(
        token: BridgeProductControlAdmissionToken,
        exactResponseBytes: Data
    ) throws {
        guard let inFlightRequest, inFlightRequest.token == token else {
            throw BridgeProductControlReplayCacheError.invalidAdmissionToken
        }
        guard exactResponseBytes.count <= maximumRequestOrResponseBytes else {
            throw BridgeProductControlReplayCacheError.responsePayloadTooLarge
        }
        guard token.requestSequence < BridgeProductWireContract.maximumSafeInteger else {
            throw BridgeProductControlReplayCacheError.sequenceExhausted
        }

        completedRequest = .init(
            exactRequestBytes: inFlightRequest.exactRequestBytes,
            exactResponseBytes: exactResponseBytes,
            requestDigest: inFlightRequest.requestDigest,
            requestSequence: token.requestSequence
        )
        self.inFlightRequest = nil
        nextExpectedRequestSequence = token.requestSequence + 1
    }

    mutating func abandon(token: BridgeProductControlAdmissionToken) throws {
        guard inFlightRequest?.token == token else {
            throw BridgeProductControlReplayCacheError.invalidAdmissionToken
        }
        inFlightRequest = nil
    }

    mutating func replaceSequenceFloor(nextExpectedRequestSequence: Int) throws {
        guard
            nextExpectedRequestSequence > 0,
            nextExpectedRequestSequence <= BridgeProductWireContract.maximumSafeInteger
        else {
            throw BridgeProductControlReplayCacheError.invalidSequenceFloor
        }
        guard inFlightRequest == nil else {
            throw BridgeProductControlReplayCacheError.invalidAdmissionToken
        }
        self.nextExpectedRequestSequence = nextExpectedRequestSequence
        completedRequest = nil
    }

    private static func digest(_ data: Data) -> Data {
        Data(SHA256.hash(data: data))
    }
}
