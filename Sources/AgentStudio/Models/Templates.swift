import Foundation

// MARK: - Create Policy

/// When sessions should be auto-created from templates.
enum CreatePolicy: String, Codable, Hashable {
    /// Create sessions when the worktree is first opened.
    case onCreate
    /// Create sessions when the worktree view is activated.
    case onActivate
    /// Only create sessions manually.
    case manual
}

// MARK: - Terminal Template

/// Template for a single terminal session to be created.
struct TerminalTemplate: Codable, Identifiable, Hashable {
    let id: UUID
    var title: String
    var agent: AgentType?
    var provider: SessionProvider
    /// Working directory relative to the worktree root.
    var relativeWorkingDir: String?

    init(
        id: UUID = UUID(),
        title: String = "Terminal",
        agent: AgentType? = nil,
        provider: SessionProvider = .ghostty,
        relativeWorkingDir: String? = nil
    ) {
        self.id = id
        self.title = title
        self.agent = agent
        self.provider = provider
        self.relativeWorkingDir = relativeWorkingDir
    }

    /// Create a TerminalSession from this template for a given worktree/repo.
    func instantiate(worktreeId: UUID, repoId: UUID) -> TerminalSession {
        TerminalSession(
            source: .worktree(worktreeId: worktreeId, repoId: repoId),
            title: title,
            agent: agent,
            provider: provider
        )
    }
}

// MARK: - Worktree Template

/// Template for the initial session layout when opening a worktree.
/// Defines what terminals to create and how to arrange them.
struct WorktreeTemplate: Codable, Identifiable, Hashable {
    let id: UUID
    var name: String
    var terminals: [TerminalTemplate]
    var createPolicy: CreatePolicy
    /// Layout direction for multi-terminal templates.
    var splitDirection: Layout.SplitDirection

    init(
        id: UUID = UUID(),
        name: String = "Default",
        terminals: [TerminalTemplate] = [TerminalTemplate()],
        createPolicy: CreatePolicy = .manual,
        splitDirection: Layout.SplitDirection = .horizontal
    ) {
        self.id = id
        self.name = name
        self.terminals = terminals
        self.createPolicy = createPolicy
        self.splitDirection = splitDirection
    }

    /// Create sessions and a tab from this template for a given worktree/repo.
    func instantiate(worktreeId: UUID, repoId: UUID) -> (sessions: [TerminalSession], tab: Tab) {
        let sessions = terminals.map { $0.instantiate(worktreeId: worktreeId, repoId: repoId) }

        guard let first = sessions.first else {
            return (sessions: [], tab: Tab(layout: Layout(), activeSessionId: nil))
        }

        // Build layout: start with first session, insert each subsequent one
        var layout = Layout(sessionId: first.id)
        for session in sessions.dropFirst() {
            let lastId = layout.sessionIds.last ?? first.id
            layout = layout.inserting(
                sessionId: session.id,
                at: lastId,
                direction: splitDirection,
                position: .after
            )
        }

        let tab = Tab(layout: layout, activeSessionId: first.id)
        return (sessions: sessions, tab: tab)
    }
}
