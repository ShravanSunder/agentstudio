import Foundation

enum FilesystemSemanticReplayConfigurationError: Error, Equatable {
    case duplicatePhysicalSlotID
    case invalidMaximumContributionsPerLease
    case retainedIdentityCapacityOverflow
}

struct FilesystemObservationSemanticAttemptIdentity: Equatable, Hashable, Sendable {
    private let value: UUID

    var isUUIDv7: Bool { UUIDv7.isV7(value) }

    fileprivate init(value: UUID) {
        self.value = value
    }
}

struct FilesystemObservationSemanticLeaseFingerprint: Equatable, Sendable {
    let binding: FilesystemObservationSlotBinding
    let orderedContributionIdentities: [FilesystemObservationContributionIdentity]

    fileprivate init(
        binding: FilesystemObservationSlotBinding,
        orderedContributionIdentities: [FilesystemObservationContributionIdentity]
    ) {
        self.binding = binding
        self.orderedContributionIdentities = orderedContributionIdentities
    }
}

struct FilesystemObservationSemanticReplayAttempt: Equatable, Sendable {
    let identity: FilesystemObservationSemanticAttemptIdentity
    let fingerprint: FilesystemObservationSemanticLeaseFingerprint

    fileprivate init(
        identity: FilesystemObservationSemanticAttemptIdentity,
        fingerprint: FilesystemObservationSemanticLeaseFingerprint
    ) {
        self.identity = identity
        self.fingerprint = fingerprint
    }
}

enum FilesystemObservationSemanticAcceptedDisposition: Equatable, Sendable {
    case observationAccepted
    case retirementFenceAccepted(FilesystemObservationRetirementFenceIdentity)
}

struct FilesystemSemanticLeaseAcceptanceAuthority: Equatable, Sendable {
    let attemptIdentity: FilesystemObservationSemanticAttemptIdentity
    fileprivate let fingerprint: FilesystemObservationSemanticLeaseFingerprint
    fileprivate let acceptedDispositions: [FilesystemObservationSemanticAcceptedDisposition]

    func matches(
        binding: FilesystemObservationSlotBinding,
        contributionIdentities: [FilesystemObservationContributionIdentity]
    ) -> Bool {
        fingerprint.binding == binding
            && fingerprint.orderedContributionIdentities == contributionIdentities
            && acceptedDispositions.count == contributionIdentities.count
    }

    var acceptedRetirementFenceIdentity: FilesystemObservationRetirementFenceIdentity? {
        for disposition in acceptedDispositions.reversed() {
            if case .retirementFenceAccepted(let identity) = disposition {
                return identity
            }
        }
        return nil
    }
}

enum FilesystemObservationSemanticPresentationResult: Equatable, Sendable {
    case began(FilesystemObservationSemanticReplayAttempt)
    case resumed(
        FilesystemObservationSemanticReplayAttempt,
        acceptedPrefix: [FilesystemObservationSemanticAcceptedDisposition]
    )
    case undeclaredPhysicalSlot
    case recoveryOnly
    case leaseTooLarge(maximum: Int, presented: Int)
    case contributionBindingMismatch
    case bindingOrIdentityVectorMismatch(
        retained: FilesystemObservationSemanticLeaseFingerprint,
        presented: FilesystemObservationSemanticLeaseFingerprint
    )
}

enum FilesystemObservationSemanticDecision: Equatable, Sendable {
    case requiresAcceptance(
        index: Int,
        identity: FilesystemObservationContributionIdentity
    )
    case alreadyAccepted(
        FilesystemObservationSemanticAcceptedDisposition,
        index: Int,
        identity: FilesystemObservationContributionIdentity
    )
    case outOfOrder(expectedIndex: Int, presentedIndex: Int)
    case identityOrIndexMismatch
    case staleConsumerAttempt
    case fingerprintMismatch
    case undeclaredPhysicalSlot
}

enum FilesystemObservationSemanticRecordResult: Equatable, Sendable {
    case recorded(acceptedCount: Int, remainingCount: Int)
    case alreadyAccepted(FilesystemObservationSemanticAcceptedDisposition)
    case outOfOrder(expectedIndex: Int, presentedIndex: Int)
    case identityOrIndexMismatch
    case staleConsumerAttempt
    case fingerprintMismatch
    case undeclaredPhysicalSlot
}

