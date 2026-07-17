import Foundation
import Testing

@testable import AgentStudio

actor BridgeWorktreeProductConstructionGate {
    private let artifact: BridgeWorktreeProductConstructionArtifact
    private var invocationCount = 0
    private var startWaiters: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []
    private var releaseContinuations: [Int: CheckedContinuation<Void, Never>] = [:]
    private var releasedInvocations: Set<Int> = []

    init(artifact: BridgeWorktreeProductConstructionArtifact) {
        self.artifact = artifact
    }

    func run(_: BridgeWorktreeProductConstructionContext) async throws
        -> BridgeWorktreeProductConstructionArtifact
    {
        invocationCount += 1
        let invocation = invocationCount
        let readyWaiters = startWaiters.filter { $0.count <= invocationCount }
        startWaiters.removeAll { $0.count <= invocationCount }
        for waiter in readyWaiters {
            waiter.continuation.resume()
        }
        if !releasedInvocations.contains(invocation) {
            await withCheckedContinuation { continuation in
                if releasedInvocations.contains(invocation) {
                    continuation.resume()
                } else {
                    releaseContinuations[invocation] = continuation
                }
            }
        }
        return artifact
    }

    func waitUntilStarted(count: Int = 1) async {
        precondition(count > 0)
        if invocationCount >= count { return }
        await withCheckedContinuation { continuation in
            startWaiters.append((count: count, continuation: continuation))
        }
    }

    func release(invocation: Int = 1) {
        releasedInvocations.insert(invocation)
        releaseContinuations.removeValue(forKey: invocation)?.resume()
    }

    func recordedInvocationCount() -> Int {
        invocationCount
    }
}

actor BridgeProgressiveFileConstructionGate {
    private struct Invocation {
        let publisher: BridgeSharedFileSnapshotPublisher
        let continuation: CheckedContinuation<BridgeSharedFileSnapshotCompletion, any Error>
    }

    private var invocationCount = 0
    private var invocations: [Int: Invocation] = [:]
    private var cancelledInvocations: Set<Int> = []
    private var cancellationWaiters: [(invocation: Int, continuation: CheckedContinuation<Void, Never>)] = []
    private var startWaiters: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []

    func run(
        _: BridgeWorktreeProductConstructionContext,
        publisher: BridgeSharedFileSnapshotPublisher
    ) async throws -> BridgeSharedFileSnapshotCompletion {
        invocationCount += 1
        let invocation = invocationCount
        let readyWaiters = startWaiters.filter { $0.count <= invocationCount }
        startWaiters.removeAll { $0.count <= invocationCount }
        for waiter in readyWaiters {
            waiter.continuation.resume()
        }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                invocations[invocation] = Invocation(
                    publisher: publisher,
                    continuation: continuation
                )
            }
        } onCancel: {
            Task { await self.recordCancellation(invocation: invocation) }
        }
    }

    func waitUntilStarted(count: Int = 1) async {
        precondition(count > 0)
        if invocationCount >= count { return }
        await withCheckedContinuation { continuation in
            startWaiters.append((count: count, continuation: continuation))
        }
    }

    func publishPreparation(
        retainedByteCount: Int = 0,
        invocation: Int = 1
    ) async throws {
        try await requiredInvocation(invocation).publisher.publishPreparation(
            makeBridgeSharedFileSnapshotPreparation(retainedByteCount: retainedByteCount)
        )
    }

    func append(
        _ window: BridgeSharedFileSnapshotWindow,
        invocation: Int = 1
    ) async throws {
        try await requiredInvocation(invocation).publisher.append(window)
    }

    func succeed(
        retainedNonwindowByteCount: Int = 0,
        invocation: Int = 1
    ) {
        let invocationState = requiredInvocation(invocation)
        invocations.removeValue(forKey: invocation)
        invocationState.continuation.resume(
            returning: BridgeSharedFileSnapshotCompletion(
                retainedNonwindowByteCount: retainedNonwindowByteCount
            )
        )
    }

    func fail(_ error: any Error, invocation: Int = 1) {
        let invocationState = requiredInvocation(invocation)
        invocations.removeValue(forKey: invocation)
        invocationState.continuation.resume(throwing: error)
    }

    func recordedInvocationCount() -> Int {
        invocationCount
    }

    func waitUntilCancelled(invocation: Int = 1) async {
        if cancelledInvocations.contains(invocation) { return }
        await withCheckedContinuation { continuation in
            cancellationWaiters.append((invocation: invocation, continuation: continuation))
        }
    }

    private func recordCancellation(invocation: Int) {
        cancelledInvocations.insert(invocation)
        let readyWaiters = cancellationWaiters.filter { $0.invocation == invocation }
        cancellationWaiters.removeAll { $0.invocation == invocation }
        for waiter in readyWaiters {
            waiter.continuation.resume()
        }
    }

    private func requiredInvocation(_ invocation: Int) -> Invocation {
        guard let invocationState = invocations[invocation] else {
            preconditionFailure("Missing progressive File construction invocation \(invocation)")
        }
        return invocationState
    }
}

