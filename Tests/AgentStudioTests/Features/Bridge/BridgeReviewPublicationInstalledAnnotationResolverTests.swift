import Testing

@testable import AgentStudioBridge

@MainActor
@Suite("Bridge Review installed annotation resolver")
struct BridgeInstalledAnnotationResolverTests {
    @Test("exact lookup resolves acknowledged and admitted retained publications")
    func resolvesExactInstalledPublicationAcrossDelayedReceipt() async throws {
        let coordinator = BridgeReviewPublicationCoordinator()
        let productAdmission = try BridgeProductAdmissionTestContext.make()
        let publicationA = try await makeReviewPreparedPublication(suffix: "annotation-a", reviewGeneration: 1)
        let publicationB = try await makeReviewPreparedPublication(suffix: "annotation-b", reviewGeneration: 2)
        let publicationC = try await makeReviewPreparedPublication(suffix: "annotation-c", reviewGeneration: 3)
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
        _ = try commitObserved(
            publicationC,
            in: coordinator,
            productAdmission: productAdmission.context
        )
        let identityA = try annotationIdentity(committedA)
        let identityB = try annotationIdentity(committedB)
        let mismatchedB = try BridgeProductReviewAnnotationPublicationIdentity(
            packageId: identityB.packageId,
            publicationId: identityB.publicationId,
            reviewGeneration: identityB.reviewGeneration,
            revision: identityB.revision + 1,
            sourceIdentity: identityB.sourceIdentity
        )

        #expect(
            coordinator.retainedPublication(
                matching: identityA,
                productAdmission: productAdmission.context
            )?.publicationId == committedA.publicationId
        )
        #expect(
            coordinator.retainedPublication(
                matching: identityB,
                productAdmission: productAdmission.context
            )?.publicationId == committedB.publicationId
        )
        #expect(
            coordinator.retainedPublication(
                matching: mismatchedB,
                productAdmission: productAdmission.context
            ) == nil
        )

        #expect(
            coordinator.recordDisplayedApplication(
                publicationId: committedB.publicationId,
                productAdmission: productAdmission.context
            ) == .advanced
        )
        #expect(
            coordinator.retainedPublication(
                matching: identityA,
                productAdmission: productAdmission.context
            ) == nil
        )
        #expect(
            coordinator.retainedPublication(
                matching: identityB,
                productAdmission: productAdmission.context
            )?.publicationId == committedB.publicationId
        )
    }

    private func annotationIdentity(
        _ publication: BridgeReviewCommittedPublication
    ) throws -> BridgeProductReviewAnnotationPublicationIdentity {
        try BridgeProductReviewAnnotationPublicationIdentity(
            packageId: publication.package.packageId,
            publicationId: publication.publicationId,
            reviewGeneration: publication.package.reviewGeneration.rawValue,
            revision: publication.package.revision,
            sourceIdentity: publication.package.query.queryId
        )
    }
}
