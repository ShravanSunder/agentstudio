import AgentStudioCore
import Foundation

@MainActor
extension BridgePaneController {
    func handleCommittedProductReviewComparisonUpdate(
        _ request: BridgeProductReviewComparisonUpdateRequest,
        productAdmission: BridgeProductAdmissionContext
    ) async -> Bool {
        guard productAdmission.withValidAdmission({ true }) == true,
            let contributionTargetCommit
        else {
            reviewGitRefreshSeedHolder.retire()
            productAdmissionGate.close()
            refreshAdmissionCoordinator.close()
            return false
        }
        let commitResult = contributionTargetCommit(request.target)
        guard productAdmission.withValidAdmission({ true }) == true else { return false }
        let canonicalBaseline: WorkspaceBaseline
        let replacedLineage: Bool
        switch commitResult {
        case .applied(let baseline):
            canonicalBaseline = baseline
            replacedLineage = true
        case .unchanged(let baseline):
            canonicalBaseline = baseline
            replacedLineage = false
        case .receiverUnavailable:
            reviewGitRefreshSeedHolder.retire()
            productAdmissionGate.close()
            refreshAdmissionCoordinator.close()
            return false
        }
        guard reviewBinding != nil, canonicalBaseline.contributionTarget == request.target else {
            reviewGitRefreshSeedHolder.retire()
            productAdmissionGate.close()
            refreshAdmissionCoordinator.close()
            return false
        }

        reviewBinding?.comparison = canonicalBaseline
        reviewComparisonTargetProjection.update(reviewBinding: reviewBinding)
        guard replacedLineage else { return true }
        reviewGitRefreshSeedHolder.retire()
        let reviewGeneration = nextReviewGeneration.next()
        nextReviewGeneration = reviewGeneration
        pendingComparisonReviewGeneration = reviewGeneration
        refreshAdmissionCoordinator.beginReviewComparisonAttempt(
            activeTarget: request.target,
            reviewGeneration: reviewGeneration.rawValue
        )
        _ = scheduleProductPresentationPublication()
        pendingReviewPackageBuildReasons.insert(.productResync)
        refreshAdmissionCoordinator.advanceAuthority(for: .review)
        retireActiveReviewRefreshTask()
        scheduleRetainedReviewPackageBuildIfPossible()
        return true
    }

    func adoptInitialContributionTargetIfEligible(
        reset: ReviewPackageLoadReset,
        productAdmission: BridgeProductAdmissionContext,
        foregroundWorkAdmission: BridgePaneRefreshWorkAdmission
    ) async throws {
        guard let reviewBinding else { return }
        let baseline = reviewBinding.comparison
        let resolvedDefaultTarget = try await resolveAndPublishReviewComparisonDefaultTargetIfCurrent(
            reset: reset,
            productAdmission: productAdmission,
            foregroundWorkAdmission: foregroundWorkAdmission
        )
        guard baseline == nil else { return }
        guard
            let resolvedDefaultTarget,
            let initialContributionTargetCommit
        else { return }
        let commitResult = initialContributionTargetCommit(
            .originDefaultBranch(
                remoteName: resolvedDefaultTarget.remoteName,
                branchName: resolvedDefaultTarget.branchName,
                basis: .commonCommit
            )
        )
        guard
            isReviewPackageLoadCurrent(
                reset: reset,
                productAdmission: productAdmission,
                foregroundWorkAdmission: foregroundWorkAdmission
            )
        else { return }
        switch commitResult {
        case .applied(let canonicalBaseline), .unchanged(let canonicalBaseline):
            guard self.reviewBinding != nil else { return }
            self.reviewBinding?.comparison = canonicalBaseline
            reviewComparisonTargetProjection.update(reviewBinding: self.reviewBinding)
            guard let activeTarget = canonicalBaseline.contributionTarget else { return }
            refreshAdmissionCoordinator.beginReviewComparisonAttempt(
                activeTarget: activeTarget,
                reviewGeneration: reset.reviewGeneration.rawValue
            )
            _ = scheduleProductPresentationPublication()
        case .receiverUnavailable:
            break
        }
    }

    func resolveAndPublishReviewComparisonDefaultTargetIfCurrent(
        reset: ReviewPackageLoadReset,
        productAdmission: BridgeProductAdmissionContext,
        foregroundWorkAdmission: BridgePaneRefreshWorkAdmission
    ) async throws -> BridgeReviewComparisonDefaultTargetIdentity? {
        guard
            isReviewPackageLoadCurrent(
                reset: reset,
                productAdmission: productAdmission,
                foregroundWorkAdmission: foregroundWorkAdmission
            )
        else { return nil }
        let resolvedDefaultTarget: BridgeReviewComparisonDefaultTargetIdentity?
        do {
            resolvedDefaultTarget = try await reviewSourceProvider.resolveReviewDefaultTarget()
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            resolvedDefaultTarget = nil
        }
        guard
            isReviewPackageLoadCurrent(
                reset: reset,
                productAdmission: productAdmission,
                foregroundWorkAdmission: foregroundWorkAdmission
            )
        else { return nil }
        refreshAdmissionCoordinator.publishReviewComparisonDefaultTarget(resolvedDefaultTarget)
        _ = scheduleProductPresentationPublication()
        return resolvedDefaultTarget
    }

    func resolveContributionRequestIfNeeded(
        _ request: BridgeReviewPipelineRequest
    ) async throws -> BridgeReviewPipelineRequest {
        guard let reviewBinding else { return request }
        guard let baseline = reviewBinding.comparison else {
            throw BridgeProviderFailure.providerFailed(
                message: "Contribution target selection required"
            )
        }
        guard let symbolicTarget = baseline.contributionTarget else { return request }
        let capture = try await reviewSourceProvider.captureContributionComparison(
            BridgeContributionComparisonRequest(
                symbolicTarget: symbolicTarget,
                baseEndpoint: request.baseEndpoint,
                headEndpoint: request.headEndpoint,
                reviewGenerationValue: request.reviewGeneration.rawValue,
                reviewAttemptAuthorityGeneration: request.reviewAttemptAuthorityGeneration,
                gitRefreshScope: request.gitRefreshScope,
                gitRefreshSeed: request.gitRefreshSeed
            )
        )
        return try BridgeResolvedContributionRequestBuilder.build(
            request: request,
            symbolicTarget: symbolicTarget,
            capture: capture,
            reviewedSubjectLabel: reviewedSubjectLabel
        )
    }

    private var reviewedSubjectLabel: String? {
        normalizedReviewedSubject(runtime.metadata.facets.worktreeName)
            ?? normalizedReviewedSubject(runtime.metadata.checkoutRef)
    }

    private func normalizedReviewedSubject(_ value: String?) -> String? {
        guard let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines),
            !normalized.isEmpty
        else { return nil }
        return normalized
    }
}
