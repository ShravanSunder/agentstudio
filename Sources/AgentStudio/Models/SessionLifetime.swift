import Foundation

/// Controls whether a terminal session uses a tmux backend for persistence.
enum SessionLifetime: String, Codable, Hashable {
    /// tmux backend, survives app restart. Session is persisted and restored on startup.
    case persistent
    /// No tmux, no restore. Session is ephemeral and not saved to disk.
    case temporary
}
