enum WorktreeContentRepairConsumerRegistryState {
    enum PriorInvalidationSnapshot: Sendable {
        case absent
        case retained(ContentRepairInvalidationGeneration)
    }

    struct ConsumerRecord: Sendable {
        var token: ContentRepairConsumerToken
        var registration: FSEventRegistrationToken
        var eligibility: ContentRepairCaptureEligibility
        var currentness: ContentRepairConsumerCurrentness
    }

    struct PreparedCaptureRecord: Sendable {
        let capture: ContentRepairPreparedCapture
        let priorCurrentnessByIdentity: [ContentRepairConsumerIdentity: ContentRepairConsumerCurrentness]
        let lateConsumerIdentities: Set<ContentRepairConsumerIdentity>
        let priorInvalidation: PriorInvalidationSnapshot
    }

    struct ActiveRepairRecord: Sendable {
        let generation: RepairGeneration
        let invalidationGeneration: ContentRepairInvalidationGeneration
        let requestsByIdentity: [ContentRepairConsumerIdentity: ContentRepairDeliveryRequest]
        var pendingConsumerIdentities: Set<ContentRepairConsumerIdentity>
        var acceptedByIdentity: [ContentRepairConsumerIdentity: ContentRepairAcceptedAcknowledgement]
    }

    struct BoundCaptureRecord: Sendable {
        let prepared: PreparedCaptureRecord
        let bound: ContentRepairBoundGeneration
    }

    enum CaptureLedgerEntry: Sendable {
        case prepared(PreparedCaptureRecord)
        case bound(BoundCaptureRecord)
        case completed(BoundCaptureRecord)
        case aborted(ContentRepairPreparedCapture)
        case superseded(ContentRepairPreparedCapture)
    }

    enum BoundCaptureTerminalization: Sendable {
        case completed
        case superseded
    }

    enum AcceptedOutboundOperation: Equatable, Sendable {
        case acknowledgement(
            repairGenerationID: RepairGenerationID,
            consumer: ContentRepairConsumerToken,
            disposition: ContentRepairConsumerDisposition
        )
        case withdrawal(ContentRepairConsumerToken)
        case replacement(
            prior: ContentRepairConsumerToken,
            eligibility: ContentRepairCaptureEligibility,
            replacement: ContentRepairConsumerReplacement
        )
    }

    struct PendingAcknowledgementRecord: Sendable {
        let accepted: ContentRepairAcceptedAcknowledgement
        let operation: AcceptedOutboundOperation
    }

    struct ConfirmedAcknowledgementRecord: Sendable {
        let pending: PendingAcknowledgementRecord
        let confirmationOrdinal: UInt64
    }

    static func recordedDisposition(
        _ disposition: ContentRepairConsumerDisposition
    ) -> ContentRepairRecordedDisposition {
        switch disposition {
        case .rebuiltCurrent(let revision):
            .rebuiltCurrent(consumerRevision: revision)
        case .markedNonCurrent(let retry):
            .markedNonCurrent(retry: retry)
        case .notApplicableNoRetainedState:
            .notApplicableNoRetainedState
        }
    }

    static func transferredCurrentness(
        _ currentness: ContentRepairConsumerCurrentness,
        replacementToken: ContentRepairConsumerToken
    ) -> ContentRepairConsumerCurrentness {
        switch currentness {
        case .current(let revision):
            return .current(revision)
        case .nonCurrent(.capturePending(let captureIdentity, let invalidationGeneration)):
            return .nonCurrent(
                .capturePending(
                    identity: captureIdentity,
                    invalidationGeneration: invalidationGeneration
                )
            )
        case .nonCurrent(.repairPending(let retry)), .nonCurrent(.retryRetained(let retry)):
            return .nonCurrent(
                .retryRetained(
                    .generate(
                        repairGenerationID: retry.repairGenerationID,
                        consumer: replacementToken
                    )
                )
            )
        case .nonCurrent(.noRetainedContent(let invalidationGeneration)):
            return .nonCurrent(.noRetainedContent(invalidationGeneration))
        }
    }

