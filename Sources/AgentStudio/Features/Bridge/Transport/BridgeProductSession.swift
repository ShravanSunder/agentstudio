import CryptoKit
import Foundation

actor BridgeProductSession {
    typealias ProducerLifecycleAcknowledger =
        @Sendable (BridgeProductProducerLifecycleAcknowledgement) async -> Bool

    private struct PendingControl: Sendable {
        let deferredResyncEpochs: [BridgeProductSurface: Int]
        let request: BridgeProductControlRequest
        let token: BridgeProductControlAdmissionToken
    }

    private let capabilityDigest: Data
    private let maximumRequestOrResponseBytes: Int
    private let paneSessionId: String
    private var producerRegistry: BridgeProductProducerRegistry
    private var revocationState = BridgeProductSessionRevocationState.idle
    private let workerInstanceId: String
    private var contentAdmissionByProducerLease: [BridgeProductProducerLease: BridgeProductContentAdmission] = [:]
    private var controlReplay: BridgeProductControlReplayCache
    private var lifecycle: BridgeProductSessionLifecycle = .awaitingOpen
    private var pendingControl: PendingControl?
    private var subscriptionState = BridgeProductSubscriptionState()
    private var workerDerivationEpochBySurface: [BridgeProductSurface: Int] = [
        .review: 0,
        .file: 0,
    ]

    init(
        paneSessionId: String,
        workerInstanceId: String,
        capabilityBytes: [UInt8],
        maximumRequestOrResponseBytes: Int = BridgeProductWireContract.maximumRequestBodyBytes
    ) throws {
        guard maximumRequestOrResponseBytes > 0,
            maximumRequestOrResponseBytes <= BridgeProductWireContract.maximumRequestBodyBytes
        else {
            throw BridgeProductSessionError.invalidRequestOrResponseByteLimit
        }
        try BridgeProductContractDecoding.validateIdentifier(paneSessionId, codingPath: [])
        try BridgeProductContractDecoding.validateIdentifier(workerInstanceId, codingPath: [])
        let capabilityHeader = try BridgeProductCapabilityHeaderEncoding.encode(capabilityBytes)
        self.paneSessionId = paneSessionId
        self.workerInstanceId = workerInstanceId
        self.capabilityDigest = Self.digest(Data(capabilityHeader.utf8))
        self.maximumRequestOrResponseBytes = maximumRequestOrResponseBytes
        self.producerRegistry = BridgeProductProducerRegistry()
        self.controlReplay = .init(
            maximumRequestOrResponseBytes: maximumRequestOrResponseBytes
        )
    }

    var snapshot: BridgeProductSessionSnapshot {
        .init(
            controlReplay: controlReplay.snapshot,
            lifecycle: lifecycle,
            pendingRequestKind: pendingControl?.request.kind,
            workerDerivationEpochBySurface: workerDerivationEpochBySurface
        )
    }

    func subscriptionSnapshot(
        subscriptionId: String
    ) -> BridgeProductSubscriptionSnapshot? {
        subscriptionState.snapshot(subscriptionId: subscriptionId)
    }

    func registerMetadataProducer(
        request: BridgeProductMetadataStreamRequest,
        operation: @escaping @Sendable (BridgeProductProducerLease) async -> Void
    ) -> BridgeProductProducerRegistration {
        guard lifecycle == .active else { return .rejected(.inactiveSession) }
        guard request.paneSessionId == paneSessionId,
            request.workerInstanceId == workerInstanceId
        else {
            return .rejected(.staleWorker)
        }
        return producerRegistry.registerMetadataProducer(
            request: request,
            operation: operation,
            completion: producerCompletion
        )
    }

    func registerContentProducer(
        request: BridgeProductContentRequest,
        operation: @escaping @Sendable (BridgeProductProducerLease) async -> Void
    ) -> BridgeProductProducerRegistration {
        let admission = request.admission
        guard lifecycle == .active else { return .rejected(.inactiveSession) }
        guard admission.paneSessionId == paneSessionId,
            admission.workerInstanceId == workerInstanceId
        else {
            return .rejected(.staleWorker)
        }

        let surface = admission.identity.surface
        let currentEpoch = workerDerivationEpochBySurface[surface, default: 0]
        guard admission.workerDerivationEpoch >= currentEpoch else {
            return .rejected(.staleSurfaceEpoch(currentFloor: currentEpoch))
        }
        advanceSurfaceFloorIfNeeded(
            surface: surface,
            workerDerivationEpoch: admission.workerDerivationEpoch
        )
        let registration = producerRegistry.registerContentProducer(
            request: request,
            operation: operation,
            completion: producerCompletion
        )
        if case .accepted(let lease) = registration {
            contentAdmissionByProducerLease[lease] = admission
        }
        return registration
    }

    func enqueueRequiredProducerOpeningFrame(
        for lease: BridgeProductProducerLease,
        build: @Sendable (Int) throws -> BridgeProductProducerFrame
    ) throws -> BridgeProductProducerEnqueueResult {
        try producerRegistry.enqueueRequiredOpeningFrame(for: lease, build: build)
    }

    func enqueueProducerFrame(
        for lease: BridgeProductProducerLease,
        build: @Sendable (Int) throws -> BridgeProductProducerFrame,
        overflowReset: @Sendable (Int) throws -> BridgeProductProducerFrame
    ) throws -> BridgeProductProducerEnqueueResult {
        try producerRegistry.enqueueNonterminalFrame(
            for: lease,
            build: build,
            overflowReset: overflowReset
        )
    }

    func enqueueTerminalProducerFrame(
        for lease: BridgeProductProducerLease,
        build: @Sendable (Int) throws -> BridgeProductProducerFrame
    ) throws -> BridgeProductProducerEnqueueResult {
        try producerRegistry.enqueueTerminalFrame(for: lease, build: build)
    }

    func dequeueProducerFrame(
        for lease: BridgeProductProducerLease
    ) -> BridgeProductQueuedProducerFrame? {
        producerRegistry.dequeueFrame(for: lease)
    }

    func stopProducer(
        _ lease: BridgeProductProducerLease
    ) async -> Bool {
        guard let stopRequest = producerRegistry.requestStop([lease]).first else {
            return false
        }
        await stopRequest.task?.value
        return producerRegistry.producerIsStopped(lease)
    }

    func unregisterProducer(
        _ lease: BridgeProductProducerLease
    ) -> BridgeProductProducerLifecycleAcknowledgement? {
        guard lifecycle != .revoked else { return nil }
        return producerRegistry.unregister(lease)
    }

    func acknowledgeProducerLifecycle(
        _ acknowledgement: BridgeProductProducerLifecycleAcknowledgement
    ) -> Bool {
        guard lifecycle != .revoked else { return false }
        let acknowledged = producerRegistry.acknowledgeLifecycle(acknowledgement)
        if acknowledged {
            contentAdmissionByProducerLease.removeValue(
                forKey: acknowledgement.producerLease
            )
        }
        return acknowledged
    }

    func producerSnapshot() -> BridgeProductProducerRegistrySnapshot {
        producerRegistry.snapshot()
    }

    private var producerCompletion: BridgeProductProducerRegistry.ProducerCompletion {
        { [weak self] lease in
            await self?.producerOperationFinished(lease)
        }
    }

    func authorizes(presentedCapability: String) -> Bool {
        guard lifecycle != .revoked else { return false }
        return capabilityMatches(presentedCapability)
    }

    func beginControl(
        exactRequestBytes: Data,
        presentedCapability: String
    ) -> BridgeProductSessionControlAdmission {
        guard lifecycle != .revoked else { return .rejected(.revoked) }
        guard capabilityMatches(presentedCapability) else { return .rejected(.unauthorized) }
        guard exactRequestBytes.count <= maximumRequestOrResponseBytes else {
            return .rejected(.payloadTooLarge)
        }
        guard
            let request = try? BridgeProductStrictJSON.decode(
                BridgeProductControlRequest.self,
                from: exactRequestBytes
            )
        else {
            return .rejected(.invalidRequest)
        }
        guard request.paneSessionId == paneSessionId,
            request.workerInstanceId == workerInstanceId
        else {
            return .rejected(.staleWorker)
        }

        switch controlReplay.begin(
            requestSequence: request.requestSequence,
            exactRequestBytes: exactRequestBytes
        ) {
        case .replay(let exactResponseBytes):
            return .replay(exactResponseBytes: exactResponseBytes)
        case .rejected(let rejection):
            return .rejected(Self.controlRejection(for: rejection))
        case .execute(let token):
            if let streamProgressRejection = streamProgressRejection(for: request) {
                try? controlReplay.abandon(token: token)
                return .rejected(streamProgressRejection)
            }
            guard let deferredResyncEpochs = prepare(request: request) else {
                try? controlReplay.abandon(token: token)
                return rejectionForUnpreparedRequest(request)
            }
            pendingControl = .init(
                deferredResyncEpochs: deferredResyncEpochs,
                request: request,
                token: token
            )
            return .execute(token)
        }
    }

    func completeControl(
        token: BridgeProductControlAdmissionToken,
        exactResponseBytes: Data
    ) throws -> BridgeProductSessionCompletionEffects {
        guard let pendingControl, pendingControl.token == token else {
            throw BridgeProductSessionError.invalidAdmissionToken
        }
        guard exactResponseBytes.count <= maximumRequestOrResponseBytes,
            let response = try? BridgeProductStrictJSON.decode(
                BridgeProductControlResponse.self,
                from: exactResponseBytes
            )
        else {
            throw BridgeProductSessionError.invalidControlResponse
        }
        guard response.correlation == pendingControl.request.correlation else {
            throw BridgeProductSessionError.mismatchedControlResponse
        }
        try BridgeProductSessionControlTransitionBuilder.validateResponseShape(
            request: pendingControl.request,
            response: response
        )

        if pendingControlIsStale(pendingControl) {
            try controlReplay.complete(token: token, exactResponseBytes: exactResponseBytes)
            self.pendingControl = nil
            return .noEffects
        }

        let transition: BridgeProductSessionControlTransition
        do {
            transition = try BridgeProductSessionControlTransitionBuilder.prepare(
                request: pendingControl.request,
                response: response,
                subscriptionState: subscriptionState,
                resyncEpochs: pendingControl.deferredResyncEpochs,
                currentEpochs: workerDerivationEpochBySurface
            )
        } catch let stateError as BridgeProductSubscriptionStateError {
            throw BridgeProductSessionError.subscriptionStateRejected(stateError)
        }

        if transition.effects.resync != nil {
            for (surface, epoch) in pendingControl.deferredResyncEpochs {
                advanceSurfaceFloorIfNeeded(
                    surface: surface,
                    workerDerivationEpoch: epoch
                )
            }
        }
        try controlReplay.complete(token: token, exactResponseBytes: exactResponseBytes)
        subscriptionState = transition.subscriptionState
        applyCompletedLifecycle(
            request: pendingControl.request,
            response: response
        )
        self.pendingControl = nil
        return transition.effects
    }

    func abandonControl(token: BridgeProductControlAdmissionToken) throws {
        guard let pendingControl, pendingControl.token == token else {
            throw BridgeProductSessionError.invalidAdmissionToken
        }
        try controlReplay.abandon(token: token)
        if case .workerSessionOpen = pendingControl.request {
            lifecycle = .awaitingOpen
        }
        self.pendingControl = nil
    }

    func revoke(
        acknowledgeLifecycle: @escaping ProducerLifecycleAcknowledger
    ) -> BridgeProductSessionRevocationBarrier {
        switch revocationState {
        case .idle:
            break
        case .inFlight(let barrier):
            return barrier
        case .succeeded(let id):
            return BridgeProductSessionRevocationBarrier(id: id, completedResult: true)
        }
        lifecycle = .revoked
        if let pendingControl {
            try? controlReplay.abandon(token: pendingControl.token)
        }
        pendingControl = nil
        subscriptionState.revokeWorker()
        let claimedAcknowledgements = producerRegistry.pendingLifecycleAcknowledgements()
        let stopRequests = producerRegistry.requestStopEveryProducer(revoking: true)
        let revocationId = UUID()
        let barrier = BridgeProductSessionRevocationBarrier(
            id: revocationId,
            task: Task { [self] in
                var didRevoke = true
                for stopRequest in stopRequests {
                    await stopRequest.task?.value
                }
                claimedAcknowledgementDrain: do {
                    for acknowledgement in claimedAcknowledgements {
                        guard await acknowledgeLifecycle(acknowledgement),
                            producerRegistry.acknowledgeLifecycle(acknowledgement)
                        else {
                            didRevoke = false
                            break claimedAcknowledgementDrain
                        }
                        contentAdmissionByProducerLease.removeValue(
                            forKey: acknowledgement.producerLease
                        )
                    }
                }
                stoppedProducerDrain: do {
                    guard didRevoke else { break stoppedProducerDrain }
                    for stopRequest in stopRequests {
                        let lease = stopRequest.lease
                        guard let acknowledgement = producerRegistry.unregister(lease),
                            await acknowledgeLifecycle(acknowledgement),
                            producerRegistry.acknowledgeLifecycle(acknowledgement)
                        else {
                            didRevoke = false
                            break stoppedProducerDrain
                        }
                        contentAdmissionByProducerLease.removeValue(forKey: lease)
                    }
                }
                didRevoke = didRevoke && producerRegistry.snapshot().hasZeroResidue
                revocationState = didRevoke ? .succeeded(id: revocationId) : .idle
                return didRevoke
            }
        )
        revocationState = .inFlight(barrier)
        return barrier
    }

    private func prepare(
        request: BridgeProductControlRequest
    ) -> [BridgeProductSurface: Int]? {
        switch request {
        case .workerSessionOpen:
            guard lifecycle == .awaitingOpen else { return nil }
            lifecycle = .opening
            return [:]
        case .workerSessionResync(let resyncRequest):
            guard lifecycle == .active,
                resyncRequest.lastAcceptedRequestSequence
                    < BridgeProductWireContract.maximumSafeInteger,
                resyncRequest.lastAcceptedRequestSequence + 1 == request.requestSequence
            else {
                return nil
            }
            return preflightResyncEpochs(resyncRequest.activeSubscriptions)
        case .productCall, .subscriptionOpen, .subscriptionUpdateBatch, .subscriptionCancel:
            guard lifecycle == .active,
                let surface = request.surface,
                let workerDerivationEpoch = request.workerDerivationEpoch
            else {
                return nil
            }
            let currentEpoch = workerDerivationEpochBySurface[surface, default: 0]
            guard workerDerivationEpoch >= currentEpoch else { return nil }
            advanceSurfaceFloorIfNeeded(
                surface: surface,
                workerDerivationEpoch: workerDerivationEpoch
            )
            return [:]
        }
    }

    private func pendingControlIsStale(_ pendingControl: PendingControl) -> Bool {
        if let surface = pendingControl.request.surface,
            let admittedEpoch = pendingControl.request.workerDerivationEpoch
        {
            return admittedEpoch < workerDerivationEpochBySurface[surface, default: 0]
        }
        return pendingControl.deferredResyncEpochs.contains { surface, admittedEpoch in
            admittedEpoch < workerDerivationEpochBySurface[surface, default: 0]
        }
    }

    private func producerOperationFinished(_ lease: BridgeProductProducerLease) {
        producerRegistry.producerOperationFinished(lease)
    }

    private func streamProgressRejection(
        for request: BridgeProductControlRequest
    ) -> BridgeProductSessionControlRejection? {
        guard case .workerSessionResync(let resyncRequest) = request else { return nil }
        let nextMetadataStreamSequence = producerRegistry.snapshot().nextMetadataStreamSequence
        guard resyncRequest.lastAcceptedStreamSequence < nextMetadataStreamSequence else {
            return .streamSequenceConflict(
                nextMetadataStreamSequence: nextMetadataStreamSequence
            )
        }
        return nil
    }

    private func advanceSurfaceFloorIfNeeded(
        surface: BridgeProductSurface,
        workerDerivationEpoch: Int
    ) {
        let currentEpoch = workerDerivationEpochBySurface[surface, default: 0]
        guard workerDerivationEpoch > currentEpoch else { return }

        workerDerivationEpochBySurface[surface] = workerDerivationEpoch
        subscriptionState.reset(surface: surface)
        let staleLeases = contentAdmissionByProducerLease.compactMap { entry -> BridgeProductProducerLease? in
            let (lease, admission) = entry
            guard admission.identity.surface == surface,
                admission.workerDerivationEpoch < workerDerivationEpoch
            else {
                return nil
            }
            return lease
        }
        _ = producerRegistry.requestStop(staleLeases)
    }

    private func rejectionForUnpreparedRequest(
        _ request: BridgeProductControlRequest
    ) -> BridgeProductSessionControlAdmission {
        if case .workerSessionResync(let resyncRequest) = request,
            lifecycle == .active,
            resyncRequest.lastAcceptedRequestSequence + 1 != request.requestSequence
        {
            return .rejected(
                .sequenceConflict(
                    nextExpectedRequestSequence: controlReplay.snapshot.nextExpectedRequestSequence
                )
            )
        }
        guard let surface = request.surface,
            let workerDerivationEpoch = request.workerDerivationEpoch
        else {
            return .rejected(.inactiveSession)
        }
        let currentEpoch = workerDerivationEpochBySurface[surface, default: 0]
        guard workerDerivationEpoch < currentEpoch else {
            return .rejected(.inactiveSession)
        }
        return .rejected(
            .staleDerivationEpoch(
                currentWorkerDerivationEpoch: currentEpoch,
                surface: surface
            )
        )
    }

    private func preflightResyncEpochs(
        _ activeSubscriptions: [BridgeProductActiveSubscription]
    ) -> [BridgeProductSurface: Int]? {
        var candidateEpochs: [BridgeProductSurface: Int] = [:]
        for subscription in activeSubscriptions {
            let surface = subscription.surface
            if let candidateEpoch = candidateEpochs[surface],
                candidateEpoch != subscription.workerDerivationEpoch
            {
                return nil
            }
            guard
                subscription.workerDerivationEpoch
                    >= workerDerivationEpochBySurface[surface, default: 0]
            else {
                return nil
            }
            candidateEpochs[surface] = subscription.workerDerivationEpoch
        }
        return candidateEpochs
    }

    private func applyCompletedLifecycle(
        request: BridgeProductControlRequest,
        response: BridgeProductControlResponse
    ) {
        switch (request, response) {
        case (.workerSessionOpen, .workerSessionAccepted):
            lifecycle = .active
        case (.workerSessionOpen, .requestError):
            lifecycle = .awaitingOpen
        case (.workerSessionResync, .resyncAccepted):
            break
        default:
            break
        }
    }

    private func capabilityMatches(_ presentedCapability: String) -> Bool {
        guard presentedCapability.utf8.count == 43 else { return false }
        let presentedDigest = Self.digest(Data(presentedCapability.utf8))
        guard presentedDigest.count == capabilityDigest.count else { return false }
        return zip(presentedDigest, capabilityDigest).reduce(UInt8(0)) { difference, pair in
            difference | (pair.0 ^ pair.1)
        } == 0
    }

    private static func controlRejection(
        for replayRejection: BridgeProductControlReplayRejection
    ) -> BridgeProductSessionControlRejection {
        switch replayRejection {
        case .payloadTooLarge:
            .payloadTooLarge
        case .requestInFlight(let nextExpectedRequestSequence):
            .requestInFlight(nextExpectedRequestSequence: nextExpectedRequestSequence)
        case .sequenceExhausted(let nextExpectedRequestSequence):
            .sequenceExhausted(nextExpectedRequestSequence: nextExpectedRequestSequence)
        case .sequenceConflict(let nextExpectedRequestSequence):
            .sequenceConflict(nextExpectedRequestSequence: nextExpectedRequestSequence)
        }
    }

    private static func digest(_ data: Data) -> Data {
        Data(SHA256.hash(data: data))
    }
}
