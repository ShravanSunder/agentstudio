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

    @Test
    func vscodeArguments_useReuseWindowFlag() {
        let request = ExternalWorkspaceOpener.vscodeCommand(
            path: URL(fileURLWithPath: "/tmp/agent studio")
        )

        #expect(request.executableURL == URL(fileURLWithPath: "/usr/bin/env"))
        #expect(request.arguments == ["code", "--reuse-window", "/tmp/agent studio"])
    }

    @Test
    func preferredEditorRequests_tryCursorThenVSCode() {
        let requests = ExternalWorkspaceOpener.preferredEditorCommands(
            path: URL(fileURLWithPath: "/tmp/project")
        )

        #expect(
            requests == [
                ExternalWorkspaceOpener.CommandRequest(
                    executableURL: URL(fileURLWithPath: "/usr/bin/env"),
                    arguments: ["cursor", "--reuse-window", "/tmp/project"]
                ),
                ExternalWorkspaceOpener.CommandRequest(
                    executableURL: URL(fileURLWithPath: "/usr/bin/env"),
                    arguments: ["code", "--reuse-window", "/tmp/project"]
                ),
            ])
    }

    @Test
    func openInPreferredEditor_fallsBackToVSCodeWhenCursorFails() {
        let path = URL(fileURLWithPath: "/tmp/project")
        var attemptedRequests: [ExternalWorkspaceOpener.CommandRequest] = []

        let success = ExternalWorkspaceOpener.open(
            commands: ExternalWorkspaceOpener.preferredEditorCommands(path: path),
            runner: { request in
                attemptedRequests.append(request)
                return request.arguments.first == "code"
            }
        )

        #expect(success)
        #expect(attemptedRequests.map(\.arguments.first) == ["cursor", "code"])
    }
}
