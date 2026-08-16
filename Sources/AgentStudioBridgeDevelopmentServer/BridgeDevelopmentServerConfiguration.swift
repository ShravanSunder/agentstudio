import AgentStudioCore
import Foundation
import Hummingbird

enum BridgeDevelopmentServerConfigurationError: Error, Equatable {
    case invalidPort
}

struct BridgeDevelopmentServerConfiguration: Sendable {
    let dataRoot: URL
    let paneID: UUID
    let port: Int
    let seedContributionTarget: WorkspaceReviewContributionTarget
    let seedWorktreeRoot: URL

    var applicationConfiguration: ApplicationConfiguration {
        .init(
            address: .hostname("127.0.0.1", port: port),
            serverName: "agentstudio-bridge-dev-server"
        )
    }

    var reviewSharedContentRootURL: URL {
        dataRoot.appending(path: "bridge-review-content", directoryHint: .isDirectory)
    }

    init(
        dataRoot: URL,
        paneID: UUID,
        port: Int,
        seedContributionTarget: WorkspaceReviewContributionTarget,
        seedWorktreeRoot: URL
    ) throws {
        guard (1...65_535).contains(port) else {
            throw BridgeDevelopmentServerConfigurationError.invalidPort
        }
        self.dataRoot = dataRoot.standardizedFileURL.resolvingSymlinksInPath()
        self.paneID = paneID
        self.port = port
        self.seedContributionTarget = seedContributionTarget
        self.seedWorktreeRoot = seedWorktreeRoot.standardizedFileURL.resolvingSymlinksInPath()
    }
}
