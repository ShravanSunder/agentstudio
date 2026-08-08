import Foundation
import Hummingbird

enum BridgeDevelopmentServerConfigurationError: Error, Equatable {
    case invalidPort
}

struct BridgeDevelopmentServerConfiguration: Sendable {
    let worktreeRoot: URL
    let reviewBase: String
    let port: Int

    var applicationConfiguration: ApplicationConfiguration {
        .init(
            address: .hostname("127.0.0.1", port: port),
            serverName: "agentstudio-bridge-dev-server"
        )
    }

    init(worktreeRoot: URL, reviewBase: String, port: Int) throws {
        guard (1...65_535).contains(port) else {
            throw BridgeDevelopmentServerConfigurationError.invalidPort
        }
        self.worktreeRoot = worktreeRoot.standardizedFileURL.resolvingSymlinksInPath()
        self.reviewBase = reviewBase
        self.port = port
    }
}
