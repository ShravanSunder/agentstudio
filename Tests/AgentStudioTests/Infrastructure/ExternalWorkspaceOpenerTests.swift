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
        let requests = ExternalWorkspaceOpener.preferredEditorRequests(
            path: URL(fileURLWithPath: "/tmp/project")
        )

        #expect(
            requests == [
                .application(
                    bundleIdentifier: "com.todesktop.230313mzl4w4u92",
                    targetPath: URL(fileURLWithPath: "/tmp/project")
                ),
                .command(
                    executableURL: URL(fileURLWithPath: "/usr/bin/env"),
                    arguments: ["cursor", "--reuse-window", "/tmp/project"]
                ),
                .application(
                    bundleIdentifier: "com.microsoft.VSCode",
                    targetPath: URL(fileURLWithPath: "/tmp/project")
                ),
                .command(
                    executableURL: URL(fileURLWithPath: "/usr/bin/env"),
                    arguments: ["code", "--reuse-window", "/tmp/project"]
                ),
            ])
    }

    @Test
    func openInPreferredEditor_fallsBackAcrossAppAndCliRequests() {
        let path = URL(fileURLWithPath: "/tmp/project")
        var attemptedRequests: [ExternalWorkspaceOpener.OpenRequest] = []

        let success = ExternalWorkspaceOpener.open(
            requests: ExternalWorkspaceOpener.preferredEditorRequests(path: path),
            runner: { request in
                attemptedRequests.append(request)
                if case .application(bundleIdentifier: "com.microsoft.VSCode", targetPath: path) = request {
                    return true
                }
                return false
            }
        )

        #expect(success)
        #expect(
            attemptedRequests == [
                .application(bundleIdentifier: "com.todesktop.230313mzl4w4u92", targetPath: path),
                .command(
                    executableURL: URL(fileURLWithPath: "/usr/bin/env"),
                    arguments: ["cursor", "--reuse-window", "/tmp/project"]
                ),
                .application(bundleIdentifier: "com.microsoft.VSCode", targetPath: path),
            ]
        )
    }
}
