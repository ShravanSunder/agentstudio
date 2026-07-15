import CryptoKit
import Foundation

actor BridgeProductSession {
    typealias ProducerLifecycleAcknowledger =
        @Sendable (BridgeProductProducerLifecycleAcknowledgement) async -> Bool

    private let capabilityDigest: Data
    private let maximumRequestOrResponseBytes: Int
    private let paneSessionId: String
    var producerRegistry: BridgeProductProducerRegistry
    private var lastAcceptedContentFrameAcknowledgementByProducerLease:
        [BridgeProductProducerLease: BridgeProductContentFrameAcknowledgement] = [:]
    private var lastAcceptedMetadataFrameAcknowledgement: BridgeProductMetadataFrameAcknowledgement?
    private var revocationState = BridgeProductSessionRevocationState.idle
    private let workerInstanceId: String
    var contentAdmissionByProducerLease: [BridgeProductProducerLease: BridgeProductContentAdmission] = [:]
    var producerFrameObservationByLease: [BridgeProductProducerLease: BridgeProductSessionProducerFrameObservation] =
        [:]
    var producerFrameWaitersByLease: [BridgeProductProducerLease: BridgeProductSessionProducerFrameWaiter] = [:]
    var producerObservationPacingWaitersByLease: [BridgeProductProducerLease: BridgeProductProducerPacingWaiter] = [:]
    var producerRetirementStateByLease: [BridgeProductProducerLease: BridgeProductSessionProducerRetirementState] = [:]
    private var controlReplay: BridgeProductControlReplayCache
    private var lifecycle: BridgeProductSessionLifecycle = .awaitingOpen
    var pendingControl: BridgeProductSessionPendingControl?
    var protocolSubscriptionDeliveryById: [String: BridgeProductProtocolSubscriptionDelivery] = [:]
    var subscriptionState = BridgeProductSubscriptionState()
    var workerDerivationEpochBySurface: [BridgeProductSurface: Int] = [
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
        self.lastAcceptedMetadataFrameAcknowledgement = nil
        self.producerRegistry = BridgeProductProducerRegistry()
        self.controlReplay = .init(
            maximumRequestOrResponseBytes: maximumRequestOrResponseBytes
        )
    }

    var snapshot: BridgeProductSessionSnapshot {
        .init(
            controlReplay: controlReplay.snapshot,
            lifecycle: lifecycle,
            pendingControlProviderDispatched:
                pendingControl?.providerDispatchCompletion != nil,
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
        let result = try producerRegistry.enqueueRequiredOpeningFrame(for: lease, build: build)
        resumeProducerFrameWaiterIfPossible(for: lease)
        return result
    }

    func enqueueProducerFrame(
        for lease: BridgeProductProducerLease,
        build: @Sendable (Int) throws -> BridgeProductProducerFrame,
        overflowReset: @Sendable (Int) throws -> BridgeProductProducerFrame
    ) throws -> BridgeProductProducerEnqueueResult {
        let result = try producerRegistry.enqueueNonterminalFrame(
            for: lease,
            build: build,
            overflowReset: overflowReset
        )
        resumeProducerFrameWaiterIfPossible(for: lease)
        return result
    }

    func enqueueTerminalProducerFrame(
        for lease: BridgeProductProducerLease,
        build: @Sendable (Int) throws -> BridgeProductProducerFrame
    ) throws -> BridgeProductProducerEnqueueResult {
        let result = try producerRegistry.enqueueTerminalFrame(for: lease, build: build)
        resumeProducerFrameWaiterIfPossible(for: lease)
        return result
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
        guard lifecycle != .revoked,
            producerRetirementStateByLease[lease] == nil
        else { return nil }
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
            resolveProducerObservationPacingCancellation(
                for: acknowledgement.producerLease
            )
            clearContentFrameObservationReplay(
                for: acknowledgement.producerLease
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

    func acknowledgeMetadataFrameObservation(
        _ acknowledgement: BridgeProductMetadataFrameAcknowledgement
    ) -> Bool {
        guard lifecycle == .active,
            acknowledgement.paneSessionId == paneSessionId,
            acknowledgement.workerInstanceId == workerInstanceId
        else {
            return false
        }
        if lastAcceptedMetadataFrameAcknowledgement == acknowledgement {
            return true
        }
        guard
            let receipt = producerRegistry.inFlightMetadataFrameReceipt(
                matching: acknowledgement
            ), acknowledgeProducerFrameObserved(receipt)
        else {
            return false
        }
        lastAcceptedMetadataFrameAcknowledgement = acknowledgement
        return true
    }

    func acknowledgeContentFrameObservation(
        _ acknowledgement: BridgeProductContentFrameAcknowledgement
    ) -> Bool {
        guard lifecycle == .active,
            acknowledgement.paneSessionId == paneSessionId,
            acknowledgement.workerInstanceId == workerInstanceId
        else {
            return false
        }
        if lastAcceptedContentFrameAcknowledgementByProducerLease.values.contains(
            acknowledgement
        ) {
            return true
        }
        guard
            let receipt = producerRegistry.inFlightContentFrameReceipt(
                matching: acknowledgement
            ), acknowledgeProducerFrameObserved(receipt)
        else {
            return false
        }
        lastAcceptedContentFrameAcknowledgementByProducerLease[receipt.producerLease] =
            acknowledgement
        return true
    }

    func clearContentFrameObservationReplay(
        for producerLease: BridgeProductProducerLease
    ) {
        lastAcceptedContentFrameAcknowledgementByProducerLease.removeValue(
            forKey: producerLease
        )
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
            return .rejected(.init(reason: .staleWorker, request: request))
        }
        if pendingControl != nil {
            return .rejected(
                .init(
                    reason: .requestInFlight(
                        nextExpectedRequestSequence: controlReplay.snapshot.nextExpectedRequestSequence
                    ),
                    request: request
                )
            )
        }

        switch controlReplay.begin(
            requestSequence: request.requestSequence,
            exactRequestBytes: exactRequestBytes
        ) {
        case .replay(let exactResponseBytes):
            return .replay(exactResponseBytes: exactResponseBytes)
        case .rejected(let rejection):
            return .rejected(
                .init(
                    reason: .init(replayRejection: rejection),
                    request: request
                )
            )
        case .execute(let token):
            if let streamProgressRejection = streamProgressRejection(for: request) {
                try? controlReplay.abandon(token: token)
                return .rejected(
                    .init(reason: streamProgressRejection, request: request)
                )
            }
            guard let deferredResyncEpochs = prepare(request: request) else {
                try? controlReplay.abandon(token: token)
                return rejectionForUnpreparedRequest(request)
            }
            pendingControl = .init(
                deferredResyncEpochs: deferredResyncEpochs,
                providerDispatchCompletion: nil,
                request: request,
                token: token
            )
            return .execute(token: token, request: request)
        }
    }

    func claimControlProviderDispatch(
        token: BridgeProductControlAdmissionToken
    ) -> Bool {
        guard var pendingControl,
            pendingControl.token == token,
            pendingControl.providerDispatchCompletion == nil,
            lifecycle != .revoked
        else {
            return false
        }
        pendingControl.providerDispatchCompletion = BridgeProductControlDispatchCompletion()
        self.pendingControl = pendingControl
        return true
    }

    func completeControl(
        token: BridgeProductControlAdmissionToken,
        exactResponseBytes: Data
    ) async throws -> BridgeProductSessionCompletionEffect {
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

        if lifecycle == .revoked || pendingControlIsStale(pendingControl) {
            try controlReplay.complete(token: token, exactResponseBytes: exactResponseBytes)
            await settlePendingControl(pendingControl)
            return .noEffect
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

        if case .resynced = transition.effect {
            for (surface, epoch) in pendingControl.deferredResyncEpochs {
                advanceSurfaceFloorIfNeeded(
                    surface: surface,
                    workerDerivationEpoch: epoch
                )
            }
        }
        if pendingControl.providerDispatchCompletion != nil {
            try admitRequiredProtocolLifecycleFrame(for: transition.effect)
        }
        try controlReplay.complete(token: token, exactResponseBytes: exactResponseBytes)
        subscriptionState = transition.subscriptionState
        if case .resynced(let resyncResult) = transition.effect {
            reconcileProtocolSubscriptionDeliveries(resyncResult)
        }
        applyCompletedLifecycle(
            request: pendingControl.request,
            response: response
        )
        if transition.effect == .noEffect
            || pendingControl.providerDispatchCompletion == nil
        {
            await settlePendingControl(pendingControl)
        }
        return transition.effect
    }

    func settleControlProviderDispatch(
        token: BridgeProductControlAdmissionToken
    ) async {
        guard let pendingControl, pendingControl.token == token else { return }
        if controlReplay.snapshot.inFlightRequestSequence == token.requestSequence {
            try? controlReplay.abandon(token: token)
            if lifecycle != .revoked,
                case .workerSessionOpen = pendingControl.request
            {
                lifecycle = .awaitingOpen
            }
        }
        await settlePendingControl(pendingControl)
    }

    func abandonControl(token: BridgeProductControlAdmissionToken) throws {
        guard let pendingControl, pendingControl.token == token else {
            throw BridgeProductSessionError.invalidAdmissionToken
        }
        guard pendingControl.providerDispatchCompletion == nil else {
            throw BridgeProductSessionError.providerDispatchAlreadyClaimed
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
        lastAcceptedContentFrameAcknowledgementByProducerLease.removeAll(
            keepingCapacity: false
        )
        let pendingProviderDispatchCompletion =
            pendingControl?.providerDispatchCompletion
        if let pendingControl {
            if pendingProviderDispatchCompletion == nil {
                try? controlReplay.abandon(token: pendingControl.token)
                self.pendingControl = nil
            }
        }
        subscriptionState.revokeWorker()
        protocolSubscriptionDeliveryById.removeAll(keepingCapacity: false)
        let producerResidueLeases = producerRegistry.lifecycleResidueLeases()
        let stopRequests = producerRegistry.requestStopEveryProducer(revoking: true)
        let stopRequestByLease = Dictionary(
            uniqueKeysWithValues: stopRequests.map { ($0.lease, $0) }
        )
        let retirementBarriers = producerResidueLeases.map { lease in
            beginProducerRetirement(
                lease,
                acknowledgeLifecycle: acknowledgeLifecycle,
                stopRequest: stopRequestByLease[lease],
                abandonOutstandingDelivery: true
            )
        }
        let revocationId = UUID()
        let barrier = BridgeProductSessionRevocationBarrier(
            id: revocationId,
            task: Task { [self] in
                var didRevoke = true
                if let pendingProviderDispatchCompletion {
                    await pendingProviderDispatchCompletion.wait()
                }
                for retirementBarrier in retirementBarriers {
                    guard await retirementBarrier.wait() else {
                        didRevoke = false
                        break
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

    private func pendingControlIsStale(
        _ pendingControl: BridgeProductSessionPendingControl
    ) -> Bool {
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
        resolveProducerObservationPacingCancellation(for: lease)
        producerRegistry.producerOperationFinished(lease)
        resumeProducerFrameWaiterIfPossible(for: lease)
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
                .init(
                    reason: .sequenceConflict(
                        nextExpectedRequestSequence: controlReplay.snapshot.nextExpectedRequestSequence
                    ),
                    request: request
                )
            )
        }
        guard let surface = request.surface,
            let workerDerivationEpoch = request.workerDerivationEpoch
        else {
            return .rejected(.init(reason: .inactiveSession, request: request))
        }
        let currentEpoch = workerDerivationEpochBySurface[surface, default: 0]
        guard workerDerivationEpoch < currentEpoch else {
            return .rejected(.init(reason: .inactiveSession, request: request))
        }
        return .rejected(
            .init(
                reason: .staleDerivationEpoch(
                    currentWorkerDerivationEpoch: currentEpoch,
                    surface: surface
                ),
                request: request
            )
        )
    }

    private func settlePendingControl(
        _ pendingControl: BridgeProductSessionPendingControl
    ) async {
        self.pendingControl = nil
        await pendingControl.providerDispatchCompletion?.complete()
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

    private static func digest(_ data: Data) -> Data {
        Data(SHA256.hash(data: data))
    }
}
