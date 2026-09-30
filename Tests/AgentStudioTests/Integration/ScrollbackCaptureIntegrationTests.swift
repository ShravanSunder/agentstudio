import AgentStudioInfrastructure
import AgentStudioTestHarness
import AgentStudioTestSupport
import Darwin
import Foundation
import Testing

@testable import AgentStudioCore

extension E2ESerializedTests {
    @Suite("ScrollbackCaptureIntegrationTests", .serialized)
    struct ScrollbackCaptureIntegrationTests {
        private enum RendezvousFact: Sendable, Equatable {
            case held
        }

        @Test("raw subprocess capture preserves bytes and passes exact history arguments and ZMX_DIR")
        func subprocessCapturePreservesBytesAndArguments() async throws {
            try await withFixture { root in
                let sessionID = ZmxSessionID.generateUUIDv7()
                let bytes = Data([0x20, 0x09, 0x1B, 0x5B, 0x33, 0x31, 0x6D, 0x00, 0xFF, 0x0A, 0x20])
                let payload = root.appending(path: "payload")
                try bytes.write(to: payload)
                let executable = try makeExecutable(
                    root: root,
                    body: """
                        [ "$1" = history ] && [ "$2" = '\(sessionID.rawValue)' ] && [ "$3" = --vt ] || exit 23
                        [ "$ZMX_DIR" = \(ZmxBackend.shellEscape(root.path)) ] || exit 24
                        exec /bin/cat \(ZmxBackend.shellEscape(payload.path))
                        """)
                let backend = ZmxBackend(zmxPath: executable.path, zmxDir: root.path)
                #expect(await backend.captureHistory(sessionID) == .accepted(bytes))
            }
        }

        @Test("successful byte-empty subprocess is empty")
        func byteEmptySubprocessIsEmpty() async throws {
            try await withFixture { root in
                let executable = try makeExecutable(root: root, body: "exit 0")
                let backend = ZmxBackend(zmxPath: executable.path, zmxDir: root.path)
                #expect(await backend.captureHistory(.generateUUIDv7()) == .empty)
            }
        }

        @Test("nonzero subprocess cannot replace a snapshot with partial stdout")
        func nonzeroSubprocessRejectsPartialOutput() async throws {
            try await withFixture { root in
                let executable = try makeExecutable(root: root, body: "printf partial; exit 19")
                let backend = ZmxBackend(zmxPath: executable.path, zmxDir: root.path)
                #expect(await backend.captureHistory(.generateUUIDv7()) == .exitedNonZero(19))
            }
        }

        @Test("missing executable reports launch errno")
        func missingExecutableReportsLaunchFailure() async throws {
            try await withFixture { root in
                let backend = ZmxBackend(zmxPath: root.appending(path: "absent-zmx").path, zmxDir: root.path)
                #expect(await backend.captureHistory(.generateUUIDv7()) == .launchFailed(errno: ENOENT))
            }
        }

        @Test("byte ceiling rejects oversized stdout without accepting its prefix")
        func byteCeilingRejectsOversizedOutput() async throws {
            try await withFixture { root in
                let executable = try makeExecutable(root: root, body: "printf 123456789")
                let backend = ZmxBackend(zmxPath: executable.path, zmxDir: root.path)
                let result = await backend.captureHistory(.generateUUIDv7(), byteCeiling: 8)
                #expect(result == .exceededCeiling)
            }
        }

