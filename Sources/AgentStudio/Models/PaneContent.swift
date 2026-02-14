import Foundation

// MARK: - Pane Content

/// Discriminated union for the content type held by a Pane or DrawerPane.
/// Each pane holds exactly one content type, fixed at creation.
enum PaneContent: Codable, Hashable {
    /// Terminal emulator content (Ghostty or tmux-backed).
    case terminal(TerminalState)
    /// Embedded web content (future: diff viewer, PR status, dev server).
    case webview(WebviewState)
    /// Source code viewer (future: file review, annotations).
    case codeViewer(CodeViewerState)
}

// MARK: - Session Provider

/// Backend provider for terminal panes.
enum SessionProvider: String, Codable, Hashable {
    /// Direct Ghostty surface, no tmux multiplexer.
    case ghostty
    /// Headless tmux backend for persistence/restore.
    case tmux
}

// MARK: - Terminal State

/// State for a terminal pane. Absorbs the former `SessionProvider` and `SessionLifetime`.
struct TerminalState: Codable, Hashable {
    /// Backend provider for this terminal.
    var provider: SessionProvider
    /// Lifecycle: persistent (tmux-backed) or temporary.
    var lifetime: SessionLifetime
}

// MARK: - Webview State (future)

/// State for a webview pane. Defined now, wired later.
struct WebviewState: Codable, Hashable {
    /// The URL to display.
    var url: URL
    /// Whether navigation controls are visible.
    var showNavigation: Bool
}

// MARK: - Code Viewer State (future)

/// State for a code viewer pane. Defined now, wired later.
struct CodeViewerState: Codable, Hashable {
    /// Path to the file being viewed.
    var filePath: URL
    /// Line to scroll to (1-based).
    var scrollToLine: Int?
}
