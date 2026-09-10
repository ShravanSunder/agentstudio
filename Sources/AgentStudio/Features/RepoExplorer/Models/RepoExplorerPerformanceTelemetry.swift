import AgentStudioInfrastructure
import Foundation

package enum RepoExplorerPerformanceStage: Int, CaseIterable, Sendable {
    case observeProject
    case distinct
    case coalesce
    case admission
    case execute
    case validate
    case publish
    case materialize
    case deadline
    case eagerAdmission
    case projectionWorker
    case commandAffectedRow
    case commandWholeSurface
    case atomSlot
    case captureRebuild
    case affectedRow
    case membershipPath
    case wholeSurface
    case mainActorApply
    case finalProjection
    case other

    init(traceValue: String) {
        switch traceValue {
        case "observe_project": self = .observeProject
        case "distinct": self = .distinct
        case "coalesce": self = .coalesce
        case "admission": self = .admission
        case "execute": self = .execute
        case "validate": self = .validate
        case "publish": self = .publish
        case "materialize": self = .materialize
        case "deadline": self = .deadline
        case "eager_admission": self = .eagerAdmission
        case "projection_worker": self = .projectionWorker
        case "command_affected_row": self = .commandAffectedRow
        case "command_whole_surface": self = .commandWholeSurface
        case "atom_slot": self = .atomSlot
        case "capture_rebuild": self = .captureRebuild
        case "affected_row": self = .affectedRow
        case "membership_path": self = .membershipPath
        case "whole_surface": self = .wholeSurface
        case "mainactor_apply": self = .mainActorApply
        case "final_projection": self = .finalProjection
        default: self = .other
        }
    }

    var traceValue: String {
        switch self {
        case .observeProject: "observe_project"
        case .distinct: "distinct"
        case .coalesce: "coalesce"
        case .admission: "admission"
        case .execute: "execute"
        case .validate: "validate"
        case .publish: "publish"
        case .materialize: "materialize"
        case .deadline: "deadline"
        case .eagerAdmission: "eager_admission"
        case .projectionWorker: "projection_worker"
        case .commandAffectedRow: "command_affected_row"
        case .commandWholeSurface: "command_whole_surface"
        case .atomSlot: "atom_slot"
        case .captureRebuild: "capture_rebuild"
        case .affectedRow: "affected_row"
        case .membershipPath: "membership_path"
        case .wholeSurface: "whole_surface"
        case .mainActorApply: "mainactor_apply"
        case .finalProjection: "final_projection"
        case .other: "other"
        }
    }
}

