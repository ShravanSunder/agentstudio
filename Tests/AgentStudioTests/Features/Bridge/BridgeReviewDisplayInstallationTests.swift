import AgentStudioInfrastructure
import Foundation
import Testing

@testable import AgentStudioBridge

@MainActor
@Suite("Display installation")
struct DisplayInstallationTests {
    @Test("duplicate applied receipt establishes replacement worker exact-predecessor authority")
    func duplicateReceiptEstablishesReplacementWorker() async throws {
        // Arrange
        let productAdmission = try BridgeProductAdmissionTestContext.make()
        let coordinator = BridgeReviewPublicationCoordinator()
        let publicationA = try await makeReviewPreparedPublication(
            suffix: "replacement-worker-a",
            reviewGeneration: 1
        )
        let publicationB = try await makeReviewPreparedPublication(
            suffix: "replacement-worker-b",
            reviewGeneration: 2
        )
        let committedA = try commitObserved(
            publicationA,
            in: coordinator,
            productAdmission: productAdmission.context
        )
        #expect(
            coordinator.admitDisplayInstallation(
                expectedDisplayedPublicationId: nil,
                candidatePublicationId: committedA.publicationId,
                workerInstanceId: "worker-a",
                productAdmission: productAdmission.context
            ) == .admitted
        )
        #expect(
            coordinator.recordDisplayedApplication(
                publicationId: committedA.publicationId,
                workerInstanceId: "worker-a",
                productAdmission: productAdmission.context
            ) == .advanced
        )

        // Act
        let duplicate = coordinator.recordDisplayedApplication(
            publicationId: committedA.publicationId,
            workerInstanceId: "worker-b",
            productAdmission: productAdmission.context
        )
        let committedB = try commitObserved(
            publicationB,
            in: coordinator,
            productAdmission: productAdmission.context
        )
        let nullAdmission = coordinator.admitDisplayInstallation(
            expectedDisplayedPublicationId: nil,
            candidatePublicationId: committedB.publicationId,
            workerInstanceId: "worker-b",
            productAdmission: productAdmission.context
        )
        let exactAdmission = coordinator.admitDisplayInstallation(
            expectedDisplayedPublicationId: committedA.publicationId,
            candidatePublicationId: committedB.publicationId,
            workerInstanceId: "worker-b",
            productAdmission: productAdmission.context
        )

        // Assert
        #expect(duplicate == .duplicate)
        #expect(nullAdmission == .rejected)
        #expect(exactAdmission == .admitted)
    }

    @Test("stale and unknown applied receipts do not establish worker display")
    func invalidReceiptsDoNotEstablishWorkerDisplay() async throws {
        // Arrange
        let productAdmission = try BridgeProductAdmissionTestContext.make()
        let coordinator = BridgeReviewPublicationCoordinator()
        let publicationA = try await makeReviewPreparedPublication(
            suffix: "invalid-worker-a",
            reviewGeneration: 1
        )
        let publicationB = try await makeReviewPreparedPublication(
            suffix: "invalid-worker-b",
            reviewGeneration: 2
        )
        let publicationC = try await makeReviewPreparedPublication(
            suffix: "invalid-worker-c",
            reviewGeneration: 3
        )
        let committedA = try commitObserved(
            publicationA,
            in: coordinator,
            productAdmission: productAdmission.context
        )
        let committedB = try commitObserved(
            publicationB,
            in: coordinator,
            productAdmission: productAdmission.context
        )
        #expect(
            coordinator.admitDisplayInstallation(
                expectedDisplayedPublicationId: nil,
                candidatePublicationId: committedB.publicationId,
                workerInstanceId: "worker-b",
                productAdmission: productAdmission.context
            ) == .admitted
        )
        #expect(
            coordinator.recordDisplayedApplication(
                publicationId: committedB.publicationId,
                workerInstanceId: "worker-b",
                productAdmission: productAdmission.context
            ) == .advanced
        )
        let committedC = try commitObserved(
            publicationC,
            in: coordinator,
            productAdmission: productAdmission.context
        )

        // Act
        let stale = coordinator.recordDisplayedApplication(
            publicationId: committedA.publicationId,
            workerInstanceId: "worker-c",
            productAdmission: productAdmission.context
        )
        let unknown = coordinator.recordDisplayedApplication(
            publicationId: UUIDv7.generate(),
            workerInstanceId: "worker-c",
            productAdmission: productAdmission.context
        )
        let freshAdmission = coordinator.admitDisplayInstallation(
            expectedDisplayedPublicationId: nil,
            candidatePublicationId: committedC.publicationId,
            workerInstanceId: "worker-c",
            productAdmission: productAdmission.context
        )

        // Assert
        #expect(stale == .rejected)
        #expect(unknown == .rejected)
        #expect(freshAdmission == .admitted)
    }

    @Test("fresh worker bootstraps current and retirement releases only its unmatched admission")
    func freshWorkerBootstrapAndRetirement() async throws {
        // Arrange
        let productAdmission = try BridgeProductAdmissionTestContext.make()
        let coordinator = BridgeReviewPublicationCoordinator()
        let publicationA = try await makeReviewPreparedPublication(
            suffix: "fresh-worker-a",
            reviewGeneration: 1
        )
        let publicationB = try await makeReviewPreparedPublication(
            suffix: "fresh-worker-b",
            reviewGeneration: 2
        )
        let publicationC = try await makeReviewPreparedPublication(
            suffix: "fresh-worker-c",
            reviewGeneration: 3
        )
        let committedA = try commitObserved(
            publicationA,
            in: coordinator,
            productAdmission: productAdmission.context
        )
        #expect(
            coordinator.admitDisplayInstallation(
                expectedDisplayedPublicationId: nil,
                candidatePublicationId: committedA.publicationId,
                workerInstanceId: "worker-a",
                productAdmission: productAdmission.context
            ) == .admitted
        )
        #expect(
            coordinator.recordDisplayedApplication(
                publicationId: committedA.publicationId,
                workerInstanceId: "worker-a",
                productAdmission: productAdmission.context
            ) == .advanced
        )
        let committedB = try commitObserved(
            publicationB,
            in: coordinator,
            productAdmission: productAdmission.context
        )

        // Act: a fresh empty worker may bootstrap current B while A remains acknowledged.
        let freshAdmission = coordinator.admitDisplayInstallation(
            expectedDisplayedPublicationId: nil,
            candidatePublicationId: committedB.publicationId,
            workerInstanceId: "worker-b",
            productAdmission: productAdmission.context
        )
        let committedC = try commitObserved(
            publicationC,
            in: coordinator,
            productAdmission: productAdmission.context
        )
        coordinator.retireDisplayWorker(workerInstanceId: "worker-b")
        let replacementAdmission = coordinator.admitDisplayInstallation(
            expectedDisplayedPublicationId: nil,
            candidatePublicationId: committedC.publicationId,
            workerInstanceId: "worker-c",
            productAdmission: productAdmission.context
        )

        // Assert
        #expect(freshAdmission == .admitted)
        #expect(replacementAdmission == .admitted)
        #expect(
            coordinator.diagnosticSnapshot.acknowledgedDisplayed?.publicationId
                == committedA.publicationId
        )
        #expect(coordinator.diagnosticSnapshot.admitted?.publicationId == committedC.publicationId)
    }

    @Test("display installation admits only the exact expected display and native current")
    func displayInstallationRequiresExactRegisters() async throws {
        // Arrange
        let productAdmission = try BridgeProductAdmissionTestContext.make()
        let coordinator = BridgeReviewPublicationCoordinator()
        let publicationA = try await makeReviewPreparedPublication(
            suffix: "display-admission-a",
            reviewGeneration: 1
        )
        let publicationB = try await makeReviewPreparedPublication(
            suffix: "display-admission-b",
            reviewGeneration: 2
        )
        let committedA = try commitObserved(
            publicationA,
            in: coordinator,
            productAdmission: productAdmission.context
        )

        // Act / Assert: bootstrap has no acknowledged display yet.
        #expect(
            coordinator.admitDisplayInstallation(
                expectedDisplayedPublicationId: nil,
                candidatePublicationId: committedA.publicationId,
                workerInstanceId: "worker-1",
                productAdmission: productAdmission.context
            ) == .admitted
        )
        #expect(
            coordinator.recordDisplayedApplication(
                publicationId: committedA.publicationId,
                workerInstanceId: "worker-1",
                productAdmission: productAdmission.context
            ) == .advanced
        )

        let committedB = try commitObserved(
            publicationB,
            in: coordinator,
            productAdmission: productAdmission.context
        )

        #expect(
            coordinator.admitDisplayInstallation(
                expectedDisplayedPublicationId: nil,
                candidatePublicationId: committedB.publicationId,
                workerInstanceId: "worker-1",
                productAdmission: productAdmission.context
            ) == .rejected
        )
        #expect(
            coordinator.admitDisplayInstallation(
                expectedDisplayedPublicationId: committedA.publicationId,
                candidatePublicationId: committedA.publicationId,
                workerInstanceId: "worker-1",
                productAdmission: productAdmission.context
            ) == .rejected
        )
        #expect(
            coordinator.admitDisplayInstallation(
                expectedDisplayedPublicationId: committedA.publicationId,
                candidatePublicationId: committedB.publicationId,
                workerInstanceId: "worker-1",
                productAdmission: productAdmission.context
            ) == .admitted
        )
    }

    @Test("delayed displayed application advances over retained publication after native current moves")
    func delayedDisplayedApplicationAdvancesOverRetainedPublication() async throws {
        // Arrange
        let productAdmission = try BridgeProductAdmissionTestContext.make()
        let coordinator = BridgeReviewPublicationCoordinator()
        let publicationA = try await makeReviewPreparedPublication(
            suffix: "delayed-display-a",
            reviewGeneration: 1
        )
        let publicationB = try await makeReviewPreparedPublication(
            suffix: "delayed-display-b",
            reviewGeneration: 2
        )
        let publicationC = try await makeReviewPreparedPublication(
            suffix: "delayed-display-c",
            reviewGeneration: 3
        )
        let committedA = try commitObserved(
            publicationA,
            in: coordinator,
            productAdmission: productAdmission.context
        )
        #expect(
            coordinator.admitDisplayInstallation(
                expectedDisplayedPublicationId: nil,
                candidatePublicationId: committedA.publicationId,
                workerInstanceId: "worker-1",
                productAdmission: productAdmission.context
            ) == .admitted
        )
        #expect(
            coordinator.recordDisplayedApplication(
                publicationId: committedA.publicationId,
                workerInstanceId: "worker-1",
                productAdmission: productAdmission.context
            ) == .advanced
        )
        let committedB = try commitObserved(
            publicationB,
            in: coordinator,
            productAdmission: productAdmission.context
        )
        #expect(
            coordinator.admitDisplayInstallation(
                expectedDisplayedPublicationId: committedA.publicationId,
                candidatePublicationId: committedB.publicationId,
                workerInstanceId: "worker-1",
                productAdmission: productAdmission.context
            ) == .admitted
        )
        _ = try commitObserved(
            publicationC,
            in: coordinator,
            productAdmission: productAdmission.context
        )
        let committedC = try #require(
            coordinator.committedPublicationForReplay(productAdmission: productAdmission.context)
        )

        // Act
        let unadmittedCurrentApplication = coordinator.recordDisplayedApplication(
            publicationId: committedC.publicationId,
            workerInstanceId: "worker-1",
            productAdmission: productAdmission.context
        )
        let delayedApplication = coordinator.recordDisplayedApplication(
            publicationId: committedB.publicationId,
            workerInstanceId: "worker-1",
            productAdmission: productAdmission.context
        )
        let duplicateApplication = coordinator.recordDisplayedApplication(
            publicationId: committedB.publicationId,
            workerInstanceId: "worker-1",
            productAdmission: productAdmission.context
        )
        let staleApplication = coordinator.recordDisplayedApplication(
            publicationId: committedA.publicationId,
            workerInstanceId: "worker-1",
            productAdmission: productAdmission.context
        )

        // Assert
        #expect(unadmittedCurrentApplication == .rejected)
        #expect(delayedApplication == .advanced)
        #expect(duplicateApplication == .duplicate)
        #expect(staleApplication == .rejected)
        #expect(coordinator.diagnosticSnapshot.acknowledgedDisplayed?.publicationId == committedB.publicationId)
        #expect(coordinator.diagnosticSnapshot.admitted == nil)
        #expect(coordinator.diagnosticSnapshot.active?.packageId == publicationC.package.packageId)
        #expect(coordinator.diagnosticSnapshot.retiring.map(\.packageId) == [publicationB.package.packageId])
    }

    @Test("impact lookup resolves acknowledged displayed A after native current advances to C")
    func resolvesAcknowledgedDisplayedPublicationBehindNativeCurrent() async throws {
        let coordinator = BridgeReviewPublicationCoordinator()
        let productAdmission = try BridgeProductAdmissionTestContext.make()
        let publicationA = try await makeReviewPreparedPublication(suffix: "impact-a", reviewGeneration: 1)
        let publicationB = try await makeReviewPreparedPublication(suffix: "impact-b", reviewGeneration: 2)
        let publicationC = try await makeReviewPreparedPublication(suffix: "impact-c", reviewGeneration: 3)
        let committedA = try commitObserved(
            publicationA,
            in: coordinator,
            productAdmission: productAdmission.context
        )
        #expect(
            coordinator.admitDisplayInstallation(
                expectedDisplayedPublicationId: nil,
                candidatePublicationId: committedA.publicationId,
                workerInstanceId: "worker-1",
                productAdmission: productAdmission.context
            ) == .admitted
        )
        #expect(
            coordinator.recordDisplayedApplication(
                publicationId: committedA.publicationId,
                workerInstanceId: "worker-1",
                productAdmission: productAdmission.context
            ) == .advanced
        )
        _ = try commitObserved(publicationB, in: coordinator, productAdmission: productAdmission.context)
        let committedC = try commitObserved(
            publicationC,
            in: coordinator,
            productAdmission: productAdmission.context
        )

        let displayed = coordinator.acknowledgedDisplayedPublication(
            productAdmission: productAdmission.context
        )
        let nativeCurrent = coordinator.committedPublicationForReplay(
            productAdmission: productAdmission.context
        )

        #expect(displayed?.publicationId == committedA.publicationId)
        #expect(nativeCurrent?.publicationId == committedC.publicationId)
    }

}
