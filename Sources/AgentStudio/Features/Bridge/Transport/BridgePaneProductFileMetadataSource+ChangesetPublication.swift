import AgentStudioCore
import Foundation

extension BridgePaneProductFileMetadataSource {
    private struct ChangesetEmissionRequest: Sendable {
        let changedPaths: Set<String>
        let foregroundWorkAdmission: BridgePaneRefreshWorkAdmission
        let gitStatusResult: GitWorkingTreeStatusResult?
        let productAdmission: BridgeProductAdmissionContext
        let productSource: BridgeProductFileSourceIdentity
        let refreshed: BridgeWorktreeRefreshedTreeRows
        let removedRows: [BridgeWorktreeTreeRowMetadata]
        let subscriptionId: String
    }

    // WIP checkpoint: split per-subscription publication before the 1.4c cutover commit.
    // swiftlint:disable:next function_body_length
    func publish(
        changeset: FileChangeset,
        productAdmission: BridgeProductAdmissionContext,
        foregroundWorkAdmission: BridgePaneRefreshWorkAdmission
    ) async throws -> [BridgePaneProductFileMetadataEmission] {
        guard changeset.worktreeId == authority.worktree.id,
            changeset.repoId == authority.worktree.repoId,
            foregroundWorkAdmission.withValidAdmission({ true }) == true,
            (productAdmission.withValidAdmission { true }) == true
        else {
            return []
        }
        let gitStatusResult: GitWorkingTreeStatusResult? =
            if changeset.containsGitInternalChanges
                || changeset.suppressedGitInternalPathCount > 0
            {
                await statusProvider.statusResult(for: authority.worktree.path)
            } else {
                nil
            }
        guard foregroundWorkAdmission.withValidAdmission({ true }) == true,
            (productAdmission.withValidAdmission { true }) == true
        else { return [] }
        var emissions: [BridgePaneProductFileMetadataEmission] = []
        for subscriptionId in contextBySubscriptionId.keys.sorted() {
            guard let context = contextBySubscriptionId[subscriptionId],
                foregroundWorkAdmission.withValidAdmission({ true }) == true,
                context.productAdmission.matches(productAdmission)
            else { return [] }
            let productSource = context.productSource
            let changedPaths = Set(
                changeset.paths.filter {
                    BridgeWorktreeFileMaterializer.canMaterializeDemandPath(
                        $0,
                        openedSource: context.openedSource
                    )
                })
            let refreshed = await treeRowRefresher(
                authority.worktree.path,
                changedPaths,
                true
            )
            guard foregroundWorkAdmission.withValidAdmission({ true }) == true,
                let currentContext = contextBySubscriptionId[subscriptionId],
                currentContext.productSource == productSource,
                currentContext.productAdmission.matches(productAdmission),
                await currentContext.manifestIndex.upsertRowsForForegroundRefresh(
                    refreshed.rows,
                    productAdmission: productAdmission,
                    foregroundWorkAdmission: foregroundWorkAdmission
                )
            else { return [] }
            let removedRows: [BridgeWorktreeTreeRowMetadata]
            switch await currentContext.manifestIndex.removePathsForForegroundRefresh(
                refreshed.missingPaths,
                productAdmission: productAdmission,
                foregroundWorkAdmission: foregroundWorkAdmission
            ) {
            case .applied(let rows):
                removedRows = rows
            case .rejected:
                return []
            }
            if let gitStatusResult {
                let acceptedStatus: Bool
                switch gitStatusResult {
                case .available(let status):
                    acceptedStatus = try await currentContext.manifestIndex.updateMemberStatus(
                        state: .ready,
                        branchName: status.branch,
                        ahead: status.summary.aheadCount,
                        behind: status.summary.behindCount,
                        staged: status.summary.staged,
                        unstaged: status.summary.changed,
                        untracked: status.summary.untracked,
                        productAdmission: productAdmission
                    )
                case .unavailable:
                    acceptedStatus = try await currentContext.manifestIndex.updateMemberStatus(
                        state: .stale,
                        branchName: nil,
                        ahead: nil,
                        behind: nil,
                        staged: nil,
                        unstaged: nil,
                        untracked: nil,
                        productAdmission: productAdmission
                    )
                }
                guard acceptedStatus else { return [] }
            }
            guard
                let subscriptionEmissions = try makeChangesetEmissions(
                    .init(
                        changedPaths: changedPaths,
                        foregroundWorkAdmission: foregroundWorkAdmission,
                        gitStatusResult: gitStatusResult,
                        productAdmission: productAdmission,
                        productSource: productSource,
                        refreshed: refreshed,
                        removedRows: removedRows,
                        subscriptionId: subscriptionId
                    )
                )
            else { return [] }
            let renewalEmissions = try await renewInvalidatedDescriptorInterests(
                subscription: currentContext.subscription,
                productAdmission: productAdmission,
                foregroundWorkAdmission: foregroundWorkAdmission
            )
            emissions.append(
                contentsOf: try changesetEmissionsWithRenewedDescriptors(
                    subscriptionEmissions,
                    renewalEmissions: renewalEmissions
                )
            )
        }
        return emissions
    }

