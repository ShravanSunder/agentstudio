import AgentStudioInfrastructure
import Foundation
import Testing

@testable import AgentStudioBridge

@Suite("Worktree annotation projection transport")
struct WorktreeAnnotationProjectionTransportTests {
    @Test("source open returns after registering producer and cancellation drains it")
    @MainActor
    func sourceOpenReturnsBeforeProductionCompletes() async throws {
        // Arrange
        let projection = WorktreeAnnotationProjectionAtom()
        let source = BridgePaneProductWorktreeAnnotationSource(
            projection: projection,
            contextID: "pane-test",
            worktreeID: "worktree-1"
        )
        let subscription = BridgeProductSubscriptionSnapshot(
            subscription: .fileAnnotations,
            subscriptionId: "annotation-subscription-1",
            subscriptionKind: .fileAnnotations,
            workerDerivationEpoch: 1,
            interestRevision: 0,
            interestSha256: try BridgeProductSubscriptionInterestState.fileAnnotations.sha256Hex(),
            interestState: .fileAnnotations,
            hasStagedUpdate: false
        )
        let emissionGate = WorktreeAnnotationEmissionGate()
        let openReturnProbe = WorktreeAnnotationOpenReturnProbe()
        let openTask = Task {
            do {
                try await source.open(subscription: subscription, surface: .file) { event in
                    try await emissionGate.emit(event)
                }
                await openReturnProbe.recordReturn()
            } catch {
                Issue.record("Annotation source open failed: \(error)")
            }
        }

        // Act
        await emissionGate.waitUntilEmissionStarts()

        // Assert
        #expect(await openReturnProbe.didReturn)
        openTask.cancel()
        await emissionGate.releaseEmission()
        await openTask.value
        await source.cancel(subscriptionId: subscription.subscriptionId)
        let emittedEventCount = await emissionGate.emittedEventCount
        projection.publishDiscovery([], worktreeID: "worktree-1")
        #expect(await emissionGate.emittedEventCount == emittedEventCount)
    }

    @Test("source producer survives open return and emits later projection revisions")
    @MainActor
    func sourceProducerSurvivesOpenReturn() async throws {
        // Arrange
        let projection = WorktreeAnnotationProjectionAtom()
        let source = BridgePaneProductWorktreeAnnotationSource(
            projection: projection,
            contextID: "pane-test",
            worktreeID: "worktree-1"
        )
        let subscription = BridgeProductSubscriptionSnapshot(
            subscription: .fileAnnotations,
            subscriptionId: "annotation-subscription-lifetime",
            subscriptionKind: .fileAnnotations,
            workerDerivationEpoch: 1,
            interestRevision: 0,
            interestSha256: try BridgeProductSubscriptionInterestState.fileAnnotations.sha256Hex(),
            interestState: .fileAnnotations,
            hasStagedUpdate: false
        )
        let recorder = WorktreeAnnotationEventRecorder()
        let openTask = Task {
            try await source.open(subscription: subscription, surface: .file) { event in
                await recorder.record(event)
            }
        }
        try await openTask.value
        await recorder.waitUntilEventCount(1)

        // Act
        projection.publishDiscovery([], worktreeID: "worktree-1")
        await recorder.waitUntilEventCount(2)

        // Assert
        #expect(await recorder.eventSourceGenerations == [0, 1])
        await source.cancel(subscriptionId: subscription.subscriptionId)
    }

    @Test("source coalesces queued full-snapshot revisions to the newest revision")
    @MainActor
    func sourceCoalescesQueuedProjectionRevisions() async throws {
        // Arrange
        let projection = WorktreeAnnotationProjectionAtom()
        let source = BridgePaneProductWorktreeAnnotationSource(
            projection: projection,
            contextID: "pane-test",
            worktreeID: "worktree-1"
        )
        let subscription = BridgeProductSubscriptionSnapshot(
            subscription: .fileAnnotations,
            subscriptionId: "annotation-subscription-coalescing",
            subscriptionKind: .fileAnnotations,
            workerDerivationEpoch: 1,
            interestRevision: 0,
            interestSha256: try BridgeProductSubscriptionInterestState.fileAnnotations.sha256Hex(),
            interestState: .fileAnnotations,
            hasStagedUpdate: false
        )
        let recorder = WorktreeAnnotationCoalescingRecorder()
        try await source.open(subscription: subscription, surface: .file) { event in
            await recorder.record(event)
        }
        await recorder.waitUntilFirstEventStarts()

        // Act
        for _ in 0..<100 {
            projection.publishDiscovery([], worktreeID: "worktree-1")
        }
        await recorder.releaseFirstEvent()
        await recorder.waitUntilEventCount(2)

        // Assert
        #expect(await recorder.eventSourceGenerations == [0, 100])
        await source.cancel(subscriptionId: subscription.subscriptionId)
    }

