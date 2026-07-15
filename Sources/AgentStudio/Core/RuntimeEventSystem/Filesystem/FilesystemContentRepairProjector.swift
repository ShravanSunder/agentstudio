actor FilesystemContentRepairProjector {
    private enum SourceProjectionState: Sendable {
        case validating(FilesystemContentRepairProjectionRequest)
        case journal(Journal)
    }

    private enum JournalProgress: Sendable {
        case readyForDelivery(index: Int)
        case acknowledging(index: Int, ContentRepairConsumerDisposition)
        case forwarding(index: Int, ContentRepairAcceptedAcknowledgement)
        case readyForProjectorAcknowledgement
    }

    private enum JournalPhase: Sendable {
        case idle(JournalProgress)
        case processing(JournalProgress)
    }

    private struct Journal: Sendable {
        let request: FilesystemContentRepairProjectionRequest
        let projectorAcknowledgement: FilesystemRepairAcknowledgementToken
        var acknowledgedConsumers: Set<ContentRepairConsumerToken>
        var phase: JournalPhase
    }

    private struct CompletedRecord: Sendable {
        let receipt: FilesystemContentRepairProjectionReceipt
        let completionOrdinal: UInt64
    }

    private enum ExternalForwardPhase: Sendable {
        case idle(ContentRepairAcceptedAcknowledgement)
        case processing(ContentRepairAcceptedAcknowledgement)
    }

    private struct CompletedForwardRecord: Sendable {
        let acknowledgement: ContentRepairAcceptedAcknowledgement
        let completionOrdinal: UInt64
    }

    private static let completedRetentionLimitPerSource = 256

    let identity: FilesystemContentRepairProjectorIdentity
    let participant: FilesystemRepairParticipantToken

    private let consumerPort: FilesystemContentRepairConsumerDeliveryPort
    private let registryPort: FilesystemContentRepairRegistryPort
    private let sourceGatePort: FilesystemContentRepairSourceGatePort

    private var lifecycle: FilesystemContentRepairProjectorLifecycle = .open
    private var projectionBySourceID: [FilesystemSourceID: SourceProjectionState] = [:]
    private var completedBySourceID: [FilesystemSourceID: [RepairGenerationID: CompletedRecord]] = [:]
    private var completedForwardedBySourceID:
        [FilesystemSourceID: [FilesystemRepairAcknowledgementToken: CompletedForwardRecord]] = [:]
    private var externalForwardByToken: [FilesystemRepairAcknowledgementToken: ExternalForwardPhase] = [:]
    private var acceptedRegistrationBySourceID: [FilesystemSourceID: FSEventRegistrationToken] = [:]
    private var nextCompletionOrdinal: UInt64 = 0

    init(
        identity: FilesystemContentRepairProjectorIdentity = .generate(),
        participantGeneration: UInt64 = 0,
        consumerPort: FilesystemContentRepairConsumerDeliveryPort,
        registryPort: FilesystemContentRepairRegistryPort,
        sourceGatePort: FilesystemContentRepairSourceGatePort
    ) {
        self.identity = identity
        participant = identity.participant(generation: participantGeneration)
        self.consumerPort = consumerPort
        self.registryPort = registryPort
        self.sourceGatePort = sourceGatePort
    }

    func project(
        _ request: FilesystemContentRepairProjectionRequest
    ) async -> FilesystemContentRepairProjectionResult {
        let repair = request.acceptance.repairGeneration
        let sourceID = repair.id.registration.sourceID

        if let completed = completedBySourceID[sourceID]?[repair.id] {
            return .replayed(completed.receipt)
        }
        if lifecycle == .shutdown { return .shuttingDown }

        if let state = projectionBySourceID[sourceID] {
            switch state {
            case .validating(let retainedRequest):
                guard retainedRequest == request else {
                    return .rejected(
                        .anotherGenerationActive(retainedRequest.acceptance.repairGeneration.id)
                    )
                }
                return .alreadyProcessing(repair.id)
            case .journal(var journal):
                guard journal.request == request else {
                    return .rejected(
                        .anotherGenerationActive(journal.request.acceptance.repairGeneration.id)
                    )
                }
                guard case .idle(let progress) = journal.phase else {
                    return .alreadyProcessing(repair.id)
                }
                journal.phase = .processing(progress)
                projectionBySourceID[sourceID] = .journal(journal)
            }
        } else {
            guard lifecycle == .open else { return .shuttingDown }
            switch FilesystemContentRepairProjectorValidation.structuralValidation(
                request,
                participant: participant
            ) {
            case .valid:
                break
            case .rejected(let rejection):
                return .rejected(rejection)
            }
            projectionBySourceID[sourceID] = .validating(request)
            let eligibility = await registryPort.validateProjection(request.activatedGeneration)
            guard case .validating(request) = projectionBySourceID[sourceID] else {
                preconditionFailure("projection admission reservation changed during validation")
            }
            switch FilesystemContentRepairProjectorValidation.registryValidation(
                eligibility,
                expected: request.activatedGeneration
            ) {
            case .eligible:
                break
            case .rejected(let rejection):
                projectionBySourceID[sourceID] = nil
                return .rejected(rejection)
            case .shuttingDown:
                projectionBySourceID[sourceID] = nil
                return .shuttingDown
            }
            retainValidatedRegistration(repair.id.registration)
            projectionBySourceID[sourceID] = .journal(
                Journal(
                    request: request,
                    projectorAcknowledgement: FilesystemRepairAcknowledgementToken(
                        repairGenerationID: repair.id,
                        participant: participant
                    ),
                    acknowledgedConsumers: [],
                    phase: .processing(
                        request.activatedGeneration.boundGeneration.deliveryRequests.isEmpty
                            ? .readyForProjectorAcknowledgement
                            : .readyForDelivery(index: 0)
                    )
                ))
        }

        let result = await advance(sourceID: sourceID)
        if case .journal(var journal) = projectionBySourceID[sourceID] {
            if case .processing(let progress) = journal.phase {
                journal.phase = .idle(progress)
            }
            projectionBySourceID[sourceID] = .journal(journal)
        }
        completeShutdownIfReady()
        return result
    }

    func forwardRegistryAcknowledgement(
        _ acknowledgement: ContentRepairAcceptedAcknowledgement
    ) async -> FilesystemRepairAcknowledgementForwardResult {
        let token = acknowledgement.sourceGateAcknowledgement
        let sourceID = token.repairGenerationID.registration.sourceID
        if let completed = completedForwardedBySourceID[sourceID]?[token] {
            return completed.acknowledgement == acknowledgement
                ? .replayed(acknowledgement) : .acknowledgementConflict(token)
        }
        guard lifecycle != .shutdown else { return .shuttingDown }
        if let retained = externalForwardByToken[token] {
            switch retained {
            case .processing(let retainedAcknowledgement):
                return retainedAcknowledgement == acknowledgement
                    ? .alreadyProcessing(token) : .acknowledgementConflict(token)
            case .idle(let retainedAcknowledgement):
                guard retainedAcknowledgement == acknowledgement else {
                    return .acknowledgementConflict(token)
                }
            }
        } else {
            guard lifecycle == .open else { return .shuttingDown }
        }
        externalForwardByToken[token] = .processing(acknowledgement)
        let eligibility = await registryPort.validateForwarding(acknowledgement)
        guard case .processing(acknowledgement) = externalForwardByToken[token] else {
            preconditionFailure("forwarding admission reservation changed during validation")
        }
        switch eligibility {
        case .eligible(.pendingExact(let validated)):
            guard validated == acknowledgement else {
                externalForwardByToken[token] = nil
                return .registryEligibilityMismatch(token)
            }
            retainValidatedRegistration(token.repairGenerationID.registration)
        case .eligible(.confirmedExact(let validated)):
            guard validated == acknowledgement else {
                externalForwardByToken[token] = nil
                return .registryEligibilityMismatch(token)
            }
            retainValidatedRegistration(token.repairGenerationID.registration)
            guard retainCompletedForward(acknowledgement) else {
                externalForwardByToken[token] = .idle(acknowledgement)
                return .completionRetentionExhausted(acknowledgement)
            }
            completeShutdownIfReady()
            return .replayed(acknowledgement)
        case .ineligible(let reason):
            externalForwardByToken[token] = nil
            completeShutdownIfReady()
            return .registryIneligible(reason)
        case .shuttingDown:
            externalForwardByToken[token] = nil
            completeShutdownIfReady()
            return .shuttingDown
        }

        let sourceGateResult = await sourceGatePort.accept(token)
        guard sourceGateResult == .applied || sourceGateResult == .alreadyApplied else {
            externalForwardByToken[token] = .idle(acknowledgement)
            completeShutdownIfReady()
            return .awaitingSourceGate(acknowledgement, sourceGateResult)
        }
        let confirmation = await registryPort.confirm(token)
        guard case .confirmed = confirmation else {
            if case .replayed = confirmation {
                guard retainCompletedForward(acknowledgement) else {
                    externalForwardByToken[token] = .idle(acknowledgement)
                    return .completionRetentionExhausted(acknowledgement)
                }
                completeShutdownIfReady()
                return .replayed(acknowledgement)
            }
            externalForwardByToken[token] = .idle(acknowledgement)
            completeShutdownIfReady()
            return .awaitingRegistryConfirmation(acknowledgement, confirmation)
        }
        guard retainCompletedForward(acknowledgement) else {
            externalForwardByToken[token] = .idle(acknowledgement)
            return .completionRetentionExhausted(acknowledgement)
        }
        completeShutdownIfReady()
        return .completed(acknowledgement)
    }

    func shutdownDebtSnapshot() -> FilesystemContentRepairProjectorShutdownDebt {
        makeShutdownDebtSnapshot()
    }

    func retireSource(
        _ request: FilesystemContentRepairSourceRetirementRequest
    ) -> FilesystemContentRepairSourceRetirementResult {
        guard lifecycle != .shutdown else { return .shuttingDown }
        let receipt = request.registryReceipt
        let acceptedRepair = request.acceptance.repairGeneration
        let acceptedRegistration = acceptedRepair.id.registration
        let bindingRegistration = request.acceptance.binding.registration
        guard receipt.sourceID == acceptedRegistration.sourceID else {
            return .rejected(
                .sourceMismatch(
                    expected: receipt.sourceID,
                    actual: acceptedRegistration.sourceID
                )
            )
        }
        guard receipt.finalRegistration == acceptedRegistration else {
            return .rejected(
                .acceptanceRegistrationMismatch(
                    expected: receipt.finalRegistration,
                    actual: acceptedRegistration
                )
            )
        }
        guard receipt.finalRegistration == bindingRegistration else {
            return .rejected(
                .acceptanceBindingMismatch(
                    expected: receipt.finalRegistration,
                    actual: bindingRegistration
                )
            )
        }
        if let currentRegistration = acceptedRegistrationBySourceID[receipt.sourceID],
            currentRegistration != receipt.finalRegistration
        {
            return .rejected(
                .currentRegistrationMismatch(
                    expected: currentRegistration,
                    actual: receipt.finalRegistration
                )
            )
        }
        let debt = makeSourceRetirementDebt(receipt.sourceID)
        guard debt.isEmpty else { return .outstandingDebt(debt) }
        let hadState = completedBySourceID.removeValue(forKey: receipt.sourceID) != nil
        let hadForwardState =
            completedForwardedBySourceID.removeValue(forKey: receipt.sourceID) != nil
        let hadRegistration = acceptedRegistrationBySourceID.removeValue(forKey: receipt.sourceID) != nil
        return hadState || hadForwardState || hadRegistration
            ? .retired(receipt) : .alreadyRetired(receipt.sourceID)
    }

    func beginOrResumeShutdown() -> FilesystemContentRepairProjectorShutdownResult {
        let debt = makeShutdownDebtSnapshot()
        switch lifecycle {
        case .shutdown:
            return .alreadyCompleted(debt)
        case .open, .draining:
            guard debt.isEmpty else {
                lifecycle = .draining
                return .awaitingDebt(debt)
            }
            lifecycle = .shutdown
            return .completed(debt)
        }
    }

    private func advance(
        sourceID: FilesystemSourceID
    ) async -> FilesystemContentRepairProjectionResult {
        while case .journal(var journal) = projectionBySourceID[sourceID] {
            let bound = journal.request.activatedGeneration.boundGeneration
            guard case .processing(let progress) = journal.phase else {
                preconditionFailure("only the processing owner may advance a repair journal")
            }
            switch progress {
            case .acknowledging(let index, let disposition):
                let deliveryRequest = bound.deliveryRequests[index]
                let result = await registryPort.acknowledge(
                    repairGenerationID: bound.repairGeneration.id,
                    consumer: deliveryRequest.consumer,
                    disposition: disposition
                )
                switch result {
                case .accepted(let accepted), .replayed(let accepted):
                    journal.phase = .processing(.forwarding(index: index, accepted))
                    projectionBySourceID[sourceID] = .journal(journal)
                    continue
                case .debtRetained, .shuttingDown:
                    return .awaitingRetry(
                        .registryAcknowledgement(
                            request: deliveryRequest,
                            result: result
                        )
                    )
                }
            case .forwarding(let index, let accepted):
                let forwarded = await forwardAcceptedConsumerAcknowledgement(accepted)
                switch forwarded {
                case .completed:
                    journal.acknowledgedConsumers.insert(
                        bound.deliveryRequests[index].consumer
                    )
                    let nextIndex = index + 1
                    journal.phase =
                        nextIndex < bound.deliveryRequests.count
                        ? .processing(.readyForDelivery(index: nextIndex))
                        : .processing(.readyForProjectorAcknowledgement)
                    projectionBySourceID[sourceID] = .journal(journal)
                    continue
                case .debt(let debt):
                    projectionBySourceID[sourceID] = .journal(journal)
                    return .awaitingRetry(debt)
                }
            case .readyForDelivery(let index):
                switch await validateDeliveryCurrentness(
                    journal: journal,
                    sourceID: sourceID,
                    index: index
                ) {
                case .eligible:
                    break
                case .terminal(let result):
                    return result
                }
                let deliveryRequest = bound.deliveryRequests[index]
                switch await consumerPort.deliver(deliveryRequest) {
                case .retryRequested(let reason):
                    return .awaitingRetry(.consumerRetry(request: deliveryRequest, reason: reason))
                case .rejected(let failure):
                    let token = FilesystemRepairAcknowledgementToken(
                        repairGenerationID: bound.repairGeneration.id,
                        participant: deliveryRequest.consumer.sourceGateParticipant
                    )
                    let result = await sourceGatePort.reject(token, failure: failure)
                    return .awaitingRetry(
                        .consumerRejected(
                            request: deliveryRequest,
                            failure: failure,
                            sourceGateResult: result
                        )
                    )
                case .disposition(let disposition):
                    journal.phase = .processing(
                        .acknowledging(index: index, disposition)
                    )
                    projectionBySourceID[sourceID] = .journal(journal)
                    continue
                }
            case .readyForProjectorAcknowledgement:
                return await completeProjectorAcknowledgement(
                    journal: journal,
                    sourceID: sourceID
                )
            }
        }
        preconditionFailure("a projected source must retain its journal until completion")
    }

    private enum ForwardAcceptedResult {
        case completed
        case debt(FilesystemContentRepairProjectionDebt)
    }

    private enum DeliveryCurrentnessValidation {
        case eligible
        case terminal(FilesystemContentRepairProjectionResult)
    }

    private func validateDeliveryCurrentness(
        journal: Journal,
        sourceID: FilesystemSourceID,
        index: Int
    ) async -> DeliveryCurrentnessValidation {
        let eligibility = await registryPort.validateProjection(
            journal.request.activatedGeneration
        )
        guard case .journal(let retainedJournal) = projectionBySourceID[sourceID],
            retainedJournal.request == journal.request,
            case .processing(.readyForDelivery(index)) = retainedJournal.phase
        else {
            preconditionFailure("delivery journal changed during currentness validation")
        }
        switch FilesystemContentRepairProjectorValidation.registryValidation(
            eligibility,
            expected: journal.request.activatedGeneration
        ) {
        case .eligible:
            return .eligible
        case .rejected(let rejection):
            projectionBySourceID[sourceID] = nil
            return .terminal(.rejected(rejection))
        case .shuttingDown:
            projectionBySourceID[sourceID] = nil
            return .terminal(.shuttingDown)
        }
    }

    private func completeProjectorAcknowledgement(
        journal: Journal,
        sourceID: FilesystemSourceID
    ) async -> FilesystemContentRepairProjectionResult {
        let projectorResult = await sourceGatePort.accept(journal.projectorAcknowledgement)
        guard projectorResult == .applied || projectorResult == .alreadyApplied else {
            return .awaitingRetry(
                .projectorAcknowledgement(
                    journal.projectorAcknowledgement,
                    result: projectorResult
                )
            )
        }
        guard let completionOrdinal = takeCompletionOrdinal() else {
            return .awaitingRetry(
                .completionRetentionExhausted(journal.projectorAcknowledgement)
            )
        }
        let bound = journal.request.activatedGeneration.boundGeneration
        let receipt = FilesystemContentRepairProjectionReceipt(
            repairGenerationID: bound.repairGeneration.id,
            invalidationGenerations: Set(bound.deliveryRequests.map(\.invalidationGeneration)),
            acknowledgedConsumers: journal.acknowledgedConsumers,
            projectorAcknowledgement: journal.projectorAcknowledgement
        )
        projectionBySourceID[sourceID] = nil
        completedBySourceID[sourceID, default: [:]][bound.repairGeneration.id] =
            CompletedRecord(receipt: receipt, completionOrdinal: completionOrdinal)
        pruneCompleted(sourceID: sourceID)
        return .completed(receipt)
    }

    private func forwardAcceptedConsumerAcknowledgement(
        _ accepted: ContentRepairAcceptedAcknowledgement
    ) async -> ForwardAcceptedResult {
        let sourceGateResult = await sourceGatePort.accept(accepted.sourceGateAcknowledgement)
        guard sourceGateResult == .applied || sourceGateResult == .alreadyApplied else {
            return .debt(.sourceGateAcknowledgement(accepted, result: sourceGateResult))
        }
        let confirmation = await registryPort.confirm(accepted.sourceGateAcknowledgement)
        switch confirmation {
        case .confirmed, .replayed:
            return .completed
        case .staleAcknowledgement, .retentionExhausted, .shuttingDown:
            return .debt(.registryConfirmation(accepted, result: confirmation))
        }
    }

    @discardableResult
    private func retainCompletedForward(
        _ acknowledgement: ContentRepairAcceptedAcknowledgement
    ) -> Bool {
        guard let ordinal = takeCompletionOrdinal() else { return false }
        let token = acknowledgement.sourceGateAcknowledgement
        let sourceID = token.repairGenerationID.registration.sourceID
        externalForwardByToken[token] = nil
        completedForwardedBySourceID[sourceID, default: [:]][token] =
            CompletedForwardRecord(
                acknowledgement: acknowledgement,
                completionOrdinal: ordinal
            )
        if var retained = completedForwardedBySourceID[sourceID],
            retained.count > Self.completedRetentionLimitPerSource,
            let oldest = retained.min(by: {
                $0.value.completionOrdinal < $1.value.completionOrdinal
            })?.key
        {
            retained[oldest] = nil
            completedForwardedBySourceID[sourceID] = retained
        }
        return true
    }

    private func takeCompletionOrdinal() -> UInt64? {
        let ordinal = nextCompletionOrdinal
        let (following, overflow) = ordinal.addingReportingOverflow(1)
        guard !overflow else { return nil }
        nextCompletionOrdinal = following
        return ordinal
    }

    private func retainValidatedRegistration(_ registration: FSEventRegistrationToken) {
        let sourceID = registration.sourceID
        guard acceptedRegistrationBySourceID[sourceID] != registration else { return }
        acceptedRegistrationBySourceID[sourceID] = registration
        completedBySourceID[sourceID] = completedBySourceID[sourceID]?.filter {
            $0.key.registration == registration
        }
        completedForwardedBySourceID[sourceID] = completedForwardedBySourceID[sourceID]?.filter {
            $0.key.repairGenerationID.registration == registration
        }
    }

    private func pruneCompleted(sourceID: FilesystemSourceID) {
        guard var retained = completedBySourceID[sourceID],
            retained.count > Self.completedRetentionLimitPerSource,
            let oldest = retained.min(by: { $0.value.completionOrdinal < $1.value.completionOrdinal })?.key
        else { return }
        retained[oldest] = nil
        completedBySourceID[sourceID] = retained
    }

    private func makeShutdownDebtSnapshot() -> FilesystemContentRepairProjectorShutdownDebt {
        FilesystemContentRepairProjectorShutdownDebt(
            activeRepairGenerations: Set(
                projectionBySourceID.values.map { state in
                    switch state {
                    case .validating(let request): request.acceptance.repairGeneration.id
                    case .journal(let journal): journal.request.acceptance.repairGeneration.id
                    }
                }
            ),
            outboundAcknowledgements: Set(externalForwardByToken.keys)
        )
    }

    private func makeSourceRetirementDebt(
        _ sourceID: FilesystemSourceID
    ) -> FilesystemContentRepairSourceRetirementDebt {
        let activeRepairGenerations: Set<RepairGenerationID>
        if let state = projectionBySourceID[sourceID] {
            switch state {
            case .validating(let request):
                activeRepairGenerations = [request.acceptance.repairGeneration.id]
            case .journal(let journal):
                activeRepairGenerations = [journal.request.acceptance.repairGeneration.id]
            }
        } else {
            activeRepairGenerations = []
        }
        return FilesystemContentRepairSourceRetirementDebt(
            activeRepairGenerations: activeRepairGenerations,
            outboundAcknowledgements: Set(
                externalForwardByToken.keys.filter {
                    $0.repairGenerationID.registration.sourceID == sourceID
                }
            )
        )
    }

    private func completeShutdownIfReady() {
        guard lifecycle == .draining, makeShutdownDebtSnapshot().isEmpty else { return }
        lifecycle = .shutdown
    }
}
