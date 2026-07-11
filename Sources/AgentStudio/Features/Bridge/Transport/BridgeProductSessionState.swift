import Foundation

enum BridgeProductSessionLifecycle: Equatable, Sendable {
    case awaitingOpen
    case opening
    case active
    case revoked
}

enum BridgeProductSessionControlRejection: Equatable, Sendable {
    case inactiveSession
    case invalidRequest
    case payloadTooLarge
    case requestInFlight(nextExpectedRequestSequence: Int)
    case revoked
    case sequenceExhausted(nextExpectedRequestSequence: Int)
    case sequenceConflict(nextExpectedRequestSequence: Int)
    case streamSequenceConflict(nextMetadataStreamSequence: Int)
    case staleDerivationEpoch(
        currentWorkerDerivationEpoch: Int,
        surface: BridgeProductSurface
    )
    case staleWorker
    case unauthorized
}

enum BridgeProductSessionControlAdmission: Equatable, Sendable {
    case execute(BridgeProductControlAdmissionToken)
    case replay(exactResponseBytes: Data)
    case rejected(BridgeProductSessionControlRejection)
}

enum BridgeProductSessionError: Error, Equatable {
    case invalidRequestOrResponseByteLimit
    case invalidControlResponse
    case invalidAdmissionToken
    case mismatchedControlResponse
    case subscriptionStateRejected(BridgeProductSubscriptionStateError)
}

struct BridgeProductSessionCompletionEffects: Equatable, Sendable {
    let commitBarrierIntent: BridgeProductSubscriptionCommitBarrierIntent?
    let cancelledSubscription: BridgeProductSubscriptionSnapshot?
    let resync: BridgeProductSubscriptionResyncResult?

    static let noEffects = Self(
        commitBarrierIntent: nil,
        cancelledSubscription: nil,
        resync: nil
    )
}

struct BridgeProductSessionSnapshot: Equatable, Sendable {
    let controlReplay: BridgeProductControlReplaySnapshot
    let lifecycle: BridgeProductSessionLifecycle
    let pendingRequestKind: String?
    let workerDerivationEpochBySurface: [BridgeProductSurface: Int]
}
