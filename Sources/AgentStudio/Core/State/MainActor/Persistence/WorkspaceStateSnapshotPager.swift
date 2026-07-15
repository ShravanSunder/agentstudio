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

    nonisolated let pagerIdentity: WorkspaceStateSnapshotPagerIdentity

    private let revisionOwner: WorkspacePersistenceRevisionOwner
    private let leaseAuthority: WorkspaceStateSnapshotPagerLeaseAuthority
    private let participants: [WorkspaceStateSnapshotPagerParticipant<ParticipantID, Item>]
    private let membershipLimits: WorkspaceStateSnapshotMembershipLimits
    nonisolated private let workLedger: MainActorWorkLedger
    private let workRecordObserver: (MainActorWorkRecord) -> Void
    private let workInvalidityObserver: (MainActorWorkInvalidity) -> Void
    private let captureEngine: WorkspaceStateSnapshotPageCaptureEngine<ParticipantID, Item>
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
        self.captureEngine = WorkspaceStateSnapshotPageCaptureEngine(
            participants: participants,
            serviceClock: serviceClock
        )
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
                captureEngine.capturePage(
                    participantIndex: ready.participantIndex,
                    membershipOffset: ready.membershipOffset,
                    lease: ready.lease,
                    limits: request.limits
                ).measuredWork
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

    private func apply(
        _ capture: WorkspaceStateSnapshotPageCaptureEngine<ParticipantID, Item>.CaptureResult,
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
