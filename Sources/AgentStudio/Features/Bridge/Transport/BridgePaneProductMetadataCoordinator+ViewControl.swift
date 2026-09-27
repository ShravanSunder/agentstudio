import Foundation

extension BridgePaneProductMetadataCoordinator {
    func publishFileViewSnapshot(
        subscriptionId: String,
        productAdmission: BridgeProductAdmissionContext
    ) async throws -> Bool {
        guard let stream = activeStream,
            stream.productAdmission.matches(productAdmission),
            subscriptionKindById[subscriptionId] == .fileMetadata,
            let acceptedScope = await stream.session.acceptedViewScope(subscriptionId: subscriptionId),
            acceptedScope.revision > 0,
            let interestState = try? BridgeProductViewScopeContract.fileDemand(from: acceptedScope.scope),
            let snapshot = await fileMetadataSource.captureKeyedSnapshot(
                subscriptionId: subscriptionId,
                demand: .init(
                    admissionSequence: acceptedScope.admissionSequence,
                    handle: acceptedScope.handle,
                    scopeRevision: acceptedScope.revision,
                    state: interestState
                ),
                productAdmission: productAdmission
            ),
            await stream.session.acceptedViewScope(subscriptionId: subscriptionId)?.revision == acceptedScope.revision,
            activeStream?.lease == stream.lease
        else { return false }
        return try await stream.session.sealFileSnapshot(
            subscriptionId: subscriptionId,
            snapshot: snapshot,
            productAdmission: productAdmission
        )
    }

    func publishReviewViewSnapshot(
        subscriptionId: String,
        productAdmission: BridgeProductAdmissionContext
    ) async throws -> Bool {
        guard let stream = activeStream,
            stream.productAdmission.matches(productAdmission),
            subscriptionKindById[subscriptionId] == .reviewMetadata,
            let acceptedScope = await stream.session.acceptedViewScope(subscriptionId: subscriptionId),
            acceptedScope.revision > 0,
            let demand = try? BridgeProductViewScopeContract.reviewDemand(from: acceptedScope.scope),
            let publication = await reviewPublicationReplay(productAdmission),
            let capture = try await reviewMetadataSource.applyViewDemand(
                .init(
                    subscriptionId: subscriptionId,
                    handle: acceptedScope.handle,
                    scopeRevision: acceptedScope.revision,
                    admissionSequence: acceptedScope.admissionSequence,
                    demand: demand,
                    expectedPublicationId: publication.publicationId,
                    productAdmission: productAdmission
                )),
            capture.handle == acceptedScope.handle,
            capture.scopeRevision == acceptedScope.revision,
            capture.publicationId == publication.publicationId,
            await stream.session.acceptedViewScope(subscriptionId: subscriptionId)?.revision == acceptedScope.revision,
            activeStream?.lease == stream.lease
        else { return false }
        return try await stream.session.sealReviewSnapshot(
            subscriptionId: subscriptionId,
            snapshot: capture.snapshot,
            productAdmission: productAdmission
        )
    }

    func acceptViewScope(
        _ request: BridgeProductViewScopeRequest,
        productAdmission: BridgeProductAdmissionContext
    ) async -> BridgeProductRequestErrorCode? {
        guard let activeStream,
            activeStream.productAdmission.matches(productAdmission)
        else { return .staleWorker }
        if request.subscriptionKind == .fileAnnotations || request.subscriptionKind == .reviewAnnotations {
            guard let admittedWorktreeID = await annotationSource.admittedWorktreeID(),
                case .object(let scopeMembers) = request.scope,
                case .string(let scopedWorktreeID)? = scopeMembers["worktreeId"],
                scopedWorktreeID == admittedWorktreeID
            else { return .invalidRequest }
        }
        let priorHandle = await activeStream.session.acceptedViewScope(
            subscriptionId: request.subscriptionId
        )?.handle
        let refusal = await activeStream.session.acceptViewScope(
            request,
            productAdmission: productAdmission
        )
        guard refusal == nil else { return refusal }
        if request.subscriptionKind == .fileMetadata {
            // E4 settles at admission. N10 recaptures behind the separate view barrier.
            Task { [weak self] in
                guard let self else { return }
                await self.applyAcceptedFileViewDemand(
                    subscriptionId: request.subscriptionId,
                    expectedHandle: request.handle,
                    expectedRevision: request.scopeRevision,
                    forceRecapture: true,
                    productAdmission: productAdmission
                )
            }
        } else if request.subscriptionKind == .reviewMetadata {
            Task { [weak self] in
                guard let self else { return }
                _ = try? await self.publishReviewViewSnapshot(
                    subscriptionId: request.subscriptionId,
                    productAdmission: productAdmission
                )
            }
        } else {
            Task { [weak self] in
                if let priorHandle, priorHandle != request.handle {
                    await self?.annotationSource.retireBatchScope(handle: priorHandle)
                }
                await self?.applyAcceptedCommentViewScope(request, productAdmission: productAdmission)
            }
        }
        return nil
    }

