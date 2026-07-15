import Testing

@testable import AgentStudio

@MainActor
@Suite(.serialized)
struct WorkspacePersistencePageCaptureFailureTests {
    @Test("typed participant bootstrap rejects invalid membership atomically")
    func typedParticipantBootstrapRejectsInvalidMembershipAtomically() {
        // Arrange
        let duplicateKey = PageCaptureTestKey("duplicate")
        let duplicateParticipant = WorkspaceStateSnapshotKeyedParticipant<
            PageCaptureTestKey,
            PageCaptureTestValue
        >()
        let capacityParticipant = WorkspaceStateSnapshotKeyedParticipant<
            PageCaptureTestKey,
            PageCaptureTestValue
        >()
        let oneKeyLimits = WorkspaceStateSnapshotMembershipLimits(
            maximumKeyCount: 1,
            maximumRawKeyBytes: 16
        )

        // Act
        let duplicateResult = makeConstruction(
            keyedParticipant: duplicateParticipant,
            keys: [duplicateKey, duplicateKey],
            limits: oneKeyLimits
        )
        let capacityResult = makeConstruction(
            keyedParticipant: capacityParticipant,
            keys: [PageCaptureTestKey("a"), PageCaptureTestKey("b")],
            limits: oneKeyLimits
        )
        let duplicateRetry = makeConstruction(
            keyedParticipant: duplicateParticipant,
            keys: [duplicateKey],
            limits: oneKeyLimits
        )
        let capacityRetry = makeConstruction(
            keyedParticipant: capacityParticipant,
            keys: [PageCaptureTestKey("a")],
            limits: oneKeyLimits
        )

        // Assert
        #expect(isConstructionRejected(duplicateResult, as: .duplicateCurrentKey))
        #expect(isConstructionRejected(capacityResult, as: .baseMembershipKeyCountCapacityExceeded))
        #expect(isConstructionSuccessful(duplicateRetry))
        #expect(isConstructionSuccessful(capacityRetry))
    }

