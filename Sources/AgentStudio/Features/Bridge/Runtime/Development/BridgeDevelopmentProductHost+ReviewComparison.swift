import AgentStudioCore
import AgentStudioGit

struct BridgeDevelopmentProductReviewInitialization {
    let comparisonTargetProjection: BridgeReviewComparisonTargetProjection
    let pipeline: BridgeReviewPipeline
    let initialTarget: WorkspaceReviewContributionTarget
    let defaultTarget: BridgeReviewComparisonDefaultTargetIdentity?
}

struct BridgeDevelopmentReviewPublicationConstruction {
    let preparedPublication: BridgeReviewPreparedPublication
    let gitRefreshSeed: GitReviewRefreshSeed?
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

    package func handleObservedWorktreeTerminal() async {
        guard !isShutdown, let activeTarget = try? Self.reviewTarget(from: paneState) else { return }
        let reviewGeneration = nextReviewGeneration.next()
        nextReviewGeneration = reviewGeneration
        await MainActor.run {
            _ = refreshAdmissionCoordinator.advanceAuthority(for: .file)
            _ = refreshAdmissionCoordinator.advanceAuthority(for: .review)
            worktreeRefreshDriver.retireActiveFileOperation()
            refreshAdmissionCoordinator.recordFileRefreshFailure(
                .init(failureKind: .fileRefreshFailed)
            )
            refreshAdmissionCoordinator.beginReviewComparisonAttempt(
                activeTarget: activeTarget,
                reviewGeneration: reviewGeneration.rawValue
            )
            refreshAdmissionCoordinator.failReviewComparisonAttempt(
                reviewGeneration: reviewGeneration.rawValue,
                failureKind: "observation_terminal",
                retryable: false
            )
        }
        retireActiveReviewComparisonTask()
        await publishCurrentPanePresentation()
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
        guard case .applied = mutationResult else { return }
        let reviewGeneration = nextReviewGeneration.next()
        nextReviewGeneration = reviewGeneration
        reviewGitRefreshSeedHolder.retire()
        retireActiveReviewComparisonTask()
        await MainActor.run {
            refreshAdmissionCoordinator.beginReviewComparisonAttempt(
                activeTarget: request.target,
                reviewGeneration: reviewGeneration.rawValue
            )
        }
        await publishCurrentPanePresentation()
        guard !isShutdown, productAdmission.withValidAdmission({ true }) == true else { return }

        let taskAttempt = allocateReviewComparisonTaskAttempt()
        activeReviewComparisonTaskAttempt = taskAttempt
        activeReviewComparisonTask = Task { [weak self] in
            guard let self else { return }
            _ = await self.runReviewComparisonPublication(
                target: request.target,
                reviewGeneration: reviewGeneration,
                classifySameSourceRefresh: false,
                productAdmission: productAdmission
            )
            await self.clearReviewComparisonTask(taskAttempt: taskAttempt)
        }
    }

    func scheduleObservedReviewRefreshIfPossible() async {
        guard !isShutdown,
            let reservation = await MainActor.run(body: {
                refreshAdmissionCoordinator.reserveForegroundRefreshPass(for: .review)
            }),
            let target = try? Self.reviewTarget(from: paneState),
            let currentPublication = await MainActor.run(body: {
                reviewPublicationCoordinator.committedPublicationForReplay(
                    productAdmission: productAdmission
                )
            })
        else { return }

        let reviewGeneration = currentPublication.package.reviewGeneration
        retireActiveReviewComparisonTask()
        await MainActor.run {
            refreshAdmissionCoordinator.beginReviewComparisonAttempt(
                activeTarget: target,
                reviewGeneration: reviewGeneration.rawValue
            )
        }
        await publishCurrentPanePresentation()

        let taskAttempt = allocateReviewComparisonTaskAttempt()
        activeReviewComparisonTaskAttempt = taskAttempt
        activeReviewComparisonTask = Task { [weak self] in
            guard let self else { return }
            await self.productProvider.recordOperationLifecycle(
                operationCorrelationID: reservation.operationCorrelationID,
                result: .success,
                stage: .refreshReserved,
                stageAttempt: reservation.operationStageAttempt,
                surface: .review
            )
            await self.productProvider.recordOperationLifecycle(
                operationCorrelationID: reservation.operationCorrelationID,
                result: .started,
                stage: .reviewPrepareStarted,
                stageAttempt: reservation.operationStageAttempt,
                surface: .review
            )
            let outcome = await self.runReviewComparisonPublication(
                target: target,
                reviewGeneration: reviewGeneration,
                classifySameSourceRefresh: true,
                predecessorPublication: currentPublication,
                refreshReservation: reservation,
                operationCorrelationID: reservation.operationCorrelationID,
                productAdmission: self.productAdmission
            )
            await self.productProvider.recordOperationLifecycle(
                operationCorrelationID: reservation.operationCorrelationID,
                result: Self.operationResult(for: outcome),
                stage: .reviewPrepareTerminal,
                stageAttempt: reservation.operationStageAttempt,
                surface: .review
            )
            await self.productProvider.recordOperationLifecycle(
                operationCorrelationID: reservation.operationCorrelationID,
                result: Self.operationResult(for: outcome),
                stage: .refreshOperationTerminal,
                stageAttempt: reservation.operationStageAttempt,
                surface: .review
            )
            await MainActor.run {
                self.refreshAdmissionCoordinator.completeRefreshPass(
                    reservation,
                    outcome: outcome
                )
            }
            await self.publishCurrentPanePresentation()
            await self.clearReviewComparisonTask(taskAttempt: taskAttempt)
        }
    }

