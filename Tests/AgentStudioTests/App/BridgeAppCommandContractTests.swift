import Testing

@testable import AgentStudio

@MainActor
@Suite("Bridge app command hard-cut contracts")
struct BridgeAppCommandContractTests {
    @Test("the four Bridge command identities replace the two ambiguous identities")
    func bridgeCommandIdentitiesAreHardCut() {
        // Arrange
        let expectedBridgeCommandIdentities: Set<String> = [
            "showBridgeReview",
            "showBridgeFiles",
            "openBridgeReviewInNewTab",
            "openBridgeFilesInNewTab",
        ]
        let removedBridgeCommandIdentities: Set<String> = [
            "openBridgeReview",
            "openBridgeFileView",
        ]

        // Act
        let commandIdentities = Set(AppCommand.allCases.map(\.rawValue))

        // Assert
        #expect(expectedBridgeCommandIdentities.isSubset(of: commandIdentities))
        #expect(commandIdentities.isDisjoint(with: removedBridgeCommandIdentities))
    }

    @Test("default Bridge show commands retain worktree-targeted catalog labels")
    func defaultShowCommandCatalogContracts() throws {
        // Arrange
        let showReview = try #require(AppCommand(rawValue: "showBridgeReview"))
        let showFiles = try #require(AppCommand(rawValue: "showBridgeFiles"))

        // Act
        let reviewDefinition = AppCommandDispatcher.shared.definition(for: showReview)
        let filesDefinition = AppCommandDispatcher.shared.definition(for: showFiles)

        // Assert
        #expect(reviewDefinition.label == "Review")
        #expect(filesDefinition.label == "Files")
        #expect(reviewDefinition.appliesTo == [.worktree])
        #expect(filesDefinition.appliesTo == [.worktree])
    }

    @Test("explicit duplicate Bridge commands say new tab and target worktrees")
    func explicitDuplicateCommandCatalogContracts() throws {
        // Arrange
        let openReviewInNewTab = try #require(AppCommand(rawValue: "openBridgeReviewInNewTab"))
        let openFilesInNewTab = try #require(AppCommand(rawValue: "openBridgeFilesInNewTab"))

        // Act
        let reviewDefinition = AppCommandDispatcher.shared.definition(for: openReviewInNewTab)
        let filesDefinition = AppCommandDispatcher.shared.definition(for: openFilesInNewTab)

        // Assert
        #expect(reviewDefinition.label == "Open Review in New Tab")
        #expect(filesDefinition.label == "Open Files in New Tab")
        #expect(reviewDefinition.appliesTo == [.worktree])
        #expect(filesDefinition.appliesTo == [.worktree])
    }
}
