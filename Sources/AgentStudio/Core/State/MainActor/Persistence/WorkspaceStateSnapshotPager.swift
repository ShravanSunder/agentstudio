import Foundation
import Synchronization

private enum SnapshotPageCaptureClaimResult: Sendable {
    case claimed(MainActorWorkTicket)
    case alreadyClaimed
}

private final class WorkspaceStateSnapshotPageCaptureRequestCustody: Sendable {
    private enum State: Sendable {
        case pending(MainActorWorkTicket)
        case claimed
    }

    let workLedger: MainActorWorkLedger
    private let state: Mutex<State>

    init(workLedger: MainActorWorkLedger, workTicket: MainActorWorkTicket) {
        self.workLedger = workLedger
        self.state = Mutex(.pending(workTicket))
    }

    deinit {
        guard case .claimed(let ticket) = claim() else { return }
        _ = workLedger.discard(ticket: ticket)
    }

    func claim() -> SnapshotPageCaptureClaimResult {
        state.withLock { state in
            switch state {
            case .pending(let ticket):
                state = .claimed
                return .claimed(ticket)
            case .claimed:
                return .alreadyClaimed
            }
        }
    }

    func discard() -> MainActorWorkDiscardResult {
        switch claim() {
        case .claimed(let ticket):
            return workLedger.discard(ticket: ticket)
        case .alreadyClaimed:
            return .rejected(.duplicateSettlement)
        }
    }
}

struct WorkspaceStateSnapshotPageCaptureRequest: Sendable {
    fileprivate let pagerIdentity: WorkspaceStateSnapshotPagerIdentity
    fileprivate let lease: WorkspaceStateSnapshotLease
    fileprivate let limits: WorkspaceStateSnapshotPageLimits
    fileprivate let custody: WorkspaceStateSnapshotPageCaptureRequestCustody

    func discardBeforeExecution() -> MainActorWorkDiscardResult {
        custody.discard()
    }
}

@MainActor
final class WorkspaceStateSnapshotPager<
    ParticipantID: Hashable & Sendable,
    Item: WorkspaceStateSnapshotIdentifiedItem
