import Foundation

@MainActor
extension BridgePaneController {
    func handleReviewMetadataInterestUpdate(
        _ params: ReviewMethods.MetadataInterestUpdateMethod.Params
    ) async throws {
        guard params.protocolId == "review" else {
            throw RPCMethodDispatchError.invalidParams("metadata interest protocol must be review")
        }
        if let streamId = params.streamId,
            streamId != reviewProtocolStreamId()
        {
            throw RPCMethodDispatchError.invalidParams("metadata interest streamId is stale")
        }
        guard let package = paneState.diff.packageMetadata else {
            throw RPCMethodDispatchError.invalidParams("metadata interest requires an active review package")
        }
        let requestedItemIds = Self.uniqueKnownReviewItemIds(params.itemIds ?? [], package: package)
        guard !requestedItemIds.isEmpty else { return }

        let traceContext = makeChildTraceContext(parent: lastReviewPackageTraceContext)
        let loadedBy = params.loadedBy ?? Self.reviewMetadataLoadedBy(for: params.lane)
        let lane = params.lane
        await enqueueReviewProtocolFrameJob(
            lane: Self.reviewMetadataSchedulerLane(for: lane),
            generation: package.reviewGeneration.rawValue,
            traceContext: traceContext
        ) { [weak self] sequence in
            guard let self,
                let currentPackage = self.paneState.diff.packageMetadata,
                currentPackage.reviewGeneration == package.reviewGeneration
            else {
                return nil
            }
            return .metadataWindow(
                try await self.makeReviewProtocolMetadataWindowFrame(
                    package: currentPackage,
                    itemIds: requestedItemIds,
                    sequence: sequence,
                    loadedBy: loadedBy,
                    lane: lane
                )
            )
        }
    }

    /// Review metadata-interest jobs map to foreground, visible, nearby, or
    /// speculative from the requesting lane (spec: review-protocol.md §2.1).
    /// Review contributes no idle-lane jobs, so idle-lane interest schedules
    /// as speculative while keeping its requested wire lineage.
    private static func reviewMetadataSchedulerLane(for lane: BridgeDemandLane) -> BridgeDemandLane {
        switch lane {
        case .foreground, .active:
            .foreground
        case .visible:
            .visible
        case .nearby:
            .nearby
        case .speculative, .idle:
            .speculative
        }
    }

    private static func uniqueKnownReviewItemIds(
        _ itemIds: [String],
        package: BridgeReviewPackage
    ) -> [String] {
        var seenItemIds = Set<String>()
        return itemIds.compactMap { itemId in
            guard package.itemsById[itemId] != nil,
                seenItemIds.insert(itemId).inserted
            else {
                return nil
            }
            return itemId
        }
    }

    private static func reviewMetadataLoadedBy(
        for lane: BridgeDemandLane
    ) -> BridgeReviewMetadataLoadedBy {
        switch lane {
        case .foreground, .active:
            .foreground
        case .visible:
            .visible
        case .nearby:
            .nearby
        case .speculative:
            .speculative
        case .idle:
            .idle
        }
    }
}