actor BridgeProgressiveFileConstructionStateHarness {
    private var state = BridgeProgressiveFileConstructionState()
    private var pendingReadWaiters: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []

    func publishPreparation(retainedByteCount: Int = 0) throws {
        try state.publishPreparation(
            makeBridgeSharedFileSnapshotPreparation(retainedByteCount: retainedByteCount)
        )
    }

    func read(
        leaseNonce: UInt64,
        cursor: BridgeSharedFileSnapshotCursor,
        cancellationState: BridgeProgressiveFileConstructionState.ReadCancellationState
    ) async throws -> BridgeSharedFileSnapshotRead {
        try await withCheckedThrowingContinuation { continuation in
            state.enqueueRead(
                leaseNonce: leaseNonce,
                cursor: cursor,
                cancellationState: cancellationState,
                continuation: continuation
            )
            resumeSatisfiedPendingReadWaiters()
        }
    }

    func append(_ window: BridgeSharedFileSnapshotWindow) throws {
        try state.append(window)
    }

    func waitUntilPendingReadCount(_ count: Int) async {
        precondition(count > 0)
        if state.pendingReadCount >= count { return }
        await withCheckedContinuation { continuation in
            pendingReadWaiters.append((count: count, continuation: continuation))
        }
    }

    private func resumeSatisfiedPendingReadWaiters() {
        let readyWaiters = pendingReadWaiters.filter { $0.count <= state.pendingReadCount }
        pendingReadWaiters.removeAll { $0.count <= state.pendingReadCount }
        for waiter in readyWaiters {
            waiter.continuation.resume()
        }
    }
}

final class BridgeWorktreeProductConstructionEventProbe: @unchecked Sendable {
    private struct Waiter {
        let kind: BridgeWorktreeProductConstructionEventKind
        let occurrence: Int
        let continuation: CheckedContinuation<BridgeWorktreeProductConstructionEvent, Never>
    }

    private let lock = NSLock()
    private var recordedEvents: [BridgeWorktreeProductConstructionEvent] = []
    private var waiters: [Waiter] = []

    var eventSink: BridgeWorktreeProductConstructionEventSink {
        { [weak self] event in self?.record(event) }
    }

    var events: [BridgeWorktreeProductConstructionEvent] {
        lock.withLock { recordedEvents }
    }

    func waitFor(
        _ kind: BridgeWorktreeProductConstructionEventKind,
        occurrence: Int = 1
    ) async -> BridgeWorktreeProductConstructionEvent {
        precondition(occurrence > 0)
        if let event = lock.withLock({ matchingEvent(kind, occurrence: occurrence) }) {
            return event
        }
        return await withCheckedContinuation { continuation in
            let immediateEvent = lock.withLock { () -> BridgeWorktreeProductConstructionEvent? in
                if let event = matchingEvent(kind, occurrence: occurrence) {
                    return event
                }
                waiters.append(Waiter(kind: kind, occurrence: occurrence, continuation: continuation))
                return nil
            }
            immediateEvent.map { continuation.resume(returning: $0) }
        }
    }

