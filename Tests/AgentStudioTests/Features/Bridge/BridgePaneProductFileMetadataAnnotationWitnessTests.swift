import Testing

@testable import AgentStudioBridge

@Suite("Bridge pane product File annotation source witnesses")
struct FileAnnotationSourceWitnessTests {
    @Test("annotation source requirements dispatch through the production File source witness")
    func annotationSourceRequirementsUseProductionWitness() async throws {
        // Arrange
        let fixture = try ProductFileSourceFixture(fileCount: 1)
        defer { fixture.remove() }
        let source = fixture.makeSource()
        try await source.open(
            subscription: fixture.openSnapshot(),
            productAdmission: fixture.productAdmission.context
        ) { _ in }
        let existentialSource: any BridgePaneProductFileMetadataProducing = source

        // Act
        let generation = try await existentialSource.currentWorktreeAnnotationSourceGeneration(
            productAdmission: fixture.productAdmission.context
        )
        let fingerprint = try await existentialSource.currentWorktreeAnnotationFingerprint(
            productAdmission: fixture.productAdmission.context
        )
        let refresh = try await existentialSource.currentWorktreeAnnotationRefresh(
            requirements: [],
            productAdmission: fixture.productAdmission.context
        )

        // Assert
        #expect(generation == 1)
        #expect(fingerprint == refresh.fingerprint)
        #expect(fingerprint.repositoryID == fixture.repoId.uuidString.lowercased())
        #expect(fingerprint.worktreeID == fixture.worktreeId.uuidString.lowercased())
    }
}