enum FilesystemObservationSemanticCompletionResult: Equatable, Sendable {
    case wholeLeaseSemanticallyAccepted(
        FilesystemSemanticLeaseAcceptanceAuthority
    )
    case incomplete(acceptedCount: Int, requiredCount: Int)
    case staleConsumerAttempt
    case fingerprintMismatch
    case undeclaredPhysicalSlot
}

struct FilesystemObservationSemanticTransferClearReceipt: Equatable, Sendable {
    fileprivate let authority: FilesystemObservationWholeLeaseTransferAuthority
    fileprivate let acknowledgement: FilesystemLeaseAcknowledgementReceipt
    fileprivate let attemptIdentity: FilesystemObservationSemanticAttemptIdentity

    var binding: FilesystemObservationSlotBinding { authority.binding }

    func matches(
        authority expectedAuthority: FilesystemObservationWholeLeaseTransferAuthority,
        acknowledgement expectedAcknowledgement: FilesystemLeaseAcknowledgementReceipt
    ) -> Bool {
        authority == expectedAuthority
            && acknowledgement == expectedAcknowledgement
            && expectedAcknowledgement.matches(expectedAuthority)
    }
}

enum FilesystemSemanticClearCompletion: Equatable, Sendable {
    case notRequired(FilesystemObservationSlotBinding)
    case cleared(FilesystemObservationSemanticTransferClearReceipt)

    var binding: FilesystemObservationSlotBinding {
        switch self {
        case .notRequired(let binding): binding
        case .cleared(let receipt): receipt.binding
        }
    }
}

enum FilesystemSemanticTransferCompletionResult: Equatable, Sendable {
    case cleared(FilesystemObservationSemanticTransferClearReceipt)
    case acknowledgementMismatch
    case authorityHasNoSemanticCustody
    case notSemanticallyComplete
    case staleConsumerAttempt
    case fingerprintMismatch
    case undeclaredPhysicalSlot
}

struct FilesystemObservationSemanticReplayDiagnostics: Equatable, Sendable {
    let declaredPhysicalSlotCount: Int
    let retainedLeaseCount: Int
    let retainedIdentityCount: Int
    let retainedIdentityHighWater: Int
    let maximumRetainedIdentityCapacity: Int
}

struct FilesystemObservationSemanticRetainedShutdownDebt: Equatable, Sendable {
    let fingerprint: FilesystemObservationSemanticLeaseFingerprint
    let currentAttemptIdentity: FilesystemObservationSemanticAttemptIdentity
    let acceptedPrefix: [FilesystemObservationSemanticAcceptedDisposition]
}

enum FilesystemObservationSemanticShutdownSlotDebt: Equatable, Sendable {
    case vacant(FilesystemObservationPhysicalSlotID)
    case retained(FilesystemObservationSemanticRetainedShutdownDebt)

    var physicalSlotID: FilesystemObservationPhysicalSlotID {
        switch self {
        case .vacant(let physicalSlotID): physicalSlotID
        case .retained(let debt): debt.fingerprint.binding.physicalSlotID
        }
    }
}

struct FilesystemObservationSemanticShutdownDebtSnapshot: Equatable, Sendable {
    let slots: [FilesystemObservationSemanticShutdownSlotDebt]

    var isQuiescent: Bool {
        slots.allSatisfy { slot in
            if case .vacant = slot { return true }
            return false
        }
    }
}

/// Actor-isolated bounded replay for contribution-bearing filesystem leases.
///
/// This value owns no synchronization or source semantics. Its caller must keep
/// it actor-isolated. Generic retry and consumer rebind may change drain tokens,
/// but the exact slot binding and ordered contribution identities remain stable.
struct FilesystemObservationSemanticReplay: Sendable {
    private struct RetainedSemanticLease: Sendable {
        let fingerprint: FilesystemObservationSemanticLeaseFingerprint
        var currentAttemptIdentity: FilesystemObservationSemanticAttemptIdentity
        var acceptedPrefix: [FilesystemObservationSemanticAcceptedDisposition]
    }

    private enum Shell: Sendable {
        case vacant
        case retained(RetainedSemanticLease)
    }

