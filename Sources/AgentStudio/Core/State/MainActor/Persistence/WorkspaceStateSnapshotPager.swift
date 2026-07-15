import Foundation

@MainActor
final class WorkspaceStateSnapshotPager<
    ParticipantID: Hashable & Sendable,
    Item: WorkspaceStateSnapshotIdentifiedItem
> where Item.SnapshotParticipantID == ParticipantID {
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
            participantInspectionCount: Int,
            scannedItemCount: Int
        )
        case exhausted(participantInspectionCount: Int, scannedItemCount: Int)
        case yielded(
            participantIndex: Int,
            slotCursor: Int,
            participantInspectionCount: Int,
            scannedItemCount: Int
        )
        case rejected(
            WorkspaceStateSnapshotPageTakeRejection<ParticipantID, Item.SnapshotItemID>,
            participantInspectionCount: Int,
            scannedItemCount: Int
        )

        var measuredWork: MainActorMeasuredWork<Self> {
            switch self {
            case .page(let page, let participantInspectionCount, let scannedItemCount):
                MainActorMeasuredWork(
                    value: self,
                    outcome: .succeeded,
                    counts: .init(
                        input: measuredInputCount(
                            participantInspectionCount: participantInspectionCount,
                            scannedItemCount: scannedItemCount
                        ),
                        changedKey: UInt64(page.itemCount)
                    )
                )
            case .exhausted(let participantInspectionCount, let scannedItemCount):
                MainActorMeasuredWork(
                    value: self,
                    outcome: .succeeded,
                    counts: .init(
                        input: measuredInputCount(
                            participantInspectionCount: participantInspectionCount,
                            scannedItemCount: scannedItemCount
                        ),
                        changedKey: 0
                    )
                )
            case .yielded(_, _, let participantInspectionCount, let scannedItemCount):
                MainActorMeasuredWork(
                    value: self,
                    outcome: .succeeded,
                    counts: .init(
                        input: measuredInputCount(
                            participantInspectionCount: participantInspectionCount,
                            scannedItemCount: scannedItemCount
                        ),
                        changedKey: 0
                    )
                )
            case .rejected(_, let participantInspectionCount, let scannedItemCount):
                MainActorMeasuredWork(
                    value: self,
                    outcome: .failed,
                    counts: .init(
                        input: measuredInputCount(
                            participantInspectionCount: participantInspectionCount,
                            scannedItemCount: scannedItemCount
                        ),
                        changedKey: 0
                    )
                )
            }
        }

        private func measuredInputCount(
            participantInspectionCount: Int,
            scannedItemCount: Int
        ) -> UInt64 {
            precondition(participantInspectionCount >= 0 && scannedItemCount >= 0)
            let sum = UInt64(participantInspectionCount).addingReportingOverflow(
                UInt64(scannedItemCount)
            )
            precondition(!sum.overflow, "bounded snapshot work count must be representable")
            return sum.partialValue
        }
    }

    private enum ParticipantCaptureResult {
        case captured(ParticipantCapturePayload)
        case rejected(
            WorkspaceStateSnapshotPageTakeRejection<ParticipantID, Item.SnapshotItemID>,
            scannedItemCount: Int
        )
    }

    private struct ParticipantCapturePayload {
        let items: [CapturedItem]
        let byteCount: Int
        let scannedItemCount: Int
        let nextSlotCursor: Int
        let exhaustedParticipant: Bool
    }

    private struct ParticipantCaptureContext {
        let participant: WorkspaceStateSnapshotPagerParticipant<ParticipantID, Item>
        let slotUpperBound: Int
        let slotCursor: Int
        let lease: WorkspaceStateSnapshotLease
        let limits: WorkspaceStateSnapshotPageLimits
        let maximumScannedItems: Int
        let startedAt: PerformanceMonotonicInstant
    }

    private enum ItemByteValidationResult {
        case accepted(nextPageByteCount: Int)
        case pageFull
        case rejected(
            WorkspaceStateSnapshotPageTakeRejection<ParticipantID, Item.SnapshotItemID>
        )
    }

    private struct CapturedItem {
        let pageItem: WorkspaceStateSnapshotPageItem<ParticipantID, Item>
        let copyToken: WorkspaceStateSnapshotBaseCopyToken
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
                if rejection == .cleanupPending {
                    return .rejected(.cleanupPending)
                }
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

    func drainCleanup(maximumValues: Int) -> WorkspaceStateSnapshotPagerCleanupDrainResult {
        var remainingBudget = max(0, maximumValues)
        var releasedValueCount = 0
        var remainingValueCount = 0
        for participant in participants {
            switch participant.drainCleanup(maximumValues: remainingBudget) {
            case .complete:
                continue
            case .drained(let released, let remaining):
                guard released <= remainingBudget else {
                    return .rejected(.cleanupValueReleaseExceedsBudget)
                }
                let releasedTotal = releasedValueCount.addingReportingOverflow(released)
                let remainingTotal = remainingValueCount.addingReportingOverflow(remaining)
                guard !releasedTotal.overflow, !remainingTotal.overflow else {
                    return .rejected(.cleanupValueCountOverflow)
                }
                releasedValueCount = releasedTotal.partialValue
                remainingValueCount = remainingTotal.partialValue
                remainingBudget -= released
            case .rejected(let rejection):
                return .rejected(rejection)
            }
        }
        if releasedValueCount == 0, remainingValueCount == 0 {
            return .complete
        }
        return .drained(
            releasedValueCount: releasedValueCount,
            remainingValueCount: remainingValueCount
        )
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
            if let boundaryResult = captureBoundaryResult(
                participantIndex: participantIndex,
                slotCursor: membershipOffset,
                participantInspectionCount: participantInspectionCount,
                scannedItemCount: scannedItemCount,
                startedAt: startedAt,
                limits: limits
            ) {
                return boundaryResult
            }
            let participant = participants[participantIndex]
            participantInspectionCount += 1
            let slotUpperBound: Int
            switch participant.slotUpperBound(for: ready.lease) {
            case .upperBound(let activeSlotUpperBound):
                slotUpperBound = activeSlotUpperBound
            case .rejected(let rejection):
                return .rejected(
                    .participantRejected(rejection),
                    participantInspectionCount: participantInspectionCount,
                    scannedItemCount: scannedItemCount
                )
            }
            if membershipOffset >= slotUpperBound {
                participantIndex += 1
                membershipOffset = 0
                if participantInspectionCount >= limits.maximumParticipantInspections {
                    return yieldedCapture(
                        participantIndex: participantIndex,
                        slotCursor: membershipOffset,
                        participantInspectionCount: participantInspectionCount,
                        scannedItemCount: scannedItemCount
                    )
                }
                continue
            }

            let participantCapture = captureParticipantItems(
                ParticipantCaptureContext(
                    participant: participant,
                    slotUpperBound: slotUpperBound,
                    slotCursor: membershipOffset,
                    lease: ready.lease,
                    limits: limits,
                    maximumScannedItems: limits.maximumScannedItems - scannedItemCount,
                    startedAt: startedAt
                )
            )
            guard case .captured(let captured) = participantCapture else {
                guard case .rejected(let rejection, let participantScannedItemCount) = participantCapture
                else { preconditionFailure() }
                return .rejected(
                    rejection,
                    participantInspectionCount: participantInspectionCount,
                    scannedItemCount: scannedItemCount + participantScannedItemCount
                )
            }
            scannedItemCount += captured.scannedItemCount
            if captured.items.isEmpty {
                if captured.exhaustedParticipant {
                    participantIndex += 1
                    membershipOffset = 0
                    if participantIndex < participants.count,
                        participantInspectionCount < limits.maximumParticipantInspections,
                        scannedItemCount < limits.maximumScannedItems,
                        !serviceLimitReached(
                            startedAt: startedAt,
                            limit: limits.maximumSynchronousServiceNanoseconds
                        )
                    {
                        continue
                    }
                } else {
                    membershipOffset = captured.nextSlotCursor
                }
                return yieldedCapture(
                    participantIndex: participantIndex,
                    slotCursor: membershipOffset,
                    participantInspectionCount: participantInspectionCount,
                    scannedItemCount: scannedItemCount
                )
            }
            return finishPageCapture(
                captured: captured,
                participant: participant,
                participantIndex: participantIndex,
                lease: ready.lease,
                participantInspectionCount: participantInspectionCount,
                scannedItemCount: scannedItemCount
            )
        }
        return .exhausted(
            participantInspectionCount: participantInspectionCount,
            scannedItemCount: scannedItemCount
        )
    }

    private func captureParticipantItems(
        _ context: ParticipantCaptureContext
    ) -> ParticipantCaptureResult {
        var items: [CapturedItem] = []
        var pageBytes = 0
        var scannedItemCount = 0
        var nextSlotCursor = context.slotCursor
        captureLoop: while nextSlotCursor < context.slotUpperBound {
            guard items.count < context.limits.maximumItems else { break }
            guard scannedItemCount < context.maximumScannedItems else { break }
            if serviceLimitReached(
                startedAt: context.startedAt,
                limit: context.limits.maximumSynchronousServiceNanoseconds
            ) {
                guard !items.isEmpty || scannedItemCount > 0 else {
                    return .rejected(
                        .synchronousServiceLimitReachedWithoutProgress,
                        scannedItemCount: scannedItemCount
                    )
                }
                break
            }

            scannedItemCount += 1
            let captureResult = context.participant.inspectBaseSlot(
                lease: context.lease,
                slotCursor: nextSlotCursor
            )
            let projectedItem: WorkspaceStateSnapshotPagerTypedItem<Item>
            let expectedItemID: Item.SnapshotItemID
            let copyToken: WorkspaceStateSnapshotBaseCopyToken
            let candidateNextSlotCursor: Int
            switch captureResult {
            case .item(let item, let expectedID, let token, let cursor):
                projectedItem = item
                expectedItemID = expectedID
                copyToken = token
                candidateNextSlotCursor = cursor
            case .skipped(let cursor):
                nextSlotCursor = cursor
                continue
            case .exhausted:
                return .captured(
                    ParticipantCapturePayload(
                        items: items,
                        byteCount: pageBytes,
                        scannedItemCount: scannedItemCount,
                        nextSlotCursor: context.slotUpperBound,
                        exhaustedParticipant: true
                    )
                )
            case .rejected(let rejection):
                return .rejected(.participantRejected(rejection), scannedItemCount: scannedItemCount)
            }
            let item = projectedItem.item
            let itemID = item.snapshotItemID
            if let identityRejection = validateProjectedItemIdentity(
                item,
                expectedItemID: expectedItemID,
                participantID: context.participant.participantID
            ) {
                return .rejected(
                    identityRejection,
                    scannedItemCount: scannedItemCount
                )
            }
            let itemBytes = projectedItem.estimatedByteCount
            switch validateItemBytes(
                itemBytes,
                itemID: itemID,
                participantID: context.participant.participantID,
                pageByteCount: pageBytes,
                maximumBytes: context.limits.maximumBytes
            ) {
            case .accepted(let nextPageByteCount):
                pageBytes = nextPageByteCount
            case .pageFull:
                break captureLoop
            case .rejected(let rejection):
                return .rejected(
                    rejection,
                    scannedItemCount: scannedItemCount
                )
            }
            items.append(
                CapturedItem(
                    pageItem: WorkspaceStateSnapshotPageItem(
                        item: item,
                        byteCount: itemBytes
                    ),
                    copyToken: copyToken
                )
            )
            nextSlotCursor = candidateNextSlotCursor
        }
        return completedParticipantCapture(
            items: items,
            pageBytes: pageBytes,
            scannedItemCount: scannedItemCount,
            nextSlotCursor: nextSlotCursor,
            slotUpperBound: context.slotUpperBound
        )
    }

    private func completedParticipantCapture(
        items: [CapturedItem],
        pageBytes: Int,
        scannedItemCount: Int,
        nextSlotCursor: Int,
        slotUpperBound: Int
    ) -> ParticipantCaptureResult {
        .captured(
            ParticipantCapturePayload(
                items: items,
                byteCount: pageBytes,
                scannedItemCount: scannedItemCount,
                nextSlotCursor: nextSlotCursor,
                exhaustedParticipant: nextSlotCursor >= slotUpperBound
            )
        )
    }
}

