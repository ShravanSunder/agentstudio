import Foundation

struct BridgeProductProducerRetirementBarrier: Equatable, Sendable {
    private enum Storage: Sendable {
        case completed(Bool)
        case inFlight(Task<Bool, Never>)
    }

    private let id: UUID
    private let storage: Storage

    init(id: UUID, task: Task<Bool, Never>) {
        self.id = id
        self.storage = .inFlight(task)
    }

    init(id: UUID, completedResult: Bool) {
        self.id = id
        self.storage = .completed(completedResult)
    }

    func wait() async -> Bool {
        switch storage {
        case .completed(let result): result
        case .inFlight(let task): await task.value
        }
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id
    }
}

enum BridgeProductSessionProducerRetirementState: Sendable {
    case inFlight(BridgeProductProducerRetirementBarrier)

    var barrier: BridgeProductProducerRetirementBarrier {
        switch self {
        case .inFlight(let barrier):
            barrier
        }
    }
}

struct BridgeProductSessionProducerFrameWaiter {
    let continuation: CheckedContinuation<BridgeProductProducerFramePullResult, Never>
    let token: UUID
}

struct BridgeProductProducerPacingWaiter {
    let continuation: CheckedContinuation<Bool, Never>
    let token: UUID
}

enum BridgeProductSessionProducerFrameObservation {
    case awaiting(BridgeProductProducerFrameReceipt)
    case observed(BridgeProductProducerFrameReceipt)
    case waiting(
        BridgeProductProducerFrameReceipt,
        UUID,
        CheckedContinuation<Bool, Never>
    )

    var receipt: BridgeProductProducerFrameReceipt {
        switch self {
        case .awaiting(let receipt), .observed(let receipt), .waiting(let receipt, _, _):
            receipt
        }
    }
}

struct BridgeProductSchemeFramePump: Sendable {
    private let acknowledgeLifecycle: BridgeProductSession.ProducerLifecycleAcknowledger
    private let producerLease: BridgeProductProducerLease
    private let productAdmission: BridgeProductAdmissionContext
    private let session: BridgeProductSession

    init(
        session: BridgeProductSession,
        producerLease: BridgeProductProducerLease,
        productAdmission: BridgeProductAdmissionContext,
        acknowledgeLifecycle: @escaping BridgeProductSession.ProducerLifecycleAcknowledger
    ) {
        self.session = session
        self.producerLease = producerLease
        self.productAdmission = productAdmission
        self.acknowledgeLifecycle = acknowledgeLifecycle
    }

    func nextFrame() async -> BridgeProductProducerFramePullResult {
        let result = await session.pullProducerFrame(
            for: producerLease,
            productAdmission: productAdmission
        )
        guard case .finished = result else { return result }
        let retirement = await session.beginProducerRetirement(
            producerLease,
            acknowledgeLifecycle: acknowledgeLifecycle,
            stopRequest: nil,
            abandonOutstandingDelivery: false
        )
        return await retirement.wait() ? .finished : .rejected(.retirementFailed)
    }

    func acknowledgeFrameConsumed(
        _ receipt: BridgeProductProducerFrameReceipt
    ) async -> Bool {
        await session.acknowledgeProducerFrameConsumed(
            receipt,
            productAdmission: productAdmission
        )
    }

    func waitUntilFrameObserved(
        _ receipt: BridgeProductProducerFrameReceipt
    ) async -> Bool {
        await session.waitUntilProducerFrameObserved(
            receipt,
            productAdmission: productAdmission
        )
    }

    func frameRequiresWorkerObservation(
        _ receipt: BridgeProductProducerFrameReceipt
    ) -> Bool {
        receipt.requiresWorkerObservation
    }

    func cancel() async -> Bool {
        let retirement = await session.beginProducerRetirement(
            producerLease,
            acknowledgeLifecycle: acknowledgeLifecycle,
            stopRequest: nil,
            abandonOutstandingDelivery: true
        )
        return await retirement.wait()
    }
}

