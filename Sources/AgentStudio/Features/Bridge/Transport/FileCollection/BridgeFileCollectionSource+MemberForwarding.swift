import AgentStudioCore
import Foundation

extension BridgeFileCollectionSource {
    /// Where an emitted collection row came from, so removing that source
    /// removes exactly its rows.
    enum CollectionRowSource: Hashable, Sendable {
        case member(UUID)
        case openedDocuments
    }

    // MARK: - Opening members

    func openMember(_ worktreeId: UUID, subscriptionId: String) async throws {
        guard let memberSource = memberSourcesById[worktreeId],
            let group = layout.memberGroup(for: worktreeId),
            var context = contextBySubscriptionId[subscriptionId]
        else { return }
        let expectedSource = context.productSource
        context.openedMemberIds.insert(worktreeId)
        contextBySubscriptionId[subscriptionId] = context
        try await emitCollectionRows(
            [BridgeFileCollectionRows.groupRow(path: group.groupPath, identityPrefix: group.identityPrefix)],
            from: .member(worktreeId),
            subscriptionId: subscriptionId,
            expectedSource: expectedSource
        )
        let memberSnapshot = try memberSubscription(
            for: memberSource,
            from: context.subscription
        )
        do {
            try await memberSource.producer.open(
                subscription: memberSnapshot,
                productAdmission: context.productAdmission,
                foregroundWorkAdmission: context.foregroundWorkAdmission,
                emit: { [self] event in
                    try await forwardMemberEvent(
                        event,
                        fromMember: worktreeId,
                        subscriptionId: subscriptionId,
                        expectedSource: expectedSource
                    )
                }
            )
            recordMemberAvailability(
                .available,
                worktreeId: worktreeId,
                subscriptionId: subscriptionId,
                expectedSource: expectedSource
            )
        } catch {
            guard !Task.isCancelled, !(error is CancellationError),
                context.foregroundWorkAdmission.withValidAdmission({ true }) == true,
                (context.productAdmission.withValidAdmission { true }) == true
            else { throw error }
            // One member's failure leaves the others browsable; its group stays
            // listed and its failure is reported separately from empty results.
            recordMemberAvailability(
                .failed,
                worktreeId: worktreeId,
                subscriptionId: subscriptionId,
                expectedSource: expectedSource
            )
        }
    }

    func updateMember(_ worktreeId: UUID, subscriptionId: String) async throws {
        guard let memberSource = memberSourcesById[worktreeId],
            let context = contextBySubscriptionId[subscriptionId]
        else { return }
        let expectedSource = context.productSource
        try await memberSource.producer.update(
            subscription: memberSubscription(for: memberSource, from: context.subscription),
            productAdmission: context.productAdmission,
            foregroundWorkAdmission: context.foregroundWorkAdmission,
            emit: { [self] event in
                try await forwardMemberEvent(
                    event,
                    fromMember: worktreeId,
                    subscriptionId: subscriptionId,
                    expectedSource: expectedSource
                )
            }
        )
    }

    func completeInitialEnumeration(subscriptionId: String) async throws {
        guard var context = contextBySubscriptionId[subscriptionId],
            let totalRowCount = context.enumerationIndex
        else { return }
        context.enumerationIndex = nil
        contextBySubscriptionId[subscriptionId] = context
        try await context.emit(
            .treeWindow(
                try .init(
                    finalWindow: true,
                    lineage: .init(lane: .foreground, loadedBy: .startupWindow),
                    pathScope: context.subscription.interestState.fileMetadataState?.pathScope ?? [],
                    rows: [],
                    source: context.productSource,
                    startIndex: totalRowCount,
                    totalRowCount: totalRowCount
                )
            )
        )
    }

    /// Re-address the worker's collection subscription to one member: its own
    /// worktree token, and only the interest paths that resolve into it.
    func memberSubscription(
        for memberSource: BridgeFileCollectionMemberSource,
        from subscription: BridgeProductSubscriptionSnapshot
    ) throws -> BridgeProductSubscriptionSnapshot {
        let worktreeId = memberSource.member.worktreeId
        let state = subscription.interestState.fileMetadataState
        let memberRelativePath = { (displayPath: String) -> String? in
            guard case .memberPath(worktreeId, let relativePath) = self.layout.resolve(displayPath: displayPath)
            else { return nil }
            return relativePath
        }
        let interests = try (state?.interests ?? []).compactMap { group in
            let paths = group.paths.compactMap(memberRelativePath)
            return paths.isEmpty ? nil : try BridgeProductFileMetadataInterestStateGroup(lane: group.lane, paths: paths)
        }
        return BridgeProductSubscriptionSnapshot(
            subscription: .fileMetadata(
                BridgeProductFileSourceSpec(
                    memberCollectionToken: memberSource.memberCollectionToken,
                    includeStatuses: subscription.subscription.fileMetadataSource?.includeStatuses ?? true
                )
            ),
            subscriptionId: subscription.subscriptionId,
            subscriptionKind: subscription.subscriptionKind,
            workerDerivationEpoch: subscription.workerDerivationEpoch,
            interestRevision: subscription.interestRevision,
            interestSha256: subscription.interestSha256,
            interestState: .fileMetadata(
                interests: interests,
                pathScope: (state?.pathScope ?? []).compactMap(memberRelativePath)
            ),
            hasStagedUpdate: subscription.hasStagedUpdate
        )
    }