    static func lateRegistrationCurrentness(
        latestInvalidationGeneration: ContentRepairInvalidationGeneration?,
        registration: FSEventRegistrationToken
    ) -> ContentRepairConsumerCurrentness {
        if let latestInvalidationGeneration {
            return .nonCurrent(.noRetainedContent(latestInvalidationGeneration))
        }
        return .current(.baseline(registration))
    }

    static func projectBoundGeneration(
        _ repair: ActiveRepairRecord
    ) -> ContentRepairBoundGeneration {
        let requests = repair.requestsByIdentity.values.sorted { left, right in
            if left.consumer.registrationOrdinal != right.consumer.registrationOrdinal {
                return left.consumer.registrationOrdinal < right.consumer.registrationOrdinal
            }
            return left.consumer.generation < right.consumer.generation
        }
        return ContentRepairBoundGeneration(
            repairGeneration: repair.generation,
            deliveryRequests: requests
        )
    }

    static func deliveryRequests(
        capture: ContentRepairPreparedCapture,
        repairGeneration: RepairGeneration
    ) -> [ContentRepairDeliveryRequest] {
        capture.consumers.map { consumer in
            ContentRepairDeliveryRequest(
                repairGeneration: repairGeneration,
                invalidationGeneration: capture.invalidationGeneration,
                consumer: consumer,
                retryToken: .generate(
                    repairGenerationID: repairGeneration.id,
                    consumer: consumer
                )
            )
        }.sorted { left, right in
            if left.consumer.registrationOrdinal != right.consumer.registrationOrdinal {
                return left.consumer.registrationOrdinal < right.consumer.registrationOrdinal
            }
            return left.consumer.generation < right.consumer.generation
        }
    }

    static func terminalizedForSupersession(
        _ repair: ActiveRepairRecord
    ) -> ActiveRepairRecord {
        var terminal = repair
        terminal.pendingConsumerIdentities = []
        return terminal
    }

    static func project(_ record: ConsumerRecord) -> ContentRepairConsumerRegistration {
        ContentRepairConsumerRegistration(
            token: record.token,
            eligibility: record.eligibility,
            currentness: record.currentness
        )
    }

    static func captureSourceID(_ entry: CaptureLedgerEntry) -> FilesystemSourceID {
        switch entry {
        case .prepared(let retained):
            retained.capture.registration.sourceID
        case .bound(let retained), .completed(let retained):
            retained.prepared.capture.registration.sourceID
        case .aborted(let capture), .superseded(let capture):
            capture.registration.sourceID
        }
    }

    static func retainedAcknowledgementRecords(
        sourceID: FilesystemSourceID,
        pendingByToken: [FilesystemRepairAcknowledgementToken: PendingAcknowledgementRecord],
        confirmedBySourceID: [FilesystemSourceID: [FilesystemRepairAcknowledgementToken:
            ConfirmedAcknowledgementRecord]]
    ) -> [PendingAcknowledgementRecord] {
        let pending = pendingByToken.values.filter { record in
            record.accepted.sourceGateAcknowledgement.repairGenerationID.registration.sourceID
                == sourceID
        }
        let confirmed = confirmedBySourceID[sourceID]?.values.map(\.pending) ?? []
        return Array(pending) + confirmed
    }

    static func prunedConfirmedAcknowledgements(
        _ confirmed: [FilesystemRepairAcknowledgementToken: ConfirmedAcknowledgementRecord],
        retentionLimit: Int
    ) -> [FilesystemRepairAcknowledgementToken: ConfirmedAcknowledgementRecord] {
        var retained = confirmed
        while retained.count > retentionLimit {
            guard
                let oldest = retained.min(by: {
                    $0.value.confirmationOrdinal < $1.value.confirmationOrdinal
                })
            else {
                break
            }
            retained[oldest.key] = nil
        }
        return retained
    }

