import Foundation

/// The primary entity for a terminal. Stable identity independent of layout, view, or surface.
struct TerminalSession: Codable, Identifiable, Hashable {
    let id: UUID
    var source: TerminalSource
    /// Matches SurfaceContainer.containerId — stable surface join key, never changes.
    let containerId: UUID
    var title: String
    var agent: AgentType?
    var provider: SessionProvider
    /// Opaque backend ID (e.g., tmux session name). Meaning depends on `provider`.
    var providerHandle: String?

    init(
        id: UUID = UUID(),
        source: TerminalSource,
        containerId: UUID = UUID(),
        title: String = "Terminal",
        agent: AgentType? = nil,
        provider: SessionProvider = .ghostty,
        providerHandle: String? = nil
    ) {
        self.id = id
        self.source = source
        self.containerId = containerId
        self.title = title
        self.agent = agent
        self.provider = provider
        self.providerHandle = providerHandle
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
    /// Headless tmux backend for persistence/restore.
    case tmux
}
