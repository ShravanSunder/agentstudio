import CryptoKit
import Darwin
import Foundation
import GRDB
import Testing

@testable import AgentStudio

@Suite("Workspace strict startup subprocess integration", .serialized)
struct WorkspaceStrictStartupSubprocessTests {
    @Test("strict SQLite failures terminate a real app process without changing durable inputs")
    func strictSQLiteFailuresTerminateWithoutChangingDurableInputs() throws {
        let executableURL = try Self.resolveAgentStudioExecutable()

        for scenario in StrictStartupFailureScenario.allCases {
            let fixture = try StrictStartupSubprocessFixture.make(for: scenario)
            defer { fixture.removeTemporaryFiles() }
            try fixture.closePreparationDatabasePools()
            let durableFilesBeforeLaunch = try fixture.durableFileDigests()
            let workspaceDirectoryBeforeLaunch = try fixture.workspaceDirectoryInventory()

            let result = try Self.runAgentStudio(executableURL: executableURL, fixture: fixture)

            #expect(!result.timedOut, "\(scenario.rawValue) did not terminate within the subprocess bound")
            #expect(result.terminationStatus != 0, "\(scenario.rawValue) unexpectedly exited successfully")
            let diagnosticLine = try #require(
                result.standardError.split(separator: "\n").first {
                    $0.contains("Workspace startup invariant violated:")
                }
            )
            #expect(diagnosticLine.contains(scenario.expectedDiagnosticCode))
            #expect(!diagnosticLine.contains(fixture.rootDirectory.path))
            #expect(!diagnosticLine.contains(fixture.legacySentinel))
            if let workspaceID = fixture.workspaceID {
                #expect(!diagnosticLine.contains(workspaceID.uuidString))
            }
            let durableFilesAfterLaunch = try fixture.durableFileDigests()
            #expect(
                durableFilesAfterLaunch == durableFilesBeforeLaunch,
                "\(scenario.rawValue) changed durable files: before=\(durableFilesBeforeLaunch) after=\(durableFilesAfterLaunch)"
            )
            let workspaceDirectoryAfterLaunch = try fixture.workspaceDirectoryInventory()
            #expect(
                workspaceDirectoryAfterLaunch == workspaceDirectoryBeforeLaunch,
                "\(scenario.rawValue) changed workspace inventory: before=\(workspaceDirectoryBeforeLaunch) after=\(workspaceDirectoryAfterLaunch)"
            )
            #expect(try String(contentsOf: fixture.legacyWorkspaceURL, encoding: .utf8) == fixture.legacySentinel)
        }
    }

    private static func resolveAgentStudioExecutable() throws -> URL {
        let testBundleURL = Bundle(for: StrictStartupTestBundleSentinel.self).bundleURL
        var searchDirectory = testBundleURL.deletingLastPathComponent()

        for _ in 0..<8 {
            let candidate = searchDirectory.appending(path: "AgentStudio")
            if FileManager.default.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
            searchDirectory.deleteLastPathComponent()
        }

        throw StrictStartupSubprocessError.agentStudioExecutableNotFound(testBundleURL)
    }

    private static func runAgentStudio(
        executableURL: URL,
        fixture: StrictStartupSubprocessFixture
    ) throws -> StrictStartupSubprocessResult {
        let standardOutputURL = fixture.rootDirectory.appending(path: "subprocess.stdout")
        let standardErrorURL = fixture.rootDirectory.appending(path: "subprocess.stderr")
        FileManager.default.createFile(atPath: standardOutputURL.path, contents: nil)
        FileManager.default.createFile(atPath: standardErrorURL.path, contents: nil)
        let standardOutputHandle = try FileHandle(forWritingTo: standardOutputURL)
        let standardErrorHandle = try FileHandle(forWritingTo: standardErrorURL)
        let process = Process()
        process.executableURL = executableURL
        process.currentDirectoryURL = fixture.rootDirectory
        process.environment = fixture.processEnvironment
        process.standardOutput = standardOutputHandle
        process.standardError = standardErrorHandle

        let terminationSignal = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in terminationSignal.signal() }
        try process.run()

        let timedOut = terminationSignal.wait(timeout: .now() + 20) == .timedOut
        if timedOut {
            process.terminate()
            if terminationSignal.wait(timeout: .now() + 2) == .timedOut {
                kill(process.processIdentifier, SIGKILL)
            }
        }
        process.waitUntilExit()
        try standardOutputHandle.close()
        try standardErrorHandle.close()

        return StrictStartupSubprocessResult(
            terminationStatus: process.terminationStatus,
            timedOut: timedOut,
            standardOutput: try String(contentsOf: standardOutputURL, encoding: .utf8),
            standardError: try String(contentsOf: standardErrorURL, encoding: .utf8)
        )
    }
}

