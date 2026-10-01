import AgentStudioInfrastructure
import Foundation
import Synchronization
import Testing

@testable import AgentStudioCore
@testable import AgentStudioTerminal

@Suite("Foreground probe classification")
struct ForegroundProbeClassificationTests {
    @Test("foreground group classification ignores stopped and background agents")
    func backgroundAgentDoesNotBecomeForeground() {
        let shell = foregroundTestProcess(pid: 4100)
        let samples = [
            foregroundTestSample(process: shell, group: 4100, foregroundGroup: 4100, argv0: "/bin/zsh"),
            foregroundTestSample(
                process: foregroundTestProcess(pid: 4101), group: 4101, foregroundGroup: 4100, argv0: "claude"),
        ]
        #expect(DarwinTerminalForegroundProbe.classify(leader: shell, samples: samples, complete: true) == .shell)
    }

    @Test(
        "both known binaries classify only inside tpgid",
        arguments: [("/tmp/claude", ForegroundProgram.claudeCode), ("codex", .codex)])
    func foregroundAgentsAreRecognized(argv0: String, expected: ForegroundProgram) {
        let shell = foregroundTestProcess(pid: 4100)
        let samples = [
            foregroundTestSample(process: shell, group: 4100, foregroundGroup: 4200, argv0: "/bin/zsh"),
            foregroundTestSample(
                process: foregroundTestProcess(pid: 4200), group: 4200, foregroundGroup: 4200, argv0: argv0),
        ]
        #expect(DarwinTerminalForegroundProbe.classify(leader: shell, samples: samples, complete: true) == expected)
    }

    @Test("a foreground program that is not a shell or agent is other")
    func anotherForegroundProgramIsOther() {
        let shell = foregroundTestProcess(pid: 4100)
        let samples = [
            foregroundTestSample(process: shell, group: 4100, foregroundGroup: 4200, argv0: "/bin/zsh"),
            foregroundTestSample(
                process: foregroundTestProcess(pid: 4200), group: 4200, foregroundGroup: 4200, argv0: "vim"),
        ]
        #expect(DarwinTerminalForegroundProbe.classify(leader: shell, samples: samples, complete: true) == .other)
    }

    @Test("incomplete or empty ps is unknown, never shell", arguments: [false, true])
    func incompletePassIsUnknown(empty: Bool) {
        let shell = foregroundTestProcess(pid: 4100)
        let samples =
            empty ? [] : [foregroundTestSample(process: shell, group: 4100, foregroundGroup: 4100, argv0: "/bin/zsh")]
        #expect(DarwinTerminalForegroundProbe.classify(leader: shell, samples: samples, complete: empty) == .unknown)
    }

    @Test("one ps pass serves every requested pane and retains only typed process identity")
    func onePassClassifiesSeveralSessions() async throws {
        let firstId = ZmxSessionID.generateUUIDv7()
        let secondId = ZmxSessionID.generateUUIDv7()
        let firstIdentity = try foregroundTestIdentity()
        let secondIdentity = try foregroundTestIdentity(leaderPid: 4500)
        let identities = ForegroundTestSessionControl(identities: [firstId: firstIdentity, secondId: secondIdentity])
        let reads = ForegroundPassCounter()
        let samples = [
            foregroundTestSample(
                process: foregroundTestProcess(pid: 4100), group: 4100, foregroundGroup: 4200, argv0: "/bin/zsh"),
            foregroundTestSample(
                process: foregroundTestProcess(pid: 4200), group: 4200, foregroundGroup: 4200, argv0: "claude"),
            foregroundTestSample(
                process: foregroundTestProcess(pid: 4500), group: 4500, foregroundGroup: 4600, argv0: "/bin/zsh"),
            foregroundTestSample(
                process: foregroundTestProcess(pid: 4600), group: 4600, foregroundGroup: 4600, argv0: "codex"),
        ]
        let probe = DarwinTerminalForegroundProbe(
            sessionDirectory: "/unused-proof", bootId: "foreground-proof-boot",
            sessionControl: identities,
            readSamples: {
                reads.increment()
                return .init(samples: samples, complete: true)
            })
        let result = try await probe.probeForeground(of: [firstId, secondId])
        #expect(reads.value() == 1)
        #expect(result[firstId]?.program == .claudeCode)
        #expect(result[secondId]?.program == .codex)
        #expect(result[firstId]?.foregroundProcess == foregroundTestProcess(pid: 4200))
        #expect(result[firstId]?.sessionIdentity == firstIdentity)
    }
}

private final class ForegroundPassCounter: Sendable {
    private let count = Mutex(0)
    func increment() { count.withLock { $0 += 1 } }
    func value() -> Int { count.withLock { $0 } }
}

private struct ForegroundTestSessionControl: ZmxSessionControlling {
    let identities: [ZmxSessionID: Data]
    func observeSessionIdentity(_ sessionID: ZmxSessionID) -> Data? { identities[sessionID] }
    func retireVerifiedSession(_ sessionID: ZmxSessionID, expectedIdentity: Data) throws -> ZmxSessionCleanupStatus {
        throw ForegroundImplementationMissing.s2
    }
}

func foregroundTestProcess(pid: Int32) -> ProcessIncarnation {
    ProcessIncarnation(pid: pid, startSeconds: 100, startMicroseconds: UInt64(pid))
}

func foregroundTestSample(
    process: ProcessIncarnation, group: Int32, foregroundGroup: Int32, argv0: String
) -> ForegroundProcessSample {
    ForegroundProcessSample(
        incarnation: process, processGroupId: group, foregroundGroupId: foregroundGroup, argv0: argv0)
}

func foregroundTestIdentity(leaderPid: Int32 = 4100, bootId: String = "foreground-proof-boot") throws -> Data {
    try ZmxSessionIdentity(
        version: 1, bootID: bootId, daemon: foregroundTestProcess(pid: leaderPid - 1),
        terminalLeader: foregroundTestProcess(pid: leaderPid), processGroupID: leaderPid, sessionCreatedAt: 100
    ).encoded()
}
