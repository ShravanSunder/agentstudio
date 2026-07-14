import Foundation

protocol FilesystemObservationSemanticCustodySink {
    mutating func accept(
        _ observation: FSEventObservation,
        identity: FilesystemObservationContributionIdentity
    ) -> FilesystemObservationSemanticCustodyResult
}

enum FilesystemObservationSemanticCustodyResult: Equatable, Sendable {
    case accepted
    case retryRequested
}

enum FilesystemObservationRecoveryAdmissionContext: Sendable {
    case notRequired
    case required(
        trigger: FilesystemRepairTriggerClass,
        watermark: FilesystemRepairWatermark,
        participants: Set<FilesystemRepairParticipantToken>
    )
}

enum FilesystemObservationWholeLeaseAuthorityEvidence: Equatable, Sendable {
    case contributions(FilesystemSemanticLeaseAcceptanceAuthority)
    case contributionsWithRecovery(
        FilesystemSemanticLeaseAcceptanceAuthority,
        FilesystemSourceGateRecoveryAcceptance
    )
    case recovery(FilesystemSourceGateRecoveryAcceptance)
}

struct FilesystemObservationWholeLeaseTransferAuthority: Equatable, Sendable {
    let preflight: FilesystemObservationWholeLeasePreflightReceipt
    let evidence: FilesystemObservationWholeLeaseAuthorityEvidence

    var binding: FilesystemObservationSlotBinding { preflight.binding }

    fileprivate init(
        preflight: FilesystemObservationWholeLeasePreflightReceipt,
        evidence: FilesystemObservationWholeLeaseAuthorityEvidence
    ) {
        self.preflight = preflight
        self.evidence = evidence
    }
}

struct FilesystemObservationSlotRetirementAuthority: Equatable, Sendable {
    private let value: UUID

    var isUUIDv7: Bool { UUIDv7.isV7(value) }

    fileprivate init() {
        value = UUIDv7.generate()
    }
}

enum FilesystemObservationRegistryCompletionAuthority: Equatable, Sendable {
    case ordinaryLease
    case retirement(FilesystemObservationSlotRetirementAuthority)
}

enum FilesystemObservationWholeLeaseTransferOutcome: Equatable, Sendable {
    case ordinaryLease
    case retired(FilesystemObservationSlotRetirementReceipt)
}

struct FilesystemObservationWholeLeaseTransferReceipt: Equatable, Sendable {
    let binding: FilesystemObservationSlotBinding
    let outcome: FilesystemObservationWholeLeaseTransferOutcome
}

enum FilesystemObservationWholeLeaseCompletionRejection: Equatable, Sendable {
    case noAcknowledgedTransfer
    case authorityMismatch
    case acknowledgementMismatch
    case semanticClearMismatch
    case sourceGateClearMismatch
    case registryTransitionRejected
}

enum FilesystemObservationWholeLeaseCompletionResult: Equatable, Sendable {
    case completed(FilesystemObservationWholeLeaseTransferReceipt)
    case rejected(FilesystemObservationWholeLeaseCompletionRejection)
}

enum FilesystemObservationLeaseTransferRetryReason: Equatable, Sendable {
    case semanticCustodyRequestedRetry
}

enum FilesystemObservationLeaseTransferRejection: Equatable, Sendable {
    case preflight(FilesystemObservationWholeLeasePreflightRejection)
    case semanticPresentation
    case semanticReplay
    case recoveryContextRequired
    case unexpectedRecoveryContext
    case sourceGateAdmission
    case genericAcknowledgement
    case semanticClear
    case sourceGateClear
    case completion(FilesystemObservationWholeLeaseCompletionRejection)
}

enum FilesystemObservationLeaseTransferResult: Equatable, Sendable {
    case transferred(FilesystemObservationWholeLeaseTransferReceipt)
    case retried(FilesystemObservationLeaseTransferRetryReason)
    case rejected(FilesystemObservationLeaseTransferRejection)
}

struct FilesystemObservationLeaseTransferDiagnostics: Equatable, Sendable {
    let semanticReplay: FilesystemObservationSemanticReplayDiagnostics
    let completedTransferCount: UInt64
    let retryCount: UInt64
    let rejectionCount: UInt64
}

