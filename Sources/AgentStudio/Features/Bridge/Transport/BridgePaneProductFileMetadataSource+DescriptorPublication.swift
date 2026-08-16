import Foundation

extension BridgePaneProductFileMetadataSource {
    struct DescriptorInterestCommit: Sendable {
        let committedPayload: BridgeProductFileDescriptorReadyPayload
        let committedRevision: Int
        let previousPayload: BridgeProductFileDescriptorReadyPayload?
        let previousRevision: Int?
    }

    func commitDescriptorInterest(
        _ materialized: BridgePaneProductFileDescriptorMaterialization,
        for row: BridgeWorktreeTreeRowMetadata,
        request: DescriptorReconciliationRequest
    ) -> DescriptorInterestCommit? {
        let subscription = request.subscription
        return request.foregroundWorkAdmission.withValidAdmission({
            request.productAdmission.withValidAdmission {
                guard var currentContext = contextBySubscriptionId[subscription.subscriptionId],
                    currentContext.productSource == request.productSource,
                    currentContext.productAdmission.matches(request.productAdmission),
                    currentContext.subscription.interestRevision == subscription.interestRevision,
                    currentContext.inFlightDescriptorInterestRevisionByPath[row.path]
                        == subscription.interestRevision
                else { return nil }
                let commit = DescriptorInterestCommit(
                    committedPayload: materialized.payload,
                    committedRevision: subscription.interestRevision,
                    previousPayload: currentContext.descriptorByPath[row.path],
                    previousRevision: currentContext.descriptorInterestRevisionByPath[row.path]
                )
                currentContext.inFlightDescriptorInterestRevisionByPath.removeValue(forKey: row.path)
                currentContext.descriptorInterestRevisionByPath[row.path] =
                    subscription.interestRevision
                currentContext.descriptorByPath[row.path] = materialized.payload
                contextBySubscriptionId[subscription.subscriptionId] = currentContext
                return commit
            }.flatMap { $0 }
        }).flatMap { $0 }
    }

    func descriptorInterestCommitIsCurrent(
        _ commit: DescriptorInterestCommit,
        for row: BridgeWorktreeTreeRowMetadata,
        request: DescriptorReconciliationRequest
    ) -> Bool {
        let subscription = request.subscription
        return request.foregroundWorkAdmission.withValidAdmission({
            request.productAdmission.withValidAdmission {
                guard let currentContext = contextBySubscriptionId[subscription.subscriptionId]
                else { return false }
                return currentContext.productSource == request.productSource
                    && currentContext.productAdmission.matches(request.productAdmission)
                    && currentContext.subscription.interestRevision == commit.committedRevision
                    && currentContext.descriptorInterestRevisionByPath[row.path]
                        == commit.committedRevision
                    && currentContext.descriptorByPath[row.path] == commit.committedPayload
            } ?? false
        }) == true
    }

    func rollbackDescriptorInterest(
        _ commit: DescriptorInterestCommit,
        for row: BridgeWorktreeTreeRowMetadata,
        request: DescriptorReconciliationRequest
    ) {
        let subscriptionId = request.subscription.subscriptionId
        guard var currentContext = contextBySubscriptionId[subscriptionId],
            currentContext.productSource == request.productSource,
            currentContext.productAdmission.matches(request.productAdmission),
            currentContext.descriptorInterestRevisionByPath[row.path]
                == commit.committedRevision,
            currentContext.descriptorByPath[row.path] == commit.committedPayload
        else { return }

        if currentContext.subscription.interestRevision == commit.committedRevision {
            currentContext.descriptorInterestRevisionByPath[row.path] = commit.previousRevision
            currentContext.descriptorByPath[row.path] = commit.previousPayload
        } else {
            currentContext.descriptorInterestRevisionByPath.removeValue(forKey: row.path)
            currentContext.descriptorByPath.removeValue(forKey: row.path)
        }
        contextBySubscriptionId[subscriptionId] = currentContext
    }
}
