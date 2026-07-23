import Darwin
import Foundation
import Testing

enum VendorPinMismatch: String, CaseIterable {
    case linkedGhosttyGitlink
    case linkedZmxGitlink
    case primaryGhosttyGitlink
    case primaryZmxGitlink
    case primaryGhosttySubmoduleHead
    case primaryZmxSubmoduleHead
}

enum VendorInvalidPrimarySource: String, CaseIterable {
    case missingFramework
    case symlinkedFramework
    case nestedFrameworkSymlink
    case frameworkIsFile
    case missingZmxOutput
    case zmxIsNotExecutable
    case symlinkedGhosttyResources
    case missingGhosttyTerminfo
}

struct VendorCommandResult {
    let exitCode: Int32
    let stdout: String
    let stderr: String
}

struct VendorWorktreeFixture {
    let temporaryRoot: URL
    let primaryRoot: URL
    let linkedRoot: URL
    let ghosttyRepository: URL
    let zmxRepository: URL
    let ghosttyFirstCommit: String
    let ghosttySecondCommit: String
    let zmxFirstCommit: String
    let zmxSecondCommit: String

    private let fileManager = FileManager.default

    init() throws {
        temporaryRoot = FileManager.default.temporaryDirectory
            .appending(path: "AgentStudio vendor fixture \(UUID().uuidString)")
        primaryRoot = temporaryRoot.appending(path: "primary AgentStudio")
        linkedRoot = temporaryRoot.appending(path: "linked worker")
        ghosttyRepository = temporaryRoot.appending(path: "dummy Ghostty source")
        zmxRepository = temporaryRoot.appending(path: "dummy zmx source")

        try FileManager.default.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)
        let ghosttyCommits = try Self.makeDummyVendorRepository(
            at: ghosttyRepository,
            markerName: "ghostty")
        ghosttyFirstCommit = ghosttyCommits.first
        ghosttySecondCommit = ghosttyCommits.second
        let zmxCommits = try Self.makeDummyVendorRepository(
            at: zmxRepository,
            markerName: "zmx")
        zmxFirstCommit = zmxCommits.first
        zmxSecondCommit = zmxCommits.second