struct FilesystemObservationLeaseTransfer {
    private var semanticReplay: FilesystemObservationSemanticReplay
    private var completedTransferCount: UInt64 = 0
    private var retryCount: UInt64 = 0
    private var rejectionCount: UInt64 = 0

    init(
        physicalSlotIDs: [FilesystemObservationPhysicalSlotID],
        maximumContributionsPerLease: Int
    ) throws {
        semanticReplay = try FilesystemObservationSemanticReplay(
            physicalSlotIDs: physicalSlotIDs,
            maximumContributionsPerLease: maximumContributionsPerLease
        )
    }

    var diagnostics: FilesystemObservationLeaseTransferDiagnostics {
        FilesystemObservationLeaseTransferDiagnostics(
            semanticReplay: semanticReplay.diagnostics,
            completedTransferCount: completedTransferCount,
            retryCount: retryCount,
            rejectionCount: rejectionCount
        )
    }

    mutating func transfer<SemanticSink: FilesystemObservationSemanticCustodySink>(
        _ lease: FilesystemObservationDrainLease,
        sourceGate: inout FilesystemSourceGate,
        recoveryContext: FilesystemObservationRecoveryAdmissionContext,
        semanticSink: inout SemanticSink,
        consumerPort: FilesystemObservationActorConsumerPort
    ) -> FilesystemObservationLeaseTransferResult {
        let preflight: FilesystemObservationWholeLeasePreflightReceipt
        switch consumerPort.preflightWholeLeaseTransfer(lease) {
        case .authorized(let receipt):
            preflight = receipt
        case .rejected(let rejection):
            return reject(.preflight(rejection))
        }

        let semanticClearRequirement: SemanticClearRequirement
        switch acceptSemanticCustody(lease, semanticSink: &semanticSink) {
        case .accepted(let authority):
            semanticClearRequirement = .required(authority)
        case .notRequired:
            semanticClearRequirement = .notRequired
        case .retryRequested:
            guard
                case .retried = consumerPort.acknowledge(
                    token: lease.token,
                    disposition: .retry
                )
            else {
                return reject(.genericAcknowledgement)
            }
            retryCount += 1
            return .retried(.semanticCustodyRequestedRetry)
        case .rejected:
            return retryRejectedLease(lease, consumerPort: consumerPort, reason: .semanticReplay)
        }

        let sourceGateClearRequirement: SourceGateClearRequirement
        switch acceptRecovery(
            in: lease,
            sourceGate: &sourceGate,
            recoveryContext: recoveryContext
        ) {
        case .accepted(let acceptance):
            sourceGateClearRequirement = .required(acceptance)
        case .notRequired:
            sourceGateClearRequirement = .notRequired
        case .rejected(let rejection):
            return retryRejectedLease(lease, consumerPort: consumerPort, reason: rejection)
        }

        return completeAcceptedTransfer(
            lease,
            preflight: preflight,
            semanticRequirement: semanticClearRequirement,
            sourceGateRequirement: sourceGateClearRequirement,
            sourceGate: &sourceGate,
            consumerPort: consumerPort
        )
    }

