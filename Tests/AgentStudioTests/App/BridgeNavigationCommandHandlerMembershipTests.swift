import AgentStudioInfrastructure
import Foundation
import Testing

@testable import AgentStudio
@testable import AgentStudioBridge
@testable import AgentStudioCore
@testable import AgentStudioTestSupport

@MainActor
@Suite("Bridge navigation membership commands", .serialized)
struct BridgeNavigationCommandHandlerMembershipTests {
    init() {
        installTestCoreAtomsIfNeeded()
    }

    // MARK: - Add

    @Test("adding a known worktree lists it once and changes neither selection")
    func addingKnownWorktreeIsIdempotent() async throws {
        // Arrange
        let fixture = try makeFixture()
        fixture.install(RecordingReceiverPresentation())
        let otherRepo = fixture.store.addRepo(
            at: fixture.root.appending(path: "added", directoryHint: .isDirectory)
        )
        let added = try #require(fixture.store.repo(otherRepo.id)?.worktrees.first)
        let before = try #require(fixture.handler.record(for: fixture.receiver))

        // Act
        let first = await fixture.handler.addWorktree(added.id, to: fixture.receiver)
        let duplicate = await fixture.handler.addWorktree(added.id, to: fixture.receiver)

        // Assert
        #expect(first == .applied)
        #expect(duplicate == .applied)
        let record = try #require(fixture.handler.record(for: fixture.receiver))
        #expect(record.memberWorktreeIds == before.memberWorktreeIds + [added.id])
        #expect(record.reviewSelection == before.reviewSelection)
        #expect(record.selectedFilesDocument == before.selectedFilesDocument)
        #expect(fixture.persistCount == 1, "a duplicate addition has no effect to save")
        #expect(fixture.refreshedFilesReceivers == [fixture.receiver])
    }

    @Test("an unknown worktree is refused without registering anything")
    func unknownWorktreeIsRefused() async throws {
        // Arrange
        let fixture = try makeFixture()
        fixture.install(RecordingReceiverPresentation())
        let before = fixture.handler.record(for: fixture.receiver)
        let reposBefore = fixture.store.repositoryTopologyAtom.repos.map(\.id)

        // Act
        let outcome = await fixture.handler.addWorktree(UUIDv7.generate(), to: fixture.receiver)

        // Assert
        #expect(outcome == .failed(.worktreeUnavailable))
        #expect(fixture.handler.record(for: fixture.receiver) == before)
        #expect(fixture.store.repositoryTopologyAtom.repos.map(\.id) == reposBefore)
    }

    // MARK: - Select

    @Test("selecting a member for Review keeps the surface and the Files selection")
    func selectingReviewMemberKeepsFiles() async throws {
        // Arrange
        let fixture = try makeFixture()
        let other = try fixture.addMember()
        let presentation = RecordingReceiverPresentation()
        fixture.install(presentation)
        let document = try #require(fixture.loosePlan)
        fixture.selectInFiles(document)

        // Act
        let outcome = await fixture.handler.selectReviewWorktree(other.id, in: fixture.receiver)

        // Assert
        #expect(outcome == .applied)
        let record = try #require(fixture.handler.record(for: fixture.receiver))
        #expect(record.reviewSelection == .member(worktreeId: other.id))
        #expect(record.surface == .files)
        #expect(record.selectedFilesDocument == document)
        #expect(presentation.preparationCount == 1)
        #expect(fixture.replacedReviewReceivers == [fixture.receiver])
    }

    // MARK: - Remove

    @Test("the owner terminal's current worktree is protected from removal")
    func protectedMemberIsRefused() async throws {
        // Arrange
        let fixture = try makeFixture()
        _ = try fixture.addMember()
        fixture.install(RecordingReceiverPresentation())
        fixture.knownCWDWorktreeId = fixture.worktree.id
        let before = fixture.handler.record(for: fixture.receiver)

        // Act
        let outcome = await fixture.handler.removeWorktree(fixture.worktree.id, from: fixture.receiver)

        // Assert
        #expect(outcome == .refusedProtected)
        #expect(fixture.handler.record(for: fixture.receiver) == before)
    }

    @Test("removing the Review member clears its displayed file and falls back to the next member")
    func removingReviewMemberFallsBack() async throws {
        // Arrange
        let fixture = try makeFixture()
        let other = try fixture.addMember()
        let presentation = RecordingReceiverPresentation()
        fixture.install(presentation)
        let memberRoot = DarwinFSEventPathCanonicalizer.canonicalURL(fixture.worktree.path).path
        let memberFile = try #require(BridgeDocumentLocation(canonicalPath: "\(memberRoot)/src/app.swift"))
        fixture.handler.recordDisplayedFilesSelection(
            BridgeFilesDisplayedSelection(
                location: memberFile,
                memberWorktreeId: fixture.worktree.id,
                memberRelativePath: "src/app.swift"
            ),
            for: fixture.receiver
        )

        // Act
        let outcome = await fixture.handler.removeWorktree(fixture.worktree.id, from: fixture.receiver)

        // Assert
        #expect(outcome == .applied)
        #expect(presentation.preparationCount == 1, "displayed content leaves only after the editor flush")
        let record = try #require(fixture.handler.record(for: fixture.receiver))
        #expect(record.memberWorktreeIds == [other.id])
        #expect(record.openedDocument(at: memberFile) == nil, "its file never reappears as a loose file")
        #expect(record.openedDocument(at: try #require(fixture.loosePlan)) != nil, "unrelated loose files stay")
        #expect(record.selectedFilesDocument == nil)
        #expect(record.reviewSelection == .member(worktreeId: other.id))
        #expect(fixture.replacedReviewReceivers == [fixture.receiver])
    }

