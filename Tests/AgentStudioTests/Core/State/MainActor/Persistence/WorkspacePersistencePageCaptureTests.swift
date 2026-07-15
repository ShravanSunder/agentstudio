import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite(.serialized)
struct WorkspacePersistencePageCaptureTests {
    @Test("abandoned and cancelled capture requests discard their ticket exactly once")
    func abandonedAndCancelledCaptureRequestsDiscardTheirTicketExactlyOnce() async {
        // Arrange
        let fixture = makePagerFixture(
            participants: [makeParticipant(.alpha, values: [("a", "one", 3)])]
        )
        let lease = requireOpenedLease(fixture.pager.openLease())
        let limits = requireLimits(maximumItems: 1, maximumBytes: 16)
        let pager = fixture.pager

        // Act
        for _ in 0..<256 {
            makeAndAbandonPageCaptureRequest(pager: pager, lease: lease, limits: limits)
        }
        // Cancellation must occur before MainActor admission.
        // swiftlint:disable:next no_task_detached
        let cancelledRequest = Task.detached {
            let request = pager.makePageCaptureRequest(lease: lease, limits: limits)
            while !Task.isCancelled {
                await Task.yield()
            }
            _ = request
            return Task.isCancelled
        }
        cancelledRequest.cancel()
        let observedCancellation = await cancelledRequest.value

        // Assert
        #expect(observedCancellation)
        #expect(fixture.workLedger.pendingWorkCount() == 0)
    }

    @Test("all request copies share one settlement and foreign routing releases custody")
    func allRequestCopiesShareOneSettlementAndForeignRoutingReleasesCustody() {
        // Arrange
        let firstFixture = makePagerFixture(
            participants: [makeParticipant(.alpha, values: [("a", "one", 3)])]
        )
        let secondFixture = makePagerFixture(
            participants: [makeParticipant(.beta, values: [("b", "two", 3)])]
        )
        let firstLease = requireOpenedLease(firstFixture.pager.openLease())
        let limits = requireLimits(maximumItems: 1, maximumBytes: 16)
        guard
            case .requested(let firstRequest) = firstFixture.pager.makePageCaptureRequest(
                lease: firstLease,
                limits: limits
            )
        else {
            Issue.record("expected first capture request")
            return
        }
        let copiedRequest = firstRequest

        // Act
        let page = requireCapturedPage(firstFixture.pager.takePage(firstRequest))
        let copiedDiscard = copiedRequest.discardBeforeExecution()
        guard
            case .requested(let foreignRequest) = firstFixture.pager.makePageCaptureRequest(
                lease: firstLease,
                limits: limits
            )
        else {
            Issue.record("expected foreign-routing request")
            return
        }
        let foreignResult = secondFixture.pager.takePage(foreignRequest)

        // Assert
        #expect(page.items.map(\.key) == [.init("a")])
        #expect(copiedDiscard == .rejected(.duplicateSettlement))
        #expect(foreignResult == .rejected(.foreignPager))
        #expect(firstFixture.workLedger.pendingWorkCount() == 0)
        #expect(secondFixture.workLedger.pendingWorkCount() == 0)
    }

    @Test("capture request records queue age from its nonisolated boundary")
    func captureRequestRecordsQueueAgeFromItsNonisolatedBoundary() async {
        // Arrange
        let fixture = makePagerFixture(
            participants: [makeParticipant(.alpha, values: [("a", "one", 3)])],
            workLedgerClock: PageCaptureScriptedClock([100, 250, 300])
        )
        let lease = requireOpenedLease(fixture.pager.openLease())
        let limits = requireLimits(maximumItems: 1, maximumBytes: 16)
        let pager = fixture.pager

        // Act
        // This proves queue age begins outside MainActor.
        // swiftlint:disable:next no_task_detached
        let requestResult = await Task.detached {
            pager.makePageCaptureRequest(lease: lease, limits: limits)
        }.value
        guard case .requested(let request) = requestResult else {
            Issue.record("expected off-main page capture request")
            return
        }
        let page = requireCapturedPage(pager.takePage(request))

        // Assert
        #expect(page.items.map(\.key) == [.init("a")])
        #expect(fixture.workRecords.records.count == 1)
        #expect(fixture.workRecords.records[0].queueAgeNanoseconds == 150)
        #expect(fixture.workRecords.records[0].synchronousServiceNanoseconds == 50)
    }

