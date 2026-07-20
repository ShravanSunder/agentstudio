import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite(.serialized)
struct TerminalRestoreRuntimeTests {
    private let enabledConfiguration = SessionConfiguration(
        isEnabled: true,
        zmxPath: "/tmp/fake-zmx",
        zmxDir: "/tmp/fake-zmx-dir",
        healthCheckInterval: 30,
        maxCheckpointAge: 60
    )

    @Test("restore returns the exact stored opaque identity")
    func restoreReturnsExactStoredOpaqueIdentity() throws {
        let storedText = "as-a1b2c3d4e5f6a7b8-00112233aabbccdd-5566778899001122"
        let storedSessionID = try #require(ZmxSessionID(restoring: storedText))
        let pane = makeTerminalPane(
            sessionID: storedSessionID,
            launchDirectory: URL(filePath: "/tmp/path-must-not-determine-zmx-identity"),
            facets: PaneContextFacets(
                repoId: UUIDv7.generate(),
                worktreeId: UUIDv7.generate(),
                cwd: URL(filePath: "/tmp/current-cwd-must-not-determine-zmx-identity")
            )
        )
        let runtime = TerminalRestoreRuntime(sessionConfiguration: enabledConfiguration)

        let restoredSessionID = runtime.zmxSessionID(for: pane)

        #expect(restoredSessionID == storedSessionID)
        #expect(restoredSessionID?.rawValue == storedText)
    }

    @Test("attach command and diagnostics use the exact stored identity")
    func attachCommandAndDiagnosticsUseExactStoredIdentity() throws {
        let storedText = "550E8400-E29B-41D4-A716-446655440000"
        let storedSessionID = try #require(ZmxSessionID(restoring: storedText))
        let pane = makeTerminalPane(sessionID: storedSessionID)
        let runtime = TerminalRestoreRuntime(sessionConfiguration: enabledConfiguration)

        let attachCommand = try #require(runtime.zmxAttachCommand(for: pane))
        let diagnostics = try #require(runtime.zmxAttachDiagnostics(for: pane))

        #expect(attachCommand.contains(ZmxBackend.shellEscape(storedText)))
        #expect(diagnostics.sessionId == storedText)
        #expect(diagnostics.socketPath == "\(enabledConfiguration.zmxDir)/\(storedText)")
    }

    @Test("non-zmx terminals do not expose a restorable zmx identity")
    func nonZmxTerminalDoesNotExposeRestorableZmxIdentity() {
        let pane = makeTerminalPane(
            provider: .ghostty,
            lifetime: .temporary,
            sessionID: .generateUUIDv7()
        )
        let runtime = TerminalRestoreRuntime(sessionConfiguration: enabledConfiguration)

        #expect(runtime.zmxSessionID(for: pane) == nil)
        #expect(runtime.zmxAttachCommand(for: pane) == nil)
        #expect(runtime.zmxAttachDiagnostics(for: pane) == nil)
    }

    @Test("disabled session restoration does not build an attach command")
    func disabledSessionRestorationDoesNotBuildAttachCommand() {
        let pane = makeTerminalPane(sessionID: .generateUUIDv7())
        let runtime = TerminalRestoreRuntime(
            sessionConfiguration: SessionConfiguration(
                isEnabled: false,
                zmxPath: "/tmp/fake-zmx",
                zmxDir: "/tmp/fake-zmx-dir",
                healthCheckInterval: 30,
                maxCheckpointAge: 60
            )
        )

        #expect(runtime.zmxAttachCommand(for: pane) == nil)
        #expect(runtime.zmxAttachDiagnostics(for: pane) == nil)
    }

    private func makeTerminalPane(
        provider: SessionProvider = .zmx,
        lifetime: SessionLifetime = .persistent,
        sessionID: ZmxSessionID,
        launchDirectory: URL = URL(filePath: "/tmp"),
        facets: PaneContextFacets = PaneContextFacets()
    ) -> Pane {
        Pane(
            content: .terminal(
                TerminalState(
                    provider: provider,
                    lifetime: lifetime,
                    zmxSessionID: sessionID
                )
            ),
            metadata: PaneMetadata(
                launchDirectory: launchDirectory,
                title: "Terminal",
                facets: facets
            )
        )
    }
}
