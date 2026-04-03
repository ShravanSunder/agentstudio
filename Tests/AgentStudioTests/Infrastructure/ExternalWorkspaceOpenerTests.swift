import Foundation
import Testing

@testable import AgentStudio

@Suite(.serialized)
struct ExternalWorkspaceOpenerTests {
    @Test
    func cursorArguments_useReuseWindowFlag() {
        let request = ExternalWorkspaceOpener.cursorCommand(
            path: URL(fileURLWithPath: "/tmp/agent studio")
        )

        #expect(request.executableURL == URL(fileURLWithPath: "/usr/bin/env"))
        #expect(request.arguments == ["cursor", "--reuse-window", "/tmp/agent studio"])
    }
}