package enum RepoExplorerPerformanceOutcome: Int, CaseIterable, Sendable {
    case observed
    case suppressed
    case coalesced
    case admitted
    case executed
    case published
    case materialized
    case equal
    case changed
    case unknown
    case retained
    case replaced
    case deferred
    case rejected
    case capacityLimited
    case started
    case completed
    case current
    case cancelled
    case superseded
    case stale
    case staleGeneration
    case staleOrigin
    case staleScope
    case failed
    case invalidated
    case revoked
    case scheduled
    case rescheduled
    case fired
    case relevantKey
    case referenceEqual
    case referenceDifferent
    case other

    init(traceValue: String) {
        if let outcome = Self.primaryOutcome(traceValue: traceValue) {
            self = outcome
            return
        }
        self = Self.secondaryOutcome(traceValue: traceValue) ?? .other
    }

    private static func primaryOutcome(traceValue: String) -> Self? {
        switch traceValue {
        case "observed": .observed
        case "suppressed": .suppressed
        case "coalesced": .coalesced
        case "admitted": .admitted
        case "executed": .executed
        case "published": .published
        case "materialized": .materialized
        case "equal": .equal
        case "changed": .changed
        case "unknown": .unknown
        case "retained": .retained
        case "replaced": .replaced
        case "deferred": .deferred
        case "rejected": .rejected
        case "capacity_limited", "capacity-limited": .capacityLimited
        case "started": .started
        case "completed": .completed
        default: nil
        }
    }

    private static func secondaryOutcome(traceValue: String) -> Self? {
        switch traceValue {
        case "current": .current
        case "cancelled": .cancelled
        case "superseded": .superseded
        case "stale": .stale
        case "stale_generation", "stale-generation": .staleGeneration
        case "stale_origin", "stale-origin": .staleOrigin
        case "stale_scope", "stale-scope": .staleScope
        case "failed": .failed
        case "invalidated": .invalidated
        case "revoked": .revoked
        case "scheduled": .scheduled
        case "rescheduled": .rescheduled
        case "fired": .fired
        case "relevant_key": .relevantKey
        case "reference_equal": .referenceEqual
        case "reference_different": .referenceDifferent
        default: nil
        }
    }

    var traceValue: String {
        switch self {
        case .observed: "observed"
        case .suppressed: "suppressed"
        case .coalesced: "coalesced"
        case .admitted: "admitted"
        case .executed: "executed"
        case .published: "published"
        case .materialized: "materialized"
        case .equal: "equal"
        case .changed: "changed"
        case .unknown: "unknown"
        case .retained: "retained"
        case .replaced: "replaced"
        case .deferred: "deferred"
        case .rejected: "rejected"
        case .capacityLimited: "capacity_limited"
        case .started: "started"
        case .completed: "completed"
        case .current: "current"
        case .cancelled: "cancelled"
        case .superseded: "superseded"
        case .stale: "stale"
        case .staleGeneration: "stale_generation"
        case .staleOrigin: "stale_origin"
        case .staleScope: "stale_scope"
        case .failed: "failed"
        case .invalidated: "invalidated"
        case .revoked: "revoked"
        case .scheduled: "scheduled"
        case .rescheduled: "rescheduled"
        case .fired: "fired"
        case .relevantKey: "relevant_key"
        case .referenceEqual: "reference_equal"
        case .referenceDifferent: "reference_different"
        case .other: "other"
        }
    }
}

package struct RepoExplorerPerformanceStageOutcomeCount: Equatable, Sendable {
    package let stage: RepoExplorerPerformanceStage
    package let outcome: RepoExplorerPerformanceOutcome
    package let count: UInt64
}

package struct RepoExplorerPerformanceSnapshot: Equatable, Sendable {
    package let stageOutcomeCounts: [RepoExplorerPerformanceStageOutcomeCount]
    package let totalRecordedOutcomeCount: UInt64
    package let exactAttributionAdmittedRecordCount: UInt64
    package let exactAttributionCapacityLimitedCount: UInt64

    package func count(
        stage: RepoExplorerPerformanceStage,
        outcome: RepoExplorerPerformanceOutcome
    ) -> UInt64 {
        stageOutcomeCounts.first {
            $0.stage == stage && $0.outcome == outcome
        }?.count ?? 0
    }
}

struct RepoExplorerPerformanceAccumulator {
    private static let outcomeCount = RepoExplorerPerformanceOutcome.allCases.count
    private static let counterCount =
        RepoExplorerPerformanceStage.allCases.count * RepoExplorerPerformanceOutcome.allCases.count

    private var stageOutcomeCounts = [UInt64](repeating: 0, count: counterCount)
    private var stageSequences = [UInt64](repeating: 0, count: RepoExplorerPerformanceStage.allCases.count)
    private var exactAttributionAdmissionLimit: UInt64 = 0
    private var exactAttributionLifetimeAdmittedRecordCount: UInt64 = 0
    private var exactRowBodyLifetimeAdmittedRecordCount: UInt64 = 0
    private var exactAttributionIntervalAdmittedRecordCount: UInt64 = 0
    private var exactAttributionIntervalCapacityLimitedCount: UInt64 = 0

    mutating func configureExactAttributionAdmissionLimit(_ limit: Int) {
        exactAttributionAdmissionLimit = UInt64(max(0, limit))
        exactAttributionLifetimeAdmittedRecordCount = 0
        exactRowBodyLifetimeAdmittedRecordCount = 0
    }

    mutating func record(
        stageValue: String,
        outcomeValue: String
    ) -> (stage: RepoExplorerPerformanceStage, outcome: RepoExplorerPerformanceOutcome) {
        let stage = RepoExplorerPerformanceStage(traceValue: stageValue)
        let outcome = RepoExplorerPerformanceOutcome(traceValue: outcomeValue)
        let counterIndex = Self.counterIndex(stage: stage, outcome: outcome)
        stageOutcomeCounts[counterIndex] &+= 1
        stageSequences[stage.rawValue] &+= 1
        return (stage, outcome)
    }