    @Test("maximum legal complete messages pack without splitting across 128 KiB frames")
    func maximumMessagesPackAcrossFramesWithoutSplitting() throws {
        // Arrange
        let snapshot = makeProjectionSnapshot(messageCount: 6)

        // Act
        let events = try BridgeProductWorktreeAnnotationProjectionPacker.events(
            snapshot: snapshot,
            surface: .file
        )
        let batches = events.compactMap { event -> BridgeProductWorktreeAnnotationMessageBatch? in
            guard case .messageBatch(let batch) = event else { return nil }
            return batch
        }

        // Assert
        #expect(batches.count > 1)
        let transportedMessageIDs = batches.flatMap { $0.messages.map(\.messageId) }
        #expect(transportedMessageIDs.count == 6)
        #expect(Set(transportedMessageIDs).count == 6)
        #expect(batches.dropLast().allSatisfy { !$0.isLastBatchForThread })
        #expect(batches.last?.isLastBatchForThread == true)
    }

    @Test("projection carries current message content without immutable anchoring context")
    func projectionExcludesHeavyDurableFields() throws {
        // Arrange
        let snapshot = makeProjectionSnapshot(messageCount: 1, savedRevision: 3)

        // Act
        let data = try JSONEncoder().encode(
            BridgeProductWorktreeAnnotationProjectionPacker.events(
                snapshot: snapshot,
                surface: .file
            )
        )
        let json = try #require(String(data: data, encoding: .utf8))

        // Assert
        #expect(!json.contains("selectedExcerpt"))
        #expect(!json.contains("contextBefore"))
        #expect(!json.contains("contextAfter"))
        #expect(json.contains("latest saved body"))
        #expect(json.contains("\"savedRevision\":3"))
        #expect(json.contains("current draft body"))
    }

    @Test("projection events round-trip through the strict JSON member vocabulary")
    func projectionEventsRoundTripThroughStrictJSONVocabulary() throws {
        let events = try BridgeProductWorktreeAnnotationProjectionPacker.events(
            snapshot: makeProjectionSnapshot(messageCount: 1),
            surface: .file
        )

        for event in events {
            let encodedEvent = try JSONEncoder().encode(event)
            let decodedEvent = try BridgeProductStrictJSON.decode(
                BridgeProductWorktreeAnnotationEvent.self,
                from: encodedEvent
            )
            #expect(decodedEvent == event)
        }
    }

    @Test("projection state requires a nonnegative emitted-thread count")
    func projectionStateRequiresExpectedThreadCount() throws {
        // Arrange
        let populatedEvents = try BridgeProductWorktreeAnnotationProjectionPacker.events(
            snapshot: makeProjectionSnapshot(messageCount: 1),
            surface: .file
        )
        let projectionState = try #require(
            populatedEvents.first { event in
                if case .projectionState = event { return true }
                return false
            }
        )
        let encoded = try JSONEncoder().encode(projectionState)
        let object = try #require(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        let payload = try #require(object["payload"] as? [String: Any])