    private func retireActiveReviewComparisonTask() {
        guard let taskAttempt = activeReviewComparisonTaskAttempt,
            let task = activeReviewComparisonTask
        else { return }
        task.cancel()
        retiringReviewComparisonTasks[taskAttempt] = task
        activeReviewComparisonTask = nil
        activeReviewComparisonTaskAttempt = nil
    }

    private func runReviewComparisonPublication(
        target: WorkspaceReviewContributionTarget,
        reviewGeneration: BridgeReviewGeneration,
        classifySameSourceRefresh: Bool,
        predecessorPublication: BridgeReviewCommittedPublication? = nil,
        refreshReservation: BridgePaneRefreshCatchUpReservation? = nil,
        operationCorrelationID: String? = nil,
        productAdmission: BridgeProductAdmissionContext
    ) async -> BridgePaneRefreshCatchUpOutcome {
        guard !Task.isCancelled else {
            await failReviewComparisonAttempt(reviewGeneration, failureKind: "publication_failed")
            return .stale
        }
        guard
            let foregroundWorkAdmission = await MainActor.run(body: {
                refreshAdmissionCoordinator.acquireForegroundWork()
            })
        else {
            await failReviewComparisonAttempt(reviewGeneration, failureKind: "foreground_unavailable")
            return .failed
        }
        guard
            await refreshRepositoryDefaultTarget(
                reviewGeneration: reviewGeneration,
                refreshReservation: refreshReservation,
                productAdmission: productAdmission,
                foregroundWorkAdmission: foregroundWorkAdmission
            )
        else { return .stale }

        do {
            let construction = try await constructReviewPublication(
                target: target,
                reviewGeneration: reviewGeneration,
                predecessorPackage: predecessorPublication?.package,
                refreshReservation: refreshReservation
            )
            guard
                await isCurrentReviewComparisonAttempt(
                    reviewGeneration: reviewGeneration,
                    refreshReservation: refreshReservation,
                    productAdmission: productAdmission,
                    foregroundWorkAdmission: foregroundWorkAdmission
                )
            else {
                await construction.preparedPublication.artifactPin?.releaseAndWait()
                return .stale
            }
            reviewGitRefreshSeedHolder.commit(construction.gitRefreshSeed)
            if let predecessorPublication,
                construction.preparedPublication.delta == nil,
                construction.preparedPublication.package.hasSameReviewTruth(
                    as: predecessorPublication.package
                )
            {
                await construction.preparedPublication.artifactPin?.releaseAndWait()
                await MainActor.run {
                    refreshAdmissionCoordinator.settleReviewComparisonAttempt(
                        reviewGeneration: reviewGeneration.rawValue,
                        displayedSnapshotIdentity: BridgePaneReviewDisplayedSnapshotIdentity(
                            packageId: predecessorPublication.package.packageId,
                            reviewGeneration: reviewGeneration.rawValue,
                            revision: predecessorPublication.package.revision
                        )
                    )
                }
                return .succeeded
            }
            guard
                let preparedPublication = await classifiedReviewPublication(
                    construction.preparedPublication,
                    reviewGeneration: reviewGeneration,
                    classifySameSourceRefresh: classifySameSourceRefresh,
                    refreshReservation: refreshReservation,
                    productAdmission: productAdmission,
                    foregroundWorkAdmission: foregroundWorkAdmission
                )
            else {
                await construction.preparedPublication.artifactPin?.releaseAndWait()
                return .stale
            }
            try await publishPreparedReviewComparison(
                preparedPublication,
                reviewGeneration: reviewGeneration,
                refreshReservation: refreshReservation,
                productAdmission: productAdmission,
                foregroundWorkAdmission: foregroundWorkAdmission,
                operationCorrelationID: operationCorrelationID
            )
            return Task.isCancelled ? .stale : .succeeded
        } catch {
            await failReviewComparisonAttempt(reviewGeneration, failureKind: "publication_failed")
            return Task.isCancelled ? .stale : .failed
        }
    }

