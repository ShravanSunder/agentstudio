import AgentStudioInfrastructure
import Foundation
import Testing

@testable import AgentStudioCore

@Suite("BridgeNavigationRules — selection, inventory and CWD association")
struct BridgeNavigationRulesTests {
    private let backend = UUIDv7.generate()
    private let frontend = UUIDv7.generate()
    private let notes = BridgeDocumentLocation(canonicalPath: "/private/tmp/feature-notes.md")!
    private let backendFile = BridgeDocumentLocation(canonicalPath: "/repos/backend/Sources/App.swift")!

    @Test("a known terminal worktree seeds membership and Review; no association seeds an empty record")
    func seedingFollowsKnownTerminalAssociation() {
        // Arrange / Act
        let seeded = BridgeNavigationRules.seededRecord(knownTerminalWorktreeId: backend)
        let empty = BridgeNavigationRules.seededRecord(knownTerminalWorktreeId: nil)

        // Assert
        #expect(seeded.effectiveMemberWorktreeIds == [backend])
        #expect(seeded.committedMemberLinks.isEmpty)
        #expect(seeded.reviewSelection == .member(worktreeId: backend))
        #expect(seeded.surface == .files)
        #expect(empty == .empty)
        #expect(empty.reviewSelection == .unselected)
    }

