import AgentStudioInfrastructure
import Foundation

extension SessionsEvidenceReducer {
    static func reduceDeliberateDone(
        _ mutation: SessionsDeliberateDoneMutation,
        context: SessionsRepositoryContext
    ) throws -> SessionsRepositoryReduction {
        let binding = try requireActiveBinding(paneId: mutation.paneId, context: context)
        let source = context.source(sourceGenerationId: binding.sourceGenerationId)
        let turnId = currentReportingTurnId(binding: binding, context: context)
        let existingResult = context.results.first {
            $0.bindingGenerationId == binding.bindingGenerationId
                && $0.turnId == turnId && $0.subject == .root
        }
        let occurrenceId = UUIDv7.generate()
        let evidence = SessionsEvidenceRecord(
            occurrenceId: occurrenceId,
            conversationId: binding.conversationId,
            bindingGenerationId: binding.bindingGenerationId,
            sourceGenerationId: binding.sourceGenerationId,
            turnId: turnId,
            subject: .root,
            kind: .completed,
            origin: .agentReported,
            freshness: .live,
            occurredAt: mutation.reportedAt
        )
        let result = SessionsResultRecord(
            id: existingResult?.id ?? UUIDv7.generate(),
            conversationId: binding.conversationId,
            bindingGenerationId: binding.bindingGenerationId,
            sourceGenerationId: binding.sourceGenerationId,
            turnId: turnId,
            subject: .root,
            completionOccurrenceId: occurrenceId,
            origin: .agentReported,
            freshness: .live,
            disposition: existingResult?.disposition ?? .unseen,
            seenAt: existingResult?.seenAt,
            createdAt: existingResult?.createdAt ?? mutation.reportedAt,
            updatedAt: mutation.reportedAt
        )
        return SessionsRepositoryReduction(
            evidenceChanges: [evidence],
            resultChanges: [result],
            outcome: .resultRecorded(resultId: result.id, occurrenceId: occurrenceId)
        )
    }

    static func reduceSourceEnd(
        _ mutation: SessionsSourceEndMutation,
        context: SessionsRepositoryContext
    ) throws -> SessionsRepositoryReduction {
        guard let source = context.source(sourceGenerationId: mutation.sourceGenerationId),
            let binding = context.binding(sourceGenerationId: mutation.sourceGenerationId),
            binding.paneId == mutation.paneId
        else {
            throw SessionsRepositoryError.sourceNotFound(mutation.sourceGenerationId)
        }
        guard source.status == .active else {
            return SessionsRepositoryReduction(
                outcome: .sourceEnded(sourceGenerationId: mutation.sourceGenerationId)
            )
        }
        let endedSource = replacing(source, status: .ended, endedAt: mutation.endedAt)
        let endedBinding = replacing(binding, status: .ended, endedAt: mutation.endedAt)
        let staleAttention = context.attention.filter {
            $0.bindingGenerationId == binding.bindingGenerationId && $0.disposition == .current
        }.map { attention in
            replacing(attention, disposition: .stale, resolvedAt: mutation.endedAt)
        }
        return SessionsRepositoryReduction(
            bindingChanges: [endedBinding],
            sourceChanges: [endedSource],
            attentionChanges: staleAttention,
            outcome: .sourceEnded(sourceGenerationId: mutation.sourceGenerationId)
        )
    }

    static func reduceAcknowledgment(
        _ mutation: SessionsMessageAcknowledgmentMutation,
        context: SessionsRepositoryContext
    ) throws -> SessionsRepositoryReduction {
        guard let message = context.messages.first(where: { $0.occurrenceId == mutation.occurrenceId }) else {
            throw SessionsRepositoryError.messageNotFound(mutation.occurrenceId)
        }
        guard message.disposition == .unseen else {
            return SessionsRepositoryReduction(
                outcome: .messageAcknowledged(occurrenceId: mutation.occurrenceId, changed: false)
            )
        }
        return SessionsRepositoryReduction(
            messageSeenChanges: [
                SessionsMessageSeenChange(
                    occurrenceId: mutation.occurrenceId,
                    acknowledgedAt: mutation.acknowledgedAt
                )
            ],
            outcome: .messageAcknowledged(occurrenceId: mutation.occurrenceId, changed: true)
        )
    }

