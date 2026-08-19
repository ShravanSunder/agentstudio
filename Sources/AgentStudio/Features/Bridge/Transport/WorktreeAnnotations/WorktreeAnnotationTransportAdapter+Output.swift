import Foundation

extension WorktreeAnnotationTransportAdapter {
    func executeOutputPreparation(
        _ assembled: WorktreeAnnotationAssembledOutputSelection,
        surface: BridgeProductSurface,
        productAdmission: BridgeProductAdmissionContext
    ) async throws -> WorktreeAnnotationOutputCommandOutcome {
        guard let outputCoordinator, let outputLabels else {
            throw WorktreeAnnotationTransportAdapterError.outputUnavailable
        }
        let sessionID = WorktreeAnnotationSessionID(rawValue: assembled.sessionID)
        let sessionDetail = try await store.outputSessionDetail(sessionID: sessionID)
        let sourceSnapshot = WorktreeAnnotationServiceActor.sourceRefreshSnapshot(
            from: sessionDetail
        )
        let sourceCapture = try await sourceResolver.refresh(
            surface,
            productAdmission,
            sourceSnapshot.requirements
        )
        let sourceEvaluation = try WorktreeAnnotationSourceEvaluator.evaluate(
            .init(
                session: sessionDetail.session,
                threads: sessionDetail.threads.map(\.thread),
                surface: surface,
                sourceEpoch: contextID,
                currentFingerprint: sourceCapture.fingerprint,
                material: sourceCapture.material
            )
        )
        let outputKind: WorktreeAnnotationOutputKind =
            switch assembled.outputKind {
            case .clipboardMarkdown: .clipboardMarkdown
            case .jsonFile: .jsonFile
            }
        let eligibleMessages = sessionDetail.threads.flatMap(\.messages).filter {
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
            let knownIDs = Set(sessionDetail.threads.flatMap(\.messages).map(\.id))
            guard excludedIDs.isSubset(of: knownIDs) else {
                throw WorktreeAnnotationRepositoryError.notFound
            }
            selectedMessages = eligibleMessages.filter { !excludedIDs.contains($0.id) }
        }
        guard !selectedMessages.isEmpty else { throw WorktreeAnnotationRepositoryError.emptySelection }
        let comparisonLabel =
            try outputLabels.comparisonLabel
            ?? WorktreeAnnotationComparisonLabelProjector.project(
                sessionDetail.session.acceptedSourceFingerprint.reviewComparisonOrigin
            )
        let result = try await outputCoordinator.executeNew(
            .init(
                outputKind: outputKind,
                sessionDetail: sessionDetail,
                selectedMessages: try selectedMessages.map { message in
                    guard let savedRevision = message.savedRevision else {
                        throw WorktreeAnnotationRepositoryError.invalidState
                    }
                    return .init(messageID: message.id, expectedSavedRevision: savedRevision)
                },
                placementsByThreadID: sourceEvaluation.placements,
                sessionLabel: outputLabels.sessionLabel,
                worktreeLabel: outputLabels.worktreeLabel,
                comparisonLabel: comparisonLabel
            )
        )
        return result.commandOutcome
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
