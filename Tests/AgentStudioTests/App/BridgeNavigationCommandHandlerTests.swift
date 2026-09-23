import AgentStudioInfrastructure
import Foundation
import Testing

@testable import AgentStudio
@testable import AgentStudioBridge
@testable import AgentStudioCore
@testable import AgentStudioTestSupport

@MainActor
@Suite("Bridge navigation command handler", .serialized)
struct BridgeNavigationCommandHandlerTests {
    init() {
        installTestCoreAtomsIfNeeded()
    }

    @Test("the initial comparison designation applies once; a reviewer choice replaces it")
    func initialDesignationAppliesOnceAndReviewerChoiceReplaces() throws {
        // Arrange
        let fixture = makeFixture()
        let receiver = BridgeReceiver.standalone(UUIDv7.generate())
        fixture.handler.ensureRecord(for: receiver, seedingKnownWorktreeId: fixture.worktree.id)
        let automatic = WorkspaceReviewContributionTarget.originDefaultBranch(remoteName: "origin", branchName: "main")
        let reviewer = WorkspaceReviewContributionTarget.branch(name: "stack/base")

        // Act
        let firstDefault = fixture.handler.commitReviewComparison(
            automatic, for: receiver, worktreeId: fixture.worktree.id, onlyIfAbsent: true)
        let repeatedDefault = fixture.handler.commitReviewComparison(
            .branch(name: "other"), for: receiver, worktreeId: fixture.worktree.id, onlyIfAbsent: true)
        let reviewerChoice = fixture.handler.commitReviewComparison(
            reviewer, for: receiver, worktreeId: fixture.worktree.id, onlyIfAbsent: false)
        let lateDefault = fixture.handler.commitReviewComparison(
            automatic, for: receiver, worktreeId: fixture.worktree.id, onlyIfAbsent: true)

        // Assert
        #expect(firstDefault == .applied(WorkspaceBaseline(contributionTarget: automatic)))
        #expect(repeatedDefault == .unchanged(WorkspaceBaseline(contributionTarget: automatic)))
        #expect(reviewerChoice == .applied(WorkspaceBaseline(contributionTarget: reviewer)))
        #expect(lateDefault == .unchanged(WorkspaceBaseline(contributionTarget: reviewer)), "reviewer target wins")
        #expect(
            fixture.handler.reviewBinding(for: receiver)
                == BridgeReviewSourceBinding(
                    worktreeId: fixture.worktree.id,
                    worktreeRootPath: fixture.worktree.path.path,
                    comparison: WorkspaceBaseline(contributionTarget: reviewer)
                )
        )
    }

    @Test("comparison commits for a non-member or a missing receiver report the receiver unavailable")
    func commitsOutsideTheCollectionAreRefused() {
        let fixture = makeFixture()
        let receiver = BridgeReceiver.terminal(UUIDv7.generate())

        #expect(
            fixture.handler.commitReviewComparison(
                .branch(name: "main"), for: receiver, worktreeId: fixture.worktree.id, onlyIfAbsent: false)
                == .receiverUnavailable
        )
        fixture.handler.ensureRecord(for: receiver, seedingKnownWorktreeId: nil)
        #expect(
            fixture.handler.commitReviewComparison(
                .branch(name: "main"), for: receiver, worktreeId: fixture.worktree.id, onlyIfAbsent: false)
                == .receiverUnavailable
        )
    }

    @Test("a temporarily unavailable member keeps its membership but yields no Review input")
    func unavailableMemberHasNoReviewInput() {
        let fixture = makeFixture()
        let receiver = BridgeReceiver.standalone(UUIDv7.generate())
        fixture.handler.ensureRecord(for: receiver, seedingKnownWorktreeId: fixture.worktree.id)

        fixture.store.mutationCoordinator.markRepoUnavailable(fixture.repo.id)

        #expect(fixture.handler.reviewBinding(for: receiver) == nil)
        #expect(fixture.handler.record(for: receiver)?.memberWorktreeIds == [fixture.worktree.id])
    }

    @Test("a failed legacy conversion is never reseeded")
    func conversionUnavailablePaneIsNotReseeded() {
        let fixture = makeFixture()
        let paneId = UUIDv7.generate()
        fixture.store.bridgeNavigationAtom.replaceConversionUnavailablePaneIds([paneId])

        let record = fixture.handler.ensureRecord(
            for: .standalone(paneId),
            seedingKnownWorktreeId: fixture.worktree.id
        )

        #expect(record == nil)
        #expect(fixture.store.bridgeNavigationAtom.record(for: .standalone(paneId)) == nil)
    }

    @Test("a known CWD association injects its member without changing selections")
    func knownCWDInjectsMember() {
        let fixture = makeFixture()
        let otherRepo = fixture.store.addRepo(at: fixture.root.appending(path: "other", directoryHint: .isDirectory))
        let otherWorktree = fixture.store.repo(otherRepo.id)?.worktrees.first
        let paneId = UUIDv7.generate()
        fixture.handler.ensureRecord(for: .terminal(paneId), seedingKnownWorktreeId: fixture.worktree.id)

        fixture.handler.applyKnownCWDAssociation(otherWorktree?.id, forTerminalPane: paneId)

        let record = fixture.handler.record(for: .terminal(paneId))
        #expect(record?.memberWorktreeIds == [fixture.worktree.id, otherWorktree?.id].compactMap(\.self))
        #expect(record?.reviewSelection == .member(worktreeId: fixture.worktree.id))
    }

    // MARK: - Fixture

    private struct Fixture {
        let root: URL
        let store: WorkspaceStore
        let handler: BridgeNavigationCommandHandler
        let repo: Repo
        let worktree: Worktree
    }

    private func makeFixture() -> Fixture {
        let root = FileManager.default.temporaryDirectory.appending(
            path: "bridge-navigation-handler-\(UUIDv7.generate().uuidString)",
            directoryHint: .isDirectory
        )
        let store = WorkspaceStore(startsObserving: false)
        let repo = store.addRepo(at: root.appending(path: "repo", directoryHint: .isDirectory))
        let worktree = store.repo(repo.id)!.worktrees.first!
        return Fixture(
            root: root,
            store: store,
            handler: BridgeNavigationCommandHandler(
                navigationAtom: store.bridgeNavigationAtom,
                repositoryTopologyAtom: store.repositoryTopologyAtom
            ),
            repo: repo,
            worktree: worktree
        )
    }
}
