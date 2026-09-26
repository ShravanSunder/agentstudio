import AgentStudioInfrastructure
import Foundation
import Testing

@testable import AgentStudio
@testable import AgentStudioBridge
@testable import AgentStudioCore
@testable import AgentStudioTestSupport

@MainActor
@Suite("Bridge navigation activation, draft barrier and close", .serialized)
struct BridgeNavigationCommandHandlerActivationTests {
    init() {
        installTestCoreAtomsIfNeeded()
    }

    // MARK: - Files activation

    @Test("a displayed File activation reports applied, and unsaved when the save fails")
    func displayedActivationSeparatesRenderedFromPersisted() async throws {
        // Arrange
        let fixture = try makeFixture()
        let presentation = RecordingReceiverPresentation()
        fixture.install(presentation)
        let document = try #require(fixture.loosePlan)

        // Act
        let persisted = await fixture.handler.activateFile(document, in: fixture.receiver)
        fixture.persistenceSucceeds = false
        let unsaved = await fixture.handler.activateFile(document, in: fixture.receiver)

        // Assert
        #expect(persisted == .applied)
        #expect(unsaved == .appliedUnsaved)
        #expect(presentation.activatedLocations == [document, document])
    }

    @Test("a refused editor flush keeps the old document and reports the unsaved draft")
    func refusedFlushKeepsOldDocument() async throws {
        // Arrange
        let fixture = try makeFixture()
        let presentation = RecordingReceiverPresentation()
        presentation.activationArrival = .refused
        fixture.install(presentation)
        let before = fixture.handler.record(for: fixture.receiver)

        // Act
        let outcome = await fixture.handler.activateFile(try #require(fixture.loosePlan), in: fixture.receiver)

        // Assert
        #expect(outcome == .refusedUnsavedDraft)
        #expect(fixture.handler.record(for: fixture.receiver) == before)
        #expect(fixture.persistCount == 0, "nothing new is saved for a refused activation")
    }

    @Test("a late arrival of an older activation is reported superseded, never applied")
    func staleActivationIsSuperseded() async throws {
        // Arrange
        let fixture = try makeFixture()
        let presentation = RecordingReceiverPresentation()
        fixture.install(presentation)
        let document = try #require(fixture.loosePlan)
        presentation.holdsNextArrival = true
        let olderActivation = Task { await fixture.handler.activateFile(document, in: fixture.receiver) }
        #expect(try await presentation.waitForHeldActivation() == .displayed)

        // Act
        let newer = await fixture.handler.activateFile(document, in: fixture.receiver)
        presentation.releaseHeldArrival(.displayed)
        let older = await olderActivation.value

        // Assert
        #expect(newer == .applied)
        #expect(older == .superseded)
        #expect(fixture.persistCount == 1, "only the current activation saves")
    }

    @Test("activation without a mounted Bridge or a record fails without touching the record")
    func activationNeedsMountedReceiver() async throws {
        // Arrange
        let fixture = try makeFixture()
        let document = try #require(fixture.loosePlan)

        // Act
        let unmounted = await fixture.handler.activateFile(document, in: fixture.receiver)
        let unknown = await fixture.handler.activateFile(document, in: .standalone(UUIDv7.generate()))

        // Assert
        #expect(unmounted == .failed(.notMounted))
        #expect(unknown == .failed(.receiverUnavailable))
    }

    // MARK: - Displayed selection receipts

    @Test("a displayed member file is admitted with its provenance and selected in Files")
    func displayedMemberFileIsRecorded() throws {
        // Arrange
        let fixture = try makeFixture()
        let location = try #require(BridgeDocumentLocation(canonicalPath: "/tmp/repo/src/app.swift"))

        // Act
        fixture.handler.recordDisplayedFilesSelection(
            BridgeFilesDisplayedSelection(
                location: location,
                memberWorktreeId: fixture.worktree.id,
                memberRelativePath: "src/app.swift"
            ),
            for: fixture.receiver
        )

        // Assert
        let record = try #require(fixture.handler.record(for: fixture.receiver))
        #expect(record.selectedFilesDocument == location)
        #expect(record.surface == .files)
        #expect(
            record.openedDocument(at: location)?.provenance
                == BridgeKnownWorktreeProvenance(
                    repoId: fixture.repo.id,
                    worktreeId: fixture.worktree.id,
                    relativePath: "src/app.swift"
                )
        )
        #expect(record.reviewSelection == .member(worktreeId: fixture.worktree.id), "Review is untouched")
    }

    @Test("a displayed file of a worktree that left the receiver is ignored")
    func displayedFileOfRemovedMemberIsIgnored() throws {
        // Arrange
        let fixture = try makeFixture()
        let before = fixture.handler.record(for: fixture.receiver)

        // Act
        fixture.handler.recordDisplayedFilesSelection(
            BridgeFilesDisplayedSelection(
                location: try #require(BridgeDocumentLocation(canonicalPath: "/tmp/elsewhere/a.swift")),
                memberWorktreeId: UUIDv7.generate(),
                memberRelativePath: "a.swift"
            ),
            for: fixture.receiver
        )

        // Assert
        #expect(fixture.handler.record(for: fixture.receiver) == before)
    }