    private func record(_ event: BridgeWorktreeProductConstructionEvent) {
        let resumptions = lock.withLock {
            recordedEvents.append(event)
            var ready:
                [(
                    CheckedContinuation<BridgeWorktreeProductConstructionEvent, Never>,
                    BridgeWorktreeProductConstructionEvent
                )] = []
            waiters.removeAll { waiter in
                guard let event = matchingEvent(waiter.kind, occurrence: waiter.occurrence) else {
                    return false
                }
                ready.append((waiter.continuation, event))
                return true
            }
            return ready
        }
        for (continuation, event) in resumptions {
            continuation.resume(returning: event)
        }
    }

    private func matchingEvent(
        _ kind: BridgeWorktreeProductConstructionEventKind,
        occurrence: Int
    ) -> BridgeWorktreeProductConstructionEvent? {
        let matchingEvents = recordedEvents.filter { $0.kind == kind }
        guard matchingEvents.count >= occurrence else { return nil }
        return matchingEvents[occurrence - 1]
    }
}

func makeBridgeConstructionOwner(
    repo: String = "repo-a",
    worktree: String = "worktree-a",
    root: String = "root-a",
    provider: String = "provider-a"
) -> BridgeWorktreeProductOwnerKey {
    BridgeWorktreeProductOwnerKey(
        repoIdentity: repo,
        worktreeIdentity: worktree,
        stableRootIdentity: root,
        providerIdentity: provider
    )
}

func makeBridgeFileConstructionKey(
    owner: BridgeWorktreeProductOwnerKey = makeBridgeConstructionOwner(),
    canonicalWorkingDirectoryIdentity: String = "cwd-a",
    pathScope: [String] = ["Sources"],
    statusSemantics: BridgeFileStatusSemanticsKey = .init(
        includesUntracked: true,
        includesIgnored: false,
        detectsRenames: true,
        recursesUntrackedDirectories: true
    ),
    ignoreSemantics: BridgeFileIgnoreSemanticsKey = .init(
        respectsRepositoryIgnore: true,
        respectsInfoExclude: true,
        respectsGlobalIgnore: false,
        additionalPatternIdentity: "patterns-a"
    )
) -> BridgeWorktreeProductConstructionKey {
    .file(
        BridgeFileConstructionKey(
            owner: owner,
            canonicalWorkingDirectoryIdentity: canonicalWorkingDirectoryIdentity,
            pathScope: pathScope,
            statusSemantics: statusSemantics,
            ignoreSemantics: ignoreSemantics
        )
    )
}

func makeBridgeReviewConstructionKey(
    owner: BridgeWorktreeProductOwnerKey = makeBridgeConstructionOwner(),
    queryKind: BridgeReviewQueryKindKey = .compare,
    comparisonSemantics: BridgeReviewComparisonSemanticsKey = .threeDot,
    canonicalWorkingDirectoryIdentity: String = "cwd-a",
    baseEndpoint: BridgeResolvedReviewEndpointKey = .init(
        kind: .gitObject,
        providerIdentity: "provider-a",
        contentIdentity: "base-oid"
    ),
    headEndpoint: BridgeResolvedReviewEndpointKey = .init(
        kind: .gitObject,
        providerIdentity: "provider-a",
        contentIdentity: "head-oid"
    ),
    pathScope: [String] = ["Sources"],
    fileTarget: String? = nil,
    viewFilter: BridgeReviewViewFilterKey = .fixture,
    grouping: BridgeReviewGroupingKey = .init(kind: .folder, label: "Folder"),
    provenance: BridgeReviewProvenanceFilterKey = .fixture,
    checkpoint: BridgeReviewCheckpointSemanticsKey? = .fixture
) -> BridgeWorktreeProductConstructionKey {
    .review(
        BridgeReviewConstructionKey(
            owner: owner,
            queryKind: queryKind,
            comparisonSemantics: comparisonSemantics,
            canonicalWorkingDirectoryIdentity: canonicalWorkingDirectoryIdentity,
            baseEndpoint: baseEndpoint,
            headEndpoint: headEndpoint,
            pathScope: pathScope,
            fileTarget: fileTarget,
            viewFilter: viewFilter,
            grouping: grouping,
            provenance: provenance,
            checkpoint: checkpoint
        )
    )
}