    @Test("one process authority permits only one active snapshot lease")
    func oneProcessAuthorityPermitsOnlyOneActiveSnapshotLease() {
        // Arrange
        let revisionOwner = WorkspacePersistenceRevisionOwner()
        let leaseAuthority = WorkspaceStateSnapshotPagerLeaseAuthority(revisionOwner: revisionOwner)
        let firstFixture = makePagerFixture(
            revisionOwner: revisionOwner,
            leaseAuthority: leaseAuthority,
            participants: [makeParticipant(.alpha, values: [("a", "one", 3)])]
        )
        let secondFixture = makePagerFixture(
            revisionOwner: revisionOwner,
            leaseAuthority: leaseAuthority,
            participants: [makeParticipant(.beta, values: [("b", "two", 3)])]
        )

        // Act
        let firstLease = requireOpenedLease(firstFixture.pager.openLease())
        let competingOpen = secondFixture.pager.openLease()
        let abortResult = firstFixture.pager.closeLease(firstLease, disposition: .abort)
        let successorOpen = secondFixture.pager.openLease()

        // Assert
        #expect(
            competingOpen
                == .rejected(.activeLeaseExists(activeLeaseID: firstLease.leaseID))
        )
        #expect(abortResult == .aborted(abortReceipt(from: abortResult)))
        #expect(isOpened(successorOpen))
    }

    @Test("retry replays the exact immutable page without recapture")
    func retryReplaysExactImmutablePageWithoutRecapture() {
        // Arrange
        let participant = makeParticipant(
            .alpha,
            values: [("a", "base-a", 6), ("b", "base-b", 6)]
        )
        let fixture = makePagerFixture(participants: [participant])
        let lease = requireOpenedLease(fixture.pager.openLease())
        let limits = requireLimits(maximumItems: 2, maximumBytes: 32)
        let originalPage = requireCapturedPage(takePage(fixture.pager, lease: lease, limits: limits))
        let captureRecordsBeforeRetry = fixture.workRecords.records

        // Act
        participant.source.replaceValue(for: .init("a"), with: .init(payload: "latest-a", byteCount: 8))
        participant.source.removeValue(for: .init("b"))
        let retryResult = fixture.pager.acknowledgePage(
            lease,
            pageID: originalPage.pageID,
            disposition: .retry
        )
        let replayResult = takePage(fixture.pager, lease: lease, limits: limits)

        // Assert
        #expect(retryResult == .queuedForRetry(pageID: originalPage.pageID))
        let replayedPage = requireReplayedPage(replayResult)
        #expect(replayedPage == originalPage)
        #expect(UUIDv7.isV7(replayedPage.pageID.rawValue))
        #expect(fixture.workRecords.records == captureRecordsBeforeRetry)
    }

    @Test("cursor advances only after the exact transferred acknowledgement")
    func cursorAdvancesOnlyAfterExactTransferredAcknowledgement() {
        // Arrange
        let fixture = makePagerFixture(
            participants: [
                makeParticipant(.alpha, values: [("a", "one", 3), ("b", "two", 3)])
            ]
        )
        let lease = requireOpenedLease(fixture.pager.openLease())
        let limits = requireLimits(maximumItems: 1, maximumBytes: 16)
        let firstPage = requireCapturedPage(takePage(fixture.pager, lease: lease, limits: limits))
        let unrelatedPageID = WorkspaceStateSnapshotPageID.make()

        // Act
        let outstandingTake = takePage(fixture.pager, lease: lease, limits: limits)
        let wrongAcknowledgement = fixture.pager.acknowledgePage(
            lease,
            pageID: unrelatedPageID,
            disposition: .transferred
        )
        let retryAcknowledgement = fixture.pager.acknowledgePage(
            lease,
            pageID: firstPage.pageID,
            disposition: .retry
        )
        let replayedPage = requireReplayedPage(takePage(fixture.pager, lease: lease, limits: limits))
        let transferAcknowledgement = fixture.pager.acknowledgePage(
            lease,
            pageID: replayedPage.pageID,
            disposition: .transferred
        )
        let secondPage = requireCapturedPage(takePage(fixture.pager, lease: lease, limits: limits))

        // Assert
        #expect(outstandingTake == .rejected(.pageAlreadyOutstanding(pageID: firstPage.pageID)))
        #expect(
            wrongAcknowledgement
                == .rejected(
                    .pageMismatch(submitted: unrelatedPageID, outstanding: firstPage.pageID)
                )
        )
        #expect(retryAcknowledgement == .queuedForRetry(pageID: firstPage.pageID))
        #expect(replayedPage == firstPage)
        #expect(transferAcknowledgement == .acknowledged(pageID: firstPage.pageID))
        #expect(firstPage.items.map(\.key) == [.init("a")])
        #expect(secondPage.items.map(\.key) == [.init("b")])
    }

    @Test("duplicate and stale acknowledgements cannot disturb newer page custody")
    func duplicateAndStaleAcknowledgementsCannotDisturbNewerPageCustody() {
        // Arrange
        let fixture = makePagerFixture(
            participants: [
                makeParticipant(.alpha, values: [("a", "one", 3), ("b", "two", 3)])
            ]
        )
        let lease = requireOpenedLease(fixture.pager.openLease())
        let limits = requireLimits(maximumItems: 1, maximumBytes: 16)
        let firstPage = requireCapturedPage(takePage(fixture.pager, lease: lease, limits: limits))
        #expect(
            fixture.pager.acknowledgePage(
                lease,
                pageID: firstPage.pageID,
                disposition: .transferred
            ) == .acknowledged(pageID: firstPage.pageID)
        )

        // Act
        let duplicateAcknowledgement = fixture.pager.acknowledgePage(
            lease,
            pageID: firstPage.pageID,
            disposition: .transferred
        )
        let secondPage = requireCapturedPage(takePage(fixture.pager, lease: lease, limits: limits))
        let staleAcknowledgement = fixture.pager.acknowledgePage(
            lease,
            pageID: firstPage.pageID,
            disposition: .transferred
        )
        let retrySecondPage = fixture.pager.acknowledgePage(
            lease,
            pageID: secondPage.pageID,
            disposition: .retry
        )
        let replayedSecondPage = requireReplayedPage(
            takePage(fixture.pager, lease: lease, limits: limits)
        )

        // Assert
        #expect(
            duplicateAcknowledgement
                == .rejected(.duplicateAcknowledgement(pageID: firstPage.pageID))
        )
        #expect(
            staleAcknowledgement
                == .rejected(
                    .staleAcknowledgement(
                        submitted: firstPage.pageID,
                        outstanding: secondPage.pageID
                    )
                )
        )
        #expect(retrySecondPage == .queuedForRetry(pageID: secondPage.pageID))
        #expect(replayedSecondPage == secondPage)
    }

    @Test("normal close rejects outstanding pages and incomplete participants")
    func normalCloseRejectsOutstandingPagesAndIncompleteParticipants() {
        // Arrange
        let fixture = makePagerFixture(
            participants: [
                makeParticipant(.alpha, values: [("a", "one", 3), ("b", "two", 3)])
            ]
        )
        let lease = requireOpenedLease(fixture.pager.openLease())
        let limits = requireLimits(maximumItems: 1, maximumBytes: 16)
        let firstPage = requireCapturedPage(takePage(fixture.pager, lease: lease, limits: limits))

        // Act
        let outstandingClose = fixture.pager.closeLease(lease, disposition: .completed)
        _ = fixture.pager.acknowledgePage(
            lease,
            pageID: firstPage.pageID,
            disposition: .transferred
        )
        let incompleteClose = fixture.pager.closeLease(lease, disposition: .completed)
        let abortResult = fixture.pager.closeLease(lease, disposition: .abort)

        // Assert
        #expect(outstandingClose == .rejected(.pageOutstanding(pageID: firstPage.pageID)))
        #expect(incompleteClose == .rejected(.participantsIncomplete))
        #expect(isAborted(abortResult))
    }

    @Test("abort is idempotent until a successor opens and cannot release the successor")
    func abortIsIdempotentUntilSuccessorOpensAndCannotReleaseSuccessor() {
        // Arrange
        let revisionOwner = WorkspacePersistenceRevisionOwner()
        let leaseAuthority = WorkspaceStateSnapshotPagerLeaseAuthority(revisionOwner: revisionOwner)
        let firstFixture = makePagerFixture(
            revisionOwner: revisionOwner,
            leaseAuthority: leaseAuthority,
            participants: [makeParticipant(.alpha, values: [("a", "one", 3)])]
        )
        let successorFixture = makePagerFixture(
            revisionOwner: revisionOwner,
            leaseAuthority: leaseAuthority,
            participants: [makeParticipant(.beta, values: [("b", "two", 3)])]
        )
        let firstLease = requireOpenedLease(firstFixture.pager.openLease())
        let firstPage = requireCapturedPage(
            takePage(
                firstFixture.pager,
                lease: firstLease,
                limits: requireLimits(maximumItems: 1, maximumBytes: 16)
            )
        )
        #expect(!firstPage.items.isEmpty)

        // Act
        let firstAbort = firstFixture.pager.closeLease(firstLease, disposition: .abort)
        let duplicateAbort = firstFixture.pager.closeLease(firstLease, disposition: .abort)
        let successorLease = requireOpenedLease(successorFixture.pager.openLease())
        let staleAbort = firstFixture.pager.closeLease(firstLease, disposition: .abort)
        let successorPage = takePage(
            successorFixture.pager,
            lease: successorLease,
            limits: requireLimits(maximumItems: 1, maximumBytes: 16)
        )

        // Assert
        let firstReceipt = abortReceipt(from: firstAbort)
        #expect(firstAbort == .aborted(firstReceipt))
        #expect(duplicateAbort == .alreadyClosed(firstReceipt))
        #expect(staleAbort == .rejected(.staleLease))
        #expect(isCapturedPage(successorPage))
    }

    @Test("item and byte limits emit only the maximal ordered prefix")
    func itemAndByteLimitsEmitOnlyMaximalOrderedPrefix() {
        // Arrange
        let itemFixture = makePagerFixture(
            participants: [
                makeParticipant(
                    .alpha,
                    values: [("a", "aaaa", 4), ("b", "bbbb", 4), ("c", "c", 1)]
                )
            ]
        )
        let itemLease = requireOpenedLease(itemFixture.pager.openLease())
        let itemLimits = requireLimits(maximumItems: 2, maximumBytes: 64)
        let byteFixture = makePagerFixture(
            participants: [
                makeParticipant(
                    .alpha,
                    values: [("a", "aaaa", 4), ("b", "bbbb", 4), ("c", "c", 1)]
                )
            ]
        )
        let byteLease = requireOpenedLease(byteFixture.pager.openLease())
        let byteLimits = requireLimits(maximumItems: 8, maximumBytes: 8)

        // Act
        let itemPage = requireCapturedPage(
            takePage(itemFixture.pager, lease: itemLease, limits: itemLimits)
        )
        let bytePage = requireCapturedPage(
            takePage(byteFixture.pager, lease: byteLease, limits: byteLimits)
        )
        _ = itemFixture.pager.acknowledgePage(
            itemLease,
            pageID: itemPage.pageID,
            disposition: .transferred
        )
        _ = byteFixture.pager.acknowledgePage(
            byteLease,
            pageID: bytePage.pageID,
            disposition: .transferred
        )
        let itemRemainder = requireCapturedPage(
            takePage(itemFixture.pager, lease: itemLease, limits: itemLimits)
        )
        let byteRemainder = requireCapturedPage(
            takePage(byteFixture.pager, lease: byteLease, limits: byteLimits)
        )

        // Assert
        #expect(itemPage.items.map(\.key) == [.init("a"), .init("b")])
        #expect(itemPage.itemCount == 2)
        #expect(bytePage.items.map(\.key) == [.init("a"), .init("b")])
        #expect(bytePage.byteCount == 8)
        #expect(itemRemainder.items.map(\.key) == [.init("c")])
        #expect(byteRemainder.items.map(\.key) == [.init("c")])
    }

    @Test("oversized item rejection is side effect free")
    func oversizedItemRejectionIsSideEffectFree() {
        // Arrange
        let fixture = makePagerFixture(
            participants: [makeParticipant(.alpha, values: [("a", "oversized", 17)])]
        )
        let lease = requireOpenedLease(fixture.pager.openLease())
        let rejectingLimits = requireLimits(maximumItems: 1, maximumBytes: 16)
        let acceptingLimits = requireLimits(maximumItems: 1, maximumBytes: 17)
        let recordCountBeforeRejection = fixture.workRecords.records.count

        // Act
        let rejection = takePage(fixture.pager, lease: lease, limits: rejectingLimits)
        let recordCountAfterRejection = fixture.workRecords.records.count
        let acceptedPage = requireCapturedPage(
            takePage(fixture.pager, lease: lease, limits: acceptingLimits)
        )

        // Assert
        #expect(
            rejection
                == .rejected(
                    .itemExceedsByteLimit(
                        participantID: .alpha,
                        key: .init("a"),
                        itemBytes: 17,
                        maximumBytes: 16
                    )
                )
        )
        #expect(recordCountAfterRejection == recordCountBeforeRejection + 1)
        #expect(fixture.workRecords.records.count == recordCountAfterRejection + 1)
        #expect(acceptedPage.items.map(\.key) == [.init("a")])
        #expect(acceptedPage.byteCount == 17)
    }

    @Test("participant registration order is stable and empty participants are skipped")
    func participantRegistrationOrderIsStableAndEmptyParticipantsAreSkipped() {
        // Arrange
        let fixture = makePagerFixture(
            participants: [
                makeParticipant(.gamma, values: []),
                makeParticipant(.beta, values: [("b", "two", 3)]),
                makeParticipant(.alpha, values: [("a", "one", 3)]),
            ]
        )
        let lease = requireOpenedLease(fixture.pager.openLease())
        let limits = requireLimits(maximumItems: 1, maximumBytes: 16)

        // Act
        let firstPage = requireCapturedPage(takePage(fixture.pager, lease: lease, limits: limits))
        _ = fixture.pager.acknowledgePage(
            lease,
            pageID: firstPage.pageID,
            disposition: .transferred
        )
        let secondPage = requireCapturedPage(takePage(fixture.pager, lease: lease, limits: limits))

        // Assert
        #expect(firstPage.participantID == .beta)
        #expect(secondPage.participantID == .alpha)
    }

    @Test("all empty participants exhaust immediately and permit completed close")
    func allEmptyParticipantsExhaustImmediatelyAndPermitCompletedClose() {
        // Arrange
        let fixture = makePagerFixture(
            participants: [
                makeParticipant(.beta, values: []),
                makeParticipant(.alpha, values: []),
            ]
        )
        let lease = requireOpenedLease(fixture.pager.openLease())
        let limits = requireLimits(maximumItems: 2, maximumBytes: 16)

        // Act
        let exhaustion = takePage(fixture.pager, lease: lease, limits: limits)
        let closeResult = fixture.pager.closeLease(lease, disposition: .completed)
        let duplicateClose = fixture.pager.closeLease(lease, disposition: .completed)

        // Assert
        let exhaustionReceipt = requireExhaustion(exhaustion)
        #expect(exhaustionReceipt.pageCount == 0)
        #expect(exhaustionReceipt.itemCount == 0)
        #expect(exhaustionReceipt.byteCount == 0)
        let closeReceipt = completedReceipt(from: closeResult)
        #expect(closeResult == .completed(closeReceipt))
        #expect(duplicateClose == .alreadyClosed(closeReceipt))
    }

    @Test("new captures record exactly once while replay and rejection record zero times")
    func newCapturesRecordExactlyOnceWhileReplayAndRejectionRecordZeroTimes() {
        // Arrange
        let fixture = makePagerFixture(
            participants: [makeParticipant(.alpha, values: [("a", "one", 3)])]
        )
        let lease = requireOpenedLease(fixture.pager.openLease())
        let limits = requireLimits(maximumItems: 1, maximumBytes: 16)
        let firstPage = requireCapturedPage(takePage(fixture.pager, lease: lease, limits: limits))
        let recordsAfterCapture = fixture.workRecords.records

        // Act
        let rejectedTake = takePage(fixture.pager, lease: lease, limits: limits)
        _ = fixture.pager.acknowledgePage(
            lease,
            pageID: firstPage.pageID,
            disposition: .retry
        )
        let replayedPage = requireReplayedPage(takePage(fixture.pager, lease: lease, limits: limits))
        let recordsAfterReplay = fixture.workRecords.records

        // Assert
        #expect(recordsAfterCapture.count == 1)
        #expect(rejectedTake == .rejected(.pageAlreadyOutstanding(pageID: firstPage.pageID)))
        #expect(replayedPage == firstPage)
        #expect(recordsAfterReplay == recordsAfterCapture)
        let record = recordsAfterCapture[0]
        #expect(record.domain == .persistence)
        #expect(record.operation == .persistencePageCapture)
        #expect(record.revision == .value(lease.baseRevision.rawValue))
        #expect(record.counts == .init(input: 1, changedKey: 1))
        #expect(UUIDv7.isV7(record.workID.rawValue))
    }

    @Test("scan bound preserves the first un-emitted key for the next capture")
    func scanBoundPreservesFirstUnemittedKeyForNextCapture() {
        // Arrange
        let participant = makeParticipant(
            .alpha,
            values: [("a", "one", 3), ("b", "two", 3), ("c", "three", 5)]
        )
        let fixture = makePagerFixture(participants: [participant])
        let lease = requireOpenedLease(fixture.pager.openLease())
        let limits = requireLimits(
            maximumItems: 8,
            maximumBytes: 64,
            maximumScannedItems: 1
        )

        // Act
        let firstPage = requireCapturedPage(takePage(fixture.pager, lease: lease, limits: limits))
        let firstDiagnostics = participant.keyedParticipant.diagnostics(for: lease)
        let readKeysAfterFirstPage = participant.source.readKeys
        let sizedKeysAfterFirstPage = participant.source.sizedKeys
        _ = fixture.pager.acknowledgePage(
            lease,
            pageID: firstPage.pageID,
            disposition: .transferred
        )
        let secondPage = requireCapturedPage(takePage(fixture.pager, lease: lease, limits: limits))

        // Assert
        #expect(firstPage.items.map(\.key) == [.init("a")])
        #expect(readKeysAfterFirstPage == [.init("a")])
        #expect(sizedKeysAfterFirstPage == [.init("a")])
        #expect(participant.source.readKeys == [.init("a"), .init("b")])
        #expect(participant.source.sizedKeys == [.init("a"), .init("b")])
        #expect(
            firstDiagnostics
                == .diagnostics(
                    .init(
                        baseMembershipCount: 3,
                        copiedBaseValueCount: 1,
                        retainedBaseValueCount: 0
                    )
                )
        )
        #expect(secondPage.items.map(\.key) == [.init("b")])
    }

    @Test("service limit before progress records failure and preserves the first key")
    func serviceLimitBeforeProgressRecordsFailureAndPreservesFirstKey() {
        // Arrange
        let participant = makeParticipant(.alpha, values: [("a", "one", 3)])
        let fixture = makePagerFixture(
            participants: [participant],
            serviceClock: PageCaptureScriptedClock([0, 10, 20, 21, 22])
        )
        let lease = requireOpenedLease(fixture.pager.openLease())
        let limits = requireLimits(
            maximumItems: 1,
            maximumBytes: 16,
            maximumSynchronousServiceNanoseconds: 10
        )

        // Act
        let limitedAttempt = takePage(fixture.pager, lease: lease, limits: limits)
        let recordsAfterLimitedAttempt = fixture.workRecords.records
        let readKeysAfterLimitedAttempt = participant.source.readKeys
        let sizedKeysAfterLimitedAttempt = participant.source.sizedKeys
        let recoveredPage = requireCapturedPage(takePage(fixture.pager, lease: lease, limits: limits))

        // Assert
        #expect(limitedAttempt == .rejected(.synchronousServiceLimitReachedWithoutProgress))
        #expect(recordsAfterLimitedAttempt.count == 1)
        #expect(recordsAfterLimitedAttempt[0].outcome == .failed)
        #expect(recordsAfterLimitedAttempt[0].counts == .init(input: 0, changedKey: 0))
        #expect(readKeysAfterLimitedAttempt.isEmpty)
        #expect(sizedKeysAfterLimitedAttempt.isEmpty)
        #expect(participant.source.readKeys == [.init("a")])
        #expect(participant.source.sizedKeys == [.init("a")])
        #expect(recoveredPage.items.map(\.key) == [.init("a")])
    }

    @Test("post-body ledger reversal preserves immutable page custody without a record")
    func postBodyLedgerReversalPreservesImmutablePageCustodyWithoutRecord() {
        // Arrange
        let fixture = makePagerFixture(
            participants: [makeParticipant(.alpha, values: [("a", "one", 3)])],
            workLedgerClock: PageCaptureScriptedClock([100, 200, 150, 300])
        )
        let lease = requireOpenedLease(fixture.pager.openLease())
        let limits = requireLimits(maximumItems: 1, maximumBytes: 16)

        // Act
        let capturedPage = requireCapturedPage(takePage(fixture.pager, lease: lease, limits: limits))
        let retryResult = fixture.pager.acknowledgePage(
            lease,
            pageID: capturedPage.pageID,
            disposition: .retry
        )
        let replayedPage = requireReplayedPage(takePage(fixture.pager, lease: lease, limits: limits))

        // Assert
        #expect(fixture.workRecords.records.isEmpty)
        #expect(
            fixture.workInvalidities.invalidities
                == [.clockReversal(.startToSynchronousEnd)]
        )
        #expect(retryResult == .queuedForRetry(pageID: capturedPage.pageID))
        #expect(replayedPage == capturedPage)
    }

    @Test("participant commit failure aborts the lease and releases shared authority")
    func participantCommitFailureAbortsLeaseAndReleasesSharedAuthority() {
        // Arrange
        let revisionOwner = WorkspacePersistenceRevisionOwner()
        let leaseAuthority = WorkspaceStateSnapshotPagerLeaseAuthority(revisionOwner: revisionOwner)
        let failingParticipant = makeParticipant(.alpha, values: [("a", "one", 3)])
        let failingFixture = makePagerFixture(
            revisionOwner: revisionOwner,
            leaseAuthority: leaseAuthority,
            participants: [failingParticipant]
        )
        let successorFixture = makePagerFixture(
            revisionOwner: revisionOwner,
            leaseAuthority: leaseAuthority,
            participants: [makeParticipant(.beta, values: [("b", "two", 3)])]
        )
        let lease = requireOpenedLease(failingFixture.pager.openLease())
        var injectedConflictingMark = false
        failingParticipant.source.performWhenEstimatingByteCount {
            guard !injectedConflictingMark else { return }
            injectedConflictingMark = true
            #expect(
                failingParticipant.keyedParticipant.markBaseValueCopied(
                    lease: lease,
                    key: .init("a"),
                    pageID: .make()
                ) == .markedCopied
            )
        }

        // Act
        let failedCapture = takePage(
            failingFixture.pager,
            lease: lease,
            limits: requireLimits(maximumItems: 1, maximumBytes: 16)
        )
        let successorOpen = successorFixture.pager.openLease()

        // Assert
        #expect(
            failedCapture
                == .rejected(
                    .participantCommitRejected(.baseValueCopiedByDifferentPage)
                )
        )
        #expect(failingParticipant.source.readKeys == [.init("a")])
        #expect(failingParticipant.source.sizedKeys == [.init("a")])
        #expect(failingParticipant.keyedParticipant.diagnostics(for: lease) == .rejected(.noActiveLease))
        #expect(isOpened(successorOpen))
    }

    @Test("empty participant inspection yields bounded continuation without post-page lookahead")
    func emptyParticipantInspectionYieldsBoundedContinuationWithoutPostPageLookahead() {
        // Arrange
        let fixture = makePagerFixture(
            participants: [
                makeParticipant(.alpha, values: [("a", "one", 3)]),
                makeParticipant(.beta, values: []),
                makeParticipant(.gamma, values: []),
            ]
        )
        let lease = requireOpenedLease(fixture.pager.openLease())
        let limits = requireLimits(
            maximumItems: 1,
            maximumBytes: 16,
            maximumParticipantInspections: 1
        )
        let page = requireCapturedPage(takePage(fixture.pager, lease: lease, limits: limits))
        #expect(
            fixture.pager.acknowledgePage(
                lease,
                pageID: page.pageID,
                disposition: .transferred
            ) == .acknowledged(pageID: page.pageID)
        )

        // Act
        let firstContinuation = requireYieldedProgress(
            takePage(fixture.pager, lease: lease, limits: limits)
        )
        let secondContinuation = requireYieldedProgress(
            takePage(fixture.pager, lease: lease, limits: limits)
        )
        let exhaustion = requireExhaustion(
            takePage(fixture.pager, lease: lease, limits: limits)
        )

        // Assert
        #expect(page.participantID == .alpha)
        #expect(firstContinuation.nextParticipantIndex == 2)
        #expect(firstContinuation.participantInspectionCount == 1)
        #expect(secondContinuation.nextParticipantIndex == 3)
        #expect(secondContinuation.participantInspectionCount == 1)
        #expect(exhaustion.pageCount == 1)
        #expect(exhaustion.itemCount == 1)
    }
}