    static func reducePrepareForLaunch(
        at launchDate: Date,
        context: SessionsRepositoryContext
    ) -> SessionsRepositoryReduction {
        let activeSources = context.sources.filter { $0.status == .active }
        let activeBindingIds = Set(activeSources.map(\.bindingGenerationId))
        let endedSources = activeSources.map { replacing($0, status: .ended, endedAt: launchDate) }
        let endedBindings = context.bindings.filter {
            activeBindingIds.contains($0.bindingGenerationId) && $0.status == .active
        }.map { replacing($0, status: .ended, endedAt: launchDate) }
        let staleAttention = context.attention.filter {
            activeBindingIds.contains($0.bindingGenerationId) && $0.disposition == .current
        }.map { replacing($0, disposition: .stale, resolvedAt: launchDate) }
        return SessionsRepositoryReduction(
            bindingChanges: endedBindings,
            sourceChanges: endedSources,
            attentionChanges: staleAttention,
            outcome: .launchPrepared(activeSourcesEnded: activeSources.count)
        )
    }

    static func reduceLiveLoss(
        _ mutation: SessionsLiveLossMutation,
        context: SessionsRepositoryContext
    ) -> SessionsRepositoryReduction {
        let lossId = UUIDv7.generate()
        return SessionsRepositoryReduction(
            lossChanges: [
                SessionsLossRecord(
                    id: lossId,
                    paneId: mutation.paneId,
                    conversationId: context.currentBinding?.conversationId,
                    bindingGenerationId: context.currentBinding?.bindingGenerationId,
                    sourceGenerationId: context.currentBinding?.sourceGenerationId,
                    providerIdentifier: context.currentBinding?.providerIdentifier,
                    eventKind: mutation.eventKind,
                    reason: mutation.reason,
                    occurredAt: mutation.occurredAt
                )
            ],
            outcome: .lossRecorded(id: lossId)
        )
    }

    static func applyEvidenceProjection(
        _ evidence: SessionsEvidenceRecord,
        source: SessionsSourceRecord?,
        context: SessionsRepositoryContext,
        reduction: inout SessionsRepositoryReduction
    ) {
        switch evidence.kind {
        case .needsYouOpened(let requestId, let explanation):
            let existing = context.attention.first {
                $0.bindingGenerationId == evidence.bindingGenerationId
                    && $0.sourceGenerationId == evidence.sourceGenerationId
                    && $0.turnId == evidence.turnId
                    && $0.subject == evidence.subject
                    && $0.requestId == requestId
            }
            reduction.attentionChanges.append(
                SessionsStoredAttentionRecord(
                    id: existing?.id ?? UUIDv7.generate(),
                    conversationId: evidence.conversationId,
                    bindingGenerationId: evidence.bindingGenerationId,
                    sourceId: source?.id,
                    sourceGenerationId: evidence.sourceGenerationId,
                    sourceKind: "provider",
                    turnId: evidence.turnId,
                    subject: evidence.subject,
                    requestId: requestId,
                    attentionKind: "question",
                    origin: evidence.origin,
                    freshness: evidence.freshness,
                    explanation: explanation,
                    disposition: .current,
                    openedOccurrenceId: evidence.occurrenceId,
                    resolutionOccurrenceId: nil,
                    openedAt: evidence.occurredAt,
                    resolvedAt: nil
                )
            )
        case .needsYouResolved(let requestId):
            guard
                let existing = context.attention.first(where: {
                    $0.bindingGenerationId == evidence.bindingGenerationId
                        && $0.sourceGenerationId == evidence.sourceGenerationId
                        && $0.turnId == evidence.turnId
                        && $0.subject == evidence.subject
                        && $0.requestId == requestId && $0.disposition == .current
                })
            else { return }
            reduction.attentionChanges.append(
                SessionsStoredAttentionRecord(
                    id: existing.id,
                    conversationId: existing.conversationId,
                    bindingGenerationId: existing.bindingGenerationId,
                    sourceId: existing.sourceId,
                    sourceGenerationId: existing.sourceGenerationId,
                    sourceKind: existing.sourceKind,
                    turnId: existing.turnId,
                    subject: existing.subject,
                    requestId: existing.requestId,
                    attentionKind: existing.attentionKind,
                    origin: existing.origin,
                    freshness: existing.freshness,
                    explanation: existing.explanation,
                    disposition: .resolved,
                    openedOccurrenceId: existing.openedOccurrenceId,
                    resolutionOccurrenceId: evidence.occurrenceId,
                    openedAt: existing.openedAt,
                    resolvedAt: evidence.occurredAt
                )
            )
        case .completed:
            guard let turnId = evidence.turnId else { return }
            let existing = context.results.first {
                $0.bindingGenerationId == evidence.bindingGenerationId
                    && $0.turnId == turnId && $0.subject == evidence.subject
            }
            guard existing == nil || existing!.origin.precedence <= evidence.origin.precedence else { return }
            reduction.resultChanges.append(
                SessionsResultRecord(
                    id: existing?.id ?? UUIDv7.generate(),
                    conversationId: evidence.conversationId,
                    bindingGenerationId: evidence.bindingGenerationId,
                    sourceGenerationId: evidence.sourceGenerationId,
                    turnId: turnId,
                    subject: evidence.subject,
                    completionOccurrenceId: evidence.occurrenceId,
                    origin: evidence.origin,
                    freshness: evidence.freshness,
                    disposition: existing?.disposition ?? .unseen,
                    seenAt: existing?.seenAt,
                    createdAt: existing?.createdAt ?? evidence.occurredAt,
                    updatedAt: evidence.occurredAt
                )
            )
        case .activityStarted, .aborted:
            break
        }
    }

