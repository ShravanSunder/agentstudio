import AgentStudioIPCTransport
import Foundation
import Testing

@testable import AgentStudioIPCClientCore

private let cursorFixtureVersion = "2026.09.15-d2fe57e"

/// A throwaway Cursor configuration directory plus a copy of the shipped agent
/// package, so the installer runs against the real resource layout.
private struct CursorPackageFixture {
    let root: URL
    let configurationDirectory: URL
    let packageRoot: URL

    static func make(file: String = #filePath) throws -> Self {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "agentstudio-cursor-package-\(UUID().uuidString)")
        let configurationDirectory = root.appending(path: "config")
        let packageRoot = root.appending(path: "AgentPackage")
        try FileManager.default.createDirectory(at: configurationDirectory, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: shippedPackageRoot(file: file), to: packageRoot)
        return Self(root: root, configurationDirectory: configurationDirectory, packageRoot: packageRoot)
    }

    /// `Tests/AgentStudioIPCClientTests` -> repository root -> shipped resources.
    static func shippedPackageRoot(file: String) -> URL {
        URL(fileURLWithPath: file)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "Sources/AgentStudio/Resources/AgentPackage")
    }

    var hooksURL: URL { configurationDirectory.appending(path: "hooks.json") }

    var installation: CursorPackageInstallation {
        CursorPackageInstallation(
            configurationDirectory: configurationDirectory,
            packageRoot: packageRoot,
            providerVersion: cursorFixtureVersion
        )
    }

    func writeHooks(_ value: JSONValue) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(value).write(to: hooksURL)
    }

    func readHooks() throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: try Data(contentsOf: hooksURL))
    }

    func hooksFields() throws -> [String: JSONValue] {
        guard case .object(let fields) = try readHooks() else { return [:] }
        return fields
    }

    func entries(for event: String) throws -> [JSONValue] {
        guard case .object(let hooks)? = try hooksFields()["hooks"],
            case .array(let entries)? = hooks[event]
        else { return [] }
        return entries
    }

    func tearDown() {
        try? FileManager.default.removeItem(at: root)
    }
}

@Suite("Cursor package installer")
struct CursorPackageInstallerTests {
    private func ownedCommands(_ entries: [JSONValue]) -> [String] {
        entries.compactMap { entry in
            guard case .object(let fields) = entry,
                case .string(let command)? = fields["command"],
                command.contains(CursorPackageInstallation.ownershipMarker)
            else { return nil }
            return command
        }
    }

    @Test("A fresh install writes one owned entry per projected hook event")
    func freshInstallWritesEveryEvent() throws {
        // Arrange
        let fixture = try CursorPackageFixture.make()
        defer { fixture.tearDown() }
        var notices: [String] = []

        // Act
        try fixture.installation.install(notice: { notices.append($0) })

        // Assert
        #expect(notices.isEmpty)
        for event in CursorHookEvent.allCases {
            let commands = ownedCommands(try fixture.entries(for: event.rawValue))
            #expect(commands.count == 1)
            #expect(commands.first?.hasSuffix(" \(event.rawValue) \(cursorFixtureVersion)") == true)
        }
        // Cursor refuses a hooks document without its schema version.
        #expect(try fixture.hooksFields()["version"] == .number(1))
        let skill = fixture.configurationDirectory.appending(path: "skills/agentstudio/SKILL.md")
        let marker = fixture.configurationDirectory.appending(path: "skills/agentstudio/.agentstudio-package")
        #expect(FileManager.default.isReadableFile(atPath: skill.path))
        #expect(FileManager.default.isReadableFile(atPath: marker.path))
    }

    @Test("No permission-gating event is installed, so no hook can answer for the user")
    func noPermissionGatingEventIsInstalled() throws {
        // Arrange
        let fixture = try CursorPackageFixture.make()
        defer { fixture.tearDown() }
        let gating = ["beforeShellExecution", "beforeMCPExecution", "beforeReadFile", "beforeTabFileRead"]

        // Act
        try fixture.installation.install(notice: { _ in })

        // Assert
        for event in gating {
            #expect(try fixture.entries(for: event).isEmpty)
        }
    }

