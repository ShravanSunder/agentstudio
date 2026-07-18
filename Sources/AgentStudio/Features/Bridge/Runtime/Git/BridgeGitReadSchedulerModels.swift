@preconcurrency import Dispatch
import Foundation

enum BridgeGitReadOperationClass: String, CaseIterable, Sendable {
    case reviewMetadata
    case selectedVisibleContent
}

enum BridgeGitReadActivityRank: Int, Comparable, Sendable {
    case unranked
    case dormant
    case loadedHidden
    case foreground

    static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var telemetryToken: String {
        switch self {
        case .unranked:
            return "unranked"
        case .dormant:
            return "dormant"
        case .loadedHidden:
            return "loaded_hidden"
        case .foreground:
            return "foreground"
        }
    }
}

struct BridgeGitReadWorktreeKey: Hashable, Sendable {
    let token: String
}

struct BridgeGitReadScopeKey: Hashable, Sendable {
    let token: String
}

struct BridgeGitReadPaneKey: Hashable, Sendable {
    let token: String
}

struct BridgeGitReadCoalescingKey: Hashable, Sendable {
    let token: String
}

struct BridgeGitReadFreshnessKey: Hashable, Sendable {
    let token: String

    static let unversioned = Self(token: "unversioned")
}

struct BridgeGitReadSlotID: Hashable, Sendable {
    let token: String
}

struct BridgeGitReadSchedulerTopology: Sendable {
    let slotsByOperationClass: [BridgeGitReadOperationClass: [BridgeGitReadSlotID]]
    let maximumQueuedOperationCountByClass: [BridgeGitReadOperationClass: Int]
    let maximumLogicalWaiterCountPerOperation: Int

    init(
        slotsByOperationClass: [BridgeGitReadOperationClass: [BridgeGitReadSlotID]],
        maximumQueuedOperationCountByClass: [BridgeGitReadOperationClass: Int],
        maximumLogicalWaiterCountPerOperation: Int
    ) {
        for operationClass in BridgeGitReadOperationClass.allCases {
            precondition(!(slotsByOperationClass[operationClass] ?? []).isEmpty)
            precondition((maximumQueuedOperationCountByClass[operationClass] ?? 0) > 0)
        }
        precondition(maximumLogicalWaiterCountPerOperation > 0)
        let allSlotIds = slotsByOperationClass.values.flatMap { $0 }
        precondition(Set(allSlotIds).count == allSlotIds.count)
        self.slotsByOperationClass = slotsByOperationClass
        self.maximumQueuedOperationCountByClass = maximumQueuedOperationCountByClass
        self.maximumLogicalWaiterCountPerOperation = maximumLogicalWaiterCountPerOperation
    }
}

extension BridgeGitReadSchedulerTopology {
    /// Symbolic recovery topology. S10b owns numeric calibration and may replace
    /// these named peer opportunities only from measured blocked-read workloads.
    static let recoveryBaseline = Self(
        slotsByOperationClass: [
            .reviewMetadata: [
                BridgeGitReadSlotID(token: "review-metadata-interactive"),
                BridgeGitReadSlotID(token: "review-metadata-peer"),
            ],
            .selectedVisibleContent: [
                BridgeGitReadSlotID(token: "selected-content-interactive"),
                BridgeGitReadSlotID(token: "visible-content-peer"),
            ],
        ],
        maximumQueuedOperationCountByClass: [
            .reviewMetadata: AppPolicies.Bridge.gitReadSchedulerMaxQueuedOperationsPerClass,
            .selectedVisibleContent: AppPolicies.Bridge.gitReadSchedulerMaxQueuedOperationsPerClass,
        ],
        maximumLogicalWaiterCountPerOperation: AppPolicies.Bridge.gitReadSchedulerMaxLogicalWaitersPerOperation
    )
}

struct BridgeGitReadContext: Sendable {
    let scheduler: BridgeGitReadScheduler
    let worktreeKey: BridgeGitReadWorktreeKey
    let scopeKey: BridgeGitReadScopeKey

    init(
        scheduler: BridgeGitReadScheduler,
        worktreeKey: BridgeGitReadWorktreeKey,
        scopeKey: BridgeGitReadScopeKey
    ) {
        self.scheduler = scheduler
        self.worktreeKey = worktreeKey
        self.scopeKey = scopeKey
    }

    init(
        scheduler: BridgeGitReadScheduler,
        worktreeKey: BridgeGitReadWorktreeKey
    ) {
        self.init(
            scheduler: scheduler,
            worktreeKey: worktreeKey,
            scopeKey: BridgeGitReadScopeKey(token: worktreeKey.token)
        )
    }
}

