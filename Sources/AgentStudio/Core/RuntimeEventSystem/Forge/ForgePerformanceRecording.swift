import AgentStudioInfrastructure

package enum ForgePerformanceInput: Sendable {
    case automatic
    case manual
    case followUp
}

package enum ForgePerformanceAdmissionOutcome: Sendable {
    case admitted
    case noDemandRejected
    case missingOriginRejected
    case activeRequestCoalesced
    case capacityLimited
    case freshnessDeferred
    case backoffDeferred
}

package enum ForgePerformanceExecutionOutcome: Sendable {
    case started
    case completed
    case failed
    case cancelled
    case superseded
}

package enum ForgePerformanceValidationOutcome: Sendable {
    case current
    case staleGeneration
    case staleOrigin
    case staleScope
}

package enum ForgePerformancePublicationOutcome: Sendable {
    case published
    case equal
    case invalidated
}

package enum ForgePerformanceDeadlineOutcome: Sendable {
    case scheduled
    case rescheduled
    case fired
    case cancelled
}

package struct ForgePerformanceSnapshot: Equatable, Sendable {
    package struct Inputs: Equatable, Sendable {
        package let automatic: UInt64
        package let manual: UInt64
        package let followUp: UInt64
    }

    package struct Admission: Equatable, Sendable {
        package let admitted: UInt64
        package let noDemandRejected: UInt64
        package let missingOriginRejected: UInt64
        package let activeRequestCoalesced: UInt64
        package let capacityLimited: UInt64
        package let freshnessDeferred: UInt64
        package let backoffDeferred: UInt64
    }

    package struct Execution: Equatable, Sendable {
        package let started: UInt64
        package let completed: UInt64
        package let failed: UInt64
        package let cancelled: UInt64
        package let superseded: UInt64
    }

    package struct Validation: Equatable, Sendable {
        package let current: UInt64
        package let staleGeneration: UInt64
        package let staleOrigin: UInt64
        package let staleScope: UInt64
    }

    package struct Publication: Equatable, Sendable {
        package let published: UInt64
        package let equal: UInt64
        package let invalidated: UInt64
    }

    package struct Deadline: Equatable, Sendable {
        package let scheduled: UInt64
        package let rescheduled: UInt64
        package let fired: UInt64
        package let cancelled: UInt64
    }

    package struct Query: Equatable, Sendable {
        package let demandedBranchCount: UInt64
        package let aliasBatchCount: UInt64
        package let returnedNodeCount: UInt64
        package let completePlan: UInt64
        package let rejectedPlan: UInt64
    }

    package struct Recovery: Equatable, Sendable {
        package let rateLimited: UInt64
        package let unavailable: UInt64
        package let recovered: UInt64
    }

    package struct Physical: Equatable, Sendable {
        package let activeMaximum: UInt64
        package let pendingMaximum: UInt64
    }

    package let inputs: Inputs
    package let admission: Admission
    package let execution: Execution
    package let validation: Validation
    package let publication: Publication
    package let deadline: Deadline
    package let query: Query
    package let recovery: Recovery
    package let physical: Physical

    package var isEmpty: Bool { self == .zero }

    static let zero = Self(
        inputs: Inputs(automatic: 0, manual: 0, followUp: 0),
        admission: Admission(
            admitted: 0,
            noDemandRejected: 0,
            missingOriginRejected: 0,
            activeRequestCoalesced: 0,
            capacityLimited: 0,
            freshnessDeferred: 0,
            backoffDeferred: 0
        ),
        execution: Execution(started: 0, completed: 0, failed: 0, cancelled: 0, superseded: 0),
        validation: Validation(current: 0, staleGeneration: 0, staleOrigin: 0, staleScope: 0),
        publication: Publication(published: 0, equal: 0, invalidated: 0),
        deadline: Deadline(scheduled: 0, rescheduled: 0, fired: 0, cancelled: 0),
        query: Query(
            demandedBranchCount: 0, aliasBatchCount: 0, returnedNodeCount: 0, completePlan: 0, rejectedPlan: 0),
        recovery: Recovery(rateLimited: 0, unavailable: 0, recovered: 0),
        physical: Physical(activeMaximum: 0, pendingMaximum: 0)
    )
}