    // MARK: - Forwarding member output

    func forwardMemberEvent(
        _ event: BridgeProductFileMetadataEvent,
        fromMember worktreeId: UUID,
        subscriptionId: String,
        expectedSource: BridgeProductFileSourceIdentity
    ) async throws {
        guard let context = contextBySubscriptionId[subscriptionId],
            context.productSource == expectedSource
        else { return }
        for translated in try translate(event, fromMember: worktreeId, subscriptionId: subscriptionId) {
            try await context.emit(translated)
        }
    }

    func translatedEmissions(
        _ emissions: [BridgePaneProductFileMetadataEmission],
        fromMember worktreeId: UUID
    ) throws -> [BridgePaneProductFileMetadataEmission] {
        try emissions.flatMap { emission in
            try translate(emission.event, fromMember: worktreeId, subscriptionId: emission.subscriptionId)
                .map { .init(event: $0, subscriptionId: emission.subscriptionId) }
        }
    }

    /// Translate one member event into collection events, recording the rows and
    /// descriptors it issues so they can be removed or resolved later.
    func translate(
        _ event: BridgeProductFileMetadataEvent,
        fromMember worktreeId: UUID,
        subscriptionId: String
    ) throws -> [BridgeProductFileMetadataEvent] {
        guard var context = contextBySubscriptionId[subscriptionId],
            let group = layout.memberGroup(for: worktreeId)
        else { return [] }
        let translation = BridgeFileCollectionMemberTranslation(
            group: group,
            collectionSource: context.productSource
        )
        defer { contextBySubscriptionId[subscriptionId] = context }
        switch event {
        case .sourceAccepted:
            return []
        case .treeWindow(let window):
            return try collectionRowEvents(
                translation.rows(window.rows),
                from: .member(worktreeId),
                context: &context
            )
        case .treeDelta(let delta):
            let operations = try delta.operations.compactMap(translation.operation)
            for operation in operations { context.record(operation, from: .member(worktreeId)) }
            guard !operations.isEmpty else { return [] }
            return [.treeDelta(try .init(operations: operations, source: context.productSource))]
        case .statusPatch(let statusPatch):
            return statusEvents(
                statusPatch.patch,
                fromMember: worktreeId,
                translation: translation,
                source: context.productSource
            )
        case .descriptorReady(let descriptorEvent):
            guard let payload = try translation.descriptorPayload(descriptorEvent.payload) else { return [] }
            context.recordIssued(payload, memberPayload: descriptorEvent.payload, worktreeId: worktreeId)
            return [.descriptorReady(.init(payload: payload))]
        case .invalidated(let invalidation):
            return try invalidationEvents(
                invalidation,
                fromMember: worktreeId,
                translation: translation,
                context: &context
            )
        }
    }

    private func statusEvents(
        _ patch: BridgeProductFileStatusPatch,
        fromMember worktreeId: UUID,
        translation: BridgeFileCollectionMemberTranslation,
        source: BridgeProductFileSourceIdentity
    ) -> [BridgeProductFileMetadataEvent] {
        switch patch {
        case .path(let path, let status):
            guard let displayPath = translation.displayPath(path) else { return [] }
            return [.statusPatch(.init(patch: .path(path: displayPath, status: status), source: source))]
        case .summary, .invalidated:
            // The collection shows one branch summary: its first member's.
            guard layout.memberGroups.first?.worktreeId == worktreeId else { return [] }
            return [.statusPatch(.init(patch: patch, source: source))]
        }
    }

