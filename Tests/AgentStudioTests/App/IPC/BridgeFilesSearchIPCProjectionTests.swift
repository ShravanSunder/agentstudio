import AgentStudioInfrastructure
import AgentStudioProgrammaticControl
import Foundation
import Testing

@testable import AgentStudio
@testable import AgentStudioBridge
@testable import AgentStudioCore

@Suite("bridge.files.search projection")
struct BridgeFilesSearchIPCProjectionTests {
    @Test("wire parameters become collection criteria with the same scope, mode and limit")
    func parametersBecomeCriteria() {
        // Arrange
        let worktreeId = UUIDv7.generate()
        let params = IPCBridgeFilesSearchParams(
            handle: "self",
            searchText: "\\.md$",
            searchMode: .regex,
            scope: .member,
            worktreeId: worktreeId,
            limit: 25
        )

        // Act
        let criteria = BridgeFilesSearchIPCProjection.criteria(params)

        // Assert
        #expect(
            criteria
                == BridgeFilesSearchCriteria(
                    searchText: "\\.md$",
                    mode: .regex,
                    scope: .member(worktreeId: worktreeId),
                    limit: 25
                )
        )
    }

    @Test("results carry canonical paths and member attribution; a loose document has none")
    func resultsCarryAttribution() throws {
        // Arrange
        let paneId = UUIDv7.generate()
        let memberId = UUIDv7.generate()
        let memberFile = try #require(BridgeDocumentLocation(canonicalPath: "/repo/app/src/plan.md"))
        let looseFile = try #require(BridgeDocumentLocation(canonicalPath: "/tmp/notes/plan.md"))
        let outcome = BridgeFilesSearchRequestOutcome.answered(
            .results(
                BridgeFilesSearchResults(
                    matches: [
                        BridgeFilesSearchMatch(
                            displayPath: "app/src/plan.md",
                            location: memberFile,
                            memberWorktreeId: memberId,
                            memberRelativePath: "src/plan.md"
                        ),
                        BridgeFilesSearchMatch(
                            displayPath: "Open Files/plan.md",
                            location: looseFile,
                            memberWorktreeId: nil,
                            memberRelativePath: nil
                        ),
                    ],
                    totalMatchCount: 3,
                    truncated: true,
                    complete: false,
                    unavailableMemberWorktreeIds: []
                )
            )
        )

        // Act
        let result = BridgeFilesSearchIPCProjection.result(outcome, paneId: paneId)

        // Assert
        #expect(
            result
                == IPCBridgeFilesSearchResult(
                    paneId: paneId,
                    status: .results,
                    matches: [
                        IPCBridgeFilesSearchMatch(
                            displayPath: "app/src/plan.md",
                            path: "/repo/app/src/plan.md",
                            memberWorktreeId: memberId,
                            memberRelativePath: "src/plan.md"
                        ),
                        IPCBridgeFilesSearchMatch(
                            displayPath: "Open Files/plan.md",
                            path: "/tmp/notes/plan.md",
                            memberWorktreeId: nil,
                            memberRelativePath: nil
                        ),
                    ],
                    totalMatchCount: 3,
                    truncated: true,
                    complete: false
                )
        )
    }

    @Test("every non-result outcome is a typed unavailable reason or a pattern error")
    func nonResultOutcomesAreTyped() {
        // Arrange
        let paneId = UUIDv7.generate()
        let cases: [(BridgeFilesSearchRequestOutcome, IPCBridgeFilesSearchUnavailableReason)] = [
            (.notMounted, .notMounted),
            (.receiverUnavailable, .receiverUnavailable),
            (.notMember, .notMember),
            (.answered(.unavailable(.noLivePage)), .noLivePage),
            (.answered(.unavailable(.sourceChanged)), .sourceChanged),
            (.answered(.unavailable(.cancelled)), .cancelled),
            (.answered(.unavailable(.failed)), .failed),
        ]

        // Act / Assert
        for (outcome, reason) in cases {
            #expect(
                BridgeFilesSearchIPCProjection.result(outcome, paneId: paneId)
                    == IPCBridgeFilesSearchResult(paneId: paneId, status: .unavailable, reason: reason)
            )
        }
        #expect(
            BridgeFilesSearchIPCProjection.result(.answered(.invalidPattern("Invalid regex")), paneId: paneId)
                == IPCBridgeFilesSearchResult(paneId: paneId, status: .invalidPattern, searchError: "Invalid regex")
        )
    }
}
