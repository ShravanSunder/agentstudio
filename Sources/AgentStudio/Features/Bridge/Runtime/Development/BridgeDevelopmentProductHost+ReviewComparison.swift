import AgentStudioCore

struct BridgeDevelopmentProductReviewInitialization {
    let comparisonTargetProjection: BridgeReviewComparisonTargetProjection
    let pipeline: BridgeReviewPipeline
    let initialTarget: WorkspaceReviewContributionTarget
    let defaultTarget: BridgeReviewComparisonDefaultTargetIdentity?
}

extension BridgeDevelopmentProductHost {
    static func makeReviewInitialization(
        state: BridgePaneState,
        provider: any BridgeReviewSourceProvider
    ) async throws -> BridgeDevelopmentProductReviewInitialization {
        let projection = await MainActor.run {
            BridgeReviewComparisonTargetProjection(state: state)
        }
        let pipeline = BridgeReviewPipeline(provider: provider)
        let initialTarget = try reviewTarget(from: state)
        let defaultTarget = try await loadReviewComparisonDefaultTarget(from: provider)
        return BridgeDevelopmentProductReviewInitialization(
            comparisonTargetProjection: projection,
            pipeline: pipeline,
            initialTarget: initialTarget,
            defaultTarget: defaultTarget
        )
    }

    func diagnosticPanePresentation() async -> BridgePaneProductPresentationSnapshot {
        await MainActor.run {
            refreshAdmissionCoordinator.productPresentationSnapshot
        }
    }

    func diagnosticCommittedReviewPublication() async -> BridgeReviewCommittedPublication? {
        await MainActor.run {
            reviewPublicationCoordinator.committedPublicationForReplay(
                productAdmission: productAdmission
            )
        }
    }

    func applyCommittedReviewComparisonUpdate(
        _ request: BridgeProductReviewComparisonUpdateRequest,
        productAdmission: BridgeProductAdmissionContext
    ) async {
        guard !isShutdown, productAdmission.withValidAdmission({ true }) == true else { return }
        let mutationResult = await contributionTargetCommit(request.target)
        guard productAdmission.withValidAdmission({ true }) == true else { return }
        let canonicalState: BridgePaneState
        switch mutationResult {
        case .applied(let state), .unchanged(let state):
            canonicalState = state
        case .paneMissing, .notBridgePane, .notWorkspaceSource:
            productAdmissionGate.close()
            return
        }
        guard case .workspace(_, let baseline)? = canonicalState.source,
            baseline?.contributionTarget == request.target
        else {
            productAdmissionGate.close()
            return
        }
        paneState = canonicalState
        await MainActor.run {
            reviewComparisonTargetProjection.update(state: canonicalState)
        }
        let reviewGeneration = nextReviewGeneration.next()
        nextReviewGeneration = reviewGeneration
        let supersededReviewComparisonTask = activeReviewComparisonTask
        await MainActor.run {
            supersededReviewComparisonTask?.cancel()
            refreshAdmissionCoordinator.beginReviewComparisonAttempt(
                activeTarget: request.target,
                reviewGeneration: reviewGeneration.rawValue
            )
        }
        await publishCurrentPanePresentation()
        guard !isShutdown, productAdmission.withValidAdmission({ true }) == true else { return }

        activeReviewComparisonTaskGeneration = reviewGeneration
        activeReviewComparisonTask = Task { [weak self] in
            guard let self else { return }
            await self.runReviewComparisonPublication(
                target: request.target,
                reviewGeneration: reviewGeneration,
                productAdmission: productAdmission
            )
            await self.clearReviewComparisonTask(reviewGeneration: reviewGeneration)
        }
    }

    private func runReviewComparisonPublication(
        target: WorkspaceReviewContributionTarget,
        reviewGeneration: BridgeReviewGeneration,
        productAdmission: BridgeProductAdmissionContext
    ) async {
        guard !Task.isCancelled else {
            await failReviewComparisonAttempt(reviewGeneration, failureKind: "publication_failed")
            return
        }
        guard
            let foregroundWorkAdmission = await MainActor.run(body: {
                refreshAdmissionCoordinator.acquireForegroundWork()
            })
        else {
            await failReviewComparisonAttempt(reviewGeneration, failureKind: "foreground_unavailable")
            return
        }
        guard
            await refreshRepositoryDefaultTarget(
                reviewGeneration: reviewGeneration,
                productAdmission: productAdmission,
                foregroundWorkAdmission: foregroundWorkAdmission
            )
        else { return }

        do {
            let preparedPublication = try await constructReviewPublication(
                target: target,
                reviewGeneration: reviewGeneration
            )
            try await publishPreparedReviewComparison(
                preparedPublication,
                productAdmission: productAdmission,
                foregroundWorkAdmission: foregroundWorkAdmission
            )
        } catch {
            await failReviewComparisonAttempt(reviewGeneration, failureKind: "publication_failed")
        }
    }

