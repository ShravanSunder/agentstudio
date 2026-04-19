import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite(.serialized)
struct ExternalWorkspaceOpenerTests {
    @Test
    func openInEditor_usesTargetRequests() {
        let path = URL(fileURLWithPath: "/tmp/agent studio")

        let requests = ExternalWorkspaceOpener.requests(
            for: .cursor,
            path: path
        )

        #expect(
            requests == [
                .application(
                    bundleIdentifier: ExternalEditorTarget.cursor.bundleIdentifier,
                    targetPath: path
                ),
                .command(
                    executableURL: URL(fileURLWithPath: "/usr/bin/env"),
                    arguments: ["cursor", "--reuse-window", "/tmp/agent studio"]
                ),
            ]
        )
    }

    @Test
    func requests_useExplicitBookmarkedTarget() {
        let path = URL(fileURLWithPath: "/tmp/project")
        let installedTargets: [ExternalEditorTarget] = [.windsurf, .vscode]

        let target = ExternalEditorTarget.resolveBookmarkedOrDefault(
            bookmarkedEditorId: "vscode",
            installedTargets: installedTargets
        )

        guard case .resolved(let resolvedTarget) = target else {
            Issue.record("Expected bookmarked target resolution")
            return
        }
        #expect(resolvedTarget.id == "vscode")
        #expect(
            ExternalWorkspaceOpener.requests(for: resolvedTarget, path: path) == [
                .application(
                    bundleIdentifier: ExternalEditorTarget.vscode.bundleIdentifier,
                    targetPath: path
                ),
                .command(
                    executableURL: URL(fileURLWithPath: "/usr/bin/env"),
                    arguments: ["code", "--reuse-window", "/tmp/project"],
                ),
            ]
        )
    }

    @Test
    func openInEditor_returnsFalseForUnknownTarget() {
        let success = ExternalWorkspaceOpener.openInEditor(
            id: "unknown",
            path: URL(fileURLWithPath: "/tmp/project"),
            installedTargets: [.cursor, .vscode]
        )

        #expect(!success)
    }

    @Test
    func open_requestsStopAtFirstSuccess() {
        let path = URL(fileURLWithPath: "/tmp/project")
        var attemptedRequests: [ExternalWorkspaceOpener.OpenRequest] = []

        let success = ExternalWorkspaceOpener.open(
            requests: ExternalWorkspaceOpener.requests(for: .vscode, path: path),
            runner: { request in
                attemptedRequests.append(request)
                if case .application(bundleIdentifier: ExternalEditorTarget.vscode.bundleIdentifier, targetPath: path) =
                    request
                {
                    return true
                }
                return false
            }
        )

        #expect(success)
        #expect(
            attemptedRequests == [
                .application(bundleIdentifier: ExternalEditorTarget.vscode.bundleIdentifier, targetPath: path)
            ]
        )
    }

    @Test
    func openAsync_requestsFallbackToCommandWhenApplicationFails() async {
        let path = URL(fileURLWithPath: "/tmp/project")
        var attemptedRequests: [ExternalWorkspaceOpener.OpenRequest] = []

        let success = await ExternalWorkspaceOpener.openAsync(
            requests: ExternalWorkspaceOpener.requests(for: .vscode, path: path),
            runner: { request in
                attemptedRequests.append(request)
                if case .application = request {
                    return false
                }
                return true
            }
        )

        #expect(success)
        #expect(
            attemptedRequests == [
                .application(
                    bundleIdentifier: ExternalEditorTarget.vscode.bundleIdentifier,
                    targetPath: path
                ),
                .command(
                    executableURL: URL(fileURLWithPath: "/usr/bin/env"),
                    arguments: ["code", "--reuse-window", "/tmp/project"],
                ),
            ]
        )
    }
}
