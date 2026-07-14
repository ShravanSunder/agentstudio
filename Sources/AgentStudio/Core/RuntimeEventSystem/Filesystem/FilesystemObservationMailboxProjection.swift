enum FilesystemObservationMailboxProjection {
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