    private func refreshRepositoryDefaultTarget(
        reviewGeneration: BridgeReviewGeneration,
        productAdmission: BridgeProductAdmissionContext,
        foregroundWorkAdmission: BridgePaneRefreshWorkAdmission
    ) async -> Bool {
        guard
            !Task.isCancelled,
            !isShutdown,
            productAdmission.withValidAdmission({ true }) == true,
            foregroundWorkAdmission.withValidAdmission({ true }) == true
        else { return false }
        let didClearCurrentDefault = await MainActor.run {
            guard
                refreshAdmissionCoordinator.isReviewComparisonAttemptPending(
                    reviewGeneration: reviewGeneration.rawValue
                )
            else { return false }
            refreshAdmissionCoordinator.publishReviewComparisonDefaultTarget(nil)
            return true
        }
        guard didClearCurrentDefault else { return false }
        await publishCurrentPanePresentation()

        let resolvedDefaultTarget: BridgeReviewComparisonDefaultTargetIdentity?
        do {
            resolvedDefaultTarget = try await reviewProvider.resolveReviewDefaultTarget()
        } catch is CancellationError {
            return false
        } catch {
            resolvedDefaultTarget = nil
        }
        guard
            !Task.isCancelled,
            !isShutdown,
            productAdmission.withValidAdmission({ true }) == true,
            foregroundWorkAdmission.withValidAdmission({ true }) == true
        else { return false }
        let didPublishCurrentDefault = await MainActor.run {
            guard
                refreshAdmissionCoordinator.isReviewComparisonAttemptPending(
                    reviewGeneration: reviewGeneration.rawValue
                )
            else { return false }
            refreshAdmissionCoordinator.publishReviewComparisonDefaultTarget(resolvedDefaultTarget)
            return true
        }
        guard didPublishCurrentDefault else { return false }
        await publishCurrentPanePresentation()
        return true
    }

    private func clearReviewComparisonTask(reviewGeneration: BridgeReviewGeneration) {
        guard activeReviewComparisonTaskGeneration == reviewGeneration else { return }
        activeReviewComparisonTask = nil
        activeReviewComparisonTaskGeneration = nil
    }

    private func publishPreparedReviewComparison(
        _ preparedPublication: BridgeReviewPreparedPublication,
        productAdmission: BridgeProductAdmissionContext,
        foregroundWorkAdmission: BridgePaneRefreshWorkAdmission
    ) async throws {
        if Task.isCancelled {
            await preparedPublication.artifactPin?.releaseAndWait()
            throw CancellationError()
        }
        guard productAdmission.withValidAdmission({ true }) == true,
            foregroundWorkAdmission.withValidAdmission({ true }) == true
        else {
            await preparedPublication.artifactPin?.releaseAndWait()
            return
        }
        let stagedToken = await MainActor.run {
            reviewPublicationCoordinator.stage(
                preparedPublication,
                productAdmission: productAdmission
            )
        }
        guard let stagedToken else {
            throw BridgeDevelopmentProductHostError.reviewPublicationFailed
        }
        let reservation: BridgeReviewMetadataPublicationReservation
        do {
            reservation = try await productProvider.reserveReviewPublication(
                package: preparedPublication.package,
                publicationId: stagedToken.publicationId,
                productAdmission: productAdmission,
                foregroundWorkAdmission: foregroundWorkAdmission
            )
            try Task.checkCancellation()
        } catch {
            _ = await MainActor.run {
                reviewPublicationCoordinator.rejectReservation(
                    stagedToken,
                    productAdmission: productAdmission
                )
            }
            throw error
        }
        let committedPublication = await MainActor.run {
            () -> BridgeReviewCommittedPublication? in
            guard
                refreshAdmissionCoordinator.isReviewComparisonAttemptPending(
                    reviewGeneration: preparedPublication.package.reviewGeneration.rawValue
                )
            else {
                _ = reviewPublicationCoordinator.rejectReservation(
                    stagedToken,
                    productAdmission: productAdmission
                )
                return nil
            }
            guard
                case .committed(let publication) = reviewPublicationCoordinator.commit(
                    stagedToken,
                    productAdmission: productAdmission,
                    presentCommitted: { _ in }
                )
            else {
                _ = reviewPublicationCoordinator.rejectReservation(
                    stagedToken,
                    productAdmission: productAdmission
                )
                return nil
            }
            refreshAdmissionCoordinator.settleReviewComparisonAttempt(
                reviewGeneration: publication.package.reviewGeneration.rawValue,
                displayedSnapshotIdentity: BridgePaneReviewDisplayedSnapshotIdentity(
                    packageId: publication.package.packageId,
                    reviewGeneration: publication.package.reviewGeneration.rawValue,
                    revision: publication.package.revision
                )
            )
            return publication
        }
        guard let committedPublication else {
            throw BridgeDevelopmentProductHostError.reviewPublicationFailed
        }
        await publishCurrentPanePresentation()
        let delivery = await productProvider.deliverReviewPublication(
            committedPublication,
            reservation: reservation,
            productAdmission: productAdmission,
            foregroundWorkAdmission: foregroundWorkAdmission
        )
        _ = await MainActor.run {
            reviewPublicationCoordinator.recordTransportDeliveryDisposition(
                delivery,
                publicationId: committedPublication.publicationId,
                productAdmission: productAdmission
            )
        }
    }

    func failReviewComparisonAttempt(
        _ reviewGeneration: BridgeReviewGeneration,
        failureKind: String
    ) async {
        await MainActor.run {
            refreshAdmissionCoordinator.failReviewComparisonAttempt(
                reviewGeneration: reviewGeneration.rawValue,
                failureKind: failureKind,
                retryable: true
            )
        }
        await publishCurrentPanePresentation()
    }

    func publishCurrentPanePresentation() async {
        let snapshot = await MainActor.run {
            refreshAdmissionCoordinator.productPresentationSnapshot
        }
        await productProvider.publishPanePresentation(snapshot)
    }
}
