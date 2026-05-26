import AppKit
import Testing

@testable import AgentStudio

@MainActor
@Suite(.serialized)
struct PathActionsTests {
    @Test("copyPath returns pasteboard write result and writes the path")
    func copyPathReturnsPasteboardWriteResultAndWritesPath() {
        let path = URL(filePath: "/tmp/agentstudio-path-actions")

        let copied = PathActions.copyPath(path)

        #expect(copied)
        #expect(NSPasteboard.general.string(forType: .string) == path.path)
    }
}