    @Test("page and exhaustion work counts include participant and slot inspections")
    func pageAndExhaustionWorkCountsIncludeAllInspections() {
        // Arrange
        let pageFixture = makePagerFixture(
            participants: [
                makeParticipant(.alpha, values: []),
                makeParticipant(.beta, values: [("b", "two", 3)]),
            ]
        )
        let pageLease = requireOpenedLease(pageFixture.pager.openLease())
        let exhaustionFixture = makePagerFixture(
            participants: [
                makeParticipant(.alpha, values: []),
                makeParticipant(.beta, values: []),
            ]
        )
        let exhaustionLease = requireOpenedLease(exhaustionFixture.pager.openLease())
        let limits = requireLimits(maximumItems: 1, maximumBytes: 16)

        // Act
        let page = requireCapturedPage(
            takePage(pageFixture.pager, lease: pageLease, limits: limits)
        )
        _ = requireExhaustion(
            takePage(exhaustionFixture.pager, lease: exhaustionLease, limits: limits)
        )

        // Assert
        #expect(page.items.map(\.itemID) == [.text("b")])
        #expect(pageFixture.workRecords.records.count == 1)
        #expect(
            pageFixture.workRecords.records[0].counts
                == .init(input: 3, changedKey: 1)
        )
        #expect(exhaustionFixture.workRecords.records.count == 1)
        #expect(
            exhaustionFixture.workRecords.records[0].counts
                == .init(input: 2, changedKey: 0)
        )
    }

    @Test("partial multi item mark failure exposes no page and successor recaptures authority")
    func partialMultiItemMarkFailureAbortsAndSuccessorRecapturesAuthority() {
        // Arrange
        let revisionOwner = WorkspacePersistenceRevisionOwner()
        let leaseAuthority = WorkspaceStateSnapshotPagerLeaseAuthority(revisionOwner: revisionOwner)
        let participant = makeParticipant(
            .alpha,
            values: [("a", "one", 3), ("b", "two", 3)]
        )
        let failingPager = makePager(
            revisionOwner: revisionOwner,
            leaseAuthority: leaseAuthority,
            participant: participant
        )
        let lease = requireOpenedLease(failingPager.openLease())
        var estimateCount = 0
        participant.source.performWhenEstimatingByteCount {
            estimateCount += 1
            guard estimateCount == 2 else { return }
            guard
                case .item(_, _, let copyToken, _) =
                    participant.keyedParticipant.inspectBaseSlot(
                        lease: lease,
                        slotCursor: 1,
                        currentValue: participant.source.storedValue
                    )
            else {
                Issue.record("expected second base slot before conflicting mark")
                return
            }
            #expect(
                participant.keyedParticipant.markBaseValueCopied(
                    lease: lease,
                    copyToken: copyToken,
                    pageID: .make()
                ) == .markedCopied
            )
        }

        // Act
        let failedCapture = takePage(
            failingPager,
            lease: lease,
            limits: requireLimits(maximumItems: 2, maximumBytes: 16)
        )
        participant.source.performWhenEstimatingByteCount {}
        let successorPager = makePager(
            revisionOwner: revisionOwner,
            leaseAuthority: leaseAuthority,
            participant: participant
        )
        let successorLease = requireOpenedLease(successorPager.openLease())
        let successorPage = requireCapturedPage(
            takePage(
                successorPager,
                lease: successorLease,
                limits: requireLimits(maximumItems: 2, maximumBytes: 16)
            )
        )

        // Assert
        #expect(
            failedCapture
                == .rejected(
                    .participantCommitRejected(.baseValueCopiedByDifferentPage)
                )
        )
        #expect(participant.keyedParticipant.diagnostics(for: lease) == .rejected(.foreignLease))
        #expect(successorPage.items.map(\.itemID) == [.text("a"), .text("b")])
        #expect(
            successorPage.items.map(\.item) == [
                .text(participantID: .alpha, id: "a", payload: "one"),
                .text(participantID: .alpha, id: "b", payload: "two"),
            ])
    }

    private func makePager(
        revisionOwner: WorkspacePersistenceRevisionOwner,
        leaseAuthority: WorkspaceStateSnapshotPagerLeaseAuthority,
        participant: PageCaptureTestParticipantFixture
    ) -> WorkspaceStateSnapshotPager<PageCaptureTestParticipantID, PageCaptureTestItem> {
        WorkspaceStateSnapshotPager(
            pagerIdentity: .make(),
            revisionOwner: revisionOwner,
            leaseAuthority: leaseAuthority,
            participants: [participant.registration],
            workLedger: MainActorWorkLedger(clock: PageCaptureIncrementingClock()),
            workRecordObserver: { _ in },
            workInvalidityObserver: { _ in }
        )
    }

    private func makeConstruction(
        keyedParticipant: WorkspaceStateSnapshotKeyedParticipant<PageCaptureTestKey, PageCaptureTestValue>,
        keys: [PageCaptureTestKey],
        limits: WorkspaceStateSnapshotMembershipLimits
    ) -> SnapshotPagerParticipantConstructionResult<
        PageCaptureTestParticipantID,
        PageCaptureTestItem
    > {
        WorkspaceStateSnapshotPagerParticipant<
            PageCaptureTestParticipantID,
            PageCaptureTestItem
        >.typed(
            participantID: .alpha,
            keyedParticipant: keyedParticipant,
            membershipLimits: limits,
            orderedBaseKeys: { keys },
            currentValue: { key in
                .value(PageCaptureTestValue(payload: key.rawValue, byteCount: 1))
            },
            projection: .init(
                itemIDForKey: { .text($0.rawValue) },
                projectItem: { key, value in
                    WorkspaceStateSnapshotPagerTypedItem(
                        item: .text(
                            participantID: .alpha,
                            id: key.rawValue,
                            payload: value.payload
                        ),
                        estimatedByteCount: value.byteCount
                    )
                }
            )
        )
    }

    private func isConstructionRejected(
        _ result: SnapshotPagerParticipantConstructionResult<
            PageCaptureTestParticipantID,
            PageCaptureTestItem
        >,
        as expectedRejection: WorkspaceStateSnapshotParticipantRejection
    ) -> Bool {
        guard case .rejected(let rejection) = result else { return false }
        return rejection == expectedRejection
    }

    private func isConstructionSuccessful(
        _ result: SnapshotPagerParticipantConstructionResult<
            PageCaptureTestParticipantID,
            PageCaptureTestItem
        >
    ) -> Bool {
        guard case .constructed = result else { return false }
        return true
    }
}
