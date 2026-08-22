import Testing

@testable import AgentStudioBridge

@MainActor
@Suite("Bridge Review publication retention bound")
struct BridgeReviewPublicationRetentionBoundTests {
    @Test("successors retain only displayed admitted and native-current publications")
    func successorsReleaseUnprotectedIntermediatePublications() async throws {
        // Arrange
        let productAdmission = try BridgeProductAdmissionTestContext.make()
        let coordinator = BridgeReviewPublicationCoordinator()
        let publicationA = try await makeReviewPreparedPublication(
            suffix: "retention-bound-a",
            reviewGeneration: 1
        )
        let publicationB = try await makeReviewPreparedPublication(
            suffix: "retention-bound-b",
            reviewGeneration: 2
        )
        let publicationC = try await makeReviewPreparedPublication(
            suffix: "retention-bound-c",
            reviewGeneration: 3
        )
        let publicationD = try await makeReviewPreparedPublication(
            suffix: "retention-bound-d",
            reviewGeneration: 4
        )
        let committedA = try commitObserved(
            publicationA,
            in: coordinator,
            productAdmission: productAdmission.context
        )
        #expect(
            coordinator.recordDisplayedApplication(
                publicationId: committedA.publicationId,
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
                productAdmission: productAdmission.context
            ) == .admitted
        )

        // Act
        _ = try commitObserved(
            publicationC,
            in: coordinator,
            productAdmission: productAdmission.context
        )
        let committedD = try commitObserved(
            publicationD,
            in: coordinator,
            productAdmission: productAdmission.context
        )

        // Assert
        let snapshot = coordinator.diagnosticSnapshot
        #expect(snapshot.active?.publicationId == committedD.publicationId)
        #expect(snapshot.acknowledgedDisplayed?.publicationId == committedA.publicationId)
        #expect(snapshot.admitted?.publicationId == committedB.publicationId)
        #expect(
            Set(snapshot.retiring.map(\.publicationId))
                == Set([committedA.publicationId, committedB.publicationId])
        )
        #expect(snapshot.retiring.count == 2)
    }

    @Test("successor completion rejects an admission for the no-longer-current candidate")
    func successorCompletionRejectsStaleCandidateAdmission() async throws {
        // Arrange
        let productAdmission = try BridgeProductAdmissionTestContext.make()
        let coordinator = BridgeReviewPublicationCoordinator()
        let publicationA = try await makeReviewPreparedPublication(
            suffix: "stale-admission-a",
            reviewGeneration: 1
        )
        let publicationB = try await makeReviewPreparedPublication(
            suffix: "stale-admission-b",
            reviewGeneration: 2
        )
        let publicationC = try await makeReviewPreparedPublication(
            suffix: "stale-admission-c",
            reviewGeneration: 3
        )
        let committedA = try commitObserved(
            publicationA,
            in: coordinator,
            productAdmission: productAdmission.context
        )
        #expect(
            coordinator.recordDisplayedApplication(
                publicationId: committedA.publicationId,
                productAdmission: productAdmission.context
            ) == .advanced
        )
        let committedB = try commitObserved(
            publicationB,
            in: coordinator,
            productAdmission: productAdmission.context
        )
        _ = try commitObserved(
            publicationC,
            in: coordinator,
            productAdmission: productAdmission.context
        )

        // Act
        let admission = coordinator.admitDisplayInstallation(
            expectedDisplayedPublicationId: committedA.publicationId,
            candidatePublicationId: committedB.publicationId,
            productAdmission: productAdmission.context
        )

        // Assert
        #expect(admission == .rejected)
        #expect(coordinator.diagnosticSnapshot.admitted == nil)
    }
}
