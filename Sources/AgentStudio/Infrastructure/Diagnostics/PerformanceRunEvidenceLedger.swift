import Foundation

enum PerformanceRunEvidenceVersion: String, Sendable {
    case v1
}

enum PerformanceRunRequiredStage: String, CaseIterable, Hashable, Sendable {
    case mainActorHeartbeat = "mainactor_heartbeat"
    case mainActorWork = "mainactor_work"
    case pipelineContraction = "pipeline_contraction"
    case quiescence
}

struct PerformanceRunProbeEnvelope: Equatable, Sendable {
    let version: PerformanceRunEvidenceVersion
    let runToken: OpaquePerformanceRunToken
    let sequence: UInt64
    let stage: PerformanceRunRequiredStage
}

enum PerformanceRunOfferResult: Equatable, Sendable {
    case offered(PerformanceRunProbeEnvelope)
    case rejected(PerformanceRunOfferRejection)
}

enum PerformanceRunSinkOfferResult: Equatable, Sendable {
    case lost(PerformanceRunProbeEnvelope, PerformanceProbeLossReason)
    case recorded(PerformanceRunProbeEnvelope)
    case rejected(PerformanceRunOfferRejection)
}

enum PerformanceRunOfferRejection: Equatable, Sendable {
    case drainFinished
    case drainInProgress
    case foreignSink
    case sequenceExhausted
}

enum PerformanceRunSettlement: Equatable, Sendable {
    case lost
    case recorded
}

enum PerformanceRunDrainState: Equatable, Sendable {
    case draining
    case finished
    case open
}

enum PerformanceRunDrainReconciliation: Equatable, Sendable {
    case accountingMismatch(offered: UInt64, settled: UInt64)
    case duplicateDrainedSequence(UInt64)
    case finished
    case foreignSink
    case incomplete(remainingCount: Int)
    case notDraining
    case pendingSettlements(count: Int)
    case recordedEvidenceMissing(count: Int)
    case staleDrain
    case unexpectedRunSequence(UInt64)
}

enum PerformanceRunBeginDrainResult: Equatable, Sendable {
    case alreadyDraining(PerformanceProbeDrainToken)
    case alreadyFinished(PerformanceProbeDrainToken)
    case began(PerformanceProbeDrainToken)
    case foreignSink
    case offersInFlight(count: Int)
    case sinkRejected(PerformanceProbeDrainStartRejection)
}

struct PerformanceSequenceGap: Equatable, Sendable {
    let after: UInt64
    let before: UInt64
}

struct PerformanceRunEvidenceSummary: Equatable, Sendable {
    let runToken: OpaquePerformanceRunToken
    let offeredCount: UInt64
    let recordedCount: UInt64
    let lostCount: UInt64
    let gaps: [PerformanceSequenceGap]
    let missingStages: Set<PerformanceRunRequiredStage>
    let drainState: PerformanceRunDrainState
}

enum PerformanceRunEvidenceInvalidity: Equatable, Sendable {
    case duplicateSettlement
    case foreignRun
    case sinkOfferInFlight
    case unknownSequence
}

private enum PerformanceRunLifecycle: Equatable, Sendable {
    case drainStarting(PerformanceProbeDrainToken)
    case draining(PerformanceProbeDrainToken, drainedSinkSequences: Set<UInt64>)
    case finished(PerformanceProbeDrainToken)
    case openBound(PerformanceProbeSinkID, inFlightSequences: Set<UInt64>)
    case openUnbound

    var drainState: PerformanceRunDrainState {
        switch self {
        case .drainStarting, .draining:
            return .draining
        case .finished:
            return .finished
        case .openBound, .openUnbound:
            return .open
        }
    }
}

private enum PerformanceRunSinkOfferReservation: Sendable {
    case rejected(PerformanceRunOfferRejection)
    case reserved(PerformanceRunProbeEnvelope)
}

private enum PerformanceRunDrainPreparation: Sendable {
    case already(PerformanceRunBeginDrainResult)
    case prepared(PerformanceProbeDrainToken)
}

final class PerformanceRunEvidenceLedger: @unchecked Sendable {
    private let runToken: OpaquePerformanceRunToken
    private let requiredStages: Set<PerformanceRunRequiredStage>
    private let lock = NSLock()
    private var nextSequence: UInt64
    private var pendingBySequence: [UInt64: PerformanceRunRequiredStage] = [:]
    private var settledSequences: Set<UInt64> = []
    private var recordedSequences: [UInt64] = []
    private var recordedStages: Set<PerformanceRunRequiredStage> = []
    private var offeredCount: UInt64 = 0
    private var recordedCount: UInt64 = 0
    private var lostCount: UInt64 = 0
    private var sinkRecordedSequences: Set<UInt64> = []
    private var lifecycle: PerformanceRunLifecycle = .openUnbound

