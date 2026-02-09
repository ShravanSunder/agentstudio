import Foundation

/// The primary entity for a terminal. Stable identity independent of layout, view, or surface.
/// `id` (sessionId) is the single identity used across all layers: WorkspaceStore, Layout,
/// ViewRegistry, SurfaceManager, SessionRuntime, and tmux.
struct TerminalSession: Codable, Identifiable, Hashable {
    let id: UUID
    var source: TerminalSource
    var title: String
    var agent: AgentType?
    var provider: SessionProvider
    var lifetime: SessionLifetime
    var residency: SessionResidency

    init(
        id: UUID = UUID(),
        source: TerminalSource,
        title: String = "Terminal",
        agent: AgentType? = nil,
        provider: SessionProvider = .ghostty,
        lifetime: SessionLifetime = .persistent,
        residency: SessionResidency = .active
    ) {
        self.id = id
        self.source = source
        self.title = title
        self.agent = agent
        self.provider = provider
        self.lifetime = lifetime
        self.residency = residency
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

    // MARK: - Backward-Compatible Codable

    private enum CodingKeys: String, CodingKey {
        case id, source, title, agent, provider, lifetime, residency
        // Legacy keys — decoded and discarded for backward compatibility
        case containerId, providerHandle
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        source = try container.decode(TerminalSource.self, forKey: .source)
        title = try container.decode(String.self, forKey: .title)
        agent = try container.decodeIfPresent(AgentType.self, forKey: .agent)
        provider = try container.decodeIfPresent(SessionProvider.self, forKey: .provider) ?? .ghostty
        lifetime = try container.decodeIfPresent(SessionLifetime.self, forKey: .lifetime) ?? .persistent
        residency = try container.decodeIfPresent(SessionResidency.self, forKey: .residency) ?? .active
        // Legacy fields decoded and discarded
        _ = try container.decodeIfPresent(UUID.self, forKey: .containerId)
        _ = try container.decodeIfPresent(String.self, forKey: .providerHandle)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(source, forKey: .source)
        try container.encode(title, forKey: .title)
        try container.encodeIfPresent(agent, forKey: .agent)
        try container.encode(provider, forKey: .provider)
        try container.encode(lifetime, forKey: .lifetime)
        try container.encode(residency, forKey: .residency)
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