func makeBridgeFileConstructionArtifact(
    retainedByteCount: Int = 64
) -> BridgeWorktreeProductConstructionArtifact {
    .fileSnapshot(
        BridgeSharedFileSnapshotBuild(
            preparation: makeBridgeSharedFileSnapshotPreparation(),
            orderedWindows: [
                BridgeSharedFileSnapshotWindow(
                    ordinal: 0,
                    startIndex: 0,
                    discoveredRowCount: 1,
                    isFinalWindow: true,
                    rows: [
                        BridgeWorktreeTreeRowMetadata(
                            rowId: "row-0",
                            path: "Sources/App.swift",
                            name: "App.swift",
                            parentPath: "Sources",
                            depth: 1,
                            isDirectory: false,
                            fileId: "file-0",
                            sizeBytes: 64,
                            lineCount: nil,
                            changeStatus: "modified"
                        )
                    ],
                    retainedByteCount: retainedByteCount
                )
            ],
            retainedByteCount: retainedByteCount
        )
    )
}

func makeBridgeSharedFileSnapshotPreparation(
    retainedByteCount: Int = 0
) -> BridgeSharedFileSnapshotPreparation {
    BridgeSharedFileSnapshotPreparation(
        ignorePolicy: .empty,
        statusResult: .unavailable(
            GitWorkingTreeStatusUnavailable(reason: .providerReturnedNil)
        ),
        retainedByteCount: retainedByteCount
    )
}

func makeBridgeProgressiveFileConstructionKey() -> BridgeFileConstructionKey {
    guard case .file(let key) = makeBridgeFileConstructionKey() else {
        preconditionFailure("Expected File construction key")
    }
    return key
}

func makeBridgeSharedFileSnapshotWindow(
    ordinal: Int,
    startIndex: Int? = nil,
    path: String? = nil,
    isFinalWindow: Bool,
    retainedByteCount: Int = 64
) -> BridgeSharedFileSnapshotWindow {
    let resolvedStartIndex = startIndex ?? ordinal
    let resolvedPath = path ?? "Sources/File-\(ordinal).swift"
    let rows = [
        BridgeWorktreeTreeRowMetadata(
            rowId: "row-\(ordinal)",
            path: resolvedPath,
            name: URL(fileURLWithPath: resolvedPath).lastPathComponent,
            parentPath: "Sources",
            depth: 1,
            isDirectory: false,
            fileId: "file-\(ordinal)",
            sizeBytes: retainedByteCount,
            lineCount: nil,
            changeStatus: nil
        )
    ]
    return BridgeSharedFileSnapshotWindow(
        ordinal: ordinal,
        startIndex: resolvedStartIndex,
        discoveredRowCount: resolvedStartIndex + rows.count,
        isFinalWindow: isFinalWindow,
        rows: rows,
        retainedByteCount: retainedByteCount
    )
}

func makeBridgeReviewConstructionArtifact(
    retainedByteCount: Int = 128
) -> BridgeWorktreeProductConstructionArtifact {
    .reviewTemplate(
        BridgeSharedReviewPackageTemplate(
            baseEndpoint: BridgeResolvedReviewEndpointKey(
                kind: .gitObject,
                providerIdentity: "provider-a",
                contentIdentity: "base-oid"
            ),
            headEndpoint: BridgeResolvedReviewEndpointKey(
                kind: .gitObject,
                providerIdentity: "provider-a",
                contentIdentity: "head-oid"
            ),
            orderedItemIdentities: ["Sources/App.swift"],
            descriptorCores: [
                BridgeSharedReviewDescriptorCore(
                    itemIdentity: "Sources/App.swift",
                    semanticVersion: "blob-a..blob-b",
                    baseLocator: .init(providerIdentity: "provider-a", contentIdentity: "blob-a", digest: "digest-a"),
                    headLocator: .init(providerIdentity: "provider-a", contentIdentity: "blob-b", digest: "digest-b")
                )
            ],
            groups: [],
            summary: .init(filesChanged: 1, additions: 2, deletions: 1),
            retainedByteCount: retainedByteCount
        )
    )
}

extension BridgeReviewViewFilterKey {
    static let fixture = Self(
        includedPathGlobs: ["Sources/**"],
        excludedPathGlobs: ["**/*.generated.swift"],
        includedFileClasses: ["source"],
        excludedFileClasses: ["binary"],
        includedExtensions: ["swift"],
        excludedExtensions: ["png"],
        changeKinds: ["modified"],
        reviewStates: ["unreviewed"],
        showsHiddenFiles: false,
        showsBinaryFiles: false,
        showsLargeFiles: true
    )
}

