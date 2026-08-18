import AgentStudioInfrastructure
import Foundation
import Observation

enum WorktreeAnnotationRecoveryState: Equatable, Sendable {
    case available
    case recoveredDegraded(WorktreeAnnotationRecoveryProvenance)
    case unavailable
}

enum WorktreeAnnotationCommandFailureCode: String, Codable, Equatable, Sendable {
    case conflict
    case editTokenConflict = "edit_token_conflict"
    case invalidSource = "invalid_source"
    case messageLocked = "message_locked"
    case notFound = "not_found"
    case openThreadCountConflict = "open_thread_count_conflict"
    case outputUnavailable = "output_unavailable"
    case recoveryAcknowledgementRequired = "recovery_acknowledgement_required"
    case sessionReadOnly = "session_read_only"
    case sessionSelectionRequired = "session_selection_required"
    case unavailable
    case unexpected
    case unresolvedWorkConfirmationRequired = "unresolved_work_confirmation_required"
}

enum WorktreeAnnotationCommandOutcomeStatus: Equatable, Sendable {
    case committed
    case admissionRequired(WorktreeAnnotationAdmissionChoice)
    case output(WorktreeAnnotationOutputCommandOutcome)
    case failed(WorktreeAnnotationCommandFailureCode)
}

struct WorktreeAnnotationPlacementContextKey: Hashable, Sendable {
    let contextID: String
    let surface: BridgeProductSurface
    let sessionID: WorktreeAnnotationSessionID
}

private struct WorktreeAnnotationPlacementContext: Sendable {
    let sourceEpoch: Int
    let placements: [WorktreeAnnotationThreadID: WorktreeAnnotationThreadPlacementProjection]
}

private struct WorktreeAnnotationSnapshotSubscription {
    let worktreeID: String
    let contextID: String
    let surface: BridgeProductSurface
    let continuation: AsyncStream<WorktreeAnnotationProjectionSnapshot>.Continuation
}

struct WorktreeAnnotationCommandOutcome: Equatable, Sendable {
    let requestID: String
    let surface: BridgeProductSurface
    let sessionID: WorktreeAnnotationSessionID?
    let status: WorktreeAnnotationCommandOutcomeStatus
}

