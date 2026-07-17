import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite(.serialized)
struct WorkspacePersistenceRevisionOwnerTests {
    @Test("initial committed revision is zero")
    func initialCommittedRevisionIsZero() {
        // Arrange
        let revisionOwner = WorkspacePersistenceRevisionOwner()

        // Act
        let committedRevision = revisionOwner.committedRevision

        // Assert
        #expect(committedRevision == .zero)
    }

    @Test("successful synchronous transaction publishes exactly the next revision")
    func successfulSynchronousTransactionPublishesExactlyNextRevision() throws {
        // Arrange
        let revisionOwner = WorkspacePersistenceRevisionOwner()
        let participant = FakePersistenceRevisionParticipant()

        // Act
        let transactionResult = try revisionOwner.performSynchronousTransaction { preparation in
            let transaction = preparation.transaction
            #expect(transaction.processGeneration == revisionOwner.processGeneration)
            #expect(transaction.expectedPreviousRevision == .zero)
            #expect(transaction.proposedRevision.rawValue == 1)
            try participant.prepare()
            return preparation.commit {
                participant.apply(proposedRevision: transaction.proposedRevision)
            }
        }

        // Assert
        #expect(transactionResult.revision.rawValue == 1)
        #expect(participant.observedRevisions == [transactionResult.revision])
        #expect(revisionOwner.committedRevision == transactionResult.revision)
    }

    @Test("all participants receive the same proposed revision")
    func allParticipantsReceiveSameProposedRevision() throws {
        // Arrange
        let revisionOwner = WorkspacePersistenceRevisionOwner()
        let identityParticipant = FakePersistenceRevisionParticipant()
        let paneParticipant = FakePersistenceRevisionParticipant()
        let tabParticipant = FakePersistenceRevisionParticipant()

        // Act
        let transactionResult = try revisionOwner.performSynchronousTransaction { preparation in
            let proposedRevision = preparation.transaction.proposedRevision
            try identityParticipant.prepare()
            try paneParticipant.prepare()
            try tabParticipant.prepare()
            return preparation.commit {
                _ = identityParticipant.apply(proposedRevision: proposedRevision)
                _ = paneParticipant.apply(proposedRevision: proposedRevision)
                return tabParticipant.apply(proposedRevision: proposedRevision)
            }
        }

        // Assert
        #expect(transactionResult.revision.rawValue == 1)
        #expect(identityParticipant.observedRevisions == [transactionResult.revision])
        #expect(paneParticipant.observedRevisions == [transactionResult.revision])
        #expect(tabParticipant.observedRevisions == [transactionResult.revision])
        #expect(revisionOwner.committedRevision == transactionResult.revision)
    }

