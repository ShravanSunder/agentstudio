import Foundation

/// The primary entity for a terminal. Stable identity independent of layout, view, or surface.
/// `id` (sessionId) is the single identity used across all layers: WorkspaceStore, Layout,
/// ViewRegistry, SurfaceManager, SessionRuntime, and zmx.
struct TerminalSession: Codable, Identifiable, Hashable {
    let id: UUID
    var source: TerminalSource
    var title: String
    var agent: AgentType?
    var provider: SessionProvider
    var lifetime: SessionLifetime
    var residency: SessionResidency

    /// Last working directory reported by the shell via OSC 7.
    /// Persisted for display on restore before the shell re-reports.
    var lastKnownCWD: URL?

    init(
        id: UUID = UUID(),
        source: TerminalSource,
        title: String = "Terminal",
        agent: AgentType? = nil,
        provider: SessionProvider = .ghostty,
        lifetime: SessionLifetime = .persistent,
        residency: SessionResidency = .active,
        lastKnownCWD: URL? = nil
    ) {
        self.id = id
        self.source = source
        self.title = title
        self.agent = agent
        self.provider = provider
        self.lifetime = lifetime
        self.residency = residency
        self.lastKnownCWD = lastKnownCWD
    }

    // MARK: - Convenience Accessors

    var worktreeId: UUID? {
        if case .worktree(let id, _) = source { return id }
        return nil
    }

    var repoId: UUID? {
        if case .worktree(_, let id) = source { return id }
        return nil
    }

}

// MARK: - Session Provider

/// Backend provider for terminal sessions.
enum SessionProvider: String, Codable, Hashable {
    /// Direct Ghostty surface, no session multiplexer.
    case ghostty
    /// Headless zmx backend for persistence/restore.
    case zmx

    // MARK: - Codable Migration

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        switch raw {
        case "tmux":
            // Legacy: persisted "tmux" → migrate to .zmx
            self = .zmx
        default:
            guard let value = SessionProvider(rawValue: raw) else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Unknown SessionProvider value: \(raw)"
                )
            }
            self = value
        }
    }
}
