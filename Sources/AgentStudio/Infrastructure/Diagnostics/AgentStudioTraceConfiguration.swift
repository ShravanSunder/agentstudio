import Foundation

enum AgentStudioTraceFlushMode: String, Equatable, Sendable {
    case buffered
    case immediate

    static func parse(_ rawValue: String?) -> Self {
        guard
            let rawValue = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
            rawValue == Self.immediate.rawValue
        else { return .buffered }
        return .immediate
    }
}

enum AgentStudioTraceBackend: Equatable, Sendable {
    case jsonl

    static func parse(_ rawValue: String?) -> (backend: Self, unsupportedSelector: String?) {
        guard let rawValue = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
            !rawValue.isEmpty
        else { return (.jsonl, nil) }

        guard rawValue == "jsonl" else {
            return (.jsonl, rawValue)
        }
        return (.jsonl, nil)
    }
}

struct AgentStudioTraceConfiguration: Equatable, Sendable {
    static let defaultDirectory = URL(fileURLWithPath: "/tmp", isDirectory: true)

    let enabledTags: Set<AgentStudioTraceTag>
    let traceName: String
    let directory: URL
    let flushMode: AgentStudioTraceFlushMode
    let backend: AgentStudioTraceBackend
    let unknownTagSelectors: [String]
    let unsupportedBackendSelector: String?

    var isEnabled: Bool {
        !enabledTags.isEmpty
    }

    static func from(environment: [String: String]) -> Self {
        let selection = AgentStudioTraceTag.parseSelection(environment["AGENTSTUDIO_TRACE_TAGS"])
        let traceName = sanitizedTraceName(environment["AGENTSTUDIO_TRACE_NAME"])
        let directory = traceDirectory(environment["AGENTSTUDIO_TRACE_DIR"])
        let flushMode = AgentStudioTraceFlushMode.parse(environment["AGENTSTUDIO_TRACE_FLUSH"])
        let backendSelection = AgentStudioTraceBackend.parse(environment["AGENTSTUDIO_TRACE_BACKEND"])
        return Self(
            enabledTags: selection.tags,
            traceName: traceName,
            directory: directory,
            flushMode: flushMode,
            backend: backendSelection.backend,
            unknownTagSelectors: selection.unknownSelectors,
            unsupportedBackendSelector: backendSelection.unsupportedSelector
        )
    }

    func isEnabled(_ tag: AgentStudioTraceTag) -> Bool {
        enabledTags.contains(tag)
    }

    func outputFileURL(processIdentifier: Int32) -> URL {
        directory.appendingPathComponent("agentstudio-\(traceName)-\(processIdentifier).jsonl")
    }

    private init(
        enabledTags: Set<AgentStudioTraceTag>,
        traceName: String,
        directory: URL,
        flushMode: AgentStudioTraceFlushMode,
        backend: AgentStudioTraceBackend,
        unknownTagSelectors: [String],
        unsupportedBackendSelector: String?
    ) {
        self.enabledTags = enabledTags
        self.traceName = traceName
        self.directory = directory
        self.flushMode = flushMode
        self.backend = backend
        self.unknownTagSelectors = unknownTagSelectors
        self.unsupportedBackendSelector = unsupportedBackendSelector
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