extension WorkspaceStateSnapshotPager {
    private func validateItemBytes(
        _ itemBytes: Int,
        itemID: Item.SnapshotItemID,
        participantID: ParticipantID,
        pageByteCount: Int,
        maximumBytes: Int
    ) -> ItemByteValidationResult {
        guard itemBytes >= 0 else {
            return .rejected(
                .invalidItemByteCount(participantID: participantID, itemID: itemID)
            )
        }
        guard itemBytes <= maximumBytes else {
            return .rejected(
                .itemExceedsByteLimit(
                    participantID: participantID,
                    itemID: itemID,
                    itemBytes: itemBytes,
                    maximumBytes: maximumBytes
                )
            )
        }
        let nextPageBytes = pageByteCount.addingReportingOverflow(itemBytes)
        guard !nextPageBytes.overflow else {
            return .rejected(.itemByteCountOverflow)
        }
        guard nextPageBytes.partialValue <= maximumBytes else {
            return .pageFull
        }
        return .accepted(nextPageByteCount: nextPageBytes.partialValue)
    }

    private func captureBoundaryResult(
        participantIndex: Int,
        slotCursor: Int,
        participantInspectionCount: Int,
        scannedItemCount: Int,
        startedAt: PerformanceMonotonicInstant,
        limits: WorkspaceStateSnapshotPageLimits
    ) -> CaptureResult? {
        if participantInspectionCount >= limits.maximumParticipantInspections {
            return .yielded(
                participantIndex: participantIndex,
                slotCursor: slotCursor,
                participantInspectionCount: participantInspectionCount,
                scannedItemCount: scannedItemCount
            )
        }
        guard
            serviceLimitReached(
                startedAt: startedAt,
                limit: limits.maximumSynchronousServiceNanoseconds
            )
        else { return nil }
        guard participantInspectionCount > 0 else {
            return .rejected(
                .synchronousServiceLimitReachedWithoutProgress,
                participantInspectionCount: participantInspectionCount,
                scannedItemCount: scannedItemCount
            )
        }
        return .yielded(
            participantIndex: participantIndex,
            slotCursor: slotCursor,
            participantInspectionCount: participantInspectionCount,
            scannedItemCount: scannedItemCount
        )
    }