    private func makeChangesetEmissions(
        _ request: ChangesetEmissionRequest
    ) throws -> [BridgePaneProductFileMetadataEmission]? {
        guard request.foregroundWorkAdmission.withValidAdmission({ true }) == true,
            (request.productAdmission.withValidAdmission { true }) == true
        else { return nil }
        var emissions = try BridgePaneProductFileMetadataEncoding.treeDeltaEmissions(
            refreshed: request.refreshed,
            removedRows: request.removedRows,
            source: request.productSource,
            subscriptionId: request.subscriptionId
        )
        guard var latestContext = contextBySubscriptionId[request.subscriptionId],
            latestContext.productSource == request.productSource,
            latestContext.productAdmission.matches(request.productAdmission)
        else { return nil }
        let invalidatedDescriptorsByPath = request.foregroundWorkAdmission.withValidAdmission {
            request.productAdmission.withValidAdmission {
                () -> [String: BridgeProductFileDescriptorReadyPayload] in
                var invalidatedDescriptorsByPath: [String: BridgeProductFileDescriptorReadyPayload] = [:]
                for path in request.changedPaths
                where !BridgePaneProductFileMetadataEncoding.isGitInternalPath(path) {
                    if let previousDescriptor = latestContext.descriptorByPath.removeValue(
                        forKey: path
                    ) {
                        invalidatedDescriptorsByPath[path] = previousDescriptor
                    }
                    latestContext.descriptorInterestRevisionByPath.removeValue(forKey: path)
                    latestContext.inFlightDescriptorInterestRevisionByPath.removeValue(
                        forKey: path
                    )
                }
                contextBySubscriptionId[request.subscriptionId] = latestContext
                return invalidatedDescriptorsByPath
            }
        }.flatMap { $0 }
        guard let invalidatedDescriptorsByPath else { return nil }
        let invalidationEmissions: [BridgePaneProductFileMetadataEmission] =
            try request.changedPaths.sorted().compactMap { path in
                guard !BridgePaneProductFileMetadataEncoding.isGitInternalPath(path),
                    let previousDescriptor = invalidatedDescriptorsByPath[path]
                else {
                    return nil
                }
                // Tree deltas cover unmaterialized paths; a null ID would reset every descriptor.
                return .init(
                    event: .invalidated(
                        try .init(
                            fileId: previousDescriptor.fileId,
                            path: path,
                            reason: .contentChanged,
                            replacementDescriptor: nil,
                            source: request.productSource
                        )
                    ),
                    subscriptionId: request.subscriptionId
                )
            }
        guard (request.productAdmission.withValidAdmission { true }) == true else { return nil }
        emissions.append(contentsOf: invalidationEmissions)
        if let gitStatusResult = request.gitStatusResult {
            let statusEvent: BridgeProductFileMetadataEvent
            switch gitStatusResult {
            case .available(let status):
                statusEvent = BridgePaneProductFileMetadataEncoding.statusEvent(
                    status,
                    source: request.productSource
                )
            case .unavailable:
                statusEvent = .statusPatch(
                    .init(patch: .invalidated, source: request.productSource)
                )
            }
            emissions.append(
                .init(
                    event: statusEvent,
                    subscriptionId: request.subscriptionId
                )
            )
        }
        return emissions
    }
}
