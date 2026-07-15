import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite(.serialized)
struct WorkspacePersistenceChangeJournalTests {
    @Test("contiguous append replays the exact requested revision range")
    func contiguousAppendReplaysExactRange() throws {
        let revisions = try makeRevisions(count: 3)
        let changeSets = revisions.enumerated().map { index, revision in
            makeChangeSet(
                revision: revision,
                change: .insert(
                    .repository(makeRepository(index: index)),
                    estimatedByteCount: 8
                )
            )
        }
        let journal = makeJournal(maximumChangeSetCount: 8, maximumEstimatedBytes: 128)

        for changeSet in changeSets {
            guard case .appended = journal.append(changeSet) else {
                Issue.record("expected contiguous append")
                return
            }
        }

        #expect(journal.oldestRevision == revisions[0])
        #expect(journal.newestRevision == revisions[2])
        #expect(journal.replay(from: revisions[0], through: revisions[2]) == .replayed(changeSets))
    }

    @Test("append rejects a revision gap without changing retained entries")
    func appendRejectsRevisionGap() throws {
        let revisions = try makeRevisions(count: 3)
        let first = makeChangeSet(
            revision: revisions[0],
            change: .insert(.repository(makeRepository(index: 0)), estimatedByteCount: 8)
        )
        let skipped = makeChangeSet(
            revision: revisions[2],
            change: .insert(.repository(makeRepository(index: 2)), estimatedByteCount: 8)
        )
        let journal = makeJournal(maximumChangeSetCount: 8, maximumEstimatedBytes: 128)
        _ = journal.append(first)

        let result = journal.append(skipped)

        #expect(
            result
                == .rejected(
                    .gap(
                        newestRevision: revisions[0],
                        submittedRevision: revisions[2]
                    )
                )
        )
        #expect(journal.retainedChangeSetCount == 1)
        #expect(journal.newestRevision == revisions[0])
    }

    @Test("tombstones survive exact replay")
    func tombstonesSurviveExactReplay() throws {
        let revision = try makeRevisions(count: 1)[0]
        let repositoryID = UUIDv7.generate()
        let tombstone = WorkspacePersistenceChange.tombstone(.repository(repositoryID))
        let changeSet = makeChangeSet(revision: revision, change: tombstone)
        let journal = makeJournal(maximumChangeSetCount: 4, maximumEstimatedBytes: 128)
        _ = journal.append(changeSet)

        #expect(journal.replay(from: revision, through: revision) == .replayed([changeSet]))
        #expect(changeSet.changes == [tombstone])
    }

    @Test("change set rejects duplicate item identities across mutation kinds")
    func changeSetRejectsDuplicateItemIdentities() throws {
        let revision = try makeRevisions(count: 1)[0]
        let repository = makeRepository(index: 0)

        let result = WorkspacePersistenceChangeSet.validated(
            revision: revision,
            changes: [
                .insert(.repository(repository), estimatedByteCount: 8),
                .tombstone(.repository(repository.id)),
            ]
        )

        #expect(result == .rejected(.duplicateItemID(.repository(repository.id))))
    }

    @Test("change set rejects empty input and nonpositive value byte estimates")
    func changeSetRejectsInvalidShape() throws {
        let revision = try makeRevisions(count: 1)[0]
        let repository = makeRepository(index: 0)

        #expect(
            WorkspacePersistenceChangeSet.validated(revision: revision, changes: [])
                == .rejected(.empty)
        )
        #expect(
            WorkspacePersistenceChangeSet.validated(
                revision: revision,
                changes: [.replace(.repository(repository), estimatedByteCount: 0)]
            ) == .rejected(.nonPositiveEstimatedByteCount(.repository(repository.id)))
        )
    }

    @Test("count and byte bounds evict oldest revisions deterministically")
    func countAndByteBoundsEvictOldestRevisions() throws {
        let revisions = try makeRevisions(count: 3)
        let countJournal = makeJournal(maximumChangeSetCount: 2, maximumEstimatedBytes: 128)
        let countChangeSets = revisions.map { revision in
            makeChangeSet(
                revision: revision,
                change: .insert(.repository(makeRepository(index: Int(revision.rawValue))), estimatedByteCount: 8)
            )
        }
        _ = countJournal.append(countChangeSets[0])
        _ = countJournal.append(countChangeSets[1])

        let countReceipt = countJournal.append(countChangeSets[2])

        #expect(
            countReceipt
                == .appended(
                    .init(
                        appendedRevision: revisions[2],
                        evictedRevisions: [revisions[0]],
                        oldestRevision: revisions[1],
                        newestRevision: revisions[2],
                        retainedChangeSetCount: 2,
                        retainedEstimatedByteCount: 16
                    )
                )
        )

        let byteJournal = makeJournal(maximumChangeSetCount: 8, maximumEstimatedBytes: 10)
        _ = byteJournal.append(countChangeSets[0])
        let byteReceipt = byteJournal.append(countChangeSets[1])

        #expect(
            byteReceipt
                == .appended(
                    .init(
                        appendedRevision: revisions[1],
                        evictedRevisions: [revisions[0]],
                        oldestRevision: revisions[1],
                        newestRevision: revisions[1],
                        retainedChangeSetCount: 1,
                        retainedEstimatedByteCount: 8
                    )
                )
        )
    }

    @Test("replay classifies stale evicted and future ranges")
    func replayClassifiesUnavailableRanges() throws {
        let revisions = try makeRevisions(count: 4)
        let journal = makeJournal(maximumChangeSetCount: 2, maximumEstimatedBytes: 128)
        for revision in revisions.prefix(3) {
            _ = journal.append(
                makeChangeSet(
                    revision: revision,
                    change: .insert(
                        .repository(makeRepository(index: Int(revision.rawValue))),
                        estimatedByteCount: 8
                    )
                )
            )
        }

        #expect(
            journal.replay(from: revisions[0], through: revisions[0])
                == .rejected(
                    .stale(
                        requestedThroughRevision: revisions[0],
                        oldestRetainedRevision: revisions[1]
                    )
                )
        )
        #expect(
            journal.replay(from: revisions[0], through: revisions[1])
                == .rejected(
                    .evicted(
                        requestedFromRevision: revisions[0],
                        oldestRetainedRevision: revisions[1]
                    )
                )
        )
        #expect(
            journal.replay(from: revisions[2], through: revisions[3])
                == .rejected(
                    .future(
                        requestedThroughRevision: revisions[3],
                        newestRetainedRevision: revisions[2]
                    )
                )
        )
    }

    @Test("append and replay preserve committed revision values exactly")
    func appendAndReplayPreserveExactRevisions() throws {
        let revisions = try makeRevisions(count: 2)
        let journal = makeJournal(maximumChangeSetCount: 4, maximumEstimatedBytes: 128)
        let first = makeChangeSet(
            revision: revisions[0],
            change: .insert(.repository(makeRepository(index: 0)), estimatedByteCount: 8)
        )
        let second = makeChangeSet(
            revision: revisions[1],
            change: .replace(.repository(makeRepository(index: 1)), estimatedByteCount: 8)
        )

        _ = journal.append(first)
        _ = journal.append(second)

        guard case .replayed(let replayed) = journal.replay(from: revisions[0], through: revisions[1]) else {
            Issue.record("expected exact replay")
            return
        }
        #expect(replayed.map(\.revision) == revisions)
        #expect(replayed[0].revision.rawValue == revisions[0].rawValue)
        #expect(replayed[1].revision.rawValue == revisions[1].rawValue)
    }

    @Test("append rejects retained byte count overflow without mutating journal state")
    func appendRejectsRetainedByteCountOverflowWithoutMutation() throws {
        let revisions = try makeRevisions(count: 2)
        let journal = makeJournal(
            maximumChangeSetCount: 2,
            maximumEstimatedBytes: .max
        )
        let first = makeChangeSet(
            revision: revisions[0],
            change: .insert(
                .repository(makeRepository(index: 0)),
                estimatedByteCount: Int.max - 1
            )
        )
        let overflowing = makeChangeSet(
            revision: revisions[1],
            change: .insert(.repository(makeRepository(index: 1)), estimatedByteCount: 2)
        )
        _ = journal.append(first)

        let result = journal.append(overflowing)

        #expect(
            result
                == .rejected(
                    .retainedEstimatedByteCountOverflow(
                        retainedEstimatedByteCount: Int.max - 1,
                        appendingEstimatedByteCount: 2
                    )
                )
        )
        #expect(journal.oldestRevision == revisions[0])
        #expect(journal.newestRevision == revisions[0])
        #expect(journal.retainedChangeSetCount == 1)
        #expect(journal.retainedEstimatedByteCount == Int.max - 1)
        #expect(journal.replay(from: revisions[0], through: revisions[0]) == .replayed([first]))
    }

    @Test("repeated eviction preserves the exact retained replay window")
    func repeatedEvictionPreservesExactReplayWindow() throws {
        let revisions = try makeRevisions(count: 130)
        let journal = makeJournal(maximumChangeSetCount: 3, maximumEstimatedBytes: 3)
        let changeSets = revisions.enumerated().map { index, revision in
            makeChangeSet(
                revision: revision,
                change: .insert(
                    .repository(makeRepository(index: index)),
                    estimatedByteCount: 1
                )
            )
        }

        for changeSet in changeSets {
            guard case .appended = journal.append(changeSet) else {
                Issue.record("expected repeated contiguous append")
                return
            }
        }

        let retainedChangeSets = Array(changeSets.suffix(3))
        #expect(journal.retainedChangeSetCount == 3)
        #expect(journal.retainedEstimatedByteCount == 3)
        #expect(journal.oldestRevision == revisions[127])
        #expect(journal.newestRevision == revisions[129])
        #expect(
            journal.replay(from: revisions[127], through: revisions[129])
                == .replayed(retainedChangeSets)
        )
        #expect(
            journal.replay(from: revisions[126], through: revisions[127])
                == .rejected(
                    .evicted(
                        requestedFromRevision: revisions[126],
                        oldestRetainedRevision: revisions[127]
                    )
                )
        )
    }

    private func makeJournal(
        maximumChangeSetCount: Int,
        maximumEstimatedBytes: Int
    ) -> WorkspacePersistenceChangeJournal {
        guard
            case .valid(let limits) = WorkspacePersistenceChangeJournalLimits.validated(
                maximumChangeSetCount: maximumChangeSetCount,
                maximumEstimatedBytes: maximumEstimatedBytes
            )
        else {
            preconditionFailure("test requires valid journal limits")
        }
        return WorkspacePersistenceChangeJournal(limits: limits)
    }

    private func makeChangeSet(
        revision: WorkspacePersistenceRevision,
        change: WorkspacePersistenceChange
    ) -> WorkspacePersistenceChangeSet {
        guard
            case .valid(let changeSet) = WorkspacePersistenceChangeSet.validated(
                revision: revision,
                changes: [change]
            )
        else {
            preconditionFailure("test requires a valid change set")
        }
        return changeSet
    }

    private func makeRevisions(count: Int) throws -> [WorkspacePersistenceRevision] {
        let revisionOwner = WorkspacePersistenceRevisionOwner()
        return try (0..<count).map { _ in
            try revisionOwner.performSynchronousTransaction { preparation in
                preparation.commit { preparation.transaction.proposedRevision }
            }
        }
    }

    private func makeRepository(index: Int) -> CanonicalRepo {
        CanonicalRepo(
            id: UUIDv7.generate(),
            name: "repository-\(index)",
            repoPath: URL(filePath: "/tmp/repository-\(index)")
        )
    }
}
