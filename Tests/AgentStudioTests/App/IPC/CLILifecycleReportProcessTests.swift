import AgentStudioPrimitives
import AgentStudioSessions
import AgentStudioTerminal
import AgentStudioTestHarness
import AgentStudioTestSupport
import Foundation
import Testing

@testable import AgentStudio
@testable import AgentStudioCLIStore
@testable import AgentStudioCore

@Suite("CLI lifecycle real process order")
struct CLILifecycleReportProcessTests {
    @Test("three real CLI processes commit in recorded order even when the first hook is held before its write")
    func latchedFirstWriterIsOvertaken() async throws {
        let fixture = try LifecycleProcessStoreFixture()
        defer { fixture.remove() }
        _ = try await valueFromDedicatedThread { try fixture.writer() }
        let executable = try fixture.processExecutableURL()
        let paneID = UUIDv7.generate()
        let sessions = (0..<3).map { _ in UUIDv7.generate().uuidString }
        let held = try launchLifecycleHook(
            fixture: fixture, executable: executable, paneID: paneID, provider: "codex", event: "SessionStart")
        do {
            #expect(try await held.expectPrecommitHold() == "ready\n")
            // Both later invocations complete before the first is released.
            let second = try await runLifecycleHook(
                fixture: fixture, executable: executable, paneID: paneID, sessionID: sessions[1])
            let third = try await runLifecycleHook(
                fixture: fixture, executable: executable, paneID: paneID, sessionID: sessions[2])
            #expect(second.status == 0, "\(second.text)")
            #expect(third.status == 0, "\(third.text)")
            try await held.releasePrecommitHold(
                payload: lifecycleHookPayload(sessionID: sessions[0], event: "SessionStart"))
            let first = try await held.finish()
            #expect(first.status == 0, "\(first.text)")
            let reports = try await valueFromDedicatedThread {
                try fixture.reader().readLifecycleReports(after: 0).get().reports
            }
            #expect(reports.map { $0.record.conversationID } == [sessions[1], sessions[2], sessions[0]])
            #expect(reports.map { $0.sequence } == [1, 2, 3])
            #expect(Set(reports.map { $0.record.reportID }).count == 3)
        } catch {
            await held.stop()
            throw error
        }
    }

    @Test("several independent CLI processes write one file and every successful receipt has its immutable row")
    func independentWriterReceiptsMatchRows() async throws {
        let fixture = try LifecycleProcessStoreFixture()
        defer { fixture.remove() }
        _ = try await valueFromDedicatedThread { try fixture.writer() }
        let executable = try fixture.processExecutableURL()
        let paneID = UUIDv7.generate()
        let sessionID = UUIDv7.generate().uuidString
        for provider in ["codex", "claude"] {
            for event in ["SessionStart", "SessionEnd"] {
                let output = try await runLifecycleHook(
                    fixture: fixture, executable: executable, paneID: paneID, sessionID: sessionID,
                    provider: provider, event: event)
                #expect(output.status == 0, "\(output.text)")
            }
        }
        let rows = try await valueFromDedicatedThread {
            try fixture.reader().readLifecycleReports(after: 0).get().reports
        }
        #expect(rows.map { $0.sequence } == [1, 2, 3, 4])
        #expect(rows.map { $0.record.providerIdentifier } == ["codex", "codex", "claude-code", "claude-code"])
        #expect(
            rows.map { $0.record.event } == [
                .sessionStart, .sessionEnd(reason: "exit"), .sessionStart, .sessionEnd(reason: "exit"),
            ])
        #expect(Set(rows.map { $0.record.reportID }).count == 4)
    }

    @Test("a real hook held before commit across readiness is live later and cannot revise the decided cold plan")
    func realHookHeldAcrossReadiness() async throws {
        try await withLifecycleIntakeFixture { fixture in
            let old = fixture.record()
            _ = try await fixture.adapter().recordProviderEvent(
                paneId: fixture.paneID, params: fixture.params(old), provenance: .matchingPane)
            let cliFixture = LifecycleProcessStoreFixture(rootURL: fixture.rootURL, databaseURL: fixture.storeURL)
            let executable = try cliFixture.processExecutableURL()
            let child = try launchLifecycleHook(
                fixture: cliFixture, executable: executable, paneID: fixture.paneID, provider: "codex",
                event: "SessionStart")
            let readiness = RestoreResumeReadiness(
                clock: TestPushClock(), deadline: .seconds(2), launchId: UUIDv7.generate(), factSink: { _, _ in })
            do {
                _ = try await child.expectPrecommitHold()
                let intake = fixture.intake()
                await AppIPCDeferredInitialization.prepareResumeReadiness(
                    readiness: readiness, intake: intake,
                    prepareForLaunch: { _ = try await fixture.ingestion.prepareForLaunch(at: fixture.now) })
                #expect(await readiness.wait(paneId: fixture.paneID) == .ready)
                let decided = try await fixture.sameProviderLookVerdict()
                let oldSession = try ProviderSessionId(rawValue: old.conversationID)
                #expect(decided == .interruptedCandidate(.init(provider: .codex, sessionId: oldSession)))
                let base = TerminalColdRestorePlan(
                    zmxExecutable: URL(fileURLWithPath: "/fixture/zmx"), zmxDirectory: fixture.rootURL,
                    sessionID: .generateUUIDv7(), loginShell: URL(fileURLWithPath: "/bin/zsh"),
                    folderCandidates: [fixture.rootURL], notice: .init(linesByCandidateIndex: [""]),
                    replayFile: nil, resume: nil, attemptID: .generate())
                let coldPlan = TerminalColdRestorePlanBuilder.applyingResumeEvidence(
                    decided, providerIdentifier: old.providerIdentifier, providerSessionId: old.conversationID, to: base
                )
                #expect(coldPlan.resume == .init(provider: .codex, sessionId: oldSession))
                let laterSession = UUIDv7.generate().uuidString
                try await child.releasePrecommitHold(
                    payload: lifecycleHookPayload(sessionID: laterSession, event: "SessionStart"))
                let output = try await child.finish()
                #expect(output.status == 0, "\(output.text)")
                let rows = try await valueFromDedicatedThread {
                    try cliFixture.reader().readLifecycleReports(after: 0).get().reports
                }
                let row = try #require(rows.first)
                #expect(rows.count == 1)
                try await intake.takeIn(through: .stored(storeId: fixture.storeID, sequence: row.sequence))
                let fetched = try await fixture.binding()
                #expect(fetched?.providerConversationId == laterSession)
                #expect(fetched?.startedFromHistoricalReport == false)
                #expect(await readiness.wait(paneId: fixture.paneID) == .ready)
                #expect(decided == .interruptedCandidate(.init(provider: .codex, sessionId: oldSession)))
                #expect(coldPlan.resume == .init(provider: .codex, sessionId: oldSession))
                await readiness.shutdown()
            } catch {
                await readiness.shutdown()
                await child.stop()
                throw error
            }
        }
    }
}

