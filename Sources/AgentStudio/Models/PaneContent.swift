import Foundation

// MARK: - Pane Content

/// Discriminated union for the content type held by a Pane.
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
    /// Bridge-backed app panel (diff viewer, code review). Design doc §15.2.
    case bridgePanel(BridgePaneState)
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
        case bridgePanel
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
            let contentType = ContentType(rawValue: typeString)
        else {
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
            do {
                self = .webview(try container.decode(WebviewState.self, forKey: .state))
            } catch {
                // Schema changed between versions — preserve raw state for round-trip
                let rawState = try? container.decodeIfPresent(AnyCodableValue.self, forKey: .state)
                self = .unsupported(UnsupportedContent(type: "webview", version: version, rawState: rawState))
            }
        case .bridgePanel:
            do {
                self = .bridgePanel(try container.decode(BridgePaneState.self, forKey: .state))
            } catch {
                let rawState = try? container.decodeIfPresent(AnyCodableValue.self, forKey: .state)
                self = .unsupported(UnsupportedContent(type: "bridgePanel", version: version, rawState: rawState))
            }
        case .codeViewer:
            do {
                self = .codeViewer(try container.decode(CodeViewerState.self, forKey: .state))
            } catch {
                let rawState = try? container.decodeIfPresent(AnyCodableValue.self, forKey: .state)
                self = .unsupported(UnsupportedContent(type: "codeViewer", version: version, rawState: rawState))
            }
        }
        _ = version  // reserved for future state migration
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
        case .bridgePanel(let state):
            try container.encode(ContentType.bridgePanel.rawValue, forKey: .type)
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
    case array([Self])
    case object([String: Self])
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
        } else if let a = try? container.decode([Self].self) {
            self = .array(a)
        } else if let o = try? container.decode([String: Self].self) {
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

// MARK: - Webview State

/// State for a webview pane — one URL per pane.
struct WebviewState: Codable, Hashable {
    var url: URL
    var title: String
    var showNavigation: Bool

    init(url: URL, title: String = "", showNavigation: Bool = true) {
        self.url = url
        self.title = title
        self.showNavigation = showNavigation
    }

    // MARK: - Backward-Compatible Decoding

    /// Decodes three shapes:
    /// 1. Current: `{url, title, showNavigation}`
    /// 2. Multi-tab (v2 legacy): `{tabs: [{url, title}], activeTabIndex, showNavigation}` — extracts first tab
    /// 3. v1 legacy: `{url, showNavigation}` (no title)
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        if let url = try? container.decode(URL.self, forKey: .url) {
            // Current shape or v1 legacy
            self.url = url
            self.title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        } else if let tabs = try? container.decode([LegacyTabState].self, forKey: .tabs),
            let firstTab = tabs.first
        {
            // Multi-tab legacy shape — extract first tab's URL
            let activeIndex = (try? container.decode(Int.self, forKey: .activeTabIndex)) ?? 0
            let tab = (activeIndex >= 0 && activeIndex < tabs.count) ? tabs[activeIndex] : firstTab
            self.url = tab.url
            self.title = tab.title
        } else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "WebviewState: missing both 'url' and 'tabs'")
            )
        }
        self.showNavigation = try container.decodeIfPresent(Bool.self, forKey: .showNavigation) ?? true
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(url, forKey: .url)
        try container.encode(title, forKey: .title)
        try container.encode(showNavigation, forKey: .showNavigation)
    }

    private enum CodingKeys: String, CodingKey {
        case url, title, showNavigation
        // Legacy keys for backward-compatible decoding
        case tabs, activeTabIndex
    }

    /// Used only for decoding the legacy multi-tab shape.
    private struct LegacyTabState: Codable {
        let url: URL
        var title: String = ""
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