    private let maximumContributionsPerLease: Int
    private let maximumRetainedIdentityCapacity: Int
    private let physicalSlotIDsInDeclarationOrder: [FilesystemObservationPhysicalSlotID]
    private var shellsByPhysicalSlotID: [FilesystemObservationPhysicalSlotID: Shell]
    private var retainedIdentityCount = 0
    private var retainedIdentityHighWater = 0

    init(
        physicalSlotIDs: [FilesystemObservationPhysicalSlotID],
        maximumContributionsPerLease: Int
    ) throws {
        guard maximumContributionsPerLease > 0 else {
            throw FilesystemSemanticReplayConfigurationError
                .invalidMaximumContributionsPerLease
        }
        let declaredPhysicalSlotIDs = Set(physicalSlotIDs)
        guard declaredPhysicalSlotIDs.count == physicalSlotIDs.count else {
            throw FilesystemSemanticReplayConfigurationError.duplicatePhysicalSlotID
        }
        let (capacity, overflow) = physicalSlotIDs.count.multipliedReportingOverflow(
            by: maximumContributionsPerLease
        )
        guard !overflow else {
            throw FilesystemSemanticReplayConfigurationError
                .retainedIdentityCapacityOverflow
        }
        self.maximumContributionsPerLease = maximumContributionsPerLease
        maximumRetainedIdentityCapacity = capacity
        physicalSlotIDsInDeclarationOrder = physicalSlotIDs
        shellsByPhysicalSlotID = Dictionary(
            uniqueKeysWithValues: physicalSlotIDs.map { ($0, Shell.vacant) }
        )
    }

    mutating func present(
        _ lease: FilesystemObservationDrainLease
    ) -> FilesystemObservationSemanticPresentationResult {
        let orderedContributionIdentities: [FilesystemObservationContributionIdentity]
        switch contributionPayload(in: lease.payload) {
        case .contributions(let identities):
            orderedContributionIdentities = identities
        case .recoveryOnly:
            return .recoveryOnly
        }
        guard shellsByPhysicalSlotID[lease.binding.physicalSlotID] != nil else {
            return .undeclaredPhysicalSlot
        }
        guard orderedContributionIdentities.count <= maximumContributionsPerLease else {
            return .leaseTooLarge(
                maximum: maximumContributionsPerLease,
                presented: orderedContributionIdentities.count
            )
        }
        guard orderedContributionIdentities.allSatisfy({ $0.binding == lease.binding }) else {
            return .contributionBindingMismatch
        }

        let fingerprint = FilesystemObservationSemanticLeaseFingerprint(
            binding: lease.binding,
            orderedContributionIdentities: orderedContributionIdentities
        )
        let attempt = FilesystemObservationSemanticReplayAttempt(
            identity: FilesystemObservationSemanticAttemptIdentity(value: UUIDv7.generate()),
            fingerprint: fingerprint
        )
        let physicalSlotID = lease.binding.physicalSlotID
        guard let shell = shellsByPhysicalSlotID[physicalSlotID] else {
            preconditionFailure("Declared semantic replay slot disappeared")
        }
        switch shell {
        case .vacant:
            shellsByPhysicalSlotID[physicalSlotID] = .retained(
                RetainedSemanticLease(
                    fingerprint: fingerprint,
                    currentAttemptIdentity: attempt.identity,
                    acceptedPrefix: []
                )
            )
            retainedIdentityCount += orderedContributionIdentities.count
            retainedIdentityHighWater = max(retainedIdentityHighWater, retainedIdentityCount)
            precondition(retainedIdentityCount <= maximumRetainedIdentityCapacity)
            return .began(attempt)
        case .retained(var retained):
            guard retained.fingerprint == fingerprint else {
                return .bindingOrIdentityVectorMismatch(
                    retained: retained.fingerprint,
                    presented: fingerprint
                )
            }
            retained.currentAttemptIdentity = attempt.identity
            shellsByPhysicalSlotID[physicalSlotID] = .retained(retained)
            return .resumed(attempt, acceptedPrefix: retained.acceptedPrefix)
        }
    }

