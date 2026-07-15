import Testing

@testable import AgentStudio

@MainActor
@Suite(.serialized)
struct WorkspacePersistencePageCaptureRouteTests {
    @Test("same participant with wrong item identity rejects without consuming source slot")
    func sameParticipantWrongItemIdentityRejectsWithoutConsumingSourceSlot() {
        // Arrange
        let source = PageCaptureTestSource(
            entries: [(PageCaptureTestKey("a"), PageCaptureTestValue(payload: "one", byteCount: 3))]
        )
        let keyedParticipant = WorkspaceStateSnapshotKeyedParticipant<
            PageCaptureTestKey,
            PageCaptureTestValue
        >()
        var projectsWrongIdentity = true
        let registration = requireConstructedParticipant(
            WorkspaceStateSnapshotPagerParticipant<
                PageCaptureTestParticipantID,
                PageCaptureTestItem
            >.typed(
                participantID: .alpha,
                keyedParticipant: keyedParticipant,
                membershipLimits: pageCaptureTestMembershipLimits,
                orderedBaseKeys: { source.orderedKeys },
                currentValue: source.storedValue,
                projection: .init(
                    itemIDForKey: { .text($0.rawValue) },
                    projectItem: { key, value in
                        WorkspaceStateSnapshotPagerTypedItem(
                            item: .text(
                                participantID: .alpha,
                                id: projectsWrongIdentity ? "wrong" : key.rawValue,
                                payload: value.payload
                            ),
                            estimatedByteCount: value.byteCount
                        )
                    }
                )
            ))
        let fixture = makePagerFixture(
            participants: [
                PageCaptureTestParticipantFixture(
                    registration: registration,
                    keyedParticipant: keyedParticipant,
                    source: source
                )
            ]
        )
        let lease = requireOpenedLease(fixture.pager.openLease())
        let limits = requireLimits(maximumItems: 1, maximumBytes: 16)

        // Act
        let mismatch = takePage(fixture.pager, lease: lease, limits: limits)
        projectsWrongIdentity = false
        let correctedPage = requireCapturedPage(
            takePage(fixture.pager, lease: lease, limits: limits)
        )

        // Assert
        #expect(
            mismatch
                == .rejected(
                    .itemIdentityMismatch(
                        participantID: .alpha,
                        expected: .text("a"),
                        actual: .text("wrong")
                    )
                )
        )
        #expect(correctedPage.items.map(\.itemID) == [.text("a")])
    }

    @Test("projected item route must match its registered participant")
    func projectedItemRouteMustMatchRegisteredParticipant() {
        // Arrange
        let source = PageCaptureTestSource(
            entries: [
                (
                    PageCaptureTestKey("a"),
                    PageCaptureTestValue(payload: "one", byteCount: 3)
                )
            ]
        )
        let keyedParticipant = WorkspaceStateSnapshotKeyedParticipant<
            PageCaptureTestKey,
            PageCaptureTestValue
        >()
        let registration = requireConstructedParticipant(
            WorkspaceStateSnapshotPagerParticipant<
                PageCaptureTestParticipantID,
                PageCaptureTestItem
            >.typed(
                participantID: .alpha,
                keyedParticipant: keyedParticipant,
                membershipLimits: pageCaptureTestMembershipLimits,
                orderedBaseKeys: { source.orderedKeys },
                currentValue: source.storedValue,
                projection: .init(
                    itemIDForKey: { .text($0.rawValue) },
                    projectItem: { key, value in
                        WorkspaceStateSnapshotPagerTypedItem(
                            item: .text(
                                participantID: .beta,
                                id: key.rawValue,
                                payload: value.payload
                            ),
                            estimatedByteCount: value.byteCount
                        )
                    }
                )
            ))
        let fixture = makePagerFixture(
            participants: [
                PageCaptureTestParticipantFixture(
                    registration: registration,
                    keyedParticipant: keyedParticipant,
                    source: source
                )
            ]
        )
        let lease = requireOpenedLease(fixture.pager.openLease())

        // Act
        let result = takePage(
            fixture.pager,
            lease: lease,
            limits: requireLimits(maximumItems: 1, maximumBytes: 16)
        )

        // Assert
        #expect(
            result
                == .rejected(
                    .itemParticipantMismatch(
                        expected: .alpha,
                        actual: .beta,
                        itemID: .text("a")
                    )
                )
        )
    }

    @Test("empty typed participant accepts insertion before its first lease")
    func emptyTypedParticipantAcceptsInsertionBeforeFirstLease() throws {
        // Arrange
        let revisionOwner = WorkspacePersistenceRevisionOwner()
        let limits = WorkspaceStateSnapshotMembershipLimits(
            maximumKeyCount: 8,
            maximumRawKeyBytes: 64
        )
        let insertedKey = PageCaptureTestKey("inserted")
        let insertedValue = PageCaptureTestValue(payload: "current", byteCount: 7)
        let keyedParticipant = WorkspaceStateSnapshotKeyedParticipant<
            PageCaptureTestKey,
            PageCaptureTestValue
        >()
        let registration = requireConstructedParticipant(
            WorkspaceStateSnapshotPagerParticipant<
                PageCaptureTestParticipantID,
                PageCaptureTestItem
            >.typed(
                participantID: .alpha,
                keyedParticipant: keyedParticipant,
                membershipLimits: limits,
                orderedBaseKeys: { [] },
                currentValue: { key in key == insertedKey ? .value(insertedValue) : .absent },
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
            ))

        // Act
        let insertion = try revisionOwner.performSynchronousTransaction { preparation in
            preparation.commit {
                keyedParticipant.recordInserted(
                    key: insertedKey,
                    rawKeyByteCount: 8,
                    transaction: preparation.transaction,
                    revisionOwner: revisionOwner
                )
            }
        }
        let workLedger = MainActorWorkLedger(clock: PageCaptureIncrementingClock())
        let pager = WorkspaceStateSnapshotPager(
            pagerIdentity: .make(),
            revisionOwner: revisionOwner,
            leaseAuthority: WorkspaceStateSnapshotPagerLeaseAuthority(
                revisionOwner: revisionOwner
            ),
            participants: [registration],
            membershipLimits: limits,
            workLedger: workLedger,
            workRecordObserver: { _ in },
            workInvalidityObserver: { _ in }
        )
        let lease = requireOpenedLease(pager.openLease())
        let page = requireCapturedPage(
            takePage(
                pager,
                lease: lease,
                limits: requireLimits(maximumItems: 1, maximumBytes: 16)
            )
        )

        // Assert
        #expect(insertion == .inserted)
        #expect(page.items.map(\.itemID) == [.text("inserted")])
    }

    @Test("pager cleanup is bounded and blocks successor lease until complete")
    func pagerCleanupIsBoundedAndBlocksSuccessorLeaseUntilComplete() throws {
        // Arrange
        let participant = makeParticipant(
            .alpha,
            values: [("a", "one", 3), ("b", "two", 3)]
        )
        let revisionOwner = WorkspacePersistenceRevisionOwner()
        let workLedger = MainActorWorkLedger(clock: PageCaptureIncrementingClock())
        let pager = WorkspaceStateSnapshotPager(
            pagerIdentity: .make(),
            revisionOwner: revisionOwner,
            leaseAuthority: WorkspaceStateSnapshotPagerLeaseAuthority(
                revisionOwner: revisionOwner
            ),
            participants: [participant.registration],
            workLedger: workLedger,
            workRecordObserver: { _ in },
            workInvalidityObserver: { _ in }
        )
        let lease = requireOpenedLease(pager.openLease())
        try revisionOwner.performSynchronousTransaction { preparation in
            preparation.commit {
                for key in participant.source.orderedKeys {
                    #expect(
                        participant.keyedParticipant.recordWillChange(
                            key: key,
                            currentValue: .value(
                                PageCaptureTestValue(payload: "base", byteCount: 4)
                            ),
                            transaction: preparation.transaction,
                            revisionOwner: revisionOwner
                        ) == .retainedFirstBaseValue
                    )
                }
            }
        }
        #expect(isAborted(pager.closeLease(lease, disposition: .abort)))

        // Act
        let blockedOpen = pager.openLease()
        let firstDrain = pager.drainCleanup(maximumValues: 1)
        let stillBlockedOpen = pager.openLease()
        let secondDrain = pager.drainCleanup(maximumValues: 1)
        let completedDrain = pager.drainCleanup(maximumValues: 1)
        let successorOpen = pager.openLease()

        // Assert
        #expect(blockedOpen == .rejected(.cleanupPending))
        #expect(firstDrain == .drained(releasedValueCount: 1, remainingValueCount: 1))
        #expect(stillBlockedOpen == .rejected(.cleanupPending))
        #expect(secondDrain == .drained(releasedValueCount: 1, remainingValueCount: 0))
        #expect(completedDrain == .complete)
        #expect(isOpened(successorOpen))
    }

    @Test("partial participant open failure rolls back participant and process authority")
    func partialParticipantOpenFailureRollsBackParticipantAndProcessAuthority() {
        // Arrange
        let revisionOwner = WorkspacePersistenceRevisionOwner()
        let leaseAuthority = WorkspaceStateSnapshotPagerLeaseAuthority(revisionOwner: revisionOwner)
        let firstParticipant = makeParticipant(.alpha, values: [("a", "one", 3)])
        let rejectingRegistration = requireConstructedParticipant(
            WorkspaceStateSnapshotPagerParticipant<
                PageCaptureTestParticipantID,
                PageCaptureTestItem
            >.typed(
                participantID: .beta,
                keyedParticipant: firstParticipant.keyedParticipant,
                membershipLimits: pageCaptureTestMembershipLimits,
                orderedBaseKeys: { [] },
                currentValue: firstParticipant.source.storedValue,
                projection: .init(
                    itemIDForKey: { .text($0.rawValue) },
                    projectItem: { key, value in
                        WorkspaceStateSnapshotPagerTypedItem(
                            item: .text(
                                participantID: .beta,
                                id: key.rawValue,
                                payload: value.payload
                            ),
                            estimatedByteCount: value.byteCount
                        )
                    }
                )
            ))
        let failingPager = WorkspaceStateSnapshotPager(
            pagerIdentity: .make(),
            revisionOwner: revisionOwner,
            leaseAuthority: leaseAuthority,
            participants: [firstParticipant.registration, rejectingRegistration],
            workLedger: MainActorWorkLedger(clock: PageCaptureIncrementingClock()),
            workRecordObserver: { _ in },
            workInvalidityObserver: { _ in }
        )

        // Act
        let failedOpen = failingPager.openLease()
        let successorPager = WorkspaceStateSnapshotPager(
            pagerIdentity: .make(),
            revisionOwner: revisionOwner,
            leaseAuthority: leaseAuthority,
            participants: [firstParticipant.registration],
            workLedger: MainActorWorkLedger(clock: PageCaptureIncrementingClock()),
            workRecordObserver: { _ in },
            workInvalidityObserver: { _ in }
        )
        let successorOpen = successorPager.openLease()

        // Assert
        #expect(
            failedOpen
                == .rejected(
                    .participantRejected(.activeLeaseExists)
                )
        )
        #expect(isOpened(successorOpen))
    }
}