        @Test("the capture owns its absolute deadline while the executable is held on a FIFO")
        func ownDeadlineExpiresWhileExecutableIsHeld() async throws {
            try await withFixture { root in
                let fifo = root.appending(path: "hold")
                try #require(mkfifo(fifo.path, 0o600) == 0)
                // A shell builtin reads the FIFO: no descendant remains alive
                // after the capture cancels and reaps its child.
                let executable = try makeExecutable(
                    root: root, body: "read held < \(ZmxBackend.shellEscape(fifo.path)); exit 0")
                let backend = ZmxBackend(zmxPath: executable.path, zmxDir: root.path)
                let clock = AgentStudioTestSupport.TestPushClock()
                let source = LocalFactSource<String, RendezvousFact>(
                    vocabulary: FactVocabulary(
                        describeScope: { $0 }, describeFact: { String(describing: $0) },
                        isClosing: { _, _ in false }))
                let recorder = try source.attach()
                let capture = Task {
                    await backend.captureHistory(.generateUUIDv7(), clock: clock, deadline: .seconds(2))
                }
                let rendezvous = Task {
                    try await withoutBlockingCooperativePool {
                        let descriptor = open(fifo.path, O_WRONLY)
                        guard descriptor >= 0 else { throw POSIXError(.EIO) }
                        source.sink("capture", .held)
                        return descriptor
                    }
                }
                let descriptor = try await rendezvous.value
                defer { _ = close(descriptor) }
                try await recorder.expectNext(in: "capture", .held)
                await clock.waitForPendingSleepCount(atLeast: 1)
                clock.advance(by: .seconds(2))
                #expect(await capture.value == .deadlineExceeded)
                try await recorder.finish()
                #expect(clock.pendingSleepCount == 0)
            }
        }

        @Test("a real unknown zmx session exits nonzero")
        func unknownRealSessionExitsNonzero() async throws {
            try await withRealBackend { _, backend in
                guard case .exitedNonZero = await backend.captureHistory(.generateUUIDv7()) else {
                    Issue.record("an unknown real session must not yield an accepted snapshot")
                    return
                }
            }
        }

        @Test("real unchanged blank-session history matches untrimmed VT stdout byte for byte")
        func realUnchangedHistoryMatchesRawVTOutput() async throws {
            try await withRealBackend { harness, backend in
                let sessionID = ZmxSessionID.generateUUIDv7()
                let zmxPath = try #require(harness.zmxPath)
                let fifo = URL(fileURLWithPath: harness.zmxDir).appending(path: "blank-hold")
                try #require(mkfifo(fifo.path, 0o600) == 0)
                _ = try await harness.spawnZmxSession(
                    zmxPath: zmxPath, sessionId: sessionID.rawValue,
                    commandArgs: ["/bin/sh", "-c", "read held < \(ZmxBackend.shellEscape(fifo.path))"])
                let descriptor = try await withoutBlockingCooperativePool {
                    let descriptor = open(fifo.path, O_WRONLY)
                    guard descriptor >= 0 else { throw POSIXError(.EIO) }
                    return descriptor
                }
                defer { _ = close(descriptor) }
                let output = try await runProcessToExit(
                    executableURL: URL(fileURLWithPath: zmxPath), arguments: ["history", sessionID.rawValue, "--vt"],
                    environment: ProcessInfo.processInfo.environment.merging(["ZMX_DIR": harness.zmxDir]) { _, new in
                        new
                    })
                try #require(output.terminationStatus == 0)
                let expected: ScrollbackCaptureResult =
                    output.standardOutput.isEmpty ? .empty : .accepted(output.standardOutput)
                #expect(await backend.captureHistory(sessionID) == expected)
                #expect(await backend.captureHistory(sessionID) == expected, "unchanged VT output must be byte-stable")
            }
        }

        private func withFixture(_ body: (URL) async throws -> Void) async throws {
            let root = FileManager.default.temporaryDirectory.appending(
                path: "scrollback-capture-\(UUIDv7.generate().uuidString)")
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: root) }
            try await body(root)
        }

        private func makeExecutable(root: URL, body: String) throws -> URL {
            let executable = root.appending(path: "capture-zmx")
            try ("#!/bin/sh\n" + body + "\n").write(to: executable, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
            return executable
        }

        private func withRealBackend(_ body: (ZmxTestHarness, ZmxBackend) async throws -> Void) async throws {
            let harness = await ZmxTestHarness()
            let backend = try #require(harness.createBackend(), "real zmx executable required")
            var bodyError: (any Error)?
            do { try await body(harness, backend) } catch { bodyError = error }
            let cleanup = await harness.cleanup()
            if !cleanup.succeeded { Issue.record("isolated zmx cleanup failed: \(cleanup.diagnostics)") }
            if let bodyError { throw bodyError }
            try #require(cleanup.succeeded)
        }
    }
}