    private func yieldedCapture(
        participantIndex: Int,
        slotCursor: Int,
        participantInspectionCount: Int,
        scannedItemCount: Int
    ) -> CaptureResult {
        .yielded(
            participantIndex: participantIndex,
            slotCursor: slotCursor,
            participantInspectionCount: participantInspectionCount,
            scannedItemCount: scannedItemCount
        )
    }

    private func makePage(
        captured: ParticipantCapturePayload,
        participant: WorkspaceStateSnapshotPagerParticipant<ParticipantID, Item>,
        participantIndex: Int,
        lease: WorkspaceStateSnapshotLease,
        pageID: WorkspaceStateSnapshotPageID
    ) -> WorkspaceStateSnapshotPage<ParticipantID, Item> {
        let pageItems = captured.items.map(\.pageItem)
        let nextPosition =
            !captured.exhaustedParticipant
            ? (participantIndex: participantIndex, membershipOffset: captured.nextSlotCursor)
            : (participantIndex: participantIndex + 1, membershipOffset: 0)
        return WorkspaceStateSnapshotPage(
            pageID: pageID,
            lease: lease,
            participantID: participant.participantID,
            items: pageItems,
            itemCount: pageItems.count,
            byteCount: captured.byteCount,
            nextParticipantIndex: nextPosition.participantIndex,
            nextMembershipOffset: nextPosition.membershipOffset,
            exhaustsLease: nextPosition.participantIndex == participants.count
        )
    }

