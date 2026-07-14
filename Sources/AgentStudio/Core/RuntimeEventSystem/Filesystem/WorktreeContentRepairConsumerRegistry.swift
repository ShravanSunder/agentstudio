struct ContentRepairActivatedGeneration: Equatable, Sendable {
    let boundGeneration: ContentRepairBoundGeneration

    fileprivate init(boundGeneration: ContentRepairBoundGeneration) {
        self.boundGeneration = boundGeneration
    }
}

actor WorktreeContentRepairConsumerRegistry {
    private typealias RegistryState = WorktreeContentRepairConsumerRegistryState
    private typealias PriorInvalidationSnapshot = RegistryState.PriorInvalidationSnapshot
    private typealias ConsumerRecord = RegistryState.ConsumerRecord
    private typealias PreparedCaptureRecord = RegistryState.PreparedCaptureRecord
    private typealias ActiveRepairRecord = RegistryState.ActiveRepairRecord
    private typealias BoundCaptureRecord = RegistryState.BoundCaptureRecord
    private typealias CaptureLedgerEntry = RegistryState.CaptureLedgerEntry
    private typealias AcceptedOutboundOperation = RegistryState.AcceptedOutboundOperation
    private typealias PendingAcknowledgementRecord = RegistryState.PendingAcknowledgementRecord
    private typealias ConfirmedAcknowledgementRecord = RegistryState.ConfirmedAcknowledgementRecord

    private var lifecycle: WorktreeContentRepairConsumerRegistryLifecycle = .open
    private var consumersBySourceID: [FilesystemSourceID: [ContentRepairConsumerIdentity: ConsumerRecord]] = [:]
    private var baselineRegistrationBySourceID: [FilesystemSourceID: FSEventRegistrationToken] = [:]
    private var pendingCaptureBySourceID: [FilesystemSourceID: ContentRepairCaptureIdentity] = [:]
    private var captureLedgerByIdentity: [ContentRepairCaptureIdentity: CaptureLedgerEntry] = [:]
    private var activeRepairBySourceID: [FilesystemSourceID: ActiveRepairRecord] = [:]
    private var pendingBoundRepairBySourceID: [FilesystemSourceID: ActiveRepairRecord] = [:]
    private var completedRepairBySourceID: [FilesystemSourceID: ActiveRepairRecord] = [:]
    private var latestInvalidationGenerationBySourceID: [FilesystemSourceID: ContentRepairInvalidationGeneration] = [:]
    private var pendingOutboundAcknowledgementByToken:
        [FilesystemRepairAcknowledgementToken: PendingAcknowledgementRecord] = [:]
    private var confirmedAcknowledgementBySourceID:
        [FilesystemSourceID: [FilesystemRepairAcknowledgementToken: ConfirmedAcknowledgementRecord]] = [:]
    private var nextConsumerRegistrationOrdinal: UInt64
    private var nextInvalidationGeneration: UInt64
    private var nextConfirmationOrdinal: UInt64 = 0
    private let initialConsumerGeneration: UInt64

    private static let completedAcknowledgementRetentionLimitPerSource = 256
    private static let terminalCaptureRetentionLimitPerSource = 256

    init(
        nextConsumerRegistrationOrdinal: UInt64 = 0,
        nextInvalidationGeneration: UInt64 = 0,
        initialConsumerGeneration: UInt64 = 0
    ) {
        self.nextConsumerRegistrationOrdinal = nextConsumerRegistrationOrdinal
        self.nextInvalidationGeneration = nextInvalidationGeneration
        self.initialConsumerGeneration = initialConsumerGeneration
    }

    func register(
        registration: FSEventRegistrationToken,
        eligibility: ContentRepairCaptureEligibility
    ) -> ContentRepairConsumerRegistrationResult {
        guard lifecycle == .open else { return .shuttingDown }
        let sourceID = registration.sourceID
        guard sourceID.kind == .registeredWorktreeContent else {
            return .sourceKindNotSupported(sourceID)
        }
        if let baseline = baselineRegistrationBySourceID[sourceID], baseline != registration {
            return .registrationConflict(expected: baseline, requested: registration)
        }
        guard
            let followingOrdinal = ContentRepairGenerationArithmetic.successor(
                of: nextConsumerRegistrationOrdinal
            )
        else {
            return .generationExhausted
        }
        baselineRegistrationBySourceID[sourceID] = registration

        let token = ContentRepairConsumerToken.registered(
            sourceID: sourceID,
            registrationOrdinal: nextConsumerRegistrationOrdinal,
            generation: initialConsumerGeneration
        )
        nextConsumerRegistrationOrdinal = followingOrdinal
        let currentness = initialCurrentness(for: token, registration: registration)
        let record = ConsumerRecord(
            token: token,
            registration: registration,
            eligibility: eligibility,
            currentness: currentness
        )
        consumersBySourceID[sourceID, default: [:]][token.identity] = record
        recordLateConsumerIfNeeded(token.identity, sourceID: sourceID)
        return .registered(RegistryState.project(record))
    }

    func updateEligibility(
        of token: ContentRepairConsumerToken,
        to eligibility: ContentRepairCaptureEligibility
    ) -> ContentRepairEligibilityUpdateResult {
        guard lifecycle == .open else { return .shuttingDown }
        guard var sourceConsumers = consumersBySourceID[token.sourceID] else { return .foreignSource }
        guard var record = sourceConsumers[token.identity], record.token == token else { return .staleToken }
        guard record.eligibility != eligibility else { return .alreadyApplied(RegistryState.project(record)) }
        record.eligibility = eligibility
        sourceConsumers[token.identity] = record
        consumersBySourceID[token.sourceID] = sourceConsumers
        return .applied(RegistryState.project(record))
    }

    func prepareCapture(
        identity: ContentRepairCaptureIdentity,
        registration: FSEventRegistrationToken
    ) -> ContentRepairCapturePreparationResult {
        guard lifecycle == .open else { return .shuttingDown }
        let sourceID = registration.sourceID
        guard sourceID.kind == .registeredWorktreeContent else {
            return .sourceKindNotSupported(sourceID)
        }
        if let expected = baselineRegistrationBySourceID[sourceID], expected != registration {
            return .registrationConflict(expected: expected, requested: registration)
        }
        if let retained = captureLedgerByIdentity[identity] {
            switch retained {
            case .prepared(let record) where record.capture.registration == registration:
                return .replayed(record.capture)
            case .bound(let record)
            where record.prepared.capture.registration == registration:
                return .replayed(record.prepared.capture)
            case .completed(let record)
            where record.prepared.capture.registration == registration:
                return .replayed(record.prepared.capture)
            case .prepared, .bound, .completed, .aborted, .superseded:
                return .captureIdentityConflict(identity)
            }
        }
        guard
            let followingInvalidationGeneration = ContentRepairGenerationArithmetic.successor(
                of: nextInvalidationGeneration
            )
        else {
            return .generationExhausted
        }

        supersedePendingRepairIfNeeded(sourceID: sourceID)
        baselineRegistrationBySourceID[sourceID] = registration
        let sourceConsumers = consumersBySourceID[sourceID] ?? [:]
        let capturedRecords = sourceConsumers.values.filter { record in
            record.eligibility == .eligible
        }
        let consumers = Set(capturedRecords.map(\.token))
        let capture = ContentRepairPreparedCapture(
            identity: identity,
            invalidationGeneration: ContentRepairInvalidationGeneration(
                value: nextInvalidationGeneration
            ),
            registration: registration,
            consumers: consumers
        )
        nextInvalidationGeneration = followingInvalidationGeneration
        let priorInvalidation: PriorInvalidationSnapshot =
            latestInvalidationGenerationBySourceID[sourceID].map(PriorInvalidationSnapshot.retained)
            ?? .absent
        latestInvalidationGenerationBySourceID[sourceID] = capture.invalidationGeneration
        pendingCaptureBySourceID[sourceID] = capture.identity
        captureLedgerByIdentity[capture.identity] = .prepared(
            PreparedCaptureRecord(
                capture: capture,
                priorCurrentnessByIdentity: Dictionary(
                    uniqueKeysWithValues: capturedRecords.map { ($0.token.identity, $0.currentness) }
                ),
                lateConsumerIdentities: [],
                priorInvalidation: priorInvalidation
            )
        )
        markCapturedConsumersPending(capture)
        return .prepared(capture)
    }

    func abortCapture(
        _ capture: ContentRepairPreparedCapture
    ) -> ContentRepairCaptureAbortResult {
        guard capture.registration.sourceID.kind == .registeredWorktreeContent else {
            return .foreignSource
        }
        guard let entry = captureLedgerByIdentity[capture.identity] else { return .staleCapture }
        switch entry {
        case .aborted(let retained):
            return retained == capture ? .alreadyAborted(capture.identity) : .staleCapture
        case .superseded:
            return .staleCapture
        case .bound(let retained), .completed(let retained):
            return retained.prepared.capture == capture
                ? .alreadyBound(retained.bound.repairGeneration.id) : .staleCapture
        case .prepared(let record):
            guard record.capture == capture else { return .staleCapture }
            captureLedgerByIdentity[capture.identity] = .aborted(capture)
            pendingCaptureBySourceID[capture.registration.sourceID] = nil
            restoreAfterAbortedCapture(record)
            captureLedgerByIdentity = RegistryState.prunedCaptureLedger(
                captureLedgerByIdentity,
                sourceID: capture.registration.sourceID,
                retentionLimit: Self.terminalCaptureRetentionLimitPerSource
            )
            completeShutdownIfReady()
            return .aborted(capture)
        }
    }

    func bind(
        _ capture: ContentRepairPreparedCapture,
        to repairGeneration: RepairGeneration
    ) -> ContentRepairCaptureBindingResult {
        guard lifecycle != .shutdown else { return .shuttingDown }
        let sourceID = capture.registration.sourceID
        guard sourceID == repairGeneration.id.registration.sourceID else { return .foreignSource }
        guard let entry = captureLedgerByIdentity[capture.identity] else { return .staleCapture }
        let preparedRecord: PreparedCaptureRecord
        switch entry {
        case .aborted(let retained):
            return retained == capture ? .captureAborted : .staleCapture
        case .superseded(let retained):
            return retained == capture ? .captureSuperseded : .staleCapture
        case .bound(let retained):
            guard retained.prepared.capture == capture,
                retained.bound.repairGeneration == repairGeneration
            else { return .staleCapture }
            if pendingBoundRepairBySourceID[sourceID]?.generation.id == repairGeneration.id {
                return .replayedPending(retained.bound)
            }
            guard activeRepairBySourceID[sourceID]?.generation.id == repairGeneration.id else {
                return .staleCapture
            }
            return .replayedActive(.init(boundGeneration: retained.bound))
        case .completed(let retained):
            guard retained.prepared.capture == capture,
                retained.bound.repairGeneration == repairGeneration
            else { return .staleCapture }
            return .replayedCompleted(retained.bound)
        case .prepared(let prepared):
            guard prepared.capture == capture else { return .staleCapture }
            preparedRecord = prepared
        }
        guard capture.registration == repairGeneration.id.registration else {
            return .registrationMismatch(
                expected: capture.registration,
                actual: repairGeneration.id.registration
            )
        }
        let actualContentParticipants = Set(
            repairGeneration.participants.filter { $0.kind == .contentConsumer }
        )
        guard actualContentParticipants == capture.sourceGateParticipants else {
            return .participantMismatch(
                expected: capture.sourceGateParticipants,
                actual: actualContentParticipants
            )
        }

        let requests = RegistryState.deliveryRequests(
            capture: capture,
            repairGeneration: repairGeneration
        )
        let bound = ContentRepairBoundGeneration(
            repairGeneration: repairGeneration,
            deliveryRequests: requests
        )
        let repairRecord = ActiveRepairRecord(
            generation: repairGeneration,
            invalidationGeneration: capture.invalidationGeneration,
            requestsByIdentity: Dictionary(uniqueKeysWithValues: requests.map { ($0.consumer.identity, $0) }),
            pendingConsumerIdentities: Set(capture.consumers.map(\.identity)),
            acceptedByIdentity: [:]
        )
        captureLedgerByIdentity[capture.identity] = .bound(
            BoundCaptureRecord(prepared: preparedRecord, bound: bound)
        )
        pendingCaptureBySourceID[sourceID] = nil
        if activeRepairBySourceID[sourceID] == nil {
            activeRepairBySourceID[sourceID] = repairRecord
            applyBoundRepairCurrentness(sourceID: sourceID, repairGeneration: repairGeneration)
            finishActiveRepairIfReady(sourceID: sourceID)
            return .boundActive(.init(boundGeneration: bound))
        } else {
            pendingBoundRepairBySourceID[sourceID] = repairRecord
            return .boundPending(bound)
        }
    }

    func activateBoundGeneration(
        _ repairGenerationID: RepairGenerationID
    ) -> ContentRepairBoundGenerationActivationResult {
        guard lifecycle != .shutdown else { return .shuttingDown }
        let sourceID = repairGenerationID.registration.sourceID
        guard sourceID.kind == .registeredWorktreeContent else { return .foreignSource }
        if let active = activeRepairBySourceID[sourceID], active.generation.id == repairGenerationID {
            return .alreadyActive(
                ContentRepairActivatedGeneration(
                    boundGeneration: RegistryState.projectBoundGeneration(active)
                )
            )
        }
        guard let pending = pendingBoundRepairBySourceID[sourceID],
            pending.generation.id == repairGenerationID
        else {
            return .staleGeneration
        }
        if let supersededActive = activeRepairBySourceID[sourceID] {
            completedRepairBySourceID[sourceID] = RegistryState.terminalizedForSupersession(
                supersededActive
            )
            captureLedgerByIdentity = RegistryState.terminalizingBoundCapture(
                captureLedgerByIdentity,
                repairGenerationID: supersededActive.generation.id,
                terminalization: .superseded,
                retentionLimit: Self.terminalCaptureRetentionLimitPerSource
            )
        }
        pendingBoundRepairBySourceID[sourceID] = nil
        activeRepairBySourceID[sourceID] = pending
        applyBoundRepairCurrentness(sourceID: sourceID, repairGeneration: pending.generation)
        finishActiveRepairIfReady(sourceID: sourceID)
        return .activated(
            ContentRepairActivatedGeneration(
                boundGeneration: RegistryState.projectBoundGeneration(pending)
            )
        )
    }

    func acknowledge(
        repairGenerationID: RepairGenerationID,
        consumer: ContentRepairConsumerToken,
        disposition: ContentRepairConsumerDisposition
    ) -> ContentRepairAcknowledgementResult {
        guard lifecycle != .shutdown else { return .shuttingDown }
        guard repairGenerationID.registration.sourceID == consumer.sourceID else {
            return .debtRetained(.foreignSource)
        }
        guard var repair = activeRepairBySourceID[consumer.sourceID] else {
            return replayedAcknowledgement(
                repairGenerationID: repairGenerationID,
                consumer: consumer,
                disposition: disposition
            )
        }
        guard repair.generation.id == repairGenerationID else {
            return .debtRetained(.staleRepairGeneration)
        }
        guard latestInvalidationGenerationBySourceID[consumer.sourceID] == repair.invalidationGeneration else {
            return .debtRetained(.staleRepairGeneration)
        }
        guard let request = repair.requestsByIdentity[consumer.identity] else {
            return .debtRetained(.staleConsumerToken)
        }
        guard request.consumer == consumer else { return .debtRetained(.staleConsumerToken) }
        if let accepted = repair.acceptedByIdentity[consumer.identity] {
            return accepted.disposition == RegistryState.recordedDisposition(disposition)
                ? .replayed(accepted) : .debtRetained(.staleConsumerToken)
        }
        guard repair.pendingConsumerIdentities.contains(consumer.identity) else {
            return .debtRetained(.staleConsumerToken)
        }
        if case .markedNonCurrent(let retry) = disposition, retry != request.retryToken {
            return .debtRetained(.retryTokenMismatch)
        }

        let accepted = ContentRepairAcceptedAcknowledgement(
            sourceGateAcknowledgement: FilesystemRepairAcknowledgementToken(
                repairGenerationID: repairGenerationID,
                participant: consumer.sourceGateParticipant
            ),
            disposition: RegistryState.recordedDisposition(disposition)
        )
        retainOutboundAcknowledgement(
            accepted,
            operation: .acknowledgement(
                repairGenerationID: repairGenerationID,
                consumer: consumer,
                disposition: disposition
            )
        )
        applyAcceptedDisposition(
            disposition,
            request: request,
            invalidationGeneration: repair.invalidationGeneration
        )
        repair.pendingConsumerIdentities.remove(consumer.identity)
        repair.acceptedByIdentity[consumer.identity] = accepted
        activeRepairBySourceID[consumer.sourceID] = repair
        finishActiveRepairIfReady(sourceID: consumer.sourceID)
        return .accepted(accepted)
    }

    func confirmSourceGateAcknowledgement(
        _ token: FilesystemRepairAcknowledgementToken
    ) -> ContentRepairAcknowledgementConfirmationResult {
        let sourceID = token.repairGenerationID.registration.sourceID
        if let confirmed = confirmedAcknowledgementBySourceID[sourceID]?[token] {
            return .replayed(confirmed.pending.accepted)
        }
        guard lifecycle != .shutdown else { return .shuttingDown }
        guard let pending = pendingOutboundAcknowledgementByToken[token] else {
            return .staleAcknowledgement
        }
        guard
            let followingOrdinal = ContentRepairGenerationArithmetic.successor(
                of: nextConfirmationOrdinal
            )
        else {
            return .retentionExhausted
        }
        pendingOutboundAcknowledgementByToken[token] = nil
        confirmedAcknowledgementBySourceID[sourceID, default: [:]][token] =
            ConfirmedAcknowledgementRecord(
                pending: pending,
                confirmationOrdinal: nextConfirmationOrdinal
            )
        nextConfirmationOrdinal = followingOrdinal
        confirmedAcknowledgementBySourceID[sourceID] = RegistryState.prunedConfirmedAcknowledgements(
            confirmedAcknowledgementBySourceID[sourceID] ?? [:],
            retentionLimit: Self.completedAcknowledgementRetentionLimitPerSource
        )
        completeShutdownIfReady()
        return .confirmed(pending.accepted)
    }

    func withdraw(
        _ token: ContentRepairConsumerToken,
        disposition _: ContentRepairWithdrawalDisposition
    ) -> ContentRepairWithdrawalResult {
        guard lifecycle != .shutdown else { return .shuttingDown }
        if let replayed = replayedWithdrawal(for: token) {
            return .withdrawnAndAcknowledged(replayed)
        }
        guard var sourceConsumers = consumersBySourceID[token.sourceID] else { return .foreignSource }
        guard let record = sourceConsumers[token.identity], record.token == token else { return .staleToken }
        if let captureIdentity = preparedCaptureIdentity(for: token.sourceID) {
            return .captureInProgress(captureIdentity)
        }
        if case .nonCurrent(.retryRetained(let retry)) = record.currentness {
            return .retainedRetryRequiresTransfer(retry)
        }
        sourceConsumers[token.identity] = nil
        consumersBySourceID[token.sourceID] = sourceConsumers

        guard var repair = activeRepairBySourceID[token.sourceID],
            repair.pendingConsumerIdentities.contains(token.identity),
            let request = repair.requestsByIdentity[token.identity]
        else {
            completeShutdownIfReady()
            return .withdrawn
        }
        let accepted = ContentRepairAcceptedAcknowledgement(
            sourceGateAcknowledgement: FilesystemRepairAcknowledgementToken(
                repairGenerationID: repair.generation.id,
                participant: request.consumer.sourceGateParticipant
            ),
            disposition: .withdrawnNoRetainedState
        )
        repair.pendingConsumerIdentities.remove(token.identity)
        repair.acceptedByIdentity[token.identity] = accepted
        activeRepairBySourceID[token.sourceID] = repair
        retainOutboundAcknowledgement(accepted, operation: .withdrawal(token))
        finishActiveRepairIfReady(sourceID: token.sourceID)
        return .withdrawnAndAcknowledged(accepted)
    }

    func replace(
        _ token: ContentRepairConsumerToken,
        eligibility: ContentRepairCaptureEligibility
    ) -> ContentRepairConsumerReplacementResult {
        guard lifecycle != .shutdown else { return .shuttingDown }
        if let replayed = replayedReplacement(for: token, eligibility: eligibility) {
            return .replaced(replayed)
        }
        guard lifecycle == .open else { return .shuttingDown }
        guard var sourceConsumers = consumersBySourceID[token.sourceID] else { return .foreignSource }
        guard let prior = sourceConsumers[token.identity], prior.token == token else { return .staleToken }
        if let captureIdentity = preparedCaptureIdentity(for: token.sourceID) {
            return .captureInProgress(captureIdentity)
        }
        guard let replacementToken = token.replacement() else {
            return .generationExhausted
        }
        let replacementCurrentness = RegistryState.transferredCurrentness(
            prior.currentness,
            replacementToken: replacementToken
        )
        let replacementRecord = ConsumerRecord(
            token: replacementToken,
            registration: prior.registration,
            eligibility: eligibility,
            currentness: replacementCurrentness
        )
        sourceConsumers[token.identity] = replacementRecord
        consumersBySourceID[token.sourceID] = sourceConsumers

        let repairDisposition: ContentRepairReplacementRepairDisposition
        if var repair = activeRepairBySourceID[token.sourceID],
            repair.pendingConsumerIdentities.contains(token.identity),
            let request = repair.requestsByIdentity[token.identity]
        {
            let accepted = ContentRepairAcceptedAcknowledgement(
                sourceGateAcknowledgement: FilesystemRepairAcknowledgementToken(
                    repairGenerationID: repair.generation.id,
                    participant: request.consumer.sourceGateParticipant
                ),
                disposition: .transferredToReplacement(replacementToken)
            )
            repair.pendingConsumerIdentities.remove(token.identity)
            repair.acceptedByIdentity[token.identity] = accepted
            activeRepairBySourceID[token.sourceID] = repair
            repairDisposition = .transferred(accepted)
            finishActiveRepairIfReady(sourceID: token.sourceID)
        } else {
            repairDisposition = .notCaptured
        }
        let replacement = ContentRepairConsumerReplacement(
            registration: RegistryState.project(replacementRecord),
            repairDisposition: repairDisposition
        )
        if case .transferred(let accepted) = repairDisposition {
            retainOutboundAcknowledgement(
                accepted,
                operation: .replacement(
                    prior: token,
                    eligibility: eligibility,
                    replacement: replacement
                )
            )
        }
        return .replaced(replacement)
    }

    private func initialCurrentness(
        for token: ContentRepairConsumerToken,
        registration: FSEventRegistrationToken
    ) -> ContentRepairConsumerCurrentness {
        let sourceID = token.sourceID
        if let captureIdentity = pendingCaptureBySourceID[sourceID],
            case .prepared(let prepared) = captureLedgerByIdentity[captureIdentity]
        {
            return .nonCurrent(
                .noRetainedContent(prepared.capture.invalidationGeneration)
            )
        }
        if let latestInvalidationGeneration = latestInvalidationGenerationBySourceID[sourceID] {
            return .nonCurrent(.noRetainedContent(latestInvalidationGeneration))
        }
        return .current(.baseline(registration))
    }

    private func markCapturedConsumersPending(_ capture: ContentRepairPreparedCapture) {
        let sourceID = capture.registration.sourceID
        guard var sourceConsumers = consumersBySourceID[sourceID] else { return }
        for consumer in capture.consumers {
            sourceConsumers[consumer.identity]?.currentness = .nonCurrent(
                .capturePending(
                    identity: capture.identity,
                    invalidationGeneration: capture.invalidationGeneration
                )
            )
        }
        consumersBySourceID[sourceID] = sourceConsumers
    }

    private func recordLateConsumerIfNeeded(
        _ identity: ContentRepairConsumerIdentity,
        sourceID: FilesystemSourceID
    ) {
        guard let captureIdentity = pendingCaptureBySourceID[sourceID],
            case .prepared(var prepared) = captureLedgerByIdentity[captureIdentity]
        else {
            return
        }
        var lateIdentities = prepared.lateConsumerIdentities
        lateIdentities.insert(identity)
        prepared = PreparedCaptureRecord(
            capture: prepared.capture,
            priorCurrentnessByIdentity: prepared.priorCurrentnessByIdentity,
            lateConsumerIdentities: lateIdentities,
            priorInvalidation: prepared.priorInvalidation
        )
        captureLedgerByIdentity[captureIdentity] = .prepared(prepared)
    }

    private func restoreAfterAbortedCapture(_ prepared: PreparedCaptureRecord) {
        let sourceID = prepared.capture.registration.sourceID
        switch prepared.priorInvalidation {
        case .absent:
            latestInvalidationGenerationBySourceID[sourceID] = nil
        case .retained(let generation):
            latestInvalidationGenerationBySourceID[sourceID] = generation
        }
        guard var sourceConsumers = consumersBySourceID[sourceID] else { return }
        for (identity, priorCurrentness) in prepared.priorCurrentnessByIdentity {
            guard var record = sourceConsumers[identity] else { continue }
            record.currentness = priorCurrentness
            sourceConsumers[identity] = record
        }
        for identity in prepared.lateConsumerIdentities {
            guard var record = sourceConsumers[identity] else { continue }
            record.currentness = RegistryState.lateRegistrationCurrentness(
                latestInvalidationGeneration: latestInvalidationGenerationBySourceID[sourceID],
                registration: record.registration
            )
            sourceConsumers[identity] = record
        }
        consumersBySourceID[sourceID] = sourceConsumers
    }

    private func applyBoundRepairCurrentness(
        sourceID: FilesystemSourceID,
        repairGeneration: RepairGeneration
    ) {
        guard var sourceConsumers = consumersBySourceID[sourceID],
            let active = activeRepairBySourceID[sourceID]
        else {
            return
        }
        for (identity, var record) in sourceConsumers {
            let retry: ContentRepairRetryToken
            if let request = active.requestsByIdentity[identity], request.consumer == record.token {
                retry = request.retryToken
                record.currentness = .nonCurrent(.repairPending(retry))
            } else if case .nonCurrent(.capturePending) = record.currentness {
                record.currentness = .nonCurrent(
                    .noRetainedContent(active.invalidationGeneration)
                )
            }
            sourceConsumers[identity] = record
        }
        consumersBySourceID[sourceID] = sourceConsumers
    }

    private func applyAcceptedDisposition(
        _ disposition: ContentRepairConsumerDisposition,
        request: ContentRepairDeliveryRequest,
        invalidationGeneration: ContentRepairInvalidationGeneration
    ) {
        let sourceID = request.consumer.sourceID
        guard latestInvalidationGenerationBySourceID[sourceID] == invalidationGeneration else {
            return
        }
        guard var sourceConsumers = consumersBySourceID[sourceID],
            var record = sourceConsumers[request.consumer.identity],
            record.token == request.consumer
        else {
            return
        }
        switch disposition {
        case .rebuiltCurrent(let revision):
            record.currentness = .current(
                .rebuilt(
                    repairGenerationID: request.repairGeneration.id,
                    consumerRevision: revision
                )
            )
            sourceConsumers[request.consumer.identity] = record
        case .markedNonCurrent(let retry):
            record.currentness = .nonCurrent(.retryRetained(retry))
            sourceConsumers[request.consumer.identity] = record
        case .notApplicableNoRetainedState:
            record.currentness = .nonCurrent(
                .noRetainedContent(invalidationGeneration)
            )
            sourceConsumers[request.consumer.identity] = record
        }
        consumersBySourceID[sourceID] = sourceConsumers
    }

    private func retainOutboundAcknowledgement(
        _ accepted: ContentRepairAcceptedAcknowledgement,
        operation: AcceptedOutboundOperation
    ) {
        let token = accepted.sourceGateAcknowledgement
        if pendingOutboundAcknowledgementByToken[token] == nil {
            pendingOutboundAcknowledgementByToken[token] = PendingAcknowledgementRecord(
                accepted: accepted,
                operation: operation
            )
        }
    }

    private func replayedWithdrawal(
        for token: ContentRepairConsumerToken
    ) -> ContentRepairAcceptedAcknowledgement? {
        RegistryState.replayedWithdrawal(
            for: token,
            pendingByToken: pendingOutboundAcknowledgementByToken,
            confirmedBySourceID: confirmedAcknowledgementBySourceID
        )
    }

    private func replayedReplacement(
        for token: ContentRepairConsumerToken,
        eligibility: ContentRepairCaptureEligibility
    ) -> ContentRepairConsumerReplacement? {
        RegistryState.replayedReplacement(
            for: token,
            eligibility: eligibility,
            pendingByToken: pendingOutboundAcknowledgementByToken,
            confirmedBySourceID: confirmedAcknowledgementBySourceID
        )
    }

    private func finishActiveRepairIfReady(sourceID: FilesystemSourceID) {
        guard let repair = activeRepairBySourceID[sourceID], repair.pendingConsumerIdentities.isEmpty else {
            return
        }
        completedRepairBySourceID[sourceID] = repair
        activeRepairBySourceID[sourceID] = nil
        captureLedgerByIdentity = RegistryState.terminalizingBoundCapture(
            captureLedgerByIdentity,
            repairGenerationID: repair.generation.id,
            terminalization: .completed,
            retentionLimit: Self.terminalCaptureRetentionLimitPerSource
        )
        completeShutdownIfReady()
    }

    private func supersedePendingRepairIfNeeded(sourceID: FilesystemSourceID) {
        if let captureIdentity = pendingCaptureBySourceID[sourceID],
            case .prepared(let prepared) = captureLedgerByIdentity[captureIdentity]
        {
            restoreAfterAbortedCapture(prepared)
            captureLedgerByIdentity[captureIdentity] = .superseded(prepared.capture)
            pendingCaptureBySourceID[sourceID] = nil
        }
        guard let pendingRepair = pendingBoundRepairBySourceID[sourceID],
            let retained = RegistryState.boundCaptureRecord(
                repairGenerationID: pendingRepair.generation.id,
                ledger: captureLedgerByIdentity
            )
        else {
            return
        }
        restoreAfterAbortedCapture(retained.prepared)
        captureLedgerByIdentity[retained.prepared.capture.identity] =
            .superseded(retained.prepared.capture)
        pendingBoundRepairBySourceID[sourceID] = nil
        captureLedgerByIdentity = RegistryState.prunedCaptureLedger(
            captureLedgerByIdentity,
            sourceID: sourceID,
            retentionLimit: Self.terminalCaptureRetentionLimitPerSource
        )
    }

    private func preparedCaptureIdentity(
        for sourceID: FilesystemSourceID
    ) -> ContentRepairCaptureIdentity? {
        if let captureIdentity = pendingCaptureBySourceID[sourceID],
            case .prepared = captureLedgerByIdentity[captureIdentity]
        {
            return captureIdentity
        }
        if let pendingRepair = pendingBoundRepairBySourceID[sourceID],
            let retained = RegistryState.boundCaptureRecord(
                repairGenerationID: pendingRepair.generation.id,
                ledger: captureLedgerByIdentity
            )
        {
            return retained.prepared.capture.identity
        }
        return nil
    }

    private func makeShutdownDebtSnapshot() -> WorktreeContentRepairConsumerRegistryShutdownDebt {
        RegistryState.shutdownDebtSnapshot(
            consumersBySourceID: consumersBySourceID,
            pendingCaptures: pendingCaptureBySourceID,
            activeRepairs: activeRepairBySourceID,
            pendingRepairs: pendingBoundRepairBySourceID,
            outboundAcknowledgements: pendingOutboundAcknowledgementByToken
        )
    }

    private func makeSourceRetirementDebt(
        _ sourceID: FilesystemSourceID
    ) -> ContentRepairSourceRetirementDebt {
        RegistryState.sourceRetirementDebt(
            consumers: consumersBySourceID[sourceID] ?? [:],
            preparedCapture: pendingCaptureBySourceID[sourceID],
            activeRepair: activeRepairBySourceID[sourceID],
            pendingRepair: pendingBoundRepairBySourceID[sourceID],
            outboundAcknowledgements: Set(
                pendingOutboundAcknowledgementByToken.keys.filter {
                    $0.repairGenerationID.registration.sourceID == sourceID
                })
        )
    }

    private func completeShutdownIfReady() {
        guard lifecycle == .draining, makeShutdownDebtSnapshot().isEmpty else { return }
        lifecycle = .shutdown
    }
}

