import AgentStudioInfrastructure
import AgentStudioTestSupport
import Darwin
import Foundation
import Testing

@testable import AgentStudioCore
@testable import AgentStudioTerminal

extension E2ESerializedTests.ScrollbackCaptureIntegrationTests {
    @Test("prompt observation completes from a short chunk while its writer remains open")
    func replayPromptDoesNotRequireAFullReadBuffer() async throws {
        let pipe = Pipe()
        defer {
            try? pipe.fileHandleForReading.close()
            try? pipe.fileHandleForWriting.close()
        }
        let prompt = "short-prompt> "
        try await withoutBlockingCooperativePool {
            try pipe.fileHandleForWriting.write(contentsOf: Data(prompt.utf8))
        }
        // No EOF and far fewer than 1024 bytes. A length-filling read cannot
        // settle this assertion; a delivered-byte read can observe the marker.
        let observed = try await awaitReplayPrompt(pipe: pipe, prompt: prompt)
        #expect(observed.range(of: Data(prompt.utf8))?.count == prompt.utf8.count)
    }

    @Test("EOF before the prompt ends the observation with its named failure")
    func replayPromptEOFIsTerminal() async throws {
        let pipe = Pipe()
        defer { try? pipe.fileHandleForReading.close() }
        try pipe.fileHandleForWriting.close()
        do {
            let prompt = "missing-prompt> "
            let observed = try await awaitReplayPrompt(pipe: pipe, prompt: prompt)
            #expect(observed.range(of: Data(prompt.utf8))?.count == prompt.utf8.count)
            Issue.record("EOF must not count as a login-shell prompt")
        } catch let failure as ReplayPromptFailure {
            #expect(failure == .outputEndedBeforePrompt)
        }
    }

    @Test("the script preserves composed folder notices before replay and the fresh shell")
    func composedNoticePrecedesReplayAndShell() throws {
        let snapshotURL = URL(fileURLWithPath: "/tmp/scrollback replay's output.vt")
        let savedNotice = "Restored after restart\nno saved output\nresume outcome"
        let fallbackNotice =
            """
            Restored after restart (saved folder missing; using the repository's main folder)
            no saved output
            resume outcome
            """
        let plan = TerminalColdRestorePlan(
            zmxExecutable: URL(fileURLWithPath: "/usr/local/bin/zmx"),
            zmxDirectory: URL(fileURLWithPath: "/tmp/zmx-dir"),
            sessionID: .generateUUIDv7(), loginShell: URL(fileURLWithPath: "/bin/zsh"),
            folderCandidates: [
                URL(fileURLWithPath: "/tmp/saved-folder"), URL(fileURLWithPath: "/tmp/repository-main-folder"),
            ],
            notice: ColdRestoreNotice(linesByCandidateIndex: [savedNotice, fallbackNotice]), replayFile: snapshotURL,
            resume: nil, attemptID: .generate())
        let script = ZmxBackend.coldRestoreScript(for: plan)
        let notice = try #require(script.range(of: "echo \(ZmxBackend.shellEscape(fallbackNotice))"))
        let replay = try #require(script.range(of: "cat \(ZmxBackend.shellEscape(snapshotURL.path)) 2>/dev/null"))
        let marker = try #require(script.range(of: "echo \(ZmxBackend.shellEscape("--- restored after restart ---"))"))
        let shell = try #require(script.range(of: "exec \(ZmxBackend.shellEscape("/bin/zsh")) -i -l"))
        #expect(script.contains("echo \(ZmxBackend.shellEscape(savedNotice))"))
        #expect(notice.lowerBound < replay.lowerBound)
        #expect(replay.lowerBound < marker.lowerBound)
        #expect(marker.lowerBound < shell.lowerBound)
    }

    @Test("cold restore replays output before the restart marker and a real login shell prompt")
    func coldRestoreReplaysThenMarksThenPrompts() async throws {
        try await withReplayStore { store in
            let pane = makeReplayPane()
            let text = "saved-before-restart-\(UUIDv7.generate().uuidString)"
            _ = try await store.store(paneId: PaneId(existingUUID: pane.id), capture: Data("  \(text)\r\n".utf8))
            let history = try await restoredHistory(pane: pane, store: store, requireReplay: true)
            try assertReplayOrdering(history.bytes, savedText: text, prompt: history.prompt)
        }
    }