    private func classifiedReviewPublication(
        _ preparedPublication: BridgeReviewPreparedPublication,
        reviewGeneration: BridgeReviewGeneration,
        classifySameSourceRefresh: Bool,
        refreshReservation: BridgePaneRefreshCatchUpReservation?,
        productAdmission: BridgeProductAdmissionContext,
        foregroundWorkAdmission: BridgePaneRefreshWorkAdmission
    ) async -> BridgeReviewPreparedPublication? {
        guard classifySameSourceRefresh else { return preparedPublication }
        let displayedPublication = await MainActor.run {
            reviewPublicationCoordinator.acknowledgedDisplayedPublication(
                productAdmission: productAdmission
            )
        }
        let expectedDisplayedPublicationId = displayedPublication?.publicationId
        let refreshImpact: BridgeReviewRefreshImpact
        if let displayedPublication,
            let impactProvider = reviewProvider as? any BridgeReviewRefreshImpactSourceProvider
        {
            do {
                refreshImpact = try await impactProvider.measureRefreshImpact(
                    displayedPackage: displayedPublication.package,
                    candidatePackage: preparedPublication.package,
                    candidateGeneration: reviewGeneration
                )
            } catch is CancellationError {
                return nil
            } catch {
                refreshImpact = .unknown(
                    displayedPackage: displayedPublication.package,
                    candidatePackage: preparedPublication.package
                )
            }
        } else {
            refreshImpact = .unknown(
                displayedPackage: displayedPublication?.package,
                candidatePackage: preparedPublication.package
            )
        }
        guard !Task.isCancelled,
            !isShutdown,
            reviewGeneration == nextReviewGeneration,
            productAdmission.withValidAdmission({ true }) == true,
            foregroundWorkAdmission.withValidAdmission({ true }) == true
        else { return nil }
        let isCurrentAttempt = await MainActor.run {
            refreshAdmissionCoordinator.isReviewComparisonAttemptPending(
                reviewGeneration: reviewGeneration.rawValue
            )
                && refreshReservation.map(refreshAdmissionCoordinator.isRefreshPassCurrent) != false
                && reviewPublicationCoordinator.acknowledgedDisplayedPublication(
                    productAdmission: productAdmission
                )?.publicationId == expectedDisplayedPublicationId
        }
        guard isCurrentAttempt else { return nil }
        return preparedPublication.classified(with: refreshImpact)
    }