    @Test("R3: a committed old CWD stays while the new CWD is derived")
    func knownCWDChangeInjectsAndMovesProtection() {
        // Arrange
        var record = BridgeNavigationRules.seededRecord(knownTerminalWorktreeId: backend)
        record.committedMemberLinks = [
            BridgeMemberLink(
                worktreeId: backend,
                contributions: [
                    BridgeLinkContribution(
                        addedBy: .app, addedAt: Date(timeIntervalSince1970: 1)
                    )
                ]
            )
        ]
        record = admitted(notes, into: record)
        record = activatedFiles(notes, in: record)

        // Act
        let moved = BridgeNavigationRules.injectingKnownCWDWorktree(frontend, into: record)

        // Assert
        #expect(moved.effectiveMemberWorktreeIds == [backend, frontend])
        #expect(moved.selectedFilesDocument == notes)
        #expect(moved.reviewSelection == .member(worktreeId: backend))
        #expect(moved.surface == .files)
        #expect(
            BridgeNavigationRules.protectedWorktreeId(in: moved, currentKnownCWDWorktreeId: frontend)
                == frontend
        )
        #expect(
            BridgeNavigationRules.protectedWorktreeId(in: moved, currentKnownCWDWorktreeId: nil) == nil,
            "no known CWD means no protected member"
        )
    }

    @Test("R3: a derived CWD disappears on an unknown association without a committed row")
    func injectionIsIdempotentAndUnknownCWDKeepsMembers() {
        let record = BridgeNavigationRules.seededRecord(knownTerminalWorktreeId: backend)

        #expect(BridgeNavigationRules.injectingKnownCWDWorktree(backend, into: record) == record)
        #expect(BridgeNavigationRules.injectingKnownCWDWorktree(nil, into: record).effectiveMemberWorktreeIds.isEmpty)
    }

    @Test("a failed old CWD contribution leaves no member after the move and uses removal fallback")
    func failedDerivedContributionMovesReviewSelection() throws {
        let oldFile = try #require(BridgeDocumentLocation(canonicalPath: "/repos/backend/old.swift"))
        var record = BridgeNavigationRules.seededRecord(knownTerminalWorktreeId: backend)
        record.openedDocuments = [oldFile: nextEntry(in: record)]
        record.selectedFilesDocument = oldFile
        let moved = BridgeNavigationRules.injectingKnownCWDWorktree(frontend, into: record)

        let reconciled = BridgeNavigationRules.reconcilingDepartedDerivedCWD(
            previousDerivedWorktreeID: backend,
            in: moved,
            memberRootsByWorktreeId: [backend: "/repos/backend", frontend: "/repos/frontend"]
        )

        #expect(reconciled.committedMemberLinks.isEmpty)
        #expect(reconciled.effectiveMemberWorktreeIds == [frontend])
        #expect(reconciled.reviewSelection == .member(worktreeId: frontend))
        #expect(reconciled.openedDocuments.isEmpty)
        #expect(reconciled.selectedFilesDocument == nil)
    }

    @Test("a committed old CWD remains after the derived association moves")
    func committedOldCWDRemainsAfterMove() {
        var record = BridgeNavigationRules.seededRecord(knownTerminalWorktreeId: backend)
        record.committedMemberLinks = [
            BridgeMemberLink(
                worktreeId: backend,
                contributions: [
                    BridgeLinkContribution(
                        addedBy: .app, addedAt: Date(timeIntervalSince1970: 1)
                    )
                ]
            )
        ]
        let moved = BridgeNavigationRules.injectingKnownCWDWorktree(frontend, into: record)

        let reconciled = BridgeNavigationRules.reconcilingDepartedDerivedCWD(
            previousDerivedWorktreeID: backend, in: moved,
            memberRootsByWorktreeId: [backend: "/repos/backend", frontend: "/repos/frontend"]
        )
        #expect(reconciled.effectiveMemberWorktreeIds == [backend, frontend])
        #expect(reconciled.reviewSelection == .member(worktreeId: backend))
    }

    @Test("R15: re-admitting the same canonical location reuses one entry and keeps the displayed selection")
    func admissionDeduplicatesByCanonicalLocation() {
        // Arrange
        var record = admitted(backendFile, into: .empty)
        record = activatedFiles(backendFile, in: record)
        let sameLocation = nextEntry(in: record)

        // Act
        let notesTransition = BridgeNavigationRules.admitting(
            nextEntry(in: record), at: notes,
            into: record
        )
        let repeatTransition = BridgeNavigationRules.admitting(
            sameLocation, at: backendFile, into: notesTransition.record)

        // Assert
        #expect(notesTransition.disposition == .appended)
        #expect(orderedOpenedLocations(notesTransition.record) == [backendFile, notes])
        #expect(notesTransition.record.selectedFilesDocument == backendFile)
        if case .reused = repeatTransition.disposition {
        } else {
            Issue.record("expected reuse of the existing entry")
        }
        #expect(repeatTransition.record == notesTransition.record)
    }

    @Test("R15: documents with equal basenames in different locations stay distinct entries")
    func equalBasenamesRemainDistinct() {
        let first = BridgeDocumentLocation(canonicalPath: "/repos/backend/README.md")!
        let second = BridgeDocumentLocation(canonicalPath: "/repos/frontend/README.md")!

        let record = admitted(second, into: admitted(first, into: .empty))

        #expect(orderedOpenedLocations(record) == [first, second])
        #expect(first.displayName == second.displayName)
    }

    @Test("R4: Files activation never rewrites the Review selection or comparison memory")
    func filesActivationIsIndependentOfReview() throws {
        // Arrange
        var record = BridgeNavigationRules.seededRecord(knownTerminalWorktreeId: backend)
        record = try #require(appliedRecord(BridgeNavigationRules.addingMemberRecord(frontend, to: record)))
        record = try #require(
            appliedRecord(
                BridgeNavigationRules.activatingReview(
                    of: frontend,
                    comparison: .branch(name: "main"),
                    in: record
                )
            )
        )
        record = admitted(notes, into: record)

        // Act
        let activated = activatedFiles(notes, in: record)

        // Assert
        #expect(activated.surface == .files)
        #expect(activated.selectedFilesDocument == notes)
        #expect(activated.reviewSelection == .member(worktreeId: frontend))
        #expect(activated.reviewComparisonsByWorktreeId == [frontend: .branch(name: "main")])
    }

    @Test("R4: switching Review between members retains each member's comparison and the Files selection")
    func reviewSwitchingRetainsPerMemberComparisons() throws {
        // Arrange
        var record = BridgeNavigationRules.seededRecord(knownTerminalWorktreeId: backend)
        record = try #require(appliedRecord(BridgeNavigationRules.addingMemberRecord(frontend, to: record)))
        record = activatedFiles(notes, in: admitted(notes, into: record))

        // Act: frontend → backend → frontend
        record = try #require(
            appliedRecord(
                BridgeNavigationRules.activatingReview(of: frontend, comparison: .branch(name: "develop"), in: record)
            )
        )
        record = try #require(
            appliedRecord(
                BridgeNavigationRules.activatingReview(of: backend, comparison: .commit(oid: oid), in: record)
            )
        )
        record = try #require(
            appliedRecord(BridgeNavigationRules.activatingReview(of: frontend, comparison: nil, in: record))
        )

        // Assert
        #expect(record.reviewSelection == .member(worktreeId: frontend))
        #expect(record.selectedReviewComparison == .branch(name: "develop"))
        #expect(record.reviewComparisonsByWorktreeId[backend] == .commit(oid: oid))
        #expect(record.selectedFilesDocument == notes)
        #expect(record.surface == .review)

        let backToFiles = BridgeNavigationRules.showingFiles(in: record)
        #expect(backToFiles.surface == .files)
        #expect(backToFiles.selectedFilesDocument == notes)
        #expect(backToFiles.reviewSelection == .member(worktreeId: frontend))
    }

    @Test("R4: Review of a non-member is refused without mutation")
    func reviewOfNonMemberIsRefused() {
        let record = BridgeNavigationRules.seededRecord(knownTerminalWorktreeId: backend)

        #expect(BridgeNavigationRules.activatingReview(of: frontend, comparison: nil, in: record) == .notMember)
        #expect(BridgeNavigationRules.selectingReviewWorktree(frontend, in: record) == .notMember)
        #expect(
            BridgeNavigationRules.recordingReviewComparison(.branch(name: "main"), for: frontend, in: record)
                == .notMember
        )
    }

    @Test("selecting a Review member leaves the displayed surface and Files selection unchanged")
    func selectingReviewWorktreeDoesNotDisplay() throws {
        var record = BridgeNavigationRules.seededRecord(knownTerminalWorktreeId: backend)
        record = try #require(appliedRecord(BridgeNavigationRules.addingMemberRecord(frontend, to: record)))
        record = activatedFiles(notes, in: admitted(notes, into: record))

        let selected = try #require(appliedRecord(BridgeNavigationRules.selectingReviewWorktree(frontend, in: record)))

        #expect(selected.reviewSelection == .member(worktreeId: frontend))
        #expect(selected.surface == .files)
        #expect(selected.selectedFilesDocument == notes)
    }

    @Test("Files activation requires an inventory entry; closing clears only its own selection")
    func activationAndCloseFollowInventory() {
        let record = admitted(notes, into: .empty)
        #expect(BridgeNavigationRules.activatingFilesDocument(backendFile, in: record) == .notInInventory)

        let activated = activatedFiles(notes, in: admitted(backendFile, into: record))
        guard
            case .closed(let closedOther, let clearedOther) = BridgeNavigationRules.closingDocument(
                backendFile,
                in: activated
            ),
            case .closed(let closedSelected, let clearedSelected) = BridgeNavigationRules.closingDocument(
                notes,
                in: activated
            )
        else {
            Issue.record("expected both closes to apply")
            return
        }

        #expect(!clearedOther)
        #expect(closedOther.selectedFilesDocument == notes)
        #expect(clearedSelected)
        #expect(closedSelected.selectedFilesDocument == nil)
        #expect(orderedOpenedLocations(closedSelected) == [backendFile])
        #expect(BridgeNavigationRules.closingDocument(notes, in: closedSelected) == .notOpen)
    }

    @Test(
        "grouping uses canonical containment: deepest member wins, outside is loose, equal roots are ambiguous",
        arguments: [
            ("/repos/app/src/main.swift", GroupingExpectation.member("app")),
            ("/repos/app/packages/ui/button.tsx", GroupingExpectation.member("nested")),
            ("/repos/application/readme.md", GroupingExpectation.loose),
            ("/private/tmp/notes.md", GroupingExpectation.loose),
            ("/repos/twin/file.txt", GroupingExpectation.ambiguous),
        ]
    )
    func groupingFollowsCanonicalContainment(path: String, expectation: GroupingExpectation) throws {
        // Arrange
        let app = UUIDv7.generate()
        let nested = UUIDv7.generate()
        let twinA = UUIDv7.generate()
        let twinB = UUIDv7.generate()
        let roots = [
            app: "/repos/app",
            nested: "/repos/app/packages/ui",
            twinA: "/repos/twin",
            twinB: "/repos/twin",
        ]
        let location = try #require(BridgeDocumentLocation(canonicalPath: path))

        // Act
        let grouping = BridgeNavigationRules.grouping(
            of: location,
            effectiveMemberWorktreeIds: [app, nested, twinA, twinB],
            memberRootsByWorktreeId: roots
        )

        // Assert
        switch expectation {
        case .member("app"):
            #expect(grouping == .member(worktreeId: app))
        case .member:
            #expect(grouping == .member(worktreeId: nested))
        case .loose:
            #expect(grouping == .loose)
        case .ambiguous:
            #expect(grouping == .ambiguous(worktreeIds: [twinA, twinB]))
        }
    }

    @Test("document locations reject relative, empty and trailing-slash paths")
    func documentLocationValidation() {
        #expect(BridgeDocumentLocation(canonicalPath: "relative/file.md") == nil)
        #expect(BridgeDocumentLocation(canonicalPath: "") == nil)
        #expect(BridgeDocumentLocation(canonicalPath: "/") == nil)
        #expect(BridgeDocumentLocation(canonicalPath: "/tmp/dir/") == nil)
        #expect(
            BridgeDocumentLocation(canonicalPath: "/repos/app/src/a.swift")?.relativePath(
                inCanonicalRoot: "/repos/app"
            ) == "src/a.swift"
        )
    }

    // MARK: - Helpers

    enum GroupingExpectation: Sendable, CustomTestStringConvertible {
        case member(String)
        case loose
        case ambiguous

        var testDescription: String {
            switch self {
            case .member(let name): "member \(name)"
            case .loose: "loose"
            case .ambiguous: "ambiguous"
            }
        }
    }

    private let oid = String(repeating: "a", count: 40)

    private func admitted(
        _ location: BridgeDocumentLocation,
        into record: BridgeNavigationRecord
    ) -> BridgeNavigationRecord {
        BridgeNavigationRules.admitting(
            nextEntry(in: record), at: location,
            into: record
        ).record
    }

    private func nextEntry(in record: BridgeNavigationRecord) -> BridgeOpenedDocumentEntry {
        let floor =
            record.openedDocuments.values.compactMap {
                openedDocumentSortKeyMillis($0.sortKey)
            }.max() ?? 1_700_000_000_000
        let minted = mintOpenedDocumentSortKey(
            wallMillis: 1_700_000_000_000, floorMillis: floor)
        return BridgeOpenedDocumentEntry(provenance: nil, sortKey: minted.key)
    }

    private func orderedOpenedLocations(_ record: BridgeNavigationRecord) -> [BridgeDocumentLocation] {
        record.openedDocuments.sorted { lhs, rhs in
            lhs.value.sortKey.uuidString < rhs.value.sortKey.uuidString
        }.map(\.key)
    }

    private func activatedFiles(
        _ location: BridgeDocumentLocation,
        in record: BridgeNavigationRecord
    ) -> BridgeNavigationRecord {
        guard case .activated(let activated) = BridgeNavigationRules.activatingFilesDocument(location, in: record)
        else {
            Issue.record("expected Files activation of \(location.canonicalPath)")
            return record
        }
        return activated
    }

    private func appliedRecord(_ outcome: BridgeMemberScopedOutcome) -> BridgeNavigationRecord? {
        guard case .applied(let record) = outcome else { return nil }
        return record
    }
}

extension BridgeNavigationRules {
    fileprivate static func addingMemberRecord(
        _ worktreeId: UUID,
        to record: BridgeNavigationRecord
    ) -> BridgeMemberScopedOutcome {
        let (updated, result) = addingMemberContribution(
            worktreeId, contributor: .person,
            addedAt: Date(timeIntervalSince1970: 1), to: record
        )
        return switch result {
        case .added: .applied(updated)
        case .alreadyPresent: .notMember
        case .refusedUnknownWorktree, .staleOwner, .staleReceiver, .unsupportedReceiver: .notMember
        }
    }
}
