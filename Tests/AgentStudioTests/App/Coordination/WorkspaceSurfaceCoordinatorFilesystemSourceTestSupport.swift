import Foundation
import GhosttyKit

@testable import AgentStudio
@testable import AgentStudioCore
@testable import AgentStudioInfrastructure
@testable import AgentStudioTerminal
@testable import AgentStudioTestSupport

func paneFilesystemEnvelope(
    pane: Pane,
    context: PaneFilesystemContext,
    sequence: UInt64
) -> RuntimeEnvelope {
    .pane(
        PaneEnvelope(
            source: .pane(context.paneId),
            seq: sequence,
            timestamp: .now,
            paneId: context.paneId,
            paneKind: pane.metadata.contentType,
            event: .paneFilesystemContext(
                .cwdSubtreeChanged(context: context, paths: ["Sources/App.swift"], batchSeq: sequence)
            )
        )
    )
}

@MainActor
struct FilesystemCoordinatorHarness {
    let store: WorkspaceStore
    let bus: EventBus<RuntimeEnvelope>
    let tempDir: URL

    func makeSubscriber() async -> RecordingSubscriber<RuntimeEnvelope> {
        let stream = await bus.subscribe(policy: .criticalUnbounded, subscriberName: #function)
        return RecordingSubscriber(stream: stream)
    }

    func shutdown() async {
        try? FileManager.default.removeItem(at: tempDir)
    }
}

enum FilesystemSourceOperation: Sendable, Equatable {
    case register(worktreeId: UUID)
    case unregister(worktreeId: UUID)
    case activity(worktreeId: UUID, isActiveInApp: Bool)
    case activePane(worktreeId: UUID?)
    case sidebarVisibleWorktrees(worktreeIds: Set<UUID>)
    case assertTopology(worktreeIds: Set<UUID>)

    var registeredWorktreeId: UUID? {
        guard case .register(let worktreeId) = self else { return nil }
        return worktreeId
    }

    var kind: FilesystemSourceOperationKind {
        switch self {
        case .register:
            .register
        case .unregister:
            .unregister
        case .activity:
            .activity
        case .activePane:
            .activePane
        case .sidebarVisibleWorktrees:
            .sidebarVisibleWorktrees
        case .assertTopology:
            .assertTopology
        }
    }

    var isRegister: Bool {
        if case .register = self { return true }
        return false
    }

    var isActivity: Bool {
        if case .activity = self { return true }
        return false
    }

    var isActivePane: Bool {
        if case .activePane = self { return true }
        return false
    }

    var isAssertTopology: Bool {
        if case .assertTopology = self { return true }
        return false
    }