    static func replayedWithdrawal(
        for token: ContentRepairConsumerToken,
        pendingByToken: [FilesystemRepairAcknowledgementToken: PendingAcknowledgementRecord],
        confirmedBySourceID: [FilesystemSourceID: [FilesystemRepairAcknowledgementToken:
            ConfirmedAcknowledgementRecord]]
    ) -> ContentRepairAcceptedAcknowledgement? {
        for record in retainedAcknowledgementRecords(
            sourceID: token.sourceID,
            pendingByToken: pendingByToken,
            confirmedBySourceID: confirmedBySourceID
        ) {
            guard case .withdrawal(let retainedToken) = record.operation,
                retainedToken == token
            else {
                continue
            }
            return record.accepted
        }
        return nil
    }

    static func replayedAcknowledgement(
        repairGenerationID: RepairGenerationID,
        consumer: ContentRepairConsumerToken,
        disposition: ContentRepairConsumerDisposition,
        pendingByToken: [FilesystemRepairAcknowledgementToken: PendingAcknowledgementRecord],
        confirmedBySourceID: [FilesystemSourceID: [FilesystemRepairAcknowledgementToken:
            ConfirmedAcknowledgementRecord]],
        completedBySourceID: [FilesystemSourceID: ActiveRepairRecord]
    ) -> ContentRepairAcknowledgementResult {
        for record in retainedAcknowledgementRecords(
            sourceID: consumer.sourceID,
            pendingByToken: pendingByToken,
            confirmedBySourceID: confirmedBySourceID
        ) {
            guard
                case .acknowledgement(
                    let retainedGeneration,
                    let retainedConsumer,
                    let retainedDisposition
                ) = record.operation,
                retainedGeneration == repairGenerationID,
                retainedConsumer == consumer,
                retainedDisposition == disposition
            else {
                continue
            }
            return .replayed(record.accepted)
        }
        guard let completed = completedBySourceID[consumer.sourceID],
            completed.generation.id == repairGenerationID
        else {
            return .debtRetained(.staleRepairGeneration)
        }
        guard let accepted = completed.acceptedByIdentity[consumer.identity],
            accepted.sourceGateAcknowledgement.participant == consumer.sourceGateParticipant,
            accepted.disposition == recordedDisposition(disposition)
        else {
            return .debtRetained(.staleConsumerToken)
        }
        return .replayed(accepted)
    }

    static func replayedReplacement(
        for token: ContentRepairConsumerToken,
        eligibility: ContentRepairCaptureEligibility,
        pendingByToken: [FilesystemRepairAcknowledgementToken: PendingAcknowledgementRecord],
        confirmedBySourceID: [FilesystemSourceID: [FilesystemRepairAcknowledgementToken:
            ConfirmedAcknowledgementRecord]]
    ) -> ContentRepairConsumerReplacement? {
        for record in retainedAcknowledgementRecords(
            sourceID: token.sourceID,
            pendingByToken: pendingByToken,
            confirmedBySourceID: confirmedBySourceID
        ) {
            guard case .replacement(let prior, let retainedEligibility, let replacement) = record.operation,
                prior == token, retainedEligibility == eligibility
            else {
                continue
            }
            return replacement
        }
        return nil
    }

    static func boundCaptureRecord(
        repairGenerationID: RepairGenerationID,
        ledger: [ContentRepairCaptureIdentity: CaptureLedgerEntry]
    ) -> BoundCaptureRecord? {
        for entry in ledger.values {
            switch entry {
            case .bound(let retained)
            where retained.bound.repairGeneration.id == repairGenerationID:
                return retained
            case .completed(let retained)
            where retained.bound.repairGeneration.id == repairGenerationID:
                return retained
            case .prepared, .bound, .completed, .aborted, .superseded:
                continue
            }
        }
        return nil
    }

    static func prunedCaptureLedger(
        _ ledger: [ContentRepairCaptureIdentity: CaptureLedgerEntry],
        sourceID: FilesystemSourceID,
        retentionLimit: Int
    ) -> [ContentRepairCaptureIdentity: CaptureLedgerEntry] {
        var retained = ledger
        let terminalEntries = retained.filter { _, entry in
            guard captureSourceID(entry) == sourceID else { return false }
            switch entry {
            case .completed, .aborted, .superseded:
                return true
            case .prepared, .bound:
                return false
            }
        }
        guard terminalEntries.count > retentionLimit else { return retained }
        let ordered = terminalEntries.sorted {
            captureInvalidationGeneration($0.value).value
                < captureInvalidationGeneration($1.value).value
        }
        for (identity, _) in ordered.prefix(terminalEntries.count - retentionLimit) {
            retained[identity] = nil
        }
        return retained
    }