    private func refreshRepositoryDefaultTarget(
        reviewGeneration: BridgeReviewGeneration,
        refreshReservation: BridgePaneRefreshCatchUpReservation?,
        productAdmission: BridgeProductAdmissionContext,
        foregroundWorkAdmission: BridgePaneRefreshWorkAdmission
    ) async -> Bool {
        guard
            !Task.isCancelled,
            !isShutdown,
            productAdmission.withValidAdmission({ true }) == true,
            foregroundWorkAdmission.withValidAdmission({ true }) == true
        else { return false }
        let isCurrentAttempt = await MainActor.run {
            guard
                refreshAdmissionCoordinator.isReviewComparisonAttemptPending(
                    reviewGeneration: reviewGeneration.rawValue
                )
                    && refreshReservation.map(refreshAdmissionCoordinator.isRefreshPassCurrent) != false
            else { return false }
            return true
        }
        guard isCurrentAttempt else { return false }

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
                    && refreshReservation.map(refreshAdmissionCoordinator.isRefreshPassCurrent) != false
            else { return false }
            refreshAdmissionCoordinator.publishReviewComparisonDefaultTarget(resolvedDefaultTarget)
            return true
        }
        guard didPublishCurrentDefault else { return false }
        await publishCurrentPanePresentation()
        return true
    }

    private func clearReviewComparisonTask(taskAttempt: UInt64) {
        retiringReviewComparisonTasks.removeValue(forKey: taskAttempt)
        guard activeReviewComparisonTaskAttempt == taskAttempt else { return }
        activeReviewComparisonTask = nil
        activeReviewComparisonTaskAttempt = nil
    }

    private static func operationResult(
        for outcome: BridgePaneRefreshCatchUpOutcome
    ) -> BridgeOperationLifecycleTraceEvent.Result {
        switch outcome {
        case .succeeded:
            .success
        case .failed:
            .failure
        case .stale, .streamReset:
            .stale
        }
    }

    private func publishPreparedReviewComparison(
        _ preparedPublication: BridgeReviewPreparedPublication,
        reviewGeneration: BridgeReviewGeneration,
        refreshReservation: BridgePaneRefreshCatchUpReservation?,
        productAdmission: BridgeProductAdmissionContext,
        foregroundWorkAdmission: BridgePaneRefreshWorkAdmission,
        operationCorrelationID: String?
    ) async throws {
        if Task.isCancelled {
            await preparedPublication.artifactPin?.releaseAndWait()
            throw CancellationError()
        }
        guard productAdmission.withValidAdmission({ true }) == true,
            foregroundWorkAdmission.withValidAdmission({ true }) == true,
            await isCurrentReviewComparisonAttempt(
                reviewGeneration: reviewGeneration,
                refreshReservation: refreshReservation,
                productAdmission: productAdmission,
                foregroundWorkAdmission: foregroundWorkAdmission
            )
        else {
            await preparedPublication.artifactPin?.releaseAndWait()
            return
        }
        let stagedToken = await MainActor.run {
            reviewPublicationCoordinator.stage(
                preparedPublication,
                operationCorrelationID: operationCorrelationID,
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
                    && refreshReservation.map(refreshAdmissionCoordinator.isRefreshPassCurrent) != false
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
                    captureCommittedPresentation: { package in
                        refreshAdmissionCoordinator.settleReviewComparisonAttempt(
                            reviewGeneration: package.reviewGeneration.rawValue,
                            displayedSnapshotIdentity: BridgePaneReviewDisplayedSnapshotIdentity(
                                packageId: package.packageId,
                                reviewGeneration: package.reviewGeneration.rawValue,
                                revision: package.revision
                            )
                        )
                        return refreshAdmissionCoordinator.productPresentationSnapshot
                    },
                    presentCommitted: { _ in }
                )
            else {
                _ = reviewPublicationCoordinator.rejectReservation(
                    stagedToken,
                    productAdmission: productAdmission
                )
                return nil
            }
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
        await recordReviewTransportDelivery(
            delivery,
            publication: committedPublication,
            productAdmission: productAdmission
        )
    }

    private func recordReviewTransportDelivery(
        _ delivery: BridgeReviewPublicationDeliveryDisposition,
        publication: BridgeReviewCommittedPublication,
        productAdmission: BridgeProductAdmissionContext
    ) async {
        _ = await MainActor.run {
            reviewPublicationCoordinator.recordTransportDeliveryDisposition(
                delivery,
                publicationId: publication.publicationId,
                productAdmission: productAdmission
            )
        }
    }

    private func isCurrentReviewComparisonAttempt(
        reviewGeneration: BridgeReviewGeneration,
        refreshReservation: BridgePaneRefreshCatchUpReservation?,
        productAdmission: BridgeProductAdmissionContext,
        foregroundWorkAdmission: BridgePaneRefreshWorkAdmission
    ) async -> Bool {
        guard !Task.isCancelled,
            !isShutdown,
            reviewGeneration == nextReviewGeneration,
            productAdmission.withValidAdmission({ true }) == true,
            foregroundWorkAdmission.withValidAdmission({ true }) == true
        else { return false }
        return await MainActor.run {
            refreshAdmissionCoordinator.isReviewComparisonAttemptPending(
                reviewGeneration: reviewGeneration.rawValue
            )
                && refreshReservation.map(refreshAdmissionCoordinator.isRefreshPassCurrent) != false
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
