import Foundation

@MainActor
package final class AtomPerformanceTelemetry {
    package static let shared = AtomPerformanceTelemetry()

    private var traceRuntime: AgentStudioTraceRuntime?
    private var eventQueue: AgentStudioTraceEventQueue?
    private var now: @MainActor @Sendable () -> ContinuousClock.Instant = { ContinuousClock().now }
    private var readAdmission = AtomReadTraceAdmission()

    private init() {}

    package func configure(
        traceRuntime: AgentStudioTraceRuntime?,
        now: @escaping @MainActor @Sendable () -> ContinuousClock.Instant = { ContinuousClock().now }
    ) {
        self.traceRuntime = traceRuntime
        self.now = now
        self.readAdmission = AtomReadTraceAdmission()
        // Must match `record`'s gate exactly. Constructing the queue for
        // `.performance` built an object that nothing could ever feed, because
        // only `.atoms` admits an atom record.
        if let traceRuntime, traceRuntime.isEnabled(.atoms) {
            self.eventQueue = AgentStudioTraceEventQueue(traceRuntime: traceRuntime)
        } else {
            self.eventQueue = nil
        }
    }

    /// Exposed so the suite can pin the invariant that the queue exists exactly
    /// when `record` is able to feed it. The two conditions drifted apart once.
    var isEventQueueActive: Bool {
        eventQueue != nil
    }

    func resetForTests() {
        eventQueue?.cancel()
        traceRuntime = nil
        eventQueue = nil
        now = { ContinuousClock().now }
        readAdmission = AtomReadTraceAdmission()
    }

    func drainForTests() async throws {
        try await eventQueue?.drain()
        if eventQueue == nil {
            try await traceRuntime?.flush()
        }
    }

    /// Reads are the highest-frequency call in the atom layer, so this path
    /// sheds under a windowed admission budget. Mutation and derived events stay
    /// unsampled: those are already bounded by write frequency.
    func recordRead(
        kind: String,
        label: String,
        operation: String,
        slotCount: Int? = nil,
        cachedKeyCount: Int? = nil,
        cacheHit: Bool? = nil
    ) {
        // Check the tag before the admitter so a disabled tag does not advance
        // admission state, and so the shed count reported to a debugging
        // session covers only reads the tag was actually watching.
        guard let traceRuntime, traceRuntime.isEnabled(.atoms), eventQueue != nil else { return }
        guard
            let shedReadCount = readAdmission.admit(
                now: now(),
                window: AppPolicies.Diagnostics.atomReadTraceAdmissionWindow,
                limit: AppPolicies.Diagnostics.atomReadTraceAdmissionLimit
            )
        else { return }

        record(
            .atomRead,
            kind: kind,
            label: label,
            operation: operation,
            slotCount: slotCount,
            cachedKeyCount: cachedKeyCount,
            cacheHit: cacheHit,
            shedReadCount: shedReadCount
        )
    }

    func recordMutation(
        kind: String,
        label: String,
        operation: String,
        acceptedChangeCount: Int,
        slotCount: Int? = nil,
        cachedKeyCount: Int? = nil
    ) {
        record(
            .atomMutation,
            kind: kind,
            label: label,
            operation: operation,
            acceptedChangeCount: acceptedChangeCount,
            slotCount: slotCount,
            cachedKeyCount: cachedKeyCount
        )
    }

    func recordDerived(
        operation: String,
        inputRevisionCount: Int,
        cacheHit: Bool
    ) {
        record(
            .atomDerived,
            kind: "derived_value",
            label: nil,
            operation: operation,
            inputRevisionCount: inputRevisionCount,
            cacheHit: cacheHit
        )
    }

    func recordEagerDerivedFamily(
        label: String,
        operation: String,
        outcome: String? = nil
    ) {
        record(
            .atomDerived,
            kind: "eager_derived_family",
            label: label,
            operation: operation,
            outcome: outcome
        )
    }

    private func record(
        _ event: AgentStudioPerformanceTraceRecorder.Event,
        kind: String,
        label: String?,
        operation: String,
        acceptedChangeCount: Int? = nil,
        slotCount: Int? = nil,
        cachedKeyCount: Int? = nil,
        inputRevisionCount: Int? = nil,
        cacheHit: Bool? = nil,
        outcome: String? = nil,
        shedReadCount: Int? = nil
    ) {
        guard let traceRuntime, traceRuntime.isEnabled(.atoms), let eventQueue else { return }
        var attributes: [String: AgentStudioTraceValue] = [
            "agentstudio.performance.atom.kind": .string(kind),
            "agentstudio.performance.atom.operation": .string(operation),
        ]
        if let label {
            attributes["agentstudio.performance.atom.label"] = .string(label)
        }
        if let acceptedChangeCount {
            attributes["agentstudio.performance.atom.accepted_change.count"] = .int(acceptedChangeCount)
        }
        if let slotCount {
            attributes["agentstudio.performance.atom.slot.count"] = .int(slotCount)
        }
        if let cachedKeyCount {
            attributes["agentstudio.performance.atom.cached_key.count"] = .int(cachedKeyCount)
        }
        if let inputRevisionCount {
            attributes["agentstudio.performance.atom.input_revision.count"] = .int(inputRevisionCount)
        }
        if let cacheHit {
            attributes["agentstudio.performance.atom.cache_hit"] = .bool(cacheHit)
        }
        if let outcome {
            attributes["agentstudio.performance.atom.outcome"] = .string(outcome)
        }
        if let shedReadCount {
            // Without this the sampled stream cannot be told apart from a quiet
            // one, which would make the `atoms` tag misleading for the focused
            // debugging it exists to serve.
            attributes["agentstudio.performance.atom.shed_read.count"] = .int(shedReadCount)
        }
        eventQueue.record(
            tag: .atoms,
            body: event.rawValue,
            eventTimeUnixNano: traceRuntime.timestampUnixNano(),
            attributes: attributes
        )
    }
}

/// Windowed admission for atom read telemetry, mirroring the trace recorder's
/// pane-association and topology-lookup admitters. Reads are the highest
/// frequency call in the atom layer, so the `atoms` tag must shed rather than
/// emit one record per read.
private struct AtomReadTraceAdmission {
    private var windowStart: ContinuousClock.Instant?
    private var admittedInWindow = 0
    private var shedSinceLastAdmitted = 0

    /// Returns the number of reads shed since the previous admitted read when
    /// this read is admitted, and `nil` when this read must be shed.
    mutating func admit(
        now: ContinuousClock.Instant,
        window: Duration,
        limit: Int
    ) -> Int? {
        resetWindowIfNeeded(now: now, window: window)
        guard admittedInWindow < limit else {
            shedSinceLastAdmitted += 1
            return nil
        }
        admittedInWindow += 1
        defer { shedSinceLastAdmitted = 0 }
        return shedSinceLastAdmitted
    }

    private mutating func resetWindowIfNeeded(now: ContinuousClock.Instant, window: Duration) {
        guard let windowStart else {
            self.windowStart = now
            admittedInWindow = 0
            return
        }
        guard windowStart.duration(to: now) >= window else { return }
        self.windowStart = now
        admittedInWindow = 0
    }
}
