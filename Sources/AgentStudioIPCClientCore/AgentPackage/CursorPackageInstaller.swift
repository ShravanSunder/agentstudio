import AgentStudioIPCTransport
import AgentStudioProgrammaticControl
import Foundation

package enum CursorPackageInstallerError: Error, Equatable, Sendable {
    case configurationDirectoryUnavailable(String)
    case packageResourcesUnavailable(String)
    case hooksDocumentUnreadable(String)
    case hooksDocumentNotAnObject(String)
    case hooksValueNotAnObject(String)
}

/// Installs and removes Agent Studio's Cursor integration inside one Cursor
/// configuration directory — either `~/.cursor` or a workspace's `.cursor`.
///
/// Ownership is carried by the hook command itself: an entry is ours exactly
/// when its command names this package's hook script. Nothing else in
/// `hooks.json` is read as ownership, so a user's own hooks — even on the same
/// events — survive install, reinstall and uninstall untouched.
package struct CursorPackageInstallation: Sendable {
    /// Any hook command containing this path fragment belongs to this package.
    package static let ownershipMarker = "/AgentPackage/providers/cursor/hooks/agentstudio-cursor-hook.sh"

    /// The hook returns as soon as the pane's socket answers, so a long ceiling
    /// would only delay a wedged turn.
    package static let hookTimeoutSeconds = 10.0

    /// Cursor's `hooks.json` carries its own schema version. Writing the
    /// version Cursor documents keeps a file this package creates from scratch
    /// loadable; an existing file's version is never rewritten.
    package static let hooksDocumentVersion = 1.0

    package let configurationDirectory: URL
    package let packageRoot: URL
    package let providerVersion: String

    package init(configurationDirectory: URL, packageRoot: URL, providerVersion: String) {
        self.configurationDirectory = configurationDirectory
        self.packageRoot = packageRoot
        self.providerVersion = providerVersion
    }

    package var hookScriptURL: URL {
        packageRoot.appending(path: "providers/cursor/hooks/agentstudio-cursor-hook.sh")
    }

    package var skillDirectoryURL: URL {
        configurationDirectory.appending(path: "skills/agentstudio")
    }

    private var hooksURL: URL { configurationDirectory.appending(path: "hooks.json") }
    private var skillMarkerURL: URL { skillDirectoryURL.appending(path: ".agentstudio-package") }
    private var sourceSkillURL: URL { packageRoot.appending(path: "skills/agentstudio/SKILL.md") }

    /// Merges this package's hook entries into `hooks.json` and installs the
    /// model skill. Nothing is written until every input is readable, so a
    /// rejected install leaves the directory exactly as it was.
    package func install(notice: (String) -> Void) throws {
        try requireWritableConfigurationDirectory()
        guard FileManager.default.isReadableFile(atPath: hookScriptURL.path),
            FileManager.default.isReadableFile(atPath: sourceSkillURL.path)
        else {
            throw CursorPackageInstallerError.packageResourcesUnavailable(packageRoot.path)
        }
        let skillContents = try Data(contentsOf: sourceSkillURL)
        var document = try readHooksObject()
        // Uninstall already leaves a non-object `hooks` alone. Install must
        // refuse it for the same reason: replacing it would throw away a value
        // this package never wrote and cannot read.
        if let present = document["hooks"], objectValue(present) == nil {
            throw CursorPackageInstallerError.hooksValueNotAnObject(hooksURL.path)
        }
        if document["version"] == nil { document["version"] = .number(Self.hooksDocumentVersion) }
        var hooksByEvent = objectValue(document["hooks"]) ?? [:]
        for event in CursorHookEvent.allCases {
            let desired = ownedEntry(for: event)
            var entries = arrayValue(hooksByEvent[event.rawValue]) ?? []
            let ownedIndexes = entries.indices.filter { isOwned(entries[$0]) }
            if ownedIndexes.isEmpty {
                entries.append(desired)
            } else {
                for index in ownedIndexes where entries[index] != desired {
                    notice("notice: replacing modified agentstudio entry \(event.rawValue)")
                }
                for index in ownedIndexes.dropFirst().reversed() { entries.remove(at: index) }
                entries[ownedIndexes[0]] = desired
            }
            hooksByEvent[event.rawValue] = .array(entries)
        }
        document["hooks"] = .object(hooksByEvent)
        try writeAtomically(.object(document), to: hooksURL)
        try FileManager.default.createDirectory(
            at: skillDirectoryURL, withIntermediateDirectories: true
        )
        try skillContents.write(to: skillDirectoryURL.appending(path: "SKILL.md"), options: .atomic)
        try Data(packageMarkerContents.utf8).write(to: skillMarkerURL, options: .atomic)
    }

    /// Removes exactly this package's hook entries and its marked skill. Event
    /// keys and the `hooks` container are dropped when nothing else occupies
    /// them, so uninstalling a fresh install restores the original document.
    package func uninstall(notice: (String) -> Void) throws {
        try requireWritableConfigurationDirectory()
        var document = try readHooksObject()
        if var hooksByEvent = objectValue(document["hooks"]) {
            for (event, entriesValue) in hooksByEvent {
                guard let entries = arrayValue(entriesValue) else { continue }
                let retained = entries.filter { !isOwned($0) }
                guard retained.count != entries.count else { continue }
                if retained.isEmpty {
                    hooksByEvent.removeValue(forKey: event)
                } else {
                    hooksByEvent[event] = .array(retained)
                }
            }
            if hooksByEvent.isEmpty {
                document.removeValue(forKey: "hooks")
            } else {
                document["hooks"] = .object(hooksByEvent)
            }
        }
        try writeAtomically(.object(document), to: hooksURL)
        guard FileManager.default.isReadableFile(atPath: skillMarkerURL.path) else {
            notice("notice: no agentstudio skill installed at \(skillDirectoryURL.path)")
            return
        }
        try FileManager.default.removeItem(at: skillDirectoryURL)
    }
}