package struct ForgePerformanceAccumulator: Sendable {
    private var inputAutomatic: UInt64 = 0
    private var inputManual: UInt64 = 0
    private var inputFollowUp: UInt64 = 0
    private var admissionAdmitted: UInt64 = 0
    private var admissionNoDemandRejected: UInt64 = 0
    private var admissionMissingOriginRejected: UInt64 = 0
    private var admissionActiveRequestCoalesced: UInt64 = 0
    private var admissionCapacityLimited: UInt64 = 0
    private var admissionFreshnessDeferred: UInt64 = 0
    private var admissionBackoffDeferred: UInt64 = 0
    private var executionStarted: UInt64 = 0
    private var executionCompleted: UInt64 = 0
    private var executionFailed: UInt64 = 0
    private var executionCancelled: UInt64 = 0
    private var executionSuperseded: UInt64 = 0
    private var validationCurrent: UInt64 = 0
    private var validationStaleGeneration: UInt64 = 0
    private var validationStaleOrigin: UInt64 = 0
    private var validationStaleScope: UInt64 = 0
    private var publicationPublished: UInt64 = 0
    private var publicationEqual: UInt64 = 0
    private var publicationInvalidated: UInt64 = 0
    private var deadlineScheduled: UInt64 = 0
    private var deadlineRescheduled: UInt64 = 0
    private var deadlineFired: UInt64 = 0
    private var deadlineCancelled: UInt64 = 0
    private var queryDemandedBranchCount: UInt64 = 0
    private var queryAliasBatchCount: UInt64 = 0
    private var queryReturnedNodeCount: UInt64 = 0
    private var queryCompletePlan: UInt64 = 0
    private var queryRejectedPlan: UInt64 = 0
    private var recoveryRateLimited: UInt64 = 0
    private var recoveryUnavailable: UInt64 = 0
    private var recoveryRecovered: UInt64 = 0
    private var physicalActiveMaximum: UInt64 = 0
    private var physicalPendingMaximum: UInt64 = 0

    package init() {}

    package mutating func recordInput(_ input: ForgePerformanceInput) {
        switch input {
        case .automatic: Self.increment(&inputAutomatic)
        case .manual: Self.increment(&inputManual)
        case .followUp: Self.increment(&inputFollowUp)
        }
    }

    package mutating func recordAdmission(_ outcome: ForgePerformanceAdmissionOutcome) {
        switch outcome {
        case .admitted: Self.increment(&admissionAdmitted)
        case .noDemandRejected: Self.increment(&admissionNoDemandRejected)
        case .missingOriginRejected: Self.increment(&admissionMissingOriginRejected)
        case .activeRequestCoalesced: Self.increment(&admissionActiveRequestCoalesced)
        case .capacityLimited: Self.increment(&admissionCapacityLimited)
        case .freshnessDeferred: Self.increment(&admissionFreshnessDeferred)
        case .backoffDeferred: Self.increment(&admissionBackoffDeferred)
        }
    }

    package mutating func recordExecution(_ outcome: ForgePerformanceExecutionOutcome) {
        switch outcome {
        case .started: Self.increment(&executionStarted)
        case .completed: Self.increment(&executionCompleted)
        case .failed: Self.increment(&executionFailed)
        case .cancelled: Self.increment(&executionCancelled)
        case .superseded: Self.increment(&executionSuperseded)
        }
    }

    package mutating func recordValidation(_ outcome: ForgePerformanceValidationOutcome) {
        switch outcome {
        case .current: Self.increment(&validationCurrent)
        case .staleGeneration: Self.increment(&validationStaleGeneration)
        case .staleOrigin: Self.increment(&validationStaleOrigin)
        case .staleScope: Self.increment(&validationStaleScope)
        }
    }

    package mutating func recordPublication(_ outcome: ForgePerformancePublicationOutcome) {
        switch outcome {
        case .published: Self.increment(&publicationPublished)
        case .equal: Self.increment(&publicationEqual)
        case .invalidated: Self.increment(&publicationInvalidated)
        }
    }

    package mutating func recordDeadline(_ outcome: ForgePerformanceDeadlineOutcome) {
        switch outcome {
        case .scheduled: Self.increment(&deadlineScheduled)
        case .rescheduled: Self.increment(&deadlineRescheduled)
        case .fired: Self.increment(&deadlineFired)
        case .cancelled: Self.increment(&deadlineCancelled)
        }
    }

    package mutating func recordQueryPlan(demandedBranchCount: Int, aliasBatchCount: Int) {
        Self.add(demandedBranchCount, to: &queryDemandedBranchCount)
        Self.add(aliasBatchCount, to: &queryAliasBatchCount)
    }

    package mutating func recordQueryOutcome(_ outcome: ForgePullRequestQueryOutcome) {
        switch outcome {
        case .complete(let pullRequests):
            Self.add(pullRequests.count, to: &queryReturnedNodeCount)
            Self.increment(&queryCompletePlan)
        case .truncated, .rateLimited, .failed:
            Self.increment(&queryRejectedPlan)
        }
        if case .rateLimited = outcome {
            Self.increment(&recoveryRateLimited)
        }
    }

    package mutating func recordUnavailableTransition() {
        Self.increment(&recoveryUnavailable)
    }

    package mutating func recordRecovery() {
        Self.increment(&recoveryRecovered)
    }

    package mutating func recordPhysicalState(active: Int, pending: Int) {
        physicalActiveMaximum = max(physicalActiveMaximum, UInt64(clamping: active))
        physicalPendingMaximum = max(physicalPendingMaximum, UInt64(clamping: pending))
    }

    package mutating func takeSnapshot() -> ForgePerformanceSnapshot {
        let snapshot = ForgePerformanceSnapshot(
            inputs: .init(automatic: inputAutomatic, manual: inputManual, followUp: inputFollowUp),
            admission: .init(
                admitted: admissionAdmitted,
                noDemandRejected: admissionNoDemandRejected,
                missingOriginRejected: admissionMissingOriginRejected,
                activeRequestCoalesced: admissionActiveRequestCoalesced,
                capacityLimited: admissionCapacityLimited,
                freshnessDeferred: admissionFreshnessDeferred,
                backoffDeferred: admissionBackoffDeferred
            ),
            execution: .init(
                started: executionStarted,
                completed: executionCompleted,
                failed: executionFailed,
                cancelled: executionCancelled,
                superseded: executionSuperseded
            ),
            validation: .init(
                current: validationCurrent,
                staleGeneration: validationStaleGeneration,
                staleOrigin: validationStaleOrigin,
                staleScope: validationStaleScope
            ),
            publication: .init(
                published: publicationPublished,
                equal: publicationEqual,
                invalidated: publicationInvalidated
            ),
            deadline: .init(
                scheduled: deadlineScheduled,
                rescheduled: deadlineRescheduled,
                fired: deadlineFired,
                cancelled: deadlineCancelled
            ),
            query: .init(
                demandedBranchCount: queryDemandedBranchCount,
                aliasBatchCount: queryAliasBatchCount,
                returnedNodeCount: queryReturnedNodeCount,
                completePlan: queryCompletePlan,
                rejectedPlan: queryRejectedPlan
            ),
            recovery: .init(
                rateLimited: recoveryRateLimited,
                unavailable: recoveryUnavailable,
                recovered: recoveryRecovered
            ),
            physical: .init(
                activeMaximum: physicalActiveMaximum,
                pendingMaximum: physicalPendingMaximum
            )
        )
        self = Self()
        return snapshot
    }

    private static func increment(_ value: inout UInt64) {
        if value < .max { value += 1 }
    }

    private static func add(_ increment: Int, to value: inout UInt64) {
        guard increment > 0 else { return }
        let increment = UInt64(increment)
        value = value > UInt64.max - increment ? .max : value + increment
    }
}

