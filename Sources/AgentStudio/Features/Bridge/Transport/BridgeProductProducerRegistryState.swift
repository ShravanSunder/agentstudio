import Foundation

struct BridgeProductMetadataProducerKey: Equatable {
    let expectedResumeDisposition: BridgeProductMetadataStreamResumeDisposition
    let request: BridgeProductMetadataStreamRequest
}

enum BridgeProductProducerKey: Equatable {
    case metadata(BridgeProductMetadataProducerKey)
    case content(BridgeProductContentRequest)

    var isContent: Bool {
        guard case .content = self else { return false }
        return true
    }

    var requiresWorkerObservation: Bool {
        true
    }

    var maximumAdmittedSequence: Int {
        switch self {
        case .metadata:
            BridgeProductWireContract.maximumSafeInteger
        case .content:
            Int(UInt32.max)
        }
    }
}

enum BridgeProductProducerWorkLifecycle: Equatable {
    case running
    case stopped
    case stopping
}

enum BridgeProductProducerEnqueueIntent {
    case nonterminal
    case requiredOpening
    case terminal
}

struct BridgeProductProducerState {
    let key: BridgeProductProducerKey
    let metadataStreamSequenceRewindFloor: Int?
    var nextMetadataStreamSequence: Int?
    var task: Task<Void, Never>?
    var lifecycle = BridgeProductProducerWorkLifecycle.running
    var openingFrameState = BridgeProductProducerOpeningFrameState.required
    var queuedFrames: [BridgeProductQueuedProducerFrame] = []
    var queuedByteCount = 0
    var nextContentSequence = 0
    var terminalFrameAdmitted = false
    var terminalFrameConsumed = false
    var frameWaiterToken: UUID?
    var inFlightFrameReceipt: BridgeProductProducerFrameReceipt?
    var producerObservationPacingExpectedSequence: Int?
    var producerObservationPacingWaiterToken: UUID?
    var producerObservedSequenceReplay: Int?
}

enum BridgeProductProducerFramePullPreparation {
    case finished
    case frame(BridgeProductProducerFrameDelivery)
    case rejected(BridgeProductProducerFramePullRejection)
    case wait(waiterToken: UUID)
}

struct BridgeProductProducerFrameWaiterResolution {
    let result: BridgeProductProducerFramePullResult
    let waiterToken: UUID
}

enum BridgeProductProducerObservationPacingPreparation {
    case observed
    case rejected
    case wait(waiterToken: UUID)
}

extension BridgeProductProducerRegistry {
    func inFlightMetadataFrameReceipt(
        matching acknowledgement: BridgeProductMetadataFrameAcknowledgement
    ) -> BridgeProductProducerFrameReceipt? {
        producersByLeaseId.values.lazy.compactMap { state in
            guard case .metadata(let metadataKey) = state.key,
                metadataKey.request.metadataStreamId == acknowledgement.metadataStreamId,
                metadataKey.request.paneSessionId == acknowledgement.paneSessionId,
                metadataKey.request.workerInstanceId == acknowledgement.workerInstanceId,
                let receipt = state.inFlightFrameReceipt,
                receipt.sequence == acknowledgement.streamSequence
            else {
                return nil
            }
            return receipt
        }.first
    }

    func inFlightContentFrameReceipt(
        matching acknowledgement: BridgeProductContentFrameAcknowledgement
    ) -> BridgeProductProducerFrameReceipt? {
        var matchingReceipt: BridgeProductProducerFrameReceipt?
        for state in producersByLeaseId.values {
            guard case .content(let request) = state.key,
                request.admission.contentRequestId == acknowledgement.contentRequestId,
                request.admission.leaseId == acknowledgement.leaseId,
                request.admission.paneSessionId == acknowledgement.paneSessionId,
                request.admission.workerInstanceId == acknowledgement.workerInstanceId,
                let receipt = state.inFlightFrameReceipt,
                receipt.sequence == acknowledgement.contentSequence
            else {
                continue
            }
            guard matchingReceipt == nil else { return nil }
            matchingReceipt = receipt
        }
        return matchingReceipt
    }

    mutating func prepareFramePull(
        for lease: BridgeProductProducerLease,
        waiterToken: UUID
    ) -> BridgeProductProducerFramePullPreparation {
        guard var state = producersByLeaseId[lease.id] else {
            return .rejected(.unknownLease)
        }
        guard state.frameWaiterToken == nil else {
            return .rejected(.waiterAlreadyRegistered)
        }
        guard state.inFlightFrameReceipt == nil else {
            return .rejected(.receiptInFlight)
        }
        if let frame = state.queuedFrames.first {
            let delivery = claimFrame(frame, lease: lease, state: &state)
            producersByLeaseId[lease.id] = state
            return .frame(delivery)
        }
        guard state.lifecycle != .stopped else {
            return state.terminalFrameConsumed
                ? .finished
                : .rejected(.producerEndedWithoutTerminal)
        }
        state.frameWaiterToken = waiterToken
        producersByLeaseId[lease.id] = state
        return .wait(waiterToken: waiterToken)
    }