    @Test("replayed text becomes real daemon history and survives a second cold restore")
    func replayBecomesTheNextSavedHistory() async throws {
        try await withReplayStore { store in
            let pane = makeReplayPane()
            let paneID = PaneId(existingUUID: pane.id)
            let text = "survives-two-restarts-\(UUIDv7.generate().uuidString)"
            _ = try await store.store(paneId: paneID, capture: Data("\(text)\r\n".utf8))
            let first = try await restoredHistory(pane: pane, store: store, requireReplay: true)
            try assertReplayOrdering(first.bytes, savedText: text, prompt: first.prompt)
            _ = try await store.store(paneId: paneID, capture: first.bytes)
            // The first fixture fully kills/joins its daemon before another
            // isolated directory recreates this same durable session id.
            let second = try await restoredHistory(pane: pane, store: store, requireReplay: true)
            #expect(second.bytes.range(of: Data(text.utf8))?.count == text.utf8.count)
            #expect(second.bytes.range(of: Data(first.prompt.utf8))?.count == first.prompt.utf8.count)
            #expect(second.bytes.range(of: Data(second.prompt.utf8))?.count == second.prompt.utf8.count)
        }
    }

    @Test("invalid saved bytes never enter the new daemon and the notice explains why")
    func invalidSnapshotIsNotReplayed() async throws {
        try await withReplayStore { store in
            let pane = makeReplayPane()
            let secret = "invalid-snapshot-content-\(UUIDv7.generate().uuidString)"
            let snapshotURL = store.snapshotURL(for: PaneId(existingUUID: pane.id))
            try await withoutBlockingCooperativePool {
                try FileManager.default.createDirectory(
                    at: snapshotURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                try (Data([0xFF]) + Data(secret.utf8)).write(to: snapshotURL)
            }
            let history = try await restoredHistory(pane: pane, store: store, requireReplay: false)
            #expect(history.bytes.range(of: Data(secret.utf8))?.count != secret.utf8.count)
            #expect(history.bytes.range(of: Data("no saved output".utf8))?.count == "no saved output".utf8.count)
            #expect(history.bytes.range(of: Data(history.prompt.utf8))?.count == history.prompt.utf8.count)
        }
    }

    private func makeReplayPane() -> Pane {
        Pane(
            id: UUIDv7.generate(),
            content: .terminal(TerminalState(provider: .zmx, lifetime: .persistent, zmxSessionID: .generateUUIDv7())),
            metadata: PaneMetadata(launchDirectory: FileManager.default.temporaryDirectory, title: "Replay journey"))
    }

    private func restoredHistory(pane: Pane, store: ScrollbackStore, requireReplay: Bool) async throws -> (
        bytes: Data, prompt: String
    ) {
        let harness = await ZmxTestHarness()
        let pipe = Pipe()
        var result: (bytes: Data, prompt: String)?
        var bodyError: (any Error)?
        do {
            let zmxPath = try #require(harness.zmxPath)
            let sessionID = try #require(pane.terminalState?.zmxSessionID)
            let root = URL(fileURLWithPath: harness.zmxDir)
            let loginShell = root.appending(path: "replay-login-shell")
            let prompt = "replay-prompt-\(UUIDv7.generate().uuidString)> "
            let shellScript = """
                #!/bin/sh
                export PS1=\(ZmxBackend.shellEscape(prompt))
                exec /bin/bash --noprofile --norc "$@"
                """
            try await withoutBlockingCooperativePool {
                try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
                try Data(shellScript.utf8).write(to: loginShell)
                try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: loginShell.path)
            }
            let plan = await TerminalColdRestorePlanBuilder.buildPlan(
                pane: pane, sessionID: sessionID,
                launchPaths: TerminalColdRestoreLaunchPaths(
                    zmxExecutablePath: zmxPath, zmxDirectoryPath: harness.zmxDir, loginShellPath: loginShell.path),
                repositoryMainFolder: nil, scrollbackStore: store)
            if requireReplay {
                try #require(
                    plan.replayFile == store.snapshotURL(for: PaneId(existingUUID: pane.id)),
                    "validated replay path must be installed")
            } else {
                try #require(plan.replayFile == nil)
                try #require(plan.notice.linesByCandidateIndex.allSatisfy { $0.contains("no saved output") })
            }
            // The actual script used by buildColdRestoreCommand; the existing
            // harness owns the attach child and its daemon's complete teardown.
            _ = try await harness.spawnZmxSession(
                zmxPath: zmxPath, sessionId: sessionID.rawValue,
                commandArgs: ["/bin/sh", "-c", ZmxBackend.coldRestoreScript(for: plan), plan.attemptID.startupToken],
                standardOutput: pipe.fileHandleForWriting)
            // Process.run has duplicated the writer into the attach child.
            // Keeping our writer open would hide EOF if that child exits.
            try pipe.fileHandleForWriting.close()
            let observed = try await awaitReplayPrompt(pipe: pipe, prompt: prompt)
            #expect(observed.range(of: Data(prompt.utf8))?.count == prompt.utf8.count)
            let output = try await runProcessToExit(
                executableURL: URL(fileURLWithPath: zmxPath),
                arguments: ["history", sessionID.rawValue, "--vt"],
                environment: ProcessInfo.processInfo.environment.merging(["ZMX_DIR": harness.zmxDir]) { _, new in new })
            try #require(output.terminationStatus == 0)
            result = (output.standardOutput, prompt)
        } catch { bodyError = error }
        let cleanup = await harness.cleanup()
        try? pipe.fileHandleForReading.close()
        try? pipe.fileHandleForWriting.close()
        if !cleanup.succeeded { Issue.record("replay fixture cleanup failed: \(cleanup.diagnostics)") }
        if let bodyError { throw bodyError }
        try #require(cleanup.succeeded)
        return try #require(result)
    }

    private func awaitReplayPrompt(pipe: Pipe, prompt: String) async throws -> Data {
        try await withoutBlockingCooperativePool {
            let marker = Data(prompt.utf8)
            let descriptor = pipe.fileHandleForReading.fileDescriptor
            var bytes = Data()
            var chunk = [UInt8](repeating: 0, count: 1024)
            while true {
                if let range = bytes.range(of: marker), range.count == marker.count {
                    return Data(bytes.prefix(upTo: range.upperBound))
                }
                // FileHandle's macOS length-based read can wait for a full
                // chunk even when the prompt is already in that chunk.
                // POSIX read returns the bytes currently delivered by the
                // pipe; zero is the attach writer's terminal EOF event.
                let count = chunk.withUnsafeMutableBytes {
                    Darwin.read(descriptor, $0.baseAddress, $0.count)
                }
                if count < 0, errno == EINTR { continue }
                guard count >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
                guard count > 0 else { throw ReplayPromptFailure.outputEndedBeforePrompt }
                bytes.append(contentsOf: chunk.prefix(count))
                guard bytes.count <= AppPolicies.Restore.captureByteCeiling else { throw POSIXError(.EOVERFLOW) }
            }
        }
    }

    private enum ReplayPromptFailure: Error, Equatable, CustomStringConvertible {
        case outputEndedBeforePrompt

        var description: String { "Replay attach output ended before the fresh login-shell prompt arrived" }
    }

    private func assertReplayOrdering(_ bytes: Data, savedText: String, prompt: String) throws {
        let saved = try #require(bytes.range(of: Data(savedText.utf8)), "saved output must be replayed")
        let marker = try #require(
            bytes.range(of: Data("--- restored after restart ---".utf8)), "restart marker must be present")
        let shellPrompt = try #require(bytes.range(of: Data(prompt.utf8)), "real fresh shell must publish its prompt")
        #expect(saved.lowerBound < marker.lowerBound)
        #expect(marker.lowerBound < shellPrompt.lowerBound)
    }

    private func withReplayStore(_ body: (ScrollbackStore) async throws -> Void) async throws {
        let root = FileManager.default.temporaryDirectory.appending(
            path: "scrollback-replay-zmx-\(UUIDv7.generate().uuidString)")
        let store = ScrollbackStore(directoryURL: root)
        var bodyError: (any Error)?
        do { try await body(store) } catch { bodyError = error }
        try await withoutBlockingCooperativePool {
            if FileManager.default.fileExists(atPath: root.path) { try FileManager.default.removeItem(at: root) }
        }
        if let bodyError { throw bodyError }
    }
}