func makeBridgeReviewViewFilterKey(
    includedPathGlobs: [String] = ["Sources/**"],
    excludedPathGlobs: [String] = ["**/*.generated.swift"],
    includedFileClasses: [String] = ["source"],
    excludedFileClasses: [String] = ["binary"],
    includedExtensions: [String] = ["swift"],
    excludedExtensions: [String] = ["png"],
    changeKinds: [String] = ["modified"],
    reviewStates: [String] = ["unreviewed"],
    showsHiddenFiles: Bool = false,
    showsBinaryFiles: Bool = false,
    showsLargeFiles: Bool = true
) -> BridgeReviewViewFilterKey {
    BridgeReviewViewFilterKey(
        includedPathGlobs: includedPathGlobs,
        excludedPathGlobs: excludedPathGlobs,
        includedFileClasses: includedFileClasses,
        excludedFileClasses: excludedFileClasses,
        includedExtensions: includedExtensions,
        excludedExtensions: excludedExtensions,
        changeKinds: changeKinds,
        reviewStates: reviewStates,
        showsHiddenFiles: showsHiddenFiles,
        showsBinaryFiles: showsBinaryFiles,
        showsLargeFiles: showsLargeFiles
    )
}

extension BridgeReviewProvenanceFilterKey {
    static let fixture = Self(
        paneIdentities: [UUID(uuidString: "00000000-0000-0000-0000-000000000001")!],
        agentSessionIdentities: ["session-a"],
        promptIdentities: ["prompt-a"],
        operationIdentities: ["operation-a"],
        createdAfterUnixMilliseconds: 10,
        createdBeforeUnixMilliseconds: 20,
        sourceKinds: ["runtimeEvent"]
    )
}

func makeBridgeReviewProvenanceFilterKey(
    paneIdentities: [UUID] = [UUID(uuidString: "00000000-0000-0000-0000-000000000001")!],
    agentSessionIdentities: [String] = ["session-a"],
    promptIdentities: [String] = ["prompt-a"],
    operationIdentities: [String] = ["operation-a"],
    createdAfterUnixMilliseconds: Int64? = 10,
    createdBeforeUnixMilliseconds: Int64? = 20,
    sourceKinds: [String] = ["runtimeEvent"]
) -> BridgeReviewProvenanceFilterKey {
    BridgeReviewProvenanceFilterKey(
        paneIdentities: paneIdentities,
        agentSessionIdentities: agentSessionIdentities,
        promptIdentities: promptIdentities,
        operationIdentities: operationIdentities,
        createdAfterUnixMilliseconds: createdAfterUnixMilliseconds,
        createdBeforeUnixMilliseconds: createdBeforeUnixMilliseconds,
        sourceKinds: sourceKinds
    )
}

extension BridgeReviewCheckpointSemanticsKey {
    static let fixture = Self(
        kind: .session,
        contentIdentity: "checkpoint-a",
        eventSequenceBounds: 1...2,
        batchSequenceBounds: 3...4
    )
}

func assertBridgeConstructionCoordinatorDrained(
    _ coordinator: BridgeWorktreeProductConstructionCoordinator,
    sourceLocation: SourceLocation = #_sourceLocation
) async {
    let snapshot = await coordinator.snapshot()
    #expect(snapshot.entryCount == 0, sourceLocation: sourceLocation)
    #expect(snapshot.waiterCount == 0, sourceLocation: sourceLocation)
    #expect(snapshot.leaseCount == 0, sourceLocation: sourceLocation)
    #expect(snapshot.payloadCount == 0, sourceLocation: sourceLocation)
    #expect(snapshot.inFlightCount == 0, sourceLocation: sourceLocation)
    #expect(snapshot.locatorCount == 0, sourceLocation: sourceLocation)
    #expect(snapshot.drainingTombstoneCount == 0, sourceLocation: sourceLocation)
    #expect(snapshot.retainedArtifactByteCount == 0, sourceLocation: sourceLocation)
}