private enum StrictStartupFailureScenario: String, CaseIterable {
    case preexistingEmptyDatabase = "preexisting-empty-database"
    case corruptCoreDatabase = "corrupt-core-database"
    case localCompletionTokenMismatch = "local-completion-token-mismatch"
    case invalidComposition = "invalid-composition"

    var expectedDiagnosticCode: String {
        switch self {
        case .preexistingEmptyDatabase, .corruptCoreDatabase, .localCompletionTokenMismatch:
            "sqlite_unavailable"
        case .invalidComposition:
            "composition_rejected"
        }
    }
}

private struct StrictStartupSubprocessResult {
    let terminationStatus: Int32
    let timedOut: Bool
    let standardOutput: String
    let standardError: String
}

private final class StrictStartupSubprocessFixture {
    let rootDirectory: URL
    let workspaceDirectory: URL
    let legacyWorkspaceURL: URL
    let legacySentinel: String
    let workspaceID: UUID?
    let localDatabaseURL: URL?
    let heldDatabasePools: [DatabasePool]

    var processEnvironment: [String: String] {
        let homeDirectory = rootDirectory.appending(path: "home")
        let temporaryDirectory = rootDirectory.appending(path: "tmp")
        let cacheDirectory = rootDirectory.appending(path: "xdg-cache")
        let stateDirectory = rootDirectory.appending(path: "xdg-state")
        return [
            "HOME": homeDirectory.path,
            "USER": "agentstudio-strict-startup-test",
            "LOGNAME": "agentstudio-strict-startup-test",
            "SHELL": "/bin/zsh",
            "TMPDIR": temporaryDirectory.path,
            "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
            "XDG_CACHE_HOME": cacheDirectory.path,
            "XDG_STATE_HOME": stateDirectory.path,
            "AGENTSTUDIO_DATA_DIR": rootDirectory.path,
            "AGENTSTUDIO_IPC_SOCKET_DIR": rootDirectory.appending(path: "ipc-socket").path,
            "AGENTSTUDIO_TRACE_TAGS": "off",
            "AGENTSTUDIO_GHOSTTY_DISABLE_DEFAULT_CONFIG": "1",
            "AGENTSTUDIO_GHOSTTY_DISABLE_VSYNC": "1",
        ]
    }

    static func make(for scenario: StrictStartupFailureScenario) throws -> StrictStartupSubprocessFixture {
        let (rootDirectory, workspaceDirectory) = try makeRootDirectory(for: scenario)
        let legacyWorkspaceURL = workspaceDirectory.appending(path: "legacy.workspace.state.json")
        let legacySentinel = "legacy workspace JSON must remain unchanged for \(scenario.rawValue)"
        try legacySentinel.write(to: legacyWorkspaceURL, atomically: true, encoding: .utf8)
        let coreDatabaseURL = rootDirectory.appending(path: "core.sqlite")

        switch scenario {
        case .preexistingEmptyDatabase:
            let corePool = try SQLiteDatabaseFactory.makeFileBackedPool(
                at: coreDatabaseURL,
                label: "AgentStudio.sqlite.strict-subprocess.preexisting-empty"
            )
            try WorkspaceCoreMigrations.migrate(corePool)
            return StrictStartupSubprocessFixture(
                rootDirectory: rootDirectory,
                workspaceDirectory: workspaceDirectory,
                legacyWorkspaceURL: legacyWorkspaceURL,
                legacySentinel: legacySentinel,
                workspaceID: nil,
                localDatabaseURL: nil,
                heldDatabasePools: [corePool]
            )

        case .corruptCoreDatabase:
            try Data("corrupt SQLite sentinel for strict subprocess proof".utf8).write(to: coreDatabaseURL)
            return StrictStartupSubprocessFixture(
                rootDirectory: rootDirectory,
                workspaceDirectory: workspaceDirectory,
                legacyWorkspaceURL: legacyWorkspaceURL,
                legacySentinel: legacySentinel,
                workspaceID: nil,
                localDatabaseURL: nil,
                heldDatabasePools: []
            )

        case .localCompletionTokenMismatch, .invalidComposition:
            let workspaceID = UUIDv7.generate()
            let localDatabaseURL = workspaceDirectory.appending(path: "\(workspaceID.uuidString).local.sqlite")
            let corePool = try SQLiteDatabaseFactory.makeFileBackedPool(
                at: coreDatabaseURL,
                label: "AgentStudio.sqlite.strict-subprocess.\(scenario.rawValue).core"
            )
            let localPool = try SQLiteDatabaseFactory.makeFileBackedPool(
                at: localDatabaseURL,
                label: "AgentStudio.sqlite.strict-subprocess.\(scenario.rawValue).local"
            )
            try WorkspaceCoreMigrations.migrate(corePool)
            try WorkspaceLocalMigrations.migrate(localPool)
            let coreRepository = WorkspaceCoreRepository(databaseWriter: corePool)
            let localRepository = WorkspaceLocalRepository(
                workspaceId: workspaceID,
                databaseWriter: localPool
            )
            let backend = WorkspaceSQLiteStoreBackend(
                coreRepository: coreRepository,
                makeLocalRepository: { _ in localRepository }
            )
            try backend.save(
                .emptyTopologyFixture(
                    workspace: .emptyFixture(
                        id: workspaceID,
                        name: "Strict subprocess \(scenario.rawValue)"
                    )
                )
            )

            switch scenario {
            case .localCompletionTokenMismatch:
                try localPool.write { database in
                    try database.execute(
                        sql: "UPDATE local_workspace_sqlite_snapshot_status SET completed_at = completed_at + 1"
                    )
                }
            case .invalidComposition:
                try localPool.write { database in
                    try database.execute(
                        sql: "UPDATE local_workspace_cursor SET active_tab_id = ? WHERE workspace_id = ?",
                        arguments: [UUIDv7.generate().uuidString, workspaceID.uuidString]
                    )
                }
            case .preexistingEmptyDatabase, .corruptCoreDatabase:
                preconditionFailure("Scenario does not use a completed workspace fixture")
            }

            return StrictStartupSubprocessFixture(
                rootDirectory: rootDirectory,
                workspaceDirectory: workspaceDirectory,
                legacyWorkspaceURL: legacyWorkspaceURL,
                legacySentinel: legacySentinel,
                workspaceID: workspaceID,
                localDatabaseURL: localDatabaseURL,
                heldDatabasePools: [corePool, localPool]
            )
        }
    }