    mutating func admitExactAttributionRecord() -> Bool {
        guard exactAttributionLifetimeAdmittedRecordCount < exactAttributionAdmissionLimit else {
            exactAttributionIntervalCapacityLimitedCount &+= 1
            return false
        }
        exactAttributionLifetimeAdmittedRecordCount &+= 1
        exactAttributionIntervalAdmittedRecordCount &+= 1
        return true
    }

    mutating func admitExactRowBodyRecord() -> Bool {
        guard exactRowBodyLifetimeAdmittedRecordCount < exactAttributionAdmissionLimit else {
            exactAttributionIntervalCapacityLimitedCount &+= 1
            return false
        }
        exactRowBodyLifetimeAdmittedRecordCount &+= 1
        return true
    }

    func sequence(for stageValue: String) -> UInt64 {
        stageSequences[RepoExplorerPerformanceStage(traceValue: stageValue).rawValue]
    }

    mutating func snapshotAndReset() -> RepoExplorerPerformanceSnapshot {
        var nonzeroCounts: [RepoExplorerPerformanceStageOutcomeCount] = []
        var totalRecordedOutcomeCount: UInt64 = 0
        for stage in RepoExplorerPerformanceStage.allCases {
            for outcome in RepoExplorerPerformanceOutcome.allCases {
                let counterIndex = Self.counterIndex(stage: stage, outcome: outcome)
                let count = stageOutcomeCounts[counterIndex]
                guard count > 0 else { continue }
                totalRecordedOutcomeCount &+= count
                nonzeroCounts.append(
                    RepoExplorerPerformanceStageOutcomeCount(
                        stage: stage,
                        outcome: outcome,
                        count: count
                    )
                )
            }
        }

        let snapshot = RepoExplorerPerformanceSnapshot(
            stageOutcomeCounts: nonzeroCounts,
            totalRecordedOutcomeCount: totalRecordedOutcomeCount,
            exactAttributionAdmittedRecordCount: exactAttributionIntervalAdmittedRecordCount,
            exactAttributionCapacityLimitedCount: exactAttributionIntervalCapacityLimitedCount
        )
        for counterIndex in stageOutcomeCounts.indices {
            stageOutcomeCounts[counterIndex] = 0
        }
        exactAttributionIntervalAdmittedRecordCount = 0
        exactAttributionIntervalCapacityLimitedCount = 0
        return snapshot
    }

    private static func counterIndex(
        stage: RepoExplorerPerformanceStage,
        outcome: RepoExplorerPerformanceOutcome
    ) -> Int {
        stage.rawValue * outcomeCount + outcome.rawValue
    }
}