    private func invalidationEvents(
        _ invalidation: BridgeProductFileInvalidatedEvent,
        fromMember worktreeId: UUID,
        translation: BridgeFileCollectionMemberTranslation,
        context: inout SubscriptionContext
    ) throws -> [BridgeProductFileMetadataEvent] {
        // A member-wide reset would clear every member's rows in the worker;
        // members do not emit one, and one must never leak across the collection.
        guard let memberFileId = invalidation.fileId,
            let displayPath = translation.displayPath(invalidation.path)
        else { return [] }
        let fileId = translation.identifier(memberFileId)
        context.issuedDescriptorsById = context.issuedDescriptorsById.filter {
            $0.value.collectionDescriptor.fileId != fileId
        }
        var replacement: BridgeProductFileDescriptorReadyPayload?
        if let memberReplacement = invalidation.replacementDescriptor {
            replacement = try translation.descriptorPayload(memberReplacement)
            if let replacement {
                context.recordIssued(replacement, memberPayload: memberReplacement, worktreeId: worktreeId)
            }
        }
        return [
            .invalidated(
                try .init(
                    fileId: fileId,
                    path: displayPath,
                    reason: invalidation.reason,
                    replacementDescriptor: replacement,
                    source: context.productSource
                )
            )
        ]
    }

    // MARK: - Collection rows

    func emitCollectionRows(
        _ rows: [BridgeProductFileTreeRow],
        from rowSource: CollectionRowSource,
        subscriptionId: String,
        expectedSource: BridgeProductFileSourceIdentity
    ) async throws {
        guard var context = contextBySubscriptionId[subscriptionId],
            context.productSource == expectedSource
        else { return }
        let events = try collectionRowEvents(rows, from: rowSource, context: &context)
        contextBySubscriptionId[subscriptionId] = context
        for event in events { try await context.emit(event) }
    }

    /// Rows join the initial positional tree while it is still being
    /// enumerated, and arrive as upserts afterwards.
    private func collectionRowEvents(
        _ rows: [BridgeProductFileTreeRow],
        from rowSource: CollectionRowSource,
        context: inout SubscriptionContext
    ) throws -> [BridgeProductFileMetadataEvent] {
        guard !rows.isEmpty else { return [] }
        context.emittedPathsBySource[rowSource, default: []].formUnion(rows.map(\.path))
        let chunks = try BridgePaneProductFileMetadataEncoding.boundedProductRowChunks(productRows: rows)
        guard var nextIndex = context.enumerationIndex else {
            return try chunks.map {
                .treeDelta(try .init(operations: [.upsertRows($0)], source: context.productSource))
            }
        }
        var events: [BridgeProductFileMetadataEvent] = []
        for chunk in chunks {
            events.append(
                .treeWindow(
                    try .init(
                        finalWindow: false,
                        lineage: .init(lane: .foreground, loadedBy: .startupWindow),
                        pathScope: context.subscription.interestState.fileMetadataState?.pathScope ?? [],
                        rows: chunk,
                        source: context.productSource,
                        startIndex: nextIndex,
                        totalRowCount: nil
                    )
                )
            )
            nextIndex += chunk.count
        }
        context.enumerationIndex = nextIndex
        return events
    }

    private func recordMemberAvailability(
        _ availability: BridgeFileCollectionMemberAvailability,
        worktreeId: UUID,
        subscriptionId: String,
        expectedSource: BridgeProductFileSourceIdentity
    ) {
        guard var context = contextBySubscriptionId[subscriptionId],
            context.productSource == expectedSource
        else { return }
        context.memberAvailability[worktreeId] = availability
        contextBySubscriptionId[subscriptionId] = context
    }
}

extension BridgeFileCollectionSource.SubscriptionContext {
    mutating func record(
        _ operation: BridgeProductFileTreeOperation,
        from rowSource: BridgeFileCollectionSource.CollectionRowSource
    ) {
        switch operation {
        case .upsertRows(let rows):
            emittedPathsBySource[rowSource, default: []].formUnion(rows.map(\.path))
        case .removeRows(let paths, _):
            emittedPathsBySource[rowSource, default: []].subtract(paths)
        }
    }

    mutating func recordIssued(
        _ payload: BridgeProductFileDescriptorReadyPayload,
        memberPayload: BridgeProductFileDescriptorReadyPayload,
        worktreeId: UUID
    ) {
        guard case .available(let collectionDescriptor) = payload.availability,
            case .available(let memberDescriptor) = memberPayload.availability
        else { return }
        issuedDescriptorsById[collectionDescriptor.descriptorId] = .init(
            collectionDescriptor: collectionDescriptor,
            displayPath: payload.path,
            origin: .member(worktreeId: worktreeId, memberDescriptor: memberDescriptor)
        )
    }
}
