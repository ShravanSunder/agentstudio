enum ContentRepairStructuralValidation: Equatable, Sendable {
    case valid
    case rejected(FilesystemContentRepairProjectionRejection)
}

enum ContentRepairRegistryValidation: Equatable, Sendable {
    case eligible
    case rejected(FilesystemContentRepairProjectionRejection)
    case shuttingDown
}

enum FilesystemContentRepairProjectorValidation {
    static func structuralValidation(
        _ request: FilesystemContentRepairProjectionRequest,
        participant: FilesystemRepairParticipantToken
    ) -> ContentRepairStructuralValidation {
        let acceptedRepair = request.acceptance.repairGeneration
        let bound = request.activatedGeneration.boundGeneration
        guard acceptedRepair.id.registration.sourceID.kind == .registeredWorktreeContent else {
            return .rejected(.sourceKindNotSupported(acceptedRepair.id.registration.sourceID))
        }
        guard acceptedRepair == bound.repairGeneration else {
            return .rejected(.acceptanceMismatch)
        }

        let actualProjectors = Set(
            acceptedRepair.participants.filter { $0.kind == .contentRepairProjector }
        )
        guard actualProjectors == [participant] else {
            return .rejected(
                .projectorParticipantMismatch(
                    expected: participant,
                    actual: actualProjectors
                )
            )
        }
        let expectedConsumers = Set(
            acceptedRepair.participants.filter { $0.kind == .contentConsumer }
        )
        let actualConsumers = Set(bound.deliveryRequests.map(\.consumer.sourceGateParticipant))
        guard expectedConsumers == actualConsumers else {
            return .rejected(
                .contentParticipantMismatch(
                    expected: expectedConsumers,
                    actual: actualConsumers
                )
            )
        }

        var consumerIdentities: Set<ContentRepairConsumerIdentity> = []
        var retryTokens: Set<ContentRepairRetryToken> = []
        let expectedInvalidationGeneration = bound.deliveryRequests.first?.invalidationGeneration
        for deliveryRequest in bound.deliveryRequests {
            guard deliveryRequest.repairGeneration == acceptedRepair else {
                return .rejected(.requestRepairGenerationMismatch(deliveryRequest.consumer))
            }
            guard deliveryRequest.consumer.sourceID == acceptedRepair.id.registration.sourceID else {
                return .rejected(.requestConsumerSourceMismatch(deliveryRequest.consumer))
            }
            if let expectedInvalidationGeneration,
                deliveryRequest.invalidationGeneration != expectedInvalidationGeneration
            {
                return .rejected(
                    .requestInvalidationGenerationMismatch(deliveryRequest.consumer)
                )
            }
            guard deliveryRequest.retryToken.repairGenerationID == acceptedRepair.id,
                deliveryRequest.retryToken.consumer == deliveryRequest.consumer
            else {
                return .rejected(.retryTokenMismatch(deliveryRequest.consumer))
            }
            guard consumerIdentities.insert(deliveryRequest.consumer.identity).inserted else {
                return .rejected(.duplicateConsumerIdentity(deliveryRequest.consumer))
            }
            guard retryTokens.insert(deliveryRequest.retryToken).inserted else {
                return .rejected(.duplicateRetryIdentity(deliveryRequest.retryToken))
            }
        }
        let sorted = bound.deliveryRequests.sorted { left, right in
            if left.consumer.registrationOrdinal != right.consumer.registrationOrdinal {
                return left.consumer.registrationOrdinal < right.consumer.registrationOrdinal
            }
            return left.consumer.generation < right.consumer.generation
        }
        return sorted == bound.deliveryRequests
            ? .valid
            : .rejected(.requestOrderMismatch)
    }

    static func registryValidation(
        _ eligibility: ContentRepairProjectionEligibilityResult,
        expected: ContentRepairActivatedGeneration
    ) -> ContentRepairRegistryValidation {
        switch eligibility {
        case .eligible(let eligible):
            let validatedGeneration: ContentRepairActivatedGeneration
            switch eligible {
            case .currentActive(let generation), .retainedCompleted(let generation):
                validatedGeneration = generation
            }
            return validatedGeneration == expected
                ? .eligible
                : .rejected(
                    .registryEligibilityMismatch(
                        expected.boundGeneration.repairGeneration.id
                    )
                )
        case .ineligible(let reason):
            return .rejected(.registryIneligible(reason))
        case .shuttingDown:
            return .shuttingDown
        }
    }
}
