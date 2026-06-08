import Foundation
import Testing

@testable import AgentStudio

@Suite("SwiftGitXWorkingTreeStatusProvider")
struct SwiftGitXWorkingTreeStatusProviderTests {
    @Test("maps client snapshot to GitWorkingTreeStatus")
    func mapsSnapshot() async {
        let provider = SwiftGitXWorkingTreeStatusProvider(
            client: StubSwiftGitXRepositoryStatusClient(
                result: .success(
                    SwiftGitXRepositoryStatusSnapshot(
                        changed: 3,
                        staged: 2,
                        untracked: 4,
                        linesAdded: 10,
                        linesDeleted: 6,
                        branch: "feature/swiftgitx",
                        aheadCount: 1,
                        behindCount: 0,
                        hasUpstream: true,
                        originURL: "git@github.com:askluna/agent-studio.git"
                    )
                )
            )
        )

        let status = await provider.status(for: URL(fileURLWithPath: "/tmp/repo"))
        let snapshot = try #require(status)

        #expect(snapshot.branch == "feature/swiftgitx")
        #expect(snapshot.summary.changed == 3)
        #expect(snapshot.summary.staged == 2)
        #expect(snapshot.summary.untracked == 4)
        #expect(snapshot.summary.linesAdded == 10)
        #expect(snapshot.summary.linesDeleted == 6)
        #expect(snapshot.summary.aheadCount == 1)
        #expect(snapshot.summary.behindCount == 0)
        #expect(snapshot.summary.hasUpstream == true)
        #expect(snapshot.originResolution == .resolved("git@github.com:askluna/agent-studio.git"))
    }

    @Test("normalizes blank origin to confirmedAbsent")
    func blankOriginBecomesAbsent() async {
        let provider = SwiftGitXWorkingTreeStatusProvider(
            client: StubSwiftGitXRepositoryStatusClient(
                result: .success(
                    SwiftGitXRepositoryStatusSnapshot(
                        changed: 0,
                        staged: 0,
                        untracked: 0,
                        linesAdded: 0,
                        linesDeleted: 0,
                        branch: "main",
                        aheadCount: 0,
                        behindCount: 0,
                        hasUpstream: true,
                        originURL: "   "
                    )
                )
            )
        )

        let status = await provider.status(for: URL(fileURLWithPath: "/tmp/repo"))
        let snapshot = try #require(status)
        #expect(snapshot.originResolution == .confirmedAbsent)
    }

    @Test("returns nil when client throws")
    func returnsNilOnClientError() async {
        let provider = SwiftGitXWorkingTreeStatusProvider(
            client: StubSwiftGitXRepositoryStatusClient(
                result: .failure(TestError.unavailable)
            )
        )

        let status = await provider.status(for: URL(fileURLWithPath: "/tmp/repo"))
        #expect(status == nil)
    }
}

private enum TestError: Error {
    case unavailable
}

private struct StubSwiftGitXRepositoryStatusClient: SwiftGitXRepositoryStatusClient {
    let result: Result<SwiftGitXRepositoryStatusSnapshot, Error>

    func status(rootPath _: URL) async throws -> SwiftGitXRepositoryStatusSnapshot {
        try result.get()
    }
}