    private mutating func completeAcceptedTransfer(
        _ lease: FilesystemObservationDrainLease,
        preflight: FilesystemObservationWholeLeasePreflightReceipt,
        semanticRequirement: SemanticClearRequirement,
        sourceGateRequirement: SourceGateClearRequirement,
        sourceGate: inout FilesystemSourceGate,
        consumerPort: FilesystemObservationActorConsumerPort
    ) -> FilesystemObservationLeaseTransferResult {
        let authority: FilesystemObservationWholeLeaseTransferAuthority
        switch (semanticRequirement, sourceGateRequirement) {
        case (.required(let semanticAuthority), .notRequired):
            authority = FilesystemObservationWholeLeaseTransferAuthority(
                preflight: preflight,
                evidence: .contributions(semanticAuthority)
            )
        case (
            .required(let semanticAuthority),
            .required(let recoveryAcceptance)
        ):
            authority = FilesystemObservationWholeLeaseTransferAuthority(
                preflight: preflight,
                evidence: .contributionsWithRecovery(
                    semanticAuthority,
                    recoveryAcceptance
                )
            )
        case (.notRequired, .required(let recoveryAcceptance)):
            authority = FilesystemObservationWholeLeaseTransferAuthority(
                preflight: preflight,
                evidence: .recovery(recoveryAcceptance)
            )
        case (.notRequired, .notRequired):
            return retryRejectedLease(
                lease,
                consumerPort: consumerPort,
                reason: .semanticReplay
            )
        }

        let acknowledgement: FilesystemLeaseAcknowledgementReceipt
        switch consumerPort.acknowledge(
            token: lease.token,
            disposition: acknowledgementDisposition(for: authority)
        ) {
        case .transferredAuthoritative(let receipt, _),
            .transferredRecovery(let receipt, _, _):
            acknowledgement = receipt
        case .retried, .dispositionMismatch, .invalidToken, .closed:
            return reject(.genericAcknowledgement)
        }

        let semanticCompletion: FilesystemSemanticClearCompletion
        switch semanticRequirement {
        case .notRequired:
            semanticCompletion = .notRequired(lease.binding)
        case .required:
            guard
                case .cleared(let receipt) = semanticReplay.completeTransferredLease(
                    authority: authority,
                    acknowledgement: acknowledgement
                )
            else {
                return reject(.semanticClear)
            }
            semanticCompletion = .cleared(receipt)
        }

        let sourceGateCompletion: FilesystemSourceGateTransferClearCompletion
        switch sourceGateRequirement {
        case .notRequired:
            sourceGateCompletion = .notRequired(lease.binding)
        case .required:
            guard
                case .cleared(let receipt) = sourceGate.clearTransferredMailboxRecovery(
                    authority: authority,
                    acknowledgement: acknowledgement
                )
            else {
                return reject(.sourceGateClear)
            }
            sourceGateCompletion = .cleared(receipt)
        }

        switch consumerPort.completeWholeLeaseTransfer(
            authority: authority,
            acknowledgement: acknowledgement,
            semantic: semanticCompletion,
            sourceGate: sourceGateCompletion,
            registry: registryCompletionAuthority(for: lease)
        ) {
        case .completed(let receipt):
            completedTransferCount += 1
            return .transferred(receipt)
        case .rejected(let rejection):
            return reject(.completion(rejection))
        }
    }

    private enum SemanticAcceptance {
        case accepted(FilesystemSemanticLeaseAcceptanceAuthority)
        case notRequired
        case retryRequested
        case rejected
    }

    private enum SemanticClearRequirement {
        case required(FilesystemSemanticLeaseAcceptanceAuthority)
        case notRequired
    }

    private enum RecoveryAcceptance {
        case accepted(FilesystemSourceGateRecoveryAcceptance)
        case notRequired
        case rejected(FilesystemObservationLeaseTransferRejection)
    }

    private enum SourceGateClearRequirement {
        case required(FilesystemSourceGateRecoveryAcceptance)
        case notRequired
    }

    private mutating func acceptSemanticCustody<
        SemanticSink: FilesystemObservationSemanticCustodySink
    >(
        _ lease: FilesystemObservationDrainLease,
        semanticSink: inout SemanticSink
    ) -> SemanticAcceptance {
        let attempt: FilesystemObservationSemanticReplayAttempt
        switch semanticReplay.present(lease) {
        case .began(let beganAttempt), .resumed(let beganAttempt, _):
            attempt = beganAttempt
        case .recoveryOnly:
            return .notRequired
        case .undeclaredPhysicalSlot, .leaseTooLarge, .contributionBindingMismatch,
            .bindingOrIdentityVectorMismatch:
            return .rejected
        }
        let contributions = contributionBatch(in: lease)
        for (index, contribution) in contributions.enumerated() {
            let identity = contribution.identity
            switch semanticReplay.decision(for: identity, at: index, attempt: attempt) {
            case .alreadyAccepted:
                continue
            case .requiresAcceptance:
                let disposition: FilesystemObservationSemanticAcceptedDisposition
                switch contribution {
                case .observation(_, let observation):
                    guard semanticSink.accept(observation, identity: identity) == .accepted else {
                        return .retryRequested
                    }
                    disposition = .observationAccepted
                case .retirementFence(_, let fence):
                    disposition = .retirementFenceAccepted(fence.identity)
                }
                guard
                    case .recorded = semanticReplay.recordAccepted(
                        disposition,
                        for: identity,
                        at: index,
                        attempt: attempt
                    )
                else {
                    return .rejected
                }
            case .outOfOrder, .identityOrIndexMismatch, .staleConsumerAttempt,
                .fingerprintMismatch, .undeclaredPhysicalSlot:
                return .rejected
            }
        }
        guard
            case .wholeLeaseSemanticallyAccepted(let authority) =
                semanticReplay.semanticCompletion(for: attempt)
        else {
            return .rejected
        }
        return .accepted(authority)
    }

