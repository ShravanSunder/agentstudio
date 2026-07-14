enum FilesystemObservationMailboxProjection {
    static func desiredShutdownReference(
        _ desiredRegistration: FilesystemObservationDesiredRegistration
    ) -> FilesystemObservationDesiredShutdownReference {
        FilesystemObservationDesiredShutdownReference(
            sourceID: desiredRegistration.sourceID,
            registration: desiredRegistration.registration,
            desiredIdentity: desiredRegistration.identity,
            acceptedTopologyRevision: desiredRegistration.acceptedTopologyRevision
        )
    }

    static func nativeShutdownReference(
        _ startingNativeLifetime: FilesystemObservationStartingNativeLifetime
    ) -> FilesystemObservationNativeShutdownReference {
        FilesystemObservationNativeShutdownReference(
            binding: startingNativeLifetime.binding,
            nativeGenerationIdentity: startingNativeLifetime.nativeGenerationIdentity
        )
    }

    static func nativeRetirementShutdownReference(
        _ lifetime: FilesystemRetiredContextReleaseLifetime
    ) -> FilesystemObservationNativeRetirementShutdownReference {
        let disposition: FilesystemObservationNativeRetirementShutdownDisposition
        switch lifetime {
        case .fenceBacked(let fenceBacked):
            disposition = .fenceBacked(
                fenceIdentity: fenceBacked.receipt.fenceIdentity,
                disposition: fenceBacked.receipt.disposition,
                retirementAuthority: fenceBacked.receipt.retirementAuthority
            )
        case .unpublished(let unpublished):
            disposition = .unpublished(
                retirementAuthority: unpublished.receipt.retirementAuthority,
                finalizationKind: unpublished.receipt.completion.finalizationKind
            )
        }
        return FilesystemObservationNativeRetirementShutdownReference(
            native: nativeShutdownReference(lifetime.startingNativeLifetime),
            disposition: disposition
        )
    }

    static func completedReleaseShutdownReplay(
        _ release: FilesystemObservationLastCompletedRelease
    ) -> FilesystemObservationCompletedReleaseShutdownReplay {
        switch release {
        case .none:
            return .vacant
        case .completed(let acknowledgement):
            let retirement: FilesystemObservationNativeRetirementShutdownReference
            switch acknowledgement {
            case .fenceBacked(let fenceBacked):
                retirement = FilesystemObservationNativeRetirementShutdownReference(
                    native: nativeShutdownReference(
                        fenceBacked.finalization.startingNativeLifetime
                    ),
                    disposition: .fenceBacked(
                        fenceIdentity: fenceBacked.receipt.fenceIdentity,
                        disposition: fenceBacked.receipt.disposition,
                        retirementAuthority: fenceBacked.receipt.retirementAuthority
                    )
                )
            case .unpublished(let unpublished):
                let startingNativeLifetime: FilesystemObservationStartingNativeLifetime
                switch unpublished {
                case .releasedRetainedContext(_, let finalization, _):
                    startingNativeLifetime = finalization.startingNativeLifetime
                case .neverMaterialized(_, let finalization, _):
                    startingNativeLifetime = finalization.startingNativeLifetime
                }
                retirement = FilesystemObservationNativeRetirementShutdownReference(
                    native: nativeShutdownReference(startingNativeLifetime),
                    disposition: .unpublished(
                        retirementAuthority: unpublished.receipt.retirementAuthority,
                        finalizationKind: unpublished.receipt.completion.finalizationKind
                    )
                )
            }
            return .completed(
                retirement: retirement,
                releaseAuthority: acknowledgement.releaseAuthority
            )
        }
    }

    static func pendingDesiredShutdownCustody(
        _ record: FilesystemObservationPendingConfigurationRecord
    ) -> FilesystemObservationPendingDesiredShutdownCustody {
        FilesystemObservationPendingDesiredShutdownCustody(
            desired: desiredShutdownReference(record.desiredRegistration),
            continuityRepair: continuityRepairShutdownCustody(
                record.continuityRepairCustody
            )
        )
    }

    static func continuityRepairShutdownCustody(
        _ custody: FilesystemContinuityRepairCustodyState
    ) -> FilesystemObservationContinuityRepairShutdownCustody {
        switch custody {
        case .absent:
            return .absent
        case .pending(let authority):
            return .pending(pendingContinuityRepairShutdownReference(authority))
        case .handoffInFlight(let handoff):
            return .handoffInFlight(
                continuityRepairHandoffStateShutdownReference(handoff)
            )
        case .acknowledged(let acknowledgement, let successor):
            return .acknowledged(
                continuityRepairAcknowledgementShutdownReference(acknowledgement),
                successor: continuityRepairAcknowledgedSuccessorShutdownReference(successor)
            )
        }
    }

    private static func pendingContinuityRepairShutdownReference(
        _ authority: FilesystemPendingContinuityRepairAuthority
    ) -> FilesystemObservationPendingContinuityRepairShutdownReference {
        FilesystemObservationPendingContinuityRepairShutdownReference(
            identity: authority.identity,
            registration: authority.desiredConfiguration.registration,
            desiredIdentity: authority.desiredIdentity,
            acceptedTopologyRevision: authority.acceptedTopologyRevision,
            cause: authority.cause,
            recoveryRevision: authority.recoveryRevision,
            requiredParticipantKinds: authority.requiredParticipantKinds
        )
    }

    private static func continuityRepairHandoffShutdownReference(
        _ authority: FilesystemContinuityRepairHandoffAuthority
    ) -> FilesystemObservationContinuityRepairHandoffShutdownReference {
        FilesystemObservationContinuityRepairHandoffShutdownReference(
            acceptingBinding: authority.acceptingBinding,
            handoffIdentity: authority.handoffIdentity,
            desiredIdentity: authority.desiredIdentity,
            acceptedTopologyRevision: authority.acceptedTopologyRevision
        )
    }

    private static func sourceRemovalShutdownReference(
        _ authority: FilesystemSourceRemovalAuthority
    ) -> FilesystemObservationSourceRemovalShutdownReference {
        FilesystemObservationSourceRemovalShutdownReference(
            identity: authority.identity,
            exactPriorBinding: authority.exactPriorBinding,
            acceptedTopologyRevision: authority.acceptedTopologyRevision
        )
    }

    private static func continuityRepairSuccessorShutdownReference(
        _ successor: FilesystemContinuityRepairSuccessorDisposition
    ) -> FilesystemObservationContinuityRepairSuccessorShutdownReference {
        switch successor {
        case .sameDesired:
            return .sameDesired
        case .superseded(let authority):
            return .superseded(pendingContinuityRepairShutdownReference(authority))
        case .removed(let authority):
            return .removed(sourceRemovalShutdownReference(authority))
        }
    }

    private static func continuityRepairHandoffStateShutdownReference(
        _ handoff: FilesystemContinuityRepairHandoff
    ) -> FilesystemObservationContinuityRepairHandoffStateShutdownReference {
        FilesystemObservationContinuityRepairHandoffStateShutdownReference(
            pending: pendingContinuityRepairShutdownReference(handoff.pendingAuthority),
            authority: continuityRepairHandoffShutdownReference(handoff.authority),
            successor: continuityRepairSuccessorShutdownReference(
                handoff.successorDisposition
            )
        )
    }

    private static func continuityRepairAcceptanceShutdownReference(
        _ acceptance: FilesystemSourceGateContinuityRepairAcceptance
    ) -> FilesystemObservationContinuityRepairAcceptanceShutdownReference {
        FilesystemObservationContinuityRepairAcceptanceShutdownReference(
            authority: continuityRepairHandoffShutdownReference(acceptance.authority),
            repairGenerationID: acceptance.repairGeneration.id
        )
    }

    private static func continuityRepairAcknowledgementShutdownReference(
        _ acknowledgement: FilesystemContinuityRepairHandoffAcknowledgement
    ) -> FilesystemObservationContinuityRepairAcknowledgementShutdownReference {
        switch acknowledgement {
        case .sameDesired(let handoff, let acceptance):
            return .sameDesired(
                handoff: continuityRepairHandoffStateShutdownReference(handoff),
                acceptance: continuityRepairAcceptanceShutdownReference(acceptance)
            )
        case .superseded(let handoff, let acceptance, let successorAuthority):
            return .superseded(
                handoff: continuityRepairHandoffStateShutdownReference(handoff),
                acceptance: continuityRepairAcceptanceShutdownReference(acceptance),
                successor: pendingContinuityRepairShutdownReference(successorAuthority)
            )
        case .removed(let handoff, let acceptance, let removalAuthority):
            return .removed(
                handoff: continuityRepairHandoffStateShutdownReference(handoff),
                acceptance: continuityRepairAcceptanceShutdownReference(acceptance),
                removal: sourceRemovalShutdownReference(removalAuthority)
            )
        }
    }

    private static func continuityRepairAcknowledgedSuccessorShutdownReference(
        _ successor: FilesystemContinuityRepairAcknowledgedSuccessor
    ) -> FilesystemObservationContinuityRepairAcknowledgedSuccessorShutdownReference {
        switch successor {
        case .noSuccessor:
            return .noSuccessor
        case .pending(let authority):
            return .pending(pendingContinuityRepairShutdownReference(authority))
        }
    }

    static func postStartShutdownDisposition(
        _ disposition: FilesystemObservationPostStartDisposition
    ) -> FilesystemObservationPostStartShutdownDisposition {
        switch disposition {
        case .current:
            .current
        case .closePredecessor(let predecessor):
            .closePredecessor(predecessor.binding)
        case .closePublished(let published):
            .closePublished(published.binding)
        case .closePredecessorAndPublished(let predecessor, let published):
            .closePredecessorAndPublished(
                predecessor: predecessor.binding,
                published: published.binding
            )
        }
    }

    static func recoveryStampsByPhysicalSlotID(
        _ seed: FilesystemObservationRecoveryAuthoritySeed,
        physicalSlotIDs: [FilesystemObservationPhysicalSlotID]
    ) -> [FilesystemObservationPhysicalSlotID: GatherRecoveryStamp] {
        switch seed {
        case .initial:
            [:]
        case .preseededSequenced(let sequence):
            Dictionary(
                uniqueKeysWithValues: physicalSlotIDs.map {
                    ($0, GatherRecoveryStamp.sequenced(sequence))
                }
            )
        }
    }

    static func mapRejectedAcknowledgement(
        _ acknowledgement: AdmissionDrainAcknowledgement
    ) -> FilesystemObservationDrainAcknowledgement {
        switch acknowledgement {
        case .invalidToken, .staleGeneration:
            .invalidToken
        case .closed:
            .closed
        case .accepted:
            preconditionFailure("Accepted acknowledgement must be mapped by its caller")
        }
    }

    static func contributionsPayload(
        from payload: GatherDrainPayload<
            FilesystemObservationPhysicalSlotID,
            FilesystemObservationMailboxContribution
        >
    ) -> FilesystemObservationDrainPayload {
        guard case .contributions(let contributions) = payload else {
            preconditionFailure("Authoritative filesystem lease changed payload kind during rebind")
        }
        return .contributions(contributionsPayloads(from: contributions))
    }

    static func recoveryPayload(
        from payload: GatherDrainPayload<
            FilesystemObservationPhysicalSlotID,
            FilesystemObservationMailboxContribution
        >,
        evidence: FixedFilesystemRecoveryEvidenceSnapshot
    ) -> FilesystemObservationDrainPayload {
        switch payload {
        case .contributionsWithRecovery(let contributions, _):
            .contributionsWithRecovery(contributionsPayloads(from: contributions), evidence)
        case .recovery:
            .recovery(evidence)
        case .contributions:
            preconditionFailure("Recovery filesystem lease changed payload kind during rebind")
        }
    }

    static func contributionsPayloads(
        from contributions: NonEmptyAdmissionBatch<
            GatherContribution<
                FilesystemObservationPhysicalSlotID,
                FilesystemObservationMailboxContribution
            >
        >
    ) -> NonEmptyAdmissionBatch<FilesystemObservationMailboxContribution> {
        NonEmptyAdmissionBatch(
            first: contributions.first.payload,
            remaining: contributions.remaining.map(\.payload)
        )
    }

}
