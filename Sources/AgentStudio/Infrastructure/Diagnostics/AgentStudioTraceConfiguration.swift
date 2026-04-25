import Foundation

struct AgentStudioTraceConfiguration: Equatable, Sendable {
    static let defaultDirectory = URL(fileURLWithPath: "/tmp", isDirectory: true)

    let enabledTags: Set<AgentStudioTraceTag>
    let traceName: String
    let directory: URL

    var isEnabled: Bool {
        !enabledTags.isEmpty
    }

    static func from(environment: [String: String]) -> Self {
        let tags = AgentStudioTraceTag.parseList(environment["AGENTSTUDIO_TRACE_TAGS"])
        let traceName = sanitizedTraceName(environment["AGENTSTUDIO_TRACE_NAME"])
        let directory = traceDirectory(environment["AGENTSTUDIO_TRACE_DIR"])
        return Self(enabledTags: tags, traceName: traceName, directory: directory)
    }

    func isEnabled(_ tag: AgentStudioTraceTag) -> Bool {
        enabledTags.contains(tag)
    }

    func outputFileURL(processIdentifier: Int32) -> URL {
        directory.appendingPathComponent("agentstudio-\(traceName)-\(processIdentifier).jsonl")
    }

    private static func sanitizedTraceName(_ rawValue: String?) -> String {
        let trimmedValue = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmedValue, !trimmedValue.isEmpty else {
            return "trace"
        }

        let allowedCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let scalars = trimmedValue.unicodeScalars.map { scalar in
            allowedCharacters.contains(scalar) ? Character(scalar) : "-"
        }
        let sanitized = String(scalars).trimmingCharacters(in: CharacterSet(charactersIn: "-_"))
        return sanitized.isEmpty ? "trace" : sanitized
    }

    private static func traceDirectory(_ rawValue: String?) -> URL {
        let trimmedValue = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmedValue, !trimmedValue.isEmpty else {
            return Self.defaultDirectory
        }
        return URL(fileURLWithPath: NSString(string: trimmedValue).expandingTildeInPath, isDirectory: true)
    }
}
