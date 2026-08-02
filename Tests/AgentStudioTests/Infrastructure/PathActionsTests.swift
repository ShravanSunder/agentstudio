import AppKit
import Testing

@testable import AgentStudioInfrastructure

@MainActor
@Suite(.serialized)
struct PathActionsTests {
    @Test("copyPath returns pasteboard write result and writes the path")
    func copyPathReturnsPasteboardWriteResultAndWritesPath() {
        let path = URL(filePath: "/tmp/agentstudio-path-actions")
        let pasteboard = InMemoryPasteboard()

        let copied = PathActions.copyPath(path, to: pasteboard)

        #expect(copied)
        #expect(pasteboard.string(forType: .string) == path.path)
    }
}

@MainActor
private final class InMemoryPasteboard: PathActionsPasteboard {
    private var values: [NSPasteboard.PasteboardType: String] = [:]

    @discardableResult
    func clearContents() -> Int {
        values.removeAll()
        return values.count
    }

    @discardableResult
    func setString(_ string: String, forType type: NSPasteboard.PasteboardType) -> Bool {
        values[type] = string
        return true
    }

    func string(forType type: NSPasteboard.PasteboardType) -> String? {
        values[type]
    }
}