    // MARK: - Close

    @Test("closing the displayed document waits for the editor flush; a refused flush keeps it")
    func closingDisplayedDocumentHonorsTheDraftBarrier() async throws {
        // Arrange
        let fixture = try makeFixture()
        let presentation = RecordingReceiverPresentation()
        presentation.preparationOutcome = .failed
        fixture.install(presentation)
        let document = try #require(fixture.loosePlan)
        fixture.selectInFiles(document)

        // Act
        let refused = await fixture.handler.closeFile(document, in: fixture.receiver)
        presentation.preparationOutcome = .prepared
        let closed = await fixture.handler.closeFile(document, in: fixture.receiver)

        // Assert
        #expect(refused == .refusedUnsavedDraft)
        #expect(closed == .applied)
        #expect(presentation.preparationCount == 2)
        let record = try #require(fixture.handler.record(for: fixture.receiver))
        #expect(record.openedDocument(at: document) == nil)
        #expect(record.selectedFilesDocument == nil)
        #expect(fixture.refreshedFilesReceivers == [fixture.receiver])
    }

    @Test("closing a document that is not displayed needs no editor flush")
    func closingHiddenDocumentSkipsTheBarrier() async throws {
        // Arrange
        let fixture = try makeFixture()
        let presentation = RecordingReceiverPresentation()
        presentation.preparationOutcome = .failed
        fixture.install(presentation)

        // Act
        let outcome = await fixture.handler.closeFile(try #require(fixture.loosePlan), in: fixture.receiver)

        // Assert
        #expect(outcome == .applied)
        #expect(presentation.preparationCount == 0)
    }

    // MARK: - Review

    @Test("Review of another member flushes editors, replaces the source and keeps the Files selection")
    func reviewOfAnotherMemberReplacesSource() async throws {
        // Arrange
        let fixture = try makeFixture()
        let otherWorktree = try fixture.addMember()
        let presentation = RecordingReceiverPresentation()
        fixture.install(presentation)
        let document = try #require(fixture.loosePlan)
        fixture.selectInFiles(document)

        // Act
        let outcome = await fixture.handler.activateReview(of: otherWorktree.id, in: fixture.receiver)

        // Assert
        #expect(outcome == .applied)
        #expect(presentation.preparationCount == 1)
        #expect(fixture.replacedReviewReceivers == [fixture.receiver])
        let record = try #require(fixture.handler.record(for: fixture.receiver))
        #expect(record.reviewSelection == .member(worktreeId: otherWorktree.id))
        #expect(record.surface == .review)
        #expect(record.selectedFilesDocument == document)
    }

    @Test("a refused flush before Review replacement changes nothing")
    func refusedFlushBlocksReviewReplacement() async throws {
        // Arrange
        let fixture = try makeFixture()
        let otherWorktree = try fixture.addMember()
        let presentation = RecordingReceiverPresentation()
        presentation.preparationOutcome = .failed
        fixture.install(presentation)
        let before = fixture.handler.record(for: fixture.receiver)

        // Act
        let outcome = await fixture.handler.activateReview(of: otherWorktree.id, in: fixture.receiver)

        // Assert
        #expect(outcome == .refusedUnsavedDraft)
        #expect(fixture.handler.record(for: fixture.receiver) == before)
        #expect(fixture.replacedReviewReceivers.isEmpty)
    }

    @Test("Review of the already selected member only shows Review")
    func reviewOfSameMemberShowsReview() async throws {
        // Arrange
        let fixture = try makeFixture()
        let presentation = RecordingReceiverPresentation()
        fixture.install(presentation)

        // Act
        let outcome = await fixture.handler.activateReview(of: fixture.worktree.id, in: fixture.receiver)

        // Assert
        #expect(outcome == .applied)
        #expect(presentation.preparationCount == 0)
        #expect(presentation.requestedSurfaces == [.review])
        #expect(fixture.replacedReviewReceivers.isEmpty)
    }

    @Test("Review of a worktree that is not a member is refused")
    func reviewOfNonMemberIsRefused() async throws {
        // Arrange
        let fixture = try makeFixture()
        fixture.install(RecordingReceiverPresentation())

        // Act
        let outcome = await fixture.handler.activateReview(of: UUIDv7.generate(), in: fixture.receiver)

        // Assert
        #expect(outcome == .failed(.notMember))
    }

    private func makeFixture() throws -> BridgeNavigationHandlerFixture {
        try BridgeNavigationHandlerFixture(
            root: FileManager.default.temporaryDirectory.appending(
                path: "bridge-navigation-activation-\(UUIDv7.generate().uuidString)",
                directoryHint: .isDirectory
            )
        )
    }
}