        // Act / Assert
        #expect(payload["expectedThreadCount"] as? Int == 1)
        for invalidValue: Any? in [nil, -1, "unknown"] {
            var invalidPayload = payload
            invalidPayload["expectedThreadCount"] = invalidValue
            var invalidObject = object
            invalidObject["payload"] = invalidPayload
            let invalidData = try JSONSerialization.data(withJSONObject: invalidObject)
            #expect(throws: (any Error).self) {
                _ = try JSONDecoder().decode(
                    BridgeProductWorktreeAnnotationEvent.self,
                    from: invalidData
                )
            }
        }

        let emptyEvents = try BridgeProductWorktreeAnnotationProjectionPacker.events(
            snapshot: makeProjectionSnapshot(messageCount: 0),
            surface: .file
        )
        guard case .projectionState(let emptyState) = try #require(emptyEvents.first) else {
            Issue.record("Expected empty projection state")
            return
        }
        #expect(emptyState.expectedThreadCount == 0)
        #expect(emptyEvents.count == 1)
    }

    @Test("projection emits annotation identities as lowercase UUIDv7 text")
    func projectionEmitsLowercaseUUIDv7Identities() throws {
        // Arrange
        let sessionUUID = try #require(UUID(uuidString: "01890abc-def0-7abc-8def-0123456789ab"))
        let sessionID = WorktreeAnnotationSessionID(rawValue: sessionUUID)

        // Act
        let data = try JSONEncoder().encode(
            BridgeProductWorktreeAnnotationProjectionPacker.events(
                snapshot: makeProjectionSnapshot(messageCount: 1, sessionID: sessionID),
                surface: .file
            )
        )
        let json = try #require(String(data: data, encoding: .utf8))

        // Assert
        #expect(json.contains(sessionUUID.uuidString.lowercased()))
        #expect(!json.contains(sessionUUID.uuidString))
    }

    @Test("every annotation projection event round-trips through the metadata frame codec")
    func projectionEventsRoundTripThroughMetadataFrameCodec() throws {
        // Arrange
        let events = try BridgeProductWorktreeAnnotationProjectionPacker.events(
            snapshot: makeProjectionSnapshot(messageCount: 1),
            surface: .file
        )
        let stream = BridgeProductMetadataStreamCorrelation(
            metadataStreamId: "metadata-stream-annotations",
            paneSessionId: "pane-session-annotations",
            wireVersion: BridgeProductWireContract.version,
            workerInstanceId: "worker-instance-annotations"
        )
        let subscription = try BridgeProductSubscriptionFrameCorrelation(
            cursor: nil,
            interestRevision: 0,
            interestSha256: String(repeating: "a", count: 64),
            sourceGeneration: 1,
            subscriptionId: "subscription-annotations",
            subscriptionKind: .fileAnnotations,
            workerDerivationEpoch: 0
        )

        // Act / Assert
        for (index, event) in events.enumerated() {
            let frame = try BridgeProductMetadataFrame.subscriptionData(
                stream: stream,
                streamSequence: index + 1,
                subscription: subscription,
                subscriptionSequence: index + 1,
                data: .fileAnnotations(event)
            )
            let decoder = try BridgeProductMetadataFrameDecoder()
            #expect(try decoder.append(BridgeProductMetadataFrameCodec.encode(frame)) == [frame])
            try decoder.finish()
        }
    }

    @Test("projection carries bounded output summaries without exact historical bytes")
    func projectionCarriesOnlyBoundedOutputSummaries() throws {
        let attemptID = WorktreeAnnotationOutputAttemptID(rawValue: UUIDv7.generate())
        let sessionID = WorktreeAnnotationSessionID(rawValue: UUIDv7.generate())
        let snapshot = makeProjectionSnapshot(
            messageCount: 1,
            sessionID: sessionID,
            outputHistory: [
                .init(
                    attemptID: attemptID,
                    sessionID: sessionID,
                    outputKind: .clipboardMarkdown,
                    state: .succeeded,
                    messageCount: 1,
                    repeatedFromAttemptID: nil,
                    createdAt: Date(timeIntervalSince1970: 101),
                    updatedAt: Date(timeIntervalSince1970: 102)
                )
            ]
        )

        let data = try JSONEncoder().encode(
            BridgeProductWorktreeAnnotationProjectionPacker.events(
                snapshot: snapshot,
                surface: .file
            )
        )
        let json = try #require(String(data: data, encoding: .utf8))

        #expect(json.lowercased().contains(attemptID.rawValue.uuidString.lowercased()))
        #expect(json.contains("clipboard_markdown"))
        #expect(!json.contains("exactBytes"))
        #expect(!json.contains("canonicalSnapshot"))
    }

    @Test("every nested annotation projection object rejects unknown fields")
    func nestedProjectionObjectsRejectUnknownFields() throws {
        // Arrange
        let sessionID = WorktreeAnnotationSessionID(rawValue: UUIDv7.generate())
        let events = try BridgeProductWorktreeAnnotationProjectionPacker.events(
            snapshot: makeProjectionSnapshot(
                messageCount: 1,
                sessionID: sessionID,
                outputHistory: [
                    .init(
                        attemptID: .init(rawValue: UUIDv7.generate()),
                        sessionID: sessionID,
                        outputKind: .clipboardMarkdown,
                        state: .succeeded,
                        messageCount: 1,
                        repeatedFromAttemptID: nil,
                        createdAt: Date(timeIntervalSince1970: 101),
                        updatedAt: Date(timeIntervalSince1970: 102)
                    )
                ]
            ),
            surface: .file
        )
        let projectionStateEvent = try #require(
            events.first { event in
                if case .projectionState = event { return true }
                return false
            }
        )
        let messageBatchEvent = try #require(
            events.first { event in
                if case .messageBatch = event { return true }
                return false
            }
        )
        let mutations: [(BridgeProductWorktreeAnnotationEvent, [AnnotationJSONPathComponent])] = [
            (projectionStateEvent, [.key("payload")]),
            (projectionStateEvent, [.key("payload"), .key("sessions"), .index(0)]),
            (projectionStateEvent, [.key("payload"), .key("commandOutcomes"), .index(0)]),
            (
                projectionStateEvent,
                [.key("payload"), .key("commandOutcomes"), .index(0), .key("status")]
            ),
            (projectionStateEvent, [.key("payload"), .key("outputHistory"), .index(0)]),
            (messageBatchEvent, [.key("payload")]),
            (messageBatchEvent, [.key("payload"), .key("context")]),
            (messageBatchEvent, [.key("payload"), .key("messages"), .index(0)]),
        ]

        // Act / Assert
        for (event, path) in mutations {
            let invalidData = try annotationEventDataByAddingUnknownField(event, at: path)
            #expect(throws: (any Error).self) {
                _ = try JSONDecoder().decode(
                    BridgeProductWorktreeAnnotationEvent.self,
                    from: invalidData
                )
            }
        }
    }
}

