import AgentStudioInfrastructure
import Foundation

extension SessionsEvidenceReducer {
    static func reduceBind(
        _ mutation: SessionsBindMutation,
        context: SessionsRepositoryContext
    ) throws -> SessionsRepositoryReduction {
        if let currentBinding = context.currentBinding,
            currentBinding.status == .active,
            currentBinding.providerIdentifier == mutation.providerIdentifier,
            currentBinding.providerConversationId == mutation.providerConversationId,
            currentBinding.sourceGenerationId == mutation.sourceGenerationId
        {
            return SessionsRepositoryReduction(outcome: .binding(.unchanged(currentBinding)))
        }
        if let historicalReduction = historicalBindReduction(mutation, context: context) {
            return historicalReduction
        }
        guard let admittedOrigin = mutation.transition.admittedOrigin else {
            throw SessionsRepositoryError.bindingConflict(mutation.paneId)
        }

        let existingConversation = context.matchingConversation
        let conversationId = existingConversation?.id ?? UUIDv7.generate()
        let conversation = SessionsConversationRecord(
            id: conversationId,
            providerIdentifier: mutation.providerIdentifier,
            providerConversationId: mutation.providerConversationId,
            createdAt: existingConversation?.createdAt ?? mutation.reportedAt,
            lastReportedAt: mutation.reportedAt
        )
        let newBinding = SessionsBindingRecord(
            bindingGenerationId: UUIDv7.generate(),
            paneId: mutation.paneId,
            conversationId: conversationId,
            providerIdentifier: mutation.providerIdentifier,
            providerConversationId: mutation.providerConversationId,
            sourceGenerationId: mutation.sourceGenerationId,
            transitionOccurrenceId: mutation.transition.occurrenceId,
            origin: admittedOrigin,
            status: .active,
            startedAt: mutation.reportedAt,
            endedAt: nil
        )
        let newSource = SessionsSourceRecord(
            id: UUIDv7.generate(),
            bindingGenerationId: newBinding.bindingGenerationId,
            sourceIdentifier: mutation.sourceId,
            sourceGenerationId: mutation.sourceGenerationId,
            providerIdentifier: mutation.providerIdentifier,
            providerVersion: mutation.providerVersion,
            providerMode: mutation.providerMode,
            qualification: "qualified",
            status: .active,
            lastCursor: nil,
            startedAt: mutation.reportedAt,
            endedAt: nil
        )
        var bindingChanges = [newBinding]
        var sourceChanges = [newSource]
        let outcome: SessionsMutationOutcome
        if let currentBinding = context.currentBinding, currentBinding.status == .active {
            let endedBinding = SessionsBindingRecord(
                bindingGenerationId: currentBinding.bindingGenerationId,
                paneId: currentBinding.paneId,
                conversationId: currentBinding.conversationId,
                providerIdentifier: currentBinding.providerIdentifier,
                providerConversationId: currentBinding.providerConversationId,
                sourceGenerationId: currentBinding.sourceGenerationId,
                transitionOccurrenceId: currentBinding.transitionOccurrenceId,
                origin: currentBinding.origin,
                status: .ended,
                startedAt: currentBinding.startedAt,
                endedAt: mutation.reportedAt
            )
            bindingChanges.insert(endedBinding, at: 0)
            sourceChanges.insert(
                contentsOf: context.sources.filter { $0.bindingGenerationId == currentBinding.bindingGenerationId }
                    .map { source in
                        SessionsSourceRecord(
                            id: source.id,
                            bindingGenerationId: source.bindingGenerationId,
                            sourceIdentifier: source.sourceIdentifier,
                            sourceGenerationId: source.sourceGenerationId,
                            providerIdentifier: source.providerIdentifier,
                            providerVersion: source.providerVersion,
                            providerMode: source.providerMode,
                            qualification: source.qualification,
                            status: .ended,
                            lastCursor: source.lastCursor,
                            startedAt: source.startedAt,
                            endedAt: mutation.reportedAt
                        )
                    },
                at: 0
            )
            outcome = .binding(.replaced(endedBinding, newBinding))
        } else {
            outcome = .binding(.established(newBinding))
        }
        return SessionsRepositoryReduction(
            conversationChanges: [conversation],
            bindingChanges: bindingChanges,
            sourceChanges: sourceChanges,
            outcome: outcome
        )
    }