package protocol ForgePerformanceRecording: Sendable {
    func recordForgePerformanceSnapshot(_ snapshot: ForgePerformanceSnapshot)
}

extension AgentStudioPerformanceTraceRecorder: ForgePerformanceRecording {
    package func recordForgePerformanceSnapshot(_ snapshot: ForgePerformanceSnapshot) {
        guard !snapshot.isEmpty else { return }
        record(
            .forgeRefresh,
            attributes: [
                "agentstudio.performance.forge.input.automatic.count": Self.forgeTraceInteger(
                    snapshot.inputs.automatic),
                "agentstudio.performance.forge.input.manual.count": Self.forgeTraceInteger(snapshot.inputs.manual),
                "agentstudio.performance.forge.input.follow_up.count": Self.forgeTraceInteger(snapshot.inputs.followUp),
                "agentstudio.performance.forge.admission.admitted.count": Self.forgeTraceInteger(
                    snapshot.admission.admitted),
                "agentstudio.performance.forge.admission.no_demand_rejected.count": Self.forgeTraceInteger(
                    snapshot.admission.noDemandRejected),
                "agentstudio.performance.forge.admission.missing_origin_rejected.count": Self.forgeTraceInteger(
                    snapshot.admission.missingOriginRejected),
                "agentstudio.performance.forge.admission.active_request_coalesced.count": Self.forgeTraceInteger(
                    snapshot.admission.activeRequestCoalesced),
                "agentstudio.performance.forge.admission.capacity_limited.count": Self.forgeTraceInteger(
                    snapshot.admission.capacityLimited),
                "agentstudio.performance.forge.admission.freshness_deferred.count": Self.forgeTraceInteger(
                    snapshot.admission.freshnessDeferred),
                "agentstudio.performance.forge.admission.backoff_deferred.count": Self.forgeTraceInteger(
                    snapshot.admission.backoffDeferred),
                "agentstudio.performance.forge.execution.started.count": Self.forgeTraceInteger(
                    snapshot.execution.started),
                "agentstudio.performance.forge.execution.completed.count": Self.forgeTraceInteger(
                    snapshot.execution.completed),
                "agentstudio.performance.forge.execution.failed.count": Self.forgeTraceInteger(
                    snapshot.execution.failed),
                "agentstudio.performance.forge.execution.cancelled.count": Self.forgeTraceInteger(
                    snapshot.execution.cancelled),
                "agentstudio.performance.forge.execution.superseded.count": Self.forgeTraceInteger(
                    snapshot.execution.superseded),
                "agentstudio.performance.forge.validation.current.count": Self.forgeTraceInteger(
                    snapshot.validation.current),
                "agentstudio.performance.forge.validation.stale_generation.count": Self.forgeTraceInteger(
                    snapshot.validation.staleGeneration),
                "agentstudio.performance.forge.validation.stale_origin.count": Self.forgeTraceInteger(
                    snapshot.validation.staleOrigin),
                "agentstudio.performance.forge.validation.stale_scope.count": Self.forgeTraceInteger(
                    snapshot.validation.staleScope),
                "agentstudio.performance.forge.publication.published.count": Self.forgeTraceInteger(
                    snapshot.publication.published),
                "agentstudio.performance.forge.publication.equal.count": Self.forgeTraceInteger(
                    snapshot.publication.equal),
                "agentstudio.performance.forge.publication.invalidated.count": Self.forgeTraceInteger(
                    snapshot.publication.invalidated),
                "agentstudio.performance.forge.deadline.scheduled.count": Self.forgeTraceInteger(
                    snapshot.deadline.scheduled),
                "agentstudio.performance.forge.deadline.rescheduled.count": Self.forgeTraceInteger(
                    snapshot.deadline.rescheduled),
                "agentstudio.performance.forge.deadline.fired.count": Self.forgeTraceInteger(snapshot.deadline.fired),
                "agentstudio.performance.forge.deadline.cancelled.count": Self.forgeTraceInteger(
                    snapshot.deadline.cancelled),
                "agentstudio.performance.forge.query.demanded_branch.count": Self.forgeTraceInteger(
                    snapshot.query.demandedBranchCount),
                "agentstudio.performance.forge.query.alias_batch.count": Self.forgeTraceInteger(
                    snapshot.query.aliasBatchCount),
                "agentstudio.performance.forge.query.returned_node.count": Self.forgeTraceInteger(
                    snapshot.query.returnedNodeCount),
                "agentstudio.performance.forge.query.complete_plan.count": Self.forgeTraceInteger(
                    snapshot.query.completePlan),
                "agentstudio.performance.forge.query.rejected_plan.count": Self.forgeTraceInteger(
                    snapshot.query.rejectedPlan),
                "agentstudio.performance.forge.recovery.rate_limited.count": Self.forgeTraceInteger(
                    snapshot.recovery.rateLimited),
                "agentstudio.performance.forge.recovery.unavailable.count": Self.forgeTraceInteger(
                    snapshot.recovery.unavailable),
                "agentstudio.performance.forge.recovery.recovered.count": Self.forgeTraceInteger(
                    snapshot.recovery.recovered),
                "agentstudio.performance.forge.physical.active.maximum": Self.forgeTraceInteger(
                    snapshot.physical.activeMaximum),
                "agentstudio.performance.forge.physical.pending.maximum": Self.forgeTraceInteger(
                    snapshot.physical.pendingMaximum),
            ]
        )
    }

    private static func forgeTraceInteger(_ value: UInt64) -> AgentStudioTraceValue {
        .int(value > UInt64(Int.max) ? Int.max : Int(value))
    }
}