private actor WorktreeAnnotationEmissionGate {
    private var emissionRelease: CheckedContinuation<Void, Never>?
    private var emissionStarted = false
    private var emissionStartedWaiters: [CheckedContinuation<Void, Never>] = []
    private(set) var emittedEventCount = 0

    func emit(_ event: BridgeProductWorktreeAnnotationEvent) async throws {
        _ = event
        emittedEventCount += 1
        emissionStarted = true
        let waiters = emissionStartedWaiters
        emissionStartedWaiters.removeAll(keepingCapacity: false)
        for waiter in waiters { waiter.resume() }
        await withCheckedContinuation { continuation in
            emissionRelease = continuation
        }
        try Task.checkCancellation()
    }

    func waitUntilEmissionStarts() async {
        guard !emissionStarted else { return }
        await withCheckedContinuation { continuation in
            emissionStartedWaiters.append(continuation)
        }
    }

    func releaseEmission() {
        emissionRelease?.resume()
        emissionRelease = nil
    }
}

private actor WorktreeAnnotationOpenReturnProbe {
    private(set) var didReturn = false

    func recordReturn() {
        didReturn = true
    }
}

private actor WorktreeAnnotationEventRecorder {
    private var events: [BridgeProductWorktreeAnnotationEvent] = []
    private var eventCountWaiters: [Int: [CheckedContinuation<Void, Never>]] = [:]

    var eventSourceGenerations: [Int] {
        events.map(\.sourceGeneration)
    }

    func record(_ event: BridgeProductWorktreeAnnotationEvent) {
        events.append(event)
        let readyTargets = eventCountWaiters.keys.filter { $0 <= events.count }
        for target in readyTargets {
            let waiters = eventCountWaiters.removeValue(forKey: target) ?? []
            for waiter in waiters { waiter.resume() }
        }
    }

    func waitUntilEventCount(_ targetCount: Int) async {
        guard events.count < targetCount else { return }
        await withCheckedContinuation { continuation in
            eventCountWaiters[targetCount, default: []].append(continuation)
        }
    }
}

private actor WorktreeAnnotationCoalescingRecorder {
    private var events: [BridgeProductWorktreeAnnotationEvent] = []
    private var eventCountWaiters: [Int: [CheckedContinuation<Void, Never>]] = [:]
    private var firstEventRelease: CheckedContinuation<Void, Never>?
    private var firstEventStarted = false
    private var firstEventStartedWaiters: [CheckedContinuation<Void, Never>] = []

    var eventSourceGenerations: [Int] {
        events.map(\.sourceGeneration)
    }

    func record(_ event: BridgeProductWorktreeAnnotationEvent) async {
        if !firstEventStarted {
            firstEventStarted = true
            let waiters = firstEventStartedWaiters
            firstEventStartedWaiters.removeAll(keepingCapacity: false)
            for waiter in waiters { waiter.resume() }
            await withCheckedContinuation { continuation in
                firstEventRelease = continuation
            }
        }
        events.append(event)
        let readyTargets = eventCountWaiters.keys.filter { $0 <= events.count }
        for target in readyTargets {
            let waiters = eventCountWaiters.removeValue(forKey: target) ?? []
            for waiter in waiters { waiter.resume() }
        }
    }

    func waitUntilFirstEventStarts() async {
        guard !firstEventStarted else { return }
        await withCheckedContinuation { continuation in
            firstEventStartedWaiters.append(continuation)
        }
    }

    func releaseFirstEvent() {
        firstEventRelease?.resume()
        firstEventRelease = nil
    }

    func waitUntilEventCount(_ targetCount: Int) async {
        guard events.count < targetCount else { return }
        await withCheckedContinuation { continuation in
            eventCountWaiters[targetCount, default: []].append(continuation)
        }
    }
}