    private static func historicalBindReduction(
        _ mutation: SessionsBindMutation,
        context: SessionsRepositoryContext
    ) -> SessionsRepositoryReduction? {
        let isNonLiveProviderBind: Bool
        if case .qualifiedSessionStart = mutation.transition {
            isNonLiveProviderBind = mutation.freshness != .live
        } else {
            isNonLiveProviderBind = false
        }
        let isKnownGeneration = context.sources.contains {
            $0.sourceGenerationId == mutation.sourceGenerationId
        }
        guard isNonLiveProviderBind || isKnownGeneration else { return nil }
        return SessionsRepositoryReduction(outcome: .historical(occurrenceId: mutation.transition.occurrenceId))
    }

    static func reduceMessage(
        _ mutation: SessionsMessageMutation,
        context: SessionsRepositoryContext
    ) throws -> SessionsRepositoryReduction {
        let attribution: SessionsMessageAttribution
        let conversationId: UUID?
        let bindingGenerationId: UUID?
        let sourceGenerationId: UUID?
        switch mutation.context {
        case .currentPaneBinding(let paneId):
            guard let binding = context.currentBinding, binding.paneId == paneId, binding.status == .active else {
                throw SessionsRepositoryError.bindingRequired(paneId)
            }
            attribution = .attributed
            conversationId = binding.conversationId
            bindingGenerationId = binding.bindingGenerationId
            sourceGenerationId = binding.sourceGenerationId
        case .sourceGeneration(let paneId, let requestedSourceGenerationId):
            guard let binding = context.binding(sourceGenerationId: requestedSourceGenerationId),
                binding.paneId == paneId
            else {
                throw SessionsRepositoryError.sourceNotFound(requestedSourceGenerationId)
            }
            attribution = .attributed
            conversationId = binding.conversationId
            bindingGenerationId = binding.bindingGenerationId
            sourceGenerationId = requestedSourceGenerationId
        case .unattributed:
            attribution = .unattributed
            conversationId = nil
            bindingGenerationId = nil
            sourceGenerationId = nil
        }
        let occurrenceId = UUIDv7.generate()
        let message = SessionsMessageRecord(
            occurrenceId: occurrenceId,
            paneId: mutation.context.paneId,
            conversationId: conversationId,
            bindingGenerationId: bindingGenerationId,
            sourceGenerationId: sourceGenerationId,
            text: mutation.text,
            attribution: attribution,
            freshness: mutation.freshness,
            disposition: .unseen,
            reportedAt: mutation.receivedAt
        )
        return SessionsRepositoryReduction(
            messageChanges: [message],
            outcome: .messageSaved(occurrenceId: occurrenceId, attribution: attribution)
        )
    }

