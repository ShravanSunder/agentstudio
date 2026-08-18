import Foundation

extension WorktreeAnnotationTransportAdapter {
    func executeOutputPreparation(
        _ assembled: WorktreeAnnotationAssembledOutputSelection,
        surface: BridgeProductSurface
    ) async throws -> WorktreeAnnotationOutputCommandOutcome {
        guard let outputCoordinator, let outputLabels else {
            throw WorktreeAnnotationTransportAdapterError.outputUnavailable
        }
        let sessionID = WorktreeAnnotationSessionID(rawValue: assembled.sessionID)
        let context = try await store.outputSnapshotContext(
            sessionID: sessionID,
            contextID: contextID,
            surface: surface
        )
        let outputKind: WorktreeAnnotationOutputKind =
            switch assembled.outputKind {
            case .clipboardMarkdown: .clipboardMarkdown
            case .jsonFile: .jsonFile
            }
        let eligibleMessages = context.sessionDetail.threads.flatMap(\.messages).filter {
            $0.savedBody != nil && $0.savedRevision != nil && $0.draft == nil && $0.status == .editable
        }
        let selectedMessages: [WorktreeAnnotationMessage]
        switch assembled.selection {
        case .explicit(let messageIds):
            let selectedIDs = Set(messageIds.map(WorktreeAnnotationMessageID.init(rawValue:)))
            selectedMessages = eligibleMessages.filter { selectedIDs.contains($0.id) }
            guard selectedMessages.count == selectedIDs.count else {
                throw WorktreeAnnotationRepositoryError.invalidState
            }
        case .allEligible(let excludedMessageIds):
            let excludedIDs = Set(excludedMessageIds.map(WorktreeAnnotationMessageID.init(rawValue:)))
            let knownIDs = Set(context.sessionDetail.threads.flatMap(\.messages).map(\.id))
            guard excludedIDs.isSubset(of: knownIDs) else {
                throw WorktreeAnnotationRepositoryError.notFound
            }
            selectedMessages = eligibleMessages.filter { !excludedIDs.contains($0.id) }
        }
        guard !selectedMessages.isEmpty else { throw WorktreeAnnotationRepositoryError.emptySelection }
        let comparisonLabel =
            try outputLabels.comparisonLabel
            ?? WorktreeAnnotationComparisonLabelProjector.project(
                context.sessionDetail.session.acceptedSourceFingerprint.reviewComparisonOrigin
            )
        let result = try await outputCoordinator.executeNew(
            .init(
                outputKind: outputKind,
                sessionDetail: context.sessionDetail,
                selectedMessages: try selectedMessages.map { message in
                    guard let savedRevision = message.savedRevision else {
                        throw WorktreeAnnotationRepositoryError.invalidState
                    }
                    return .init(messageID: message.id, expectedSavedRevision: savedRevision)
                },
                placementsByThreadID: context.placementsByThreadID,
                sessionLabel: outputLabels.sessionLabel,
                worktreeLabel: outputLabels.worktreeLabel,
                comparisonLabel: comparisonLabel
            )
        )
        return result.commandOutcome
    }

    func queryOutputCandidates(
        _ body: BridgeProductAnnotationCandidateQuery,
        surface: BridgeProductSurface
    ) async throws -> WorktreeAnnotationOutputCandidatePage {
        let cursor: WorktreeAnnotationOutputCandidateCursor? =
            switch body.cursor {
            case .start:
                nil
            case .after(let flatOrdinal, let messageID):
                .init(flatOrdinal: flatOrdinal, messageID: .init(rawValue: messageID))
            }
        return try await store.fetchOutputCandidates(
            sessionID: .init(rawValue: body.sessionId),
            expectedSessionRevision: body.expectedSessionRevision,
            cursor: cursor,
            limit: body.limit,
            contextID: contextID,
            surface: surface
        )
    }

    func executeOutputRepeat(
        attemptID: WorktreeAnnotationOutputAttemptID
    ) async throws -> WorktreeAnnotationOutputCommandOutcome {
        guard let outputCoordinator else {
            throw WorktreeAnnotationTransportAdapterError.outputUnavailable
        }
        return try await outputCoordinator.executeRepeat(sourceAttemptID: attemptID).commandOutcome
    }
}
