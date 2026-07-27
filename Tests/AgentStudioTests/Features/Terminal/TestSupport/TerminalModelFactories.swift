import AgentStudioCore
import Foundation

@testable import AgentStudioTerminal

func makeRestoredZmxSessionID(_ rawValue: String) throws -> ZmxSessionID {
    try JSONDecoder().decode(
        ZmxSessionID.self,
        from: JSONEncoder().encode(rawValue)
    )
}

func makeSurfaceMetadata(
    launchDirectory: String? = "/tmp/test-dir",
    command: String? = nil,
    title: String = "Terminal",
    worktreeId: UUID? = nil,
    repoId: UUID? = nil,
    paneId: UUID? = nil
) -> SurfaceMetadata {
    SurfaceMetadata(
        launchDirectory: launchDirectory.map { URL(fileURLWithPath: $0) },
        command: command,
        title: title,
        worktreeId: worktreeId,
        repoId: repoId,
        paneId: paneId
    )
}
