import AgentStudioInfrastructure
import AgentStudioTestHarness
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

    @Test("a newer navigation wins while an older path is still being canonicalized")
    func newerActivationSupersedesDiscovery() async throws {
        let fixture = try makeFixture()
        let presentation = RecordingReceiverPresentation()
        fixture.install(presentation)
        let document = try #require(fixture.loosePlan)
        let canonicalizer = HeldBridgeNavigationCanonicalizer()
        let older = Task {
            await fixture.handler.perform(
                .activateFile(absolutePath: document.canonicalPath),
                in: fixture.receiver,
                canonicalize: { await canonicalizer.resolve($0) }
            )
        }
        #expect(await canonicalizer.waitForFirstPath() == document.canonicalPath)

        let newer = await fixture.handler.perform(
            .activateFile(absolutePath: document.canonicalPath),
            in: fixture.receiver,
            canonicalize: { await canonicalizer.resolve($0) }
        )
        await canonicalizer.releaseFirst()

        #expect(newer == .applied)
        #expect(await older.value == .superseded)
        #expect(presentation.activatedLocations == [document])
        #expect(fixture.persistCount == 1)
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
    func displayedMemberFileIsRecorded() async throws {
        // Arrange
        let fixture = try makeFixture()
        let location = try #require(BridgeDocumentLocation(canonicalPath: "/tmp/repo/src/app.swift"))

        // Act
        let receipt = fixture.handler.recordDisplayedFilesSelection(
            BridgeFilesDisplayedSelection(
                location: location,
                memberWorktreeId: fixture.worktree.id,
                memberRelativePath: "src/app.swift"
            ),
            for: fixture.receiver
        )
        await receipt?.value

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
    func displayedFileOfRemovedMemberIsIgnored() async throws {
        // Arrange
        let fixture = try makeFixture()
        let before = fixture.handler.record(for: fixture.receiver)

        // Act
        let receipt = fixture.handler.recordDisplayedFilesSelection(
            BridgeFilesDisplayedSelection(
                location: try #require(BridgeDocumentLocation(canonicalPath: "/tmp/elsewhere/a.swift")),
                memberWorktreeId: UUIDv7.generate(),
                memberRelativePath: "a.swift"
            ),
            for: fixture.receiver
        )
        await receipt?.value

        // Assert
        #expect(fixture.handler.record(for: fixture.receiver) == before)
    }

    @Test("a newer displayed receipt wins while an older admission waits off-main")
    func newerDisplayedReceiptWins() async throws {
        let fixture = try makeFixture()
        let olderLocation = try #require(BridgeDocumentLocation(canonicalPath: "/tmp/older.swift"))
        let newerLocation = try #require(BridgeDocumentLocation(canonicalPath: "/tmp/newer.swift"))
        let heldPreparation = HeldStep<BridgeDocumentLocation>("older displayed selection preparation")
        await fixture.holdNextDisplayedSelection(heldPreparation)
        let older = fixture.handler.recordDisplayedFilesSelection(
            .init(location: olderLocation, memberWorktreeId: nil, memberRelativePath: nil),
            for: fixture.receiver)
        #expect(try await heldPreparation.firstArrival() == olderLocation)

        let newer = fixture.handler.recordDisplayedFilesSelection(
            .init(location: newerLocation, memberWorktreeId: nil, memberRelativePath: nil),
            for: fixture.receiver)
        await newer?.value
        heldPreparation.release()
        await older?.value

        let record = try #require(fixture.handler.record(for: fixture.receiver))
        #expect(record.selectedFilesDocument == newerLocation)
        #expect(record.openedDocument(at: olderLocation) == nil)
        #expect(record.openedDocument(at: newerLocation) != nil)
    }

    // MARK: - Close

    @Test("closing the displayed document waits for the editor flush; a refused flush keeps it")
    func closingDisplayedDocumentHonorsTheDraftBarrier() async throws {
        // Arrange
        let fixture = try makeFixture()
        let presentation = RecordingReceiverPresentation()
        presentation.preparationOutcome = .saveOutcomeUnknown
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
        presentation.preparationOutcome = .saveOutcomeUnknown
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
        let otherWorktree = try await fixture.addMember()
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
        let otherWorktree = try await fixture.addMember()
        let presentation = RecordingReceiverPresentation()
        presentation.preparationOutcome = .saveOutcomeUnknown
        fixture.install(presentation)
        let before = fixture.handler.record(for: fixture.receiver)

        // Act
        let outcome = await fixture.handler.activateReview(of: otherWorktree.id, in: fixture.receiver)

        // Assert
        #expect(outcome == .refusedUnsavedDraft)
        #expect(fixture.handler.record(for: fixture.receiver) == before)
        #expect(fixture.replacedReviewReceivers.isEmpty)
    }

    @Test("a full pool of pending draft barriers refuses unknown saves without replacing Review")
    func fullPoolUnknownDraftBarriersKeepReview() async throws {
        let activationCount = 16
        var heldDrafts: [HeldStep<Int>] = []
        var activations:
            [(
                fixture: BridgeNavigationHandlerFixture,
                before: BridgeNavigationRecord?,
                task: Task<BridgeNavigationCommandOutcome, Never>
            )] = []
        for index in 0..<activationCount {
            let fixture = try makeFixture()
            let otherWorktree = try await fixture.addMember()
            let heldDraft = HeldStep<Int>("unknown draft barrier \(index)")
            heldDrafts.append(heldDraft)
            fixture.install(UnknownDraftActivationPresentation(heldDraft: heldDraft, index: index))
            let before = fixture.handler.record(for: fixture.receiver)
            let task = Task { @MainActor in
                await fixture.handler.activateReview(of: otherWorktree.id, in: fixture.receiver)
            }
            activations.append((fixture: fixture, before: before, task: task))
        }

        for (index, heldDraft) in heldDrafts.enumerated() {
            #expect(try await heldDraft.firstArrival() == index)
        }
        for heldDraft in heldDrafts { heldDraft.release() }

        for activation in activations {
            #expect(await activation.task.value == .refusedUnsavedDraft)
            #expect(activation.fixture.handler.record(for: activation.fixture.receiver) == activation.before)
            #expect(activation.fixture.replacedReviewReceivers.isEmpty)
            await activation.fixture.linkMembershipActor.shutdown()
        }
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

private actor HeldBridgeNavigationCanonicalizer {
    private var holdsFirst = true
    private var firstPath: String?
    private var firstPathWaiter: CheckedContinuation<String, Never>?
    private var releaseWaiter: CheckedContinuation<Void, Never>?

    func resolve(_ path: String) async -> BridgeDocumentLocation? {
        if holdsFirst {
            holdsFirst = false
            firstPath = path
            firstPathWaiter?.resume(returning: path)
            firstPathWaiter = nil
            await withCheckedContinuation { releaseWaiter = $0 }
        }
        return BridgeDocumentLocation(canonicalPath: path)
    }

    func waitForFirstPath() async -> String {
        if let firstPath { return firstPath }
        return await withCheckedContinuation { firstPathWaiter = $0 }
    }

    func releaseFirst() {
        releaseWaiter?.resume()
        releaseWaiter = nil
    }
}

@MainActor
private final class UnknownDraftActivationPresentation: BridgeReceiverPresentation {
    private let heldDraft: HeldStep<Int>
    private let index: Int

    init(heldDraft: HeldStep<Int>, index: Int) {
        self.heldDraft = heldDraft
        self.index = index
    }

    func prepareActiveEditorsForNavigation() async -> BridgeEditorPreparationOutcome {
        try? await heldDraft.arrive(index)
        return .saveOutcomeUnknown
    }

    func activateFileDocument(_: BridgeDocumentLocation, line _: Int?) async -> BridgeFileActivationArrival {
        .cancelled
    }

    func searchFilesCollection(_: BridgeFilesSearchCriteria) async -> BridgeFilesSearchOutcome {
        .unavailable(.noLivePage)
    }

    func requestViewerSurface(_: BridgeProductSurface) -> Bool { true }
}
