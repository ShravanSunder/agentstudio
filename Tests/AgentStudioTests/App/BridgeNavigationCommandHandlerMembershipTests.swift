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
        #expect(record.effectiveMemberWorktreeIds == before.effectiveMemberWorktreeIds + [added.id])
        #expect(record.reviewSelection == before.reviewSelection)
        #expect(record.selectedFilesDocument == before.selectedFilesDocument)
        #expect(await fixture.linkCommitPort.commitCount == 2, "both adds reach the commit boundary")
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
        let other = try await fixture.addMember()
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
        let fixture = try makeFixture(terminalReceiver: true)
        _ = try await fixture.addMember()
        fixture.install(RecordingReceiverPresentation())
        fixture.setCurrentCWDWorktree(fixture.worktree)
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
        let other = try await fixture.addMember()
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
        #expect(record.effectiveMemberWorktreeIds == [other.id])
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
        _ = try await fixture.addMember()
        let presentation = RecordingReceiverPresentation()
        presentation.preparationOutcome = .saveOutcomeUnknown
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
        let fixture = try makeFixture(terminalReceiver: true)
        _ = try await fixture.addMember()
        let presentation = FlushThenMoveCWDPresentation {
            fixture.setCurrentCWDWorktree(fixture.worktree)
        }
        fixture.install(presentation)
        let before = fixture.handler.record(for: fixture.receiver)

        // Act
        let outcome = await fixture.handler.removeWorktree(fixture.worktree.id, from: fixture.receiver)

        // Assert
        #expect(outcome == .refusedProtected)
        #expect(fixture.handler.record(for: fixture.receiver) == before)
    }

    @Test("a failed CWD contribution disappears after a move and Review falls back off-main")
    func failedCWDContributionMovesReview() async throws {
        let fixture = try makeFixture(terminalReceiver: true, failInitialAppCommit: true)
        fixture.install(RecordingReceiverPresentation())
        await fixture.linkMembershipActor.awaitReceiverIdle(fixture.receiver)
        let before = try #require(fixture.handler.record(for: fixture.receiver))
        #expect(before.committedMemberLinks.isEmpty)
        #expect(before.effectiveMemberWorktreeIds == [fixture.worktree.id])

        let otherRepo = fixture.store.addRepo(
            at: fixture.root.appending(path: "moved-cwd", directoryHint: .isDirectory)
        )
        let newWorktree = try #require(fixture.store.repo(otherRepo.id)?.worktrees.first)
        fixture.handler.applyKnownCWDAssociation(
            newWorktree.id, forTerminalPane: fixture.receiver.paneId
        )
        let immediate = try #require(fixture.handler.record(for: fixture.receiver))
        #expect(immediate.effectiveMemberWorktreeIds == [newWorktree.id])
        #expect(immediate.reviewSelection == .member(worktreeId: fixture.worktree.id))

        await fixture.linkMembershipActor.awaitReceiverIdle(fixture.receiver)
        let settled = try #require(fixture.handler.record(for: fixture.receiver))
        #expect(settled.committedMemberWorktreeIds == [newWorktree.id])
        #expect(settled.effectiveMemberWorktreeIds == [newWorktree.id])
        #expect(settled.reviewSelection == .member(worktreeId: newWorktree.id))
    }

    @Test("a committed old CWD keeps its app contribution when the CWD moves")
    func committedCWDContributionSurvivesMove() async throws {
        let fixture = try makeFixture(terminalReceiver: true)
        fixture.install(RecordingReceiverPresentation())
        await fixture.linkMembershipActor.awaitReceiverIdle(fixture.receiver)
        let otherRepo = fixture.store.addRepo(
            at: fixture.root.appending(path: "next-cwd", directoryHint: .isDirectory)
        )
        let newWorktree = try #require(fixture.store.repo(otherRepo.id)?.worktrees.first)

        fixture.handler.applyKnownCWDAssociation(
            newWorktree.id, forTerminalPane: fixture.receiver.paneId
        )
        await fixture.linkMembershipActor.awaitReceiverIdle(fixture.receiver)

        let record = try #require(fixture.handler.record(for: fixture.receiver))
        #expect(record.committedMemberWorktreeIds == [fixture.worktree.id, newWorktree.id])
        #expect(record.effectiveMemberWorktreeIds == [fixture.worktree.id, newWorktree.id])
        #expect(
            record.committedMemberLinks.allSatisfy {
                $0.contributions.map(\.addedBy) == [.app]
            })
    }

    @Test("drawer owner movement while the draft barrier waits returns staleOwner")
    func ownerMovementIsRecheckedAfterDraftWait() async throws {
        let fixture = try makeFixture()
        let drawerSourceID = UUIDv7.generate()
        func drawerSource(parentPaneID: UUID) -> Pane {
            Pane(
                id: drawerSourceID,
                content: .terminal(
                    TerminalState(
                        provider: .zmx, lifetime: .persistent, zmxSessionID: .generateUUIDv7()
                    )),
                metadata: PaneMetadata(title: "Drawer source"),
                kind: .drawerChild(parentPaneId: parentPaneID)
            )
        }
        fixture.store.paneAtom.addPane(drawerSource(parentPaneID: fixture.receiver.paneId))
        fixture.install(
            FlushThenMoveCWDPresentation {
                let newOwner = Pane(
                    content: .terminal(
                        TerminalState(
                            provider: .zmx, lifetime: .persistent, zmxSessionID: .generateUUIDv7()
                        )),
                    metadata: PaneMetadata(title: "New owner")
                )
                fixture.store.paneAtom.addPane(newOwner)
                _ = fixture.store.paneAtom.deletePaneAndOwnedDrawerChildren(drawerSourceID)
                fixture.store.paneAtom.addPane(drawerSource(parentPaneID: newOwner.id))
            })

        let result = try await fixture.handler.removeMemberLink(
            fixture.worktree.id, from: fixture.receiver,
            sourcePaneID: drawerSourceID, contributor: .person
        )

        #expect(result == .staleOwner)
        #expect(fixture.handler.record(for: fixture.receiver)?.containsMember(fixture.worktree.id) == true)
    }

    @Test("failed contribution commit leaves the atom unchanged")
    func failedCommitDoesNotPublish() async throws {
        let fixture = try makeFixture()
        fixture.install(RecordingReceiverPresentation())
        await fixture.linkMembershipActor.awaitReceiverIdle(fixture.receiver)
        let otherRepo = fixture.store.addRepo(
            at: fixture.root.appending(path: "failed-commit", directoryHint: .isDirectory)
        )
        let other = try #require(fixture.store.repo(otherRepo.id)?.worktrees.first)
        let before = fixture.handler.record(for: fixture.receiver)
        await fixture.linkCommitPort.failFollowingCommit()

        do {
            _ = try await fixture.handler.addMemberLink(
                other.id, to: fixture.receiver,
                sourcePaneID: fixture.receiver.paneId, contributor: .person
            )
            Issue.record("Expected the commit to fail")
        } catch {
            #expect(error as? BridgeLinkPortFailure == .outcomeUnknown)
        }

        #expect(fixture.handler.record(for: fixture.receiver) == before)
    }

    @Test("agent removes only its own contribution and person removes the link")
    func authorScopedRemoval() async throws {
        let fixture = try makeFixture()
        fixture.install(RecordingReceiverPresentation())
        let provider = try BridgeAgentProviderName("codex")
        let alice = BridgeLinkContributor.agent(
            BridgeAgentContributorIdentity(
                provider: provider, sessionRef: try BridgeAgentSessionRef("alice")
            ))
        let bob = BridgeLinkContributor.agent(
            BridgeAgentContributorIdentity(
                provider: provider, sessionRef: try BridgeAgentSessionRef("bob")
            ))

        #expect(
            try await fixture.handler.addMemberLink(
                fixture.worktree.id, to: fixture.receiver,
                sourcePaneID: fixture.receiver.paneId, contributor: alice
            ) == .added(effect: .newContribution))
        #expect(
            try await fixture.handler.removeMemberLink(
                fixture.worktree.id, from: fixture.receiver,
                sourcePaneID: fixture.receiver.paneId, contributor: bob
            ) == .refusedNotAuthor)
        #expect(
            try await fixture.handler.removeMemberLink(
                fixture.worktree.id, from: fixture.receiver,
                sourcePaneID: fixture.receiver.paneId, contributor: alice
            ) == .removed(removedContributions: [alice]))
        #expect(fixture.handler.record(for: fixture.receiver)?.containsMember(fixture.worktree.id) == true)
        #expect(
            try await fixture.handler.removeMemberLink(
                fixture.worktree.id, from: fixture.receiver,
                sourcePaneID: fixture.receiver.paneId, contributor: .person
            ) == .removed(removedContributions: [.app]))
        #expect(fixture.handler.record(for: fixture.receiver)?.containsMember(fixture.worktree.id) == false)
    }

    @Test("pending member removal has one terminal consumer even when awaited late")
    func pendingRemovalLateAwaitIsConsumedOnce() async throws {
        let fixture = try makeFixture()
        fixture.install(RecordingReceiverPresentation())
        let receiverID = PaneId(existingUUID: fixture.receiver.paneId)

        let immediate = try await fixture.linkMembershipActor.removeMember(
            receiver: receiverID, worktree: fixture.worktree.id, contributor: .person
        )
        guard case .pendingDraftSettlement(let operationID) = immediate else {
            Issue.record("Expected a pending draft settlement")
            return
        }
        await fixture.linkMembershipActor.awaitReceiverIdle(fixture.receiver)
        let settled = try await fixture.linkMembershipActor.awaitPendingMemberRemoval(
            receiver: receiverID, operationId: operationID
        )
        #expect(settled == .removed(removedContributions: [.app]))
        do {
            _ = try await fixture.linkMembershipActor.awaitPendingMemberRemoval(
                receiver: receiverID, operationId: operationID
            )
            Issue.record("A settled operation was delivered twice")
        } catch {
            #expect(error as? BridgeLinkPortFailure == .unavailable)
        }
        await fixture.linkMembershipActor.shutdown()
    }

    @Test("pending removal keeps the draft with the precise native barrier reason")
    func pendingRemovalReportsDraftReason() async throws {
        let cases: [(BridgeEditorPreparationOutcome, BridgeDraftKeptReason)] = [
            (.refused, .refused),
            (.saveFailed, .saveFailed),
            (.saveOutcomeUnknown, .saveOutcomeUnknown),
        ]
        for (preparation, expectedReason) in cases {
            let fixture = try makeFixture()
            let presentation = RecordingReceiverPresentation()
            presentation.preparationOutcome = preparation
            fixture.install(presentation)
            let receiverID = PaneId(existingUUID: fixture.receiver.paneId)

            let immediate = try await fixture.linkMembershipActor.removeMember(
                receiver: receiverID, worktree: fixture.worktree.id, contributor: .person
            )
            guard case .pendingDraftSettlement(let operationID) = immediate else {
                Issue.record("Expected a pending draft settlement")
                await fixture.linkMembershipActor.shutdown()
                continue
            }
            let settled = try await fixture.linkMembershipActor.awaitPendingMemberRemoval(
                receiver: receiverID, operationId: operationID
            )
            #expect(settled == .draftKept(reason: expectedReason))
            #expect(fixture.handler.record(for: fixture.receiver)?.containsMember(fixture.worktree.id) == true)
            await fixture.linkMembershipActor.shutdown()
        }
    }

    @Test("shutdown settles a pending draft wait once before any commit dispatch")
    func shutdownSettlesPendingDraftWait() async throws {
        let fixture = try makeFixture()
        let presentation = HoldingEditorPreparationPresentation()
        fixture.install(presentation)
        let receiverID = PaneId(existingUUID: fixture.receiver.paneId)
        let immediate = try await fixture.linkMembershipActor.removeMember(
            receiver: receiverID, worktree: fixture.worktree.id, contributor: .person
        )
        guard case .pendingDraftSettlement(let operationID) = immediate else {
            Issue.record("Expected a pending draft settlement")
            return
        }
        var entered = presentation.preparationStarted.makeAsyncIterator()
        _ = await entered.next()

        await fixture.linkMembershipActor.shutdown()
        do {
            _ = try await fixture.linkMembershipActor.awaitPendingMemberRemoval(
                receiver: receiverID, operationId: operationID
            )
            Issue.record("Shutdown should settle the waiting operation")
        } catch {
            #expect(error as? BridgeLinkPortFailure == .unavailable)
        }
        #expect(fixture.handler.record(for: fixture.receiver)?.containsMember(fixture.worktree.id) == true)
        presentation.release()
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
        #expect(record.effectiveMemberWorktreeIds.isEmpty)
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
        let other = try await fixture.addMember()
        fixture.install(RecordingReceiverPresentation())
        let secondReceiver = BridgeReceiver.terminal(UUIDv7.generate())
        fixture.store.paneAtom.addPane(
            Pane(
                id: secondReceiver.paneId,
                content: .terminal(
                    TerminalState(
                        provider: .zmx, lifetime: .persistent, zmxSessionID: .generateUUIDv7()
                    )),
                metadata: PaneMetadata(title: "Second receiver")
            ))
        fixture.seedCommittedMember(other.id, for: secondReceiver)
        let removedEntry = RemovedWorktreeEntry(id: other.id, path: other.path)

        // Act
        await fixture.handler.applyCatalogUnregistration(of: [removedEntry])

        // Assert
        #expect(fixture.handler.record(for: fixture.receiver)?.effectiveMemberWorktreeIds == [fixture.worktree.id])
        #expect(fixture.handler.record(for: secondReceiver)?.effectiveMemberWorktreeIds.isEmpty == true)
        #expect(fixture.handler.record(for: secondReceiver)?.reviewSelection == .unselected)
        #expect(fixture.handler.pendingCatalogUnregistrationRootsById.isEmpty)
    }

    @Test("catalog removal emits one post-commit fact for another author, none for app only")
    func catalogRemovalFacts() async throws {
        let fixture = try makeFixture()
        fixture.install(RecordingReceiverPresentation())
        let agent = BridgeLinkContributor.agent(
            BridgeAgentContributorIdentity(
                provider: try BridgeAgentProviderName("codex"),
                sessionRef: try BridgeAgentSessionRef("catalog-fact")
            ))
        let receiverID = PaneId(existingUUID: fixture.receiver.paneId)
        let added = try await fixture.linkMembershipActor.addMember(
            receiver: receiverID, worktree: fixture.worktree.id, contributor: agent
        )
        #expect(added == .added(effect: .newContribution))
        let facts = await fixture.linkMembershipActor.membershipFacts()

        await fixture.handler.applyCatalogUnregistration(of: [
            RemovedWorktreeEntry(id: fixture.worktree.id, path: fixture.worktree.path)
        ])
        await fixture.linkMembershipActor.shutdown()
        var emitted: [BridgeLinkContributionsRemoved] = []
        for await fact in facts { emitted.append(fact) }
        #expect(emitted.count == 1)
        #expect(emitted.first?.removedBy == .app)
        #expect(emitted.first?.removedContributions.contains(agent) == true)

        let appOnly = try makeFixture()
        appOnly.install(RecordingReceiverPresentation())
        let appOnlyFacts = await appOnly.linkMembershipActor.membershipFacts()
        await appOnly.handler.applyCatalogUnregistration(of: [
            RemovedWorktreeEntry(id: appOnly.worktree.id, path: appOnly.worktree.path)
        ])
        await appOnly.linkMembershipActor.shutdown()
        var appOnlyEmitted: [BridgeLinkContributionsRemoved] = []
        for await fact in appOnlyFacts { appOnlyEmitted.append(fact) }
        #expect(appOnlyEmitted.isEmpty)
    }

    @Test("PR reference port commits contributor-scoped rows and emits a cross-author fact")
    func pullRequestPortFacts() async throws {
        let fixture = try makeFixture()
        fixture.install(RecordingReceiverPresentation())
        let receiverID = PaneId(existingUUID: fixture.receiver.paneId)
        let reference = try ForgePullRequestIdentity(
            host: "github.com", owner: "example", repository: "repo", number: 42
        )
        let agent = BridgeLinkContributor.agent(
            BridgeAgentContributorIdentity(
                provider: try BridgeAgentProviderName("codex"),
                sessionRef: try BridgeAgentSessionRef("pr-fact")
            ))
        let facts = await fixture.linkMembershipActor.membershipFacts()

        #expect(
            try await fixture.linkMembershipActor.addPullRequestReference(
                receiver: receiverID, reference: reference, contributor: agent
            ) == .added(effect: .newItem))
        #expect(
            try await fixture.linkMembershipActor.addPullRequestReference(
                receiver: receiverID, reference: reference, contributor: agent
            ) == .alreadyPresent)
        #expect(
            try await fixture.linkMembershipActor.removePullRequestReference(
                receiver: receiverID, reference: reference, contributor: .person
            ) == .removed(removedContributions: [agent]))

        await fixture.linkMembershipActor.shutdown()
        var emitted: [BridgeLinkContributionsRemoved] = []
        for await fact in facts { emitted.append(fact) }
        #expect(emitted.count == 1)
        #expect(emitted.first?.item == .pullRequest(reference))
        #expect(emitted.first?.removedBy == .person)
    }

    // MARK: - Fixture

    private func makeFixture(
        terminalReceiver: Bool = false,
        failInitialAppCommit: Bool = false
    ) throws -> BridgeNavigationHandlerFixture {
        try BridgeNavigationHandlerFixture(
            root: FileManager.default.temporaryDirectory.appending(
                path: "bridge-navigation-membership-\(UUIDv7.generate().uuidString)",
                directoryHint: .isDirectory
            ),
            terminalReceiver: terminalReceiver,
            failInitialAppCommit: failInitialAppCommit
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

    func activateFileDocument(_: BridgeDocumentLocation, line _: Int?) async -> BridgeFileActivationArrival {
        .cancelled
    }

    func searchFilesCollection(_: BridgeFilesSearchCriteria) async -> BridgeFilesSearchOutcome {
        .unavailable(.noLivePage)
    }

    @discardableResult
    func requestViewerSurface(_: BridgeProductSurface) -> Bool { true }
}

@MainActor
private final class HoldingEditorPreparationPresentation: BridgeReceiverPresentation {
    let preparationStarted: AsyncStream<Void>
    private let startedContinuation: AsyncStream<Void>.Continuation
    private var releaseContinuation: CheckedContinuation<Void, Never>?

    init() {
        (preparationStarted, startedContinuation) = AsyncStream.makeStream(
            of: Void.self, bufferingPolicy: .bufferingNewest(1)
        )
    }

    func prepareActiveEditorsForNavigation() async -> BridgeEditorPreparationOutcome {
        await withCheckedContinuation { continuation in
            releaseContinuation = continuation
            startedContinuation.yield(())
        }
        return .prepared
    }

    func release() {
        releaseContinuation?.resume()
        releaseContinuation = nil
        startedContinuation.finish()
    }

    func activateFileDocument(_: BridgeDocumentLocation, line _: Int?) async -> BridgeFileActivationArrival {
        .cancelled
    }

    func searchFilesCollection(_: BridgeFilesSearchCriteria) async -> BridgeFilesSearchOutcome {
        .unavailable(.noLivePage)
    }

    @discardableResult
    func requestViewerSurface(_: BridgeProductSurface) -> Bool { true }
}