struct BridgeGitReadRequest: Sendable {
    let worktreeKey: BridgeGitReadWorktreeKey
    let operationClass: BridgeGitReadOperationClass
    let coalescingKey: BridgeGitReadCoalescingKey
    let freshnessKey: BridgeGitReadFreshnessKey
    let deadline: Duration
}

enum BridgeGitReadSchedulerError: Error, Equatable, Sendable {
    case timedOut
    case capacityReached
    case closed
    case resultTypeMismatch
}

enum BridgeGitReadFailure {
    static let timeoutMessage = "Bridge Git data-plane read timed out"
    static let capacityMessage = "Bridge Git data-plane read capacity reached"
}

protocol BridgeGitReadDeadlineScheduling: Sendable {
    func schedule(
        after duration: Duration,
        _ handler: @escaping @Sendable () -> Void
    ) -> BridgeGitReadScheduledDeadline
}

struct BridgeGitReadScheduledDeadline: Sendable {
    private let box: BridgeGitReadScheduledDeadlineBox

    init(cancel: @escaping @Sendable () -> Void) {
        box = BridgeGitReadScheduledDeadlineBox(cancel: cancel)
    }

    func cancel() {
        box.cancel()
    }
}

private final class BridgeGitReadScheduledDeadlineBox: @unchecked Sendable {
    private let lock = NSLock()
    private let cancelHandler: @Sendable () -> Void
    private var didCancel = false

    init(cancel: @escaping @Sendable () -> Void) {
        cancelHandler = cancel
    }

    func cancel() {
        lock.lock()
        guard !didCancel else {
            lock.unlock()
            return
        }
        didCancel = true
        lock.unlock()
        cancelHandler()
    }
}

struct DispatchBridgeGitReadDeadlineScheduler: BridgeGitReadDeadlineScheduling {
    private static let queue = DispatchQueue(
        label: "com.agentstudio.bridge.git-read-deadline",
        qos: .userInitiated
    )

    func schedule(
        after duration: Duration,
        _ handler: @escaping @Sendable () -> Void
    ) -> BridgeGitReadScheduledDeadline {
        let workItem = DispatchWorkItem(block: handler)
        Self.queue.asyncAfter(
            deadline: .now() + Self.dispatchInterval(for: duration),
            execute: workItem
        )
        return BridgeGitReadScheduledDeadline {
            workItem.cancel()
        }
    }

    private static func dispatchInterval(for duration: Duration) -> DispatchTimeInterval {
        let components = duration.components
        let seconds = components.seconds.multipliedReportingOverflow(by: 1_000_000_000)
        let total = seconds.partialValue.addingReportingOverflow(components.attoseconds / 1_000_000_000)
        guard !seconds.overflow, !total.overflow else { return .seconds(Int.max) }
        guard total.partialValue > 0 else { return .nanoseconds(0) }
        guard total.partialValue <= Int64(Int.max) else { return .seconds(Int.max) }
        return .nanoseconds(Int(total.partialValue))
    }
}

enum BridgeGitReadSchedulerLifecycle: String, Sendable {
    case active
    case closing
    case closed
}

enum BridgeGitReadSchedulerEventKind: String, Sendable {
    case queued
    case coalesced
    case started
    case logicalTimeout
    case logicalCancellation
    case draining
    case physicallyReturned
    case slotReleased
}

struct BridgeGitReadSchedulerEvent: Sendable {
    let kind: BridgeGitReadSchedulerEventKind
    let operationId: UInt64
    let slotId: BridgeGitReadSlotID?
    let operationClass: BridgeGitReadOperationClass
    let worktreeKey: BridgeGitReadWorktreeKey
    let activityRank: BridgeGitReadActivityRank
    let queueWait: Duration?
    let snapshot: BridgeGitReadSchedulerSnapshot
}

typealias BridgeGitReadSchedulerEventSink = @Sendable (BridgeGitReadSchedulerEvent) -> Void

struct BridgeGitReadSchedulerSnapshot: Sendable {
    let lifecycle: BridgeGitReadSchedulerLifecycle
    let queuedCountByOperationClass: [BridgeGitReadOperationClass: Int]
    let runningCountByOperationClass: [BridgeGitReadOperationClass: Int]
    let drainingCountByOperationClass: [BridgeGitReadOperationClass: Int]
    let activeOperationIds: Set<UInt64>
    let occupiedSlotIds: Set<BridgeGitReadSlotID>
    let logicalWaiterCount: Int
    let coalescedLogicalWaiterCount: Int
    let scheduledDeadlineCount: Int
    let admittedWorktreeKeys: Set<BridgeGitReadWorktreeKey>
    let paneActivityCount: Int
    let fairnessHistoryCount: Int
}