private struct LifecycleProcessStoreFixture: Sendable {
    let rootURL: URL
    let databaseURL: URL
    init() throws {
        rootURL = FileManager.default.temporaryDirectory.appending(path: "lifecycle-process-\(UUIDv7.generate())")
        databaseURL = rootURL.appending(path: "cli.sqlite")
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
    }
    init(rootURL: URL, databaseURL: URL) {
        self.rootURL = rootURL
        self.databaseURL = databaseURL
    }
    func writer() throws -> CLIStore { try CLIStore.openWriter(url: databaseURL, channel: .debug).get() }
    func reader() throws -> CLIStore { try CLIStore.openReader(url: databaseURL, expectedChannel: .debug).get() }
    func remove() { try? FileManager.default.removeItem(at: rootURL) }
    func processExecutableURL() throws -> URL {
        guard let buildDirectory = ProcessInfo.processInfo.environment["SWIFT_BUILD_DIR"] else {
            throw LifecycleProcessFixtureFailure.buildDirectoryMissing
        }
        let projectRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let buildURL =
            buildDirectory.hasPrefix("/")
            ? URL(fileURLWithPath: buildDirectory) : projectRoot.appending(path: buildDirectory)
        return buildURL.appending(path: "debug/agentstudio-cli")
    }
}

private func launchLifecycleHook(
    fixture: LifecycleProcessStoreFixture, executable: URL, paneID: UUID, provider: String, event: String
) throws -> CLILifecycleWriterProcess {
    // This wrapper announces entry before exec; the real hook then blocks on
    // its normal stdin read until the test closes the payload pipe.
    try CLILifecycleWriterProcess(
        executable: URL(fileURLWithPath: "/bin/sh"),
        arguments: [
            "-c", "printf 'ready\\n'; exec \"$@\"", "lifecycle-hook", executable.path, "hook", provider, event,
        ],
        environment: [
            "AGENTSTUDIO_CLI_STORE": fixture.databaseURL.path, "AGENTSTUDIO_CLI_STORE_CHANNEL": "debug",
            "AGENTSTUDIO_PANE_ID": paneID.uuidString, "AGENTSTUDIO_PANE_TOKEN": "test-pane-token",
            "AGENTSTUDIO_IPC_SOCKET": fixture.rootURL.appending(path: "missing.sock").path,
            "AGENTSTUDIO_CLI": executable.path,
        ])
}

private func lifecycleHookPayload(sessionID: String, event: String) -> Data {
    Data("{\"session_id\":\"\(sessionID)\",\"hook_event_name\":\"\(event)\",\"reason\":\"exit\"}".utf8)
}

private func runLifecycleHook(
    fixture: LifecycleProcessStoreFixture, executable: URL, paneID: UUID, sessionID: String,
    provider: String = "codex", event: String = "SessionStart"
) async throws -> CLILifecycleWriterProcess.Output {
    let child = try launchLifecycleHook(
        fixture: fixture, executable: executable, paneID: paneID, provider: provider, event: event)
    do {
        _ = try await child.expectPrecommitHold()
        try await child.releasePrecommitHold(payload: lifecycleHookPayload(sessionID: sessionID, event: event))
        return try await child.finish()
    } catch {
        await child.stop()
        throw error
    }
}
