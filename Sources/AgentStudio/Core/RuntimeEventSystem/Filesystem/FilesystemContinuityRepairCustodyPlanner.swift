enum FilesystemContinuityRepairCustodyPlanner {
    static func makePendingAuthority(
        identity: FilesystemPendingContinuityRepairIdentity,
        desiredRegistration: FilesystemObservationDesiredRegistration,
        cause: FilesystemPendingContinuityRepairCause,
        recoveryRevision: FilesystemContinuityRepairRevision
    ) -> FilesystemPendingContinuityRepairAuthority {
        FilesystemPendingContinuityRepairAuthority(
            identity: identity,
            desiredIdentity: desiredRegistration.identity,
            desiredConfiguration: desiredRegistration.configuration,
            acceptedTopologyRevision: desiredRegistration.acceptedTopologyRevision,
            cause: cause,
            recoveryRevision: recoveryRevision,
            requiredParticipantKinds: FilesystemRepairParticipantKind.requiredKinds(
                for: desiredRegistration.sourceID.kind,
                trigger: .continuityLoss
            )
        )
    }

    enum SupersessionRequirement: Equatable, Sendable {
        case preserve(FilesystemContinuityRepairCustodyState)
        case issuePendingAuthority(
            cause: FilesystemPendingContinuityRepairCause,
            recoveryRevision: FilesystemContinuityRepairRevision
        )
        case issueHandoffSuccessorAuthority(
            handoff: FilesystemContinuityRepairHandoff,
            cause: FilesystemPendingContinuityRepairCause,
            recoveryRevision: FilesystemContinuityRepairRevision
        )
    }

    enum SupersessionInput: Sendable {
        case preserve(FilesystemContinuityRepairCustodyState)
        case replacePending(FilesystemPendingContinuityRepairAuthority)
        case replaceHandoffSuccessor(
            handoff: FilesystemContinuityRepairHandoff,
            successorAuthority: FilesystemPendingContinuityRepairAuthority
        )
    }

    struct PendingRecordSupersessionInput: Sendable {
        let desiredRegistration: FilesystemObservationDesiredRegistration
        let supersession: SupersessionInput
    }

    enum RepairInventory: Sendable {
        case vacant
        case retained
    }

    enum AcceptingPublicationSnapshot: Sendable {
        case unavailable
        case accepting(FilesystemObservationPostStartPublication)
    }

    enum PendingCustodySnapshot: Sendable {
        case absent
        case retained(FilesystemContinuityRepairCustodyState)
    }

    enum PendingConfigurationRecordSnapshot: Sendable {
        case absent
        case retained(FilesystemObservationPendingConfigurationRecord)
    }

    struct HandoffPreparationInput: Sendable {
        let repairInventory: RepairInventory
        let acceptingPublication: AcceptingPublicationSnapshot
        let pendingCustody: PendingCustodySnapshot
        let acceptingNativeLifetime: FilesystemObservationAcceptingNativeLifetime
        let candidateHandoffIdentity: FilesystemContinuityRepairHandoffIdentity
    }

    enum HandoffPreparationPlan: Equatable, Sendable {
        case unchanged(FilesystemContinuityRepairHandoffPreparationResult)
        case install(FilesystemContinuityRepairHandoff)

        var result: FilesystemContinuityRepairHandoffPreparationResult {
            switch self {
            case .unchanged(let result):
                result
            case .install(let handoff):
                .prepared(handoff)
            }
        }
    }

    enum PendingRecordHandoffPreparationPlan: Equatable, Sendable {
        case unchanged(FilesystemContinuityRepairHandoffPreparationResult)
        case replace(
            record: FilesystemObservationPendingConfigurationRecord,
            result: FilesystemContinuityRepairHandoffPreparationResult
        )

        var result: FilesystemContinuityRepairHandoffPreparationResult {
            switch self {
            case .unchanged(let result), .replace(_, let result):
                result
            }
        }
    }

    enum AcceptanceBindingSnapshot: Sendable {
        case unavailable
        case declared
    }

    struct HandoffAcknowledgementInput: Sendable {
        let bindingSnapshot: AcceptanceBindingSnapshot
        let pendingCustody: PendingCustodySnapshot
        let acceptance: FilesystemSourceGateContinuityRepairAcceptance
    }

    enum HandoffAcknowledgementPlan: Equatable, Sendable {
        case unchanged(FilesystemRepairHandoffAcknowledgementResult)
        case retain(
            acknowledgement: FilesystemContinuityRepairHandoffAcknowledgement,
            successor: FilesystemContinuityRepairAcknowledgedSuccessor
        )

        var result: FilesystemRepairHandoffAcknowledgementResult {
            switch self {
            case .unchanged(let result):
                result
            case .retain(let acknowledgement, _):
                .acknowledged(acknowledgement)
            }
        }
    }

    enum PendingRecordHandoffAcknowledgementPlan: Equatable, Sendable {
        case unchanged(FilesystemRepairHandoffAcknowledgementResult)
        case replace(
            record: FilesystemObservationPendingConfigurationRecord,
            result: FilesystemRepairHandoffAcknowledgementResult
        )

        var result: FilesystemRepairHandoffAcknowledgementResult {
            switch self {
            case .unchanged(let result), .replace(_, let result):
                result
            }
        }
    }

    struct PendingRecordHandoffPreparationInput: Sendable {
        let repairInventory: RepairInventory
        let acceptingPublication: AcceptingPublicationSnapshot
        let pendingRecord: PendingConfigurationRecordSnapshot
        let acceptingNativeLifetime: FilesystemObservationAcceptingNativeLifetime
        let candidateHandoffIdentity: FilesystemContinuityRepairHandoffIdentity
    }

    struct PendingRecordHandoffAcknowledgementInput: Sendable {
        let bindingSnapshot: AcceptanceBindingSnapshot
        let pendingRecord: PendingConfigurationRecordSnapshot
        let acceptance: FilesystemSourceGateContinuityRepairAcceptance
    }

    enum PendingRemovalSnapshot: Sendable {
        case absent
        case retained(FilesystemObservationPendingConfigurationRecord)
    }

    enum PendingRemovalPlan: Equatable, Sendable {
        case unchanged(FilesystemRemovedPendingConfiguration)
        case removeRecord(
            FilesystemObservationPendingConfigurationRecord,
            disposition: FilesystemRemovedPendingConfiguration
        )
        case retainRecord(
            FilesystemObservationPendingConfigurationRecord,
            disposition: FilesystemRemovedPendingConfiguration
        )

        var disposition: FilesystemRemovedPendingConfiguration {
            switch self {
            case .unchanged(let disposition), .removeRecord(_, let disposition):
                disposition
            case .retainRecord(_, let disposition):
                disposition
            }
        }
    }

    static func supersessionRequirement(
        for retainedCustody: FilesystemContinuityRepairCustodyState
    ) -> SupersessionRequirement {
        switch retainedCustody {
        case .absent, .acknowledged(_, .noSuccessor):
            return .preserve(.absent)
        case .pending(let authority), .acknowledged(_, .pending(let authority)):
            return .issuePendingAuthority(
                cause: authority.cause,
                recoveryRevision: authority.recoveryRevision
            )
        case .handoffInFlight(let handoff):
            switch handoff.successorDisposition {
            case .sameDesired:
                return .issueHandoffSuccessorAuthority(
                    handoff: handoff,
                    cause: handoff.pendingAuthority.cause,
                    recoveryRevision: handoff.pendingAuthority.recoveryRevision
                )
            case .superseded(let authority):
                return .issueHandoffSuccessorAuthority(
                    handoff: handoff,
                    cause: authority.cause,
                    recoveryRevision: authority.recoveryRevision
                )
            case .removed:
                return .preserve(retainedCustody)
            }
        }
    }

    static func supersededCustody(
        _ input: SupersessionInput
    ) -> FilesystemContinuityRepairCustodyState {
        switch input {
        case .preserve(let retainedCustody):
            return retainedCustody
        case .replacePending(let successorAuthority):
            return .pending(successorAuthority)
        case .replaceHandoffSuccessor(let handoff, let successorAuthority):
            return .handoffInFlight(
                FilesystemContinuityRepairHandoff(
                    pendingAuthority: handoff.pendingAuthority,
                    authority: handoff.authority,
                    successorDisposition: .superseded(successorAuthority)
                )
            )
        }
    }

    static func supersededPendingRecord(
        _ input: PendingRecordSupersessionInput
    ) -> FilesystemObservationPendingConfigurationRecord {
        FilesystemObservationPendingConfigurationRecord(
            desiredRegistration: input.desiredRegistration,
            continuityRepairCustody: supersededCustody(input.supersession)
        )
    }

    static func prepareHandoff(
        _ input: HandoffPreparationInput
    ) -> HandoffPreparationPlan {
        guard case .retained = input.repairInventory else {
            return .unchanged(.absent)
        }
        guard case .accepting(let publication) = input.acceptingPublication else {
            return .unchanged(.bindingMismatch)
        }
        guard case .retained(let custody) = input.pendingCustody else {
            return .unchanged(.absent)
        }

        let pendingAuthority: FilesystemPendingContinuityRepairAuthority
        switch custody {
        case .absent, .acknowledged(_, .noSuccessor):
            return .unchanged(.absent)
        case .pending(let authority), .acknowledged(_, .pending(let authority)):
            pendingAuthority = authority
        case .handoffInFlight(let handoff):
            guard handoff.authority.acceptingBinding == input.acceptingNativeLifetime.binding else {
                return .unchanged(.bindingMismatch)
            }
            guard
                handoff.authority.desiredIdentity
                    == input.acceptingNativeLifetime.startingNativeLifetime.desiredRegistration.identity
            else {
                return .unchanged(.desiredIdentityMismatch)
            }
            return .unchanged(.replayed(handoff))
        }

        let desiredRegistration =
            input.acceptingNativeLifetime.startingNativeLifetime.desiredRegistration
        guard pendingAuthority.desiredIdentity == desiredRegistration.identity else {
            return .unchanged(.desiredIdentityMismatch)
        }
        guard publication.acceptingNativeLifetime == input.acceptingNativeLifetime else {
            return .unchanged(.bindingMismatch)
        }

        let handoff = FilesystemContinuityRepairHandoff(
            pendingAuthority: pendingAuthority,
            authority: FilesystemContinuityRepairHandoffAuthority(
                acceptingBinding: input.acceptingNativeLifetime.binding,
                handoffIdentity: input.candidateHandoffIdentity,
                desiredIdentity: pendingAuthority.desiredIdentity,
                acceptedTopologyRevision: pendingAuthority.acceptedTopologyRevision
            ),
            successorDisposition: .sameDesired
        )
        return .install(handoff)
    }

    static func prepareHandoffRecord(
        _ input: PendingRecordHandoffPreparationInput
    ) -> PendingRecordHandoffPreparationPlan {
        let pendingCustody: PendingCustodySnapshot
        switch input.pendingRecord {
        case .absent:
            pendingCustody = .absent
        case .retained(let pendingRecord):
            pendingCustody = .retained(pendingRecord.continuityRepairCustody)
        }
        let plan = prepareHandoff(
            HandoffPreparationInput(
                repairInventory: input.repairInventory,
                acceptingPublication: input.acceptingPublication,
                pendingCustody: pendingCustody,
                acceptingNativeLifetime: input.acceptingNativeLifetime,
                candidateHandoffIdentity: input.candidateHandoffIdentity
            )
        )
        guard case .install(let handoff) = plan else {
            return .unchanged(plan.result)
        }
        guard case .retained(let pendingRecord) = input.pendingRecord else {
            preconditionFailure("A handoff cannot install without exact pending custody")
        }
        return .replace(
            record: FilesystemObservationPendingConfigurationRecord(
                desiredRegistration: pendingRecord.desiredRegistration,
                continuityRepairCustody: .handoffInFlight(handoff)
            ),
            result: plan.result
        )
    }

    static func acknowledgeHandoff(
        _ input: HandoffAcknowledgementInput
    ) -> HandoffAcknowledgementPlan {
        guard case .declared = input.bindingSnapshot else {
            return .unchanged(.bindingMismatch)
        }
        guard case .retained(let custody) = input.pendingCustody else {
            return .unchanged(.absent)
        }

        switch custody {
        case .acknowledged(let retainedAcknowledgement, _):
            guard acceptance(from: retainedAcknowledgement) == input.acceptance else {
                return .unchanged(.staleAcceptance)
            }
            return .unchanged(.alreadyAcknowledged(retainedAcknowledgement))
        case .handoffInFlight(let handoff):
            guard handoff.authority.acceptingBinding == input.acceptance.authority.acceptingBinding
            else {
                return .unchanged(.bindingMismatch)
            }
            guard input.acceptance.matches(handoff.authority) else {
                return .unchanged(.staleAcceptance)
            }
            return acknowledgementPlan(handoff: handoff, acceptance: input.acceptance)
        case .absent, .pending:
            return .unchanged(.staleAcceptance)
        }
    }

    static func acknowledgeHandoffRecord(
        _ input: PendingRecordHandoffAcknowledgementInput
    ) -> PendingRecordHandoffAcknowledgementPlan {
        let pendingCustody: PendingCustodySnapshot
        switch input.pendingRecord {
        case .absent:
            pendingCustody = .absent
        case .retained(let pendingRecord):
            pendingCustody = .retained(pendingRecord.continuityRepairCustody)
        }
        let plan = acknowledgeHandoff(
            HandoffAcknowledgementInput(
                bindingSnapshot: input.bindingSnapshot,
                pendingCustody: pendingCustody,
                acceptance: input.acceptance
            )
        )
        guard case .retain(let acknowledgement, let successor) = plan else {
            return .unchanged(plan.result)
        }
        guard case .retained(let pendingRecord) = input.pendingRecord else {
            preconditionFailure("A handoff acknowledgement cannot retain without exact custody")
        }
        return .replace(
            record: FilesystemObservationPendingConfigurationRecord(
                desiredRegistration: pendingRecord.desiredRegistration,
                continuityRepairCustody: .acknowledged(
                    acknowledgement,
                    successor: successor
                )
            ),
            result: plan.result
        )
    }

    static func withdrawPendingRecordForRemoval(
        snapshot: PendingRemovalSnapshot,
        removalAuthority: FilesystemSourceRemovalAuthority
    ) -> PendingRemovalPlan {
        guard case .retained(let pendingRecord) = snapshot else {
            return .unchanged(.absent)
        }
        let disposition = FilesystemRemovedPendingConfiguration.withdrawn(
            pendingRecord.desiredRegistration
        )
        guard case .handoffInFlight(let handoff) = pendingRecord.continuityRepairCustody else {
            return .removeRecord(pendingRecord, disposition: disposition)
        }

        let retainedRecord = FilesystemObservationPendingConfigurationRecord(
            desiredRegistration: pendingRecord.desiredRegistration,
            continuityRepairCustody: .handoffInFlight(
                FilesystemContinuityRepairHandoff(
                    pendingAuthority: handoff.pendingAuthority,
                    authority: handoff.authority,
                    successorDisposition: .removed(removalAuthority)
                )
            )
        )
        return .retainRecord(retainedRecord, disposition: disposition)
    }

    private static func acceptance(
        from acknowledgement: FilesystemContinuityRepairHandoffAcknowledgement
    ) -> FilesystemSourceGateContinuityRepairAcceptance {
        switch acknowledgement {
        case .sameDesired(_, let acceptance),
            .superseded(_, let acceptance, _),
            .removed(_, let acceptance, _):
            acceptance
        }
    }

    private static func acknowledgementPlan(
        handoff: FilesystemContinuityRepairHandoff,
        acceptance: FilesystemSourceGateContinuityRepairAcceptance
    ) -> HandoffAcknowledgementPlan {
        switch handoff.successorDisposition {
        case .sameDesired:
            return .retain(
                acknowledgement: .sameDesired(handoff: handoff, acceptance: acceptance),
                successor: .noSuccessor
            )
        case .superseded(let successorAuthority):
            return .retain(
                acknowledgement: .superseded(
                    handoff: handoff,
                    acceptance: acceptance,
                    successorAuthority: successorAuthority
                ),
                successor: .pending(successorAuthority)
            )
        case .removed(let removalAuthority):
            return .retain(
                acknowledgement: .removed(
                    handoff: handoff,
                    acceptance: acceptance,
                    removalAuthority: removalAuthority
                ),
                successor: .noSuccessor
            )
        }
    }
}