        try requireSuccess(Self.runGit(["init", primaryRoot.path], in: temporaryRoot))
        try configureGit(in: primaryRoot)
        try writeTrackedSuperprojectFiles()
        try requireSuccess(
            Self.runGit(
                ["-c", "protocol.file.allow=always", "submodule", "add", ghosttyRepository.path, "vendor/ghostty"],
                in: primaryRoot))
        try requireSuccess(
            Self.runGit(
                ["-c", "protocol.file.allow=always", "submodule", "add", zmxRepository.path, "vendor/zmx"],
                in: primaryRoot))
        try requireSuccess(
            Self.runGit(["checkout", ghosttyFirstCommit], in: primaryRoot.appending(path: "vendor/ghostty")))
        try requireSuccess(Self.runGit(["checkout", zmxFirstCommit], in: primaryRoot.appending(path: "vendor/zmx")))
        try requireSuccess(Self.runGit(["add", "."], in: primaryRoot))
        try requireSuccess(Self.runGit(["commit", "-m", "fixture superproject"], in: primaryRoot))
        try publishPrimaryOutputs()
        try requireSuccess(
            Self.runGit(
                ["worktree", "add", "-b", "linked-fixture", linkedRoot.path],
                in: primaryRoot))
    }

    var primaryFrameworkURL: URL {
        primaryRoot.appending(path: "Frameworks/GhosttyKit.xcframework")
    }

    var linkedFrameworkURL: URL {
        linkedRoot.appending(path: "Frameworks/GhosttyKit.xcframework")
    }

    var primaryZmxOutputURL: URL {
        primaryRoot.appending(path: "vendor/zmx/zig-out")
    }

    var linkedZmxOutputURL: URL {
        linkedRoot.appending(path: "vendor/zmx/zig-out")
    }

    var primaryGhosttyResourcesURL: URL {
        primaryRoot.appending(path: "Sources/AgentStudio/Resources/ghostty")
    }

    var linkedGhosttyResourcesURL: URL {
        linkedRoot.appending(path: "Sources/AgentStudio/Resources/ghostty")
    }

    var primaryGhosttyTerminfoURL: URL {
        primaryRoot.appending(path: "Sources/AgentStudio/Resources/terminfo/67/ghostty")
    }

    var linkedGhosttyTerminfoURL: URL {
        linkedRoot.appending(path: "Sources/AgentStudio/Resources/terminfo/67/ghostty")
    }

    var primaryTrackedTerminfoURL: URL {
        primaryRoot.appending(path: "Sources/AgentStudio/Resources/terminfo/78/xterm-256color")
    }

    func cleanup() {
        try? fileManager.removeItem(at: temporaryRoot)
    }

    func runHelper(
        _ command: String,
        in worktree: URL,
        currentDirectory: URL? = nil,
        environment: [String: String] = [:]
    ) throws -> VendorCommandResult {
        try Self.run(
            executable: URL(fileURLWithPath: "/bin/bash"),
            arguments: [worktree.appending(path: "scripts/vendor-worktree.sh").path, command],
            in: currentDirectory ?? worktree,
            environment: environment)
    }

    func gitStatus(in worktree: URL) throws -> String {
        let result = try Self.runGit(["status", "--short"], in: worktree)
        try requireSuccess(result)
        return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func checkedOutRevision(path: String, in worktree: URL) throws -> String {
        let result = try Self.runGit(["-C", path, "rev-parse", "HEAD"], in: worktree)
        try requireSuccess(result)
        return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func requireSuccess(_ result: VendorCommandResult) throws {
        try Self.requireSuccess(result)
    }

    func primaryOutputSnapshot(allowMissing: Bool = false) throws -> [String: Data] {
        try snapshot(
            urls: [
                primaryFrameworkURL,
                primaryZmxOutputURL,
                primaryGhosttyResourcesURL,
                primaryGhosttyTerminfoURL,
            ],
            allowMissing: allowMissing)
    }

    func sharedProjectionSnapshot() throws -> [String: Data] {
        try snapshot(
            urls: [
                linkedGhosttyResourcesURL,
                linkedGhosttyTerminfoURL,
            ],
            allowMissing: false)
    }

    func localProjectionSnapshot() throws -> [String: Data] {
        try snapshot(
            urls: [
                linkedFrameworkURL,
                linkedZmxOutputURL,
                linkedGhosttyResourcesURL,
                linkedGhosttyTerminfoURL,
            ],
            allowMissing: false)
    }

    func expectExactSharedProjection() throws {
        #expect(try canonicalSymlinkTarget(linkedFrameworkURL) == primaryFrameworkURL.resolvingSymlinksInPath().path)
        #expect(try canonicalSymlinkTarget(linkedZmxOutputURL) == primaryZmxOutputURL.resolvingSymlinksInPath().path)
        #expect(try isSymbolicLink(linkedGhosttyResourcesURL) == false)
        #expect(try isSymbolicLink(linkedGhosttyTerminfoURL) == false)
        #expect(
            try snapshot(urls: [linkedGhosttyResourcesURL], allowMissing: false)
                == snapshot(urls: [primaryGhosttyResourcesURL], allowMissing: false))
        #expect(try Data(contentsOf: linkedGhosttyTerminfoURL) == Data(contentsOf: primaryGhosttyTerminfoURL))
        try assertNoNestedSymlinks(in: linkedGhosttyResourcesURL)
    }

    func expectCompleteLocalProjection() throws {
        for url in [
            linkedFrameworkURL,
            linkedZmxOutputURL,
            linkedGhosttyResourcesURL,
            linkedGhosttyTerminfoURL,
        ] {
            #expect(fileManager.fileExists(atPath: url.path))
            #expect(try isSymbolicLink(url) == false)
        }
    }

    func apply(_ mismatch: VendorPinMismatch) throws {
        switch mismatch {
        case .linkedGhosttyGitlink:
            try updateGitlink(
                worktree: linkedRoot,
                path: "vendor/ghostty",
                commit: ghosttySecondCommit)
        case .linkedZmxGitlink:
            try updateGitlink(
                worktree: linkedRoot,
                path: "vendor/zmx",
                commit: zmxSecondCommit)
        case .primaryGhosttyGitlink:
            try updateGitlink(
                worktree: primaryRoot,
                path: "vendor/ghostty",
                commit: ghosttySecondCommit)
        case .primaryZmxGitlink:
            try updateGitlink(
                worktree: primaryRoot,
                path: "vendor/zmx",
                commit: zmxSecondCommit)
        case .primaryGhosttySubmoduleHead:
            try requireSuccess(
                Self.runGit(
                    ["checkout", ghosttySecondCommit],
                    in: primaryRoot.appending(path: "vendor/ghostty")))
        case .primaryZmxSubmoduleHead:
            try requireSuccess(
                Self.runGit(
                    ["checkout", zmxSecondCommit],
                    in: primaryRoot.appending(path: "vendor/zmx")))
        }
    }

    func apply(_ invalidSource: VendorInvalidPrimarySource) throws {
        switch invalidSource {
        case .missingFramework:
            try fileManager.removeItem(at: primaryFrameworkURL)
        case .symlinkedFramework:
            try fileManager.removeItem(at: primaryFrameworkURL)
            try fileManager.createSymbolicLink(
                at: primaryFrameworkURL,
                withDestinationURL: primaryGhosttyResourcesURL)
        case .nestedFrameworkSymlink:
            let externalLibrary = temporaryRoot.appending(path: "external libghostty")
            try Data("external framework library".utf8).write(to: externalLibrary)
            let nestedLibrary = primaryFrameworkURL.appending(path: "macos-arm64/libghostty.a")
            try fileManager.removeItem(at: nestedLibrary)
            try fileManager.createSymbolicLink(
                at: nestedLibrary,
                withDestinationURL: externalLibrary)
        case .frameworkIsFile:
            try fileManager.removeItem(at: primaryFrameworkURL)
            try Data("not a framework".utf8).write(to: primaryFrameworkURL)
        case .missingZmxOutput:
            try fileManager.removeItem(at: primaryZmxOutputURL)
        case .zmxIsNotExecutable:
            chmod(primaryZmxOutputURL.appending(path: "bin/zmx").path, 0o644)
        case .symlinkedGhosttyResources:
            let replacement = temporaryRoot.appending(path: "foreign resources")
            try fileManager.copyItem(at: primaryGhosttyResourcesURL, to: replacement)
            try fileManager.removeItem(at: primaryGhosttyResourcesURL)
            try fileManager.createSymbolicLink(
                at: primaryGhosttyResourcesURL,
                withDestinationURL: replacement)
        case .missingGhosttyTerminfo:
            try fileManager.removeItem(at: primaryGhosttyTerminfoURL)
        }
    }

    func makeCommandSpies(logURL: URL) throws -> URL {
        let directory = temporaryRoot.appending(path: "command spies")
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        try writeExecutable(
            at: directory.appending(path: "git"),
            contents: """
                #!/bin/bash
                printf 'git %s\\n' "$*" >> \(Self.shellQuote(logURL.path))
                exec /usr/bin/git "$@"
                """)
        try writeExecutable(
            at: directory.appending(path: "zig"),
            contents: """
                #!/bin/bash
                printf 'zig %s\\n' "$*" >> \(Self.shellQuote(logURL.path))
                exit 97
                """)
        try Data().write(to: logURL)
        return directory
    }

    func makeLocalProducerSpies() throws -> URL {
        let directory = temporaryRoot.appending(path: "local producer spies")
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        try writeExecutable(
            at: directory.appending(path: "mise"),
            contents: """
                #!/bin/bash
                set -euo pipefail
                mkdir -p Frameworks/GhosttyKit.xcframework/macos-arm64
                printf 'local framework\\n' > Frameworks/GhosttyKit.xcframework/macos-arm64/libghostty.a
                mkdir -p vendor/zmx/zig-out/bin
                printf '#!/bin/bash\\necho local-zmx\\n' > vendor/zmx/zig-out/bin/zmx
                chmod 700 vendor/zmx/zig-out/bin/zmx
                mkdir -p Sources/AgentStudio/Resources/ghostty/shell-integration
                printf 'local shell\\n' > Sources/AgentStudio/Resources/ghostty/shell-integration/ghostty.sh
                mkdir -p Sources/AgentStudio/Resources/terminfo/67
                printf 'local terminfo\\n' > Sources/AgentStudio/Resources/terminfo/67/ghostty
                """)
        return directory
    }

    func makeFailingCopySpy() throws -> URL {
        let directory = temporaryRoot.appending(path: "failing copy spy")
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        try writeExecutable(
            at: directory.appending(path: "cp"),
            contents: """
                #!/bin/bash
                exit 71
                """)
        return directory
    }

    private func updateGitlink(worktree: URL, path: String, commit: String) throws {
        try requireSuccess(
            Self.runGit(
                ["update-index", "--add", "--cacheinfo", "160000,\(commit),\(path)"],
                in: worktree))
        try requireSuccess(Self.runGit(["commit", "-m", "change \(path) pin"], in: worktree))
    }

    private func publishPrimaryOutputs() throws {
        let frameworkLibrary = primaryFrameworkURL.appending(path: "macos-arm64/libghostty.a")
        try fileManager.createDirectory(
            at: frameworkLibrary.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        try Data("primary ghostty library".utf8).write(to: frameworkLibrary)

        let zmxBinary = primaryZmxOutputURL.appending(path: "bin/zmx")
        try fileManager.createDirectory(
            at: zmxBinary.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        try writeExecutable(
            at: zmxBinary,
            contents: "#!/bin/bash\necho fixture-zmx\n")

        let shellIntegration =
            primaryGhosttyResourcesURL
            .appending(path: "shell-integration/ghostty.sh")
        try fileManager.createDirectory(
            at: shellIntegration.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        try Data("primary shell integration".utf8).write(to: shellIntegration)

        try fileManager.createDirectory(
            at: primaryGhosttyTerminfoURL.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        try Data("primary ghostty terminfo".utf8).write(to: primaryGhosttyTerminfoURL)
    }

    private func writeTrackedSuperprojectFiles() throws {
        let productionScript = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appending(path: "scripts/vendor-worktree.sh")
        guard fileManager.fileExists(atPath: productionScript.path) else {
            throw CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: productionScript.path])
        }
        let fixtureScript = primaryRoot.appending(path: "scripts/vendor-worktree.sh")
        try fileManager.createDirectory(
            at: fixtureScript.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        try fileManager.copyItem(at: productionScript, to: fixtureScript)
        chmod(fixtureScript.path, 0o755)

        let trackedTerminfo = primaryTrackedTerminfoURL
        try fileManager.createDirectory(
            at: trackedTerminfo.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        try Data("tracked custom xterm".utf8).write(to: trackedTerminfo)
        try """
        Frameworks/GhosttyKit.xcframework
        vendor/zmx/zig-out
        Sources/AgentStudio/Resources/ghostty
        Sources/AgentStudio/Resources/terminfo/67
        """.appending("\n").write(
            to: primaryRoot.appending(path: ".gitignore"),
            atomically: true,
            encoding: .utf8)
    }

    private func configureGit(in repository: URL) throws {
        try requireSuccess(Self.runGit(["config", "user.name", "Fixture"], in: repository))
        try requireSuccess(Self.runGit(["config", "user.email", "fixture@example.invalid"], in: repository))
        try requireSuccess(Self.runGit(["config", "commit.gpgsign", "false"], in: repository))
    }

    private func canonicalSymlinkTarget(_ url: URL) throws -> String {
        let destination = try fileManager.destinationOfSymbolicLink(atPath: url.path)
        #expect(destination.hasPrefix("/"), "Shared links must use absolute targets")
        return URL(fileURLWithPath: destination).resolvingSymlinksInPath().path
    }

    private func isSymbolicLink(_ url: URL) throws -> Bool {
        let values = try url.resourceValues(forKeys: [.isSymbolicLinkKey])
        return values.isSymbolicLink == true
    }

    private func assertNoNestedSymlinks(in root: URL) throws {
        guard
            let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: [.isSymbolicLinkKey])
        else {
            Issue.record("Could not enumerate \(root.path)")
            return
        }
        for case let child as URL in enumerator {
            #expect(try isSymbolicLink(child) == false)
        }
    }

    private func snapshot(urls: [URL], allowMissing: Bool) throws -> [String: Data] {
        var result: [String: Data] = [:]
        for root in urls {
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: root.path, isDirectory: &isDirectory) else {
                if allowMissing {
                    result[root.lastPathComponent] = Data("<missing>".utf8)
                    continue
                }
                throw CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: root.path])
            }
            if !isDirectory.boolValue {
                result[root.lastPathComponent] = try Data(contentsOf: root)
                continue
            }
            guard let enumerator = fileManager.enumerator(at: root, includingPropertiesForKeys: nil) else {
                continue
            }
            for case let child as URL in enumerator {
                var childIsDirectory: ObjCBool = false
                guard fileManager.fileExists(atPath: child.path, isDirectory: &childIsDirectory),
                    !childIsDirectory.boolValue
                else {
                    continue
                }
                let relativePath = child.path.replacingOccurrences(
                    of: root.path + "/",
                    with: "")
                result["\(root.lastPathComponent)/\(relativePath)"] = try Data(contentsOf: child)
            }
        }
        return result
    }

    private func writeExecutable(at url: URL, contents: String) throws {
        try contents.write(to: url, atomically: true, encoding: .utf8)
        chmod(url.path, 0o755)
    }

    private static func makeDummyVendorRepository(
        at repository: URL,
        markerName: String
    ) throws -> (first: String, second: String) {
        try FileManager.default.createDirectory(at: repository, withIntermediateDirectories: true)
        try requireSuccess(runGit(["init"], in: repository))
        try requireSuccess(runGit(["config", "user.name", "Fixture"], in: repository))
        try requireSuccess(runGit(["config", "user.email", "fixture@example.invalid"], in: repository))
        try requireSuccess(runGit(["config", "commit.gpgsign", "false"], in: repository))
        try Data("\(markerName) revision one".utf8).write(to: repository.appending(path: "build.zig"))
        try requireSuccess(runGit(["add", "."], in: repository))
        try requireSuccess(runGit(["commit", "-m", "first"], in: repository))
        let first = try gitRevision(in: repository)
        try Data("\(markerName) revision two".utf8).write(to: repository.appending(path: "build.zig"))
        try requireSuccess(runGit(["commit", "-am", "second"], in: repository))
        return (first, try gitRevision(in: repository))
    }

    private static func gitRevision(in repository: URL) throws -> String {
        let result = try runGit(["rev-parse", "HEAD"], in: repository)
        try requireSuccess(result)
        return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func runGit(_ arguments: [String], in directory: URL) throws -> VendorCommandResult {
        try run(
            executable: URL(fileURLWithPath: "/usr/bin/git"),
            arguments: arguments,
            in: directory,
            environment: ["GIT_ALLOW_PROTOCOL": "file"])
    }

    private static func run(
        executable: URL,
        arguments: [String],
        in directory: URL,
        environment: [String: String]
    ) throws -> VendorCommandResult {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.currentDirectoryURL = directory
        var mergedEnvironment = ProcessInfo.processInfo.environment
        for (key, value) in environment {
            mergedEnvironment[key] = value
        }
        process.environment = mergedEnvironment
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()
        return VendorCommandResult(
            exitCode: process.terminationStatus,
            stdout: String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "",
            stderr: String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "")
    }

    private static func requireSuccess(_ result: VendorCommandResult) throws {
        guard result.exitCode == 0 else {
            throw CocoaError(
                .executableLoad,
                userInfo: [NSLocalizedDescriptionKey: result.stderr])
        }
    }

    private static func shellQuote(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\"'\"'"))'"
    }
}