    mutating func resolveFrameWaiterIfPossible(
        for lease: BridgeProductProducerLease
    ) -> BridgeProductProducerFrameWaiterResolution? {
        guard var state = producersByLeaseId[lease.id],
            let waiterToken = state.frameWaiterToken,
            state.inFlightFrameReceipt == nil
        else {
            return nil
        }
        let result: BridgeProductProducerFramePullResult
        if let frame = state.queuedFrames.first {
            state.frameWaiterToken = nil
            result = .frame(claimFrame(frame, lease: lease, state: &state))
        } else if state.lifecycle == .stopped, state.terminalFrameConsumed {
            state.frameWaiterToken = nil
            result = .finished
        } else if state.lifecycle == .stopped {
            state.frameWaiterToken = nil
            result = .rejected(.producerEndedWithoutTerminal)
        } else {
            return nil
        }
        producersByLeaseId[lease.id] = state
        return .init(result: result, waiterToken: waiterToken)
    }

    mutating func cancelFrameWaiter(
        for lease: BridgeProductProducerLease,
        waiterToken: UUID
    ) -> Bool {
        guard var state = producersByLeaseId[lease.id],
            state.frameWaiterToken == waiterToken
        else {
            return false
        }
        state.frameWaiterToken = nil
        producersByLeaseId[lease.id] = state
        return true
    }

    mutating func acknowledgeFrameConsumed(
        _ receipt: BridgeProductProducerFrameReceipt
    ) -> Bool {
        let lease = receipt.producerLease
        guard var state = producersByLeaseId[lease.id],
            state.inFlightFrameReceipt == receipt,
            state.queuedFrames.first?.sequence == receipt.sequence
        else {
            return false
        }
        let frame = state.queuedFrames.removeFirst()
        state.queuedByteCount -= frame.data.count
        state.inFlightFrameReceipt = nil
        state.terminalFrameConsumed = state.terminalFrameConsumed || frame.terminal
        if frame.requiredOpening {
            state.openingFrameState = .delivered
        }
        if state.key.isContent {
            state.producerObservedSequenceReplay = receipt.sequence
        }
        producersByLeaseId[lease.id] = state
        return true
    }

    mutating func prepareProducerObservationPacing(
        for lease: BridgeProductProducerLease,
        sequence: Int,
        waiterToken: UUID
    ) -> BridgeProductProducerObservationPacingPreparation {
        guard var state = producersByLeaseId[lease.id],
            state.key.isContent,
            state.lifecycle != .stopped
        else {
            return .rejected
        }
        if state.producerObservedSequenceReplay == sequence {
            state.producerObservedSequenceReplay = nil
            producersByLeaseId[lease.id] = state
            return .observed
        }
        guard state.producerObservationPacingWaiterToken == nil,
            state.producerObservationPacingExpectedSequence == nil,
            state.queuedFrames.contains(where: { $0.sequence == sequence })
        else {
            return .rejected
        }
        state.producerObservationPacingExpectedSequence = sequence
        state.producerObservationPacingWaiterToken = waiterToken
        producersByLeaseId[lease.id] = state
        return .wait(waiterToken: waiterToken)
    }

    mutating func takeProducerObservationPacingResolution(
        for receipt: BridgeProductProducerFrameReceipt
    ) -> UUID? {
        let lease = receipt.producerLease
        guard var state = producersByLeaseId[lease.id],
            state.producerObservationPacingExpectedSequence == receipt.sequence,
            state.producerObservedSequenceReplay == receipt.sequence,
            let waiterToken = state.producerObservationPacingWaiterToken
        else {
            return nil
        }
        state.producerObservationPacingExpectedSequence = nil
        state.producerObservationPacingWaiterToken = nil
        state.producerObservedSequenceReplay = nil
        producersByLeaseId[lease.id] = state
        return waiterToken
    }

    mutating func cancelProducerObservationPacing(
        for lease: BridgeProductProducerLease,
        waiterToken: UUID
    ) -> Bool {
        guard var state = producersByLeaseId[lease.id],
            state.producerObservationPacingWaiterToken == waiterToken
        else {
            return false
        }
        state.producerObservationPacingExpectedSequence = nil
        state.producerObservationPacingWaiterToken = nil
        producersByLeaseId[lease.id] = state
        return true
    }

    mutating func abandonProducerObservationPacing(
        for lease: BridgeProductProducerLease
    ) -> UUID? {
        guard var state = producersByLeaseId[lease.id] else { return nil }
        let waiterToken = state.producerObservationPacingWaiterToken
        state.producerObservationPacingExpectedSequence = nil
        state.producerObservationPacingWaiterToken = nil
        state.producerObservedSequenceReplay = nil
        producersByLeaseId[lease.id] = state
        return waiterToken
    }

    mutating func abandonFrameDelivery(
        for lease: BridgeProductProducerLease
    ) -> UUID? {
        guard var state = producersByLeaseId[lease.id] else { return nil }
        let waiterToken = state.frameWaiterToken
        state.frameWaiterToken = nil
        state.inFlightFrameReceipt = nil
        producersByLeaseId[lease.id] = state
        return waiterToken
    }

    private func claimFrame(
        _ frame: BridgeProductQueuedProducerFrame,
        lease: BridgeProductProducerLease,
        state: inout BridgeProductProducerState
    ) -> BridgeProductProducerFrameDelivery {
        let receipt = BridgeProductProducerFrameReceipt(
            producerLease: lease,
            requiresWorkerObservation: state.key.requiresWorkerObservation,
            sequence: frame.sequence,
            nonce: UUID()
        )
        state.inFlightFrameReceipt = receipt
        return .init(frame: frame, receipt: receipt)
    }
}
