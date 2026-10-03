import AgentStudioAppIPC
import AgentStudioCLIStore
import AgentStudioProgrammaticControl
import AgentStudioSessions
import Foundation
import GRDB

enum CLILifecycleRefusalReason: String, Equatable, Sendable {
    case invalidStoredRow, qualificationRejected, retiredPane, foreignStore, supersededByUnorderedReport
}

/// Dispositions the immutable CLI prefix through Sessions' existing local transaction owner.
actor CLILifecycleReportIntake: LifecycleReportIntaking {
    private let storeURL: URL
    private let expectedChannel: CLIStoreChannel
    private let admission: AgentStudioIPCSessionsAdapter
    private let sqliteAccess: any SessionsSQLiteAccess
    private let workspaceID: UUID
    private let paneExists: @MainActor @Sendable (UUID, UUID) -> Bool
    private let refusalProbe: @Sendable (CLILifecycleRefusalReason) -> Void
    private var listenerBoundary: LifecycleReportBoundary = .noStore
    // Actor reentrancy must not let a later live request overtake an in-flight prefix.
    private var operationTail: Task<Void, Never>?
    private var launchGate: AsyncStream<Void>.Continuation?
    private let finalRevokedPaneIDs: @Sendable () -> Set<UUID>

    init(
        storeURL: URL, expectedChannel: CLIStoreChannel, admission: AgentStudioIPCSessionsAdapter,
        sqliteAccess: any SessionsSQLiteAccess, workspaceID: UUID,
        paneExists: @escaping @MainActor @Sendable (UUID, UUID) -> Bool,
        finalRevokedPaneIDs: @escaping @Sendable () -> Set<UUID> = { [] },
        awaitsLaunchInitialization: Bool = false,
        refusalProbe: @escaping @Sendable (CLILifecycleRefusalReason) -> Void = { _ in }
    ) {
        self.storeURL = storeURL
        self.expectedChannel = expectedChannel
        self.admission = admission
        self.sqliteAccess = sqliteAccess
        self.workspaceID = workspaceID
        self.paneExists = paneExists
        self.refusalProbe = refusalProbe
        self.finalRevokedPaneIDs = finalRevokedPaneIDs
        if awaitsLaunchInitialization {
            let (stream, continuation) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
            launchGate = continuation
            operationTail = Task { for await _ in stream {} }
        }
    }

    func captureListenerReadyBoundary() async throws -> LifecycleReportBoundary {
        try await serializeOperation { try await self.captureBoundary() }
    }

    func takeIn(through boundary: LifecycleReportBoundary) async throws {
        try await serializeOperation { try await self.drain(through: boundary) }
    }

    func recordLive(paneId: UUID, params: IPCSessionEventParams, provenance: IPCSessionEventProvenance = .matchingPane)
        async throws -> IPCSessionEventResult
    {
        try await serializeOperation {
            try await self.admitLive(paneId: paneId, params: params, provenance: provenance)
        }
    }

    /// App reserves the whole listener/S0/sweep/intake operation before exposing live ingress.
    /// The facade uses the existing readiness protocol without recursively taking the queue.
    func initializeForLaunch(
        _ initialization: @escaping @Sendable (any LifecycleReportIntaking) async -> Void
    ) async {
        if let gate = launchGate {
            await initialization(LaunchIntake(intake: self))
            launchGate = nil
            gate.finish()
        } else {
            try? await serializeOperation { await initialization(LaunchIntake(intake: self)) }
        }
    }

    func finish() async {
        launchGate?.finish()
        launchGate = nil
        await operationTail?.value
        operationTail = nil
    }

    private func serializeOperation<Output: Sendable>(
        _ operation: @escaping @Sendable () async throws -> Output
    ) async throws -> Output {
        let previous = operationTail
        let result = Task {
            await previous?.value
            return try await operation()
        }
        operationTail = Task { _ = try? await result.value }
        return try await result.value
    }

    fileprivate func captureBoundary() async throws -> LifecycleReportBoundary {
        guard let read = try await readStore(after: 0, through: 0) else {
            listenerBoundary = .noStore
            return .noStore
        }
        try await fenceAwaiting(through: read.highWater)
        listenerBoundary = .stored(storeId: read.storeID, sequence: read.highWater)
        return listenerBoundary
    }

    fileprivate func drain(through boundary: LifecycleReportBoundary) async throws {
        guard case .stored(let storeID, let through) = boundary else { return }
        let mark = try await readMark(storeID)
        guard let read = try await readStore(after: mark, through: through), read.storeID == storeID else {
            throw CLIStoreFailure.invalidIdentity
        }
        try await fenceAwaiting(through: read.highWater)
        let items =
            (read.batch.reports.map { LifecycleIntakeItem.report($0) }
            + read.batch.issues.map { LifecycleIntakeItem.invalid($0) }).sorted { $0.sequence < $1.sequence }
        for item in items {
            switch item {
            case .invalid(let issue):
                try await refuse(.invalidStoredRow, storeID: storeID, sequence: issue.sequence)
            case .report(let report):
                _ = try await disposition(report, storeID: storeID)
            }
        }
    }

    private func admitLive(paneId: UUID, params: IPCSessionEventParams, provenance: IPCSessionEventProvenance)
        async throws -> IPCSessionEventResult
    {
        guard let position = params.lifecycleReport else {
            // Reading the fence cannot advance the prefix or admit older rows first.
            let fence = try? await readStore(after: 0, through: 0)?.highWater
            guard await paneExists(paneId, workspaceID), !finalRevokedPaneIDs().contains(paneId) else {
                refusalProbe(.retiredPane)
                return refused(paneId: paneId, params: params)
            }
            let participant = CLILifecycleCursorCommitParticipant(
                storeID: nil, sequence: nil,
                paneID: paneId, ordering: .unordered(fence: fence), finalRevokedPaneIDs: finalRevokedPaneIDs)
            do {
                return try await admission.admitProviderEvent(
                    paneId: paneId, params: params, provenance: provenance, commitParticipant: participant)
            } catch CLILifecycleCommitRefusal.retiredPane {
                refusalProbe(.retiredPane)
                return refused(paneId: paneId, params: params)
            }
        }
        guard position.sequence > 0, position.sequence <= IPCSchemaScalars.maximumExactInteger,
            let read = try await readStore(after: 0, through: 0), read.storeID == position.storeId,
            position.sequence <= read.highWater
        else {
            refusalProbe(.foreignStore)
            return refused(paneId: paneId, params: params)
        }
        let mark = try await readMark(position.storeId)
        guard position.sequence > mark else {
            return .init(paneId: paneId, disposition: .admitted, correlationId: params.correlationId)
        }
        try await fenceAwaiting(through: read.highWater)
        if position.sequence > mark + 1 {
            try await drain(through: .stored(storeId: position.storeId, sequence: position.sequence - 1))
        }
        return try await disposition(
            paneID: paneId, params: params, storeID: position.storeId,
            sequence: position.sequence, recordedAt: nil, provenance: provenance)
    }

    private func disposition(_ report: CLILifecycleReport, storeID: UUID) async throws -> IPCSessionEventResult {
        let record = report.record
        let name: IPCSessionEventName
        let reason: String?
        switch record.event {
        case .sessionStart:
            name = .sessionStart
            reason = nil
        case .sessionEnd(let value):
            name = .sessionEnd
            reason = value
        }
        let params = IPCSessionEventParams(
            handle: "self",
            provider: .init(
                identifier: record.providerIdentifier, version: record.providerVersion, mode: record.providerMode),
            event: .init(
                name: name, conversationId: record.conversationID, turnId: nil, requestId: nil,
                toolId: nil, subagentId: nil, occurrenceId: record.reportID, endReason: reason),
            correlationId: record.correlationID,
            lifecycleReport: .init(storeId: storeID, sequence: report.sequence))
        return try await disposition(
            paneID: record.paneID, params: params, storeID: storeID,
            sequence: report.sequence, recordedAt: record.recordedAt)
    }

    private func disposition(
        paneID: UUID, params: IPCSessionEventParams, storeID: UUID,
        sequence: Int64, recordedAt: Date?, provenance: IPCSessionEventProvenance = .matchingPane
    ) async throws -> IPCSessionEventResult {
        guard await paneExists(paneID, workspaceID), !finalRevokedPaneIDs().contains(paneID) else {
            try await refuse(.retiredPane, storeID: storeID, sequence: sequence)
            return refused(paneId: paneID, params: params)
        }
        // Fence the latest established generation, not whichever old binding was modified last.
        let ordering = try await sqliteAccess.read { database -> (Bool, Int64?) in
            guard
                let row = try Row.fetchOne(
                    database,
                    sql: """
                        SELECT binding.evidence_unordered, binding.unordered_fence_sequence
                        FROM sessions_pane_binding AS binding
                        JOIN sessions_operation AS establishment
                          ON establishment.binding_generation_id = binding.binding_generation_id
                         AND establishment.outcome_kind IN ('bindingEstablished', 'bindingReplaced')
                        WHERE binding.pane_id = ?
                        GROUP BY binding.binding_generation_id
                        ORDER BY MIN(establishment.commit_revision) DESC LIMIT 1
                        """, arguments: [paneID.uuidString])
            else { return (false, nil) }
            return (
                try row.decode(Int.self, forColumn: "evidence_unordered") == 1,
                try row.decode(Int64?.self, forColumn: "unordered_fence_sequence")
            )
        }
        if ordering.0, ordering.1 == nil || sequence <= (ordering.1 ?? Int64.max) {
            try await refuse(.supersededByUnorderedReport, storeID: storeID, sequence: sequence)
            return refused(paneId: paneID, params: params)
        }
        let historical: Bool
        if case .stored(let initialStore, let initialSequence) = listenerBoundary {
            historical = initialStore == storeID && sequence <= initialSequence
        } else {
            historical = false
        }
        let participant = CLILifecycleCursorCommitParticipant(
            storeID: storeID, sequence: sequence,
            paneID: paneID, ordering: .ordered, finalRevokedPaneIDs: finalRevokedPaneIDs)
        let result: IPCSessionEventResult
        do {
            result = try await admission.admitProviderEvent(
                paneId: paneID, params: params, provenance: provenance,
                historicalStart: historical && params.event.name == .sessionStart,
                reportedAt: recordedAt, commitParticipant: participant)
        } catch CLILifecycleCommitRefusal.retiredPane {
            try await refuse(.retiredPane, storeID: storeID, sequence: sequence)
            return refused(paneId: paneID, params: params)
        }
        if result.disposition != .admitted {
            try await refuse(.qualificationRejected, storeID: storeID, sequence: sequence)
        }
        return result
    }

    private func readMark(_ storeID: UUID) async throws -> Int64 {
        try await sqliteAccess.read { try CLILifecycleCursorCommitParticipant.mark(in: $0, storeID: storeID) }
    }

    private func fenceAwaiting(through highWater: Int64) async throws {
        try await sqliteAccess.write {
            try CLILifecycleCursorCommitParticipant.fenceAwaitingBindings(in: $0, through: highWater)
        }
    }

    private func refuse(_ reason: CLILifecycleRefusalReason, storeID: UUID, sequence: Int64) async throws {
        let participant = CLILifecycleCursorCommitParticipant(
            storeID: storeID, sequence: sequence,
            paneID: nil, ordering: .unchanged)
        try await sqliteAccess.write { try participant.commit(in: $0) }
        refusalProbe(reason)
    }

    private func refused(paneId: UUID, params: IPCSessionEventParams) -> IPCSessionEventResult {
        .init(paneId: paneId, disposition: .unqualified, correlationId: params.correlationId)
    }

    private func readStore(after mark: Int64, through boundary: Int64) async throws -> LifecycleStoreRead? {
        try await Self.readStore(url: storeURL, channel: expectedChannel, after: mark, through: boundary)
    }

    @concurrent private nonisolated static func readStore(
        url: URL, channel: CLIStoreChannel,
        after mark: Int64, through boundary: Int64
    ) async throws -> LifecycleStoreRead? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let reader = try CLIStore.openReader(url: url, expectedChannel: channel).get()
        return try LifecycleStoreRead(
            storeID: reader.identity.storeID,
            highWater: reader.lifecycleReportBoundary().get(),
            batch: reader.readLifecycleReports(after: mark, through: boundary).get())
    }
}

private struct LaunchIntake: LifecycleReportIntaking {
    let intake: CLILifecycleReportIntake
    func captureListenerReadyBoundary() async throws -> LifecycleReportBoundary { try await intake.captureBoundary() }
    func takeIn(through boundary: LifecycleReportBoundary) async throws { try await intake.drain(through: boundary) }
}

private struct LifecycleStoreRead: Sendable {
    let storeID: UUID
    let highWater: Int64
    let batch: CLILifecycleReadBatch
}

private enum LifecycleIntakeItem {
    case report(CLILifecycleReport)
    case invalid(CLILifecycleDecodeIssue)
    var sequence: Int64 {
        switch self {
        case .report(let report): report.sequence
        case .invalid(let issue): issue.sequence
        }
    }
}