    private mutating func acceptRecovery(
        in lease: FilesystemObservationDrainLease,
        sourceGate: inout FilesystemSourceGate,
        recoveryContext: FilesystemObservationRecoveryAdmissionContext
    ) -> RecoveryAcceptance {
        let evidence: FixedFilesystemRecoveryEvidenceSnapshot
        switch lease.payload {
        case .contributions, .recovery:
            if case .recovery(let recoveryEvidence) = lease.payload {
                evidence = recoveryEvidence
            } else {
                guard case .notRequired = recoveryContext else {
                    return .rejected(.unexpectedRecoveryContext)
                }
                return .notRequired
            }
        case .contributionsWithRecovery(_, let recoveryEvidence):
            evidence = recoveryEvidence
        }
        guard
            case .required(let trigger, let watermark, let participants) = recoveryContext
        else {
            return .rejected(.recoveryContextRequired)
        }
        switch sourceGate.acceptMailboxRecovery(
            evidence,
            trigger: trigger,
            watermark: watermark,
            participants: participants
        ) {
        case .admitted(let acceptance):
            return .accepted(acceptance)
        case .bindingMismatch, .retainedRequestConflict, .rejected,
            .generationExhausted, .shuttingDown:
            return .rejected(.sourceGateAdmission)
        }
    }

    private func acknowledgementDisposition(
        for authority: FilesystemObservationWholeLeaseTransferAuthority
    ) -> FilesystemObservationDrainDisposition {
        switch authority.evidence {
        case .contributions:
            .transferredAuthoritative(authority)
        case .contributionsWithRecovery(_, let acceptance), .recovery(let acceptance):
            .transferredRecovery(authority, acceptance)
        }
    }

    private func registryCompletionAuthority(
        for lease: FilesystemObservationDrainLease
    ) -> FilesystemObservationRegistryCompletionAuthority {
        let containsRetirementFence = contributionBatch(in: lease).contains { contribution in
            if case .retirementFence = contribution { return true }
            return false
        }
        return containsRetirementFence
            ? .retirement(FilesystemObservationSlotRetirementAuthority())
            : .ordinaryLease
    }

    private mutating func retryRejectedLease(
        _ lease: FilesystemObservationDrainLease,
        consumerPort: FilesystemObservationActorConsumerPort,
        reason: FilesystemObservationLeaseTransferRejection
    ) -> FilesystemObservationLeaseTransferResult {
        guard
            case .retried = consumerPort.acknowledge(
                token: lease.token,
                disposition: .retry
            )
        else {
            return reject(.genericAcknowledgement)
        }
        return reject(reason)
    }

    private mutating func reject(
        _ reason: FilesystemObservationLeaseTransferRejection
    ) -> FilesystemObservationLeaseTransferResult {
        rejectionCount += 1
        return .rejected(reason)
    }

    private func contributionBatch(
        in lease: FilesystemObservationDrainLease
    ) -> [FilesystemObservationMailboxContribution] {
        switch lease.payload {
        case .contributions(let batch), .contributionsWithRecovery(let batch, _):
            [batch.first] + batch.remaining
        case .recovery:
            []
        }
    }

}