extension CursorPackageInstallation {
    fileprivate var packageMarkerContents: String {
        "\(CursorProviderIdentity.identifier) \(providerVersion)\n"
    }

    /// Cursor's entries are flat objects on the event key: there is no matcher
    /// group wrapping them the way Claude Code's `settings.json` has.
    fileprivate func ownedEntry(for event: CursorHookEvent) -> JSONValue {
        .object([
            "type": .string("command"),
            "command": .string("\(hookScriptURL.path) \(event.rawValue) \(providerVersion)"),
            "timeout": .number(Self.hookTimeoutSeconds),
        ])
    }

    fileprivate func isOwned(_ entry: JSONValue) -> Bool {
        guard case .object(let fields) = entry, case .string(let command)? = fields["command"] else {
            return false
        }
        return command.contains(Self.ownershipMarker)
    }

    fileprivate func requireWritableConfigurationDirectory() throws {
        var isDirectory: ObjCBool = false
        guard
            FileManager.default.fileExists(
                atPath: configurationDirectory.path, isDirectory: &isDirectory
            ), isDirectory.boolValue,
            FileManager.default.isWritableFile(atPath: configurationDirectory.path)
        else {
            throw CursorPackageInstallerError.configurationDirectoryUnavailable(
                configurationDirectory.path
            )
        }
    }

    fileprivate func readHooksObject() throws -> [String: JSONValue] {
        guard FileManager.default.isReadableFile(atPath: hooksURL.path) else { return [:] }
        let data: Data
        do {
            data = try Data(contentsOf: hooksURL)
        } catch {
            throw CursorPackageInstallerError.hooksDocumentUnreadable(hooksURL.path)
        }
        guard !data.isEmpty else { return [:] }
        guard let decoded = try? JSONDecoder().decode(JSONValue.self, from: data) else {
            throw CursorPackageInstallerError.hooksDocumentUnreadable(hooksURL.path)
        }
        guard case .object(let fields) = decoded else {
            throw CursorPackageInstallerError.hooksDocumentNotAnObject(hooksURL.path)
        }
        return fields
    }

    fileprivate func writeAtomically(_ value: JSONValue, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(value).write(to: url, options: .atomic)
    }

    fileprivate func objectValue(_ value: JSONValue?) -> [String: JSONValue]? {
        guard case .object(let fields)? = value else { return nil }
        return fields
    }

    fileprivate func arrayValue(_ value: JSONValue?) -> [JSONValue]? {
        guard case .array(let elements)? = value else { return nil }
        return elements
    }
}