    private static func makeRootDirectory(
        for scenario: StrictStartupFailureScenario
    ) throws -> (root: URL, workspaces: URL) {
        let rootDirectory = FileManager.default.temporaryDirectory.appending(
            path: "agentstudio-strict-startup-subprocess-\(scenario.rawValue)-\(UUIDv7.generate().uuidString)"
        )
        let workspaceDirectory = rootDirectory.appending(path: "workspaces")
        for directory in [
            rootDirectory,
            workspaceDirectory,
            rootDirectory.appending(path: "home"),
            rootDirectory.appending(path: "tmp"),
            rootDirectory.appending(path: "xdg-cache"),
            rootDirectory.appending(path: "xdg-state"),
        ] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return (rootDirectory, workspaceDirectory)
    }

    init(
        rootDirectory: URL,
        workspaceDirectory: URL,
        legacyWorkspaceURL: URL,
        legacySentinel: String,
        workspaceID: UUID?,
        localDatabaseURL: URL?,
        heldDatabasePools: [DatabasePool]
    ) {
        self.rootDirectory = rootDirectory
        self.workspaceDirectory = workspaceDirectory
        self.legacyWorkspaceURL = legacyWorkspaceURL
        self.legacySentinel = legacySentinel
        self.workspaceID = workspaceID
        self.localDatabaseURL = localDatabaseURL
        self.heldDatabasePools = heldDatabasePools
    }

    func durableFileDigests() throws -> [String: StrictStartupFileDigest] {
        var databaseURLs = [rootDirectory.appending(path: "core.sqlite")]
        if let localDatabaseURL {
            databaseURLs.append(localDatabaseURL)
        }
        let durableURLs =
            databaseURLs.flatMap { databaseURL in
                [
                    databaseURL,
                    URL(filePath: "\(databaseURL.path)-wal"),
                    URL(filePath: "\(databaseURL.path)-shm"),
                ]
            } + [legacyWorkspaceURL]

        return try Dictionary(
            uniqueKeysWithValues: durableURLs.map { durableURL in
                let relativePath = durableURL.path.replacingOccurrences(of: rootDirectory.path + "/", with: "")
                guard FileManager.default.fileExists(atPath: durableURL.path) else {
                    return (relativePath, .missing)
                }
                let data = try Data(contentsOf: durableURL)
                return (relativePath, .sha256(SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()))
            })
    }

    func workspaceDirectoryInventory() throws -> [String] {
        try FileManager.default.contentsOfDirectory(
            at: workspaceDirectory,
            includingPropertiesForKeys: nil
        ).map(\.lastPathComponent).sorted()
    }

    func removeTemporaryFiles() {
        for databasePool in heldDatabasePools {
            try? databasePool.close()
        }
        try? FileManager.default.removeItem(at: rootDirectory)
    }

    func closePreparationDatabasePools() throws {
        for databasePool in heldDatabasePools {
            try databasePool.close()
        }
    }
}

private enum StrictStartupFileDigest: Equatable {
    case missing
    case sha256(String)
}

private enum StrictStartupSubprocessError: Error {
    case agentStudioExecutableNotFound(URL)
}

private final class StrictStartupTestBundleSentinel: NSObject {}