extension WorktreeContentRepairConsumerRegistry {
    private func replayedAcknowledgement(
        repairGenerationID: RepairGenerationID,
        consumer: ContentRepairConsumerToken,
        disposition: ContentRepairConsumerDisposition
    ) -> ContentRepairAcknowledgementResult {
        RegistryState.replayedAcknowledgement(
            repairGenerationID: repairGenerationID,
            consumer: consumer,
            disposition: disposition,
            pendingByToken: pendingOutboundAcknowledgementByToken,
            confirmedBySourceID: confirmedAcknowledgementBySourceID,
            completedBySourceID: completedRepairBySourceID
        )
    }

    func completeRetry(
        _ retry: ContentRepairRetryToken,
        consumerRevision: UInt64
    ) -> ContentRepairRetryCompletionResult {
        guard lifecycle != .shutdown else { return .shuttingDown }
        let sourceID = retry.consumer.sourceID
        guard retry.repairGenerationID.registration.sourceID == sourceID else { return .foreignSource }
        guard var sourceConsumers = consumersBySourceID[sourceID],
            var record = sourceConsumers[retry.consumer.identity]
        else {
            return .staleConsumerToken
        }
        guard record.token == retry.consumer else { return .staleConsumerToken }
        switch record.currentness {
        case .nonCurrent(.retryRetained(let retained)) where retained == retry:
            record.currentness = .current(
                .rebuilt(
                    repairGenerationID: retry.repairGenerationID,
                    consumerRevision: consumerRevision
                )
            )
            sourceConsumers[retry.consumer.identity] = record
            consumersBySourceID[sourceID] = sourceConsumers
            completeShutdownIfReady()
            return .completed(RegistryState.project(record))
        case .current(.rebuilt(let generation, let revision))
        where generation == retry.repairGenerationID && revision == consumerRevision:
            return .replayed(RegistryState.project(record))
        case .current, .nonCurrent:
            return .staleRetry
        }
    }