    static func requireActiveBinding(
        paneId: UUID,
        context: SessionsRepositoryContext
    ) throws -> SessionsBindingRecord {
        guard let binding = context.currentBinding, binding.paneId == paneId, binding.status == .active else {
            throw SessionsRepositoryError.bindingRequired(paneId)
        }
        return binding
    }

    static func deliberateTurnId(bindingGenerationId: UUID) -> String {
        "deliberate:\(bindingGenerationId.uuidString)"
    }

    static func currentReportingTurnId(
        binding: SessionsBindingRecord,
        context: SessionsRepositoryContext
    ) -> String {
        let activeSourceGenerationIds = Set(
            context.sources.filter { $0.status == .active }.map(\.sourceGenerationId)
        )
        return Self.currentTurnId(
            evidence: context.evidence,
            bindingGenerationId: binding.bindingGenerationId,
            activeSourceGenerationIds: activeSourceGenerationIds
        ) ?? deliberateTurnId(bindingGenerationId: binding.bindingGenerationId)
    }

    static func evidence(
        from attention: SessionsStoredAttentionRecord,
        kind: SessionsEvidenceKind
    ) -> SessionsEvidenceRecord {
        SessionsEvidenceRecord(
            occurrenceId: attention.openedOccurrenceId,
            conversationId: attention.conversationId,
            bindingGenerationId: attention.bindingGenerationId,
            sourceGenerationId: attention.sourceGenerationId,
            turnId: attention.turnId,
            subject: attention.subject,
            kind: kind,
            origin: attention.origin,
            freshness: attention.freshness,
            occurredAt: attention.openedAt
        )
    }

    static func replacing(
        _ binding: SessionsBindingRecord,
        status: SessionsBindingStatus,
        endedAt: Date
    ) -> SessionsBindingRecord {
        SessionsBindingRecord(
            bindingGenerationId: binding.bindingGenerationId,
            paneId: binding.paneId,
            conversationId: binding.conversationId,
            providerIdentifier: binding.providerIdentifier,
            providerConversationId: binding.providerConversationId,
            sourceGenerationId: binding.sourceGenerationId,
            transitionOccurrenceId: binding.transitionOccurrenceId,
            origin: binding.origin,
            status: status,
            startedAt: binding.startedAt,
            endedAt: endedAt
        )
    }

    static func replacing(
        _ source: SessionsSourceRecord,
        status: SessionsSourceStatus,
        endedAt: Date
    ) -> SessionsSourceRecord {
        SessionsSourceRecord(
            id: source.id,
            bindingGenerationId: source.bindingGenerationId,
            sourceIdentifier: source.sourceIdentifier,
            sourceGenerationId: source.sourceGenerationId,
            providerIdentifier: source.providerIdentifier,
            providerVersion: source.providerVersion,
            providerMode: source.providerMode,
            qualification: source.qualification,
            status: status,
            lastCursor: source.lastCursor,
            startedAt: source.startedAt,
            endedAt: endedAt
        )
    }

    static func replacing(
        _ attention: SessionsStoredAttentionRecord,
        disposition: SessionsAttentionDisposition,
        resolvedAt: Date
    ) -> SessionsStoredAttentionRecord {
        SessionsStoredAttentionRecord(
            id: attention.id,
            conversationId: attention.conversationId,
            bindingGenerationId: attention.bindingGenerationId,
            sourceId: attention.sourceId,
            sourceGenerationId: attention.sourceGenerationId,
            sourceKind: attention.sourceKind,
            turnId: attention.turnId,
            subject: attention.subject,
            requestId: attention.requestId,
            attentionKind: attention.attentionKind,
            origin: attention.origin,
            freshness: attention.freshness,
            explanation: attention.explanation,
            disposition: disposition,
            openedOccurrenceId: attention.openedOccurrenceId,
            resolutionOccurrenceId: attention.resolutionOccurrenceId,
            openedAt: attention.openedAt,
            resolvedAt: resolvedAt
        )
    }
}
