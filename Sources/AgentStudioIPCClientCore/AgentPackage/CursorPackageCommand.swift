import AgentStudioProgrammaticControl
import Foundation

/// Everything `agentstudio package <verb> cursor` needs from its process.
package struct CursorPackageCommandInputs {
    package let arguments: [String]
    package let environment: [String: String]
    package let executableURL: URL
    package let noticeSink: (String) -> Void
    package let errorSink: (String) -> Void
    package let installedVersionReader: () -> String?

    package init(
        arguments: [String],
        environment: [String: String],
        executableURL: URL,
        noticeSink: @escaping (String) -> Void,
        errorSink: @escaping (String) -> Void,
        installedVersionReader: @escaping () -> String? = CursorInstalledVersion.read
    ) {
        self.arguments = arguments
        self.environment = environment
        self.executableURL = executableURL
        self.noticeSink = noticeSink
        self.errorSink = errorSink
        self.installedVersionReader = installedVersionReader
    }
}

/// Parses `agentstudio package install|uninstall cursor [--config-dir <path>]`
/// and runs it against the resolved Cursor configuration directory.
package enum CursorPackageCommand {
    package static let commandPrefix = ["package"]
    package static let providerArgument = "cursor"

    /// - Returns: the process exit code when `arguments` address this command,
    ///   and `nil` when they belong to another command or another provider.
    package static func handle(_ inputs: CursorPackageCommandInputs) -> Int32? {
        guard inputs.arguments.first == commandPrefix.first,
            let verb = inputs.arguments.dropFirst().first,
            inputs.arguments.dropFirst(2).first == providerArgument
        else {
            return nil
        }
        guard verb == "install" || verb == "uninstall" else {
            inputs.errorSink("agentstudio package: expected install or uninstall, got \(verb)")
            return 1
        }
        let options = Array(inputs.arguments.dropFirst(3))
        guard let configurationDirectory = resolvedConfigurationDirectory(options: options, inputs: inputs)
        else {
            inputs.errorSink("agentstudio package: could not resolve the Cursor configuration directory")
            return 1
        }
        let installation = CursorPackageInstallation(
            configurationDirectory: configurationDirectory,
            packageRoot: resolvedPackageRoot(inputs: inputs),
            providerVersion: resolvedProviderVersion(options: options, inputs: inputs)
        )
        do {
            if verb == "install" {
                try installation.install(notice: inputs.noticeSink)
                inputs.noticeSink("installed agentstudio Cursor hooks in \(configurationDirectory.path)")
                inputs.noticeSink(
                    "notice: a Cursor `--print` run reports session and tool events but no turn boundaries;"
                        + " turn start and turn done are reported from an attended pane session only"
                )
            } else {
                try installation.uninstall(notice: inputs.noticeSink)
                inputs.noticeSink("removed agentstudio Cursor hooks from \(configurationDirectory.path)")
            }
            return 0
        } catch {
            inputs.errorSink("agentstudio package \(verb) cursor failed: \(describe(error))")
            return 1
        }
    }

    /// Cursor loads both `~/.cursor/hooks.json` and a workspace's own
    /// `.cursor/hooks.json`, and the workspace one is keyed off the *repository
    /// root* rather than the working directory. The user-level directory is the
    /// default because it is the one location that applies to every workspace;
    /// `--config-dir <repo>/.cursor` installs the project-local file instead.
    private static func resolvedConfigurationDirectory(
        options: [String],
        inputs: CursorPackageCommandInputs
    ) -> URL? {
        if let explicit = value(of: "--config-dir", in: options) {
            return URL(fileURLWithPath: explicit)
        }
        if let configured = inputs.environment["CURSOR_CONFIG_DIR"], !configured.isEmpty {
            return URL(fileURLWithPath: configured)
        }
        guard let home = inputs.environment["HOME"], !home.isEmpty else { return nil }
        return URL(fileURLWithPath: home).appending(path: ".cursor")
    }

    /// The bundled CLI lives at `<app>/Contents/Helpers/agentstudio` and its
    /// package resources at `<app>/Contents/Resources/AgentPackage`, so the root
    /// is derived from the running executable rather than a search path.
    private static func resolvedPackageRoot(inputs: CursorPackageCommandInputs) -> URL {
        if let override = inputs.environment["AGENTSTUDIO_PACKAGE_ROOT"], !override.isEmpty {
            return URL(fileURLWithPath: override)
        }
        return inputs.executableURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "Resources/AgentPackage")
    }

    /// The installed release is written into every hook command, so a Cursor
    /// upgrade reports the new version and the app refuses it as unqualified
    /// instead of admitting capabilities nobody verified.
    private static func resolvedProviderVersion(
        options: [String],
        inputs: CursorPackageCommandInputs
    ) -> String {
        if let explicit = value(of: "--provider-version", in: options), !explicit.isEmpty {
            return explicit
        }
        if let installed = inputs.installedVersionReader() { return installed }
        inputs.noticeSink(
            "notice: cursor-agent --version unavailable; recording \(CursorProviderIdentity.supportedExactVersion)"
        )
        return CursorProviderIdentity.supportedExactVersion
    }

    private static func value(of option: String, in options: [String]) -> String? {
        guard let flagIndex = options.firstIndex(of: option),
            case let valueIndex = options.index(after: flagIndex), valueIndex < options.count
        else {
            return nil
        }
        return options[valueIndex]
    }

    private static func describe(_ error: any Error) -> String {
        switch error {
        case CursorPackageInstallerError.configurationDirectoryUnavailable(let path):
            "configuration directory is missing or not writable: \(path)"
        case CursorPackageInstallerError.packageResourcesUnavailable(let path):
            "agent package resources are missing: \(path)"
        case CursorPackageInstallerError.hooksDocumentUnreadable(let path):
            "hooks.json is not readable JSON: \(path)"
        case CursorPackageInstallerError.hooksDocumentNotAnObject(let path):
            "hooks.json is not a JSON object: \(path)"
        case CursorPackageInstallerError.hooksValueNotAnObject(let path):
            "\(path) has a non-object \"hooks\" value; not modified"
        default:
            "unexpected failure"
        }
    }
}

/// Reads the release of the `cursor-agent` executable on PATH. Absence is an
/// ordinary outcome: the user may install the hooks before Cursor.
package enum CursorInstalledVersion {
    package static func read() -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["cursor-agent", "--version"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return nil
        }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0,
            let text = String(data: data, encoding: .utf8)
        else {
            return nil
        }
        return parsedVersion(text)
    }

    /// `cursor-agent --version` prints a bare calendar build such as
    /// `2026.09.15-d2fe57e`, so the release carries hex as well as digits.
    package static func parsedVersion(_ text: String) -> String? {
        let candidate = text.split(separator: " ").first.map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let candidate, !candidate.isEmpty,
            candidate.allSatisfy({ $0.isHexDigit || $0 == "." || $0 == "-" })
        else {
            return nil
        }
        return candidate
    }
}