    func lookup(_ token: ContentRepairConsumerToken) -> ContentRepairConsumerLookupResult {
        guard let sourceConsumers = consumersBySourceID[token.sourceID] else { return .foreignSource }
        guard let record = sourceConsumers[token.identity], record.token == token else { return .staleToken }
        return .registered(RegistryState.project(record))
    }

    func shutdownDebtSnapshot() -> WorktreeContentRepairConsumerRegistryShutdownDebt {
        makeShutdownDebtSnapshot()
    }

    func beginOrResumeShutdown() -> ContentRepairConsumerRegistryShutdownResult {
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

    func retireSource(
        _ sourceID: FilesystemSourceID
    ) -> ContentRepairSourceRetirementResult {
        guard lifecycle != .shutdown else { return .shuttingDown }
        guard sourceID.kind == .registeredWorktreeContent else {
            return .sourceKindNotSupported(sourceID)
        }
        let sourceIsKnown =
            baselineRegistrationBySourceID[sourceID] != nil
            || consumersBySourceID[sourceID] != nil
            || completedRepairBySourceID[sourceID] != nil
            || latestInvalidationGenerationBySourceID[sourceID] != nil
            || confirmedAcknowledgementBySourceID[sourceID] != nil
        guard sourceIsKnown else { return .alreadyRetired(sourceID) }
        let debt = makeSourceRetirementDebt(sourceID)
        guard debt.isEmpty else { return .outstandingDebt(debt) }
        consumersBySourceID[sourceID] = nil
        baselineRegistrationBySourceID[sourceID] = nil
        completedRepairBySourceID[sourceID] = nil
        latestInvalidationGenerationBySourceID[sourceID] = nil
        confirmedAcknowledgementBySourceID[sourceID] = nil
        captureLedgerByIdentity = captureLedgerByIdentity.filter { _, entry in
            RegistryState.captureSourceID(entry) != sourceID
        }
        completeShutdownIfReady()
        return .retired(sourceID)
    }
}