    static func terminalizingBoundCapture(
        _ ledger: [ContentRepairCaptureIdentity: CaptureLedgerEntry],
        repairGenerationID: RepairGenerationID,
        terminalization: BoundCaptureTerminalization,
        retentionLimit: Int
    ) -> [ContentRepairCaptureIdentity: CaptureLedgerEntry] {
        guard
            let bound = boundCaptureRecord(
                repairGenerationID: repairGenerationID,
                ledger: ledger
            )
        else {
            return ledger
        }
        var terminal = ledger
        switch terminalization {
        case .completed:
            terminal[bound.prepared.capture.identity] = .completed(bound)
        case .superseded:
            terminal[bound.prepared.capture.identity] = .superseded(bound.prepared.capture)
        }
        return prunedCaptureLedger(
            terminal,
            sourceID: repairGenerationID.registration.sourceID,
            retentionLimit: retentionLimit
        )
    }

    private static func captureInvalidationGeneration(
        _ entry: CaptureLedgerEntry
    ) -> ContentRepairInvalidationGeneration {
        switch entry {
        case .prepared(let retained):
            retained.capture.invalidationGeneration
        case .bound(let retained), .completed(let retained):
            retained.prepared.capture.invalidationGeneration
        case .aborted(let capture), .superseded(let capture):
            capture.invalidationGeneration
        }
    }

    static func retainedRetries(
        consumers: [ContentRepairConsumerIdentity: ConsumerRecord]
    ) -> Set<ContentRepairRetryToken> {
        var retries: Set<ContentRepairRetryToken> = []
        for record in consumers.values {
            guard case .nonCurrent(.retryRetained(let retry)) = record.currentness else {
                continue
            }
            retries.insert(retry)
        }
        return retries
    }

    static func shutdownDebtSnapshot(
        consumersBySourceID: [FilesystemSourceID: [ContentRepairConsumerIdentity: ConsumerRecord]],
        pendingCaptures: [FilesystemSourceID: ContentRepairCaptureIdentity],
        activeRepairs: [FilesystemSourceID: ActiveRepairRecord],
        pendingRepairs: [FilesystemSourceID: ActiveRepairRecord],
        outboundAcknowledgements: [FilesystemRepairAcknowledgementToken: PendingAcknowledgementRecord]
    ) -> WorktreeContentRepairConsumerRegistryShutdownDebt {
        let retries = Set(
            consumersBySourceID.values.flatMap { consumers in
                retainedRetries(consumers: consumers)
            })
        return WorktreeContentRepairConsumerRegistryShutdownDebt(
            preparedCaptures: Set(pendingCaptures.values),
            activeRepairGenerations: Set(activeRepairs.values.map(\.generation.id)),
            pendingRepairGenerations: Set(pendingRepairs.values.map(\.generation.id)),
            retainedRetries: retries,
            outboundAcknowledgements: Set(outboundAcknowledgements.keys)
        )
    }

    static func sourceRetirementDebt(
        consumers: [ContentRepairConsumerIdentity: ConsumerRecord],
        preparedCapture: ContentRepairCaptureIdentity?,
        activeRepair: ActiveRepairRecord?,
        pendingRepair: ActiveRepairRecord?,
        outboundAcknowledgements: Set<FilesystemRepairAcknowledgementToken>
    ) -> ContentRepairSourceRetirementDebt {
        ContentRepairSourceRetirementDebt(
            preparedCaptures: Set(preparedCapture.map { [$0] } ?? []),
            activeRepairGenerations: Set(activeRepair.map { [$0.generation.id] } ?? []),
            pendingRepairGenerations: Set(pendingRepair.map { [$0.generation.id] } ?? []),
            retainedRetries: retainedRetries(consumers: consumers),
            outboundAcknowledgements: outboundAcknowledgements
        )
    }
}
