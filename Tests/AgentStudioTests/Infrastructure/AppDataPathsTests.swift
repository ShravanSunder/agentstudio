import Foundation
import Testing

@testable import AgentStudio

@Suite(.serialized)
struct AppDataPathsTests {

    @Test
    func test_rootDirectory_defaultsToReleaseLocation() {
        let root = AppDataPaths.rootDirectory(
            environment: [:],
            isDebugBuild: false
        )

        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        #expect(root.path == "\(homeDir)/.agentstudio")
    }

    @Test
    func test_rootDirectory_defaultsToDebugLocation() {
        let root = AppDataPaths.rootDirectory(
            environment: [:],
            isDebugBuild: true
        )

        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        #expect(root.path == "\(homeDir)/.agentstudio-db")
    }

    @Test
    func test_rootDirectory_envOverrideWinsForReleaseAndDebug() {
        let env = ["AGENTSTUDIO_DATA_DIR": "~/custom-agentstudio"]

        let releaseRoot = AppDataPaths.rootDirectory(
            environment: env,
            isDebugBuild: false
        )
        let debugRoot = AppDataPaths.rootDirectory(
            environment: env,
            isDebugBuild: true
        )

        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        #expect(releaseRoot.path == "\(homeDir)/custom-agentstudio")
        #expect(debugRoot.path == "\(homeDir)/custom-agentstudio")
    }

    @Test
    func test_derivedPathsFollowRootDirectory() {
        let env = ["AGENTSTUDIO_DATA_DIR": "~/state-root"]
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path

        let root = AppDataPaths.rootDirectory(
            environment: env,
            isDebugBuild: false
        )
        let workspaces = AppDataPaths.workspacesDirectory(
            environment: env,
            isDebugBuild: false
        )
        let zmx = AppDataPaths.zmxDirectory(
            environment: env,
            isDebugBuild: false
        )
        let checkpoint = AppDataPaths.surfaceCheckpointURL(
            environment: env,
            isDebugBuild: false
        )

        #expect(root.path == "\(homeDir)/state-root")
        #expect(workspaces.path == "\(homeDir)/state-root/workspaces")
        #expect(zmx.path == "\(homeDir)/state-root/z")
        #expect(checkpoint.path == "\(homeDir)/state-root/surface-checkpoint.json")
    }

    @Test
    func test_displayPathUsesTildeForHomeDirectory() {
        let root = AppDataPaths.rootDirectory(
            environment: [:],
            isDebugBuild: true
        )

        #expect(AppDataPaths.displayPath(for: root) == "~/.agentstudio-db")
    }
}