    private func finishPageCapture(
        captured: ParticipantCapturePayload,
        participant: WorkspaceStateSnapshotPagerParticipant<ParticipantID, Item>,
        participantIndex: Int,
        lease: WorkspaceStateSnapshotLease,
        participantInspectionCount: Int,
        scannedItemCount: Int
    ) -> CaptureResult {
        let pageID = WorkspaceStateSnapshotPageID.make()
        if let rejection = markCapturedItemsCopied(
            captured.items,
            by: participant,
            lease: lease,
            pageID: pageID
        ) {
            return .rejected(
                .participantCommitRejected(rejection),
                participantInspectionCount: participantInspectionCount,
                scannedItemCount: scannedItemCount
            )
        }
        let page = makePage(
            captured: captured,
            participant: participant,
            participantIndex: participantIndex,
            lease: lease,
            pageID: pageID
        )
        return .page(
            page,
            participantInspectionCount: participantInspectionCount,
            scannedItemCount: scannedItemCount
        )
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
                copyToken: item.copyToken,
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
        case .page(let page, _, _):
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
        case .yielded(let participantIndex, let slotCursor, let participantInspectionCount, _):
            var advancedReady = ready
            advancedReady.participantIndex = participantIndex
            advancedReady.membershipOffset = slotCursor
            state = .ready(advancedReady)
            return .yielded(
                WorkspaceStateSnapshotPageProgressReceipt(
                    lease: ready.lease,
                    nextParticipantIndex: participantIndex,
                    participantInspectionCount: participantInspectionCount
                )
            )
        case .rejected(let rejection, _, _):
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
