import Foundation

extension BridgePaneProductMetadataCoordinator {
    func publishFileViewSnapshot(
        subscriptionId: String,
        productAdmission: BridgeProductAdmissionContext
    ) async throws -> Bool {
        guard let stream = activeStream,
            stream.productAdmission.matches(productAdmission),
            subscriptionKindById[subscriptionId] == .fileMetadata,
            let snapshot = await fileMetadataSource.captureKeyedSnapshot(
                subscriptionId: subscriptionId,
                productAdmission: productAdmission
            ),
            activeStream?.lease == stream.lease
        else { return false }
        return try await stream.session.sealFileSnapshot(
            subscriptionId: subscriptionId,
            snapshot: snapshot,
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
        return await activeStream.session.acceptViewScope(request, productAdmission: productAdmission)
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
        if request.subscriptionKind == .fileAnnotations || request.subscriptionKind == .reviewAnnotations {
            await annotationSource.requestBatchResnapshot(handle: request.handle)
        } else if request.subscriptionKind == .fileMetadata || request.subscriptionKind == .reviewMetadata {
            guard let foregroundWorkAdmission = refreshWorkAdmissionSource.acquire() else {
                deferredUpdateSubscriptionIds.insert(request.subscriptionId)
                return nil
            }
            if let subscription = await activeStream.session.subscriptionSnapshot(
                subscriptionId: request.subscriptionId
            ) {
                startSubscriptionUpdate(
                    subscription,
                    activeStream: activeStream,
                    productAdmission: productAdmission,
                    foregroundWorkAdmission: foregroundWorkAdmission
                )
            }
        }
        return nil
    }
}
