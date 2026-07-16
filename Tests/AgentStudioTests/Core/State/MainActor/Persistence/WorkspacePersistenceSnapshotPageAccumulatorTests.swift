import Foundation
import Testing

@testable import AgentStudio

@Suite("Workspace persistence snapshot page accumulator")
struct WorkspacePersistenceSnapshotPageAccumulatorTests {
    @Test("more than one page budget accumulates in exact participant and item order")
    func moreThanOnePageBudgetAccumulatesInExactParticipantAndItemOrder() async {
        // Arrange
        let lease = await makeLease()
        let accumulator = WorkspacePersistenceSnapshotPageAccumulator(lease: lease)
        let repositoryIDs = (0..<257).map { _ in UUIDv7.generate() }
        let firstPage = makePage(
            lease: lease,
            participantID: .unavailableRepositories,
            items: repositoryIDs.prefix(256).map {
                makePageItem(.unavailableRepository($0))
            }
        )
        let secondPage = makePage(
            lease: lease,
            participantID: .unavailableRepositories,
            items: repositoryIDs.suffix(1).map {
                makePageItem(.unavailableRepository($0))
            },
            exhaustsLease: true
        )

        // Act
        let firstAppend = await accumulator.append(
            firstPage,
            sequence: WorkspacePersistenceSnapshotPageSequence(rawValue: 0)
        )
        let secondAppend = await accumulator.append(
            secondPage,
            sequence: WorkspacePersistenceSnapshotPageSequence(rawValue: 1)
        )
        let result = await accumulator.finish(
            makeExhaustionReceipt(
                lease: lease,
                pages: [firstPage, secondPage]
            ))

        // Assert
        #expect(firstAppend == .accepted(pageID: firstPage.pageID))
        #expect(secondAppend == .accepted(pageID: secondPage.pageID))
        guard case .finished(let participants) = result else {
            Issue.record("expected accumulated participant items")
            return
        }
        #expect(participants.map(\.participantID) == WorkspacePersistenceSnapshotParticipantID.allCases)
        #expect(participants.count == WorkspacePersistenceSnapshotParticipantID.allCases.count)
        #expect(
            participants.first { $0.participantID == .unavailableRepositories }?.items
                == repositoryIDs.map(WorkspacePersistenceSnapshotItem.unavailableRepository)
        )
        #expect(
            participants.filter { $0.participantID != .unavailableRepositories }
                .allSatisfy { $0.items.isEmpty }
        )
    }

    @Test("empty participants remain present in canonical order")
    func emptyParticipantsRemainPresentInCanonicalOrder() async {
        // Arrange
        let lease = await makeLease()
        let accumulator = WorkspacePersistenceSnapshotPageAccumulator(lease: lease)

        // Act
        let result = await accumulator.finish(
            WorkspaceStateSnapshotExhaustionReceipt(
                lease: lease,
                pageCount: 0,
                itemCount: 0,
                byteCount: 0
            ))

        // Assert
        guard case .finished(let participants) = result else {
            Issue.record("expected empty canonical participant fleet")
            return
        }
        #expect(participants.map(\.participantID) == WorkspacePersistenceSnapshotParticipantID.allCases)
        #expect(participants.allSatisfy { $0.items.isEmpty })
    }

    @Test("foreign and stale leases are rejected without accepting their pages")
    func foreignAndStaleLeasesAreRejectedWithoutAcceptingTheirPages() async {
        // Arrange
        let pagerIdentity = WorkspaceStateSnapshotPagerIdentity.make()
        let lease = await makeLease(pagerIdentity: pagerIdentity)
        let staleLease = await makeLease(pagerIdentity: pagerIdentity)
        let foreignLease = await makeLease()
        let accumulator = WorkspacePersistenceSnapshotPageAccumulator(lease: lease)
        let stalePage = makePage(
            lease: staleLease,
            participantID: .unavailableRepositories,
            items: [makePageItem(.unavailableRepository(UUIDv7.generate()))]
        )
        let foreignPage = makePage(
            lease: foreignLease,
            participantID: .unavailableRepositories,
            items: [makePageItem(.unavailableRepository(UUIDv7.generate()))]
        )

        // Act
        let staleResult = await accumulator.append(
            stalePage,
            sequence: WorkspacePersistenceSnapshotPageSequence(rawValue: 0)
        )
        let foreignResult = await accumulator.append(
            foreignPage,
            sequence: WorkspacePersistenceSnapshotPageSequence(rawValue: 0)
        )

        // Assert
        #expect(staleResult == .rejected(.staleLease))
        #expect(foreignResult == .rejected(.foreignLease))
    }

    @Test("duplicate page identities and out-of-order sequences are rejected")
    func duplicatePageIdentitiesAndOutOfOrderSequencesAreRejected() async {
        // Arrange
        let lease = await makeLease()
        let accumulator = WorkspacePersistenceSnapshotPageAccumulator(lease: lease)
        let firstPage = makePage(
            lease: lease,
            participantID: .unavailableRepositories,
            items: [makePageItem(.unavailableRepository(UUIDv7.generate()))]
        )

        // Act
        let firstResult = await accumulator.append(
            firstPage,
            sequence: WorkspacePersistenceSnapshotPageSequence(rawValue: 0)
        )
        let duplicateResult = await accumulator.append(
            firstPage,
            sequence: WorkspacePersistenceSnapshotPageSequence(rawValue: 1)
        )
        let outOfOrderPage = makePage(
            lease: lease,
            participantID: .unavailableRepositories,
            items: [makePageItem(.unavailableRepository(UUIDv7.generate()))]
        )
        let outOfOrderResult = await accumulator.append(
            outOfOrderPage,
            sequence: WorkspacePersistenceSnapshotPageSequence(rawValue: 2)
        )

        // Assert
        #expect(firstResult == .accepted(pageID: firstPage.pageID))
        #expect(duplicateResult == .rejected(.duplicatePageID(firstPage.pageID)))
        #expect(
            outOfOrderResult
                == .rejected(
                    .pageSequenceMismatch(
                        expected: WorkspacePersistenceSnapshotPageSequence(rawValue: 1),
                        actual: WorkspacePersistenceSnapshotPageSequence(rawValue: 2)
                    )
                )
        )
    }

    @Test("same participant may span pages but participant regression is rejected")
    func sameParticipantMaySpanPagesButParticipantRegressionIsRejected() async {
        // Arrange
        let lease = await makeLease()
        let accumulator = WorkspacePersistenceSnapshotPageAccumulator(lease: lease)
        let firstPage = makePage(
            lease: lease,
            participantID: .repositories,
            items: []
        )
        let sameParticipantPage = makePage(
            lease: lease,
            participantID: .repositories,
            items: []
        )
        let laterParticipantPage = makePage(
            lease: lease,
            participantID: .worktrees,
            items: []
        )
        let regressedPage = makePage(
            lease: lease,
            participantID: .repositories,
            items: []
        )

        // Act
        let firstResult = await accumulator.append(
            firstPage,
            sequence: .init(rawValue: 0)
        )
        let sameParticipantResult = await accumulator.append(
            sameParticipantPage,
            sequence: .init(rawValue: 1)
        )
        let laterParticipantResult = await accumulator.append(
            laterParticipantPage,
            sequence: .init(rawValue: 2)
        )
        let regressionResult = await accumulator.append(
            regressedPage,
            sequence: .init(rawValue: 3)
        )

        // Assert
        #expect(firstResult == .accepted(pageID: firstPage.pageID))
        #expect(sameParticipantResult == .accepted(pageID: sameParticipantPage.pageID))
        #expect(laterParticipantResult == .accepted(pageID: laterParticipantPage.pageID))
        #expect(
            regressionResult
                == .rejected(
                    .participantRegression(
                        previous: .worktrees,
                        submitted: .repositories
                    )
                )
        )
    }

    @Test("an item owned by another participant is rejected")
    func itemOwnedByAnotherParticipantIsRejected() async {
        // Arrange
        let lease = await makeLease()
        let accumulator = WorkspacePersistenceSnapshotPageAccumulator(lease: lease)
        let foreignItem = WorkspacePersistenceSnapshotItem.unavailableRepository(UUIDv7.generate())
        let page = makePage(
            lease: lease,
            participantID: .repositories,
            items: [makePageItem(foreignItem)]
        )

        // Act
        let result = await accumulator.append(page, sequence: .init(rawValue: 0))

        // Assert
        #expect(
            result
                == .rejected(
                    .foreignItem(
                        declaredParticipant: .repositories,
                        actualParticipant: .unavailableRepositories,
                        itemID: foreignItem.itemID
                    )
                )
        )
    }

    @Test("exhaustion totals are checked before final output is published")
    func exhaustionTotalsAreCheckedBeforeFinalOutputIsPublished() async {
        // Arrange
        let lease = await makeLease()
        let accumulator = WorkspacePersistenceSnapshotPageAccumulator(lease: lease)
        let page = makePage(
            lease: lease,
            participantID: .unavailableRepositories,
            items: [makePageItem(.unavailableRepository(UUIDv7.generate()))]
        )
        _ = await accumulator.append(page, sequence: .init(rawValue: 0))

        // Act
        let mismatch = await accumulator.finish(
            WorkspaceStateSnapshotExhaustionReceipt(
                lease: lease,
                pageCount: 2,
                itemCount: 1,
                byteCount: UInt64(page.byteCount)
            ))
        let valid = await accumulator.finish(makeExhaustionReceipt(lease: lease, pages: [page]))

        // Assert
        #expect(mismatch == .rejected(.pageCountMismatch(expected: 1, actual: 2)))
        guard case .finished = valid else {
            Issue.record("a rejected receipt must not consume accumulation state")
            return
        }
    }

    @Test("aggregate byte accounting rejects overflow without consuming the page sequence")
    func aggregateByteAccountingRejectsOverflowWithoutConsumingThePageSequence() async {
        // Arrange
        let lease = await makeLease()
        let accumulator = WorkspacePersistenceSnapshotPageAccumulator(lease: lease)
        let pages = (0..<3).map { _ in
            makePage(
                lease: lease,
                participantID: .unavailableRepositories,
                items: [
                    makePageItem(
                        .unavailableRepository(UUIDv7.generate()),
                        byteCount: Int.max
                    )
                ]
            )
        }

        // Act
        let firstResult = await accumulator.append(pages[0], sequence: .init(rawValue: 0))
        let secondResult = await accumulator.append(pages[1], sequence: .init(rawValue: 1))
        let overflowResult = await accumulator.append(pages[2], sequence: .init(rawValue: 2))
        let replacementPage = makePage(
            lease: lease,
            participantID: .unavailableRepositories,
            items: [
                makePageItem(
                    .unavailableRepository(UUIDv7.generate()),
                    byteCount: 1
                )
            ]
        )
        let replacementResult = await accumulator.append(
            replacementPage,
            sequence: .init(rawValue: 2)
        )

        // Assert
        #expect(firstResult == .accepted(pageID: pages[0].pageID))
        #expect(secondResult == .accepted(pageID: pages[1].pageID))
        #expect(overflowResult == .rejected(.byteCountOverflow))
        #expect(replacementResult == .accepted(pageID: replacementPage.pageID))
    }

    @Test("accumulator is callable from detached work")
    func accumulatorIsCallableFromDetachedWork() async {
        // Arrange
        let lease = await makeLease()
        let page = makePage(
            lease: lease,
            participantID: .unavailableRepositories,
            items: [makePageItem(.unavailableRepository(UUIDv7.generate()))]
        )

        // Act
        // Detached execution is the behavior under proof: this owner must not inherit MainActor.
        // swiftlint:disable:next no_task_detached
        let result = await Task.detached {
            let accumulator = WorkspacePersistenceSnapshotPageAccumulator(lease: lease)
            let appendResult = await accumulator.append(page, sequence: .init(rawValue: 0))
            let finishResult = await accumulator.finish(
                makeExhaustionReceipt(lease: lease, pages: [page])
            )
            return (appendResult, finishResult)
        }.value

        // Assert
        #expect(result.0 == .accepted(pageID: page.pageID))
        guard case .finished(let participants) = result.1 else {
            Issue.record("expected off-main accumulation to finish")
            return
        }
        #expect(participants.count == WorkspacePersistenceSnapshotParticipantID.allCases.count)
    }
}