    @Test("a refused editor flush keeps the member and its content")
    func refusedFlushKeepsMember() async throws {
        // Arrange
        let fixture = try makeFixture()
        _ = try fixture.addMember()
        let presentation = RecordingReceiverPresentation()
        presentation.preparationOutcome = .failed
        fixture.install(presentation)
        let before = fixture.handler.record(for: fixture.receiver)

        // Act
        let outcome = await fixture.handler.removeWorktree(fixture.worktree.id, from: fixture.receiver)

        // Assert
        #expect(outcome == .refusedUnsavedDraft)
        #expect(fixture.handler.record(for: fixture.receiver) == before)
    }

    @Test("a CWD that moves into the member while the page flushes turns the removal into a refusal")
    func protectionIsRecheckedAfterTheFlush() async throws {
        // Arrange
        let fixture = try makeFixture()
        _ = try fixture.addMember()
        let presentation = FlushThenMoveCWDPresentation {
            fixture.knownCWDWorktreeId = fixture.worktree.id
        }
        fixture.install(presentation)
        let before = fixture.handler.record(for: fixture.receiver)

        // Act
        let outcome = await fixture.handler.removeWorktree(fixture.worktree.id, from: fixture.receiver)

        // Assert
        #expect(outcome == .refusedProtected)
        #expect(fixture.handler.record(for: fixture.receiver) == before)
    }

    @Test("removing the last member empties Review and keeps loose files usable")
    func removingLastMemberEmptiesReview() async throws {
        // Arrange
        let fixture = try makeFixture()
        fixture.install(RecordingReceiverPresentation())

        // Act
        let outcome = await fixture.handler.removeWorktree(fixture.worktree.id, from: fixture.receiver)

        // Assert
        #expect(outcome == .applied)
        let record = try #require(fixture.handler.record(for: fixture.receiver))
        #expect(record.memberWorktreeIds.isEmpty)
        #expect(record.reviewSelection == .unselected)
        #expect(record.openedDocuments.map(\.location) == [try #require(fixture.loosePlan)])
    }

    @Test("temporary unavailability is not a removal: the member stays listed")
    func temporaryUnavailabilityIsNotRemoval() async throws {
        // Arrange
        let fixture = try makeFixture()
        fixture.install(RecordingReceiverPresentation())
        let before = fixture.handler.record(for: fixture.receiver)

        // Act
        fixture.store.mutationCoordinator.markRepoUnavailable(fixture.repo.id)
        await fixture.handler.applyCatalogUnregistration(of: [])

        // Assert
        #expect(fixture.handler.record(for: fixture.receiver) == before)
        #expect(fixture.handler.reviewBinding(for: fixture.receiver) == nil, "unavailable, not removed")
    }

    // MARK: - Catalog unregistration

    @Test("catalog unregistration removes the worktree from every receiver that lists it")
    func catalogUnregistrationPropagates() async throws {
        // Arrange
        let fixture = try makeFixture()
        let other = try fixture.addMember()
        fixture.install(RecordingReceiverPresentation())
        let secondReceiver = BridgeReceiver.terminal(UUIDv7.generate())
        fixture.handler.ensureRecord(for: secondReceiver, seedingKnownWorktreeId: other.id)
        let removedEntry = RemovedWorktreeEntry(id: other.id, path: other.path)

        // Act
        await fixture.handler.applyCatalogUnregistration(of: [removedEntry])

        // Assert
        #expect(fixture.handler.record(for: fixture.receiver)?.memberWorktreeIds == [fixture.worktree.id])
        #expect(fixture.handler.record(for: secondReceiver)?.memberWorktreeIds.isEmpty == true)
        #expect(fixture.handler.record(for: secondReceiver)?.reviewSelection == .unselected)
        #expect(fixture.handler.pendingCatalogUnregistrationRootsById.isEmpty)
    }

    // MARK: - Fixture

    private func makeFixture() throws -> BridgeNavigationHandlerFixture {
        try BridgeNavigationHandlerFixture(
            root: FileManager.default.temporaryDirectory.appending(
                path: "bridge-navigation-membership-\(UUIDv7.generate().uuidString)",
                directoryHint: .isDirectory
            )
        )
    }
}

/// Flushes successfully, but the owner terminal's CWD moves while it does.
@MainActor
private final class FlushThenMoveCWDPresentation: BridgeReceiverPresentation {
    private let moveCWD: @MainActor () -> Void

    init(moveCWD: @escaping @MainActor () -> Void) {
        self.moveCWD = moveCWD
    }

    func prepareActiveEditorsForNavigation() async -> BridgeEditorPreparationOutcome {
        moveCWD()
        return .prepared
    }

    func activateFileDocument(_: BridgeDocumentLocation) async -> BridgeFileActivationArrival {
        .cancelled
    }

    @discardableResult
    func requestViewerSurface(_: BridgeProductSurface) -> Bool { true }
}
