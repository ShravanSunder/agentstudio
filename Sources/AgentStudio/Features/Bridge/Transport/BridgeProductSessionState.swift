import Foundation

enum BridgeProductSessionLifecycle: Equatable, Sendable {
    case awaitingOpen
    case opening
    case active
    case revoked
}

struct BridgeProductSessionPendingControl: Sendable {
    let deferredResyncEpochs: [BridgeProductSurface: Int]
    var providerDispatchCompletion: BridgeProductControlDispatchCompletion?
    let request: BridgeProductControlRequest
    let token: BridgeProductControlAdmissionToken
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

extension BridgeProductSessionControlRejection {
    init(replayRejection: BridgeProductControlReplayRejection) {
        switch replayRejection {
        case .payloadTooLarge:
            self = .payloadTooLarge
        case .requestInFlight(let nextExpectedRequestSequence):
            self = .requestInFlight(nextExpectedRequestSequence: nextExpectedRequestSequence)
        case .sequenceExhausted(let nextExpectedRequestSequence):
            self = .sequenceExhausted(nextExpectedRequestSequence: nextExpectedRequestSequence)
        case .sequenceConflict(let nextExpectedRequestSequence):
            self = .sequenceConflict(nextExpectedRequestSequence: nextExpectedRequestSequence)
        }
    }
}

struct BridgeProductSessionControlRejectionContext: Equatable, Sendable {
    let reason: BridgeProductSessionControlRejection
    let request: BridgeProductControlRequest?

    init(
        reason: BridgeProductSessionControlRejection,
        request: BridgeProductControlRequest? = nil
    ) {
        self.reason = reason
        self.request = request
    }

    static let inactiveSession = Self(reason: .inactiveSession)
    static let invalidRequest = Self(reason: .invalidRequest)
    static let payloadTooLarge = Self(reason: .payloadTooLarge)
    static let revoked = Self(reason: .revoked)
    static let staleWorker = Self(reason: .staleWorker)
    static let unauthorized = Self(reason: .unauthorized)

    static func requestInFlight(
        nextExpectedRequestSequence: Int
    ) -> Self {
        .init(reason: .requestInFlight(nextExpectedRequestSequence: nextExpectedRequestSequence))
    }

    static func sequenceExhausted(
        nextExpectedRequestSequence: Int
    ) -> Self {
        .init(reason: .sequenceExhausted(nextExpectedRequestSequence: nextExpectedRequestSequence))
    }

    static func sequenceConflict(
        nextExpectedRequestSequence: Int
    ) -> Self {
        .init(reason: .sequenceConflict(nextExpectedRequestSequence: nextExpectedRequestSequence))
    }

    static func streamSequenceConflict(
        nextMetadataStreamSequence: Int
    ) -> Self {
        .init(reason: .streamSequenceConflict(nextMetadataStreamSequence: nextMetadataStreamSequence))
    }

    static func staleDerivationEpoch(
        currentWorkerDerivationEpoch: Int,
        surface: BridgeProductSurface
    ) -> Self {
        .init(
            reason: .staleDerivationEpoch(
                currentWorkerDerivationEpoch: currentWorkerDerivationEpoch,
                surface: surface
            )
        )
    }
}

enum BridgeProductSessionControlAdmission: Equatable, Sendable {
    case execute(
        token: BridgeProductControlAdmissionToken,
        request: BridgeProductControlRequest
    )
    case replay(exactResponseBytes: Data)
    case rejected(BridgeProductSessionControlRejectionContext)
}

enum BridgeProductSessionError: Error, Equatable {
    case invalidRequestOrResponseByteLimit
    case invalidControlResponse
    case invalidAdmissionToken
    case mismatchedControlResponse
    case providerDispatchAlreadyClaimed
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
    let pendingControlProviderDispatched: Bool
    let pendingRequestKind: String?
    let workerDerivationEpochBySurface: [BridgeProductSurface: Int]
}
