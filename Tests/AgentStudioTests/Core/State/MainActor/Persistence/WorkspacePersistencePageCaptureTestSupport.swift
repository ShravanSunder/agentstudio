import Foundation
import Synchronization

@testable import AgentStudio

enum PageCaptureTestParticipantID: String, Equatable, Hashable, Sendable {
    case alpha
    case beta
    case gamma
}

struct PageCaptureTestKey: Equatable, Hashable, Sendable {
    let rawValue: String

    init(_ rawValue: String) {
        self.rawValue = rawValue
    }
}

struct PageCaptureTestValue: Equatable, Sendable {
    let payload: String
    let byteCount: Int
}

@MainActor
final class PageCaptureTestSource {
    private(set) var orderedKeys: [PageCaptureTestKey]
    private(set) var readKeys: [PageCaptureTestKey] = []
    private(set) var sizedKeys: [PageCaptureTestKey] = []
    private var valuesByKey: [PageCaptureTestKey: PageCaptureTestValue]
    private var estimatedByteCountAction: (() -> Void)?

    init(entries: [(PageCaptureTestKey, PageCaptureTestValue)]) {
        orderedKeys = entries.map(\.0)
        valuesByKey = Dictionary(uniqueKeysWithValues: entries)
    }

    func storedValue(
        for key: PageCaptureTestKey
    ) -> WorkspaceStateSnapshotStoredValue<PageCaptureTestValue> {
        readKeys.append(key)
        guard let value = valuesByKey[key] else { return .absent }
        return .value(value)
    }

    func byteCount(
        for key: PageCaptureTestKey,
        storedValue: WorkspaceStateSnapshotStoredValue<PageCaptureTestValue>
    ) -> Int {
        sizedKeys.append(key)
        estimatedByteCountAction?()
        return switch storedValue {
        case .value(let value):
            value.byteCount
        case .absent:
            key.rawValue.utf8.count
        }
    }

    func replaceValue(for key: PageCaptureTestKey, with value: PageCaptureTestValue) {
        valuesByKey[key] = value
    }

    func removeValue(for key: PageCaptureTestKey) {
        valuesByKey.removeValue(forKey: key)
    }

    func performWhenEstimatingByteCount(_ action: @escaping () -> Void) {
        estimatedByteCountAction = action
    }
}

@MainActor
struct PageCaptureTestParticipantFixture {
    let registration:
        WorkspaceStateSnapshotPagerParticipant<
            PageCaptureTestParticipantID,
            PageCaptureTestKey,
            PageCaptureTestValue
        >
    let keyedParticipant:
        WorkspaceStateSnapshotKeyedParticipant<
            PageCaptureTestKey,
            PageCaptureTestValue
        >
    let source: PageCaptureTestSource
}

@MainActor
struct PageCapturePagerFixture {
    let pager:
        WorkspaceStateSnapshotPager<
            PageCaptureTestParticipantID,
            PageCaptureTestKey,
            PageCaptureTestValue
        >
    let workRecords: PageCaptureWorkRecordRecorder
    let workInvalidities: PageCaptureWorkInvalidityRecorder
    let workLedger: MainActorWorkLedger
}

@MainActor
final class PageCaptureWorkRecordRecorder {
    private(set) var records: [MainActorWorkRecord] = []

    func record(_ record: MainActorWorkRecord) {
        records.append(record)
    }
}

@MainActor
final class PageCaptureWorkInvalidityRecorder {
    private(set) var invalidities: [MainActorWorkInvalidity] = []

    func record(_ invalidity: MainActorWorkInvalidity) {
        invalidities.append(invalidity)
    }
}

final class PageCaptureIncrementingClock: PerformanceMonotonicClock, Sendable {
    private let nextNanosecond = Mutex<UInt64>(0)

    func now() -> PerformanceMonotonicInstant {
        nextNanosecond.withLock { nextNanosecond in
            nextNanosecond += 10
            return PerformanceMonotonicInstant(uptimeNanoseconds: nextNanosecond)
        }
    }
}

final class PageCaptureScriptedClock: PerformanceMonotonicClock, Sendable {
    private let instants: Mutex<[UInt64]>

