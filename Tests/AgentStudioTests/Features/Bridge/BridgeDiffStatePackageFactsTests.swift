import Foundation
import Testing

@testable import AgentStudio

struct BridgeDiffStatePackageFactsTests {
    @Test("diff state stores and clears native package facts")
    @MainActor
    func diffStateStoresAndClearsNativePackageFacts() throws {
        // Arrange
        let package = try decodeBridgeReviewPackageFixture()
        let delta = BridgeReviewDelta(
            packageId: package.packageId,
            reviewGeneration: package.reviewGeneration,
            revision: package.revision + 1,
            operations: BridgeReviewDelta.Operations()
        )
        let state = DiffState()

        // Act
        state.setPackageMetadata(package)
        state.setPackageDelta(delta)

        // Assert
        #expect(state.packageMetadata == package)
        #expect(state.packageDelta == delta)

        // Act
        state.setPackageMetadata(nil)
        state.setPackageDelta(nil)

        // Assert
        #expect(state.packageMetadata == nil)
        #expect(state.packageDelta == nil)
    }
}

private func decodeBridgeReviewPackageFixture() throws -> BridgeReviewPackage {
    let projectRoot = URL(fileURLWithPath: TestPathResolver.projectRoot(from: #filePath))
    let fixtureURL = projectRoot.appending(
        path: "Tests/BridgeContractFixtures/valid/bridge-review-package.json"
    )
    return try JSONDecoder().decode(
        BridgeReviewPackage.self,
        from: Data(contentsOf: fixtureURL)
    )
}
