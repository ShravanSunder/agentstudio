import AgentStudioInfrastructure
import Foundation
import Testing

@testable import AgentStudio
@testable import AgentStudioBridge
@testable import AgentStudioCore
@testable import AgentStudioTestSupport

@MainActor
@Suite("Bridge Files collection search routing", .serialized)
struct BridgeNavigationCommandHandlerSearchTests {
    init() {
        installTestCoreAtomsIfNeeded()
    }

    @Test("an unmounted receiver answers notMounted without touching navigation")
    func unmountedReceiverIsUnavailable() async throws {
        // Arrange
        let fixture = try makeFixture()
        let before = fixture.handler.record(for: fixture.receiver)

        // Act
        let search = criteria(scope: .allMembersAndOpenedDocuments)
        let outcome = await fixture.handler.searchFiles(search, in: fixture.receiver)

        // Assert
        #expect(outcome == .notMounted)
        #expect(fixture.handler.record(for: fixture.receiver) == before)
    }

    @Test("a mounted receiver relays the collection answer and leaves navigation unchanged")
    func mountedReceiverRelaysAnswer() async throws {
        // Arrange
        let fixture = try makeFixture()
        let presentation = RecordingReceiverPresentation()
        let document = try #require(fixture.loosePlan)
        let results = BridgeFilesSearchResults(
            matches: [
                BridgeFilesSearchMatch(
                    displayPath: "Open Files/plan.md",
                    location: document,
                    memberWorktreeId: nil,
                    memberRelativePath: nil
                )
            ],
            totalMatchCount: 1,
            truncated: false,
            complete: true,
            unavailableMemberWorktreeIds: []
        )
        presentation.searchOutcome = .results(results)
        fixture.install(presentation)
        let before = fixture.handler.record(for: fixture.receiver)
        let search = criteria(scope: .openedDocuments)

        // Act
        let outcome = await fixture.handler.searchFiles(search, in: fixture.receiver)

        // Assert
        #expect(outcome == .answered(.results(results)))
        #expect(presentation.searchedCriteria == [search])
        #expect(presentation.activatedLocations.isEmpty)
        #expect(presentation.requestedSurfaces.isEmpty)
        #expect(fixture.handler.record(for: fixture.receiver) == before)
        #expect(fixture.persistCount == 0)
    }

    @Test("narrowing to a worktree outside the receiver is refused before the page is asked")
    func nonMemberNarrowingIsRefused() async throws {
        // Arrange
        let fixture = try makeFixture()
        let presentation = RecordingReceiverPresentation()
        fixture.install(presentation)

        // Act
        let outcome = await fixture.handler.searchFiles(
            criteria(scope: .member(worktreeId: UUIDv7.generate())),
            in: fixture.receiver
        )

        // Assert
        #expect(outcome == .notMember)
        #expect(presentation.searchedCriteria.isEmpty)
    }

    private func criteria(scope: BridgeFilesSearchScope) -> BridgeFilesSearchCriteria {
        BridgeFilesSearchCriteria(searchText: "plan", mode: .text, scope: scope, limit: 20)
    }

    private func makeFixture() throws -> BridgeNavigationHandlerFixture {
        try BridgeNavigationHandlerFixture(
            root: FileManager.default.temporaryDirectory.appending(
                path: "bridge-navigation-search-\(UUIDv7.generate().uuidString)",
                directoryHint: .isDirectory
            )
        )
    }
}
