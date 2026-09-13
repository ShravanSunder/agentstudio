import AgentStudioInfrastructure
import Foundation

package enum SessionsEvidenceReducer {
    package static func currentTurnId(
        evidence: [SessionsEvidenceRecord],
        bindingGenerationId: UUID,
        activeSourceGenerationIds: Set<UUID>
    ) -> String? {
        let matchingRootEvidence = evidence.filter {
            $0.bindingGenerationId == bindingGenerationId
                && $0.subject == .root
                && $0.freshness == .live
                && $0.turnId != nil
                && activeSourceGenerationIds.contains($0.sourceGenerationId)
                && $0.kind.establishesTurnContext
        }.sorted(by: evidenceOrder)
        return matchingRootEvidence.last(where: { $0.origin == .reported })?.turnId
            ?? matchingRootEvidence.last(where: { $0.origin == .agentReported })?.turnId
            ?? matchingRootEvidence.last(where: { $0.origin == .estimated })?.turnId
    }

    package static func reduce(_ input: SessionsReductionInput) -> SessionsProjection {
        let sortedEvidence = input.evidence.sorted(by: evidenceOrder)
        let historicalEvidence = sortedEvidence.filter { evidence in
            evidence.conversationId != input.conversationId
                || evidence.bindingGenerationId != input.bindingGenerationId
                || evidence.freshness != .live
                || input.endedSourceGenerationIds.contains(evidence.sourceGenerationId)
                || (input.currentTurnId != nil && evidence.turnId != input.currentTurnId)
        }
        let currentEvidence = sortedEvidence.filter { evidence in
            !historicalEvidence.contains { $0.occurrenceId == evidence.occurrenceId }
        }
        let attention = reduceAttention(
            evidence: sortedEvidence.filter {
                $0.conversationId == input.conversationId
                    && $0.bindingGenerationId == input.bindingGenerationId
            },
            endedSourceGenerationIds: input.endedSourceGenerationIds,
            currentTurnId: input.currentTurnId
        )
        let results = reduceResults(evidence: currentEvidence)
        let stateEvidence = currentEvidence.filter { evidence in
            switch evidence.kind {
            case .activityStarted, .completed, .needsYouOpened:
                true
            case .aborted, .needsYouResolved:
                false
            }
        }
        let strongestOrigin = stateEvidence.map(\.origin).max { left, right in
            left.precedence < right.precedence
        }
        let strongestEvidence = stateEvidence.filter { $0.origin == strongestOrigin }
        let currentAttention = attention.current.filter { $0.origin == strongestOrigin }
        let rootCompletion = strongestEvidence.last { evidence in
            evidence.subject == .root && evidence.kind.isCompletion
                && !hasMatchingLaterAbort(for: evidence, in: currentEvidence)
        }
        let rootActivity = strongestEvidence.last { evidence in
            evidence.subject == .root && evidence.kind.isActivity
                && !hasMatchingLaterAbort(for: evidence, in: currentEvidence)
        }
        let state: SessionsAgentState
        if !currentAttention.isEmpty {
            state = .needsYou
        } else if rootCompletion != nil {
            state = .done
        } else if rootActivity != nil {
            state = .running
        } else {
            state = .unknown
        }

        return SessionsProjection(
            state: state,
            stateOrigin: state == .unknown ? nil : strongestOrigin,
            currentAttention: attention.current,
            staleAttention: attention.stale,
            results: results,
            historicalOccurrenceIds: historicalEvidence.map(\.occurrenceId)
        )
    }

    package static func reduce(
        mutation: SessionsMutation,
        against context: SessionsRepositoryContext
    ) throws -> SessionsRepositoryReduction {
        switch mutation {
        case .bind(let bindMutation):
            try reduceBind(bindMutation, context: context)
        case .message(let messageMutation):
            try reduceMessage(messageMutation, context: context)
        case .recordEvidence(let evidenceMutation):
            try reduceEvidence(evidenceMutation, context: context)
        case .deliberateNeedsYou(let attentionMutation):
            try reduceDeliberateNeedsYou(attentionMutation, context: context)
        case .clearDeliberateNeedsYou(let clearMutation):
            try reduceClearDeliberateNeedsYou(clearMutation, context: context)
        case .deliberateDone(let doneMutation):
            try reduceDeliberateDone(doneMutation, context: context)
        case .sourceEnded(let sourceEndMutation):
            try reduceSourceEnd(sourceEndMutation, context: context)
        case .acknowledgeMessage(let acknowledgmentMutation):
            try reduceAcknowledgment(acknowledgmentMutation, context: context)
        case .recordLiveLoss(let lossMutation):
            reduceLiveLoss(lossMutation, context: context)
        case .prepareForLaunch(let launchDate):
            reducePrepareForLaunch(at: launchDate, context: context)
        }
    }
}

