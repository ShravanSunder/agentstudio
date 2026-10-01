import AgentStudioInfrastructure
import Foundation
import Testing

@testable import AgentStudioCore
@testable import AgentStudioTerminal

extension E2ESerializedTests.ZmxE2ETests {
    @Test(
        "a candidate runs its exact UUID as one argument inside the interactive login shell",
        arguments: ["claude-code", "codex"])
    func resumeExactSessionInsideLoginShell(providerIdentifier: String) async throws {
        try await withRealBackend { harness, _ in
            let fixture = try ResumeZmxFixture(harness: harness, providerIdentifier: providerIdentifier, exitCode: 0)
            let process = try await fixture.launch()
            do {
                let argv = try await fixture.receiveArgv()
                #expect(
                    argv == [
                        "2", providerIdentifier == "codex" ? "resume" : "--resume",
                        fixture.invocation.sessionId.rawValue,
                    ])
                #expect(try String(contentsOf: fixture.profileURL, encoding: .utf8).contains("login"))
                try await fixture.releaseResume()
                let output = try await process.expectInteractiveShell()
                #expect(try String(contentsOf: fixture.callsURL, encoding: .utf8) == "called\n")
                #expect(output.contains("Resumed"))
                try await fixture.killOwnedSession()
                try await process.stop()
            } catch {
                try? await fixture.killOwnedSession()
                try? await process.stop()
                throw error
            }
        }
    }

    @Test(
        "a failed resume shows its reason, starts the interactive shell and is never retried",
        arguments: ["claude-code", "codex"])
    func failedResumeLeavesShellWithoutRetry(providerIdentifier: String) async throws {
        try await withRealBackend { harness, _ in
            let fixture = try ResumeZmxFixture(harness: harness, providerIdentifier: providerIdentifier, exitCode: 23)
            let process = try await fixture.launch()
            do {
                let argv = try await fixture.receiveArgv()
                #expect(argv.last == fixture.invocation.sessionId.rawValue)
                try await fixture.releaseResume()
                let output = try await process.expectInteractiveShell()
                #expect(output.contains("session-no-longer-exists"))
                #expect(try String(contentsOf: fixture.callsURL, encoding: .utf8) == "called\n")
                try await fixture.killOwnedSession()
                try await process.stop()
            } catch {
                try? await fixture.killOwnedSession()
                try? await process.stop()
                throw error
            }
        }
    }
    @Test("a missing provider CLI leaves the interactive shell with the visible lookup reason")
    func missingResumeCLILeavesShell() async throws {
        try await withRealBackend { harness, _ in
            let fixture = try ResumeZmxFixture(harness: harness, providerIdentifier: "codex", exitCode: 0)
            try FileManager.default.removeItem(at: fixture.cliURL)
            let process = try await fixture.launch()
            do {
                let output = try await process.expectInteractiveShell()
                #expect(output.contains("command not found"))
                #expect(!FileManager.default.fileExists(atPath: fixture.callsURL.path))
                try await fixture.killOwnedSession()
                try await process.stop()
            } catch {
                try? await fixture.killOwnedSession()
                try? await process.stop()
                throw error
            }
        }
    }

}