> {
    private struct ReadyState {
        let lease: WorkspaceStateSnapshotLease
        var participantIndex: Int
        var membershipOffset: Int
        var pageCount: UInt64
        var itemCount: UInt64
        var byteCount: UInt64
        var lastAcknowledgedPageID: WorkspaceStateSnapshotPageID?
    }

    private struct OutstandingState {
        var ready: ReadyState
        let page: WorkspaceStateSnapshotPage<ParticipantID, Item>
        var retryWasRequested: Bool
    }

    private enum State {
        case idle(lastClose: WorkspaceStateSnapshotPagerCloseReceipt?)
        case ready(ReadyState)
        case outstanding(OutstandingState)
        case exhausted(ReadyState, WorkspaceStateSnapshotExhaustionReceipt)
    }

    private enum CaptureResult {
        case page(
            WorkspaceStateSnapshotPage<ParticipantID, Item>,
            scannedItemCount: Int
        )
        case exhausted(scannedItemCount: Int)
        case yielded(
            participantIndex: Int,
            participantInspectionCount: Int,
            scannedItemCount: Int
        )
        case rejected(
            WorkspaceStateSnapshotPageTakeRejection<ParticipantID, Item.SnapshotItemID>,
            scannedItemCount: Int
        )

        var measuredWork: MainActorMeasuredWork<Self> {
            switch self {
            case .page(let page, let scannedItemCount):
                MainActorMeasuredWork(
                    value: self,
                    outcome: .succeeded,
                    counts: .init(
                        input: UInt64(scannedItemCount),
                        changedKey: UInt64(page.itemCount)
                    )
                )
            case .exhausted(let scannedItemCount):
                MainActorMeasuredWork(
                    value: self,
                    outcome: .succeeded,
                    counts: .init(input: UInt64(scannedItemCount), changedKey: 0)
                )
            case .yielded(_, let participantInspectionCount, let scannedItemCount):
                MainActorMeasuredWork(
                    value: self,
                    outcome: .succeeded,
                    counts: .init(
                        input: UInt64(participantInspectionCount + scannedItemCount),
                        changedKey: 0
                    )
                )
            case .rejected(_, let scannedItemCount):
                MainActorMeasuredWork(
                    value: self,
                    outcome: .failed,
                    counts: .init(input: UInt64(scannedItemCount), changedKey: 0)
                )
            }
        }
    }

    private enum ParticipantCaptureResult {
        case captured(
            items: [CapturedItem],
            byteCount: Int,
            scannedItemCount: Int
        )
        case rejected(
            WorkspaceStateSnapshotPageTakeRejection<ParticipantID, Item.SnapshotItemID>,
            scannedItemCount: Int
        )
    }

    private struct CapturedItem {
        let pageItem: WorkspaceStateSnapshotPageItem<ParticipantID, Item>
        let membershipOffset: Int
    }

    nonisolated let pagerIdentity: WorkspaceStateSnapshotPagerIdentity

    private let revisionOwner: WorkspacePersistenceRevisionOwner
    private let leaseAuthority: WorkspaceStateSnapshotPagerLeaseAuthority
    private let participants: [WorkspaceStateSnapshotPagerParticipant<ParticipantID, Item>]
    private let membershipLimits: WorkspaceStateSnapshotMembershipLimits
    nonisolated private let workLedger: MainActorWorkLedger
    private let workRecordObserver: (MainActorWorkRecord) -> Void
    private let workInvalidityObserver: (MainActorWorkInvalidity) -> Void
    private let serviceClock: any PerformanceMonotonicClock
    private var state: State = .idle(lastClose: nil)

    init(
        pagerIdentity: WorkspaceStateSnapshotPagerIdentity,
        revisionOwner: WorkspacePersistenceRevisionOwner,
        leaseAuthority: WorkspaceStateSnapshotPagerLeaseAuthority,
        participants: [WorkspaceStateSnapshotPagerParticipant<ParticipantID, Item>],
        membershipLimits: WorkspaceStateSnapshotMembershipLimits = .init(
            maximumKeyCount: 100_000,
            maximumRawKeyBytes: 64 * 1024 * 1024
        ),
        workLedger: MainActorWorkLedger,
        workRecordObserver: @escaping (MainActorWorkRecord) -> Void,
        workInvalidityObserver: @escaping (MainActorWorkInvalidity) -> Void,
        serviceClock: any PerformanceMonotonicClock = SystemPerformanceMonotonicClock()
    ) {
        self.pagerIdentity = pagerIdentity
        self.revisionOwner = revisionOwner
        self.leaseAuthority = leaseAuthority
        self.participants = participants
        self.membershipLimits = membershipLimits
        self.workLedger = workLedger
        self.workRecordObserver = workRecordObserver
        self.workInvalidityObserver = workInvalidityObserver
        self.serviceClock = serviceClock
    }

    func openLease() -> WorkspaceStateSnapshotPagerOpenResult {
        guard case .idle = state else {
            return .rejected(
                .activeLeaseExists(activeLeaseID: activeLeaseFromState().leaseID)
            )
        }
        guard Set(participants.map(\.participantID)).count == participants.count else {
            return .rejected(.duplicateParticipantID)
        }
        let authorityResult = leaseAuthority.open(
            pagerIdentity: pagerIdentity,
            revisionOwner: revisionOwner
        )
        guard case .opened(let lease) = authorityResult else { return authorityResult }

        var openedParticipants: [WorkspaceStateSnapshotPagerParticipant<ParticipantID, Item>] = []
        for participant in participants {
            let openResult = participant.open(lease: lease, limits: membershipLimits)
            guard case .opened = openResult else {
                for openedParticipant in openedParticipants {
                    _ = openedParticipant.close(lease: lease)
                }
                _ = leaseAuthority.release(lease)
                guard case .rejected(let rejection) = openResult else { preconditionFailure() }
                return .rejected(.participantRejected(rejection))
            }
            openedParticipants.append(participant)
        }

        state = .ready(
            ReadyState(
                lease: lease,
                participantIndex: 0,
                membershipOffset: 0,
                pageCount: 0,
                itemCount: 0,
                byteCount: 0,
                lastAcknowledgedPageID: nil
            )
        )
        return .opened(lease)
    }

    nonisolated func makePageCaptureRequest(
        lease: WorkspaceStateSnapshotLease,
        limits: WorkspaceStateSnapshotPageLimits
    ) -> WorkspaceStateSnapshotPageCaptureRequestResult {
        let enqueueResult = workLedger.enqueue(
            domain: .persistence,
            operation: .persistencePageCapture,
            revision: .value(lease.baseRevision.rawValue)
        )
        guard case .enqueued(let ticket) = enqueueResult else {
            guard case .rejected(let invalidity) = enqueueResult else { preconditionFailure() }
            return .rejected(invalidity)
        }
        return .requested(
            WorkspaceStateSnapshotPageCaptureRequest(
                pagerIdentity: pagerIdentity,
                lease: lease,
                limits: limits,
                custody: WorkspaceStateSnapshotPageCaptureRequestCustody(
                    workLedger: workLedger,
                    workTicket: ticket
                )
            )
        )
    }

    func takePage(
        _ request: WorkspaceStateSnapshotPageCaptureRequest
    ) -> WorkspaceStateSnapshotPageTakeResult<ParticipantID, Item> {
        guard request.pagerIdentity == pagerIdentity, request.custody.workLedger === workLedger else {
            switch request.discardBeforeExecution() {
            case .discarded:
                return .rejected(.foreignPager)
            case .rejected(let invalidity):
                return .rejected(.mainActorWorkRejected(invalidity))
            }
        }

        guard case .claimed(let ticket) = request.custody.claim() else {
            return .rejected(.mainActorWorkRejected(.duplicateSettlement))
        }

        let lease = request.lease
        switch state {
        case .idle:
            return discard(ticket, returning: .noActiveLease)
        case .outstanding(var outstanding):
            guard outstanding.ready.lease == lease else {
                return discard(ticket, returning: .foreignLease)
            }
            guard outstanding.retryWasRequested else {
                return discard(
                    ticket,
                    returning: .pageAlreadyOutstanding(pageID: outstanding.page.pageID)
                )
            }
            outstanding.retryWasRequested = false
            state = .outstanding(outstanding)
            if case .rejected(let invalidity) = workLedger.discard(ticket: ticket) {
                return .rejected(.mainActorWorkRejected(invalidity))
            }
            return .replayed(outstanding.page)
        case .exhausted(let ready, let receipt):
            guard ready.lease == lease else {
                return discard(ticket, returning: .foreignLease)
            }
            if case .rejected(let invalidity) = workLedger.discard(ticket: ticket) {
                return .rejected(.mainActorWorkRejected(invalidity))
            }
            return .exhausted(receipt)
        case .ready(let ready):
            guard ready.lease == lease else {
                return discard(ticket, returning: .foreignLease)
            }

            let execution = workLedger.withMeasuredMainActorWork(ticket: ticket) {
                capturePage(from: ready, limits: request.limits).measuredWork
            }
            switch execution {
            case .rejectedBeforeExecution(let invalidity):
                return .rejected(.mainActorWorkRejected(invalidity))
            case .completedWithoutRecord(let capture, let invalidity):
                workInvalidityObserver(invalidity)
                return apply(capture, from: ready)
            case .completed(let capture, let record):
                workRecordObserver(record)
                return apply(capture, from: ready)
            }
        }
    }

    private func discard(
        _ ticket: MainActorWorkTicket,
        returning rejection: WorkspaceStateSnapshotPageTakeRejection<ParticipantID, Item.SnapshotItemID>
    ) -> WorkspaceStateSnapshotPageTakeResult<ParticipantID, Item> {
        switch workLedger.discard(ticket: ticket) {
        case .discarded:
            return .rejected(rejection)
        case .rejected(let invalidity):
            return .rejected(.mainActorWorkRejected(invalidity))
        }
    }

    func acknowledgePage(
        _ lease: WorkspaceStateSnapshotLease,
        pageID: WorkspaceStateSnapshotPageID,
        disposition: WorkspaceStateSnapshotPageDisposition
    ) -> WorkspaceStateSnapshotPageAcknowledgementResult {
        switch state {
        case .idle:
            return .rejected(.noActiveLease)
        case .ready(let ready), .exhausted(let ready, _):
            guard ready.lease == lease else { return .rejected(.foreignLease) }
            if ready.lastAcknowledgedPageID == pageID {
                return .rejected(.duplicateAcknowledgement(pageID: pageID))
            }
            return .rejected(.noPageOutstanding)
        case .outstanding(var outstanding):
            guard outstanding.ready.lease == lease else { return .rejected(.foreignLease) }
            guard outstanding.page.pageID == pageID else {
                if outstanding.ready.lastAcknowledgedPageID == pageID {
                    return .rejected(
                        .staleAcknowledgement(
                            submitted: pageID,
                            outstanding: outstanding.page.pageID
                        )
                    )
                }
                return .rejected(
                    .pageMismatch(submitted: pageID, outstanding: outstanding.page.pageID)
                )
            }
            switch disposition {
            case .retry:
                outstanding.retryWasRequested = true
                state = .outstanding(outstanding)
                return .queuedForRetry(pageID: pageID)
            case .transferred:
                var ready = outstanding.ready
                ready.participantIndex = outstanding.page.nextParticipantIndex
                ready.membershipOffset = outstanding.page.nextMembershipOffset
                ready.pageCount += 1
                ready.itemCount += UInt64(outstanding.page.itemCount)
                ready.byteCount += UInt64(outstanding.page.byteCount)
                ready.lastAcknowledgedPageID = pageID
                if outstanding.page.exhaustsLease {
                    let receipt = WorkspaceStateSnapshotExhaustionReceipt(
                        lease: lease,
                        pageCount: ready.pageCount,
                        itemCount: ready.itemCount,
                        byteCount: ready.byteCount
                    )
                    state = .exhausted(ready, receipt)
                } else {
                    state = .ready(ready)
                }
                return .acknowledged(pageID: pageID)
            }
        }
    }

    func closeLease(
        _ lease: WorkspaceStateSnapshotLease,
        disposition: WorkspaceStateSnapshotPagerCloseDisposition
    ) -> WorkspaceStateSnapshotPagerCloseResult {
        if case .idle(let lastClose) = state {
            guard let lastClose, lastClose.lease == lease else {
                return .rejected(.noActiveLease)
            }
            if let activeLease = leaseAuthority.activeLease, activeLease != lease {
                return .rejected(.staleLease)
            }
            return .alreadyClosed(lastClose)
        }

        let activeLease = activeLeaseFromState()
        guard activeLease == lease else { return .rejected(.foreignLease) }
        switch disposition {
        case .completed:
            switch state {
            case .outstanding(let outstanding):
                return .rejected(.pageOutstanding(pageID: outstanding.page.pageID))
            case .ready:
                return .rejected(.participantsIncomplete)
            case .exhausted:
                return finishClose(lease: lease, disposition: .completed)
            case .idle:
                preconditionFailure()
            }
        case .abort:
            return finishClose(lease: lease, disposition: .abort)
        }
    }

    private func capturePage(
        from ready: ReadyState,
        limits: WorkspaceStateSnapshotPageLimits
    ) -> CaptureResult {
        let startedAt = serviceClock.now()
        var participantIndex = ready.participantIndex
        var membershipOffset = ready.membershipOffset
        var scannedItemCount = 0
        var participantInspectionCount = 0

        while participantIndex < participants.count {
            if participantInspectionCount >= limits.maximumParticipantInspections {
                return .yielded(
                    participantIndex: participantIndex,
                    participantInspectionCount: participantInspectionCount,
                    scannedItemCount: scannedItemCount
                )
            }
            if serviceLimitReached(
                startedAt: startedAt,
                limit: limits.maximumSynchronousServiceNanoseconds
            ) {
                guard participantInspectionCount > 0 else {
                    return .rejected(
                        .synchronousServiceLimitReachedWithoutProgress,
                        scannedItemCount: scannedItemCount
                    )
                }
                return .yielded(
                    participantIndex: participantIndex,
                    participantInspectionCount: participantInspectionCount,
                    scannedItemCount: scannedItemCount
                )
            }
            let participant = participants[participantIndex]
            participantInspectionCount += 1
            let membershipCount: Int
            switch participant.membershipCount(for: ready.lease) {
            case .count(let activeMembershipCount):
                membershipCount = activeMembershipCount
            case .rejected(let rejection):
                return .rejected(.participantRejected(rejection), scannedItemCount: scannedItemCount)
            }
            if membershipOffset >= membershipCount {
                participantIndex += 1
                membershipOffset = 0
                if participantInspectionCount >= limits.maximumParticipantInspections {
                    return .yielded(
                        participantIndex: participantIndex,
                        participantInspectionCount: participantInspectionCount,
                        scannedItemCount: scannedItemCount
                    )
                }
                continue
            }

            let participantCapture = captureParticipantItems(
                participant,
                membershipCount: membershipCount,
                membershipOffset: membershipOffset,
                lease: ready.lease,
                limits: limits,
                startedAt: startedAt
            )
            guard
                case .captured(let items, let pageBytes, let participantScannedItemCount) =
                    participantCapture
            else {
                guard case .rejected(let rejection, let participantScannedItemCount) = participantCapture
                else { preconditionFailure() }
                return .rejected(rejection, scannedItemCount: scannedItemCount + participantScannedItemCount)
            }
            scannedItemCount += participantScannedItemCount
            let pageID = WorkspaceStateSnapshotPageID.make()
            if let rejection = markCapturedItemsCopied(
                items,
                by: participant,
                lease: ready.lease,
                pageID: pageID
            ) {
                return .rejected(
                    .participantCommitRejected(rejection),
                    scannedItemCount: scannedItemCount
                )
            }

            let pageItems = items.map(\.pageItem)
            let nextOffset = membershipOffset + pageItems.count
            let nextPosition =
                nextOffset < membershipCount
                ? (participantIndex: participantIndex, membershipOffset: nextOffset)
                : (participantIndex: participantIndex + 1, membershipOffset: 0)
            let page = WorkspaceStateSnapshotPage(
                pageID: pageID,
                lease: ready.lease,
                participantID: participant.participantID,
                items: pageItems,
                itemCount: pageItems.count,
                byteCount: pageBytes,
                nextParticipantIndex: nextPosition.participantIndex,
                nextMembershipOffset: nextPosition.membershipOffset,
                exhaustsLease: nextPosition.participantIndex == participants.count
            )
            return .page(page, scannedItemCount: scannedItemCount)
        }
        return .exhausted(scannedItemCount: scannedItemCount)
    }

    private func captureParticipantItems(
        _ participant: WorkspaceStateSnapshotPagerParticipant<ParticipantID, Item>,
        membershipCount: Int,
        membershipOffset: Int,
        lease: WorkspaceStateSnapshotLease,
        limits: WorkspaceStateSnapshotPageLimits,
        startedAt: PerformanceMonotonicInstant
    ) -> ParticipantCaptureResult {
        var items: [CapturedItem] = []
        var pageBytes = 0
        var scannedItemCount = 0
        while membershipOffset + items.count < membershipCount {
            if items.count >= limits.maximumItems {
                break
            }
            if scannedItemCount >= limits.maximumScannedItems {
                guard !items.isEmpty else {
                    return .rejected(.scannedItemLimitReachedWithoutProgress, scannedItemCount: scannedItemCount)
                }
                break
            }
            if serviceLimitReached(startedAt: startedAt, limit: limits.maximumSynchronousServiceNanoseconds) {
                guard !items.isEmpty else {
                    return .rejected(
                        .synchronousServiceLimitReachedWithoutProgress,
                        scannedItemCount: scannedItemCount
                    )
                }
                break
            }

            let itemMembershipOffset = membershipOffset + items.count
            scannedItemCount += 1
            let captureResult = participant.captureItem(
                lease: lease,
                membershipOffset: itemMembershipOffset
            )
            guard case .captured(let projectedItem) = captureResult else {
                guard case .rejected(let rejection) = captureResult else { preconditionFailure() }
                return .rejected(.participantRejected(rejection), scannedItemCount: scannedItemCount)
            }
            let item = projectedItem.item
            let itemID = item.snapshotItemID
            let itemBytes = projectedItem.estimatedByteCount
            guard itemBytes >= 0 else {
                return .rejected(
                    .invalidItemByteCount(participantID: participant.participantID, itemID: itemID),
                    scannedItemCount: scannedItemCount
                )
            }
            guard itemBytes <= limits.maximumBytes else {
                return .rejected(
                    .itemExceedsByteLimit(
                        participantID: participant.participantID,
                        itemID: itemID,
                        itemBytes: itemBytes,
                        maximumBytes: limits.maximumBytes
                    ),
                    scannedItemCount: scannedItemCount
                )
            }
            let nextPageBytes = pageBytes.addingReportingOverflow(itemBytes)
            guard !nextPageBytes.overflow else {
                return .rejected(.itemByteCountOverflow, scannedItemCount: scannedItemCount)
            }
            if nextPageBytes.partialValue > limits.maximumBytes {
                break
            }
            items.append(
                CapturedItem(
                    pageItem: WorkspaceStateSnapshotPageItem(
                        participantID: participant.participantID,
                        item: item,
                        byteCount: itemBytes
                    ),
                    membershipOffset: itemMembershipOffset
                )
            )
            pageBytes = nextPageBytes.partialValue
        }
        precondition(!items.isEmpty, "validated limits must produce a non-empty page")
        return .captured(items: items, byteCount: pageBytes, scannedItemCount: scannedItemCount)
    }

    private func markCapturedItemsCopied(
        _ items: [CapturedItem],
        by participant: WorkspaceStateSnapshotPagerParticipant<ParticipantID, Item>,
        lease: WorkspaceStateSnapshotLease,
        pageID: WorkspaceStateSnapshotPageID
    ) -> WorkspaceStateSnapshotParticipantRejection? {
        for item in items {
            let markResult = participant.markBaseValueCopied(
                lease: lease,
                membershipOffset: item.membershipOffset,
                pageID: pageID
            )
            guard markResult == .markedCopied else {
                guard case .rejected(let rejection) = markResult else { preconditionFailure() }
                return rejection
            }
        }
        return nil
    }

    private func apply(
        _ capture: CaptureResult,
        from ready: ReadyState
    ) -> WorkspaceStateSnapshotPageTakeResult<ParticipantID, Item> {
        switch capture {
        case .page(let page, _):
            state = .outstanding(
                OutstandingState(ready: ready, page: page, retryWasRequested: false)
            )
            return .page(page)
        case .exhausted:
            let receipt = WorkspaceStateSnapshotExhaustionReceipt(
                lease: ready.lease,
                pageCount: ready.pageCount,
                itemCount: ready.itemCount,
                byteCount: ready.byteCount
            )
            state = .exhausted(ready, receipt)
            return .exhausted(receipt)
        case .yielded(let participantIndex, let participantInspectionCount, _):
            var advancedReady = ready
            advancedReady.participantIndex = participantIndex
            advancedReady.membershipOffset = 0
            state = .ready(advancedReady)
            return .yielded(
                WorkspaceStateSnapshotPageProgressReceipt(
                    lease: ready.lease,
                    nextParticipantIndex: participantIndex,
                    participantInspectionCount: participantInspectionCount
                )
            )
        case .rejected(let rejection, _):
            if case .participantCommitRejected = rejection {
                _ = finishClose(lease: ready.lease, disposition: .abort)
            }
            return .rejected(rejection)
        }
    }

    private func serviceLimitReached(startedAt: PerformanceMonotonicInstant, limit: UInt64) -> Bool {
        let now = serviceClock.now()
        guard now >= startedAt else { return true }
        return now.uptimeNanoseconds - startedAt.uptimeNanoseconds >= limit
    }

    private func finishClose(
        lease: WorkspaceStateSnapshotLease,
        disposition: WorkspaceStateSnapshotPagerCloseDisposition
    ) -> WorkspaceStateSnapshotPagerCloseResult {
        var releasedMembershipCount = 0
        var releasedRetainedBaseValueCount = 0
        for participant in participants {
            let closeResult = participant.close(lease: lease)
            guard case .closed(let receipt) = closeResult else {
                guard case .rejected(let rejection) = closeResult else { preconditionFailure() }
                return .rejected(.participantRejected(rejection))
            }
            releasedMembershipCount += receipt.releasedMembershipCount
            releasedRetainedBaseValueCount += receipt.releasedBaseValueCount
        }
        guard leaseAuthority.release(lease) else { return .rejected(.staleLease) }
        let receipt = WorkspaceStateSnapshotPagerCloseReceipt(
            lease: lease,
            disposition: disposition,
            releasedParticipantCount: participants.count,
            releasedMembershipCount: releasedMembershipCount,
            releasedRetainedBaseValueCount: releasedRetainedBaseValueCount
        )
        state = .idle(lastClose: receipt)
        switch disposition {
        case .completed:
            return .completed(receipt)
        case .abort:
            return .aborted(receipt)
        }
    }

    private func activeLeaseFromState() -> WorkspaceStateSnapshotLease {
        switch state {
        case .ready(let ready), .exhausted(let ready, _):
            return ready.lease
        case .outstanding(let outstanding):
            return outstanding.ready.lease
        case .idle:
            preconditionFailure("idle snapshot pager has no active lease")
        }
    }
}