    init(
        runToken: OpaquePerformanceRunToken = .make(),
        requiredStages: Set<PerformanceRunRequiredStage>,
        initialSequence: UInt64 = 0
    ) {
        self.runToken = runToken
        self.requiredStages = requiredStages
        self.nextSequence = initialSequence
    }

    func offer(stage: PerformanceRunRequiredStage) -> PerformanceRunOfferResult {
        lock.withLock { offerLocked(stage: stage) }
    }

    func offer(
        stage: PerformanceRunRequiredStage,
        to sink: any PerformanceProbeRecordingSink
    ) -> PerformanceRunSinkOfferResult {
        let reservation = lock.withLock {
            reserveSinkOfferLocked(stage: stage, sinkID: sink.sinkID)
        }
        guard case .reserved(let envelope) = reservation else {
            guard case .rejected(let rejection) = reservation else { preconditionFailure() }
            return .rejected(rejection)
        }

        let sinkOutcome = sink.offer(.runStage(envelope))
        return lock.withLock {
            finishSinkOfferReservationLocked(sequence: envelope.sequence)
            switch sinkOutcome {
            case .accepted:
                precondition(settleLocked(envelope, as: .recorded) == nil)
                precondition(sinkRecordedSequences.insert(envelope.sequence).inserted)
                return .recorded(envelope)
            case .lost(let reason):
                precondition(settleLocked(envelope, as: .lost) == nil)
                return .lost(envelope, reason)
            }
        }
    }

    func settle(
        _ envelope: PerformanceRunProbeEnvelope,
        as settlement: PerformanceRunSettlement
    ) -> PerformanceRunEvidenceInvalidity? {
        lock.withLock {
            guard !isSinkOfferInFlightLocked(sequence: envelope.sequence) else {
                return .sinkOfferInFlight
            }
            return settleLocked(envelope, as: settlement)
        }
    }

    func beginDrain(sink: any PerformanceProbeDrainableSink) -> PerformanceRunBeginDrainResult {
        let preparation = lock.withLock { prepareDrainLocked(sinkID: sink.sinkID) }
        guard case .prepared(let token) = preparation else {
            guard case .already(let result) = preparation else { preconditionFailure() }
            return result
        }

        let sinkResult = sink.beginDrain(using: token)
        return lock.withLock {
            guard case .drainStarting(let current) = lifecycle, current == token else {
                preconditionFailure("drain lifecycle changed during sink admission close")
            }
            switch sinkResult {
            case .began, .alreadyStarted:
                lifecycle = .draining(token, drainedSinkSequences: [])
                return .began(token)
            case .rejected(let rejection):
                lifecycle = .openBound(token.sinkID, inFlightSequences: [])
                return .sinkRejected(rejection)
            }
        }
    }

    func reconcileDrain(_ receipt: PerformanceProbeDrainReceipt) -> PerformanceRunDrainReconciliation {
        lock.withLock {
            guard case .draining(let drainToken, var drainedSinkSequences) = lifecycle else {
                return .notDraining
            }
            guard drainToken.sinkID == receipt.token.sinkID else { return .foreignSink }
            guard drainToken == receipt.token else { return .staleDrain }

            for record in receipt.records {
                guard case .runStage(let envelope) = record, envelope.runToken == runToken else {
                    continue
                }
                guard sinkRecordedSequences.contains(envelope.sequence) else {
                    return .unexpectedRunSequence(envelope.sequence)
                }
                guard drainedSinkSequences.insert(envelope.sequence).inserted else {
                    return .duplicateDrainedSequence(envelope.sequence)
                }
            }
            lifecycle = .draining(drainToken, drainedSinkSequences: drainedSinkSequences)

            guard pendingBySequence.isEmpty else {
                return .pendingSettlements(count: pendingBySequence.count)
            }
            let settledCount = recordedCount + lostCount
            guard offeredCount == settledCount else {
                return .accountingMismatch(offered: offeredCount, settled: settledCount)
            }
            guard receipt.remainingCount == 0 else {
                return .incomplete(remainingCount: receipt.remainingCount)
            }
            let missingSinkSequences = sinkRecordedSequences.subtracting(drainedSinkSequences)
            guard missingSinkSequences.isEmpty else {
                return .recordedEvidenceMissing(count: missingSinkSequences.count)
            }
            lifecycle = .finished(drainToken)
            return .finished
        }
    }

