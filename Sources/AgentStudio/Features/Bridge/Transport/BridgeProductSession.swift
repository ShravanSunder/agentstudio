import Foundation

private struct BridgeProductMetadataFrameAcknowledgementReplay {
    let acknowledgement: BridgeProductMetadataFrameAcknowledgement
    let producerLease: BridgeProductProducerLease
}

actor BridgeProductSession {
    typealias ProducerLifecycleAcknowledger =
        @Sendable (BridgeProductProducerLifecycleAcknowledgement) async -> Bool

    nonisolated let capabilityAuthenticator: BridgeProductCapabilityAuthenticator
    private let maximumRequestOrResponseBytes: Int
    private let paneSessionId: String
    var producerRegistry: BridgeProductProducerRegistry
    private var lastAcceptedContentFrameAcknowledgementByProducerLease:
        [BridgeProductProducerLease: BridgeProductContentFrameAcknowledgement] = [:]
    private var lastAcceptedMetadataFrameAcknowledgement: BridgeProductMetadataFrameAcknowledgementReplay?
    private var revocationState = BridgeProductSessionRevocationState.idle
    private let workerInstanceId: String
    var contentAdmissionByProducerLease: [BridgeProductProducerLease: BridgeProductContentAdmission] = [:]
    var productAdmissionByProducerLease: [BridgeProductProducerLease: BridgeProductAdmissionContext] = [:]
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
        self.capabilityAuthenticator = BridgeProductCapabilityAuthenticator(
            encodedCapability: capabilityHeader
        )
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
        productAdmission: BridgeProductAdmissionContext,
        operation: @escaping @Sendable (BridgeProductProducerLease) async -> Void
    ) -> BridgeProductProducerRegistration {
        productAdmission.withValidAdmission {
            guard lifecycle == .active else { return .rejected(.inactiveSession) }
            guard request.paneSessionId == paneSessionId,
                request.workerInstanceId == workerInstanceId
            else {
                return .rejected(.staleWorker)
            }
            let registration = producerRegistry.registerMetadataProducer(
                request: request,
                operation: operation,
                completion: producerCompletion
            )
            if case .accepted(let lease) = registration {
                productAdmissionByProducerLease[lease] = productAdmission
            }
            return registration
        } ?? .rejected(.closing)
    }

    func registerContentProducer(
        request: BridgeProductContentRequest,
        productAdmission: BridgeProductAdmissionContext,
        operation: @escaping @Sendable (BridgeProductProducerLease) async -> Void
    ) -> BridgeProductProducerRegistration {
        productAdmission.withValidAdmission {
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
                productAdmissionByProducerLease[lease] = productAdmission
            }
            return registration
        } ?? .rejected(.closing)
    }

    func enqueueRequiredProducerOpeningFrame(
        for lease: BridgeProductProducerLease,
        productAdmission: BridgeProductAdmissionContext,
        build: @Sendable (Int) throws -> BridgeProductProducerFrame
    ) throws -> BridgeProductProducerEnqueueResult {
        try productAdmission.withValidAdmission {
            guard producerAdmissionMatches(productAdmission, for: lease) else {
                return .rejected(.unknownLease)
            }
            let result = try producerRegistry.enqueueRequiredOpeningFrame(
                for: lease,
                build: build
            )
            resumeProducerFrameWaiterIfPossible(for: lease)
            return result
        } ?? .rejected(.lifecycleClosed)
    }

    func enqueueRequiredContentOpeningFrame(
        for lease: BridgeProductProducerLease,
        productAdmission: BridgeProductAdmissionContext,
        foregroundWorkAdmission: BridgePaneRefreshWorkAdmission,
        build: @Sendable (Int) throws -> BridgeProductProducerFrame
    ) throws -> BridgeProductProducerEnqueueResult {
        try foregroundWorkAdmission.withValidAdmission {
            try enqueueRequiredProducerOpeningFrame(
                for: lease,
                productAdmission: productAdmission,
                build: build
            )
        } ?? .rejected(.lifecycleClosed)
    }

    func enqueueProducerFrame(
        for lease: BridgeProductProducerLease,
        productAdmission: BridgeProductAdmissionContext,
        build: @Sendable (Int) throws -> BridgeProductProducerFrame,
        overflowReset: @Sendable (Int) throws -> BridgeProductProducerFrame
    ) throws -> BridgeProductProducerEnqueueResult {
        try productAdmission.withValidAdmission {
            guard producerAdmissionMatches(productAdmission, for: lease) else {
                return .rejected(.unknownLease)
            }
            let result = try producerRegistry.enqueueNonterminalFrame(
                for: lease,
                build: build,
                overflowReset: overflowReset
            )
            resumeProducerFrameWaiterIfPossible(for: lease)
            return result
        } ?? .rejected(.lifecycleClosed)
    }

    func enqueueContentFrame(
        for lease: BridgeProductProducerLease,
        productAdmission: BridgeProductAdmissionContext,
        foregroundWorkAdmission: BridgePaneRefreshWorkAdmission,
        build: @Sendable (Int) throws -> BridgeProductProducerFrame,
        overflowReset: @Sendable (Int) throws -> BridgeProductProducerFrame
    ) throws -> BridgeProductProducerEnqueueResult {
        try foregroundWorkAdmission.withValidAdmission {
            try enqueueProducerFrame(
                for: lease,
                productAdmission: productAdmission,
                build: build,
                overflowReset: overflowReset
            )
        } ?? .rejected(.lifecycleClosed)
    }

    func enqueueTerminalProducerFrame(
        for lease: BridgeProductProducerLease,
        productAdmission: BridgeProductAdmissionContext,
        build: @Sendable (Int) throws -> BridgeProductProducerFrame
    ) throws -> BridgeProductProducerEnqueueResult {
        try productAdmission.withValidAdmission {
            guard producerAdmissionMatches(productAdmission, for: lease) else {
                return .rejected(.unknownLease)
            }
            let result = try producerRegistry.enqueueTerminalFrame(for: lease, build: build)
            resumeProducerFrameWaiterIfPossible(for: lease)
            return result
        } ?? .rejected(.lifecycleClosed)
    }

    func enqueueTerminalContentFrame(
        for lease: BridgeProductProducerLease,
        productAdmission: BridgeProductAdmissionContext,
        foregroundWorkAdmission: BridgePaneRefreshWorkAdmission,
        build: @Sendable (Int) throws -> BridgeProductProducerFrame
    ) throws -> BridgeProductProducerEnqueueResult {
        try foregroundWorkAdmission.withValidAdmission {
            try enqueueTerminalProducerFrame(
                for: lease,
                productAdmission: productAdmission,
                build: build
            )
        } ?? .rejected(.lifecycleClosed)
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
            productAdmissionByProducerLease.removeValue(
                forKey: acknowledgement.producerLease
            )
            if lastAcceptedMetadataFrameAcknowledgement?.producerLease
                == acknowledgement.producerLease
            {
                lastAcceptedMetadataFrameAcknowledgement = nil
            }
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
        producerRegistry.snapshot().includingSessionAdmissionResidue(
            contentAdmissionCount: contentAdmissionByProducerLease.count,
            productAdmissionCount: productAdmissionByProducerLease.count
        )
    }

    private var producerCompletion: BridgeProductProducerRegistry.ProducerCompletion {
        { [weak self] lease in
            await self?.producerOperationFinished(lease)
        }
    }

    func producerAdmissionMatches(
        _ productAdmission: BridgeProductAdmissionContext,
        for lease: BridgeProductProducerLease
    ) -> Bool {
        productAdmissionByProducerLease[lease]?.matches(productAdmission) == true
    }

    func authorizes(presentedCapability: String) -> Bool {
        guard lifecycle != .revoked else { return false }
        return capabilityMatches(presentedCapability)
    }

    func acknowledgeMetadataFrameObservation(
        _ acknowledgement: BridgeProductMetadataFrameAcknowledgement,
        productAdmission: BridgeProductAdmissionContext
    ) -> Bool {
        productAdmission.withValidAdmission {
            guard lifecycle == .active,
                acknowledgement.paneSessionId == paneSessionId,
                acknowledgement.workerInstanceId == workerInstanceId
            else {
                return false
            }
            if let replay = lastAcceptedMetadataFrameAcknowledgement,
                replay.acknowledgement == acknowledgement
            {
                return producerAdmissionMatches(
                    productAdmission,
                    for: replay.producerLease
                )
            }
            guard
                let receipt = producerRegistry.inFlightMetadataFrameReceipt(
                    matching: acknowledgement
                ), producerAdmissionMatches(productAdmission, for: receipt.producerLease),
                acknowledgeProducerFrameObserved(receipt)
            else {
                return false
            }
            lastAcceptedMetadataFrameAcknowledgement = .init(
                acknowledgement: acknowledgement,
                producerLease: receipt.producerLease
            )
            return true
        } ?? false
    }

    func acknowledgeContentFrameObservation(
        _ acknowledgement: BridgeProductContentFrameAcknowledgement,
        productAdmission: BridgeProductAdmissionContext
    ) -> Bool {
        productAdmission.withValidAdmission {
            guard lifecycle == .active,
                acknowledgement.paneSessionId == paneSessionId,
                acknowledgement.workerInstanceId == workerInstanceId
            else {
                return false
            }
            if let replayLease = lastAcceptedContentFrameAcknowledgementByProducerLease.first(
                where: { $0.value == acknowledgement }
            )?.key {
                return producerAdmissionMatches(productAdmission, for: replayLease)
            }
            guard
                let receipt = producerRegistry.inFlightContentFrameReceipt(
                    matching: acknowledgement
                ), producerAdmissionMatches(productAdmission, for: receipt.producerLease),
                acknowledgeProducerFrameObserved(receipt)
            else {
                return false
            }
            lastAcceptedContentFrameAcknowledgementByProducerLease[receipt.producerLease] =
                acknowledgement
            return true
        } ?? false
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
        presentedCapability: String,
        productAdmission: BridgeProductAdmissionContext
    ) -> BridgeProductSessionControlAdmission {
        guard capabilityMatches(presentedCapability) else { return .rejected(.unauthorized) }
        guard
            (productAdmission.withValidAdmission { true }) == true
        else {
            return .admissionClosed
        }
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

        return productAdmission.withValidAdmission {
            beginValidatedControl(
                exactRequestBytes: exactRequestBytes,
                request: request,
                productAdmission: productAdmission
            )
        } ?? .admissionClosed
    }

    private func beginValidatedControl(
        exactRequestBytes: Data,
        request: BridgeProductControlRequest,
        productAdmission: BridgeProductAdmissionContext
    ) -> BridgeProductSessionControlAdmission {
        guard lifecycle != .revoked else { return .rejected(.revoked) }
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
                productAdmission: productAdmission,
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
        return pendingControl.productAdmission.withValidAdmission {
            pendingControl.providerDispatchCompletion = BridgeProductControlDispatchCompletion()
            self.pendingControl = pendingControl
            return true
        } ?? false
    }

    func completeControl(
        token: BridgeProductControlAdmissionToken,
        exactResponseBytes: Data
    ) async throws -> BridgeProductSessionCompletionEffect {
        guard let pendingControl, pendingControl.token == token else {
            throw BridgeProductSessionError.invalidAdmissionToken
        }
        guard
            (pendingControl.productAdmission.withValidAdmission { true }) == true
        else {
            await settleControlProviderDispatch(token: token)
            return .noEffect
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
            let didComplete =
                try pendingControl.productAdmission.withValidAdmission {
                    try controlReplay.complete(token: token, exactResponseBytes: exactResponseBytes)
                    return true
                } ?? false
            if didComplete {
                await settlePendingControl(pendingControl)
            } else {
                await settleControlProviderDispatch(token: token)
            }
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

        let committedEffect = try pendingControl.productAdmission.withValidAdmission {
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
            return transition.effect
        }
        guard let committedEffect else {
            await settleControlProviderDispatch(token: token)
            return .noEffect
        }
        if committedEffect == .noEffect
            || pendingControl.providerDispatchCompletion == nil
        {
            await settlePendingControl(pendingControl)
        }
        return committedEffect
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
        lastAcceptedMetadataFrameAcknowledgement = nil
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
        capabilityAuthenticator.matches(presentedCapability)
    }
}