extension BridgeProductSession {
    func pullProducerFrame(
        for lease: BridgeProductProducerLease,
        productAdmission: BridgeProductAdmissionContext
    ) async -> BridgeProductProducerFramePullResult {
        let waiterToken = UUID()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                if Task.isCancelled {
                    continuation.resume(returning: .cancelled)
                    return
                }
                let admitted =
                    productAdmission.withValidAdmission {
                        guard producerAdmissionMatches(productAdmission, for: lease) else {
                            continuation.resume(returning: .rejected(.unknownLease))
                            return true
                        }
                        switch producerRegistry.prepareFramePull(
                            for: lease,
                            waiterToken: waiterToken
                        ) {
                        case .finished:
                            continuation.resume(returning: .finished)
                        case .frame(let delivery):
                            registerProducerFrameObservation(delivery.receipt)
                            continuation.resume(returning: .frame(delivery))
                        case .rejected(let rejection):
                            continuation.resume(returning: .rejected(rejection))
                        case .wait:
                            producerFrameWaitersByLease[lease] = .init(
                                continuation: continuation,
                                token: waiterToken
                            )
                        }
                        return true
                    } ?? false
                if !admitted {
                    continuation.resume(returning: .cancelled)
                }
            }
        } onCancel: {
            Task {
                await self.cancelProducerFrameWaiter(
                    for: lease,
                    waiterToken: waiterToken
                )
            }
        }
    }

    func acknowledgeProducerFrameConsumed(
        _ receipt: BridgeProductProducerFrameReceipt,
        productAdmission: BridgeProductAdmissionContext
    ) -> Bool {
        productAdmission.withValidAdmission {
            guard producerAdmissionMatches(productAdmission, for: receipt.producerLease) else {
                return false
            }
            return acknowledgeProducerFrameObserved(receipt)
        } ?? false
    }

    func acknowledgeProducerFrameObserved(
        _ receipt: BridgeProductProducerFrameReceipt
    ) -> Bool {
        let lease = receipt.producerLease
        guard let observation = producerFrameObservationByLease[lease],
            observation.receipt == receipt,
            producerRegistry.acknowledgeFrameConsumed(receipt)
        else {
            return false
        }
        resolveProducerObservationPacingIfPossible(for: receipt)
        switch observation {
        case .awaiting:
            producerFrameObservationByLease[lease] = .observed(receipt)
        case .observed:
            return false
        case .waiting(_, _, let continuation):
            producerFrameObservationByLease.removeValue(forKey: lease)
            continuation.resume(returning: true)
        }
        return true
    }

    func waitUntilProducerFrameSequenceObserved(
        for lease: BridgeProductProducerLease,
        sequence: Int,
        productAdmission: BridgeProductAdmissionContext
    ) async -> Bool {
        let waiterToken = UUID()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                guard !Task.isCancelled else {
                    continuation.resume(returning: false)
                    return
                }
                let pacingWaiterRegistration =
                    productAdmission.withValidAdmission {
                        guard producerAdmissionMatches(productAdmission, for: lease) else {
                            continuation.resume(returning: false)
                            return false
                        }
                        switch producerRegistry.prepareProducerObservationPacing(
                            for: lease,
                            sequence: sequence,
                            waiterToken: waiterToken
                        ) {
                        case .observed:
                            continuation.resume(returning: true)
                        case .rejected:
                            continuation.resume(returning: false)
                        case .wait:
                            guard producerObservationPacingWaitersByLease[lease] == nil else {
                                _ = producerRegistry.cancelProducerObservationPacing(
                                    for: lease,
                                    waiterToken: waiterToken
                                )
                                continuation.resume(returning: false)
                                return false
                            }
                            producerObservationPacingWaitersByLease[lease] = .init(
                                continuation: continuation,
                                token: waiterToken
                            )
                            return true
                        }
                        return false
                    }
                if pacingWaiterRegistration == true {
                    producerObservationPacingRegistrationObserver?(lease, sequence)
                }
                if pacingWaiterRegistration == nil {
                    continuation.resume(returning: false)
                }
            }
        } onCancel: {
            Task {
                await self.cancelProducerObservationPacingWaiter(
                    for: lease,
                    waiterToken: waiterToken
                )
            }
        }
    }

    func waitUntilProducerFrameObserved(
        _ receipt: BridgeProductProducerFrameReceipt,
        productAdmission: BridgeProductAdmissionContext
    ) async -> Bool {
        let waiterToken = UUID()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                guard !Task.isCancelled else {
                    continuation.resume(returning: false)
                    return
                }
                let lease = receipt.producerLease
                let admitted =
                    productAdmission.withValidAdmission {
                        guard producerAdmissionMatches(productAdmission, for: lease),
                            let observation = producerFrameObservationByLease[lease],
                            observation.receipt == receipt
                        else {
                            continuation.resume(returning: false)
                            return true
                        }
                        switch observation {
                        case .awaiting:
                            producerFrameObservationByLease[lease] = .waiting(
                                receipt,
                                waiterToken,
                                continuation
                            )
                        case .observed:
                            producerFrameObservationByLease.removeValue(forKey: lease)
                            continuation.resume(returning: true)
                        case .waiting:
                            continuation.resume(returning: false)
                        }
                        return true
                    } ?? false
                if !admitted {
                    continuation.resume(returning: false)
                }
            }
        } onCancel: {
            Task {
                await self.cancelProducerFrameObservationWaiter(
                    receipt,
                    waiterToken: waiterToken
                )
            }
        }
    }

    func resumeProducerFrameWaiterIfPossible(
        for lease: BridgeProductProducerLease
    ) {
        guard let resolution = producerRegistry.resolveFrameWaiterIfPossible(for: lease),
            let waiter = producerFrameWaitersByLease[lease],
            waiter.token == resolution.waiterToken
        else {
            return
        }
        producerFrameWaitersByLease.removeValue(forKey: lease)
        if case .frame(let delivery) = resolution.result {
            registerProducerFrameObservation(delivery.receipt)
        }
        waiter.continuation.resume(returning: resolution.result)
    }

    func beginProducerRetirement(
        _ lease: BridgeProductProducerLease,
        acknowledgeLifecycle: @escaping ProducerLifecycleAcknowledger,
        stopRequest: BridgeProductProducerRegistry.StopRequest?,
        abandonOutstandingDelivery: Bool
    ) -> BridgeProductProducerRetirementBarrier {
        if let existing = producerRetirementStateByLease[lease] {
            return existing.barrier
        }
        guard producerRegistry.hasLifecycleResidue(for: lease) else {
            return BridgeProductProducerRetirementBarrier(
                id: lease.id,
                completedResult: true
            )
        }
        if abandonOutstandingDelivery {
            abandonProducerFrameDelivery(for: lease)
        }

        let retirementId = UUID()
        let task = Task { [self] in
            let result = await completeProducerRetirement(
                lease,
                acknowledgeLifecycle: acknowledgeLifecycle,
                stopRequest: stopRequest
            )
            producerRetirementStateByLease.removeValue(forKey: lease)
            return result
        }
        let barrier = BridgeProductProducerRetirementBarrier(
            id: retirementId,
            task: task
        )
        producerRetirementStateByLease[lease] = .inFlight(barrier)
        return barrier
    }

    private func cancelProducerFrameWaiter(
        for lease: BridgeProductProducerLease,
        waiterToken: UUID
    ) {
        guard
            producerRegistry.cancelFrameWaiter(
                for: lease,
                waiterToken: waiterToken
            ), let waiter = producerFrameWaitersByLease[lease],
            waiter.token == waiterToken
        else {
            return
        }
        producerFrameWaitersByLease.removeValue(forKey: lease)
        waiter.continuation.resume(returning: .cancelled)
    }

    func abandonProducerFrameDelivery(
        for lease: BridgeProductProducerLease
    ) {
        resolveProducerObservationPacingCancellation(for: lease)
        resolveProducerFrameObservationCancellation(for: lease)
        let waiterToken = producerRegistry.abandonFrameDelivery(for: lease)
        guard let waiterToken,
            let waiter = producerFrameWaitersByLease[lease],
            waiter.token == waiterToken
        else {
            return
        }
        producerFrameWaitersByLease.removeValue(forKey: lease)
        waiter.continuation.resume(returning: .cancelled)
    }

    private func registerProducerFrameObservation(
        _ receipt: BridgeProductProducerFrameReceipt
    ) {
        let lease = receipt.producerLease
        if case .observed = producerFrameObservationByLease[lease] {
            producerFrameObservationByLease.removeValue(forKey: lease)
        }
        precondition(producerFrameObservationByLease[lease] == nil)
        producerFrameObservationByLease[lease] = .awaiting(receipt)
    }

    private func resolveProducerFrameObservationCancellation(
        for lease: BridgeProductProducerLease
    ) {
        guard let observation = producerFrameObservationByLease.removeValue(forKey: lease) else {
            return
        }
        if case .waiting(_, _, let continuation) = observation {
            continuation.resume(returning: false)
        }
    }

    private func cancelProducerFrameObservationWaiter(
        _ receipt: BridgeProductProducerFrameReceipt,
        waiterToken: UUID
    ) {
        let lease = receipt.producerLease
        guard
            case .waiting(let pendingReceipt, let pendingToken, let continuation) =
                producerFrameObservationByLease[lease],
            pendingReceipt == receipt,
            pendingToken == waiterToken
        else {
            return
        }
        producerFrameObservationByLease.removeValue(forKey: lease)
        continuation.resume(returning: false)
    }

    private func resolveProducerObservationPacingIfPossible(
        for receipt: BridgeProductProducerFrameReceipt
    ) {
        let lease = receipt.producerLease
        guard
            let waiterToken = producerRegistry.takeProducerObservationPacingResolution(
                for: receipt
            ), let waiter = producerObservationPacingWaitersByLease[lease],
            waiter.token == waiterToken
        else {
            return
        }
        producerObservationPacingWaitersByLease.removeValue(forKey: lease)
        waiter.continuation.resume(returning: true)
    }

    private func cancelProducerObservationPacingWaiter(
        for lease: BridgeProductProducerLease,
        waiterToken: UUID
    ) {
        guard
            producerRegistry.cancelProducerObservationPacing(
                for: lease,
                waiterToken: waiterToken
            ), let waiter = producerObservationPacingWaitersByLease[lease],
            waiter.token == waiterToken
        else {
            return
        }
        producerObservationPacingWaitersByLease.removeValue(forKey: lease)
        waiter.continuation.resume(returning: false)
    }

    func resolveProducerObservationPacingCancellation(
        for lease: BridgeProductProducerLease
    ) {
        let waiterToken = producerRegistry.abandonProducerObservationPacing(for: lease)
        guard let waiter = producerObservationPacingWaitersByLease.removeValue(forKey: lease) else {
            return
        }
        guard waiterToken == nil || waiter.token == waiterToken else {
            preconditionFailure("Bridge producer pacing waiter identity diverged")
        }
        waiter.continuation.resume(returning: false)
    }

    private func completeProducerRetirement(
        _ lease: BridgeProductProducerLease,
        acknowledgeLifecycle: @escaping ProducerLifecycleAcknowledger,
        stopRequest: BridgeProductProducerRegistry.StopRequest?
    ) async -> Bool {
        let acknowledgement: BridgeProductProducerLifecycleAcknowledgement
        if let pendingAcknowledgement = producerRegistry.pendingLifecycleAcknowledgement(
            for: lease
        ) {
            acknowledgement = pendingAcknowledgement
        } else {
            guard let stopRequest = stopRequest ?? producerRegistry.requestStop([lease]).first else {
                return false
            }
            await stopRequest.task?.value
            guard producerRegistry.producerIsStopped(lease),
                let newAcknowledgement = producerRegistry.unregister(lease)
            else {
                return false
            }
            acknowledgement = newAcknowledgement
        }
        guard await acknowledgeLifecycle(acknowledgement),
            producerRegistry.acknowledgeLifecycle(acknowledgement)
        else {
            return false
        }
        contentAdmissionByProducerLease.removeValue(forKey: lease)
        productAdmissionByProducerLease.removeValue(forKey: lease)
        clearContentFrameObservationReplay(for: lease)
        return true
    }
}