private func makeProjectionSnapshot(
    messageCount: Int,
    savedRevision: Int = 1,
    sessionID: WorktreeAnnotationSessionID = .init(rawValue: UUIDv7.generate()),
    outputHistory: [WorktreeAnnotationOutputHistorySummary] = []
) -> WorktreeAnnotationProjectionSnapshot {
    let threadID = WorktreeAnnotationThreadID(rawValue: UUIDv7.generate())
    let now = Date(timeIntervalSince1970: 100)
    let session = WorktreeAnnotationSession(
        id: sessionID,
        repositoryID: "repository-1",
        worktreeID: "worktree-1",
        originatingWorkspaceID: nil,
        lifecycle: .living,
        sourceRelationship: .applicable,
        acceptedSourceFingerprint: .init(
            repositoryID: "repository-1",
            worktreeID: "worktree-1",
            fileSourceIdentity: "file-source-1",
            reviewComparisonOrigin: nil
        ),
        semanticRevision: 1,
        createdAt: now,
        updatedAt: now,
        completedAt: nil
    )
    let thread = WorktreeAnnotationThread(
        id: threadID,
        sessionID: sessionID,
        origin: .located(
            .init(
                repositoryRelativePath: "Sources/Example.swift",
                startLine: 1,
                endLine: 2,
                sourceRole: .file,
                diffSide: nil,
                sourceIdentity: "file-source-1",
                selectedExcerpt: "must stay native",
                contextBefore: "native before",
                contextAfter: "native after"
            )
        ),
        resolution: .open,
        createdOrdinal: 0,
        semanticRevision: 1,
        createdAt: now,
        updatedAt: now,
        resolvedAt: nil
    )
    let messages = (0..<messageCount).map { ordinal in
        let messageID = WorktreeAnnotationMessageID(rawValue: UUIDv7.generate())
        return WorktreeAnnotationMessage(
            id: messageID,
            threadID: threadID,
            ordinal: ordinal,
            semanticRevision: 1,
            createdAt: now,
            updatedAt: now,
            savedBody: savedRevision > 0
                ? "latest saved body" + String(repeating: "s", count: 16 * 1024 - 17)
                : nil,
            savedRevision: savedRevision > 0 ? savedRevision : nil,
            draft: .init(
                messageID: messageID,
                activeEditToken: "editor-\(ordinal)",
                body: "current draft body" + String(repeating: "d", count: 16 * 1024 - 18),
                draftRevision: 1,
                updatedAt: now
            ),
            status: .editable
        )
    }
    return WorktreeAnnotationProjectionSnapshot(
        revision: 1,
        worktreeID: "worktree-1",
        recoveryState: .available,
        sessions: [session],
        details: [.init(session: session, threads: [.init(thread: thread, messages: messages)])],
        placementsByThreadID: [:],
        outputHistory: outputHistory,
        commandOutcomes: [
            .init(
                requestID: "request-1",
                surface: .file,
                sessionID: sessionID,
                status: .committed
            )
        ]
    )
}

private enum AnnotationJSONPathComponent {
    case index(Int)
    case key(String)
}

private enum AnnotationJSONMutationError: Error {
    case invalidPath
}

private func annotationEventDataByAddingUnknownField(
    _ event: BridgeProductWorktreeAnnotationEvent,
    at path: [AnnotationJSONPathComponent]
) throws -> Data {
    let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(event))
    return try JSONSerialization.data(
        withJSONObject: try annotationJSONObjectByAddingUnknownField(object, at: path),
        options: [.sortedKeys]
    )
}

private func annotationJSONObjectByAddingUnknownField(
    _ object: Any,
    at path: [AnnotationJSONPathComponent]
) throws -> Any {
    guard let component = path.first else {
        guard var dictionary = object as? [String: Any] else {
            throw AnnotationJSONMutationError.invalidPath
        }
        dictionary["method"] = "unexpected"
        return dictionary
    }
    let remainingPath = Array(path.dropFirst())
    switch component {
    case .index(let index):
        guard var array = object as? [Any], array.indices.contains(index) else {
            throw AnnotationJSONMutationError.invalidPath
        }
        array[index] = try annotationJSONObjectByAddingUnknownField(
            array[index],
            at: remainingPath
        )
        return array
    case .key(let key):
        guard var dictionary = object as? [String: Any], let child = dictionary[key] else {
            throw AnnotationJSONMutationError.invalidPath
        }
        dictionary[key] = try annotationJSONObjectByAddingUnknownField(
            child,
            at: remainingPath
        )
        return dictionary
    }
}