    init(_ instants: [UInt64]) {
        self.instants = Mutex(instants)
    }

    func now() -> PerformanceMonotonicInstant {
        instants.withLock { instants in
            precondition(!instants.isEmpty, "scripted page-capture clock exhausted")
            return PerformanceMonotonicInstant(uptimeNanoseconds: instants.removeFirst())
        }
    }
}

@MainActor
func makeParticipant(
    _ participantID: PageCaptureTestParticipantID,
    values: [(key: String, payload: String, byteCount: Int)]
) -> PageCaptureTestParticipantFixture {
    let source = PageCaptureTestSource(
        entries: values.map {
            (
                PageCaptureTestKey($0.key),
                PageCaptureTestValue(payload: $0.payload, byteCount: $0.byteCount)
            )
        }
    )
    let keyedParticipant = WorkspaceStateSnapshotKeyedParticipant<
        PageCaptureTestKey,
        PageCaptureTestValue
    >()
    let registration = WorkspaceStateSnapshotPagerParticipant(
        participantID: participantID,
        keyedParticipant: keyedParticipant,
        orderedBaseKeys: { source.orderedKeys },
        currentValue: { key in source.storedValue(for: key) },
        estimatedByteCount: { key, storedValue in
            source.byteCount(for: key, storedValue: storedValue)
        }
    )
    return PageCaptureTestParticipantFixture(
        registration: registration,
        keyedParticipant: keyedParticipant,
        source: source
    )
}

@MainActor
func makePagerFixture(
    revisionOwner: WorkspacePersistenceRevisionOwner? = nil,
    leaseAuthority: WorkspaceStateSnapshotPagerLeaseAuthority? = nil,
    participants: [PageCaptureTestParticipantFixture],
    workLedgerClock: any PerformanceMonotonicClock = PageCaptureIncrementingClock(),
    serviceClock: any PerformanceMonotonicClock = PageCaptureIncrementingClock()
) -> PageCapturePagerFixture {
    let resolvedRevisionOwner = revisionOwner ?? WorkspacePersistenceRevisionOwner()
    let resolvedLeaseAuthority =
        leaseAuthority
        ?? WorkspaceStateSnapshotPagerLeaseAuthority(revisionOwner: resolvedRevisionOwner)
    let ledger = MainActorWorkLedger(clock: workLedgerClock)
    let workRecords = PageCaptureWorkRecordRecorder()
    let workInvalidities = PageCaptureWorkInvalidityRecorder()
    let pager = WorkspaceStateSnapshotPager(
        pagerIdentity: .make(),
        revisionOwner: resolvedRevisionOwner,
        leaseAuthority: resolvedLeaseAuthority,
        participants: participants.map(\.registration),
        workLedger: ledger,
        workRecordObserver: workRecords.record,
        workInvalidityObserver: workInvalidities.record,
        serviceClock: serviceClock
    )
    return PageCapturePagerFixture(
        pager: pager,
        workRecords: workRecords,
        workInvalidities: workInvalidities,
        workLedger: ledger
    )
}

func requireLimits(
    maximumItems: Int,
    maximumBytes: Int,
    maximumScannedItems: Int = 64,
    maximumParticipantInspections: Int = 32,
    maximumSynchronousServiceNanoseconds: UInt64 = 1_000_000
) -> WorkspaceStateSnapshotPageLimits {
    let result = WorkspaceStateSnapshotPageLimits.validated(
        maximumItems: maximumItems,
        maximumBytes: maximumBytes,
        maximumScannedItems: maximumScannedItems,
        maximumParticipantInspections: maximumParticipantInspections,
        maximumSynchronousServiceNanoseconds: maximumSynchronousServiceNanoseconds
    )
    guard case .valid(let limits) = result else {
        preconditionFailure("test requires valid snapshot page limits")
    }
    return limits
}

@MainActor
func takePage(
    _ pager: WorkspaceStateSnapshotPager<
        PageCaptureTestParticipantID,
        PageCaptureTestKey,
        PageCaptureTestValue
    >,
    lease: WorkspaceStateSnapshotLease,
    limits: WorkspaceStateSnapshotPageLimits
) -> WorkspaceStateSnapshotPageTakeResult<
    PageCaptureTestParticipantID,
    PageCaptureTestKey,
    PageCaptureTestValue
