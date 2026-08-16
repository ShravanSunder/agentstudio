import Foundation
import Testing

@testable import AgentStudioBridge
@testable import AgentStudioBridgeDevelopmentServer

@Suite("Bridge development worktree annotation output effect")
struct BridgeDevelopmentAnnotationOutputEffectTests {
    @Test("captures clipboard Markdown and JSON under the isolated development data root")
    func capturesOutputWithoutSystemUIAuthority() async throws {
        // Arrange
        let attemptID = try #require(
            UUID(uuidString: "019fffe3-53dc-7c98-a8df-0f9521a146a1")
        )
        let dataRoot = FileManager.default.temporaryDirectory.appending(
            path: "bridge-development-annotation-output-\(attemptID.uuidString)",
            directoryHint: .isDirectory
        )
        defer { try? FileManager.default.removeItem(at: dataRoot) }
        let effect = BridgeDevelopmentWorktreeAnnotationOutputEffect(dataRoot: dataRoot)
        let markdownBytes = Data("# Review\n\nComment".utf8)
        let jsonBytes = Data(#"{"version":1}"#.utf8)

        // Act
        let clipboardOutcome = await effect.perform(
            WorktreeAnnotationOutputEffectRequest(
                attemptID: attemptID,
                outputKind: .clipboardMarkdown,
                contentType: "text/markdown; charset=utf-8",
                exactBytes: markdownBytes,
                destinationPath: nil
            )
        )
        let destinationOutcome = await effect.chooseJSONDestination(
            suggestedFilename: "review-comments.json"
        )
        let destinationPath: String
        switch destinationOutcome {
        case .selected(let path):
            destinationPath = path
        case .cancelled, .failed:
            Issue.record("Expected the development effect to select an isolated JSON path")
            return
        }
        let jsonOutcome = await effect.perform(
            WorktreeAnnotationOutputEffectRequest(
                attemptID: attemptID,
                outputKind: .jsonFile,
                contentType: "application/json",
                exactBytes: jsonBytes,
                destinationPath: destinationPath
            )
        )

        // Assert
        #expect(clipboardOutcome == .succeeded)
        #expect(jsonOutcome == .succeeded)
        #expect(
            try Data(contentsOf: effect.clipboardCaptureURL(for: attemptID)) == markdownBytes
        )
        #expect(try Data(contentsOf: URL(fileURLWithPath: destinationPath)) == jsonBytes)
        #expect(URL(fileURLWithPath: destinationPath).deletingLastPathComponent() == effect.outputDirectory)
    }

    @Test("rejects an injected JSON destination outside the isolated development output directory")
    func rejectsDestinationOutsideDataRoot() async throws {
        // Arrange
        let attemptID = try #require(
            UUID(uuidString: "019fffe3-53dc-7c98-a8df-0f9521a146a2")
        )
        let dataRoot = FileManager.default.temporaryDirectory.appending(
            path: "bridge-development-annotation-output-\(attemptID.uuidString)",
            directoryHint: .isDirectory
        )
        defer { try? FileManager.default.removeItem(at: dataRoot) }
        let effect = BridgeDevelopmentWorktreeAnnotationOutputEffect(dataRoot: dataRoot)

        // Act
        let outcome = await effect.perform(
            WorktreeAnnotationOutputEffectRequest(
                attemptID: attemptID,
                outputKind: .jsonFile,
                contentType: "application/json",
                exactBytes: Data("{}".utf8),
                destinationPath: FileManager.default.temporaryDirectory
                    .appending(path: "outside-review-comments.json")
                    .path
            )
        )

        // Assert
        guard case .failed(let message) = outcome else {
            Issue.record("Expected an out-of-root development destination to fail")
            return
        }
        #expect(message.contains("isolated development output directory"))
    }
}
