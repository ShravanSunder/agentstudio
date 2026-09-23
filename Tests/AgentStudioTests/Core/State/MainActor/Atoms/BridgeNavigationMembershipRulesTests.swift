import AgentStudioInfrastructure
import Foundation
import Testing

@testable import AgentStudioCore

@Suite("BridgeNavigationRules — R16 membership, removal and unregistration")
struct BridgeNavigationMembershipRulesTests {
    private let backend = UUIDv7.generate()
    private let frontend = UUIDv7.generate()
    private let docs = UUIDv7.generate()
    private var roots: [UUID: String] {
        [backend: "/repos/backend", frontend: "/repos/frontend", docs: "/repos/docs"]
    }
    private let backendFile = BridgeDocumentLocation(canonicalPath: "/repos/backend/Sources/App.swift")!
    private let frontendFile = BridgeDocumentLocation(canonicalPath: "/repos/frontend/src/app.tsx")!
    private let notes = BridgeDocumentLocation(canonicalPath: "/private/tmp/feature-notes.md")!

    @Test("adding a known member appends once; duplicate addition has no effect and no selection changes")
    func addingIsIdempotentAndSelectionFree() throws {
        let seeded = BridgeNavigationRules.seededRecord(knownTerminalWorktreeId: backend)

        guard case .added(let added) = BridgeNavigationRules.addingMember(frontend, to: seeded) else {
            Issue.record("expected addition")
            return
        }

        #expect(added.memberWorktreeIds == [backend, frontend])
        #expect(added.reviewSelection == seeded.reviewSelection)
        #expect(added.surface == seeded.surface)
        #expect(BridgeNavigationRules.addingMember(frontend, to: added) == .alreadyMember)
    }

    @Test("removing the protected current-CWD member is refused with no mutation")
    func protectedRemovalIsRefused() {
        let record = collection()

        let outcome = BridgeNavigationRules.removingMember(
            backend,
            from: record,
            reason: .explicitCommand(protectedWorktreeId: backend),
            memberRootsByWorktreeId: roots
        )

        #expect(outcome == .refusedProtected)
    }

    @Test("removing a non-member reports notMember")
    func removingNonMember() {
        let outcome = BridgeNavigationRules.removingMember(
            UUIDv7.generate(),
            from: collection(),
            reason: .explicitCommand(protectedWorktreeId: nil),
            memberRootsByWorktreeId: roots
        )
        #expect(outcome == .notMember)
    }

    @Test("removal clears its displayed file and entries without reclassifying them as loose files")
    func removalClearsOwnedEntriesWithoutReclassification() throws {
        // Arrange: Files shows a frontend file; notes stay loose
        var record = collection()
        record.selectedFilesDocument = frontendFile
        record.filesFilter = .member(worktreeId: frontend)

        // Act
        let (removed, effect) = try removal(frontend, from: record, protected: backend)

        // Assert
        #expect(removed.memberWorktreeIds == [backend, docs])
        #expect(effect.removedDocuments == [frontendFile])
        #expect(!removed.openedDocuments.map(\.location).contains(frontendFile), "must not reappear as loose")
        #expect(removed.openedDocuments.map(\.location) == [backendFile, notes])
        #expect(effect.clearedFilesSelection)
        #expect(removed.selectedFilesDocument == nil)
        #expect(effect.resetFilesFilter)
        #expect(removed.filesFilter == .allMembers)
        #expect(effect.reviewFallback == .unchanged)
        #expect(removed.reviewSelection == .member(worktreeId: backend))
        #expect(removed.reviewComparisonsByWorktreeId[frontend] == nil)
    }

    @Test("removal leaves an unrelated displayed loose document selected")
    func removalKeepsUnrelatedSelection() throws {
        var record = collection()
        record.selectedFilesDocument = notes

        let (removed, effect) = try removal(frontend, from: record, protected: backend)

        #expect(!effect.clearedFilesSelection)
        #expect(removed.selectedFilesDocument == notes)
    }

    @Test(
        "removing the selected Review member falls back to the next member in order, wrapping",
        arguments: [
            (removedIndex: 0, expectedFallbackIndex: 1),
            (removedIndex: 1, expectedFallbackIndex: 2),
            (removedIndex: 2, expectedFallbackIndex: 0),
        ]
    )
    func reviewFallbackIsOrderedAndWraps(removedIndex: Int, expectedFallbackIndex: Int) throws {
        // Arrange
        let members = [backend, frontend, docs]
        var record = collection()
        record.reviewSelection = .member(worktreeId: members[removedIndex])
        record.surface = .review

        // Act
        let (removed, effect) = try removal(members[removedIndex], from: record, protected: nil)

        // Assert
        let fallback = members[expectedFallbackIndex]
        #expect(effect.reviewFallback == .switched(toWorktreeId: fallback))
        #expect(removed.reviewSelection == .member(worktreeId: fallback))
        #expect(removed.selectedReviewComparison == record.reviewComparisonsByWorktreeId[fallback])
        #expect(removed.surface == .review, "an empty or switched Review never forces Files")
    }

    @Test("a fallback member without a saved comparison uses first-time designation, not the removed baseline")
    func fallbackWithoutComparisonDoesNotCopyRemovedBaseline() throws {
        var record = collection()
        record.reviewSelection = .member(worktreeId: frontend)
        record.reviewComparisonsByWorktreeId = [frontend: .branch(name: "main")]

        let (removed, _) = try removal(frontend, from: record, protected: nil)

        #expect(removed.reviewSelection == .member(worktreeId: docs))
        #expect(removed.selectedReviewComparison == nil)
    }

