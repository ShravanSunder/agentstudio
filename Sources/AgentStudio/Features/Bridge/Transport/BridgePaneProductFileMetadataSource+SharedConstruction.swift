import Foundation

extension BridgePaneProductFileMetadataSource {
    func currentSource() -> BridgeProductFileSourceCurrentResult {
        .available(
            BridgeProductFileSourceSpec(
                currentAuthorityRepoId: authority.worktree.repoId,
                currentAuthorityRootPathToken: authority.worktree.stableKey,
                currentAuthorityWorktreeId: authority.worktree.id
            )
        )
    }

    func cancel(subscriptionId: String) async {
        guard let context = contextBySubscriptionId.removeValue(forKey: subscriptionId),
            let constructionLease = context.constructionLease
        else { return }
        await sharedConstructionBinder.release(constructionLease)
    }

    func diagnosticSnapshot() async -> BridgeFileMetadataSourceDiagnostics {
        let contexts = Array(contextBySubscriptionId.values)
        var manifestRowCount = 0
        for context in contexts {
            manifestRowCount += await context.manifestIndex.count
        }
        return BridgeFileMetadataSourceDiagnostics(
            descriptorCount: contexts.reduce(0) { $0 + $1.descriptorByPath.count },
            inFlightDescriptorCount: contexts.reduce(0) {
                $0 + $1.inFlightDescriptorInterestRevisionByPath.count
            },
            manifestRowCount: manifestRowCount,
            subscriptionCount: contexts.count
        )
    }

    func attachConstructionLease(
        _ constructionLease: BridgeSharedFileSnapshotConsumerLease,
        subscriptionId: String,
        productSource: BridgeProductFileSourceIdentity,
        productAdmission: BridgeProductAdmissionContext,
        foregroundWorkAdmission: BridgePaneRefreshWorkAdmission
    ) -> Bool {
        foregroundWorkAdmission.withValidAdmission {
            productAdmission.withValidAdmission {
                guard var context = contextBySubscriptionId[subscriptionId],
                    context.productSource == productSource,
                    context.productAdmission.matches(productAdmission)
                else { return false }
                context.constructionLease = constructionLease
                contextBySubscriptionId[subscriptionId] = context
                return true
            } ?? false
        } ?? false
    }

    func applyPreparation(
        _ preparation: BridgeSharedFileSnapshotPreparation,
        subscriptionId: String,
        productSource: BridgeProductFileSourceIdentity,
        productAdmission: BridgeProductAdmissionContext,
        foregroundWorkAdmission: BridgePaneRefreshWorkAdmission
    ) -> SubscriptionContext? {
        var preparedContext: SubscriptionContext?
        let didPrepare =
            foregroundWorkAdmission.withValidAdmission {
                productAdmission.withValidAdmission { () -> Bool in
                    guard var context = contextBySubscriptionId[subscriptionId],
                        context.productSource == productSource,
                        context.productAdmission.matches(productAdmission)
                    else { return false }
                    context.openedSource = context.openedSource.withIgnorePolicy(
                        preparation.ignorePolicy
                    )
                    contextBySubscriptionId[subscriptionId] = context
                    preparedContext = context
                    return true
                } ?? false
            }
        return didPrepare == true ? preparedContext : nil
    }

    func releaseContext(
        subscriptionId: String,
        expectedSource: BridgeProductFileSourceIdentity
    ) async {
        guard let context = contextBySubscriptionId[subscriptionId],
            context.productSource == expectedSource
        else { return }
        contextBySubscriptionId.removeValue(forKey: subscriptionId)
        if let constructionLease = context.constructionLease {
            await sharedConstructionBinder.release(constructionLease)
        }
    }

    func isCurrent(
        subscriptionId: String,
        source: BridgeProductFileSourceIdentity,
        productAdmission: BridgeProductAdmissionContext
    ) -> Bool {
        guard let context = contextBySubscriptionId[subscriptionId] else { return false }
        return context.productSource == source
            && context.productAdmission.matches(productAdmission)
    }

    func publishCurrentStatus(
        _ statusResult: GitWorkingTreeStatusResult,
        emit: BridgePaneProductFileMetadataEventSink,
        productAdmission: BridgeProductAdmissionContext,
        productSource: BridgeProductFileSourceIdentity,
        foregroundWorkAdmission: BridgePaneRefreshWorkAdmission
    ) async throws {
        switch statusResult {
        case .available(let status):
            guard foregroundWorkAdmission.withValidAdmission({ true }) == true,
                (productAdmission.withValidAdmission { true }) == true
            else { return }
            try await emit(
                BridgePaneProductFileMetadataEncoding.statusEvent(
                    status,
                    source: productSource
                )
            )
        case .unavailable:
            guard foregroundWorkAdmission.withValidAdmission({ true }) == true,
                (productAdmission.withValidAdmission { true }) == true
            else { return }
            try await emit(
                .statusPatch(.init(patch: .invalidated, source: productSource))
            )
        }
    }
}