    func decision(
        for contributionIdentity: FilesystemObservationContributionIdentity,
        at index: Int,
        attempt: FilesystemObservationSemanticReplayAttempt
    ) -> FilesystemObservationSemanticDecision {
        switch retainedLease(for: attempt) {
        case .undeclaredPhysicalSlot:
            return .undeclaredPhysicalSlot
        case .vacant:
            return .fingerprintMismatch
        case .retained(let retained):
            guard retained.fingerprint == attempt.fingerprint else {
                return .fingerprintMismatch
            }
            guard retained.currentAttemptIdentity == attempt.identity else {
                return .staleConsumerAttempt
            }
            let identities = retained.fingerprint.orderedContributionIdentities
            guard identities.indices.contains(index), identities[index] == contributionIdentity else {
                return .identityOrIndexMismatch
            }
            if index < retained.acceptedPrefix.count {
                return .alreadyAccepted(
                    retained.acceptedPrefix[index],
                    index: index,
                    identity: contributionIdentity
                )
            }
            guard index == retained.acceptedPrefix.count else {
                return .outOfOrder(
                    expectedIndex: retained.acceptedPrefix.count,
                    presentedIndex: index
                )
            }
            return .requiresAcceptance(index: index, identity: contributionIdentity)
        }
    }

    mutating func recordAccepted(
        _ disposition: FilesystemObservationSemanticAcceptedDisposition,
        for contributionIdentity: FilesystemObservationContributionIdentity,
        at index: Int,
        attempt: FilesystemObservationSemanticReplayAttempt
    ) -> FilesystemObservationSemanticRecordResult {
        let physicalSlotID = attempt.fingerprint.binding.physicalSlotID
        guard let shell = shellsByPhysicalSlotID[physicalSlotID] else {
            return .undeclaredPhysicalSlot
        }
        guard case .retained(var retained) = shell else {
            return .fingerprintMismatch
        }
        guard retained.fingerprint == attempt.fingerprint else {
            return .fingerprintMismatch
        }
        guard retained.currentAttemptIdentity == attempt.identity else {
            return .staleConsumerAttempt
        }
        let identities = retained.fingerprint.orderedContributionIdentities
        guard identities.indices.contains(index), identities[index] == contributionIdentity else {
            return .identityOrIndexMismatch
        }
        if index < retained.acceptedPrefix.count {
            return .alreadyAccepted(retained.acceptedPrefix[index])
        }
        guard index == retained.acceptedPrefix.count else {
            return .outOfOrder(
                expectedIndex: retained.acceptedPrefix.count,
                presentedIndex: index
            )
        }
        retained.acceptedPrefix.append(disposition)
        shellsByPhysicalSlotID[physicalSlotID] = .retained(retained)
        return .recorded(
            acceptedCount: retained.acceptedPrefix.count,
            remainingCount: identities.count - retained.acceptedPrefix.count
        )
    }

    func semanticCompletion(
        for attempt: FilesystemObservationSemanticReplayAttempt
    ) -> FilesystemObservationSemanticCompletionResult {
        switch retainedLease(for: attempt) {
        case .undeclaredPhysicalSlot:
            return .undeclaredPhysicalSlot
        case .vacant:
            return .fingerprintMismatch
        case .retained(let retained):
            guard retained.fingerprint == attempt.fingerprint else {
                return .fingerprintMismatch
            }
            guard retained.currentAttemptIdentity == attempt.identity else {
                return .staleConsumerAttempt
            }
            let requiredCount = retained.fingerprint.orderedContributionIdentities.count
            guard retained.acceptedPrefix.count == requiredCount else {
                return .incomplete(
                    acceptedCount: retained.acceptedPrefix.count,
                    requiredCount: requiredCount
                )
            }
            return .wholeLeaseSemanticallyAccepted(
                FilesystemSemanticLeaseAcceptanceAuthority(
                    attemptIdentity: attempt.identity,
                    fingerprint: attempt.fingerprint,
                    acceptedDispositions: retained.acceptedPrefix
                )
            )
        }
    }

    var diagnostics: FilesystemObservationSemanticReplayDiagnostics {
        var retainedLeaseCount = 0
        for shell in shellsByPhysicalSlotID.values {
            if case .retained = shell {
                retainedLeaseCount += 1
            }
        }
        return FilesystemObservationSemanticReplayDiagnostics(
            declaredPhysicalSlotCount: shellsByPhysicalSlotID.count,
            retainedLeaseCount: retainedLeaseCount,
            retainedIdentityCount: retainedIdentityCount,
            retainedIdentityHighWater: retainedIdentityHighWater,
            maximumRetainedIdentityCapacity: maximumRetainedIdentityCapacity
        )
    }