    var assertedTopologyWorktreeIds: Set<UUID>? {
        guard case .assertTopology(let worktreeIds) = self else { return nil }
        return worktreeIds
    }
}

enum FilesystemSourceOperationKind: Sendable, Equatable {
    case register
    case unregister
    case activity
    case activePane
    case sidebarVisibleWorktrees
    case assertTopology
}

struct OrderedFilesystemSourceSnapshot: Sendable {
    let registeredRoots: [UUID: URL]
    let activityByWorktreeId: [UUID: Bool]
    let activePaneWorktreeId: UUID?
}

actor OrderedRecordingFilesystemSource: WorkspaceFilesystemSourceManaging {
    private var registeredRoots: [UUID: URL] = [:]
    private var activityByWorktreeId: [UUID: Bool] = [:]
    private var activePaneWorktreeId: UUID?
    private var operationLog: [FilesystemSourceOperation] = []
    private var operationWaiters: [FilesystemSourceOperationKind: [CheckedContinuation<Void, Never>]] = [:]
    private var operationCountWaiters: [(Int, CheckedContinuation<Void, Never>)] = []
    private var topologyWaiters: [(Set<UUID>, CheckedContinuation<Void, Never>)] = []
    private var topologyCountWaiters: [(Int, CheckedContinuation<Void, Never>)] = []
    private var shouldPauseNextUnregister = false
    private var pausedUnregisterWaiters: [CheckedContinuation<Void, Never>] = []
    private var resumeUnregisterWaiters: [CheckedContinuation<Void, Never>] = []

    func start() async {}

    func shutdown() async {}

    func register(worktreeId: UUID, repoId _: UUID, rootPath: URL) async {
        registeredRoots[worktreeId] = rootPath
        appendOperation(.register(worktreeId: worktreeId))
    }

    func unregister(worktreeId: UUID) async {
        registeredRoots.removeValue(forKey: worktreeId)
        activityByWorktreeId.removeValue(forKey: worktreeId)
        if activePaneWorktreeId == worktreeId {
            activePaneWorktreeId = nil
        }
        appendOperation(.unregister(worktreeId: worktreeId))
        guard shouldPauseNextUnregister else { return }
        shouldPauseNextUnregister = false
        let waiters = pausedUnregisterWaiters
        pausedUnregisterWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
        await withCheckedContinuation { continuation in
            resumeUnregisterWaiters.append(continuation)
        }
    }

    func assertTopology(_ assertion: FilesystemTopologyAssertion) async {
        let desiredWorktreeIds = Set(assertion.contextsByWorktreeId.keys)
        registeredRoots = assertion.contextsByWorktreeId.mapValues(\.rootPath)
        activityByWorktreeId = activityByWorktreeId.filter { desiredWorktreeIds.contains($0.key) }
        if let activePaneWorktreeId, !desiredWorktreeIds.contains(activePaneWorktreeId) {
            self.activePaneWorktreeId = nil
        }
        appendOperation(.assertTopology(worktreeIds: desiredWorktreeIds))
    }

    func setActivity(worktreeId: UUID, isActiveInApp: Bool) async {
        activityByWorktreeId[worktreeId] = isActiveInApp
        appendOperation(.activity(worktreeId: worktreeId, isActiveInApp: isActiveInApp))
    }

    func setActivePaneWorktree(worktreeId: UUID?) async {
        activePaneWorktreeId = worktreeId
        appendOperation(.activePane(worktreeId: worktreeId))
    }

    func setSidebarVisibleWorktrees(_ worktreeIds: Set<UUID>) async {
        appendOperation(.sidebarVisibleWorktrees(worktreeIds: worktreeIds))
    }

    func snapshot() -> OrderedFilesystemSourceSnapshot {
        OrderedFilesystemSourceSnapshot(
            registeredRoots: registeredRoots,
            activityByWorktreeId: activityByWorktreeId,
            activePaneWorktreeId: activePaneWorktreeId
        )
    }

    func pauseNextUnregister() {
        shouldPauseNextUnregister = true
    }

    func waitForPausedUnregister() async {
        guard shouldPauseNextUnregister else { return }
        await withCheckedContinuation { continuation in
            pausedUnregisterWaiters.append(continuation)
        }
    }

    func resumePausedUnregister() {
        let waiters = resumeUnregisterWaiters
        resumeUnregisterWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
    }

    func operations() -> [FilesystemSourceOperation] {
        operationLog
    }

    func resetOperations() {
        operationLog.removeAll(keepingCapacity: true)
    }

    func operationKinds() -> [FilesystemSourceOperationKind] {
        operationLog.map { operation in
            switch operation {
            case .register:
                .register
            case .unregister:
                .unregister
            case .activity:
                .activity
            case .activePane:
                .activePane
            case .sidebarVisibleWorktrees:
                .sidebarVisibleWorktrees
            case .assertTopology:
                .assertTopology
            }
        }
    }

    func waitForOperation(_ kind: FilesystemSourceOperationKind) async {
        guard !operationKinds().contains(kind) else { return }
        await withCheckedContinuation { continuation in
            operationWaiters[kind, default: []].append(continuation)
        }
    }

    func waitForOperationCount(_ count: Int) async {
        guard operationLog.count < count else { return }
        await withCheckedContinuation { continuation in
            operationCountWaiters.append((count, continuation))
        }
    }

    func waitForAssertTopology(worktreeIds: Set<UUID>) async {
        if operationLog.contains(.assertTopology(worktreeIds: worktreeIds)) { return }
        await withCheckedContinuation { continuation in
            topologyWaiters.append((worktreeIds, continuation))
        }
    }

    func waitForAssertTopologyCount(atLeast minimumCount: Int) async {
        if assertTopologyCount >= minimumCount { return }
        await withCheckedContinuation { continuation in
            topologyCountWaiters.append((minimumCount, continuation))
        }
    }

    private func appendOperation(_ operation: FilesystemSourceOperation) {
        operationLog.append(operation)
        let kind = operation.kind
        let waiters = operationWaiters.removeValue(forKey: kind) ?? []
        for waiter in waiters {
            waiter.resume()
        }
        var remainingCountWaiters: [(Int, CheckedContinuation<Void, Never>)] = []
        for (expectedCount, continuation) in operationCountWaiters {
            if operationLog.count >= expectedCount {
                continuation.resume()
            } else {
                remainingCountWaiters.append((expectedCount, continuation))
            }
        }
        operationCountWaiters = remainingCountWaiters
        guard case .assertTopology(let worktreeIds) = operation else { return }
        var remainingTopologyCountWaiters: [(Int, CheckedContinuation<Void, Never>)] = []
        let currentAssertTopologyCount = assertTopologyCount
        for (minimumCount, continuation) in topologyCountWaiters {
            if currentAssertTopologyCount >= minimumCount {
                continuation.resume()
            } else {
                remainingTopologyCountWaiters.append((minimumCount, continuation))
            }
        }
        topologyCountWaiters = remainingTopologyCountWaiters
        var remainingWaiters: [(Set<UUID>, CheckedContinuation<Void, Never>)] = []
        for (expectedWorktreeIds, continuation) in topologyWaiters {
            if expectedWorktreeIds == worktreeIds {
                continuation.resume()
            } else {
                remainingWaiters.append((expectedWorktreeIds, continuation))
            }
        }
        topologyWaiters = remainingWaiters
    }

    private var assertTopologyCount: Int {
        operationLog.filter(\.isAssertTopology).count
    }
}

actor GateableFilesystemProjectionIndex: WorkspaceFilesystemProjectionIndexing {
    private let base = FilesystemProjectionIndex()
    private var commitFailuresRemaining = 0
    private var sourceSyncPauseCount = 0
    private var projectionPauseCount = 0
    private var pausedSourceSyncCount = 0
    private var pausedProjectionCount = 0
    private var pausedSourceSyncContinuations: [CheckedContinuation<Void, Never>] = []
    private var resumeSourceSyncContinuations: [CheckedContinuation<Void, Never>] = []
    private var pausedProjectionContinuations: [CheckedContinuation<Void, Never>] = []
    private var resumeProjectionContinuations: [CheckedContinuation<Void, Never>] = []
    private var recordedShutdownInvocationCount = 0
    private var shutdownWaiters: [CheckedContinuation<Void, Never>] = []

    func shutdown() async {
        recordedShutdownInvocationCount += 1
        let waiters = shutdownWaiters
        shutdownWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
        resumePausedProjection()
        await base.shutdown()
    }

    func waitForShutdown() async {
        guard recordedShutdownInvocationCount == 0 else { return }
        await withCheckedContinuation { continuation in
            shutdownWaiters.append(continuation)
        }
    }

    func shutdownInvocationCount() -> Int {
        recordedShutdownInvocationCount
    }

    func pauseNextSourceSync() {
        sourceSyncPauseCount += 1
    }

    func pauseNextProjection() {
        projectionPauseCount += 1
    }

    func failNextCommit() {
        commitFailuresRemaining += 1
    }

    func waitForPausedSourceSync() async {
        guard pausedSourceSyncCount == 0 else { return }
        await withCheckedContinuation { continuation in
            pausedSourceSyncContinuations.append(continuation)
        }
    }

    func waitForPausedProjection() async {
        guard pausedProjectionCount == 0 else { return }
        await withCheckedContinuation { continuation in
            pausedProjectionContinuations.append(continuation)
        }
    }

    func resumePausedSourceSync() {
        let continuations = resumeSourceSyncContinuations
        resumeSourceSyncContinuations.removeAll()
        pausedSourceSyncCount = 0
        for continuation in continuations {
            continuation.resume()
        }
    }

    func resumePausedProjection() {
        let continuations = resumeProjectionContinuations
        resumeProjectionContinuations.removeAll()
        pausedProjectionCount = 0
        for continuation in continuations {
            continuation.resume()
        }
    }

    func reconcileSourceSync(_ request: FilesystemSourceSyncRequest) async -> FilesystemSourceSyncDiff {
        if sourceSyncPauseCount > 0 {
            sourceSyncPauseCount -= 1
            pausedSourceSyncCount += 1
            for continuation in pausedSourceSyncContinuations {
                continuation.resume()
            }
            pausedSourceSyncContinuations.removeAll()
            await withCheckedContinuation { continuation in
                resumeSourceSyncContinuations.append(continuation)
            }
        }
        return await base.reconcileSourceSync(request)
    }

    func commitSourceSync(requestGeneration: UInt64, topologyGeneration: UInt64) async -> Bool {
        if commitFailuresRemaining > 0 {
            commitFailuresRemaining -= 1
            return false
        }
        return await base.commitSourceSync(requestGeneration: requestGeneration, topologyGeneration: topologyGeneration)
    }

    func applyPaneUpdate(_ update: FilesystemProjectionPaneUpdate) async -> FilesystemProjectionPaneUpdateOutcome {
        await base.applyPaneUpdate(update)
    }

    func projectPaneFilesystem(_ request: PaneFilesystemProjectionRequest) async -> PaneFilesystemProjectionResult {
        if projectionPauseCount > 0 {
            projectionPauseCount -= 1
            pausedProjectionCount += 1
            for continuation in pausedProjectionContinuations {
                continuation.resume()
            }
            pausedProjectionContinuations.removeAll()
            await withCheckedContinuation { continuation in
                resumeProjectionContinuations.append(continuation)
            }
        }
        return await base.projectPaneFilesystem(request)
    }
}

@MainActor
final class MockFilesystemCoordinatorSurfaceManager: WorkspaceSurfaceManaging {
    func syncFocus(activeSurfaceId _: UUID?) {}

    func createSurface(
        config _: Ghostty.SurfaceConfiguration,
        metadata _: SurfaceMetadata
    ) -> Result<ManagedSurface, SurfaceError> {
        .failure(.ghosttyNotInitialized)
    }

    @discardableResult
    func attach(_: UUID, to _: UUID) -> Ghostty.SurfaceView? { nil }

    func detach(_: UUID, reason _: SurfaceDetachReason) {}

    func undoClose() -> ManagedSurface? { nil }

    func requeueUndo(_: UUID) {}

    func destroy(_: UUID) {}
}