    @Test("removing the last member empties Review and keeps unrelated loose documents")
    func lastMemberRemoval() throws {
        // Arrange
        var record = BridgeNavigationRules.seededRecord(knownTerminalWorktreeId: backend)
        record.openedDocuments = [
            BridgeOpenedDocument(location: backendFile, provenance: nil),
            BridgeOpenedDocument(location: notes, provenance: nil),
        ]
        record.surface = .review

        // Act
        let (removed, effect) = try removal(backend, from: record, protected: nil)

        // Assert
        #expect(removed.memberWorktreeIds.isEmpty)
        #expect(effect.reviewFallback == .emptied)
        #expect(removed.reviewSelection == .unselected)
        #expect(removed.openedDocuments.map(\.location) == [notes])
        #expect(removed.surface == .review)
    }

    @Test("catalog unregistration applies the same removal even to the formerly protected member")
    func catalogUnregistrationBypassesProtection() {
        var record = collection()
        record.selectedFilesDocument = backendFile
        record.reviewSelection = .member(worktreeId: backend)

        let outcome = BridgeNavigationRules.removingMember(
            backend,
            from: record,
            reason: .catalogUnregistration,
            memberRootsByWorktreeId: roots
        )

        guard case .removed(let removed, let effect) = outcome else {
            Issue.record("expected removal")
            return
        }
        #expect(effect.removedDocuments == [backendFile])
        #expect(effect.clearedFilesSelection)
        #expect(effect.reviewFallback == .switched(toWorktreeId: frontend))
        #expect(removed.memberWorktreeIds == [frontend, docs])
    }

    @Test("an unresolvable member root falls back to admitted provenance, never a path guess")
    func unresolvableRootUsesProvenance() throws {
        // Arrange: the frontend root is no longer resolvable
        var record = collection()
        record.openedDocuments = [
            BridgeOpenedDocument(
                location: frontendFile,
                provenance: BridgeKnownWorktreeProvenance(
                    repoId: UUIDv7.generate(),
                    worktreeId: frontend,
                    relativePath: "src/app.tsx"
                )
            ),
            BridgeOpenedDocument(
                location: BridgeDocumentLocation(canonicalPath: "/repos/frontend/untracked.md")!,
                provenance: nil
            ),
        ]
        var rootsWithoutFrontend = roots
        rootsWithoutFrontend.removeValue(forKey: frontend)

        // Act
        let outcome = BridgeNavigationRules.removingMember(
            frontend,
            from: record,
            reason: .catalogUnregistration,
            memberRootsByWorktreeId: rootsWithoutFrontend
        )

        // Assert
        guard case .removed(let removed, let effect) = outcome else {
            Issue.record("expected removal")
            return
        }
        #expect(effect.removedDocuments == [frontendFile])
        #expect(removed.openedDocuments.map(\.location.canonicalPath) == ["/repos/frontend/untracked.md"])
    }

    @Test("a nested member keeps its own documents when the outer member is removed")
    func nestedMemberDocumentsSurviveOuterRemoval() throws {
        // Arrange
        let outer = UUIDv7.generate()
        let nested = UUIDv7.generate()
        let nestedFile = BridgeDocumentLocation(canonicalPath: "/repos/app/packages/ui/button.tsx")!
        let outerFile = BridgeDocumentLocation(canonicalPath: "/repos/app/main.swift")!
        let record = BridgeNavigationRecord(
            openedDocuments: [
                BridgeOpenedDocument(location: outerFile, provenance: nil),
                BridgeOpenedDocument(location: nestedFile, provenance: nil),
            ],
            memberWorktreeIds: [outer, nested]
        )

        // Act
        let outcome = BridgeNavigationRules.removingMember(
            outer,
            from: record,
            reason: .explicitCommand(protectedWorktreeId: nil),
            memberRootsByWorktreeId: [outer: "/repos/app", nested: "/repos/app/packages/ui"]
        )

        // Assert
        guard case .removed(let removed, let effect) = outcome else {
            Issue.record("expected removal")
            return
        }
        #expect(effect.removedDocuments == [outerFile])
        #expect(removed.openedDocuments.map(\.location) == [nestedFile])
    }

    // MARK: - Helpers

    private func collection() -> BridgeNavigationRecord {
        BridgeNavigationRecord(
            openedDocuments: [
                BridgeOpenedDocument(location: backendFile, provenance: nil),
                BridgeOpenedDocument(location: frontendFile, provenance: nil),
                BridgeOpenedDocument(location: notes, provenance: nil),
            ],
            memberWorktreeIds: [backend, frontend, docs],
            reviewSelection: .member(worktreeId: backend),
            reviewComparisonsByWorktreeId: [
                backend: .branch(name: "main"),
                frontend: .branch(name: "develop"),
                docs: .ref(name: "origin/main"),
            ]
        )
    }

    private func removal(
        _ worktreeId: UUID,
        from record: BridgeNavigationRecord,
        protected protectedWorktreeId: UUID?
    ) throws -> (BridgeNavigationRecord, BridgeMemberRemovalEffect) {
        let outcome = BridgeNavigationRules.removingMember(
            worktreeId,
            from: record,
            reason: .explicitCommand(protectedWorktreeId: protectedWorktreeId),
            memberRootsByWorktreeId: roots
        )
        guard case .removed(let removed, let effect) = outcome else {
            throw RemovalFailure(outcome: outcome)
        }
        return (removed, effect)
    }

    private struct RemovalFailure: Error {
        let outcome: BridgeMemberRemovalOutcome
    }
}