    func applyAcceptedFileViewDemand(
        subscriptionId: String,
        expectedHandle: String,
        expectedRevision: Int,
        forceRecapture: Bool,
        productAdmission: BridgeProductAdmissionContext
    ) async {
        guard let activeStream,
            activeStream.productAdmission.matches(productAdmission),
            let current = await activeStream.session.acceptedViewScope(subscriptionId: subscriptionId),
            current.handle == expectedHandle,
            current.revision == expectedRevision,
            let state = try? BridgeProductViewScopeContract.fileDemand(from: current.scope),
            let foregroundWorkAdmission = refreshWorkAdmissionSource.acquire()
        else { return }
        try? await fileMetadataSource.applyViewDemand(
            subscriptionId: subscriptionId,
            demand: .init(
                admissionSequence: current.admissionSequence,
                handle: current.handle,
                scopeRevision: current.revision,
                state: state
            ),
            productAdmission: productAdmission,
            foregroundWorkAdmission: foregroundWorkAdmission,
            forceRecapture: forceRecapture
        ) { _ in }
        _ = try? await publishFileViewSnapshot(
            subscriptionId: subscriptionId,
            productAdmission: productAdmission
        )
    }

    private func applyAcceptedCommentViewScope(
        _ request: BridgeProductViewScopeRequest,
        productAdmission: BridgeProductAdmissionContext
    ) async {
        guard let activeStream,
            activeStream.productAdmission.matches(productAdmission),
            let current = await activeStream.session.acceptedViewScope(subscriptionId: request.subscriptionId),
            current.handle == request.handle,
            current.revision == request.scopeRevision,
            case .object(let members) = request.scope,
            case .string(let worktreeID)? = members["worktreeId"],
            case .array(let sessionValues)? = members["sessionIds"]
        else { return }
        let sessionIDs = Set(
            sessionValues.compactMap { value -> WorktreeAnnotationSessionID? in
                guard case .string(let rawValue) = value else { return nil }
                return UUID(uuidString: rawValue).map(WorktreeAnnotationSessionID.init(rawValue:))
            })
        try? await annotationSource.acceptBatchScope(
            handle: request.handle,
            worktreeID: worktreeID,
            sessionIDs: sessionIDs,
            scopeRevision: request.scopeRevision
        )
    }

    func acceptViewResnapshot(
        _ request: BridgeProductViewResnapshotRequest,
        productAdmission: BridgeProductAdmissionContext
    ) async -> BridgeProductRequestErrorCode? {
        guard let activeStream,
            activeStream.productAdmission.matches(productAdmission)
        else { return .staleWorker }
        let refusal = await activeStream.session.acceptViewResnapshot(
            request,
            productAdmission: productAdmission
        )
        guard refusal == nil else { return refusal }
        Task { [weak self] in
            await self?.recaptureAcceptedViewResnapshot(request, productAdmission: productAdmission)
        }
        return nil
    }

    private func recaptureAcceptedViewResnapshot(
        _ request: BridgeProductViewResnapshotRequest,
        productAdmission: BridgeProductAdmissionContext
    ) async {
        guard let activeStream,
            activeStream.productAdmission.matches(productAdmission)
        else { return }
        if request.subscriptionKind == .fileAnnotations || request.subscriptionKind == .reviewAnnotations {
            await annotationSource.requestBatchResnapshot(handle: request.handle)
        } else if request.subscriptionKind == .fileMetadata || request.subscriptionKind == .reviewMetadata {
            if request.subscriptionKind == .reviewMetadata {
                _ = try? await publishReviewViewSnapshot(
                    subscriptionId: request.subscriptionId,
                    productAdmission: productAdmission
                )
                return
            }
            await applyAcceptedFileViewDemand(
                subscriptionId: request.subscriptionId,
                expectedHandle: request.handle,
                expectedRevision: request.scopeRevision,
                forceRecapture: true,
                productAdmission: productAdmission
            )
        }
    }
}
