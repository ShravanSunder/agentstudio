import Foundation
import Testing

@testable import AgentStudio

struct BridgeReviewVocabularyBoundaryTests {
    @Test("Bridge diff runtime vocabulary stays read-only")
    func bridgeDiffRuntimeVocabularyStaysReadOnly() throws {
        let projectRoot = URL(fileURLWithPath: TestPathResolver.projectRoot(from: #filePath))
        let relativeSourcePaths = [
            "Sources/AgentStudio/Core/RuntimeEventSystem/Contracts/PaneRuntimeCommand.swift",
            "Sources/AgentStudio/Core/RuntimeEventSystem/Contracts/PaneRuntimeEvent.swift",
            "Sources/AgentStudio/Core/RuntimeEventSystem/Contracts/PaneKindEvent.swift",
            "Sources/AgentStudio/Core/RuntimeEventSystem/Replay/EventReplayBuffer.swift",
            "Sources/AgentStudio/Core/RuntimeEventSystem/Diagnostics/RuntimeEnvelopeTraceSummary.swift",
            "Sources/AgentStudio/Features/Bridge/Runtime/BridgePaneController+DiffCommands.swift",
        ]
        let forbiddenTokens = [
            "approveHunk",
            "rejectHunk",
            "hunkApproved",
            "allApproved",
        ]

        for relativePath in relativeSourcePaths {
            let source = try String(
                contentsOf: projectRoot.appending(path: relativePath),
                encoding: .utf8
            )

            for forbiddenToken in forbiddenTokens {
                #expect(
                    !source.contains(forbiddenToken),
                    "\(relativePath) still contains stale Bridge review mutation token \(forbiddenToken)"
                )
            }
        }
    }
}