    static func reduceEvidence(
        _ mutation: SessionsEvidenceMutation,
        context: SessionsRepositoryContext
    ) throws -> SessionsRepositoryReduction {
        guard case .sourceGeneration(let paneId, let sourceGenerationId) = mutation.context,
            let binding = context.binding(sourceGenerationId: sourceGenerationId),
            binding.paneId == paneId
        else {
            throw SessionsRepositoryError.sourceNotFound(mutation.context.sourceGenerationIdForError)
        }
        let source = context.source(sourceGenerationId: sourceGenerationId)
        let isCurrent =
            binding.status == .active && source?.status == .active
            && context.currentBinding?.bindingGenerationId == binding.bindingGenerationId
            && mutation.freshness == .live
        let freshness: SessionsEvidenceFreshness = isCurrent ? .live : .historical
        let evidence = SessionsEvidenceRecord(
            occurrenceId: mutation.occurrenceId,
            conversationId: binding.conversationId,
            bindingGenerationId: binding.bindingGenerationId,
            sourceGenerationId: sourceGenerationId,
            turnId: mutation.turnId,
            subject: mutation.subject,
            kind: mutation.kind,
            origin: mutation.origin,
            freshness: freshness,
            occurredAt: mutation.occurredAt
        )
        let sourceChanges =
            source.flatMap { source in
                mutation.sourceCursor.map { cursor in
                    SessionsSourceRecord(
                        id: source.id,
                        bindingGenerationId: source.bindingGenerationId,
                        sourceIdentifier: source.sourceIdentifier,
                        sourceGenerationId: source.sourceGenerationId,
                        providerIdentifier: source.providerIdentifier,
                        providerVersion: source.providerVersion,
                        providerMode: source.providerMode,
                        qualification: source.qualification,
                        status: source.status,
                        lastCursor: cursor,
                        startedAt: source.startedAt,
                        endedAt: source.endedAt
                    )
                }
            }.map { [$0] } ?? []
        guard isCurrent else {
            return SessionsRepositoryReduction(
                sourceChanges: sourceChanges,
                evidenceChanges: [evidence],
                outcome: .historical(occurrenceId: mutation.occurrenceId)
            )
        }
        var reduction = SessionsRepositoryReduction(
            sourceChanges: sourceChanges,
            evidenceChanges: [evidence],
            outcome: .evidenceRecorded(occurrenceId: mutation.occurrenceId)
        )
        applyEvidenceProjection(evidence, source: source, context: context, reduction: &reduction)
        return reduction
    }

    static func reduceDeliberateNeedsYou(
        _ mutation: SessionsDeliberateNeedsYouMutation,
        context: SessionsRepositoryContext
    ) throws -> SessionsRepositoryReduction {
        switch try deliberateReportTarget(
            paneId: mutation.paneId,
            freshness: mutation.freshness,
            context: context
        ) {
        case .liveBinding(let binding):
            return liveDeliberateNeedsYou(mutation, binding: binding, context: context)
        case .endedBindingHistory(let binding):
            return historicalDeliberateNeedsYou(mutation, binding: binding, context: context)
        }
    }

    /// A late needs-you keeps the report's request identity and explanation but
    /// enters already stale against the binding that ended: the snapshot derives
    /// attention from live evidence on the current binding, so nothing here can
    /// raise attention on a pane that has since moved on.
    private static func historicalDeliberateNeedsYou(
        _ mutation: SessionsDeliberateNeedsYouMutation,
        binding: SessionsBindingRecord,
        context: SessionsRepositoryContext
    ) -> SessionsRepositoryReduction {
        let source = context.source(sourceGenerationId: binding.sourceGenerationId)
        let occurrenceId = UUIDv7.generate()
        let attentionId = UUIDv7.generate()
        let attention = SessionsStoredAttentionRecord(
            id: attentionId,
            conversationId: binding.conversationId,
            bindingGenerationId: binding.bindingGenerationId,
            sourceId: source?.id,
            sourceGenerationId: binding.sourceGenerationId,
            sourceKind: "deliberate",
            turnId: deliberateTurnId(bindingGenerationId: binding.bindingGenerationId),
            subject: .root,
            requestId: attentionId.uuidString,
            attentionKind: "deliberate",
            origin: .agentReported,
            freshness: mutation.freshness,
            explanation: mutation.explanation,
            disposition: .stale,
            openedOccurrenceId: occurrenceId,
            resolutionOccurrenceId: nil,
            openedAt: mutation.reportedAt,
            resolvedAt: mutation.reportedAt
        )
        let evidence = evidence(
            from: attention,
            kind: .needsYouOpened(requestId: attention.requestId, explanation: mutation.explanation)
        )
        return SessionsRepositoryReduction(
            evidenceChanges: [evidence],
            attentionChanges: [attention],
            outcome: .historical(occurrenceId: occurrenceId)
        )
    }