/// Bounded UI projection for durable worktree annotations.
///
/// The repository remains authoritative. This Atom contains demanded session
/// detail, discovery summaries, and bounded output-history summaries only.
/// Exact output bytes and canonical output snapshots remain repository reads.
@MainActor
@Observable
package final class WorktreeAnnotationProjectionAtom {
    private(set) var recoveryState: WorktreeAnnotationRecoveryState = .available
    private(set) var discoveryByWorktreeID: [String: [WorktreeAnnotationSession]] = [:]
    private(set) var detailBySessionID: [WorktreeAnnotationSessionID: WorktreeAnnotationSessionDetail] = [:]
    private(set) var outputHistoryBySessionID: [WorktreeAnnotationSessionID: [WorktreeAnnotationOutputHistorySummary]] =
        [:]
    private(set) var commandOutcomeByRequestID: [String: WorktreeAnnotationCommandOutcome] = [:]
    private var placementByContextKey: [WorktreeAnnotationPlacementContextKey: WorktreeAnnotationPlacementContext] = [:]
    private var commandOutcomeRequestIDsByAge: [String] = []
    private var projectionRevision = 0
    private var snapshotSubscriptions: [UUID: WorktreeAnnotationSnapshotSubscription] = [:]

    package init() {}

    func publishDiscovery(_ sessions: [WorktreeAnnotationSession], worktreeID: String) {
        discoveryByWorktreeID[worktreeID] = Array(
            sessions.suffix(AppPolicies.Bridge.worktreeAnnotationMaximumDiscoverySessions)
        )
        publishSnapshotChange()
    }

    func publish(detail: WorktreeAnnotationSessionDetail) {
        retain(detail: detail)
        publishSnapshotChange()
    }

    func publish(
        detail: WorktreeAnnotationSessionDetail,
        sourceEvaluation: WorktreeAnnotationSourceEvaluationResult,
        contextID: String,
        surface: BridgeProductSurface,
        sourceEpoch: Int
    ) {
        retain(detail: detail)
        placementByContextKey[
            WorktreeAnnotationPlacementContextKey(
                contextID: contextID,
                surface: surface,
                sessionID: detail.session.id
            )
        ] = WorktreeAnnotationPlacementContext(
            sourceEpoch: sourceEpoch,
            placements: sourceEvaluation.placements
        )
        publishSnapshotChange()
    }

    func publish(
        detail: WorktreeAnnotationSessionDetail,
        exactPlacementFor threadID: WorktreeAnnotationThreadID,
        contextID: String,
        surface: BridgeProductSurface
    ) {
        guard
            let thread = detail.threads.first(where: { $0.thread.id == threadID }),
            case .located(let origin) = thread.thread.origin
        else {
            publish(detail: detail)
            return
        }
        retain(detail: detail)
        let contextKey = WorktreeAnnotationPlacementContextKey(
            contextID: contextID,
            surface: surface,
            sessionID: detail.session.id
        )
        let existingContext = placementByContextKey[contextKey]
        var placements = existingContext?.placements ?? [:]
        placements[threadID] = WorktreeAnnotationThreadPlacementProjection(
            placement: .exact,
            currentPath: origin.repositoryRelativePath,
            currentStartLine: origin.startLine,
            currentEndLine: origin.endLine,
            currentSourceIdentity: origin.sourceIdentity
        )
        placementByContextKey[contextKey] = WorktreeAnnotationPlacementContext(
            sourceEpoch: existingContext?.sourceEpoch ?? 0,
            placements: placements
        )
        publishSnapshotChange()
    }

    private func retain(detail: WorktreeAnnotationSessionDetail) {
        detailBySessionID[detail.session.id] = detail
        var discovery = discoveryByWorktreeID[detail.session.worktreeID] ?? []
        if let index = discovery.firstIndex(where: { $0.id == detail.session.id }) {
            discovery[index] = detail.session
        } else {
            discovery.append(detail.session)
            discovery.sort { lhs, rhs in
                if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
                return lhs.id.rawValue.uuidString < rhs.id.rawValue.uuidString
            }
        }
        discoveryByWorktreeID[detail.session.worktreeID] = discovery
    }

    func detail(sessionID: WorktreeAnnotationSessionID?) -> WorktreeAnnotationSessionDetail? {
        guard let sessionID else { return nil }
        return detailBySessionID[sessionID]
    }

    func placement(
        contextID: String,
        surface: BridgeProductSurface,
        sessionID: WorktreeAnnotationSessionID,
        threadID: WorktreeAnnotationThreadID
    ) -> WorktreeAnnotationThreadPlacementProjection? {
        placementByContextKey[
            WorktreeAnnotationPlacementContextKey(
                contextID: contextID,
                surface: surface,
                sessionID: sessionID
            )
        ]?.placements[threadID]
    }

    func placements(
        contextID: String,
        surface: BridgeProductSurface,
        sessionID: WorktreeAnnotationSessionID
    ) -> [WorktreeAnnotationThreadID: WorktreeAnnotationThreadPlacementProjection] {
        placementByContextKey[
            WorktreeAnnotationPlacementContextKey(
                contextID: contextID,
                surface: surface,
                sessionID: sessionID
            )
        ]?.placements ?? [:]
    }

    func evictDetail(sessionID: WorktreeAnnotationSessionID) {
        detailBySessionID.removeValue(forKey: sessionID)
        outputHistoryBySessionID.removeValue(forKey: sessionID)
        placementByContextKey = placementByContextKey.filter { $0.key.sessionID != sessionID }
        publishSnapshotChange()
    }

    func evictAllDetails() {
        detailBySessionID.removeAll()
        outputHistoryBySessionID.removeAll()
        placementByContextKey.removeAll()
        publishSnapshotChange()
    }

    func publishRecoveryState(_ state: WorktreeAnnotationRecoveryState) {
        recoveryState = state
        if state != .available {
            detailBySessionID.removeAll()
            outputHistoryBySessionID.removeAll()
            placementByContextKey.removeAll()
        }
        publishSnapshotChange()
    }

    func publish(commandOutcome: WorktreeAnnotationCommandOutcome) {
        if commandOutcomeByRequestID[commandOutcome.requestID] == nil {
            commandOutcomeRequestIDsByAge.append(commandOutcome.requestID)
        }
        commandOutcomeByRequestID[commandOutcome.requestID] = commandOutcome
        let excessCount =
            commandOutcomeRequestIDsByAge.count
            - AppPolicies.Bridge.worktreeAnnotationMaximumRetainedCommandOutcomes
        if excessCount > 0 {
            for requestID in commandOutcomeRequestIDsByAge.prefix(excessCount) {
                commandOutcomeByRequestID.removeValue(forKey: requestID)
            }
            commandOutcomeRequestIDsByAge.removeFirst(excessCount)
        }
        publishSnapshotChange()
    }

    func publish(
        outputHistory: [WorktreeAnnotationOutputHistorySummary],
        sessionID: WorktreeAnnotationSessionID
    ) {
        let boundedHistory = Array(
            outputHistory.prefix(AppPolicies.Bridge.worktreeAnnotationMaximumOutputHistorySummaries)
        )
        guard boundedHistory.allSatisfy({ $0.sessionID == sessionID }) else { return }
        outputHistoryBySessionID[sessionID] = boundedHistory
        publishSnapshotChange()
    }

    func commandOutcome(requestID: String) -> WorktreeAnnotationCommandOutcome? {
        commandOutcomeByRequestID[requestID]
    }

    func snapshots(
        worktreeID: String,
        contextID: String,
        surface: BridgeProductSurface
    ) -> AsyncStream<WorktreeAnnotationProjectionSnapshot> {
        let subscriptionID = UUIDv7.generate()
        return AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            snapshotSubscriptions[subscriptionID] = WorktreeAnnotationSnapshotSubscription(
                worktreeID: worktreeID,
                contextID: contextID,
                surface: surface,
                continuation: continuation
            )
            continuation.yield(snapshot(worktreeID: worktreeID, contextID: contextID, surface: surface))
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor in
                    self?.snapshotSubscriptions.removeValue(forKey: subscriptionID)
                }
            }
        }
    }

    private func publishSnapshotChange() {
        projectionRevision += 1
        for subscription in snapshotSubscriptions.values {
            subscription.continuation.yield(
                snapshot(
                    worktreeID: subscription.worktreeID,
                    contextID: subscription.contextID,
                    surface: subscription.surface
                )
            )
        }
    }

    private func snapshot(
        worktreeID: String,
        contextID: String,
        surface: BridgeProductSurface
    ) -> WorktreeAnnotationProjectionSnapshot {
        let details = detailBySessionID.values
            .filter { $0.session.worktreeID == worktreeID }
            .sorted { $0.session.createdAt < $1.session.createdAt }
        return WorktreeAnnotationProjectionSnapshot(
            revision: projectionRevision,
            worktreeID: worktreeID,
            recoveryState: recoveryState,
            sessions: discoveryByWorktreeID[worktreeID] ?? [],
            details: details,
            placementsByThreadID: Dictionary(
                uniqueKeysWithValues: details.flatMap { detail in
                    let placements =
                        placementByContextKey[
                            WorktreeAnnotationPlacementContextKey(
                                contextID: contextID,
                                surface: surface,
                                sessionID: detail.session.id
                            )
                        ]?.placements ?? [:]
                    return placements.map { ($0.key, $0.value) }
                }
            ),
            outputHistory: outputHistoryBySessionID.values
                .flatMap { $0 }
                .filter { summary in
                    details.contains { $0.session.id == summary.sessionID }
                }
                .sorted { lhs, rhs in
                    if lhs.createdAt != rhs.createdAt { return lhs.createdAt > rhs.createdAt }
                    return lhs.attemptID.rawValue.uuidString > rhs.attemptID.rawValue.uuidString
                }
                .prefix(AppPolicies.Bridge.worktreeAnnotationMaximumOutputHistorySummaries)
                .map { $0 },
            commandOutcomes: commandOutcomeRequestIDsByAge.compactMap {
                commandOutcomeByRequestID[$0]
            }
        )
    }
}

struct WorktreeAnnotationProjectionSnapshot: Sendable {
    let revision: Int
    let worktreeID: String
    let recoveryState: WorktreeAnnotationRecoveryState
    let sessions: [WorktreeAnnotationSession]
    let details: [WorktreeAnnotationSessionDetail]
    let placementsByThreadID: [WorktreeAnnotationThreadID: WorktreeAnnotationThreadPlacementProjection]
    let outputHistory: [WorktreeAnnotationOutputHistorySummary]
    let commandOutcomes: [WorktreeAnnotationCommandOutcome]
}
