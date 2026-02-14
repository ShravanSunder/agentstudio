import Foundation

/// Controls whether a terminal session uses a zmx backend for persistence.
enum SessionLifetime: String, Codable, Hashable {
    /// zmx backend, survives app restart. Session is persisted and restored on startup.
    case persistent
    /// No zmx, no restore. Session is ephemeral and not saved to disk.
    case temporary
}