    private static func liveDeliberateNeedsYou(
        _ mutation: SessionsDeliberateNeedsYouMutation,
        binding: SessionsBindingRecord,
        context: SessionsRepositoryContext
    ) -> SessionsRepositoryReduction {
        let source = context.source(sourceGenerationId: binding.sourceGenerationId)
        let reportingTurnId = currentReportingTurnId(binding: binding, context: context)
        let prior = context.attention.first {
            $0.bindingGenerationId == binding.bindingGenerationId
                && $0.sourceKind == "deliberate" && $0.disposition == .current
                && $0.turnId == reportingTurnId && $0.subject == .root
        }
        let occurrenceId = UUIDv7.generate()
        let attentionId = prior?.id ?? UUIDv7.generate()
        let requestId = prior?.requestId ?? attentionId.uuidString
        let attention = SessionsStoredAttentionRecord(
            id: attentionId,
            conversationId: binding.conversationId,
            bindingGenerationId: binding.bindingGenerationId,
            sourceId: source?.id,
            sourceGenerationId: binding.sourceGenerationId,
            sourceKind: "deliberate",
            turnId: reportingTurnId,
            subject: .root,
            requestId: requestId,
            attentionKind: "deliberate",
            origin: .agentReported,
            freshness: .live,
            explanation: mutation.explanation,
            disposition: .current,
            openedOccurrenceId: occurrenceId,
            resolutionOccurrenceId: nil,
            openedAt: mutation.reportedAt,
            resolvedAt: nil
        )
        let evidence = evidence(
            from: attention, kind: .needsYouOpened(requestId: requestId, explanation: mutation.explanation))
        return SessionsRepositoryReduction(
            evidenceChanges: [evidence],
            attentionChanges: [attention],
            outcome: .attentionRecorded(requestId: requestId, occurrenceId: occurrenceId)
        )
    }

    static func reduceClearDeliberateNeedsYou(
        _ mutation: SessionsClearDeliberateNeedsYouMutation,
        context: SessionsRepositoryContext
    ) throws -> SessionsRepositoryReduction {
        let binding = try requireActiveBinding(paneId: mutation.paneId, context: context)
        guard
            let prior = context.attention.first(where: {
                $0.bindingGenerationId == binding.bindingGenerationId
                    && $0.sourceKind == "deliberate" && $0.disposition == .current
            })
        else {
            throw SessionsRepositoryError.attentionNotFound(mutation.paneId)
        }
        let occurrenceId = UUIDv7.generate()
        let resolved = SessionsStoredAttentionRecord(
            id: prior.id,
            conversationId: prior.conversationId,
            bindingGenerationId: prior.bindingGenerationId,
            sourceId: prior.sourceId,
            sourceGenerationId: prior.sourceGenerationId,
            sourceKind: prior.sourceKind,
            turnId: prior.turnId,
            subject: prior.subject,
            requestId: prior.requestId,
            attentionKind: prior.attentionKind,
            origin: prior.origin,
            freshness: prior.freshness,
            explanation: prior.explanation,
            disposition: .resolved,
            openedOccurrenceId: prior.openedOccurrenceId,
            resolutionOccurrenceId: occurrenceId,
            openedAt: prior.openedAt,
            resolvedAt: mutation.clearedAt
        )
        let evidence = SessionsEvidenceRecord(
            occurrenceId: occurrenceId,
            conversationId: prior.conversationId,
            bindingGenerationId: prior.bindingGenerationId,
            sourceGenerationId: prior.sourceGenerationId,
            turnId: prior.turnId,
            subject: prior.subject,
            kind: .needsYouResolved(requestId: prior.requestId),
            origin: .agentReported,
            freshness: .live,
            occurredAt: mutation.clearedAt
        )
        return SessionsRepositoryReduction(
            evidenceChanges: [evidence],
            attentionChanges: [resolved],
            outcome: .attentionCleared(requestId: prior.requestId)
        )
    }
}

extension SessionsReportContext {
    fileprivate var sourceGenerationIdForError: UUID {
        if case .sourceGeneration(_, let sourceGenerationId) = self { return sourceGenerationId }
        return paneId
    }
}