extension SessionsEvidenceKind {
    fileprivate var establishesTurnContext: Bool {
        switch self {
        case .activityStarted, .completed, .aborted: true
        case .needsYouOpened, .needsYouResolved: false
        }
    }

    fileprivate var isActivity: Bool {
        if case .activityStarted = self { return true }
        return false
    }

    fileprivate var isCompletion: Bool {
        if case .completed = self { return true }
        return false
    }
}

extension SessionsEvidenceReducer {
    fileprivate struct ReducedAttention {
        var current: [SessionsAttentionProjection]
        var stale: [SessionsAttentionProjection]
    }

    fileprivate static func evidenceOrder(_ left: SessionsEvidenceRecord, _ right: SessionsEvidenceRecord) -> Bool {
        if left.occurredAt != right.occurredAt { return left.occurredAt < right.occurredAt }
        return left.occurrenceId.uuidString < right.occurrenceId.uuidString
    }

    fileprivate static func reduceAttention(
        evidence: [SessionsEvidenceRecord],
        endedSourceGenerationIds: Set<UUID>,
        currentTurnId: String?
    ) -> ReducedAttention {
        var openAttention: [String: SessionsAttentionProjection] = [:]
        for record in evidence.sorted(by: evidenceOrder) {
            switch record.kind {
            case .needsYouOpened(let requestId, let explanation):
                let key = attentionKey(
                    sourceGenerationId: record.sourceGenerationId,
                    turnId: record.turnId,
                    subject: record.subject,
                    requestId: requestId
                )
                openAttention[key] = SessionsAttentionProjection(
                    id: record.occurrenceId,
                    requestId: requestId,
                    explanation: explanation,
                    sourceGenerationId: record.sourceGenerationId,
                    turnId: record.turnId,
                    subject: record.subject,
                    origin: record.origin,
                    freshness: record.freshness,
                    disposition: .current,
                    openedOccurrenceId: record.occurrenceId,
                    openedAt: record.occurredAt
                )
            case .needsYouResolved(let requestId):
                let key = attentionKey(
                    sourceGenerationId: record.sourceGenerationId,
                    turnId: record.turnId,
                    subject: record.subject,
                    requestId: requestId
                )
                openAttention.removeValue(forKey: key)
            case .activityStarted, .completed, .aborted:
                break
            }
        }

        var current: [SessionsAttentionProjection] = []
        var stale: [SessionsAttentionProjection] = []
        for projection in openAttention.values {
            guard endedSourceGenerationIds.contains(projection.sourceGenerationId) else {
                if projection.freshness == .live,
                    currentTurnId == nil || projection.turnId == currentTurnId
                {
                    current.append(projection)
                }
                continue
            }
            if projection.origin == .reported {
                stale.append(
                    SessionsAttentionProjection(
                        id: projection.id,
                        requestId: projection.requestId,
                        explanation: projection.explanation,
                        sourceGenerationId: projection.sourceGenerationId,
                        turnId: projection.turnId,
                        subject: projection.subject,
                        origin: projection.origin,
                        freshness: projection.freshness,
                        disposition: .stale,
                        openedOccurrenceId: projection.openedOccurrenceId,
                        openedAt: projection.openedAt
                    )
                )
            }
        }
        current.sort { $0.openedAt < $1.openedAt }
        stale.sort { $0.openedAt < $1.openedAt }
        return ReducedAttention(current: current, stale: stale)
    }

    fileprivate static func reduceResults(evidence: [SessionsEvidenceRecord]) -> [SessionsResultProjection] {
        var results: [String: SessionsResultProjection] = [:]
        for record in evidence.sorted(by: evidenceOrder) {
            guard case .completed = record.kind, let turnId = record.turnId else { continue }
            let key = "\(turnId):\(record.subject.storageKey)"
            if let prior = results[key], prior.origin.precedence > record.origin.precedence { continue }
            results[key] = SessionsResultProjection(
                id: record.occurrenceId,
                turnId: turnId,
                subject: record.subject,
                completionOccurrenceId: record.occurrenceId,
                origin: record.origin,
                freshness: record.freshness
            )
        }
        return results.values.sorted { $0.completionOccurrenceId.uuidString < $1.completionOccurrenceId.uuidString }
    }

    fileprivate static func hasMatchingLaterAbort(
        for evidence: SessionsEvidenceRecord,
        in records: [SessionsEvidenceRecord]
    ) -> Bool {
        records.contains { candidate in
            candidate.occurredAt >= evidence.occurredAt
                && candidate.sourceGenerationId == evidence.sourceGenerationId
                && candidate.turnId == evidence.turnId
                && candidate.subject == evidence.subject
                && candidate.kind == .aborted
        }
    }

    fileprivate static func attentionKey(
        sourceGenerationId: UUID,
        turnId: String?,
        subject: SessionsEvidenceSubject,
        requestId: String
    ) -> String {
        "\(sourceGenerationId.uuidString):\(turnId ?? "none"):\(subject.storageKey):\(requestId)"
    }
}