@MainActor
package final class RepoExplorerPerformanceTelemetry {
    package static let shared = RepoExplorerPerformanceTelemetry()

    private var traceRuntime: AgentStudioTraceRuntime?
    private var eventQueue: AgentStudioTraceEventQueue?
    private weak var performanceTraceRecorder: AgentStudioPerformanceTraceRecorder?
    private var periodicReporterToken: UUID?
    private var keyClass: String?
    private var facet: String?
    private var rowRelation: String?
    private var accumulator = RepoExplorerPerformanceAccumulator()

    private init() {}

    package func configure(
        traceRuntime: AgentStudioTraceRuntime?,
        performanceTraceRecorder: AgentStudioPerformanceTraceRecorder?,
        exactAttributionAdmissionLimit: Int = AppPolicies.Diagnostics.repoExplorerExactAttributionRecordLimit
    ) {
        if let periodicReporterToken, let existingRecorder = self.performanceTraceRecorder {
            existingRecorder.unregisterPeriodicSnapshotReporter(periodicReporterToken)
        }
        self.traceRuntime = traceRuntime
        self.performanceTraceRecorder = performanceTraceRecorder
        accumulator.configureExactAttributionAdmissionLimit(exactAttributionAdmissionLimit)
        if let traceRuntime, traceRuntime.isEnabled(.performance) {
            eventQueue = AgentStudioTraceEventQueue(traceRuntime: traceRuntime)
        } else {
            eventQueue = nil
        }
        periodicReporterToken = performanceTraceRecorder?.registerPeriodicSnapshotReporter { [weak self] in
            self?.flushSnapshot()
        }
    }

    package func setContext(keyClass: String?, facet: String? = nil, rowRelation: String? = nil) {
        self.keyClass = keyClass
        self.facet = facet
        self.rowRelation = rowRelation
    }

    package var isContextActive: Bool { keyClass != nil }

    package func admitExactRowBodyRecord() -> Bool {
        guard keyClass != nil, traceRuntime?.isEnabled(.performance) == true else { return false }
        return accumulator.admitExactRowBodyRecord()
    }

    package func sequence(for stage: String) -> UInt64 {
        accumulator.sequence(for: stage)
    }

    package func record(stage: String, outcome: String) {
        guard let traceRuntime, traceRuntime.isEnabled(.performance), let eventQueue else { return }
        let controlledValue = accumulator.record(stageValue: stage, outcomeValue: outcome)
        guard let keyClass, accumulator.admitExactAttributionRecord() else { return }
        var attributes: [String: AgentStudioTraceValue] = [
            "agentstudio.performance.repo_explorer.stage": .string(controlledValue.stage.traceValue),
            "agentstudio.performance.repo_explorer.key_class": .string(keyClass),
            "agentstudio.performance.repo_explorer.outcome": .string(controlledValue.outcome.traceValue),
        ]
        if let facet { attributes["agentstudio.performance.repo_explorer.facet"] = .string(facet) }
        if let rowRelation {
            attributes["agentstudio.performance.repo_explorer.row_relation"] = .string(rowRelation)
        }
        eventQueue.record(
            tag: .performance,
            body: AgentStudioPerformanceTraceRecorder.Event.repoExplorerKeyedWake.rawValue,
            eventTimeUnixNano: traceRuntime.timestampUnixNano(),
            attributes: attributes
        )
    }

    package func snapshotAndReset() -> RepoExplorerPerformanceSnapshot {
        accumulator.snapshotAndReset()
    }

    package func drainForTests() async throws {
        try await eventQueue?.drain()
        if eventQueue == nil { try await traceRuntime?.flush() }
    }

    package func resetForTests() {
        if let periodicReporterToken, let performanceTraceRecorder {
            performanceTraceRecorder.unregisterPeriodicSnapshotReporter(periodicReporterToken)
        }
        eventQueue?.cancel()
        traceRuntime = nil
        eventQueue = nil
        performanceTraceRecorder = nil
        periodicReporterToken = nil
        keyClass = nil
        facet = nil
        rowRelation = nil
        accumulator = RepoExplorerPerformanceAccumulator()
    }

    package func flushSnapshot() {
        guard let performanceTraceRecorder else { return }
        let snapshot = accumulator.snapshotAndReset()
        for count in snapshot.stageOutcomeCounts {
            performanceTraceRecorder.record(
                .repoExplorerStageSnapshot,
                attributes: [
                    "agentstudio.performance.repo_explorer.stage": .string(count.stage.traceValue),
                    "agentstudio.performance.repo_explorer.outcome": .string(count.outcome.traceValue),
                    "agentstudio.performance.repo_explorer.interval.count": .int(
                        count.count > UInt64(Int.max) ? Int.max : Int(count.count)
                    ),
                ]
            )
        }
        if snapshot.exactAttributionCapacityLimitedCount > 0 {
            performanceTraceRecorder.record(
                .repoExplorerStageSnapshot,
                attributes: [
                    "agentstudio.performance.repo_explorer.stage": .string("admission"),
                    "agentstudio.performance.repo_explorer.outcome": .string("capacity_limited"),
                    "agentstudio.performance.repo_explorer.interval.count": .int(
                        snapshot.exactAttributionCapacityLimitedCount > UInt64(Int.max)
                            ? Int.max : Int(snapshot.exactAttributionCapacityLimitedCount)
                    ),
                ]
            )
        }
    }
}