    func summary() -> PerformanceRunEvidenceSummary {
        lock.withLock {
            let sorted = recordedSequences.sorted()
            let gaps = zip(sorted, sorted.dropFirst()).compactMap { left, right in
                right > left + 1 ? PerformanceSequenceGap(after: left, before: right) : nil
            }
            return PerformanceRunEvidenceSummary(
                runToken: runToken,
                offeredCount: offeredCount,
                recordedCount: recordedCount,
                lostCount: lostCount,
                gaps: gaps,
                missingStages: requiredStages.subtracting(recordedStages),
                drainState: lifecycle.drainState
            )
        }
    }

    private func offerLocked(stage: PerformanceRunRequiredStage) -> PerformanceRunOfferResult {
        switch lifecycle {
        case .drainStarting, .draining:
            return .rejected(.drainInProgress)
        case .finished:
            return .rejected(.drainFinished)
        case .openBound, .openUnbound:
            break
        }
        guard nextSequence < UInt64.max else { return .rejected(.sequenceExhausted) }
        nextSequence += 1
        offeredCount += 1
        pendingBySequence[nextSequence] = stage
        return .offered(
            PerformanceRunProbeEnvelope(
                version: .v1,
                runToken: runToken,
                sequence: nextSequence,
                stage: stage
            ))
    }

    private func reserveSinkOfferLocked(
        stage: PerformanceRunRequiredStage,
        sinkID: PerformanceProbeSinkID
    ) -> PerformanceRunSinkOfferReservation {
        switch lifecycle {
        case .openUnbound:
            lifecycle = .openBound(sinkID, inFlightSequences: [])
        case .openBound(let boundSinkID, _):
            guard boundSinkID == sinkID else { return .rejected(.foreignSink) }
        case .drainStarting, .draining:
            return .rejected(.drainInProgress)
        case .finished:
            return .rejected(.drainFinished)
        }

        let offerResult = offerLocked(stage: stage)
        guard case .offered(let envelope) = offerResult else {
            guard case .rejected(let rejection) = offerResult else { preconditionFailure() }
            return .rejected(rejection)
        }
        guard case .openBound(let boundSinkID, var inFlightSequences) = lifecycle else {
            preconditionFailure("sink reservation requires open bound lifecycle")
        }
        precondition(inFlightSequences.insert(envelope.sequence).inserted)
        lifecycle = .openBound(boundSinkID, inFlightSequences: inFlightSequences)
        return .reserved(envelope)
    }

    private func finishSinkOfferReservationLocked(sequence: UInt64) {
        guard case .openBound(let sinkID, var inFlightSequences) = lifecycle else {
            preconditionFailure("sink settlement requires open bound lifecycle")
        }
        precondition(inFlightSequences.remove(sequence) != nil)
        lifecycle = .openBound(sinkID, inFlightSequences: inFlightSequences)
    }

    private func isSinkOfferInFlightLocked(sequence: UInt64) -> Bool {
        guard case .openBound(_, let inFlightSequences) = lifecycle else { return false }
        return inFlightSequences.contains(sequence)
    }

    private func settleLocked(
        _ envelope: PerformanceRunProbeEnvelope,
        as settlement: PerformanceRunSettlement
    ) -> PerformanceRunEvidenceInvalidity? {
        guard envelope.runToken == runToken else { return .foreignRun }
        guard pendingBySequence.removeValue(forKey: envelope.sequence) != nil else {
            return settledSequences.contains(envelope.sequence) ? .duplicateSettlement : .unknownSequence
        }
        settledSequences.insert(envelope.sequence)
        switch settlement {
        case .recorded:
            recordedCount += 1
            recordedSequences.append(envelope.sequence)
            recordedStages.insert(envelope.stage)
        case .lost:
            lostCount += 1
        }
        return nil
    }

    private func prepareDrainLocked(sinkID: PerformanceProbeSinkID) -> PerformanceRunDrainPreparation {
        switch lifecycle {
        case .openUnbound:
            let token = PerformanceProbeDrainToken.make(sinkID: sinkID)
            lifecycle = .drainStarting(token)
            return .prepared(token)
        case .openBound(let boundSinkID, let inFlightSequences):
            guard boundSinkID == sinkID else { return .already(.foreignSink) }
            guard inFlightSequences.isEmpty else {
                return .already(.offersInFlight(count: inFlightSequences.count))
            }
            let token = PerformanceProbeDrainToken.make(sinkID: sinkID)
            lifecycle = .drainStarting(token)
            return .prepared(token)
        case .drainStarting(let token), .draining(let token, _):
            return .already(
                token.sinkID == sinkID ? .alreadyDraining(token) : .foreignSink
            )
        case .finished(let token):
            return .already(
                token.sinkID == sinkID ? .alreadyFinished(token) : .foreignSink
            )
        }
    }
}