> {
    let requestResult = pager.makePageCaptureRequest(lease: lease, limits: limits)
    guard case .requested(let request) = requestResult else {
        preconditionFailure("expected page capture request ticket")
    }
    return pager.takePage(request)
}

nonisolated func makeAndAbandonPageCaptureRequest(
    pager: WorkspaceStateSnapshotPager<
        PageCaptureTestParticipantID,
        PageCaptureTestKey,
        PageCaptureTestValue
    >,
    lease: WorkspaceStateSnapshotLease,
    limits: WorkspaceStateSnapshotPageLimits
) {
    let request = pager.makePageCaptureRequest(lease: lease, limits: limits)
    withExtendedLifetime(request) {}
}

func requireOpenedLease(
    _ result: WorkspaceStateSnapshotPagerOpenResult
) -> WorkspaceStateSnapshotLease {
    guard case .opened(let lease) = result else {
        preconditionFailure("expected snapshot lease to open")
    }
    return lease
}

func isOpened(_ result: WorkspaceStateSnapshotPagerOpenResult) -> Bool {
    guard case .opened = result else { return false }
    return true
}

func requireCapturedPage(
    _ result: WorkspaceStateSnapshotPageTakeResult<
        PageCaptureTestParticipantID,
        PageCaptureTestKey,
        PageCaptureTestValue
    >
) -> WorkspaceStateSnapshotPage<
    PageCaptureTestParticipantID,
    PageCaptureTestKey,
    PageCaptureTestValue
> {
    guard case .page(let page) = result else {
        preconditionFailure("expected newly captured snapshot page")
    }
    return page
}

func requireReplayedPage(
    _ result: WorkspaceStateSnapshotPageTakeResult<
        PageCaptureTestParticipantID,
        PageCaptureTestKey,
        PageCaptureTestValue
    >
) -> WorkspaceStateSnapshotPage<
    PageCaptureTestParticipantID,
    PageCaptureTestKey,
    PageCaptureTestValue
> {
    guard case .replayed(let page) = result else {
        preconditionFailure("expected retained snapshot page replay")
    }
    return page
}

func isCapturedPage(
    _ result: WorkspaceStateSnapshotPageTakeResult<
        PageCaptureTestParticipantID,
        PageCaptureTestKey,
        PageCaptureTestValue
    >
) -> Bool {
    guard case .page = result else { return false }
    return true
}

func requireExhaustion(
    _ result: WorkspaceStateSnapshotPageTakeResult<
        PageCaptureTestParticipantID,
        PageCaptureTestKey,
        PageCaptureTestValue
    >
) -> WorkspaceStateSnapshotExhaustionReceipt {
    guard case .exhausted(let receipt) = result else {
        preconditionFailure("expected snapshot pager exhaustion")
    }
    return receipt
}

func requireYieldedProgress(
    _ result: WorkspaceStateSnapshotPageTakeResult<
        PageCaptureTestParticipantID,
        PageCaptureTestKey,
        PageCaptureTestValue
    >
) -> WorkspaceStateSnapshotPageProgressReceipt {
    guard case .yielded(let receipt) = result else {
        preconditionFailure("expected bounded snapshot pager continuation")
    }
    return receipt
}

func isAborted(_ result: WorkspaceStateSnapshotPagerCloseResult) -> Bool {
    guard case .aborted = result else { return false }
    return true
}

func abortReceipt(
    from result: WorkspaceStateSnapshotPagerCloseResult
) -> WorkspaceStateSnapshotPagerCloseReceipt {
    guard case .aborted(let receipt) = result else {
        preconditionFailure("expected aborted snapshot pager close")
    }
    return receipt
}

func completedReceipt(
    from result: WorkspaceStateSnapshotPagerCloseResult
) -> WorkspaceStateSnapshotPagerCloseReceipt {
    guard case .completed(let receipt) = result else {
        preconditionFailure("expected completed snapshot pager close")
    }
    return receipt
}
