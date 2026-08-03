import Foundation
import Testing

@testable import AgentStudioInfrastructure

@Suite("Swift build input fingerprint script")
struct SwiftBuildInputFingerprintScriptTests {
    @Test("identical input trees produce the same fingerprint")
    func identicalInputTreesProduceTheSameFingerprint() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }

        let firstFingerprint = try fixture.fingerprint()
        let secondFingerprint = try fixture.fingerprint()

        #expect(firstFingerprint == secondFingerprint)
    }

    @Test("content changes invalidate the fingerprint")
    func contentChangesInvalidateTheFingerprint() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let originalFingerprint = try fixture.fingerprint()

        try fixture.write("Sources/AgentStudio/Generated.swift", contents: "let value = 2\n")

        #expect(try fixture.fingerprint() != originalFingerprint)
    }

    @Test("renames invalidate the fingerprint")
    func renamesInvalidateTheFingerprint() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let originalFingerprint = try fixture.fingerprint()
        let oldPath = fixture.root.appendingPathComponent("Tests/AgentStudioTests/Fixture.swift")
        let newPath = fixture.root.appendingPathComponent("Tests/AgentStudioTests/RenamedFixture.swift")

        try FileManager.default.moveItem(at: oldPath, to: newPath)

        #expect(try fixture.fingerprint() != originalFingerprint)
    }

    @Test("mode changes invalidate the fingerprint")
    func modeChangesInvalidateTheFingerprint() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let originalFingerprint = try fixture.fingerprint()
        let path = fixture.root.appendingPathComponent("scripts/swift-test-helpers.sh")

        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: 0o755)],
            ofItemAtPath: path.path
        )

        #expect(try fixture.fingerprint() != originalFingerprint)
    }

    @Test("symlink target changes invalidate the fingerprint")
    func symlinkTargetChangesInvalidateTheFingerprint() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let originalFingerprint = try fixture.fingerprint()
        let linkPath = fixture.root.appendingPathComponent("Sources/AgentStudio/Resources/link")

        try FileManager.default.removeItem(at: linkPath)
        try FileManager.default.createSymbolicLink(
            atPath: linkPath.path,
            withDestinationPath: "different-target.txt"
        )

        #expect(try fixture.fingerprint() != originalFingerprint)
    }

    @Test("empty directory changes invalidate the fingerprint")
    func emptyDirectoryChangesInvalidateTheFingerprint() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let originalFingerprint = try fixture.fingerprint()

        try FileManager.default.createDirectory(
            at: fixture.root.appendingPathComponent("Sources/AgentStudio/Resources/empty-directory"),
            withIntermediateDirectories: false
        )

        #expect(try fixture.fingerprint() != originalFingerprint)
    }

    @Test("generated resources and framework contents invalidate the fingerprint")
    func generatedResourcesAndFrameworkContentsInvalidateTheFingerprint() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let originalFingerprint = try fixture.fingerprint()

        try fixture.write(
            "Sources/AgentStudio/Resources/BridgeWeb/app/index.html",
            contents: "<html>changed</html>\n"
        )
        let resourceFingerprint = try fixture.fingerprint()
        #expect(resourceFingerprint != originalFingerprint)

        try fixture.write(
            "Frameworks/GhosttyKit.xcframework/macos-arm64/GhosttyKit",
            contents: "framework changed\n"
        )
        #expect(try fixture.fingerprint() != resourceFingerprint)
    }

    private struct Fixture {
        let root: URL

        init() throws {
            root = FileManager.default.temporaryDirectory
                .appendingPathComponent(
                    "agentstudio-swift-build-input-fingerprint-" + UUIDv7.generate().uuidString
                )
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

            try write("Package.swift", contents: "// fixture manifest\n")
            try write("Package.resolved", contents: "{}\n")
            try write(".mise.toml", contents: "[tasks]\n")
            try write("Sources/AgentStudio/Generated.swift", contents: "let value = 1\n")
            try write(
                "Sources/AgentStudio/Resources/BridgeWeb/app/index.html",
                contents: "<html>fixture</html>\n"
            )
            try write("Sources/AgentStudio/Resources/terminfo/78/xterm-ghostty", contents: "terminfo\n")
            try write("Tests/AgentStudioTests/Fixture.swift", contents: "let fixture = true\n")
            try write("Frameworks/GhosttyKit.xcframework/macos-arm64/GhosttyKit", contents: "framework\n")
            try write("scripts/swift-build-slot.sh", contents: "#!/usr/bin/env bash\n")
            try write("scripts/swift-test-helpers.sh", contents: "#!/usr/bin/env bash\n")
            try write("scripts/run-swift-test-task.sh", contents: "#!/usr/bin/env bash\n")
            try write("scripts/swift-build-input-fingerprint.sh", contents: "#!/usr/bin/env bash\n")
            try write("Sources/AgentStudio/Resources/alternate-target.txt", contents: "alternate\n")
            try write("Sources/AgentStudio/Resources/different-target.txt", contents: "different\n")
            try FileManager.default.createSymbolicLink(
                atPath: root.appendingPathComponent("Sources/AgentStudio/Resources/link").path,
                withDestinationPath: "alternate-target.txt"
            )
        }

        func write(_ relativePath: String, contents: String) throws {
            let url = root.appendingPathComponent(relativePath)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Data(contents.utf8).write(to: url)
        }

        func fingerprint() throws -> String {
            let script = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("scripts/swift-build-input-fingerprint.sh")
            let stdout = Pipe()
            let stderr = Pipe()
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/bash")
            process.arguments = [script.path]
            process.environment = ProcessInfo.processInfo.environment.merging(
                ["SWIFT_BUILD_INPUT_ROOT": root.path]
            ) { _, newValue in newValue }
            process.standardOutput = stdout
            process.standardError = stderr

            try process.run()
            process.waitUntilExit()

            let output = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let error = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            guard process.terminationStatus == 0, let output, !output.isEmpty else {
                throw FingerprintError.failed(status: process.terminationStatus, message: error)
            }
            return output
        }

        func remove() {
            try? FileManager.default.removeItem(at: root)
        }
    }
}

private enum FingerprintError: Error, CustomStringConvertible {
    case failed(status: Int32, message: String)

    var description: String {
        switch self {
        case .failed(let status, let message):
            return "fingerprint script failed with status \(status): \(message)"
        }
    }
}