    @Test("Unrelated settings and unrelated hooks survive install and uninstall")
    func unrelatedSettingsSurvive() throws {
        // Arrange
        let fixture = try CursorPackageFixture.make()
        defer { fixture.tearDown() }
        let userHook = JSONValue.object([
            "type": .string("command"),
            "command": .string("/usr/local/bin/my-audit.sh"),
            "timeout": .number(30),
        ])
        let original = JSONValue.object([
            "version": .number(1),
            "hooks": .object(["preToolUse": .array([userHook]), "afterFileEdit": .array([userHook])]),
        ])
        try fixture.writeHooks(original)

        // Act
        try fixture.installation.install(notice: { _ in })
        let afterInstall = try fixture.hooksFields()
        try fixture.installation.uninstall(notice: { _ in })

        // Assert
        #expect(afterInstall["version"] == .number(1))
        #expect(try fixture.entries(for: "preToolUse").contains(userHook))
        #expect(try fixture.entries(for: "afterFileEdit") == [userHook])
        #expect(try fixture.readHooks() == original)
    }

    @Test("Reinstalling the same package changes nothing and reports nothing")
    func reinstallIsIdempotent() throws {
        // Arrange
        let fixture = try CursorPackageFixture.make()
        defer { fixture.tearDown() }
        try fixture.installation.install(notice: { _ in })
        let first = try Data(contentsOf: fixture.hooksURL)
        var notices: [String] = []

        // Act
        try fixture.installation.install(notice: { notices.append($0) })

        // Assert
        #expect(try Data(contentsOf: fixture.hooksURL) == first)
        #expect(notices.isEmpty)
    }

    @Test("A modified owned entry is reported once and then restored")
    func modifiedOwnedEntryIsReported() throws {
        // Arrange
        let fixture = try CursorPackageFixture.make()
        defer { fixture.tearDown() }
        try fixture.installation.install(notice: { _ in })
        let expected = try Data(contentsOf: fixture.hooksURL)
        var fields = try fixture.hooksFields()
        guard case .object(var hooks)? = fields["hooks"],
            case .array(var entries)? = hooks["stop"],
            case .object(var entry) = entries[0]
        else {
            Issue.record("installed stop entry was not shaped as expected")
            return
        }
        entry["timeout"] = .number(999)
        entries[0] = .object(entry)
        hooks["stop"] = .array(entries)
        fields["hooks"] = .object(hooks)
        try fixture.writeHooks(.object(fields))
        var notices: [String] = []

        // Act
        try fixture.installation.install(notice: { notices.append($0) })

        // Assert
        #expect(notices == ["notice: replacing modified agentstudio entry stop"])
        #expect(try Data(contentsOf: fixture.hooksURL) == expected)
    }

    @Test("Uninstall removes exactly the package's entries and its marked skill")
    func uninstallRemovesOnlyOwnedEntries() throws {
        // Arrange
        let fixture = try CursorPackageFixture.make()
        defer { fixture.tearDown() }
        try fixture.installation.install(notice: { _ in })

        // Act
        try fixture.installation.uninstall(notice: { _ in })

        // Assert
        #expect(try fixture.hooksFields()["hooks"] == nil)
        #expect(
            !FileManager.default.fileExists(
                atPath: fixture.configurationDirectory.appending(path: "skills/agentstudio").path
            )
        )
    }

    @Test("A missing configuration directory fails without writing anything")
    func missingConfigurationDirectoryWritesNothing() throws {
        // Arrange
        let fixture = try CursorPackageFixture.make()
        defer { fixture.tearDown() }
        let absent = fixture.root.appending(path: "absent")
        let installation = CursorPackageInstallation(
            configurationDirectory: absent,
            packageRoot: fixture.packageRoot,
            providerVersion: cursorFixtureVersion
        )

        // Act / Assert
        #expect(throws: CursorPackageInstallerError.configurationDirectoryUnavailable(absent.path)) {
            try installation.install(notice: { _ in })
        }
        #expect(!FileManager.default.fileExists(atPath: absent.path))
    }

    /// Uninstall already steps around a non-object `hooks`. Install replacing it
    /// would destroy a value the package never wrote.
    @Test("A non-object hooks value aborts the install and writes nothing")
    func nonObjectHooksValueAbortsInstall() throws {
        // Arrange
        let fixture = try CursorPackageFixture.make()
        defer { fixture.tearDown() }
        try fixture.writeHooks(.object(["hooks": .string("mine"), "version": .number(1)]))
        let original = try Data(contentsOf: fixture.hooksURL)

        // Act / Assert
        #expect(throws: CursorPackageInstallerError.hooksValueNotAnObject(fixture.hooksURL.path)) {
            try fixture.installation.install(notice: { _ in })
        }
        #expect(try Data(contentsOf: fixture.hooksURL) == original)
        #expect(
            !FileManager.default.fileExists(atPath: fixture.installation.skillDirectoryURL.path))
    }

    @Test("A missing package root fails before hooks.json is touched")
    func missingPackageRootWritesNothing() throws {
        // Arrange
        let fixture = try CursorPackageFixture.make()
        defer { fixture.tearDown() }
        let installation = CursorPackageInstallation(
            configurationDirectory: fixture.configurationDirectory,
            packageRoot: fixture.root.appending(path: "absent-package"),
            providerVersion: cursorFixtureVersion
        )

        // Act / Assert
        #expect(throws: CursorPackageInstallerError.self) {
            try installation.install(notice: { _ in })
        }
        #expect(!FileManager.default.fileExists(atPath: fixture.hooksURL.path))
    }

    @Test("The shipped hook script is present and executable")
    func shippedHookScriptIsExecutable() throws {
        // Arrange
        let fixture = try CursorPackageFixture.make()
        defer { fixture.tearDown() }

        // Act
        let script = fixture.installation.hookScriptURL

        // Assert
        #expect(FileManager.default.isExecutableFile(atPath: script.path))
        #expect(script.path.hasSuffix(CursorPackageInstallation.ownershipMarker))
    }
}