    @Test("throwing transaction publishes no revision")
    func throwingTransactionPublishesNoRevision() {
        // Arrange
        let revisionOwner = WorkspacePersistenceRevisionOwner()
        let successfulParticipant = FakePersistenceRevisionParticipant()
        let rejectingParticipant = FakePersistenceRevisionParticipant(shouldReject: true)
        // Act / Assert
        #expect(throws: FakePersistenceTransactionError.rejected) {
            let _: FakePersistenceTransactionResult = try revisionOwner.performSynchronousTransaction { preparation in
                try successfulParticipant.prepare()
                try rejectingParticipant.prepare()
                return preparation.commit {
                    successfulParticipant.apply(proposedRevision: preparation.transaction.proposedRevision)
                }
            }
        }
        #expect(successfulParticipant.observedRevisions.isEmpty)
        #expect(rejectingParticipant.observedRevisions.isEmpty)
        #expect(revisionOwner.committedRevision == .zero)
    }

    @Test("unchanged decision cancels participant custody without publishing a revision")
    func unchangedDecisionCancelsParticipantCustodyWithoutPublishingRevision() throws {
        // Arrange
        let revisionOwner = WorkspacePersistenceRevisionOwner()
        let participant = FakePersistenceRevisionParticipant()
        var didApply = false
        var didCancel = false

        // Act
        let result = try revisionOwner.performSynchronousTransactionDecision { preparation in
            let registration = revisionOwner.registerPreparedParticipantMutation(
                participant: participant,
                preparation: preparation,
                apply: { didApply = true },
                cancel: { didCancel = true }
            )
            #expect(registration == .registered)
            return WorkspacePersistenceTransactionDecision.unchanged("unchanged")
        }

        // Assert
        #expect(result == "unchanged")
        #expect(!didApply)
        #expect(didCancel)
        #expect(revisionOwner.committedRevision == .zero)
    }

    @Test("sequential transactions publish a contiguous revision stream")
    func sequentialTransactionsPublishContiguousRevisionStream() throws {
        // Arrange
        let revisionOwner = WorkspacePersistenceRevisionOwner()
        var transactions: [WorkspacePersistenceTransaction] = []

        // Act
        for _ in 0..<2 {
            try revisionOwner.performSynchronousTransaction { preparation in
                transactions.append(preparation.transaction)
                return preparation.commit {}
            }
        }

        // Assert
        #expect(transactions.map(\.expectedPreviousRevision.rawValue) == [0, 1])
        #expect(transactions.map(\.proposedRevision.rawValue) == [1, 2])
        #expect(revisionOwner.committedRevision.rawValue == 2)
    }

    @Test("reentrant transaction is rejected without duplicate revision issuance")
    func reentrantTransactionIsRejectedWithoutDuplicateRevisionIssuance() throws {
        // Arrange
        let revisionOwner = WorkspacePersistenceRevisionOwner()
        var outerTransaction: WorkspacePersistenceTransaction?

        // Act
        try revisionOwner.performSynchronousTransaction { preparation in
            outerTransaction = preparation.transaction
            #expect(throws: WorkspacePersistenceRevisionOwnerError.reentrantTransaction) {
                try revisionOwner.performSynchronousTransaction { nestedPreparation in
                    nestedPreparation.commit {}
                }
            }
            return preparation.commit {}
        }

        // Assert
        #expect(outerTransaction?.proposedRevision.rawValue == 1)
        #expect(revisionOwner.committedRevision.rawValue == 1)
    }

    @Test("process generation is stable and UUIDv7")
    func processGenerationIsStableAndUUIDv7() {
        // Arrange
        let revisionOwner = WorkspacePersistenceRevisionOwner()

        // Act
        let firstRead: WorkspacePersistenceProcessGeneration = revisionOwner.processGeneration
        let secondRead: WorkspacePersistenceProcessGeneration = revisionOwner.processGeneration

        // Assert
        #expect(firstRead == secondRead)
        #expect(firstRead.isUUIDv7)
        #expect(UUIDv7.isV7(firstRead.rawValue))
    }

    @Test("workspace store initial composition is independent from the revision owner")
    func workspaceStoreInitialCompositionIsIndependentFromRevisionOwner() {
        // Arrange
        let atomRegistry = AtomRegistry()

        // Act
        let workspaceStore = WorkspaceStore(
            identityAtom: atomRegistry.workspaceIdentity,
            windowMemoryAtom: atomRegistry.workspaceWindowMemory,
            repositoryTopologyAtom: atomRegistry.workspaceRepositoryTopology,
            paneAtom: atomRegistry.workspacePane,
            tabLayoutAtom: atomRegistry.workspaceTabLayout,
            mutationCoordinator: atomRegistry.workspaceMutationCoordinator
        )

        // Assert
        #expect(workspaceStore.identityAtom === atomRegistry.workspaceIdentity)
        #expect(workspaceStore.paneGraphAtom === atomRegistry.workspacePaneGraph)
        #expect(workspaceStore.tabGraphAtom === atomRegistry.workspaceTabGraph)
    }
}

private enum FakePersistenceTransactionResult: Equatable {
    case applied(revision: WorkspacePersistenceRevision)

    var revision: WorkspacePersistenceRevision {
        switch self {
        case .applied(let revision):
            revision
        }
    }
}

private enum FakePersistenceTransactionError: Error, Equatable {
    case rejected
}

@MainActor
private final class FakePersistenceRevisionParticipant {
    private(set) var observedRevisions: [WorkspacePersistenceRevision] = []
    private let shouldReject: Bool

    init(shouldReject: Bool = false) {
        self.shouldReject = shouldReject
    }

    func prepare() throws {
        guard !shouldReject else {
            throw FakePersistenceTransactionError.rejected
        }
    }

    func apply(proposedRevision: WorkspacePersistenceRevision) -> FakePersistenceTransactionResult {
        observedRevisions.append(proposedRevision)
        return .applied(revision: proposedRevision)
    }
}
