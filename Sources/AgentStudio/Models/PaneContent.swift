import Foundation

// MARK: - Pane Content

/// Discriminated union for the content type held by a Pane or DrawerPane.
/// Each pane holds exactly one content type, fixed at creation.
///
/// Uses custom Codable with a `type` discriminator and `version` field for
/// forward-compatible deserialization. Unknown content types decode as
/// `.unsupported` instead of crashing, allowing older app versions to
/// load workspaces saved by newer versions.
enum PaneContent: Hashable {
    /// Terminal emulator content (Ghostty or zmx-backed).
    case terminal(TerminalState)
    /// Embedded web content (future: diff viewer, PR status, dev server).
    case webview(WebviewState)
    /// Source code viewer (future: file review, annotations).
    case codeViewer(CodeViewerState)
    /// Placeholder for content types not recognized by this app version.
    /// Preserved on round-trip to avoid data loss.
    case unsupported(UnsupportedContent)
}

// MARK: - PaneContent + Codable

extension PaneContent: Codable {
    /// Current schema version. Bump when any variant's state shape changes.
    static let currentVersion = 2

    private enum ContentType: String, Codable {
        case terminal
        case webview
        case codeViewer
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case version
        case state
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1

        // Try to decode the type discriminator; fall back to unsupported if unknown
        guard let typeString = try? container.decode(String.self, forKey: .type),
              let contentType = ContentType(rawValue: typeString) else {
            // Unknown type — preserve raw JSON for round-trip
            let rawType = (try? container.decode(String.self, forKey: .type)) ?? "unknown"
            let rawState = try container.decodeIfPresent(AnyCodableValue.self, forKey: .state)
            self = .unsupported(UnsupportedContent(type: rawType, version: version, rawState: rawState))
            return
        }

        switch contentType {
        case .terminal:
            self = .terminal(try container.decode(TerminalState.self, forKey: .state))
        case .webview:
            self = .webview(try container.decode(WebviewState.self, forKey: .state))
        case .codeViewer:
            self = .codeViewer(try container.decode(CodeViewerState.self, forKey: .state))
        }
        _ = version // reserved for future state migration
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Self.currentVersion, forKey: .version)

        switch self {
        case .terminal(let state):
            try container.encode(ContentType.terminal.rawValue, forKey: .type)
            try container.encode(state, forKey: .state)
        case .webview(let state):
            try container.encode(ContentType.webview.rawValue, forKey: .type)
            try container.encode(state, forKey: .state)
        case .codeViewer(let state):
            try container.encode(ContentType.codeViewer.rawValue, forKey: .type)
            try container.encode(state, forKey: .state)
        case .unsupported(let content):
            try container.encode(content.type, forKey: .type)
            try container.encode(content.version, forKey: .version)
            try container.encodeIfPresent(content.rawState, forKey: .state)
        }
    }
}

// MARK: - Unsupported Content

/// Preserves unrecognized pane content for round-trip persistence.
struct UnsupportedContent: Codable, Hashable {
    let type: String
    let version: Int
    let rawState: AnyCodableValue?
}

// MARK: - AnyCodableValue

/// Type-erased Codable value for preserving unknown JSON structures.
enum AnyCodableValue: Codable, Hashable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case array([AnyCodableValue])
    case object([String: AnyCodableValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let b = try? container.decode(Bool.self) {
            self = .bool(b)
        } else if let i = try? container.decode(Int.self) {
            self = .int(i)
        } else if let d = try? container.decode(Double.self) {
            self = .double(d)
        } else if let s = try? container.decode(String.self) {
            self = .string(s)
        } else if let a = try? container.decode([AnyCodableValue].self) {
            self = .array(a)
        } else if let o = try? container.decode([String: AnyCodableValue].self) {
            self = .object(o)
        } else {
            self = .null
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let v): try container.encode(v)
        case .int(let v): try container.encode(v)
        case .double(let v): try container.encode(v)
        case .bool(let v): try container.encode(v)
        case .array(let v): try container.encode(v)
        case .object(let v): try container.encode(v)
        case .null: try container.encodeNil()
        }
    }
}

// MARK: - Session Provider

/// Backend provider for terminal panes.
enum SessionProvider: String, Codable, Hashable {
    /// Direct Ghostty surface, no session multiplexer.
    case ghostty
    /// Headless zmx backend for persistence/restore.
    case zmx
}

// MARK: - Terminal State

/// State for a terminal pane. Absorbs the former `SessionProvider` and `SessionLifetime`.
struct TerminalState: Codable, Hashable {
    /// Backend provider for this terminal.
    var provider: SessionProvider
    /// Lifecycle: persistent (zmx-backed) or temporary.
    var lifetime: SessionLifetime
}

// MARK: - Webview Tab State

/// State for a single tab within a webview pane.
struct WebviewTabState: Codable, Hashable, Identifiable {
    let id: UUID
    var url: URL
    var title: String

    init(id: UUID = UUID(), url: URL, title: String = "") {
        self.id = id
        self.url = url
        self.title = title
    }
}

// MARK: - Webview State

/// State for a webview pane with multi-tab support.
struct WebviewState: Codable, Hashable {
    var tabs: [WebviewTabState]
    var activeTabIndex: Int
    var showNavigation: Bool

    /// Single-URL convenience init (preserves existing call sites).
    init(url: URL, showNavigation: Bool = true) {
        self.tabs = [WebviewTabState(url: url)]
        self.activeTabIndex = 0
        self.showNavigation = showNavigation
    }

    init(tabs: [WebviewTabState], activeTabIndex: Int = 0, showNavigation: Bool = true) {
        self.tabs = tabs
        self.activeTabIndex = activeTabIndex
        self.showNavigation = showNavigation
    }

    /// The currently active tab, if the index is valid.
    var activeTab: WebviewTabState? {
        guard activeTabIndex >= 0, activeTabIndex < tabs.count else { return nil }
        return tabs[activeTabIndex]
    }
}

// MARK: - Code Viewer State (future)

/// State for a code viewer pane. Defined now, wired later.
struct CodeViewerState: Codable, Hashable {
    /// Path to the file being viewed.
    var filePath: URL
    /// Line to scroll to (1-based).
    var scrollToLine: Int?
}