@Suite("Cursor package command")
struct CursorPackageCommandTests {
    @Test("Arguments for another provider or command are not claimed")
    func unrelatedArgumentsAreNotClaimed() {
        // Arrange
        let unrelated = [["session.query"], ["package", "install", "claude"], ["package"]]

        // Act
        let outcomes = unrelated.map { arguments in
            CursorPackageCommand.handle(
                CursorPackageCommandInputs(
                    arguments: arguments,
                    environment: [:],
                    executableURL: URL(fileURLWithPath: "/tmp/agentstudio"),
                    noticeSink: { _ in },
                    errorSink: { _ in },
                    installedVersionReader: { nil }
                )
            )
        }

        // Assert
        #expect(outcomes.allSatisfy { $0 == nil })
    }

    @Test("Install and uninstall run against an explicit configuration directory")
    func installAndUninstallThroughTheCommand() throws {
        // Arrange
        let fixture = try CursorPackageFixture.make()
        defer { fixture.tearDown() }
        var notices: [String] = []
        var errors: [String] = []
        func run(_ verb: String) -> Int32? {
            CursorPackageCommand.handle(
                CursorPackageCommandInputs(
                    arguments: [
                        "package", verb, "cursor", "--config-dir", fixture.configurationDirectory.path,
                    ],
                    environment: ["AGENTSTUDIO_PACKAGE_ROOT": fixture.packageRoot.path],
                    executableURL: URL(fileURLWithPath: "/tmp/agentstudio"),
                    noticeSink: { notices.append($0) },
                    errorSink: { errors.append($0) },
                    installedVersionReader: { cursorFixtureVersion }
                )
            )
        }

        // Act
        let installExit = run("install")
        let installedEntries = try fixture.entries(for: "sessionStart")
        let uninstallExit = run("uninstall")

        // Assert
        #expect(installExit == 0)
        #expect(uninstallExit == 0)
        #expect(errors.isEmpty)
        #expect(installedEntries.count == 1)
        #expect(try fixture.hooksFields()["hooks"] == nil)
    }

    @Test("Install says plainly which CLI mode reports turn boundaries")
    func installReportsTheHeadlessTurnGap() throws {
        // Arrange
        let fixture = try CursorPackageFixture.make()
        defer { fixture.tearDown() }
        var notices: [String] = []

        // Act
        let exitCode = CursorPackageCommand.handle(
            CursorPackageCommandInputs(
                arguments: [
                    "package", "install", "cursor", "--config-dir", fixture.configurationDirectory.path,
                ],
                environment: ["AGENTSTUDIO_PACKAGE_ROOT": fixture.packageRoot.path],
                executableURL: URL(fileURLWithPath: "/tmp/agentstudio"),
                noticeSink: { notices.append($0) },
                errorSink: { _ in },
                installedVersionReader: { cursorFixtureVersion }
            )
        )

        // Assert
        #expect(exitCode == 0)
        #expect(notices.contains { $0.contains("no turn boundaries") })
    }

    @Test("An unreadable configuration directory reports one line and exits one")
    func unreadableConfigurationDirectoryExitsOne() {
        // Arrange
        var errors: [String] = []

        // Act
        let exitCode = CursorPackageCommand.handle(
            CursorPackageCommandInputs(
                arguments: ["package", "install", "cursor", "--config-dir", "/nonexistent/agentstudio"],
                environment: [:],
                executableURL: URL(fileURLWithPath: "/tmp/agentstudio"),
                noticeSink: { _ in },
                errorSink: { errors.append($0) },
                installedVersionReader: { cursorFixtureVersion }
            )
        )

        // Assert
        #expect(exitCode == 1)
        #expect(errors.count == 1)
        #expect(errors.first?.contains("configuration directory is missing or not writable") == true)
    }
}