    var shutdownDebtSnapshot: FilesystemObservationSemanticShutdownDebtSnapshot {
        FilesystemObservationSemanticShutdownDebtSnapshot(
            slots: physicalSlotIDsInDeclarationOrder.map { physicalSlotID in
                guard let shell = shellsByPhysicalSlotID[physicalSlotID] else {
                    preconditionFailure("Declared semantic replay slot disappeared")
                }
                switch shell {
                case .vacant:
                    return .vacant(physicalSlotID)
                case .retained(let retained):
                    return .retained(
                        FilesystemObservationSemanticRetainedShutdownDebt(
                            fingerprint: retained.fingerprint,
                            currentAttemptIdentity: retained.currentAttemptIdentity,
                            acceptedPrefix: retained.acceptedPrefix
                        )
                    )
                }
            }
        )
    }

    /// H2's transfer coordinator is the only intended caller. Exact whole-lease
    /// authority plus the mailbox-minted post-ACK receipt are required so semantic
    /// completion alone cannot prematurely clear retained replay.
    mutating func completeTransferredLease(
        authority wholeLeaseAuthority: FilesystemObservationWholeLeaseTransferAuthority,
        acknowledgement: FilesystemLeaseAcknowledgementReceipt
    ) -> FilesystemSemanticTransferCompletionResult {
        guard acknowledgement.matches(wholeLeaseAuthority) else {
            return .acknowledgementMismatch
        }
        let semanticAuthority: FilesystemSemanticLeaseAcceptanceAuthority
        switch wholeLeaseAuthority.evidence {
        case .contributions(let authority),
            .contributionsWithRecovery(let authority, _):
            semanticAuthority = authority
        case .recovery:
            return .authorityHasNoSemanticCustody
        }
        let physicalSlotID = semanticAuthority.fingerprint.binding.physicalSlotID
        guard let shell = shellsByPhysicalSlotID[physicalSlotID] else {
            return .undeclaredPhysicalSlot
        }
        guard case .retained(let retained) = shell else {
            return .fingerprintMismatch
        }
        guard retained.fingerprint == semanticAuthority.fingerprint else {
            return .fingerprintMismatch
        }
        guard retained.currentAttemptIdentity == semanticAuthority.attemptIdentity else {
            return .staleConsumerAttempt
        }
        guard
            retained.acceptedPrefix.count
                == retained.fingerprint.orderedContributionIdentities.count
        else {
            return .notSemanticallyComplete
        }
        shellsByPhysicalSlotID[physicalSlotID] = .vacant
        retainedIdentityCount -= retained.fingerprint.orderedContributionIdentities.count
        return .cleared(
            FilesystemObservationSemanticTransferClearReceipt(
                authority: wholeLeaseAuthority,
                acknowledgement: acknowledgement,
                attemptIdentity: semanticAuthority.attemptIdentity
            )
        )
    }

    private enum RetainedLeaseLookup {
        case undeclaredPhysicalSlot
        case vacant
        case retained(RetainedSemanticLease)
    }

    private func retainedLease(
        for attempt: FilesystemObservationSemanticReplayAttempt
    ) -> RetainedLeaseLookup {
        guard let shell = shellsByPhysicalSlotID[attempt.fingerprint.binding.physicalSlotID]
        else {
            return .undeclaredPhysicalSlot
        }
        switch shell {
        case .vacant:
            return .vacant
        case .retained(let retained):
            return .retained(retained)
        }
    }

    private enum ContributionPayloadClassification {
        case contributions([FilesystemObservationContributionIdentity])
        case recoveryOnly
    }

    private func contributionPayload(
        in payload: FilesystemObservationDrainPayload
    ) -> ContributionPayloadClassification {
        switch payload {
        case .contributions(let contributions),
            .contributionsWithRecovery(let contributions, _):
            return .contributions(
                ([contributions.first] + contributions.remaining).map(\.identity)
            )
        case .recovery:
            return .recoveryOnly
        }
    }
}