private func makeLease(
    pagerIdentity: WorkspaceStateSnapshotPagerIdentity = .make()
) async -> WorkspaceStateSnapshotLease {
    await MainActor.run {
        WorkspaceStateSnapshotLease.open(
            pagerIdentity: pagerIdentity,
            revisionOwner: WorkspacePersistenceRevisionOwner()
        )
    }
}

private func makePageItem(
    _ item: WorkspacePersistenceSnapshotItem,
    byteCount: Int = 16
) -> WorkspaceStateSnapshotPageItem<
    WorkspacePersistenceSnapshotParticipantID,
    WorkspacePersistenceSnapshotItem
> {
    .init(item: item, byteCount: byteCount)
}

private func makePage(
    lease: WorkspaceStateSnapshotLease,
    participantID: WorkspacePersistenceSnapshotParticipantID,
    items: [WorkspaceStateSnapshotPageItem<
        WorkspacePersistenceSnapshotParticipantID,
        WorkspacePersistenceSnapshotItem
    >],
    exhaustsLease: Bool = false
) -> WorkspaceStateSnapshotPage<
    WorkspacePersistenceSnapshotParticipantID,
    WorkspacePersistenceSnapshotItem
> {
    let byteCount = items.reduce(into: 0) { total, item in total += item.byteCount }
    let participantIndex =
        WorkspacePersistenceSnapshotParticipantID.allCases.firstIndex(of: participantID) ?? 0
    return .init(
        pageID: .make(),
        lease: lease,
        participantID: participantID,
        items: items,
        itemCount: items.count,
        byteCount: byteCount,
        nextParticipantIndex: exhaustsLease
            ? WorkspacePersistenceSnapshotParticipantID.allCases.count : participantIndex,
        nextMembershipOffset: items.count,
        exhaustsLease: exhaustsLease
    )
}

private func makeExhaustionReceipt(
    lease: WorkspaceStateSnapshotLease,
    pages: [WorkspaceStateSnapshotPage<
        WorkspacePersistenceSnapshotParticipantID,
        WorkspacePersistenceSnapshotItem
    >]
) -> WorkspaceStateSnapshotExhaustionReceipt {
    WorkspaceStateSnapshotExhaustionReceipt(
        lease: lease,
        pageCount: UInt64(pages.count),
        itemCount: pages.reduce(into: 0) { total, page in total += UInt64(page.itemCount) },
        byteCount: pages.reduce(into: 0) { total, page in total += UInt64(page.byteCount) }
    )
}
